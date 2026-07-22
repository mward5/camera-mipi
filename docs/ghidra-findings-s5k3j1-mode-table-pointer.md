**CORRECTION (same day, later pass) — the address field byte order below is wrong.**
This doc says the register-address field at entry offset +4/+5 is "raw bytes, MSB-first."
That's backwards: it's a plain **little-endian** `u16` (`b[4] | (b[5]<<8)`), confirmed by
comparing decoded entries directly against Linux's own `mode_3976x2736_regs[]` (e.g. this
doc's "`0xfcfc` matches" check was a false positive — `0xfcfc` is byte-swap-symmetric, so
it couldn't have caught the error; the giveaway was entries this doc read as `0xd090`/
`0xc890`, which are exactly Linux's real `0x90d0`/`0x90c8` byte-reversed). **This error
also invalidates item 3's "PLL registers absent from the whole file" conclusion below —
they were there all along, just missed by searching for the wrong byte order.** See
`docs/ghidra-findings-s5k3j1-pll-source.md`'s end-of-document correction for the actual
values, which match Linux exactly. Section 2's field layout is otherwise correct (width
@+0, value @+8, sentinel logic, unused padding) — only the address byte order was wrong.

# Ghidra findings: S5K3J1 mode-config table pointer chain, entry layout, and PLL location

Answers `RE-TARGET-2-s5k3j1-mode-table-pointer.md`. Same binary,
`s5k3j1sx04.sys`, SHA256 `5bf53228c5b2067d50aaee87b4f3eb9565e5b86ea754f2e280a19259478c519a`.
Scripts in `/home/mward/work/ghidra/*.py`, full raw output in
`reference/windows-driver-artifacts/xps-rear-win-20260713/s5k3j1_table_trace*.log` and
`s5k3j1_mode_table_decode.log` / `s5k3j1_pll_static_scan.log`.

## Bottom line

**Items 1 and 2 are fully resolved, with the table itself already decoded and cross-checked
against known-good Linux values.** But this specific table does not contain the PLL/EXTCLK
registers you're after (item 3) — those are confirmed **absent from the static `.sys` file
entirely**, not just from this one table. So there's no RVA to hand you for them; a live
capture is still needed, but not via the original breakpoint plan. See "What this means for
next steps" below for a concrete fallback.

## 1. Table-pointer source

The chain (device-extension based, satisfies item 1(a)/(c)):

```
FUN_140005028(ctx, table_ptr)
  called from FUN_14000976c(ctx, mode_group, mode_index):
    table_ptr = *(int **)( *(long *)(ctx + 0x1f38 + mode_group*8) + mode_index*0x90 + 0x28 )
```

- `ctx + 0x1f38` is a **device-extension field**: an array of 4 pointers (8 bytes apart),
  one per "mode group." Populated once at driver init (`FUN_140009250`, called during
  `EvtDevicePrepareHardware`/D0 entry) — by the time the camera is streaming, this field
  already holds its final, resolved value, so you don't need to trace the selection logic
  below at all, just read it live.
- The value written there is chosen by another devext field, `*(int*)(ctx+0x1e9c)` (a
  small board-variant selector, 0/2/3 seen), but **all 4 slots get the same value** —
  so effectively there's just one active table root, not 4 independent ones.
- The 3 possible roots are themselves **static, image-relative pointers**, not runtime pool
  allocations — i.e. despite the device-extension indirection, the actual table is baked
  into the `.sys` file:

  | Variant selector | Root global | Points to (mode-descriptor array, 0x90 bytes/entry) |
  |---|---|---|
  | 0 / default | `DAT_14002b7d0` (RVA `0x2b7d0`) | table RVA `0x25410` |
  | 2 | `DAT_14002ae80` (RVA `0x2ae80`) | table RVA `0x21630` |
  | 3 | `DAT_14002b350` (RVA `0x2b350`) | table RVA `0x23260` |

  `mode_index` selects a 0x90-byte record within whichever of these arrays is active;
  offset `+0x28` within that record is the pointer (also image-relative/static) to the
  actual register table `FUN_140005028` plays.

- **Which variant is this hardware?** Decoded the first mode-descriptor record for all
  three (bytes: width u32, height u32, fps u32, ..., VTS u32 at offset 0x30): variant 0
  gives width=**3976**, height=**2736**, fps=**30**, VTS=**2856** — an **exact match** to
  Linux's `S5K3J1_PPL_512MHZ`/`S5K3J1_VTS_30FPS` constants (`2856`). Variants 2 and 3 have
  different VTS (2846, 3198) — different board tunings, not this one. **This confirms
  variant 0 / table RVA `0x25410` is the one actually in use on this Dell XPS.** If you
  want to confirm live rather than trust this inference, read `ctx+0x1e9c` — it should
  read `0`.

