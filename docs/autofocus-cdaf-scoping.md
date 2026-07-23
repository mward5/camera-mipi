# Real closed-loop autofocus (CDAF) for the rear camera — scoping plan

**Status (2026-07-23): Phase 0/1 prototyping is well underway with real
hardware results** — a working coarse+fine hill-climb with settle detection
and continuous monitor/recovery, validated on two scenes. **Read this
notice before trusting any AGC-related claim in this document dated
2026-07-22**: everything measured that day (the "AGC confound eliminated,
no locking needed" conclusion, and everything downstream of it) was run
against a stale local libcamera build that turned out to be missing the
AGC gain-floor fix, making gain appear artificially frozen rather than
genuinely converged. Found and corrected 2026-07-23 — see genuine unknown
4 below for the full account. The *search methodology* (settle detection,
coarse+fine scan, monitor+hysteresis) is unaffected; the *AGC-specific*
conclusions are not yet re-validated against the corrected build.

## Why this is next

The kernel side is done: the rear `s5k3j1` sensor streams real frames (25 fps,
corruption bug fixed 2026-07-21 — see `STATUS.md`), and the `lc898217` VCM driver
(`drivers/lc898217/lc898217.c`) exposes `V4L2_CID_FOCUS_ABSOLUTE` (0–1023) and
physically moves the lens, confirmed on real hardware. What's missing is an
*autofocus algorithm* — something that reads frames, computes a focus metric, and
drives that control — which lives in userspace/libcamera, not the kernel driver.

PDAF (phase-detection AF, using the sensor's dual-stream PAFi sideband path) is a
confirmed dead end on this kernel: `intel_ipu6_isys`'s
`v4l2_subdev_routing_validate()` is called with `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1`,
which explicitly forbids the one-sink-to-many-source routing PDAF sideband capture
needs. See `STATUS.md`'s PDAF history for the full kernel-side investigation (not
repeated here). A WIP userspace-side PDAF attempt (dual-stream CSI2 routing in
`SimpleCameraData`/`SimplePipelineHandler`) existed uncommitted in
`~/work/git-ubuntu/libcamera`'s `hi556` branch; confirmed 2026-07-22 it's inert on
this kernel (`discoverIp6PdafSideband()` never finds a matching CSI2 entity in the
current media graph, not just blocked at the final routing-config step) and
archived rather than deleted, to a local branch `pdaf-sideband-wip` (based off
`hi556`, single commit `a6a3a29`) — worth checking before starting PDAF from
scratch if `intel-ipu6-isys` ever grows real multi-stream routing support, since
the rear camera's `.aiqb` (`s5k3j1sx04_CJALR11_ADL_PDAF_T2.aiqb`) confirms Windows
does real PDAF capture on this sensor, so the hardware capability is real and the
kernel routing restriction is more likely a driver gap than a hardware ceiling.
**CDAF (contrast-detection: a sharpness metric + hill-climb on `focus_absolute`)
is the only tractable approach for this scoping effort.**

## Current pipeline

The active stack is libcamera's `simple` pipeline handler + software ISP
(`IPASoft`, no dedicated ISP hardware). Relevant facts, confirmed by reading the
project's local libcamera checkout (`~/work/git-ubuntu/libcamera`, which already
carries an `s5k3j1`-specific tuning file and a couple of local patches — not a
stock upstream tree):

- `IPASoftSimple` (`src/ipa/simple/soft_simple.cpp`) already uses the same
  `libipa::Algorithm<Module>` plugin architecture as `rkisp1`/`ipu3`/`rpi`
  (`src/ipa/libipa/algorithm.h`, `module.h`). Active algorithms are declared
  per-sensor in `src/ipa/simple/data/s5k3j1.yaml`: `BlackLevel`, `Awb`, `Ccm`
  (disabled), `Adjust`, `Agc` — implementations in
  `src/ipa/simple/algorithms/*.{h,cpp}`.
- Per-frame flow: `queueRequest()` → `computeParams()` (calls `algo->prepare()`)
  → `processStats()` (calls `algo->process()`, then emits `setSensorControls`) —
  all in `soft_simple.cpp`.
- `src/libcamera/pipeline/simple/simple.cpp` currently does **zero lens wiring**
  (`grep -n "Lens\|focus\|Focus"` returns nothing). Lens control plumbing exists
  generically elsewhere (`CameraLens::setFocusPosition()` in
  `src/libcamera/camera_lens.cpp:87`, reachable via
  `CameraSensor::focusLens()`), and other pipeline handlers already use it —
  `src/libcamera/pipeline/ipu3/ipu3.cpp:1209-1218` and
  `src/libcamera/pipeline/rpi/common/pipeline_base.cpp:872,1258-1264` are the
  working reference patterns — but the `simple` pipeline just never hooked it up.
- `struct SwIspStats` (`include/libcamera/internal/software_isp/swisp_stats.h`)
  has exactly two fields today: a global `RGB<uint64_t> sum_` and a single
  64-bin luminance histogram. **No sharpness/gradient/windowed-region data
  exists.** It's populated by `src/libcamera/software_isp/swstats_cpu.cpp`,
  whose per-line accumulators (e.g. `statsBGGR8Line0`) deliberately subsample —
  stride `x += 4`, sampling one 2×2 Bayer block per 4, plus row-skipping via
  `ySkipMask_` — for CPU-cost reasons. A Laplacian/Tenengrad-style sharpness
  metric wants a dense local neighborhood, which this sparse access pattern
  doesn't provide for free.
- `include/libcamera/ipa/soft.mojom`'s `IPASoftEventInterface` (lines 34-37)
  declares exactly three signals: `setSensorControls`, `setIspParams`,
  `metadataReady`. **No `setLensControls` signal exists**, unlike
  `include/libcamera/ipa/raspberrypi.mojom:285`, which declares one explicitly.
- The controls are *not* a blocker: `src/libcamera/control_ids_core.yaml` already
  defines `AfMode`/`AfState`/`AfRange`/`AfSpeed`/`AfMetering`/`AfWindows`/
  `AfTrigger`/`AfPause` (~lines 804-1146), `LensPosition` (line 1025), and
  `FocusFoM` (line 655 — an int32 "in-focus" figure-of-merit explicitly
  decoupled from any specific stats hardware, well suited to a software CDAF
  metric). They just aren't advertised by `IPASoftSimple::init()` yet
  (`ipaControls` built at `soft_simple.cpp:181` from `context_.ctrlMap`).

