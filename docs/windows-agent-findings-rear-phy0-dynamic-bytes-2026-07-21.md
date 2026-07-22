# Windows-agent findings — rear PHY0 dynamic-byte value compare — 2026-07-21

Session goal (per `WINDOWS-AGENT-BRIEF-7-rear-phy0-dynamic-bytes.md`): dump the full MCD-PHY0 macro
(`BAR0 + 0x10000`, `0x1960` bytes) on a **working Windows rear stream**, across **3 rear-stream
restarts**, and compare the per-lane **dynamic** bytes' *values* to broken **Linux-rear** — per lane,
the control Linux-vs-Linux-front never provided (front is 2-lane, can't stand in for a 4-lane
problem). Captured back-to-back with brief 6 on the same boot.

Raw captures delivered alongside this file in the project root:
`win-rear-phy0-1.bin` / `-2.bin` / `-3.bin` (raw 6496-byte binaries, for `scripts/decode-phy0-lanes.py`)
and `win-rear-phy0-1.txt` / `-2.txt` / `-3.txt` (the RWEverything hex dumps they were parsed from).

---

## TL;DR

- **One clean, universal divergence: lane field `+0xb8` reads `0x00` on Windows on all 5 lanes
  across all 3 restarts, where Linux-rear holds `0x10–0x13`.** Windows never reaches Linux's range
  on any lane. This is the standout — a per-lane field the working receiver keeps at `0` and the
  broken one does not (see caveat below: could be a *symptom* readout rather than a causal lever).
- Two softer, per-lane-only differences: `+0x11d` on **D2/D3** (Windows `21` vs Linux `27`) and
  `+0x152` on **D1/D0** (Windows `00` vs Linux `60`) — but both fields churn through exactly those
  values on other lanes/attempts, so they are phase/attempt differences within a shared value set,
  not out-of-range. Not clean divergences.
- Everything else (`+0x1c`, `+0xb0`, `+0xb2`, `+0xb3`) is static or churns within Linux's value
  set → matched. So of the ~6 dynamic per-lane bytes, five are matched-or-within-range and **only
  `+0xb8` is consistently, universally outside Linux's range.**

---

## Method / integrity

- BAR0 base = **`0x7FFF000000`** (confirmed brief 6, unchanged). PHY0 macro = `BAR0 + 0x10000` =
  `0x7FFF010000`, length `0x1960` (6496 bytes). Device `8086:465D`, bus0/dev5/fn0.
- **Safety rule enforced** (see `windows-agent-findings-csi2-fe-registers-2026-07-21.md` §0): the
  IPU6 BAR is only read while the rear camera is actively streaming (D0). Reading it while suspended
  bugchecked the box earlier this session; not repeated here.
- **Dump command:** `DMEM 0x7FFF010000 0x1960` (NOT `SAVE` — `SAVE Memory` truncates the address to
  32-bit and would dump BIOS firmware; `DMEM` reads the full 64-bit address correctly). `DMEM` with a
  filename writes the *text* hex table, so each dump was captured to `.txt` and parsed here into a
  true raw `.bin` (verified exactly `0x1960` = 6496 bytes each).
- **Liveness — each dump taken with a genuinely-live rear preview** (user-confirmed + in-burst
  proof): `PWR_STATE (BAR0+0x5C) = 0x003A113B` (IS_PWR=UP_DONE) on all three, and `TSC_LO` visibly
  incrementing between two back-to-back reads each time:
  - dump 1: `0x482990C7 → 0x4829C499`
  - dump 2: `0xF9C52BA9 → 0xF9C592D5`
  - dump 3: `0xB5C82CA7 → 0xB5C83F71`
- The three dumps are distinct live captures (different TSC; real byte-level churn between them),
  not a repeated/stale snapshot.
- Lane blocks 0x200 apart; confirmed roles D1/D0/**C0(clock)**/D2/D3 at `0x200/0x400/0x600/0x800/0xa00`.

