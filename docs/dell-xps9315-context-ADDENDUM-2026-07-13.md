# Addendum to dell-xps9315-ipu6-rear-camera-context.md — 2026-07-13

**Why this is a separate file:** the original context doc (`dell-xps9315-ipu6-rear-camera-context.md`) is owned by an admin/root ACL on this filesystem and isn't writable from a normal user session, so this session's findings are appended here instead. Read the original first for full background, then this file for what's changed since its §10 (2026-05-18).

## §11. Linux kernel progress (2026-07-13) — VCM identification breakthrough, and a regression

**Big finding: the ACPI-declared VCM type is confirmed, and it's a number Intel's own tooling doesn't recognize.**

The rear sensor's ACPI `SSDB` buffer (returned by a `Method (SSDB, 0, ...)` under `\_SB.PC00.LNK0`, same struct shape used everywhere for Intel camera modules) has a `vcmtype` field at byte offset `0x4F` (79 decimal) inside a 108-byte (`0x6C`) buffer — this lines up exactly with `struct ipu_sensor_ssdb.vcmtype` in the mainline kernel's `include/media/ipu-bridge.h`. Reading it live on Linux via `acpi_call` (`modprobe acpi_call; echo '\_SB.PC00.LNK0.SSDB' > /proc/acpi/call; cat /proc/acpi/call`, byte 79 of the returned hex buffer):

```
vcmtype = 0x13 = 19 (decimal)
```

This was independently re-confirmed by the *stock*, unmodified Ubuntu kernel package (not our out-of-tree work) logging at boot:
```
acpi INT346D:00: Unknown VCM type 19
```
So this is solid, twice-confirmed data, not a fluke of our custom code.

**The problem: 19 doesn't match anything named.** The kernel's own `ipu_vcm_types[]` table (`drivers/media/pci/intel/ipu-bridge.c`) only has 9 entries:
```
1=ad5823, 2=dw9714, 3=ad5816, 4=dw9719, 5=dw9718, 6=dw9806b, 7=wv517s, 8=lc898122xa, 9=lc898212axb
```
We also pulled the *actual* Dell driver binary (`s5k3j1sx04.sys`, confirmed via Dell's support page to be the latest available version — no newer driver exists to check) and extracted its internal VCM name string table via `strings`, which extends further but still stops short:
```
0=NoneVCM, 1=AD5823, 2=DW9714, 3=AD5816, 4=DW9719, 5=DW9718, 6=DW9806B, 7=WV517S,
8=LC898122XA, 9=LC898212AXB, 10=AK7371, 11=BU64297GWZ, 12=DW9800, 13=DW9808, 14=LC898217
```
Index **19 is past the end of even this longer table**. One untested hypothesis: the byte could be BCD-encoded (`0x13` read as decimal "13" rather than hex 19), which would point to `DW9808` — plausible but unconfirmed.

**EEPROM found, not (yet) a VCM.** After fixing two driver bugs that were blocking the rear sensor from actually probing (see below), a real, powered I2C bus scan (`i2cdetect -y 1`) found exactly one other device on the bus at address **`0x50`**. Reading its register 0 (`i2cget -y 1 0x50 0x00 b`) returned `0x0a` — this does **not** match `dw9719`'s known chip-ID register value (`0xF1`). `0x50` is a very standard address for a camera-module calibration/OTP EEPROM, so the working theory is this is an EEPROM, not the VCM actuator. No other address responded anywhere in a full `0x03`–`0x77` scan.

**Likely explanation for finding nothing else: the VCM's power rail may simply be off.** The `TPS68470_VCM` regulator slot in the local board-data patch (`int3472-tps68470-test/tps68470_board_data.c`, struct `dell_7212_tps68470_vcm_reg_init_data`) has `num_consumer_supplies = 0` — nothing currently requests/enables it, since `s5k3j1.c` has zero VCM-related code at all. If a physical VCM chip exists on its own dedicated rail (very plausible), it would sit completely silent on the bus, unpowered, explaining why the scan found nothing there even though autofocus visibly works in Windows. A diagnostic-only `.always_on = 1` was added locally to force this rail on for testing; result not yet confirmed as of this note (reboot to test was in progress).

**Two real driver bugs found and fixed in the local out-of-tree copies** (paths are Linux-side, under `~/work/ubuntu-src/`, not present on this Windows filesystem):
1. `ipu-bridge-test/ipu-bridge.c`: a genuine ordering bug in `ipu_bridge_connect_sensor()` — the INT346D-specific i2c-client-instantiation quirk was scheduled as async work *before* `primary->secondary = fwnode` (which attaches the swnode graph carrying `link-frequencies`/`data-lanes`/etc.) was set. If that async work ran first, `s5k3j1_probe()` would see a fwnode with no properties and fail permanently (`-EINVAL`, not deferred). Fixed by moving the quirk trigger to after the secondary-fwnode assignment.
2. A separate, harder-to-pin-down issue turned out to be a **methodology** bug, not a code bug: repeated `insmod`/`rmmod` reload cycles (without rebooting) silently no-op *any* source change, because `ipu_bridge_init()` bails out immediately if the IPU6 controller's fwnode graph already has any endpoint at all — which it will, from the very first successful boot-time probe (even a stock one). The fix was to stop testing via manual reload and instead install the built `.ko` files into `/lib/modules/$(uname -r)/updates/` (which `depmod` prioritizes over `kernel/` for same-named modules — same mechanism `acpi-call-dkms` uses) + `depmod -a` + `update-initramfs -u`, then reboot, so the custom modules are what load automatically at boot, before anything stock gets a chance to run first.

Both `s5k3j1.c` and `ipu-bridge.c` currently have temporary `dev_info`/`pr_info` debug prints added for this diagnosis — **these should be removed** before treating the local tree as a clean patch.

**Important regression, unresolved:** with the custom driver stack (`ipu-bridge.c` + `tps68470_board_data.c` + `s5k3j1.c`) actually loaded and working, **dual-monitor stopped working** — the 2-in-1's internal display and an external LG monitor would not work simultaneously; only one at a time. Reverting to stock modules fixed it immediately. Not yet root-caused. One plausible mechanism: the ACPI table shows the IPU6 exposed as a child device under `\_SB.PC00.GFX0` (`Device (IPUA)` at `_ADR 0x3480`), suggesting some ACPI-level coupling between the camera ISP and the integrated GPU on this platform (shared power resource or GPIO, perhaps) — unconfirmed, just a hypothesis. **Treat this as a real blocker for daily-driver use of the custom stack**, independent of how the camera work itself goes.

**See also:** `WINDOWS-AGENT-BRIEF.md` in this same folder — a task-oriented brief for a Claude Code agent running in this Windows To Go environment, with a concrete next-step task list for identifying the physical VCM chip.
