#!/usr/bin/env python3
"""Compares Laplacian variance (the metric used everywhere else in this
project so far) against a Tenengrad-style gradient-energy metric, on frames
already captured by scripts/af-continuous-sweep.sh - no new hardware capture
needed. Answers unknown 2's open "only one metric has been tried" gap.

No numpy on this box - Tenengrad is approximated with two PIL Sobel
convolutions (ImageFilter.Kernel) plus a 256-entry point() LUT for the
squaring step (fast: point() with a callable builds a lookup table once for
'L'-mode images, not a per-pixel Python loop), then summed. This clips at
255 per pixel before combining, so it's a relative/comparative metric, not a
mathematically exact Tenengrad - fine for "does this track focus at least as
well as Laplacian variance", not fine for an absolute cross-paper number.
"""
import csv
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

SOBEL_X = ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=1, offset=128)
SOBEL_Y = ImageFilter.Kernel((3, 3), [-1, -2, -1, 0, 0, 0, 1, 2, 1], scale=1, offset=128)
_SQUARE_LUT = [min(255, ((p - 128) ** 2) // 64) for p in range(256)]


def laplacian_variance(img_l: Image.Image) -> float:
    edges = img_l.filter(ImageFilter.FIND_EDGES)
    return ImageStat.Stat(edges).var[0]


def tenengrad(img_l: Image.Image) -> float:
    gx = img_l.filter(SOBEL_X).point(_SQUARE_LUT)
    gy = img_l.filter(SOBEL_Y).point(_SQUARE_LUT)
    combined = ImageChops.add(gx, gy)
    return ImageStat.Stat(combined).sum[0]


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <continuous-sweep-outdir>", file=sys.stderr)
        sys.exit(1)
    outdir = Path(sys.argv[1])

    # Reuse the position bucketing already computed by af-analyze-continuous.py
    # (analysis.csv has seq -> position), rather than re-deriving it from
    # positions.csv/clock-anchor.txt.
    analysis_csv = outdir / "analysis.csv"
    if not analysis_csv.exists():
        print(f"{analysis_csv} not found - run scripts/af-analyze-continuous.py "
              f"on this dataset first", file=sys.stderr)
        sys.exit(1)

    rows = list(csv.DictReader(analysis_csv.open()))
    by_pos = {}
    for r in rows:
        by_pos.setdefault(int(r["position"]), []).append(r)

    print(f"{'pos':>5} {'n':>3} {'lapvar_mean':>12} {'tenengrad_mean':>15}")
    lap_means, ten_means = [], []
    for pos in sorted(by_pos):
        lap_vals, ten_vals = [], []
        for r in by_pos[pos]:
            path = outdir / f"frame-cam0-stream0-{int(r['seq']):06d}.ppm"
            if not path.exists():
                continue
            img = Image.open(path).convert("L")
            lap_vals.append(laplacian_variance(img))
            ten_vals.append(tenengrad(img))
        if not lap_vals:
            continue
        lm = sum(lap_vals) / len(lap_vals)
        tm = sum(ten_vals) / len(ten_vals)
        lap_means.append((pos, lm))
        ten_means.append((pos, tm))
        print(f"{pos:>5} {len(lap_vals):>3} {lm:>12.1f} {tm:>15.0f}")

    def summarize(name, means):
        vals = [v for _, v in means]
        best = max(means, key=lambda m: m[1])
        spread = max(vals) - min(vals)
        avg = sum(vals) / len(vals)
        diffs = [vals[i + 1] - vals[i] for i in range(len(vals) - 1)]
        signs = [1 if d > 0 else -1 for d in diffs]
        sign_changes = sum(1 for i in range(len(signs) - 1) if signs[i] != signs[i + 1])
        # crude noise estimate: how much do same-position samples disagree,
        # relative to the spread across different positions - reuses lap/ten
        # per-frame values already computed above via a second pass would be
        # needed for a real per-position stddev; keep this simple and just
        # report the peak/spread/monotonicity, which is what we actually
        # care about for "does this metric make hill-climbing viable".
        print(f"\n{name}: peak at pos={best[0]} ({best[1]:.1f}), "
              f"spread={spread:.1f} ({spread/avg*100:.0f}% of avg), "
              f"sign_changes={sign_changes}")

    summarize("Laplacian variance", lap_means)
    summarize("Tenengrad (approx)", ten_means)


if __name__ == "__main__":
    main()
