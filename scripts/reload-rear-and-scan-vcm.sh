#!/bin/bash
# Rebuild the out-of-tree ipu-bridge/tps68470/s5k3j1 modules against the
# currently running kernel (they were last built for 7.0.0-15-generic; we're
# now on 7.0.0-27-generic), swap them in, then scan the rear camera's I2C bus
# for the VCM. Deliberately does NOT touch streaming/cam/media-ctl - this is
# probe/power-up + i2cdetect only, to avoid the known PDAF dual-stream oops.
#
# Run as: bash reload-rear-and-scan-vcm.sh  (NOT sudo - builds as your own
# user so object files stay mward:mward and don't confuse syncthing; module
# load/unload steps escalate via sudo internally where actually needed).
#
# NOTE: superseded by install-custom-modules.sh for most purposes - that one
# installs into the module tree + initrd, avoiding the "already configured,
# skip" stale-fwnode-graph issue this insmod-based approach can hit if the
# stock modules already probed earlier in the same boot.
set -e

KDIR="/lib/modules/$(uname -r)/build"
IPU_BRIDGE_DIR="/home/mward/work/camera-mipi/drivers/ipu-bridge"
TPS_DIR="/home/mward/work/camera-mipi/drivers/int3472-tps68470"
IPU6_DIR="/home/mward/work/camera-mipi/drivers/s5k3j1"

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user (not sudo/root) - it escalates only where needed." >&2
	exit 1
fi

echo "=== 0. Pre-flight: refuse to run if something has a camera open ==="
if lsof /dev/video* 2>/dev/null | grep -q /dev/video; then
	echo "ABORT: something has a /dev/video* node open (browser tab, PipeWire, cheese, etc)."
	echo "Close it and re-run."
	lsof /dev/video* 2>/dev/null
	exit 1
fi
echo "OK - no active camera consumers"

echo
echo "=== 1. Rebuild out-of-tree modules as $(whoami) against $(uname -r) ==="
make -C "$KDIR" M="$IPU_BRIDGE_DIR" modules
make -C "$KDIR" M="$TPS_DIR" modules
make -C "$KDIR" M="$IPU6_DIR" drivers/media/i2c/s5k3j1.ko
echo "Rebuild OK (still owned by $(whoami))"

echo
echo "=== 2. Unload current stack (leaf-first; hi556/front camera left untouched) ==="
set +e
sudo modprobe -r intel_ipu6_isys
sudo modprobe -r intel_ipu6_psys
sudo modprobe -r intel_ipu6
sudo modprobe -r ipu_bridge
sudo modprobe -r s5k3j1
sudo modprobe -r intel_skl_int3472_tps68470
set -e

echo
echo "=== 3. Load custom modules ==="
sudo insmod "$TPS_DIR/intel_skl_int3472_tps68470.ko"
sudo insmod "$IPU_BRIDGE_DIR/ipu-bridge.ko"
sudo modprobe intel_ipu6
sudo modprobe intel_ipu6_psys
sudo modprobe intel_ipu6_isys

echo
echo "=== 3b. tps68470-regulator uses PROBE_PREFER_ASYNCHRONOUS; its devm_clk_get()"
echo "     can race clk-tps68470's (synchronous) probe and fail with -ENOENT."
echo "     That failure isn't auto-retried, so check for it and force a rebind."
sleep 2
REG_DEV=$(find /sys/bus/platform/devices -maxdepth 1 -iname "tps68470-regulator*" -printf '%f\n' 2>/dev/null | head -1)
if [[ -n "$REG_DEV" ]]; then
	if [[ -L "/sys/bus/platform/devices/$REG_DEV/driver" ]]; then
		echo "tps68470-regulator already bound OK, no retry needed"
	else
		echo "tps68470-regulator not bound - retrying via unbind/bind ($REG_DEV)"
		echo "$REG_DEV" | sudo tee /sys/bus/platform/drivers/tps68470-regulator/unbind >/dev/null 2>/dev/null || true
		sleep 1
		echo "$REG_DEV" | sudo tee /sys/bus/platform/drivers/tps68470-regulator/bind >/dev/null
		sleep 1
		if [[ -L "/sys/bus/platform/devices/$REG_DEV/driver" ]]; then
			echo "tps68470-regulator now bound OK"
		else
			echo "tps68470-regulator still not bound - check dmesg"
			sudo dmesg | tail -20
		fi
	fi
else
	echo "WARNING: no tps68470-regulator* platform device found"
fi

echo
echo "=== 3c. s5k3j1: udev may auto-load the STOCK module the instant INT346D"
echo "     appears, racing our explicit insmod of the patched build. Force it."
sudo modprobe -r s5k3j1 2>/dev/null || true
sudo insmod "$IPU6_DIR/drivers/media/i2c/s5k3j1.ko"

echo
echo "=== 4. Wait for probe, check for i2c-INT346D ==="
sleep 3
if [[ -d /sys/bus/i2c/devices/i2c-INT346D:00 ]]; then
	echo "PRESENT: i2c-INT346D:00"
	ls -la /sys/bus/i2c/devices/i2c-INT346D:00 | head -20
else
	echo "NOT PRESENT - quirk did not trigger. Recent dmesg:"
	sudo dmesg | tail -60
	exit 1
fi

echo
echo "=== 5. dmesg since load ==="
sudo dmesg | grep -iE 'int346d|s5k3j1|tps68470|instantiated|avdd|regulator' | tail -40

echo
echo "=== 6. i2cdetect the rear camera's bus (sensor only, address 0x10 expected) ==="
DEVPATH=$(readlink -f /sys/bus/i2c/devices/i2c-INT346D:00)
BUS=$(basename "$(dirname "$DEVPATH")" | grep -oE '[0-9]+$')
echo "Rear camera bus: i2c-$BUS"
sudo i2cdetect -y "$BUS"

echo
echo "=== Done. Do NOT run cam/media-ctl streaming - this was probe+scan only. ==="
echo "To roll back: sudo modprobe -r s5k3j1 intel_ipu6_isys intel_ipu6_psys intel_ipu6 ipu_bridge intel_skl_int3472_tps68470"
echo "              sudo modprobe intel_skl_int3472_tps68470; sudo modprobe s5k3j1; sudo modprobe intel_ipu6_isys"
echo "(this reloads the stock in-kernel versions from /lib/modules/$(uname -r)/kernel/...)"
