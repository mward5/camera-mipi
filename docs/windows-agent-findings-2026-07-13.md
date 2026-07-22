# Windows-agent findings — 2026-07-13

Session goal: identify the rear-camera (Samsung S5K3J1, `ACPI\INT346D`) VCM chip behind `SSDB.vcmtype = 19 (0x13)`, an index unrecognized in every known VCM name table (max index 14).

**Bottom line: best current answer is `DW9808`, with real (though not 100%-certain) supporting evidence — see §5.** Everything in §1–4 below was the long, mostly-unsuccessful path to get there (WinRT API dead end, RWEverything blocked, deep-but-inconclusive live kernel debugging); §5 is what actually answered the question, via a much simpler technique than everything before it.

## 1. WinRT `Windows.Devices.I2c` API — tried, dead end

The API itself is reachable from a plain (non-packaged) desktop PowerShell process with no manifest/capability issues — `I2cController.GetDefaultAsync()` and `I2cDevice.GetDeviceSelector()` + `DeviceInformation.FindAllAsync()` all worked without error. This answers the brief's "genuinely untested" question: yes, it's callable, but:

```
Selector: System.Devices.InterfaceClassGuid:="{A11EE3C6-8421-4202-A3E7-B91FF90188E4}" AND System.Devices.InterfaceEnabled:=...True
Bus count: 1
Id:   \\?\ACPI#MSFT8000#1#{a11ee3c6-8421-4202-a3e7-b91ff90188e4}\I2C4
Name: DESKTOP-QUC97RT
```

Only **one** bus is exposed, and it's `ACPI\MSFT8000` — Microsoft's virtual/test I2C-SPI-GPIO provider (from the old Windows IoT Extension SDK), not real silicon. The real Intel Serial IO I2C controllers on this machine (see below) are claimed exclusively by the SpbCx-based camera driver stack and are never registered with the WinRT Resource Hub on standard desktop Windows — this API path is effectively only useful on Windows IoT Core boards, not here. **Conclusion: this API cannot reach the camera's I2C bus on this hardware.**

## 2. PnP topology (for reference / next session)

Rear camera device: `ACPI\INT346D\0`.

Its `DEVPKEY_Device_Parent` chain does **not** pass through an I2C controller — it goes straight to `ACPI\PNP0A08\0` (PCI Express Root Complex) → ACPI HAL → root. This matches the already-known Linux-side finding that `LNK0`'s `_CRS` is empty/gated (`L0DI == 0`) — there's no standard ACPI-published I2C resource link for the rear camera, so the PnP-tree walk trick doesn't work for this specific device (it may still work for other, non-gated devices).

Discovered controllers relevant to any future attempt:

| Device | Instance ID | Notes |
|---|---|---|
| Intel Serial IO I2C Host Controller - 51C5 | `PCI\VEN_8086&DEV_51C5&SUBSYS_0B341028&REV_01\3&11583659&0&C8` | Candidate bus |
| Intel Serial IO I2C Host Controller - 51E8 | `PCI\VEN_8086&DEV_51E8&SUBSYS_0B341028&REV_01\3&11583659&0&A8` | Candidate bus (front `hi556`/`INT3537` known-good uses `0000:00:15.0` = `51e8` on Linux side per prior notes) |
| Intel Serial IO I2C Host Controller - 51E9 | `PCI\VEN_8086&DEV_51E9&SUBSYS_0B341028&REV_01\3&11583659&0&A9` | Candidate bus |
| Intel Serial IO I2C Host Controller - 51EA | `PCI\VEN_8086&DEV_51EA&SUBSYS_0B341028&REV_01\3&11583659&0&AA` | Candidate bus |
| Intel(R) Control Logic (×2) | `ACPI\INT3472\1`, `ACPI\INT3472\A` | PMIC/GPIO control logic, one per camera (front/rear), matches Linux `int3472`/`tps68470` work already in progress |
| **Intel(R) SMBus - 51A3** | `PCI\VEN_8086&DEV_51A3&SUBSYS_0B341028&REV_01\3&11583659&0&FC` | **Legacy PCH SMBus controller — architecturally separate from the Serial IO controllers above.** Important for item 3. |

