# Windows-agent brief: read back the IPU6 CSI2 front-end (FE) registers

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To
Go install on a Dell XPS 13 9315 2-in-1. Disposable, throwaway environment, admin rights
fine, same ground rules as prior sessions (scope is reconnaissance — read data, don't
change system config beyond what's needed to run a diagnostic tool). RWEverything should
already work this session (see `windows-agent-findings-csi2-timing-2026-07-16.md` §1 for
the `VulnerableDriverBlocklistEnable` fix if `RwDrv.sys` fails to load).

Short context: a Samsung S5K3J1 rear camera works on Windows but produces a black screen
on Linux — it streams and frame-syncs, but every packet inside every frame is corrupted
at the CSI2/physical layer. Exhaustive Linux-vs-Windows comparison has now matched, byte
for byte, **every receiver-side register we've found a way to read** — PHY calibration
tables, ISYS clock/power, hub access grants — *except one block that was never captured
from Windows*: the CSI2 controller's per-port **front-end (FE) registers**. On Linux
these are set to fixed literals with no configurability. This brief captures the Windows
values of that one uncompared block, so we can tell whether Windows configures its
receiver front-end differently (e.g. a different clock-mode / FE_MODE setting) than
Linux's hardcoded `FE_MODE = 0`.

## What to read

The IPU6 device is PCI `8086:xxxx` (Intel IPU6; on Linux it enumerates at
`0000:00:05.0`). Its **BAR0** is a memory-mapped register window. Everything below is an
offset **from the start of BAR0**.

The CSI2 controller lives at `BAR0 + 0x220000`. Each CSI2 port has its own 0x1000-byte
register slice: `port_base(id) = 0x220000 + id*0x1000`. The **rear S5K3J1 is port 1**;
the **front hi556 (works — use as control) is port 3**.

Target registers (32-bit reads), for the rear sensor (port 1):

| Register            | Absolute offset (BAR0 + …) | Linux value (rear) |
|---------------------|----------------------------|--------------------|
| PPI2CSI_ENABLE      | `0x221200`                 | `0x1`              |
| PPI2CSI_CONFIG_INTF | `0x221204`                 | `0x18` (4 lanes)   |
| CSI_FE_ENABLE       | `0x221280`                 | `0x1`              |
| **CSI_FE_MODE**     | **`0x221284`**             | **`0x0`**  ← key   |
| CSI_FE_MUX_CTRL     | `0x221288`                 | `0x0` (SENSOR_IN)  |
| CSI_FE_SYNC_CNTR    | `0x221290`                 | `0x3` (line+frame) |

For the **control** (front hi556, port 3), the same offsets but port base `0x223000`
(so FE_MODE = `0x223284`). Linux reads `mode=0x0 mux=0x0 sync=0x3`, `ppi_intf=0x8`
(2 lanes) there.

**The single most important value is `CSI_FE_MODE` (rear = `0x221284`).** Linux hardcodes
it to `0`. If Windows writes anything other than `0` here, that is the first receiver-side
divergence found in the entire investigation.

## Timing — this MUST be read while the camera is actively streaming

This register window is power-gated / access-arbitrated: it is only backed by real
silicon while that port is actively streaming (same behavior as the PHY0 region in
brief 3). So:

1. Open the Windows **Camera** app and **switch to the rear camera** so a live preview is
   running. Leave it running.
2. *Then* do the RWEverything MMIO reads at the offsets above.
3. Repeat for the control: switch the Camera app to the **front** camera, get a live
   preview, then read the port-3 offsets (`0x223…`).

## How to read MMIO with RWEverything

1. Launch RWEverything (Rw.exe) as admin.
2. **Find BAR0's physical base:** menu → *PCI* → locate the Intel Image Processing Unit /
   IPU6 device (vendor `8086`). Read its BAR0 (the first memory BAR, Type = Memory,
   usually 64-bit) from config offset `0x10`. Mask off the low 4 flag bits to get the
   physical base address. Record it (call it `BAR0`).
3. **Read the registers:** menu → *Memory*, go to address `BAR0 + 0x221284` (etc.), read
   the 32-bit dword. Do this for every offset in both tables while the matching camera
   streams.

`RwDrv.sys` can script this from the command line if a GUI is awkward:
`Rw.exe /Command="R32 0x<BAR0_plus_offset>" /Nogui /Stdout` — but confirm the address math
by hand first (BAR0 base + offset).

## What each outcome means

- **FE_MODE (0x221284) reads `0x0` on Windows too** → receiver front-end clock/mode config
  is matched, and the "continuous vs non-continuous clock mode" hypothesis is closed from
  the receiver side. Clean, useful negative.
- **FE_MODE reads non-zero on Windows** → the first real receiver-side difference. Capture
  the exact value; that becomes the next Linux experiment (force the same value under the
  existing DMI gate).
- **Reads return `0xFFFFFFFF`** → the hub-access arbiter is gating userspace MMIO the same
  way it gated Linux's userspace mmap. That is itself a reportable result (means this
  block isn't readable from userspace on either OS). If so: note whether the preview was
  *genuinely live* at read time, and try a few reads in quick succession right after the
  preview image appears — the window may open only once frames are flowing.

## Deliverable

Write findings to `windows-agent-findings-csi2-fe-registers-2026-07-XX.md` in the project
root. Include: the discovered BAR0 base; both tables filled with the Windows-read values
(rear port 1 **and** control port 3); whether each read was taken with a confirmed-live
preview; and any all-`0xFFFFFFFF` reads noted as such. Also dump the full 0x100-byte FE
region for each port (`0x221200`–`0x221300` and `0x223200`–`0x223300`) as raw hex — there
may be adjacent config we haven't thought to name.
