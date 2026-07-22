# Ghidra findings: S5K3J1 PLL write site — not found, but the search was exhaustive and turned up real adjacent findings

Answers `RE-TARGET-3-s5k3j1-pll-source.md`. Same binary throughout,
`s5k3j1sx04.sys`, SHA256 `5bf53228c5b2067d50aaee87b4f3eb9565e5b86ea754f2e280a19259478c519a`.
Scripts in `/home/mward/work/ghidra/*.py`, raw output in
`reference/windows-driver-artifacts/xps-rear-win-20260713/s5k3j1_all_i2c_submits.log`,
`s5k3j1_ce00.log`, `s5k3j1_post_table_calls.log`, `s5k3j1_cde0.log`.

## Bottom line

**The write site was not found this session, despite an exhaustive search along every
angle item 1 suggested.** No static/image-relative pointer chain exists to hand you —
this isn't a "needs DEVICE_OBJECT" situation either, it's genuinely "not located yet,
and the obvious places to look have all been ruled out." Real findings below, plus one
new, much cheaper angle to try that avoids KD entirely.

## 1. No second caller of the known write primitive — ruled out systematically, not just by inspection

Rather than re-checking `FUN_14000d1c8`'s xrefs by hand again, did a full-binary
instruction scan for every call site using the exact same submission signature (a call
through the CFG dispatch stub with the IOCTL-shaped constant `0x41808`, the pattern common
to every raw-I2C-transfer function found so far). Found **25 functions** using this
pattern total. Only 5 are in the sensor/VCM range (the other 20 are the NVM/EEPROM
chip-plugin family from the earlier string scan — `Cmd_24AA16Write`, `Cmd_Cat24c16Write`,
etc. — unrelated):

| Function | Role (confirmed) |
|---|---|
| `FUN_14000c7c0` (RVA `0xC7C0`) | sensor generic **read_reg** |
| `FUN_14000cb0c` (RVA `0xCB0C`) | VCM read (burst) |
| `FUN_14000ce00` (RVA `0xCE00`) | VCM read (single, 12-bit — new this session, confirmed via its caller's `"Failed to read vcm register"` string) |
| `FUN_14000cf48` (RVA `0xCF48`) | VCM write |
| `FUN_14000d1c8` (RVA `0xD1C8`) | sensor generic **write_reg** (the one from the last pass) |

**There is no 6th/unknown low-level I2C primitive.** `FUN_14000d1c8` genuinely has exactly
one caller (`FUN_14000c604`, which itself has exactly one caller, `FUN_140005028`, the
static table player) — confirmed again via this broader scan, not just the earlier
targeted xref check. So item 1's leading hypothesis (a second, not-yet-found caller of the
same primitive) doesn't hold: **the PLL writes don't go through this primitive at all.**

## 2. New: found where the PLL registers get *read back* — confirms the register range, not the write site

Chased the two functions called immediately after the static table player in
`FUN_14000976c` (`FUN_140008828`, `FUN_140004cbc`) — both turned out to be **reads, not
writes**:

- `FUN_140004cbc(ctx, reg, &out_value, width)` → `FUN_14000cde0` → `FUN_14000c7c0` (the
  same sensor read_reg primitive above, confirmed via direct decompilation this time, not
  inference). Generic register-read wrapper with retry-on-failure logic.
