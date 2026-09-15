# PDAF (phase-detect autofocus) for the s5k3j1 rear camera — implementation plan

**Status of this document:** written 2026-09-14 by Fable 5.1 under a credit budget, for
execution by Opus 5. Revised 2026-09-14 after a follow-up question about noise reduction and
what the IPU6 actually does: Findings 5 and 6 and work packages WP4 and WP5 are from that pass.
Sections are ordered so that each is usable on its own. Findings 1–6 are
verified research (file:line citations are against the trees named below). The work packages
(WP0–WP4) are ordered so that stopping after any one of them still leaves a real deliverable.

Trees referenced:
- Kernel: `~/work/git-ubuntu/resolute` (branch `dell-xps9315-2in1`, synthetic root =
  `Ubuntu-7.0.0-31.31` as of 2026-09-14; published as `github.com/mward5/linux-xps9315-2in1`,
  **whose `main` is still the pre-rebase 29.29-based tip** - the rebase is local-only and its
  push is deliberately deferred, see below).
- Sensor driver: `~/work/intel/ipu6-drivers` branch `dell-xps9315-s5k3j1` (published as
  `mward5/ipu6-drivers-xps9315-2in1`), file `drivers/media/i2c/s5k3j1.c`.
- libcamera: `~/work/git-ubuntu/libcamera` branch `xps-9315-2-in-1-cameras` (0.7.0 base).
- Project repo: `~/work/camera-mipi` (`STATUS.md`, `docs/`, `scripts/`, `reference/`).

## Context

The Dell XPS 13 9315 2-in-1 rear camera (Samsung S5K3J1, ACPI INT346D, IPU6ep CSI2 port 1,
VCM LC898217 at i2c 0x72) streams, has a working lens driver, working AGC, and real continuous
contrast-detect autofocus (CDAF) in libcamera's software ISP (`src/ipa/simple/algorithms/af.cpp`).
Measured CDAF convergence is ~29 s for a full scan (~7 s for a local re-scan); lens settle is up
to ~870 ms per step. The user judges this "as good as CDAF gets". PDAF is the lever: the sensor
has on-chip phase-detect pixels (Windows runs it as "PDAFType2" with a "PAFi" 3968x684 sideband
stream, per `reference/windows-driver-artifacts/win-collected/graph_settings_s5k3j1sx04_*.xml`),
and libcamera already ships a mature hybrid PDAF+CDAF control law in the Raspberry Pi IPA
(`src/ipa/rpi/controller/rpi/af.cpp`, BSD-2-Clause).

Goal: a two-phase plan with a real chance of upstream acceptance.
- **Phase 1** — fully open stack: mainline-derived kernel + libcamera simple pipeline + soft ISP.
  This is where all the real work is. WP0 through WP3, plus WP5.
- **Phase 2** — the Intel `intel/ipu6-drivers` (DKMS) stack. **Open, not a dead end** (WP4).
  An earlier revision of this plan called it dead on the grounds that the processing-system
  driver is unmaintained at this kernel version. That was wrong and unverified: Canonical ships
  a signed `intel-ipu6-psys`, and it is loaded, bound and probed on this machine now. The
  remaining cost is that the path bypasses libcamera entirely, not that it is unavailable.

Two findings drove the revision. The 2026-07-22 attempt was abandoned on a diagnosis that turns
out to be wrong (Finding 1). And the noise the user sees has a separate, measurable cause with
its own fix that does not depend on PDAF at all (WP5).

## Finding 1 — the "ONLY_1_TO_1 blocker" was a misdiagnosis; the real gate is the streams-API switch

Verified in `~/work/git-ubuntu/resolute` (`drivers/media/pci/intel/ipu6/`):
- `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1` (`ipu6-isys-subdev.c:261`) is `NO_1_TO_N | NO_N_TO_1`
  (`include/media/v4l2-subdev.h:1600`). It forbids fan-out/fan-in only. Two independent routes
  `{sink0/stream0 -> src1/stream0}` and `{sink0/stream1 -> src2/stream1}` are legal.
- Mainline ISYS already has everything PDAF needs kernel-side: `V4L2_SUBDEV_FL_STREAMS` on the
  CSI2 subdev (`ipu6-isys-subdev.c:336`), `MEDIA_BUS_FMT_META_8..24` on CSI2 pads
  (`ipu6-isys-csi2.c:77`), `V4L2_META_FMT_GENERIC_8/CSI2_10/12/16` on capture nodes with
  `V4L2_BUF_TYPE_META_CAPTURE` (`ipu6-isys-video.c:102-108`, `:1249-1260`), 8 source pads /
  capture nodes per CSI2 port (`ipu6-isys-csi2.h:23`), and per-node VC/DT taken from the
  sensor's `get_frame_desc` entry whose `.stream` equals the route's sink stream
  (`ipu6-isys-video.c:1197-1212`, `ipu6-isys-csi2.c:628-672`). Nodes sharing a VC share one
  firmware stream with one input pin per DT (`ipu6-isys-video.c:870-905`, `:465-500`).
  Metadata capture landed 2024-01 (`d3bd039cd2a0`) and was fixed 2025-05 (`f5a2826cd50c`,
  META_* -> `MIPI_CSI2_DT_EMBEDDED_8B` in `ipu6_isys_mbus_code_to_mipi`).
  `Documentation/admin-guide/media/ipu6-isys.rst:132-155` documents a RAW + metadata
  dual-capture recipe using `media-ctl -R` and `yavta -B meta-capture`.
- **The real blocker:** `drivers/media/v4l2-core/v4l2-subdev.c:59`
  `static bool v4l2_subdev_enable_streams_api;` is a compile-time `false`. The core then strips
  `V4L2_SUBDEV_CAP_STREAMS` from QUERYCAP (`:649-660`), returns `-ENOIOCTLCMD` for
  `VIDIOC_SUBDEV_[GS]_ROUTING` (`:1005`, `:1032`) and clears the client streams cap (`:1130`).
  libcamera keys everything on that cap (`v4l2_subdevice.cpp:1146`; `simple.cpp:520-525` sets
  `supportsRouting` only when `hasStreams()`), which is exactly why the archived WIP's
  `discoverIp6PdafSideband()` "never found a matching CSI2 entity" — the kernel hid it.
- A sensor cannot expose a second stream at all without the **internal sink pad** concept
  (`MEDIA_PAD_FL_INTERNAL`): routes need a sink pad, and a sensor has none. That flag is absent
  from this tree (grep of `include/uapi/linux/media.h`), and no mainline i2c sensor sets
  `V4L2_SUBDEV_FL_STREAMS` (only `ds90ub9xx`/`max967xx` bridges do). Both come with Sakari
  Ailus's metadata series (Finding 2).