## 2. In-memory entry layout

Confirmed by decoding table RVA `0x25410` directly (no live system needed — it's static)
and cross-checking against registers already known from Linux's `s5k3j1.c`: entry
`{width=2, addr=0xfcfc, value=0x4000}` appears at index 4 (and again at 8, 12) in the
decoded table, an **exact match** to Linux's own `{0xfcfc, 0x4000}` write — strong
confirmation the layout below is right, not a guess:

**Fixed-size 16-byte records**, no variable-length entries:

| Byte offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | value width, native LE `int32` | 1–4 (bytes); special value `32` seen once near the start of the table (entry with `addr=0x0000`) — likely a non-register "delay"/control pseudo-entry, matching the driver's own `if (param_4 == 0x20) FUN_14000dc50(...)` special-case in the caller wrapper (`0x20`=32 decimal) |
| 4 | 2 | register address, **raw bytes, MSB-first** (i.e. already wire-ready big-endian) | read this as two literal bytes, not a native ushort |
| 6 | 2 | unused/zero | always `00 00` in every entry seen |
| 8 | 4 | value, native LE `int32` | only the low N bytes (per the width field) are meaningful; serialized MSB-first onto the wire at write time by `FUN_14000843c` |
| 12 | 4 | unused/zero | always `00 00 00 00` in every entry seen |

**Sentinel**: just the width field (byte offset 0) reading `0xffff` — not a whole
terminator record. Confirmed: table RVA `0x25410` has exactly 586 real entries before
hitting this sentinel.

**Width/stride merge encoding**: no separate stride field — the player peeks the *next*
entry's address field and merges only if `next_addr == this_addr + this_width` (and total
merged length stays ≤ `0x22`=34 bytes, matching the ETW capture's observed max burst size
exactly).

## 3. Do the PLL regs live in this table? No — confirmed absent from the whole file

Decoded all ~586/451/539 entries in all three variant tables and searched for
`0x0136`/`0x0300`/`0x0304`/`0x0306`/`0x030c`/`0x030e`/`0x0310`/`0x0312` as address fields:
**zero matches in any of the three tables.** To rule out them living in some other static
table entirely, did a full-binary byte-pattern scan (all loaded sections: `.text`,
`.rdata`, `.data`, etc.) for the same 16-byte entry shape with these specific addresses:
**zero matches anywhere in the file.**

This means brief 4/5's original hypothesis — that mode-config data is sourced from a
runtime `.aiqb`/`.cpf` tuning blob rather than being static in the `.sys` — is **correct
for this specific register range**, even though it turned out to be **wrong** for the
general per-resolution table (which is fully static, as shown above). PLL/EXTCLK values
are exactly the kind of per-physical-unit calibration data that would plausibly live in a
tuning blob rather than fixed code, unlike windowing/resolution config which is fixed by
the sensor's pixel array regardless of which physical unit you have.

## What this means for next steps

The original breakpoint plan (`FUN_14000d1c8` @ RVA `0xD1C8`) is off the table given local
KD's read-only constraint. The static-table read (this note) doesn't reach the PLL
registers either, since they're genuinely not static. That leaves the **optional fallback
from RE-TARGET-2 itself — a live memory search — as the most promising remaining path**,
now with a much more precise pattern to search for, since the entry format is confirmed
exactly:

```
s -d <pool/heap range> 01 36 00 00      ; then check what's 4 bytes before each hit
```

More precisely: search live memory for the 6-byte sequence `01 36 00 00` at byte offset+4
of a 16-byte-aligned candidate (i.e. search for `?? 00 00 00 01 36 00 00` where the first
byte is 1–4), which is the same entry shape confirmed above. If the runtime-parsed
`.aiqb`-derived table uses this same generic entry format (plausible — `FUN_140005028` is
a generic "config script" interpreter that may well play both static and blob-derived
tables through the identical shape), this should locate it directly in the driver's pool
allocations. Same pattern for `03 00`/`03 04`/`03 06`/`03 0c`/`03 0e`/`03 10`/`03 12` to
confirm/cross-check once one hit is found (they're likely contiguous in whatever table
holds them, same as they are in Linux's own table).

If that search comes up empty too, the PLL configuration may not be table-driven at all on
Windows (i.e. hardcoded `write_reg()` calls in C, with only the *value* sourced from a
parsed config struct field rather than a byte-table) — in which case the next step would
be a fresh Ghidra pass specifically for the `.aiqb` blob's parse/load function, which is a
larger, separate task not started here.
