# CSV export format

A session is exported as a small **bundle** (a `.zip`, or a folder) containing one CSV
per stream plus metrics, annotations, and a metadata JSON. **Column order is fixed** so
the offline Python analysis is stable. Every CSV has a header row. All timestamps are
**device microseconds** (the extended 64-bit value — see
[`BLE_PROTOCOL.md`](BLE_PROTOCOL.md#clock-synchronization)).

```
<session-label>_<sessionId>/
  session_meta.json    Session fields + Subject (code only) + Calibration snapshot
  ecg.csv              t_us, ecg
  bioz.csv             t_us, z0_milliohm, dz
  ppg.csv              t_us, green, red, ir
  metrics.csv          t_us, hr_bpm, spo2_pct, contact_quality, motion, pat_ms, sbp_est, dbp_est
  annotations.csv      t_us, type, sbp, dbp, text
```

## Per-file detail

### `session_meta.json`
```jsonc
{
  "schemaVersion": 1,
  "session": {
    "id": "…", "subjectCode": "S01", "label": "rest",
    "deviceId": "…", "firmwareVersion": "1.0.0",
    "startedAt": "ISO-8601", "endedAt": "ISO-8601",
    "notes": "…",
    "metricsSource": "app" | "firmware",
    "gating": { "motionThresh": 1234, "contactThresh": 5000, "windowMs": 500 }
  },
  "subject": { "code": "S01", "ageBand": "18-25", "sex": null, "notes": "" },
  "calibration": {            // snapshot at session start, or null if uncalibrated
    "model": "linear_invPAT",
    "coeffs": { "sbp": [a, b], "dbp": [a, b] },   // BP = a + b * (1/PAT_seconds)
    "rmseSbp": 4.2, "rmseDbp": 3.1, "r": 0.91,
    "createdAt": "ISO-8601"
  }
}
```

### `ecg.csv`
| column | unit                  |
|--------|-----------------------|
| `t_us` | device microseconds   |
| `ecg`  | signed ADC counts     |

### `bioz.csv`
| column          | unit                                  |
|-----------------|---------------------------------------|
| `t_us`          | device microseconds                   |
| `z0_milliohm`   | baseline magnitude (repeated per row) |
| `dz`            | pulsatile delta-Z (ADC counts)        |

`z0_milliohm` is sampled once per packet; on export it is forward-filled onto every
ΔZ sample row so each row is self-contained.

### `ppg.csv`
| column  | unit                          |
|---------|-------------------------------|
| `t_us`  | device microseconds           |
| `green` | counts (18-bit right-justified) |
| `red`   | counts                        |
| `ir`    | counts                        |

### `metrics.csv`
| column            | unit / notes                          |
|-------------------|---------------------------------------|
| `t_us`            | device microseconds                   |
| `hr_bpm`          | beats/min, blank if invalid           |
| `spo2_pct`        | percent, **estimate**, blank if invalid |
| `contact_quality` | 0–100                                 |
| `motion`          | 0–255                                 |
| `pat_ms`          | milliseconds, blank if invalid        |
| `sbp_est`         | mmHg, blank if invalid/uncalibrated   |
| `dbp_est`         | mmHg, blank if invalid/uncalibrated   |

### `annotations.csv`
| column | notes                                                                   |
|--------|-------------------------------------------------------------------------|
| `t_us` | device microseconds                                                     |
| `type` | `cuff_reading` \| `motion_start` \| `motion_stop` \| `artifact` \| `marker` |
| `sbp`  | mmHg (only for `cuff_reading`), else blank                              |
| `dbp`  | mmHg (only for `cuff_reading`), else blank                              |
| `text` | free text, CSV-escaped                                                   |

A `cuff_reading` annotation is the **ground-truth capture** used for PAT→BP calibration
and validation.

## CSV escaping

Fields containing a comma, double-quote, or newline are wrapped in double quotes with
internal quotes doubled (RFC 4180). Blank numeric cells denote "invalid / not available"
(not zero).
