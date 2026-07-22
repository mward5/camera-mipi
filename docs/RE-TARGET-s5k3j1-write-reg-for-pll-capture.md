# RE target for Ghidra (Linux side): find the S5K3J1 register-write function

**Why:** To capture the actual PLL divider *values* Windows writes to the sensor (the open
item from `windows-agent-findings-pll-divider-2026-07-20.md`), the plan is a live WinDbg
breakpoint on the Windows side. The ETW trace confirmed *that* Windows writes ~619 registers
to the sensor at `0x10` but does not expose the payload bytes. A breakpoint on the sensor
driver's own write-register function gives the `(register, value)` directly. This note is
what to find in Ghidra so the Windows-side breakpoint can be set on the next boot.

## Binary to analyze

- `s5k3j1sx04.sys` — on this same shared folder (`.../Documents/`).
- Size **208,968 bytes**, **SHA256 `5BF53228C5B2067D50AAEE87B4F3EB9565E5B86EA754F2E280A19259478C519A`**
  (confirm you're analyzing this exact file — it's the copy pulled from the live DriverStore
  on 2026-07-13; matches the currently-installed driver).

## Landmarks already known (from the 2026-07-13 live-KD session)

These are RVAs (offsets from module base) already mapped in this same binary — use them to
orient / cross-check that Ghidra's rebasing lines up:

| Item | RVA |
|---|---|
| `DispatchDeviceControl` handler | `base + 0x180B0` |
| `FxObject` vtable | `base + 0xB3828` |
| `IRP_MJ_*` byte-index table | `base + 0xBAAD4` |
| `IRP_MJ_*` dword rel-offset table | `base + 0xBAAC0` |

The register-write path is reached (indirectly) from the device-control dispatch, so
`DispatchDeviceControl` at `base+0x180B0` is a reasonable starting point to trace downward.

## What to find

The function that writes one sensor register over I2C — i.e. the Windows equivalent of Linux's
`s5k3j1_write_reg(reg, val)`. Anchors to locate it:

1. **String xref:** search for `Hardware Prepare: I2C%d function %d, addr 0x%x` (seen in this
   driver's strings, near I2C code) and follow its xrefs.
2. **Buffer shape:** the function builds a small buffer **MSB-first** — reg high byte, reg low
   byte, then value byte(s) — matching the SMIA/CCS format. The ETW capture showed the writes
   are 4-byte (16-bit reg + 16-bit val), 3-byte (16-bit reg + 8-bit val), and burst variants.
3. **Submit path:** it hands that buffer to the SPB/I2C target — look for `SpbXxx` DDI calls or
   `WdfIoTargetSendWriteSynchronously` / an `IOCTL_SPB_*` sequence submit. The write-reg
   wrapper sits just above that submit.

## What I need back (either form works — pick whichever is cleaner in the decompiler)

**Option A — function entry (cleanest if arg layout is clear):**
- RVA of the write-register function's entry.
- Which x64 argument is the **register** and which is the **value**, and their widths.
  (x64 fastcall: 1st–4th integer args = `rcx, rdx, r8, r9`. If the signature is
  `write(ctx, reg, val)` then `rdx`=reg, `r8`=val — but confirm from the decompiler.)

**Option B — the buffer-assembly point (most robust; captures 16-bit, 8-bit, AND burst writes
uniformly):**
- RVA of the instruction right where a pointer to the fully-assembled I2C buffer is live in a
  register, plus which register holds the pointer and where the length is.
  Then on Windows I just `db <reg> L<len>` at that point and get every write regardless of size.

Either way, **give me RVAs (offset from image base), not absolute addresses** — they're
boot-invariant. On the Windows side I re-derive the live load base each boot via `!drvobj
s5k3j1sx04 2` and break at `base + RVA`.

## After you have it

Drop the RVA(s) into a file on this shared folder (or just tell me in chat), reboot to Windows,
and I'll: attach local KD, resolve the live base, set an auto-continuing breakpoint
(`bp base+RVA "db/r …; g"` — auto-continue so each hit halts only microseconds, safe for the
USB boot disk), then have you start a rear-camera stream so the PLL-config writes fire. I'll
decode the `0x0136` / `0x0300`–`0x0312` values and fill in the Windows column of the comparison
table.
