#!/usr/bin/env bash
# Stop camera test stack after a hung cam / frozen terminal session.
# Run from a NEW TTY (Ctrl+Alt+F3) if the desktop is stuck: log in, then:
#   bash ~/work/camera-mipi/scripts/dell-xps9315-stop-test-modules.sh
set -euo pipefail

echo "Stopping user camera daemons..."
systemctl --user stop wireplumber pipewire pipewire.socket 2>/dev/null || true
killall -9 wireplumber pipewire cam timeout 2>/dev/null || true

echo "Unloading out-of-tree test modules (may take a few seconds)..."
# Order: sensor first, then bridge helpers, then int3472 test modules
for mod in s5k3j1 hi556; do
	if lsmod | awk '{print $1}' | grep -qx "$mod"; then
		echo "  rmmod $mod"
		sudo modprobe -r "$mod" 2>/dev/null || sudo rmmod "$mod" 2>/dev/null || true
	fi
done
for mod in intel_skl_int3472_tps68470 intel_skl_int3472_discrete ipu_bridge; do
	if lsmod | awk '{print $1}' | grep -qx "$mod"; then
		echo "  rmmod $mod"
		sudo modprobe -r "$mod" 2>/dev/null || sudo rmmod "$mod" 2>/dev/null || true
	fi
done

echo ""
echo "Remaining IPU/camera modules:"
lsmod | grep -iE 's5k3j1|ipu|int3472|hi556' || echo "  (none of the test modules)"

echo ""
echo "If rmmod hangs, use REJECT mode (next boot) instead of waiting:"
echo "  sudo cp ~/work/camera-mipi/reference/windows-driver-artifacts/modprobe.d-dell-xps9315-camera-test.conf /etc/modprobe.d/"
echo "  sudo update-initramfs -u"
echo "  reboot"
