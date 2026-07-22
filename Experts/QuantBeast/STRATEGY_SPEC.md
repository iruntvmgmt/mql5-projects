# QuantBeast Strategy Specification

**Status:** Current-code specification plus completion requirements.  
**Trading approval:** None of the strategies is approved for live use.

**Build-out note (2026-07-21):** the shared entry-mode / level-source /
stop-mode / target-mode framework called for in the per-strategy "Required
completion" lists below is now implemented additively across all four engines
(break-retest / probe-confirm / displacement / rejection triggers via
`ConfirmCandleTrigger` / `ConfirmLevelTrigger`; `SelectLevel`; `ComputeStop`;
`ComputeTarget`), each defaulting to the previously-hardcoded behavior and
selected by `Inp*_LevelSource` / `Inp*_StopMode` / `Inp*_TargetMode`;
momentum-failure and regime-deterioration exits are wired (default off).
Deterministic reachability/mode coverage is TEST 52-55. The remaining items in
each list below — chiefly expanded deterministic *feature-path* fixtures (e.g.
ordinary-wick false-positive rejection) and per-mode organic validation — are
still open.

## Shared contract

Each strategy derives from `CStrategyBase` and must:

- Implement eligibility, long evaluation, and short evaluation.
- Return `StrategySignal`; never place or modify orders.
- Supply strategy ID, direction, signal time, entry, stop, target, confidence, expected R, setup code, trigger code, rejection code, and reason.
- Use confirmed information only.
- Pass through arbitration, risk validation, sizing, and execution.
- Receive position-opened, updated, and closed callbacks when lifecycle wiring is completed.

Current shared limitations:

- Position callbacks are empty and never dispatched.
- Valid signals do not carry a durable numeric signal ID beyond the journal string ID.
- Rejections preserve evaluated BUY/SELL direction and signal journal IDs include direction.
- Strategy-level hardcoded spread limits coexist with the configurable global spread limit.
- Direct class-level eligibility, valid-long, and valid-short behavior has deterministic coverage for all four engines. Organic true-tick evidence accepted FBO BUY/SELL and produced BO/FBO/TP/MR BUY/SELL rejections; BO/TP/MR accepted lifecycle sequences remain unproven across 6 distinct organic windows tested as of 2026-07-19 (see `TestEvidence/organic_multiwindow_20260719/EVIDENCE.md`), with 88-100% of BO/TP/MR rejections attributable to the eligibility gate itself rather than window selection.

## Strategy 1: Session Volatility Breakout (`BO`)

### Intended model

Trade expansion after compression near an opening-range, session, or recent structural boundary.

### Current eligibility

- Strategy enabled.
- Feature engine reports compression for the configured minimum duration.
- Current ATR percentile rank is no higher than `InpBO_CompressionPct`, so the BO-specific compression-percent input independently affects eligibility.
- Spread is no more than a hardcoded 40 points.
- Event state is normal.
- Volatility is not extreme or shock.
- Liquidity is not unsafe.
- Optional HTF slope direction aligns.

### Current long/short trigger

- Long requires price near the current range high, then beyond it.
- Short requires price near the current range low, then below it.
- Immediate-break and displacement branches exist.
- The candle-close and displacement branches use the just-completed primary bar; immediate-break mode intentionally uses the current quote.

### Current stop and target

- Stop is beyond the opposite side of the current range plus an ATR multiple.
- Target is fixed R from the entry/stop distance.

### Required completion

- Extend the current confirmed prior-range definition with selectable opening/session boundary modes.
- Implement break/retest and probe/confirmation modes or reject unsupported input values.
- Add opening-range and true session-boundary selection.
- Implement acceptance/follow-through/reclaim logic.
- Add structural, ATR, retest, swing, and hybrid stop options.
- Add partial, runner, failed-acceptance, time, and session-end exits.
- Direct long, short, and ineligible tests pass; duplicate, adverse-spread, and organic feature-path tests remain required.

## Strategy 2: Failed Breakout (`FBO`)

### Intended model

Trade a formally measured penetration beyond a meaningful level followed by timely failure and reclaim.

### Current eligibility

- `failed_breakout` or `reclaim_detected` must be true.
- Spread is no more than a hardcoded 40 points.
- Event state is normal.
- Volatility is not extreme or shock.

### Current signal model

- FeatureEngine selects an objective previous-day/session/range level and records the reclaimed level plus sweep extreme.
- Requires the closed bar and current price to be back through the recorded level.
- Applies penetration and maximum-bars checks.
- Stop is beyond the approximate session extreme plus ATR.
- Target uses VWAP/range midpoint when valid. If either level is unavailable or on the wrong side of entry, the corresponding configured R fallback is used: `InpFBO_TargetVWAPR` for VWAP fallback and `InpFBO_TargetMidR` for midpoint fallback.

### Current operational status

