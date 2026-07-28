# D028 Stage 0B findings

The candidate-index defect is fixed without changing either strategy's trigger, score, clustering priority, or exit policy. Candidate arrays are compact at subsystem boundaries; every processed slot is validated and clustering fails closed on count/index/identity mismatch.

## Baseline status

- B0 A: 224 trades, 28.2447R; certified trade-row parity `true`.
- B1 SweepReclaim: 190 trades, 28.6117R; certified trade-row parity `true`.
- B2 corrected legacy shared ownership: 372 trades, 23.0157R, 0.0619R expectancy, PF 1.1253, 25.2798R drawdown.

Historical D027 Stage 6 A+Sweep (371 trades, +20.7400R) is preserved unchanged but is formally `INVALIDATED_FOR_COMBINED_BASELINE_COMPARISON`. It contained 19 malformed raw candidates produced by undefined indexing. The fresh pre-fix D028 run contained 24; corrected B2 contains zero.

## Corrected combined attribution

- Raw candidates: 1093 (A 717, SweepReclaim 376).
- Valid initialized candidates: 1093; malformed: 0.
- Selected cluster events: 1018; unique cluster IDs: 867.
- Executions/trades/deals: 372/372/744.
- Owners: A 246 trades; SweepReclaim 126 trades.
- Exits: SL 153, TP 97, own-family opposite 56, cross-family opposite 66, unknown 0.
- Core retained 215, displaced 9, newly executed 31.
- Rejections/outcomes: {'EXECUTED': 372, 'ORDER_FAILED': 1, 'REJECT_DUPLICATE_CLUSTER': 139, 'REJECT_EXPIRED': 2, 'REJECT_OWNERSHIP': 318, 'REJECT_SPREAD': 6, 'REJECT_STOPS': 180}.

All summary, analytics, native HTML, deal, frozen-window, owner, and exit totals reconcile. Stage 1 is unblocked, but was not started in this commit.
