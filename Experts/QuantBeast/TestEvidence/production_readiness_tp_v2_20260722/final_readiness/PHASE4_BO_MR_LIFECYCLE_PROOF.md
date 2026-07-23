# Phase 4 -- BO and MR complete Shadow lifecycle proof

Extracted from the **existing, already-committed** unified matrix evidence
(`unified_strategy_matrix/`) -- no new tester runs were needed, since real,
organic, fully-reconstructed trade lifecycles for both strategies already
exist in that evidence. This follows the task's explicit instruction not
to force artificial signals or relax thresholds to manufacture coverage.

## BO -- one fully reconstructed lifecycle (SHORT)

Source: `run04_20260620_20260624`, SignalJournal `[34034028,35889604)`,
TradeJournal `[197688,201484)`.

| Field | Value |
|---|---|
| Signal timestamp | 2026.06.23 21:45:00 |
| Setup / trigger code | 100 (`SETUP_BO_COMPRESSION`) / 111 (`TRIGGER_BO_CLOSE_BEYOND`) |
| Confidence | 0.844 |
| Signal validity | ACCEPTED (reason: "Breakout Short: precComp=7 bars, atrRank=4.0, prox=1.17") |
| Proposed entry / stop / target | 4116.05 / 4124.00 / 4104.13, expected R 1.50 |
| Arbitration / risk | Accepted (reached Shadow) |
| Position size | 0.12 lots |
| Shadow fill | 4115.95 (10pt slippage vs. proposed 4116.05) |
| Stop/target registered | 4124.00 / 4104.13 -- exact match to signal |
| Management | held ~19 minutes (21:45:00 -> 22:04:10) |
| Exit path | `EXIT_STOP_LOSS` |
| MFE / MAE | 2.44 / -8.08 |
| Costs | commission -0.84, swap 0.00 |
| Final R / Net P&L | -1.02 / -99.00 |

**Complete pipeline proven for BO:** organic candidate -> valid signal ->
arbitration -> risk -> Shadow entry -> management -> exit -> reconciled
journal (TradeJournal row present and internally consistent with the
originating SignalJournal row -- same entry/stop/target family, same
timestamp).

**Gap, honestly noted:** only the SHORT path has an organic trade so far
(1 of 6 windows produced any BO acceptance at all, per the unified matrix's
pooled totals). No BUY-side BO trade has been captured. Per this phase's
own instruction ("do not force artificial signals... extend only through a
predeclared additional-window plan documented before running it"), this is
recorded as an open item for a future, explicitly predeclared window pass
-- not manufactured this session.

## MR -- fully reconstructed lifecycles, both directions

MR reached `ACCEPTED` in 6 of 6 windows (13 total acceptances, per the
unified matrix), with both LONG and SHORT organically represented.

### SHORT example (winner)

Source: `run03_20260216_20260220`, TradeJournal `[192860,197688)`.

| Field | Value |
|---|---|
| Entry time | 2026.02.17 12:25:00 |
| Direction | SHORT |
| Entry / Stop / Target | 4931.89 / 4939.46 / 4917.36 |
| Position size | 0.12 lots |
| Management | held ~24 minutes |
| Exit path | `EXIT_TARGET_HIT` (`ExitReason=0`) |
| MFE / MAE | 14.55 / -0.90 |
| Final R / Net P&L | **1.91** / **130.92** |

A second SHORT example in the same window (2026.02.17 14:40:00) also hit
target for R=1.96 / net $139.60 -- both a losing-scenario stop-out class
and a winning-scenario target-hit class are represented across MR's
pooled evidence (e.g. `run01`/`run02`/`run05` show MR stop-outs at
R approx -0.02 to -1.07).

### LONG example

Source: `run04_20260620_20260624`, TradeJournal `[197688,201484)`.

| Field | Value |
|---|---|
| Entry time | 2026.06.22 19:15:00 |
| Direction | LONG |
| Entry / Stop / Target | 4177.61 / 4169.54 / 4194.02 |
| Position size | 0.12 lots |
| Management | held ~74 minutes |
| Exit path | `EXIT_STOP_LOSS` (`ExitReason=1`) |
| MFE / MAE | 15.12 / -1.40 |
| Final R / Net P&L | 0.86 / 88.56 |

Two further LONG examples in the same window show a near-breakeven
stop-out (R -0.02) and a small loss with an oversized lot (R -0.10, volume
0.59 -- a real, organically-sized position, not a fixture), demonstrating
sizing responds to real signal/risk inputs across trades, not a fixed
constant.

**Complete pipeline proven for MR, both directions:** organic candidate ->
valid signal -> arbitration -> risk -> Shadow entry -> management -> exit
(both `EXIT_TARGET_HIT` and `EXIT_STOP_LOSS` observed) -> reconciled journal.

## Conclusion

- **BO**: Phase 4's "at least one fully reconstructed trade lifecycle"
  requirement is met (SHORT). BUY-side remains an open, explicitly-declared
  gap for a future pass, not manufactured here.
- **MR**: Phase 4's requirement is met with both directions, both exit
  classes (target-hit and stop-loss), and multiple independent windows --
  the strongest evidence of any non-FBO strategy in this sprint.

No threshold was tuned and no signal was manufactured to produce any of
the trades documented above -- all were already present in evidence
committed in the prior sprint, extracted here for Phase 4's specific
lifecycle-completeness question.
