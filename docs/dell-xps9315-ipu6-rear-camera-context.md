# Dell XPS 13 9315 2-in-1 — rear camera (INT346D / S5K3J1) — Linux ↔ Windows context

**Purpose:** Single handoff doc for **Linux kernel / libcamera work** and **Windows reference**. Upload to an assistant when continuing rear-camera bring-up without re-explaining the story.

**End goal on Linux (Ubuntu “Resolute”, e.g. `7.0.0-15-generic`):** Rear **Samsung S5K3J1** (**`INT346D`**, **`\_SB_.PC00.LNK0`**) streaming through **IPU6** + **libcamera**/`cam`, matching Windows behavior. **Probe/bind/power are working** (2026-05-18+); remaining gap is **ISYS never completes frames** — likely **PDAFType2 / dual PAFi metadata routing**, not I2C/GPIO/SSDB.

---

## 1. Hardware and software baseline

| Item | Detail |
|------|--------|
| Machine | Dell XPS 13 **9315** 2-in-1 |
| Stack | **Intel IPU6** + IVSC-style bridge; **SoundWire** audio already solid |
| Front camera | **HI556**, ACPI **`INT3537`**, path **`\_SB_.PC00.LNK2`** — **works** on Linux + libcamera |
| Rear camera | **Samsung S5K3J1**, ACPI **`INT346D`**, path **`\_SB_.PC00.LNK0`** — **probes + streams on sensor**; **ISYS Capture 8 times out** (no frames in `cam`) |
| IR camera | **OG0VA1B**, ACPI **`OVTI00AB`** — Windows Hello / IR (third sensor) |
| Windows side | **Windows 11 To Go** (Rufus), **25H2**; Dell **Intel IR Camera Driver** **63.22000.16989.1 A03** |
| Local refs | **`~/work/dell-drivers/`** (full package); **`~/work/win-collected/`** + **`~/work/xps9315-rear-win/`** (2026-05-26 To Go session) |
| Linux kernel note | **`ipu-bridge`** may be **out-of-tree** / DKMS (e.g. **intel-ipu6-dkms**); **`s5k3j1`** driver from **ipu6-drivers** tree, not only mainline tarball |

---

## 2. Linux findings (authoritative for “what’s wrong”)

### Historical (pre quirk — still useful for SSDT context)

- **`Method (_CRS)` on `LNK0`:** gated by **`L0DI`** — empty `_CRS` on cold Linux boot prevented **`i2c-INT346D`** until **ipu-bridge quirk** (see §10).
- **AML:** **`LNK0` / `LNK2`** share templates; HIDs via **`HCID`/`GRID`** + NVS (**`L0H*` / `L2H*`**).

### Current state (2026-05-18+)

- **`intel-ipu6` / `ipu-bridge`:** **2 cameras**, both **`INT346D`** + **`INT3537`** supported.
- **Front `INT3537` → `hi556`:** **`cam`** capture works (~15 MB ppm).
- **Rear `INT346D` → `s5k3j1`:** **binds** on **`i2c-1`** ( **`i2c-INT346D:00` @ 0x10** ), **TPS68470** regulators/GPIO (Surface GO map GPIO 9/7), graph **`s5k3j1` → CSI2 1 → ISYS Capture 8** (`/dev/video8`).
- **Format:** 3976×2736 SGRBG10; crop **3968×2736 @ left=4**; link **848 MHz** — matches Windows XML.
- **`cam` rear:** hangs at capture; **`intel_ipu6_isys: stream stop/close time out`** on Capture 8. Sensor logs **`s_stream(1): 0`**, **`streaming: 3976x2736`**.
- **`pdaf_trial` 0/1/2** (module param in out-of-tree **`s5k3j1.c`**): no ISYS fix.
- **Not the bottleneck:** Dell GPIO 3/4 trial, **`get_frame_desc`** (causes lockups — do not re-add), raw **`v4l2-ctl STREAMON`** alone (broken pipe on this stack — use **`cam`**).
- **PCI ↔ `i2c-*` (re-verify each boot):** **`i2c-0`** → **`0000:00:15.0`** (`51e8`), **`i2c-1`** → `15.1` (`51e9`), **`i2c-2`** → `15.2`, **`i2c-3`** → `19.0` (`51c5`).

