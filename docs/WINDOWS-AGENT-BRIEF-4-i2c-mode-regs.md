# Windows-agent brief: capture the real I2C register writes to the S5K3J1 sensor during streaming

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To
Go install on a Dell XPS 13 9315 2-in-1. Disposable, throwaway environment, admin rights
fine, same ground rules as the prior sessions (scope is reconnaissance — read data, don't
change system config beyond what's needed to run a diagnostic tool). RWEverything should
already work this session (see `windows-agent-findings-csi2-timing-2026-07-16.md` §1 for
the `VulnerableDriverBlocklistEnable` fix if `RwDrv.sys` fails to load again).

Read `windows-agent-findings-csi2-timing-2026-07-16.md` and
`windows-agent-findings-phy-trim-2026-07-16b.md` (same folder) before starting for the
full history of the PHY/CSI2 side of this investigation — this brief is about a
different, adjacent question.

## The one open question

Linux's `s5k3j1.c` writes a large, undocumented register table (`mode_3976x2736_regs[]`,
~577 entries, including a ~400-byte contiguous run around register `0x90c8` that looks
like actual ARM Cortex-M machine code being uploaded into the sensor's internal
processor) as part of configuring the sensor for its one supported streaming mode. This
table came from Intel's own validated `ipu6-drivers` package, not a local guess — but
**we could not find these bytes anywhere in the Windows sensor driver
(`s5k3j1sx04.sys`)**, in any form (checked exhaustively: raw byte match, byte-swapped,
address-only array, and every disassembled instruction's immediate operands — zero
matches, confirmed twice in separate sessions). That means Windows configures the sensor
through some mechanism this project hasn't found yet, and static analysis of the driver
binary has been fully exhausted for this question. We need a **live capture** of the
actual I2C traffic Windows sends to the sensor while it's genuinely streaming, to
directly compare against Linux's table.

**Related context you should know but isn't this session's main goal**: a separate
finding this same evening determined that Linux's actual IPU6 ISP firmware
(`/lib/firmware/intel/ipu/ipu6ep_fw.bin`, loaded via the kernel's CSE-authenticated
firmware path) is *not* fully identical to the firmware bundled in Dell's Windows driver
package — 5 of 7 internal firmware sub-components match by SHA-384 hash exactly, but the
2 largest (including one with a nonzero code entry point, i.e. real executable code, not
just data) differ, one of them by a full 4KB in size. It's plausible the sensor's
mode-config sequence is partly or wholly handled by this ISP firmware rather than by
literal I2C writes from host driver software at all — if so, this session's I2C capture
might come back showing *less* register traffic than Linux's driver sends, which would
itself be an important, informative result, not a failure of the capture.

## Task list, in priority order

1. **Open the Camera app, switch to the rear/world-facing camera, and get a live preview
   running** before doing anything else — same precondition as every prior session.

2. **Primary approach: Windows' built-in I2C/SPB ETW tracing.** Windows exposes I2C bus
   traffic through the Simple Peripheral Bus Class Extension (SpbCx) framework, which has
   its own ETW trace provider(s). Don't assume you know the exact provider name — query
   for it live:
   ```
   logman query providers | findstr /i "spb i2c serial"
   ```
   Once you've identified the right provider(s), start a trace (`logman start ... -p
   "<provider>" -ets` or `wpr -start` with a matching custom profile), open/reopen the
   rear camera preview so a fresh stream-start sequence occurs while tracing is active,
   then stop the trace and decode it (`tracerpt` or Windows Performance Analyzer, whichever
   is available/installable in this throwaway environment). Look specifically for I2C
   transactions addressed to `0x10` (the sensor's I2C address, confirmed from the Linux
   side) around the time the preview starts.

3. **If ETW tracing doesn't pan out: WinDbg kernel debugging**, breakpointing the I2C
   transfer entry point in the Intel Serial IO I2C driver stack (same category of
   technique as the 2026-07-13 VCM session's WDF tracing attempt, and the
   2026-07-16b session's explicit note that this is "a tractable but substantial
   reverse-engineering project on its own" if pursued via live tracing — reading
   `iaLPSS2_I2C` or equivalent driver statically in Ghidra to find the transfer function
   first, rather than live-tracing blind, is the more tractable path per that session's
   own conclusion). Treat as a real time investment, not a quick fallback.

4. **Lower-effort partial alternative: targeted RWEverything I2C spot-reads.** While the
   rear camera preview is running, use RWEverything's I2C/SMBus tool to read specific
   known register addresses from Linux's `mode_3976x2736_regs[]` table directly off the
   sensor at address `0x10` (e.g. start with `0x90c8`, `0x90ca`, `0x90cc`, a few more from
   early in the table) and record what comes back. This won't show the write *sequence*
   or timing, only final register state, and some of these registers may not be
   meaningfully readable back (write-only microcode upload targets, in particular) — but
   it's a fast sanity check that needs no new tooling, worth trying even alongside the
   ETW/WinDbg approaches rather than instead of them.

## Reporting back

Write findings to a new file in this same folder, named
`windows-agent-findings-i2c-mode-regs-<today's-date>.md`. Include: which method(s) you
tried and what worked or didn't, the raw captured I2C transaction data (addresses,
register offsets, values, and order if you got a real trace), and a direct comparison
against Linux's `mode_3976x2736_regs[]` (available in this project's
`drivers/s5k3j1/drivers/media/i2c/s5k3j1.c`, if you want to pull specific values to
check against — copy the relevant range into your findings doc rather than assuming
you have filesystem access back to the Linux side). If the capture shows *no* meaningful
I2C traffic to `0x90c8`-range addresses at all during a real, working stream, that's
itself the answer: it means this configuration lives in the ISP firmware, not in
host-driver I2C writes, and no further I2C-side investigation of this specific table is
worth pursuing.
