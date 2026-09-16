#!/usr/bin/env bash
# Is data type 0x30 on the wire? Asked with one RAW MIPI input pin.
#
# The 10-bit version of this test (pdaf-image-dt-sweep.sh) found 0x30
# indistinguishable from a type nothing sends. It left one confound: 10-bit
# Bayer has bpp != bpp_packed, so ipu6_isys_fw_pin_cfg() builds a
# PIN_TYPE_RAW_SOC pin - the SoC conversion path, which expects RAW10 pixel
# data. Capturing nothing through it is consistent with "0x30 absent" and with
# "0x30 present but unconsumable by that path".
#
# An 8-bit format has bpp == bpp_packed and yields PIN_TYPE_MIPI with
# MIPI_STORE_MODE_DISCARD_LONG_HEADER: a raw packet store that keeps whatever
# arrives on the pin's data type. s5k3j1's image_code_8bit advertises the image
# stream as 8-bit all the way down, so link validation passes.
#
# Arms, in order, each (8bit, dt):
#   0,-1    10-bit baseline, the configuration known to work
#   1,-1    8-bit control - MUST capture, or the 8-bit path itself is broken
#           and every 8-bit row below is meaningless
#   1,0x30  the question
#   1,0x3f  negative control, nothing sends this
#   1,0x30  repeated
#   1,-1    8-bit control repeated
#
# Requires the forced pin DISARMED - while armed, its route pins nr_queues at 2
# and no single node can capture.
set -euo pipefail

W=3976; H=2736
DTP=/sys/module/s5k3j1/parameters/image_dt_override
BP=/sys/module/s5k3j1/parameters/image_code_8bit
ARMS=("0 -1" "1 -1" "1 0x30" "1 0x3f" "1 0x30" "1 -1")

for f in "$DTP" "$BP"; do
	[ -e "$f" ] || { echo "ERROR: $f missing - wrong s5k3j1 build" >&2; exit 1; }
done
H_PAD=/sys/module/intel_ipu6_isys/parameters/pdaf_hack_pad
if [ -e "$H_PAD" ] && [ "$(cat $H_PAD)" != "-1" ]; then
	echo "ERROR: forced pin still armed - remove /etc/modprobe.d/pdaf-twopin.conf and reboot" >&2
	exit 1
fi
echo "s5k3j1 srcversion: $(cat /sys/module/s5k3j1/srcversion)"

sudo -v
PW=(pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service)
RESTORE=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	echo -1 | sudo tee "$DTP" >/dev/null 2>&1
	echo 0  | sudo tee "$BP"  >/dev/null 2>&1
	if [ "$RESTORE" = 1 ]; then
		systemctl --user unmask "${PW[@]}" >/dev/null 2>&1
		systemctl --user start pipewire.socket pipewire.service wireplumber.service >/dev/null 2>&1
	fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

RESTORE=1
systemctl --user mask --now "${PW[@]}" >/dev/null 2>&1 || true
sleep 1.5
MDEV=""
for d in /dev/media*; do
	case "$(media-ctl -d "$d" -p 2>/dev/null || true)" in
	*"driver"*"intel-ipu6"*) MDEV="$d"; break ;; esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device" >&2; exit 1; }
NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
CSI2="Intel IPU6 CSI2 1"
echo "media $MDEV  image $NODE"
echo
printf '| %-5s | %-5s | %-7s | %-12s | %s\n' "8bit" "dt" "frames" "bytes/frame" "pin"
printf '| %-5s | %-5s | %-7s | %-12s | %s\n' "---" "---" "---" "---" "---"

for arm in "${ARMS[@]}"; do
	set -- $arm; eightbit=$1; dt=$2
	echo "$eightbit" | sudo tee "$BP"  >/dev/null
	printf '%d' "$dt" | sudo tee "$DTP" >/dev/null
	if [ "$eightbit" = 1 ]; then MBUS=SGRBG8_1X8; PIX=SGRBG8; else MBUS=SGRBG10_1X10; PIX=SGRBG10; fi
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:${MBUS}/${W}x${H}]" >/dev/null 2>&1 || true
	done
	got=$(media-ctl -d "$MDEV" -p 2>/dev/null | grep -A3 'entity.*CSI2 1' | sed -n 's/.*fmt:\([A-Z0-9_]*\)\/.*/\1/p' | tail -1)
	log=$(mktemp)
	timeout 15 stdbuf -oL -eL yavta --no-query -f "$PIX" -s "${W}x${H}" -n 4 -c5 \
		"$NODE" > "$log" 2>&1 || true
	frames=$(sed -n 's/^Captured \([0-9]*\) frames.*/\1/p' "$log" | tail -1)
	bytes=$(grep -oE '^[0-9]+ \([0-9]+\).* ([0-9]+) B ' "$log" | awk '{print $(NF-1)}' | tail -1)
	printf '| %-5s | %-5s | %-7s | %-12s | %s\n' \
		"$eightbit" "$dt" "${frames:-0}" "${bytes:-—}" "${got:-?}"
	rm -f "$log"; sleep 1
done
echo
echo "Read the two 1,-1 arms first: the 8-bit path must capture. If it does not,"
echo "every 8-bit row is meaningless and this test has not run."
echo "Then 1,0x30 against 1,0x3f: alike means 0x30 is not on the wire; 0x30"
echo "capturing anything at all means it is."