## 3. RWEverything — blocked, not by SmartScreen but by the kernel Vulnerable Driver Blocklist

The brief anticipated a SmartScreen/Defender *reputation* block (fixable with a Defender exclusion). What actually happened was different and more consequential:

- Added a scoped Defender exclusion for `C:\Users\Public\Downloads\RwPortableX64V1.7` (no prior detections existed). This did **not** fix the load failure.
- Launching `Rw.exe` produced: *"A driver cannot load on this device — Driver: RwDrv.sys — A security setting is detecting this as a vulnerable driver and blocking it from loading."*
- This is Microsoft's **Vulnerable Driver Blocklist**, enforced via Memory Integrity (HVCI) and Smart App Control — a kernel code-integrity policy, independent of Defender's AV exclusion list. `RwDrv.sys` (WinRing0-family) grants raw kernel/MSR/port access to any usermode caller and is a known real-world BYOVD (Bring Your Own Vulnerable Driver) tool used in ransomware attacks to disable EDR/AV, hence the blocklist entry.
- Checked status: HVCI was running (`SecurityServicesRunning: {2}`, registry `Enabled=1`); Smart App Control was in **Evaluation** mode (`VerifiedAndReputablePolicyState=1` — reversible without a reinstall, unlike Enforce mode).
- Disabled both via registry (`Enabled=0`, `VerifiedAndReputablePolicyState=0`) — **this requires a reboot to take effect.**
- User reported this specific Windows To Go install does not reboot cleanly: it hangs on restart, requiring a long power-button hold, and a prior hard power-cycle triggered an extended filesystem repair. Given USB/external-boot media is known to be more corruption-prone under unclean power loss, and given RWEverything's classic I2C/SMBus tab is architecturally built around the **legacy PCH SMBus controller (`51A3`)**, not the modern Serial IO/LPSS controllers (`51E8` etc.) where the camera actually lives — meaning even a successful driver load had uncertain odds of reaching the right bus — **the reboot was not attempted.**
- Reverted both registry values back to their original state (`1`/`1`) and removed the Defender exclusion. Since no reboot occurred, neither change ever took effect — **the machine is unchanged from its state at the start of this session.**

## 4. Local kernel debugging (WinDbg) — got it working, reached deep into the driver, VCM table still not found

Follow-up session (same day) revisited the brief's last-resort option. **This one worked, in the sense that local kernel debugging is now fully functional on this machine and a real, deep static analysis of `s5k3j1sx04.sys` was carried out — but the VCM table itself was not located.**

### Getting local KD working (three reboots)