---

## Filled comparison table (Windows d1,d2,d3  |  Linux-rear)

Values are the byte at `block + field`. `✓` = matched or Windows-set contains the Linux value;
`✗` = Linux value not present in the 3 Windows samples for that lane.

| lane | field | win d1,d2,d3 | win set | Linux | |
|------|-------|--------------|---------|-------|---|
| D1 (0x200) | +0x1c | 03,03,03 | 03 | 03 | ✓ |
| D1 | +0xb0 | 0d,0d,0d | 0d | 0d | ✓ |
| D1 | +0xb2 | 10,10,10 | 10 | 10 | ✓ |
| D1 | +0xb3 | c8,c8,c8 | c8 | c8 | ✓ |
| **D1** | **+0xb8** | **00,00,00** | **00** | **12** | **✗** |
| D1 | +0x11d | 27,27,21 | 21,27 | 21 | ✓ |
| D1 | +0x152 | 00,00,00 | 00 | 60 | ✗ (churns to 60 on other lanes) |
| D0 (0x400) | +0x1c | 03,03,03 | 03 | 03 | ✓ |
| D0 | +0xb0 | 0d,09,09 | 09,0d | 09 | ✓ |
| D0 | +0xb2 | 10,10,10 | 10 | 10 | ✓ |
| D0 | +0xb3 | c8,c8,c8 | c8 | c8 | ✓ |
| **D0** | **+0xb8** | **00,00,00** | **00** | **12** | **✗** |
| D0 | +0x11d | 27,21,27 | 21,27 | 21 | ✓ |
| D0 | +0x152 | 00,00,00 | 00 | 60 | ✗ (churns to 60 on other lanes) |
| C0/clk (0x600) | +0x1c | 03,03,03 | 03 | 03 | ✓ |
| C0 | +0xb0 | 0d,09,09 | 09,0d | 09 | ✓ |
| C0 | +0xb2 | 00,00,04 | 00,04 | 00 | ✓ |
| C0 | +0xb3 | c8,c8,c8 | c8 | c8 | ✓ |
| **C0** | **+0xb8** | **00,00,00** | **00** | **10** | **✗** |
| C0 | +0x11d | 27,21,21 | 21,27 | 21 | ✓ |
| C0 | +0x152 | 11,11,11 | 11 | 11 | ✓ |
| D2 (0x800) | +0x1c | 03,03,03 | 03 | 03 | ✓ |
| D2 | +0xb0 | 09,09,0d | 09,0d | 0d | ✓ |
| D2 | +0xb2 | 10,10,10 | 10 | 10 | ✓ |
| D2 | +0xb3 | c8,c8,c8 | c8 | c8 | ✓ |
| **D2** | **+0xb8** | **00,00,00** | **00** | **12** | **✗** |
| D2 | +0x11d | 21,21,21 | 21 | 27 | ✗ (churns to 27 on lower lanes) |
| D2 | +0x152 | 60,00,00 | 00,60 | 00 | ✓ |
| D3 (0xa00) | +0x1c | 03,03,03 | 03 | 03 | ✓ |
| D3 | +0xb0 | 0d,0d,0d | 0d | 0d | ✓ |
| D3 | +0xb2 | 10,10,10 | 10 | 10 | ✓ |
| D3 | +0xb3 | c8,c8,c8 | c8 | c8 | ✓ |
| **D3** | **+0xb8** | **00,00,00** | **00** | **13** | **✗** |
| D3 | +0x11d | 21,21,21 | 21 | 27 | ✗ (churns to 27 on lower lanes) |
| D3 | +0x152 | 40,00,40 | 00,40 | 00 | ✓ |

---

## Analysis

