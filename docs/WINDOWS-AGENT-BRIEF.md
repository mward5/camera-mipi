# Windows-agent brief: identify the rear-camera VCM chip

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To Go install on a Dell XPS 13 9315 2-in-1. This is a **disposable, throwaway environment** — the user can run you with admin rights, and it's fine to install diagnostic tools, add Defender/SmartScreen exclusions for legitimate hardware tools, etc. without the usual caution you'd apply on a daily-driver machine. That said, **scope is strictly reconnaissance**: read data, scan hardware, report findings. Don't write Windows drivers, don't change system configuration beyond what's needed to run a diagnostic tool, don't install anything with lasting effects beyond this session.

For full project history, read `dell-xps9315-ipu6-rear-camera-context.md` and `dell-xps9315-context-ADDENDUM-2026-07-13.md` in this same folder. This brief is the condensed, action-oriented version — you shouldn't need the full history to get started, but it's there if you want deeper background on any point.

## The one open question

The rear camera (Samsung S5K3J1, ACPI device `INT346D`) visibly autofocuses in the Windows Camera app — the user has watched the lens rack/hunt. That means a physical VCM (voice coil motor / lens actuator) chip exists and is being driven. **We don't know which chip it is.** Identifying it is the goal of this session.

## What's already known (don't re-derive this)

- The camera's ACPI firmware declares a VCM type via a byte field (`vcmtype`, called `SSDB.vcmtype` in Intel's own driver source) that both Windows and Linux drivers are meant to read to know which VCM chip driver to load. On this machine, that byte's value is **19 (0x13)**.
- Every VCM name table anyone (Intel's own Linux kernel code, and the actual currently-installed, latest-available Dell driver `s5k3j1sx04.sys`) is willing to name only goes up to index 14. Value 19 is unrecognized everywhere we've checked. The table, for reference (index → chip name): `1=AD5823, 2=DW9714, 3=AD5816, 4=DW9719, 5=DW9718, 6=DW9806B, 7=WV517S, 8=LC898122XA, 9=LC898212AXB, 10=AK7371, 11=BU64297GWZ, 12=DW9800, 13=DW9808, 14=LC898217`.
- A Linux-side I2C bus scan (once the sensor was actually powered correctly) found exactly one other device on the bus, at address `0x50`, whose register 0 reads `0x0a` — probably a calibration EEPROM, not the VCM (doesn't match `DW9719`'s known ID byte `0xF1`). No VCM-looking address (typically `0x0C`/`0x18`/`0x0E`-ish) responded — plausibly because its power rail just isn't being turned on by the incomplete Linux driver stack, not because it doesn't exist.
- Windows definitely powers this correctly (autofocus works), so a bus scan done *while Windows has the camera actively open* is the best chance of seeing the real VCM respond.

## Task list, in priority order

1. **Try the `Windows.Devices.I2c` WinRT API first.** This is a public Windows 10+ API (originally for IoT Core, but present on desktop Windows too) that can talk to on-board I2C controllers directly from a short PowerShell or C# script, with no special driver and no admin-elevation drama. This hasn't been tried yet for this hardware — it's genuinely untested whether the Intel Serial IO I2C controller on this machine exposes itself in a way this API can reach, but it's worth trying first since it sidesteps the SmartScreen/Defender issue entirely if it works. Look up `Windows.Devices.I2c.I2cDevice` / `I2cController` usage examples; you'll need to enumerate available I2C controllers (`I2cController.GetControllersAsync`) and find the one matching the rear camera's bus (cross-reference against the PnP parent-chain data in the existing collection scripts — see below).

2. **Fallback: RWEverything's I2C/SMBus scanner.** The user tried this before and Windows blocked it outright (RWEverything bundles an unsigned/community low-level driver that trips SmartScreen/Defender reputation heuristics — this is normal for that tool, not a sign of anything wrong with it). Given the throwaway environment, it's reasonable to add a Defender exclusion or otherwise let it through this time. Use its I2C/SMBus tab to scan the bus for any address beyond the known sensor (`0x10`) and the suspected EEPROM (`0x50`).

3. **Before scanning (either method): open the Windows Camera app, switch to the rear/world-facing camera, and leave the preview running.** This ensures the VCM's power rail is genuinely active — don't scan a cold/idle bus.

4. **Scan the full plausible address range** (roughly `0x03`–`0x77`), not just where known devices already are. For any new address found, read a handful of registers and record the raw bytes even if they don't obviously match a known chip signature — raw data is still useful for later analysis, even without an immediate ID match.

5. **Optional/advanced, only if the above doesn't pan out:** local kernel debugging (`bcdedit /debug on` + WinDbg) attached to the running `s5k3j1sx04.sys` to directly inspect the resolved `Vcm[vcmtype].Type` value in memory (the driver's own error strings, e.g. `"CheckVcmTable Order Error... vcmtype=%d, Vcm[vcmtype].Type=%d"`, show this is a real in-memory structure you could read). This has real setup overhead (enabling test-signing/kernel debug mode) — treat it as a last resort, and note it changes the boot configuration (should be reverted after, `bcdedit /debug off`).

