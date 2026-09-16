#!/usr/bin/env python3
"""Poll the IPU6 CSI-2 receiver's per-VC frame-sync status while a camera
streams, and report which virtual channels are actually arriving.

This reads what is on the wire, independently of whether anything is
configured to capture it - which is the one question the image path cannot
answer. See docs/pdaf-implementation-plan.md, "The PDAF mode table, measured".

Why polling works: ipu6-isys-csi2.c writes 0 to the CSI_SYNC IRQ MASK, so sync
events never raise an interrupt. ipu6_isys_csi2_isr() - which reads the status
and clears it - therefore only runs on the *error* IRQ, which fires a handful
of times per stream. Between those, the status register accumulates, so an
OR over repeated reads sees every VC that produced a frame start or end.

Run as root (the PCI BAR is 0600). Usage:
  pdaf-csi2-vc-probe.py <port> <seconds> [dump-path]
"""
import mmap
import sys
import time

PCI_RESOURCE = "/sys/bus/pci/devices/0000:00:05.0/resource0"
CSI_REG_BASE = 0x220000
PORT_STRIDE = 0x1000
BLOCK = 0x300

IRQ_CSI = 0x80
IRQ_CSI_SYNC = 0xA0
STATUS = 0x8
NR_VC = 16

NAMED = {
    0x200: "PPI2CSI_ENABLE",
    0x204: "PPI2CSI_CONFIG_PPI_INTF",
    0x208: "PPI2CSI_CONFIG_CSI_FEATURE",
    0x280: "CSI_FE_ENABLE",
    0x284: "CSI_FE_MODE",
    0x288: "CSI_FE_MUX_CTRL",
    0x290: "CSI_FE_SYNC_CNTR_SEL",
}


def main():
    port = int(sys.argv[1])
    secs = float(sys.argv[2])
    dump = sys.argv[3] if len(sys.argv) > 3 else None
    off = CSI_REG_BASE + port * PORT_STRIDE

    with open(PCI_RESOURCE, "r+b") as f:
        m = mmap.mmap(f.fileno(), off + BLOCK, offset=0)

        acc = 0
        reads = 0
        end = time.time() + secs
        while time.time() < end:
            acc |= int.from_bytes(m[off+IRQ_CSI_SYNC+STATUS:
                                    off+IRQ_CSI_SYNC+STATUS+4], "little")
            reads += 1
        block = bytes(m[off:off+BLOCK])
        m.close()

    print(f"  polled {reads} times over {secs:g}s; "
          f"accumulated CSI_SYNC status = 0x{acc:08x}")
    seen = []
    for vc in range(NR_VC):
        fs = bool(acc & (1 << (vc * 2)))
        fe = bool(acc & (2 << (vc * 2)))
        if fs or fe:
            seen.append(f"VC{vc}({'FS' if fs else ''}{'+' if fs and fe else ''}"
                        f"{'FE' if fe else ''})")
    print("  virtual channels seen: " + (", ".join(seen) if seen else "NONE"))
    if len(seen) > 1:
        print("  >>> more than one VC is arriving on this port <<<")

    if dump:
        with open(dump, "wb") as out:
            out.write(block)
        vals = {o: int.from_bytes(block[o:o+4], "little") for o in NAMED}
        print("  " + "  ".join(f"{NAMED[o]}=0x{v:x}" for o, v in vals.items()))


if __name__ == "__main__":
    main()
