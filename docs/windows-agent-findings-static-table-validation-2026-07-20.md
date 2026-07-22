# Findings: static mode-table validation + WinDbg local-KD tooling diagnosis — 2026-07-20

Follow-up to `ghidra-findings-s5k3j1-mode-table-pointer.md`. Goal: validate the parsing
method against the live driver before trusting it for anything else, using local KD.

## 1. Static table validated — full match against Ghidra's decode

Read `base+0x25410` (16 entries, `db` L0x100) from the live, loaded `s5k3j1sx04.sys` on a
genuinely fresh boot. Result:

| Index | Width | Addr | Value | Note |
|---|---|---|---|---|
| 0 | 2 | `0x0001` | `0x0100` | |
| 1 | 2 | `0x2860` | `0x4000` | |
| 2 | 2 | `0x0000` | `0x0000` | |
| 3 | 2 | `0x0000` | `0x30a1` | |
| 4 | 2 | `0xfcfc` | `0x4000` | matches Ghidra exactly |
| 5 | 2 | `0x1060` | `0x0001` | |
| 6 | **32** | `0x0000` | `0x0003` | the width=32 control/delay pseudo-entry Ghidra predicted |
| 7 | 2 | `0x0060` | `0x0005` | |
| 8 | 2 | `0xfcfc` | `0x4000` | matches Ghidra exactly |
| 9 | 2 | `0x6214` | `0x7971` | |
| 10 | 2 | `0x6218` | `0x7150` | |
| 11 | 2 | `0x2860` | `0x2000` | |
| 12 | 2 | `0xfcfc` | **`0x2000`** | address matches, **value does not** — see correction below |
| 13-15 | 2 | `0x90c8`/`ca`/`cc` | `0x0000` | start of the ~400-byte microcode-looking region from brief 4 |

**Method fully confirmed**: 16-byte fixed records, width (u32 LE) at +0, register address
(raw MSB-first bytes) at +4, value (u32 LE) at +8, unused padding at +6 and +12. The
width=32 pseudo-entry, its position near the top of the table, and the start of the
`0x90c8` region all line up exactly with the prior Ghidra pass.

**Correction to `ghidra-findings-s5k3j1-mode-table-pointer.md`**: that doc states
`{width=2, addr=0xfcfc, value=0x4000}` "appears at index 4 (and again at 8, 12)." Index 4
and 8 do match exactly. **Index 12 has the same address (`0xfcfc`) but a different value
(`0x2000`, not `0x4000`)** — minor, doesn't affect the layout conclusions, but worth
knowing if anyone diffs against that document directly. Most likely explanation: a
progressive multi-stage write to the same register, not a documentation error in the
table's actual content.

## 2. Driver base address via psapi.dll — reusable technique, no KD needed

`!drvobj` (and any other extension command) is unreliable this session for reasons in §3.
Found a clean workaround for the one thing it was being used for here — getting a loaded
driver's image base — that needs **no kernel debugger at all**:

```powershell
Add-Type -Namespace Psapi -Name Native -MemberDefinition @'
[DllImport("psapi.dll", SetLastError=true)]
public static extern bool EnumDeviceDrivers([Out] IntPtr[] lpImageBase, uint cb, out uint lpcbNeeded);
[DllImport("psapi.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern uint GetDeviceDriverBaseName(IntPtr ImageBase, System.Text.StringBuilder lpFilename, uint nSize);
'@
$need = 0
[Psapi.Native]::EnumDeviceDrivers($null, 0, [ref]$need) | Out-Null
$bases = New-Object IntPtr[] ([int]($need / 8))
[Psapi.Native]::EnumDeviceDrivers($bases, $need, [ref]$need) | Out-Null
foreach ($b in $bases) {
    $sb = New-Object System.Text.StringBuilder 260
    [Psapi.Native]::GetDeviceDriverBaseName($b, $sb, 260) | Out-Null
    if ($sb.ToString() -match 's5k3j1sx04') { "$($sb.ToString())  0x$($b.ToString('X'))" }
}
```

