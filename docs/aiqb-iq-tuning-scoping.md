# Image-quality tuning from Intel AIQ `.aiqb` files — scoping

Status: **scoped, not started.** Reconnaissance done 2026-07-24; no code written yet.

## Goal

Replace ad-hoc, hand-measured image-quality tuning with the real calibration data
Intel/Dell shipped for these exact sensor modules — starting with the colour
correction matrix (CCM), and very likely lens shading correction (LSC) after it.

## Why: the ad-hoc approach already failed once

The rear camera's CCM was measured by hand from white-paper captures on
2026-07-22, shipped, and then **reverted the same day** (`+hi5566`). Two samples
taken under blinds-open daylight didn't generalise — verified in a third room at
~5535K the CCM made colour measurably *worse* than no CCM at all, because the
interpolator clamps to the nearest calibrated node and neither node suited warmer
light. See `STATUS.md`. The conclusion recorded then, and still the right one:
two samples under one lighting condition are not a calibration, and no amount of
care with a sheet of paper turns them into one.

Separately, the front camera's colour is visibly off in a way tuning should fix:
a red shirt renders orange on `hi556` while a Logitech C925e renders it correctly
(user observation, 2026-07-24).

## Key finding: this is *not* a reverse-engineering project

The initial assumption was that `.aiqb` was an opaque binary needing Ghidra work.
It isn't. Everything required is already on this machine, from Intel's own
open-source IPU6 releases:

| What | Where |
| --- | --- |
| Struct definitions | `~/work/intel/ipu6-camera-bins/include/ipu6epmtl/ia_imaging/ia_cmc_types.h` |
| Parser API | `.../ia_imaging/ia_cmc_parser.h` |
| **Working parser library** | `~/work/intel/ipu6-camera-bins/lib/libia_cmc_parser-ipu6epmtl.so.0` |
| AIQB parser library | `.../lib/libia_aiqb_parser-ipu6epmtl.so.0` |
| NVM (EEPROM) parser | `.../lib/libia_nvm-ipu6epmtl.so.0` |

The entry point is:

```c
ia_cmc_t *ia_cmc_parser_init_v1(const ia_binary_data *a_aiqb_binary,
                                const ia_binary_data *a_nvm_binary);
void      ia_cmc_parser_deinit(ia_cmc_t *ia_cmc);
```

Confirmed exported by the shipped `.so` (`nm -D`). So the plan is "link Intel's
parser and print the structs", not "decode a format".

Both Intel repos are live git checkouts (remote `github.com/intel/...`), last
updated 2025-05-20 — `ipu6-camera-bins` at tag base `20240926`, `ipu6-camera-hal`
at `20241122`. The parser is therefore far newer than the 2022 tuning files it
needs to read, which is the easy direction.

## What the parser hands back

`ia_cmc_t` (`ia_cmc_types.h:~1486`) contains, among much else:

- `cmc_parsed_color_matrices` — **the CCM data, the immediate target**
- `cmc_parsed_lens_shading` — **LSC tables**, the biggest remaining visual gap
  against a tuned consumer webcam (soft ISP has no LSC at all today)
- `cmc_parsed_black_level`, `cmc_general_data`,
  `cmc_parsed_analog_gain_conversion`, and more

The CCM payload is exactly the shape needed:

```c
typedef struct {
    cmc_light_source light_src_type; /* A, D50, D55, D65, D75, F1..F12, ... */
    chromaticity_t   chromaticity;   /* sensor R/G, B/G */
    cie_coords_t     cie_coords;     /* CIE x, y  -> gives us a CT */
    int32_t          matrix_accurate[9];   /* each 3 consecutive sum to 1 */
    int32_t          matrix_preferred[9];
} cmc_color_matrix_t;
```

Per-illuminant matrices, each with CIE coordinates and a named light source —
i.e. a real multi-illuminant calibration, which is precisely what the paper
measurements could not produce.

## Why it maps cleanly onto libcamera's soft ISP

Verified in the source, not assumed:

- `src/ipa/simple/algorithms/ccm.cpp` selects the matrix with
  `ccm_.getInterpolated(ct)`, keyed on `activeState.awb.temperatureK`, and the
  tuning file format is a list of `{ ct: <K>, ccm: [9 floats] }` nodes.
  AIQ gives us per-illuminant matrices plus CIE coordinates → derive a CT per
  matrix → emit exactly that list. **Structurally a direct match.**
- Application point matches too. Soft ISP does
  `combinedMatrix = ccm * gainMatrix` (`ccm.cpp`, `awb.cpp`) and the debayer
  applies `combinedMatrix` to the linear raw value before the gamma LUT
  (`debayer_cpu.cpp:807`, `:827`). That is the canonical position — CCM on
  linear data, after white balance, before gamma — which is where AIQ's CCM
  belongs as well.

## Which files, and which one is *ours*

Rear camera (`s5k3j1`), Dell driver only — **Intel ships no `s5k3j1` `.aiqb`
anywhere**, so the Dell blob is the sole source and always will be:

