# Status — 2026-07-21 (updated)

> **★ 2026-07-21: REAR CAMERA CORRUPTION SOLVED.** Root cause = `PPI2CSI_CONFIG_PPI_INTF`
> (reg 0x204) **bit 1**, which mainline `ipu6-isys-csi2.c` never sets and Windows sets on every
> port. With it set, the rear S5K3J1 streams sustained 25 fps with real image data; with it clear,
> the stream dies with a fatal DPHY error. **Production fix committed** (`drivers/ipu6-isys`
> `fb9ea18`): DMI-gated bit-1 set for this exact model, debug param removed, builds clean —
> **not yet installed/running** (needs `scripts/install-custom-modules.sh` + reboot to replace the
> debug-param module currently loaded). See the "2026-07-21: BREAKTHROUGH" section below.

## What works

- Rear `S5K3J1` sensor (ACPI `INT346D`) probes and streams correctly, with the custom
  `ipu-bridge`/`int3472-tps68470`/`s5k3j1` module stack installed via
  `scripts/install-custom-modules.sh` (into `/lib/modules/$(uname -r)/updates/` +
  `depmod` + `update-initramfs`, so the custom modules load automatically at boot,
  before stock modules get a chance to run first and pollute the ACPI fwnode graph state
  — see "Testing methodology" below for why this matters).
- ACPI `SSDB` struct decoding is solid and reproducible: `vcmtype` lives at byte offset
  `0x4F` (79) in the 108-byte buffer returned by `\_SB.PC00.LNK0.SSDB`, matching
  `struct ipu_sensor_ssdb` in mainline `include/media/ipu-bridge.h`. Read live via
  `acpi_call` (`modprobe acpi_call; echo '\_SB.PC00.LNK0.SSDB' > /proc/acpi/call; cat /proc/acpi/call`).
- **The `lc898217` VCM driver, fully verified on real hardware (2026-07-15).** Confirmed
  end-to-end: `ipu_bridge_instantiate_vcm()` creates the client at the right `_CRS` index,
  the driver probes and binds, shows up in `media-ctl -p` as `lc898217 1-0072` (`subtype
  Lens`, independently reconfirming the `0x72` address via a completely different code
  path than the original reverse-engineering), exposes `focus_absolute` with the expected
  `0-1023` range, accepts a real `v4l2-ctl -c focus_absolute=300` write, and the regulator
  goes `active` via genuine runtime PM (not the old `always_on` hack) — meaning the `Init`
  calibration handshake against the real chip succeeded too, since a failure there would
  have made the `v4l2-ctl` open/set calls themselves fail. See "VCM driver" section below
  for the one real bug found and fixed along the way.

## VCM identity: `LC898217` (ON Semiconductor) — CONFIRMED on real hardware

This took a long path to resolve — see `docs/vcm-investigation-lc898217.md` for the full
story. Summary:

- `vcmtype = 19 (0x13)`, confirmed independently by both a live `acpi_call` read and the
  *stock* Ubuntu kernel's own `ipu_bridge.c` logging `Unknown VCM type 19` at boot.
- This index doesn't match any of the ~14 named entries in Intel's own `ipu_vcm_types[]`
  table or the actual Dell Windows driver's compiled-in chip list — an initial guess of
  `DW9808` (via a BCD-decode hypothesis on the byte) turned out to be **wrong**.
- Ghidra decompilation of the real Windows driver (`s5k3j1sx04.sys`, copied locally —
  see `reference/windows-driver-artifacts/`) found that `Vcm[19]` (the *exact* raw index,
  no reinterpretation needed) is a real, populated table entry whose function pointers
  resolve to code containing internal debug strings `"LC898217_SetPos"`,
  `"LC898217_GetPos"`, `"LC898217_GetStatus"`, `"LC898217_SetConfig"` — read directly out
  of the binary, not inferred.
- Independently, a real, currently-in-upstream-review Linux driver exists for the closely
  related `LC898217XC` variant (`drivers/media/i2c/lc898217xc.c`, submitted to
  `linux-media@vger.kernel.org` by Vasiliy Doylov, reviewed by Dave Stevenson) — and its
  DAC register address (`CCI_REG16(0x84)`) matches exactly what the Ghidra decompile of
  Dell's driver found for the position-set function. Two independent reverse-engineering
  efforts agreeing on the same register address is strong corroboration.
