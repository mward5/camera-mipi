#!/usr/bin/env bash
# Ask the CSI-2 receiver which virtual channels arrive, in each mode-table arm.
#
# The ported Windows PDAF table produces exactly one measured difference: a
# constant 0.8498% longer line, with no extra lines and no extra bytes
# delivered. Extra time on the wire that never reaches a buffer is what an
# interleaved second data type costs - the receiver spends the time and
# discards it, having no pin configured for that DT. This looks at the
# receiver directly rather than at what it hands us.
#
# Usage: pdaf-csi2-vc-ab.sh [expected-srcversion]
set -euo pipefail

WANT_SRCVERSION="${1:-}"
PORT=1           # rear camera is CSI2 port 1
IMG_W=3976
IMG_H=2736
PROBE_SECS=2

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HOME/work/af-sweep-data/pdaf-csi2vc-$(date +%Y%m%d-%H%M%S)"

[ -e /sys/module/s5k3j1/parameters/pdaf_win_mode ] || {
	echo "ERROR: loaded s5k3j1 has no pdaf_win_mode param." >&2; exit 1; }
LIVE=$(cat /sys/module/s5k3j1/srcversion)
echo "loaded s5k3j1 srcversion: $LIVE"
[ -z "$WANT_SRCVERSION" ] || [ "$LIVE" = "$WANT_SRCVERSION" ] || {
	echo "ERROR: expected $WANT_SRCVERSION - stale module." >&2; exit 1; }

sudo -v
mkdir -p "$OUT"

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
echo "media device: $MDEV   image node: $IMG_NODE   dumps: $OUT"

# A baseline with nothing streaming: whatever shows up here is stale state,
# not traffic, and has to be subtracted from how the streaming arms are read.
echo
echo "=== idle (not streaming) ==="
sudo python3 "$HERE/pdaf-csi2-vc-probe.py" "$PORT" 1 "$OUT/idle.bin"

probe_arm() {
	local mode="$1" label="$2"
	echo "$mode" | sudo tee /sys/module/s5k3j1/parameters/pdaf_win_mode >/dev/null
	for e in "\"s5k3j1 1-0010\":0" "\"$CSI2\":0" "\"$CSI2\":1"; do
		media-ctl -d "$MDEV" -V "$e [fmt:SGRBG10_1X10/${IMG_W}x${IMG_H}]" >/dev/null 2>&1 || true
	done
	yavta --no-query -f SGRBG10 -s "${IMG_W}x${IMG_H}" -n 4 -c300 "$IMG_NODE" \
		>/dev/null 2>&1 &
	local pid=$!
	sleep 1.5                     # let the stream reach steady state
	echo
	echo "=== $label (pdaf_win_mode=$mode), streaming ==="
	sudo python3 "$HERE/pdaf-csi2-vc-probe.py" "$PORT" "$PROBE_SECS" \
		"$OUT/$label.bin"
	kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
	sleep 0.5
}

probe_arm 0 stock-1
probe_arm 1 pdaf-2
probe_arm 0 stock-3
probe_arm 1 pdaf-4

echo
echo "=== register-block differences between arms ==="
python3 - "$OUT" <<'PY'
import pathlib, sys, itertools
d = pathlib.Path(sys.argv[1])
blocks = {p.stem: p.read_bytes() for p in sorted(d.glob("*.bin"))}
# The sync status word is what we polled and is expected to differ; exclude it
# so it cannot mask quieter differences elsewhere in the block.
SKIP = {0xA0 + 0x8}
names = [n for n in blocks if n != "idle"]
for a, b in itertools.combinations(names, 2):
    diffs = []
    for off in range(0, len(blocks[a]), 4):
        if off in SKIP:
            continue
        x = int.from_bytes(blocks[a][off:off+4], "little")
        y = int.from_bytes(blocks[b][off:off+4], "little")
        if x != y:
            diffs.append((off, x, y))
    tag = "same-arm" if a.split('-')[0] == b.split('-')[0] else "CROSS-ARM"
    print(f"  {a:9s} vs {b:9s} [{tag}]: {len(diffs)} words differ")
    for off, x, y in diffs[:8]:
        print(f"      +0x{off:03x}  0x{x:08x} -> 0x{y:08x}")
print()
print("  Same-arm differences are the noise floor. A cross-arm difference only")
print("  counts if it exceeds what the same-arm pairs show.")
PY
