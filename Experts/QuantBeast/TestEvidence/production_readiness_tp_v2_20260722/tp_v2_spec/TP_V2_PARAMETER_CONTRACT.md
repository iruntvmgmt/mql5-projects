# TP V2 parameter contract

Every threshold below is fixed **before** any TP V2 backtest evidence is
gathered (the user's explicit build-then-test sequencing for this sprint --
implementation and specs finish first, the real evidence run happens last).
None of these were chosen to maximize trade frequency; each cites the prior
empirical observation or existing codebase convention it is grounded in.
Changing any of these after evidence exists requires a new `DECISION_LOG.md`
entry and a `TP_V2_SPEC_VERSION` bump -- never a silent edit.

## Prior empirical grounding (observed before this spec was written)

From this repository's own 2026-07-22 XAUUSD M5 research (all pre-dating this
spec, all cited by path):

- `tp_structure_decomposition_20260722/README.md`: within TP-structure-
  rejected rows on a real 2026-06-22 true-tick window, observed candle
  displacement was broad (`0.017..1.803` ATR), **median 0.325 ATR**.
  Directional efficiency floor of `0.4` and slope floor of `0.3` are the
  shared structural classifier's own coherent, already-in-production
  thresholds (not independently invented here).
- `tp_displacement_matrix_20260722/README.md`: lowering the *shared*
  structural classifier's displacement threshold to `0.8` or even `0.6`
  produced **no change** in TP reachability -- most rejected rows were
  `STRUCTURE_BALANCED`/`STRUCTURE_FAILED_BREAKOUT`/`STRUCTURE_BREAKOUT_ATTEMPT`,
  not simply under-threshold. This is direct evidence that the shared
  classifier is architecturally the wrong sole authority for a multi-bar
  sequential hypothesis -- exactly why V2 builds its own decoupled trend-
  integrity/invalidation model instead of tuning that classifier further.
- `structural_threshold_coherence_20260722/README.md`: slope threshold `0.3`
  is shared and coherent across `TrendState`/`StructuralState` as of this
  freeze; V2 reuses it rather than inventing a separate value.
- `tp_value_return_diagnostics_20260722/README.md`: `moving_toward_value`,
  `value_return_progress`, `crossed_into_value` are real bar-over-bar
  contraction fields (added specifically because the legacy
  `returning_to_value` conflated location with direction of travel) --
  V2's `PULLBACK_ACTIVE` local condition uses these, not the legacy proxy.

## Research defaults (`Include/QuantBeast/Strategies/TrendPullbackV2Engine.mqh`)

