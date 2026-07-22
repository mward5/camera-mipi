#!/usr/bin/env python3
"""
Per-lane decoder for the IPU6 MCD-PHY0 dynamic status bytes.

WHY THIS EXISTS
---------------
The corruption symptom (every packet's payload corrupts at ~4 Gbps while SOF
survives) is a bit/lane physical-integrity signature. Every *static* config
byte has been byte-matched to working Windows. The only bytes in the PHY0 MMIO
region that are NOT static are a small set per lane that flip from an "idle"
pattern to an "active/calibrated" pattern when a lane is brought up. Prior work
diffed them in bulk and called them non-diagnostic. This tool instead breaks
them out PER LANE, so a single mis-calibrating lane stands out -- specifically
the upper data-lane pair (D2/D3) that ONLY the 4-lane rear sensor exercises and
the working 2-lane front camera (hi556) never touches.

REGION LAYOUT (empirically derived from the two live captures on disk)
----------------------------------------------------------------------
PHY0 MMIO = BAR0+0x10000, 0x1960 bytes (see scripts/dump-phy0-live.py).
Organized as 0x200-byte per-PPI/per-lane blocks. The dynamic ("lane state")
bytes sit at these block-relative offsets, with the observed idle baseline:

    +0x01c  +0x0b0  +0x0b2  +0x0b3  +0x0b8  +0x11d  +0x152
idle: 0x01    0x01    0x00    0x80    0x00    0x07    0x00

  * Rear  s5k3j1 (ACPI port 1 -> phy_port 0, x4): blocks at 0x0200..0x0a00
          = 4 data lanes + 1 clock lane (5 blocks).
  * Front hi556  (ACPI port 3, x2):               blocks at 0x1400..0x1800
          = 2 data lanes + 1 clock lane (3 blocks).

The PPI->physical-lane mapping (D0/D1/C0/D2/D3) in ipu6-isys-mcd-phy.c's header
comment is a HYPOTHESIS for labeling only; block offsets are the ground truth.

USAGE
-----
  # Differential (recommended) -- rear-active vs front-active captures:
  ./decode-phy0-lanes.py reference/linux-phy0-live.bin \
                         reference/linux-phy0-live-hi556.bin

  # Decode a single fresh rear-streaming capture against the baked-in idle
  # baseline (no second file needed):
  ./decode-phy0-lanes.py reference/linux-phy0-live.bin

  # Grab a fresh rear capture live and decode it (needs sudo + rear camera
  # actively streaming, e.g. `cam --capture=100000` held open in another shell):
  sudo ./decode-phy0-lanes.py --live
"""
import sys
import mmap

BLOCK_SIZE = 0x200
REAR_BLOCKS  = [0x0200, 0x0400, 0x0600, 0x0800, 0x0a00]   # s5k3j1 x4: 4 data + 1 clk
FRONT_BLOCKS = [0x1400, 0x1600, 0x1800]                   # hi556  x2: 2 data + 1 clk

# Lane labels. Rear labels are CONFIRMED (not just guessed): block 0x0600 shows
# the distinct clock-lane signature (+0x0b2=0x00, +0x0b8=0x10, unlike the data
# lanes), and it sits at block index 2 == PPI2 == C0 in the driver's own header
# comment (PPI0=D1, PPI1=D0, PPI2=C0, PPI3=D2, PPI4=D3). D2/D3 are the upper
# pair that ONLY the 4-lane rear sensor uses; hi556 never exercises them.
LABELS = {
    0x0200: "D1", 0x0400: "D0", 0x0600: "C0(clk)", 0x0800: "D2", 0x0a00: "D3",
    0x1400: "d0?", 0x1600: "d1?", 0x1800: "clk?",   # hi556 cluster: not confirmed
}

# block-relative offsets of the dynamic lane-state bytes, with observed idle value
FIELDS = [0x01c, 0x0b0, 0x0b2, 0x0b3, 0x0b8, 0x11d, 0x152]
IDLE   = {0x01c: 0x01, 0x0b0: 0x01, 0x0b2: 0x00, 0x0b3: 0x80,
          0x0b8: 0x00, 0x11d: 0x07, 0x152: 0x00}

