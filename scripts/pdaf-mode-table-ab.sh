#!/usr/bin/env bash
# A/B the stock mode table against the Windows PDAF mode table (s5k3j1
# module param pdaf_win_mode). See docs/pdaf-implementation-plan.md,
# "WP0 resolved on the sensor side".
#
# The question this answers first is NOT "is there PDAF data" - nothing here
# can capture a sideband - but "does the PDAF table stream at all, and does
# anything about the image stream change". The table alters the PLL, lane
# mode, binning and both timings at once, so "no frames" would mean the mode
# does not come up on this receiver, not that the sensor emits nothing.
#
# Arms are interleaved and repeated because this project has been burned by
# unreplicated observations: the CSI-2 error counters in particular are known
# to vary run to run with nothing changed (plan doc, WP0 follow-up section 5).
#
# Usage: pdaf-mode-table-ab.sh [frames] [expected-srcversion]
set -euo pipefail

FRAMES="${1:-40}"
WANT_SRCVERSION="${2:-}"
IMG_W=3976
IMG_H=2736
# stock, win, stock, win - interleaved so drift cannot masquerade as effect.
ARMS=(0 1 0 1)

[ -e /sys/module/s5k3j1/parameters/pdaf_win_mode ] || {
	echo "ERROR: loaded s5k3j1 has no pdaf_win_mode param - wrong module." >&2
	echo "       cat /sys/module/s5k3j1/srcversion" >&2
	exit 1
}

# Always verify what is actually loaded before believing a run: a session on
# 2026-09-16 measured a stale DKMS module for several rounds.
LIVE_SRCVERSION=$(cat /sys/module/s5k3j1/srcversion)
echo "loaded s5k3j1 srcversion: $LIVE_SRCVERSION"
if [ -n "$WANT_SRCVERSION" ] && [ "$LIVE_SRCVERSION" != "$WANT_SRCVERSION" ]; then
	echo "ERROR: expected $WANT_SRCVERSION - a stale module is loaded." >&2
	exit 1
fi

# Escalate once up front so the per-arm sysfs writes and dmesg reads do not
# stop to prompt in the middle of a timed capture.
sudo -v

RESTORE_SERVICES=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	echo 0 | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null 2>&1
	[ "$RESTORE_SERVICES" = "1" ] && \
		systemctl --user start pipewire.socket pipewire wireplumber 2>/dev/null
}
trap cleanup EXIT INT TERM

# Stop the socket first or it reactivates the service and the stop is
# cancelled - which silently leaves the camera held.
systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
RESTORE_SERVICES=1
sleep 1

# Numbering is not stable across boots; a USB webcam has taken media0 before.
MDEV=""
for d in /dev/media*; do
	[ -e "$d" ] || continue
	info=$(media-ctl -d "$d" -p 2>/dev/null || true)
	case "$info" in *"driver"*"intel-ipu6"*) MDEV="$d"; break ;; esac
done
[ -n "$MDEV" ] || { echo "ERROR: no intel-ipu6 media device found" >&2; exit 1; }

IMG_NODE=$(media-ctl -d "$MDEV" -e "Intel IPU6 ISYS Capture 8")
[ -n "$IMG_NODE" ] || { echo "ERROR: could not resolve the image node" >&2; exit 1; }
CSI2="Intel IPU6 CSI2 1"
echo "media device: $MDEV   image node: $IMG_NODE"
echo

# dmesg is usually restricted; only used for the CSI-2 error column.
DMESG="dmesg"
$DMESG >/dev/null 2>&1 || DMESG="sudo dmesg"

run_arm() {
	local mode="$1" label="$2"
	local log; log=$(mktemp)

	echo "$mode" | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null

	# The mode table is chosen in s5k3j1_set_pad_format(), so the subdev
	# S_FMT below is what makes the param take effect - not the module load.
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done

	local since; since=$($DMESG 2>/dev/null | wc -l)

	# No --file: disk throughput must not enter a frame-rate measurement.
	yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c"$FRAMES" \
		"$IMG_NODE" > "$log" 2>&1 || true

	local captured fps bytes vts errs
	captured=$(grep -c '^[0-9]* ([0-9]*)' "$log" || true)
	fps=$(sed -n 's/.*(\([0-9.]*\) fps).*/\1/p' "$log" | tail -1)
	bytes=$(sed -n 's/^[0-9]* ([0-9]*) \[[^]]*\] [^ ]* [0-9]* \([0-9]*\) B.*/\1/p' "$log" | tail -1)
	vts=$(v4l2-ctl -d "$(media-ctl -d "$MDEV" -e 's5k3j1 1-0010')" \
		--get-ctrl vertical_blanking 2>/dev/null | sed 's/.*: //')
	errs=$($DMESG 2>/dev/null | tail -n +"$((since+1))" | grep -c 'csi2-1 error' || true)

	printf '| %-14s | %7s | %9s | %12s | %8s | %6s |\n' \
		"$label" "${captured:-0}" "${fps:-—}" "${bytes:-—}" "${vts:-—}" "${errs:-—}"
	$DMESG 2>/dev/null | tail -n +"$((since+1))" | grep 'csi2-1 error' \
		| sed 's/.*csi2-1 error/    csi2-1 error/' | sort | uniq -c | sed 's/^/  /'
	rm -f "$log"
}

printf '| %-14s | %7s | %9s | %12s | %8s | %6s |\n' \
	"arm" "frames" "fps" "bytes/frame" "vblank" "errs"
printf '| %-14s | %7s | %9s | %12s | %8s | %6s |\n' \
	"---" "---" "---" "---" "---" "---"
for m in "${ARMS[@]}"; do
	[ "$m" = 0 ] && run_arm 0 "stock" || run_arm 1 "pdaf_win_mode"
done

echo
echo "Expected if nothing changed: 3976x2736 x 10bpp packed = 21888000 bytes/frame."
echo "A different byte count or frame geometry is the trustworthy signal here."
echo "Error counts vary run to run with nothing changed - compare arms, not runs."