**Standard rear test:**

```bash
systemctl --user stop wireplumber pipewire pipewire.socket
killall -9 wireplumber pipewire cam 2>/dev/null
REAR=$(media-ctl -d /dev/media0 -e "s5k3j1 1-0010")
CSI=$(media-ctl -d /dev/media0 -e "Intel IPU6 CSI2 1")
# media-ctl -V + v4l2-ctl set-subdev-fmt 3976x2736 on CSI pads if CSI stuck at 4096x3072
sudo dmesg -C
timeout 45 cam --camera='\_SB_.PC00.LNK0' --capture=1 --file=/tmp/rear.ppm
sudo dmesg | grep -iE 's5k3j1|s_stream|streaming|isys|time out'
```

---

## 3. Windows / Dell driver clues

- **INF / driver:** **`s5k3j1sx04.inf`** matches **`ACPI\INT346D`**; dependencies include **`SpbCx`**, **`inteli2c`** (typical Intel Serial IO I2C stack).
- **`strings` on `s5k3j1sx04.sys`:** Includes messages like **`Hardware Prepare: I2C%d function %d, addr 0x%x`** and **`[ERROR] ... I2C is not supported in BIOS`** — aligns with **empty `_CRS` / BIOS gating** on Linux.
- **DebugView:** Mostly **unhelpful** (release driver; likely **WPP/ETW**, not `DbgPrint` to debugger).
- **Useful path seen when disabling/re-enabling driver (DebugView or similar):**
  - **`S5K3J1SX04 Base Full Driver Path`** → `\SystemRoot\System32\drivers\s5k3j1sx04.sys`
  - **`Sensor 0 GC file path:`** → **`C:\Windows\System32\drivers\graph_settings_S5K3J1SX04_1BAA01T3_ADL.xml`**  
    (`1BAA01T3` = module/calibration id; **`ADL`** = Alder Lake–family platform string in package.)

### 3b. Why “which I2C bus?” looks abstracted on Windows

- **Definitive wiring** (controller + 7‑bit address) is normally in **ACPI `_CRS`** (`IICB` / `I2cSerialBus` / `ResourceSource`), not in the **Camera** class Registry keys.
- **Registry has no `Csi2DataLanes` / `LinkFreq`** on this machine — tuning is in **`graph_settings*.xml`** + **`.cpf`/`.aiqb`**, not `{ca3e7ab9-…}` camera class keys.
- **PnP parent walk** from **`ACPI\INT346D\0`** stops at **PCI Express Root Complex** (not **`PCI\…51E8`**). Normal: sensor is **System** class; I2C via **SpbCx + inteli2c** + ACPI connection IDs from **`LogConf`/`BootConfig`**.
- **Windows `_CRS` for rear is non-empty** when active (see §9): three serial-bus connection IDs **9, 10, 11** for **`INT346D`** vs **7, 8** for front **`INT3537`**, **12** for **`OVTI00AB`**.

### 3c. Local reference paths on Linux

| What | Path |
|------|------|
| **Dell camera package** (386 MB) | `~/work/dell-drivers/Intel-IR-Camera-Driver_CCKMF_WIN64_63.22000.16989.1_A03_01/0/Drivers/Drivers/` |
| **Rear graph (this machine)** | `~/work/dell-drivers/graph_settings/graph_settings_s5k3j1sx04_1BAA01T3_ADL.xml` |
| **Front graph** | `~/work/dell-drivers/graph_settings/graph_settings_HI556_1BG502TG_ADL.xml` |
| **IR graph** | `~/work/dell-drivers/graph_settings/graph_settings_og0va1b_1BG502TG_ADL.xml` |
| **Rear INF / SYS / PDAF blobs** | `…/Drivers/s5k3j1sx04.{inf,sys}`, `s5k3j1sx04_1BAA01T3_ADL_PDAF_T2.{cpf,aiqb}`, `*_PDAF_MD_T3.*` |
| **Serial IO I2C INFs** | `~/work/dell-drivers/Intel-Serial-IO-Driver_…/payload/17763/Drivers/x64/iaLPSS2_I2C_ADL*.inf` |
| **IVSC driver** | `~/work/dell-drivers/Intel-Integrated-Sensor-Solution-Driver_…/` |
| **To Go: ACPI/registry** | `~/work/win-collected/` (`ACPI_INT346D.reg`, `notes.txt`, …) |
| **To Go: PnP CSVs** | `~/work/xps9315-rear-win/` |

