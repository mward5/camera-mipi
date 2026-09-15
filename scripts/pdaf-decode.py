#!/usr/bin/env python3
"""PDAF phase-0: decode a captured PAF buffer into candidate L/R planes.

THROWAWAY EXPERIMENT - see docs/pdaf-implementation-plan.md, WP0 step 5.

The PAFi layout is not documented. Intel's own headers name two shapes
(ia_css_program_group_data_defs.h):

  PAF_INTERLEAVED      "L and R PDAF pixel pairs ... LRLR.., RLRL.."
  PAF_NON_INTERLEAVED  "L and R PDAF pixel line pairs. If line n is L, n+1 is R"

This writes both interpretations as PGM files. Whichever produces a pair of
images that look like a vertically-subsampled copy of the scene is the right
one - decide by looking, not by guessing.

Stdlib only: this machine has no numpy.
"""
import argparse, os, sys

def write_pgm(path, w, h, data):
    with open(path, 'wb') as f:
        f.write(b"P5\n%d %d\n255\n" % (w, h))
        f.write(bytes(data))

def split_interleaved(buf, w, h):
    """Each line is LRLR..; L = even byte positions, R = odd."""
    hw = w // 2
    L = bytearray(hw * h); R = bytearray(hw * h)
    for y in range(h):
        row = buf[y * w:(y + 1) * w]
        L[y * hw:(y + 1) * hw] = row[0::2]
        R[y * hw:(y + 1) * hw] = row[1::2]
    return (hw, h, L), (hw, h, R)

def split_line_pairs(buf, w, h):
    """Even lines are L, odd lines are R."""
    hh = h // 2
    L = bytearray(w * hh); R = bytearray(w * hh)
    for y in range(hh):
        L[y * w:(y + 1) * w] = buf[(2 * y) * w:(2 * y + 1) * w]
        R[y * w:(y + 1) * w] = buf[(2 * y + 1) * w:(2 * y + 2) * w]
    return (w, hh, L), (w, hh, R)

def stats(name, buf):
    n = len(buf)
    if not n:
        return
    mn, mx = min(buf), max(buf)
    mean = sum(buf) / n
    distinct = len(set(buf))
    print(f"  {name:<22} n={n:<9} min={mn:<4} max={mx:<4} mean={mean:7.2f} distinct={distinct}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("buffer", help="a paf-NNN.bin from pdaf-phase0-capture.sh")
    ap.add_argument("--width", type=int, default=3968)
    ap.add_argument("--height", type=int, default=684)
    ap.add_argument("--outdir", default=None)
    a = ap.parse_args()

    raw = open(a.buffer, 'rb').read()
    expect = a.width * a.height
    print(f"file      : {a.buffer}")
    print(f"size      : {len(raw)} bytes (expected {expect} for {a.width}x{a.height} 8-bit)")
    if len(raw) < expect:
        print("NOTE: shorter than expected; either the format differs or the buffer is padded/short.")
        expect = len(raw) - (len(raw) % a.width)
        a.height = expect // a.width
        print(f"      falling back to {a.width}x{a.height}")
    buf = raw[:expect]

    print("\nwhole-buffer statistics (all-constant means the sensor sent nothing real):")
    stats("raw", buf)

    outdir = a.outdir or os.path.dirname(os.path.abspath(a.buffer))
    base = os.path.splitext(os.path.basename(a.buffer))[0]

    print("\ncandidate A - interleaved LRLR within each line:")
    (lw, lh, L), (rw, rh, R) = split_interleaved(buf, a.width, a.height)
    stats("A.left", L); stats("A.right", R)
    write_pgm(os.path.join(outdir, f"{base}-A-left.pgm"), lw, lh, L)
    write_pgm(os.path.join(outdir, f"{base}-A-right.pgm"), rw, rh, R)

    print("\ncandidate B - alternating L/R lines:")
    (lw2, lh2, L2), (rw2, rh2, R2) = split_line_pairs(buf, a.width, a.height)
    stats("B.left", L2); stats("B.right", R2)
    write_pgm(os.path.join(outdir, f"{base}-B-left.pgm"), lw2, lh2, L2)
    write_pgm(os.path.join(outdir, f"{base}-B-right.pgm"), rw2, rh2, R2)

    print(f"\nwrote 4 PGMs to {outdir} - look at them; the correct split shows the scene twice.")

if __name__ == "__main__":
    main()
