#!/usr/bin/env python3
"""Dump IPU6 buttress IS_FREQ_CTL (0x34) and PWR_STATE (0x5c) registers via
mmap on the PCI resource0 sysfs file. Run with sudo while a camera is
genuinely streaming.

Usage: sudo python3 dump-buttress.py <label>
"""
import mmap
import sys

PCI_RESOURCE = "/sys/bus/pci/devices/0000:00:05.0/resource0"
IS_FREQ_CTL = 0x34
PWR_STATE = 0x5c

label = sys.argv[1] if len(sys.argv) > 1 else ""

with open(PCI_RESOURCE, "r+b") as f:
    m = mmap.mmap(f.fileno(), 0x100, offset=0)
    freq_ctl = int.from_bytes(m[IS_FREQ_CTL:IS_FREQ_CTL+4], "little")
    pwr_state = int.from_bytes(m[PWR_STATE:PWR_STATE+4], "little")
    m.close()

is_pwr_fsm = (pwr_state >> 19) & 0x1f
is_pwr = (pwr_state >> 3) & 0x3

print(f"[{label}] IS_FREQ_CTL=0x{freq_ctl:08x} (start={bool(freq_ctl>>31&1)} "
      f"ratio=0x{freq_ctl & 0xff:02x} qos_floor=0x{(freq_ctl>>8)&0xff:02x})")
print(f"[{label}] PWR_STATE=0x{pwr_state:08x} IS_PWR_FSM=0x{is_pwr_fsm:02x} "
      f"IS_PWR=0x{is_pwr:02x} (IS_RDY==0xa)")
