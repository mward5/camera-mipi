# VCM identification investigation — 2026-07-14

How the rear S5K3J1 camera's VCM/autofocus actuator chip was identified as `LC898217`
(ON Semiconductor), starting from an unrecognized ACPI byte value. Written up here since
this only otherwise existed in a conversation transcript.

## Starting point: `vcmtype = 19`, unrecognized everywhere

Intel's camera ACPI convention exposes a per-sensor descriptor block, `SSDB`, readable as
a named ACPI buffer under the sensor's own ACPI scope (here, `\_SB.PC00.LNK0`, the rear
camera's link per Windows PnP data). Its layout matches `struct ipu_sensor_ssdb` in
mainline `include/media/ipu-bridge.h` — a `vcmtype` byte at offset `0x4F` (79 decimal)
that's supposed to name the actuator chip via a lookup table.

Read live via `acpi_call`:
```
modprobe acpi_call
echo '\_SB.PC00.LNK0.SSDB' > /proc/acpi/call
cat /proc/acpi/call   # decode byte 79 (0-indexed) of the returned hex buffer
```
Result: `vcmtype = 0x13 = 19`.

This was independently re-confirmed by the *stock*, unmodified Ubuntu kernel's own
`ipu_bridge.c` logging at boot: `acpi INT346D:00: Unknown VCM type 19` — solid,
twice-confirmed data, not an artifact of any local patch.

The problem: every VCM name table available named at most ~14 entries (Intel's own
`ipu_vcm_types[]` in `drivers/media/pci/intel/ipu-bridge.c`, and — after extracting
strings from the actual Dell Windows driver binary `s5k3j1sx04.sys` — its own compiled-in
chip list, which extends further than Intel's kernel table but still stops at index 14
(`LC898217`, as it turned out, ironically — see below). Index 19 matched nothing named
in either.

## Dead ends tried first

1. **`Windows.Devices.I2c` WinRT API** — callable without error, but only exposes a
   virtual `ACPI\MSFT8000` test bus (leftover Windows IoT Core infrastructure), not the
   real Intel Serial IO I2C controllers the camera is actually on. Doesn't reach real
   hardware on this class of desktop/laptop machine.
2. **RWEverything** — blocked not by ordinary SmartScreen reputation flagging but by
   Microsoft's **Vulnerable Driver Blocklist** (its bundled `RwDrv.sys`, WinRing0-family,
   is a known BYOVD tool). Disabling HVCI/Smart App Control to work around it would have
   required a reboot on a Windows To Go install that doesn't reboot cleanly — not
   attempted. Also, its classic I2C/SMBus tab targets the legacy PCH SMBus controller,
   architecturally separate from the modern Serial IO/LPSS controllers the camera is on —
   uncertain it would have reached the right bus even if unblocked.
3. **Live WinDbg kernel debugging** — got fully working after real effort (three rough
   reboots: signature-verification failures on Microsoft's own `kldbgdrv.sys` traced to
   an unreliable hardware RTC, eventually resolved with `testsigning on`). Reached deep
   into the driver's dispatch chain (`!drvobj` → `DRIVER_OBJECT`/`DEVICE_OBJECT` →
   vtable → `DispatchDeviceControl`) via clean, verifiable steps, but stalled in
   undocumented WDF/KMDF internal C++ class layouts with no public structure definitions
   to check offsets against. A search for the VCM validation error string and every
   per-chip debug string (`DW9808_SetPos`, etc.) in live memory found **zero hits** —
   explained by the next finding.

## What actually worked: static string/data analysis of the on-disk binary

The `INIT` section of a Windows driver (one-time setup code/data, including debug
strings only needed during driver load) gets freed from memory after boot — which is
exactly why the live-memory searches in step 3 above found nothing. But it's still
present in the **on-disk** `.sys` file. Just copying the file
(`C:\Windows\System32\drivers\s5k3j1sx04.sys`, no live debugging, no reboot, no elevation
needed) and extracting printable strings offline found what live memory couldn't:

- The exact validation error string (a prior paraphrase had been slightly wrong):
  `"[ERROR] %s CheckVcmTable Order Error, disable VCM to keep safe!!!!!!, vcmtype=%d, Vcm[vcmtype].Type=%d"`
- Build provenance: `c:\Jenkins\workspace\adl_pipeline\Source\Camera\Platform\ADL\x64\Release\s5k3j1sx04.pdb`
  — an Alder-Lake-specific CI build, consistent with this exact laptop's platform.
- Exactly **14** compiled-in VCM chip implementations (`<CHIP>_SetPos`/`_Init`/etc. debug
  strings), in this order: `AD5823, DW9714, AD5816, DW9719, DW9718, DW9806B, WV517S,
  LC898122XA, LC898212AXB, AK7371, BU64297GWZ, DW9800, DW9808, LC898217` — this order
  matched Intel's kernel table for indices 1–9, extending further, but topping out at 14.

