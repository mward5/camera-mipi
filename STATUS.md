# Status — 2026-07-27 (updated)

> This file is a curated current-state summary, not an append-only log. Update the
> relevant section in place when something changes rather than adding a new dated
> entry at the bottom — that's what made this file hard to read before the
> 2026-07-27 cleanup (see `docs/status-archive-rear-camera-corruption.md` for the
> detailed historical debugging narrative this file used to contain in full).

## Current state at a glance (2026-07-27)

Both cameras stream and work day-to-day. Remaining items are refinement, not
breakage.

- **Rear camera (`s5k3j1`) streaming corruption** — SOLVED 2026-07-21. Full story
  archived; see `docs/status-archive-rear-camera-corruption.md`.
- **VCM / autofocus** — driver verified 2026-07-15; real closed-loop continuous AF
  built and validated on hardware 2026-07-23. Known gap: AF is slow (~29s full
  convergence) and hunts/backtracks before settling — see the TODO entry below and
  the 2026-07-27 chat discussion on CDAF headroom (parabolic peak-fit is the
  concrete next idea, not yet tried).
- **Rear camera auto-exposure (AGC)** — two real bugs found and fixed 2026-07-22
  through 2026-07-24 (`+hi5567` through `+hi5570`); both cameras land in a sane
  exposure range now. Still frame-global metering (no region weighting) — real
  headroom left, not yet pursued.
- **Front/rear camera CCM (colour correction)** — real per-illuminant vendor
  calibration data extracted from Dell's `.aiqb` files and deployed live on both
  cameras 2026-07-27 (see `docs/aiqb-cmc-dump-findings.md`). Genuine improvement on
  skin/clothing colour; known live defect (green cast on neutral surfaces, magenta
  highlight clipping — root-caused, not fixed) documented in the CCM TODO entries
  below. Not yet packaged into a `.deb`/changelog entry.
- **`hi556` orientation/naming fix** — root-caused and patched 2026-07-24
  (`docs/hi556-camera-orientation.patch`), not yet built or tested on hardware.
- **Rear camera privacy-indicator LED never lights** — root-caused 2026-07-24
  (TPS68470 path has no privacy-LED concept at all), not fixed.
- **PDAF** — re-assessed 2026-07-25-ish: the algorithm already exists in-tree and
  is license-compatible, but blocked kernel-side on the
  `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1` restriction on the PAF sideband stream. Next
  step (deferred to its own chat as of 2026-07-27): understand exactly where that
  restriction lives and how Raspberry Pi's PDAF path differs architecturally.
- **Upstream submission** — not yet done for anything. See "Upstream goal" below
  for the standing bar (DMI+HID gated, zero regression risk), and the CCM findings
  doc for an open question specific to that data's proprietary-source licensing.

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

## VCM driver — DONE, verified on hardware 2026-07-15

