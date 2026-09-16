#!/usr/bin/env bash
# Decide whether the Windows PDAF mode's frame period carries a fixed
# line-count overhead, or simply runs a slightly slower clock.
#
# Measured at one VBLANK setting, the PDAF arm's period is 1.0049312x the
# stock arm's. With FRM_LENGTH_LINES 2846 against 2856 - and the stock mode's
# period known to equal its FLL exactly, to five significant figures, from the
# tall-vblank measurement - that leaves 24.08 line-times unaccounted for.
#
# Two explanations fit that single point equally well:
#   model A, extra lines: period = (2736 + vblank + E) * t, same t both arms
#   model B, slower clock: period = (2736 + vblank) * t_arm, E = 0
#
# They diverge as soon as vblank moves: under A the surplus stays a constant
# number of lines, under B it grows in proportion. This sweeps vblank in both
# arms and fits both models.
#
# Usage: pdaf-extra-lines.sh [expected-srcversion]
set -euo pipefail

WANT_SRCVERSION="${1:-}"
IMG_W=3976
IMG_H=2736
FRAMES=40
VBLANKS=(120 300 600 1200)

[ -e /sys/module/s5k3j1/parameters/pdaf_win_mode ] || {
	echo "ERROR: loaded s5k3j1 has no pdaf_win_mode param." >&2; exit 1; }
LIVE=$(cat /sys/module/s5k3j1/srcversion)
echo "loaded s5k3j1 srcversion: $LIVE"
[ -z "$WANT_SRCVERSION" ] || [ "$LIVE" = "$WANT_SRCVERSION" ] || {
	echo "ERROR: expected $WANT_SRCVERSION - stale module." >&2; exit 1; }

sudo -v
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
SUBDEV=$(media-ctl -d "$MDEV" -e "s5k3j1 1-0010")
CSI2="Intel IPU6 CSI2 1"

DATA=$(mktemp)
measure() {   # measure <mode> <vblank> -> prints "mode vblank fps"
	local mode="$1" vb="$2" log fps
	log=$(mktemp)
	echo "$mode" | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done
	# set_fmt resets VBLANK to the mode default, so force it afterwards.
	v4l2-ctl -d "$SUBDEV" --set-ctrl vertical_blanking="$vb" >/dev/null 2>&1 || true
	local got; got=$(v4l2-ctl -d "$SUBDEV" --get-ctrl vertical_blanking 2>/dev/null | sed 's/.*: //')
	yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c"$FRAMES" \
		"$IMG_NODE" > "$log" 2>&1 || true
	fps=$(grep -v '^Captured' "$log" \
		| sed -n 's/.* \([0-9][0-9.]*\) fps.*/\1/p' \
		| tail -n +4 | sort -g \
		| awk '{v[NR]=$1} END{if(NR)printf "%.4f", (NR%2)?v[(NR+1)/2]:(v[NR/2]+v[NR/2+1])/2}')
	printf '%s %s %s\n' "$mode" "${got:-$vb}" "${fps:-0}" >> "$DATA"
	printf '  mode=%-1s vblank=%-5s fps=%s\n' "$mode" "${got:-$vb}" "${fps:-—}"
	rm -f "$log"
}

echo "sweeping vblank in both arms (interleaved)"
for vb in "${VBLANKS[@]}"; do
	measure 0 "$vb"
	measure 1 "$vb"
done

echo
python3 - "$DATA" <<'PY'
import sys
H = 2736
rows = []
for line in open(sys.argv[1]):
    m, vb, fps = line.split()
    if float(fps) > 0:
        rows.append((int(m), int(vb), float(fps)))

stock = {vb: 1.0/f for m, vb, f in rows if m == 0}
pdaf  = {vb: 1.0/f for m, vb, f in rows if m == 1}
common = sorted(set(stock) & set(pdaf))
if not common:
    print("no paired measurements"); sys.exit()

# line time from the stock arm, whose period is known to equal FLL exactly
ts = [stock[vb]/(H+vb) for vb in common]
t = sum(ts)/len(ts)
print(f"stock line time: {t*1e9:8.2f} ns  (spread "
      f"{(max(ts)-min(ts))/t*100:.3f}% across vblank - flat means the model holds)")
print()
print(f"{'vblank':>7} {'stock ms':>9} {'pdaf ms':>9} {'A: extra lines':>15} {'B: clock ratio':>15}")
extras, ratios = [], []
for vb in common:
    fll_p = H + vb - 10      # the PDAF table's FLL sits 10 lines under stock
    E = pdaf[vb]/t - fll_p   # model A: surplus line-times
    k = (pdaf[vb]/(fll_p*t)) # model B: period scale factor
    extras.append(E); ratios.append(k)
    print(f"{vb:>7} {stock[vb]*1e3:9.4f} {pdaf[vb]*1e3:9.4f} {E:15.2f} {k:15.6f}")

def spread(v):
    return (max(v)-min(v))/ (sum(v)/len(v)) * 100
print()
print(f"model A  extra lines: mean {sum(extras)/len(extras):7.2f}   spread {spread(extras):6.2f}%")
print(f"model B  clock ratio: mean {sum(ratios)/len(ratios):9.6f}   spread {spread(ratios):6.2f}%")
print()
print("The model whose value stays CONSTANT across vblank is the right one.")
print("A constant extra-line count means the sensor emits that many lines")
print("beyond its frame length - which is what PD data would look like.")
PY
rm -f "$DATA"
