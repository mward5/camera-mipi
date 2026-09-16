#!/usr/bin/env python3
"""Compare the per-arm frames grabbed by pdaf-mode-table-ab.sh.

The two mode tables differ at 0x0900 (binning), so the image content can
change while the frame size does not. This reports per-arm statistics and a
coarse row profile; identical statistics across arms of the same label, and
a real difference between labels, is what a binning change would look like.

Frames are SGRBG10 packed as the IPU6 delivers them - 4 pixels per 5 bytes.
Only the high byte of each pixel is used here, which is plenty for comparing
brightness structure and costs no unpacking.

Usage: pdaf-compare-frames.py <dir>
"""
import sys
import pathlib
import statistics

W, H = 3976, 2736
ROW_BYTES = W * 5 // 4


def profile(path):
    """Mean of every pixel's high byte, plus a 12-band vertical profile."""
    data = path.read_bytes()
    rows = len(data) // ROW_BYTES
    means, band, bands = [], [], []
    per_band = max(1, rows // 12)
    for r in range(rows):
        row = data[r * ROW_BYTES:(r + 1) * ROW_BYTES]
        # high bytes sit at 0,1,2,3 of each 5-byte group; byte 4 is the low bits
        hi = [row[i] for i in range(0, len(row) - 4, 5)]
        m = sum(hi) / len(hi) if hi else 0.0
        means.append(m)
        band.append(m)
        if len(band) >= per_band:
            bands.append(sum(band) / len(band))
            band = []
    if band:
        bands.append(sum(band) / len(band))
    return len(data), rows, means, bands[:12]


def main():
    d = pathlib.Path(sys.argv[1])
    frames = sorted(d.glob("*.raw"))
    if not frames:
        print("  no frames captured")
        return
    results = []
    for f in frames:
        size, rows, means, bands = profile(f)
        results.append((f.name, size, rows, means, bands))
        print(f"  {f.name:24s} {size:>10d} B  {rows:>5d} rows  "
              f"mean {statistics.mean(means):7.2f}  "
              f"row-sd {statistics.pstdev(means):6.2f}")

    print()
    print("  vertical profile (12 bands, mean of pixel high bytes):")
    for name, _, _, _, bands in results:
        print(f"    {name:24s} " + " ".join(f"{b:6.1f}" for b in bands))

    print()
    print("  A binning change would move these profiles between arms.")
    print("  Scene drift moves them between repeats of the SAME arm too -")
    print("  compare stock-vs-pdaf against stock-vs-stock before concluding.")


if __name__ == "__main__":
    main()
