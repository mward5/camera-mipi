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
# it's installed there anyway for consistency with the others.
#
# intel-ipu6-isys.ko overrides the stock, compressed kernel/.../
# intel-ipu6-isys.ko.zst - carries the PPI2CSI_CONFIG_PPI_INTF bit-1 fix,
# see STATUS.md's "BREAKTHROUGH" entry.
#
# Run as: bash install-custom-modules.sh  (NOT sudo - builds as your own user
# so object files stay yours and don't confuse syncthing; only the final
# install/depmod/initramfs steps escalate via sudo internally).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

KDIR="/lib/modules/$(uname -r)/build"
UPDATES="/lib/modules/$(uname -r)/updates"

# Real in-tree paths inside the linux-xps9315-2in1 submodule (a fork of
# Ubuntu's resolute kernel) - these directories carry other, unrelated
# drivers too (e.g. ipu3-cio2, ivsc), which get built alongside ours as an
# unavoidable side effect of Kbuild building a whole directory's Makefile
# out-of-tree; harmless, just extra compile time.
LINUX_FORK_DIR="$REPO_ROOT/drivers/linux-xps9315-2in1"
IPU_BRIDGE_SUBDIR="drivers/media/pci/intel"
TPS_SUBDIR="drivers/platform/x86/intel/int3472"

IPU6_DRIVERS_DIR="$REPO_ROOT/drivers/ipu6-drivers"
LC898217_DIR="$REPO_ROOT/drivers/lc898217"

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user (not sudo/root) - it escalates only where needed." >&2
	exit 1
fi

if [[ ! -d "$KDIR" ]]; then
	echo "error: $KDIR not found - install linux-headers-$(uname -r) first:" >&2
	echo "  sudo apt install linux-headers-$(uname -r)" >&2
	exit 1
fi

for d in "$LINUX_FORK_DIR" "$IPU6_DRIVERS_DIR" "$LC898217_DIR"; do
	if [[ ! -e "$d/.git" ]]; then
		echo "error: $d is empty - submodules not checked out. Run:" >&2
		echo "  git -C \"$REPO_ROOT\" submodule update --init --recursive" >&2
		exit 1
	fi
done

echo "=== 1. Rebuild out-of-tree modules as $(whoami) against $(uname -r) ==="
make -C "$KDIR" M="$LINUX_FORK_DIR/$IPU_BRIDGE_SUBDIR" modules
make -C "$KDIR" M="$LINUX_FORK_DIR/$TPS_SUBDIR" modules
make -C "$KDIR" M="$IPU6_DRIVERS_DIR" drivers/media/i2c/s5k3j1.ko
make -C "$KDIR" M="$LC898217_DIR" modules
echo "Rebuild OK (still owned by $(whoami))"

echo
echo "=== 2. Install into $UPDATES (overrides stock kernel/ modules by name) ==="
sudo mkdir -p "$UPDATES"
sudo install -o root -g root -m 644 \
	"$LINUX_FORK_DIR/$IPU_BRIDGE_SUBDIR/ipu-bridge.ko" "$UPDATES/ipu-bridge.ko"
sudo install -o root -g root -m 644 \
	"$LINUX_FORK_DIR/$TPS_SUBDIR/intel_skl_int3472_tps68470.ko" "$UPDATES/intel_skl_int3472_tps68470.ko"
sudo install -o root -g root -m 644 \
	"$LINUX_FORK_DIR/$IPU_BRIDGE_SUBDIR/ipu6/intel-ipu6-isys.ko" "$UPDATES/intel-ipu6-isys.ko"
sudo install -o root -g root -m 644 \
	"$IPU6_DRIVERS_DIR/drivers/media/i2c/s5k3j1.ko" "$UPDATES/s5k3j1.ko"
sudo install -o root -g root -m 644 \
	"$LC898217_DIR/lc898217.ko" "$UPDATES/lc898217.ko"

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
