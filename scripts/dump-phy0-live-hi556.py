#!/usr/bin/env python3
"""Same as dump-phy0-live.py but writes to a separate file, for capturing
PHY0 state while hi556 (not s5k3j1) is the active stream - for the
Linux-side differential comparison (working camera vs broken camera,
same physical PHY0 cluster, same kernel, same moment in time).
Run with sudo while a hi556 stream is genuinely active."""
import mmap

PCI_RESOURCE = "/sys/bus/pci/devices/0000:00:05.0/resource0"
OUT_PATH = "/home/mward/work/camera-mipi/reference/linux-phy0-live-hi556.bin"
PHY0_OFFSET = 0x10000
LENGTH = 0x1960

with open(PCI_RESOURCE, "r+b") as f:
    m = mmap.mmap(f.fileno(), PHY0_OFFSET + LENGTH, offset=0)
    data = m[PHY0_OFFSET:PHY0_OFFSET + LENGTH]
    m.close()

with open(OUT_PATH, "wb") as out:
    out.write(data)

print(f"wrote {len(data)} bytes to {OUT_PATH}")
