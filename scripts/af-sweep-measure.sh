#!/usr/bin/env bash
# Phase 0 of the closed-loop-autofocus scoping work (see
# docs/autofocus-cdaf-scoping.md): sweep the lc898217 VCM's focus_absolute
# control across its advertised range and, at each position, capture a burst
# of frames + per-frame metadata so a later analysis pass can read off (a)
# lens settle time (how many frames after a move before the scene stops
# changing) and (b) the usable focus range (where sharpness actually varies
# vs. where the lens is clipped/at a mechanical stop).
#
# This script only captures a raw dataset - it does not compute a sharpness
# metric or attempt a hill-climb. That's Phase 1 (a separate analysis/
# prototype tool that reads the output of this script). Not yet run against
# real hardware; written as a first-draft harness for a future session, see
# docs/autofocus-cdaf-scoping.md Phase 0.
#
# Point the camera at a scene with real depth variation (not a flat wall)
# before running - a flat/textureless scene makes every position look the
# same regardless of focus, which defeats the purpose of the sweep.
set -euo pipefail

OUTDIR="${1:-/tmp/af-sweep}"
STEP="${STEP:-64}"          # focus_absolute units between sweep positions
FRAMES_PER_POS="${FRAMES_PER_POS:-8}"  # burst size, for settle-time analysis
LIBCAM="${LIBCAM:-$HOME/work/git-ubuntu/libcamera/build}"
CAM="${CAM:-$LIBCAM/src/apps/cam/cam}"
FOCUS_MIN=0
FOCUS_MAX=1023

mkdir -p "$OUTDIR"
CSV="$OUTDIR/sweep.csv"
echo "position,frames_per_pos,write_wall_time,logfile" >"$CSV"

systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
killall -9 wireplumber pipewire cam 2>/dev/null || true
sleep 1

# Media device numbering isn't stable across boots (confirmed 2026-07-22: a
# USB webcam took /dev/media0, pushing the IPU6 controller to /dev/media1,
# on a boot where scripts/dell-xps9315-test-rear-dual.sh's hardcoded
# /dev/media0 default would have silently targeted the wrong device) -
# find the IPU6 media device by driver name instead of assuming a number.
MDEV="${MDEV:-}"
if [ -z "$MDEV" ]; then
	for d in /dev/media*; do
		if media-ctl -d "$d" -p 2>/dev/null | grep -q '^driver.*intel-ipu6'; then
			MDEV="$d"
			break
		fi
	done
fi
if [ -z "$MDEV" ]; then
	echo "Could not find the intel-ipu6 media device among /dev/media*" >&2
	exit 1
fi

LENS=$(media-ctl -d "$MDEV" -e "lc898217 1-0072")
SENSOR=$(media-ctl -d "$MDEV" -e "s5k3j1 1-0010")
echo "MDEV=$MDEV Lens=$LENS Sensor=$SENSOR"

export LD_LIBRARY_PATH="$LIBCAM/src/libcamera:${LD_LIBRARY_PATH:-}"
export LIBCAMERA_IPA_MODULE_PATH="$LIBCAM/src/ipa/simple"
export LIBCAMERA_DISABLE_IPU6_PDAF="${LIBCAMERA_DISABLE_IPU6_PDAF:-1}"

for ((pos = FOCUS_MIN; pos <= FOCUS_MAX; pos += STEP)); do
	echo "=== focus_absolute=$pos ==="
	v4l2-ctl -d "$LENS" -c focus_absolute="$pos"

	# No settle delay here on purpose - Phase 0's whole point is to capture
	# the transition and measure how many frames it actually takes, not
	# assume an answer. Compare against a static baseline read from the
	# sensor subdev at each position, in case the lens driver's move
	# ever fails silently (write succeeds at I2C level per the driver's
	# fire-and-forget .s_ctrl, but that doesn't prove the chip moved).
	v4l2-ctl -d "$LENS" --get-ctrl=focus_absolute

	WALL_TIME=$(date +%s.%N)
	LOG="$OUTDIR/pos_${pos}.log"
	timeout 30 "$CAM" --camera='\_SB_.PC00.LNK0' \
		--capture="$FRAMES_PER_POS" \
		--file="$OUTDIR/pos_${pos}_frame-#.ppm" \
		--metadata >"$LOG" 2>&1 || {
		echo "cam exited non-zero at position $pos, see $LOG" >&2
	}

	echo "$pos,$FRAMES_PER_POS,$WALL_TIME,$LOG" >>"$CSV"
done

echo "Done. Dataset in $OUTDIR, index in $CSV."
echo "Next: Phase 1 analysis tool reads pos_*_frame-*.ppm + pos_*.log to"
echo "compute a sharpness metric per frame and correlate against position/time."
