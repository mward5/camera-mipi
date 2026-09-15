#!/usr/bin/env bash
# PDAF phase-0 capture harness - THROWAWAY EXPERIMENT, not part of the shipped stack.
#
# Proves (or disproves) that the s5k3j1 emits its PAFi sideband, by capturing the
# CSI-2 PDAF data type to a metadata node alongside the normal image stream.
# See docs/pdaf-implementation-plan.md, WP0.
#
# Requires the phase-0 module hacks to be loaded:
#   intel-ipu6-isys  pdaf_hack_pad=2 pdaf_hack_port=1 pdaf_hack_vc=0 pdaf_hack_dt=0x30
#   s5k3j1           pdaf_paf_out=1
#
# Usage: pdaf-phase0-capture.sh [frames] [outdir]
set -euo pipefail

FRAMES="${1:-40}"
OUT="${2:-$HOME/work/af-sweep-data/pdaf-phase0-$(date +%Y%m%d-%H%M%S)}"
PAF_W=3968
PAF_H=684
IMG_W=3976
IMG_H=2736
# Lens positions to visit during the run, for the phase-vs-position curve.
POSITIONS=(0 256 512 768 1023)

# --- free the device FIRST: media-ctl can fail while pipewire holds it, which
# --- made device discovery intermittently report "no intel-ipu6 media device".
RESTORE_SERVICES=0
early_cleanup() {
	[ "$RESTORE_SERVICES" = "1" ] && systemctl --user start pipewire.socket pipewire wireplumber 2>/dev/null
}
trap early_cleanup EXIT INT TERM
echo "stopping pipewire/wireplumber for exclusive access"
systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
RESTORE_SERVICES=1
sleep 1

# --- device discovery (numbering is NOT stable across boots; a USB webcam can
# --- take media0, and did on 2026-09-14) -------------------------------------
# NOTE: do not pipe media-ctl into `grep -q` here. grep -q exits on the first
# match, media-ctl then takes SIGPIPE, and `set -o pipefail` fails the whole
# test even though the match succeeded. That race made discovery work five
# times and then start failing. Capture the output first instead.
MDEV=""
for d in /dev/media*; do
	[ -e "$d" ] || continue
	info=$(media-ctl -d "$d" -p 2>/dev/null || true)
	case "$info" in
	*"driver"*"intel-ipu6"*) MDEV="$d"; break ;;
	esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device found" >&2; exit 1; }

ent() { media-ctl -d "$MDEV" -e "$1" 2>/dev/null; }
IMG_NODE=$(ent "Intel IPU6 ISYS Capture 8")
PAF_NODE=$(ent "Intel IPU6 ISYS Capture 9")
SENSOR=$(ent "s5k3j1 1-0010")
LENS=$(ent "lc898217 1-0072")
CSI2="Intel IPU6 CSI2 1"

for v in IMG_NODE PAF_NODE SENSOR LENS; do
	[ -n "${!v}" ] || { echo "ERROR: could not resolve $v" >&2; exit 1; }
done

echo "media device : $MDEV"
echo "image node   : $IMG_NODE   (CSI2 1 pad 1)"
echo "PAF node     : $PAF_NODE   (CSI2 1 pad 2, forced vc0/dt0x30)"
echo "sensor/lens  : $SENSOR / $LENS"
echo "output       : $OUT"
mkdir -p "$OUT"

# --- preconditions ----------------------------------------------------------
if [ ! -e /sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad ]; then
	echo "ERROR: the ISYS phase-0 hack is not loaded (no pdaf_hack_pad param)" >&2; exit 1
fi
HACK_PAD=$(cat /sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad)
PAF_OUT=$(cat /sys/module/s5k3j1/parameters/pdaf_paf_out 2>/dev/null || echo "?")
echo "pdaf_hack_pad=$HACK_PAD  pdaf_paf_out=$PAF_OUT"
[ "$HACK_PAD" = "2" ] || echo "WARNING: pdaf_hack_pad is not 2"
[ "$PAF_OUT" = "1" ]  || echo "WARNING: s5k3j1 pdaf_paf_out is not 1 - sensor may not emit PAF"

# --- full cleanup; ALWAYS put the services back (2026-07-24 lesson) ---
cleanup() {
	set +e
	pkill -f "pdaf-meta-capture.py.*$PAF_NODE" 2>/dev/null
	pkill -f "yavta.*$IMG_NODE" 2>/dev/null
	media-ctl -d "$MDEV" -l "\"$CSI2\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [0]" 2>/dev/null
	if [ "$RESTORE_SERVICES" = "1" ]; then
		echo "restarting pipewire/wireplumber"
		systemctl --user start pipewire.socket pipewire wireplumber 2>/dev/null
	fi
}
trap cleanup EXIT INT TERM

