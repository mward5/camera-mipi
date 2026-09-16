#!/usr/bin/env bash
# Does the two-pin path starve because the mechanism is broken, or because the
# second data type never arrives on the wire?
#
# The two-pin firmware config is accepted and started - "open complete",
# "start complete" - and then nothing is delivered and both stop and close time
# out. The driver queues buffer lists in PAIRS ("queue buf list ... 2 bufs")
# and completes them together, so if the sideband's data type never arrives the
# pair can never complete and NEITHER node gets a frame. On that reading the
# starve is correct behaviour for an absent data type, not a fault.
#
# The competing reading is that two input pins are broken here whatever the DT.
#
# These differ on one observable: whether the IMAGE node captures frames when
# the sideband pin is pointed at a data type that definitely DOES arrive.
#
#   0x2b  the image's own RAW10 - certain to arrive
#   0x12  embedded 8-bit - plausible; the receiver logs "Inter-frame long
#         packet discarded" on every stream start even unarmed
#   0x30  the PAF candidate the vendor descriptors declare
#
# image captures for 0x2b but not 0x30  -> the mechanism works, 0x30 is absent
# image captures for none of them       -> two input pins are broken here
#
# pdaf_hack_dt is read per stream-start, so this sweeps without rebooting. The
# route still has to be armed at module load - see pdaf-twopin-modprobe.conf.
#
# Usage: pdaf-twopin-dt-sweep.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG_W=3976; IMG_H=2736; PAF_W=3968; PAF_H=684
DTS=(0x2b 0x12 0x30 0x2b)     # repeated: the first arm is also the control
HACK=/sys/module/intel_ipu6_isys/parameters

[ -e "$HACK/pdaf_hack_dt" ] || { echo "ERROR: forced-pin build not loaded" >&2; exit 1; }
[ "$(cat $HACK/pdaf_hack_pad)" = "2" ] || {
	echo "ERROR: pdaf_hack_pad=$(cat $HACK/pdaf_hack_pad), expected 2 - arm at load time" >&2
	exit 1; }

sudo -v
PW_UNITS=(pipewire.socket pipewire-pulse.socket pipewire.service
	  pipewire-pulse.service wireplumber.service)
RESTORE=0; MDEV=""
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null; pkill -f pdaf-meta-capture 2>/dev/null
	echo 48 | sudo tee "$HACK/pdaf_hack_dt" >/dev/null 2>&1
	[ -n "$MDEV" ] && media-ctl -d "$MDEV" \
		-l "\"Intel IPU6 CSI2 1\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [0]" 2>/dev/null
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
for d in /dev/media*; do
	case "$(media-ctl -d "$d" -p 2>/dev/null || true)" in
	*"driver"*"intel-ipu6"*) MDEV="$d"; break ;; esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device" >&2; exit 1; }
IMG_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
PAF_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 9")
CSI2="Intel IPU6 CSI2 1"
PAFDIR="$HOME/work/af-sweep-data/twopin-dtsweep-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PAFDIR"
echo "media $MDEV  image $IMG_NODE  sideband $PAF_NODE"
echo

printf '| %-6s | %-14s | %-14s |\n' "dt" "image frames" "sideband frames"
printf '| %-6s | %-14s | %-14s |\n' "---" "---" "---"
for dt in "${DTS[@]}"; do
	printf '%d' "$dt" | sudo tee "$HACK/pdaf_hack_dt" >/dev/null
	media-ctl -d "$MDEV" -l "\"$CSI2\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [1]" 2>/dev/null
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done
	python3 -u "$HERE/pdaf-meta-capture.py" "$PAF_NODE" --width "$PAF_W" \
		--height "$PAF_H" --set-format-only >/dev/null 2>&1 || true

	il=$(mktemp); pl=$(mktemp)
	timeout 15 python3 -u "$HERE/pdaf-meta-capture.py" "$PAF_NODE" --width "$PAF_W" \
		--height "$PAF_H" --count 5 --outdir "$PAFDIR/dt$dt" > "$pl" 2>&1 &
	pp=$!
	sleep 0.5
	timeout 15 stdbuf -oL -eL yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" \
		-n 4 -c5 "$IMG_NODE" > "$il" 2>&1 &
	ip=$!
	wait $ip 2>/dev/null || true; wait $pp 2>/dev/null || true

	imgf=$(sed -n 's/^Captured \([0-9]*\) frames.*/\1/p' "$il" | tail -1)
	paff=$(grep -c '^frame ' "$pl" 2>/dev/null || echo 0)
	printf '| %-6s | %-14s | %-14s |\n' "$dt" "${imgf:-0}" "${paff:-0}"
	rm -f "$il" "$pl"
	media-ctl -d "$MDEV" -l "\"$CSI2\":2 -> \"Intel IPU6 ISYS Capture 9\":0 [0]" 2>/dev/null
	sleep 1
done
echo
echo "The 0x2b arms are the control: that data type certainly arrives. If the"
echo "image node captures there and not at 0x30, the two-pin mechanism works"
echo "and DT 0x30 simply is not on the wire. If it captures nowhere, two input"
echo "pins are broken here and nothing can be concluded about the sensor."
