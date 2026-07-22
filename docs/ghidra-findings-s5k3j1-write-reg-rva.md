# Ghidra findings: S5K3J1 Windows driver write-register RVA

Answers `RE-TARGET-s5k3j1-write-reg-for-pll-capture.md`. Analyzed
`s5k3j1sx04.sys`, SHA256 `5bf53228c5b2067d50aaee87b4f3eb9565e5b86ea754f2e280a19259478c519a`
(confirmed matches the file named in the RE-TARGET doc byte-for-byte). Used Ghidra 12.1.2
headless (`pyghidra`) for full auto-analysis + decompilation.

## Sanity check: landmark RVAs confirmed

All four RVAs from the RE-TARGET doc landed exactly where expected in this binary, so the
rebasing/offset assumptions hold and everything below is directly comparable:

| Landmark | RVA | Confirmed |
|---|---|---|
| `DispatchDeviceControl` | `0x180B0` | Yes — `FUN_140017ef0`, a device-control IOCTL dispatcher |
| `FxObject` vtable | `0xB3828` | present (no named function there, as expected — it's data) |
| `IRP_MJ_*` byte-index table | `0xBAAD4` | present (data) |
| `IRP_MJ_*` dword rel-offset table | `0xBAAC0` | present (data) |

## The answer: one RVA, Option B (buffer-assembly point), via Option A's cleanliness

**RVA `0xD1C8`** (`FUN_14000d1c8`) is the function to break on. It turns out to satisfy both
options at once: by function *entry*, the full I2C write buffer is already assembled by its
caller and handed in as a plain pointer+length — so a plain function-entry breakpoint gets
you the buffer-assembly-point robustness (works uniformly for 16-bit, 8-bit, *and* burst
writes) without needing a mid-function instruction address.

**Signature** (x64 MS ABI — 1st–4th int/pointer args = `rcx, rdx, r8, r9`):

```
FUN_14000d1c8(void *ctx /*rcx*/, uint8_t *buf /*rdx*/, uint32_t len /*r8d*/, uint32_t channel /*r9d*/)
```

- `rdx` = pointer to the **fully-assembled wire buffer**: register address (MSB-first,
  1 or 2 bytes depending on a global address-width setting — 2 bytes for this sensor, per
  the PLL registers all being in the `0x0300`+ range) immediately followed by the value
  bytes (also MSB-first). This is exactly Linux's on-wire format for `s5k3j1_write_reg()`.
- `r8d` = total buffer length in bytes (2–34 observed; 34 = `0x22`, which is this function's
  hard cap on merged-burst size — matches the ETW capture's max 34-byte burst exactly, a
  good cross-check that this is the right function).
- `r9d` = I2C channel index, always `0` on the path that reaches this function from the
  sensor mode-config table player (a separate VCM write path uses a different low-level
  function, `FUN_14000cf48`/`FUN_14000cb0c`, not this one — don't confuse the two if you see
  writes to channel != 0).
- Null-checks on `rdx` (not `rdx==some magic reg value`) confirm it's a pointer, not a
  register value directly — this was cross-checked against the caller
  (`FUN_140005028`, the mode-config table player) which passes `&local_stack_buffer` and an
  `int` length at this exact call site.

**Breakpoint command** (auto-continuing, matches the RE-TARGET doc's safety note about the
flaky USB boot disk — each hit halts only microseconds):

```
bp <base>+0xD1C8 "db @rdx L@r8d; g"
```

## Call chain (for context / verification)

```
FUN_140005028  (mode-config table player: walks entries until 0xffff sentinel,
                merges consecutive same-stride registers into bursts up to 34 bytes,
                assembles [addr bytes][value bytes] into a stack buffer)
  -> FUN_14000c604  (thin wrapper, channel hardcoded to 0)
       -> FUN_14000d1c8  ***BREAK HERE*** (RVA 0xD1C8)
            -> connects/verifies I2C channel via FUN_14000c628
            -> submits the buffer via a CFG-indirected call
               (IOCTL-shaped constant 0x41808 — SPB sequence submit, not decoded
               further, not needed for this task)
```

(Separately confirmed `FUN_14000cf48`/`FUN_14000cb0c` are the **VCM** register
read/write primitives — their callers all cluster with the `'%s %s Failed to write vcm
reg'`-family strings, not the sensor mode-config path. Don't target those for this task.)

## How this maps back to the PLL question

Once the breakpoint is live and a rear-camera stream starts, every sensor register write —
including the `0x0136` EXTCLK register and the `0x0300`–`0x0312` PLL block — will hit this
one breakpoint, each time dumping `[addr_hi, addr_lo, ...value_bytes]` directly. Since the
address is always the first 1–2 bytes of the dumped buffer, filtering the capture for
buffers starting with `03 00`, `03 04`, `03 06`, `03 0C`, `03 0E`, `03 10`, `03 12`, or
`01 36` (big-endian) picks out exactly the registers `WINDOWS-AGENT-BRIEF-5` asked about —
whether they arrive as individual 4-byte writes or merged into a larger burst (e.g. if
`0x030c`–`0x0312` land within one 34-byte-max merge run, they'll show up concatenated in a
single hit; the address prefix still identifies where each field starts based on the known
per-register width Linux uses for the same registers).
