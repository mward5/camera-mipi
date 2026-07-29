# Dell XPS 13 9315 2-in-1 — camera support on Linux

Reverse-engineering and building working Linux driver support for the cameras on the
**Dell XPS 13 9315 2-in-1** (Alder Lake, Intel IPU6ep), specifically:

- **Rear camera**: Samsung `S5K3J1`, ACPI `INT346D` — the main focus of this project, and
  the furthest along. Streams real image data, has a working autofocus lens (VCM) with a
  from-scratch Linux driver, and runs real continuous contrast-detection autofocus in
  libcamera's software ISP. Phase-detect autofocus (PDAF) hardware is present but not
  usable on this kernel — see "Not fixed / known dead ends" below. See
  [`STATUS.md`](STATUS.md) for full current state.
- **Front camera**: OmniVision `HI556`, ACPI `INT3537` — works via mainline `hi556.c`, no
  kernel changes needed. Its `libcamera` image-quality tuning (autoexposure, colour) has
  had substantial work in this project even though the kernel driver is untouched — see
  "Userspace work" below.
- **IR/Windows Hello camera**: `OG0VA1B`, ACPI `OVTI00AB` — not yet attempted; groundwork
  only (see `docs/windows-agent-findings-2026-07-13.md`). Simpler target than the rear
  camera (no PDAF/VCM).

## Goals

1. Get the rear S5K3J1 camera producing a working video stream, ideally with autofocus.
   **Done** — see [`STATUS.md`](STATUS.md) for the current image-quality/polish work.
2. Get this organized and documented well enough to be useful to other owners of this
   laptop model, not just as personal notes.

## Layout

- `drivers/` — three git submodules, each a real fork carrying this laptop's patches as
  normal, diffable commits against exact upstream history (not flat/disconnected copies —
  see "Building" below for how they fit together):
  - `linux-xps9315-2in1/` — a fork of Ubuntu's `resolute` kernel, branched from the exact
    tag this project tests against (`Ubuntu-7.0.0-28.28`). Real in-tree commits, each DMI+HID
    quirk-gated to this laptop:
    - `drivers/media/pci/intel/ipu-bridge.c` — an ACPI i2c-instantiation fix for the rear
      camera's ACPI link, the VCM `_CRS` resource-index fix (this board has 3 I2C resources
      per sensor, not the common 2, so the VCM lands at a different index), and a link-
      frequency fix (512MHz, not 848MHz) against real upstream's own S5K3J1 SAUCE patch,
      which independently added S5K3J1 support with the same wrong frequency value.
    - `drivers/platform/x86/intel/int3472/tps68470_board_data.c` — TPS68470 PMIC board data
      for this laptop's DMI model, fixing two real board-wiring bugs inherited from a
      copy-pasted "Trial C" starting point (`avdd`→`ANA`, `dvdd`/`dovdd`→`CORE`/`VSIO`,
      matching this board's actual Surface-Go-derived rail layout), and wiring the VCM's
      regulator to a real consumer instead of an `always_on` diagnostic hack.
    - `drivers/media/pci/intel/ipu6/ipu6-isys-csi2.c` — **root cause of the rear camera's
      total capture failure.** Mainline never sets bit 1 of `PPI2CSI_CONFIG_PPI_INTF`
      (reg `0x204`); Windows sets it on every CSI2 port. With it clear the rear sensor's
      4-lane/1024Mbps stream never syncs (black screen); with it set, sustained real video.
      See `STATUS.md`'s "BREAKTHROUGH" entry for the full diagnosis.
  - `ipu6-drivers/` — a fork of Intel's own
    [`intel/ipu6-drivers`](https://github.com/intel/ipu6-drivers), rebased onto the exact
    upstream commit this project's `s5k3j1.c` work is based on, carrying: a real link-
    frequency bug fix (512MHz, not 848MHz — a genuine D-PHY timing mismatch), PMIC
    power-sequencing/GPIO-order fixes, a crop fix, and PDAF stream plumbing (kernel side
    works; the libcamera side is a dead end on this kernel's routing restrictions, see
    `STATUS.md`).
  - `lc898217/` — **new driver**, not previously packaged anywhere: the rear camera's VCM
    (lens actuator) chip, identified via Ghidra analysis of the Windows driver (see
    `docs/vcm-investigation-lc898217.md`) and adapted from Vasiliy Doylov's real upstream
    `lc898217xc.c` submission, with his copyright preserved. Adds the chip-specific `Init`
    calibration handshake this variant needs, and fixes a real cross-platform bug in the
    upstream driver it's based on (missing `i2c_device_id` table — silently never binds on
    any `CONFIG_OF=n` x86 kernel, this one included).
- `scripts/` — install/reload/diagnostic helper scripts for testing the above, plus
  analysis tools (autofocus sweep/hill-climb, AGC exposure measurement from captured
  frames).
- `docs/` — investigation write-ups, session findings, and scoping docs for larger pieces
  of work (autofocus architecture, `.aiqb` calibration-data extraction) written before
  starting them.
- `reference/` — supporting evidence: ACPI table dumps, Windows driver artifacts, live
  register captures, and the Ghidra reverse-engineering scripts/output used to identify
  the rear camera's VCM chip.

## Building

```
git clone --recurse-submodules <this repo's URL>
cd camera-mipi
bash scripts/install-custom-modules.sh
```

Prerequisites: `linux-headers-$(uname -r)` installed (the script checks and tells you if
it's missing). Reboot afterward — this ensures a genuinely clean ACPI/fwnode state rather
than relying on `insmod`/`rmmod` cycling, which silently no-ops some of these fixes (see
the script's own comments for why). To revert, see the script's own printed instructions
at the end of a successful run.

All quirks in `drivers/linux-xps9315-2in1/` and `drivers/ipu6-drivers/` are gated on an
exact DMI model match (and, where relevant, ACPI HID) — safe to build and run this on
unrelated hardware; the quirks simply won't activate.

This covers the kernel side only. Real continuous autofocus and the autoexposure/colour
fixes described above live in `libcamera`'s software ISP, published separately at
`mward5/libcamera` (branch `xps-9315-2-in-1-cameras`) — both halves are needed for a fully
working rear camera with real AF/AGC. See that repo's own build/install instructions.

## Not fixed / known dead ends

Recorded so they aren't re-attempted without new evidence — see `STATUS.md` for the full
detail behind each:

- **PDAF** — the kernel's `v4l2_subdev_routing_validate()` forbids the 1-sink-to-2-source
  routing the sideband capture needs (`V4L2_SUBDEV_ROUTING_ONLY_1_TO_1`), a hard kernel
  restriction, not a missing setup step. Continuous autofocus instead uses pure
  contrast-detection (CDAF) in the software ISP.
- **Rear camera's privacy/indicator LED** — never lights, because the rear camera hangs
  off the TPS68470 PMIC path, which has no privacy-LED concept anywhere in mainline (the
  front camera's discrete INT3472 path does, hence its LED works).
- **Dual-monitor flakiness** — was suspected to be caused by this project's driver stack;
  root-caused to an unrelated mutter/Thunderbolt-hotplug bug, filed upstream as
  [mutter#4928](https://gitlab.gnome.org/GNOME/mutter/-/work_items/4928).

## Start here

Read [`STATUS.md`](STATUS.md) for current state and what's left to do.
