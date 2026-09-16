#!/usr/bin/env bash
# Read the s5k3j1's discriminating registers back over I2C while it streams,
# for each of the two mode tables (s5k3j1 module param pdaf_win_mode).
#
# Everything measured so far infers the sensor's state from its output: the
# Windows PDAF table streams, but its binning and PLL differences produce no
# observable change. This asks the sensor directly - did the writes land?
#
#   values match the PDAF table  -> the sensor accepted them and simply does
#                                   not behave as we assume these registers mean
#   values match the stock table -> something is overwriting them after the
#                                   mode table is applied
#
# Reads are non-destructive, but they do share the bus with the driver, which
# writes exposure and gain each frame. -f is required because the address is
# claimed. Run only when you are prepared for the stream to be disturbed.
#
# Usage: pdaf-sensor-readback.sh [expected-srcversion]
set -euo pipefail

WANT_SRCVERSION="${1:-}"
BUS=1
ADDR=0x10
IMG_W=3976
IMG_H=2736

# reg:name:stock:pdaf  - the nine that tell the two tables apart, plus the
# PD block that is present only in the PDAF table.
REGS=(
	"0x0114:CSI_LANE_MODE:0x0300:0x0301"
	"0x0300:VT_PIX_CLK_DIV:0x0007:0x0005"
	"0x0302:VT_SYS_CLK_DIV:absent:0x0001"
	"0x0306:PLL_MULTIPLIER:0x0095:0x00d2"
	"0x030c:PRE_PLL_CLK_DIV2:0x0000:0x0001"
	"0x0310:PLL_MULTIPLIER2:0x0109:0x0140"
	"0x0340:FRM_LENGTH_LINES:0x0b28:0x0b1e"
	"0x0342:LINE_LENGTH_PCK:0x2510:0x24e0"
	"0x0900:BINNING_MODE:0x0221:0x0011"
	"0x0116:DATA_TYPE:0x2b00:0x3000"
	"0x0110:PD_CTRL:absent:0x0002"
	"0x0b80:PD_ENABLE:0x0000:0x0100"
	"0x0b88:PD_AREA:absent:0x0000"
)

[ -e /sys/module/s5k3j1/parameters/pdaf_win_mode ] || {
	echo "ERROR: loaded s5k3j1 has no pdaf_win_mode param." >&2; exit 1; }
LIVE=$(cat /sys/module/s5k3j1/srcversion)
echo "loaded s5k3j1 srcversion: $LIVE"
[ -z "$WANT_SRCVERSION" ] || [ "$LIVE" = "$WANT_SRCVERSION" ] || {
	echo "ERROR: expected $WANT_SRCVERSION - stale module." >&2; exit 1; }

sudo -v
sudo modprobe i2c-dev

PW_UNITS=(pipewire.socket pipewire-pulse.socket pipewire.service
	  pipewire-pulse.service wireplumber.service)
RESTORE=0
cleanup() {
	set +e
	pkill -f "yavta.*video" 2>/dev/null
	echo 0 | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null 2>&1
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

rd() {  # rd <reg> -> 0xHHHH ; 16-bit register address, 16-bit big-endian value
	local r="$1" hi lo out
	hi=$(printf '0x%02x' $(( r >> 8 )))
	lo=$(printf '0x%02x' $(( r & 0xff )))
	out=$(sudo i2ctransfer -f -y "$BUS" w2@"$ADDR" "$hi" "$lo" r2 2>/dev/null) || {
		echo "ERR"; return; }
	# i2ctransfer may print the two bytes space-separated or one per line;
	# flatten to a token list and take the first two either way.
	local toks; read -r -a toks <<<"$(echo $out)"
	[ "${#toks[@]}" -ge 2 ] || { echo "ERR"; return; }
	printf '0x%02x%02x' "$(( ${toks[0]} ))" "$(( ${toks[1]} ))"
}

read_arm() {
	local mode="$1" label="$2"
	echo "$mode" | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done

	yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c200 "$IMG_NODE" \
		>/dev/null 2>&1 &
	local pid=$!
	sleep 1.5          # let the mode settle and the stream reach steady state

	echo
	echo "=== $label (pdaf_win_mode=$mode), read while streaming ==="
	printf '  %-8s %-18s %-10s %-10s %-10s %s\n' \
		reg name stock pdaf-table "read" verdict
	local entry reg name exp_s exp_p got verdict
	for entry in "${REGS[@]}"; do
		IFS=: read -r reg name exp_s exp_p <<<"$entry"
		got=$(rd "$reg")
		verdict="?"
		[ "$got" = "$exp_p" ] && verdict="PDAF table"
		[ "$got" = "$exp_s" ] && verdict="stock table"
		[ "$exp_s" = "$exp_p" ] && verdict="(same in both)"
		printf '  %-8s %-18s %-10s %-10s %-10s %s\n' \
			"$reg" "$name" "$exp_s" "$exp_p" "$got" "$verdict"
	done

	kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
	sleep 0.5
}

read_arm 0 stock
read_arm 1 pdaf_win_mode
read_arm 0 "stock (repeat)"

echo
echo "The verdict column is the whole point: a PDAF arm reading stock values"
echo "means the writes are being overwritten; reading PDAF values means they"
echo "landed and these registers do not mean what the table implies."