```
reference/windows-driver-artifacts/dell-drivers/Intel-IR-Camera-Driver_.../0/Drivers/Drivers/
  s5k3j1sx04_CJALR11_ADL_PDAF_T2.aiqb      642,208   <- current best guess
  s5k3j1sx04_1BAA01T3_ADL_PDAF_T2.aiqb     610,736
  s5k3j1sx04_1BAA02T3_ADL_PDAF_T2.aiqb     642,200
  s5k3j1sx04_1BAA01T3_ADL_PDAF_MD_T3.aiqb  815,300
  s5k3j1sx04_1BAA01T3_ADL.aiqb             610,736
```

Front camera (`hi556`): Dell ships five variants; Intel's tree has two of the
same names. Dell's is **newer** — embedded build dates are `22122113`
(2022-12-21) for Dell vs `22032407` (2022-03-24) for Intel's — and is the one
matched to this machine.

The middle token (`CJALR11`, `1BAA01T3`, `CJFLE25`, …) is a module/part ID.
**Picking the right file is unresolved and matters**: the wrong module's
calibration is no better than a guess. Best lead is the sensor EEPROM at I2C
`0x50`, which no Linux driver here has ever read, and which the Windows driver
does read (`parsed_nvm_ptr_lsc`, `Failed to Read EEPROM data` strings found in
`s5k3j1sx04.sys`). Note the parser's second argument is exactly that NVM blob,
so reading the EEPROM serves double duty: identifying the module *and* feeding
per-unit calibration into the parse.

## Container format (verified, but we don't need it)

Decoded far enough to sanity-check the parser, no further — the vendor library
does the real work:

```
0x00  "CPFF"  magic
0x04  uint32  total size   (matches file size exactly on all files checked)
0x18  "LCMC"  record       (camera module characterisation - the CCM/LSC data)
0x28  "DFLT"  record
0x38  "AIQB"  record       (nested; contains "LAIQ" sub-records)
0x5C  ASCII   build date, e.g. "22092214" = 2022-09-22 14:xx
0x60+ ASCII   provenance: "IQStudio" 22.38.2.0, "LibIQ" 2.0.359.0, comment
```

## Plan

**Phase 1 — extractor.** Small C program: read `.aiqb` into an `ia_binary_data`,
call `ia_cmc_parser_init_v1(aiqb, NULL)`, walk
`cmc_parsed_color_matrices`, print each matrix with its light source,
chromaticity and CIE coordinates. Success criterion: it parses the *Dell* blob
(not just Intel's) and returns a plausible number of matrices. Run against every
candidate file — differences between module variants are themselves evidence.

**Phase 2 — fixed-point and CT.** Determine the `int32_t` scale factor (the
"each 3 consecutive elements sum to 1" invariant makes this self-checking: the
correct divisor is whatever makes each row sum to 1.0). Convert CIE x/y to a
correlated colour temperature (McCamy's approximation is fine) to key the
libcamera nodes.

**Phase 3 — emit and validate.** Generate the `Ccm:` block for `s5k3j1.yaml` /
`hi556.yaml`. Validate the way the CCM revert taught us to: capture in **at
least three genuinely different lighting conditions**, including one outside the
calibration range, and confirm it is better in all of them — not just the one it
was tuned on. `scripts/agc-analyze-exposure.py` already measures captured
frames; it needs a per-channel/colour-error mode for this.

**Phase 4 (separate, larger) — LSC.** The soft ISP has no lens shading
correction, so this is a new `libipa` algorithm plus a `DebayerParams` change,
not just tuning. Bigger than the CCM work; sequence it after.

## Open questions and risks

1. **Module identification.** Which `.aiqb` matches this unit. Unresolved.
   Read the EEPROM at `0x50` first.
2. **Pipeline equivalence.** The application point matches, but AIQ may assume a
   different white point normalisation or expect `matrix_preferred` vs
   `matrix_accurate`. A matrix that is correct in AIQ's pipeline can still be
   wrong transplanted. This is the trap the paper measurement fell into and the
   reason Phase 3 insists on multi-illuminant validation.
3. **`accurate` vs `preferred`.** Two matrices per illuminant. "Preferred" is
   normally the vendor's aesthetic choice, "accurate" the colorimetric one.
   Try both; the Logitech comparison is a useful reference for which reads right.
4. **Licensing / upstreaming.** These are proprietary Dell/Intel binaries.
   Extracting values for this machine is one thing; **shipping them in an
   upstream patch is a different question**, and this project's stated goal is
   real upstream submission (see `STATUS.md` "Upstream goal"). Worth deciding
   early — it may mean the extracted tuning stays a local/downstream artifact,
   or that only the *extractor* is upstreamable, not its output. Do not sink
   Phase 3 effort before forming a view on this.
5. **ABI match.** `libia_cmc_parser-ipu6epmtl.so.0` is built against a specific
   `ia_cmc_types.h`; use the headers from the *same* checkout, and prefer the
   `ipu6epmtl` variant (this is an ADL/MTL-class part — `ipu6ep`/`ipu6` variants
   also exist in the tree).

## Deliverables

- `scripts/aiqb-dump-cmc.c` (or `.py` via `ctypes`) — the Phase 1 extractor
- A `docs/` note recording, per candidate file, what came out — evidence for the
  module-ID question
- Generated `Ccm:` blocks, validated per Phase 3 before shipping