- Sensor side today (`s5k3j1.c:1572-1596`): 2-entry `get_frame_desc` (stream 0 RAW10 VC0;
  stream 1 `META_8`, VC **1**, DT **0x12 EMBEDDED_8B** — both guesses) plus stream-aware
  `enum_mbus_code/enum_frame_size/get_fmt/set_fmt` for stream 1 = 3968x684 `META_8`
  (`:1090-1125`, `:1157-1174`, `:1285-1320`), gated by `pdaf_trial` module param
  (`:747-755`) and `int346d_rear`. No `FL_STREAMS`, no routing, no internal pad.

## Finding 2 — upstream status as of 2026-09-14

**Kernel, V4L2 core (Sakari Ailus, Intel):**
- "Metadata series preparation" v7, 2026-08-07, 14 patches, acked by Dave Stevenson, Laurent
  Pinchart, Jacopo Mondi, Frank Li; author intends to merge "once the next rc1 is in the media
  tree". It adds `struct v4l2_subdev_client_info` to pad ops and `MEDIA_LNK_FL_VALIDATE_LATE`
  (from v3/v4, 22–29 patches, IPU6 named as a user). The `V4L2_SUBDEV_CAP_STREAMS` bit bump
  was **postponed** out of v7. https://ratatoskr.run/linux-media/2026/08/17381668/t ,
  https://ratatoskr.run/linux-media/2026/03/8466606/t , https://lwn.net/Articles/1067015/
