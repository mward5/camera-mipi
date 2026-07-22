# Real closed-loop autofocus (CDAF) for the rear camera — scoping plan

**Status: scoping only, not started.** This document plans the work; no kernel,
libcamera, or driver source has been touched to implement any of it yet. See
`scripts/af-sweep-measure.sh` for a first-draft Phase 0 harness (also written,
also not yet run against hardware).

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

1. **Lens physical settle time after a `focus_absolute` write.** Completely
   unmeasured — needed to pace any hill-climb loop. Measure by writing a
   position, capturing frames in a tight burst immediately after, and finding
   when the sharpness metric on a fixed scene stops changing / stabilizes
   within noise. Test at multiple step sizes (small vs. full-range jumps),
   since settle time plausibly scales with move distance.
2. **Which sharpness metric actually works on real frames from this sensor.**
   Candidates: Laplacian variance, Tenengrad (gradient magnitude), or a metric
   matching what `SwStatsCpu`'s existing sparse sampling could cheaply support.
   Evaluate against real captured frames across multiple scenes/lighting, for
   monotonicity around the true focus point — a metric with multiple local
   maxima or a flat/noisy peak makes hill-climbing unreliable.
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

## Phased plan

### Phase 0 — instrument and measure (done: a first-draft script exists)

**Goal:** answer unknowns 1 and 3, and gather the raw data for unknown 4's
AGC-drift question. `scripts/af-sweep-measure.sh` (written this session, **not
yet run against hardware**) sweeps `focus_absolute` in configurable steps
across 0–1023 via the `lc898217 1-0072` subdev, capturing a burst of frames +
`cam --metadata` output at each position into `/tmp/af-sweep/` (or an
overridable `OUTDIR`), indexed by a `sweep.csv`.

**Files touched:** `scripts/af-sweep-measure.sh` only. No libcamera/kernel
changes.

**Done when:** the script has been run against real hardware on a scene with
real depth variation, producing a dataset from which settle time and usable
range can be read off by a human or Phase 1's analysis tool.

### Phase 1 — standalone CDAF prototype + hill-climb validation (Option B)

**Goal:** answer unknown 2 definitively, and validate a real closed-loop
hill-climb end-to-end against physical hardware, producing the tuning
constants Phase 3's in-tree algorithm will need.

- Build a small analysis/control tool (language TBD — doesn't need to match
  libcamera's C++, this is throwaway research code) that reads Phase 0's
  dataset to compare candidate sharpness metrics, then drives a live
  coarse-then-fine hill-climb (loosely modeled on `ipu3/algorithms/af.cpp`'s
  `afCoarseScan()`/`afFineScan()`/`afScan()` shape, but calling `v4l2-ctl`
  directly instead of reading IPU3 hardware stats), using Phase 0's measured
  settle time to pace each step.
- Explicitly resolve the AGC-locking question from unknown 4 and record the
  answer plus the final metric/step-size/threshold choices.

**Files touched:** new tool, location TBD (`scripts/` or a new `tools/`
directory — this project isn't a git repo, so no branch/PR concerns, just pick
a location when this phase starts). No libcamera/kernel changes.

**Done when:** the tool reliably converges focus across multiple real scenes
with a documented, repeatable success rate, and the chosen metric/constants/
AGC-interaction handling are written down here for Phase 3 to consume.

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

**Goal:** port Phase 1's validated algorithm into the in-tree
`Algorithm<Module>` structure.

- Add `src/ipa/simple/algorithms/af.{h,cpp}` implementing `prepare()`/
  `process()`/`configure()`/`queueRequest()` as needed, following `agc.h`/
  `agc.cpp`'s shape (closest existing example of a per-frame stats-driven
  algorithm in this IPA — `ipu3`/`rpi`'s `af.cpp` are algorithmically similar
  but built around hardware stats this path doesn't have).
- Port Phase 1's hill-climb, reading the new `SwIspStats` sharpness field and
  emitting the new `setLensControls` signal instead of direct V4L2 writes.
- If Phase 1 found AGC-locking necessary, implement it via shared
  `IPAContext`/`IPAFrameContext` coordination between `Af` and `Agc` — a new
  touchpoint, not present today.
- Register `Af:` in `s5k3j1.yaml`'s `algorithms:` list; advertise
  `AfMode`/`AfState`/etc. per Open Questions #2.

**Files touched:** new `src/ipa/simple/algorithms/af.{h,cpp}`,
`src/ipa/simple/algorithms/meson.build`, `src/ipa/simple/data/s5k3j1.yaml`,
`src/ipa/simple/soft_simple.cpp` (control advertisement), possibly
`src/ipa/simple/algorithms/agc.{h,cpp}` and shared context/module headers if
AGC coordination is needed.

**Done when:** `cam` (or `scripts/dell-xps9315-test-rear-cam.sh`) run against
the real pipeline handler autofocuses a real scene end-to-end, no external
harness involved, matching or exceeding Phase 1's measured convergence
reliability.

## Open questions (decide explicitly, don't drift into an answer)

1. **Single-shot AF only, vs. continuous AF (`AfModeContinuous`)?**
   Recommend scoping Phases 1–3 to single-shot/triggered AF only, and treating
   continuous AF as an explicit non-goal to revisit later — continuous AF has
   materially different timing and AGC-interaction requirements (a live scene,
   not a static target; needs to re-trigger without user action).
2. **Expose `AfTrigger`/`AfState`/`AfMode` to applications now, or keep AF
   internal/debug-only during Phase 3?** Exposing the full control set commits
   to a stable app-facing contract before the algorithm is proven. Recommend
   internal/debug-only in early Phase 3, full exposure deferred.
3. **Would any real client on this system actually consume these controls if
   added?** Not checked yet — worth a cheap look before investing in full
   control exposure: does GNOME's Camera/Snapshot app (or anything else on
   this system using libcamera) call `AfTrigger`/read `AfState` at all, or
   would it ignore them regardless? Determines whether Phase 3's "done"
   criterion needs an app-level demo or only a `cam`-CLI-level one.
4. **`setLensControls` mojom shape** — dedicated signal (rpi pattern) vs.
   extending the existing `setSensorControls` signal (ipu3 pattern). Recommend
   the dedicated signal for clarity; decide before Phase 2 starts.
5. **Whether to ever expose the kernel driver's undocumented `GetStatus`/
   `GetPos` protocol (reg `0x0A`) as a real busy/settle signal**, vs. relying
   on Phase 0's fixed empirically-measured delay. Only worth pursuing if
   Phase 0 finds settle time is highly variable and a fixed delay can't safely
   cover it — a kernel-driver change, separate scope from the userspace/IPA
   phases above. Deferred/conditional, not committed.
6. **10-bit vs. 11-bit DAC range ambiguity** (open in
   `docs/vcm-investigation-lc898217.md`, distinct from but related to unknown
   3 above) — Phase 0's sweep should incidentally surface clipping/wraparound
   above `0x3FF` if present; check for it explicitly rather than assuming
   Phase 0 resolves it just by having run.
7. **Keep Phase 1's standalone harness after Phase 3 lands, or discard it?**
   Recommend keeping it — cheap to keep, useful as an external validation
   baseline for in-tree AF performance. Location (`scripts/` vs. a new
   `tools/` dir) to be settled when Phase 1 starts.
