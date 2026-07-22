# Windows-agent findings — IPU6 CSI2 front-end (FE) registers — 2026-07-21

Session goal (per `WINDOWS-AGENT-BRIEF-6-csi2-fe-registers.md`): capture the Windows values of the
CSI2 controller per-port **front-end (FE) registers** — the one receiver-side block never captured
from Windows — for the rear Samsung S5K3J1 (port 1) and the front control (port 3), to diff against
Linux's hardcoded `FE_MODE = 0`. **The single most important value is `CSI_FE_MODE`.**

---

## TL;DR

- **`CSI_FE_MODE` reads `0x0` on Windows for BOTH ports — matches Linux exactly.** The
  "continuous vs non-continuous clock mode" / FE clock-mode hypothesis is a **clean negative**,
  closed from the receiver side. This was the brief's key question; answer is "matched."
- **BUT a different register in the same block does diverge: `PPI2CSI_CONFIG_INTF` has bit 1
  (`0x2`) set on Windows and clear on Linux** — rear `0x1A` vs `0x18`, front `0x0A` vs `0x08`.
  This is uniform across both ports (not rear-specific), so it is not by itself the rear-only
  smoking gun, but it *is* the first concrete receiver-side Windows/Linux config difference found,
  and a cheap next Linux experiment.
- **Two operational lessons this session** (also saved to agent memory):
  1. Reading the IPU6 BAR while the device is **runtime-suspended (D3)** bugchecked the machine.
     Only read while the target camera is actively streaming (D0). See §0.
  2. RWEverything CLI `R32`/`DMEM` read full 64-bit addresses correctly (printed address *label*
     is cosmetically truncated to low-32); `SAVE ... Memory` **truncates** to 32-bit — use `DMEM`
     for dumps of the >4GB BAR. See §1.

---

## Notes for the next agent / brief authors (please read before running RWEverything)

Corrections and gotchas found this session, so the next Windows- or Linux-side agent doesn't
re-learn them the hard way:

- **`SAVE <file> Memory <addr> <len>` silently truncates the address to 32 bits.** On this box the
  IPU6 BAR0 is at `0x7FFF000000` (above 4GB); `SAVE` dumped BIOS firmware from `0xFF000000` instead
  of the BAR. **Use `DMEM <addr> <size>` for any dump** (it reads the full 64-bit address; it writes
  the *text* hex table, which is trivially parsed back to raw bytes). Brief 7's suggested
  `Rw.exe /Command="Save …"` line will produce garbage — use `DMEM`.
- **`R32`/`DMEM` print a cosmetically-truncated address label** (`R32 0x7FFF221284` echoes
  `…0xFF221284 = …`) but the **read itself uses the full 64-bit address** — trust the value, ignore
  the label. Proven by an aliasing test (§1).
- **Never read the IPU6 BAR while the device is runtime-suspended (D3)** — it bugchecks the machine
  (§0). Stream the target camera first (D0), confirm via a non-BAR signal, then read.
- **Sensor identity:** the front webcam is the **HI556** (port 3). The `OG0VA1B` / `ACPI\OVTI00AB`
  device is the **IR camera for Windows Hello**, *not* the front webcam — don't use it as the
  2-lane control. Rear target is **S5K3J1** (`ACPI\INT346D`, port 1). A Logitech C925e USB webcam is
  also attached; it is not the IPU6.

## 0. CRITICAL: a bugcheck was caused by reading the BAR while the IPU6 was suspended

Early in the session, before any camera was streaming, exploratory reads of the IPU6 BAR0 window
(buttress TSC/PWR_STATE, a `DMEM` of the BAR head) were issued while the IPU6 was **runtime-suspended
to D3**. This caused a **bugcheck / unclean reboot** (user observed the BSOD "…encountered a problem…";
Event 6008 unexpected-shutdown logged; **no BugCheck 1001 / WHEA event / minidump** — crash-dump
writing fails on this WTG/USB install, so a fatal PCIe/WHEA error leaves almost no forensic trace).

**Root cause:** the IPU6 is a PCIe device that runtime-suspends when idle. Reading its BAR0 in D3
generates an Unsupported-Request completion that WHEA escalates to a fatal error. The all-`0xFFFFFFFF`
values returned by such reads are the ones that survive; a later one tips it over (possibly
asynchronously, after the `Rw.exe` invocation has already returned its output).

**Corrected procedure (used for all real data below):** the device must be in **D0 (target camera
actively streaming)** before *any* BAR read; confirm streaming by a signal that does **not** read
the BAR (visible live preview + `PWR_STATE`/`TSC` liveness captured *inside* the same streaming
window); keep each read to a single tight `Rw.exe` burst. Reading an *unbacked sub-region* while the
device is otherwise in D0 is safe (returns `0xFFFFFFFF`) — the fatal case is the whole device in D3.
System recovered cleanly after reboot (IPU6 `Status=OK, CM_PROB_NONE`).

---

## 1. Tooling / method