Instant, reliable, works from an unelevated-adjacent PowerShell session (admin needed for
psapi driver enumeration in general, which this session already has). Use this instead of
`!drvobj`/`lm` for driver-base lookups going forward — only need KD for the actual memory
*read* once you have the address.

## 3. Local KD tooling bug — diagnosed, not fixed

This machine's local KD (`kd.exe -kl`, DbgX-based WinDbg 10.0.29617.1000, `winget`-installed)
has a real, reproducible problem: **anything beyond a literal-address memory read hangs
indefinitely** (confirmed safe to interrupt — never froze the whole machine, only the
`kd.exe` client process; each hang was recovered by timeout + fresh reconnect, no reboot
needed once this was understood). Bisected across ~8 attempts this session:

| Command class | Result |
|---|---|
| `dq <literal hex address>` | **Works, every time, instantly** |
| `db <literal hex address>` | **Works, every time, instantly** |
| `? <pure arithmetic, e.g. 1+1>` | **Works, instantly** — expression evaluator itself is healthy |
| `!drvobj <name> 2` | Hangs, regardless of `.sympath` (tried default `srv*`, empty local-only cache, and the real populated cache from 2026-07-13 — all three hang; only a *nonexistent* cache path failed fast with a clean type-info error instead of hanging) |
| `r $t0 = poi(<addr>); ? @$t0` | Hangs |
| `.for (...) { du poi(@$t0+...) ... }` | Hangs |

Conclusion: the failure is specific to **`poi()`, pseudo-register state, or extension-DLL
invocation** — not the debugger connection, not literal memory access, not the expression
evaluator in general. Root cause not further isolated (would need testing `poi()` alone vs.
pseudo-registers alone, not done this session). Confirmed **not fixed by rebooting** —
tested fresh on a clean boot, same failures.

**Practical implication for future sessions**: stick to literal-address `db`/`dq` only.
Anywhere a pointer chase is needed (following a struct field to another address), do it as
multiple separate `kd.exe` invocations, computing each next address by hand between calls,
rather than a single scripted command using `poi()`/pseudo-registers/`.for`. Slower, but
proven 100% reliable today across many consecutive calls. Always wrap with a shell-level
`timeout` (15-20s) and check machine responsiveness (e.g. `Get-Date` in a fresh PowerShell
call) immediately after any command that might hang — every hang this session left the rest
of the machine fully responsive, confirming the risk is contained to the `kd.exe` client.

## 4. Where this leaves the PLL divider question (brief 5)

The `ctx+0x1f38` pointer chain from `ghidra-findings-s5k3j1-mode-table-pointer.md` was for
the **mode table** (resolution/fps/etc config) — which §1 above confirms is fully static
and now validated. It was never going to lead to the PLL registers: those are separately
confirmed **absent from every static table in the file** (per that same doc's item 3), i.e.
genuinely sourced elsewhere at runtime (the `.aiqb`/`.cpf` tuning blob).

Two remaining paths, neither attempted yet:
1. **Fresh Ghidra pass** (Linux side) targeting the `.aiqb` blob's parse/load function —
   explicitly flagged in the prior findings doc as "a larger, separate task not started."
   Would give a real pointer chain to the runtime PLL data, usable with today's proven
   literal-address `db` technique (no need for `poi()`/pseudo-registers even then — just
   more manual round-trips).
2. **Live memory search** for a distinctive byte pattern (e.g. the `0x0136` register
   encoding) using WinDbg's `s` (search) command — untested whether `s` is in the
   safe (literal-args) category or the broken (extension/expression) category; worth a
   single cheap test before relying on it. Needs a bounded search range to be practical/safe
   — not yet identified.

Static-table validation (this session's actual goal) is complete and successful. The PLL
question from brief 5 remains open, blocked on one of the two paths above rather than on
today's tooling issue specifically.
