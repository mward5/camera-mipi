# Procedure #6 — is SOF a genuine physical-layer signal, or firmware-synthesized?

**Item #6 from the 2026-07-17 fresh-eyes review.** Linux-side only, no Windows round-trip.
The cheapest stage needs *no code change* — it reads information the stock driver already
logs.

## Why this matters

IPU6 frame-start (SOF) events are delivered by the ISYS firmware, not directly by the
CSI2 receiver hardware. If the CSI-2 **frame-start/frame-end short packets** on the wire
are themselves corrupt, but firmware emits SOF anyway (synthesized/recovered), then the
corruption is **pure physical-layer** and *data-type-agnostic*. That outcome:

- **validates** focusing on the PHY/lane/clock items (#2 clock mode, #3 lane deskew,
  #5 lane order/polarity), and
- **deprioritizes** #7 (VC/DT / embedded-data-line mismatch), which is a data-layer
  hypothesis that can't be the cause if even the short packets are corrupt.

## The 20 CSI2 receiver error bits

The error IRQ status register (`csi2->base + CSI_PORT_REG_BASE_IRQ_CSI + STATUS`, mask
`GENMASK(19,0)`) has one bit per error. Bit index == array index in `dphy_rx_errors[]`
([ipu6-isys-csi2.c:61](../drivers/ipu6-isys/ipu6-isys-csi2.c:61)). The stock driver
already prints each set bit **by name** in `ipu6_isys_csi2_error()`
([csi2.c:224-228](../drivers/ipu6-isys/ipu6-isys-csi2.c:224)), so you can read the bit map
straight out of dmesg:

```
bit  error string                                  meaning for this investigation
 0   Single packet header error corrected          ECC fixed a header bit flip
 1   Multiple packet header errors detected        header uncorrectable
 2   Payload checksum (CRC) error                  long-packet PAYLOAD corrupt
 3   Transfer FIFO overflow
 4   Reserved short packet data type detected
 5   Reserved long packet data type detected
 6   Incomplete long packet detected
 7   Frame sync error            *** FS/FE SHORT-PACKET integrity — the key bit for #6
 8   Line sync error             *** LS short-packet integrity
 9   DPHY recoverable synchronization error        PHY re-synced mid-stream
10   DPHY fatal error                              PHY lost sync unrecoverably
11   DPHY elastic FIFO overflow
12   Inter-frame short packet discarded
13   Inter-frame long packet discarded
14   MIPI pktgen overflow
15   MIPI pktgen data loss
16   FIFO overflow
17   Lane deskew                 *** direct lane-deskew failure — ties to #3
18   SOT sync error              *** HS-entry / start-of-transmission sync — ties to #2
19   HSIDLE detected
```

## Stage 1 — enumerate the bits that actually fire (no code change)

Custom modules must be installed (`install-custom-modules.sh`; per STATUS they may have
been removed). Then:

```bash
sudo dmesg -C                          # clear

# Select the REAR camera explicitly. `cam --capture` with no -c grabs the FIRST
# camera (on this box that's the Logitech USB webcam, or hi556 if it's unplugged)
# -- NOT the rear. Resolve the rear (s5k3j1 = LNK0 = "Internal back camera") by
# identity, since its index shifts with what else is plugged in:
REAR=$(cam -l 2>/dev/null | grep -iE 'back camera|LNK0' | grep -oE '^[0-9]+')
echo "rear camera index = $REAR"       # sanity-check it found exactly one
cam -c "$REAR" --capture=100000 &       # hold the rear stream open
sleep 5

# Confirm the RIGHT port is streaming: rear = port 1 = "Intel IPU6 CSI2 1".
media-ctl -d /dev/media1 -p | grep -A2 's5k3j1'   # its link should read ENABLED

sudo dmesg > /home/mward/work/camera-mipi/reference/dmesg-rear-stream-$(date +%Y%m%d).txt
kill %1

# enumerate which named CSI2 errors appeared, with counts. The rear is csi2-1;
# if you see csi2-3 errors instead you captured hi556 -- wrong camera, redo.
grep -oE 'csi2-[0-9] error: .*' reference/dmesg-rear-stream-*.txt | sort | uniq -c | sort -rn
# confirm SOF events are firing in the same window:
grep -icE 'sof|frame start|buffer.*ready|CSI2.*sync' reference/dmesg-rear-stream-*.txt
```

**Decision matrix:**

| Observation | Conclusion | Next |
|---|---|---|
| **bit 7 "Frame sync error" present AND SOF events fire** | SOF is synthesized despite corrupt FS short packets → **pure-PHY, data-type-agnostic** | Focus #2/#3/#5; **drop #7** |
| bit 7 present but **no** SOF events | frame never starts cleanly at all | different failure mode; revisit stream setup |
| bit 7 **absent**, only bit 2 (payload CRC) present | short packets OK, only long-packet payload corrupt → **data-layer / descramble** | keep **#7** alive; polarity/deskew less likely |
| **bit 17 "Lane deskew" present** | receiver directly reports deskew failure | strong #3 signal → run `decode-phy0-lanes.py --live` stability check, then scope |
| **bit 18 "SOT sync error" present** | HS-entry / start-of-transmission sync fails | implicates #2 (clock mode) / settle → prioritize BRIEF-6 (FE_MODE) |
| bit 9/10 (DPHY sync) dominant, bit 7 absent | PHY loses sync mid-packet | pure-PHY; #3/#5 |

Note from existing evidence: the error signature quoted throughout STATUS.md **already
includes "Frame sync error"** and SOF events are known to fire repeatedly — so the top row
is the *likely* outcome and #6 may resolve to "pure-PHY confirmed" on the very first
capture. Stage 1 is mostly about making that rigorous and, importantly, checking whether
**bit 17 (Lane deskew)** or **bit 18 (SOT sync)** appear — neither is mentioned anywhere
in STATUS yet, and either one would sharply narrow the remaining hypotheses.

## Stage 2 — raw per-interrupt bitmask (only if Stage 1 is ratelimited away)

`dev_err_ratelimited` drops most errors ("N callbacks suppressed"), so a rare bit could be
hidden. If Stage 1's enumeration looks incomplete, capture the raw bitmask with per-bit
counters. Minimal instrumentation in
[`ipu6_isys_register_errors()`](../drivers/ipu6-isys/ipu6-isys-csi2.c:198), matching the
existing debug-print style already in this file (remove before any upstream submission —
tracked in STATUS TODO):

```c
void ipu6_isys_register_errors(struct ipu6_isys_csi2 *csi2)
{
	u32 irq = readl(csi2->base + CSI_PORT_REG_BASE_IRQ_CSI +
			CSI_PORT_REG_BASE_IRQ_STATUS_OFFSET);
	struct ipu6_isys *isys = csi2->isys;
	u32 mask;

	mask = isys->pdata->ipdata->csi2.irq_mask;

	/* DEBUG #6: raw error bitmask, unratelimited-but-deduped. Remove for upstream. */
	{
		static u32 last_irq;
		if ((irq & mask) != last_irq) {
			dev_info(&isys->adev->auxdev.dev,
				 "DEBUG csi2-%d raw err irq=0x%05x\n",
				 csi2->port, irq & mask);
			last_irq = irq & mask;
		}
	}

	writel(irq & mask, csi2->base + CSI_PORT_REG_BASE_IRQ_CSI +
	       CSI_PORT_REG_BASE_IRQ_CLEAR_OFFSET);
	csi2->receiver_errors |= irq & mask;
}
```

The dedup (`last_irq`) prints only when the *combination* of bits changes, which avoids
flooding while still capturing every distinct error pattern. Decode the hex against the
bit table above (e.g. `0x00080` = bit 7 only = frame sync; `0x20000` = bit 17 = lane
deskew). Rebuild/install/reboot, recapture as in Stage 1.

## Deliverable

Append findings to STATUS.md: the exact set of error bits that fire (with counts),
whether SOF fires concurrently, and which decision-matrix row applies — i.e. whether the
corruption is confirmed pure-PHY (and #7 can be dropped), plus whether bits 17/18 appear.
