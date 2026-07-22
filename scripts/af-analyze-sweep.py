#!/usr/bin/env python3
"""Phase 1 (early prototype) analysis for scripts/af-sweep-measure.sh output.

Reads a Phase 0 dataset (sweep.csv + pos_<N>_frame-*.ppm), computes a
Laplacian-variance sharpness metric on a central crop of each frame, and
prints per-position stats: sharpness of the first vs. last frame in each
burst (a first-pass proxy for "did the lens finish settling within the
burst?") and the mean sharpness per position (to see whether the metric
actually varies across the sweep - if it's flat, the scene doesn't have
enough depth variation for this dataset to be useful).

No numpy dependency (not installed on this box) - PIL only, pure Python
loops over a downsampled crop for speed.
"""
import csv
import glob
import sys
from pathlib import Path

from PIL import Image, ImageFilter, ImageStat

CROP_SIZE = 800  # central NxN crop, kept at full sensor resolution (no
                  # resize) since resizing would blur exactly the high-
                  # frequency detail a sharpness metric needs.


def sharpness(path: Path) -> float:
    img = Image.open(path).convert("L")
    w, h = img.size
    left = (w - CROP_SIZE) // 2
    top = (h - CROP_SIZE) // 2
    crop = img.crop((left, top, left + CROP_SIZE, top + CROP_SIZE))
    edges = crop.filter(ImageFilter.FIND_EDGES)
    return ImageStat.Stat(edges).var[0]


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <sweep-outdir>", file=sys.stderr)
        sys.exit(1)

    outdir = Path(sys.argv[1])
    csv_path = outdir / "sweep.csv"
    rows = list(csv.DictReader(csv_path.open()))

    print(f"{'pos':>5} {'n':>3} {'first':>10} {'last':>10} {'mean':>10} {'min':>10} {'max':>10}")
    results = []
    for row in rows:
        pos = int(row["position"])
        frames = sorted(glob.glob(str(outdir / f"pos_{pos}_frame-*.ppm")))
        if not frames:
            print(f"{pos:>5}  (no frames found)")
            continue
        vals = [sharpness(Path(f)) for f in frames]
        results.append((pos, vals))
        print(f"{pos:>5} {len(vals):>3} {vals[0]:>10.1f} {vals[-1]:>10.1f} "
              f"{sum(vals)/len(vals):>10.1f} {min(vals):>10.1f} {max(vals):>10.1f}")

    if results:
        best = max(results, key=lambda r: sum(r[1]) / len(r[1]))
        print(f"\nSharpest mean position in this sweep: {best[0]} "
              f"(mean={sum(best[1])/len(best[1]):.1f})")
        spread = max(sum(v) / len(v) for _, v in results) - min(sum(v) / len(v) for _, v in results)
        flat_pct = spread / (sum(sum(v) / len(v) for _, v in results) / len(results)) * 100
        print(f"Mean-sharpness spread across the sweep: {spread:.1f} "
              f"({flat_pct:.0f}% of average) - if this is small, the scene "
              f"likely doesn't have enough depth variation for this dataset "
              f"to say anything about real focus behavior.")


if __name__ == "__main__":
    main()
