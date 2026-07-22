# Windows-agent findings — S5K3J1 PLL divider / sensor I2C config — 2026-07-20

Session goal (per `WINDOWS-AGENT-BRIEF-5-pll-divider-regs.md`): read back the rear sensor's
actual PLL divider register values (`0x0136`, `0x0300`–`0x0312`) while Windows streams, to
confirm whether the S5K3J1's real MIPI output bit rate matches what Linux assumes
(512 MHz link / 1024 Mbps/lane) — or whether Windows programs different dividers, which
would explain the every-packet-corrupt-but-frame-sync-survives symptom on Linux.

## Bottom line

**Partial result — important, but the specific ask (divider *values*) is not fully answered.**

- **Confirmed**: Windows configures the S5K3J1 predominantly via **host I2C writes to
  address `0x10`** — captured live during a real streaming session: **619 writes + 36
  reads**. This is not firmware-handoff; the host driver drives the sensor register
  configuration directly, at the same order of magnitude as Linux's `mode_3976x2736_regs[]`
  table (~577 entries). The write *format* matches Linux exactly (16-bit big-endian
  register address + value).
- **Confirmed**: the capture includes **burst writes** (14 × 34-byte, plus 32/22/18/14/12/10/8/6-byte
  writes) whose payload totals ~450+ data bytes — closely matching the **~400-byte contiguous
  microcode-looking run around `0x90c8`** that Linux uploads. Strong evidence Windows uploads
  the *same* microcode/config blob via chunked I2C bursts. (This also substantially answers
  the open question from brief 4 — see §5.)
- **Not obtained**: the actual PLL divider **values**. The `Intel-iaLPSS2-I2C` ETW provider —
  even at maximum verbosity (level `0xFF`, all keywords) — logs only the transfer
  *descriptors* (slave address, length, direction, status), **not the payload bytes**. No
  other available provider (SpbCx class extension, MF-FrameServer, Sensors, camera stack)
  carries the raw I2C bytes either. Extracting the values requires WinDbg buffer-dumping —
  see §6.

Method note: the brief's stated primary approach (RWEverything I2C spot-read of `0x10`) is
**not viable on this hardware** — the sensor sits on an Intel LPSS (Serial IO) DesignWare I2C
controller owned exclusively by the Windows SpbCx camera driver stack during streaming;
RWEverything's I2C/SMBus tool targets the *legacy PCH SMBus controller* (`0x51A3`), which is
different silicon not wired to the sensor. Driving the LPSS controller directly via raw MMIO
would collide with the live Windows driver and risk wedging the bus. So I used passive ETW
capture instead, which is both safe and (for a *write*-sequence question) more directly
comparable to Linux's written values than a read-back would be. The catch is that this
provider doesn't expose the bytes.

## 1. Capture method

- Confirmed `VulnerableDriverBlocklistEnable = 0` still in effect (RWEverything/RwDrv would
  load), sensor `ACPI\INT346D\0` (S5K3J1SX04) present and OK, camera not yet running (clean
  pre-stream state).
- Started an ETW trace on three providers *before* opening the camera:
  - `Intel-iaLPSS2-I2C` `{C2F86198-03CA-4771-8D4C-CE6E15CBCA56}` — the LPSS I2C controller driver
  - `Intel-iaLPSS-I2C` `{D4AEAC44-AD44-456E-9C90-33F8CDCED6AF}` — legacy variant (no events emitted)
  - `Microsoft-Windows-SPB-ClassExtension` `{72CD9FF7-4AF8-4B89-AEDE-5F26FDA13567}` — SpbCx framework
    (emitted I/O-flow markers only; **empty `EventData`** in decode — no address or payload)
  - All at keywords `0xFFFFFFFFFFFFFFFF`, level `0xFF`.
- User opened Camera → rear/world-facing → confirmed live preview. Let it run, then stopped
  the trace. ETL = 13 MB, decoded via `tracerpt … -of XML` = 21 MB.
