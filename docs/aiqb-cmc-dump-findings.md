# AIQB CMC extractor — Phase 1 findings

Status: **Phase 1 complete, 2026-07-27.** `scripts/aiqb-dump-cmc.c` links
Intel's `libia_cmc_parser-ipu6epmtl.so.0` and successfully parses every
Dell `.aiqb` candidate for both `hi556` and `s5k3j1`. See
`docs/aiqb-iq-tuning-scoping.md` for the project background.

## The one framing bug it took to get here

`ia_cmc_parser_init_v1()` does not understand the `.aiqb` file as shipped
on disk. The file is a `"CPFF"`-wrapped envelope (magic + size + checksum)
containing named sub-blocks (`"LCMC"`, `"DFLT"`, `"AIQB"`, ...). Feeding the
parser the whole file makes it walk those tag bytes as if they were a
record size field — `"LCMC"` read as a little-endian `uint32` is
`0x434D434C` (~1.1 GB) — and it segfaults reading far past the buffer
trying to copy that many bytes. This reproduced identically on Intel's own
`TPG1_INTEL.aiqb` / `TPG2_INTEL.aiqb` reference files, which ruled out a
file-specific problem.

The fix: locate the *inner* `"AIQB"`-tagged sub-blob (it has the same
magic+size+reserved+checksum framing as the outer envelope) and hand
*that* to the parser, not the raw file. This is container framing, not
payload decoding — matches the project's "not a reverse-engineering
project" stance. `scripts/aiqb-dump-cmc.c` does this by scanning for the
`"AIQB"` tag and validating that its declared size fits inside the file.

## Second surprise: the data lives in the *advanced* CCM record, not the basic one

Every file tested returns an empty `cmc_parsed_color_matrices` (the
`cmc_color_matrix_t` struct the scoping doc originally targeted). The real
per-illuminant CCM data is in `cmc_parsed_advanced_color_matrix`
(`cmc_acm_color_matrix_t`, float-based, no fixed-point scale question) —
each light source's `traditional_color_matrix` is a ready-to-use 3×3 with
each row already summing to 1.0000. `cmc_lens_shading` (the *new*-format
LSC pointer, not the legacy `cmc_parsed_lens_shading`) is populated too, in
every file — Phase 4 has real data waiting whenever it's picked up.

## hi556 (front camera): module ID resolved

`HI556_1BG502T3_ADL.aiqb` has embedded build date `22122113`
(2022-12-21) — exactly the Dell date the scoping doc identified as
"newer... matched to this machine" (vs `22032407` for Intel's copy of the
same part number). It also carries the comment `"LVI AWB updated"` and is
the fullest of the five candidates. This is the file to use.

| File | Build date | Comment | Light sources | CCM cluster |
| --- | --- | --- | --- | --- |
| **1BG502T3 (chosen)** | 22122113 | LVI AWB updated | 6 (2586K–7000K) | baseline |
| 1BG502TG | 22032407 | NEW_LSC_TUNING | 6 (2586K–7000K) | identical to baseline |
| 1BG508T3 | 22092212 | NEW_LSC_TUNING | 6 (2586K–7000K) | identical to baseline |
| CJFLE25 | 22120607 | Oasis Chicony | 6 (2586K–7000K) | identical to baseline |
| H8B5 | 21110408 | dashiell official release | 7 (2375K–7000K) | different (older/different vendor build) |

Four of five files share the exact same CCM values, differing only in
comment/LSC content — reassuring, since it means the CCM is stable across
these Dell builds and not something that drifted between minor releases.
`H8B5` is the odd one out (oldest build date, different vendor name in the
comment) and is not the match.

## s5k3j1 (rear camera): module ID still open

No build-date shortcut exists here (unlike hi556, the doc never recorded
a target date for the rear module). But the five candidates cluster into
three distinct calibrations:

| File | Size | Light sources | CCM cluster |
| --- | --- | --- | --- |
| 1BAA01T3_ADL | 610,736 | 6 (2671K–7000K-ish) | cluster A |
| 1BAA01T3_ADL_PDAF_T2 | 610,736 | 6 | cluster A (identical to above) |
| 1BAA01T3_ADL_PDAF_MD_T3 | 815,300 | 6 | cluster B (close to A but measurably different) |
| 1BAA02T3_ADL_PDAF_T2 | 642,200 | 7 (2305K–6506K) | cluster C |
| **CJALR11_ADL_PDAF_T2** | 642,208 | 7 (2305K–6506K) | cluster C (identical to 1BAA02T3) |

`CJALR11` (the scoping doc's size-based "current best guess") and
`1BAA02T3` produce byte-for-byte identical CCM tables, which is consistent
with them being the same physical module design under different lot/date
part numbers — but this is still not proof of which module is in *this*
machine. The doc's plan to read the sensor EEPROM at I2C `0x50` remains
the real way to resolve this (see scoping doc, open question 1). Do not
ship a rear-camera CCM before that's done — this is exactly the kind of
unverified guess the earlier CCM revert (`+hi5566`) burned us on.

## Full per-file dumps

Saved for reference in `/tmp/aiqb-dumps/*.txt` this session (not checked
in — regenerate any time with `scripts/aiqb-dump-cmc.c` against
`reference/windows-driver-artifacts/.../Drivers/*.aiqb`).

## Next steps (not started)

1. **hi556 can proceed to Phase 2/3** (CT already given directly by
   `cct` field — no McCamy approximation needed, simpler than the scoping
   doc assumed, since the *advanced* record hands back CCT directly
   rather than just CIE xy). Emit a `Ccm:` block for `hi556.yaml` from
   `HI556_1BG502T3_ADL.aiqb` and validate per Phase 3 (3+ lighting
   conditions, at least one outside calibration range) before shipping.
2. **s5k3j1 blocked on module ID.** Read the EEPROM at `0x50` first.
3. **Licensing decision (doc risk #4) still not made** — worth doing
   before sinking effort into Phase 3 polish for either camera.