- RWEverything portable: `C:\Users\Public\Downloads\RwPortableX64V1.7\Win64\Portable\Rw.exe`.
  `RwDrv.sys` in `System32\drivers`; loads on demand (`VulnerableDriverBlocklistEnable = 0`,
  confirmed still `0` after the reboot + Defender updates).
- **BAR0 physical base = `0x7FFF000000`** (16 MB, 64-bit BAR above 4GB). Cross-confirmed via WMI
  `Win32_DeviceMemoryAddress` (range `0x7FFF000000–0x7FFFFFFFFF`); unchanged from the 2026-07-16
  session. Device: `PCI\VEN_8086&DEV_465D` (`IPU6EP_ADLP`), bus 0 dev 5 fn 0, driver `iaisp64`.
- **64-bit addressing gotcha:** `R32 0x7FFF221284` prints `Read Memory Address 0xFF221284 = …`
  — the printed address is cosmetically masked to low-32, but the *read uses the full 64-bit
  address* (proven by an aliasing test: three addresses sharing low-32 returned three different
  values). `DMEM <addr> <size>` behaves the same (correct). `SAVE <file> Memory <addr> <len>`
  **truncates** to 32-bit (it dumped BIOS `_FVH` firmware from `0xFF000000` instead of the BAR) —
  **do not use SAVE here; use DMEM.**
- Invocation: `& Rw.exe /Command="R32 …;R32 …;DMEM …" /Nogui /Stdout /Min`.

---

## 2. Sensor / port identity note

- Rear world-facing target: **S5K3J1SX04** (`ACPI\INT346D\0`) = **port 1**.
- Front user-facing control: **HI556** = **port 3** (per user).
- `OG0VA1B` (`ACPI\OVTI00AB\1`) is the **IR camera for Windows Hello**, *not* the front webcam —
  noted to avoid confusion; it was not used as the control here.
- A Logitech USB webcam C925e is also attached; it was avoided (not the IPU6).

---

## 3. Port 1 — rear S5K3J1 (target) — read with confirmed-live preview

Liveness captured in the same burst: `PWR_STATE (BAR0+0x5C) = 0x003A113B` (IS_PWR = UP_DONE, D0,
identical to 2026-07-16); `TSC_LO (BAR0+0x164) = 0x3ABD021A` then `0x3ABD0E6B` on immediate re-read
(**incrementing → live silicon**). User confirmed live rear preview (camera focused on a wall).

| Register            | Offset (BAR0+…) | **Windows** | Linux            | Match |
|---------------------|-----------------|-------------|------------------|-------|
| PPI2CSI_ENABLE      | `0x221200`      | `0x00000001`| `0x1`            | ✓ |
| **PPI2CSI_CONFIG_INTF** | `0x221204`  | **`0x0000001A`** | `0x18` (4 lanes) | ✗ **bit1 set** |
| CSI_FE_ENABLE       | `0x221280`      | `0x00000001`| `0x1`            | ✓ |
| **CSI_FE_MODE**     | `0x221284`      | **`0x00000000`** | `0x0`       | ✓ **match** |
| CSI_FE_MUX_CTRL     | `0x221288`      | `0x00000000`| `0x0` (SENSOR_IN)| ✓ |
| CSI_FE_SYNC_CNTR    | `0x221290`      | `0x00000003`| `0x3` (line+frame)| ✓ |

### Full FE region dump, port 1 — `0x221200`–`0x2212FF` (raw hex, 16 bytes/row)
```
0x221200: 01 00 00 00 1A 00 00 00 06 00 00 00 01 00 00 00
0x221210: 10 08 01 00 18 18 08 10 90 09 80 01 98 19 88 11
0x221220: 51 0A 40 02 59 1A 48 12 D0 0B C0 03 D8 1B C8 13
0x221230: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x221240: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x221250: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x221260: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x221270: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x221280: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0x221290: 03 00 00 00 01 00 00 00 FF FF FF FF FF FF FF FF
0x2212A0: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF   (…FF through 0x2212FF)
```
Decoded dwords of interest (little-endian):
- `0x221208 = 0x00000006`, `0x22120C = 0x00000001` (unnamed, adjacent to PPI2CSI block)
- per-lane table `0x221210..0x22122C` (8 dwords): `0x00010810 0x10081818 0x01800990 0x11881998
  0x02400A51 0x12481A59 0x03C00BD0 0x13C81BD8`
- `0x22128C = 0x00000000` (unnamed, after MUX_CTRL); `0x221294 = 0x00000001` (unnamed, after SYNC_CNTR)
- `0x221230–0x22127F` and `0x221298–0x2212FF` = `0xFFFFFFFF` (unbacked sub-regions, safe FF reads)

---

## 4. Port 3 — front HI556 (control) — read with confirmed-live preview

Liveness in the same burst: `PWR_STATE = 0x003A113B`; `TSC_LO = 0x23B1E0DB` then `0x23B1F16F`
(**incrementing → live**). User confirmed live front preview.

