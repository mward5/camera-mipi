# Windows-agent findings — MCD-PHY trim-field dynamics — 2026-07-16 (session 2)

Session goal (per `WINDOWS-AGENT-BRIEF-3-phy-trim-fields.md`): determine whether the PHY0 config-table register fields that disagree with Linux's hardcoded `x4_port0_config_regs[]` table (found in the prior 2026-07-16 session) are (1) fixed per-die trim that Linux's `writel()` would clobber, or (2) genuine per-session config that Windows computes dynamically.

**Bottom line: it's neither pure hypothesis cleanly — the outcome is the brief's own "most informative" branch: step 2 differs from step 3.** A small, specific set of byte offsets change value between two consecutive Camera-app opens within the *same boot*, while the rest of the ~6.5KB register block stays completely stable. That rules out "these are static values Linux's write would harmlessly overwrite with an equally-valid constant" and rules out "these are read-only calibration data Windows itself never touches" — something is actively rewriting a handful of specific fields every time the stream (re)starts.

**Correction to a claim made in the previous chat session**: I told the user offsets like `0x2B0` looked like stable per-instance e-fuse trim, because they matched exactly between two different boots' first-camera-open reads. That comparison was too small a sample — this session's step 2 vs step 3 (same boot) shows `0x2B0` actually changes value on every stream restart. It is not static trim. Treat that earlier read as superseded by this session's data.

## 1. Method

Three dumps of the same `0x1960`-byte PHY0 block (`BAR0+0x10000` = `0x7FFF010000`), all via `RWEverything`'s `DMEM` command, same technique as before:

1. **Fresh boot, before any camera app opened this session.** Confirmed via `(Get-Date) - LastBootUpTime` = ~2.7 minutes, no `Camera` process running.
2. **After opening Camera app, switching to rear camera, confirming live preview.**
3. **After closing and reopening the Camera app a second time**, same boot as step 2 (no reboot in between).

## 2. Step 1 (fresh boot, pre-camera): entire block is `0xFFFFFFFF`

Every single byte across all `0x1960` bytes reads `0xFFFFFFFF` — including the offsets (`0x280`, `0x480`, `0x680`, `0x880`, `0xA80` lane-groups) that show real structured data once the camera has streamed. This is a stronger, cleaner result than expected: the entire MCD-PHY macro instance is power-gated/unmapped until its power-up sequence runs at least once — nothing here is boot-time-resident fuse data readable independent of the stream lifecycle. This already argues against hypothesis 1 in its simplest form (passively-readable factory trim).

## 3. Step 2 vs Step 3 (same boot, camera closed and reopened): six bytes change, everything else is identical

Full diff, every byte that differs between the two dumps (all other ~6,490 bytes are byte-for-byte identical):

| Offset (rel. to `BAR0+0x10000`) | Step 2 (1st open) | Step 3 (2nd open) | Location |
|---|---|---|---|
| `0x028` | `0x19` | `0x18` | Header/common-init region (before the per-lane config tables even start) |
| `0x2B0` | `0x09` | `0x0D` | Inside the `0x280` lane-group's tail block |
| `0x352` | `0x60` | `0x40` | Inside the `0x280` lane-group's tail block (a few bytes past `0x340`, which itself is byte-identical to Linux's hardcoded value both times) |
| `0x1162`–`0x1163` | `01 04` | `02 08` | Inside a lane-group tail in the *second* full repeat of the pattern (starting ~`0x1080`) |
| `0x1362`–`0x1363` | `01 04` | `02 08` | Same relative position, next lane-group in the second repeat |
| `0x1562`–`0x1563` | `00 00` | `10 7C` | Same relative position, next lane-group in the second repeat |