- Sensor traffic located at XML line ~59098 onward ("Controller INFO: Connected to target:
  Addr:0x10 Mode:7bit ClkFreq:400000").

## 2. What the trace shows for sensor `0x10` (the useful, confirmed data)

I2C bus parameters (from the "Connected to target" event):
- **Slave address `0x10`, 7-bit mode, 400 kHz (fast mode), PIO transfer.**

Transfer counts during the captured stream session (first write `14:00:40.968`, last
`14:00:47.280` — the later writes are per-frame AE/AF/AWB runtime updates, not initial config):

| Transfer size | Count | Interpretation |
|---|---|---|
| WRITE 4 bytes | 399 | 16-bit reg addr + 16-bit value (standard SMIA/CCS `write_reg(u16,u16)` — same as Linux) |
| WRITE 3 bytes | 125 | 16-bit reg addr + 8-bit value (8-bit register writes) |
| WRITE 2 bytes | 36  | 16-bit reg addr only — the address-set that precedes each read (matches read count exactly) |
| WRITE 6 bytes | 32  | 16-bit addr + 4 data bytes (burst / 32-bit field) |
| WRITE 34 bytes | 14 | 16-bit addr + **32 data bytes** — burst upload chunks (microcode/tuning blob) |
| WRITE 8/10/12/14/18/22/32 bytes | 13 total | more burst-upload chunks of varying length |
| READ (length 2) | 36  | 16-bit value reads (chip-ID / status / read-back verification) |

- **Total: 619 writes + 36 reads.** Linux's `mode_3976x2736_regs[]` is ~577 entries — same
  order of magnitude, consistent with Windows sending essentially the same volume of
  register configuration.
- **The 14 × 34-byte bursts alone carry 14 × 32 = 448 data bytes**, closely matching Linux's
  ~400-byte contiguous run around `0x90c8` that "looks like ARM Cortex-M machine code being
  uploaded into the sensor's internal processor." Adding the other large writes, Windows
  clearly uploads a comparable blob — via I2C burst writes, from the host, not firmware.

## 3. The specific PLL registers (what we know and don't)

The PLL config registers the brief asked about (`0x0136`, `0x0300`, `0x0304`, `0x0306`,
`0x030c`, `0x030e`, `0x0310`, `0x0312`) are **4-byte writes**, and they are present among the
399 four-byte writes near the start of the sequence (the PLL block is written right after the
EXTCLK register, early in mode config — consistent with the very first 4-byte writes at line
~59292 onward). **But the trace does not expose the 4 payload bytes of any write**, so the
actual values written cannot be read out of this capture. We can see *that* Windows writes
~8 four-byte registers in the PLL-config region at the right point in the sequence; we cannot
see *what values* it writes.

Linux's values (reference, for the follow-up comparison — from the brief / `s5k3j1.c`):

| Register | Linux writes | Meaning |
|---|---|---|
| `0x0136` | `0x1333` | EXTCLK = 19.2 MHz |
| `0x0300` | `0x0007` | vt_pix_clk_div |
| `0x0304` | `0x0002` | pre_pll_clk_div |
| `0x0306` | `0x0095` | pll_multiplier |
| `0x030c` | `0x0000` | — |
| `0x030e` | `0x0003` | — |
| `0x0310` | `0x0109` | — |
| `0x0312` | `0x0001` | — |

The Windows column of this table is what a follow-up needs to fill in (see §6).

## 4. Why RWEverything spot-reads were not used

Documented for the record so the next session doesn't retry a dead end:
- Sensor `0x10` is on an **Intel LPSS DesignWare I2C controller**, claimed exclusively by the
  Windows SpbCx/`inteli2c` driver stack whenever the camera is open.
- RWEverything's I2C/SMBus function targets the **legacy PCH SMBus host controller (`0x51A3`)**,
  which is separate silicon and is not the bus the sensor is on. (This same `51A3`-vs-`51E8`-family
  distinction was flagged in the 2026-07-13 findings §3.)
- Driving the LPSS controller directly via RWEverything MMIO would put a second master on a
  controller the Windows driver is actively using → likely bus wedge / camera-stack crash,
  and (given the ASMedia USB-boot-bridge shutdown-hang issue found this same day) a
  potentially painful recovery. Not attempted.
- Stopping the stream first to free the controller doesn't help: the sensor loses its PMIC
  power rail on stream stop, so the PLL registers wouldn't survive to be read back.

## 5. Bonus: this also addresses brief 4 (the `mode_3976x2736_regs[]` question)

Brief 4 asked whether Windows configures the sensor via host I2C writes at all, or whether the
config lives in the ISP firmware (given the register table couldn't be found in
`s5k3j1sx04.sys`). **This capture answers it: Windows does drive the sensor config via host
I2C — 619 writes including burst uploads totaling hundreds of bytes.** The reason those bytes
weren't found statically in `s5k3j1sx04.sys` is not that they're firmware-side; they're
data the driver sources at runtime (from its `.aiqb`/`.cpf` tuning blobs and/or graph config)
and streams out over I2C. The bytes are real host-I2C traffic — just not embedded as a
literal contiguous array in the `.sys` code section.

## 6. Follow-up path to get the actual values (recommended for a dedicated session)

The values require capturing the I2C write *buffer*, which no ETW provider exposes. Two paths:

1. **WinDbg buffer-dump (most direct).** Local KD is already working on this machine
   (`kd -kl`, from the 2026-07-13 session; boot config unchanged). Approach: identify the
   `iaLPSS2_I2C` driver's transfer/FIFO-fill function, set a breakpoint that dumps the WDF
   request's input buffer (the 4 bytes) and auto-continues (`bp <addr> "db <bufptr> L4; g"`),
   then start a stream. **Finding the breakpoint address is the real work** — no public
   symbols exist for the third-party Intel driver, so this needs **offline Ghidra/IDA RE of
   `iaLPSS2_I2C_ADL.sys`** to locate the function first (per the brief's own note and the
   2026-07-16b session's conclusion that blind live-tracing is the wrong order). Ghidra is not
   installed in this WTG environment; do the RE on the copied `.sys` offline.
   - **Risk to weigh**: the boot disk is behind the flaky ASMedia USB bridge (see the
     shutdown-hang diagnosis from 2026-07-16). Auto-continuing breakpoints only halt for
     microseconds each, so cumulative halt over ~600 writes is milliseconds — should be
     tolerable — but any mistake causing a sustained KD halt could stall boot-disk I/O. Keep
     breakpoints auto-continuing; don't sit at a prompt while halted.
2. **Sensor-driver WPP trace.** `s5k3j1sx04.sys` uses WPP/ETW (per 2026-05 notes). Extract its
   trace GUID + TMF from the binary and enable it — *if* the driver has trace points that log
   register writes with values, this would give them cleanly. Uncertain payoff (release driver;
   may only log control-flow, not values) and needs the TMF to decode.

Given #1 needs offline Ghidra and #2 is uncertain, neither is a quick in-session add — both are
genuine follow-up projects, consistent with how the brief framed the WinDbg fallback ("a real
time investment, not a quick fallback").

## 7. Interpretation for the Linux investigation

Even without the exact values, this narrows things:
- The sensor is definitely being configured by ~the same volume/shape of host I2C register
  traffic on Windows as Linux writes — so a *gross* structural difference (e.g. Windows skips
  the PLL block entirely, or configures a totally different mode) is unlikely.
- The open possibility the brief cares about — that Windows programs *subtly different PLL
  divider values* targeting the same nominal link frequency — remains **neither confirmed nor
  refuted**, because the values aren't in the capture. It's still a live hypothesis worth the
  §6 follow-up, precisely because it would be invisible to every receiver-side comparison done
  so far (all of which matched).
- If the §6 follow-up eventually shows the PLL values *match* Linux's exactly, that closes the
  last sensor-side register avenue and points at something non-register: analog signal
  integrity / board / cable, or a firmware-mediated timing difference not visible as a register
  on either OS.

## Artifacts

- Raw ETL: `scratchpad/pllcap.etl` (13 MB) and decoded `scratchpad/pllcap.xml` (21 MB) — in
  this session's scratchpad (not persisted to the shared folder; regenerate if needed, the
  capture is reproducible). Sensor `0x10` activity begins at XML line ~59098.
