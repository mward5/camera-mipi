#!/usr/bin/env python3
"""Phase 1 CDAF hill-climb prototype (see docs/autofocus-cdaf-scoping.md).

Standalone, throwaway research code (Option B) - drives a real coarse-then-
fine hill-climb against the actual hardware: writes focus_absolute via
v4l2-ctl to the lc898217 lens subdev, reads frames as `cam` writes them to
disk (polling for the next expected filename rather than the clock-
correlation trick af-analyze-continuous.py needed - here the controller
itself issues every focus write, so it can just timestamp with its own
clock), and computes a Tenengrad-style gradient-energy sharpness metric per
frame.

Originally used Laplacian variance (matching af-analyze-continuous.py), but
scripts/af-compare-metrics.py plus a direct visual check of the actual PPM
frames (2026-07-22 - see docs/autofocus-cdaf-scoping.md) found Laplacian
variance's reported peak on the wall test scene (positions 0-256) does NOT
match what the images actually look like - those frames are visibly
blurrier than positions ~640-720, which is where Tenengrad's peak (and a
direct look at the frames) says the real peak is. Root cause: this scene
has a large overexposed glare/hotspot plus a noisy background, and a naive
full-frame Laplacian variance is dominated by that rather than the
in-focus grid-line texture. Switched the live controller to Tenengrad
accordingly - still not verified as *the* right choice in general, only
verified as more trustworthy than Laplacian variance *on this scene*.

Two things this deliberately does differently from a naive hill-climb,
both driven by empirical findings from the sweep scripts:
  - Settle detection (wait for N consecutive frames within a tolerance
    band) instead of a fixed post-move delay. 2026-07-22's stationary sweep
    found settle time for a constant 64-unit step ranging from instant to
    ~870ms, including an apparent overshoot/ringing case - a short fixed
    delay would sometimes read a transiently wrong value.
  - After converging, it doesn't stop. It switches to a continuous monitor
    loop that watches for degradation and re-scans - per the project's
    "continuous AF, not single-shot" decision, and runs with zero external
    trigger needed, per the "must work without app cooperation" decision.
    A scripted "jolt" partway through the monitor phase (deliberately
    writing a bad position, simulating something knocking focus off)
    exercises that recovery path without needing a human to change the
    physical scene mid-run.

Not integrated into libcamera - this validates the algorithm and its
constants before Phase 3 ports it into a real src/ipa/simple/algorithms/
af.cpp. Full-frame captures are written to OUTDIR and NOT cleaned up
automatically; a real (in-process, no-disk-round-trip) implementation is
what Phase 3 is for.

AGC locking (2026-07-23, see docs/autofocus-cdaf-scoping.md "Decided
2026-07-23: lock, don't normalize" and "Built and validated"): confirmed
gain-driven sharpness noise is roughly the same size as the real focus
signal (pooled r=0.705 between gain and sharpness at fixed focus), and an
external v4l2-ctl write to analogue_gain gets overwritten by Agc within a
frame - unlike focus_absolute, which nothing else touches. So --lock-agc
(on by default) mirrors what scripts/af-continuous-sweep.sh already does:
pre-warm with real Agc briefly to pick a starting exposure/gain, then
remove `Agc:` from the *local dev build's* tuning file (never the
system-installed package Snapshot uses, so this never affects normal
camera use) and re-assert the pre-warmed values. Restored on exit; a
self-healing check at startup detects and git-checkouts a YAML left
mid-edit by a prior run that got SIGKILLed (confirmed happening in
practice while building the sweep-script version of this).
"""
import argparse
import csv
import re
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat

FOCUS_MIN = 0
FOCUS_MAX = 1023