| Register            | Offset (BAR0+…) | **Windows** | Linux            | Match |
|---------------------|-----------------|-------------|------------------|-------|
| PPI2CSI_ENABLE      | `0x223200`      | `0x00000001`| `0x1`            | ✓ |
| **PPI2CSI_CONFIG_INTF** | `0x223204`  | **`0x0000000A`** | `0x8` (2 lanes)  | ✗ **bit1 set** |
| CSI_FE_ENABLE       | `0x223280`      | `0x00000001`| `0x1`            | ✓ |
| **CSI_FE_MODE**     | `0x223284`      | **`0x00000000`** | `0x0`       | ✓ **match** |
| CSI_FE_MUX_CTRL     | `0x223288`      | `0x00000000`| `0x0`            | ✓ |
| CSI_FE_SYNC_CNTR    | `0x223290`      | `0x00000003`| `0x3`            | ✓ |

### Full FE region dump, port 3 — `0x223200`–`0x2232FF` (raw hex)
```
0x223200: 01 00 00 00 0A 00 00 00 06 00 00 00 01 00 00 00
0x223210: 10 08 01 00 18 18 08 10 90 09 80 01 98 19 88 11
0x223220: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223230: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223240: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223250: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223260: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223270: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
0x223280: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0x223290: 03 00 00 00 01 00 00 00 FF FF FF FF FF FF FF FF
0x2232A0: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF   (…FF through 0x2232FF)
```
Decoded: `0x223208 = 0x00000006`, `0x22320C = 0x00000001`; per-lane table `0x223210..0x22321C`
(4 dwords only — 2-lane): `0x00010810 0x10081818 0x01800990 0x11881998`; `0x223294 = 0x00000001`.
`0x223220` onward and `0x223298–0x2232FF` = `0xFFFFFFFF`.

---

## 5. Analysis

### 5.1 CSI_FE_MODE — matched (the brief's key question)
`CSI_FE_MODE = 0x0` on Windows for both ports, identical to Linux's hardcoded `FE_MODE = 0`.
`CSI_FE_ENABLE`, `CSI_FE_MUX_CTRL (SENSOR_IN)`, and `CSI_FE_SYNC_CNTR (line+frame)` also match.
→ The receiver front-end clock/mode configuration is **matched** between Windows and Linux. The
"continuous vs non-continuous clock" hypothesis is closed from the receiver side. Clean negative.

### 5.2 PPI2CSI_CONFIG_INTF — a real, uniform divergence (new)
| | Windows | Linux | delta |
|---|---|---|---|
| Port 1 (rear, 4-lane) | `0x1A` | `0x18` | +`0x2` (bit1) |
| Port 3 (front, 2-lane)| `0x0A` | `0x08` | +`0x2` (bit1) |

Field decoding from these four values: bit 3 (`0x8`) always set; bit 4 (`0x10`) = 4-lane vs 2-lane
selector; **bit 1 (`0x2`) = a Windows-only bit, set on every port, cleared by Linux on every port.**

Interpretation: because the **working** front control also has bit 1 set on Windows (and works on
Linux with bit 1 clear), bit 1 is **not** the rear-only smoking gun. But it is the first concrete
receiver-side register value that Windows programs and Linux does not — worth a Linux experiment:
force `PPI2CSI_CONFIG_INTF |= 0x2` on the rear port (under the existing DMI gate) and re-check CRC/
sync. Low cost, well-motivated by the fact that the corrupting path is CSI2/physical and this is a
PPI→CSI interface-config bit.

### 5.3 Adjacent unnamed config surfaced by the region dump
- `+0x08 = 0x6`, `+0x0C = 0x1` — identical on both ports.
- Per-lane table at `+0x10`: first 4 dwords identical on both ports; the rear (4-lane) has 4 *extra*
  dwords (`+0x20..+0x2C`) that the front (2-lane) leaves unbacked (`0xFF`) — consistent with a
  per-lane structure sized by lane count (2 dwords/lane). Values are packed (e.g. `0x00010810`,
  `0x10081818`); not yet decoded — captured raw for the Linux side to compare against whatever
  `ipu6-isys-csi2.c` writes to the PPI2CSI region.
- `+0x94 = 0x1` — identical on both ports (adjacent to `CSI_FE_SYNC_CNTR`).

---

## 6. Deliverable checklist (per brief)
- [x] Discovered BAR0 base: `0x7FFF000000`.
- [x] Both tables filled with Windows-read values (port 1 rear **and** port 3 control).
- [x] Each read taken with a confirmed-live preview (user-confirmed + in-burst `PWR_STATE`/`TSC`
      liveness; `TSC` incrementing both times).
- [x] All-`0xFFFFFFFF` reads noted as such (unbacked sub-regions within each port's FE slice; these
      were safe because the device was in D0 — see §0).
- [x] Full `0x100`-byte FE region dumped for each port (`0x221200`–`0x2212FF`, `0x223200`–`0x2232FF`).

## 7. Recommended next step for Linux work
Force `PPI2CSI_CONFIG_INTF` bit 1 (`|= 0x2`) on the rear CSI2 port under the existing DMI gate and
re-test the S5K3J1 for CRC/sync recovery. Treat `CSI_FE_MODE` as settled (`0` is correct). Keep the
raw per-lane `+0x10` table for comparison, in case a lane-mapping mismatch is hiding there.
