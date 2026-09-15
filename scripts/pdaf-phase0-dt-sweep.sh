#!/usr/bin/env bash
# PDAF phase-0: sweep candidate CSI-2 data types. THROWAWAY.
#
# Run with sudo - it writes /sys/module/intel_ipu6_isys/parameters/pdaf_hack_dt,
# which is root-only. The parameter is read when a stream is set up, not at
# probe, so no reboot is needed between candidates.
#
# Why: with every V4L2 plumbing problem solved, the ISYS firmware still refuses
# the stream ("stream on Intel IPU6 CSI2 1 failed with -22"). The data type is
# the most likely thing it dislikes. 0x30 is our best guess from the Windows
# I2C trace; these are the plausible alternatives.
#
# Usage: sudo bash pdaf-phase0-dt-sweep.sh [user]
set -uo pipefail

RUN_AS="${1:-mward}"
DTS=(48 49 50 51 18 43)   # 0x30..0x33 user-defined, 0x12 embedded8, 0x2B raw10
PARAM=/sys/module/intel_ipu6_isys/parameters/pdaf_hack_dt
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"

[ -w "$PARAM" ] || { echo "ERROR: cannot write $PARAM (run with sudo)" >&2; exit 1; }
ORIG=$(cat "$PARAM")
restore() { echo "$ORIG" > "$PARAM" 2>/dev/null; echo "restored pdaf_hack_dt=$ORIG"; }
trap restore EXIT INT TERM

for dt in "${DTS[@]}"; do
	printf '\n========== trying dt=%d (%#x) ==========\n' "$dt" "$dt"
	echo "$dt" > "$PARAM"
	MARK=$(date '+%Y-%m-%d %H:%M:%S')
	sudo -u "$RUN_AS" XDG_RUNTIME_DIR="/run/user/$(id -u "$RUN_AS")" \
		timeout 90 bash "$SCRIPTDIR/pdaf-phase0-capture.sh" 8 \
		2>&1 | grep -E "PAF buffers captured|PAF capture exit|distinct|seq=" | head -6
	echo "--- kernel says ---"
	journalctl -k --since "$MARK" 2>/dev/null \
		| grep -iE "stream on|failed with|pdaf_hack: csi2|dangling|time out" \
		| sed 's/^.*kernel: //' | head -4
	sleep 3
done

echo
echo "Any candidate showing 'PAF buffers captured: N' with N>0 is the answer."