# Tenengrad-style gradient energy, matching scripts/af-compare-metrics.py.
# Approximate (clips at 255 per pixel before combining Gx/Gy) but empirically
# validated against actual frame content, unlike the Laplacian-variance
# metric this replaced - see the module docstring.
_SOBEL_X = ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=1, offset=128)
_SOBEL_Y = ImageFilter.Kernel((3, 3), [-1, -2, -1, 0, 0, 0, 1, 2, 1], scale=1, offset=128)
_SQUARE_LUT = [min(255, ((p - 128) ** 2) // 64) for p in range(256)]


def sharpness(path: Path) -> float:
    img = Image.open(path).convert("L")
    gx = img.filter(_SOBEL_X).point(_SQUARE_LUT)
    gy = img.filter(_SOBEL_Y).point(_SQUARE_LUT)
    combined = ImageChops.add(gx, gy)
    return ImageStat.Stat(combined).sum[0]


def find_ipu6_media_device() -> str:
    for dev in sorted(Path("/dev").glob("media*")):
        try:
            out = subprocess.run(["media-ctl", "-d", str(dev), "-p"],
                                  capture_output=True, text=True, timeout=5).stdout
        except Exception:
            continue
        if "driver" in out and "intel-ipu6" in out:
            return str(dev)
    raise RuntimeError("Could not find the intel-ipu6 media device among /dev/media*")


def resolve_entity(mdev: str, entity: str) -> str:
    out = subprocess.run(["media-ctl", "-d", mdev, "-e", entity],
                          capture_output=True, text=True, check=True).stdout
    return out.strip()


def set_focus(lens_dev: str, pos: int):
    pos = max(FOCUS_MIN, min(FOCUS_MAX, pos))
    subprocess.run(["v4l2-ctl", "-d", lens_dev, "-c", f"focus_absolute={pos}"],
                    check=True, capture_output=True)
    return pos


def get_ctrl(dev: str, name: str) -> int:
    out = subprocess.run(["v4l2-ctl", "-d", dev, f"--get-ctrl={name}"],
                          capture_output=True, text=True, check=True).stdout
    return int(re.search(r"(\d+)\s*$", out).group(1))


def set_ctrls(dev: str, **ctrls):
    arg = ",".join(f"{k}={v}" for k, v in ctrls.items())
    subprocess.run(["v4l2-ctl", "-d", dev, "-c", arg], check=True, capture_output=True)


def yaml_has_agc(yaml_path: Path) -> bool:
    return any(line.rstrip("\n") == "  - Agc:" for line in yaml_path.open())


def restore_yaml_if_broken(yaml_path: Path, libcam_src_root: Path, log_print):
    """Self-healing: a prior run killed via SIGKILL (e.g. an enclosing
    `timeout` escalating past SIGTERM, which can't be trapped/caught) can
    leave this file mid-edit with Agc missing. Confirmed happening in
    practice 2026-07-23 while building the sweep-script version of this
    lock. Fix it before doing anything else rather than silently running
    "locked" when the caller didn't ask for that."""
    if yaml_has_agc(yaml_path):
        return
    log_print(f"WARNING: {yaml_path} is missing Agc (likely left over from "
              "an interrupted previous run) - restoring via git checkout.")
    subprocess.run(["git", "-C", str(libcam_src_root), "checkout", "--",
                     "src/ipa/simple/data/s5k3j1.yaml"], check=True)
    if not yaml_has_agc(yaml_path):
        raise RuntimeError(f"git checkout didn't restore Agc in {yaml_path} "
                            "- needs manual attention")


def lock_agc(sensor_dev: str, cam_bin: str, width: int, height: int, env: dict,
             outdir: Path, prewarm_time: float, yaml_path: Path, log_print):
    """Pre-warms with real Agc, then removes it from the tuning file and
    freezes exposure/gain at whatever Agc picked. Returns the backup path
    (caller restores it in a finally block) or None if nothing was changed."""
    log_print(f"LOCK_AGC: pre-warming Agc for {prewarm_time}s to pick a starting exposure/gain...")
    prewarm_log = (outdir / "prewarm.log").open("w")
    proc = subprocess.Popen(
        [cam_bin, r"--camera=\_SB_.PC00.LNK0",
         "-s", f"width={width},height={height},role=viewfinder", "--capture"],
        stdout=prewarm_log, stderr=subprocess.STDOUT, env=env)
    time.sleep(prewarm_time)
    proc.send_signal(2)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
    prewarm_log.close()

    exposure = get_ctrl(sensor_dev, "exposure")
    gain = get_ctrl(sensor_dev, "analogue_gain")
    log_print(f"Locking at exposure={exposure} analogue_gain={gain} "
              f"(removing Agc from {yaml_path} for this run)")

    backup = outdir / "s5k3j1.yaml.orig-backup"
    backup.write_text(yaml_path.read_text())
    lines = [l for l in yaml_path.read_text().splitlines(keepends=True)
             if l.rstrip("\n") != "  - Agc:"]
    yaml_path.write_text("".join(lines))
    if yaml_has_agc(yaml_path):
        raise RuntimeError(f"Failed to remove Agc from {yaml_path}")

    # Agc removed means nothing drives these controls anymore - re-assert
    # the pre-warmed values explicitly in case the sensor reset on re-open.
    set_ctrls(sensor_dev, exposure=exposure, analogue_gain=gain)
    return backup


class FrameWatcher:
    """Polls for the next expected cam output frame by filename, in order.

    Simpler and more robust than trying to correlate cam's own printed
    timestamps (which run on a different clock epoch, see
    af-analyze-continuous.py's header) - this controller issues every focus
    write itself, so it only needs to know "give me the next new frame",
    tagged with this process's own wall-clock time when it notices it.
    """

    def __init__(self, outdir: Path, poll_interval: float = 0.02):
        self.outdir = outdir
        self.poll_interval = poll_interval
        self.next_seq = 0

    def _path_for(self, seq: int) -> Path:
        return self.outdir / f"frame-cam0-stream0-{seq:06d}.ppm"

    def next_frame(self, timeout: float = 3.0):
        """Blocks for the next frame, returns (seq, wall_time, sharpness) or
        None on timeout.

        cam occasionally drops a frame's file write entirely (confirmed
        2026-07-23: a 4-frame gap in an otherwise-continuous sequence, cam
        itself kept streaming fine). The naive version of this only ever
        waited on self.next_seq and never advanced past a frame that would
        never arrive - one missing file permanently deadlocked every
        subsequent call, silently turning the rest of a run into all-zero
        readings. If the expected frame doesn't show up in time, scan a
        little ahead for a later one that did, and skip forward to it.
        """
        deadline = time.monotonic() + timeout
        path = self._path_for(self.next_seq)
        while time.monotonic() < deadline:
            if path.exists():
                # cam writes the file in one shot in practice, but guard
                # against reading a partially-flushed file anyway.
                for attempt in range(3):
                    try:
                        sh = sharpness(path)
                        break
                    except Exception:
                        time.sleep(0.03)
                else:
                    return None
                seq = self.next_seq
                self.next_seq += 1
                return seq, time.monotonic(), sh
            time.sleep(self.poll_interval)
        # Timed out on self.next_seq specifically - check whether cam moved
        # on without it (a dropped frame) rather than stalling entirely.
        for lookahead in range(1, 50):
            candidate = self.next_seq + lookahead
            if self._path_for(candidate).exists():
                self.next_seq = candidate
                return self.next_frame(timeout=timeout)
        return None

    def drain_stale(self):
        """Skip past any frames already sitting on disk (e.g. from the AGC
        settle window) so the next next_frame() call returns a fresh one."""
        while self._path_for(self.next_seq).exists():
            self.next_seq += 1


def settle_and_read(watcher: FrameWatcher, log_rows, tolerance=0.02,
                     min_stable=4, timeout=1.5):
    """Consumes frames until min_stable consecutive readings are within
    `tolerance` of their own mean, or timeout elapses. Returns
    (mean_sharpness, settled: bool, n_frames_seen)."""
    window = []
    start = time.monotonic()
    n = 0
    while time.monotonic() - start < timeout:
        fr = watcher.next_frame(timeout=max(0.05, timeout - (time.monotonic() - start)))
        if fr is None:
            break
        seq, t, sh = fr
        n += 1
        log_rows.append((seq, t, sh))
        window.append(sh)
        if len(window) > min_stable:
            window.pop(0)
        if len(window) == min_stable:
            m = sum(window) / len(window)
            if m > 0 and all(abs(v - m) <= tolerance * m for v in window):
                return m, True, n
    # timed out - best effort from whatever we have
    tail = window if window else [0.0]
    return sum(tail) / len(tail), False, n


def coarse_fine_scan(lens_dev, watcher, log_rows, coarse_step, fine_step,
                      settle_kwargs, log_print):
    samples = []
    for pos in range(FOCUS_MIN, FOCUS_MAX + 1, coarse_step):
        actual = set_focus(lens_dev, pos)
        mean_sh, settled, n = settle_and_read(watcher, log_rows, **settle_kwargs)
        samples.append((actual, mean_sh))
        log_print(f"  coarse pos={actual:4d} sharpness={mean_sh:8.1f} "
                   f"settled={settled} frames={n}")
    coarse_best = max(samples, key=lambda s: s[1])[0]

    fine_lo = max(FOCUS_MIN, coarse_best - coarse_step)
    fine_hi = min(FOCUS_MAX, coarse_best + coarse_step)
    fine_samples = []
    for pos in range(fine_lo, fine_hi + 1, fine_step):
        actual = set_focus(lens_dev, pos)
        mean_sh, settled, n = settle_and_read(watcher, log_rows, **settle_kwargs)
        fine_samples.append((actual, mean_sh))
        log_print(f"  fine   pos={actual:4d} sharpness={mean_sh:8.1f} "
                   f"settled={settled} frames={n}")
    fine_best, fine_best_sh = max(fine_samples, key=lambda s: s[1])

    set_focus(lens_dev, fine_best)
    converged_sh, settled, n = settle_and_read(watcher, log_rows, **settle_kwargs)
    log_print(f"  converged pos={fine_best:4d} sharpness={converged_sh:8.1f} "
               f"settled={settled}")
    return fine_best, converged_sh


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--coarse-step", type=int, default=96)
    ap.add_argument("--fine-step", type=int, default=16)
    ap.add_argument("--settle-tolerance", type=float, default=0.02)
    ap.add_argument("--settle-min-stable", type=int, default=4)
    ap.add_argument("--settle-timeout", type=float, default=1.5)
    ap.add_argument("--agc-settle-time", type=float, default=2.5)
    ap.add_argument("--monitor-seconds", type=float, default=10.0)
    ap.add_argument("--monitor-interval", type=float, default=0.5)
    ap.add_argument("--degrade-threshold", type=float, default=0.10,
                     help="fractional drop from converged baseline that triggers a re-scan")
    ap.add_argument("--jolt-at", type=float, default=5.0,
                     help="seconds into the monitor phase to force a bad "
                          "position, simulating something knocking focus off")
    ap.add_argument("--width", type=int, default=800)
    ap.add_argument("--height", type=int, default=600)
    ap.add_argument("--cam", default=str(Path.home() / "work/git-ubuntu/libcamera/build/src/apps/cam/cam"))
    ap.add_argument("--libcam", default=str(Path.home() / "work/git-ubuntu/libcamera/build"))
    ap.add_argument("--lock-agc", dest="lock_agc", action="store_true", default=True,
                     help="lock exposure/gain before scanning, matching "
                          "af-continuous-sweep.sh (default: on)")
    ap.add_argument("--no-lock-agc", dest="lock_agc", action="store_false")
    ap.add_argument("--prewarm-time", type=float, default=4.0,
                     help="seconds to let real Agc pick a starting exposure/gain before locking it")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    trace_csv = outdir / "hillclimb-trace.csv"
    events_log = outdir / "events.log"

    def log_print(msg):
        line = f"[{time.monotonic():.2f}] {msg}"
        print(line)
        with events_log.open("a") as f:
            f.write(line + "\n")

    subprocess.run(["systemctl", "--user", "stop", "wireplumber", "pipewire",
                     "pipewire.socket"], capture_output=True)
    subprocess.run(["killall", "-9", "wireplumber", "pipewire", "cam"],
                    capture_output=True)
    time.sleep(1)

    mdev = find_ipu6_media_device()
    lens_dev = resolve_entity(mdev, "lc898217 1-0072")
    sensor_dev = resolve_entity(mdev, "s5k3j1 1-0010")
    log_print(f"MDEV={mdev} lens={lens_dev} sensor={sensor_dev}")

    import os
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{args.libcam}/src/libcamera:" + env.get("LD_LIBRARY_PATH", "")
    env["LIBCAMERA_IPA_MODULE_PATH"] = f"{args.libcam}/src/ipa/simple"
    env.setdefault("LIBCAMERA_DISABLE_IPU6_PDAF", "1")

    # Tuning YAML lives in the source tree, not the build dir (LIBCAM's
    # parent is the source root - confirmed via IPAProxy's own "Using
    # tuning file ..." log line, same as af-continuous-sweep.sh).
    libcam_src_root = Path(args.libcam).parent
    yaml_path = libcam_src_root / "src/ipa/simple/data/s5k3j1.yaml"
    restore_yaml_if_broken(yaml_path, libcam_src_root, log_print)

    set_focus(lens_dev, 0)

    # yaml_backup/cam_proc are set inside the try below (locking can itself
    # fail partway, after modifying the YAML but before returning) - the
    # try/finally has to cover locking too, not just the main capture, or a
    # failure during lock_agc() would leave the YAML broken with no cleanup
    # for *this* run (the startup self-healing check above only catches it
    # on the *next* run).
    yaml_backup = None
    cam_proc = None
    camlog = None
    log_rows = []
    try:
        if args.lock_agc:
            yaml_backup = lock_agc(sensor_dev, args.cam, args.width, args.height,
                                    env, outdir, args.prewarm_time, yaml_path, log_print)

        camlog = (outdir / "capture.log").open("w")
        cam_proc = subprocess.Popen(
            [args.cam, r"--camera=\_SB_.PC00.LNK0",
             "-s", f"width={args.width},height={args.height},role=viewfinder",
             "--capture",
             f"--file={outdir / 'frame-#.ppm'}"],
            stdout=camlog, stderr=subprocess.STDOUT, env=env)
        watcher = FrameWatcher(outdir)

        settle_desc = ("stream/lens settle, AGC locked" if args.lock_agc
                       else "stream startup + AGC settle")
        log_print(f"Waiting for {settle_desc} ({args.agc_settle_time}s)...")
        # Wait for the first frame to confirm streaming actually started.
        fr = watcher.next_frame(timeout=10.0)
        if fr is None:
            log_print("ERROR: no frames arrived - is the camera stack up? "
                       f"See {outdir/'capture.log'}")
            sys.exit(1)
        time.sleep(args.agc_settle_time)
        watcher.drain_stale()

        settle_kwargs = dict(tolerance=args.settle_tolerance,
                              min_stable=args.settle_min_stable,
                              timeout=args.settle_timeout)

        log_print("=== Coarse + fine scan ===")
        best_pos, converged_sh = coarse_fine_scan(
            lens_dev, watcher, log_rows, args.coarse_step, args.fine_step,
            settle_kwargs, log_print)
        log_print(f"Converged: pos={best_pos} sharpness={converged_sh:.1f}")

        log_print(f"=== Monitoring {args.monitor_seconds}s "
                   f"(jolt at +{args.jolt_at}s, threshold {args.degrade_threshold:.0%}) ===")
        # Each check uses a short settled reading (a few consecutive stable
        # frames), not one raw frame - single frames can be transiently
        # wrong right after any focus change, per the settle-time findings
        # above, and that includes changes this loop didn't itself initiate
        # (e.g. something bumping the lens). Two consecutive degraded
        # readings are required before re-scanning, as basic hysteresis
        # against single-reading noise - the "don't visibly hunt on a
        # static scene" requirement from the design decisions.
        monitor_settle_kwargs = dict(tolerance=args.settle_tolerance,
                                      min_stable=3, timeout=1.2)
        t0 = time.monotonic()
        jolted = False
        rescans = 0
        consecutive_degraded = 0
        while time.monotonic() - t0 < args.monitor_seconds:
            elapsed = time.monotonic() - t0
            if not jolted and elapsed >= args.jolt_at:
                bad_pos = FOCUS_MIN if best_pos > (FOCUS_MAX - FOCUS_MIN) / 2 else FOCUS_MAX
                log_print(f"  [self-test] jolting focus to {bad_pos} "
                           f"to simulate something knocking it off")
                set_focus(lens_dev, bad_pos)
                jolted = True
                watcher.drain_stale()
                continue

            sh, settled, n = settle_and_read(watcher, log_rows, **monitor_settle_kwargs)
            drop = 1 - (sh / converged_sh) if converged_sh else 0
            log_print(f"  monitor sharpness={sh:8.1f} settled={settled} "
                       f"(vs converged {converged_sh:.1f}, {drop:+.1%})")
            if drop > args.degrade_threshold:
                consecutive_degraded += 1
            else:
                consecutive_degraded = 0
            if consecutive_degraded >= 2:
                rescans += 1
                consecutive_degraded = 0
                log_print(f"  degradation confirmed on 2 consecutive checks - "
                           f"re-scanning (rescan #{rescans})")
                best_pos, converged_sh = coarse_fine_scan(
                    lens_dev, watcher, log_rows, args.coarse_step, args.fine_step,
                    settle_kwargs, log_print)
                log_print(f"  re-converged: pos={best_pos} sharpness={converged_sh:.1f}")
            time.sleep(args.monitor_interval)

        log_print(f"Done. {rescans} re-scan(s) triggered during monitoring "
                   f"({'as expected from the jolt' if rescans >= 1 else 'NONE - check jolt/threshold tuning'}).")

    finally:
        if cam_proc is not None:
            cam_proc.send_signal(2)  # SIGINT, let it flush
            try:
                cam_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                cam_proc.kill()
        if camlog is not None:
            camlog.close()

        if yaml_backup is not None:
            yaml_path.write_text(yaml_backup.read_text())
            yaml_backup.unlink()
            log_print(f"Restored {yaml_path} (Agc re-enabled).")

        subprocess.run(["systemctl", "--user", "start", "pipewire.socket",
                         "pipewire", "wireplumber"], capture_output=True)

        with trace_csv.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["seq", "wall_time", "sharpness"])
            w.writerows(log_rows)
        log_print(f"Trace written to {trace_csv}")


if __name__ == "__main__":
    main()
