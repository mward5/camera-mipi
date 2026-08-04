#!/bin/bash
# Install the ipu-bridge/tps68470/ipu6-isys/s5k3j1/lc898217 modules via DKMS
# (see ../dkms.conf) instead of the one-shot manual build in
# install-custom-modules.sh. The real advantage: DKMS re-registers itself to
# rebuild automatically on future kernel upgrades (AUTOINSTALL="yes" in
# dkms.conf), so you don't need to re-run anything by hand after `apt
# upgrade` installs a new kernel.
#
# Secure Boot: DKMS's own signing support (see `man dkms.conf`'s
# mok_signing_key/mok_certificate) generates a MOK (Machine Owner Key)
# keypair automatically on first build if Secure Boot is enabled and no key
# exists yet, then signs the built modules with it. The one thing nothing
# can script around: enrolling that key into the UEFI trust store is an
# inherently interactive, one-time step by Secure Boot's own design - this
# script gets you to the "run mokutil --import and reboot" point and tells
# you exactly what to expect, but the actual key-confirmation screen at
# boot (enter the password you're about to set, confirm) needs you at the
# keyboard. On Secure Boot-disabled systems, none of this applies - modules
# just build and load directly.
#
# Run as: bash install-dkms.sh  (NOT sudo - only escalates internally where
# actually needed, matching install-custom-modules.sh's convention).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DKMS_CONF="$REPO_ROOT/dkms.conf"

KDIR="/lib/modules/$(uname -r)/build"

if [[ $EUID -eq 0 ]]; then
	echo "Run this as your normal user (not sudo/root) - it escalates only where needed." >&2
	exit 1
fi

if [[ ! -d "$KDIR" ]]; then
	echo "error: $KDIR not found - install linux-headers-$(uname -r) first:" >&2
	echo "  sudo apt install linux-headers-$(uname -r)" >&2
	exit 1
fi

for d in "$REPO_ROOT/drivers/linux-xps9315-2in1" "$REPO_ROOT/drivers/ipu6-drivers" "$REPO_ROOT/drivers/lc898217"; do
	if [[ ! -e "$d/.git" ]]; then
		echo "error: $d is empty - submodules not checked out. Run:" >&2
		echo "  git -C \"$REPO_ROOT\" submodule update --init --recursive" >&2
		exit 1
	fi
done

if ! command -v dkms &>/dev/null; then
	echo "error: dkms is not installed:" >&2
	echo "  sudo apt install dkms" >&2
	exit 1
fi

PACKAGE_NAME=$(awk -F'"' '/^PACKAGE_NAME=/{print $2; exit}' "$DKMS_CONF")
PACKAGE_VERSION=$(awk -F'"' '/^PACKAGE_VERSION=/{print $2; exit}' "$DKMS_CONF")
SRC_LINK="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"

echo "=== 1. Register $PACKAGE_NAME/$PACKAGE_VERSION with DKMS ==="
if [[ -e "$SRC_LINK" && "$(readlink -f "$SRC_LINK")" != "$REPO_ROOT" ]]; then
	echo "error: $SRC_LINK already exists and doesn't point at $REPO_ROOT - remove it first if that's stale:" >&2
	echo "  sudo dkms remove -m $PACKAGE_NAME -v $PACKAGE_VERSION --all ; sudo rm $SRC_LINK" >&2
	exit 1
fi
sudo ln -sfn "$REPO_ROOT" "$SRC_LINK"
sudo dkms add -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" 2>&1 | grep -v "^Creating symlink" || true

echo
echo "=== 2. Build + install (this is where Secure Boot signing/MOK generation happens, if applicable) ==="
sudo dkms install -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" --force

echo
echo "=== 3. Regenerate initrd ==="
sudo update-initramfs -u -k "$(uname -r)"

echo
if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
	if [[ -f /var/lib/dkms/mok.pub ]] && ! mokutil --test-key /var/lib/dkms/mok.pub 2>/dev/null | grep -qi "is already in db"; then
		echo "=== Secure Boot is ON and DKMS generated a new signing key that isn't enrolled yet. ==="
		echo "One-time step needed before the modules will actually load:"
		echo "  sudo mokutil --import /var/lib/dkms/mok.pub"
		echo "(it will ask you to set a temporary password - remember it)"
		echo "then reboot. At boot you'll see a blue \"MOK Manager\" screen -"
		echo "choose \"Enroll MOK\" -> \"Continue\" -> \"Yes\", enter that password,"
		echo "then let it reboot normally. This only happens once; every future"
		echo "kernel upgrade's DKMS rebuild will already be trusted."
	else
		echo "=== Secure Boot is ON; DKMS's signing key is already enrolled - nothing extra needed. ==="
	fi
else
	echo "=== Secure Boot is off - modules install and load directly, no signing step needed. ==="
fi

echo
echo "=== Done. Reboot to test with a genuinely clean ACPI/fwnode state. ==="
echo "To revert: sudo dkms remove -m $PACKAGE_NAME -v $PACKAGE_VERSION --all"
echo "           sudo rm $SRC_LINK"
echo "           sudo update-initramfs -u -k $(uname -r)"
