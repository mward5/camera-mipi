#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Measure the exposure character of captured PPM frames, to judge AGC tuning
# against real output pixels rather than against the raw stats the AGC itself
# sees. Reports the displayed-brightness distribution and how much of the frame
# is clipped, which is what "looks washed out / too bright" actually means.
#
# Plain-stdlib P6 PPM parsing: no numpy on this box, and PIL isn't needed for
# what amounts to a byte histogram.

import sys


def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()

    # P6 header: magic, width, height, maxval - whitespace separated, with
    # '#' comments legal anywhere in the header.
    fields = []
    i = 2  # skip "P6"
    while len(fields) < 3:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b'#':
            while data[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        start = i
        while i < len(data) and not data[i:i + 1].isspace():
            i += 1
        fields.append(int(data[start:i]))
    i += 1  # single whitespace byte after maxval

    width, height, maxval = fields
    if maxval != 255:
        raise ValueError(f'{path}: only 8-bit PPM supported (maxval={maxval})')
    return width, height, data[i:i + width * height * 3]


def analyse(path):
    width, height, pix = read_ppm(path)

    # Luma histogram (Rec.601, matching what swstats_cpu.cpp uses) plus a
    # per-channel clipped count, since a channel can clip while luma doesn't.
    yhist = [0] * 256
    clipped_any = 0
    npix = width * height

    for p in range(0, npix * 3, 3):
        r = pix[p]
        g = pix[p + 1]
        b = pix[p + 2]
        yhist[(r * 77 + g * 150 + b * 29) >> 8] += 1
        if r >= 250 or g >= 250 or b >= 250:
            clipped_any += 1

    total = sum(yhist)
    mean = sum(v * n for v, n in enumerate(yhist)) / total

    def pct_at_or_above(threshold):
        return 100.0 * sum(yhist[threshold:]) / total

    def percentile(q):
        want = q * total
        run = 0
        for v, n in enumerate(yhist):
            run += n
            if run >= want:
                return v
        return 255

    print(f'{path}  ({width}x{height})')
    print(f'  mean displayed luma : {mean:6.1f} / 255  ({100 * mean / 255:.1f}%)')
    print(f'  median (p50)        : {percentile(0.50):6d}')
    print(f'  p90 / p99           : {percentile(0.90):6d} / {percentile(0.99):d}')
    print(f'  luma >= 250 (clip)  : {pct_at_or_above(250):6.2f}%')
    print(f'  luma >= 240         : {pct_at_or_above(240):6.2f}%')
    print(f'  any channel >= 250  : {100.0 * clipped_any / npix:6.2f}%')
    return mean, pct_at_or_above(250)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'usage: {sys.argv[0]} <frame.ppm> [frame.ppm ...]', file=sys.stderr)
        sys.exit(1)
    for path in sys.argv[1:]:
        analyse(path)
