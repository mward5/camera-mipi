#!/bin/bash
# Builds scripts/aiqb-dump-cmc.c against Intel's shipped ipu6epmtl parser lib.
# See docs/aiqb-iq-tuning-scoping.md for why this variant and not ipu6/ipu6ep.
set -euo pipefail

IPU6_BINS="$HOME/work/intel/ipu6-camera-bins"
INCLUDE="$IPU6_BINS/include/ipu6epmtl/ia_imaging"
LIBDIR="$IPU6_BINS/lib"
OUT="$(dirname "$0")/aiqb-dump-cmc"

gcc -Wall -Wextra -I"$INCLUDE" \
    "$(dirname "$0")/aiqb-dump-cmc.c" \
    -o "$OUT" \
    -L"$LIBDIR" -Wl,-rpath,"$LIBDIR" -Wl,--disable-new-dtags \
    -l:libia_cmc_parser-ipu6epmtl.so.0

echo "built: $OUT"
