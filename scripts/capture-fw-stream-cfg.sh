#!/usr/bin/env bash
# Capture the ISYS firmware stream configuration that the driver actually
# sends, for a normal working single-node capture.
#
# ipu6_fw_isys_dump_stream_cfg() has always logged the whole structure - pin
# counts, and per input pin the data type, mapped_dt, bits per pixel and input
# resolution - at debug level, from ipu6-isys-video.c:552, immediately before
# it goes to firmware. Nothing in twelve rounds of WP0 ever turned it on, and
# the same is true of the link-validation format mismatch, which also logs at
# debug level and so reported nothing at all when a capture failed.
#
# This is the control: what a KNOWN-GOOD config looks like. Anything compared
# against it later - a second input pin, or the real streams API in WP1 - needs
# this to compare to.
#
# Usage: capture-fw-stream-cfg.sh [outfile]
set -euo pipefail

OUT="${1:-$HOME/work/af-sweep-data/fw-stream-cfg-$(date +%Y%m%d-%H%M%S).txt}"
IMG_W=3976
IMG_H=2736
DD=/sys/kernel/debug/dynamic_debug/control

sudo -v
sudo test -w "$DD" || { echo "ERROR: $DD not writable - is debugfs mounted?" >&2; exit 1; }

PW_UNITS=(pipewire.socket pipewire-pulse.socket pipewire.service
	  pipewire-pulse.service wireplumber.service)
RESTORE=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	# Leave the log level as we found it, or every future capture is noisy.
	echo 'func ipu6_fw_isys_dump_stream_cfg -p' | sudo tee "$DD" >/dev/null 2>&1
	echo 'file ipu6-isys-video.c -p' | sudo tee "$DD" >/dev/null 2>&1
	if [ "$RESTORE" = 1 ]; then
		systemctl --user unmask "${PW_UNITS[@]}" >/dev/null 2>&1
		systemctl --user start pipewire.socket pipewire.service \
			wireplumber.service >/dev/null 2>&1
	fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

RESTORE=1
systemctl --user mask --now "${PW_UNITS[@]}" >/dev/null 2>&1 || true
sleep 1.5

MDEV=""
for d in /dev/media*; do
	info=$(media-ctl -d "$d" -p 2>/dev/null || true)
	case "$info" in *"driver"*"intel-ipu6"*) MDEV="$d"; break ;; esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device" >&2; exit 1; }
IMG_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
CSI2="Intel IPU6 CSI2 1"

# The cfg dump itself, plus all of ipu6-isys-video.c - that file carries the
# link-validation mismatch path and the per-node vc/dt derivation, both of
# which are debug-level and both of which matter here.
echo 'func ipu6_fw_isys_dump_stream_cfg +p' | sudo tee "$DD" >/dev/null
echo 'file ipu6-isys-video.c +p' | sudo tee "$DD" >/dev/null
echo "dynamic debug enabled for the cfg dump and ipu6-isys-video.c"

MARK="fw-cfg-capture-$$"
echo "$MARK" | sudo tee /dev/kmsg >/dev/null

for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
	media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
done

echo "capturing 10 frames on $IMG_NODE"
yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c10 "$IMG_NODE" 2>&1 | tail -2

sleep 0.5
mkdir -p "$(dirname "$OUT")"
sudo dmesg | sed -n "/$MARK/,\$p" > "$OUT"
echo
echo "=== firmware stream config as sent (control: one node, working) ==="
grep -E 'nof_input_pins|nof_output_pins|input pin|output_pin|\.dt |\.mapped_dt|\.bits_per_pix|\.input_res|\.input_pin_id|\.output_res|\.stride|\.pt |src_stream|Framedesc' "$OUT" \
	| sed 's/^.*isys\.[0-9]*: //' | sed 's/^/  /'
echo
echo "full log: $OUT  ($(wc -l < "$OUT") lines)"