`win-collected` **`graph_settings_s5k3j1sx04_1BAA01T3_ADL.xml`** and **`s5k3j1sx04.sys`** are **byte-identical** to the Dell package.

### 3d. Three sensors on this 9315 (Windows enum)

| ACPI | Driver | Role | Calibration (`DosDeviceName`) | `_CRS` connection IDs |
|------|--------|------|-------------------------------|------------------------|
| **`INT346D\0`** | `s5k3j1sx04` | Rear world **S5K3J1** | **`1BAA01T3`** | **9, 10, 11** |
| **`INT3537\2`** | `hi556` | Front RGB **HI556** | **`1BG502TG`** | **7, 8** |
| **`OVTI00AB\1`** | `og0va1b` | Front IR **OG0VA1B** | **`1BG502TG`** | **12** |

User-visible **Camera** class device is only **`DISPLAY\INT3480`** (Intel AVStream / IPU6). Sensors are **System** class PDOs.

### 3e. PDAF / graph — why rear differs from front (Windows authoritative)

| Sensor | `PDAF_Type` (INF/service) | Raw preset `csi_be` |
|--------|---------------------------|---------------------|
| **S5K3J1** | **`2`** (PDAFType2) | **8014** `flow="Raw"`: **`<paf format="PAFi" enabled="1" width="3968" height="684"/>`** always present |
| **HI556** | none | **8009** Raw: **output only**, no `<paf>` |
| **OG0VA1B** | none | **8001** Raw: **output only** |

Rear sensor mode: **`pdaf_type="PDAFType2"`**, **`<pdaf width="3968" height="684"/>`**, **`csi_port="0"`**, crop **left=4** → active **3968×2736**. Presets **8015+** use **`active_outputs="2"`** (dual output). **Hypothesis for Linux ISYS timeout:** firmware/graph expects **raw + PAFi sideband** on CSI2 1; Linux routes **single raw** to Capture 8 only.

---

## 4. What to do interactively on Windows To Go (checklist for the agent)

Use this as a **live script**: user performs steps; assistant suggests **next** checks and **what to save** to a USB share or zip for Linux.

### A. Files to copy off Windows (high value)

1. **`C:\Windows\System32\drivers\graph_settings_S5K3J1SX04_1BAA01T3_ADL.xml`**  
   - If copy blocked: **Admin Notepad** → Open → Save As to USB.  
   - Also copy **any** `graph_settings_S5K3J1SX04_*` or `graph_settings_*INT346*` siblings in the same folder.
2. **Dell `s5k3j1sx04.inf`** (from extracted driver package, if not already archived).
3. Optional: **export** of relevant **Registry** keys (see §B) as `.reg` text.

### B. Registry (search / export)

Search under **`HKLM\SYSTEM\CurrentControlSet`** for:

