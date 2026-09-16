#!/usr/bin/env bash
# Capture the ISYS firmware stream configuration when TWO input pins are
# configured on one virtual channel - the other half of the comparison whose
# control scripts/capture-fw-stream-cfg.sh took.
#
# Twelve rounds of WP0 debugged this configuration failing to deliver a buffer,
# and never captured what the driver actually sent to firmware.
# ipu6_fw_isys_dump_stream_cfg() has always logged it at debug level.
#
# The capture is EXPECTED to fail. The dump happens in
# ipu6_isys_video_set_streaming() before the firmware call, so the
# configuration is logged whether or not any frame ever arrives. Do not read a
# failed capture as a failed run - read the cfg.
#
# Requires the forced pin armed at module load: install
# scripts/pdaf-twopin-modprobe.conf as /etc/modprobe.d/pdaf-twopin.conf and
# reboot first.
#
# Usage: pdaf-twopin-cfg-dump.sh [outfile]
set -euo pipefail

OUT="${1:-$HOME/work/af-sweep-data/fw-cfg-twopin-$(date +%Y%m%d-%H%M%S).txt}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG_W=3976; IMG_H=2736
PAF_W=3968; PAF_H=684
DD=/proc/dynamic_debug/control

HACK=/sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad
[ -e "$HACK" ] || { echo "ERROR: loaded intel-ipu6-isys has no pdaf_hack_pad." >&2
	echo "       Wrong module - install the pdaf-phase0-twopin build." >&2; exit 1; }
if [ "$(cat $HACK)" != "2" ]; then
	echo "ERROR: pdaf_hack_pad is $(cat $HACK), expected 2." >&2
	echo "       It must be set at module load: install" >&2
	echo "       scripts/pdaf-twopin-modprobe.conf and reboot." >&2
	exit 1
fi
echo "forced pin armed: pad=$(cat $HACK) vc=$(cat ${HACK%pad}vc) dt=$(cat ${HACK%pad}dt)"

sudo -v
PW_UNITS=(pipewire.socket pipewire-pulse.socket pipewire.service
	  pipewire-pulse.service wireplumber.service)
RESTORE=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	pkill -f "pdaf-meta-capture" 2>/dev/null
	echo 'func ipu6_fw_isys_dump_stream_cfg -p' | sudo tee "$DD" >/dev/null 2>&1
	echo 'file ipu6-isys-video.c -p' | sudo tee "$DD" >/dev/null 2>&1
	echo 'file ipu6-isys-queue.c -p' | sudo tee "$DD" >/dev/null 2>&1
	[ -n "${MDEV:-}" ] && media-ctl -d "$MDEV" \
		-l "\"Intel IPU6 CSI2 1\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [0]" 2>/dev/null
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
PAF_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 9")
CSI2="Intel IPU6 CSI2 1"
echo "media $MDEV  image $IMG_NODE  sideband $PAF_NODE"

# queue.c carries the nr_streaming/nr_queues accounting, which is the other
# thing that can silently withhold buffers.
for spec in 'func ipu6_fw_isys_dump_stream_cfg +p' 'file ipu6-isys-video.c +p' \
	    'file ipu6-isys-queue.c +p'; do
	echo "$spec" | sudo tee "$DD" >/dev/null
done

MARK="twopin-cfg-$$"
echo "$MARK" | sudo tee /dev/kmsg >/dev/null

media-ctl -d "$MDEV" -l "\"$CSI2\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [1]"
for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
	media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
done
python3 -u "$HERE/pdaf-meta-capture.py" "$PAF_NODE" --width "$PAF_W" \
	--height "$PAF_H" --set-format-only 2>&1 | sed 's/^/  metafmt: /'

echo "starting both nodes (the capture is expected to fail; the cfg is the point)"
timeout 20 yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c10 "$IMG_NODE" \
	>/dev/null 2>&1 &
IMG_PID=$!
sleep 0.5
timeout 20 python3 -u "$HERE/pdaf-meta-capture.py" "$PAF_NODE" --width "$PAF_W" \
	--height "$PAF_H" --count 10 >/dev/null 2>&1 &
PAF_PID=$!
wait $IMG_PID 2>/dev/null || true
wait $PAF_PID 2>/dev/null || true

sleep 0.5
mkdir -p "$(dirname "$OUT")"
sudo dmesg | sed -n "/$MARK/,\$p" > "$OUT"
echo
echo "=== firmware stream config as sent (two input pins) ==="
grep -E 'nof_input_pins|nof_output_pins|input pin|output_pin|\.dt |\.mapped_dt|\.bits_per_pix|\.input_res|\.input_pin_id|\.output_res|\.stride|\.pt |Framedesc|pdaf_hack|queue [0-9]+ of|not streaming yet|No buffers|link format|source_stream' "$OUT" \
	| sed 's/^.*isys\.[0-9]*: //' | sed 's/^/  /'
echo
echo "full log: $OUT  ($(wc -l < "$OUT") lines)"
echo
echo "Compare against the single-node control: nof_input_pins=1, dt 0x2b,"
echo "bits_per_pix 10, mapped_dt 0x40, input_res 3976x2736, one output pin,"
echo "input_pin_id 0, stride 8000, pt 3."