PCI_RESOURCE = "/sys/bus/pci/devices/0000:00:05.0/resource0"
PHY0_OFFSET  = 0x10000
LENGTH       = 0x1960


def live_dump():
    with open(PCI_RESOURCE, "r+b") as f:
        m = mmap.mmap(f.fileno(), PHY0_OFFSET + LENGTH, offset=0)
        data = m[PHY0_OFFSET:PHY0_OFFSET + LENGTH]
        m.close()
    return data


def fields_of(data, base):
    """Return {field_offset: byte} for one lane block, or None if out of range."""
    if base + max(FIELDS) >= len(data):
        return None
    return {off: data[base + off] for off in FIELDS}


def decode(data, blocks, label, baseline=None):
    """Print a per-lane table. baseline (optional) is another capture's bytes
    used as the idle reference; if None, the baked-in IDLE constants are used."""
    print(f"\n=== {label} ===")
    hdr = "  block   lane     " + "  ".join(f"+{o:#05x}" for o in FIELDS) + "   state"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))
    rows = []
    for i, base in enumerate(blocks):
        fv = fields_of(data, base)
        if fv is None:
            continue
        # idle reference for each field
        if baseline is not None:
            ref = {o: baseline[base + o] for o in FIELDS}
        else:
            ref = IDLE
        active = any(fv[o] != ref[o] for o in FIELDS)
        cells = []
        for o in FIELDS:
            mark = " " if fv[o] == ref[o] else "*"   # * = differs from idle ref
            cells.append(f" 0x{fv[o]:02x}{mark}")
        state = "ACTIVE" if active else "idle"
        lane = LABELS.get(base, "?").ljust(7)
        print(f"  {base:#06x}  {lane}" + " ".join(cells) + f"   {state}")
        rows.append((base, fv))
    # outlier detection: among ACTIVE blocks, flag any whose field vector is
    # unique (all other active blocks agree but this one differs)
    active_rows = [(b, fv) for b, fv in rows
                   if any(fv[o] != IDLE[o] for o in FIELDS)]
    if len(active_rows) >= 2:
        print("\n  per-lane comparison (active blocks only):")
        for o in FIELDS:
            vals = {b: fv[o] for b, fv in active_rows}
            uniq = set(vals.values())
            if len(uniq) > 1:
                detail = ", ".join(f"{b:#06x}=0x{v:02x}" for b, v in vals.items())
                print(f"    +{o:#05x} DIFFERS across lanes: {detail}")
        print("    (a lane that differs from its siblings here is the one to "
              "scope; D2/D3 are rear-only)")
    return rows


def main():
    args = sys.argv[1:]
    if args and args[0] == "--live":
        data = live_dump()
        decode(data, REAR_BLOCKS, "REAR s5k3j1 (live, x4) vs baked-in idle")
        decode(data, FRONT_BLOCKS, "FRONT hi556 (live, x2) vs baked-in idle")
        return

    if len(args) == 1:
        data = open(args[0], "rb").read()
        decode(data, REAR_BLOCKS, f"REAR s5k3j1 (x4) from {args[0]} vs baked-in idle")
        decode(data, FRONT_BLOCKS, f"FRONT hi556 (x2) from {args[0]} vs baked-in idle")
        return

    if len(args) == 2:
        rear_cap  = open(args[0], "rb").read()   # rear streaming
        front_cap = open(args[1], "rb").read()   # front streaming
        # rear blocks: active in rear_cap, idle in front_cap
        decode(rear_cap, REAR_BLOCKS,
               f"REAR s5k3j1 (x4) ACTIVE={args[0]}  idle-ref={args[1]}",
               baseline=front_cap)
        # front blocks: active in front_cap, idle in rear_cap
        decode(front_cap, FRONT_BLOCKS,
               f"FRONT hi556 (x2) ACTIVE={args[1]}  idle-ref={args[0]}",
               baseline=rear_cap)
        return

    print(__doc__)
    sys.exit(1)


if __name__ == "__main__":
    main()