| Constant | Value | Grounding |
|---|---:|---|
| `QB_TPV2_MIN_TREND_PERSISTENCE` | 5 bars | V1's existing `m_minTrendPersistence` default (`TrendPullbackEngine.mqh`) -- an already-used, already-coherent floor, not re-derived from scratch. |
| `QB_TPV2_MIN_DIR_EFFICIENCY` | 0.40 | Matches the shared structural classifier's own hardcoded floor (`tp_structure_decomposition_20260722`) -- deliberately equal, not looser, to avoid recreating the input/classifier incoherence that report documented (TP input `0.3` vs. classifier `0.4`, "does not make the input wholly inert but prevents it from relaxing the impulse path"). |
| `QB_TPV2_MIN_IMPULSE_DISPLACEMENT` | 0.30 ATR | Equals the observed **median** displacement (`0.325`, rounded to the already-used `0.30` value from V1's `QB_TP_OBS_IMPULSE_MIN_DISPLACEMENT`) -- a "typical" impulse candle by this window's own distribution, not a loosened floor chosen to catch more bars. |
| `QB_TPV2_MIN_RETRACEMENT_DEPTH` | 0.10 | V1's existing pullback-depth floor (`TrendPullbackEngine.mqh` `EvaluateLong`/`EvaluateShort`) -- excludes trivial noise-level retracements. |
| `QB_TPV2_MAX_RETRACEMENT_DEPTH` | 0.618 | V1's existing `m_maxPullbackDepth` default -- standard Fibonacci retracement convention, already in production use, not re-derived. |
| `QB_TPV2_MAX_LIFECYCLE_AGE` | 20 bars | V1's existing `m_maxPullbackBars` default -- 100 minutes on M5, already-used bound. |
| `QB_TPV2_INVALIDATION_ATR` | 0.5 ATR beyond `impulse_start_price` | V1's existing `m_stopBeyondStruct` default (`0.5`) -- reused here as the lifecycle's own invalidation distance rather than inventing a new number. |
| `QB_TPV2_MAX_SPREAD_PTS` | 35.0 points | V1's existing `m_maxSpreadPts` default -- unchanged convention. |
| `QB_TPV2_REJECTION_WICK_ATR` | 0.30 ATR | Reuses the same `0.30` figure already established as "a moderate, meaningful" threshold elsewhere in this codebase (impulse displacement), applied to `rejection_wick_upper`/`rejection_wick_lower` (already ATR-normalized fields) for the default trigger. |
| `QB_TPV2_RETEST_TOLERANCE_ATR` | 0.15 ATR | Half of `QB_TPV2_REJECTION_WICK_ATR` -- a bounded "close enough to the broken level" tolerance for the optional break-retest variant, not independently tuned. |
| `QB_TPV2_RETEST_MAX_BARS` | 5 bars | One quarter of `QB_TPV2_MAX_LIFECYCLE_AGE` -- bounded, not tuned. |
| `QB_TPV2_TARGET_EXTENSION_R` | 1.618 | V1's existing `m_targetExtensionR` default -- same Fibonacci-extension convention, unchanged. |

## Trigger set (Part C)

All four variants share identical upstream trend/impulse/pullback/integrity/
invalidation logic (the state machine in `TP_V2_STATE_MACHINE.md`) -- only
the `RESUMPTION_ARMED -> TRIGGERED` check differs, so any comparison between
them isolates trigger behavior alone.

1. **Closed-bar micro-structure break** (`ENUM_TPV2_TRIGGER_MICROBREAK`): a
   completed bar's close breaks back past the pullback's own counter-extreme
   (the running high/low recorded during `PULLBACK_ACTIVE`, tracked the same
   way V1 tracks `impulse_extreme`) in the nominated direction. Self-
   calibrating -- no additional numeric threshold.
2. **Rejection + directional confirmation** (`ENUM_TPV2_TRIGGER_REJECTION_CONFIRM`,
   **default**): a completed bar shows a rejection wick
   `>= QB_TPV2_REJECTION_WICK_ATR` against further retracement, followed by
   the next completed bar closing in the nominated direction beyond the
   rejection bar's close.
3. **Displacement reclaim** (`ENUM_TPV2_TRIGGER_DISPLACEMENT_RECLAIM`): a
   completed bar displaces `>= QB_TPV2_MIN_IMPULSE_DISPLACEMENT` (same floor
   as the original impulse -- a reclaim should be at least as committed) and
   closes beyond the pullback's midpoint (`(impulse_extreme +
   impulse_start_price) / 2`).
4. **Break-retest** (`ENUM_TPV2_TRIGGER_BREAK_RETEST`, optional research
   variant): after a micro-structure break (#1) occurs, price must retest
   within `QB_TPV2_RETEST_TOLERANCE_ATR` of the broken level within
   `QB_TPV2_RETEST_MAX_BARS` bars and hold (no invalidation-level breach)
   before the trigger confirms.

### Default trigger selection

**Rejection + directional confirmation is the default**
(`InpTPV2_TriggerMode` default value), because it is the most literal
embodiment of the economic hypothesis's own wording -- "demonstrates renewed
directional control." A rejection wick against continued retracement,
confirmed by a directional close, directly measures the market rejecting
further adverse movement at that specific point; a bare micro-structure
break (#1) is weaker evidence of *control* (it only shows price moved, which
noise can also do), and displacement reclaim (#3) requires a large committed
bar that may only fire well after control was already re-established. This
was decided from the hypothesis wording, not from which variant would
produce the most historical trades -- no historical trade count was consulted
before making this choice (Decision D004, `DECISION_LOG.md`).

The other three remain explicit, individually selectable research variants
(`InpTPV2_TriggerMode`) -- never silently swapped in as the default without a
`DECISION_LOG.md` entry and new evidence.

## Experimental gating

`InpEnableTPV2Experimental` (default `false`) gates whether a `TRIGGERED`
episode's constructed signal is ever marked `valid=true`. With it `false`,
TP V2 still runs its full lifecycle and journals every transition/rejection
(for evidence-gathering purposes), but every constructed signal is forced
invalid with reason `TPV2_EXPERIMENTAL_DISABLED` and is never passed to
arbitration -- structurally identical in guarantee to V1's tracker being
unreachable from execution, verified by dedicated test coverage (see
`TP_V2_REASON_CODES.md` and `../tp_v2_tests/`).
