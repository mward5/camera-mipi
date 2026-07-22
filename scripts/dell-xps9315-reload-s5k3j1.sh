#!/usr/bin/env bash
# Reload patched s5k3j1 for Dell XPS 9315 rear (INT346D) testing.
set -euo pipefail

KVER="$(uname -r)"
KO_SRC="${KO_SRC:-$HOME/work/camera-mipi/drivers/s5k3j1/drivers/media/i2c/s5k3j1.ko}"
KO_DST="/lib/modules/${KVER}/updates/ipu-test/s5k3j1.ko"
MOK_PRIV="${MOK_PRIV:-$HOME/mok-key/MOK.priv}"
MOK_DER="${MOK_DER:-$HOME/mok-key/MOK.der}"
PDAF_TRIAL="${PDAF_TRIAL:-0}"

if [[ ! -f "$KO_SRC" ]]; then
	echo "Missing module: $KO_SRC" >&2
	exit 1
fi

sudo install -D -m 0644 "$KO_SRC" "$KO_DST"
sudo "/usr/src/linux-headers-${KVER}/scripts/sign-file" sha256 "$MOK_PRIV" "$MOK_DER" "$KO_DST" "$KO_DST"
sudo depmod -a
sudo rmmod s5k3j1 2>/dev/null || true
sleep 1
sudo modprobe s5k3j1 "pdaf_trial=${PDAF_TRIAL}"
echo "pdaf_trial=$(cat /sys/module/s5k3j1/parameters/pdaf_trial)"
if [[ "$(cat /sys/module/s5k3j1/parameters/pdaf_trial)" != "0" ]]; then
	echo "WARNING: pdaf_trial should be 0 for INT346D rear (PDAF on + tall vblank)" >&2
fi
