# RE follow-up (Ghidra, Linux side): locate the mode-config register table in memory

**Why the plan changed:** the original plan was a WinDbg breakpoint at `FUN_14000d1c8`
(RVA `0xD1C8`). But this WTG machine's kernel debugging is configured `debugtype=Local`, and
**local kernel debugging (`kd -kl`) is read-only — it cannot set breakpoints or control
execution** (breakpoints would need network KD to a second Windows machine). Local KD *can*
freely **read** live kernel memory, though. So instead of catching the writes in the act, we
read the **source register table** out of the live driver's memory while the camera streams.

Your earlier Ghidra pass found the player: **`FUN_140005028`** — "mode-config table player:
walks entries until `0xffff` sentinel, merges consecutive same-stride registers into bursts."
This note asks for what's needed to find and parse that table at runtime.

## Binary

Same file: `s5k3j1sx04.sys`, SHA256 `5BF53228C5B2067D50AAEE87B4F3EB9565E5B86EA754F2E280A19259478C519A`.

## What I need back (3 items)

### 1. Table-pointer source (the critical one)
Where does `FUN_140005028` get the pointer to the register table it walks? The table itself is
almost certainly a runtime heap/pool allocation (loaded from the `.aiqb`/`.cpf` tuning blob —
that's why brief-4 couldn't find it statically in the `.sys`), so I need the location of the
**pointer**, not a static address of the table. One of:
- **(a)** It's a function argument → trace up the callers until the pointer bottoms out, and
  report where: a **global variable (give its RVA)** — I'll read `dq base+RVA` live to get the
  runtime table address — or a **device-extension field (give the offset `+0xNNN`)** — I'll walk
  `DRIVER_OBJECT+0x08 → DEVICE_OBJECT`, `+0x40 → DeviceExtension` (as mapped on 2026-07-13) and
  read that field.
- **(b)** It reads a global pointer directly → give that global's **RVA**.
- **(c)** It reads a devext field directly → give the **offset**.

Bottom line: I need one concrete, live-readable location that holds the runtime table pointer.

### 2. In-memory entry layout (so I can parse the dump)
For one table entry *as it sits in memory* (not the on-wire form):
- byte offset + size of the **register address** field, and of the **value** field;
- **endianness** — native little-endian `u16`, or raw MSB-first wire bytes?
- how the per-entry **width/stride** is encoded (your note said it merges "same-stride"
  registers, so each entry likely carries a value-width or length field — where/how big?);
- the exact **sentinel** (is `0xffff` a whole terminator entry, or just the reg field?);
- **entry size** — fixed-size records, or variable-length?

### 3. Confirm the PLL regs live in this table
Do `0x0136` (EXTCLK) and `0x0300`–`0x0312` (the PLL block from `WINDOWS-AGENT-BRIEF-5`) appear
in the table `FUN_140005028` plays, or in a separate earlier init sequence? If separate, give
the pointer source for that other table too (same as item 1).

## Optional fallback (only if the pointer chase is messy)
If items 1–2 are awkward to pin down, an alternative: give me a **distinctive in-memory anchor
byte-pattern** that must appear in the table — e.g. the encoding of `0x0136 = 0x1333`, or the
first several bytes of the ~400-byte `0x90c8` microcode run — **in whatever byte order the
in-memory table uses**. Local KD has a memory-search command (`s`); with a unique anchor I can
scan the driver's pool allocations and find the table without the pointer chase. (Pointer
chase is preferred/more reliable; this is just a backstop.)

## Then (Windows side, single machine, no reboot beyond getting back here)
Camera streaming → I attach `kd -kl`, resolve the live base via `!drvobj s5k3j1sx04 2`, follow
item 1 to the runtime table pointer, dump the table, and parse out `0x0136` + `0x0300`–`0x0312`
using item 2 — filling in the Windows column of the PLL comparison table. Pure reads, no halts,
no boot-disk risk.