On the kernel side, `drivers/lc898217/lc898217.c`'s `focus_absolute` control is
**write-only and fire-and-forget**: `lc898217_set_ctrl()` (line 193) does a
synchronous I2C write to the DAC register (`lc898217_set_dac()`, line 89) and
returns immediately — no move-complete or busy signal is exposed to userspace.
The chip's real position/status register (`0x0A`, meant to be read twice 2ms
apart to detect "still settling", per the reverse-engineered Windows protocol —
see the file's own comment at lines 59-66 and
`docs/vcm-investigation-lc898217.md:109-119`) is deliberately not implemented.
**Lens physical settle time after a `focus_absolute` write is completely
unmeasured.**

## Architecture options

### Option A — in-tree `libipa::Algorithm` (the real long-term architecture)

Add `src/ipa/simple/algorithms/af.{h,cpp}`, an `Af` class following the same
`ipa::soft::Algorithm` base as `Agc`/`Awb`/`Blc`/`Adjust`, declared in
`s5k3j1.yaml`'s `algorithms:` list, driven every frame through the same
`prepare()`/`process()` cycle.

This requires two real, independent plumbing sub-projects to land *before any AF
logic can run at all*, because the data path it needs doesn't exist:

1. **Stats extension.** Add a sharpness/gradient field to `SwIspStats`, and
   implement its accumulation in `swstats_cpu.cpp`. `Af::process()` only sees a
   `const SwIspStats *` (per `IPASoftSimple::processStats()`,
   `soft_simple.cpp:309-323`) — no direct pixel access. Either extend the
   per-line accumulators with a denser sampling path just for this metric (extra
   CPU cost, unmeasured), or approximate from the existing sparse samples
   (accuracy unknown — this is one of the things Phase 1 below needs to answer).
   `SwStatsCpu` already supports one `Rectangle window_` (`setWindow()`), reusable
   as a single AF ROI — not the multi-region grid `AfWindows` implies, so treat
   multi-region AF as out of scope unless this later proves necessary.
2. **IPA IPC extension.** Extend `soft.mojom` with a lens-control signal (two
   real precedents differ: rpi's dedicated `setLensControls(ControlList)`
   signal vs. ipu3's pattern of adding a second `ControlList lensControls`
   parameter onto the existing per-frame signal, `ipu3.cpp:1204-1219` —
   **recommend the rpi-style dedicated signal for clarity**, but this is a
   judgment call, see Open Questions). Requires mojom codegen regeneration
   (`utils/codegen/ipc/generators/mojom_libcamera_generator.py`, meson-driven).
   Then wire `simple.cpp` from scratch: acquire `sensor_->focusLens()`, connect
   the new signal to a slot calling `CameraLens::setFocusPosition()` — following
   `ipu3.cpp:1205-1218` or `pipeline_base.cpp:1258-1264` as the template.