- `FUN_140008828`, called unconditionally right after every mode-set, reads back **`0x0308`,
  `0x030A`, `0x030E`, `0x0310`, `0x0312`** via this wrapper and combines them into a derived
  value (`((frame_interval*2)/reg_030e) * reg_0310) / (1 << reg_0312_low_byte)`-shaped
  arithmetic — reads as a "compute actual pixel/line clock from the live PLL state"
  calculation, not a write.
- Separately, `FUN_14000976c` itself reads back `0x0340` (SMIA `frame_length_lines`/VTS)
  the same way, right after the table write that sets it — same read-back-to-verify
  pattern.

**This extends the confirmed PLL register range**: it's not just the 8 registers brief 5
asked about, but a **full contiguous block `0x0300`–`0x0312`** (adding `0x0308` and
`0x030A` to the set) — all of which the driver treats as live and meaningful, confirmed by
this read-back usage. Useful context even without the write site: if you can get a live
read of `0x0308`/`0x030A` too while you're at it, that rounds out the whole PLL config
block, not just the 6 registers originally asked about (`0x0300`–`0x0312` minus these two).

## 3. Where this leaves it

Exhausted every angle item 1 suggested:
- Static mode-config table: absent (prior pass).
- Every low-level I2C-submit call site in the whole binary: accounted for, none reaches PLL.
- The two functions called right after the table write in the mode-set sequence: both
  reads, not the write.

The write must happen somewhere not yet examined — most likely **device power-up
(`EvtDeviceD0Entry` or equivalent)**, before the mode-set sequence even runs, rather than
being part of it. That's a genuinely new area — nothing in the three passes so far has
looked at power-up specifically (all three centered on `EvtDevicePrepareHardware`,
`FUN_14002fb50` from the very first pass, and the mode-set chain). Haven't started this;
flagging it as the concrete next step rather than guessing further without instruction.

## A cheaper alternative, no KD needed at all

Given `FUN_140008828` computes a derived "actual pixel/frame clock" value from the live PLL
state on **every single mode-set**, it's worth checking whether that computed value (or the
raw `0x0340`/VTS read-back) is surfaced anywhere queryable from ordinary userspace — a
DirectShow/MediaFoundation camera property, a KS property set, or similar. If so, that
would let you cross-check the *effect* of Windows's PLL configuration (the resulting real
clock/frame rate) without any kernel debugging, register-level capture, or further Ghidra
work — a much lower-effort path to partially answering brief 5's question (confirms
whether the resulting bit rate matches Linux's 512MHz/1024Mbps assumption, even without the
literal divider register values). Not investigated this session — would need checking what
KS properties `s5k3j1sx04.sys` (or the Intel camera HAL sitting above it) actually exposes.

## CORRECTION (same day, later pass): section 3 above is wrong — found it, byte-order bug in the decoder

**The PLL registers were in the static per-mode table all along** (the one from
`ghidra-findings-s5k3j1-mode-table-pointer.md`, RVA `0x25410` for variant 0). "Absent from
the whole file" was a decoder bug, not a real result: the register-address field at entry
offset +4/+5 is a plain **little-endian** `u16`, not "raw MSB-first bytes." Caught by
comparing decoded entries directly against Linux's actual `mode_3976x2736_regs[]`
byte-for-byte — an entry this session's tooling read as address `0x90d0` printed as
`0xd090` (and `0x90c8` as `0xc890`), which is exactly Linux's real register byte-reversed,
not a coincidence. (The earlier `0xfcfc` cross-check in the mode-table-pointer doc didn't
catch this because `0xfcfc` reads the same either way — a false-positive validation.)

Re-scanning the same table (already confirmed as the active one via the VTS=2856 exact
match) with the corrected address decode finds every PLL/EXTCLK register, and **every
value matches Linux exactly**:

| Register | Windows (RVA `0x25410`, variant 0) | Linux (`s5k3j1.c`) |
|---|---|---|
| `0x0136` (EXTCLK) | `0x1333` | `0x1333` ✓ |
| `0x0300` | `0x0007` | `0x0007` ✓ |
| `0x0304` | `0x0002` | `0x0002` ✓ |
| `0x0306` | `0x0095` | `0x0095` ✓ |
| `0x030c` | `0x0000` | `0x0000` ✓ |
| `0x030e` | `0x0003` | `0x0003` ✓ |
| `0x0310` | `0x0109` | `0x0109` ✓ |
| `0x0312` | `0x0001` | `0x0001` ✓ |

`0x0308`/`0x030a` (added to the watch list in section 2 above, since they're read back
elsewhere) aren't written by either driver — Linux's own table has no entries for them
either, so their absence is consistent, not a gap.

**This closes brief 5's question completely, with a clean positive result, straight from
the static file — no live capture or WinDbg session needed after all.** The sensor's
PLL/EXTCLK configuration is byte-for-byte identical between Windows and Linux on this
hardware. Combined with every other register-level parity check this investigation has
done (CSI2 FE/hub-access registers, buttress clock/power state, PHY calibration table),
sensor PLL configuration is now definitively ruled out as the cause of the Linux-side
corruption, joining that same list rather than remaining an open question.