- ON Semi's official `LC898217XC` datasheet (in `reference/ghidra-analysis/datasheets/`)
  confirms the chip architecture (closed-loop AF, 128-byte EEPROM, 110mA driver — matches
  the Linux driver's Kconfig text exactly) but does **not** publish the register map or a
  DAC bit-width — so neither of the two reverse-engineered numbers (10-bit clamp in the
  Windows binary vs. 11-bit in the `lc898217xc.c` driver) can be confirmed against a
  vendor spec. Component lifecycle data (DigiKey: `LC898217XC-MH` EOL'd June 2023) is
  consistent with Dell's late-2022 laptop having used this exact variant.

**Confirmed 2026-07-15, on real hardware.** `\_SB.PC00.LNK0._CRS` builds its resource
buffer from up to several `IICB(L0Ax, L0BS)` I2C address slots, gated by a device-count
field `L0DI`. Read live via `/dev/mem` (these NVS fields have no convenience accessor
like `SSDB` does): `L0DI = 3` (not `0`, correcting an old assumption that was never
actually verified directly), `L0A0 = 0x10` (the sensor — confirms byte alignment is
correct), `L0A1 = 0x50` (the EEPROM — second independent confirmation), and a third slot
`L0A2 = 0x72`. With the `TPS68470_VCM` regulator forced on (the `always_on` diagnostic
hack) and the system rebooted, `i2cget -y 1 0x72 0xf0 b` returned **`0x72`** — exactly
the ASCII `'r'` signature byte the Ghidra-decompiled `LC898217_Init` routine checks for
at that exact register. (Note: `i2cdetect`'s own generic scan does *not* show a device at
`0x72` — its default probe method apparently doesn't reliably hit this address; the
targeted register read is what actually confirmed it.) This is about as close to
definitive proof as reverse-engineering without a vendor register-map datasheet gets:
**the chip is present, powered, and identifies itself correctly at I2C address `0x72`.**

**Open question, now more tractable**: 10-bit vs. 11-bit position range. Not just a
precision question — if the real hardware is 10-bit and code sends an 11-bit-range
value, the top bit could alias or wrap unpredictably. With the chip now confirmed
present and readable, this could plausibly be tested directly (e.g. write a position via
`i2cset` and read back via `GetPos`/`GetStatus` to see if values above `0x3FF` behave
sanely) rather than guessed at — not yet attempted, but no longer blocked on chip
identity.

## Dual-monitor flakiness — RESOLVED (for this project's purposes): unrelated mutter bug, filed upstream

Originally flagged as a regression: with the custom driver stack loaded, the 2-in-1's
internal display and an external monitor appeared to stop working simultaneously, fixed
by reverting to stock modules. That original correlation no longer looks causal:

- 2026-07-15: dual-monitor came up fine with the custom stack loaded (same reboot that
  confirmed the VCM chip at `0x72`).
- User has also since observed the *same* single-output symptom with **stock modules,
  no custom stack loaded at all**.

**2026-07-22: root cause fully diagnosed, confirmed unrelated to this camera work.**
It's a genuine mutter bug, not a kernel/i915/driver-stack issue: hot-replugging a
Thunderbolt monitor/dock while the laptop lid is closed triggers a Thunderbolt
tunnel-activation failure (`downstream port is locked` → USB3/PCIe/DP tunnels all fail
→ device bounces/re-enumerates), and the resulting HPD storm leaves mutter looping
forever on `Page flip failed: drmModeAtomicCommit: Invalid argument` for the internal
`eDP-1` panel — exactly one CRTC can ever be lit until recovered. A VT-switch
(`Ctrl+Alt+F3` → `Ctrl+Alt+F2`) forces a full modeset and clears it in-process, proving
the kernel/i915 connector state itself is fine; mutter just fails to fall back from an
incremental page-flip to a full modeset after the hotplug event. Filed upstream with a
full debug-armed reproduction log: [mutter#4928](https://gitlab.gnome.org/GNOME/mutter/-/work_items/4928).

Closed out as a gating concern for this project — no further action needed here; not a
blocker for daily-driver use of the camera work. Any future recurrence: use the
VT-switch recovery above, and see `~/mutter-4928-capture-note.md` if another
debug-armed capture is ever needed for that upstream issue.

## Testing methodology note

Simple `insmod`/`rmmod` reload cycles are **not reliable** for testing changes to
`ipu-bridge.c`: `ipu_bridge_init()` early-exits if the IPU6 controller's fwnode graph
already has *any* endpoint from an earlier boot-time probe (even a stock one), silently
no-op'ing any fix without any error. Always test via a clean boot with the custom
modules installed into the module tree (`scripts/install-custom-modules.sh`), not via
manual reload (`scripts/reload-rear-and-scan-vcm.sh` is kept for reference/quick
diagnostics only, marked as such in its header).

## VCM driver: written, builds clean, not yet tested on hardware

`drivers/lc898217/lc898217.c` now exists — adapted from the real upstream
`lc898217xc.c` v3 (fetched verbatim from the linux-media mailing list this
session, not reconstructed from a summary), with Vasiliy Doylov's copyright
preserved and ours added alongside. Builds cleanly against this kernel's
headers. Changes made this session, in order:

1. **Live-confirmed `\_SB.PC00.LNK0._CRS` now returns a proper, populated
   3-resource buffer** (sensor `0x10` / EEPROM `0x50` / VCM `0x72`, in that
   index order, valid End Tag) — read via `acpi_call`. This means the
   original "empty `_CRS`" premise behind the existing sensor-instantiation
   quirk doesn't hold *at this point in boot*; whatever originally motivated
   that quirk was more likely the `ipu_bridge_init()` early-exit timing
   issue already documented above, not a genuinely empty resource buffer.
   Not investigated further this session (out of scope), but worth keeping
   in mind for the eventual patch-series cleanup.
2. **`ipu_vcm_types[18] = "lc898217"`** added in `drivers/ipu-bridge/ipu-bridge.c`
   for `SSDB.vcmtype == 19`.
3. **`_CRS` resource-index fix for the VCM**: mainline's
   `ipu_bridge_instantiate_vcm_work()` hardcodes resource index `1` (correct
   for the common two-resource sensor+VCM case), which on this machine's
   three-resource layout resolves to the *EEPROM's* address instead of the
   VCM's. Fixed via a new `xps9315_2in1_vcm_index_quirk()` helper, gated on
   **both** DMI (exact model) and HID — not HID alone — so this cannot
   affect any other machine, including other `INT346D`-based laptops that
   may have the more common two-resource layout. This gating choice is
   explicitly driven by the goal of eventual upstream submission with zero
   regression risk to already-supported hardware (see "Upstream goal"
   below).
4. **`drivers/lc898217/lc898217.c` written** (new standalone out-of-tree
   module, own git repo, same convention as the other three driver dirs).
   Implements the `Init` calibration handshake this chip appears to need
   (register `0xF0` signature check, `0xE0` trigger/poll, `0xB3` completion
   poll — none of which the XC variant's driver does) behind a
   `skip_chip_init` module param for easy A/B testing against a bare DAC
   write. Uses the conservative 10-bit position range. Proactively
   incorporates Dave Stevenson's real v3 review feedback on `lc898217xc.c`
   (fetched verbatim, not yet folded into that driver upstream as of this
   writing): drops the unused `focus` ctrl pointer, restores position via
   `__v4l2_ctrl_handler_setup()` on runtime-PM resume, drops the now-
   unnecessary `.subscribe_event`/`.unsubscribe_event` ops and
   `V4L2_SUBDEV_FL_HAS_EVENTS`.
5. **`TPS68470_VCM` regulator wiring fixed**: gave the XPS 13 9315 2-in-1 its
   own `xps9315_2in1_tps68470_vcm_reg_init_data` (it had been reusing
   `dell_7212_tps68470_vcm_reg_init_data`, a genuinely different Dell
   model's struct) with a real `REGULATOR_SUPPLY("vcc", "i2c-INT346D:00-VCM")`
   consumer matching the new driver, and removed the diagnostic
   `.always_on = 1` hack — which, as a side effect of the struct sharing,
   had been leaking into that other Dell model's behavior too. Both structs
   are now independent and clean.
6. `scripts/install-custom-modules.sh` updated to build/install
   `lc898217.ko` alongside the other three modules.
7. **Real bug found and fixed via hardware testing: missing `i2c_device_id`
   table.** The driver (and `lc898217xc.c` upstream, which has the same gap)
   relied solely on `of_match_table` for i2c driver binding. This machine's
   kernel has `CONFIG_OF` disabled (confirmed via `/boot/config-*`), and
   `i2c_of_match_device()` unconditionally returns `NULL` in that case
   (`drivers/i2c/i2c-core.h`) — so the VCM client (created via swnode name,
   not a real OF/ACPI node) never bound to any driver at all, silently,
   with no error anywhere. Diagnosed by adding temporary `dev_info()` trace
   prints to `lc898217_probe()` and confirming it was never even being
   called. Fixed by adding a proper `i2c_device_id` table (`{ "lc898217" }`)
   and `.id_table`, matching what the real, working `dw9714.c` already does
   — `i2c_match_id()` is the `CONFIG_OF`-independent fallback match path.
   This also fixed a secondary issue: without an `i2c_device_id` table, the
   module's only advertised modalias was `of:...`, while the actual device
   uevent is `i2c:lc898217` — so udev could never auto-load the module at
   boot either, even once binding was fixed. **Worth reporting back** to
   Vasiliy Doylov's real `lc898217xc.c` v3 submission as review feedback —
   it likely has the identical bug on any `CONFIG_OF=n` x86 platform, and
   nobody caught it in the review thread (Dave Stevenson's comments didn't
   mention it).

**Fully verified working end-to-end 2026-07-15** (see "What works" above
for the specifics): driver binds, shows up correctly in `media-ctl -p` as
a `Lens` entity at `1-0072`, `focus_absolute` control works with a real
value write, and the `Init` handshake + regulator wiring both function
correctly via genuine runtime PM.

**Still open**: test `skip_chip_init=1` to see whether the Init handshake
is actually load-bearing or the bare DAC write (matching the XC driver) is
sufficient — not yet tested, since the handshake already works fine as-is
and there's no urgency to simplify it. (Note: this module param was
subsequently removed - see below - since the handshake is unconditional now.)
Actually removed 2026-07-15: `skip_chip_init` dropped, handshake now always
runs (proven correct via live testing; Windows does it unconditionally too).

## Rear camera: no picture in desktop apps (separate, unresolved issue)

Unmasking PipeWire and opening the Camera app (GNOME Snapshot) selecting the
rear camera showed a **black screen** — a genuinely separate problem from
the VCM work above, since the rear sensor's own video streaming was never
previously tested through the *full* desktop pipeline (PipeWire → libcamera
→ GNOME app), only via more basic methods. Investigated 2026-07-15,
extensively, with two real findings:

### Fixed: a genuine link-frequency bug (512MHz vs. 848MHz)

See the `s5k3j1.c` and `ipu-bridge.c` commits from this session. The `848MHz`
value used everywhere (an early guess, per its own comment) didn't match
the sensor driver's own per-mode PPL/VTS timing (which implies 512MHz via
the driver's 2x-per-lane doubling formula — matching both the
`mipi_data_rate_1024mbps` register table name and `S5K3J1_PPL_512MHZ`).
Fixed and confirmed via live testing: the initial "stream stop/close time
out" **crash-loop** (repeating every ~10-90s) is gone — streaming is now
stable at the kernel level. This was a real bug, worth keeping fixed
regardless of the remaining issue below.

### Still unresolved: no frames ever actually complete

Even with the link-frequency fix, the picture is still black. Diagnosed via
`intel_ipu6_isys` dynamic-debug logging: buffers get queued cleanly into
"Intel IPU6 ISYS Capture 8", the pipeline is fully armed, but **zero
interrupt-driven activity happens afterward** — no start-of-frame, no
capture-done, and critically, **no CSI2 PHY-level errors** either (which
would show as `csi2-N error: ...` if the raw D-PHY signal were garbled).
That combination (clean setup, zero interrupts, no PHY errors) points to
the sensor's own internal firmware/microcode never actually beginning real
pixel transmission, despite its software `MODE_SELECT=STREAMING` register
write succeeding at the I2C level (which only proves the byte was written,
not that the uploaded code does what's intended).

**`mode_3976x2736_regs[]`** (in `s5k3j1.c`, register addresses starting
around `0x90c8`) is not a simple named-register table — the byte pattern
(confirmed 2026-07-15: a contiguous 200-entry/400-byte run from `0x90c8`
to `0x9256`, everything else in the table is normal scattered register
config) looks like actual ARM Cortex-M machine code being uploaded into
the sensor's internal processor (a firmware/microcode blob). I2C writes to
it always report success regardless of whether the *uploaded code* is
byte-for-byte correct.

**Corrected 2026-07-15 — this is NOT a reverse-engineered blob and is no
longer the leading suspect.** `git log -L` on `s5k3j1.c` shows the entire
`mode_3976x2736_regs[]` table, including this microcode run, came from the
very first commit (`3cdeb08`, "Import Ubuntu ipu6-drivers
0~git202603270946.51fe7248-0ubuntu1") — i.e. it's Intel's own
vendor-authored driver code for this exact sensor (file header: `Copyright
(c) 2021 Intel Corporation`, and its own comments already cross-reference
the real `Windows graph_settings_S5K3J1SX04_*` XML for crop values), not
something derived from Ghidra analysis of the Dell Windows driver. A prior
session's note that it "was derived via Ghidra static analysis" was
mistaken. Confirmed directly: the 400-byte microcode run does **not**
appear anywhere in `s5k3j1sx04.sys` (checked byte-for-byte, both 16-bit
endian orders, and as interleaved `{addr,val}` records — no match at any
length down to 8 bytes, whereas the same search methodology correctly
finds the known `LC898217_*` strings in the same file). Since this is
Intel's own shipped code for this exact chip (not a guess), it's now
unlikely to be the bug — look elsewhere first.

**Ruled out, definitively, this session (2026-07-15):**
- PDAF/dual-stream involvement — `pdaf_trial=1` (PDAF fully disabled,
  single-stream only) produces the *identical* failure, so a missing
  second stream isn't the (sole) explanation.
- The link-frequency mismatch — fixed, confirmed via live testing (the
  crash-loop is gone), but didn't produce a picture on its own.
- CSI2 PHY-level signal issues — zero `csi2-N error` messages ever logged.
  **Superseded 2026-07-16, see below — this is no longer true after the
  regulator fix.**
- **The "dual-stream PAFi sideband" approach from an earlier (2026-05-26)
  Cursor session** (archived at
  `~/work/cursor-chat-archive/camera-mipi/2026-05-05_ipu6-camera-debug_1b32533b.md`,
  around line 6301 onward) — that session found the *same* "ISYS Capture 8
  never completes a frame" symptom, ruled out an (unrelated, since-fixed)
  VBLANK register bug as not the root cause, and built dual-stream PDAF
  metadata-sideband routing (kernel driver `get_frame_desc()` two-stream
  support - already present in current `s5k3j1.c` - plus a patched
  `libcamera` `simple` pipeline handler adding `Ip6PdafSideband` support,
  built but **never installed as the system package** - confirmed via
  `strings` on `/usr/lib/x86_64-linux-gnu/libcamera.so.0.7.0`, which has
  none of that code, vs. the local build at
  `~/work/git-ubuntu/libcamera/build/` which does). Tested this session by
  running the local build directly (`LD_LIBRARY_PATH` override, no system
  changes) - its own PDAF-sideband discovery never triggered (confirmed via
  `LIBCAMERA_LOG_LEVELS=SimplePipeline:0`), because it requires a
  CSI2-pad-2-to-Capture-9 media link that doesn't exist by default and must
  be created manually (`media-ctl -l`/`-R`, see
  `scripts/dell-xps9315-test-rear-dual.sh`). Attempting that manual
  creation **fails with `ENOTSUP`**: the kernel's
  `v4l2_subdev_routing_validate()` is called with
  `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1` (`drivers/media/pci/intel/ipu6/ipu6-isys-subdev.c`),
  which explicitly forbids routing one sink pad's streams to *different*
  source pads - exactly what dual-stream PAFi sideband capture requires.
  This is a hard, intentional kernel-driver restriction, not a missing
  setup step - the whole approach is a dead end on this kernel version,
  independent of the "PDAF disabled still fails" finding above that already
  argued against it being the real mechanism.

## 2026-07-16 update: real regulator bug found and fixed, symptom changed (still unresolved)

**Root cause found for the "zero interrupts, zero PHY errors" symptom above:
`avdd` was wired to the wrong TPS68470 rail.** `tps68470_board_data.c`'s
`xps9315_2in1_*` board data (added in the very first rear-camera bring-up
commit, `1b25a92`, 2026-05-22, tagged in its own comment as "Trial C: Dell
7212 rail map") copy-pasted the rail assignment from the **Dell 7212's
`INT3479`** sensor — a different device on a different board — just to get
something that would let `s5k3j1` probe. That left the sensor's `avdd`
(analog rail) request satisfied by `VSIO @ 1.8V` instead of the real analog
supply, while the actual `ANA` regulator (correctly defined at `2.8V`, the
canonical value used by this file's own known-good Surface Go pattern
where `avdd` maps to `ANA`) had **zero consumers wired to it for this
sensor** — confirmed live via `/sys/class/regulator/*/state`: `ANA` read
`disabled` while every other rail the sensor uses read `enabled`. Many CMOS
sensors gate their MIPI D-PHY transmitter itself off the analog domain, so
this is consistent with the sensor's firmware never even attempting real
HS transmission before.

**Fix applied and confirmed live**: moved `avdd`'s consumer-supply mapping
from `VSIO` onto `ANA` (see `int346d_ana_consumer_supplies` in
`tps68470_board_data.c`). After a clean reboot, `ANA` now reads `enabled`
at `2815200` µV, matching spec.

**Symptom changed, but the picture is still black.** A direct `cam`
capture (`scripts/dell-xps9315-test-rear-cam.sh`) now *completes* (no
45s timeout, real sequence numbers) instead of hanging, but the returned
frame is still all-zero pixels. More importantly, the kernel log is now
flooded with CSI2 PHY-layer errors that were completely absent before —
`Single/Multiple packet header error`, `Payload CRC error`, `Frame/Line
sync error`, `DPHY recoverable/fatal sync error`, `SOT sync error`, `FIFO
overflow` (`ipu6_isys_csi2_error`, rate-limited via "callbacks
suppressed"). This is real progress: the failure mode moved from "the
sensor never attempts transmission at all" to "the sensor is transmitting,
but the high-speed link isn't training/syncing correctly at the physical
layer" — a different, and probably more tractable, class of bug.

**One investigation dead-end from this session, worth flagging so it isn't
re-chased**: `drivers/s5k3j1/drivers/media/pci/intel/ipu6/ipu6-isys-csi2.c`
(bundled into this repo by the original `3cdeb08` "Import Ubuntu
ipu6-drivers" commit) has a D-PHY-aggregation scheme
(`ipu6_csi2_dwc_phy_power_set`) with a `port % 2` / "only port a/c/e
support 4 lanes" restriction, and our rear sensor sits on `Intel IPU6 CSI2
1` (an odd port per `media-ctl -p`) — which looked like a strong candidate
root cause. **It isn't relevant**: `intel_ipu6_isys.ko` is a stock kernel
module this project never rebuilds (only `ipu-bridge`/`tps68470`/
`s5k3j1`/`lc898217` go through the custom `updates/` install), and the
*actually running* code, confirmed in `~/work/git-ubuntu/resolute` at the
exact tag matching this kernel, uses a completely different, generic,
formula-based D-PHY timing mechanism (`ipu6_isys_csi2_calc_timing()`,
computing `ctermen`/`csettle`/`dtermen`/`dsettle` purely from `link_freq`
via the standard MIPI D-PHY receiver-timing formula) with no lane-count/
port-parity restriction at all. The bundled `ipu6-isys-*` copy under
`drivers/s5k3j1/drivers/media/pci/intel/ipu6/` is reference-only leftover
from the import commit, not what's loaded on this system — don't debug
against it; use `~/work/git-ubuntu/resolute` for anything ISYS/CSI2/PHY
-level.

**Settle-time hypothesis tested 2026-07-16, ruled out**: added a 2-3ms
delay after `avdd` enable and a 1-2ms delay after `clk_prepare_enable`
(before releasing reset) in `s5k3j1_power_on()`, rebuilt, reinstalled,
clean reboot. Confirmed `ANA` still `enabled` at `2815200` µV. Same CSI2
error signature reproduced (`DPHY recoverable synchronization error`,
`FIFO overflow`, packet header/CRC errors) — PLL/rail settle timing was
not the bottleneck. The delays are harmless and left in place, but this
doesn't explain the remaining failure.

**Dynamic debug pass 2026-07-16 — real further progress, root cause still
not pinned down.** Enabled `dev_dbg` for `ipu6-isys-csi2.c`
(`echo 'file ipu6-isys-csi2.c +p' | sudo tee
/sys/kernel/debug/dynamic_debug/control`) and re-ran the capture test.
Findings:
- Computed D-PHY receiver timing (`ctermen 0 csettle 698 dtermen 0 dsettle
  665`) looks legitimate — `ctermen`/`dtermen` are correctly 0 by the
  driver's own formula (datasheet-minimum `A=0,B=0` coefficients for those
  fields), and `csettle`/`dsettle` (~87ns/~83ns) are in a normal range for
  a ~1Gbps-class link. No obvious host-side misconfiguration here.
- Host correctly configures 4 lanes (`stream on CSI2-1 with 4 lanes`).
- **`sof_event` now fires repeatedly** (13 successive start-of-frame
  events, sequence 0-12, in one stream-on/off cycle) — this directly
  supersedes the original "zero interrupt-driven activity, no
  start-of-frame" diagnosis. The link now achieves frame-level sync
  repeatedly; the failure is packet-level corruption *within* frames
  (header/CRC/sync errors, FIFO overflow) severe enough that no valid
  pixel data survives, not a dead/untrained link.

This pattern (frame sync OK, per-packet data lost) points at either a real
sensor-side bit-rate mismatch (actual transmitted rate not quite matching
the assumed 1024Mbps/lane) or a borderline physical-layer signal integrity
issue — distinguishing the two needs either register-level PLL
reverse-engineering beyond what static analysis has settled, or actual
instrumentation (oscilloscope/protocol analyzer) not available in a normal
debugging session. Treat further single-value guesses (yet another delay,
yet another register tweak) as low-confidence from here; the next
productive step is probably a fresh, targeted Windows-side capture of the
sensor's actual negotiated/working CSI2 timing (same "windows-agent"
methodology already used successfully for the VCM identification), not
more blind static-analysis passes.

**Follow-up static analysis, same session — confirms the wall above, no
new lead.** Went back to `s5k3j1sx04.sys` in Ghidra specifically looking
for the mode-config/PLL table (byte-scanned for the known register
addresses as both an interleaved and a standalone address-only array, and
searched all disassembled instructions for immediate operands matching
`0x90c8`/`0xfcfc`) — **zero matches, any form.** Combined with the earlier
finding that the raw microcode bytes aren't in this binary either, this
confirms Windows's sensor-mode/PLL setup for this resolution isn't in the
sensor microdriver at all — it's handled by a separate, shared Intel
ISP/camera-HAL binary we haven't collected. The only real hit was the chip
ID (`0x30a1`) verification function (`FUN_140008554` in Ghidra's naming) —
confirmed to be a simple probe-time sanity check (read register, compare,
log), no timing/PLL logic. Also checked the `graph_settings_s5k3j1sx04_*.xml`
files for a statically-declared pixel/CSI rate: both `pixel_rate` and
`pixel_rate_csi` are `"0"` in every variant — negotiated at runtime, not
recoverable from the XML offline. **Static analysis of already-collected
artifacts is now genuinely exhausted for this specific question.**

Also traced *why* `bytesused` comes back 0 despite real `sof_event`s: IPU6
capture completion is firmware-driven (the CSE/ISP firmware reports frame
metadata over IPC, evidenced by the `Sending BOOT_LOAD to CSE` /
`AUTHENTICATE_RUN` boot messages), and `ipu6-isys-csi2.c`'s
`receiver_errors` accumulator tracks exactly the PHY error classes we're
seeing. A zero-byte "completed successfully" buffer for a frame the
firmware itself flagged as corrupted is consistent, expected behavior for
this architecture, not a separate software bug on top of the PHY issue —
there's no further Linux-side lead here without reverse-engineering the
closed CSE firmware itself, a much bigger undertaking.

**A new Windows-capture brief has been written**:
`docs/WINDOWS-AGENT-BRIEF-2-csi2-timing.md`, targeting exactly this gap —
get a live, ground-truth register dump of the IPU6 CSI2 receiver's D-PHY
timing/lane config while Windows is actually streaming this sensor, to
diff against Linux's computed `ctermen/csettle/dtermen/dsettle` values.
Follows the same methodology (RWEverything MMIO/PCI reads, WinDbg as
fallback, ETW tracing as a lower-effort alternative) that successfully
resolved the VCM identification. Needs a Windows-To-Go boot to run — not
something continuable from the Linux side alone.

**MCLK/extclk correctness — ruled out, definitively, 2026-07-16.**
`s5k3j1.c`'s `s5k3j1_check_hwcfg()` hard-fails probe (`-EINVAL`) if the
ACPI-reported `clock-frequency` (`ssdb.mclkspeed`, plumbed through by
`ipu-bridge.c`) doesn't exactly equal `S5K3J1_EXT_CLK` (19200000). Since
probe succeeds and the sensor streams, ACPI's reported MCLK is provably
exactly 19.2MHz — this cannot be a silently-wrong-value bug like the
link-frequency one was. (Whether the *physical* oscillator genuinely
outputs 19.2MHz is a hardware-instrumentation question, not something
further code reading can settle.)

**OTP/calibration data — confirmed as a real, separate gap, but probably
not this bug.** Searched `s5k3j1sx04.sys` for calibration-related strings
and found a substantial NVM/OTP subsystem in the real Windows driver:
`parsed_nvm_ptr_lsc` (lens-shading-correction tables), `Calibration
version is %s`, `CheckNvmTable Order Error`, `Failed to Read OTP data`,
`Failed to Read EEPROM data`, plus a documented "skip nvm read... (Type%d)"
path implying it's conditional on module/NVRAM type, not universally
mandatory. Linux currently does zero equivalent EEPROM reading (`0x50` is
still just "probably an EEPROM," never actually read by any Linux driver).
Worth doing eventually for correct image quality, but LSC/calibration is
normally an ISP-side correction applied *after* successful pixel
transmission — unlikely to explain physical-layer D-PHY sync errors, so
it's parked as a known future gap rather than the live suspect.

**Next step for a future session**: with settle-time, MCLK, and receiver
D-PHY config all ruled out or checking out clean, and real progress logged
(SOF events now fire; see dynamic-debug pass above), the remaining failure
is packet-level corruption within an already-frame-synced link. The most
promising lead is a fresh, targeted Windows-side capture of the sensor's
actual working CSI2/PLL configuration (same methodology that resolved the
VCM identification — see `docs/WINDOWS-AGENT-BRIEF.md` as a template),
since further blind static-analysis guesses have diminishing returns at
this point. Budget this as its own investigation, not a quick follow-up.

## 2026-07-16, continued: Windows CSI2 capture — a false lead, then a real one

The Windows-agent capture (`WINDOWS-AGENT-BRIEF-2-csi2-timing.md`) came back with
findings in `windows-agent-findings-csi2-timing-2026-07-16.md`. Two things came out of
it, and it's important to be honest that the first one was chased hard before being
disproven — a real time cost, worth recording so it doesn't happen again.

**False lead: "Linux drives the wrong physical PHY."** The Windows session found PHY0
active/ready and PHY1 idle while genuinely streaming, and flagged that Linux's
`ipu6_isys_driver_port_to_phy_port()` (in `ipu6-isys-mcd-phy.c`, part of the stock
`intel_ipu6_isys.ko` — never previously rebuilt out-of-tree by this project) has a
hardcoded "swap port 0↔1" rule that looked like it would select the wrong PHY for our
sensor. This looked like a strong, well-evidenced lead and real effort went into it: an
out-of-tree build of `intel_ipu6_isys` was set up (`drivers/ipu6-isys/`, copied from
`~/work/git-ubuntu/resolute` at the matching tag, builds clean, correctly depends on the
already-loaded stock `intel-ipu6`) as the vehicle for a DMI+HID-gated fix. **It was wrong.**
Chasing it required conflating three different "port number" concepts (ACPI `LNK0`
naming, a sysfs `port@0` fwnode entry, media-ctl's "CSI2 1" entity name) before finally
checking the one thing that actually resolves it: `ipu6_isys_driver_port_to_phy_port()`
unconditionally `dev_err`s ("invalid port... for lane...", not gated by dynamic debug)
if the port/lane combination is invalid for 4-lane mode — and grepping the entire boot's
kernel log for that string found **zero matches**. That's only possible if Linux's own
port number already computes to the same `phy_port=0` Windows uses. There is no PHY
mismatch. The `drivers/ipu6-isys/` build skeleton is left in place (it compiles and is
genuinely reusable infrastructure) but has no quirk in it — don't resurrect the swap
theory without new evidence.

**Real, still-open lead: per-lane PHY calibration register differences.** With the port
question settled, a script
(comparison logic worth re-deriving if needed — diffs `x4_port0_config_regs[]` from
`ipu6-isys-mcd-phy.c` against the Windows agent's raw hex dump of the same live memory
region) was run to check Windows's §6 finding properly: **44 of the 50 registers in the
per-lane PHY config table differ** between Linux's hardcoded constants and the live
values read off genuinely-working Windows hardware. The differences aren't random —
concentrated in specific byte positions (often the top byte of a 32-bit register,
sometimes a whole middle byte) while other bytes/nibbles match exactly. Intel's own
driver source has zero comments or named bitfields for any of these registers (pure
magic constants), so there's no source-level hint about which bits are meaningful
protocol config (must match) versus per-die factory calibration/trim (legitimately
varies per chip, and would mean Linux's blind 32-bit `writel()` of a fixed table is
**clobbering** real trim data with a generic constant — the actual fix would be a
read-modify-write preserving whatever's already there, not a table-value correction).

**A third Windows-capture brief has been written**:
`docs/WINDOWS-AGENT-BRIEF-3-phy-trim-fields.md` — asks for the same 50 addresses to be
read at three points (fresh boot before any camera use, after first stream start, after
a second open/close cycle) to distinguish "fixed hardware trim nothing ever writes"
from "genuinely recomputed each time" from "written once, stable." That result will
determine whether the real fix is a read-modify-write (preserve trim, only set config
bits) or finding Windows's actual per-boot computation. Needs a Windows-To-Go boot to
run, same as the other two briefs.

## 2026-07-16, continued again: PHY trim results in, a candidate fix written and tested (negative)

The third brief's results came back in
`windows-agent-findings-phy-trim-2026-07-16b.md` — a clean, decisive answer. Of the
whole `0x1960`-byte PHY0 memory region: (1) it reads all `0xFFFFFFFF` before any camera
use this boot (the macro is power-gated/unmapped until first power-up — rules out
"passively-readable factory trim"), and (2) only **6 specific bytes**, none of which
overlap any of the 50 registers in `x4_port0_config_regs[]`, change value between two
consecutive stream stop/starts within the same boot (some kind of per-attempt
calibration/retry state, not exposed to or needed by driver software). Critically, **all
50 of the register fields Linux actually writes were confirmed stable** across repeated
stream restarts — genuine per-board static config, not mid-negotiation noise.

**Fix written**: `drivers/ipu6-isys/ipu6-isys-mcd-phy.c` now has
`xps9315_2in1_x4_port0_config_regs[]`, populated with the live values captured off
genuinely-working Windows hardware (44 of 50 differ from upstream's generic table),
gated on exact DMI model, wired into `ipu6_isys_mcd_phy_config()`'s write loop. This
required setting up `intel_ipu6_isys` as a new (5th) out-of-tree module
(`drivers/ipu6-isys/`, copied from `~/work/git-ubuntu/resolute` at the matching tag —
see that directory's own git log for the full history, including a dead-end PHY-port-
swap theory that was checked and disproven before being shipped). `install-custom-modules.sh`
now builds and installs all 5 modules.

**Caveat noted before testing**: several of the corrected values have their top 24 bits
reading as zero (e.g. register `0x694` → `0xfa`) — consistent with genuine per-die
config, but couldn't rule out these being write-triggered, self-clearing bits (a
post-hoc read wouldn't show what should actually be written).

**Tested on real hardware, 2026-07-16 — negative result.** Rebuilt/installed/rebooted
(all 5 custom modules load; `intel_ipu6_isys(OE)` tainted-module marker and matching
`srcversion` between the loaded module and the built `.ko` both confirm the custom build
is genuinely what's running, not the stock module). Enabled dynamic debug for
`ipu6-isys-mcd-phy.c` and re-ran the capture test. The existing `dev_dbg` at the port/PHY
assignment point logged **`port1 PHY0 lanes 4`** for the rear sensor — meaning the real
runtime `cfg->port` is **1**, not 0 as an earlier write-up in this file mistakenly said
(a narrative labeling error only; the quirk's actual gating condition correctly uses the
post-swap `phy_port` value, not `cfg->port`, so this didn't affect the code — `cfg.port=1`
→ swap → `phy_port=0`, matching the guard). DMI fields (`sys_vendor`/`product_name`) both
confirmed matching live. So the quirk should have fired, and almost certainly did.

**Result: byte-for-byte identical CSI2 error signature** (`Single/Multiple packet header
error`, `Payload CRC error`, `Frame sync error`, `DPHY recoverable/fatal synchronization
error`, `FIFO overflow`) — no observable change at all from using the corrected register
values versus upstream's generic ones.

**Confirmed directly, not just inferred, 2026-07-16**: read the live PHY0 register block
straight off real hardware from the Linux side, via `mmap()` on
`/sys/bus/pci/devices/0000:00:05.0/resource0` (BAR0+0x10000, same 0x1960-byte region;
`scripts/dump-phy0-live.py`) while a stream was deliberately held open in the background
(`cam --capture=100000`, since the region is power-gated/unmapped except while actively
streaming — confirmed empirically: a dump taken between streams read all `0xFFFFFFFF`,
same as the Windows agent's own "before any camera use" baseline). **All 50 of the
registers in `x4_port0_config_regs[]`'s address range matched our intended
`xps9315_2in1_x4_port0_config_regs[]` values exactly, byte-for-byte** — proving the write
landed precisely as coded, not just "should have fired." Linux's real, live PHY0 state
while streaming is now provably identical to Windows's genuinely-working state for this
entire register block, and the stream still corrupts identically. This rules out the
self-clearing-bit caveat too (a wrong self-clearing guess would very likely have produced
*different* live values than what we told it to write, not an exact match).

**This is now a clean, direct, high-confidence negative result, not an inference**: this
specific register block was never the actual cause of the physical-layer corruption. The
quirk is left in place (harmless, DMI-gated, and now proven to make Linux's PHY config
byte-identical to Windows's working config for this block) but should not be considered a
fix. Don't re-attempt "correct the PHY config table" as a hypothesis without genuinely
new evidence — this specific avenue has been tried, verified byte-for-byte, and ruled out.

**Correction, 2026-07-20**: re-examined *why* the original PHY config table looked wrong
in the first place, using `hi556` (the front camera, provably working, never touched by
any fix) as a control. Extracted `hi556`'s own calibration table
(`x2_port3_config_regs[]`, same PHY0 memory region, different lane-group offset —
`hi556` and `s5k3j1` share physical PHY0, just different port slots) from the *same*
2026-07-16 Windows capture and diffed it against its static Linux values the same way.
**8-9 of 10 fields differ, in the same "top byte differs, rest matches" pattern** as
`s5k3j1`'s table showed before the fix. Since `hi556` works perfectly despite this same
degree of "deviation," the deviation itself was never diagnostic of anything broken —
it's normal per-die calibration/trim data that legitimately differs from Intel's generic
reference constants for *every* sensor on this board, not something specific to
`s5k3j1`. Friday's fix wasn't wrong to attempt, but the premise ("this table looks wrong
because it doesn't match the static reference") doesn't actually hold up — a good
illustration of why comparing live values against a working system doesn't help unless
you know *which specific bytes* are meant to match. Worth remembering before treating any
future "doesn't match the static table" finding as inherently suspicious.

**Where this leaves the investigation**: settle-time, MCLK, receiver D-PHY timing
formula, PHY port assignment, and PHY per-lane config-table values have all now been
checked and ruled out or shown not to help. The remaining physical-layer corruption is
real but its cause is not yet identified.

## 2026-07-17: PDAF vblank ruled out; dvdd/dovdd rail mapping fixed (untested)

**`pdaf_trial` re-tested under the current (post-fixes) system state — negative.**
Every capture test the previous night ran with the default `pdaf_trial=0`, which per
`s5k3j1_default_vblank()` uses a taller, PDAF-padded vblank (`vts=3420`) rather than the
pristine import's stock timing (`vts=2856`) — a variable nobody had isolated yet. Flipped
`pdaf_trial=1` live via the writable `0644` module param (no reboot needed — confirmed
via `/sys/module/s5k3j1/parameters/pdaf_trial`) and re-ran the capture: `streaming:
3976x2736 vts=2856` confirms the stock timing took effect, but the exact same CSI2 error
signature reproduced. Ruled out as a contributing factor.

That said, this dead end usefully reframed the investigation: `mode_3976x2736_regs[]`
and the other core register tables came from Intel's real validated `ipu6-drivers`
import (`3cdeb08`) unmodified — meaning they almost certainly work on whatever reference
hardware Intel validated them against. The actual gap is therefore something specific to
*this board* that the reference hardware didn't need, layered on top of the pristine
import — the same category as the `ANA` rail bug, not a defect in the driver's core
logic. That's the right frame for anything still worth investigating here.

**Found a second instance of the same bug pattern.** `tps68470_board_data.c`'s reset/
powerdown GPIO mapping for this board is Surface Go's (`gpio.9`/`gpio.7`), not Dell
7212's (`gpio.3`/`gpio.4`, which the code comment says doesn't even let the sensor
probe) — meaning this board's real PMIC wiring is a Surface Go derivative, not a Dell
7212 one. But the regulator rail mapping (the same "Trial C" commit that caused the
`ANA` bug) still used Dell 7212's `AUX1`/`AUX2` for `dvdd`/`dovdd`, not Surface Go's
canonical `CORE`/`VSIO`. **Fixed**: `dvdd` moved to `CORE`, `dovdd` moved to `VSIO`,
matching Surface Go exactly (see `drivers/int3472-tps68470`'s git log, commit
`4b30044` — which also retroactively commits the `avdd`→`ANA` fix from the prior
session, never actually committed at the time). `CORE`=1.2000V vs the previously-used
`AUX1`=1.2132V is a small but real voltage difference; `VSIO` and `AUX2` were already
voltage-identical at 1.8006V, so if this matters it's about the physical pin/trace, not
the voltage — same category of risk as the `ANA` bug, where voltage alone didn't
guarantee the right physical rail.

**Tested on real hardware, 2026-07-17 — negative result.** Confirmed the reassignment
landed correctly, directly (not just inferred): `/sys/bus/i2c/devices/i2c-INT346D:00/`'s
`supplier:regulator:regulator.N` links now show `regulator.2` (`CORE`), `regulator.3`
(`ANA`), `regulator.6` (`VSIO`) — exactly the intended consumers, no longer `AUX1`/`AUX2`.
Re-ran the capture test: **byte-for-byte identical CSI2 error signature** (same error
types, confirmed all-zero pixel data too). This rail reassignment doesn't explain the
corruption either, despite the well-motivated reasoning (Surface Go lineage, evidenced
independently by the GPIO mapping) behind trying it. Left in place — it's still a more
principled mapping than the Dell-7212 remnant it replaced, just not a fix for this bug.

**Running tally of what's now been tested and ruled out for the physical-layer
corruption**: settle-time, MCLK, D-PHY receiver timing formula, PHY port/cluster
assignment, PHY per-lane config-table values (byte-for-byte matched to Windows),
PDAF-related vblank/VTS timing, and now the `dvdd`/`dovdd` rail mapping. Two real,
confirmed board-wiring bugs were found and fixed along the way (`avdd`→`ANA`,
`dvdd`/`dovdd`→`CORE`/`VSIO`), which is genuine, durable progress independent of whether
they resolve this specific symptom — but the corruption itself has survived every
hypothesis tested so far. Also confirmed via direct comparison against both mainline
Linux and the pending Ubuntu `7.0.0-28.28` kernel (2026-07-17): no relevant upstream fix
exists yet for any of the files involved (`ipu6-isys-mcd-phy.c`, `ipu6-isys-csi2.c`,
`ipu6-isys.c`, `s5k3j1.c`, the int3472/tps68470 platform driver) — this isn't a case of
missing a known fix, the remaining cause is genuinely unidentified anywhere.

Given how much register-level ground has been covered without success on the CSI2/PHY
side specifically, if this rail fix doesn't help either, further progress there likely
needs genuine IPU6/MCD-PHY hardware documentation (not available) or true external
instrumentation on the MIPI lines — but this rail fix is a fresh, well-motivated,
not-yet-exhausted lead on a different subsystem (power, not PHY config) and worth
testing before concluding that.

**Kernel upgraded to 7.0.0-28-generic** (confirmed neutral for this bug beforehand — see
above). Custom `.ko`s subsequently **removed entirely from `updates/`** by the user
("no point having non-working custom modules loaded") — current state as of this
writing is **stock modules only**, rear camera non-functional, VCM/autofocus regressed
back to non-working, `avdd`/`dvdd`/`dovdd` rail fixes not in effect. Rebuilding via
`install-custom-modules.sh` restores all of it (already confirmed working against
7.0.0-28-generic once, before removal).

## 2026-07-17, continued: IPU6 ISP firmware may genuinely differ from Windows

Prompted by a question about whether the IPU6 firmware itself might differ between
Windows and Linux (as opposed to driver-side register configuration). Checked directly,
no live capture needed — both firmware images were already available locally.

**Exact provenance of the Windows-side firmware, for the record**: Dell's real,
Windows-signed IPU6 firmware came from
`reference/windows-driver-artifacts/dell-drivers/Intel-IR-Camera-Driver_CCKMF_WIN64_63.22000.16989.1_A03_01/0/Drivers/Drivers/cpd_component_signed.bin`
— the `Intel-IR-Camera-Driver_CCKMF_WIN64_63.22000.16989.1_A03_01` package, a Dell
driver download (`CCKMF` = Dell's driver ID, `A03_01` = Dell's release revision — the
standard naming Dell's own support-site downloads use), collected into this project's
`reference/` tree during an earlier session (folder dated 2026-05-11, well before
tonight). **Despite the package name, this is not IR-camera-specific firmware** — Dell's
"IR Camera Driver" download bundles the *shared* core IPU6 ISP firmware used by every
camera on the platform (front, rear, and IR alike; there's only one IPU6 ISP and one
firmware image per platform, not one per camera), plus three platform-variant copies
(`cpd_component_signed.bin` unsuffixed, `_adln`, `_rpl` — all three confirmed the exact
same size, 462848 bytes, all tagged `ipu6v5_IPU`; the unsuffixed one is the one actually
used here and matches this exact chip's `hardware version 5`). The Linux-side file being
compared against is this system's own live
`/lib/firmware/intel/ipu/ipu6ep_fw.bin.zst`, from the `linux-firmware-intel-graphics`
package.

Both are Intel's `$CPD` firmware-container format, structurally identical (same 3-entry
directory: `IUNM.man`/`iunit.met`/`iunit`, same entry offsets, both tagged `ipu6v5_IPU`
matching this exact chip's `hardware version 5`). The `iunit` firmware blob itself splits
into 7 sub-components, each with an embedded SHA-384 hash in the CPD metadata (parsed
directly per `struct ipu6_cpd_metadata_cmpnt` in `ipu6-cpd.h`) — **5 of 7 are
byte-identical (hash match) between the Windows and Linux firmware. The 2 largest
differ**: one is the same size (237568 bytes) with a different hash; the other differs
in size by exactly 4096 bytes (180224 in Windows vs. 184320 in Linux) and shares a
nonzero code entry point (`0xd3f`) in both, meaning it's real executable microcode, not
just a data table. IPU6 firmware conventionally splits into PSYS (processing) and ISYS
(imaging/capture — the exact CSI2/D-PHY receive subsystem this whole investigation has
been chasing) server images; if the differing 2 are those, this reframes the entire
session — the corruption could be a genuine ISP-firmware-version mismatch, not any
driver-side register/timing/config bug, which would explain why every hypothesis tested
against driver-side configuration (settle-time, MCLK, D-PHY timing, PHY port, PHY
config-table, PDAF timing, rail mapping) came back negative despite reasonable evidence
for each.

Note: an attempt to also directly extract/compare `fw_pkg_date`/`target_platform_type`
build-identifier fields from the manifest (`IUNM.man`) did not parse cleanly (wrong
offset assumption for where `struct ipu6_cpd_module_data_hdr` actually begins within
that entry — there's an additional CSE manifest/signature header before it that wasn't
fully reverse-engineered) — don't trust any specific date/version numbers from this
session for that field. The component-level SHA-384 hash comparison above is solid and
didn't depend on that parse.

**Untested candidate fix, staged and ready**: Dell's firmware file was compressed to
match Linux's format (`zstd -19`, round-trip verified byte-for-byte against the original)
and is ready at
`/tmp/claude-1000/-home-mward-work-camera-mipi/2c538e8b-e4df-4038-b7e1-ba728e438065/scratchpad/ipu6ep_fw.bin.zst`
(note: scratchpad, not durable — regenerate from
`reference/windows-driver-artifacts/dell-drivers/Intel-IR-Camera-Driver_CCKMF_WIN64_63.22000.16989.1_A03_01/0/Drivers/Drivers/cpd_component_signed.bin`
via `zstd -19` if this has been cleaned up by a future session). Confirmed safe to try:
software-side validation in `ipu6_cpd_validate_cpd_file()` is purely structural (magic
marker, manifest/metadata size bounds), not a content fingerprint check, so it will pass;
real authentication happens in CSE hardware via cryptographic signature against Intel's
production keys, and since Dell's firmware is legitimately Intel-signed (not self-signed)
it should authenticate the same way — worst case on mismatch is a clean CSE
authentication failure (IPU6 probe fails, cameras stop working, no hardware risk), fully
reversible by restoring the original file (back it up first). Needs the custom module
stack reinstalled alongside it to reach a real streaming attempt (stock modules likely
don't even have board data for this exact machine).

**Tested on real hardware, 2026-07-17 — negative result, but confirms the swap itself
worked correctly.** Rebooted with Dell's firmware installed + custom modules
reinstalled. Confirmed directly, not assumed: decompressing the installed
`ipu6ep_fw.bin.zst` reproduces Dell's exact SHA-256
(`836f1cde0a21dd9ff106ed525c8b19e5fd6b7ebfea05eb68e38013316b496e21`), and dmesg shows
`Sending BOOT_LOAD to CSE` → `Sending AUTHENTICATE_RUN to CSE` → **`CSE authenticate_run
done`** — Dell's Windows-signed firmware genuinely passed CSE hardware authentication on
this exact silicon, confirming it's legitimately compatible (not just structurally
similar). `ANA`/`CORE`/`VSIO` rail fixes confirmed still in effect. Re-ran the capture
test: **identical CSI2 error signature** (`747 callbacks suppressed`, full same error
list — packet header, CRC, frame/line sync, DPHY recoverable/fatal, FIFO overflow).

So the ISP firmware content difference found earlier, while real (confirmed via SHA-384
component hashes) and worth having verified, is **not the cause of the corruption** —
using Dell's exact Windows-signed firmware changes nothing. This firmware swap is
reverted mentally as a "not the fix" but can stay installed (it's Dell's own real
firmware, legitimately signed, no reason to prefer the generic upstream one over it) or
be restored from the `.orig-backup` if preferred — doesn't matter either way. This also
means the 2 differing firmware sub-components most likely aren't PSYS/ISYS server images
after all (or if they are, the difference between them isn't what's causing this
specific symptom) — don't re-chase the firmware-version theory without new evidence.

**Also drafted**: `docs/WINDOWS-AGENT-BRIEF-4-i2c-mode-regs.md` — a live I2C capture
(ETW-based SPB/I2C tracing, primary approach; WinDbg or targeted RWEverything spot-reads
as fallbacks) to see what Windows actually writes to the sensor's I2C address during
real streaming, to compare against `mode_3976x2736_regs[]` — since static analysis of
`s5k3j1sx04.sys` already conclusively showed this table isn't in that binary in any
form. The brief explicitly flags that a capture showing little/no I2C traffic to the
`0x90c8`-range addresses would itself be an important result, consistent with the
firmware finding above (mode config might live in ISP firmware, not host I2C writes at
all).

## 2026-07-17, continued yet again: live I2C capture — register content conclusively confirmed correct

`windows-agent-findings-i2c-mode-regs-2026-07-17.md` came back — an exceptionally clean
capture. **The ETW approach (`Intel-iaLPSS2-I2C` + `Microsoft-Windows-SPB-ClassExtension`
providers) worked completely on the first attempt**: 620 real I2C transactions to the
sensor (`0x10`) captured across one full stream-start-through-live-preview window,
correlated by Activity ID and timestamp into a phase-by-phase sequence (unlock handshake
→ microcode upload → calibration tables → mode-select → mode readback/verification →
live AE/AGC convergence loop). Full raw data (`.etl`, decoded CSV, correlation script)
left in `docs/` alongside the findings doc.

**Directly answers the open question from the very first static-analysis pass**:
Windows *does* send the exact `0x90C8`–`0x9256` microcode range over real I2C, live,
during every stream start — confirmed, not ISP-firmware-substituted. This still doesn't
explain why static analysis of `s5k3j1sx04.sys` found zero byte matches for this content
(remains an open, lower-priority curiosity — possibilities noted in the findings doc:
compressed/obfuscated in the binary, sourced from a separate resource file, or assembled
programmatically) — but it settles the actual question this brief was chasing.

**Did the byte-for-byte comparison the findings doc suggested as the immediate next
step**: parsed all 13 Phase B transactions (200 register values, `0x90c8`–`0x9256`) plus
the 11-transaction Phase A unlock/bank-select handshake (matching
`mipi_data_rate_1024mbps[]` + the opening of `mode_3976x2736_regs[]`) against Linux's
actual table values at the same addresses. **Zero mismatches across all 211 checked
register values.** Our microcode blob and unlock sequence are provably, exactly correct
— not an inference from "it's Intel's validated import," but a direct, live,
byte-for-byte confirmation against genuinely-working Windows traffic.

**This closes off register *content* as a hypothesis space entirely, with real
confidence, not just "probably fine."** Combined with everything else already ruled
out (settle-time, MCLK, D-PHY timing formula, PHY port assignment, PHY per-lane
config-table values, PDAF timing, rail mapping, and the ISP firmware content difference),
essentially every checkable *static configuration* variable has now been confirmed
correct or shown not to matter. What's left, genuinely untested: **the timing/pacing of
these I2C transactions** — the ETW capture has real timestamps for every transaction
(available in `i2c_reconstructed.csv`/`i2c_sensor_0x10_full.csv`, left in `docs/`) that
haven't been analyzed yet, and inter-transaction delays are exactly the kind of thing
register-content comparison can't reveal.

**Correction**: the user pushed back on I2C pacing as a likely mechanism (I2C is
host-clocked with per-byte ACK/NACK; if writes arrived too fast the device would NACK,
and we've seen no such errors) — fair, and a better-justified critique than what I'd
proposed. That prompted a look at data already sitting in the same capture that had been
dismissed as out of scope: 58 I2C transactions to address `0x4D`, which the Windows
agent's own report guessed was "probably the TPS68470 PMIC/companion chip" but didn't
analyze. It was exactly the right redirect.

## 2026-07-17, continued once more: real voltage-value bugs found via the 0x4D capture

Decoded the `0x4D` transactions directly from `docs/i2c_reconstructed.csv` (already on
disk, no new Windows session needed) against mainline's real TPS68470 register map
(`include/linux/mfd/tps68470.h`, `drivers/regulator/tps68470-regulator.c` in
`~/work/git-ubuntu/resolute`) — `0x4D` is confirmed as the TPS68470 PMIC, and the
transactions include direct writes to each rail's voltage-trim DAC register
(`VDVAL`/`VAVAL`/`VCMVAL`/`VIOVAL`/`VSIOVAL`) during a real stream-start. Decoded each
raw selector value through the driver's own `linear_range` voltage formula
(`core_ranges`: 900000µV base, 25000µV/step; `ldo_ranges`: 875000µV base, 17800µV/step)
and compared against what this board data has been configuring:

| Rail | Register | Windows raw sel | Windows actual µV | Our configured µV | Match? |
|---|---|---|---|---|---|
| CORE | VDVAL (0x42) | `0x06` | 1,050,000 | 1,200,000 | **MISMATCH** |
| ANA | VAVAL (0x41) | `0x75` | 2,957,600 | 2,815,200 | **MISMATCH** |
| VCM | VCMVAL (0x3C) | `0x6D` | 2,815,200 | 2,815,200 | exact match |
| VSIO | VSIOVAL (0x40) | `0x34` | 1,800,600 | 1,800,600 | exact match |
| VIO | VIOVAL (0x3F) | `0x34` | 1,800,600 | 1,800,600 | exact match |

VCM/VSIO/VIO all matching exactly validates both the capture and the decode formula —
this isn't a parsing artifact. **CORE and ANA are both real, previously-undetected
voltage bugs**: `CORE` (the sensor's digital-core logic supply) has been configured
150mV too high (1.2V vs. the real 1.05V), and `ANA` (the analog front-end) 142mV too low
(2.8152V vs. the real 2.9576V). Both prior values were generic "nominal" assumptions —
1.2V/2.8V are common textbook figures for these rail types — carried forward from the
very first bring-up, never before checked against real hardware. This differs in kind
from the earlier `ANA`/`dvdd`/`dovdd` fixes (which were about *which physical pin*); this
is about the *voltage value itself* on rails that were otherwise already correctly wired.

This is a materially better-fitting candidate than anything checked previously: feeding
a sensor's digital core logic and analog front-end at the wrong voltage is a plausible,
specific mechanism for exactly the observed symptom (frame sync achieves, MIPI packet
content corrupts) — marginal internal clock/PLL generation or analog-domain signal
integrity from an off-spec supply, not a binary on/off failure.

**Fixed**: `xps9315_2in1_tps68470_core_reg_init_data` (1050000) and
`xps9315_2in1_tps68470_ana_reg_init_data` (2957600) in `tps68470_board_data.c`, commit
`ee32b0c`.

**Tested on real hardware, 2026-07-17 — negative result.** Confirmed directly (not
assumed): fresh boot, `/sys/class/regulator/regulator.2/microvolts` (`CORE`) reads
`1050000`, `regulator.3` (`ANA`) reads `2957600` — the corrected voltages are genuinely
in effect, not just configured in source. Re-ran the capture test: **identical CSI2
error signature** (same full list — packet header, CRC, frame/line sync, DPHY
recoverable, FIFO overflow). Despite being the most precisely-evidenced fix of the whole
investigation (live-captured, cross-validated against 3 other rails matching exactly),
correcting the CORE/ANA voltages doesn't change the corruption at all.

**Where this leaves things**: every static configuration variable checkable from either
side of this investigation has now been verified correct-and-matching-Windows, or shown
not to matter, with real evidence rather than inference — settle-time, MCLK, D-PHY
timing formula (confirmed dead/unused code for this PHY backend), PHY port/cluster
assignment, PHY per-lane calibration values (byte-for-byte match), PDAF vblank timing,
regulator rail *mapping* (which physical pin), regulator *voltage values* (which
voltage), ISP firmware content, and now sensor I2C register content (byte-for-byte
match, 211 values across the full microcode blob and unlock handshake). Two real,
confirmed-necessary board-wiring/voltage bugs got fixed along the way and should stay
fixed regardless of this specific symptom. The corruption itself has survived
everything. What's left unexamined: true external instrumentation (protocol/logic
analyzer on the physical MIPI lines) or the CSE-authenticated ISP firmware's own
internal behavior (opaque, encrypted, not statically analyzable) — both categories this
project has already concluded aren't accessible with the tools at hand.

## 2026-07-17, still continuing: two more checks against the same capture — one closed, one fixed

Kept mining the same `i2c_reconstructed.csv`/`i2c_sensor_0x10_full.csv` data rather than
starting a new Windows session — both of these were answerable from data already on
disk.

**Clock generation (`clk-tps68470.c`) — checked, confirmed correct, ruled out.** The
TPS68470 also generates the sensor's MCLK via an internal PLL, and its enable/config
registers (`PLLCTL` @ 0x0D, `CLKCFG1` @ 0x0F) appear in the same `0x4D` capture window.
Computed what Linux's own driver produces for these two registers directly from source:
`CLKCFG1 = (0x02<<0)|(0x02<<2) = 0x0A` (exact match to the capture); `PLLCTL`'s
probe-time value `(0x05<<4)|(0x01<<7) = 0xD0` then `prepare()` setting bit 0 →
`0xD1` (exact match to the capture's `0xD0`→`0xD1` sequence). Both byte-for-byte
correct. (The actual PLL divider *ratios* — `XTALDIV`/`PLLDIV`/`POSTDIV`/etc. — aren't in
this capture at all, written once at probe time before the captured window started; the
values Linux uses, `clk_freqs[0] = {19200000, 170, 32, 1, 2, 3}`, are Intel's own
reference table for exactly 19.2MHz, which is independently already confirmed as the
exact required frequency.) Clock generation is not the cause.

**GPIO reset/powerdown release order — real discrepancy found, fixed.**
`gpio-tps68470.c` reveals GPIO offsets 7/8/9 (the "logic outputs") are all bits of one
shared register, `SGPO` (0x22) — not individually addressed. This board's mapping is
reset=GPIO9 (bit 2), powerdown=GPIO7 (bit 0), both active-low. The captured `SGPO`
sequence during a real stream-start: `0x00 → 0x00 → 0x04 → 0x05` — decodes to both held,
both held, **reset released first** (bit 2 high, bit 0 still low), **then powerdown
released** (both high). `s5k3j1_power_on()` released in the opposite order (powerdown
first, then reset) since the very first bring-up commit. **Fixed**: swapped to
reset-then-powerdown in `power_on()` (matching the direct capture evidence);
`power_off()`'s assert order also swapped for symmetry (powerdown-then-reset), though
that direction is an assumption, not independently verified — the trace only covered
stream-start, not shutdown. Commit `23bc618`. Builds clean.

**Tested on real hardware, 2026-07-17 — negative result.** Fresh boot, custom modules
confirmed loaded (matching `srcversion`). Re-ran the capture test: **identical CSI2
error signature**, same as every prior attempt. The GPIO release-order fix — despite
being a real, independently-verified discrepancy against genuinely-working hardware, not
a guess — doesn't change the corruption either. Left in place (it's still the
Windows-verified-correct order, no reason to revert it).

**This closes out essentially every lead this session's methodology can produce.**
Between this and the CORE/ANA voltage fix, the *entire* `0x4D` (TPS68470) capture has now
been mined: voltage-trim registers (2 real bugs, fixed), clock/PLL enable sequence
(confirmed correct), and GPIO release order (1 real bug, fixed) all checked against
actual Windows behavior. Combined with the sensor's own I2C content (byte-for-byte
match) and the earlier PHY/firmware/timing work, there is no remaining static
configuration difference between this Linux setup and genuinely-working Windows that
hasn't been checked, found correct, or fixed. Two real, confirmed, durable bugs (rail
voltages/mapping, GPIO order) came out of tonight's work and are worth keeping regardless
of this specific symptom. The corruption itself remains unexplained by anything
discoverable through configuration comparison. Next steps, if this continues, genuinely
need something this session's tools can't do: a hardware protocol/logic analyzer on the
physical MIPI lines, or reverse-engineering the CSE-authenticated ISP firmware's runtime
behavior (opaque/encrypted, not statically inspectable). The one piece of captured data
not yet touched is the `0x72` (VCM) transaction set in the same capture — untried, lower
priority (the VCM's own function, focus control, is confirmed working correctly already;
unlikely to bear on the rear-sensor CSI2 corruption specifically) but available if
someone wants to check it.

## 2026-07-17, fresh-eyes review: ideas for next session (Monday)

Asked a separate Opus 4.8 agent to review this entire file cold, specifically to find
angles the "diff live configuration against Windows" methodology might structurally be
blind to. Its framing of the symptom is worth leading with: real `sof_event`s firing
repeatedly, with every packet inside each frame corrupted (header/CRC/DPHY-sync errors,
FIFO overflow), at ~4Gbps aggregate (1024Mbps × 4 lanes) is the classic signature of a
**bit/lane-level physical problem** — exactly the class that comparing register *values*
against a working system can't see, no matter how exhaustively it's done. That's a fair
critique of the whole night's approach, not just a new lead. Ideas, prioritized:

1. **Use the working front camera (hi556) as a live differential baseline instead of
   Windows.** Every comparison this session was Linux-vs-Windows. But hi556 streams
   correctly through the *same* IPU6/MCD-PHY receiver, same kernel, same silicon, right
   now. Dump the live CSI2/PHY receiver register block while hi556 streams (reuse
   `scripts/dump-phy0-live.py`, adapted to hi556's port/PHY instance) and diff it against
   s5k3j1's live block during its own (failed) stream. This isolates receiver-side
   differences (clock mode, VC/DT filtering, deskew, FIFO/credit config) against a
   known-good reference on identical hardware — no Windows round-trip needed, cheapest
   and most direct thing not yet tried.
2. **Continuous vs. non-continuous MIPI clock mode.** `s5k3j1.c` never parses/sets
   `V4L2_MBUS_CSI2_NONCONTINUOUS_CLOCK` on the endpoint. If the sensor gates its HS clock
   between packets but the receiver expects a continuous clock (or vice versa), that
   produces exactly repeated SOT/DPHY-sync errors while SOF still survives. Cheap A/B:
   force the flag in `ipu-bridge.c`'s endpoint config and retest.
3. **Lane deskew calibration Linux may be skipping.** Ties to the earlier PHY-trim
   finding of 6 bytes that change between consecutive Windows stream-starts (flagged at
   the time as "per-attempt calibration/retry state," never followed up). Linux does one
   static `writel()` and never runs an adaptive per-lane deskew; at 1024Mbps, inter-lane
   skew tolerance is tight, and un-deskewed lanes produce exactly this per-packet
   corruption pattern while clock/SOF still recover. Worth mapping those 6 bytes'
   addresses and checking whether they gate a calibration handshake the driver omits.
4. **FIFO overflow as a real bandwidth/clock-throttling signal, not just a side-effect.**
   Check the IPU6 ISYS operating frequency/power state during capture (buttress
   registers, P-state) — if ISYS is running at a reduced clock, it may physically be
   unable to drain a 4Gbps stream regardless of anything else being correct. Also verify
   ISYS video-node `bytesperline`/`sizeimage` actually match RAW10-packed 3976 width — a
   stride/format mismatch alone can overflow the receive FIFO.
5. **Physical lane order/polarity mapping.** `ipu-bridge.c` hardcodes
   `data_lanes[i] = i+1`. If this board's PCB cross-routes lanes or inverts polarity on
   some pairs, clock recovers and SOF latches (header rides the correctly-mapped path)
   while payload CRC fails on every packet — invisible to every capture done so far.
   Cross-check via #1's hi556 diff, and check for a lane-remap field in the MCD-PHY
   block or the SSDB/`_DSD` lane-mapping property.
6. **Confirm SOF is a genuine physical-layer signal, not a firmware-synthesized
   heuristic.** Completion is CSE-firmware-driven; if the underlying frame-start short
   packets are *also* corrupted and SOF is being synthesized anyway, the problem is
   unambiguously pure-PHY (points at #2/#3/#5), ruling out anything data-type-specific.
7. **VC/DT or embedded-data-line mismatch even with `pdaf_trial=1`.** The sensor's own
   firmware may still emit an embedded-data/PDAF line on a second virtual channel/data
   type that ISYS isn't configured to expect, producing header errors on exactly those
   lines regardless of the driver-side PDAF flag.
8. **Two cheap ruleouts**: grep dmesg for `DMAR`/IOMMU faults during the capture window
   (a silent DMA fault would produce all-zero frames regardless of PHY correctness,
   independent of everything else checked); and get a future Windows session to read back
   the sensor's actual *PLL divider* registers (only the enable/control bits were ever
   captured — the divider ratios that set the real bit rate were never directly
   confirmed, only assumed correct from the ACPI-declared 512MHz link frequency).

Start with #1 and #2 — both same-session, Linux-only, no reboot required for #1's dump
(hi556 is already working and streamable), and directly target the receiver-side blind
spot the rest of this file's methodology couldn't see.

## 2026-07-20 (Monday): #1 done — closes PHY table again via a new method; #2 hit a dead address

**#1 (hi556 differential dump) — done, real result, but a negative one.** Captured live
PHY0 dumps on this Linux system (not Windows) while each camera was genuinely,
separately streaming: `reference/linux-phy0-live.bin` (rear, still broken) and
`reference/linux-phy0-live-hi556.bin` (front, confirmed genuinely working — real 30fps,
real ~20MB frames, not the zero-byte corruption). Comparing `s5k3j1`'s own lane-group
region (`0x280`-`0xb74`) and `hi556`'s own lane-group region (`0x1680`-`0x194c`) between
the two captures: only 3-4 bytes differ in *each* region, matching the same small
"per-attempt calibration/retry state" already characterized on 2026-07-16 (confirmed
here as unrelated to which port is actually active — it changes in *both* regions
regardless of which camera streams). `common_init` region (`0x0000`-`0x0060`):
byte-identical. **This independently re-confirms, via a completely different method
(Linux-side differential against a genuinely working camera, not another Windows
comparison), that the PHY calibration table is not the cause** — doubly ruled out now.

**Correction to the 2026-07-16 PHY-table finding, prompted by this**: extracted `hi556`'s
own calibration table from the original Windows capture and found it *also* deviates
from its static Linux reference in the same "top byte differs, rest matches" pattern
`s5k3j1`'s table showed (8-9 of 10 fields, similar degree though not byte-identical
positions). Since `hi556` works perfectly despite this, the deviation itself was never
diagnostic — it's normal per-die trim data that differs from Intel's generic reference
constants for *every* sensor on this board, not something specific to `s5k3j1`. The
2026-07-16 fix wasn't wrong to attempt, but its premise doesn't hold up under this
control. Worth remembering before treating any future "doesn't match the static table"
finding as inherently suspicious.

**#2 (clock-mode flag) — couldn't be tested as originally framed.**
`V4L2_MBUS_CSI2_NONCONTINUOUS_CLOCK` doesn't appear anywhere in this driver stack,
mainline or ours — genuinely unimplemented, not just unset, so there's no flag to flip.

**Attempted a related, more direct check — hit a dead address, not a real result.**
Tried to compare the actual CSI2 receiver's per-port control registers (`PPI2CSI`/`FE`
front-end enable/mode/mux registers, `CSI_REG_PORT_BASE(id) = 0x220000 + id*0x1000` per
`ipu6-platform-isys-csi2-reg.h`) between `s5k3j1` (port 1) and `hi556` (port 3) while
each streamed — this is genuine CSI2 receiver *configuration*, distinct from the PHY0
calibration table, and would have directly informed #2's underlying question even
without a software flag to toggle. **Result: all `0xFFFFFFFF` for both ports, identical
— i.e. unmapped, not a real register read.** Traced `isys_base` computation
(`isp->base + isys_ipdata.hw_variant.offset`, with `IPU6_UNIFIED_OFFSET = 0`) and
confirmed the base address math *should* put `CSI_REG_BASE` at `BAR0+0x220000` — but
since both ports read identically all-FF, this specific offset is evidently not backed
on this exact silicon (IPU6EP/hardware-version-5). It may be correct for a different
`ipu_ver` variant this same header serves. **Not resolved — needs someone to find the
actual, correct base address for the CSI2 receiver's per-port register block on IPU6EP
specifically** before this angle can be pursued further. Scripts left in place:
`scripts/dump-csi2-port.py <port_id> <out_path>` (run with sudo while the relevant
camera streams) — reusable once the right offset is found.

**Update, same day: the dead address above was a false alarm — resolved by reading the
registers from inside the driver instead of via userspace mmap.** Read the surrounding
code in `ipu6-isys-csi2.c` (`ipu6_isys_csi2_set_stream()`) and `ipu6.c`
(`ipu6_isys_init()`) fully:

- `isys_ipdata.hw_variant.offset` is never conditionally overridden anywhere (single
  static struct, always `IPU6_UNIFIED_OFFSET = 0`) — confirmed the base-address math was
  correct all along for every IPU6 variant, including this one.
- Found the actual access-gating mechanism: `CSI_REG_HUB_DRV_ACCESS_PORT(id)` /
  `CSI_REG_HUB_FW_ACCESS_PORT(ofs, id)` are a "hub" arbiter — the enable path writes `1`
  to both, for *every* port, right before configuring `FE_MODE`/`FE_MUX_CTRL`/
  `PPI2CSI_ENABLE`/etc., and only writes `0` (releasing that port) on disable. So during
  active streaming these should stay granted — the all-FF dumps were a timing artifact
  (Monday's userspace `dump-csi2-port.py` reads almost certainly raced a disable/retry
  window mid-corruption, not a wrong offset).
- Also settles #2 outright while in this code: `CSI_REG_CSI_FE_MODE` is
  `writel(0, ...)` — a bare literal, no flag, no DMI check, no conditional branch of any
  kind. This receiver driver has **zero plumbing** for
  `V4L2_MBUS_CSI2_NONCONTINUOUS_CLOCK` — confirmed by reading the exact write site, not
  just its absence from grep.

**Proved it empirically rather than just by code reading**: added `dev_info()` register
dumps directly in `ipu6-isys-csi2.c` right after the real `enable(true)` sequence
completes (commit `e33c57d` in `drivers/ipu6-isys`), rebuilt, installed, rebooted, and
captured a real rear-camera (port 1) stream attempt:

```
csi2-1 hub access: drv=0x1 fw=0x0
csi2-1 fe: enable=0x1 mode=0x0 mux=0x0 sync=0x3 ppi_enable=0x1 ppi_intf=0x18
```

All live, sane values — confirms the address math and settles the timing-artifact
explanation above. `mode=0x0`, `mux=0x0` (= `CSI_SENSOR_INPUT`), `sync=0x3`
(line+frame ID), `ppi_intf=0x18` (4 lanes) are all exactly what the driver source says
it should write — no surprises there.

**One real anomaly, not yet a conclusion**: the driver writes `1` to both
`DRV_ACCESS_PORT` and `FW_ACCESS_PORT`, but `FW_ACCESS_PORT` reads back `0`. Could be
normal (a status bit only firmware itself sets on actual claim, not a plain read/write
register) or could be a genuine firmware-side non-acknowledgment specific to this
silicon/FW build. **Next step: get the identical `csi2-3` (hi556, working) reading as a
control** — same trick that already debunked the PHY-table theory once. If hi556 also
reads `fw=0x0`, this is normal and closed. If hi556 reads `fw=0x1`, that's a real,
narrow, well-evidenced lead into the actual corruption.

**Control result: hi556 (port 3) also reads `fw=0x0`**, identical shape to rear in every
other field too (`mode=0x0 mux=0x0 sync=0x3`), differing only in `ppi_intf` (`0x8` vs
`0x18` — exactly the 2-lane vs 4-lane difference, expected). **Anomaly closed as normal
read-back behavior, not a bug** — same pattern as the PHY-table correction: don't treat
`fw_access_port` reading back `0` as suspicious again without new evidence. This whole
CSI2 hub-access/FE-register avenue is now fully closed, both for the original
all-`0xFFFFFFFF` dead end (explained, not a real issue) and the `fw=0x0` anomaly (normal,
matches working camera).

**Also tried mining the two existing Monday PHY0 captures directly** (`linux-phy0-live.bin`
rear vs `linux-phy0-live-hi556.bin` front) via a byte-for-byte diff rather than each
against its own static reference. Found 48 differing bytes in a clearly repeating
0x200-byte-stride pattern (~7 bytes per group, 5 groups in the 0x0000-0xc00 region, 4
more in 0x1400-0x1900). **Judged non-diagnostic**: the shape (one byte changes a lot,
rest close) matches the already-documented, already-ruled-out "6 bytes churn between
consecutive stream restarts, not exposed to the driver, doesn't gate anything" finding
from 2026-07-16 — these two captures are just many stream-cycles apart rather than two
adjacent restarts, so more accumulated churn shows up. Didn't chase this further; flagging
here so a future session doesn't re-discover the same 48 bytes and mistake them for a new
lead.

**Cheap ruleout from Opus's list, done: no DMAR/IOMMU fault.** `sudo dmesg | grep -iE
"DMAR|IOMMU"` shows `pci 0000:00:05.0: DMAR: Passthrough IOMMU for integrated Intel IPU`
— the IPU device runs in IOMMU passthrough mode, no address translation in play, and
there are zero fault messages anywhere in the boot log. Silent DMA fault as an
explanation for the corruption is ruled out cleanly. (The other half of that item —
getting a future Windows session to read the sensor's actual PLL divider registers,
never directly confirmed — is still open.)

**Format/stride half of item #4, checked and inconclusive (not a real ruleout).**
`/dev/video10` (Capture 8, fed by `Intel IPU6 CSI2 1` pad1, the rear sensor's `ENABLED`
link) negotiates `3976x2736`, `'BA10'` (unpacked 10-bit Bayer, 2 bytes/sample),
`bytesperline=8000`, `sizeimage=21896000`. `8000 = align(3976*2, 64)` — exactly correct
for the *unpacked* V4L2 output format. But this only checks the ISYS-to-userspace output
buffer stride, not the MIPI-wire-level RAW10-packed assumption the CSI2 receiver itself
uses while descrambling incoming data (that's a separate, internal ISYS configuration,
not visible via `v4l2-ctl --get-fmt-video`). Given the actual corruption is
header/CRC/DPHY-sync errors at the physical/protocol layer — before any unpacking would
even happen — a stride mismatch downstream of that wouldn't produce this symptom anyway.
Closing this specific check as clean but not meaningfully diagnostic either way; the real
question item #4 was gesturing at (wire-level packing config) remains untested.

**Clock/power-state half of item #4, tested directly — closed, identical between working
and broken.** Found the actual mechanism: `isys_buttress_ctrl.ratio =
IPU6_IS_FREQ_CTL_DEFAULT_RATIO` (`0x08`, `ipu6.c:212`) is a single fixed constant, written
once via `ipu6_buttress_power()` whenever the ISYS power domain comes up — no
per-sensor, per-resolution, or per-bandwidth scaling anywhere in this driver. Read the
live buttress registers directly (`scripts/dump-buttress.py`, `BAR0+0x34` =
`IS_FREQ_CTL`, `BAR0+0x5c` = `PWR_STATE`, always-mapped, no power-gating unlike the PHY0
block) while each camera was genuinely streaming, as a direct working/broken control
comparison:

```
[hi556] IS_FREQ_CTL=0x800f1008 (start=True ratio=0x08 qos_floor=0x10)
[hi556] PWR_STATE=0x003a113b IS_PWR_FSM=0x07 IS_PWR=0x03 (IS_RDY==0xa)
[rear]  IS_FREQ_CTL=0x800f1008 (start=True ratio=0x08 qos_floor=0x10)
[rear]  PWR_STATE=0x003a113b IS_PWR_FSM=0x07 IS_PWR=0x03 (IS_RDY==0xa)
```

**Byte-for-byte identical.** `IS_PWR=0x3` (`UP_DONE`) confirms the ISYS power domain
itself is fully up in both cases — a reduced/stuck ISYS clock is now ruled out as
directly, and by the same working-camera-control method that already closed the PHY
table and CSI2 FE/hub-access questions. (`IS_PWR_FSM=0x07`,
`STOP_CLK_CYCLES2`, in both — appears to be the FSM's normal resting value post-settle,
not a stuck-in-transition indicator, since `IS_PWR` itself already reads `UP_DONE`.)

**Where this leaves things**: every receiver-side (IPU6/ISYS/CSI2/buttress) register
we've found a way to read now matches byte-for-byte between the genuinely-working hi556
stream and the corrupted rear stream — PHY0 calibration, CSI2 FE/PPI2CSI config, hub
access grant, and now ISYS clock/power state. The remaining, most likely place for a real
difference to exist is sensor-side: `s5k3j1`'s own PLL divider ratio, which sets its
actual MIPI bit rate. Per item #8, this was never directly confirmed on Windows — only
the enable/control bits were captured; the divider values were assumed correct from the
ACPI-declared 512MHz link frequency, not read back. This is now the clearest remaining
untested thread.

**Follow-up, same day: brief 5 (PLL divider values) sent to Windows, partial result, now
handed to Ghidra.** `docs/WINDOWS-AGENT-BRIEF-5-pll-divider-regs.md` asked for the actual
`0x0136`/`0x0300`-`0x0312` values Windows writes to the sensor. Findings
(`docs/windows-agent-findings-pll-divider-2026-07-20.md`):

- **RWEverything spot-reads were not viable**: the sensor's I2C bus is an Intel LPSS
  DesignWare controller owned exclusively by the SpbCx camera stack while streaming;
  RWEverything's I2C tool only reaches the legacy PCH SMBus controller, different silicon
  entirely. Driving the LPSS controller directly would collide with the live driver
  (bus-wedge risk). Correctly not attempted.
- **ETW capture confirms the *shape* but not the *values***: `Intel-iaLPSS2-I2C` at max
  verbosity shows **619 writes + 36 reads** to the sensor during a real stream-start —
  same order of magnitude as Linux's ~577-entry table, same wire format (16-bit
  big-endian reg + value), including **14×34-byte burst writes** whose payload (448 bytes)
  closely matches Linux's ~400-byte `0x90c8` microcode upload. This also answers brief 4's
  open question: Windows *does* configure the sensor via host I2C, not ISP-firmware
  handoff — the bytes just aren't embedded literally in `s5k3j1sx04.sys` because they're
  sourced from its `.aiqb`/tuning-blob data at runtime. **But the ETW provider only exposes
  transfer descriptors (address/length/direction), never the payload bytes** — no provider
  tried carries the actual values.
- Recommended follow-up: a WinDbg breakpoint on the sensor driver's own write-register
  function, needing the RVA found via offline Ghidra RE first (`docs/RE-TARGET-s5k3j1-write-reg-for-pll-capture.md`).

**Ghidra RE done, same day** (`s5k3j1sx04.sys`, SHA256
`5bf53228c5b2067d50aaee87b4f3eb9565e5b86ea754f2e280a19259478c519a` — confirmed matching the
copy named in the RE-TARGET doc; analyzed headless via `pyghidra`, scripts in
`/home/mward/work/ghidra/*.py`, full output in
`reference/windows-driver-artifacts/xps-rear-win-20260713/s5k3j1_*.log`). Findings written
to `docs/ghidra-findings-s5k3j1-write-reg-rva.md`:

- All four landmark RVAs from the RE-TARGET doc (`DispatchDeviceControl` etc.) landed
  exactly where expected, confirming the rebasing assumption holds for this exact file.
- Traced the actual call chain: `FUN_140005028` is the Windows equivalent of Linux's
  `mode_3976x2736_regs[]` player — walks a table of entries until a `0xffff` sentinel,
  merges consecutive same-stride registers into bursts capped at **34 bytes** (matching
  the ETW capture's observed max burst size exactly — a solid cross-check), assembles
  `[addr bytes][value bytes]` (both MSB-first, matching Linux's own wire format) into a
  stack buffer, then hands `(pointer, length)` down through a thin wrapper into
  **`FUN_14000d1c8` @ RVA `0xD1C8`** — the one function to put a breakpoint on. At its
  entry, `rdx` already holds the fully-assembled buffer and `r8d` the length, so a single
  auto-continuing breakpoint there (`bp base+0xD1C8 "db @rdx L@r8d; g"`) captures every
  sensor register write uniformly, address and value together, single or burst. (Also
  confirmed `FUN_14000cf48`/`FUN_14000cb0c` are the unrelated VCM read/write primitives —
  their callers cluster with the `'%s %s Failed to write vcm reg'` strings, not the sensor
  mode-config path; don't target those.)
- Next step is on the Windows side: set that breakpoint, start a rear-camera stream, and
  filter the captured buffers for ones starting with `03 00`/`03 04`/`03 06`/`03 0C`/
  `03 0E`/`03 10`/`03 12`/`01 36` (big-endian) to finally fill in the Windows column of the
  PLL comparison table.

**Update, same day: breakpoint plan blocked, pivoted to reading the table statically —
new Ghidra pass, real progress but PLL regs still not located.** The WTG machine's kernel
debugging is configured `debugtype=Local`, and **local KD is read-only — it cannot set
breakpoints**, only read memory (network KD to a second machine would be needed for that,
not available). So the `0xD1C8` breakpoint plan from the previous note is off the table.
Pivoted (`docs/RE-TARGET-2-s5k3j1-mode-table-pointer.md`) to finding and reading the
mode-config *table itself* out of memory instead of catching writes in the act. Findings
in `docs/ghidra-findings-s5k3j1-mode-table-pointer.md`:

- Fully traced the table-pointer chain from `FUN_140005028` (the table player) back
  through a device-extension array (`ctx+0x1f38`, populated once at driver init) to what
  turned out to be a **fully static, image-relative table** — not a runtime blob pointer
  as brief 4 assumed. Three board-variant tables exist (RVA `0x25410`/`0x21630`/`0x23260`);
  decoded variant 0's first mode-descriptor record directly from the binary and got an
  **exact match** to Linux's own constants (width 3976, height 2736, fps 30, **VTS
  2856** — Linux's `S5K3J1_VTS_30FPS`) confirming variant 0 / RVA `0x25410` is what's
  actually active on this hardware, no live system needed to establish that.
- Decoded all 586 entries in that table and got another exact cross-check for free:
  entry `{width=2, addr=0xfcfc, value=0x4000}` appears 3 times, byte-for-byte matching
  Linux's own `{0xfcfc, 0x4000}` write in `s5k3j1.c` — strong independent confirmation the
  16-byte entry format (LE-int width @ +0, address bytes MSB-first @ +4/+5, LE-int value
  @ +8, sentinel = width field reading `0xffff`) is decoded correctly, not guessed.
- **But none of the 8 PLL/EXTCLK registers (`0x0136`, `0x0300`–`0x0312`) appear in any of
  the three per-mode tables.** Ran a full-binary byte-pattern scan (every loaded section)
  for the same entry shape at these specific addresses: **zero matches anywhere in the
  file.** So brief 4/5's "sourced from a runtime `.aiqb`/`.cpf` blob" hypothesis turns out
  to be **correct specifically for this register range** — even though it's **wrong** for
  the general per-resolution table, which is fully static. Makes sense in hindsight: PLL
  trim is exactly the kind of per-physical-unit calibration data that would live in a
  tuning blob, unlike fixed windowing/resolution config.
- **Recommended fallback, not yet tried**: since local KD can still freely read live
  memory, a targeted memory search (`s -d <range> ...`) for the same confirmed 16-byte
  entry shape at these specific addresses, across the driver's pool/heap allocations,
  might locate the runtime-parsed blob table directly — plausible if `FUN_140005028` plays
  both static and blob-derived tables through the same generic entry format. Not
  confirmed either way yet; the next concrete step if this thread continues.

**Update, same day: static-table method validated live, KD diagnosed as read-only, and a
4th Ghidra pass exhausted the write-site search without finding it.** Two more docs came
back from the Windows session:

- `docs/windows-agent-findings-static-table-validation-2026-07-20.md`: read `base+0x25410`
  live and got an **entry-for-entry match** against the Ghidra decode from the previous
  note (one minor correction: the `0xfcfc` entry at index 12 has value `0x2000`, not
  `0x4000` like indices 4/8 — a genuine progressive multi-stage write, not a decode error).
  Also diagnosed a real local-KD bug on this WTG machine: `poi()`, pseudo-registers, and
  extension commands (`!drvobj` etc.) all hang indefinitely — only literal-address
  `db`/`dq` work reliably. Confirmed not fixed by reboot. Practical effect: no live
  pointer-chasing without a static/image-relative anchor at every hop; the original
  breakpoint plan (`FUN_14000d1c8` @ `0xD1C8`) is off the table too, since local KD can't
  set breakpoints at all (would need network KD to a second machine).
- `docs/RE-TARGET-3-s5k3j1-pll-source.md` asked for the PLL write's actual call site,
  given the mode-table dead-end. Findings in
  `docs/ghidra-findings-s5k3j1-pll-source.md`:
  - Did a full-binary scan for every function using the same raw-I2C-submit signature
    (call through the CFG dispatch stub with IOCTL constant `0x41808`) — 25 total, only 5
    in the sensor/VCM range, all already accounted for (sensor read/write, VCM read
    ×2/write). **Confirmed there is no unknown 6th primitive** — `FUN_14000d1c8` genuinely
    has only the one caller chain found last time, so the PLL writes don't go through it.
  - Chased the two functions called right after the table write in the mode-set sequence
    (`FUN_140008828`, `FUN_140004cbc`) — both turned out to be **reads, not writes**: they
    read back `0x0308`, `0x030A`, `0x030E`, `0x0310`, `0x0312` (and separately `0x0340`/VTS)
    right after mode-set, to compute a derived "actual pixel/frame clock" value. Useful
    side-result: **confirms the real PLL block is the full contiguous `0x0300`–`0x0312`**,
    two registers wider than brief 5 originally asked about (adds `0x0308`, `0x030A`).
  - **The actual write site remains unfound** after exhausting every angle available
    without touching a genuinely new area (device D0-entry/power-up, not yet examined —
    everything looked at so far centers on `EvtDevicePrepareHardware` or the mode-set
    chain). Flagged as the concrete next step, not yet started.
  - **New, much cheaper alternative surfaced, not tried**: since `FUN_140008828` computes
    a derived actual-clock value from live PLL state on every mode-set, it might be exposed
    via an ordinary queryable DirectShow/MediaFoundation/KS camera property from userspace
    — which would confirm whether Windows's resulting bit rate matches Linux's
    512MHz/1024Mbps assumption without any KD or further Ghidra work at all. Worth checking
    before continuing the RE chase further.

**Update, same session, continuing without a Windows reboot: found a real bug in my own
decoder, and it resolves brief 5 completely.** After the check-in above, kept working the
Linux-side Ghidra angle rather than recommending a reboot yet, on the reasoning that Ghidra
passes are cheap and Windows round-trips are expensive — better to exhaust cheap options
before asking for another one. Chased `EvtDeviceD0Entry` (found via its own debug string,
`FUN_14000ee80` → `FUN_140003760` → `FUN_1400062e0`) all the way down: GPIO reset, CMOS
chip-ID check, VCM init, EEPROM identification (`FUN_140018c74`, "InitRom"), an NVM debug-dump
utility (`FUN_140018758`, writes calibration EEPROM contents to `C:\NVMDump\*.bin` for
diagnostics — unrelated to sensor config despite superficially matching argument shapes),
and a module-name string lookup — **none of it touches PLL/EXTCLK registers**. Real
negative result, but not the answer.

Then, re-examining the two static tables from `FUN_14000a878` (dismissed in an earlier pass
as "NVM-probe tables") properly with the confirmed entry format, found something
decisive: entries this session's tooling decoded as address `0xd090`/`0xc890` are exactly
Linux's real registers `0x90d0`/`0x90c8`, **byte-reversed** — **the address field is a
plain little-endian `u16`, not "raw MSB-first bytes" as both prior findings docs assumed.**
That assumption was never actually validated against an asymmetric test case — the one
cross-check used (`0xfcfc`) is byte-swap-symmetric, so it couldn't have caught the error.

Re-scanning the confirmed-active table (RVA `0x25410`, variant 0) with the corrected
decode finds all 8 PLL/EXTCLK registers, and **every value matches Linux exactly**:

| Register | Windows | Linux |
|---|---|---|
| `0x0136` (EXTCLK) | `0x1333` | `0x1333` ✓ |
| `0x0300` | `0x0007` | `0x0007` ✓ |
| `0x0304` | `0x0002` | `0x0002` ✓ |
| `0x0306` | `0x0095` | `0x0095` ✓ |
| `0x030c` | `0x0000` | `0x0000` ✓ |
| `0x030e` | `0x0003` | `0x0003` ✓ |
| `0x0310` | `0x0109` | `0x0109` ✓ |
| `0x0312` | `0x0001` | `0x0001` ✓ |

`0x0308`/`0x030a` aren't written by either driver (Linux's own table has no entries for
them either) — consistent, not a gap.

**Brief 5 is now closed, cleanly and positively, straight from the static file — no
WinDbg session ever needed.** Corrected both `ghidra-findings-s5k3j1-mode-table-pointer.md`
and `ghidra-findings-s5k3j1-pll-source.md` in place with this finding rather than leaving
the wrong conclusion standing. Sensor PLL/EXTCLK configuration joins the growing list of
things definitively ruled out as the corruption's cause (CSI2 FE/hub-access registers,
buttress clock/power state, PHY calibration table) — all byte-for-byte identical between
Windows and Linux on this exact hardware.

## 2026-07-21: lane-mapping/polarity audit, clock-mode reframe, per-lane decoder, and a fresh-eyes re-audit

Session focused on auditing the lane-mapping/polarity and MCD-PHY-calibration-trigger
angles, then re-auditing the whole 2026-07-17 fresh-eyes list for what was actually
executed. No hardware retest this session — analysis, tooling, and briefs, left staged
for a (possibly lower-effort) follow-up.

**Lane order / polarity / ACPI `_DSD` (fresh-eyes #5) — audited and closed.** Verified
directly against the code and the ACPI dump:
- The camera ACPI nodes (`LNK0`–`LNK4`) have **no `_DSD` at all** — only an SSDB buffer
  (built in a `Method`) + `_DSM` (confirmed: zero `_DSD` in DSDT.dsl lines 95000–98000).
  So there is no `data-lanes` or `lane-polarities` array from ACPI to ignore or default.
- SSDB carries only a lane *count* (`L0NL` @ SSDB offset 0x1D → `struct ipu_sensor_ssdb.lanes`);
  no polarity field. The `csiparams[10]` region that could theoretically hold PHY params
  is all-zero in this firmware.
- `ipu-bridge.c` synthesizes `data-lanes = [1,2,3,4]` and emits **no** `lane-polarities`
  property (`ipu-bridge.c:454`, `:1083`). `s5k3j1.c` validates lane count == 4 and ignores
  polarity (`s5k3j1.c:1881`), correct — sensor TX polarity is fixed silicon.
- The IPU6 receiver parses the endpoint but keeps **only** `port` + `num_data_lanes`,
  discarding `vep.bus.mipi_csi2.flags` (`ipu6-isys.c:752-753`) — so any polarity/clock
  flags are structurally ignored. Polarity, if any, lives only in the fixed MCD-PHY
  per-lane config tables, which are byte-matched to Windows across the whole PHY0 region.
  **Nothing is being ignored; polarity is subsumed by the existing byte-match. Ruled out.**

**MCD-PHY "skipped calibration trigger" hypothesis — refuted, with one honest caveat.**
- Reference-mismatch worth recording: intel/ipu6-drivers **#417 / OV08X40 / Dell Pro Max
  14/16 is Meteor Lake**, which dispatches to **DWC-PHY** (`ipu6-isys.c:1108-1109`,
  `is_ipu6ep_mtl` → `dwc_phy_set_power`). This machine is IPU6**EP** (hw_ver 5, non-MTL) →
  **MCD-PHY** (`:1110-1111`). The "band-index/rounding" timing logic lives in dwc-phy and
  is **dead code here**. That whole bug class can't apply to this hardware.
- The MCD-PHY control surface is complete and small: `PHY_CTL {PWR_EN, RESET}` /
  `PHY_STATUS {POWER_ACK, READY}`. Stream-on runs powerup→reset→common_init→config→reset→
  **READY poll** (`mcd-phy.c:782-806`). The READY poll *is* the calibration-complete/lock
  handshake; it has a 200 ms timeout and logs `"PHY ready ack timeout"` — a string that
  appears in **zero** captured logs. No separate "arm auto-deskew" trigger register exists
  (mainline or ours) to be skipped. MCD-PHY also **ignores** the `timing`/settle struct it
  is passed (only the signature references it) — receiver settle comes from the
  byte-matched tables, not a computed value.
- **Caveat (user's point, conceded):** "hi556 rides the same code and works" only rules
  out a *categorically skipped* step — it is **not** a valid control for a *rate-dependent
  adequacy* problem (READY can assert with residual skew that's fine at hi556's 2-lane/
  lower rate but fatal at the rear's 4-lane/1024 Mbps). So skipped-trigger is refuted;
  runs-but-converges-worse is not.

**"6 dynamic bytes are static under Linux" premise — empirically false.** Diffed the two
on-disk live captures (`reference/linux-phy0-live.bin` rear-streaming vs
`…-hi556.bin` front-streaming): the rear lane-group registers hold **active/calibrated**
values while the rear streams and drop to **idle** when the front streams instead; the
front's lane group mirrors it. The bytes move — the rear PHY reaches the same active state
the working camera does.

**New tool: `scripts/decode-phy0-lanes.py`** — per-lane decoder for those dynamic bytes.
Block layout reverse-engineered from the captures: 0x200-byte per-PPI blocks; rear
(s5k3j1 x4) uses blocks 0x0200–0x0a00 (D1/D0/**C0**/D2/D3), front (hi556 x2) uses
0x1400–0x1800. **Lane→PPI mapping confirmed** (not guessed): the clock lane's distinct
signature lands exactly on block index 2 = PPI2 = C0, matching the driver's own header
comment. Result on the current captures: **all 5 rear lanes reach ACTIVE — no lane stuck
idle/dead.** The dynamic fields split by lane *role* (lower pair D0/D1 `+0x11d=0x21
+0x152=0x60`; rear-only upper pair D2/D3 `+0x11d=0x27 +0x152=0x00`), i.e. they look like
they encode lane position, not health — no single lane flashing an error code. Limitation:
a static snapshot can't see per-packet skew drift. **Cheap follow-up:** run
`sudo scripts/decode-phy0-lanes.py --live` several times during a held-open rear stream;
a lane whose fields are *unstable run-to-run* while others are stable is one that can't
hold lock.

**Re-audit of the 2026-07-17 fresh-eyes 8 — NOT all were tried:**
- #1 hi556 differential — done (07-20, negative).
- #2 continuous vs non-continuous clock — **parked, not resolved.** No software toggle
  exists (`FE_MODE = writel(0)`, flags discarded), so the planned A/B was impossible. The
  receiver FE clock-mode was never compared to Windows. This is the one uncompared
  receiver surface → **`docs/WINDOWS-AGENT-BRIEF-6-csi2-fe-registers.md`** written to read
  `CSI_FE_MODE` (rear = `BAR0+0x221284`) off Windows during a live stream.
- #3 lane deskew / 6 bytes — **partial;** per-lane decode only built this session (above).
- #4 FIFO/ISYS freq+power/stride — done (07-20, byte-identical).
- #5 lane order/polarity/`_DSD` — **done this session** (above).
- #6 SOF genuine vs firmware-synthesized — **was untried.** Procedure written:
  **`docs/PROCEDURE-6-sof-genuine-vs-synthesized.md`.** Key: the stock driver already
  prints all 20 CSI2 error bits by name, so Stage 1 needs no code change — enumerate which
  fire. Bit 7 "Frame sync error" is already in the known signature and SOF fires anyway →
  the *likely* result is "pure-PHY confirmed, drop #7." Also checks bit 17 "Lane deskew"
  and bit 18 "SOT sync" (neither mentioned in STATUS yet; either would sharply narrow
  things and tie to #3/#2 respectively).
- #7 VC/DT / embedded-data-line mismatch — **untried** (the `pdaf_trial` vblank test is
  related but is not this check). Gated behind #6: if #6 confirms pure-PHY, #7 can be
  dropped.
- #8a DMAR/IOMMU — done (07-20, none). #8b Windows PLL dividers — done (all 8 match).

**Recommended order for the follow-up (cheapest-first, all Linux-side except the brief):**
(1) #6 Stage 1 — reinstall custom modules, capture a rear-stream dmesg, enumerate the
error bits; likely resolves #6 and may light up bit 17/18. (2) `decode-phy0-lanes.py
--live` × several during a rear stream for the run-to-run stability check (#3). (3) run
BRIEF-6 on a Windows-To-Go boot to settle #2 from the receiver side. #7 only if #6 comes
back *not* pure-PHY.

**#6 RESULT (2026-07-21, real hardware, `cam -c <rear> --capture`) — pure-PHY confirmed,
and sharper than expected.** Captured a single rear-stream attempt
(`reference/dmesg-rear-stream-20260721.txt`). Timeline: CSI2 receiver enabled (FE
`mode=0 ppi_intf=0x18` = 4 lanes) → 210 ms later `s5k3j1 s_stream(1)` returns 0 (sensor
transmitting) → 54 ms after that, **one burst of 10 error bits within 94 µs, then
silence** (the atomic failure unit; the old "747 callbacks suppressed" pattern was a GUI
client's retry loop, not sustained per-frame corruption). **No ratelimit truncation**
(`total==distinct==10`, no "callbacks suppressed"), so bit *absences* are trustworthy.

Bits that fired: 0/1 (header err corrected/uncorrectable), 6 (incomplete long packet),
**7 (Frame sync)**, **8 (Line sync)**, **9 (DPHY recoverable)**, **10 (DPHY FATAL)**,
12/13 (inter-frame short/long discarded), 16 (FIFO overflow). Bits notably **absent**:
**2 (Payload CRC)**, **17 (Lane deskew)**, **18 (SOT sync)**.

Interpretation — the sharpest characterization of the failure yet:
- **DPHY fatal (bit 10)** = unrecoverable PHY sync loss = pure physical layer. **#6
  answered: the corruption is pure-PHY.**
- **No Payload CRC (bit 2)** = sync is lost *before* any long packet is parsed → not a
  data-corruption/descramble problem.
- **No SOT sync error (bit 18)** = each lane enters high-speed cleanly; sync is lost
  *during* the sustained burst, not at HS entry. Lanes reach HS individually, then the
  aggregate 4-lane stream loses coherence fatally within ~1–2 frame times. **This is the
  textbook signature of inter-lane skew exceeding tolerance** — directly supports #3 and
  the user's rate/timing-margin hypothesis (4 lanes × 1024 Mbps, D2/D3 rear-only).
- Consequences for the other items: **#7 dropped** (fatal PHY sync loss precedes any VC/DT
  handling). **#2 weakened** (clean SOT argues against a clock-mode mismatch, which would
  break at HS entry; FE_MODE brief still worth doing but now ranks *below* the lane work).

**Where this leaves the investigation:** the leading hypothesis is now **inter-lane skew /
per-lane timing margin at 4-lane 1024 Mbps** (#3 + user's timing-margin point), NOT a
static-config or data-layer cause. Static PHY register snapshots can't see the transient
mid-burst sync loss (the `--live` decoder shows all lanes "ACTIVE" because it reads the
settled/stalled state, not the 54 ms failure window). Next candidate experiments, in
rough priority: (1) if the sensor can be driven at fewer lanes or a lower link rate (a
binned/slower mode), test whether corruption disappears — a positive result would *prove*
the physical-margin hypothesis by construction (bigger change: needs a new `s5k3j1` mode
table). (2) Capture per-lane PHY error/status *during* the failure window rather than
after (harder — transient). (3) BRIEF-6 FE_MODE read (de-prioritized by clean SOT, cheap
receiver-side insurance). External MIPI-line instrumentation remains the
definitive-but-unavailable endpoint, and this result makes its case stronger and more
specific (measure inter-lane skew on D0–D3).

**Correction + reopened lead (2026-07-21, prompted by the user).** An earlier draft of
this note implied the failure "may not be software-fixable" if it's physical skew. That's
wrong and worth correcting in the record: **Windows works on this exact silicon, which is
proof a working software/firmware configuration exists** — the hardware is identical, only
the driver stack differs. This is an unsolved search problem (find the missing config
lever), not an unsolvable one. The only "works-on-Windows-but-hard-on-Linux" cases that
wouldn't reduce to replicable software are a CSE/firmware command or ACPI method Windows
invokes that Linux doesn't — still *unreplicated software*, not a wall.

What this reopens, concretely: if the failure is inter-lane-skew-shaped, Windows must be
compensating for it somehow — a per-lane deskew calibration / delay-trim / PHY mode we
haven't reproduced. Two reasons such a lever could exist and still be invisible to
everything checked so far:
- **MCD-PHY (this hardware's backend) has no runtime per-lane timing/deskew computation at
  all** — it ignores the `timing` struct; every per-lane value comes from static tables.
  (The per-lane timing math lives in DWC-PHY, the MTL backend — dead code here.) If
  Windows's MCD-PHY driver computes/applies per-lane deskew that Linux's doesn't, a
  static-table byte-match never sees it.
- **The "6 dynamic bytes" were dismissed on an invalid control.** Their *values* were only
  ever compared Linux-rear-vs-Linux-front-hi556 (both churn → "non-diagnostic") — but
  hi556 is 2-lane and can't be a control for a 4-lane-margin effect (same objection the
  user raised about the shared-code argument). The 50-register byte-match that "settled"
  the PHY region **explicitly excluded** the 6 dynamic bytes ("none of which overlap").
  Those 6 are exactly where a per-lane calibration would write its *results*. They have
  **never** been compared Windows-rear-working vs Linux-rear-broken.

**New highest-value cheap experiment (supersedes the priority list above):** capture the
rear PHY0 region on a *working Windows* rear stream and diff specifically the 6 per-lane
dynamic bytes against Linux-rear (`reference/linux-phy0-live.bin`), using
`scripts/decode-phy0-lanes.py`. If Windows-rear converges those bytes to different values
than Linux-rear, that difference is the missing lever (points at a deskew calibration Linux
omits). One Windows capture, not a scope. **Brief written: `WINDOWS-AGENT-BRIEF-7-rear-phy0-dynamic-bytes.md`**
(to be run in the same WTG boot as BRIEF-6, since both need a live rear stream + the same
BAR0).

**Partial answer already available from brief-3's existing data.** `windows-agent-findings-phy-trim-2026-07-16b.md`
was itself Windows-*rear* captures. Two of its reported dynamic offsets map onto the decoder's
field scheme (`0x2B0` = block `0x0200` `+0xb0`, `0x352` = block `0x0200` `+0x152`), and
Linux-rear's values (`0x0d`, `0x60`) both fall **inside** the Windows-rear churn range it saw
({0x09,0x0d}, {0x60,0x40}). So for the 2 overlapping fields there's **no gross divergence** —
Linux-rear looks like a normal sample of the same churn. This is only 2 of ~6 dynamic bytes and
they're noisy, so BRIEF-7 exists to make the full-region, all-lanes comparison rigorous — but the
leading expectation is now that the dynamic bytes match too, and the real gap is a per-lane deskew
mechanism the MCD-PHY Linux path never runs (vs. something whose *result* is visible in these bytes).

**BRIEF-6 + BRIEF-7 RESULTS (2026-07-21, WTG boot). One hypothesis closed, one concrete new lead.**
Findings docs: `windows-agent-findings-csi2-fe-registers-2026-07-21.md`,
`windows-agent-findings-rear-phy0-dynamic-bytes-2026-07-21.md`; raw dumps `docs/win-rear-phy0-{1,2,3}.bin`.
(Op note from the agent: IPU6 BAR0 = `0x7FFF000000`; reading the BAR while the IPU6 is runtime-suspended
to D3 **bugchecks the machine** — only read while the target camera is actively streaming. Use RWEverything
`DMEM`, not `SAVE` — `SAVE` truncates the address to 32-bit.)

- **BRIEF-7 (PHY0 dynamic bytes) — CLOSED, it's the thermometer not the lever.** Ran
  `decode-phy0-lanes.py` on all 3 Windows-rear dumps vs Linux-rear. Of the ~6 dynamic per-lane bytes,
  five match or share churn sets. The one clean, universal divergence is field **`+0xb8` = `0x00` on
  Windows (all 5 lanes, all 3 restarts) vs `0x10–0x13` on Linux-rear.** But the full mcd-phy write-offset
  list confirms the driver **never writes any `*b8` offset** (`0x2b8/0x4b8/0x6b8/0x8b8/0xab8` absent from
  every `phy_reg` table) — so `+0xb8` is a **hardware read-back status**, not config. `0x10–0x13` is the
  PHY reporting **per-lane error status because Linux's lanes are failing**; Windows reads `0` because
  they're healthy. Consequences: (a) the PHY0 *config* Linux writes is now re-confirmed matched to Windows
  **per-lane on a valid 4-lane control** — config hypothesis thoroughly dead; (b) `+0xb8` shows **all 5
  lanes erroring together** (data `~0x12`, clock `0x10`), pointing away from "one flaky D2/D3 lane" toward
  a **shared/systemic cause** (clock, all-lane skew, or something upstream of the lanes). `+0xb8` is now a
  usable **per-lane health instrument** for future tests (0 = healthy, nonzero = erroring).
- **BRIEF-6 (FE registers) — `CSI_FE_MODE = 0x0` matches (clock-mode closed), but found a real
  driver-written divergence:** **`PPI2CSI_CONFIG_INTF` (reg 0x204) bit 1 (`0x2`) is set on Windows on
  BOTH ports, clear on Linux** (rear `0x1A` vs `0x18`, front `0x0A` vs `0x08`). Linux's `csi2.c:332` writes
  only `FIELD_PREP(NOF_ENABLED_DLANES_MASK=GENMASK(4,3), nlanes-1)`, leaving bit 1 = 0. Bit 1 is **unnamed**
  in the reg header. Unlike `+0xb8` this is a register the driver **does** write, on the corrupting
  PPI→CSI path — the first genuine driver-written receiver-side config divergence found. Caveat: the
  working front (hi556) also has bit 1 set on Windows yet works on Linux without it — **but hi556 is 2-lane
  and not a valid control for a 4-lane/1024 Mbps effect** (the user's standing point), so worth testing.

**EXPERIMENT STAGED (not yet tested): `ppi_intf_bit1` module param.** Added to `drivers/ipu6-isys/ipu6-isys-csi2.c`
(new `#include <linux/moduleparam.h>`, writable `0644` bool param, ORs `BIT(1)` into the PPI_INTF write when
set; default 0 = stock). Test: rebuild+install `intel-ipu6-isys`, reboot once, then A/B live:
`echo 1 | sudo tee /sys/module/intel_ipu6_isys/parameters/ppi_intf_bit1`, restart a rear stream
(`cam -c <rear> --capture`), and check whether the `csi2-1` error burst clears / `+0xb8` drops to 0.
`echo 0` to revert without reboot. If it recovers sync → strong lead (and replicate Windows exactly, DMI-gate,
clean up). If not → revert; the remaining leads are physical (inter-lane skew) needing instrumentation.
(Verify the module param name once loaded — it may be `intel_ipu6_isys` or `intel_ipu6_isys_csi2` depending
on how the symbol lands; `ls /sys/module/*/parameters/ | grep ppi_intf_bit1`.)

**Kernel bumped to 7.0.0-28-generic; resolute updated to match (2026-07-21).** Running kernel is now
`7.0.0-28-generic` (headers/build tree installed, so custom modules build against it). `~/work/git-ubuntu/resolute`
was one release behind (`Ubuntu-7.0.0-27.27`) → `git fetch --tags` + checked out **`Ubuntu-7.0.0-28.28`** (the
`.28i1/.28i2` tags are pre-release iterations; `.28` is the match). Diff 27.27→28.28 for our subsystem:
- **Corruption-path files UNCHANGED** (`ipu6-isys-csi2.c`, `ipu6-isys-mcd-phy.c`, `ipu6-isys.c`) — no upstream
  fix for our bug landed; the `ppi_intf_bit1` experiment and all custom-module logic are unaffected.
- `ipu6.c`: trivial 2-line error-path robustness fix (`if (isp->psys)` → `if (!IS_ERR_OR_NULL(isp->psys))`)
  in the *failed-probe* cleanup only — not relevant, no need to port.
- **`ipu-bridge.c` (+84 lines): the rebase-relevant change STATUS's TODO already anticipated** — a new
  HID-vs-DSM/GUID match mechanism (`upside_down_match_info`) for the sensor 180°-rotation quirk, plus DMI
  entries for Dell XPS 13 9340/9350, XPS 14 9440, XPS 16 9640, XPS 14 DA14260 (Pro 14 Premium). About
  upside-down sensor mounting, *not* corruption; does not touch the XPS 13 9315 2-in-1; doesn't affect the
  build (our `drivers/ipu-bridge` is a separate out-of-tree copy). But our out-of-tree `ipu-bridge.c` is now
  further behind upstream's structure → the "rebase `ipu-bridge`" TODO should target `Ubuntu-7.0.0-28.28`.

## 2026-07-21: BREAKTHROUGH — PPI2CSI_CONFIG_INTF bit 1 makes the rear camera stream

**Setting `ppi_intf_bit1=1` fixed it.** On real hardware (7.0.0-28-generic, custom module with the
staged param, srcversion `B6C7054…` confirmed loaded): with bit 1 (`0x2`) OR'd into the
`PPI2CSI_CONFIG_PPI_INTF` write, `cam -c <rear> --capture=200` produced **200 sustained frames at
25.19 fps, `bytesused=43425792` each** (= 3968×2736×4, full ABGR8888). Before this change, **zero
frames ever completed** — the stream threw one 10-error burst and stalled.

CSI2 error signature collapsed from 10 types to 3, and the 3 fire **once at stream start** then go
quiet while frames flow:
- **Gone:** DPHY **fatal** error (bit 10, the unrecoverable one), Frame sync (7), Line sync (8),
  header errors (0/1), inter-frame short discard (12), FIFO overflow (16).
- **Remaining (one-shot at startup, non-fatal):** incomplete long packet (6), DPHY **recoverable**
  sync (9), inter-frame long discarded (13). The PHY now *recovers* instead of dying.

**Root cause:** mainline `ipu6-isys-csi2.c` writes only `FIELD_PREP(NOF_ENABLED_DLANES_MASK, nlanes-1)`
to `PPI2CSI_CONFIG_PPI_INTF` (reg 0x204), leaving bit 1 clear. Windows sets bit 1 on every CSI2 port
(found via BRIEF-6, 2026-07-21). Bit 1 is unnamed in the register header. hi556 (2-lane) tolerates it
clear, which is why it was never caught — it only bites 4-lane/1024 Mbps, exactly the user's standing
"2-lane is not a valid control" point. This was the one driver-written, never-byte-matched receiver
register in the whole investigation.

**CONFIRMED SOLVED (both checks passed, 2026-07-21):**
1. ✅ A/B revert (toggled live, no reboot): `ppi_intf_bit1=0` → stream broken again (`bytesused:0`,
   0 fps, fatal-error burst back); `=1` → 25.19 fps full frames. **Bit 1 is definitively causal.**
2. ✅ Image quality: early frames (0–2) are black (auto-exposure ramp), but a late frame (#59) has all
   three RGB channels fully populated (range 0–255, means ~171–184) — a real, well-exposed image, not
   black and not garbage. The rear camera genuinely works: sustained clean 25 fps with real pixels.

**Productionized — committed `fb9ea18` (2026-07-21):** the debug `ppi_intf_bit1` param is replaced by
a DMI-gated bit-1 set (`ppi_intf_bit1_dmi_ids`, this exact model only) in the PPI_INTF write. Builds
clean; needs `install-custom-modules.sh` + reboot to become the running module. Open question left for
the eventual upstream submission: is bit 1 correct for *all* IPU6 CSI2 (a latent mainline bug — plausible,
since Windows sets it on every port) or specific to this board? If the former, this is a genuine
mainline fix candidate, not just a quirk. Needs the semantics of bit 1 pinned down (or at least a
statement that Windows sets it universally) before submission. See [[project-s5k3j1-upstream-goal]].

## Upstream goal

The user's stated goal for this project is eventual real upstream
submission — to Dell, the Intel IPU/MIPI team, and/or Linux kernel media
maintainers — not just a personal working setup. Stated rationale: Dell
didn't fund Linux support for this model, but a working, clean patch might
get accepted anyway; part of a broader goal of encouraging Linux support on
consumer/2-in-1 hardware, not just servers and dev laptops. This raises the
bar on any platform-specific code added to shared files: it must be gated
narrowly enough (DMI + HID, following the pattern above) that it provably
cannot regress any other machine, known or hypothetical — not just "works
on my machine."

## TODO

- [x] **Rear camera (s5k3j1) auto-exposure — SOLVED 2026-07-22, two independent root causes
      found and fixed, both confirmed live against a bright window/monitor with debug telemetry:**
      1. **`libcamera` AGC gain-floor bug (`again10`).** In `src/ipa/simple/soft_simple.cpp`,
         `context_.configuration.agc.again10` (the threshold `Agc::updateExposure()` in
         `algorithms/agc.cpp` uses to decide "still above the gain floor, cut gain" vs. "at the
         floor, cut exposure instead") was computed as `camHelper_->gain(1.0)` — feeding the
         literal register code `1` through the sensor's code→gain formula, assuming code 1 is
         close to the real minimum. For `s5k3j1`'s `CameraSensorHelper` (`gain = code/32`,
         real floor at code 32 = 1.0x), that computes to `1/32` of the real floor, so the
         "cut gain" branch is *always* taken, the target is always below the achievable
         minimum, `std::clamp` silently snaps it back to exactly the floor every single frame,
         and the "cut exposure" branch is never reached — exposure sticks at the driver's max
         default forever, no matter how overexposed the scene is. (`hi556` wasn't hit by this:
         its helper's constants happen to put `gain(1.0)≈1.06`, just above its real floor, by
         coincidence of that sensor's calibration, not by design.) Fix: use the already-computed
         real floor (`againMin`) directly instead of the `gain(1.0)` heuristic.
      2. **Hardwired digital-gain floor in the kernel driver.** `s5k3j1.c`'s
         `S5K3J1_DGTL_GAIN_DEFAULT` was `2560` (2.5x). The libcamera soft-ISP `simple` pipeline
         only ever adjusts `V4L2_CID_EXPOSURE`/`V4L2_CID_ANALOGUE_GAIN` — it never touches
         `V4L2_CID_DIGITAL_GAIN` — so this 2.5x sat as a fixed, AGC-invisible multiplier applied
         via `__v4l2_ctrl_handler_setup()` on every stream-on. Changed default to `1024` (1x,
         neutral). Requires `install-custom-modules.sh` + reboot to take effect (confirmed
         working after reboot, `digital_gain` control now shows `default=1024 value=1024`).
      Both fixes shipped in the local `libcamera` package as `0.7.0-1ubuntu3+hi5563` (bundled
      with the first `hi556` CCM pass, below) — see `debian/changelog` in
      `~/work/git-ubuntu/libcamera` for the exact commit-style writeups. **A separate, real
      limitation found but NOT fixed**: the AGC algorithm has no anti-flicker handling, and in
      a dim room with flicker-prone lighting, exposure pins at max (genuinely not enough light)
      and gain hunts wildly frame-to-frame (observed swinging 1.17x–3.05x with a ~1s period) —
      confirmed via live telemetry, not a regression from either fix above, pre-existing gap.
      Fixable (dampen gain step / widen hysteresis, or real flicker-period detection) but not
      attempted; more room light sidesteps it in the meantime.
- [x] **hi556 CCM — tuned and shipped, 2026-07-22.** Enabled `Ccm` in
      `ipa/simple/data/hi556.yaml` (was commented out). Measured against non-clipped white-paper
      captures under ~6800K room light: first pass (`R×1.034, G×0.977, B×0.991`, from two
      pre-CCM samples) under-corrected by about 60% (confirmed both by live visual check — user
      still saw "a tad green" — and by a post-CCM raw-frame measurement); second pass
      (`R×1.062`) closed the gap to ~1%, at or below the sample-to-sample measurement noise
      floor (framing/AWB-convergence variance was itself ~1% between otherwise-identical
      captures). Shipped as `+hi5563` (first pass) then `+hi5564` (retune). Diagonal-only, single
      `ct: 6800` node — no evidence of real cross-channel bleed requiring off-diagonal terms, and
      no coverage claimed outside ~6800K-ish lighting.
- [ ] **s5k3j1 (rear) CCM — attempted and REVERTED 2026-07-22, needs a better approach.**
      Two paper measurements (blinds open at two different amounts, ~8300K and ~12500K
      estimated) showed a small, consistent-direction cast (mild excess red/blue, deficient
      green — opposite direction from hi556) and were built into a 2-node CCM (`+hi5565`).
      Verification in a **third, different room** with good-but-indirect natural light
      (~5535K, well outside the calibrated range) showed the CCM active made color *worse*
      there (R-G +4.9%, B-G -2.2%, both worse than no CCM), because the interpolator clamps to
      the nearest node (8300K) outside its calibrated range and that node doesn't suit warmer
      light. Reverted to disabled in `+hi5566` — two blinds-open, near-window samples aren't
      representative enough coverage to leave a CCM on for general use. **Don't re-attempt
      with more ad-hoc paper measurements** — see below.
- [ ] **Extract real IQ tuning (CCM, AWB, black level, gamma) from the Intel AIQ `.aiqb`
      binaries instead of ad-hoc measurement (future, separate effort) — the better path
      forward for both cameras' color tuning, prompted by the rear-camera CCM failure above.**
      `reference/windows-driver-artifacts/dell-drivers/.../Drivers/` has
      `s5k3j1sx04_CJALR11_ADL_PDAF_T2.aiqb` (rear) and hi556's own `.aiqb` — these came from
      Intel/Dell's actual lab calibration (multiple standard illuminants, properly interpolated
      across the full CT range), which is exactly the kind of broad, controlled coverage that
      today's single-room, shifting-daylight paper measurements couldn't replicate — the rear
      camera CCM attempt above is a concrete example of why ad-hoc measurement isn't good
      enough. Not yet started: needs the `.aiqb`/`.cpf` binary format parsed (Intel AIQ tools if
      available, or RE similar to how the VCM/PLL/CSI2 work in this project was done). The
      `graph_settings_*.xml` files (64 of them) are pipeline-graph topology, not IQ tuning — not
      useful for this despite being XML/human-readable. Realistic scope: the soft ISP only
      consumes a small subset (black level, AWB gains, a 3x3 CCM, gamma) — don't expect to
      consume the `.aiqb` wholesale, just mine those specific fields once the format is known.
- [ ] **Real closed-loop autofocus for the rear camera — scoped 2026-07-22, Phase 0 run once
      with real findings, dataset not yet clean.** Full architecture options, decisions made
      2026-07-22 (continuous AF is the actual goal, not single-shot; must work with zero app
      cooperation, like `Agc`/`Awb` already do), a 4-phase roadmap, and open questions are all
      in `docs/autofocus-cdaf-scoping.md`. `scripts/af-sweep-measure.sh` (Phase 0 harness) ran
      against real hardware: found and fixed a `/dev/media0`-vs-`/dev/media1` numbering bug
      (media device enumeration order isn't stable across boots — same fix applied to
      `dell-xps9315-test-rear-dual.sh`, which had the identical latent bug), then produced a
      16-position sweep
      (~3GB, `~/work/af-sweep-data/run1`, outside the repo). `scripts/af-analyze-sweep.py`
      (first Phase 1 tool) found the dataset isn't trustworthy yet: every burst's first frame
      reads as blank (systematic, discard as convention), and AGC exposure drifted 6.5× across
      the sweep with no real per-position convergence (state leaks across positions because
      each position is a separate short-lived `cam` process and exposure is a persisted
      hardware V4L2 register) — confirms the "AGC interaction" unknown is a real, already-
      encountered problem, not just a design risk. Next step: a continuous-session harness
      (single long-lived capture, focus changed mid-stream from a concurrent process against
      the lens subdev) instead of per-position process relaunch — not yet built, see the doc's
      Phase 0/1 sections. PDAF context (dead end on this kernel, WIP archived in
      `~/work/git-ubuntu/libcamera` branch `pdaf-sideband-wip`) is preserved in that doc rather
      than here.
- [ ] **Rebase `drivers/ipu-bridge` onto current real upstream, before further cleanup.**
      Its base commit (`7364894 from linux_7.0.0.orig.tar.gz`) came from an apt-source
      snapshot that's already confirmed stale: diffing it against
      `~/work/git-ubuntu/resolute` at the exact matching tag (`Ubuntu-7.0.0-27.27`, fixed
      2026-07-14 — see below) turned up real upstream additions we're currently missing,
      including a new sensor-module GUID lookup mechanism and DMI quirk entries for other
      Dell laptops (XPS 14, Dell Pro 14 Premium). Rebasing onto the exact current tag
      first means our own delta (the XPS 13 9315 2-in-1 quirk) becomes a small, clean diff
      against what's actually current, rather than silently reverting or conflicting with
      upstream's own newer work. Do this *before* the patch-series cleanup below, since
      rebasing will likely reshape the diff anyway.
- [x] Write or adapt a standalone `lc898217`-style Linux VCM driver — done and **fully
      verified on real hardware** 2026-07-15, see "What works" and "VCM driver" sections
      above.
- [x] The 10-bit position range is now live and working (`focus_absolute` exposed with
      `0-1023`, a real value write confirmed via `v4l2-ctl`) — the 11-bit question is now
      moot unless empirical testing later shows 10-bit is *too* conservative (unlikely
      given the boundary-safety reasoning in `docs/vcm-investigation-lc898217.md`).
- [ ] **Restore the stock Linux IPU6 firmware and re-verify the camera still works.** The system
      is currently running Dell's Windows-signed IPU6 firmware (`ipu6ep_fw.bin.zst` decompresses to
      `836f1cde…`), swapped in 2026-07-17 as a test that came back negative (firmware content does
      not affect the corruption — see that day's entry). It should be reverted to stock because the
      bit-1 fix must be shown to work on the firmware a normal Linux user actually has (the working
      camera today was validated on Dell's fw). The bit-1 fix is host-side (CSI2 receiver register)
      so it *should* be firmware-independent, but verify. Two clean restore paths: (a) the intact
      root-owned backup `/lib/firmware/intel/ipu/ipu6ep_fw.bin.zst.orig-backup`
      (`sudo cp` it back), or (b) `sudo apt reinstall linux-firmware-intel-graphics` (the package
      provides the stock file). Then reboot (IPU6 fw is loaded at runtime via request_firmware; a
      reboot is cleanest) and confirm the rear camera still streams in the Camera app. Do this
      *after* confirming the production module fix reproduces on the current fw, so the two changes
      stay isolated.
- [ ] Root-cause the dual-monitor regression.
- [ ] Clean up the driver git histories in `drivers/*` — current commits mix real fixes
      with debug prints/diagnostics in the same commit (e.g. `ipu-bridge`'s "debug code."
      commit contains both a genuine ordering-bug fix and a `pr_info` debug line). Needs
      re-splitting into a clean, reviewable patch series before any upstream submission.
- [x] Remove the temporary debug prints — done 2026-07-21, one clean commit per repo, each
      rebuilt to confirm it still compiles: `ipu6-isys` `cf30003` (CSI2 FE/PPI2CSI/hub-access
      register dump), `ipu-bridge` `2b27a66` (`pr_info` cfg/link-freq dump), `s5k3j1` `3554b56`
      (link-frequency `DEBUG` block). Swept all five repos afterward: no `DEBUG`-tagged prints
      remain. `dev_dbg()` calls left in place (compile/runtime-gated, legitimate).
- [x] `TPS68470_VCM`'s `.always_on = 1` diagnostic hack — done 2026-07-15, see "VCM driver"
      section above.
- [ ] Decide eventual upstream submission targets: `ipu-bridge.c`'s DMI-gated i2c quirk
      and the TPS68470 board data are plausible mainline-kernel candidates once cleaned
      up; the `s5k3j1.c` PDAF/dual-stream work may be more appropriate for Intel's
      `ipu6-drivers` out-of-tree package given how novel the dual-stream pattern is (no
      existing IPU6 driver does this).
- [x] `~/work/git-ubuntu/resolute` is now a working, exact-tag-matched clone of the
      canonical Ubuntu kernel git tree (`Ubuntu-7.0.0-27.27` — matches the currently
      running kernel exactly, fixed 2026-07-14). It supersedes the old apt-source tree
      for anything needing precise upstream comparison, since apt-source snapshots are
      easy to let go stale silently (which is what happened before). Use this as the
      rebase target for the item above.

## Attribution

Anything adapted from someone else's work — code, register-map findings, documentation —
gets real attribution, not just because GPL requires preserving copyright notices, but
because it's the right way to build on other people's effort. The clearest case so far:
`drivers/media/i2c/lc898217xc.c` by Vasiliy Doylov (`nekocwd@mainlining.org`), currently
in upstream review at `linux-media@vger.kernel.org`, is the direct basis for the eventual
VCM driver here. If/when that happens: keep his `SPDX-License-Identifier` and copyright
line in the file, add our own copyright line for whatever we change (don't replace his),
and say so explicitly in the commit message and any code comments describing what
changed and why. Same principle applies to anything else pulled in along the way (ON
Semi's datasheet content, other reference drivers, etc.) — cite the source in
`docs/vcm-investigation-lc898217.md` (already done for what's used so far) and in code
comments at the point of use, not just in a README credits section after the fact.

## Front camera (`hi556`) and IR camera (`og0va1b`) — reference, not active work

- `hi556` already works via mainline + libcamera (see `~/work/git-ubuntu/libcamera`,
  branch `hi556`, and `~/work/git-ubuntu/pipewire`, same branch — left where they are,
  not part of this project directory, since they're general package-build workspaces).
- `og0va1b` (ACPI `OVTI00AB`) is a possible future target — confirmed no PDAF/VCM (much
  simpler than the rear camera, closer in shape to `hi556`). See
  `docs/windows-agent-findings-2026-07-13.md` §"Secondary task" for what's already known.