Notes on the pattern:
- The `01 04`→`02 08` flip at two different lane-groups (`0x1162`, `0x1362`) happening identically and simultaneously suggests a shared counter or shared state bit, not independent per-lane randomness.
- `0x762` (the same relative position in the *first* repeat's corresponding lane-group) holds `10 7C` in **both** step 2 and step 3 — stable — while the *analogous* position in the second repeat (`0x1562`) went from `00 00` to `10 7C`. So this isn't a value "moving" from one slot to another; it's more consistent with a small set of lane-groups independently getting touched/updated on each stream restart, with which one(s) get touched not being the same every time.
- All five `0x280`/`0x480`/`0x680`/`0x880`/`0xA80` lane-group **header** fields (the ones compared against Linux's table in the prior session, e.g. `0x280`, `0x290`, `0x294`, `0x2A8`, `0x300`, `0x310`, `0x338`, `0x33C`, `0x340`, `0x374`) were **all** stable across step 2 and step 3 — none of the offsets that matched or partially-matched Linux's hardcoded table changed between opens. Only a few bytes just past each header block moved.

## 4. What this means for the two hypotheses

Neither hypothesis is a clean fit:

- **Not pure hypothesis 1** (static per-die trim): step 1 proves nothing is readable until first power-up (rules out "always-resident fuse data"), and step 2 vs step 3 proves at least 6 specific bytes are rewritten on every stream restart within a single boot (rules out "write-once-then-static-forever" too).
- **Not clean hypothesis 2 either** (deterministic protocol config from negotiated link parameters): if it were a straightforward recomputation from stable inputs (same sensor, same mode, same lane count, same link frequency — nothing about the negotiated stream parameters changed between the two opens), you'd expect either identical output both times (if deterministic) or a fully different pattern (if genuinely re-negotiated) — not a *partial*, small, specific set of bytes changing while the bulk of the block (including the exact fields being compared against Linux's table) stays fixed.

**Most likely explanation**: these specific moving bytes are runtime/calibration state — plausibly something like an eye-training retry count, a per-attempt calibration index, or an internal state-machine slot/sequence value that the PHY's power-up firmware routine updates each time it re-runs the training sequence, rather than either "the config value itself" or "burned-in trim." The **actual protocol-relevant config fields** (the ones from the prior session's Linux-table comparison) look genuinely stable across stream restarts within a boot — which is good news for a future fix attempt: it means those specific fields are safe to treat as "this boot's real configured value" without worrying they're mid-negotiation noise, at least for the header/`0x2xx-0x3xx`-style offsets within each lane group.

## 5. WinDbg write-breakpoint — not attempted, and why

The brief's suggested "most decisive" test — catching a `writel()` to these addresses in the act via a hardware breakpoint — was not pursued this session. x86/x64 hardware data breakpoints (`ba` in WinDbg, backed by `DR0`–`DR3`) trap on **virtual/linear addresses**, not physical ones. Setting an effective breakpoint on this MMIO region requires first knowing the kernel-mode virtual address `iaisp64.sys` mapped this BAR to (the pointer `MmMapIoSpace()` or equivalent returned internally to the driver) — that's undocumented driver-internal state, the same category of problem the 2026-07-13 VCM session explicitly concluded was "a tractable but substantial reverse-engineering project on its own, not a quick follow-up" after ~6 layers of WDF tracing still hadn't reached vendor code. Given the register-diff evidence above already answers the brief's core question cleanly (outcome: "step 2 differs from step 3"), that deeper RE effort didn't seem justified this session. If a future session wants to pursue it anyway: loading `iaisp64.sys` into Ghidra/IDA offline (not live tracing) to find the `MmMapIoSpace` call site and its stored result would be the more tractable path, per the same recommendation from the earlier VCM session.

## 6. Recommendation for the Linux-side fix

Given §4, a blind `writel()` of Linux's static table (the current mainline approach) is likely **wrong in two different ways simultaneously**:
1. For the handful of bytes shown to be dynamic runtime state (§3): writing a fixed constant there is almost certainly meaningless or harmful — these look like they should be left alone (read-modify-write, or not touched at all, letting the PHY's own internal sequencing handle them) rather than overwritten with any static value at all, Linux's or otherwise.
2. For the fields that differ from Linux's table but stay stable across restarts (the majority of the mismatches found in the prior session, e.g. `0x280`, `0x294`, `0x2A8`, `0x338`, `0x33C`): these look like genuine per-board/per-die configuration Windows is using correctly, that Linux's generic upstream table simply has wrong for this specific module/board combination.

A future session should try to separate these two categories precisely (only about 6 bytes fall in category 1; everything else in category 2) and produce a corrected static table for category 2 fields specifically, while leaving category 1 offsets out of any Linux-side `writel()` entirely.
