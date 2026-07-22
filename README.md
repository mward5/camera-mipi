# Dell XPS 13 9315 2-in-1 — camera support on Linux

Reverse-engineering and building working Linux driver support for the cameras on the
**Dell XPS 13 9315 2-in-1** (Alder Lake, Intel IPU6ep), specifically:

- **Rear camera**: Samsung `S5K3J1`, ACPI `INT346D` — the main focus of this project.
  Has phase-detect autofocus (PDAF) hardware and a VCM lens actuator, neither implemented
  upstream. See [`STATUS.md`](STATUS.md) for current state.
- **Front camera**: OmniVision `HI556`, ACPI `INT3537` — already works via mainline
  `hi556.c` + `libcamera`.
- **IR/Windows Hello camera**: `OG0VA1B`, ACPI `OVTI00AB` — not yet attempted; groundwork
  only (see `docs/windows-agent-findings-2026-07-13.md`). Simpler target than the rear
  camera (no PDAF/VCM).

## Goals

1. Get the rear S5K3J1 camera producing a working video stream, ideally with autofocus.
2. Get this organized and documented well enough to be useful to other owners of this
   laptop model, not just as personal notes.

## Layout

- `drivers/` — the three out-of-tree kernel modules under active development, each its
  own git repo (history not yet cleaned into a proper patch series — see `STATUS.md`).
  - `ipu-bridge/` — patched `drivers/media/pci/intel/ipu-bridge.c`, adds an ACPI
    i2c-instantiation quirk for this laptop (empty `_CRS` on the rear camera's ACPI link).
  - `int3472-tps68470/` — patched TPS68470 PMIC board data for this laptop's DMI model.
  - `s5k3j1/` — Intel's out-of-tree `ipu6-drivers` package, with local fixes/additions to
    `drivers/media/i2c/s5k3j1.c` (power sequencing, crop, PDAF stream plumbing).
- `scripts/` — install/reload/diagnostic helper scripts for testing the above.
- `docs/` — investigation write-ups and session findings.
- `reference/` — supporting evidence: ACPI table dumps, Windows driver artifacts, and the
  Ghidra reverse-engineering scripts/output used to identify the rear camera's VCM chip.

## Start here

Read [`STATUS.md`](STATUS.md) for current state and what's left to do.
