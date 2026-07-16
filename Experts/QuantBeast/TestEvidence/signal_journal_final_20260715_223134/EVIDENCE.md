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

## Second defect demonstrated and repaired

Severity: High (historical audit-evidence integrity).

`OpenJournalFile()` opened an existing `FILE_READ|FILE_WRITE` journal but did
not seek to its end. MT5 therefore positioned the handle at byte zero, and the
first subsequent rows overwrote the beginning of the historical CSV. The first
writer-fixture attempt exposed this directly: five fixture rows replaced the
opening bytes while file size remained 4,850 bytes. That mutation is recorded
as a failed boundary and is not represented as compliant proof.

The smallest repair makes journal initialization fail closed unless
`FileSeek(handle, 0, SEEK_END)` succeeds. After recompilation, the identical
writer fixture increased the existing file from 4,850 to 6,698 bytes and the
new suffix contained exactly the five fixture rows. No older suffix bytes were
rewritten by the repaired run.

## Verified result

- MetaEditor build 6002: `0 errors, 0 warnings`.
- Source SHA-256: `6a4f83c34b4cd27d89739e4df760347994ba7a28f9aaae41990eb4bfcc2052be`.
- EX5 SHA-256: `cf3bceae2ee37841487684e974e29e2c246f521c9deb62a942136e28747f5fd7`.
- Deterministic file-output fixture uses generated ticks and the production
  `CTradeJournal` writer; it does not call a broker order path.
- BUY and SELL directions are preserved in both direction and signal ID.
- Strategy rejections, arbitration loser, and risk rejection are `REJECTED`.
- Only the fully passing fixture signal is `ACCEPTED`.
- The existing organic configuration produced a genuinely new agent section,
  but March true ticks were unavailable, MT5 fell back to generated ticks, the
  run was forced to stop, and no organic CSV row appeared. Organic file proof
  therefore remains pending data availability.

Exact artifacts: `compile_result.txt`, raw UTF-16LE `QuantBeastEA.log`,
`signal_rows_appended.txt`, `organic_run_boundary.txt`, and the unique INI.
