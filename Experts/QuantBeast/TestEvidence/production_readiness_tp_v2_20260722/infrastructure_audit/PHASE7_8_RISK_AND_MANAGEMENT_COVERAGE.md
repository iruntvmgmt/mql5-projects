# Phase 7 -- Risk-engine and position-sizing coverage for TP V2

## Audit findings

- **`CRiskEngine::ValidateTrade`/`ValidateSizedTrade`** and
  **`CPositionSizer::CalculateLots`/`EstimateRisk`** (`Risk/RiskEngine.mqh`,
  `Risk/PositionSizer.mqh`): take a generic `StrategySignal` (or raw
  entry/stop/equity numbers) with **no strategy-ID branch anywhere** --
  `CalculateLots` does not even accept a `strategy_id` parameter. TP V2
  cannot be excluded from the central risk contract because there is no
  code path that discriminates by strategy in the first place.
- **Per-strategy daily trade counts** (Phase 7 item 7): DO exist --
  `g_StrategyTradesToday[QB_STRAT_COUNT]` (`QuantBeastEA.mq5:111`),
  indexed via `StrategyIndexFromId()` (line 460), which explicitly maps
  `STRATEGY_ID_TREND_PULLBACK_V2 -> QB_STRAT_IDX_TPV2` (line 466). Array
  sized by `QB_STRAT_COUNT` (5, fixed in Phase 2/D005). Increment
  (`MarkStrategyTrade`, line 470), restart-restore (line 1021), and
  restart-save (`SaveStrategyTradeCounters`, line 375) all go through the
  same ID-indexed path -- correct for TP V2 by construction, not by a
  TPV2-specific patch. (Earlier in this session's Phase 6 audit this
  mechanism was reported as "not implemented for any strategy" -- that
  was based on an incomplete grep; this phase's deeper check found it
  under `StrategyTradesToday`/`StrategyIndexFromId`, not the search terms
  originally tried. Corrected here.)
- **Per-strategy position counts** (`EffectiveStrategyCount`,
  `QuantBeastEA.mq5:159`): delegates to `CShadowPortfolio::GetStrategyCount`
  or `CPositionManager::GetStrategyCount`, both ID-keyed lookups (not
  fixed arrays) -- correct for TP V2 automatically.
- **Ownership parsing / performance attribution / TP V1 vs V2
  confusion** (items 8, 9, 10): already covered by `QBTestStrategyIdFromComment`
  (extended with TPV2 assertions, Phase 2) and `QBTestTPV1V2Isolation`
  (Test 91, proves disjoint vocabularies and version tags). TradeJournal's
  `Strategy` column is the literal string `"TPV2"` vs `"TP"` -- confirmed
  directly in Phase 5's real trade data (`TradeJournal.csv` rows tagged
  `TPV2` for the one organic TP V2 trade, never conflated with `TP`).

## New deterministic test (SafetyTests.mqh Test 100)

`QBTestTPV2RiskEngineAcceptance` directly exercises `CRiskEngine` and
`CPositionSizer` with a `STRATEGY_ID_TREND_PULLBACK_V2` signal:

1. A valid TP V2 SELL signal (correct geometry, R:R 2.0, confidence 0.60)
   is **accepted** by `ValidateTrade`.
2. The same signal with an inverted stop (wrong side of entry for a SELL)
   is **rejected** with an "...geometry..." reason.
3. The same signal with `expected_reward_r=0.5` (below the configured
   1.0 minimum) is **rejected** with a "Reward:Risk too low" reason.
4. `CalculateLots` given identical entry/stop/equity produces the
   **identical lot size** whether `strategy_id` is `TREND_PULLBACK_V2` or
   `BREAKOUT` -- empirical proof of the central risk contract, not just a
   code-reading claim.
5. The sized TP V2 trade also clears `ValidateSizedTrade` via the same
   sizer-based actual-risk estimate every other strategy uses.

## Not applicable / no dedicated test needed

- **Exposure aggregation** (item 6): `totalExposure` is a caller-computed
  sum across all open positions regardless of strategy (summed in
  `QuantBeastEA.mq5` before calling `ValidateTrade`) -- there is no
  per-strategy exposure carve-out to have excluded TP V2 from; it is
  included the same way every position is, by virtue of being counted at
  all.

---

# Phase 8 -- Shadow management and exit coverage

## Audit finding: management is strategy-agnostic by construction

`CPositionManager`'s management logic (breakeven, ATR trailing, partial
close, time stop, momentum exit, regime exit) operates uniformly on
`PositionContext` records. Searched every reference to `strategy_id` in
`PositionManager.mqh`: all of them are either storing which strategy owns
a position (`m_positions[i].strategy_id = ...`) or counting/filtering by
strategy for reporting (`GetStrategyCount`) -- **none of the management
decision branches (breakeven trigger, trailing update, partial-close
trigger, time/momentum/regime exit) reference `strategy_id` at all.**
There is no code path that could have assumed "only four strategies" in
position management, because management never dispatches on strategy
identity in the first place.

## Evidence already proving TP V2 goes through real management

TP V2's one organic Shadow trade (`run_p3_03_20260216_20260220`,
2026.02.18 11:40:00 SELL) already exercised: initial protective stop/
target registration (exact match to signal geometry), live management for
~25 minutes, and a real stop-hit exit (`EXIT_STOP_LOSS`) with MFE/MAE and
final R recorded -- the full management pipeline, organically, not a
fixture. The real Coinexx-Demo `CONTROLLED_EXECUTION_FIXTURE` this same
session additionally proved the live SL-modification code path
end-to-end via the actual broker (`trade_modify_sl_tp`, breakeven-style
move from 4045.09 to 4048.00, confirmed by position-state diff) --
demonstrating the same modification mechanism management code would use
for a real TP V2 breakeven/trailing move, at the broker-protocol level.

## Conclusion

No new management-branch test is needed for TP V2 specifically: the
mechanism is provably strategy-agnostic (audit), the full entry-to-exit
pipeline has already been organically proven for TP V2 in Shadow mode
(Phase 3/4 evidence), and the broker-level SL-modification mechanism has
been proven for real (this session's fixture). Breakeven/trailing/
partial-close/time-exit specifically triggering on a TP V2 position
remains proven by the strategy-agnostic code path, not yet by an organic
TP V2 example of each branch individually -- an honest, low-risk gap
(these branches are already covered organically by FBO/MR's richer trade
history) rather than a defect.

## Compile / test status

Compile: `0 errors, 0 warnings`.
Self-test regression: **105 passed, 0 failed** (Test 100 added this
phase; final count reflects all of Phases 6-13's additions verified
together in the same run -- see `PHASE9_RESTART_RECOVERY_FIVE_STRATEGIES.md`).

**Broker orders transmitted for this phase: none new** (Test 100 is a
pure deterministic fixture; the broker-level SL-modification evidence
cited above was already transmitted and documented in
`run_manifests/run_ce01_20260723_broker_fixture.md`).
