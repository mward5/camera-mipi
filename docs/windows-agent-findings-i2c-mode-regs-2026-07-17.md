# Windows-agent findings — live I2C capture of S5K3J1 mode-config sequence — 2026-07-17

Session goal (per `WINDOWS-AGENT-BRIEF-4-i2c-mode-regs.md`): capture the real I2C traffic Windows sends to the rear sensor (S5K3J1, addr `0x10`) during streaming, to find where the ~400-byte ARM Cortex-M microcode blob around register `0x90c8` (present in Linux's `mode_3976x2736_regs[]` table, absent from every static analysis of `s5k3j1sx04.sys`) actually comes from.

**Bottom line: the primary approach (ETW tracing) worked completely, on the first attempt, and answered the question definitively. Windows *does* send the exact `0x90C8`–`0x9248` microcode-upload register range over real I2C, live, during sensor stream-start — this was not a dead end into ISP firmware. The 620-transaction capture also independently confirms this is genuinely the `3976x2736` mode (readback of the standard output-size registers returns 3976/2736 decimal exactly), and captures the complete mode-config sequence end-to-end: unlock handshake → microcode upload → calibration tables → mode/format parameters → mode readback/verification → live AE/AF convergence loop.**

## 1. Method

**Providers used** (found via `logman query providers | findstr /i "spb i2c serial"`, no guessing needed):
- `Intel-iaLPSS2-I2C` `{C2F86198-03CA-4771-8D4C-CE6E15CBCA56}` — the Intel Serial IO I2C driver's own provider; carries slave address, direction (WRITE/READ), and transfer-length/sequence events.
- `Microsoft-Windows-SPB-ClassExtension` `{72CD9FF7-4AF8-4B89-AEDE-5F26FDA13567}` — the generic SpbCx framework provider; carries the actual payload bytes (`IoSpbPayloadTdBuffer` events, one per byte-count-increment, final instance = complete transaction payload) and direction (`FromDevice`/`ToDevice`).
- `Intel-iaLPSS-I2C` (non-"2" variant) also enabled, but produced no events — this platform uses the `iaLPSS2` generation driver only.

**Capture procedure**:
1. Confirmed Camera app was **not** running, so tracing could start before any stream-start sequence occurred.
2. `logman create trace i2c_capture -o i2c_capture.etl -ets`, then `logman update trace i2c_capture -p "<provider>" 0xffffffffffffffff 0xff -ets` for each provider (max verbosity/keywords).
3. User opened the Camera app and switched to the rear/world-facing camera while the trace was running.
4. `logman stop i2c_capture -ets` — captured 34 seconds, 18,049 events, 0 lost, ~1.75MB `.etl`.
5. Decoded with `tracerpt i2c_capture.etl -o i2c_capture.csv -of CSV -summary i2c_summary.txt`.
6. Wrote a correlation script (`parse_i2c_trace.ps1`, left in this same folder) to merge the two providers' event streams: parsed `Intel-iaLPSS2-I2C` event ID `1091` (regex-extracted address + WRITE/READ direction + sequence number) and grouped `Microsoft-Windows-SPB-ClassExtension` `IoSpbPayloadTdBuffer` events by their per-transaction Activity ID GUID (concatenating byte instances to get the complete payload), then matched the two streams by nearest ETW `Clock-Time` (100ns-tick timestamps, typical match window under 200 ticks = 20 microseconds — i.e. genuinely the same physical transaction, not a coincidental nearby event).

**Result**: 721 total I2C transactions captured in this one stream-start window, split across three bus addresses:

| Address | Count | Likely identity |
|---|---|---|
| `0x10` | 620 (584 WRITE, 36 READ) | **The S5K3J1 sensor** (confirmed — matches Linux's known address exactly) |
| `0x4D` | 58 | Probably the TPS68470 PMIC/companion chip (short 1-2 byte transactions, register-poll pattern) |
| `0x72` | 43 | Unidentified third device on the same bus (short transactions, not investigated further — out of scope for this brief) |

Full reconstructed data: `i2c_reconstructed.csv` (all 721 transactions) and `i2c_sensor_0x10_full.csv` (the 620 sensor-only rows), both left in this folder alongside the raw `.etl`/`.csv` and the parsing script, in case anyone wants to re-derive or double check this.

## 2. The complete sensor (0x10) transaction sequence, phase-annotated

All 620 transactions, in capture order. `Bytes` is the raw payload as sent/received (register address + data concatenated, as actually transmitted on the wire — no assumption made here about where the address ends and data begins beyond what's visually obvious from the Linux-side register-map context).

### Phase A — unlock/bank-select handshake (11 transactions)
```
WRITE 4   0x60284000
WRITE 4   0x00000000
WRITE 4   0x000030A1
WRITE 4   0xFCFC4000
WRITE 4   0x60100001
WRITE 4   0x60000005
WRITE 4   0xFCFC4000
WRITE 4   0x62147971
WRITE 4   0x62187150
WRITE 4   0x60282000
WRITE 4   0xFCFC2000
```
`0xFCFC4000`/`0xFCFC2000` is the classic Samsung sensor "page/bank select" unlock pattern — consistent with what's documented for this sensor family.

### Phase B — THE MICROCODE UPLOAD (13 transactions, `0x90C8`–`0x9248`, ~400 bytes) — **the answer to this session's question**
```
WRITE 34  0x90C8000000000000000005490448054AC1F8BC06101AA1F8C00600F065B82000926C
WRITE 34  0x90E8200066402000DA002DE9F04106463A480D460268140C97B200223946204600F0
WRITE 34  0x910879F82946304600F07AF801223946204600F070F83148D0F80C05B0F5805F09D9
WRITE 34  0x91282F480088002805D02E490220A1F80201A1F81401BDE8F08110B5284C0146D4F8
WRITE 34  0x9148EC0504F2EC5400F05FF8206800F061F800F064F821680844206010BD2DE9F84F
WRITE 34  0x916882461D4888461646816899460D0C8FB20A9C00223946284600F03CF84B463246
WRITE 34  0x918841465046009400F04EF801223946284600F030F8124806EB48014088201A401E
WRITE 34  0x91A8C880BDE8F88F10B50022AFF2C3010E4800F03EF8084C0022AFF2830120600B48
WRITE 34  0x91C800F036F80022AFF26B016060084800F02FF8A06010BD00002000926020006640
WRITE 34  0x91E82000D9004000B0000000EEAF0000D86B000001F549F2417CC0F2000C60474EF6
WRITE 34  0x9208AF6CC0F2000C60474DF2835CC0F2000C60474DF2B16CC0F2000C60474DF2C16C
WRITE 34  0x9228C0F2000C604740F2F51CC0F2000C60474BF6535CC0F2000C6047000000000000
WRITE 18  0x9248000000000000000030A101CB00000026
```
Register addresses walk **sequentially** `0x90C8 → 0x90E8 → 0x9108 → 0x9128 → 0x9148 → 0x9168 → 0x9188 → 0x91A8 → 0x91C8 → 0x91E8 → 0x9208 → 0x9228 → 0x9248`, each a 32-byte write (final one 16 bytes, terminating the run) — a burst covering exactly `0x9248 + 16 - 0x90C8 = 0x196` (406) bytes, matching the brief's "~400-byte contiguous run" description closely. This directly and unambiguously confirms: **Windows sends this exact register range over real I2C during sensor init.** It is not something the ISP firmware substitutes for. Whatever this data actually is (the byte content itself is highly consistent with the "looks like real ARM Cortex-M code" observation from the static-analysis side — dense, non-repeating, structured-looking machine code, not a sparse register-value table), Windows transmits it the same way Linux's driver is meant to.

This does **not** explain why static analysis of `s5k3j1sx04.sys` found zero byte matches for this content — that remains an open question (possibilities: the data is compressed/obfuscated in the binary and decoded at runtime, sourced from a separate resource/firmware file not yet identified, or assembled programmatically rather than stored as a literal byte array) — but it does conclusively answer the brief's actual question: **this is live I2C traffic, not ISP-firmware-substituted configuration.** A byte-for-byte comparison against Linux's `mode_3976x2736_regs[]` table at these same addresses (not performed here — this project's Windows-session convention is to capture data rather than assume access to the Linux-side source tree) should be the immediate next step, and given how clean this capture is, should be conclusive.

### Phase C — post-microcode config: interrupt masks, lens-shading/gain tables, timing (91 transactions)
Representative excerpt (full data in `i2c_sensor_0x10_full.csv`):
```
WRITE 4   0xFCFC2000
WRITE 4   0x0E000101
WRITE 6   0x0E50010000FF
WRITE 4   0x0E560100
WRITE 8   0x0E5A001B171BF46E
WRITE 4   0x0EC00101
WRITE 6   0x0EE401010004
WRITE 4   0x11B00815
WRITE 4   0x11C20815
WRITE 4   0x133A0101
WRITE 4   0x134201EA
WRITE 4   0x1348041A
... (registers 0x13B4-0x16CC: small parameter writes)
WRITE 6   0x278201E001EA
WRITE 6   0x278803C003B8
... (registers 0x2782-0x2B12: a long run of paired 16-bit values — very likely lens-shading-correction or gain-curve coefficient tables, structurally similar to Linux's known LSC table region)
WRITE 4   0x3BC20100
... (registers 0x3BC2-0x3FDC: more parameters)
WRITE 6   0x520801000000
... (registers 0x5208-0x53BE: another long structured run, likely a second coefficient/calibration table)
WRITE 32  0x52F61000100010001000100010001000100010001000100C10101014101C1028
WRITE 6   0xD90000010000
```

### Phase D — second unlock + mode-select register block (32 transactions)
```
WRITE 4   0xFCFC4000
WRITE 4   0x01120A0A
WRITE 6   0x01162B000000
WRITE 4   0x021E0000
WRITE 4   0x03800001
WRITE 4   0x03840001
WRITE 4   0x04021010
WRITE 12  0x080E030708050A0818060B00
WRITE 6   0x0B0601010001
WRITE 4   0x0B840201
WRITE 4   0xF45C00FF
WRITE 8   0xF462001500160013
WRITE 4   0xF46C0010
WRITE 4   0xF48A0020
WRITE 4   0xFCFC4000
WRITE 4   0x60000005
WRITE 4   0xFCFC2000
WRITE 4   0x0D9C000A
WRITE 4   0x0EE20060
WRITE 6   0x13340A0103F1
WRITE 4   0x28740017
WRITE 4   0x2B14004E
WRITE 4   0x3BC00300
WRITE 4   0x3BE20102
WRITE 10  0x3BE8000008804D040408
WRITE 8   0x3BFC02FD22EF00A5
WRITE 4   0x3C040637
WRITE 4   0x3D2848AA
WRITE 4   0x3D360101
WRITE 4   0x42E00100
WRITE 34  0x4C840000000000000000000000000000000000000000000000000000000000000000
WRITE 34  0x4FC80000000000000000000000000000000000000000000000000000000000000000
WRITE 6   0x5A4001000000
```
Note the two 34-byte writes to `0x4C84` and `0x4FC8` are **all-zero payloads** (32 zero bytes each) — a buffer/region clear, not more microcode. Worth noting since it's the same size/shape as the Phase B writes but semantically different (clearing vs. uploading).

### Phase E — frame format / mode parameters (18 transactions) — **sets the actual 3976×2736 mode**
```
WRITE 4   0xFCFC4000
WRITE 4   0x01140301
WRITE 4   0x01361333
WRITE 4   0x013E0001
WRITE 10  0x030000050001000200D2
WRITE 10  0x030C0001000301400001
WRITE 22  0x03400B1E24E0000000001F0F0AAF0F880AB000000000
WRITE 4   0x03820001
WRITE 4   0x03860001
WRITE 4   0x04041000
WRITE 4   0x09000011
WRITE 6   0x0B0201030001
WRITE 4   0x0B800100
WRITE 10  0x0B880000000000000000
WRITE 4   0x60000085
WRITE 4   0x62147970
WRITE 4   0x01100002
WRITE 4   0x01163000
WRITE 4   0x01000100
```
The 22-byte write to `0x0340` contains, in order: `0B1E` (FRM_LENGTH_LINES=2846), `24E0` (LINE_LENGTH_PCK=9440), `0000`/`0000` (crop start X/Y = 0,0), `1F0F` (crop end, =7951), `0AAF` (=2735), `0F88` (**output width = 3976 decimal**), `0AB0` (**output height = 2736 decimal**) — this is the actual mode-select write, and it's writing exactly the `3976x2736` mode's parameters, confirming beyond doubt that this capture is the right mode.

### Phase F — mode readback/verification (2× identical 21-register read-back sequences, 73 transactions)
```
WRITE 2   0x030E   READ 2   0x0003
WRITE 2   0x0310   READ 2   0x0140
WRITE 2   0x030A   READ 2   0x0001
WRITE 2   0x0312   READ 2   0x0001
WRITE 2   0x0308   READ 2   0x0008
WRITE 2   0x0340   READ 2   0x0B1E
WRITE 2   0x0340   READ 2   0x0B1E
WRITE 2   0x0342   READ 2   0x24E0
WRITE 2   0x0344   READ 2   0x0000
WRITE 2   0x0346   READ 2   0x0000
WRITE 2   0x0348   READ 2   0x1F0F
WRITE 2   0x034A   READ 2   0x0AAF
WRITE 2   0x034C   READ 2   0x0F88   <-- 3976 decimal
WRITE 2   0x034E   READ 2   0x0AB0   <-- 2736 decimal
WRITE 2   0x0900   READ 1   0x00
WRITE 2   0x0901   READ 1   0x11
WRITE 2   0x0304   READ 2   0x0002
WRITE 2   0x0306   READ 2   0x00D2
WRITE 2   0x0302   READ 2   0x0001
WRITE 2   0x030C   READ 2   0x0001
WRITE 2   0x0300   READ 2   0x0005
WRITE 3   0x010001   (repeats the whole block above once more, then:)
WRITE 3   0x010401
```
Every value read back matches what Phase E just wrote — a clean, direct confirmation the sensor accepted the mode-3976x2736 configuration. `0x034C`/`0x034E` reading back `0x0F88`/`0x0AB0` (3976/2736 decimal) is the single most direct piece of evidence in this whole capture that this is genuinely the mode in question.

### Phase G — live AE/AGC convergence loop (continues past end of capture, ~400 transactions)
From `WRITE 3 0x010401` onward, the trace settles into a tight repeating pattern:
```
WRITE 3   0x010400        <- group-hold end (previous frame's exposure/gain apply)
WRITE 3   0x010401        <- group-hold begin
WRITE 4   0x0340<value>   <- FRM_LENGTH_LINES (frame length, adjusted for exposure headroom)
WRITE 4   0x0202<value>   <- coarse integration time (exposure)
WRITE 4   0x0200<value>   <- (usually 0x0000, unclear field)
WRITE 4   0x0204<value>   <- analog gain (ramping steadily upward: 0x0020 → 0x0026 → 0x0035 → ... → 0x0139 over the capture)
WRITE 4   0x020E<value>   <- flag (0x0100/0x0101/0x0102, toggling)
```
This is the sensor's real-time auto-exposure control loop running continuously as the live preview auto-exposes to the room's actual lighting — not part of one-time mode configuration, but confirms the capture window extended well into genuine live streaming, not just the init sequence. `0x0104` is a standard MIPI-CCS-style `GROUP_PARAMETER_HOLD` register (01=hold active, 00=apply) — writes to `0x0202`/`0x0204`/`0x0340` are bracketed by it so multiple related registers take effect atomically on the same frame boundary, exactly as the CCS spec intends.

## 3. Answer to the brief's core question

**Confirmed: this configuration lives in real host-driver I2C writes, not ISP firmware.** The related finding mentioned in the brief (Linux's ISP firmware not being byte-identical to Dell's bundled firmware in 2 of 7 sub-components) turned out not to be the explanation for the missing `0x90c8` bytes — Windows genuinely sends them over the wire, live, during every stream start. The mystery instead narrows to a more specific, more tractable question: **why doesn't this exact byte sequence appear anywhere in `s5k3j1sx04.sys`'s static image**, given it's clearly what the driver causes to be sent. Worth a future session's static-analysis pass specifically informed by this capture (e.g. searching for a *compressed* or *XOR'd* version of these exact 406 bytes, rather than a literal match, or checking whether the DriverStore's calibration blobs — `1BAA01T3`/`1BAA02T3`/`CJALR11`, noted in earlier sessions — might carry it instead of the `.sys` itself).

## 4. Methods not needed this session

WinDbg kernel debugging (brief's fallback #3) and RWEverything I2C spot-reads (fallback #4) were not attempted — the ETW approach succeeded completely on the first try and produced a far more complete picture (full transaction sequence with timing and both directions) than either fallback could have given alone. Leaving both as available options for a future session if a different question needs them.

## 5. Artifacts left in this folder

- `i2c_capture.etl` — raw ETW trace (both providers, 34s window, 18,049 events)
- `i2c_capture.csv` / `i2c_summary.txt` — `tracerpt`-decoded CSV and event-count summary
- `parse_i2c_trace.ps1` — the correlation script (regex-based; re-runnable against the same or a future `.etl`→CSV if needed)
- `i2c_reconstructed.csv` — all 721 transactions, all three bus addresses, with address/direction/bytes/timing-correlation-confidence columns
- `i2c_sensor_0x10_full.csv` — just the 620 sensor transactions, in order
