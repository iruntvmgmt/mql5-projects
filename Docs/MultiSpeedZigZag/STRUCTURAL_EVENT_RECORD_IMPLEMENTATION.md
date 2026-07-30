# Structural Event Record Implementation

## Result

`MSZZStructuralEventRecord` is implemented as additive ownership evidence. Existing strategies, candidates, legacy break flags/IDs, execution paths and thresholds are unchanged.

## Architecture

- `Core/Types.mqh` defines the record and adds bullish/bearish records to `MSZZSpeedSnapshot`.
- `Core/StructuralEventRecord.mqh` is the single projection, identity, builder and validator policy.
- `TripleZigZagEngine::BuildSpeed()` retains the direction-adjacent origin at the moment each second projection anchor is confirmed. On a legacy break it passes exact local bars, ATR, anchors and retained origin to the shared builder.
- `Research/StructuralReplay.mqh` uses the same pivot-ID, projection and builder policy and exposes per-bar records.
- Legacy `BO|...` IDs remain compatibility fields. Certified identities use `MSZZSE1`.

No record is reconstructed from the final snapshot. A missing/invalid origin or projection makes only the new record invalid; legacy behavior continues identically.

## Ownership certification

The certified June 2025 XAUUSD M5 replay contained 217 valid events:

| Speed | Long | Short |
|---|---:|---:|
| Fast | 8 | 14 |
| Medium | 50 | 55 |
| Slow | 39 | 51 |

All 217 matched engine versus replay field-for-field and all 217 IDs were unique. Fifteen occurred on bars where a pivot was confirmed during the same rebuild, proving that the retained scan-time origin/projection basis—not reconstructed final state—was captured.

## Validation and tests

Focused deterministic tests cover valid bullish/bearish and all speeds; exact projection/geometry; origin chronology; missing origin, zero ATR, invalid close and projection mismatch; deterministic identity; basis/speed/direction separation; copy lifetime; real-history rebuild/replay parity; same-rebuild pivot mutation; and uniqueness.

Fresh Bash/Wine compilation:

- EA: `2026.07.30 13:07:36.167`, 0 errors, 0 warnings.
- focused test: `2026.07.30 13:41:55.715`, 0 errors, 0 warnings.
- all 33 `Test_MSZZ_*.mq5` sources: 0 errors, 0 warnings, 0 tooling no-ops.

Runtime:

- focused test: failures=0;
- historical parity: 217/217;
- existing regression: 32/32 PASS, zero tooling no-ops/timeouts;
- P4: 330 trades, +47.6083336413R, R-PF 1.2472234619, canonical journal SHA-256 unchanged.

## Authorization impact

Structural input ownership is now available for MC, BRC, TP, CBR and RR. No family is authorized: the v2 typed candidate schema is still a design rather than implemented generator/journal code; TP also lacks its value service; SSR is unaffected. D034 and D035 remain blocked.
