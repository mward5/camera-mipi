#!/usr/bin/env python3
"""Dump a CSI2 per-port register block (CSI_REG_PORT_BASE(id) = BAR0 +
0x220000 + id*0x1000, 0x300 bytes covering GPREG/IRQ/PPI2CSI/FE registers)
via mmap on the PCI resource0 sysfs file. Run with sudo while the relevant
camera is genuinely streaming.

Usage: sudo python3 dump-csi2-port.py <port_id> <out_path>
"""
import mmap
import sys

PCI_RESOURCE = "/sys/bus/pci/devices/0000:00:05.0/resource0"
CSI_REG_BASE = 0x220000
LENGTH = 0x300

port_id = int(sys.argv[1])
out_path = sys.argv[2]
offset = CSI_REG_BASE + port_id * 0x1000

with open(PCI_RESOURCE, "r+b") as f:
    m = mmap.mmap(f.fileno(), offset + LENGTH, offset=0)
    data = m[offset:offset + LENGTH]
    m.close()

with open(out_path, "wb") as out:
    out.write(data)

print(f"wrote {len(data)} bytes (port {port_id}, offset 0x{offset:x}) to {out_path}")