### The one clean result: `+0xb8` — Windows `0x00` vs Linux `0x10–0x13`, universally
Across **all five lanes and all three restarts**, Windows-rear holds `+0xb8 = 0x00`. Linux-rear
holds `0x12,0x12,0x10,0x12,0x13` (D1,D0,C0,D2,D3). Windows never visits Linux's range on any lane;
Linux's value is never in the Windows sample set. This is the only field that is *consistently and
universally* outside the other OS's range — exactly the pattern brief 7 was hunting for.

**Two readings, and we can't yet tell which from the receiver side alone:**
1. **Causal lever (Linux writes something Windows doesn't):** `+0xb8` is a per-lane config/deskew
   register that Linux programs to `~0x10-0x13` and Windows leaves at `0`. Experiment: force the
   rear per-lane `+0xb8 = 0x00` on Linux (under the existing DMI gate) and re-check CRC/sync.
2. **Symptom / health readout (more likely, given the values):** `+0xb8` is a per-lane
   error/mismatch *status* that reads `0` on a healthy stream (Windows) and non-zero (`0x10-0x13`)
   on the broken Linux stream *because* the lanes are erroring. If so it is a beautiful per-lane
   confirmation that the corruption is physical-layer and lane-wide — but a **symptom, not the fix.**

**Next step is to identify `+0xb8`'s semantics on the Linux side** (is it in the values
`ipu6-isys-mcd-phy.c` *writes*, or a register it only ever *reads back*?). That single question
decides whether `+0xb8` is the lever or the thermometer. The raw `.bin`s are provided so the field
can be located in the driver's write tables directly.

### The softer, per-lane differences (probably not real)
- `+0x11d`: Windows D2/D3 stayed at `21` (all 3), Linux D2/D3 = `27`. But `+0x11d` churns `{21,27}`
  and Windows visits `27` on D0/D1/C0 — the Windows/Linux per-lane *phase* differs but the value set
  is shared. Looks like attempt-to-attempt shuffle, not a fixed divergence.
- `+0x152`: Windows D1/D0 stayed at `00` (all 3), Linux = `60`. But `+0x152` churns `{00,40,60}`
  across lanes/attempts (D2 hit `60`, D3 hit `40`), and C0 matches exactly (`11`). brief 3 saw this
  byte churn `{0x60,0x40}` on D1; our captures widen the observed set to include `00`. Shared set →
  not a clean divergence.

### Matched fields
`+0x1c` (`03`), `+0xb3` (`c8`) fully static and matched. `+0xb2` matched (`10`, C0=`00/04`).
`+0xb0` churns `{09,0d}` on both OSes and brackets every Linux value → matched. These reconfirm the
long-standing "static config + `+0xb0` dynamic byte" result, now per-lane on a valid 4-lane control.

---

## Deliverable checklist (per brief)
- [x] Confirmed BAR0 base (`0x7FFF000000`) and PHY0 macro (`0x7FFF010000`, `0x1960`).
- [x] 3 full-region dumps across 3 rear-stream restarts, each with a genuinely-live rear preview
      (liveness evidence above; `PWR_STATE` + incrementing `TSC` in every burst).
- [x] Raw region delivered: `win-rear-phy0-{1,2,3}.bin` (+ `.txt` source) in project root.
- [x] Filled comparison table with all 3 Windows values beside the Linux column, divergences flagged.

## Recommendation for Linux-side work
1. **Identify `+0xb8` semantics** in `ipu6-isys-mcd-phy.c` — written config vs read-back status. This
   is the decisive question. If written: try forcing rear per-lane `+0xb8 = 0` on Linux. If
   read-only status: treat `0x10-0x13` as a per-lane error signature confirming physical-layer
   corruption, and keep looking upstream (PPI2CSI / PHY calibration input) for the cause.
2. Deprioritize `+0x11d` / `+0x152` per-lane differences — shared churn sets, not out-of-range.
3. Cross-reference with brief 6's finding: `PPI2CSI_CONFIG_INTF` bit 1 set on Windows / clear on
   Linux (both ports). Between that and `+0xb8`, the two concrete receiver-side Windows/Linux deltas
   found this session are worth testing together.
