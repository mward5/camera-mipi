# Windows-agent brief: read back the S5K3J1's actual PLL divider registers

**Read this first.** You're a Claude Code agent running natively inside a Windows 11 To
Go install on a Dell XPS 13 9315 2-in-1. Disposable, throwaway environment, admin rights
fine, same ground rules as prior sessions (scope is reconnaissance — read data, don't
change system config beyond what's needed to run a diagnostic tool). RWEverything should
already work this session (see `windows-agent-findings-csi2-timing-2026-07-16.md` §1 for
the `VulnerableDriverBlocklistEnable` fix if `RwDrv.sys` fails to load again).

You don't need the full history to do this task, but if you want it: `STATUS.md` in this
project's root is the canonical, continuously-updated investigation record. Short version
— a Samsung S5K3J1 rear camera produces a black screen on Linux, streaming and
frame-syncing correctly but with every packet inside every frame corrupted at the
CSI2/physical layer (header/CRC/DPHY-sync errors, FIFO overflow). Exhaustive comparison
against a genuinely-working Windows capture on this exact hardware has now matched, byte
for byte, every receiver-side (IPU6/ISYS/CSI2 controller) register we've found a way to
read: PHY calibration tables, CSI2 front-end config, hub access-grant registers, and ISYS
clock/power state are all identical between Linux and Windows, and between this sensor
and the front camera (which works fine on both OSes). The one thing never actually
confirmed is whether the **sensor itself** is running its internal PLL at the same
divider ratios on both OSes — everything checked so far has been receiver-side, not
sensor-side.

## The one open question

Linux's `s5k3j1.c` driver writes this exact register block to the sensor (I2C address
`0x10`) as part of PLL configuration, immediately after setting the external clock
register:

```
{0x0136, 0x1333},   /* EXTCLK frequency, 19.2 MHz */
{0x0300, 0x0007},   /* likely vt_pix_clk_div */
{0x0304, 0x0002},   /* likely pre_pll_clk_div */
{0x0306, 0x0095},   /* likely pll_multiplier */
{0x030c, 0x0000},
{0x030e, 0x0003},
{0x0310, 0x0109},
{0x0312, 0x0001},
```

These addresses follow the standard SMIA/CCS PLL-configuration layout (external clock →
pre-PLL divider → multiplier → output dividers), which sets the sensor's actual MIPI
output bit rate. Linux declares (via ACPI/driver config, not by reading the sensor) that
this works out to a 512MHz link frequency / 1024Mbps-per-lane data rate. **That figure has
never been independently confirmed — only assumed from the register values Linux itself
writes.** If Windows's driver programs different divider values (even while both sides
believe they're targeting "the same" nominal link frequency), the sensor could be
transmitting at a subtly different real bit rate than the IPU6 receiver is configured to
expect — which would produce exactly this symptom (frame sync survives, every packet's
payload/header is wrong) and would be completely invisible to every receiver-side
register comparison done so far, since the receiver would be internally self-consistent
on both OSes while the sensor's actual output differs.

## Task list, in priority order

1. **Open the Camera app, switch to the rear/world-facing camera, and get a live preview
   running** before doing anything else — same precondition as every prior session.

2. **Primary approach: RWEverything I2C spot-reads.** While the rear camera preview is
   genuinely running, use RWEverything's I2C/SMBus tool to read these exact register
   addresses back from the sensor at address `0x10`:
   - `0x0136`/`0x0137` (EXTCLK frequency — sanity check, should read back the same 19.2MHz
     Linux assumes)
   - `0x0300`/`0x0301`, `0x0304`/`0x0305`, `0x0306`/`0x0307` (the core PLL chain: pixel
     clock divider, pre-PLL divider, multiplier — the three values that most directly set
     the output bit rate)
   - `0x030c`/`0x030d`, `0x030e`/`0x030f`, `0x0310`/`0x0311`, `0x0312`/`0x0313` (secondary
     PLL/output-stage dividers)
   - These are 16-bit big-endian registers in Linux's own I2C access convention (see how
     `s5k3j1_write_reg()` in `s5k3j1.c` splits a `u16` register value into two byte writes,
     MSB first) — read both bytes of each and report the combined 16-bit value, not just
     one byte.
   - This is a much narrower ask than the previous I2C-capture session (brief 4) — you're
     reading a handful of specific, already-known register addresses back after the sensor
     is already streaming, not capturing an entire unknown write sequence. A working
     RWEverything I2C read of `0x10` is sufficient; you don't need ETW tracing or WinDbg for
     this unless the spot-reads come back looking wrong/inconsistent (e.g. all-zero or
     clearly unpowered) and you need to understand why.

3. **If spot-reads look inconsistent or the sensor doesn't respond at those addresses
   while previewing**: fall back to the same live I2C tracing approach used successfully
   in brief 4 (`logman query providers | findstr /i "spb i2c serial"`, then trace across a
   fresh stream-start) to capture the actual **write** sequence to these addresses, not
   just a post-hoc read. This also directly answers whether Windows writes these registers
   at all, or configures the PLL some other way (e.g. via firmware handoff, like the
   `mode_3976x2736_regs[]` question from brief 4).

## Reporting back

Write findings to a new file in this same folder, named
`windows-agent-findings-pll-divider-<today's-date>.md`. Include: the exact 16-bit value
read back from each register listed above, which method you used, and — if you got a real
write-sequence capture instead of just a static read — the order and any timing between
these specific register writes. A direct table (address → Linux's value → Windows's
value) is the most useful format. If any values differ from Linux's, that's the finding;
if they all match exactly, that's also a real, useful result — it would mean the sensor's
own PLL configuration is confirmed identical too, closing off the last receiver/sensor
register-level avenue and pointing the investigation toward something that isn't a
register at all (analog signal integrity, board/cable, or something firmware-mediated that
isn't visible to register reads on either OS).
