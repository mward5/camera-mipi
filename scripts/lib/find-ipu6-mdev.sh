# Finds the IPU6 media device by driver name and sets $MDEV, or exits 1.
# Numbering isn't stable across boots (confirmed 2026-07-22: a USB webcam
# can take /dev/media0, pushing the IPU6 controller to /dev/media1) - so
# this probes by driver name instead of assuming a fixed number. Honors a
# pre-set $MDEV (e.g. MDEV=/dev/media1 ./script.sh) without re-probing.
#
# Meant to be sourced, not executed - relies on the caller already having
# `set -u` active (or not) and doesn't set it itself.

MDEV="${MDEV:-}"
if [ -z "$MDEV" ]; then
	for d in /dev/media*; do
		if media-ctl -d "$d" -p 2>/dev/null | grep -q '^driver.*intel-ipu6'; then
			MDEV="$d"
			break
		fi
	done
fi
if [ -z "$MDEV" ]; then
	echo "Could not find the intel-ipu6 media device among /dev/media*" >&2
	exit 1
fi
