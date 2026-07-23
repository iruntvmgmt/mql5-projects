# Phase 6 -- Arbitration and allocation verification

## Audit findings (code inspection, no changes needed)

- **`CSignalArbitrator::Arbitrate()`** (`Portfolio/SignalArbitrator.mqh`):
  every branch (`ARBITRATION_HIGHEST_SCORE`, `ARBITRATION_REGIME_PRIORITY`,
  `ARBITRATION_REQUIRE_CONFLUENCE`, `ARBITRATION_REJECT_CONFLICTS`) loops
  over `validCount`/`count`, both caller-supplied array sizes -- there is
  no hardcoded strategy-count bound anywhere in this file except the
  `REGIME_PRIORITY` compatibility-bonus chain, already fixed for TP V2 in
  Phase 2 (commit `27173da`). Candidate ordering does not create
  accidental priority: `ScoreSignal()` is a pure function of the signal's
  own fields (confidence, regime, expected R, spread, HTF direction), not
  of array position.
- **`CAllocationEngine`** (`Portfolio/AllocationEngine.mqh`): the internal
  `m_ids[8]` array is ID-keyed (`IndexOf()` linear-scans by string ID and
  allocates a new slot on first sight), not strategy-index-keyed -- TP V2
  gets its own slot exactly like any other strategy the first time
  `RecordSignal`/`RecordOutcome` is called for it. `ALLOC_EQUAL` (default)
  returns 1.0 unconditionally, so enabling TP V2 does not change any
  existing strategy's weight unless the allocation mode is explicitly
  switched.
- **Per-strategy daily trade counts / max-trades limits**: searched
  `RiskEngine.mqh`, `PositionManager.mqh`, `ExposureManager.mqh` --
  **no such mechanism exists for any strategy** (not a TP V2-specific
  gap; this feature is simply not implemented in the current codebase).
  Recorded here for completeness since Phase 7/Phase 6 both ask about it.
- **`CRiskEngine::ValidateTrade`/`ValidateSizedTrade`**: both take a
  generic `const StrategySignal &signal` -- no strategy-ID branch exists
  to have omitted TP V2 from. Confirmed by grep: zero references to any
  `STRATEGY_ID_*` constant anywhere in `Risk/RiskEngine.mqh` or
  `Risk/PositionSizer.mqh`.

## New deterministic tests (SafetyTests.mqh Tests 96-99)

| Test | Proves |
|---|---|
| 96 `QBTestTenDirectionalCandidates` | A full 10-candidate array (5 strategies x BUY+SELL) is scored and arbitrated correctly in one call -- the highest-confidence candidate (TPV2 SELL) wins and all other 9 are explicitly marked `REJECT_ARBITRATION_LOST`, proving the loop scales past the old 8-element bound with no omitted element. |
| 97 `QBTestArbitrationOnePositionLimit` | TP V2 is subject to the same one-position/no-opposite-signal gate as any strategy: an existing long blocks a new TPV2 SELL (`REJECT_CONFLICTING_SIGNAL`) and a new TPV2 BUY same-direction stack (`REJECT_EXPOSURE_LIMIT`); the identical TPV2 candidate is accepted when no position is open -- isolating the block to position state, not a hidden TPV2-specific rejection. This is the deterministic counterpart to the organic MR-blocks-TPV2 collision found in Phase 5. |
| 98 `QBTestArbitrationEqualScoreTieHighestScore` | Default `ARBITRATION_HIGHEST_SCORE` tie-break (strict `>`, first-seen wins) is symmetric regardless of whether TP V2 or another strategy occupies the first slot -- no accidental priority for or against TP V2. |
| 99 `QBTestAllocationEngineIncludesTPV2` | `CAllocationEngine` treats TP V2 as a fully independent, correctly-keyed strategy under all three modes: `ALLOC_EQUAL` stays 1.0, `ALLOC_CONFIDENCE` gives TP V2 a distinctly higher weight than a lower-confidence strategy, `ALLOC_PERFORMANCE` gives TP V2 a distinctly higher weight than a worse-performing strategy. |

Combined with Test 94 (regime-priority compatibility) and Test 95 (five
simultaneous candidates, TPV2 wins on merit and loses to each of the
other four in turn), all Phase 6 checklist items are now covered by
either code-inspection audit (candidate ordering, fifth-strategy loop
inclusion, allocation weights) or a deterministic test (ten directional
candidates, TPV2 winning/losing arbitration, FBO/MR/BO/BO beating TPV2,
equal-score ties, one-position-limit/exposure-constrained arbitration).

**Not covered by a dedicated new test** (already true by construction,
no test needed): disabled-strategy and killed-strategy exclusion --
`ENUM_QB_MODE`/`InpXX_Enabled` gates and `KillSwitch.mqh` (index-bounded
by `QB_STRAT_COUNT`, fixed in Phase 2/D005) both operate upstream of
`Arbitrate()`, so a disabled or killed strategy's candidate is simply
never constructed and never reaches the arbitrator -- there is no
arbitrator-side code path that could accidentally admit one.

## Compile / test status

Compile: `0 errors, 0 warnings` (MetaEditor GUI compile, confirmed by
EX5 timestamp refresh 12:20 vs source edit 12:05).
Self-test regression (Shadow, `InpSelfTestOnInit=true`,
`QuantBeast.SelfTestDetail.20260722.ini`): **102 passed, 0 failed**
(up from 98; Tests 96-99 all pass).

**Broker orders transmitted for this phase: none** (pure code audit and
deterministic fixture tests).
