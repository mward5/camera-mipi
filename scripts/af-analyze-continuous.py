#!/usr/bin/env python3
"""Analysis for scripts/af-continuous-sweep.sh output.

Correlates cam's per-frame timestamps (a different, uncalibrated clock -
see the shell script's header) against the focus-position write log via the
one-time (uptime, camclock) anchor pair captured at stream start, buckets
each frame to whichever focus_absolute write most recently preceded it, and
computes a Laplacian-variance sharpness metric per frame. Reports:
  - per-position mean/first/last sharpness and exposure (a real focus curve
    should be unimodal - rise then fall - not monotonic; a monotonic curve
    here would suggest a lingering AGC-drift confound, same as Phase 0's
    first, discarded attempt)
  - settle behavior: how many frames after a position change before
    sharpness stabilizes, i.e. an empirical read on lens settle time.

No numpy dependency (not installed on this box) - PIL only.
"""
import bisect
import csv
import glob
import re
import sys
from pathlib import Path

from PIL import Image

from af_metrics import laplacian_variance


def sharpness(path: Path) -> float:
    return laplacian_variance(Image.open(path).convert("L"))


def parse_capture_log(log_path: Path):
    """Returns list of dicts: {seq, camclock, exposure, gain}, one per frame,
    in the order cam printed them (matches ascending seq)."""
    frames = []
    cur = None
    seq_re = re.compile(r"^([\d.]+) \([\d.]+ fps\) cam0-stream0 seq: (\d+)")
    for line in log_path.open(errors="replace"):
        m = seq_re.match(line)
        if m:
            if cur is not None:
                frames.append(cur)
            cur = {"camclock": float(m.group(1)), "seq": int(m.group(2)),
                   "exposure": None, "gain": None}
            continue
        if cur is not None:
            if "ExposureTime" in line:
                cur["exposure"] = float(line.split("=")[1])
            elif "AnalogueGain" in line:
                cur["gain"] = float(line.split("=")[1])
    if cur is not None:
        frames.append(cur)
    return frames


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <continuous-sweep-outdir>", file=sys.stderr)
        sys.exit(1)

    outdir = Path(sys.argv[1])

    anchor_text = (outdir / "clock-anchor.txt").read_text()
    anchor = dict(kv.split("=") for kv in anchor_text.split())
    anchor_uptime = float(anchor["anchor_uptime"])
    anchor_camclock = float(anchor["anchor_camclock"])
    offset = anchor_uptime - anchor_camclock

    positions = []  # (uptime, position), sorted by construction
    with (outdir / "positions.csv").open() as f:
        for row in csv.DictReader(f):
            positions.append((float(row["uptime"]), int(row["position"])))
    pos_times = [p[0] for p in positions]

    frames = parse_capture_log(outdir / "capture.log")
    frame_files = {int(Path(p).stem.split("-")[-1]): Path(p)
                   for p in glob.glob(str(outdir / "frame-*.ppm"))}

    # bucket[position] -> list of (frames_since_change, sharpness, exposure)
    buckets = {}
    since_change = {}
    last_pos = None
    rows_out = []
    for fr in frames:
        frame_uptime = fr["camclock"] + offset
        idx = bisect.bisect_right(pos_times, frame_uptime) - 1
        if idx < 0:
            continue  # before the first logged focus write (settle window)
        pos = positions[idx][1]
        if pos != last_pos:
            since_change[pos] = 0
            last_pos = pos
        else:
            since_change[pos] = since_change.get(pos, 0) + 1

        path = frame_files.get(fr["seq"])
        if path is None:
            continue
        sh = sharpness(path)
        buckets.setdefault(pos, []).append((since_change[pos], sh, fr["exposure"]))
        rows_out.append((fr["seq"], pos, since_change[pos], sh, fr["exposure"], fr["gain"]))

    csv_out = outdir / "analysis.csv"
    with csv_out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["seq", "position", "frames_since_change", "sharpness", "exposure", "gain"])
        w.writerows(rows_out)

    print(f"{'pos':>5} {'n':>3} {'first':>10} {'last':>10} {'mean':>10} "
          f"{'exp_first':>10} {'exp_last':>10}")
    means = []
    for pos in sorted(buckets):
        entries = sorted(buckets[pos])  # by frames_since_change
        shs = [e[1] for e in entries]
        exps = [e[2] for e in entries if e[2] is not None]
        mean_sh = sum(shs) / len(shs)
        means.append((pos, mean_sh))
        exp_first = exps[0] if exps else float("nan")
        exp_last = exps[-1] if exps else float("nan")
        print(f"{pos:>5} {len(shs):>3} {shs[0]:>10.1f} {shs[-1]:>10.1f} {mean_sh:>10.1f} "
              f"{exp_first:>10.1f} {exp_last:>10.1f}")

    if means:
        best = max(means, key=lambda m: m[1])
        print(f"\nSharpest mean position: {best[0]} (mean={best[1]:.1f})")
        vals = [m[1] for m in means]
        spread = max(vals) - min(vals)
        print(f"Mean-sharpness spread: {spread:.1f} ({spread/(sum(vals)/len(vals))*100:.0f}% of average)")

        # crude monotonicity check: a real focus peak should rise then fall,
        # not move in one direction the whole way.
        diffs = [vals[i+1] - vals[i] for i in range(len(vals) - 1)]
        signs = [1 if d > 0 else -1 for d in diffs]
        sign_changes = sum(1 for i in range(len(signs) - 1) if signs[i] != signs[i+1])
        print(f"Sign changes in the sharpness-vs-position trend: {sign_changes} "
              f"(0 = monotonic, i.e. probably still confounded; >=1 = has a real peak shape)")

    print(f"\nFull per-frame data: {csv_out}")


if __name__ == "__main__":
    main()
