# Windows-agent brief: are the MCD-PHY per-lane register fields fixed trim or driver-written config?

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To
Go install on a Dell XPS 13 9315 2-in-1. Disposable, throwaway environment, admin rights
fine, same ground rules as the prior sessions (scope is reconnaissance — read data, don't
change system config beyond what's needed to run a diagnostic tool). RWEverything should
already work this session — the 2026-07-16 session found and fixed the actual blocker
(`VulnerableDriverBlocklistEnable` registry value, set to `0`, left disabled by design —
see `windows-agent-findings-csi2-timing-2026-07-16.md` §1 if `RwDrv.sys` mysteriously
fails to load again).

Read `windows-agent-findings-csi2-timing-2026-07-16.md` (same folder) in full before
starting — it has the exact register addresses, the raw hex dump, and the reasoning that
led to this session's question. This brief only makes sense in that context.

## The one open question

That prior session found Linux's static `x4_port0_config_regs[]` table (in
`ipu6-isys-mcd-phy.c`) and the live values it read off real hardware while Windows
streamed the rear camera **disagree on 44 of 50 registers** — but not randomly: many
differences are concentrated in specific bytes (often the top byte of a 32-bit register,
sometimes a whole middle byte), while other bytes/nibbles match exactly. That pattern is
consistent with two very different explanations, and **we need to know which one is
real** before anyone touches the register-write code:

1. **These are per-die factory calibration/trim fields** (e.g. burned into e-fuses at
   manufacturing time) that legitimately differ from board to board — in which case
   Linux's blind 32-bit `writel()` of a fixed table value is actively **clobbering** the
   correct per-die trim with a generic constant, and the real fix is a
   read-modify-write that only touches the actual protocol-config bits and leaves
   whatever's already in the register alone.
2. **These are genuine protocol configuration values Windows's own driver computes and
   writes differently** (e.g. based on the real negotiated link parameters) — in which
   case the fix is figuring out Windows's actual computation and matching it.

## The test that distinguishes them

**Read the same 50 register addresses (from the prior findings doc's §6 raw hex dump,
PHY0 base `BAR0+0x10000`) at three points in time, without changing anything else:**

1. **Immediately after a fresh boot, before opening any camera app at all this
   session.** This captures whatever's in these registers purely from hardware
   power-on/reset defaults and any early firmware/BIOS init — before Windows's own
   camera driver has done anything.
2. **After opening the Camera app, switching to the rear camera, and confirming a live
   preview** (same precondition as both prior sessions).
3. **After closing the Camera app and reopening it a second time** (confirms whether
   values are freshly (re)computed on every stream start, or set once and left alone).

**If all three reads are byte-for-byte identical**: these fields are fixed hardware
defaults nothing ever writes — strong evidence for hypothesis 1 above (per-die trim,
Linux's write is likely clobbering it).

**If step 1 differs from steps 2/3, but 2 and 3 match each other**: the camera driver
writes these once per stream-start with a stable, reproducible value — could go either
way, but leans toward hypothesis 2 (a real computed config, consistently reproduced).

**If step 2 differs from step 3** (values change between two consecutive opens): that's
the most informative outcome of all — proves these are computed fresh each time
from something dynamic (a real per-session negotiation), which would mean Linux's
static-table approach is fundamentally the wrong model regardless of trim-vs-config,
and the actual computation needs to be found (check whether a WinDbg breakpoint on
writes to this address range is feasible, per the prior brief's fallback approach, to
catch the driver in the act rather than just diffing before/after snapshots).

## Reporting back

Write findings to a new file in this same folder, named
`windows-agent-findings-phy-trim-<today's-date>.md`. Include: the three raw register
dumps (or just the deltas between them, if that's more legible — but keep the full raw
data available since precision matters here), which of the three outcomes above matches,
and your best reasoning about what that implies. If you find any way to determine
*whether* Windows's own driver code path even issues a write to these specific addresses
at all (vs. only ever reading them) — via WinDbg, ETW, or anything else — that's the
single most decisive thing you could bring back, more valuable than more register
snapshots.
