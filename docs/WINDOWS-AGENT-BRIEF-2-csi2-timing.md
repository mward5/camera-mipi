# Windows-agent brief: capture the real, working rear-camera CSI2/D-PHY parameters

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To
Go install on a Dell XPS 13 9315 2-in-1. This is a **disposable, throwaway
environment** — the user can run you with admin rights, and it's fine to install
diagnostic tools, add Defender/SmartScreen exclusions for legitimate hardware tools,
etc. without the usual caution you'd apply on a daily-driver machine. That said, **scope
is strictly reconnaissance**: read data, scan hardware, report findings. Don't write
Windows drivers, don't change system configuration beyond what's needed to run a
diagnostic tool, don't install anything with lasting effects beyond this session.

For full project history, read `dell-xps9315-ipu6-rear-camera-context.md` and
`dell-xps9315-context-ADDENDUM-2026-07-13.md` in this same folder, and
`WINDOWS-AGENT-BRIEF.md` (the earlier VCM-identification brief — same machine, same
methodology, that one succeeded). This brief is the condensed, action-oriented version.

## The one open question

The rear camera (Samsung `S5K3J1`, ACPI `INT346D`) works correctly in Windows — real
autofocus, real pictures. On Linux, as of 2026-07-16, it's gotten very close: the sensor
powers up correctly (a real regulator-wiring bug was found and fixed), the mode-config
register sequence writes cleanly, streaming starts, and the CSI2 receiver on the host
side now achieves **frame-level sync** (`sof_event` fires repeatedly, once per frame).
But within each frame, the link is throwing constant physical-layer errors — packet
header errors, CRC errors, frame/line sync errors, `DPHY recoverable/fatal
synchronization error`, `SOT sync error`, `FIFO overflow` — severe enough that no valid
pixel data survives (the resulting frame buffer is all zero). **We need to know the
actual, real MIPI D-PHY / CSI2 receiver configuration Windows uses while genuinely
streaming this sensor at its main resolution**, so we can diff it against what Linux is
computing and find the mismatch.

## What's already known (don't re-derive this)

- Sensor's own `V4L2_CID_LINK_FREQ` reports **512 MHz**, meaning an assumed HS data rate
  of **1024 Mbps/lane, 4 lanes** (`3976x2736 needs 1024Mbps/lane, 4 lanes`, per the
  sensor driver's own comment — this is Intel's own vendor-supplied config table,
  imported wholesale from Intel's `ipu6-drivers` package, not something reverse-engineered
  locally, so it's a credible starting assumption, not a guess).
- MCLK is confirmed **exactly** 19.2MHz (the Linux driver hard-fails probe if it isn't,
  and probe succeeds) — not a suspect.
- The Linux CSI2 receiver's own D-PHY timing computation (`ipu6-isys-csi2.c`,
  `ipu6_isys_csi2_calc_timing()`) is a generic formula based purely on `link_freq`:
  computed values this session were `ctermen=0 csettle=698 dtermen=0 dsettle=665`
  (0.125ns units, so ~0/~87ns/~0/~83ns). `ctermen`/`dtermen` being 0 is expected
  (datasheet-minimum coefficients), and `csettle`/`dsettle` are in a plausible range for
  a ~1Gbps-class link — nothing obviously wrong, but "plausible" isn't "confirmed
  correct."
- **We could not find the sensor's actual streaming/mode-config register table, or any
  PLL/CSI2-rate metadata, anywhere in the collected Windows artifacts.** Checked and
  ruled out: (1) the sensor's Windows driver binary `s5k3j1sx04.sys` — no raw byte match,
  no address-only array, no code cross-reference to any of the known register addresses;
  it appears Windows sensor-mode/PLL setup is handled by a different, shared Intel
  ISP/camera-HAL component we haven't collected, not this per-sensor microdriver. (2) The
  `graph_settings_s5k3j1sx04_*.xml` files — `pixel_rate`/`pixel_rate_csi` are both
  statically `"0"`, meaning the real rate is negotiated at runtime, not declared
  statically anywhere we can read offline.
