# D028 — Multi-Book Portfolio Architecture

## Decision status

**Stage 0 blocked on 2026-07-28. No architecture implementation has started.**

D028 begins at `dc14d99f9cc97404b93ec17aa9dc6b589e41b9b4` on
`feature/d028-multibook-portfolio`. The isolated tester is a **HEDGING**
account, so it can represent separate physical strategy positions. A virtual
netting ledger remains a required architectural component for portability.

The standalone controls reproduced exactly, but the required legacy combined
control did not. Investigation found a pre-existing candidate-array indexing
defect in the D027 combined-strategy integration. The old combined result is
therefore not a deterministic baseline and D028's explicit Stage 0 stop gate
applies.

## Non-negotiable design

The eventual architecture remains:

```text
causal strategy signal engines
        ↓
independent logical strategy books
        ↓
portfolio risk manager
        ↓
hedging/netting execution coordinator
        ↓
broker positions
```

Each book will own its strategy/family identity, magic, logical position,
entry, stop, target, trailing/partial/time-stop state, opposite-signal policy,
risk allocation, persistence, and accounting. Cross-family mutation will be
disabled under independent-books research. The portfolio manager—not an
unrelated strategy signal—will determine whether additional exposure is
allowed.

New behavior will be disabled by default. Legacy behavior will remain the
default until an explicit research configuration selects another policy.
Canonical A, canonical E, SweepReclaim entry logic, and all D027 decisions
remain unchanged.

## Account-mode audit

- Environment: `/Users/matt/MT5-MSZZ-TEST`
- Symbol/timeframe: XAUUSD M5
- History window: 2025-03-01 through 2026-07-24
- Execution model: MT5 `Model=2`
- Detected mode: `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`
- Tester log label: `MSZZ OWNERSHIP REFRESHED mode=HEDGING`
- Physical simultaneous positions: supported by the isolated tester
- Virtual books: not required for this tester, but required by the D028 design
- Live account: not used

The current ownership layer already queries `ACCOUNT_MARGIN_MODE` in
`Include/MultiSpeedZigZag/Execution/PositionOwnership.mqh`; D028 must preserve
explicit hedging/netting/exchange handling rather than infer account behavior.

## Stage 0 control audit

Fresh runs used configs tracked in `Tools/D028/` and results stored externally
under `/Users/matt/MT5-MSZZ-TEST/D028_Stage0_Results`.

| Control | Trades | Cumulative R | Expectancy R | PF | Max DD R | Result |
|---|---:|---:|---:|---:|---:|---|
| FastMedConfluence A 2R | 224 | 28.2447 | 0.1261 | 1.2446 | 15.1583 | exact |
| SweepReclaim 2R | 190 | 28.6117 | 0.1506 | 1.2688 | 18.2941 | exact |
| Legacy A + Sweep 2R, fresh | 372 | 23.0157 | 0.0619 | 1.1253 | 25.2800 | mismatch |
| Legacy A + Sweep 2R, D027 certified | 371 | 20.7400 | 0.0559 | 1.1129 | 25.2798 | reference |

The A and SweepReclaim trade-analytics rows are byte-equivalent as parsed CSV
records to their certified standalone controls. The combined control differs
in two FastMedConfluence entries and adds one FastMedConfluence trade.

## Baseline defect

`CMSZZStrategySuite::AddCandidate` grows its output array in blocks:

```cpp
if(count>=ArraySize(out)) ArrayResize(out,count+16);
```

The EA then appends D027 candidates at allocated size rather than logical
count:

```cpp
int at=ArraySize(candidates);
ArrayResize(candidates,at+1);
candidates[at]=d027_candidates[i];
candidate_count++;
```

When A emits one candidate, the legacy array has logical count 1 and allocated
size 16. SweepReclaim is written at index 16, while the subsequent loop
processes indices 0 and 1. Index 1 is uninitialized. The D027 and fresh D028
signal journals contain malformed `RAW_CANDIDATE` rows with impossible
strategy IDs/prices, directly confirming the invalid read.

Different uninitialized values changed whether the real A candidate executed:

- 2025-12-19 17:00 versus 17:30
- an additional execution on 2026-05-28 19:40

This is not a market-data, account-mode, strategy-trigger, or standalone
equivalence failure. It is undefined combined-candidate arbitration behavior.

## Required resolution before Stage 1

Do not implement multi-book architecture until the owner selects how to
rebaseline the invalid legacy control. The defensible route is:

1. Fix the append/indexing defect without changing any signal definition.
2. Add a deterministic regression covering a legacy candidate plus a D027
   candidate in the same bar.
3. Compile with zero errors/warnings and run every existing MSZZ suite.
4. Re-run A, SweepReclaim, and combined controls.
5. Preserve standalone exact equivalence.
6. Declare the corrected deterministic combined result as a superseding D028
   control while leaving historical D027 artifacts untouched.

That route cannot honestly reproduce the invalid 371-trade path exactly. It
requires explicit authorization because the D028 specification says not to
proceed when baseline parity fails.

## Planned layers after resolution

1. `StrategyBook.mqh`: independent logical ownership and per-book exits.
2. `PortfolioRiskManager.mqh`: fixed portfolio, strategy, family, direction,
   symbol, loss, drawdown, and book-count caps.
3. `ExecutionCoordinator.mqh`: ticket isolation on hedging accounts and broker
   net-difference execution on netting/exchange accounts.
4. `VirtualNettingLedger.mqh`: virtual basis, quantity, synthetic stops,
   realized/unrealized R, and proportional cost attribution.
5. Portfolio journals: book state, risk decisions, execution allocations, and
   logical trade analytics.

No D028 strategy or exit result is claimed by this checkpoint.
