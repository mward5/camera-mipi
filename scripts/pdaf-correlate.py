#!/usr/bin/env python3
"""PDAF phase-0: offline phase correlation on captured PAF buffers.

THROWAWAY EXPERIMENT - see docs/pdaf-implementation-plan.md, WP0 step 6.

For each region of the frame, slide the right plane against the left over a
bounded shift range, take the sum of absolute differences, and call the
sub-sample minimum the phase. Confidence is how deep and distinct that minimum
is relative to the curve's mean.

This is the thing WP3 must eventually reimplement in C++ inside libcamera,
where it stands in for the IPU6's own pafstatistics_1 hardware kernel. Keep
the region grid and the bounded shift range: correlating at full resolution is
not affordable at 30 fps (see the plan's note on Finding 4).

Success criterion for WP0: phase should vary monotonically with lens position.
The slope becomes the first estimate of libcamera's pdaf_gain.

Sign convention: the reported phase is the shift s that best aligns L[x] with
R[x+s]. Verified against synthetic frames built as R[x] = L[x+d]: the tool
reports -d, exactly and consistently, for d in {-6,-3,0,+3,+6}. Only the sign
of pdaf_gain depends on this, so what matters is that it is consistent.

Stdlib only: this machine has no numpy.
"""
import argparse, glob, os, re, sys

def load_planes(path, width, height, layout):
    raw = open(path, 'rb').read()
    need = width * height
    if len(raw) < need:
        height = len(raw) // width
        need = width * height
    buf = raw[:need]
    if layout == "interleaved":
        hw = width // 2
        L = [buf[y * width:(y + 1) * width][0::2] for y in range(height)]
        R = [buf[y * width:(y + 1) * width][1::2] for y in range(height)]
        return L, R, hw, height
    else:  # line pairs
        hh = height // 2
        L = [buf[(2 * y) * width:(2 * y + 1) * width] for y in range(hh)]
        R = [buf[(2 * y + 1) * width:(2 * y + 2) * width] for y in range(hh)]
        return L, R, width, hh

def correlate_cell(L, R, y0, y1, x0, x1, max_shift, row_step):
    """SAD over shifts; returns (phase, confidence) or (None, 0)."""
    sums = {}
    for s in range(-max_shift, max_shift + 1):
        tot = 0; cnt = 0
        for y in range(y0, y1, row_step):
            lrow = L[y]; rrow = R[y]
            xs = max(x0, x0 - s); xe = min(x1, x1 - s)
            if xe <= xs:
                continue
            for x in range(xs, xe, 2):
                tot += abs(lrow[x] - rrow[x + s])
                cnt += 1
        if cnt:
            sums[s] = tot / cnt
    if len(sums) < 3:
        return None, 0.0
    best = min(sums, key=sums.get)
    mean = sum(sums.values()) / len(sums)
    lo = sums[best]
    # parabolic sub-sample refinement
    phase = float(best)
    if best - 1 in sums and best + 1 in sums:
        a, b, c = sums[best - 1], sums[best], sums[best + 1]
        denom = (a - 2 * b + c)
        if denom != 0:
            phase = best + 0.5 * (a - c) / denom
    conf = (mean - lo) / mean if mean > 0 else 0.0
    return phase, conf

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="paf-*.bin buffers")
    ap.add_argument("--width", type=int, default=3968)
    ap.add_argument("--height", type=int, default=684)
    ap.add_argument("--layout", choices=["interleaved", "linepairs"], default="interleaved")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--rows", type=int, default=3)
    ap.add_argument("--max-shift", type=int, default=16)
    ap.add_argument("--row-step", type=int, default=8, help="subsample rows for speed")
    a = ap.parse_args()

    print(f"layout={a.layout} grid={a.cols}x{a.rows} shifts=+/-{a.max_shift} row_step={a.row_step}")
    print(f"{'file':<24} {'weighted phase':>14} {'mean conf':>10}   per-cell (phase@conf)")
    for path in sorted(a.files):
        try:
            L, R, w, h = load_planes(path, a.width, a.height, a.layout)
        except Exception as e:
            print(f"{os.path.basename(path):<24} ERROR {e}")
            continue
        cw = w // a.cols; ch = h // a.rows
        cells = []
        num = 0.0; den = 0.0; confs = []
        for r in range(a.rows):
            for c in range(a.cols):
                x0 = c * cw + a.max_shift; x1 = (c + 1) * cw - a.max_shift
                y0 = r * ch; y1 = (r + 1) * ch
                ph, cf = correlate_cell(L, R, y0, y1, x0, x1, a.max_shift, a.row_step)
                if ph is None:
                    cells.append("  --  "); confs.append(0.0); continue
                cells.append(f"{ph:+5.2f}@{cf:.2f}")
                num += ph * cf; den += cf; confs.append(cf)
        wph = (num / den) if den > 0 else float('nan')
        mc = sum(confs) / len(confs) if confs else 0.0
        print(f"{os.path.basename(path):<24} {wph:>14.3f} {mc:>10.3f}   {' '.join(cells)}")

    print("\nWP0 passes if weighted phase moves monotonically with lens position.")
    print("Pair these against lens-positions.txt from the capture run.")

if __name__ == "__main__":
    main()