## Existing tooling you can reuse

`Users/Edward/dell-xps9315-win-collect/` is a mature PowerShell toolkit (scripts A–F, see its `README.md`) that already handles PnP device enumeration, registry export, and driver-version collection well. It does **not** do raw I2C register access — that's the gap this session exists to fill. Feel free to re-run `RUN-ALL.ps1` if any of its collected data would help (e.g. re-confirming the PCI Serial IO I2C controller instance ID to cross-reference against whatever the WinRT API enumerates), but don't duplicate what it already does.

## Secondary task (only after the VCM question above): OG0VA1B IR camera (Windows Hello)

This is lower priority and purely forward-looking — gathering groundwork in case Linux support for the IR/Windows Hello camera is attempted later. Don't spend time on this until the VCM task above is done or stuck.

**What's already known / already collected** (no need to re-fetch): the IR sensor is `ACPI\OVTI00AB` (confirmed from `og0va1b.inf`'s match string). We already have `og0va1b.inf`/`.sys` and a large set of `graph_settings_og0va1b_*_ADL.xml` variants archived locally on the Linux side. There's a mainline Linux driver for a closely related OmniVision part, `drivers/media/i2c/og01a1b.c`, but it matches ACPI HID `OVTI01AC`, not `OVTI00AB` — same vendor family, useful as a reference/template, but not a direct match, so real driver work would still be needed. IR/Windows-Hello sensors are typically much simpler than the rear camera (no VCM, no PDAF, single stream) — more like the already-working front `hi556` in shape.

**What's actually worth collecting from Windows** (the same technique used for the rear camera, applied to `OVTI00AB` instead):
1. A live PnP walk (`Get-PnpDevice` + `DEVPKEY_Device_Parent`, same pattern as the existing collection scripts use for `INT346D`) to confirm which I2C controller/bus this sensor sits on.
2. If feasible with whatever I2C access method worked for the VCM task above: read the sensor's own ACPI `SSDB` buffer (same struct shape, same method name pattern under its `LNK`-style ACPI device) — link frequency, lane count, MCLK speed — the same fields already decoded for `INT346D`, just for this device instead.
3. Confirm there's no VCM/PDAF involved (expected, but worth a quick check of the graph XML for a `<paf>` element the way `INT346D`'s had one) — if genuinely absent, that's good news for how simple a future port would be.

## Reporting back

**Write your findings to a new file in this same folder**, named `windows-agent-findings-<today's-date>.md`. This folder lives on an ordinary NTFS partition that gets mounted directly from the Linux side of this project — anything you write here is automatically visible next time, no manual copy/paste or USB transfer needed. Include: what you tried, what worked or didn't, any raw register bytes you read from any address, and your best guess (with reasoning) at the VCM chip identity if you reach one.
