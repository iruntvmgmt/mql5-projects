# Phase 9 -- Restart and recovery with five strategies

## Real defect found and fixed: TP V2's restart-persisted state was silently dropped

While auditing `Core/StateStore.mqh` for restart/reconciliation coverage
(the same class of check Phase 2 ran, but Phase 2's own grep patterns did
not surface this -- these functions have no `[4]`/`[8]` array literal to
match, only four explicit named `GV_WriteDouble`/`GV_ReadDouble` calls
per function), two genuine restart-persistence gaps were found:

1. **`SaveKillSwitchState`/`LoadKillSwitchState`** wrote and read exactly
   four `GV_KILL_STRAT_*` GlobalVariables (BO/FBO/TP/MR). TP V2's kill
   flag (`KillSwitchState.strategy_kill[QB_STRAT_IDX_TPV2]`) was never
   persisted. **Impact: if an operator killed TP V2 specifically via the
   kill switch, a terminal restart would silently un-kill it** -- TP V2
   would resume trading after a restart the operator explicitly intended
   to keep it off. This is a genuine safety regression, not merely an
   observability gap, since kill-switches exist specifically to survive
   restarts.
2. **`SaveStrategyTradeCounters`/`LoadStrategyTradeCounters`** likewise
   only round-tripped BO/FBO/TP/MR. TP V2's daily trade count
   (`g_StrategyTradesToday[QB_STRAT_IDX_TPV2]`) always reset to 0 across
   a restart, even same-day. **Impact: TP V2's daily per-strategy trade
   cap (`InpMaxDailyPerStrategy` via `m_maxDailyPerStrategy` in
   `RiskEngine::ValidateTrade`) could be silently bypassed by restarting
   mid-day** -- a minor but real risk-control gap.

Both are exactly the "restart reconstruction; strategy ID mapping;
persistence schemas" categories Phase 2 was scoped to audit; they were
missed there because the audit's search terms (`[4]`, `[8]`, `< 4`, etc.)
don't match four separately-named `GV_*` constants and four individually
-typed `GV_WriteDouble` call sites. Documented here as a genuine gap in
the earlier audit's coverage, not just a new finding.

### Fix

Added `GV_STRAT_TRADES_TPV2` and `GV_KILL_STRAT_TPV2` constants
(`Core/StateStore.mqh`), added the corresponding
`GV_WriteDouble`/`GV_ReadDouble` calls to both save/load function pairs,
and added both new keys to `ClearAllState()`'s cleanup list (so a clean
reset now actually clears TP V2's persisted state too, where previously
it would have been silently left behind).

### New deterministic test (SafetyTests.mqh Test 101)

`QBTestTPV2RestartPersistence` round-trips both functions through a
scoped (test-isolated, via `SetStateScopeSymbol`) save/load cycle:
sets only TP V2's kill flag and a distinct TP V2 trade count (7, vs
1/2/3/4 for the other four strategies), saves, reloads, and asserts TP
V2's values survive correctly while the other four remain exactly as
set (not cross-contaminated) -- then cleans up via `ClearAllState()` and
restores the original state-scope symbol.

## Other Phase 9 items -- already correct (code audit)

- **Strategy ownership recovery / comment parsing**: `QBStrategyIdFromComment`
  -> `QBIsKnownStrategyId` (fixed Phase 2) is the single source of truth
  used by both `PositionManager::ReconstructFromBroker` and live-fill
  transaction handling -- already verified and tested.
- **Initial stop/target restoration**: `RecoverEntryMetadata` reads
  broker history by position ticket, strategy-agnostic (no `strategy_id`
  branch in its own logic) -- correct for TP V2 by construction.
- **Strategy index restoration**: `StrategyIndexFromId` (`QuantBeastEA.mq5:460`)
  explicitly maps `STRATEGY_ID_TREND_PULLBACK_V2 -> QB_STRAT_IDX_TPV2`.
- **Risk exposure restoration**: `CExposureManager` (`Portfolio/ExposureManager.mqh`)
  has no per-strategy state at all -- sums lots across all open positions
  regardless of strategy, so nothing to restore per-strategy.
- **Unknown-position / incompatible-state quarantine**: `CReconciliation::Classify`
  (`Execution/Reconciliation.mqh`) operates on the generic
  `ReconciliationResult` produced by `ReconstructFromBroker` -- no
  strategy-count assumption found (no `[4]`/`[8]` literal in this file).

## Broker-free fixture reconstruction proof

A full broker-position restart-reconstruction proof (`ReconstructFromBroker`
against a real TP V2-owned position across an actual MT5 terminal
restart) was **not** performed this phase -- it would require either (a)
a real broker position deliberately preserved through a restart, or (b)
a synthetic broker-position mock, and `ReconstructFromBroker` reads live
MT5 position/history APIs directly (no injectable broker-position mock
exists in this codebase to exercise it purely deterministically). This
remains an open item: the persistence-layer defect above (which
`ReconstructFromBroker` does not depend on) is now fixed and tested, and
`QBTestTPV2RestartResetSemantics` (Test 90) already proves the *lifecycle
engine's* in-memory restart-reset semantics; the remaining gap is
specifically the live-broker-position reconstruction path, honestly
reported rather than manufactured with an artificial mock.

## Compile / test status

Compile: `0 errors, 0 warnings` (MetaEditor GUI compile, EX5 refreshed
12:51 vs. source edits through 12:31).
Self-test regression: **105 passed, 0 failed** (Test 101 added; Tests
96-102 and rewritten Test 37 from Phases 6/13 all pass in the same run).

**Broker orders transmitted for this phase: none.**
