# Known Issues and Production Blockers

## Build verification (updated 2026-07-25)

All four files (EA, both test scripts, parity exporter) now compile with 0 errors on MetaEditor build 6033/6061. `Test_MSZZ_Determinism` and `Test_MSZZ_Clusters` have been executed against real XAUUSD M5 history with PASS results. See BACKTEST_LOG.md for full evidence. Remaining build/test items below are newly identified, not resolved by this pass unless marked FIXED.

### FIXED this pass

- **Compile blocker**: `Include/MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh` declared a local reference bound to an array element (`MSZZOpportunityCluster &cluster=clusters[target];`). MQL5 only permits references as function parameters, not local variables (compiler error 229). Fixed by indexing `clusters[target]` directly.
- **Crash-risk defect**: `ZeroMemory()` was called on structs containing `string` members (`MSZZPivot`, `MSZZSpeedSnapshot`, `MSZZCandidate`, `MSZZOpportunityCluster`) in five sites across `TripleZigZagEngine.mqh`, `StrategySuite.mqh`, `OpportunityClusterEngine.mqh`, and `Test_MSZZ_Clusters.mq5`. MetaQuotes documents this as potentially crash-causing. Fixed by removing the calls where the struct was freshly declared/resized (already safely default-initialized) and by explicit field-by-field reset in `CMSZZTripleZigZagEngine::ResetSnapshot` (see next item for why "just assign a fresh local" was insufficient on its own).
- **Uninitialized-field defect (found via runtime evidence, not static review)**: the first fix attempt for `ResetSnapshot` relied on assigning from a freshly-declared local `MSZZSpeedSnapshot blank;`, assuming MQL5 zero-initializes every field of a struct containing a string. Running `Export_MSZZ_Parity` against real data produced a garbage pivot row (`speed=21048726`, empty `pivot_id`) immediately after the header — proof that plain scalar fields (e.g. the nested `MSZZPivot.valid` flag) are not reliably zero-initialized this way. Fixed by resetting every field of `MSZZSpeedSnapshot` and its four nested `MSZZPivot` members explicitly in `ResetSnapshot`/`BlankPivot`. Re-verified clean (76 pivot rows, zero garbage, zero empty IDs) after the fix.

### Identified, not fixed (behavior/design questions — require a DECISION_LOG entry before changing)

- **Malformed cluster IDs**: `OpportunityClusterEngine::ClusterId()` builds `MSZZC|symbol|timeframe|direction|origin_type|origin_id`, but `origin_id` is itself often an already pipe-delimited breakout/pivot ID (e.g. `BO|XAUUSD|5|1|S|<time>|MSZZ|XAUUSD|5|1|-1|<time>|<time>`). Confirmed empirically: every cluster ID exported by `Export_MSZZ_Parity` on real data contains 17 `|` characters, not the 5 the documented format implies. Any consumer that naively splits on `|` cannot reliably recover the intended fields. Needs either a different delimiter/encoding for the outer ID or a hashed/short origin reference — this is a behavior change and needs a DECISION_LOG entry before implementation.
- **Netting account assumption**: the EA's `CloseOppositeIfNeeded`/`InpOnePositionPerSymbol` logic uses `PositionSelect(_Symbol)`/`PositionGetInteger(POSITION_TYPE)`, which assumes a netting account (at most one position per symbol). There is no `ACCOUNT_MARGIN_MODE` check. Empirically confirmed relevant: the isolated test demo account (Coinexx-Demo 870012) is a **hedging** account. Shadow mode never exercises this path (no real orders are placed), so it has not caused an observed failure, but it is unverified/unsafe for any account where live execution is eventually authorized on a hedging account.
- **Event persistence failure after successful order submission**: in `ExecuteCluster`, if `ConsumeEvent()` fails after a live order was successfully submitted, the EA only logs `"MSZZ WARNING: cluster executed but persistence failed."` with no compensating control (retry, halt, or alternate ownership marker). On restart, this could allow the same cluster to be reprocessed. Not exercised in this pass since all three live-execution gates were closed in every run.
- **Freeze-level conservatism**: `ExecutionGuard::ValidateStops` uses `MathMax(stops_level, freeze_level)` as the minimum SL/TP distance for both. Freeze level normally governs modification of an existing order/position near market, not initial SL/TP placement on a new position. This is overly conservative rather than unsafe, but is a documented deviation from typical broker semantics.

### Reviewed and accepted (not a defect)

- The EA's `#property version "0.300"` triggers MetaEditor warning 68 ("incompatible with MQL5 Market, must be xxx.yyy") because Market publishing requires a major version ≥1. Confirmed by testing `"1.00"` (0 warnings) vs `"0.300"` (warning) side by side. Left as `0.300` because that is the branch's real, documented milestone number everywhere in these docs, and this EA is not being published to MQL5 Market. **The build should not be described as zero-warning** — it is zero-error, one reviewed/accepted warning.

## Structural engine

- Full-history rebuild is O(bars × speeds × ATR length) each new bar.
- No incremental/rebuild parity harness exists yet.
- Only last-two-confirmed-pivot trendlines are implemented.
- Reversal source is wick-based and breakout source is close-based; other source modes are deferred.

## Strategy suite

- Scores are research ranking placeholders.
- Sequential confirmation, retest, sweep/reclaim, compression, and structure-transition strategies are reserved only.
- Formal opportunity clusters are not yet persisted as first-class objects.

## Execution

- Fixed lots only (no account-risk sizing).
- Symbol volume-step normalization, broker stop/freeze-level validation, and a spread gate are implemented in `ExecutionGuard` (updated 2026-07-25 — these were previously listed as absent; see freeze-level conservatism note above for a caveat), but are unexercised by shadow-mode testing since the live-order path never runs with all three gates closed.
- No daily drawdown, trade count, or emergency kill switch.
- Consumed-event memory: the underlying `CMSZZEventStore` file persistence was directly verified to survive a genuine process restart (2026-07-25, see BACKTEST_LOG.md). What remains unverified is the EA's own end-to-end restart behavior on a live/demo chart across real elapsed bar-closes, and the event-persistence-after-successful-order failure mode noted above.
- Position ownership reconstruction is not implemented.
- Netting-account assumption throughout `CloseOppositeIfNeeded`/`InpOnePositionPerSymbol` — see above; empirically the test demo account is hedging-mode.

## Research

- No bar-for-bar Pine parity export has been completed.
- No backtest result supports an edge claim.
- No live or demo authorization should be inferred from the presence of an execution path.