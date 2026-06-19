# BLE protocol — single source of truth

This document defines the custom GATT service exposed by the wearable firmware. The
firmware, the web app (`web/src/ble`), and the iOS app (`ios/VitalView/BLE`) must all
agree with this document. **All multi-byte fields are little-endian.**

Samples are **batched** per notification to respect BLE throughput. Assume a ~20 ms
connection interval and ATT MTU ≥ 185 bytes; keep each notification payload
**≤ ~180 bytes**.

## UUIDs

The placeholder UUIDs below follow the pattern `f001000X-1a2b-4c3d-8e5f-000000000000`,
where `X` is the characteristic index. Regenerate with `uuidgen` if you like, but keep
firmware + both apps in sync.

**Service:** `f0010000-1a2b-4c3d-8e5f-000000000000`

| Characteristic   | UUID                                   | Props                | Purpose                          |
|------------------|----------------------------------------|----------------------|----------------------------------|
| Control / Status | `f0010001-1a2b-4c3d-8e5f-000000000000` | write, read, notify  | Commands + device state          |
| ECG stream       | `f0010002-1a2b-4c3d-8e5f-000000000000` | notify               | ECG samples                      |
| BioZ stream      | `f0010003-1a2b-4c3d-8e5f-000000000000` | notify               | Bioimpedance (Z₀ + pulsatile ΔZ) |
| PPG stream       | `f0010004-1a2b-4c3d-8e5f-000000000000` | notify               | Green / Red / IR samples         |
| Metrics          | `f0010005-1a2b-4c3d-8e5f-000000000000` | notify               | Derived metrics (firmware-side)  |
| Battery          | `0x180F` / `0x2A19`                     | read, notify         | Standard Battery Service         |

## Stream identifiers and rate codes

Stream IDs (used in `START` bitmask and `SET_RATE`):

| Stream | id | bitmask | default rate | rate codes (`SET_RATE`)                          |
|--------|----|---------|--------------|--------------------------------------------------|
| ECG    | 0  | `0x01`  | 256 Hz       | `0`=128, `1`=256, `2`=512                         |
| BioZ   | 1  | `0x02`  | 64 Hz        | `0`=32, `1`=64, `2`=128                           |
| PPG    | 2  | `0x04`  | 100 Hz       | `0`=50, `1`=100, `2`=200, `3`=400                 |

## Control / Status characteristic

**Write** a 1-byte opcode followed by optional little-endian arguments:

| Opcode | Name         | Args                                  | Effect                                                        |
|--------|--------------|---------------------------------------|--------------------------------------------------------------|
| `0x01` | `START`      | `uint8` stream bitmask                | Enable + begin notifying the selected streams                |
| `0x02` | `STOP`       | —                                     | Stop all streaming                                           |
| `0x03` | `SET_RATE`   | `uint8` stream id, `uint8` rate code  | Set a stream's sample rate                                   |
| `0x04` | `SYNC_CLOCK` | —                                     | Device replies (status notify) with its current `t_us`       |
| `0x05` | `GET_INFO`   | —                                     | Device replies (status notify) with info payload (see below) |

**Status notification** payload (sent on change, on `SYNC_CLOCK`, and ~1 Hz heartbeat):

```
uint8   msg_type        // 0x10 = STATUS, 0x11 = INFO, 0x12 = CLOCK
// --- STATUS (0x10) ---
uint8   streaming_mask  // which streams are currently on
uint8   ecg_rate_code
uint8   bioz_rate_code
uint8   ppg_rate_code
uint32  t_us            // device clock at time of message
uint8   battery_pct
uint8   error_flags     // bit0=lead-off, bit1=ppg saturation, bit2=buffer overflow
// --- INFO (0x11) ---
uint8   fw_major, fw_minor, fw_patch
uint8   device_id[6]    // e.g. BLE MAC; rendered as hex
uint16  capabilities    // bitmask of supported streams/features
// --- CLOCK (0x12) ---
uint32  t_us            // device clock; client stores offset = hostNow_us - t_us
```

## Clock synchronization

On connect the client issues `SYNC_CLOCK` and stores `offset = hostNow_us − device_t_us`.
**All cross-stream alignment and PAT computation use device `t_us`, never host
wall-clock.** The host offset is used only to render an approximate wall-clock for the
operator and to timestamp annotations consistently.

`t_us` is a **uint32 microsecond** counter and therefore **wraps every ≈4294.97 s
(≈71.6 min)**. The source layer extends it to a monotonic 64-bit value per stream by
detecting backward jumps (`new + 2³² ` when `new ≪ last`). Recorded/exported timestamps
are the extended values.

## Stream packet layouts

Each notification is one packet: a fixed header followed by `K` packed samples. `K` is
chosen so the total payload ≤ ~180 bytes; **parsers derive `K` from the payload length**
rather than assuming a constant, so firmware may use any `K` that fits.

### ECG (`f0010002…`)
```
offset 0  uint16  seq             // increments per packet; gaps ⇒ dropped packets
offset 2  uint32  t_us            // device timestamp of FIRST sample in packet
offset 6  uint16  sample_rate_hz
offset 8  int32   samples[K]      // signed ADC counts (default K = 20 ⇒ 88-byte payload)
```
Sample `i` has timestamp `t_us + round(i * 1e6 / sample_rate_hz)`.

### BioZ (`f0010003…`)
```
offset 0  uint16  seq
offset 2  uint32  t_us
offset 6  uint16  sample_rate_hz
offset 8  int32   z0_milliohm     // baseline magnitude (contact quality), once/packet
offset 12 int32   dz_samples[K]   // pulsatile delta-Z samples (default K = 16 ⇒ 76 bytes)
```

### PPG (`f0010004…`)
```
offset 0  uint16  seq
offset 2  uint32  t_us
offset 6  uint16  sample_rate_hz
offset 8  { uint32 green; uint32 red; uint32 ir; } samples[K]   // 18-bit data right-justified
                                                                // default K = 12 ⇒ 152 bytes
```

### Metrics (`f0010005…`, lower rate, e.g. 1–4 Hz)
```
offset 0  uint32  t_us
offset 4  uint16  hr_bpm_x10        // 0xFFFF = invalid
offset 6  uint16  spo2_pct_x10      // 0xFFFF = invalid (label as ESTIMATE)
offset 8  uint8   contact_quality   // 0..100 from BioZ Z0 stability
offset 9  uint8   motion_flag       // 0 = still, 1..255 = motion severity from dZ variance
offset 10 int32   pat_us            // R-peak → PPG foot delay; INT32_MIN = invalid
offset 14 int16   sbp_mmHg          // estimated; INT16_MIN = invalid / uncalibrated
offset 16 int16   dbp_mmHg          // estimated; INT16_MIN = invalid / uncalibrated
offset 18 uint16  rpeak_flags       // bit0 set if an R-peak occurred this window
```

### Sentinel / invalid values
| Field            | Invalid sentinel |
|------------------|------------------|
| `hr_bpm_x10`     | `0xFFFF`         |
| `spo2_pct_x10`   | `0xFFFF`         |
| `pat_us`         | `INT32_MIN`      |
| `sbp_mmHg`/`dbp` | `INT16_MIN`      |

## Client responsibilities

- Track `seq` **per stream** to detect and count dropped packets; expose a
  "dropped packets" / "link quality" indicator.
- Align streams by device `t_us` (extended to 64-bit as above).
- Treat firmware-computed metrics as **optional**: the apps also compute their own
  metrics (see [`DSP.md`](DSP.md)) so the algorithms can be iterated without reflashing.
  A setting selects the metrics source (firmware vs app).
