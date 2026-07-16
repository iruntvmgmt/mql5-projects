# Final signal-decision journal evidence — 2026-07-15 22:31:34 EDT

## Defect demonstrated

Severity: Medium (audit and risk-decision integrity).

The controller wrote an `ACCEPTED` signal row immediately after unsized
`RiskEngine.ValidateTrade()`, before sizing, sized-risk validation, broker
volume/stop/target legality, and margin validation. A later risk-stage failure
could therefore leave a false accepted row.

## Repair boundary

- Final signal acceptance is emitted only after all central pre-execution risk,
  sizing, broker-legality, and margin checks pass.
- Every failure in those later checks emits one rejected signal decision.
- Broker request/fill outcomes remain in `OrderJournal.csv`.
- Tester-only Test 35 exercises the production CSV writer with strategy-long,
  strategy-short, arbitration-loser, central-risk-rejected, and accepted rows.
- No broker order path is called by the fixture.

## Pre-run boundary

- Common `SignalJournal.csv`: 4,850 bytes; modified 2026-07-15 15:30:00 EDT.
- Tester-agent log: 133,940,460 bytes; modified 2026-07-15 18:24:17 EDT.
- Tester-manager log: 114,604,660 bytes; modified 2026-07-15 18:24:17 EDT.
- Native organic rerun returned ambiguous `job_id: 0`; none of these files grew,
  so no run or pass was claimed.

Compile, runtime, hashes, new-row excerpts, and remaining organic/true-real-tick
boundaries are appended only after fresh evidence exists.