**First conclusion (wrong)**: assumed string-declaration order in the binary matched the
actual `Vcm[]` array index order, which would put index 13 → `DW9808` (via a BCD-decode
reinterpretation of the `0x13` byte, since raw hex 19 didn't fit a 14-entry table at all).
This was a reasonable-looking but ultimately incorrect inference — flagged here as a
lesson: **string layout order in a compiled binary is not guaranteed to match array
initializer index order.** The compiler can and did lay these out differently.

## Settling it for real: reading the actual `Vcm[]` table with Ghidra

Installed Ghidra 12.1.2 (official NSA release, not the unofficial community snap) with
PyGhidra for scriptable headless analysis (`reference/ghidra-analysis/*.py`). Loaded the
copied `s5k3j1sx04.sys`, let auto-analysis run, then:

1. Found `CheckVcmTable`'s actual logic (`analyze_vcm.py`): a 20-slot validation array
   (`0x14` = 20 iterations, not 14 as previously assumed), each slot 0x50 (80) bytes wide,
   with a 2-byte `Type` field followed by 5 function-pointer fields.
2. **Read the raw table contents directly** at both candidate indices (`read_vcm_table.py`):
   - **Index 13** (the earlier BCD guess): `Type = 0`, all 5 function pointers `NULL`.
     Completely empty slot. The `DW9808` hypothesis was simply wrong.
   - **Index 19** (the actual raw `vcmtype` value, no reinterpretation): `Type = 428
     (0x1ac)`, five real, non-null function pointers, in a completely different code
     region than any of the `DW9808` functions.
3. Decompiled those five function pointers (`identify_slot19.py`) and found their own
   internal debug strings: `"LC898217_SetPos"`, `"LC898217_GetPos"`,
   `"LC898217_GetStatus"`, `"LC898217_SetConfig"`, plus a shared `GetHPStatus`
   implementation. **Read directly out of the binary's data, not inferred from string
   layout order this time** — this is the actual answer: `vcmtype = 19` → `LC898217`.

## Register-level protocol extracted (Ghidra decompile of Dell's driver)

No public datasheet for this exact protocol exists (ON Semi's official datasheet
describes the chip architecturally but does not publish its register map — see below).
This is the closest thing to a reference:

- **`Init`**: read reg `0xF0`, expect byte `'r'` (`0x72`) — chip signature/ready check.
  Poll reg `0xE0` until it reads `0` (up to 10×1ms). Write reg `0xE0 = 1` — triggers an
  internal calibration/firmware "download" (matches the `"LC898217_Init down load not
  finish!"` debug string found in the earlier strings pass). Poll reg `0xB3` (up to
  ~500×2ms) waiting for it to clear. Read reg `0x0A` for the initial position.
- **`SetPos`**: clamp to `[0, 0x3FF]` (10-bit range, per this decompile — see open
  question below), write reg `0x84`.
- **`GetPos`**: read reg `0x0A`, shift right 4.
- **`ResetPos`**: re-asserts the current position via `SetPos` (not a ramp-down).
- **`GetStatus`**: reads reg `0x0A` twice, 2ms apart, returns whether they differ (i.e.
  "still settling").

## Independent corroboration: a real upstream Linux driver exists for `LC898217XC`

Found via GitHub/kernel-mailing-list search (real source, not vendor-blob Android trees
this time): `vanilla-mobile-nixos` (a project mainlining Qualcomm SDM845 phones) carries
a full patch series adding `drivers/media/i2c/lc898217xc.c` for the OnePlus 6's rear VCM,
by Vasiliy Doylov. This was **also submitted upstream** to `linux-media@vger.kernel.org`
(now at v3, reviewed by Dave Stevenson — a well-known V4L2/media subsystem reviewer).

Critically: `LC898217XC_DAC_ADDR = CCI_REG16(0x84)` — **the exact same register address**
independently found by decompiling Dell's Windows driver. Two completely independent
reverse-engineering efforts (a phone mainlining community, and this session's binary
decompilation) landing on the same register address is strong, genuine corroboration —
not something either party could have copied from the other.

Dave Stevenson's review comments (all minor, none disputing the register-level approach):
unused struct field, restore focus position after a runtime-PM resume
(`__v4l2_ctrl_handler_setup()`), and some now-unnecessary event-handling boilerplate from
before a mainline WDF-adjacent refactor. Worth incorporating the resume-restore fix when
adapting this driver, since laptop suspend/autosuspend will exercise that path regularly.

Architectural note for the eventual Linux port: **the VCM is not a separate driver or PnP
device on Windows** — all 14 chip implementations are statically linked into
`s5k3j1sx04.sys` itself, selected at runtime via the `Vcm[vcmtype]` table. A Linux port
should still be a standalone `lc898217`-style i2c VCM module binding its own i2c_client
(matching `dw9714.c`/`dw9719.c`'s pattern), not code folded into `s5k3j1.c`.

## Open question: chip variant and position resolution

- Windows binary (`LC898217`, no suffix) clamps to 10-bit (`0x3FF` = 1023).
- The real Linux driver (`LC898217XC`, explicit suffix) uses 11-bit (`2047`).
- ON Semi's official datasheet for `LC898217XC`
  (`reference/ghidra-analysis/datasheets/LC898217XC_D-1810890.pdf`) confirms chip
  architecture (closed-loop AF, 128-byte EEPROM 16B/page, 110mA constant-current driver —
  matches the Linux driver's Kconfig text exactly, VDD 2.6–3.3V, I2C-compatible 2-wire
  interface up to 1MHz) but **does not publish a DAC bit-width or register map at all**.
  Neither the 10-bit nor 11-bit number can be confirmed against a vendor spec — both were
  independently reverse-engineered, not read from documentation.
- DigiKey component-lifecycle data: `LC898217XC-MH` was marked EOL in June 2023, with a
  packaging change notice from Feb 2020 — meaning it was a normal, actively-produced part
  through at least early 2023. Dell's XPS 13 9315 2-in-1 (late 2022) would have sourced
  components while this exact SKU was still current production, just months before its
  EOL — a plausible, tight timeline match, not a stretch.
- **Practical risk if this is guessed wrong**: not a precision issue (1024 vs. 2048 steps
  over a few hundred microns of travel is imperceptible either way) but a **boundary**
  issue — if the real hardware is 10-bit and code sends an 11-bit-range value, the extra
  top bit could alias/wrap unpredictably (e.g. position 1500 silently becoming 1500 &
  0x3FF = 476), breaking a focus-search loop's assumption of monotonic position-vs-command
  behavior. Recommend defaulting to the conservative 10-bit range until tested against
  real hardware.

## Final confirmation on real hardware (2026-07-15)

Everything above was static analysis and cross-referencing — strong, but not a live
hardware test. Two more pieces closed the loop:

**Finding the actual I2C address, from data already on hand.** `\_SB.PC00.LNK0._CRS`
builds its resource buffer as a sequence of `IICB(L0Ax, L0BS)` calls, gated by a
device-count field `L0DI` (`If (L0DI > Zero) ... If (L0DI > One) ...`, etc. — a
mostly-static device-tree-like enumeration baked into ACPI bytecode). Unlike `L0VC`
(read earlier via the `SSDB` convenience method), there's no method that conveniently
returns `L0A0`/`L0A1`/`L0A2` — `_CRS` itself only builds and returns them if `L0DI`
is already nonzero, and the old working assumption (`L0DI == 0`, from the original
Cursor-era investigation) turned out to have never actually been verified by directly
reading NVS. Parsing the `GNVS` `Field` block in `DSDT.dsl` (same technique as before:
sum cumulative bit-widths of every preceding field, watching for `Offset()` resets) gave
exact byte offsets: `L0DI` at GNVS+1493, `L0BS` at +1494, `L0A0` at +1495 (16-bit),
`L0A1` at +1497 (16-bit), `L0A2` at +1499 (16-bit) — physical addresses `0x6150C5D5`
through `0x6150C5DA` (`GNVS` base `0x6150C000`). Read directly via `/dev/mem` (a
standard, read-only technique for ACPI NVS, which is reserved memory rather than general
System RAM, so `STRICT_DEVMEM` typically permits reads):

```
sudo dd if=/dev/mem bs=1 skip=$((0x6150C5D5)) count=8 2>/dev/null | xxd
# 0301 1000 5000 7200
```

Decoded: `L0DI = 3` (not 0 — three devices declared, correcting the old assumption),
`L0A0 = 0x10` (the sensor's own known address — confirms the byte alignment is right),
`L0A1 = 0x50` (the EEPROM's known address — a second independent confirmation), and
`L0A2 = 0x72` — a third slot, unaccounted for by anything else already identified. Given
the sensor and EEPROM already occupy the first two slots, this third address was a
strong candidate for the VCM.

**Live confirmation.** With the `TPS68470_VCM` regulator forced on (the `always_on`
diagnostic hack in `drivers/int3472-tps68470/tps68470_board_data.c`) and the system
rebooted (confirmed via dmesg: `VCM: Bringing 875000uV into 2815200-2815200uV`),
a targeted register read:

```
sudo i2cget -y 1 0x72 0xf0 b
# 0x72
```

returned exactly `0x72` — the ASCII `'r'` signature byte that the Ghidra-decompiled
`LC898217_Init` routine checks for at register `0xF0` before proceeding. Notably,
`i2cdetect`'s own generic bus scan does *not* show a device at `0x72` (its default probe
method, constrained by the `i2c_designware` controller's lack of SMBus Quick Write
support, apparently doesn't reliably hit this specific address) — the targeted `i2cget`
is what actually confirmed it, not the broad scan.

**Bottom line**: the chip is confirmed present, powered, and identifies itself correctly
at I2C address `0x72`. Chip identity and address are no longer open questions — the
remaining work is writing the actual Linux driver (see `STATUS.md` TODO).
