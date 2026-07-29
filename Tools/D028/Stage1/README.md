# D028 Stage 1 — Default-Off Portfolio Architecture

This checkpoint implements architecture only. It does not claim a portfolio
backtest, single-book equivalence under the new path, or a SweepReclaim exit
result.

## Safety boundary

- `InpEnableMultiBookPortfolio` defaults to `false`.
- Legacy execution is unchanged when the input is false.
- Explicit activation validates the architecture and then fails initialization
  closed. Broker routing remains intentionally unavailable until Stage 2 tests
  and Stage 3 equivalence.
- No live account was used. Verification used `/Users/matt/MT5-MSZZ-TEST`.
- The detected isolated account mode is `HEDGING`.

## Implemented components

See `architecture_inventory.csv` for the exact tracked files and boundary.
The four journal filenames are:

- `MSZZ_StrategyBookJournal.csv`
- `MSZZ_PortfolioRiskJournal.csv`
- `MSZZ_ExecutionAllocationJournal.csv`
- `MSZZ_PortfolioTradeAnalytics.csv`

Netting/exchange plans explicitly require EA-managed synthetic protection;
they do not imply independent broker-side stops for offsetting logical books.
Persistence, restart reconciliation, partial-cost allocation, simultaneous
event ordering, and actual broker transmission remain test-gated Stage 2 work.

## Verification

The EA and all 22 existing `Test_MSZZ_*` scripts compiled in the isolated
instance with zero errors and zero warnings. All 22 runtime suites passed with
zero failures.

Default-off legacy shadows remained exact:

| Window | Raw candidates | Clusters | Malformed | Trades |
|---|---:|---:|---:|---:|
| short | 113 | 46 | 0 | 0 |
| long | 431 | 178 | 0 | 0 |

No baseline backtest was rerun: Stage 0B already certified A, SweepReclaim, and
the corrected legacy combination, while Stage 1 changed only default-disabled
architecture. New-path single-book equivalence is deliberately reserved for
Stage 3 after Stage 2 tests.
