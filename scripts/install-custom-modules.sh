#!/bin/bash
# Install our custom-built ipu-bridge/tps68470/s5k3j1/lc898217/ipu6-isys
# modules into the standard module tree (updates/, which depmod prioritizes
# over kernel/ for same-named modules - same mechanism used by
# acpi-call-dkms already on this system). Then regenerate the initrd so
# they load automatically at boot, before udev's normal auto-probe ever
# gets a chance to touch these ACPI devices with the stock versions. This
# avoids the "already configured, skip" early-exit in ipu_bridge_init()
# that made every insmod-based reload attempt silently no-op our fixes.
#
# lc898217.ko is new (no stock equivalent exists in the kernel tree to
# override), so it just needs to exist in the module tree for depmod to
# pick it up as a normal dependency of the i2c-instantiated VCM client -
# no special "updates/ override" behavior needed for it specifically, but
# it's installed there anyway for consistency with the other four.
#
# intel-ipu6-isys.ko (drivers/ipu6-isys/) overrides the stock, compressed
# kernel/.../intel-ipu6-isys.ko.zst - added 2026-07-16 for the
# xps9315_2in1 PHY config-table quirk, see STATUS.md.
#
# Run as: bash install-custom-modules.sh  (NOT sudo - builds as your own user
# so object files stay mward:mward and don't confuse syncthing; only the
# final install/depmod/initramfs steps escalate via sudo internally).
set -e

KDIR="/lib/modules/$(uname -r)/build"
UPDATES="/lib/modules/$(uname -r)/updates"
IPU_BRIDGE_DIR="/home/mward/work/camera-mipi/drivers/ipu-bridge"
TPS_DIR="/home/mward/work/camera-mipi/drivers/int3472-tps68470"
IPU6_DIR="/home/mward/work/camera-mipi/drivers/s5k3j1"
LC898217_DIR="/home/mward/work/camera-mipi/drivers/lc898217"
IPU6_ISYS_DIR="/home/mward/work/camera-mipi/drivers/ipu6-isys"

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user (not sudo/root) - it escalates only where needed." >&2
	exit 1
fi

echo "=== 1. Rebuild out-of-tree modules as $(whoami) against $(uname -r) ==="
make -C "$KDIR" M="$IPU_BRIDGE_DIR" modules
make -C "$KDIR" M="$TPS_DIR" modules
make -C "$KDIR" M="$IPU6_DIR" drivers/media/i2c/s5k3j1.ko
make -C "$KDIR" M="$LC898217_DIR" modules
make -C "$KDIR" M="$IPU6_ISYS_DIR" modules
echo "Rebuild OK (still owned by $(whoami))"

echo
echo "=== 2. Install into $UPDATES (overrides stock kernel/ modules by name) ==="
sudo mkdir -p "$UPDATES"
sudo install -o root -g root -m 644 "$IPU_BRIDGE_DIR/ipu-bridge.ko" "$UPDATES/ipu-bridge.ko"
sudo install -o root -g root -m 644 "$TPS_DIR/intel_skl_int3472_tps68470.ko" "$UPDATES/intel_skl_int3472_tps68470.ko"
sudo install -o root -g root -m 644 "$IPU6_DIR/drivers/media/i2c/s5k3j1.ko" "$UPDATES/s5k3j1.ko"
sudo install -o root -g root -m 644 "$LC898217_DIR/lc898217.ko" "$UPDATES/lc898217.ko"
sudo install -o root -g root -m 644 "$IPU6_ISYS_DIR/intel-ipu6-isys.ko" "$UPDATES/intel-ipu6-isys.ko"

echo
echo "=== 3. depmod ==="
sudo depmod -a "$(uname -r)"

echo
echo "=== 4. Regenerate initrd ==="
sudo update-initramfs -u -k "$(uname -r)"

echo
echo "=== Done. Reboot now to test with a genuinely clean ACPI/fwnode state. ==="
echo "To revert: sudo rm $UPDATES/{ipu-bridge.ko,intel_skl_int3472_tps68470.ko,s5k3j1.ko,lc898217.ko,intel-ipu6-isys.ko}"
echo "           sudo depmod -a; sudo update-initramfs -u -k $(uname -r)"
