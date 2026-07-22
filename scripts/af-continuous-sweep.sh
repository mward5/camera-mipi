#!/usr/bin/env bash
# Phase 1 continuous-session AF sweep harness (see docs/autofocus-cdaf-scoping.md
# Phase 0's "Run 2026-07-22" results): scripts/af-sweep-measure.sh's per-position
# separate `cam` processes let AGC state leak across positions (exposure is a
# persisted V4L2 hardware register, and AGC never reconverges from scratch in a
# 6-frame burst) - this script instead runs ONE continuous `cam` capture session
# and writes focus_absolute from this script concurrently, while cam streams in
# the background. That's much closer to how a real hill-climb algorithm would
# actually operate (continuous stream, focus changed mid-stream) and lets AGC
# converge once at the start rather than resetting every position.
#
# Captures at a reduced resolution (default 800x600, ~1.4MB/frame vs. ~33MB at
# full sensor resolution) so a real sweep with good settle-time resolution
# (many frames per position) stays a few hundred MB instead of many GB.
#
# cam's own per-frame timestamps are on a different clock epoch than
# /proc/uptime (confirmed empirically 2026-07-22 - looks like CLOCK_MONOTONIC,
# which doesn't include suspended time, vs. /proc/uptime which does on this
# kernel - the two were about 120s apart on a freshly-booted-but-once-suspended
# system). So this script calibrates a one-time offset from the first observed
# frame, rather than assuming the clocks match.
set -euo pipefail

OUTDIR="${1:-/tmp/af-continuous}"
STEP="${STEP:-64}"            # focus_absolute units between sweep positions
HOLD_TIME="${HOLD_TIME:-1.0}" # seconds to hold each position before the next
SETTLE_TIME="${SETTLE_TIME:-2.5}"  # seconds at focus=0 before the sweep starts,
                                    # to let AGC converge on the real scene once
WIDTH="${WIDTH:-800}"
HEIGHT="${HEIGHT:-600}"
LIBCAM="${LIBCAM:-$HOME/work/git-ubuntu/libcamera/build}"
CAM="${CAM:-$LIBCAM/src/apps/cam/cam}"
FOCUS_MIN=0
FOCUS_MAX=1023

mkdir -p "$OUTDIR"
POSCSV="$OUTDIR/positions.csv"
CAMLOG="$OUTDIR/capture.log"
echo "uptime,position" >"$POSCSV"

systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
killall -9 wireplumber pipewire cam 2>/dev/null || true
sleep 1

# Media device numbering isn't stable across boots (see
# scripts/af-sweep-measure.sh's header) - find it by driver name.
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
echo "MDEV=$MDEV Lens=$LENS"

export LD_LIBRARY_PATH="$LIBCAM/src/libcamera:${LD_LIBRARY_PATH:-}"
export LIBCAMERA_IPA_MODULE_PATH="$LIBCAM/src/ipa/simple"
export LIBCAMERA_DISABLE_IPU6_PDAF="${LIBCAMERA_DISABLE_IPU6_PDAF:-1}"

# Known starting position before the stream (and AGC settle window) begins.
v4l2-ctl -d "$LENS" -c focus_absolute=0

NPOS=$(( (FOCUS_MAX - FOCUS_MIN) / STEP + 1 ))
EST_SECONDS=$(python3 -c "print($SETTLE_TIME + $NPOS*$HOLD_TIME + 3)")
EST_FRAMES=$(python3 -c "print(int(($EST_SECONDS)*26)+50)")  # generous cap; we stop early via SIGINT
echo "~$NPOS positions, estimated run ~${EST_SECONDS}s, capture cap $EST_FRAMES frames"

"$CAM" --camera='\_SB_.PC00.LNK0' \
	-s width="$WIDTH",height="$HEIGHT",role=viewfinder \
	--capture="$EST_FRAMES" \
	--file="$OUTDIR/frame-#.ppm" \
	--metadata >"$CAMLOG" 2>&1 &
CAM_PID=$!
trap 'kill -9 "$CAM_PID" 2>/dev/null || true' EXIT

echo "Waiting for first frame to calibrate the clock offset..."
FIRST_LINE=""
for _ in $(seq 1 100); do
	FIRST_LINE=$(grep -m1 "seq: 000000" "$CAMLOG" 2>/dev/null || true)
	[ -n "$FIRST_LINE" ] && break
	sleep 0.1
done
if [ -z "$FIRST_LINE" ]; then
	echo "Timed out waiting for the first frame - is the camera stack up? See $CAMLOG" >&2
	exit 1
fi
ANCHOR_UPTIME=$(cut -d' ' -f1 /proc/uptime)
ANCHOR_CAMCLOCK=$(echo "$FIRST_LINE" | awk '{print $1}')
echo "anchor_uptime=$ANCHOR_UPTIME anchor_camclock=$ANCHOR_CAMCLOCK" | tee "$OUTDIR/clock-anchor.txt"

echo "Settling ${SETTLE_TIME}s at focus=0 for AGC to converge on the real scene..."
sleep "$SETTLE_TIME"

for ((pos = FOCUS_MIN; pos <= FOCUS_MAX; pos += STEP)); do
	v4l2-ctl -d "$LENS" -c focus_absolute="$pos"
	UPTIME=$(cut -d' ' -f1 /proc/uptime)
	echo "$UPTIME,$pos" >>"$POSCSV"
	echo "focus_absolute=$pos at uptime=$UPTIME"
	sleep "$HOLD_TIME"
done

echo "Sweep done, letting a trailing buffer of frames land..."
sleep 0.5
kill -INT "$CAM_PID" 2>/dev/null || true
sleep 1
kill -9 "$CAM_PID" 2>/dev/null || true
wait "$CAM_PID" 2>/dev/null || true
trap - EXIT

echo "Done. frame-*.ppm + capture.log + positions.csv + clock-anchor.txt in $OUTDIR"