- Installed WinDbg via `winget install --id Microsoft.WinDbg` (the modern DbgX-based package; bundles console tools `kd.exe`/`cdb.exe`/`ntsd.exe` under `<pkg>\amd64\`, separate from the GUI `DbgX.Shell.exe`).
- `bcdedit /debug on` + reboot (1st reboot): local KD (`kd -kl`) failed — *"Windows cannot verify the digital signature for this file"* for `kldbgdrv.sys` (Microsoft's own local-KD proxy driver), confirmed via Event ID 7000. Root cause: **HVCI (Memory Integrity)**, running at the time, blocking even a first-party MS driver.
- Disabled HVCI + Smart App Control again, reboot (2nd reboot): `kldbgdrv.sys` **still** failed the same signature check, even with HVCI off (`SecurityServicesRunning: {0}` confirmed). This ruled out HVCI as the actual cause — something else was rejecting the signature. Best (unconfirmed) hypothesis: this machine's unreliable hardware RTC (`w32tm` showed clock source "Local CMOS Clock, not synchronized"; `Microsoft-Windows-HAL` logged ACPI Time/Alarm Device failures) may cause a bad clock value during the very early boot phase when code-integrity signature timestamps are validated.
- Added `bcdedit /set testsigning on` (relaxes signature validation differently than HVCI), reboot (3rd reboot): **`kd -kl` connected successfully.** Local kernel debugging is confirmed working on this machine going forward, with `testsigning on` + `debug on` + HVCI/Smart App Control disabled.
- All three reboots were rough (hang requiring hard power-cycle each time) but the filesystem came back clean (`fsutil dirty query C:` → not dirty) every time — no corruption resulted despite the repeated hard resets.
- **Left enabled by design, not a pending cleanup item**: `testsigning on`, `debug on`, HVCI disabled, Smart App Control disabled. User confirmed this is the intended standing configuration for this disposable Windows To Go environment going forward — no need to revert at the end of a session. Future sessions can assume local kernel debugging is already available without re-running the three-reboot setup in this section.

### What was found once attached

- `!drvobj s5k3j1sx04 2` resolved the driver object (`ffffd18a227e7de0`) and its dispatch table — all `IRP_MJ_*` entries point to a single shared dispatch routine.
- **`lm` (module list) is broken in this WinDbg build under batch/`-c` mode** — always returns just a header with no rows, for both full and address-filtered forms. Worked around this entirely by using `!drvobj`, `u` (disassemble), and raw `dq`/`db` memory reads instead, anchored off addresses obtained from the driver object.
- Confirmed via live disassembly that the driver's actual load base is **`0xfffff801'64570000`** (read directly out of a `lea rdx,[...]` instruction used as a jump-table anchor — a hard, verified fact, not a guess).
- Fully decoded the driver's `IRP_MJ_*` dispatch jump table (two-level: byte index table at `base+0xBAAD4`, dword relative-offset table at `base+0xBAAC0`). `IRP_MJ_DEVICE_CONTROL` (0x0E) → compact index 1 → `base+0x47dfc`; `IRP_MJ_INTERNAL_DEVICE_CONTROL` (0x0F) → compact index 4 → `base+0x47eae` (routes to generic pass-through, i.e. internal IOCTLs are just forwarded down the IPU6 stack, not handled here).
- Traced from there through several more layers, all cleanly resolvable via live memory reads (not just static disassembly guesswork) because `DRIVER_OBJECT`/`DEVICE_OBJECT` layouts are public/documented:
  - `DeviceObject = 0xffffd18a'22f74c80` (read from `DRIVER_OBJECT+0x08`).
  - `DeviceExtension = 0xffffd18a'244ad2f0` (read from `DEVICE_OBJECT+0x40`).
  - The dispatch routine's `rsi` register (used throughout as the base for further field access) is **not** `DeviceExtension` itself but `*(DeviceExtension - 0x30)` = `0xffffd18a'244ad000` — this was a real wrong turn mid-session (first attempt dereferenced the wrong base and hit a NULL pointer) before being corrected by re-disassembling the function's true prologue.
  - `*(rsi + 0x280)` → `0xffffd18a'244cb5a0`, an FxObject-style C++ object.
  - Its vtable → `0xfffff801'64623828`; vtable slot 8 (`+0x40`) → **`0xfffff801'645880b0`**, confirmed to be the real `DispatchDeviceControl` handler (resolved via CFG's `KscpCfgDispatchUserCallTargetEsSmep` indirect-call thunk in the disassembly).
- Disassembled `645880b0` and followed it through several more layers of clearly-legitimate, coherent KMDF internals: remove-lock acquisition, an `FxRequest` object cache/allocation path (checking a type-tag `0x1102` at a cached slot, offset `+0x288` from the core device object), and `IoQueue`-style request processing (`KeEnterCriticalRegion`, etc.).
- Searched a 9MB span of the module for the debug string quoted in earlier notes (`"CheckVcmTable..."`) and for `S5K3J1`/`VCM`/`vcmtype` — **zero hits**, even though the search mechanism itself was verified working (found a different, known-present string in the same pass). Best explanation: that validation code and its string are almost certainly compiled into the driver's **`INIT` section**, which Windows frees after `DriverEntry` completes — consistent with `DriverEntry`'s own address (from `!drvobj`) pointing ~47MB away from everything else, i.e. into now-stale/reused memory. The actual VCM lookup table (unlike the one-time validation code) is presumably still resident in `.rdata` since it's needed on every autofocus operation, but there's no remaining text anchor to find it by.
- Scanned further into the `DispatchDeviceControl` call graph for any `call` target outside the tight `0x6458xxxx`–`0x645Fxxxx` address cluster everything had been in so far — found one outlier (`0x6464ddf8`) and checked it; it was also generic WDF framework code (a pre-processor list-walk with a standard error path), not vendor code.

### Why this stopped short

Every structure resolved via **documented** Windows structures (`DRIVER_OBJECT`, `DEVICE_OBJECT`) was solid and verifiable. Everything past that point is **undocumented WDF/KMDF internal C++ class layout** (`FxPkgIo`, `FxRequest`, `FxIoQueue` equivalents) with no public definition to check offsets against — real progress was still being made (each hop resolved to genuinely valid, coherent code/data, not garbage), but the vendor's own `EvtIoDeviceControl` callback and the VCM table were not reached after ~6 layers of tracing, and repeated sampling kept landing on more framework plumbing rather than vendor code. This is consistent with KMDF's I/O processing pipeline being a deep, multi-object dispatch (queue → request wrapper → registered callback) — reaching the vendor callback this way is a tractable but substantial reverse-engineering project on its own, not a quick follow-up.

### Recommendation if resumed

A disassembler with type/symbol support (Ghidra or IDA, ideally with public WDF structure definitions loaded) would be dramatically more efficient than continuing via raw `kd.exe` batch commands — this session proved the *access* method works (local KD, no more reboot risk needed from here since HVCI/testsigning are already enabled), the remaining gap is purely about better RE tooling for the undocumented WDF layers, not about system access.

## 5. Static string analysis of the on-disk `.sys` file — this is what actually answered the question

After the live-KD reverse engineering in §4 stalled (undocumented WDF internals, no anchor), a much simpler idea worked instead: copy the **on-disk** driver file (not a live memory dump) and extract its printable strings offline. The on-disk PE file still contains the `INIT`-section content that gets freed from live memory after boot — which is exactly what defeated the in-memory string search in §4.

- Copied `C:\Windows\System32\drivers\s5k3j1sx04.sys` → `s5k3j1sx04.sys` in this same folder (208,968 bytes). No live kernel debugging, no reboot, no elevated anything required for this — it's a plain file read.
- Extracted printable ASCII strings via a short PowerShell regex pass (`strings` isn't available in this Git Bash environment, so used `[regex]::Matches($text, "[\x20-\x7E]{4,}")` over the raw bytes instead).
- Confirmed the exact error string (the addendum's earlier quote was a close paraphrase, not verbatim):
  ```
  [ERROR] %s CheckVcmTable Order Error, disable VCM to keep safe!!!!!!, vcmtype=%d, Vcm[vcmtype].Type=%d
  ```
- Also found the build provenance: `c:\Jenkins\workspace\adl_pipeline\Source\Camera\Platform\ADL\x64\Release\s5k3j1sx04.pdb` — confirms an Alder-Lake-specific CI build.
- **Key finding**: searching for VCM chip driver function names (`<CHIP>_SetPos`, `<CHIP>_Init`, etc.) found **exactly 14 chip implementations, no more**:
  ```
  AD5823, DW9714, AD5816, DW9719, DW9718, DW9806B, WV517S,
  LC898122XA, LC898212AXB, AK7371, BU64297GWZ, DW9800, DW9808, LC898217
  ```
  This is the exact same 14 chips, in the exact same order, as the known index-1-to-14 table from Intel's Linux driver. There is **no 15th/16th/…/19th chip implementation compiled into this binary** — whatever `vcmtype=19` resolves to, it can only ever be one of these 14 (or "NoneVCM", also found in the strings), because that's the full set of code the driver is physically capable of executing.
- **Minor corroborating detail**: of all 14 chips, only two have dedicated `Cmd_<CHIP>Write`/`Cmd_<CHIP>Read` debug-command strings for direct register peek/poke — **`DW9806B` and `DW9808`**. Weak signal, not proof, but consistent with these two being the ones the vendor's engineers were actually debugging/using most recently on this platform family (as opposed to the other 12, which are presumably carried over for other Dell models using the same driver base).

### Conclusion

This substantially strengthens the addendum's previously-unconfirmed **BCD hypothesis**: if the raw ACPI byte `0x13` is read as decimal digits "1" and "3" (i.e., BCD-encoded thirteen) rather than hex 19, it points directly at entry **#13 in this exact list: `DW9808`**. Given the driver has no 19th/20th entry to fall back on, and index 13 is a valid, populated, real slot in this specific binary's chip list, **`DW9808` is now a well-evidenced best answer rather than a guess** — though it is not a 100%-certain identification; it wasn't confirmed by directly reading `Vcm[19].Type` from a live table (the goal of §4, which didn't reach it). A future session could still pursue that direct confirmation (e.g., loading this same `.sys` file into Ghidra/IDA offline, finding `CheckVcmTable`'s xrefs with proper tooling, and reading the actual `Vcm[]` table contents/stride from the static file — much more tractable now that the INIT-section content is preserved in this copy).

### Additional artifacts collected for offline work

- `s5k3j1sx04.inf` and `s5k3j1sx04.cat` (18,681 and 7,978 bytes) copied alongside the `.sys` from the DriverStore (`FileRepository\s5k3j1sx04.inf_amd64_779a70ee887fc686\`).
- That same DriverStore folder also contains **three separate calibration profile sets** for the rear camera module: `1BAA01T3`, `1BAA02T3`, and `CJALR11` (each with PDAF `.aiqb`/`.cpf` tuning-blob variants) — suggesting this driver package supports multiple physical module revisions. Not copied (different topic — IPU6 tuning data, not VCM identification — but worth knowing they exist if the Linux camera-tuning work needs them later). `vcmtype` comes from ACPI `SSDB`, tied to the actual board/BIOS, not from these calibration files, so this doesn't change the `DW9808` conclusion — just useful context that this is a driver shared across several module revisions.
- **Key addresses recorded as RVAs (base-relative offsets), not raw live hex** — the live addresses only apply to this specific boot's ASLR layout; these offsets will line up directly once the copied `.sys` is loaded into Ghidra/IDA:

  | Item | RVA (offset from module base) |
  |---|---|
  | `DispatchDeviceControl` handler | `base + 0x180B0` |
  | `FxObject` vtable (the one resolved in §4) | `base + 0xB3828` |
  | `IRP_MJ_*` byte-index table | `base + 0xBAAD4` |
  | `IRP_MJ_*` dword relative-offset table | `base + 0xBAAC0` |

  (This session's live `base` was `0xfffff801'64570000` — only relevant for cross-checking against a live KD session on this exact boot; irrelevant once working from the static file offline.)

### Attempted: hardware breakpoint for direct confirmation — abandoned, no viable anchor

Considered setting a hardware data breakpoint (`ba r`) on the live memory holding a chip-specific trace string (e.g. `"DW9808_SetPos"`), reasoning that a read hit would mean that exact chip's code was executing — a much more surgical, lower-noise approach than breakpointing on a hot generic kernel function. This depended entirely on the trace string still being resident in live memory.

- Searched the same 9MB range (verified working via a known-present-string sanity check earlier in the session) for `DW9808_SetPos`, `DW9806B_SetPos`, then the shorter fragments `SetPos`, `DW9808`, `AD5823` individually — **zero hits for all of them**, uniformly across every chip name tried, not just the target hypothesis.
- This generalizes the earlier `CheckVcmTable`-string finding: it's not just that one error message that's discarded from live memory — **the entire block of per-chip VCM debug/trace strings is gone**, consistent with it being compiled into a discardable section (`INIT` or a similar paged debug-string pool) that's freed after driver load, uniformly, regardless of which chip is actually in use.
- **No live anchor exists for a data breakpoint.** Getting a code-execution breakpoint instead would require first finding `DW9808_SetPos`'s actual code address directly — which runs into the same "no cross-reference tooling without symbols" problem that stalled the WDF trace in §4, just from a different angle. Not pursued further; the risk (a code-address guess is far less certain than a string-anchored one) wasn't worth it given the answer is already well-evidenced from §5.
- No system risk was taken in this attempt — all reads were plain memory searches, no breakpoint was ever actually armed.

## 6. Architecture note: the VCM is not a separate driver on Windows (relevant to the Linux port)

Worth recording explicitly since it bears directly on what a Linux fix needs to look like: on this Windows driver, **the VCM is not a separate `.sys` file or a separate PnP device**. All 14 chip implementations (§5) are functions statically linked into `s5k3j1sx04.sys` itself, selected at runtime via the `Vcm[vcmtype]` table. Device Manager never shows an independent "AD5823" or "DW9808" device — only `ACPI\INT346D` (the sensor) and the two `ACPI\INT3472` control-logic devices (PMIC/GPIO).

This is architecturally different from the typical Linux approach, where VCM drivers are usually separate kernel modules (`dw9807-vcm.ko`, `ad5820.ko`, etc.) binding as their own `i2c_client` at a distinct I2C address, independent of the sensor driver. So even with the chip identity narrowed to `DW9808`, the Linux-side fix is likely to mean finding/using (or writing) a standalone `dw9808`-style VCM module, not modifying `s5k3j1` to embed VCM logic the way this Windows driver does.

## Recommendations for next attempt

1. **Best current answer (`DW9808`) is not yet 100%-confirmed** — it's a strong inference from the closed set of 14 compiled-in chips plus the BCD-decoding hypothesis for `vcmtype=19`→13, not a direct read of `Vcm[19].Type`. If more certainty is needed, load the copied `s5k3j1sx04.sys` (§5, now sitting in this folder) into Ghidra/IDA **offline** — no live kernel debugging needed, and the INIT-section content (including `CheckVcmTable`) is intact in this static copy, unlike in live memory. This is a much more tractable path than resuming the raw `kd.exe` tracing from §4.
2. **No boot-config revert needed** — `testsigning on` / `debug on` / HVCI disabled / Smart App Control disabled is the intended standing state for this WTG environment (confirmed by user), not a temporary debugging leftover. Future sessions should be able to use local KD immediately without repeating the three-reboot setup from §4, as long as this environment's boot config hasn't changed since.
3. If retrying RWEverything instead: first confirm (from its own docs/changelog, not memory) whether the specific version available actually supports the Serial IO/LPSS I2C controllers at all — the `51A3` vs `51E8`-family distinction found in §3 suggests its classic SMBus tab may be the wrong tool regardless of driver-load success. Given §5's answer, this path is now lower priority than before.
4. Confirmed module base for future sessions (only needed if resuming live KD): `s5k3j1sx04.sys` loads at **`0xfffff801'64570000`** (will vary per boot due to KASLR — re-derive via the same `!drvobj` → disassemble technique each session, don't hardcode).
5. On the Linux side: given §6, the fix is most likely a standalone `dw9808`-style VCM module bound to its own I2C address, not a change inside `s5k3j1`.

## Secondary task (OG0VA1B IR camera) — quick pass, matches expectations

Primary VCM task reached a good stopping point (§5), so did the brief's lightweight secondary-task checks:

- Device confirmed present: `ACPI\OVTI00AB\1`, friendly name "Camera Sensor OG0VA1B", status OK.
- `DEVPKEY_Device_Parent` walk: same pattern as the rear camera — goes straight to `ACPI\PNP0A08\0` → ACPI HAL → root, no I2C controller in the chain (expected, ACPI-enumerated camera sensors don't show the I2C link this way — see §2).
- Driver package found in DriverStore (`og0va1b.inf_amd64_8f234a229321432e\`) with a **large set of `graph_settings_og0va1b_*_ADL.xml` variants present locally on this Windows install** (`1BG502T3`, `1BG502TG`, `1BG508T3`, `BBG516T3`, and several `CJFxxx`/`YHUx` variants) — possibly a richer/newer set than whatever's already archived on the Linux side; worth a diff if that archive predates this driver version.
- **Confirmed no PDAF/VCM**: grepped one graph-settings XML (`graph_settings_og0va1b_1BG502T3_ADL.xml`, 330 lines, plain ASCII) for `paf` and `vcm` (case-insensitive) — **zero matches**. Matches the brief's expectation exactly: this IR/Windows Hello sensor has no VCM, no PDAF, single stream — a much simpler port target than the rear camera, more like the already-working front `hi556`.
- Not copied/dug further (`og0va1b.sys`, its own `SSDB` link-frequency/lane-count fields, etc.) — brief marked this as forward-looking groundwork only, and the one concrete open question it flagged (PDAF presence) is now answered.
