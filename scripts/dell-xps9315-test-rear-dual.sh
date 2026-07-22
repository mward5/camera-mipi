#!/usr/bin/env bash
# Manual dual-stream rear test (raw + PAFi metadata) without libcamera.
set -euo pipefail

MDEV="${MDEV:-/dev/media0}"
OUT="${1:-/tmp/rear-dual.raw}"
META="${2:-/tmp/rear-pdaf.bin}"

systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
killall -9 wireplumber pipewire cam 2>/dev/null || true
sleep 1

SENSOR=$(media-ctl -d "$MDEV" -e "s5k3j1 1-0010")
CSI2=$(media-ctl -d "$MDEV" -e "Intel IPU6 CSI2 1")
CAP0=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
CAP1=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 9")

echo "Sensor=$SENSOR CSI2=$CSI2"
echo "Raw=$CAP0 PAF=$CAP1"

media-ctl -d "$MDEV" -l "'Intel IPU6 CSI2 1':2 -> 'Intel IPU6 ISYS Capture 9':0[1]"
media-ctl -d "$MDEV" -R "'Intel IPU6 CSI2 1' [0/0->1/0[1],0/1->2/1[1]]"

media-ctl -d "$MDEV" -V "'s5k3j1 1-0010':0/0 [fmt:SGRBG10/3976x2736]"
media-ctl -d "$MDEV" -V "'s5k3j1 1-0010':0/1 [fmt:METAF8/3968x684]"
media-ctl -d "$MDEV" -V "'Intel IPU6 CSI2 1':0/0 [fmt:SGRBG10/3976x2736]"
media-ctl -d "$MDEV" -V "'Intel IPU6 CSI2 1':0/1 [fmt:METAF8/3968x684]"
media-ctl -d "$MDEV" -V "'Intel IPU6 CSI2 1':1/0 [fmt:SGRBG10/3976x2736]"
media-ctl -d "$MDEV" -V "'Intel IPU6 CSI2 1':2/1 [fmt:METAF8/3968x684]"

v4l2-ctl -d "$CAP1" --set-fmt-meta=width=3968,height=684,pixelformat=GEN8
v4l2-ctl -d "$CAP0" --set-fmt-video=width=3976,height=2736,pixelformat=GB10

echo "Starting metadata capture on $CAP1"
v4l2-ctl -d "$CAP1" --stream-mmap --stream-count=1 --stream-to="$META" &
META_PID=$!
sleep 0.5

echo "Starting raw capture on $CAP0"
timeout 45 v4l2-ctl -d "$CAP0" --stream-mmap --stream-count=1 --stream-to="$OUT" || true
wait "$META_PID" || true

ls -la "$OUT" "$META" 2>&1
file "$OUT" "$META" 2>&1
