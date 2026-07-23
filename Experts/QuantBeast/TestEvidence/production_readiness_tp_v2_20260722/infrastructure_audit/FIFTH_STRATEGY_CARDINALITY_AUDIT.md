# Fifth-strategy cardinality audit (Phase 2, follow-on sprint)

Repository-wide search for assumptions tied to exactly four strategies or
eight directional candidates, per `QuantBeast_Production_Readiness_Sprint.md`
Phase 2. Search patterns used: `[4]`, `[8]`, `< 4`, `<= 3`, `== 4`, plus
direct greps for `STRATEGY_ID_*` chains, `QB_STRAT_COUNT` usage, and every
file referencing `STRATEGY_ID_BREAKOUT` (a reliable proxy for BO/FBO/TP/MR-
only mappings, since every hardcoded 4-strategy chain includes it).

## Real defects found and fixed

1. **`Include/QuantBeast/Execution/PositionManager.mqh`, `QBIsKnownStrategyId()`**
   -- the single source of truth `QBStrategyIdFromComment()` (itself used
   identically by both live-fill transaction handling and restart
   reconstruction, per its own doc comment) delegates to, was missing
   `STRATEGY_ID_TREND_PULLBACK_V2`. **Impact: any real TPV2-owned position or
   pending order's `QB_TPV2_...` comment would resolve to `"UNKNOWN"` at
   both live-fill time and restart-reconstruction time** -- it would never
   be recognized as owned, never actively managed, and would fall under
   whatever `InpUnknownPosPolicy` dictates (report/quarantine/flatten)
   instead of normal management. This is the most severe finding in this
   audit -- a real restart/ownership defect, not just a missing bonus or
   cosmetic gap. Fixed with a one-line addition; the fix propagates to
   every call site automatically since they all funnel through this one
   function (confirmed via `grep` of every `QBIsKnownStrategyId`/
   `QBStrategyIdFromComment` call site). Test coverage extended
   (`QBTestStrategyIdFromComment`, two new assertions).
2. **`Include/QuantBeast/Portfolio/SignalArbitrator.mqh`,
   `ARBITRATION_REGIME_PRIORITY`'s compatibility-bonus chain** -- checked
   `STRATEGY_ID_TREND_PULLBACK` but not `_V2`, so a TP V2 candidate always
   scored a `0.0` regime-compatibility bonus in this arbitration mode,
   regardless of trend regime, silently disadvantaging it against TP V1.
   Fixed by including `STRATEGY_ID_TREND_PULLBACK_V2` in the same branch as
   V1 (both represent the identical trend-following compatibility claim
   against `regime.trend != TREND_NEUTRAL` -- reusing the existing `0.20`
   value, not inventing a new threshold). **Zero impact on default
   behavior**: `InpArbitrationMethod` default is `ARBITRATION_HIGHEST_SCORE`,
   not `ARBITRATION_REGIME_PRIORITY` -- this only matters if an operator
   explicitly switches modes. New deterministic test
   (`QBTestTPV2RegimePriorityCompatibility`, Test 94) proves TP V2 receives
   the identical bonus as TP V1 via a symmetric tie-break check (whichever
   candidate is listed first wins, in both orderings -- only possible if
   both score identically).

## Checked, confirmed NOT defects (false positives / already correct)

- `Include/QuantBeast/Risk/ChallengeMode.mqh` `[4]` hits -- Challenge
  *stage* indices (0-4, five stages), unrelated to strategy count.
- `Include/QuantBeast/Analytics/TradeJournal.mqh`,
  `Include/QuantBeast/Analytics/CounterfactualTracker.mqh` `[4]`/`[8]` hits
  -- CSV positional field-array indices, unrelated to strategy count.
- `Include/QuantBeast/Portfolio/AllocationEngine.mqh` `m_ids[8]` etc. --
  dynamically grown by string ID lookup (`IndexOf`), gracefully bounded
  (`if(m_count >= 8) return -1`), 5 << 8, no overflow risk. Confirmed TP V2
  is automatically included: `GetWeight`/`RecordSignal` are called with
  `signal.strategy_id` (generic string), not a fixed index.
- `Include/QuantBeast/Risk/KillSwitch.mqh` -- already uses `QB_STRAT_COUNT`
  dynamically everywhere (fixed in the prior sprint alongside
  `KillSwitchState.strategy_kill[5]`); reverified clean this pass.
- `Include/QuantBeast/Core/Types.mqh` `QBStrategyFamilyLabel()` -- does not
  include TPV2, but is **dead code**: `grep` confirms zero call sites
  anywhere in the codebase (every strategy's `Init()`, including all four
  pre-existing strategies, passes its family string literally instead of
  calling this lookup). Not a live defect; noted for completeness only.
- `Include/QuantBeast/Core/StateStore.mqh`, `Execution/Reconciliation.mqh`,
  `Execution/RecoveryEngine.mqh`, `Portfolio/ExposureManager.mqh` -- zero
  strategy-count-specific hardcoding found; all either strategy-agnostic
  (aggregate accounting) or already dynamic.
- `SignalArbitrator`'s cooldown/duplicate-memory structures
  (`m_recentSignalIDs[]` etc.) -- dynamically `ArrayResize`'d to a
  strategy-agnostic cap (`m_recentMax=50`), not indexed by strategy.
- `UI/Dashboard.mqh` -- the only `"TP"` hits are Take-Profit chart-line
  object names, unrelated to the TP strategy.
- `Tools/acceptance_funnel_report.py`, `strategy_performance_report.py`,
  `tpv2_structure_report.py` -- none hardcode a strategy list; all group by
  whatever `Strategy` values actually appear in the journal data, already
  confirmed correctly displaying all 5 strategies in the prior sprint's
  evidence without any code change needed.

## Observed, pre-existing, out of scope for this audit

- `AllocationEngine::RecordOutcome()` is never called anywhere in the
  codebase -- `ALLOC_PERFORMANCE` mode's realized-R scoring always falls
  back to `avgR=0.0`, degenerating to equal weighting regardless of mode.
  This predates TP V2 and affects all strategies identically (not a
  cardinality issue); `ALLOC_EQUAL` is the default so no runtime behavior
  changes. Left unfixed -- wiring `RecordOutcome()` requires deciding where
  in the trade-close path to call it, a larger change than this audit's
  "smallest safe change" mandate, and touches economic allocation behavior
  which this phase is explicitly not meant to alter.

## Verification

Compile: 0 errors, 0 warnings. Self-tests: 97 passed, 0 failed (Tests 1-93
unchanged plus new Test 94; `QBTestStrategyIdFromComment` extended with two
TPV2 assertions, both passing). No trading behavior changed for any
existing default configuration.
