#!/usr/bin/env bash
# Is data type 0x30 on the wire? Asked with ONE input pin.
#
# Every previous look configured a second input pin beside the image, and two
# input pins on one virtual channel hang this firmware - accepted, opened,
# started, then nothing delivered and both stop and close timing out. So every
# previous look was blind, and the question is untouched.
#
# s5k3j1's image_dt_override changes the data type the sensor DECLARES for the
# image stream. ipu6_isys_setup_video() copies that into the firmware's single
# input pin, so the receiver looks for a different type without a second pin
# existing at all.
#
#   -1    RAW10, normal - the control, must capture 21,888,000-byte frames
#   0x30  the PAF stream's type, per the Windows driver's own descriptors
#   0x3f  a type nothing should be sending - the negative control
#
# 0x30 behaving like -1   -> it is on the wire
# 0x30 behaving like 0x3f -> it is not
# -1 not capturing        -> harness broken, read nothing else
#
# The forced-pin hack MUST be disarmed: while it is armed its extra route makes
# nr_queues 2 permanently, and a single streaming node then never satisfies
# ipu6-isys-queue.c:377. Remove /etc/modprobe.d/pdaf-twopin.conf and reboot.
#
# Usage: pdaf-image-dt-sweep.sh
set -euo pipefail

IMG_W=3976; IMG_H=2736
DTS=(-1 0x30 0x3f -1 0x30)
PARAM=/sys/module/s5k3j1/parameters/image_dt_override

[ -e "$PARAM" ] || { echo "ERROR: loaded s5k3j1 has no image_dt_override" >&2; exit 1; }
if [ -e /sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad ] &&
   [ "$(cat /sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad)" != "-1" ]; then
	echo "ERROR: the forced pin is still armed (pdaf_hack_pad=$(cat /sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad))." >&2
	echo "       Its extra route pins nr_queues at 2 and no single node can ever" >&2
	echo "       capture. Remove /etc/modprobe.d/pdaf-twopin.conf and reboot." >&2
	exit 1
fi
echo "s5k3j1 srcversion: $(cat /sys/module/s5k3j1/srcversion)"

sudo -v
PW_UNITS=(pipewire.socket pipewire-pulse.socket pipewire.service
	  pipewire-pulse.service wireplumber.service)
RESTORE=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	echo -1 | sudo tee "$PARAM" >/dev/null 2>&1
	if [ "$RESTORE" = 1 ]; then
		systemctl --user unmask "${PW_UNITS[@]}" >/dev/null 2>&1
		systemctl --user start pipewire.socket pipewire.service wireplumber.service >/dev/null 2>&1
	fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

RESTORE=1
systemctl --user mask --now "${PW_UNITS[@]}" >/dev/null 2>&1 || true
sleep 1.5
MDEV=""
for d in /dev/media*; do
	case "$(media-ctl -d "$d" -p 2>/dev/null || true)" in
	*"driver"*"intel-ipu6"*) MDEV="$d"; break ;; esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device" >&2; exit 1; }
IMG_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
CSI2="Intel IPU6 CSI2 1"
echo "media $MDEV  image $IMG_NODE"
echo

printf '| %-5s | %-7s | %-13s | %-9s |\n' "dt" "frames" "bytes/frame" "fw start"
printf '| %-5s | %-7s | %-13s | %-9s |\n' "---" "---" "---" "---"
for dt in "${DTS[@]}"; do
	printf '%d' "$dt" | sudo tee "$PARAM" >/dev/null
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done
	MARK="dtprobe-$dt-$$"; echo "$MARK" | sudo tee /dev/kmsg >/dev/null
	log=$(mktemp)
	timeout 15 stdbuf -oL -eL yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" \
		-n 4 -c5 "$IMG_NODE" > "$log" 2>&1 || true
	frames=$(sed -n 's/^Captured \([0-9]*\) frames.*/\1/p' "$log" | tail -1)
	bytes=$(sed -n 's/^[0-9]* ([0-9]*) \[[^]]*\] [^ ]* [0-9]* \([0-9]*\) B.*/\1/p' "$log" | tail -1)
	klog=$(sudo dmesg | sed -n "/$MARK/,\$p")
	started=$(echo "$klog" | grep -c 'start stream: complete' || true)
	dtsent=$(echo "$klog" | sed -n 's/.*Framedesc:.*dt \(0x[0-9a-f]*\).*/\1/p' | tail -1)
	printf '| %-5s | %-7s | %-13s | %-9s |  declared %s\n' \
		"$dt" "${frames:-0}" "${bytes:-—}" \
		"$([ "${started:-0}" -gt 0 ] && echo yes || echo no)" "${dtsent:-?}"
	rm -f "$log"; sleep 1
done
echo
echo "Read the -1 arms first: they must capture 5 frames of 21888000 bytes."
echo "If they do not, the harness is broken and nothing else here means"
echo "anything. 'declared' echoes the data type the driver actually put in the"
echo "frame descriptor, so a parameter that did not take is visible."