- The main series "Generic line based metadata support, internal pads" is at **v12, 86
  patches, June 2026**, unmerged. It adds `MEDIA_PAD_FL_INTERNAL`, generic serial metadata
  mbus formats, line-based metadata capture, MIPI CCS embedded data, and (per its history)
  enabling the streams API. Pieces are being split out and merged separately (e.g. imx219
  `.get_frame_desc`, 2026-06-11, https://ratatoskr.run/linux-media/2026/06/17119150/t ).
- Practical reading: the kernel API our sensor patch must target is *that* series' shape
  (internal sink pad -> source pad routes, sensor-specific format on the internal pad, generic
  `META_*` on the source pad). Anything else will not be accepted. Merge into mainline is
  plausible within a few cycles but not scheduled; the plan therefore builds on a local
  backport of the needed subset and keeps the sensor patch rebasable.
- No mainline `s5k3j1` driver, no `INT346D` thread on linux-media found (lore blocked by
  Anubis during this research; web search found only S5KJN1/S5KJN5). The only public
  `s5k3j1.c` is Intel's out-of-tree one (added 2025-09-09 by Jimmy Su).

**intel/ipu6-drivers (DKMS):** `origin/master` `71bddb515` (2026-08-19). For kernels >= 6.10
the DKMS build ships only `intel-ipu6-psys` + sensor drivers and uses the **in-kernel**
`intel-ipu6`/`intel-ipu6-isys` (README; `dkms.conf` conditionals; `patch/v7.0/` added
2026-06/07). Its legacy out-of-tree ISYS (`drivers/media/pci/intel/ipu-isys-*.c`, pre-6.10)
hard-codes `vc = 0` and has no streams/routing/META support. No PDAF, metadata or multi-stream
commits in its history. **So on this 7.0 kernel, Phase 2's kernel side is the same mainline
ISYS as Phase 1.** Only userspace differs (Intel `ipu6-camera-hal` + closed `libia_aiq` in
`ipu6-camera-bins`, where the actual phase computation lives) plus PSYS.

**Intel HAL / bins:** `ipu6-camera-hal` has `PlatformData::isPdafEnabled()` feeding
`cca::CCA_STATS_PDAF` (`src/3a/AiqCore.cpp`, `src/core/IspParamAdaptor.cpp`), PSYS program
group `isa_lb_video_pdaf_3` (`config/linux/ipu6ep/psys_policy_profiles.xml`), and the ia_css
headers define the ISYS PDAF link (`IA_CSS_ISYS_LINK_PDAF_OUTPUT`) and the data layouts
`IA_CSS_DATA_FORMAT_PAF_NON_INTERLEAVED` ("L and R PDAF pixel line pairs") /
`IA_CSS_DATA_FORMAT_PAF_INTERLEAVED` ("L and R PDAF pixel pairs, LRLR.. / RLRL.., may
alternate"). No code in `src/` captures a PAF V4L2 metadata node (gh code search), no
`PDAFType2` sensor XML in `config/`, and `ipu6-camera-bins` has no `s5k3j1` tuning at all.

**libcamera:** latest release v0.7.1 (2026-04-29, C++20, multithreaded debayer). Local tree
is 0.7.0. Upstream softisp is churning: `IPASoftSimple` renamed `IPASoftIsp` (v9 accepted
2026-08-18), AGC refactor, LSC, temporal denoise, "Rework software-isp/converter selection"
(2026-08-31). **No autofocus exists upstream outside the RPi IPA** (patchwork search), so this
project's CDAF `Af` is itself unsubmitted and is the base PDAF builds on. Upstream already
merged (2025-01) "camera_sensor: Add support for embedded data": `CameraSensor::
embeddedDataStream()/embeddedDataFormat()/setEmbeddedDataEnabled()` implemented by
`CameraSensorRaw` from the sensor's routing (`camera_sensor_raw.cpp:270-360`), consumed by
`pipeline/rpi/pisp`. It classifies streams by `MediaBusFormatInfo::Type` and **skips metadata
streams that are not embedded data** (`:315-333`) — a PDAF stream needs a small extension
there. `V4L2VideoDevice` supports meta capture nodes (`v4l2_videodevice.cpp:618-621`,
`:893-928` generic line-based). RPi's hybrid AF: `af.cpp` (970 lines) with the PDAF control
law in `getPhase()` (:331), `doPDAF()` (:433, proportional loop `pdafGain`, `pdafSquelch`,
`confEpsilon`), `earlyTerminationByPhase()` (:476), `doAF()` (:588, dropout to CDAF), lens
slew in `updateLensPosition()` (:692). Data contract `pdaf_data.h`: `PdafData{uint16_t
conf; int16_t phase}` (S.11.4) in a `RegionStats` grid.

## Finding 3 — the PAF stream's VC/DT and enable registers, from the Windows I2C capture

`docs/windows-agent-findings-i2c-mode-regs-2026-07-17.md` (Phase D/E, the live Windows
stream-start) vs the Linux mode table `mode_3976x2736_regs` (`s5k3j1.c:145-723`):

| Register | Windows | Linux table | Likely meaning |
|---|---|---|---|
| `0x0116` | `0x2B00` in Phase D, then **`0x3000`** in Phase E | `0x2B00` only (`:476`, `:676`) | MIPI data type of the second (PD) output: 0x2B = RAW10, **0x30 = User-Defined 1** |
| `0x0118` | `0x0000` | `0x0000` | probably PD output virtual channel = **0** |
| `0x0B80` | **`0x0100`** | `0x0000` (`:713`) | PD tail/sideband output enable |
| `0x0B84` | `0x0201` | `0x0201` | PD config (unchanged) |
| `0x0B88..` | 8 zero bytes | absent | PD window/offset clear |
| `0x0900/0x0901` | `0x00`/`0x11` | `0x0221` (`:709`) | binning mode/type — differs, may or may not matter |

Hypothesis to test first (WP0): the PAF sideband is **VC 0, DT 0x30, 8-bit user-defined,
3968 bytes x 684 lines**, enabled by `0x0B80=0x0100` + `0x0116=0x3000`. The archived WIP's
guess (VC1, DT 0x12) contradicts this evidence. Because Windows puts it on VC0, mainline ISYS
will create one firmware stream with two input pins (RAW10 + 0x30), the exact shape of the
documented RAW+metadata recipe. Mainline's `ipu6_isys_mbus_code_to_mipi()` maps `META_8` to
DT 0x12 only as a *fallback* when the sensor has no frame desc (`ipu6-isys-video.c:1204-1205`);
with a frame desc the sensor's DT (0x30) is used verbatim.

`0x0900` is written by Windows as two 8-bit values (`0x0900=0x00` binning off, `0x0901=0x11`),
whereas the Linux table writes 16-bit `0x0221`. Not obviously PDAF-related but it is a real
divergence in a "byte-matched" table; WP0 should A/B it.

Data layout: "PAFi" almost certainly = PAF *interleaved* (Intel's `PAF_INTERLEAVED`, "L and R
pixel pairs LRLR.."). 684 = 2736/4 lines. Whether the 3968 bytes/line are 8-bit PD samples
or a packed format is unknown; WP0 decodes it empirically (WP0 step 5).

## Finding 4 — what has to be built that does not exist anywhere yet

1. **PD pixel -> phase/confidence**: the RPi algorithm consumes *precomputed* per-region
   phase+confidence (imx708 computes it on-sensor). S5K3J1 Type2 emits raw L/R samples; the
   correlation (per region: SAD or NCC of the L row against the R row over shifts of
   +/-N samples, parabolic sub-sample minimum, confidence from curve depth vs. noise) must be
   written. Windows does this inside closed `libia_aiq`. This is the only genuinely novel
   algorithm piece. Keep it a self-contained, testable module (offline on captured dumps first).
2. **PDAF stream tagging in the kernel API**: Sakari's design tags a sensor's internal stream by
   the mbus code on the internal pad (e.g. `MEDIA_BUS_FMT_CCS_EMBEDDED_*`). There is no code for
   "PDAF data". Two options: a sensor-specific `MEDIA_BUS_FMT_S5K3J1_PDAF` style code (matches
   the embedded-data precedent, minimal), or a new generic `MEDIA_BUS_FMT_PDAF_*` family
   (broader, needs a maintainer conversation). **Recommendation: sensor-specific code, and ask
   on linux-media early** (WP2 step 0) — the user posts, after we explain the trade-off
   (memory: explain concepts, do not hand over draft text unexplained).
3. **libcamera plumbing** for an auxiliary metadata stream in the simple pipeline + soft ISP IPA
   (second capture node per camera, buffer pairing by sequence, IPA buffer mapping).

Note on item 1 after the Finding 5 correction: this substitutes for a hardware kernel
(`pafstatistics_1`), so treat CPU cost as a first-class design constraint. A 3968x684 plane at
30 fps is 81 MB/s of input. Subsample into a coarse region grid and correlate only within each
cell over a bounded shift range; do not correlate at full resolution.

## Finding 5 — CORRECTED: the IPU6 *does* compute PAF statistics in hardware, for this sensor too

**This section originally claimed the opposite. Recorded as a correction, per project convention,
rather than silently rewritten.** The first pass concluded that because no PDAF-named program
group appears in this sensor's graph *settings* file, the processing system plays no part and
Windows computes the phase in software. That reasoning was unsound: the settings file only
overrides resolutions and formats, while the *descriptor* defines which kernels exist and run.
Reading `config/linux/ipu6ep/gcss/graph_descriptor.xml` settles it.

The program group this sensor actually uses, `isa_lb_video`, contains:

- `<kernel enabled="1" idx="65" name="pafstatistics_1" pal_uuid="47216" rcb="0"/>` — a hardware
  PAF statistics kernel, enabled.
- `<port direction="0" id="27" name="ext_pdaf_stats"/>` — an **input** port for externally
  supplied PDAF data, fed straight to `mux_pdaf_stat_1_0:0`, with the mux set `active_input="0"`.
- `<port content_type="spatial" direction="1" id="16" name="pdaf_stats"/>` — the statistics
  output, sourced from `pafstatistics_1:output`.

`isa_lb_video_pdaf_3`, the Type 3 variant, is the **same program group with 23 lines different**.
It drops the `ext_pdaf_stats` link, flips the mux to `active_input="1"`, and feeds the same
`pafstatistics_1` kernel from `pext_1_0`, a pixel extractor taking `outputafpixelsimage` off the
defect-pixel-correction stage. Only the routing bitmask differs otherwise.

So the two PDAF types are two ways of feeding one hardware kernel:

| | source of phase pixels | mux input |
|---|---|---|
| Type 2, ours | ISYS delivers the PAF sideband, enters via `ext_pdaf_stats` | 0 |
| Type 3, `ov13b10` | extracted from the image stream inside the ISA by `pext_1_0` | 1 |

**Consequences for this plan.** The design does not change: software correlation on a
CPU-captured PAF plane remains the only option on the open stack, and it is tractable. But the
honest characterisation does. WP3's correlator substitutes for a *hardware statistics kernel*,
not merely for a library function, so budget more effort for it and expect a CPU cost that a
region grid and subsampling must keep in check. The control law on top of those statistics does
still live in the closed autofocus library, and that part the Raspberry Pi algorithm covers.

**It also means the open stack leaves a real, loaded hardware ISP idle.** The same program group
carries `bnlm_3_2` (Bayer non-local-means denoise), `xnr_5_2`, `gd_dpc_2_1` (defect pixels),
`lsc_1_1` (lens shading), `bxt_demosaic`, `bxt_wb`, `bxt_acm`, `gammatm_v3`, the 3A statistics
kernels and video stabilisation. None of it is reachable without the processing-system driver.

## Finding 6 — the graph settings file is Apache-2.0 and we already hold it

The "Intel has published no graph for this sensor" blocker is weaker than it looked.

- Dell's Windows driver ships `graph_settings_HI556_1BG502T3_ADL.xml`, and Intel publishes a
  file of the same name in `ipu6-camera-hal/config/linux/ipu6ep/gcss/`. They are **byte
  identical** (md5 `56df1fb064472c466a4edf7020d08350`, 12689 lines each, same version string
  `IPU6_20210118.0.1.0.247.1.2021.1.18.14.59.25`). These are one artifact shipped to both
  operating systems, not two parallel formats.
- The rear camera's own `graph_settings_s5k3j1sx04_CJALR11_ADL.xml` carries the same header:
  Copyright Intel Corporation, **Apache License 2.0**. Not the "INTEL CONFIDENTIAL" banner that
  the separate `graph_descriptor.xml` carries.
- Version compatibility is plausible rather than proven. Ours is `IPU6_EP_20211220...`; Intel's
  Linux ipu6ep descriptor is `IPU6_EP_20210318` and their `ov13b10` settings are
  `IPU6_EP_20220216...`. Ours sits between the two, and the newer `ov13b10` settings work
  against that descriptor, so the settings-to-descriptor coupling is evidently loose.
- Caveat on the descriptor: `config/linux/ipu6ep/gcss/graph_descriptor.xml` is the program-group
  catalogue the settings file references, and it is labelled INTEL CONFIDENTIAL **even though
  Intel publishes it in a public repository**. Using it as Intel ships it is fine; we should not
  redistribute it ourselves. Authoring a descriptor from scratch would be genuinely infeasible,
  since it indexes firmware kernel and routing descriptors we do not have.

So: we would not need to *create* the graph. We would need to *try the one we have*. The
remaining unpublished piece is the per-module tuning binary, and the project has already shown
(2026-07-27, `docs/aiqb-cmc-dump-findings.md`) that the Dell `.aiqb` parses correctly against
Intel's own **Linux** parser library. Its redistribution licence is a separate open question
already tracked against the colour-matrix work.

## Strategy

Hack first, then build the upstream-shaped version on evidence. Do not start Phase 1's
kernel-API work until WP0 has proven (a) the sensor emits PAF data with the Finding 3
registers, (b) we can decode it, (c) an offline correlator yields a phase that varies
monotonically with lens position. Each of those is a cheap, independent, decisive experiment,
and each failure mode changes the plan.

Conventions carried over from this project (do not relearn): every platform quirk is DMI+HID
gated (`int346d_i2c_quirk_dmi_ids` pattern in `ipu-bridge.c`); kernel-targeted repos use the
`Assisted-by:` trailer, libcamera uses `Co-Authored-By:`; no squashing on public branches;
builds go to a sibling `<pkg>-<version>_output/` dir; big captures go under
`~/work/af-sweep-data/`, never `/tmp` (7.5 GB tmpfs); restart pipewire/wireplumber in the same
command that stops them; `media-ctl` does not print ancillary links; verify a dev build's
reported git hash before trusting it; module changes need install to `/lib/modules/$(uname
-r)/updates/` + reboot, not insmod/rmmod (see `STATUS.md`, `scripts/install-custom-modules.sh`).

## WP0 — throwaway proof of PAF emission and offline phase (Phase 0, not for upstream)

Purpose: answer the three unknowns above with the smallest possible change set. Nothing here
is submitted anywhere; it is deleted once WP2 replaces it. Deliverable even if we stop here:
`docs/pdaf-phase0-findings.md` with captured data, decoded layout, phase-vs-position curve.

1. **Kernel-side hack, ISYS** (`drivers/media/pci/intel/ipu6/ipu6-isys-video.c` in the
   resolute fork, new branch `pdaf-phase0-hack`): module params `pdaf_hack_port=1`,
   `pdaf_hack_pad=2`, `pdaf_hack_dt=0x30`, `pdaf_hack_vc=0`. When set and the capture node is
   `csi2->av[pdaf_hack_pad]` on that port, skip the route lookup in the stream-prepare path
   (`ipu6_isys_video.c` around `:1190-1215`, where `av->source_stream`/`av->vc`/`av->dt` are
   derived) and force `vc/dt`, and accept `V4L2_META_FMT_GENERIC_8` 3968x684 on it. Keep the
   image node untouched. Rationale: avoids the streams API and internal pads entirely for the
   experiment. Alternative if the route lookup is awkward: flip `v4l2_subdev_enable_streams_api`
   to `true` and give the CSI2 a second active route via `media-ctl -R`; the sensor still has
   no routing so the frame-desc lookup would fail — hence the forced-vc/dt param is needed
   anyway. Build/install per `scripts/install-custom-modules.sh` (isys module only) + reboot.
2. **Sensor-side hack** (`s5k3j1.c`, same-named branch in the ipu6-drivers fork): extend the
   existing `pdaf_trial` param with a value that writes `0x0B80=0x0100`, `0x0116=0x3000`
   (after the mode table, before stream-on), and optionally `0x0900=0x0011` as 8-bit writes;
   keep `get_frame_desc` as is (the ISYS hack ignores it). Keep VBLANK at the stock
   `vts_def - height` first; the "tall vblank" idea (`S5K3J1_VBLANK_PD_AF`, `:731-732`) was a
   guess for embedded-in-frame PD lines and is probably wrong for a VC/DT sideband; A/B it only
   if no PAF frames arrive.
3. **Capture**: stop pipewire/wireplumber (restart in the same command), then per
   `ipu6-isys.rst:132-155`: `media-ctl -l` the CSI2 port-1 pad 2 -> "Intel IPU6 ISYS Capture 9"
   link, `media-ctl -V` formats, `yavta -B meta-capture -f GENERIC_8 -s 3968x684 -c30 --file=...`
   on the meta node concurrently with `yavta`/`cam` on the image node. Watch `dmesg` for CSI2
   errors. Success = meta buffers complete with non-constant content. Failure branches:
   no completion -> try DT 0x31..0x37, VC 1, and the `0x0900` variant; CSI2 framing errors ->
   size mismatch, dump `bytesused`.
4. **Ground-truth pairing**: also capture with the lens driven to 0/256/512/768/1023 via
   `v4l2-ctl -d /dev/v4l-subdevN --set-ctrl focus_absolute=...` (reuse
   `scripts/af-continuous-sweep.sh` conventions: single session, positions written mid-stream).
5. **Decode** (`scripts/pdaf-decode.py`, stdlib only — no numpy on this box): test the
   candidate layouts from Finding 3 (8-bit LRLR interleaved; 10-bit packed; line-pair
   non-interleaved) by checking which one makes L and R images that look like a 4x-vertically
   subsampled copy of the scene (write PGMs and look). Expect a small horizontal disparity
   between L and R that flips sign across focus.
6. **Offline correlator** (`scripts/pdaf-correlate.py`): per grid cell (start 4x3), SAD over
   shifts -16..+16 samples, parabolic minimum, confidence = (mean SAD - min SAD) / noise
   floor. Produce phase vs `focus_absolute` for 2 scenes (wall, futon — the same two used for
   CDAF validation). Success = monotonic, roughly linear, sign-consistent; slope becomes the
   first `pdaf_gain` estimate. Record everything in `docs/pdaf-phase0-findings.md`.

Exit criteria for WP0: PAF frames captured, layout decoded, phase-vs-position curve with a
usable confidence signal on at least one scene. If (c) fails but (a)/(b) pass, the plan still
proceeds with WP1/WP2 but the algorithm work in WP3 becomes the risk item.

## WP1 — kernel: streams API + internal pads on the fork (Phase 1a, pre-upstream enabling)

Purpose: give the local kernel the API shape the upstream sensor patch needs. Not
upstreamable itself (upstream = Sakari's series); kept as a clearly labelled "backport" set.

1. Fetch Sakari's v12 series (June 2026, 86 patches; find the cover on lore/ratatoskr, or the
   author's linuxtv.org git tree named in the prep-series cover letters) and identify the
   minimal subset: `MEDIA_PAD_FL_INTERNAL` + core routing support for internal sink pads,
   the streams-API enable, and any `v4l2_subdev_state`/`routing_validate` changes the sensor
   patch depends on. Apply with `patch -p1 --fuzz=3` per the memory recipe (git am will fail
   on context drift), on branch `pdaf-streams-backport` of the resolute fork, one commit per
   upstream patch with original authorship preserved.
   Fallback if the subset is too entangled: build a `media_stage`/linux-next kernel .deb once
   for development, and keep the fork for the sensor/ISYS commits only.
2. Decide how to deploy: replacing `videodev`/`mc` via DKMS is possible but out of the
   project's current DKMS scope (5 leaf modules). **Recommendation: build the full kernel .deb
   from the fork for development** (`make bindeb-pkg`, output to the sibling `_output/` dir);
   revisit DKMS packaging of core modules only if the user wants daily use before upstream
   lands.
3. Re-run the WP0 capture through the real API (no hack): `media-ctl -R` on the CSI2 with two
   routes, `media-ctl -V` with `/1` stream suffixes, `yavta` meta capture. This is the
   acceptance test for WP1+WP2 together.

## WP2 — sensor: upstream-shaped PDAF stream in `s5k3j1.c` (Phase 1a, submittable)

Target: the `intel/ipu6-drivers` fork first (it is the only tree with the driver), written
so the same patch applies to a future mainline `s5k3j1.c` and to Intel's tree.

0. **RFC to linux-media before coding the format** (user posts; we explain): "sensor with a
   PDAF Type2 sideband on a second CSI-2 DT — how should the internal-pad format be
   expressed?" with the two options from Finding 4.2. Also ask Sakari whether IPU6 ISYS is
   expected to accept a user-defined DT (0x30) input pin. Proceed with the sensor-specific
   code while waiting.
1. Replace the `pdaf_trial` experiment with a real design, following the CCS/ov2740 embedded
   data patches in Sakari's series: pads = `{0: source}` + `{1: internal sink, image}` +
   `{2: internal sink, PDAF}`; `V4L2_SUBDEV_FL_STREAMS`; `init_state` creates routes
   1/0->0/0 (image, always active) and 2/0->0/1 (PDAF, inactive by default);
   `set_routing` validates with `V4L2_SUBDEV_ROUTING_ONLY_1_TO_1 | NO_STREAM_MIX` as the
   series' sensors do; `enable_streams/disable_streams` instead of `s_stream`; PDAF register
   writes (`0x0B80`, `0x0116`, whatever WP0 proved) applied only when the PDAF stream is
   enabled; `get_frame_desc` reports stream 1 with the VC/DT WP0 proved; internal-pad format
   = the sensor-specific PDAF code, source-pad stream-1 format = `MEDIA_BUS_FMT_META_8`
   3968x684 (or the packed width WP0 found). Remove the `int346d_rear` gating from the PDAF
   path: PDAF is a sensor capability, not a Dell quirk (keep the DMI gating only for the
   board-specific power/GPIO items already there).
2. Fix the identity/attribution items already noted in memory for this repo's commits
   (`mward5@` author, `Assisted-by:` trailer).
3. Verify with WP1 step 3. Then also verify the image-only path is byte-identical to before
   when the PDAF route is inactive (zero-regression bar).
4. Submission plan: PR to `intel/ipu6-drivers` (they accepted Jimmy Su's original; include the
   512 MHz link-frequency fix already on the fork as a separate PR first — it is independent
   and valuable), and a mainline `s5k3j1` driver submission is a separate, larger effort
   (new driver + `ipu-bridge` entry, needs the series merged first). Record both in
   `STATUS.md`'s upstream section.

## WP3 — libcamera: PDAF data path + hybrid AF in the soft ISP (Phase 1b)

Work on a rebase of the project's AF/AGC commits onto **upstream libcamera master** (not
0.7.0): upstream softisp moved (IPASoftIsp rename, AGC refactor, converter selection). Do the
rebase as its own preparatory step and re-verify CDAF on hardware before adding PDAF; it is
also the prerequisite for ever submitting the CDAF `Af`, which must go upstream before or with
the PDAF extension.

1. **Sensor model**: extend `CameraSensorRaw` stream discovery (`camera_sensor_raw.cpp:
   270-360`) to keep a PDAF stream (new `MediaBusFormatInfo::Type::PdafData` or a
   sensor-format table entry for the new mbus code), exposed like `embeddedDataStream()`:
   `pdafStream()`, `pdafFormat()`, `setPdafEnabled()`. Mirror the existing embedded-data
   functions exactly; that is the shape reviewers already accepted.
2. **Simple pipeline** (`src/libcamera/pipeline/simple/simple.cpp`): when the sensor reports a
   PDAF stream and the CSI2 entity `supportsRouting`, find a free CSI2 source pad whose link
   goes to a meta-capable capture node, add the second route, set stream-1 formats on sensor
   and CSI2 (the archived WIP `pdaf-sideband-wip` branch, `bf35185`, is a usable draft of this
   sequencing — reuse its structure, drop the `s5k3j1`-name check and env var), open the meta
   node (`V4L2VideoDevice`, `isMetaCapture()`), allocate/queue buffers, and pair PDAF buffers
   with image frames by `sequence`. Deliver the PDAF buffer to the IPA per frame. Feature must
   be fully inert when no PDAF stream exists (every other simple-pipeline camera).
3. **IPA transport** (`include/libcamera/ipa/soft.mojom`): add `mapBuffers/unmapBuffers`
   (pattern: `ipu3.mojom`/`rkisp1.mojom`) and a `pdafBufferId` argument (or a separate async
   `processPdaf(frame, bufferId)`) so the IPA can read the dmabuf. Keep `processStats` for the
   existing stats.
4. **Algorithms** (`src/ipa/simple/algorithms/`):
   - New `pdaf_correlator.{h,cpp}`: the WP0 correlator ported to C++, output
     `RegionStats<PdafData>`-equivalent grid (reuse RPi's `PdafData` struct definition with
     its copyright; consider moving `pdaf_data.h` into `libipa` as the upstream-friendly
     home — ask on libcamera-devel).
   - Extend `Af`: a PDAF mode that runs before/alongside the CDAF scan, porting RPi's
     `doPDAF`/`getPhase`/`earlyTerminationByPhase`/dropout logic with explicit Raspberry Pi
     Ltd attribution, driving the lens via the existing `setLensControls` path. Keep the
     existing CDAF machinery as the fallback exactly as RPi does. Tunables in
     `s5k3j1.yaml`: `pdaf_gain` (sign and magnitude from WP0 slope), `pdaf_squelch`,
     `conf_epsilon`, `conf_thresh`, `dropout_frames`, region weights.
   - Reuse the existing Agc-freeze-during-scan and post-converge grace logic unchanged.
5. **Validation** (same discipline as CDAF): headless `cam --metadata` runs on the wall and
   futon scenes; log `AfState`, lens position, phase, conf per frame; measure time-to-focus
   (target: order 1 s vs 29 s) and repeatability (stddev over 5 trials, compare with CDAF's
   104/12.8); the jolt-recovery test; then the PipeWire/Snapshot path with the systemd
   drop-in recipe in memory; then ship as `+xps9315-2-in-1-N` .deb via `dpkg-buildpackage`.
6. **Submission**: series order upstream — (a) CDAF `Af` for softisp, (b) sensor PDAF stream
   discovery, (c) simple-pipeline aux stream, (d) PDAF correlator + hybrid AF. Each
   independently useful; (a) can go now.

## WP4 — Phase 2 REOPENED: the processing system is alive on this machine (corrected twice)

**Correction history, recorded rather than rewritten.** This section first said Phase 2 was a
dead end because `intel-ipu6-psys` is unmaintained and broken on modern kernels. **That is false
on this machine, and it was never verified before being written.** It came from community reports
about kernels 6.16 to 6.19 and from the absence of PSYS patches in Intel's `patch/v7.0/` set.
Both observations are real; the conclusion drawn from them was not.

**Measured on 7.0.0-31-generic, 2026-09-14:**

| Check | Result |
|---|---|
| `intel_ipu6_psys` loaded | yes, refcount 0 |
| Bound to the auxiliary device | yes, `intel_ipu6.psys.40` |
| Probe result in the journal | `pkg_dir entry count:8`, `psys probe minor: 0` |
| Character device | `/dev/ipu-psys0`, 509:0 |
| Shipped by | `linux-main-modules-ipu6-7.0.0-31-generic` 7.0.0-31.31+2 |
| Module path | `/usr/lib/modules/7.0.0-31-generic/ubuntu/dkms/ipu6/intel-ipu6-psys.ko.zst` |
| Signed by | Canonical Ltd. Kernel Module Signing |
| Still loaded with Secure Boot on | yes, verified after the 2026-09-14 re-enable |

Canonical builds this driver from the DKMS source into a signed in-tree module and ships it in
lockstep with every kernel ABI bump. It has been probed and running on this laptop since the
12 September boot. The firmware package directory was read successfully, which means the
processing firmware loaded into the processing system and the driver agreed with it about its
eight components.

**Independently, Intel's `origin/master` PSYS source builds clean against 7.0.0-31 headers.**
Recipe, confirmed working, which the DKMS config does not spell out:

```
git -C <ipu6-drivers> archive origin/master | tar x -C <builddir>
cd <builddir> && patch -p1 < patches/0001-v6.10-IPU6-headers-used-by-PSYS.patch
make -C /lib/modules/$(uname -r)/build M=<builddir>/drivers/media/pci/intel/ipu6/psys \
  CONFIG_VIDEO_INTEL_IPU6=m EXTERNAL_BUILD=1 \
  ccflags-y="-I<builddir>/include -I<builddir>/drivers/media/pci/intel/ipu6 \
             -I<builddir>/drivers/media/pci/intel" modules
```

All ten objects compile, link and pass MODPOST; `vermagic` matches the running kernel exactly.
The build product is kept at `~/work/ipu6-psys-buildtest_output/intel-ipu6-psys.ko`. Its
`srcversion` is `A75828D2B87995661B11D0E` against Canonical's `A2DCB27B28F4396A95385CF`, so
Canonical carries local changes to the driver; worth diffing before modifying it.

**Secure Boot is ENABLED on this machine** (re-enabled by the user 2026-09-14; it had been off
since a Dell firmware flash in June). So a locally built processing-system module will **not**
load unless it is signed with the enrolled machine-owner key, the same way DKMS already signs
this project's modules. Swapping Canonical's module for a local one has not been done and is
not needed: the load question is answered by the running system. If the driver itself ever needs
modifying, sign the result with the enrolled key rather than expecting an unsigned module to
load, and diff Canonical's source first since their `srcversion` differs from Intel's.

### What Phase 2 actually requires now

The kernel half is **done and shipped**. Of the four blockers this plan previously listed, three
have fallen:

1. ~~Graph settings unavailable~~ — Apache-2.0 and in hand (Finding 6).
2. ~~Tuning data unavailable~~ — the Dell `.aiqb` parses against Intel's Linux parser
   (`docs/aiqb-cmc-dump-findings.md`).
3. ~~Processing-system driver unmaintained and unbuildable~~ — false here; shipped, signed,
   loaded, probed.
4. **Still true: it bypasses libcamera.** The Intel path runs `ipu6-camera-hal` under
   `icamerasrc` on GStreamer. The exposure work, colour matrices, CDAF algorithm and the
   PipeWire and desktop integration do not apply to it, and the autofocus control law would move
   inside a closed library.

Genuinely unknown, and the next things to find out:

- Does `ipu6-camera-hal` build and run against this kernel's interface? Both it and
  `ipu6-camera-bins` are already cloned under `~/work/intel/`.
- The journal reports `IPU6 in secure mode`. What that permits or forbids for processing-system
  submissions is not understood and should be checked before assuming the path is open.
- Does the HAL tolerate a sensor whose kernel driver it does not know, given that the graph and
  tuning are supplied? The `s5k3j1` is absent from the HAL's own sensor configuration.
- Does the ISA actually improve the image enough to be worth the integration cost?

### Recommended sequencing

Phase 2 is now a real option rather than a dead end, but it is still the *larger* and more
disruptive of the two routes to better image quality, and it forfeits work that already exists
and is shipped. **WP5 remains the recommended first move for the noise problem**: it is smaller,
keeps the libcamera stack, and is upstreamable. Treat Phase 2 as a parallel investigation with
its own bounded steps:

1. Diff Canonical's PSYS source against Intel's master to see what they carry.
2. Build `ipu6-camera-hal` against the local `ipu6-camera-bins`. Stop if it does not build.
3. Drop in the Apache-2.0 `s5k3j1` graph settings and the Dell `.aiqb`, and see whether `libgcss`
   accepts the file against Intel's ipu6ep descriptor.
4. Attempt one capture through `icamerasrc`. Compare noise against a soft-ISP capture using the
   WP5 measurement tooling, so the comparison is numeric rather than visual.
5. Only then decide whether Phase 2 deserves real investment. Write the outcome up in
   `docs/pdaf-intel-hal.md` either way.

Independent of all of the above, still submit the WP2 sensor patch to `intel/ipu6-drivers` and
send the 512 MHz link-frequency fix as its own earlier pull request.

## WP5 — noise reduction in the software ISP (independent of PDAF, likely the bigger visible win)

Motivation, measured rather than assumed: the Windows graph for this camera runs
`<tnr_6_0>`, temporal noise reduction, as a processing-system program group inside
`post_gdc_video`, with private `tnr_ref_in` and `tnr_ref_out` reference-frame buffers, in all 74
processed presets. Bayer noise reduction sits ahead of it inside the ISA back end. Our software
ISP has no noise reduction of any kind: `src/ipa/simple/algorithms/` holds only black level,
white balance, colour matrix, gain, adjust and autofocus. That is a sufficient explanation for
the visible noise, and closing it does not require any of the PDAF machinery.

This is also open ground upstream, which makes it a genuine contribution rather than a local
patch. As of the FOSDEM 2026 software-ISP status talk by Bryan O'Donoghue and Hans de Goede, the
delivered features are GPU acceleration, open sensor calibration with colour matrices, and lens
shading correction. Noise reduction is not among them.

Sequencing note: **do WP5 before or in parallel with WP3, not after.** Both touch the same files
and both want the upstream rebase done first, and WP5 delivers something the user can see
immediately whereas PDAF delivers speed.

1. **Rebase onto upstream libcamera master first** (shared prerequisite with WP3, do it once).
   Re-verify AGC and CDAF on hardware afterwards before adding anything.
2. **Measure the baseline.** Extend `scripts/agc-analyze-exposure.py`, which already parses P6
   PPM with no third-party dependencies, to report a temporal noise estimate: capture a burst of
   a static scene at fixed exposure and gain, then report per-pixel standard deviation across
   frames and a spatial estimate from a flat patch. Do this at two light levels. Without this,
   any denoise claim is an eyeball judgement, and this project's own history is full of eyeball
   judgements that measurement overturned.
3. **Implement temporal denoise first**, mirroring what the hardware does and what costs least:
   a motion-compensated-free recursive blend of the previous output frame with the current one,
   with a per-pixel blend factor that falls off as the absolute difference grows, so moving
   regions are not smeared. One reference frame, one pass, no search. Add it as a new
   `Algorithm` in `src/ipa/simple/algorithms/` following the shape of `agc.cpp`, with the
   reference frame held in the debayer stage rather than the IPA, since that is where pixel data
   lives.
4. **Then consider spatial denoise** on the Bayer data ahead of debayer, which is where the
   hardware puts it. Only if step 3 leaves visible noise, and only with the measurement from
   step 2 to justify it. Spatial filtering trades detail for smoothness and is easy to overdo.
5. **Watch the interaction with autofocus.** The sharpness statistic is computed on raw samples
   in `swstats_cpu.cpp`, before any of this, so a denoise stage placed in the debayer path should
   not perturb it. Verify that rather than assume it, because this project has been caught twice
   by statistics gathered at one pipeline point and consumed at another.
6. **Consider lens shading too.** The colour-matrix work already found populated
   `cmc_lens_shading` records in every `.aiqb` and left them unused. Upstream now has lens
   shading infrastructure in `libipa`. That is a separate, well-defined follow-on with data
   already in hand.
7. **Validate and ship** the same way as every prior change: both cameras, measured before and
   after, through the installed package and not only the development build.

## Decisions taken in this plan (change if the user disagrees)

- Hack-first WP0 before any API work (cheap, decisive; the biggest unknowns are hardware and
  data-format facts, not code volume).
- Full kernel .deb for development in WP1 rather than DKMS-replacing V4L2 core modules.
- Sensor-specific PDAF mbus code on the internal pad, generic `META_8` on the source pad,
  with an early RFC to linux-media; PDAF stream not DMI-gated (sensor capability).
- PDAF algorithm: port RPi's control law into the existing softisp `Af` with attribution,
  plus a new correlator; do not port the whole RPi `Af` class.
- Rebase libcamera work onto upstream master before WP3.
- Phase 2 kept open but not recommended as the first move. The processing-system driver is
  shipped, signed, loaded and probed on this machine, and Intel's source builds clean here, so
  availability is no longer the question. The reason to prefer WP5 first is that Phase 2
  forfeits the libcamera stack that already works, not that it cannot be reached.
- Noise reduction split out as WP5, sequenced before or alongside WP3 rather than after, because
  it is the more visible improvement and is open ground upstream.

## Verification summary (end-to-end)

1. WP0: `yavta` meta buffers complete; decoded L/R PGMs look like the scene; phase vs
   `focus_absolute` monotonic on 2 scenes (`docs/pdaf-phase0-findings.md`).
2. WP1/WP2: with no hacks loaded, `media-ctl -p` shows the CSI2 routes, `media-ctl -R` +
   `-V ...:0/1` succeed, `yavta -B meta-capture` streams; image-only path unchanged (diff
   `v4l2-ctl --all` + a captured frame checksum against the pre-change build).
3. WP3: `cam --metadata` shows `AfState` reaching `Focused` in ~1 s with PDAF conf above
   threshold, CDAF fallback engaging when the lens is covered; 5-trial stddev; jolt recovery;
   Snapshot via PipeWire; installed-package re-verification (not dev build only).
4. WP4: **done for the kernel half** — `intel-ipu6-psys` is shipped by Canonical, loaded, bound
   and probed on 7.0.0-31, and Intel's master source builds clean here. Remaining checks are
   userspace: does `ipu6-camera-hal` build, does `libgcss` accept the Apache-2.0 `s5k3j1` graph,
   and does one `icamerasrc` capture measure less noisy than a soft-ISP capture using WP5's
   tooling. Write up in `docs/pdaf-intel-hal.md`. Sensor pull request to `intel/ipu6-drivers`
   proceeds independently.
5. WP5: measured per-pixel temporal standard deviation and a flat-patch spatial estimate, before
   and after, at two light levels, on both cameras, through the installed package. Autofocus
   convergence time and repeatability unchanged by the denoise stage.

## Risks

- Sensor may not emit PAF with only the Finding 3 registers (Windows also uploads microcode
  blocks earlier in the sequence; those are already byte-matched per memory). Mitigation: A/B
  the remaining divergences one at a time; the I2C trace is the oracle.
- IPU6 ISYS firmware may reject a user-defined DT input pin. Mitigation: try 0x12/0x2B on VC1
  if the sensor allows changing 0x0116/0x0118; ask Sakari.
- Low-light PDAF confidence is worse than CDAF; the dropout-to-CDAF design covers it.
- Upstream kernel API is still moving (86-patch series). Mitigation: keep the sensor patch
  small, rebase-friendly, and RFC early.
- **Methodology risk this plan has already realised twice.** Two confident claims in earlier
  revisions turned out wrong, both from inferring absence rather than checking: that the IPU6
  does no hardware phase processing for this sensor (refuted by the graph descriptor), and that
  the processing-system driver is unavailable at this kernel (refuted by `lsmod`). Before
  asserting a capability is missing, check the running system or the authoritative definition
  file, not the derived or per-sensor one.
- Temporal denoise smears motion if the blend factor is tuned too aggressively, and the failure
  mode is subtle on a static test scene. Test with real movement in frame, not only the wall.
- Credits: each WP has a standalone deliverable; WP0 alone materially de-risks everything, and
  WP5 is independently useful even if PDAF is never attempted.

## Sources

- Kernel prep series v7: https://ratatoskr.run/linux-media/2026/08/17381668/t ; v3:
  https://ratatoskr.run/linux-media/2026/03/8466606/t ; LWN: https://lwn.net/Articles/1067015/
- imx219 get_frame_desc split-out naming the v12/86 series:
  https://ratatoskr.run/linux-media/2026/06/17119150/t
- IPU6 ISYS admin guide (RAW + metadata recipe): https://docs.kernel.org/admin-guide/media/ipu6-isys.html
- intel/ipu6-drivers: https://github.com/intel/ipu6-drivers (README, commits to 2026-08-19)
- intel/ipu6-camera-hal PAF data-format definitions:
  https://github.com/intel/ipu6-camera-hal/blob/main/modules/ia_css/ipu6ep/include/ia_css_program_group_data_defs.h
- libcamera embedded data support: https://patchwork.libcamera.org/patch/21872/ ;
  v0.7.1 release: https://www.phoronix.com/news/libcamera-0.7.1-Released
- FOSDEM 2026 software-ISP status (O'Donoghue, de Goede):
  https://archive.fosdem.org/2026/schedule/event/TKSK3G-libcamera-softisp/
- IPU6 proprietary-versus-mainline stack write-up, incl. PSYS build failures on recent kernels:
  https://jetm.github.io/blog/posts/ipu6-webcam-libcamera-on-linux/
- Local evidence: `docs/windows-agent-findings-i2c-mode-regs-2026-07-17.md`,
  `docs/aiqb-cmc-dump-findings.md`,
  `reference/windows-driver-artifacts/dell-drivers/graph_settings/` (Apache-2.0 graph files),
  `reference/windows-driver-artifacts/win-collected/graph_settings_s5k3j1sx04_CJALR11_ADL.xml`,
  `~/work/git-ubuntu/libcamera` branch `pdaf-sideband-wip` (`bf35185`).

## Deferred: publishing the 31.31 kernel rebase

Done locally 2026-09-14, **not pushed**. The `dell-xps9315-2in1` branch was rebased from a
synthetic root at `Ubuntu-7.0.0-29.29` onto a new one at `Ubuntu-7.0.0-31.31`, to match the
running kernel (7.0.0-31-generic). Zero upstream drift in all four patched files, no conflicts,
all 18 commits' content/authors/dates preserved, patched file content bit-for-bit unchanged.

- New root `26ff6f5ff2e9`, new tip `b0e18a8cd92f`.
- Pre-rebase tip saved at `refs/backup/dell-xps9315-2in1-pre-31.31` (`f0712f8df120`).
- `github.com/mward5/linux-xps9315-2in1` `main` is still at `f0712f8df120`.

**Publishing was deliberately deferred until there are significant driver changes worth a
release**, so one force push carries both. When that happens, the order matters:

1. `git push --force github-xps9315 dell-xps9315-2in1:main` in `~/work/git-ubuntu/resolute`.
2. Update the `camera-mipi` submodule pin for `drivers/linux-xps9315-2in1` to the new tip.
3. Commit and push `camera-mipi`.

Doing 1 without 2 breaks `git clone --recurse-submodules` of `camera-mipi` for everyone, because
the pinned commit becomes unreachable on the fork. That clone path is what the README tells
people to use, so this is a real break, not a cosmetic one.

## WP0 outcome — attempted 2026-09-15, twelve rounds, NOT achieved

**The question WP0 exists to answer is still open: we do not know whether the s5k3j1 emits its
PAFi sideband.** The forced-second-input-pin approach could not be made to deliver frames, and
the attempt is stopped here rather than patched further. What it established along the way is
worth more than the attempt cost, and is recorded below.

### What the attempt proved

- **Every V4L2 layer can be satisfied.** Format, route, link validation, stream accounting and
  stream start all succeed. The sideband node reaches its capture loop and blocks.
- **The data type is NOT the variable.** Six candidates failed identically; then the decisive
  control, setting the sideband pin to the very data type the image stream uses, also produced
  nothing — **and starved the image node too**. So a second input pin stops the whole stream
  regardless of what it is labelled.
- **It is not the receiver being re-initialised.** Refcounting the front-end setup changed
  nothing, and the refcount never even reported a second entry.
- **The sensor-side register hypothesis was never tested**, because no configuration ever
  delivered a buffer to compare against.

### Why it stops here

Each round moved the failure strictly later and each found a real bug, but the last three rounds
stopped converging: the symptom is now "both nodes stream, nothing is delivered, no error
anywhere", and the remaining candidates are inside firmware behaviour this driver does not
expose. Further progress needs the real mechanism rather than a forced pin — which is WP1 and
WP2, the streams API and internal pads, and is what upstream is building anyway.

### What is reusable

- `scripts/pdaf-meta-capture.py` — line-based metadata capture over ctypes. Neither `yavta`
  1.32.0 (no metadata formats at all) nor `v4l2-ctl` (no way to pass width/height) can do this.
- `scripts/pdaf-correlate.py` — the phase correlator, verified against synthetic frames with
  known disparities from -6 to +6 and recovering every one exactly. This is the piece WP3 needs.
- `scripts/pdaf-decode.py`, `scripts/pdaf-phase0-capture.sh`, `scripts/pdaf-phase0-dt-sweep.sh`.
- The driver branches `pdaf-phase0-hack` in both driver submodules, as a record of what was
  tried and why each step was needed.

### Hard-won knowledge of the ISYS streaming path

Worth keeping; none of it is documented anywhere obvious.

- `nr_queues` is the count of **active routes**, and `ipu6-isys-queue.c:377` withholds buffers
  from the firmware until the number of streaming nodes equals it. An extra active route
  therefore hangs ordinary single-node capture **silently**.
- The vb2 queue type only becomes metadata on REQBUFS, via `vb2_queue_change_type`, not on
  S_FMT — and link validation picks which format to compare by that queue type.
- `get_stream_mask_by_pipeline` builds its mask from each node's **sink** stream and applies it
  to the node's **source** pad. Those are equal under one-to-one routing, so the conflation is
  invisible until a route breaks the assumption.
- The format-mismatch path in `ipu6_isys_link_validate` logs at **debug** level, so a failed
  capture reports nothing at default log level.
- libcamera **reconfigures the media link topology** on configure(), disabling links set up
  beforehand.

### Recommended next move

**WP5, the soft-ISP denoise work.** It is independent of all of this, addresses the noise the
user actually sees, is open ground upstream, and needs no kernel changes. WP1 and WP2 remain the
correct route to PDAF, but they depend on an unmerged 86-patch kernel series and should not be
started until that lands or is deliberately backported.

**To restore the machine:** `sudo rm /etc/modprobe.d/pdaf-phase0.conf` then reboot. All driver
changes sit behind parameters that default to inert, so no rebuild is needed.
