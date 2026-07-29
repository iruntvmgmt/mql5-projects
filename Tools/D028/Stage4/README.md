# D028 Stage 4 — Multi-Book Portfolio Tests

Stage 4 executes the corrected legacy control and three actual independent-book
portfolios over the frozen XAUUSD M5 window in the isolated HEDGING tester.

## Configurations

- P1: FastMedConfluence A 2R plus SweepReclaim 2R under corrected legacy
  shared ownership.
- P2: independent 2R books with opposing exposure disabled.
- P3: independent 2R books with opposing exposure enabled.
- P4: independent FastMedConfluence E 3R and SweepReclaim 2R books with
  opposing exposure enabled.

P1 reuses the corrected Stage 0B execution result. P2–P4 were executed by the
EA, not constructed by adding standalone results. Their raw artifacts remain
at `/Users/matt/MT5-MSZZ-TEST/D028_Stage4_Results`.

## Reproduction

Run `analyze_stage4.py` with Python 3. It reads the external native reports and
CSV journals and regenerates:

- `legacy_control.csv`
- `portfolio_summary.csv`
- `strategy_contribution.csv`
- `portfolio_window_summary.csv`
- `portfolio_exposure_summary.csv`
- `portfolio_integrity_audit.csv`
- `stage4_findings.md`

The analyzer fails closed unless native trades/deals, logical trades,
allocation opens, unique logical IDs, book closures, distinct magics,
per-book targets, reconciliation rejects, and cross-family actions reconcile.
Two consecutive runs produced byte-identical tracked outputs.

## Integrity result

P2–P4 have zero duplicate logical IDs, zero target-policy errors, zero
own-book reconciliation rejects, and zero cross-family actions. The distinct
book magics are 27084001 (FastMedConfluence) and 27124002 (SweepReclaim).
The account mode recorded for every book is `HEDGING`.

An initially generated P2 result was discarded before analysis because the
first direct multi-book implementation lacked durable strategy-qualified
duplicate suppression. A later audit found delayed MT5 history visibility
could mislabel a successful own-family close and reject its replacement
entry. The close now records from the successful trade result immediately;
P2–P4 were rerun from the corrected source. No provisional result is retained
as evidence.

All three final runs contain one broker `ORDER_FAILED` candidate with an
`invalid stops` retcode. It created no logical trade and all trade/deal
reconciliations remain exact. It is reported, not suppressed.

Stage 4 does not select a SweepReclaim exit model or confer production status.
Stage 5 remains a separate bounded study.