# --- topology + formats -----------------------------------------------------
echo "enabling CSI2 pad 2 -> Capture 9"
media-ctl -d "$MDEV" -l "\"$CSI2\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [1]"

# The image pipeline needs its formats configured before streaming; libcamera
# normally does this, and without it link validation fails with EPIPE on the
# image node - which is why every run before this one captured zero frames on
# both nodes. The PDAF pad's stream-1 format is seeded by the driver in
# init_state, and media-ctl cannot address a stream without the streams API.
echo "setting image pipeline formats (${IMG_W}x${IMG_H})"
for ent in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
	media-ctl -d "$MDEV" -V "$ent [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" 2>&1 | sed "s|^|  set $ent: |"
done
# The image node's pipeline start validates the sideband link too, and that
# check compares the seeded pad format against THIS node's format. Set it now,
# or the image node fails with EPIPE - silently, since that mismatch is logged
# at debug level only (ipu6-isys-video.c, format mismatch path).
echo "pre-setting the PAF node format"
python3 "$(dirname "$0")/pdaf-meta-capture.py" "$PAF_NODE" \
	--width "$PAF_W" --height "$PAF_H" --set-format-only 2>&1 | sed 's/^/  /'

echo "resulting pipeline formats:"
media-ctl -d "$MDEV" -p 2>/dev/null | grep -E "^- entity .*(CSI2 1|s5k3j1)|fmt:" | sed 's/^/  /' | head -12

# --- capture ----------------------------------------------------------------
# yavta 1.32.0 knows no metadata formats, and v4l2-ctl's --set-fmt-meta takes
# only a fourcc with no way to pass width/height, which a line-based metadata
# format requires. Hence our own tool.
# The image node must start FIRST. The PDAF sink stream is stripped before the
# sensor is asked for anything, so a PDAF-only start never brings it up.
echo "starting image stream ($FRAMES frames) on $IMG_NODE"
yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c"$FRAMES" \
	--file="$OUT/img-#.raw" "$IMG_NODE" \
	> "$OUT/yavta-img.log" 2>&1 &
IMG_PID=$!
sleep 2

echo "starting PAF capture ($FRAMES frames) on $PAF_NODE"
python3 "$(dirname "$0")/pdaf-meta-capture.py" "$PAF_NODE" \
	--width "$PAF_W" --height "$PAF_H" --count "$FRAMES" --outdir "$OUT" \
	> "$OUT/paf-capture.log" 2>&1 &
PAF_PID=$!

# drive the lens through known positions while both streams run
( sleep 2
  for p in "${POSITIONS[@]}"; do
	v4l2-ctl -d "$LENS" --set-ctrl focus_absolute="$p" 2>/dev/null
	echo "$(date +%s.%N) $p" >> "$OUT/lens-positions.txt"
	sleep 1.5
  done ) &
LENS_PID=$!

# set -e must not abort on a non-zero child; we want to report it.
PAF_RC=0
wait $PAF_PID || PAF_RC=$?
wait $IMG_PID 2>/dev/null || true
wait $LENS_PID 2>/dev/null || true

# --- report -----------------------------------------------------------------
echo
echo "=== result ==="
echo "PAF capture exit: $PAF_RC"
echo "--- capture log ---"; sed 's/^/  /' "$OUT/paf-capture.log" 2>/dev/null | tail -25
NPAF=$(ls "$OUT"/paf-*.bin 2>/dev/null | wc -l)
echo "PAF buffers captured: $NPAF"
if [ "$NPAF" -gt 0 ]; then
	echo "sizes:   $(stat -c%s "$OUT"/paf-*.bin 2>/dev/null | sort -u | tr '\n' ' ')"
	echo "entropy check (unique bytes in first buffer):"
	od -An -tu1 -v "$(ls "$OUT"/paf-*.bin | head -1)" 2>/dev/null | tr -s ' ' '\n' | sort -u | wc -l \
		| sed 's/^/  distinct byte values: /'
fi
echo
echo "CSI-2 receiver errors during the run:"
journalctl -k --since "-2min" 2>/dev/null | grep -c "csi2-1 error" | sed 's/^/  csi2-1 error lines: /'
echo
echo "output in $OUT"