FeatureEngine now assigns directional failed-breakout, reclaim, bars-beyond, breakout-distance, reclaim-level, and sweep-extreme fields from completed bars. Direct FBO long, short, and rejection fixtures pass. Organic true-tick evidence produced accepted BUY/SELL Shadow entries and completed trade rows; broader frequency and ordinary-wick false-positive behavior remain unvalidated.

### Required completion

- Expand deterministic feature fixtures for penetration, bars beyond, failure, reclaim, displacement, and ordinary-wick rejection.
- Support previous-day, session, opening-range, confirmed-swing, and recent-range levels.
- Implement reclaim, confirmation-close, retest, and lower-timeframe-displacement entry modes.
- Support sweep, volatility, and confirmed microstructure stops.
- Add opposite-boundary, partial, and runner targets.
- Add deterministic tests preventing ordinary wicks from being mislabeled as failed auctions.

## Strategy 3: Trend Pullback (`TP`)

### Intended model

Enter an established directional move after a controlled pullback and momentum resumption.

### Current eligibility

- Weak or strong directional trend, excluding exhausted states.
- Minimum directional efficiency and trend persistence.
- Optional HTF slope-direction agreement.
- Structure classified as impulse or pullback.
- Pullback age is not greater than `InpTP_MaxPullbackBars` when the relevant swing age is available.
- Normal event state.

### Current signal model

- Measures current price retracement inside the recent range.
- Requires depth between 0.1 and configured maximum.
- Enforces long pullback age from bars since swing high and short pullback age from bars since swing low.
- Uses `returning_to_value` as a weak proxy for pullback completion.
- Exports separate observational diagnostics for actual one-bar contraction
  toward VWAP (`moving_toward_value`, `value_return_progress`, and
  `crossed_into_value`). TP eligibility still consumes the legacy near-value
  proxy until organic evidence supports a state-transition rule.
- Maintains an observation-only closed-bar lifecycle: `idle` → `impulse` →
  `retracing` → `resume_candidate`, with explicit `invalidated` and `expired`
  terminal observations. It advances once per feature snapshot even though
  both directions are evaluated. Lifecycle state is journaled but cannot yet
  authorize a trade.
- Stop is beyond the recent swing/range plus ATR.
- Target is fixed extension R.

### Required completion

- Validate the observational impulse/retracement/resumption lifecycle on
  organic, exact-byte-bounded windows, then define the price anchors needed to
  turn it into candidate logic.
- Implement actual trigger modes such as rejection, micro-break, close confirmation, or retest.
- Add trend maturity/exhaustion constraints.
- Add failed-continuation, regime-deterioration, session, and time exits.
- Add long/short and choppy-regime scenario tests.

## Strategy 4: Mean Reversion (`MR`)

### Intended model

Trade a statistically meaningful deviation back toward equilibrium only in balanced, non-expanding markets.

### Current eligibility

- Balanced structural regime.
- Normalized trend slope below configured maximum.
- No expansion, extreme, or shock volatility.
- No exhausted trend.
- Spread no more than a hardcoded 30 points.
- Normal event state.

### Current signal model

- Long requires negative normalized VWAP deviation and a rejection wick.
- Short requires positive normalized VWAP deviation and a rejection wick.
- Strong opposing trends block entry.
- Stop is based on current range extreme.
- Target is the opposite VWAP standard-deviation band when `vwap_sd` is available; otherwise MR falls back to VWAP, range midpoint, then fixed-R behavior.

### Current statistical implementation

`FeatureEngine` calculates a volume-weighted variance and `vwap_sd`, then assigns `sd_dist` as completed-bar distance from VWAP divided by that standard deviation. The window and OTC tick-volume proxy remain research limitations.

### Required completion

- Define session and rolling VWAP windows explicitly.
- Validate the implemented weighted variance/standard deviation against independent fixtures.
- Confirm value rejection with closed-bar logic.
- Add return-to-value and failure-to-revert management rules.
- Add trend-transition protection and balanced/expanding-regime tests.

## Arbitration contract

The arbitrator may score by confidence, regime confidence, R:R, spread percentile, and HTF alignment. It also applies cooldown, duplicate, direction-conflict, and stacking rules.

Current status and required completion:

- Arbitration rejections are logged after final arbitration/risk status.
- Persist accepted signal IDs and cooldown timestamps.
- Make signal IDs stable and collision-resistant across symbols/timeframes.
- Test all arbitration modes, ties, long/short conflicts, cooldown, duplicates, and restart behavior.

## Strategy acceptance gate

A strategy may be marked complete only when:

1. Every required feature is calculated from confirmed data.
2. Long and short logic has deterministic positive and negative tests.
3. Every supported trigger input maps to a real implementation.
4. Unsupported inputs are rejected explicitly.
5. Stops and targets pass broker legality tests.
6. Rejections are journaled with the correct direction and reason code.
7. Position lifecycle callbacks are dispatched.
8. Training and holdout tester evidence is recorded without claiming profitability from insufficient samples.