Reference algorithms exist but aren't directly reusable, only structurally
instructive:
- `src/ipa/ipu3/algorithms/af.cpp` — same `Algorithm<Module>` base, clean
  coarse/fine hill-climb (`afCoarseScan()`/`afFineScan()`/`afScan()`,
  `kCoarseSearchStep=30`/`kFineSearchStep=1` at lines 69-70,
  `afEstimateVariance()` at line 357 for the contrast metric, driving a raw
  0–1023 VCM range — same numeric range as this project's `focus_absolute`) —
  but reads `ipu3_uapi_stats_3a::af_raw_buffer`, dedicated IPU3 hardware AF-grid
  stats that don't exist here.
- `src/ipa/rpi/controller/rpi/af.cpp` — fuller reference (scan state machine,
  parabola peak fit, dioptre→raw-position `Pwl` mapping curve) but also depends
  on dedicated hardware focus-region stats.

**Cost profile: high effort before anything is observable.** Two plumbing
changes (a shared-memory stats-struct change plus an IPC codegen change) must
land and be verified correct before the hill-climb algorithm can be exercised
even once — and none of the real unknowns below get answered along the way.

### Option B — standalone userspace prototype (outside the IPA)

A small out-of-tree tool that:
- Drives the lens directly via `v4l2-ctl -d <lc898217 subdev> -c
  focus_absolute=<N>` (the exact invocation already verified working, per
  `STATUS.md`), located via `media-ctl -e "lc898217 1-0072"` — same pattern
  `scripts/dell-xps9315-test-rear-dual.sh` already uses for other entities.
- Captures frames via the existing `cam` CLI (already used by
  `scripts/dell-xps9315-test-rear-cam.sh`), which supports `--capture=N`,
  `--file=` with `#`-expansion for frame sequence, and `--metadata` for
  per-frame `ControlList` dumps (exposure/gain as computed by the real AGC) —
  no libcamera code changes needed to drive it repeatedly.
- Computes a sharpness/contrast metric on the *decoded output frame* in an
  external analysis script (Python/numpy, or similar) — completely outside
  libcamera's stats path.
- Implements the hill-climb loop itself in userspace glue code, logging every
  (position, metric, timestamp, exposure, gain) tuple for offline analysis.

`src/py/libcamera` Python bindings exist as a meson option (`pycamera`) but are
not currently built in this project's `build/` dir — avoid that dependency for
now and drive `cam` as a subprocess instead, to keep Phase 0/1 simple.

**Cost profile: low effort, fast iteration, zero risk to the working
kernel/libcamera trees**, and it directly produces answers to every unknown
below, using real hardware and real frames, before any IPA/mojom/stats-format
code is written.

### Recommendation: **B first, feeding into A**

Option A's first deliverable milestone is two plumbing sub-projects that are
pure engineering risk with zero empirical payoff — they don't tell you anything
about settle time, metric choice, usable range, or AGC interaction. Every
tuning constant an in-tree `Af` algorithm needs (step sizes, timing, metric
choice) is currently a guess. Option B lets those constants be derived from
logged real data, iterating fast (no IPA rebuild/reflash/mojom-regen per
experiment), before they're hardcoded into IPA code that's much more expensive
to iterate on.

Trade-off, stated explicitly: Option B produces no shippable feature by itself
(a research/measurement tool only, no app ever sees automatic focus from it),
and it doesn't validate final in-pipeline CPU cost or the exact accuracy of
whatever sparse-sampling approximation Option A's stats extension ends up using.
It de-risks the *algorithmic and hardware-timing* unknowns; it does not remove
the need for Option A's plumbing work.

## Genuine unknowns (measure, don't guess)

1. **Lens physical settle time after a `focus_absolute` write.**
   **Measured 2026-07-22** (see Phase 1's stationary re-run below) — and the
   answer is more complicated than a single number. For a constant 64-unit
   step, observed settle time ranged from effectively instant up to ~870ms
   depending on the specific transition, with at least one transition
   showing an overshoot/ringing pattern before settling. Not simply
   proportional to step size (step size was held constant across the whole
   test) — plausibly genuine position-dependent VCM mechanical behavior. A
   fixed short per-step delay is not a safe design for a real hill-climb;
   see Phase 1's writeup for the full data and the practical implication
   (settle-detection via consecutive-stable-frames, not a fixed delay, is
   the safer design — possibly reviving the kernel driver's unimplemented
   `GetStatus` busy signal, open question 5). **Not yet tested**: whether
   settle time actually scales with step size (only 64-unit steps tried so
   far) or whether the variability is purely transition/position-specific
   regardless of distance moved.
2. **Which sharpness metric actually works on real frames from this sensor.**
   **Measured 2026-07-22** (see Phase 1's metric-comparison results below) —
   Laplacian variance and Tenengrad were compared on the same dataset and
   they disagreed sharply on where the peak was; settled by looking at the
   actual images, not trusting either number. **Laplacian variance was
   actually wrong** on the test scene (a glare/hotspot-heavy wall), not just
   noisier — its claimed peak was visibly blurrier than Tenengrad's. Switched
   the hill-climb prototype to Tenengrad. **Not fully resolved**: only tested
   on one scene with a specific confound (large overexposed region); unknown
   whether Tenengrad's win generalizes or was specific to that glare problem,
   and whether restricting either metric to a well-exposed textured ROI
   (excluding saturated regions) would be a more fundamental fix than the
   choice of metric formula. `SwStatsCpu`'s sparse-sampling-compatible metric
   option from the original framing hasn't been evaluated at all yet.
3. **How 0–1023 maps to actual usable lens travel.** Unknown whether the lens
   hits hard mechanical/magnetic stops well short of the advertised range.
   Related but distinct from `docs/vcm-investigation-lc898217.md`'s still-open
   10-bit-vs-11-bit DAC question — if real hardware clips or wraps above
   `0x3FF`, that affects both `LC898217_MAX_FOCUS_POS` in the kernel driver and
   any AF algorithm's search range. Measure by sweeping the full range against
   a scene with real depth variation and plotting sharpness vs. position.
4. **Interaction with AGC during a scan.** `src/ipa/simple/algorithms/agc.cpp`
   runs its exposure/gain hysteresis loop with zero knowledge that a focus
   sweep might be in progress. Risks: exposure/gain drift changes the
   sharpness metric's scale between samples (corrupting hill-climb
   comparisons), or AGC visibly hunts at the same time as AF. Measure by
   logging exposure/gain alongside focus position and sharpness during a scan,
   to see whether AGC settles fast enough to be noise, or needs explicit
   locking — which has no existing mechanism (`soft_simple.cpp`'s
   `setSensorControls.emit()` on every frame, `soft_simple.cpp:339`, would
   keep re-overwriting any externally-forced exposure/gain value; whether
   that's actually true, or whether the AGC would just quietly re-converge to
   the same values, is itself worth confirming empirically in Phase 1 before
   assuming AGC-locking requires touching `agc.cpp`).

   **2026-07-22: root cause found, "resolved" for the static-scene case —
   2026-07-23: that resolution retracted, it was a measurement artifact of
   a stale build, not a real finding.** Phase 0's first attempt found
   exposure drifting 6.5× across a 16-position sweep with no genuine
   per-position convergence (see the per-position-process-relaunch
   explanation below, which is still correct and unaffected by this
   retraction). Phase 1's continuous-session harness then reported
   `ExposureTime`/`AnalogueGain` **identical across every single frame** of
   every sweep and hill-climb run for the rest of 2026-07-22 — gain read
   exactly `1.000000` on literally every frame captured that entire day,
   which was (wrongly) written up as "AGC confound eliminated, no locking
   needed."

   **What actually happened, found 2026-07-23**: the local libcamera dev
   build used for *all* of that testing (`~/work/git-ubuntu/libcamera/
   build`, driven via `LD_LIBRARY_PATH`/`LIBCAMERA_IPA_MODULE_PATH`
   overrides in every script) had not been recompiled since **2026-05-26**,
   while the source tree's git HEAD was at a 2026-07-22 commit. The single
   relevant commit in that gap: `75b4474` — the AGC gain-floor fix (see
   `STATUS.md`'s 2026-07-22 entry) — was sitting uncompiled in the tree the
   whole time. Every AF test that day ran the *pre-fix* AGC, whose
   documented failure mode is exactly "gain permanently sticks at the
   floor" — i.e. gain reading exactly `1.000000` on every frame wasn't
   evidence of clean AGC convergence, it was the bug. Discovered when the
   user, viewing the rear camera live through GNOME Snapshot (which uses
   the system-installed package, already correctly built), reported
   visibly oscillating gain/brightness on an out-of-focus wall — behavior
   my dev-build testing had never once shown, because it *couldn't*.
   Rebuilt (`ninja -C build`, confirmed via the reported git hash matching
   HEAD) and re-tested directly: gain now shows real movement (a defocused-
   wall test climbed `1.9375 → 2.53125 → 3.125` over ~4s, then a separate
   ~2.5-minute observation found one real transient event — gain dipped
   `3.125 → 2.5 → 1.875` then climbed back through several steps to a new
   steady value `2.4375` over ~2.7s, around 12s into that capture, with the
   remaining ~130s rock-steady) — confirming AGC genuinely can and does
   move now, unlike literally every reading from the previous day. **Not
   fully resolved**: this single transient is evidence of real instability
   but is not the same as the *sustained continuous* oscillation the user
   described watching live in Snapshot — that hasn't been reproduced yet in
   direct testing, so the gap between what's been measured and what was
   directly observed is still open, not explained away.

   **Practical fallout**: unknown 4 is back to genuinely open, and so is
   most of what Phase 1's write-up below claimed to have settled about AGC
   and, by extension, anything downstream that assumed a stable/flat
   exposure baseline (metric comparison, hill-climb convergence numbers).
   The *methodology* (continuous session, settle detection, coarse+fine
   search, monitor+hysteresis) is unaffected — none of that depends on AGC
   behavior being correct, only on frames existing — but every specific
   *AGC-related conclusion* from 2026-07-22 needs to be treated as
   unconfirmed until re-run against the corrected build. Not yet done this
   session; flagged here rather than silently re-validated, per this
   project's own standing practice of recording retracted findings rather
   than quietly overwriting them.

## Phased plan

### Phase 0 — instrument and measure (done: a first-draft script exists)

**Goal:** answer unknowns 1 and 3, and gather the raw data for unknown 4's
AGC-drift question. `scripts/af-sweep-measure.sh` sweeps `focus_absolute` in
configurable steps across 0–1023 via the `lc898217 1-0072` subdev, capturing a
burst of frames + `cam --metadata` output at each position, indexed by a
`sweep.csv`. `scripts/af-analyze-sweep.py` (a minimal early Phase 1 tool, PIL
only — no numpy on this box) computes a Laplacian-variance sharpness metric on
a central 800×800 crop of each frame to check whether a sweep's data actually
shows focus variation.

**Files touched:** `scripts/af-sweep-measure.sh`, `scripts/af-analyze-sweep.py`.
No libcamera/kernel changes.

**Run 2026-07-22 — real findings, dataset not yet clean enough to trust.**
First run hit an environment bug: the script (copying
`dell-xps9315-test-rear-dual.sh`'s convention) hardcoded `/dev/media0` for the
IPU6 controller, but on this boot a USB webcam took `/dev/media0` and pushed
IPU6 to `/dev/media1` — media device numbering isn't stable across boots.
Fixed by detecting the device by driver name (`intel-ipu6`) instead of
assuming a number; `scripts/dell-xps9315-test-rear-dual.sh` has the same
latent bug, not yet fixed there.

After the fix, a full sweep ran cleanly (16 positions, step 64, 6 frames/burst,
~3GB, no capture errors, lens position readback matched every write including
at the top of the range — no visible clipping at 1023 in this run, a small
data point for the still-open 10-bit/11-bit question). But
`af-analyze-sweep.py` surfaced two real confounds that mean **this dataset
can't yet answer unknown 3 (usable range) reliably**:
1. **Every burst's first frame is degenerate** (sharpness reads 0 at every
   single position, 16/16) — clearly systematic, not noise. Discard frame 0
   of any burst as a standing convention.
2. **AGC never reaches steady state per position, and visibly carries state
   across positions.** Exposure climbed monotonically from 344 (position 0)
   to 2250 (position 960) — a 6.5× drift — with gain pinned at 1.0. Inside a
   single burst (e.g. position 384: `689,689,689,689,689,757`) exposure sits
   flat for 5 frames then steps once at the end — the signature of AGC taking
   one slow, smoothed step per short-lived `cam` process invocation, inherited
   from whatever the *previous* position's process left in the sensor's
   hardware exposure register (a real V4L2 control, so it persists across
   process boundaries), not converging fresh each time. Mean sharpness then
   declines almost monotonically across the sweep with no peak-and-fall shape
   a real focus curve should have — consistent with the metric tracking
   exposure-driven brightness/motion-blur drift more than actual focus.

**Implication for the harness design, not yet built:** per-position
short-lived `cam` processes are the wrong methodology — AGC's convergence
rate is evidently too slow relative to a 6-frame burst, and the *inter*-burst
state leakage makes positions non-independent measurements. A clean re-run
needs a single continuous `cam`/capture session with focus_absolute changed
mid-stream (from a second concurrent process against the lens subdev, which
is a separate device node from the video capture node) rather than one
process per position — closer to how the real hill-climb algorithm would
operate anyway (see Phase 1 below, which should build this rather than the
Phase 0 script attempting it). Deferred rather than built this session — a
genuinely more involved harness (background process + concurrent focus
writes + timestamp correlation), better scoped as first-class Phase 1 work.

**Done when:** re-run with a continuous-session harness produces a sharpness-
vs-position curve with a real peak/fall shape, from which settle time and
usable range can be read off with confidence — **reached, see Phase 1's
2026-07-22 results below**, which built exactly that harness.

### Phase 1 — standalone CDAF prototype + hill-climb validation (Option B)

**Goal:** answer unknown 2 definitively, and validate a real closed-loop
**continuous** AF loop end-to-end against physical hardware (per the
2026-07-22 decision above — single-shot was rejected as impractical),
producing the tuning constants Phase 3's in-tree algorithm will need.

- Build a small analysis/control tool (language TBD — doesn't need to match
  libcamera's C++, this is throwaway research code) that reads Phase 0's
  dataset to compare candidate sharpness metrics, then drives a live
  coarse-then-fine hill-climb (loosely modeled on `ipu3/algorithms/af.cpp`'s
  `afCoarseScan()`/`afFineScan()`/`afScan()` shape, but calling `v4l2-ctl`
  directly instead of reading IPU3 hardware stats), using Phase 0's measured
  settle time to pace each step.
- Beyond a single converge-and-stop run: validate a **continuous** loop that,
  after converging, keeps monitoring the sharpness metric on live frames and
  only re-triggers a new scan once it's degraded past some threshold — and
  tune that threshold/debounce so a static scene doesn't visibly hunt. This is
  the part a single-shot design wouldn't have needed at all, so treat it as
  first-class validation work, not an afterthought once convergence works.
- Explicitly resolve the AGC-locking question from unknown 4 and record the
  answer plus the final metric/step-size/threshold choices — now more
  important given AF runs continuously, not just in discrete windows.

**Run 2026-07-22 — continuous-session harness built and validated; AGC
confound eliminated; a real (if noisy) focus curve obtained.**
`scripts/af-continuous-sweep.sh` replaces per-position `cam` relaunches with
one continuous background `cam` session (captured at 800×600 instead of full
sensor resolution — ~1.4MB/frame vs. ~33MB, confirmed the `simple` pipeline
honors `-s width=,height=,role=viewfinder` — so a real sweep stays a few
hundred MB) while this script writes `focus_absolute` from a concurrent
process against the separate lens subdev. `cam`'s own per-frame timestamps
turned out to be on a different clock epoch than `/proc/uptime` (~120s apart
on this boot — consistent with `CLOCK_MONOTONIC` vs. an uptime clock that
includes suspended time), so the script polls for the first frame and
calibrates a one-time offset rather than assuming the clocks match.
`scripts/af-analyze-continuous.py` correlates frames to positions via that
offset and computes Laplacian variance per frame.

Result, sweeping 0–960 (step 64, ~1s hold/position, 486 frames, 669MB, in
`~/work/af-sweep-data/run2-continuous`):
- **AGC confound gone**: `ExposureTime` read back **exactly 39184 on every
  single one of 486 frames**, the whole sweep through. Confirms the
  hypothesis from Phase 0's first run — AGC converges once during the
  settle window and, with a single continuous session instead of per-
  position process relaunch, has no reason to move again for a static scene.
  Unknown 4 (AGC interaction) is now resolved for the "hold a static scene"
  case: **no explicit locking mechanism is needed**, a continuous session is
  sufficient on its own. (Still open: behavior *during* an active scan, where
  the scene *is* changing frame-to-frame as focus sweeps — this run didn't
  test that, since AGC had already converged before the first focus write.)
- **A real sharpness signal, not just exposure/motion-blur noise**: mean
  sharpness spread across the sweep was 13% of average (vs. 104% in Phase
  0's confounded first run), and the curve has 3 sign changes (rises and
  falls, not monotonic) — peaking at position 640 (mean 1483.3). Take this
  specific peak position with real caution, though: single scene, single
  run, laptop handheld/resting rather than tripod-mounted, 800×600 not full
  resolution. It's evidence the metric and methodology now work, not yet a
  calibrated "this is where this scene focuses" constant.
- **Settle-time signal, inconclusive in this run** (handheld/resting laptop,
  not deliberately stationary) — see the corrected re-run below, done the
  same day once the laptop was set up stationary against a real test scene.
  The tentative "≲1 frame" read from this run turned out to be **wrong**,
  not just imprecise — worth recording plainly since it would have been an
  easy wrong number to carry forward into Phase 3's tuning constants.

**Run 2026-07-22, same day, corrected — laptop stationary, aimed at a wall
scene the user has used to demo AF on Windows** (`~/work/af-sweep-data/
run3-stationary`, same script/params, 0–960 step 64, 26 frames/position).
With handshake noise removed, the settle-time picture changes completely:

- **AGC finding reproduced exactly**: `ExposureTime` again identical
  (`39184`) on every frame of the whole sweep, same value as the previous
  run despite a different scene — further confirmation this is a solid,
  repeatable result, not a fluke.
- **A different peak, as expected for a different scene**: this wall sits
  best-focused around position 0–256 (flat, sharpest, mean ~1880) with a
  general decline through 320–960 (down to ~1690) — a real, physically
  sensible result (a nearer/farther wall than whatever was in frame during
  the first stationary run's scene), not a contradiction of the earlier
  peak-near-640 result. Confirms position→sharpness mapping is genuinely
  scene/distance-dependent, as it should be — there's no universal "best"
  `focus_absolute` value, which is exactly why a real hill-climb algorithm
  is needed rather than a fixed default.
- **Settle time, corrected and quantified**: per-position settle-frame index
  (first frame after which all remaining frames in that position's burst
  stay within 2% of the position's final mean), computed programmatically
  from `analysis.csv`:
  ```
  pos    settle_frame   ~ms     note
  0- 256, 384, 448        0       0    (sharpness barely differs from prior
                                        position - nothing to detect, not
                                        evidence of a fast physical settle)
  320                    22    ~873    slow, two-stage: flat -> partial drop
                                        -> further drop -> partial RECOVERY
                                        near the end of the 1s hold
  512                    21    ~834    same two-stage-then-recovery pattern
  576                    12    ~476    two-stage drop, no recovery this time
  640                     4    ~159    fast-ish, but still a real multi-frame
                                        transition, not instant
  704                    17    ~675    dramatic: jumps well ABOVE both the
                                        previous and final steady value for
                                        several frames before dropping back
                                        down - looks like real overshoot/
                                        ringing, not just noise
  768                     3    ~119    fast settle
  832-960                 0       0    (again, minimal sharpness change to
                                        detect)
  ```
  **The earlier "≲1 frame" read from the noisy handheld run was wrong, not
  just imprecise.** For the same 64-unit step size, settle time ranges from
  effectively instant up to ~870ms depending on the specific transition, with
  at least one case (704) showing what looks like genuine mechanical
  overshoot/ringing before settling — a real design hazard: a hill-climb
  loop that samples immediately (or even a few hundred ms) after a move can
  read a transiently wrong sharpness value, especially right after a larger
  jump. Since step size was held constant (64) across all of these, the
  variability isn't explained by move distance alone — plausibly genuine
  VCM mechanical behavior (backlash/hysteresis/resonance can be
  position-dependent for voice-coil motors), though this run can't fully
  rule out some of it being a fixed IPU6/libcamera pipeline latency riding
  along with the true physical delay (the correlation is between a
  `v4l2-ctl` write's timestamp and a frame's arrival timestamp, which
  necessarily includes some capture-pipeline latency on top of any real lens
  motion) — a constant pipeline latency alone wouldn't explain why some
  transitions show `settle_frame=0` and others ~870ms, so the *variability*
  is real regardless, even if the *absolute* numbers have some fixed offset
  baked in.
  **Practical takeaway for Phase 3's tuning constants**: this run's
  `HOLD_TIME=1.0s` provided enough margin for every observed transition to
  fully settle (even the slowest, ~870ms, stabilized before the 1s window
  ended) — but that's uncomfortably close to the observed worst case, not a
  comfortable safety margin. A real hill-climb loop should not use a fixed
  short per-step delay; it should either use a generous fixed delay (on the
  order of 1s+, expensive for scan speed) or — better — watch for N
  consecutive frames within a tolerance band before trusting a sample,
  exactly the kind of settle-detection logic `docs/vcm-investigation-
  lc898217.md`'s undocumented `GetStatus` protocol was hypothesized to help
  with (open question 5 above) — this result makes that kernel-driver
  extension look more worth doing than "conditional/deferred," though still
  not proven necessary until a real hill-climb is built and a fixed-delay
  approach is shown to be too slow or unreliable in practice.

**Not yet done, natural next steps**: test AGC behavior *during* an active
scan (not just before one, which both runs so far tested); repeat the
settle-time measurement with a smaller step size to see whether variability
scales with distance or is truly position/transition-specific; compare
Laplacian variance against Tenengrad on the same dataset (unknown 2 asked
for a comparison, only one metric has been tried so far); investigate
position 704's overshoot pattern specifically, ideally with finer time
resolution (higher frame rate or a smaller/faster stream config) than this
~25fps 800×600 setup provides.

**Files touched:** `scripts/af-continuous-sweep.sh` + `scripts/af-analyze-
continuous.py` (sweep/measure only), and now `scripts/af-hillclimb-
prototype.py` (the actual control loop, below) — all in `scripts/`, all
committed. No libcamera/kernel changes.

**Run 2026-07-22, later same day — hill-climb control loop built and
validated end-to-end against real hardware.** `scripts/af-hillclimb-
prototype.py` is a live, interactive controller (not a fixed schedule like
the sweep scripts): it runs one continuous `cam` session (`--capture` with no
count = stream until interrupted), polls for each new frame by expected
filename as it's written (simpler than the sweep scripts' clock-correlation
trick, since here the controller itself issues every focus write and can
timestamp with its own clock directly), and drives:
- A coarse-then-fine search (coarse step 96, fine step 16 by default,
  structurally modeled on `ipu3/algorithms/af.cpp`'s two-phase scan).
- **Settle detection instead of a fixed delay** at every step: waits for N
  (default 4) consecutive frames within a tolerance band (default 2%) of
  each other before trusting a reading, capped by a timeout — directly
  applying the corrected settle-time finding above rather than the
  originally-guessed fixed delay.
- After converging, a **continuous monitor loop** (not converge-and-stop):
  periodically takes another short settled reading and compares it to the
  converged baseline; two consecutive degraded readings (hysteresis against
  single-reading noise) trigger a fresh coarse+fine scan. This is the
  "continuous AF, zero app cooperation" design decision made concrete — it
  runs and re-converges on its own, no external trigger involved.
- A scripted self-test jolt partway through the monitor phase (deliberately
  writing a bad position, simulating something knocking focus off) so the
  recovery path gets exercised on every run without needing a human to
  change the physical scene mid-test.

**Result, run against the same stationary wall scene**: coarse+fine scan
converged to position 720 (sharpness 1515.2, a real plateau — neighboring
fine samples 688/704/720/736 all landed within ~1% of each other, 1517–1534).
The monitor loop held quietly for the pre-jolt period (readings within ~1.4%
of baseline the whole time — no false triggers, confirming the hysteresis
design works). The jolt (forced to position 0) produced a consistent ~5–7%
sharpness drop; **a first run at the default 10% threshold didn't trigger** —
real, useful calibration data, not a bug: this scene's overall sharpness
dynamic range across the whole 0–1023 sweep is only about 16% (coarse-scan
min 1289 to max 1538), so a jolt to a moderately-bad-but-not-worst position
didn't cross a 10% bar. A re-run at 5% (chosen because the steady-state
noise floor measured well under 2%, so 5% has real margin above noise while
still being small enough to catch a real but moderate disturbance) triggered
correctly on the 2nd consecutive degraded reading and re-converged — this
time landing on position 784 (sharpness 1479.7), not exactly the original
720. **Not a bug**: the coarse scan's own data shows 672–864 is a broad,
gently-varying plateau (coarse readings 1505–1529 across that whole span),
not a sharp single-valued peak, so which exact position a grid-based
coarse+fine search lands on within a wide plateau is sensitive to noise and
grid alignment between runs — worth knowing as a real property of this
search strategy (repeatable *quality*, not always the exact same *position*,
on a scene with a broad rather than sharp focus response), not treated as a
defect.

**Practical tuning takeaway**: `--degrade-threshold` should be set relative
to the *actual scene's* sharpness dynamic range and the measured noise
floor, not left at an arbitrary default — 10% was too conservative here.
Phase 3's real implementation should likely compute a threshold as a
fraction of the *converged* peak's own prominence (e.g. relative to the gap
between the converged sharpness and the coarse scan's minimum sampled value)
rather than a single hardcoded constant, since that dynamic range clearly
varies by scene (this run: ~16% end-to-end swing; the earlier sweep runs
implied similar-magnitude ranges — no scene tested so far has shown a huge,
easy-to-threshold swing).

**Run 2026-07-22, later same day — metric comparison finds Laplacian
variance was actually WRONG on this scene, not just noisy; switched to
Tenengrad and the results got dramatically cleaner.** `scripts/af-compare-
metrics.py` computed both Laplacian variance and a Tenengrad-style
gradient-energy metric (Sobel Gx/Gy, squared, summed — approximate, clips at
255/pixel before combining, no numpy on this box) on the same `run3-
stationary` frames already on disk, no new capture needed. The two metrics
disagreed sharply: Laplacian variance's mean-sharpness peak was at position
0–256; Tenengrad's was at 640–704. **Settled by looking at the actual
frames, not by trusting either number**: converted representative PPMs
(positions 0, 256, 640, 704, 960) to PNG and inspected them directly.
Positions 0 and 256 are visibly blurry (soft, thick grid lines on the wall's
grid pattern); 640 and 704 are visibly crisp (thin, well-defined lines) —
**Tenengrad's peak matches reality; Laplacian variance's claimed peak does
not.** Root cause, plausible: this scene has a large overexposed glare/
hotspot (a bright reflection or light source) plus a noisy background, and
naive full-frame Laplacian variance (PIL's `FIND_EDGES`, no ROI exclusion)
is dominated by that rather than the in-focus grid-line texture — the
metric was measuring something real, just not focus.

**This retroactively casts doubt on every specific converged-position number
reported above from the Laplacian-variance-based runs** (720, 784, etc.) —
the search *algorithm* (coarse+fine, settle detection, monitor+hysteresis+
recovery) is still validated as mechanically sound, since it's metric-
agnostic, but its *specific numeric outputs* on this scene, from before this
fix, shouldn't be trusted as ground truth. (As it happens, those runs'
Laplacian-variance coarse scans did *also* score 640–720 above position 0
internally — e.g. run5's coarse scan read 1529.0 at 672 vs. 1429.0 at 0 —
so they likely converged to a real-enough sharp region rather than a
completely wrong one; but the absolute values were unreliable enough, and
disagreed enough between separate sessions on presumably the same physical
setup — run3's position-0 mean was 1878, run4/run5's were 1429–1449, a >25%
gap — that this shouldn't be relied on as confirmation.)

**Fixed**: `scripts/af-hillclimb-prototype.py` now uses the same Tenengrad
metric as the default (import note: still an approximation, not a
mathematically pure Tenengrad, and still not proven to be *the* right choice
in general — only proven more trustworthy than Laplacian variance *on this
scene*, via direct visual inspection, which is the standard any future
metric change should be held to as well). Re-ran the full converge/monitor/
jolt/recover cycle with the fix: coarse+fine scan now produces a clean,
textbook single-peaked curve (rises smoothly to a peak at 704, falls away on
both sides — compare the earlier Laplacian-variance runs' noisier, multi-
bump shapes), and **converged to the exact same position (704) both before
and after the jolt-triggered re-scan** — notably more repeatable than the
Laplacian-variance run's 720-then-784 result. Monitor-phase noise floor and
jolt detection behavior both still worked correctly with the new metric.

**Run 2026-07-22, later still — 5 repeated convergence trials, a real
success-rate number.** Ran `af-hillclimb-prototype.py` 5 times back-to-back
(`--monitor-seconds 0`, convergence only) against the same wall scene:
converged positions were `[720, 704, 720, 704, 720]` — mean 713.6, stddev
7.8, i.e. **every single trial landed within one fine-step (16 units, ~1.6%
of the full range) of the same point**, alternating between two adjacent
grid samples of what the earlier visual check confirmed is the real sharp
plateau. 5/5 "success" by the obvious definition (converged near the known-
good region, no wild outliers, no failures to converge). One real
operational finding along the way, not about the algorithm: the first
attempt at this run hit a robustness gap — an external `timeout 60` killed
a slow trial via `SIGTERM`, which bypasses Python's `finally:` cleanup
(unlike `SIGINT`), leaving the background `cam` process holding the camera
device open and breaking the next trial with "no frames arrived". Not a bug
in the AF logic itself, but worth remembering for any future orchestration
around this script: give it enough time budget, and don't rely on an
external hard-kill for normal-path cleanup.

**Run 2026-07-22, later still — second scene (no glare confound), metrics
agree, and a real transient-disturbance finding.** User repositioned the
camera to a normal indoor scene with real depth (a futon, a door, a cat
tree) and no dominant overexposed hotspot, specifically to test whether
Tenengrad's win over Laplacian variance on the wall scene generalizes or was
specific to that glare problem.

- `af-continuous-sweep.sh` + `af-analyze-continuous.py`: a textbook clean
  result — sharpness rises smoothly from position 0 to a peak at 448, falls
  away smoothly through 960, only 1 sign change, 43% dynamic-range spread
  (much larger than the wall scene's 11–16% — this scene has real depth
  variation to work with). `af-compare-metrics.py`: **Laplacian variance and
  Tenengrad now agree closely** (peaks at 448 and 512 respectively — one
  fine-step apart, both clean unimodal curves) — confirming the wall scene's
  disagreement was specific to its glare/hotspot confound, not a general
  flaw in Laplacian variance. Visual spot-check (converted representative
  frames to PNG, looked directly): position 0 and 960 are visibly blurry,
  448 is clearly sharp — matches both metrics.
- Ran `af-hillclimb-prototype.py` (Tenengrad) against this scene: coarse
  scan found a rising trend toward the high end, peaking at 864 (14.3M) —
  but the **fine scan's own revisit of position 864, moments later, read
  only 11.85M**, ~20% lower than the coarse pass's reading of the *same
  nominal position*. Converged at 768 (11.1M) — a real position, but
  noticeably below the coarse scan's own peak reading. Investigated by
  pulling the actual frames from both the coarse-pass and fine-pass reads of
  position 864 and looking at them directly: the coarse-pass frame is
  visibly sharper (crisp chair detail, clear picture-frame edges) than the
  fine-pass frame (soft, blurry) — a real difference, not just numeric
  noise. **Root cause: the user confirmed they likely walked through the
  camera's field of view during the coarse scan** — a transient scene
  change, not a lens or metric problem. (An initial hypothesis worth
  recording as *ruled out* rather than repeating the mistake of chasing it
  further, per this project's own convention of documenting dead ends: VCM
  positional hysteresis — the same commanded DAC value reproducibly landing
  at a different physical position depending on approach direction/history —
  was considered, since it's a real phenomenon in voice-coil actuators and
  would have been a novel, useful finding if true. The mundane explanation
  fits the evidence just as well and is far more likely, so this wasn't
  pursued further, but it's worth revisiting *if* a similar discrepancy ever
  shows up on a verified-static scene.)
- **Real design implication, independent of the specific cause**: a coarse-
  then-fine grid search has no defense against a single transient outlier
  sample steering it toward the wrong region — here it cost some quality
  (768 vs. the scene's real ~448-peak-equivalent-region for this framing)
  but didn't fail outright, since the fine scan's own internally-consistent
  data still picked a locally-reasonable point. A more robust design would
  re-confirm a candidate coarse-scan winner with a second read before
  committing to a fine-search window around it, rather than trusting a
  single sample. Also revealed a real instrumentation gap: `hillclimb-
  trace.csv` doesn't log exposure/gain per frame (only sharpness), which
  would have helped distinguish "scene motion" from "AGC drift" faster
  without needing to pull and visually compare frames by hand — worth adding
  before the next round of testing.

**Done when:** the tool reliably converges focus across multiple real scenes
with a documented, repeatable success rate, **and** demonstrates stable
continuous operation (re-scans when the scene/focus genuinely changes, stays
quiet on a static scene) over an extended run, not just a single convergence
— **reached for two scenes now**: wall scene had 5/5 repeated convergence
trials within one fine-step, plus quiet-hold and jolt-recovery; futon scene
confirmed metric agreement without the glare confound and produced a real
(if externally-disturbed) convergence run. **Not yet done**: repeated trials
and a jolt-recovery test on the second scene (only wall scene got that
depth of testing so far), and the still-open items below.

**Not yet done, natural next steps**: test AGC behavior *during* an active
scan (not just before one); repeat with a smaller step size to see whether
settle-time variability scales with distance; make the degrade-threshold
scene-relative rather than a fixed constant (see above); add exposure/gain
logging to `hillclimb-trace.csv`; add a re-confirmation read before
committing to a fine-search window, to harden against transient disturbances
like the one found above; repeated trials and jolt-recovery testing on the
second scene, matching the depth already done on the wall scene; consider
restricting any future metric to a well-exposed, textured ROI (excluding
saturated regions) as a more fundamental robustness improvement than metric
choice alone.

### Phase 2 — in-tree `soft.mojom` + `SwIspStats` plumbing (Option A, part 1)

**Goal:** land the two prerequisite plumbing changes with no AF logic yet —
verify the pipes work with a trivial/manual payload first.

- Extend `include/libcamera/ipa/soft.mojom`'s `IPASoftEventInterface` with the
  lens-control signal (see Open Questions #4 for the shape decision),
  regenerate IPA proxy/skeleton code.
- Wire `src/libcamera/pipeline/simple/simple.cpp` to connect it to a slot
  calling `CameraSensor::focusLens()->setFocusPosition()` (pattern:
  `ipu3.cpp:1205-1218` or `pipeline_base.cpp:1258-1264`). Validate with a
  manual/hardcoded test emission — confirm the lens moves through the new IPC
  path, distinct from the direct-V4L2 path Phases 0/1 used.
- Extend `SwIspStats` with a sharpness field (global scalar first, reusing
  `SwStatsCpu`'s existing `window_`/`setWindow()` as the AF ROI; defer
  multi-region `AfWindows` support), sized/shaped per Phase 1's metric
  decision, implemented in `swstats_cpu.{h,cpp}`.
- Advertise `FocusFoM` in `IPASoftSimple::init()`'s `ipaControls` map
  (`soft_simple.cpp:180-181`) as a smoke test that the new field flows
  end-to-end.

**Files touched:** `include/libcamera/ipa/soft.mojom`,
`include/libcamera/internal/software_isp/swisp_stats.h`,
`src/libcamera/software_isp/swstats_cpu.{h,cpp}`,
`src/libcamera/pipeline/simple/simple.cpp`, `src/ipa/simple/soft_simple.cpp`.

**Done when:** a manually-triggered lens move via the new IPC signal works
end-to-end through the real pipeline handler (not just direct V4L2), and a
real sharpness value from live frames is visible in `SwIspStats`/`FocusFoM`
metadata — with no hill-climb logic yet, proving the plumbing independently of
the algorithm.

### Phase 3 — real `Af` algorithm class (Option A, part 2)

**Goal:** port Phase 1's validated **continuous** algorithm into the in-tree
`Algorithm<Module>` structure, running automatically with zero app
cooperation required (per the 2026-07-22 decision above) — the same way
`Agc`/`Awb` already run on every frame today with no app involvement.

- Add `src/ipa/simple/algorithms/af.{h,cpp}` implementing `prepare()`/
  `process()`/`configure()`/`queueRequest()` as needed, following `agc.h`/
  `agc.cpp`'s shape (closest existing example of a per-frame stats-driven
  algorithm in this IPA — `ipu3`/`rpi`'s `af.cpp` are algorithmically similar
  but built around hardware stats this path doesn't have).
- Port Phase 1's continuous monitor-and-rescan loop (not a one-shot
  converge-and-stop), reading the new `SwIspStats` sharpness field and
  emitting the new `setLensControls` signal instead of direct V4L2 writes.
  **Default the algorithm to always running** — it must not require an app to
  write `AfTrigger` (which stays internal-only per Open Question #2) to do
  anything at all.
- If Phase 1 found AGC-locking necessary, implement it via shared
  `IPAContext`/`IPAFrameContext` coordination between `Af` and `Agc` — a new
  touchpoint, not present today.
- Register `Af:` in `s5k3j1.yaml`'s `algorithms:` list; keep
  `AfMode`/`AfState`/etc. internal/debug-only per Open Questions #2 (no
  app-facing control contract yet).

**Files touched:** new `src/ipa/simple/algorithms/af.{h,cpp}`,
`src/ipa/simple/algorithms/meson.build`, `src/ipa/simple/data/s5k3j1.yaml`,
`src/ipa/simple/soft_simple.cpp` (control advertisement), possibly
`src/ipa/simple/algorithms/agc.{h,cpp}` and shared context/module headers if
AGC coordination is needed.

**Done when:** an app with zero AF-awareness — GNOME's Camera/Snapshot app is
the concrete target, not just `cam`/`scripts/dell-xps9315-test-rear-cam.sh` —
shows continuously-in-focus rear-camera video with no control writes from the
app at all, matching or exceeding Phase 1's measured continuous-operation
reliability (converges on real changes, stays quiet on a static scene).

## Open questions (decide explicitly, don't drift into an answer)

1. **Decided 2026-07-22: continuous AF is the actual goal, not single-shot.**
   Original recommendation (scope to single-shot/triggered AF only, treat
   continuous as a later non-goal) was rejected — single-shot AF isn't
   practical for real-world use (a laptop's rear camera is a live, moving
   scene; nobody's going to press a trigger control before every shot). This
   changes the shape of Phases 1 and 3 non-trivially, see the updates to those
   sections below: the algorithm needs a "monitor current focus quality, only
   re-scan when it's degraded enough to be worth the disruption" loop, not
   just a single converge-and-stop hill-climb, and needs hysteresis/debounce
   tuning to avoid visibly hunting on a static scene. AGC interaction (unknown
   4 above) also gets more important, not less — AF is now running literally
   all the time instead of during discrete triggered windows.
2. **Decided 2026-07-22 (no objection to the recommendation): keep
   `AfTrigger`/`AfState`/`AfMode` internal/debug-only through Phase 3**, full
   app-facing control exposure deferred to a later effort.
3. **Decided 2026-07-22, and combines with #1 and #2 into the core design
   requirement: AF must work with zero app cooperation.** For this to be
   useful at all, a client that has no idea `Af` controls exist — today's
   GNOME Camera/Snapshot app, or the plain `cam` CLI — must still see
   continuously-in-focus video, the same way `Agc`/`Awb` already run
   automatically every frame today with no app involvement. Concretely: `Af`
   must default to running continuously and autonomously inside the IPA (like
   `Agc`, not gated behind an app ever writing `AfTrigger`), and Phase 3's
   "done" criterion is an app-level demo, not just a `cam`-CLI/debug-control
   demo — see the updated Phase 3 section below. Keeping the controls
   internal-only (#2) is compatible with this: they're for future
   observability/override, not a requirement for basic function.
4. **`setLensControls` mojom shape** — dedicated signal (rpi pattern) vs.
   extending the existing `setSensorControls` signal (ipu3 pattern). Per
   2026-07-22 direction, left as originally proposed: decide when Phase 2
   actually starts, not now.
5. **Whether to ever expose the kernel driver's undocumented `GetStatus`/
   `GetPos` protocol (reg `0x0A`) as a real busy/settle signal**, vs. relying
   on a fixed empirically-measured delay. Was "only worth pursuing if settle
   time proves highly variable" — **settle time was measured 2026-07-22
   (unknown 1 above) and is confirmed highly variable** (effectively instant
   to ~870ms for the same 64-unit step size, with at least one apparent
   overshoot/ringing case), so this is no longer a hypothetical trigger
   condition, it's met. **Still not committed** — a fixed delay generous
   enough to cover the observed worst case (comfortably over ~1s, e.g. with
   margin) is a legitimate, simpler alternative to a kernel-driver change,
   just a slower one; the real decision is a speed/complexity tradeoff to
   make once Phase 1's actual hill-climb loop is built and it's clear
   whether fixed-delay pacing is fast enough to feel responsive.
6. **10-bit vs. 11-bit DAC range ambiguity** (open in
   `docs/vcm-investigation-lc898217.md`, distinct from but related to unknown
   3 above) — Phase 0's sweep should incidentally surface clipping/wraparound
   above `0x3FF` if present; check for it explicitly rather than assuming
   Phase 0 resolves it just by having run. **Still open.**
7. **Keep Phase 1's standalone harness after Phase 3 lands, or discard it?**
   Recommend keeping it — cheap to keep, useful as an external validation
   baseline for in-tree AF performance. Location (`scripts/` vs. a new
   `tools/` dir) to be settled when Phase 1 starts. **Still open** (no
   objection expected, but not explicitly confirmed).
