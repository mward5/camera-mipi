# RE target for Ghidra (Linux side): find where the S5K3J1's PLL/EXTCLK register values actually come from

**Why:** `WINDOWS-AGENT-BRIEF-5-pll-divider-regs.md` asked for the sensor's real PLL divider
values. `ghidra-findings-s5k3j1-mode-table-pointer.md` found and fully decoded the static
mode-config table (`FUN_140005028`, table RVA `0x25410`) — **confirmed correct today via
live memory read, entry-for-entry** (see `windows-agent-findings-static-table-validation-2026-07-20.md`
if you want the detail) — but that same doc also confirmed the PLL/EXTCLK registers
(`0x0136`, `0x0300`, `0x0304`, `0x0306`, `0x030c`, `0x030e`, `0x0310`, `0x0312`) are **not
in that table, and not anywhere static in the file at all** (full-binary byte-pattern scan,
zero matches). So they're written by some other code path, sourced from something
runtime/parsed (the `.aiqb`/`.cpf` tuning blob is the leading theory) — and that other code
path hasn't been found yet. That's this brief's job.

## Hard constraint — read this before starting

Today's session diagnosed a **real, reproducible bug** in this machine's local WinDbg
(`kd.exe -kl`, 10.0.29617.1000): `poi()`, pseudo-registers (`$t0`), and **extension
commands including `!drvobj`/`!object`** all hang indefinitely. Confirmed **not** a
one-off — reproduced fresh after a reboot too. The only things that work reliably: literal
`db <hex address>`, `dq <hex address>`, and pure-arithmetic `?` (no memory access).

Practical effect: **I cannot look up a `DEVICE_OBJECT`, walk to a device extension, or do
any live pointer-chase that starts from `\Driver\s5k3j1sx04` as a named kernel object.**
I *can* get the driver's static image base for free from plain PowerShell (no KD needed —
`psapi.dll`'s `EnumDeviceDrivers`), and I *can* read any address I can compute as
`image_base + <fixed offset>` via one literal `db`/`dq` call each. Multi-hop chases are
fine as long as every hop is `db <literal address>` → read a pointer value → compute the
next literal address by hand → repeat. What's **not** usable: anything requiring `!drvobj`,
`!object`, `poi()`, or a device-extension pointer whose ultimate source is a runtime
`DEVICE_OBJECT` I have no way to locate.

**So: please prioritize finding an answer that's reachable via a static/global pointer
chain (image-base-relative, like the mode table's root pointers turned out to be), over
one that's only reachable via the WDF device extension.** If the real answer genuinely
requires the device extension with no static alternative, still report the chain — it may
be usable with different tooling later — but flag it clearly as "needs DEVICE_OBJECT,
not capturable with current method" so I don't waste a session trying.

## Binary

Same file: `s5k3j1sx04.sys`, SHA256 `5BF53228C5B2067D50AAEE87B4F3EB9565E5B86EA754F2E280A19259478C519A`.

## What to find

1. **The function(s) that issue the actual I2C writes for `0x0136` and the `0x0300`-`0x0312`
   block.** These are 4-byte writes (16-bit reg + 16-bit value) per the ETW capture from
   `windows-agent-findings-pll-divider-2026-07-20.md` — confirmed present, early in the
   stream-start write sequence, right where PLL config belongs (immediately after EXTCLK,
   SMIA/CCS convention). Since `FUN_140005028` (the generic table player) doesn't contain
   these addresses, this is a **different call site** — possibly still calling the same
   low-level write primitive (`FUN_14000d1c8` from `ghidra-findings-s5k3j1-write-reg-rva.md`,
   RVA `0xD1C8`) but with a **different, not-yet-found caller** feeding it these specific
   register/value pairs, or a hardcoded sequence of individual `write_reg(reg, val)`-style
   calls rather than a table walk at all.
   - Good starting point: look for xrefs to `FUN_14000d1c8` (RVA `0xD1C8`) other than the
     already-known `FUN_14000c604`/`FUN_140005028` chain — a second caller is the most
     likely shape of the answer.
   - If no second caller exists, the PLL writes may go through a *different* low-level I2C
     primitive entirely (recall `FUN_14000cf48`/`FUN_14000cb0c` were separately identified
     as the *VCM* read/write primitives, not sensor mode-config — worth ruling out whether
     PLL writes reuse one of those instead, or a third primitive not yet catalogued).

2. **Trace where the VALUES come from**, once you find the call site(s). For each of the 8
   registers, is the value:
   - a **literal constant in the disassembly** (i.e. hardcoded, not `.aiqb`-sourced after
     all — would mean it's static somewhere, just not in the table-shaped format the last
     pass searched for; worth a quick check even though brief 4/5's working theory was
     runtime-sourced)? If so — great, just report the constant, no live capture needed at
     all for that register.
   - or a **read from memory at some computed address** — if so, trace that address's
     origin. Is it:
     - `driver_image_base + <fixed RVA>` (a plain global) — **ideal answer**, directly
       usable.
     - `ctx + <fixed offset>` where `ctx` is the device-extension pointer passed into the
       function (WDF convention, same pattern as the mode-table's `ctx+0x1f38`) — usable
       only if `ctx` itself is *also* reachable from a static global somewhere (some
       drivers keep a single static "the one device instance" pointer for convenience,
       especially plausible here since there's only ever one rear-camera instance on this
       machine — worth explicitly checking for this before concluding it's a dead end).
       If `ctx` truly only comes from the WDF framework at runtime with no static shortcut,
       report the offset anyway but flag it per the constraint above.

3. **If the values trace back to a parsed blob/struct** (rather than a plain global), find:
   - where that struct's pointer is stored (global vs. `ctx`-relative, same question as
     above),
   - the struct's layout for these 8 fields specifically (offsets, sizes, byte order — same
     level of detail as the mode-table entry layout from the last pass), so the capture can
     be parsed once read.

## Fallback (if no pointer chain is findable at all)

A live memory **search** for a byte-pattern anchor remains an option — `s` (WinDbg's search
command) wasn't tested this session for whether it falls in the "safe" (literal args) or
"broken" (extension/expression) category, so it's untested territory, not a known-good
fallback. If the pointer-chain investigation above comes up empty, it'd help to have: the
exact byte encoding the *actual* PLL write function uses for these registers (may not be
the same 16-byte record shape as the mode table, since this is confirmed to be a different
code path) — so a search pattern can be constructed precisely rather than guessed.

## Reporting back

Same pattern as before: `ghidra-findings-s5k3j1-pll-source.md` (or similar name) in this
folder. Please explicitly label whichever answer you find as either "static, image-relative
— directly usable" or "needs DEVICE_OBJECT/device-extension — not capturable with current
tooling" so I don't waste a session on something today's constraint rules out.