- **`INT346D`**, **`S5K3`**, **`s5k3j1`**, **`LNK0`**, **`346D`**
- Camera class GUID subtree:  
  **`HKLM\SYSTEM\CurrentControlSet\Control\Class\{ca3e7ab9-b4d3-4a6e-8393-3dc467432258}\`**  
  Inspect numbered subkeys for **`Csi2DataLanes`**, **`ACPI`**, **`HardwareID`**, friendly names, **location** strings.

Save: **right-click key → Export** for any branch that clearly belongs to **rear / world-facing** vs front.

### C. Device Manager and PnP (PowerShell) — **rear InstanceId + parent chain (priority)**

1. **Device Manager:** locate **rear / world-facing** camera and **Intel Serial IO I2C Host Controller** instances — note **Location**, **Hardware Ids**, **Parent** in **Properties**.

2. **List cameras with hardware IDs** (pick the row with **`ACPI\INT346D`** = rear; **`INT3537`** = front):

   ```powershell
   Get-PnpDevice -Class Camera -PresentOnly | ForEach-Object {
     $iid = $_.InstanceId
     $hw = (Get-PnpDeviceProperty -InstanceId $iid -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
     [pscustomobject]@{
       FriendlyName = $_.FriendlyName
       Status       = $_.Status
       InstanceId   = $iid
       HardwareIds  = ($hw -join ' | ')
     }
   } | Format-List
   ```

3. **Parent walk** — set **`$leaf`** to the **full rear** `InstanceId` (use **single quotes**):

   ```powershell
   $leaf = 'ACPI\INT346D\0'   # REPLACE with your full InstanceId from step 2

   $current = $leaf
   $n = 0
   while ($current -and $n -lt 30) {
     Write-Host ("`n[$n] " + $current)
     $dev = Get-PnpDevice -InstanceId $current -ErrorAction SilentlyContinue
     if ($dev) {
       Write-Host ("     FriendlyName: " + $dev.FriendlyName)
       Write-Host ("     Class:         " + $dev.Class)
       Write-Host ("     Status:        " + $dev.Status)
     }
     $parentProp = Get-PnpDeviceProperty -InstanceId $current -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue
     if (-not $parentProp -or -not $parentProp.Data) {
       Write-Host "     (no parent — top of chain)"
       break
     }
     $current = [string]$parentProp.Data
     $n++
   }
   ```

   If **`DEVPKEY_Device_Parent`** errors on your build, inside the loop use:

   ```powershell
   $parentProp = Get-PnpDeviceProperty -InstanceId $current |
     Where-Object { $_.KeyName -match 'Parent' } | Select-Object -First 1
   $current = [string]$parentProp.Data
   ```

4. **Optional — full property dump for rear only** (after `$leaf` is set):

   ```powershell
   Get-PnpDeviceProperty -InstanceId $leaf | Sort-Object KeyName |
     Format-Table KeyName, Type, Data -AutoSize
   ```

5. **If rear does not appear under `Camera` class**, search by ACPI:

   ```powershell
   Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'INT346D' } |
     Format-List FriendlyName, Class, Status, InstanceId
   ```

6. **Optional — enumerate I2C-ish / Intel devices:**

   ```powershell
   Get-PnpDevice | Where-Object { $_.FriendlyName -match 'I2C|Serial|8086' } |
     Format-Table Status, Class, FriendlyName, InstanceId -AutoSize
   ```

**Paste back for Linux / agent:** output of **step 2** (both cameras) + **step 3** parent walk for **`INT346D`**, and optionally **step 4**.

### D. ACPI / firmware dumps (already partially done)

- **RWEverything:** ACPI tables → save **DSDT** and **SSDT** binaries or text as needed.
- **Intel `acpidump.efi` + `iasl.exe`:** consistent **ASL/AML** sources for **`LNK0`**, **`L2DI`/`L0DI`**, **`_CRS`**, **`_STA`**, power resources.

### E. “Wake” hardware before dumps

- Open **Windows Camera**, **switch front ↔ world-facing**, leave preview **running** while exporting Registry / ACPI — reduces “cold” vs “active” mismatch for some investigations (optional).

---

## 5. What we still need (explicit gaps)

| Gap | Why it matters |
|-----|----------------|
| **IPU6 dual-stream / PAF metadata routing** on CSI2 1 | Windows always enables **PAFi 3968×684**; Linux ISYS Capture 8 never completes — compare front CSI2 0 vs rear CSI2 1 **`media-ctl`** graph (pad count, metadata links). See **`Documentation/admin-guide/media/ipu6-isys.rst`**, ov2740-style embedded lines. |
| **Map ACPI connection IDs 9–11 → `0000:00:15.x`** | Windows **`BootConfig`** uses IDs not PCI parent walk; correlate with AML **`ResourceSource`** / live Linux **`i2c-1`**. |
| **libcamera pipeline** for rear | **`s5k3j1.yaml`**, simple pipeline; metadata node if PAF stream required. |
| **Optional: second ISYS capture node** | Rear may need Capture **9–15** for metadata while **8** takes raw — enumerate on working Windows vs broken Linux. |

**Resolved (do not re-litigate):** empty `_CRS` gate (**ipu-bridge quirk**), GPIO map (**TPS68470 9/7**), **`0x10`** address, **848 MHz** link, **3968×2736** crop, registry **`Csi2DataLanes`** (absent by design), PnP walk to **51E8** (abstracted on Windows).

---

## 6. How to use this with Cloud Agent

1. **Upload this `.md`** as the first context attachment.  
2. Say explicitly: *“Suggest the next interactive step only; I will paste results or export files.”*  
3. Paste **snippets** (Registry value names + data, XML excerpts around `csi`/`i2c`/`link`, PowerShell output) — avoid pasting secrets if any appear in OEM strings.  
4. Prefer pasting **§4.C steps 2–3** (camera table + **full parent walk** for **`INT346D`**) early — highest signal for “which controller.”  
5. **Zip artifacts** (XML + `.reg` + ACPI + `.txt` of PowerShell) back to the Linux machine for SSDT / kernel work in the **desktop Cursor** project.

---

## 7. Out of scope / caveats

- **Cloud Agent** does not see the To Go desktop live; you drive **regedit**, **Explorer**, **RWEverything**; the agent suggests and interprets **pasted** output.
- **DebugView** may remain empty; do not depend on it for the **`Hardware Prepare:`** line.
- **Linux `graph_settings`** and **Windows XML** naming differ; treat Windows XML as **hints**, not a byte-for-byte Linux config.
- **To Go performance:** a **slow old 2.5″ HDD** (especially in a **USB** enclosure) makes the session **much** worse than **internal** or **external SSD** — random I/O and background services hurt. Slowness is usually **storage**, not “WTG is always unusable.”

---

## 8. Revision

| Date | Note |
|------|------|
| 2026-05-11 | Initial handoff from Cursor (Linux) + Windows To Go session notes |
| 2026-05-12 | §3b Windows abstraction vs ACPI/PnP; §4.C expanded (HardwareIds + parent walk + fallbacks); §5/§6/§7 updates |
| 2026-05-26 | §1–§3 updated for probe success + ISYS/PDAF; §3c–§3e **`dell-drivers`** map; §5 gaps reframed; §9 To Go session log; §10 streaming status |

### §9. Session log

- **2026-05-26 (Windows To Go + `dell-drivers` merge):**
  - Artifacts: **`~/work/win-collected/`** (registry, ACPI, 4× graph XML, `s5k3j1sx04.sys`, `oem28.inf`, `notes.txt`); **`~/work/xps9315-rear-win/`** (PnP/property CSVs, `reg-s5k3j1-service.txt`).
  - Rear **`ACPI\INT346D\0`**: System class, service **`s5k3j1sx04`**, BIOS **`\_SB.PC00.LNK0`**, calibration **`1BAA01T3`**, driver **63.22000.16989.1**.
  - PnP parent: **`INT346D` → `ACPI\PNP0A08\0` → HAL** (no **51E8** in chain — expected).
  - **`LogConf`/`BootConfig`**: rear **3** serial-bus connections **9, 10, 11**; front **7, 8**; IR **12**; PMIC **INT3472** **2–5**.
  - Registry: **`PDAF_Type=2`** on **`Services\s5k3j1sx04`**; no **`Csi2*`** keys anywhere; camera class **`0064`** = driver metadata only.
  - Graph **`1BAA01T3_ADL`**: **PDAFType2**, **PAFi 3968×684 enabled even in Raw preset 8014**; front HI556 Raw has **no `<paf>`**.
  - **`dell-drivers`** package confirms same files + full **`*_PDAF_T2.cpf`/`.aiqb`** set; use **`graph_settings/`** for cross-sensor compare.
  - **Conclusion:** Linux next focus = **IPU6 dual VC / metadata (PAFi)**, not registry or PnP parent walk.
  - **Windows To Go pitfalls observed (so future sessions go faster):**
    - **ExecutionPolicy:** `.ps1` blocked until `Set-ExecutionPolicy -Scope Process Bypass -Force`.
    - **Drive letters:** WTG often has **no `D:`**; use `C:\Users\<you>\Documents\...` or detect the removable drive letter before running scripts.
    - **Encoding:** Linux→Windows copy sometimes mangled Unicode **em-dash `—`** into `â€”`, causing PowerShell parser failures; prefer plain ASCII `-` in scripts/strings.
    - **Console paste reorder:** multi-line pastes can execute out of order; use a **single-line** semicolon-separated command or run from a `.ps1` opened in Notepad.
    - **Camera class export:** `reg export ...\\{ca3e7ab9-b4d3-4a6e-8393-3dc467432258}` may fail / be irrelevant here because sensors enumerate as **System** devices and the user-visible camera is **`DISPLAY\\INT3480`**.

### §10. Linux kernel progress

| Piece | Path | Status |
|-------|------|--------|
| **ipu-bridge** INT346D quirk + `physical_node` | `~/work/ubuntu-src/ipu-bridge-test/` | **Working** |
| **TPS68470 board data** | `~/work/ubuntu-src/int3472-tps68470-test/` | **Working** — Surface GO GPIO **9/7** (not Dell 7212 3/4) |
| **s5k3j1** out-of-tree | `~/work/ubuntu-src/ipu6-drivers-…/s5k3j1.c` | **Dual-stream PAFi:** `get_frame_desc` stream0 RAW10 VC0 + stream1 META8 VC1; INT346D tall vblank; **libcamera** simple pipeline opens Capture 9 sideband |
| **Front libcamera** | `cam` + **`\_SB_.PC00.LNK2`** | **Working** |
| **Rear libcamera** | `cam` + **`\_SB_.PC00.LNK0`** | **Hangs** — ISYS Capture **8** timeout |
| **Sign / load** | `~/mok-key/MOK.{priv,der}` | Required under Secure Boot; lockdown blocks **debugfs** |

**Module install paths:** `updates/ipu-test/` (**ipu-bridge**, **s5k3j1**), `updates/int3472-test/` (**int3472-tps68470**).

**Operational:** stop **PipeWire** before test; **do not `media-ctl -r`**; resolve subdevs by name / **848 MHz**, not fixed `/dev/v4l-subdevN`; if CSI2 1 stuck at **4096×3072**, set subdev fmt **3976×2736** on both CSI pads.

**If terminals freeze or reboot needs power-button hold:** experimental **`s5k3j1`** / hung **`cam`** can wedge the media stack (`lsmod` may show **`s5k3j1 … -1`**). Recovery:

1. New TTY (Ctrl+Alt+F3): `bash ~/work/git-ubuntu/dell-xps9315-stop-test-modules.sh`
2. Block auto-load: `sudo cp ~/work/git-ubuntu/modprobe.d-dell-xps9315-camera-test.conf /etc/modprobe.d/ && sudo update-initramfs -u && reboot`
3. Do **not** run reload/test scripts until the system is stable; front camera may still work with in-tree drivers if test modules are blacklisted.

**Recommended next work:**

1. Reload **`s5k3j1`**, test with **built libcamera** (`~/work/git-ubuntu/libcamera/build/src/apps/cam/cam`) via **`dell-xps9315-test-rear-cam.sh`**.
2. If still failing: try **`dell-xps9315-test-rear-dual.sh`** (raw v4l2 + metadata) and verify VC1 vs embedded-line hypothesis.
3. Tune PDAF MIPI VC/DT if dmesg shows CSI2 framing errors.