- Given the above, **static analysis of already-collected files is exhausted** for this
  question — it needs a live capture from an actual running Windows camera session.

## Task list, in priority order

1. **Open the Windows Camera app, switch to the rear/world-facing camera, and leave the
   preview running** (same precondition as the VCM session — don't probe a cold/idle
   pipeline). Confirm it's actually streaming (a live, moving preview, not a frozen
   frame).

2. **Try `RWEverything`'s MMIO/PCI BAR reader first** (already used successfully last
   session for I2C; same Defender-exclusion handling applies). The goal: read the Intel
   IPU6 PCI device's own CSI2 receiver register block — specifically whatever hardware
   registers back the D-PHY receiver timing fields (`termen`/`settle` for both clock and
   data lanes; on Linux these are named `CSI_PORT_REG_RX_CSI_DLY_CNT_TERMEN_CLANE`-style
   registers in `ipu6-isys-csi2.c` if you want the exact naming pattern to search
   Windows-side documentation or the IPU6 datasheet family for) while the camera is
   actively streaming. This gets a **hard ground-truth register dump** — the literal
   values the receiver hardware is configured with on a genuinely working system — without
   needing to reverse-engineer any Windows driver code at all. This is the highest-value,
   most direct thing to collect. Record every register you can read in that block, raw,
   even if you can't identify all of them by name.

3. **Also worth checking via RWEverything or a PCI config-space tool**: the number of
   active CSI2 lanes and the actual negotiated HS clock/data rate, if the IPU6's own
   status registers expose this anywhere (rather than just the receiver-timing config
   registers from step 2). A live "lanes active" or "current data rate" status register,
   if one exists, would directly confirm or refute the 4-lanes/1024Mbps assumption above.

4. **Fallback if MMIO register access doesn't pan out: WinDbg kernel debugging** attached
   to the actual ISP/CSI2-receiver driver (not `s5k3j1sx04.sys` — that one only handles
   sensor I2C, not the CSI2 receiver; you'll need to identify which Windows driver owns
   the IPU6 PCI device itself, likely something MIPI/ISP-named under
   `C:\Windows\System32\drivers\`, check `Get-PnpDevice` for the PCI IPU6 device's actual
   bound driver). Same setup overhead as before (`bcdedit /debug on`, test-signing) —
   treat as a last resort, and revert (`bcdedit /debug off`) when done.

5. **Optional but potentially very informative and much lower-effort: ETW tracing.**
   Windows' camera/Frame Server stack has built-in ETW providers (`Microsoft-Windows-Sensors-*`
   and the MIPI camera-related providers under `Microsoft-Windows-Kernel-*` or
   Intel-specific providers if the driver registers one). A generic capture — `wpr -start
   GeneralProfile` or a targeted `logman`/`tracelog` session around the moment the camera
   preview starts — might surface negotiated stream parameters (resolution, frame rate,
   pixel format, and possibly CSI2/MIPI parameters) in human-readable trace events without
   needing kernel debugging at all. Worth a quick attempt before falling back to WinDbg.

## Existing tooling you can reuse

`Users/Edward/dell-xps9315-win-collect/` (scripts A-F) already handles PnP enumeration
and driver-version collection — useful for step 4 (identifying which driver binary
actually owns the IPU6 PCI device). Don't duplicate what it already does; re-run
`RUN-ALL.ps1` if useful.

## Reporting back

**Write your findings to a new file in this same folder**, named
`windows-agent-findings-csi2-timing-<today's-date>.md`. This folder lives on an ordinary
NTFS partition mounted directly from the Linux side of this project — anything you write
here is automatically visible next time. Include: what you tried, what worked or didn't,
every raw register value you read (even ones you can't identify), and your best
reasoning about what the real D-PHY receiver timing / lane count / data rate actually is
on a working system. If you get genuine register-level ground truth, that's the single
most useful thing you could bring back — it turns "the Linux computation looks
plausible" into either "confirmed matching" or "here's the exact mismatch to fix."
