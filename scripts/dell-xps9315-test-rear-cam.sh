#!/usr/bin/env bash
# Quick rear camera capture test (stop PipeWire, run cam once).
set -euo pipefail

OUT="${1:-/tmp/rear.ppm}"
LIBCAM="${LIBCAM:-$HOME/work/git-ubuntu/libcamera/build}"
CAM="${CAM:-$LIBCAM/src/apps/cam/cam}"

systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
killall -9 wireplumber pipewire cam 2>/dev/null || true
sleep 1

export LD_LIBRARY_PATH="$LIBCAM/src/libcamera:${LD_LIBRARY_PATH:-}"
export LIBCAMERA_IPA_MODULE_PATH="$LIBCAM/src/ipa/simple"
# Dual PAFi sideband is experimental; set to 0 to try Capture 9 path:
export LIBCAMERA_DISABLE_IPU6_PDAF="${LIBCAMERA_DISABLE_IPU6_PDAF:-1}"

echo "Testing rear LNK0 -> $OUT (cam: $CAM)"
echo "LIBCAMERA_DISABLE_IPU6_PDAF=$LIBCAMERA_DISABLE_IPU6_PDAF"
timeout 45 "$CAM" --camera='\_SB_.PC00.LNK0' --capture=1 --file="$OUT" || {
	echo "cam exited $?" >&2
	killall -9 cam 2>/dev/null || true
	exit 124
}
ls -la "$OUT"
file "$OUT"
