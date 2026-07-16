# Arbitration and signal-journal decision integrity — 2026-07-15

## Confirmed defects

**Severity: Medium (audit and decision integrity).**

1. Position-conflict and same-direction stacking checks removed candidates from arbitration selection but left their `valid` flag true.
2. The controller journaled every valid strategy output as `ACCEPTED` before arbitration and central risk. Lower-ranked, conflict, duplicate, cooldown, exposure, and risk-rejected candidates could therefore retain false acceptance rows.
3. Journal signal IDs used only strategy plus timestamp, so simultaneous long and short evaluations for one strategy shared the same ID.

These defects did not directly bypass risk or transmit an invalid order, but they made the signal audit trail materially unreliable.

## Repair

- Every arbitration rejection now sets `valid=false` and a specific rejection code/reason.
- Every valid non-winning candidate becomes `REJECT_ARBITRATION_LOST`.
- The controller immediately journals strategy-level rejections, then journals arbitration losers after arbitration.
- The winning signal is journaled only after central risk, as either risk-rejected or signal-accepted.
- `ACCEPTED` now means the signal passed strategy, arbitration, and central pre-trade risk. Order submission/fill status remains the responsibility of `OrderJournal.csv`.
- Journal signal IDs now include strategy, direction, and signal time.

## Deterministic evidence

Test 34 proves:

- the higher-ranked FBO SELL is selected;
- the lower-ranked candidate becomes an explicit arbitration rejection;
- a committed duplicate is rejected;
- opposing candidates are both rejected under reject-conflicts policy;
- same-direction stacking against an existing position becomes an explicit exposure rejection.

Final compile: `0 errors, 0 warnings, 10330 ms`.

Final Shadow regression: `36 passed, 0 failed`; `22080 ticks`, `1104 bars`; tester balance unchanged at `10000.00`. No broker orders were transmitted.

## Hashes

- `QuantBeastEA.mq5`: `a771a2f6e2f3812f478885df525400f2b697f16656087ae208f08953e1588a6d`
- `SignalArbitrator.mqh`: `a7165c091cc6a4817188f35cd634a62bebc99a770a0ee1b6f1303b1b87266732`
- `TradeJournal.mqh`: `e2c42fc46abbe5ee6ca7886d200b6cb6fb5661f4c7fe4c7db45bd4d67964d05d`
- `SafetyTests.mqh`: `cca2edbf58b1aeabaef7af1016fb607535222272a933474a3d4348ee9ab90be1`
- `QuantBeastEA.ex5`: `0357dfb5323a25969645f59ea2ca6c95de642678e8c2c7d376337fd172469e85`

## Boundary

The arbitration mutation contract has runtime proof and controller/journal routing has static trace evidence. A completed organic post-repair run that emits and inspects the new CSV rows is still required for file-level journal proof. The existing shared journal contains historical pre-repair rows and must not be rewritten as if they were new evidence.

On 2026-07-15 after the repair, a rerun attempt was blocked by test infrastructure: the native MT5 MCP transport at `127.0.0.1:22346` was unavailable, and a direct Wine `/config` launch opened the terminal UI but did not start a new tester section. The local agent log retained its prior `18:24:17` timestamp and no new signal CSV appeared. The launched terminal process was stopped. This is a blocked attempt, not runtime or file-level proof.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge modes remain prohibited.
