# D029 — Percentage-Risk Sizing, Executable Partial-Leg Validation, and Portfolio Reconciliation

Branch `feature/d029-percent-risk-partials`, forked from D028's final SHA
`1ff69f918aefe43ce7c213992805be33a9c3be6a` on `feature/d028-multibook-portfolio`.
No merge to `main`. No live deployment. This is a new, bounded study — it
does not rewrite, reinterpret, or rerun D028's certified results.

## Why this study exists

D028 found no SweepReclaim exit-management variant that improved on the
original fixed-2R exit, including the two partial-close designs SR3 and
SR4. But SR3/SR4 were never actually tested as designed: the account's
fixed `0.01`-lot position size equals the broker's minimum tradable size
and volume step, so every attempted 50% partial close clamped back to the
full position and was skipped. SR3 silently collapsed into SR1's exact
trade sequence (byte-identical output hash); SR4 collapsed into a broken,
repeated no-op loop. **D028's SR3/SR4 status remains `REDESIGN_REQUIRED` —
not disproven, not validly tested.** D029 exists to resolve that gap
correctly, by sizing positions as a percentage of equity (rather than a
fixed lot) so partial closes become numerically possible, then testing
whether a genuinely executable partial or runner design improves
SweepReclaim standalone and the actual independent-book portfolio.

## Research questions

**Primary**: can a percentage-of-equity position-sizing engine produce
executable, risk-normalized partial exits for SweepReclaim without changing
its entries, structural stop, signal logic, portfolio architecture, or
causal assumptions?

**Secondary**: once partials execute correctly, do any partial or runner
designs improve standalone SweepReclaim and the actual independent-book
P3/P4 portfolios relative to percentage-sized fixed-exit controls?

The goal is a valid, causal, auditable answer — not a result above `50R`.

## Non-negotiable constraints (unchanged from the handoff, restated for the record)

No changes to: FastMedConfluence A or E entry logic, SweepReclaim entry
logic, candidate generation, clustering, event identity, signal timing,
structural initial stops. No optimization of risk percentage, portfolio-risk
caps, partial fractions, or runner thresholds after results are seen. No
merge to `main`, no live deployment, no changes to Quant Beast, no rewriting
of D027 or D028 evidence.

D028's independent-book architecture is preserved unchanged: HEDGING
account, separate physical tickets, separate magics, own-book-only closing,
cross-family close/reverse disabled, opposing books allowed, one book per
strategy, total portfolio risk enforced.

## Phase 0 — frozen rules

All values below are frozen **before** any D029 backtest is run or any
result is inspected. Full machine-readable copy: `Tools/D029/Phase0/frozen_design.md`.

```text
Sizing mode:                          PERCENT_EQUITY
Risk per FastMed book:                0.25%
Risk per SweepReclaim book:           0.25%
Maximum total portfolio initial risk: 0.50%
Maximum active books:                 2
Maximum books per strategy:           1

Partial fraction:                     50%
SR3 first partial trigger:            +1R
SR3 remaining target:                 +2R
SR3 remaining stop after partial:     entry price
SR4 first partial trigger:            +1R
SR4 runner stop after partial:        entry price
SR4 fixed target after partial:       none
SR4 trailing source:                  confirmed causal structural pivots only

Opposing books:                       allowed
Cross-family close/reversal:          disabled
```

### Symbol metadata (XAUUSD, Coinexx-Demo)

Captured read-only via `Scripts/MultiSpeedZigZagTools/SymbolMetadataProbe.mq5`
(no trading action; `SymbolInfo*`/`AccountInfo*` calls only), run once on
the isolated instance:

```text
volume_min:     0.01
volume_max:     100.00
volume_step:    0.01
tick_size:      0.01
tick_value:     1.00
contract_size:  100
point:          0.01
digits:         2
account_currency: USD
```

### Tester balance selection

Sizing formula (see Phase 1 below for the exact frozen calculation):
`raw_volume = (equity * risk_pct/100) / (stop_distance_price * (tick_value/tick_size))`.
For a 0.02-lot minimum partial-capable position at 0.25% risk, this reduces
to `balance >= 800 * stop_distance_price`.

D028's certified SweepReclaim SR0 run (`MSZZ_TradeAnalytics.csv`, 190
trades, no new backtest needed) gives the canonical stop-distance
distribution: min 0.54, median 5.44, mean 8.25, p95 25.78, max 112.59
(XAUUSD price units). Projecting six candidate balances against this
distribution (`Tools/D029/Phase0/volume_resolution_analysis.py`,
`volume_resolution_summary.csv`):

| candidate | % trades >=0.02 lots | % exact 50/50 | % non-exact split | % below minimum |
|---|---|---|---|---|
| $10,000 | 82.63% | 43.68% | 38.95% | 5.26% |
| $25,000 | 98.42% | 57.37% | 41.05% | 0.53% |
| $50,000 | 99.47% | 53.68% | 45.79% | 0.00% |
| $75,000 | 99.47% | 54.74% | 44.74% | 0.00% |
| **$100,000** | **100.00%** | 45.79% | 54.21% | 0.00% |
| $150,000 | 100.00% | 51.05% | 48.95% | 0.00% |

**Frozen tester balance: $100,000** — the handoff's own suggested starting
candidate, verified rather than assumed to clear the required 95% threshold
(it clears at 100%, the maximum possible margin). This choice was made
purely from stop-distance/volume-resolution projection, never from any
profitability figure. Honest disclosure made here, before any D029 result
exists: at $100,000, the majority of trades (54.21%) will split into a
non-exact 50/50 partial (e.g. a 0.07-lot position splits 0.03/0.04, not
0.035/0.035) rather than a clean even halves — every such case will be
separately categorized in Phase 3's accounting, per the handoff's own
tolerance rule, not silently treated as a clean split. This is a real
property of percentage sizing at this account's volume step and is
disclosed rather than hidden.

Same $100,000 balance is used for every D029 control and portfolio run.

## Phase 0 verification

`Scripts/MultiSpeedZigZagTools/SymbolMetadataProbe.mq5` compiled (`0
errors, 0 warnings`), synced to the isolated instance (hash-verified), and
run once via `[Common] Login=870012` / `[StartUp] Script=...` — confirmed
in the terminal journal (`script SymbolMetadataProbe (XAUUSD,M5) loaded
successfully` / `removed` / `closes terminal with code 0`). Output written
to Wine's shared `Common/Files` folder (a `FILE_COMMON` fallback path in
the probe script, not the portable instance's own `MQL5/Files`) —
documented here since it took two failed attempts to locate: the first two
launches hung because the config lacked the `[Common] Login=870012` section
required for a live-attached (non-Tester) script run, distinct from every
other config used across D026–D028 which all used `[Tester]`-based
backtest launches instead. No trading account state was affected by any of
these attempts (read-only script, `InpAllowLiveExecution`/`InpAcknowledgeRisk`
not applicable to a plain script).

This document, `Tools/D029/Phase0/README.md`, `frozen_design.md`, and
`volume_resolution_summary.csv` are committed as `D029 Phase 0: freeze
percentage-risk and partial-leg study` before any Phase 1 implementation
begins.
