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
#
# AGC locking (2026-07-23, see docs/autofocus-cdaf-scoping.md "Decided
# 2026-07-23: lock, don't normalize"): confirmed gain-driven sharpness noise
# is roughly the same size as the actual cross-position focus signal, and an
# external v4l2-ctl write to analogue_gain gets overwritten by AGC within a
# frame (unlike focus_absolute, which nothing else touches). So locking here
# means temporarily removing `Agc:` from the *local dev build's* tuning file
# (LOCK_AGC=1, the default) - safe because this dev build's YAML
# (~/work/git-ubuntu/libcamera/src/ipa/simple/data/s5k3j1.yaml) is completely
# separate from the system-installed package GNOME Snapshot actually uses, so
# this never affects normal camera use, only this script's own test captures.
# A short pre-warm run (Agc still enabled) picks a reasonable starting
# exposure/gain before the lock takes effect - the goal is a *constant* value
# for the scan, not a "correct" one. The YAML is always restored on exit,
# success or failure, via the same trap mechanism used for the cam process.
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
LOCK_AGC="${LOCK_AGC:-1}"
PREWARM_TIME="${PREWARM_TIME:-4}"  # seconds to let real AGC pick a starting
                                    # exposure/gain before locking it in place
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

CAM_PID=""
# The tuning YAML is loaded from the source tree, not the build directory
# (confirmed via IPAProxy's own "Using tuning file ..." log line) - LIBCAM
# points at .../libcamera/build, so its parent is the source root.
YAML_PATH="$(dirname "$LIBCAM")/src/ipa/simple/data/s5k3j1.yaml"
YAML_BACKUP=""
cleanup() {
	if [ -n "$CAM_PID" ]; then
		kill -9 "$CAM_PID" 2>/dev/null || true
	fi
	if [ -n "$YAML_BACKUP" ] && [ -f "$YAML_BACKUP" ]; then
		mv "$YAML_BACKUP" "$YAML_PATH"
		echo "Restored $YAML_PATH (Agc re-enabled)."
	fi
}

# Self-healing: a prior run that got SIGKILLed (e.g. by an enclosing
# `timeout`, which escalates past SIGTERM and can't be trapped) can leave
# this file mid-edit with Agc still missing. Confirmed happening in
# practice 2026-07-23. Detect and fix it before doing anything else, rather
# than silently running "locked" when the caller didn't ask for that.
if ! grep -q '^  - Agc:$' "$YAML_PATH"; then
	echo "WARNING: $YAML_PATH is missing Agc (likely left over from an" >&2
	echo "  interrupted previous run) - restoring via git checkout before proceeding." >&2
	git -C "$(dirname "$LIBCAM")" checkout -- src/ipa/simple/data/s5k3j1.yaml
	if ! grep -q '^  - Agc:$' "$YAML_PATH"; then
		echo "git checkout didn't fix it either - aborting, needs manual attention" >&2
		exit 1
	fi
fi
trap cleanup EXIT

SENSOR=$(media-ctl -d "$MDEV" -e "s5k3j1 1-0010")
if [ "$LOCK_AGC" = "1" ]; then
	echo "LOCK_AGC=1: pre-warming AGC for ${PREWARM_TIME}s to pick a starting exposure/gain..."
	"$CAM" --camera='\_SB_.PC00.LNK0' \
		-s width="$WIDTH",height="$HEIGHT",role=viewfinder \
		--capture >"$OUTDIR/prewarm.log" 2>&1 &
	PREWARM_PID=$!
	sleep "$PREWARM_TIME"
	kill -INT "$PREWARM_PID" 2>/dev/null || true
	sleep 0.5
	kill -9 "$PREWARM_PID" 2>/dev/null || true
	wait "$PREWARM_PID" 2>/dev/null || true

	EXP=$(v4l2-ctl -d "$SENSOR" --get-ctrl=exposure | grep -oP '\d+$')
	GAIN=$(v4l2-ctl -d "$SENSOR" --get-ctrl=analogue_gain | grep -oP '\d+$')
	echo "Locking at exposure=$EXP analogue_gain=$GAIN (removing Agc from $YAML_PATH for this run)"

	YAML_BACKUP="$OUTDIR/s5k3j1.yaml.orig-backup"
	cp "$YAML_PATH" "$YAML_BACKUP"
	sed -i '/^  - Agc:$/d' "$YAML_PATH"
	if grep -q '^  - Agc:$' "$YAML_PATH"; then
		echo "Failed to remove Agc from $YAML_PATH - aborting rather than running unlocked" >&2
		exit 1
	fi
	# Agc removed means nothing drives these controls anymore - re-assert the
	# pre-warmed values explicitly in case the sensor reset them on re-open.
	v4l2-ctl -d "$SENSOR" -c exposure="$EXP",analogue_gain="$GAIN"
fi

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

if [ "$LOCK_AGC" = "1" ]; then
	echo "Settling ${SETTLE_TIME}s at focus=0 (AGC locked, this is just letting the stream/lens settle, not AGC)..."
else
	echo "Settling ${SETTLE_TIME}s at focus=0 for AGC to converge on the real scene..."
fi
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
CAM_PID=""

echo "Done. frame-*.ppm + capture.log + positions.csv + clock-anchor.txt in $OUTDIR"
# cleanup() still runs on exit below (via the trap) to restore the YAML if it
# was modified for LOCK_AGC - not cleared here on purpose.
