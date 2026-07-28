#!/usr/bin/env python3
"""Sharpness metrics shared across the AF prototyping/analysis scripts.

Both metrics operate on an already-opened, already-'L'-converted (and, where
a caller wants it, already-cropped) PIL image - callers own file I/O and any
cropping, this module owns only the metric math, so each script's own
`sharpness(path)` wrapper keeps its existing behavior (crop-before-measure
in af-analyze-sweep.py, no crop elsewhere) unchanged.

tenengrad() is the metric af-hillclimb-prototype.py's live controller
actually uses (see that module's docstring for why: Laplacian variance's
reported peak on the 2026-07-22 wall-test scene didn't match what the
frames actually looked like, on a scene with an overexposed glare/hotspot
plus a noisy background). laplacian_variance() is kept for
af-analyze-continuous.py, af-analyze-sweep.py, and af-compare-metrics.py's
own side-by-side comparison of the two.
"""
from PIL import Image, ImageChops, ImageFilter, ImageStat

# Approximate Tenengrad (clips at 255 per pixel before combining Gx/Gy via
# ImageChops.add) - a relative/comparative metric, not a mathematically
# exact one. No numpy on this box; the squaring step uses a 256-entry
# point() LUT (fast: builds the lookup table once for 'L'-mode images,
# not a per-pixel Python loop) instead.
SOBEL_X = ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=1, offset=128)
SOBEL_Y = ImageFilter.Kernel((3, 3), [-1, -2, -1, 0, 0, 0, 1, 2, 1], scale=1, offset=128)
_SQUARE_LUT = [min(255, ((p - 128) ** 2) // 64) for p in range(256)]


def tenengrad(img_l: Image.Image) -> float:
    gx = img_l.filter(SOBEL_X).point(_SQUARE_LUT)
    gy = img_l.filter(SOBEL_Y).point(_SQUARE_LUT)
    combined = ImageChops.add(gx, gy)
    return ImageStat.Stat(combined).sum[0]


def laplacian_variance(img_l: Image.Image) -> float:
    edges = img_l.filter(ImageFilter.FIND_EDGES)
    return ImageStat.Stat(edges).var[0]