(Title was stale until 2026-07-27 cleanup — said "not yet tested" despite
the "Fully verified working end-to-end" note below it. Real closed-loop
autofocus built on top of this later; see the "Real closed-loop
autofocus" item in the TODO section.)

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

## Rear camera (s5k3j1) corruption/streaming saga — RESOLVED 2026-07-21

Symptom: the rear camera showed a black screen in desktop apps (GNOME
Snapshot); deeper investigation found the stream never actually completed a
frame. The debugging path ran from 2026-07-16 through 2026-07-21 through
several real-but-not-root-cause bugs along the way (a link-frequency
mismatch, a regulator sequencing bug, PHY trim experiments, a full
lane-mapping/polarity audit, live I2C register captures).

**Root cause**: `PPI2CSI_CONFIG_PPI_INTF` (register `0x204`) **bit 1**, which
mainline `ipu6-isys-csi2.c` never sets and Windows sets on every port. With
it set, the rear `S5K3J1` streams sustained 25 fps with real image data;
with it clear, the stream dies with a fatal DPHY error.

**Fix**: `drivers/ipu6-isys` commit `fb9ea18`, DMI-gated bit-1 set for this
exact model.

**Open upstream question**: whether bit 1 is needed on *all* IPU6 CSI2 (a
latent mainline bug, since Windows sets it universally) or is specific to
this board — not yet pinned down, and worth resolving before any upstream
submission of this fix.

Full chronological debugging log (every dead end, every false lead, in
full technical detail) preserved verbatim in
`docs/status-archive-rear-camera-corruption.md`.

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
      attempted; more room light sidesteps it in the meantime. **Confirmed on the rear camera
      too, 2026-07-23** (see the autofocus TODO item below): same character of sustained,
      periodic gain hunting (swinging ~2.9x–4.5x, roughly 1.5–2s per step) — and, tested
      directly, **independent of focus state**, ruling out defocus as cause or cure. Since the
      `Agc` algorithm code is shared between `hi556.yaml` and `s5k3j1.yaml` (`src/ipa/simple/
      algorithms/agc.cpp`), this is one generic algorithm gap affecting both cameras, not two
      separate bugs.
      **FIXED 2026-07-24 (see correction below — the first shipped fix, +hi5567, was itself
      buggy; +hi5568 is the real fix).** User reported the rear camera washed out / oscillating on an
      off-white wall ~5 inches away, with a pulsating "sunburst" — the same gain-hunting bug,
      now root-caused precisely rather than just characterized. Instrumented live with the
      existing `IPASoftExposure` debug logging against that exact scene: exposure was pinned at
      its max (`exp 3412`, the whole run), and gain swung in a very regular ~6-sample cycle
      between ~2.6x and ~3.9x (~50% swing) at the stats interval this build runs at (4 frames
      apart at 25fps ≈ 160ms/sample) — a ~1s period, matching what the user described watching
      live. Root cause: `Agc::updateExposure()`'s fixed ~10% step, with zero damping, overshoots
      the ±0.2 satisfactory band on essentially every update when the scene's brightness responds
      very steeply to gain (bright, close, reflective wall) — a textbook relay/bang-bang limit
      cycle, not a scene-specific Windows-tuning gap. **Fix**: added a persistent per-session
      step-scale factor to `IPAActiveState::agc` (`direction`/`stepScale`) — multiplicative
      decrease (×0.5) when the correction direction flips from the previous update (meaning the
      previous step overshot), slow additive recovery (+0.1, capped at 1.0) otherwise (AIMD).
      At `stepScale == 1.0` the arithmetic is bit-identical to the old fixed-step behaviour, so
      scenes that never overshoot see zero change. **Confirmed live both ways**: s5k3j1 against
      the same close-wall scene now converges (~5.5s) and holds rock-steady instead of hunting
      forever; hi556 against a normal indoor scene never left `stepScale = 1.0` across the whole
      capture (no reversal ever detected) — confirming the fix is inert, and therefore
      non-regressing, on the case that already worked. Committed `065d3d5` on the `hi556` branch.
      Shipped as `+hi5567` — this build also packages the Phase 2/3 autofocus work (`169d683`,
      `11a61f8`, `46b8669`) and the rear-camera CCM revert (`0edde37`) for the first time; both
      had only ever been validated via the dev-build `LD_LIBRARY_PATH` override, never actually
      installed as the system package, until now. **Not chased further, low priority**: the
      ~5.5s convergence time on the pathological close-wall scene is noticeably slower than a
      normal scene's ~1s convergence (see the hi556 capture above) — expected, since the fix
      trades some responsiveness for stability specifically in the high-sensitivity regime that
      used to oscillate forever; no evidence yet that this is worth tuning further.
      **Correction, same day: +hi5567 was itself buggy and did NOT actually fix the oscillation —
      found by live re-verification against the installed package, not by re-reading the code.**
      Re-ran the exact same close-wall capture through the newly-installed `+hi5567` system
      package and gain was *still* swinging wildly (~1.3x–3.8x), even with `stepScale` bottomed
      out near its floor. A frozen-gain diagnostic (temporarily skip `updateExposure()`, just log
      the raw `exposureMSV` every frame while gain/exposure stay fixed) proved the raw scene
      signal itself is genuinely stable — a smooth ~5% drift over 7 seconds, no oscillation at
      all — which conclusively ruled out real environmental/lighting flicker as the cause and
      pointed straight back at the controller's own logic. Tracing actual logged deltas against
      the code found two real bugs: (1) the delta computation was scaled by `stepScale`, but the
      pre-existing "guarantee minimum progress" fallback (`if (delta < againMinStep) again -=
      againMinStep;`) was **not** — it always applied the full, fixed, unscaled `againMinStep`
      constant (1% of the sensor's whole gain range) once the damped delta shrank below it, which
      happens on essentially every correction once `stepScale` drops much below 1 — silently
      undoing all the damping and applying a full-size undamped step regardless of how small
      `stepScale` had become; (2) recovery was too eager — a *single* non-reversal reading (same
      direction as before, or landing inside the band by chance) was treated as full evidence of
      convergence, when on this scene a swing can pass straight through the satisfactory band in
      one sample while still very much oscillating (compounded by real feedback delay in the
      control loop — a commanded step doesn't fully show up in stats for a frame or two).
      **Fixed both**: scaled the minimum-step floor by `stepScale` too, and added
      `IPAActiveState::agc.stableCount`, requiring 4 consecutive non-reversal readings before
      growing the step size back rather than just one. Committed `026525a`. **Re-verified live
      against the same real close-wall scene, this time via the actually-installed system
      package** (not just the dev build): gain now settles within ~1s (a brief `stepScale` dip to
      0.5, smooth recovery to 1.0 as it genuinely stabilizes) and holds rock-steady at a single
      value for a full 30-second capture — previously it never stopped oscillating for any
      duration tested, at any `stepScale`. hi556 re-confirmed unaffected (stepScale never leaves
      1 on a normal scene). Shipped as `+hi5568`, installed and verified end-to-end through the
      real PipeWire/WirePlumber path. **Lesson for future sessions, worth remembering**: "the
      code should now damp this" and "it actually converges on real hardware" are different
      claims — the first shipped version looked correct by construction and passed a narrower
      live test, but only re-testing against the *installed* package on the *same real scene* at
      full duration caught that a safety-net fallback was quietly defeating the whole fix. Don't
      declare a control-loop fix verified from a single short capture or from reasoning about the
      code alone; watch it hold steady for the full expected duration, ideally through the actual
      shipped artifact, before calling it done.
- [x] **AGC metering aimed far too bright (washed-out / blown highlights) — root-caused and
      FIXED 2026-07-24, shipped as `+hi5569`.** With the oscillation fixed, the user reported the
      rear camera still looked "hot" — large areas burned out to pure white on an ordinary desk
      scene. Measured rather than eyeballed, via a new tool `scripts/agc-analyze-exposure.py`
      (stdlib-only P6 PPM parser; reports mean output luma, percentiles, and clipped fraction of
      captured frames): the settled image had **79.7% mean output luma with 30.6% of the frame
      clipped to pure white** — genuinely, measurably overexposed, not a matter of taste.
      **Root cause, two compounding mechanisms, both real bugs:** (1) `Agc` aimed the mean sample
      value at the *middle of the histogram range* (`kExposureOptimal = kExposureBinsCount/2`, a
      mean of 40% of full scale). That is the correct target for a perceptually-coded signal, but
      `SwStatsCpu` builds the histogram directly from **raw Bayer samples, which are linear** —
      gamma is applied later, in `DebayerCpu`'s LUT (`swstats_cpu.cpp:188` fills the histogram
      from raw r/g/b; `debayer_cpu.cpp:827` computes `gamma(raw * gain)`). Aiming a *linear* mean
      at the middle of its range puts the *encoded* mean far above the middle (~66% by the gamma
      curve alone). (2) The **AWB gains are applied after the point the statistics are measured**,
      so the pixel that reaches the screen is brighter than the sample AGC metered, by the
      luma-weighted mean of those gains — green is pinned at 1.0 and R/B are scaled up to meet it
      (`awb.cpp:93`), so that factor is always ≥1, and it differs per sensor and per illuminant
      (measured 1.28 on s5k3j1, 1.23 on hi556). **Confirmed by a real target sweep** (temporary
      env-var override, 9 settings, capturing and measuring real output at each): clipping fell
      monotonically 33.4% → 4.5% → 1.9% as the target dropped 2.5 → 1.4 → 1.2, exactly as the
      mechanism predicts. **Fix**: derive the target from the level the *output* should sit at —
      `kOutputLinearTarget = 0.18`, the classic 18% mid-grey, which maps to ~46% after gamma 2.2 —
      and fold in the luma-weighted AWB gain so the output mean lands on target regardless of what
      AWB settled on. Clamped to `[1.2, old target]`: the upper bound means it can never aim
      *brighter* than before (bounding regression risk), the lower bound keeps the "too dark"
      branch reachable since MSV bottoms out at 1.0 against a ±0.2 band. Measured on settled
      captures, both cameras: s5k3j1 **79.7%/30.6% clipped → 59.6%/0.33%**; hi556
      **59.6%/0.36% → 41.0%/0.00%**. Both converge without hunting (the damping fix above still
      holds), and the derived target differs between them (1.21 vs 1.23) purely from their
      different AWB gains — the intended per-sensor adaptation, achieved with no per-sensor
      constant. Committed `2618932`. **A highlight-protection constraint was built and then
      deliberately dropped** — worth recording so it isn't re-attempted blindly: clipping on these
      scenes is **per-channel** (warm light drives red into saturation while luminance stays
      modest), and the raw *luma* histogram cannot see it. Measured directly: on the desk scene the
      histogram topped out at bin 21 of 64 — predicting zero clipping — while 2% of output pixels
      were genuinely clipped. Doing it properly needs **per-channel histograms, or a post-gain
      clipped count, added to `SwIspStats`**; that's the concrete follow-up if highlight protection
      is wanted later. **Known characteristic, not chased**: hi556 now settles a little on the dark
      side on a low-contrast scene (41% mean, highlights only reaching p99=226, i.e. unused
      headroom) while s5k3j1 sits at 59.6% — both are within normal spread for mean-based metering
      on different scene content, and the pair averages ~50%, but if the front camera reads too dark
      in practice the single knob is `kOutputLinearTarget`.
      **Superseded same day by a per-camera knob, and CONFIRMED BY THE USER.** A single shared
      constant turned out not to suit both sensors: at the value putting `hi556` at a proper ~50%
      mean, `s5k3j1` clipped ~11% of the frame; at the value keeping `s5k3j1` clean, `hi556` sat at
      ~38% and looked visibly dim. Measured A/B on one scene also showed 0.18 and 0.22 are
      indistinguishable on `hi556` (37.8% vs 37.5%) because the ±0.2 MSV deadband absorbs a change
      that small — worth remembering before tuning this by small increments again. Fixed properly by
      giving `Agc` an `init()` that reads an optional `exposureTarget` from the tuning file (the
      pattern `BlackLevel` already uses for `blackLevel`), clamped to a sane range, defaulting to the
      derived value for any sensor that doesn't set one. Set per camera from measured captures:
      `hi556` 0.34, `s5k3j1` 0.22 — both then land ~48–57% mean. Committed on the `hi556` branch and
      shipped as `+hi5570`. **User confirmation, 2026-07-24: "Both cameras look the best they have
      ever looked."** Retuning either camera is now a YAML edit
      (`/usr/share/libcamera/ipa/simple/{hi556,s5k3j1}.yaml`) plus a pipewire/wireplumber restart —
      no rebuild — though a package upgrade overwrites them.
      **Remaining known gap, user-reported same day: autofocus is slow — "not production ready, but
      it does eventually get there."** Expected: this is pure contrast-detection hill-climbing with
      no PDAF (dead end on this kernel, see the AF TODO), so it physically steps the lens and waits
      for settle at each position; measured ~29s full convergence. That is the next obvious
      image-quality item after the `.aiqb` work, and is tracked in the autofocus TODO below rather
      than here.
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
      **Superseded live 2026-07-27** (not yet packaged/changelog-bumped) by 6 real
      per-illuminant matrices extracted from `HI556_1BG502T3_ADL.aiqb` — see
      `docs/aiqb-cmc-dump-findings.md` and the extraction tool, `scripts/aiqb-dump-cmc.c`.
      Confirmed genuine improvement on skin tone and clothing colour (the original motivating
      complaint — red shirt rendering orange — user-confirmed fixed). **But a real, measured
      defect was found in the same pass**: a green cast on neutral surfaces (wall, saturation
      ~0.2-0.23 vs ~0.05 on a reference Logitech shot) and magenta clipping on blown highlights
      (a sun-on-fabric highlight measured `RGB(255,201,255)` — R/B clip before G catches up).
      Root-caused via live `LIBCAMERA_LOG_LEVELS=IPASoftAwb:DEBUG,IPASoftCcm:DEBUG` logging
      (see the temporary debug line added to `ccm.cpp`): AWB converges normally mid-range
      (~5067K, not an out-of-range clamp), but the new CCM's much larger off-diagonal
      coefficients amplify small AWB gray-world residuals by roughly 2.4x (worked the algebra:
      a small deficit δ in R/B relative to G becomes roughly `+0.7δ` in G and `-1.7δ`/`-1.6δ` in
      R/B at the output) — a structural gap between AIQ's real-illuminant-keyed calibration and
      libcamera's 1D-colour-temperature-only interpolation, not a bad file or wrong module.
      **User's call, 2026-07-27**: keep it live despite the known defect — net improvement on
      the axis that matters most day-to-day (skin/clothing) outweighs the neutral-surface/
      highlight regression. Not yet packaged into a `.deb`/changelog entry pending that
      decision being made durable (see chat).
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
      **Re-enabled live 2026-07-27** (not yet packaged/changelog-bumped) with 7 real
      per-illuminant matrices extracted from `s5k3j1sx04_CJALR11_ADL_PDAF_T2.aiqb` — see
      `docs/aiqb-cmc-dump-findings.md`. This is real vendor calibration data, not ad-hoc
      measurement, so the lesson above doesn't block re-attempting — but **module ID is still
      NOT confirmed** for this physical unit; `CJALR11` is the scoping doc's size-based best
      guess, sharing identical CCM data with the `1BAA02T3` candidate, while two other
      candidates give measurably different matrices. Same net result as the `hi556` re-tune
      done the same day: real improvement on skin/clothing colour, and the same green-cast/
      magenta-highlight-clip defect, more pronounced here since this file's matrix coefficients
      are larger in magnitude. User is evaluating live; upstream submission decision (and the
      module-ID EEPROM read, see the scoping doc's open question 1) both still pending.
- [ ] **Extract real IQ tuning (CCM, then LSC) from the Intel AIQ `.aiqb` binaries instead of
      ad-hoc measurement — SCOPED 2026-07-24, Phase 1 (extractor) DONE 2026-07-27, CCM live on
      both cameras for evaluation (see the `hi556`/`s5k3j1` CCM entries above and
      `docs/aiqb-cmc-dump-findings.md`). LSC (Phase 4) not started.**
      Prompted by the rear-camera CCM having been measured by hand and reverted the same day
      (`+hi5566`) because two paper samples under one lighting condition didn't generalise, and
      reinforced 2026-07-24 by the user observing a red shirt rendering orange on `hi556` while a
      Logitech C925e renders it correctly. **Key finding from reconnaissance: this is NOT a
      reverse-engineering project.** The struct definitions (`ia_cmc_types.h`), the parser API
      (`ia_cmc_parser.h`) and a *working parser library* (`libia_cmc_parser-ipu6epmtl.so.0`, symbols
      confirmed via `nm -D`) are all already on disk in `~/work/intel/ipu6-camera-bins/`, from
      Intel's own open-source IPU6 release — so the job is "link Intel's parser and print the
      structs", not "decode a format". `ia_cmc_t` exposes `cmc_parsed_color_matrices` (per-illuminant
      3x3 CCMs with light-source type, sensor chromaticity and CIE coordinates — a real
      multi-illuminant calibration) and also `cmc_parsed_lens_shading`, i.e. LSC tables, which is the
      biggest remaining visual-quality gap since the soft ISP has no lens shading correction at all.
      Verified it maps cleanly onto libcamera: `ccm.cpp` already selects by interpolated colour
      temperature (`ccm_.getInterpolated(ct)`) and the tuning-file format is exactly a list of
      `{ct, 3x3}` nodes, while the application point matches too (CCM on linear data after AWB gains,
      before gamma — `debayer_cpu.cpp:807`/`:827`). Container format decoded far enough to
      sanity-check (`CPFF` magic, `LCMC`/`DFLT`/`AIQB` records, embedded build date and `IQStudio`
      /`LibIQ` provenance) but deliberately no further, since the vendor parser does the real work.
      **Biggest open question: which `.aiqb` is this unit's** — the middle filename token
      (`CJALR11`, `1BAA01T3`, ...) is a module ID and the wrong module's calibration is no better
      than a guess; best lead is the sensor EEPROM at I2C `0x50`, never read by any Linux driver
      here, which doubles as the parser's second (`nvm`) argument. **Also unresolved and worth
      deciding early: licensing.** These are proprietary Dell/Intel blobs; extracting values for this
      machine is one thing, shipping them upstream is another, and this project's stated goal is real
      upstream submission. Note Intel ships no `s5k3j1` `.aiqb` at all, so the Dell blob is the only
      source for the rear camera and always will be; for `hi556` Dell's copy is also newer than
      Intel's (build dates `22122113` vs `22032407`). Full plan, phases, risks and file inventory in
      the scoping doc.
- [ ] **Real closed-loop autofocus for the rear camera — scoped 2026-07-22, working hill-climb
      prototype validated against real hardware with AGC locking (2026-07-23), and Phases 2 AND 3 of the
      in-tree libcamera integration now built, committed, and validated end-to-end on real hardware
      (2026-07-23) — the rear camera does real continuous autofocus in libcamera's soft ISP.**
      **2026-07-23
      correction, read first**: every AGC-related claim below dated 2026-07-22 (the "AGC confound eliminated, no
      locking needed" conclusion in particular) was measured against a local libcamera dev build
      that hadn't been recompiled since 2026-05-26 and was silently missing the 2026-07-22 AGC
      gain-floor fix (`75b4474`) — gain reading exactly `1.000000` on every single frame all day
      wasn't clean convergence, it was that bug (gain stuck at the floor). Caught when the user
      observed real oscillating gain live in GNOME Snapshot (the correctly-built system package)
      on an out-of-focus scene — behavior the stale dev build literally could not produce.
      Rebuilt and re-confirmed gain now moves for real; a ~2.5-minute re-test found one real
      transient instability event but hasn't yet reproduced the *sustained* oscillation the user
      described watching live — that gap is still open. **Re-ran the full continuous sweep against
      the corrected build and got a real answer, not just a caveat**: gain does not stabilize
      within any practical scan duration on this scene — a first attempt (`SETTLE_TIME=2.5s`,
      the script's default) looked unstable through positions 0–256 then rock-steady after, which
      looked like "just needs more settle time," but an 8-second-settle retest showed gain still
      drifting smoothly (a roughly monotonic ~8.5% decline) across the *entire* ~27s sweep with no
      point at which it truly stopped. So the fix isn't a longer wait — it's explicit AGC locking
      during a scan or normalizing the sharpness metric by the gain in effect per sample, an
      actual design change not yet built. Every AGC-specific number from 2026-07-22 (metric
      comparison peaks, hill-climb convergence positions) should be treated as measured under
      contaminated conditions; the search *methodology* (settle detection, coarse+fine scan,
      monitor+hysteresis) is unaffected since it doesn't depend on AGC behaving. Full account in
      `docs/autofocus-cdaf-scoping.md`'s genuine-unknown 4. Full history, decisions,
      architecture options, and a 4-phase roadmap are all in `docs/autofocus-cdaf-scoping.md` —
      kept as the single source of truth for this effort rather than duplicated here. Summary
      (AGC-related parts of which are now superseded by the correction above):
      Phase 0 (`scripts/af-sweep-measure.sh`, per-position `cam` relaunch) hit a confounded
      dataset (AGC state leaking across positions) and a real `/dev/media0` numbering bug (fixed
      in both that script and `dell-xps9315-test-rear-dual.sh`); Phase 1 fixed the confound with
      a continuous-session harness (`scripts/af-continuous-sweep.sh`/`af-analyze-continuous.py`)
      and, along the way, corrected an earlier wrong settle-time guess (real range: instant to
      ~870ms, not "~1 frame") and caught a real metric-correctness bug (`scripts/af-compare-
      metrics.py` + direct visual inspection of frames found Laplacian variance's claimed peak
      was actually blurrier than Tenengrad's on the glare-heavy test scene — switched the
      default metric). The actual hill-climb controller (`scripts/af-hillclimb-prototype.py`)
      is built and works: coarse+fine search with settle detection (not a fixed delay),
      continuous monitor-and-rescan (not converge-and-stop, per the "zero app cooperation"
      decision), validated with 5 repeated convergence trials landing within one fine-step of
      each other and a working jolt-detect-recover cycle. **Confirmed on a second scene**
      (futon/door/cat-tree, no glare confound): Laplacian variance and Tenengrad now agree
      closely, confirming the wall scene's metric disagreement was specific to its glare
      problem, not a general Laplacian-variance flaw. That run also caught a real coarse-vs-
      fine-scan discrepancy at the same nominal position (~20% sharpness difference on a
      revisit) traced to a transient scene disturbance (someone walking through frame during
      the scan), not a hardware or algorithm bug — but it's a real robustness gap worth fixing
      (single-sample coarse-scan winners aren't re-confirmed before committing to a fine-search
      window). **Separately, and unrelated to the AF work itself: a real, now-fixed WirePlumber
      camera-enumeration race was found and resolved 2026-07-23.** The rear camera had stopped
      showing up in PipeWire's device list (`wpctl status`) — user reported it wasn't working
      even before this session started, and specifically raised (reasonably) whether the
      2026-07-22 rear-camera CCM revert had broken more than just the color tuning, or whether
      that same morning's software update was responsible. **Both ruled out with direct
      evidence**: `src/ipa/simple/data/s5k3j1.yaml` in `~/work/git-ubuntu/libcamera` is
      byte-for-byte identical to its state right after S5K3J1 support was first added (`git
      diff 4b111cf -- src/ipa/simple/data/s5k3j1.yaml` is empty) — the CCM add+revert was
      tested live and reverted before ever being committed, so nothing was lost; only the
      changelog *text* documenting that history got bundled into a later, unrelated commit
      (`0edde37`, message explains this explicitly). And `/var/log/apt/history.log` shows
      that morning's update touched krb5, tar, a gstreamer point-release, gnome-session, and
      unrelated packages — none of `pipewire`/`wireplumber`/`libcamera`/the kernel, and no
      reboot had happened since the previous day. **Actual root cause, found directly in
      WirePlumber's own journal** (`journalctl --user -u wireplumber`): `ERROR MediaDevice
      media_device.cpp:848 /dev/media1[intel-ipu6]: Failed to setup link 'Intel IPU6 CSI2
      1'[1] -> 'Intel IPU6 ISYS Capture 8'[0]: Device or resource busy`. libcamera's camera
      manager enumerates cameras once at startup; if the IPU6 media-graph link is held by
      anything else (e.g. a concurrent `cam` test process, plausibly from this session's own
      testing, or something else on a boot before this session existed) at that exact moment,
      the rear camera's registration fails silently with no visible symptom anywhere except
      that one buried journal line, and it stays missing for the rest of that WirePlumber
      session — explaining both today's specific instance and plausibly the general flakiness
      going back further. **Fixed**: `killall -9 cam` (ensure nothing else holds `/dev/media1`)
      then a clean `systemctl --user stop wireplumber pipewire pipewire.socket` → `start` cycle;
      confirmed via `wpctl status` showing `s5k3j1 [libcamera]` / `Built-in Back Camera` as a
      real source, and via a clean WirePlumber journal with the `Adding camera
      '\_SB_.PC00.LNK0'` line completing normally this time. User confirmed Snapshot sees the
      rear camera now. **Not yet done**: this is a timing race, not eliminated — it can
      presumably recur if WirePlumber (re)starts while something else holds `/dev/media1`; no
      permanent fix (e.g. a startup retry/backoff in WirePlumber's camera monitor, or ensuring
      test scripts never leave `cam` running across a wireplumber restart) has been
      investigated. **AGC lock built and validated for both scripts, 2026-07-23**:
      `af-continuous-sweep.sh` and `af-hillclimb-prototype.py` both now default to `--lock-agc`
      (pre-warm with real Agc briefly, remove `Agc:` from the local dev build's tuning file only,
      re-assert the pre-warmed exposure/gain, restore on exit, self-healing if a prior run got
      SIGKILLed mid-edit). Locked sweep spread dropped to 4% (from 7–16% contaminated); locked
      hill-climb converged near the same region the clean sweep found and held within 0.5–1.8%
      during monitoring, the tightest quiet-hold result yet. Also fixed a real, separate bug
      surfaced while testing this: `cam` occasionally drops a frame's file write, and the old
      frame-watcher deadlocked forever waiting for that exact missing sequence number — now skips
      ahead. **One genuinely new, unresolved finding**: 5 repeated locked convergence trials landed
      far less tightly (`[720, 624, 864, 880, 880]`, stddev 104) than the earlier *unlocked* result
      (stddev 7.8) — not a regression, the opposite: the old tight clustering was itself a
      contamination artifact, and with it removed this wall scene's true focus response looks like
      a broad, shallow plateau (matching the clean sweep's 4% total spread) rather than one sharp
      peak, so a grid search legitimately lands on different nearby points run to run. **Resolved,
      same day**: repeated the identical 5-trial locked test on the futon scene (43% dynamic range,
      clear single peak) — positions `[544, 528, 512, 512, 512]`, stddev 12.8, range 32, dramatically
      tighter than the wall scene's stddev 104. Confirms convergence consistency tracks the scene's
      real focus signal strength, not anything about the lock or search algorithm — not a defect, a
      quantified, scene-dependent property to remember when judging any future convergence number in
      isolation. Secondary, unexplained observation: converged sharpness *values* declined somewhat
      across the 5 futon trials (15.0M→13.1M over ~3 min) — plausibly lighting drift or session-to-
      session pre-warm variation, neither confirmed, doesn't affect the position-consistency finding.
      **Phase 2 in-tree plumbing built + committed 2026-07-23 (Opus), code-complete, builds clean,
      hardware validation pending** (`~/work/git-ubuntu/libcamera` `hi556` branch, 7 files, +119
      lines, `ninja -C build` clean, mojom regenerated and verified; commits `169d683` sharpness
      statistic + `11a61f8` lens control/FocusFoM wiring): a dedicated rpi-style `setLensControls(ControlList)`
      signal added to `soft.mojom`'s `IPASoftEventInterface` (Open Question #4 decided — dedicated
      signal, not the ipu3 extend-`setSensorControls` pattern), wired IPA→`SoftwareIsp`→
      `simple.cpp`→`focusLens()->setFocusPosition()` mirroring the existing `setSensorControls`
      chain and `ipu3.cpp`/`pipeline_base.cpp` lens patterns; a new `uint64_t sharpness` field on
      `SwIspStats` accumulated in `swstats_cpu.cpp`'s per-line macros (sum of squared horizontal
      green gradients — a subsampled Tenengrad cousin, the metric Phase 1 settled on); `FocusFoM`
      advertised in `ipaControls` and reported per-frame from that stat; and an env-gated
      (`LIBCAMERA_SOFT_AF_DEBUG_POS`) validation scaffold that emits a fixed focus position through
      the new IPC path (inert by default, replaced by Phase 3's `Af`). **Both halves validated end-to-end on real
      hardware 2026-07-23 — Phase 2 DONE.** One dev-build `cam` run proved it: the lens moved
      `focus_absolute` 100 → 800 driven purely by `LIBCAMERA_SOFT_AF_DEBUG_POS=800` (IPA emits
      `setLensControls` → IPC → `SimpleCameraData::setLensControls` → `focusLens()->
      setFocusPosition`), and `FocusFoM` showed real varying values (84M→87M→62M→39M as the lens
      defocused the scene) in `cam --metadata` from the new `SwIspStats::sharpness` field.
      **Retraction (documented, not silently fixed)**: an intermediate check that day concluded the
      sensor↔lens ancillary link was missing and the lens half was blocked kernel-side — WRONG, a
      `media-ctl` false negative. `media-ctl` 1.32.0 doesn't print `MEDIA_LNK_FL_ANCILLARY` links
      and an entity's "N links" count is pad links only, so `lc898217 1-0072` showing `0 link` meant
      nothing. `MEDIA_IOC_G_TOPOLOGY` (ctypes ioctl, `scratchpad/topo.py`) shows the link plainly:
      `247 (s5k3j1 1-0010) -> 253 (lc898217 1-0072)`. Kernel side was correct all along
      (`v4l2_fwnode_reference_parse`'s `fwnode_property_get_reference_args` DOES fall through to the
      swnode secondary — `property.c:610-617`). Lesson: never infer ancillary-link presence from
      `media-ctl`; query the topology ioctl or let libcamera (which parses ancillary links at
      `media_device.cpp:764`) judge. Full design notes +
      validation procedure (media-ctl ancillary-link check, `FocusFoM` metadata sweep,
      `LIBCAMERA_SOFT_AF_DEBUG_POS` lens-move test) in `docs/autofocus-cdaf-scoping.md`'s Phase 2
      "Built 2026-07-23" note. **Phase 3 (the real `Af` algorithm) built, committed (`46b8669`), and
      validated on hardware 2026-07-23.** `src/ipa/simple/algorithms/af.{h,cpp}` is a `libipa`
      `Algorithm` following `agc.cpp`'s shape, enabled by `- Af:` in `s5k3j1.yaml`: reads
      `SwIspStats::sharpness`, runs a coarse+fine hill-climb with Phase 1's settle detection
      (N consecutive stable readings, frame-budget timeout) and a scene-relative re-scan threshold
      (fraction of the converged peak's prominence, floored so a flat scene doesn't hunt), then
      holds and monitors. Search state lives in `Af` members; only the desired position + an
      `applyLens` flag cross to the IPA via `IPAActiveState::af`, which `processStats()` reads to
      emit `setLensControls`. `Af` now owns `FocusFoM` and reports `AfState`; the Phase 2 debug
      scaffold was removed in the same commit. **Validated with `cam --metadata` (no app, no
      trigger, no debug env)**: the lens autonomously swept a full coarse scan, fine-scanned around
      the winner, and **converged to 752 and held rock-steady for 21s with no false re-triggers**
      (right in the 640–784 region every Phase 1 wall-scene run found); `AfState` went
      `Scanning`→`Focused`. **Notable**: this ran with AGC *unlocked* and still converged cleanly —
      so the plan's conditional AGC-coordination task was empirically checked and isn't needed for
      convergence (left unimplemented; an `activeState.af.scanning` freeze flag is the obvious
      refinement if a harder scene ever needs it). **App-level demo set up + proven through the real
      PipeWire path 2026-07-23**: Snapshot uses pipewire→*system* libcamera, so a temporary systemd
      user drop-in (`~/.config/systemd/user/{pipewire,wireplumber}.service.d/dev-libcamera.conf`)
      points both at the dev build (`LD_LIBRARY_PATH` dev `src/libcamera`+`base`,
      `LIBCAMERA_IPA_MODULE_PATH` dev `src/ipa/simple`, `LIBCAMERA_DISABLE_IPU6_PDAF=1`) — system
      package is `0.7.0-1ubuntu3+hi556`, same ABI, and the dev IPA signature matched so it ran
      in-process (verified via `/proc/<pid>/maps`). Proven by streaming node 110 "Built-in Back
      Camera" with `gst-launch-1.0 pipewiresrc target-object=111 ! videoconvert ! fakesink` (same
      path as Snapshot): the lens autonomously swept coarse+fine and converged to 784, identical to
      the direct-`cam` run. Drop-in left in place for the user to open Snapshot and watch it focus;
      revert = delete the two `.conf` files + `daemon-reload` + restart pipewire/wireplumber.
      Remaining: user's visual confirmation in the Snapshot GUI, convergence-speed tuning (~29s
      slow), AGC freeze-during-scan if needed, and productionizing the dev build into an updated
      `+hi556` `.deb` so Snapshot uses it without the drop-in. PDAF context (dead end on this
      kernel, WIP archived in `~/work/git-ubuntu/libcamera` branch `pdaf-sideband-wip`) is preserved
      in that doc rather than here.
      **2026-07-24 — PDAF re-assessed, and the effort estimate revises DOWN substantially. The
      only genuine blocker is the kernel routing restriction; the algorithm is already written.**
      Prompted by asking how much better PDAF would be than the shipped CDAF. Checked rather than
      assumed, and the assumption that "there is no PDAF implementation in the available Linux code
      base" is **wrong**: `src/ipa/rpi/controller/rpi/af.cpp` in the very libcamera tree this project
      already builds is a complete, mature, **hybrid PDAF+CDAF** autofocus, BSD-2-Clause, from
      Raspberry Pi Ltd. Its own header states the design: "a hybrid of CDAF and PDAF, favouring
      PDAF... When PDAF confidence is low (due e.g. to low contrast or extreme defocus) or PDAF data
      are absent, fall back to CDAF with a programmed scan pattern... The scan may terminate early
      if PDAF recovers." The data contract is small — `src/ipa/rpi/controller/pdaf_data.h` defines
      `PdafData { uint16_t conf; int16_t phase; }` (phase S.11.4 fixed point) delivered as a grid
      via `RegionStats<PdafData>`. **Key detail that lowers the calibration barrier**: rpi's tuning
      exposes `pdafGain` — "coefficient for PDAF feedback loop" — plus `pdafSquelch`, `confThresh`,
      `confEpsilon`, `dropoutFrames`, i.e. they run a *proportional feedback loop* and iterate rather
      than doing one calibrated defocus→position jump. So precise per-module PDAF calibration is not
      a prerequisite to get something working; a tuned gain is. (The per-module calibration does
      plausibly live in the `.aiqb` files — note the rear camera's are named `..._PDAF_T2.aiqb` —
      which ties this to the `.aiqb` extraction item above.) PDAF also appears in the Intel HAL
      (`AiqCore.cpp`, `PlatformData`) but that is plumbing only, with the real phase processing
      inside the closed `libia_aiq`; and our own `s5k3j1.c` already carries dual-stream
      `get_frame_desc` PDAF support kernel-side. **Net**: the remaining work is a PAF sideband data
      path (kernel `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1` restriction, still the hard blocker) plus
      delivering `PdafRegions`-equivalent data into the soft-ISP IPA — *not* designing an AF
      algorithm, since a working license-compatible one is in-tree. **Estimated payoff, from this
      project's own measured numbers**: current CDAF does ~18 lens moves at ~1.5s each (settle plus
      4 stable readings) for ~29s total; PDAF collapses that to one measurement, one move and a
      confirmation — order 0.5–1.2s, i.e. ~25–50x, with the floor set by lens mechanics (settle
      measured up to ~870ms) rather than by computation. Bigger precision win is on low-contrast
      scenes, exactly where CDAF is measurably worst here (repeated-trial stddev 104 on the flat
      wall vs 12.8 on the textured futon scene). Caveats: low light hurts PDAF more than CDAF
      (phase pixels are partially masked), and porting `af.cpp` must preserve Raspberry Pi Ltd's
      copyright and say so explicitly, per this file's Attribution section. These convergence
      figures are reasoned estimates from measured settle/reading times, **not** measured PDAF
      results — nothing here has been run on this hardware.
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
- [ ] **Camera naming inconsistency (`hi556` vs `Built-in Back Camera`) — root-caused 2026-07-24,
      small upstreamable kernel fix, not yet written.** User noticed the front camera shows as the
      bare driver name while the rear shows a friendly name. **Not a distro naming convention and
      not a libcamera/PipeWire issue** — `cam`'s `cameraName()` builds the name from
      `properties::Location` ("Internal front camera" / "Internal back camera") and *only* falls
      back to the model string when Location is absent. Location is absent for `hi556` because
      **mainline `hi556.c` never calls `v4l2_fwnode_device_parse()` /
      `v4l2_ctrl_new_fwnode_properties()`**, so it exposes neither `V4L2_CID_CAMERA_ORIENTATION`
      (0x009a0922) nor the rotation control — libcamera says so explicitly at probe: "Recommended
      V4L2 control 0x009a0922 not supported" / "The sensor kernel driver needs to be fixed" /
      "Failed to retrieve the camera location". Our `s5k3j1.c` *does* make both calls
      (lines 1763-1769), which is the entire reason the rear camera gets a friendly name. **The data
      is already available**: `ipu-bridge.c` parses `rotation` and `orientation` from ACPI
      SSDB/`_PLD` and attaches them to every sensor it instantiates (see its `.rotation`/
      `.orientation` property names and `ipu_bridge_parse_orientation()`), so `hi556.c` simply drops
      properties that are already being handed to it. **Fix is ~8 lines** in `hi556_init_controls()`
      after the existing `ctrl_hdlr->error` check, mirroring `s5k3j1.c`. Attractive upstream
      candidate: no DMI/HID gating needed since this is a missing standard call rather than a
      platform quirk, it fixes rotation as well as location, and it benefits every `hi556` machine on
      every distro (confirmed by the user to look the same on Ubuntu and Fedora live images, which
      run the same mainline driver). **Verify before assuming the result**: that this machine's
      `_PLD` for `\_SB.PC00.LNK2` actually reports a front panel position - if `_PLD` is missing
      `ipu_bridge_parse_orientation()` warns and falls back to a default, which would yield a wrong
      or still-absent location. Purely cosmetic - the camera works correctly either way.
      **VERIFIED 2026-07-24 and patch drafted (`docs/hi556-camera-orientation.patch`), not yet built
      or tested.** Read `_PLD` at runtime via `acpi_call` (the static DSDT buffer is only a
      placeholder - the method patches byte 8 from the NVS globals `L0PL`/`L2PL`, which the BIOS
      fills at boot and which are never assigned in the DSDT). Runtime result: **LNK0 byte 8 =
      `0x69` -> panel 5 = Back, LNK2 byte 8 = `0x61` -> panel 4 = Front** (panel is bits 3-5). LNK0
      decoding to Back independently validates the bit arithmetic, since that is the value the rear
      camera already demonstrably resolves to. So the ACPI data is correct and present, and
      `hi556.c` is simply discarding it - the patch will work. Repro for the check:
      `sudo modprobe acpi_call && echo '\_SB.PC00.LNK2._PLD' | sudo tee /proc/acpi/call && cat
      /proc/acpi/call`. **Remaining work**: `hi556` is a *stock* module this project has never built
      out-of-tree, so testing needs it set up as a 6th out-of-tree module (copy from
      `~/work/git-ubuntu/resolute` at the matching tag, add to `install-custom-modules.sh`) plus a
      reboot, per the testing-methodology note above.
- [ ] **Privacy/indicator LED never lights for the rear camera — root-caused 2026-07-24, not
      fixed.** User: on Windows the white camera indicator lights for both front and back cameras;
      on Linux only for the front. **This is a real gap in Linux's TPS68470 support, not just our
      board data.** The two cameras take different INT3472 paths: the front `hi556` hangs off a
      *discrete* `INT3472:02`, and mainline's `int3472/discrete.c` understands
      `INT3472_GPIO_TYPE_PRIVACY_LED` (maps it to a `privacy-led` con_id and drives it with sensor
      power) — so the front LED works. The rear `s5k3j1` hangs off the **TPS68470 PMIC**
      (`INT3472:07`, an I2C/MFD device), and the TPS68470 path has **no privacy-LED concept at all**
      — grepping `drivers/platform/x86/intel/int3472/` for `PRIVACY_LED` hits only `discrete.c`.
      Our `tps68470_board_data.c` GPIO lookup table for `i2c-INT346D:00` accordingly declares only
      `reset` and `powerdown`; there is nothing to add a third entry *to*, since no consumer exists.
      **Unknown, and the next thing to establish**: which TPS68470 GPIO (if any) is physically wired
      to the rear indicator. Windows lights it, so a software-controllable path must exist. Two
      routes: (a) Ghidra the Windows TPS68470/camera driver the way the VCM identity was settled, or
      (b) empirically toggle the unused TPS68470 GPIOs and watch for the LED — cheap, but note the
      unused lines may control rails or straps, so treat it as a real experiment rather than a
      poke-and-see. Worth doing properly: **an indicator that stays dark while a camera is capturing
      is a privacy failure, not a cosmetic difference**, which is the argument for matching Windows'
      behaviour rather than treating "the LED belongs to the front camera" as equally valid. A fix
      would be genuinely upstreamable (privacy-LED support for the TPS68470 path benefits every
      TPS68470 camera platform, not just this model), and would need the LED wired to sensor
      power/streaming state the way `discrete.c` does it, not toggled ad hoc.
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
- [x] Decide eventual upstream submission targets — resolved by actually doing the
      real-lineage fork, not just deciding: `ipu-bridge.c`/`tps68470_board_data.c`/
      `ipu6-isys-csi2.c` now live as real commits on a `resolute` fork
      (`~/work/git-ubuntu/resolute`, branch `dell-xps9315-2in1`); `s5k3j1.c` on a real
      `intel/ipu6-drivers` fork (`~/work/intel/ipu6-drivers`, branch
      `dell-xps9315-s5k3j1`). **Real, valuable side-finding**: real upstream Ubuntu
      already has its own S5K3J1 SAUCE patch (`3c095f789fe1`, Intel's Jimmy Su) with
      the exact same wrong 848MHz link-frequency bug this project found and fixed —
      our fix is genuine feedback against a real, named engineer's patch, not just a
      personal workaround. Full detail in `~/.claude/plans/final-refinement-pass-for-glimmering-squid.md`
      (Part 2.2) and the `project-s5k3j1-kernel-fork-surgery` memory. Still pending:
      creating the actual GitHub repos, pushing, and wiring them into this repo as
      submodules (needs the user's go-ahead per the "review before push" convention).
- [x] `~/work/git-ubuntu/resolute` is a working, exact-tag-matched clone of the
      canonical Ubuntu kernel git tree (now at `Ubuntu-7.0.0-28.28`, matching the
      currently running kernel; updated 2026-07-29, was `27.27`). It supersedes the
      old apt-source tree for anything needing precise upstream comparison, since
      apt-source snapshots are easy to let go stale silently (which is what happened
      before). This was the rebase target for the item above.

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
