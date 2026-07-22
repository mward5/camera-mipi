# Windows-agent brief: full rear PHY0 dump on a WORKING stream (dynamic-byte value compare)

**Read this first.** You're a Claude Code agent inside a Windows 11 To Go install on a
Dell XPS 13 9315 2-in-1. Disposable, admin fine, reconnaissance only (read data, don't
change system config beyond what a diagnostic tool needs). RWEverything should work (see
`windows-agent-findings-csi2-timing-2026-07-16.md` §1 for the `VulnerableDriverBlocklistEnable`
fix if `RwDrv.sys` won't load).

**Do this in the SAME session as `WINDOWS-AGENT-BRIEF-6-csi2-fe-registers.md`** — both need
a live rear-camera stream and the same IPU6 BAR0, so capture them back-to-back on one boot.

## Why (what's new vs brief 3)

Brief 3 (`windows-agent-findings-phy-trim-2026-07-16b.md`) dumped this same PHY0 region and
established which bytes are *dynamic* (change between two Camera opens) vs *static*. What it
never did — and what this brief does — is compare the **values** of the rear lane-group
bytes between **working Windows-rear** and **broken Linux-rear**, per lane. The 50 static
config registers were matched Linux-vs-Windows long ago; the ~6 dynamic per-lane bytes were
only ever compared Linux-rear-vs-Linux-*front* (an invalid control — the front camera is
2-lane and can't stand in for a 4-lane problem). This closes that gap.

## What to capture

The MCD-PHY0 macro is at **`BAR0 + 0x10000`**, length **`0x1960`** bytes (IPU6 BAR0: the
Intel IPU6 device, `8086:…`, Linux enumerates it at `0000:00:05.0`; find BAR0 base via
RWEverything → PCI → config offset `0x10`, mask low 4 bits — same as brief 6).

The region is power-gated: it reads all-`0xFFFFFFFF` until a stream has run. So:

1. Open the Windows **Camera** app, switch to the **rear** camera, get a live preview.
2. Dump the full `0x1960`-byte region to a file. **Repeat for 3 consecutive rear-stream
   restarts** (close Camera / reopen, or toggle front↔rear) so we capture the per-attempt
   churn range, not a single instant. Save as `win-rear-phy0-1.bin`, `-2.bin`, `-3.bin`
   (raw binary preferred; if only hex is available, a flat hex dump is fine).

RWEverything can save a memory range to file from the Memory view (or script
`Rw.exe /Command="Save <BAR0+0x10000> 0x1960 win-rear-phy0-N.bin" /Nogui`; verify the tool's
exact save syntax first). If binary save is awkward, dumping the region as hex to stdout and
redirecting to a `.txt` works too — we can parse either.

## The comparison target (so you can eyeball it on the spot)

These are the **Linux-rear (broken)** values at the per-lane dynamic-byte offsets, from
`scripts/decode-phy0-lanes.py reference/linux-phy0-live.bin`. Lane blocks are 0x200 apart;
the confirmed lane roles are D1/D0/**C0(clock)**/D2/D3. Read the same offsets in each
`win-rear-phy0-*.bin` and note where Windows lands:

```
block   lane     +0x01c +0x0b0 +0x0b2 +0x0b3 +0x0b8 +0x11d +0x152
0x0200  D1        0x03   0x0d   0x10   0xc8   0x12   0x21   0x60
0x0400  D0        0x03   0x09   0x10   0xc8   0x12   0x21   0x60
0x0600  C0(clk)   0x03   0x09   0x00   0xc8   0x10   0x21   0x11
0x0800  D2        0x03   0x0d   0x10   0xc8   0x12   0x27   0x00
0x0a00  D3        0x03   0x0d   0x10   0xc8   0x13   0x27   0x00
```

(For reference, brief 3 already saw Windows-rear churn `0x2B0` = block0 `+0xb0` over
{0x09,0x0d} and `0x352` = block0 `+0x152` over {0x60,0x40} — Linux-rear's 0x0d / 0x60 both
fell inside that range. This brief checks the *other* lanes/fields the same way.)

**The question:** across the 3 Windows-rear dumps, do any of the D0–D3 lane blocks hold
values **outside the range Linux-rear shows** — especially the rear-only upper pair **D2
(0x0800) / D3 (0x0a00)**? A lane where Windows consistently sits somewhere Linux never does
= a per-lane calibration/deskew result Linux isn't reaching, i.e. the missing software
lever. If every field is within Linux's range (just churning), the dynamic bytes are matched
too and the search moves elsewhere — a clean, useful negative either way.

## Deliverable

Write `windows-agent-findings-rear-phy0-dynamic-bytes-2026-07-XX.md` and drop the raw
`win-rear-phy0-{1,2,3}.bin` (or `.txt`) alongside it in the project root, so the full region
can be run through `scripts/decode-phy0-lanes.py` on the Linux side. In the findings note:
confirmed BAR0 base; whether each dump had a genuinely-live rear preview; and a filled copy
of the table above with the Windows values (all 3 restarts) beside the Linux column, flagging
any lane that lands outside Linux's range.
