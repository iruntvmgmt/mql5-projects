# TP V2 reason codes

Every state transition and every rejection carries an explicit machine-
parseable reason code, journaled the same way V1 tags every rejection with
`lifecycleVersion=`/`lifecycle=` (`MakeLifecycleRejected()`). V2 additionally
tags every entry (not just rejections) so the full transition history of an
episode is reconstructable from the journal alone, per the audit protocol's
auditability rule ("a future auditor must be able to answer... from
repository files alone").

Prefix convention: `TQ_` = trend qualification, `IMP_` = impulse, `PB_` =
pullback, `ARM_` = resumption-armed, `TRIG_` = trigger, `INV_` = invalidation,
`EXP_` = expiry, `GEOM_` = geometry/signal construction.

## Entry codes (one per forward state transition)

| Code | Meaning |
|---|---|
| `TQ_ENTER_TREND_QUALIFIED` | Directional trend, not exhausted, persistence and efficiency floors both held for `QB_TPV2_MIN_TREND_PERSISTENCE` bars *before* any impulse check ran. |
| `IMP_ENTER_IMPULSE_ACTIVE` | A completed, direction-aligned candle displaced `>= QB_TPV2_MIN_IMPULSE_DISPLACEMENT` while `TREND_QUALIFIED`. |
| `PB_ENTER_PULLBACK_ACTIVE` | A countertrend bar measured retracement depth `>= QB_TPV2_MIN_RETRACEMENT_DEPTH` of the impulse range. |
| `ARM_ENTER_RESUMPTION_ARMED` | Retracement depth in `[QB_TPV2_MIN_RETRACEMENT_DEPTH, QB_TPV2_MAX_RETRACEMENT_DEPTH]` and the local pullback condition indicated the retracement ending. |
| `TRIG_ENTER_TRIGGERED_MICROBREAK` | Trigger #1 confirmed. |
| `TRIG_ENTER_TRIGGERED_REJECTION_CONFIRM` | Trigger #2 confirmed (default trigger). |
| `TRIG_ENTER_TRIGGERED_DISPLACEMENT_RECLAIM` | Trigger #3 confirmed. |
| `TRIG_ENTER_TRIGGERED_BREAK_RETEST` | Trigger #4 confirmed. |

## Rejection / non-advancement codes

| Code | Meaning |
|---|---|
| `TQ_REJECT_TREND_NOT_DIRECTIONAL` | `regime.trend` is neither up nor down. |
| `TQ_REJECT_TREND_EXHAUSTED` | `regime.trend` is `TREND_EXHAUSTED_*`. |
| `TQ_REJECT_PERSISTENCE_BELOW_FLOOR` | `trend_persistence < QB_TPV2_MIN_TREND_PERSISTENCE`. |
| `TQ_REJECT_EFFICIENCY_BELOW_FLOOR` | `dir_efficiency < QB_TPV2_MIN_DIR_EFFICIENCY`. |
| `IMP_REJECT_INSUFFICIENT_DISPLACEMENT` | Candle displacement `< QB_TPV2_MIN_IMPULSE_DISPLACEMENT`; stays `TREND_QUALIFIED`. |
| `PB_REJECT_INSUFFICIENT_RETRACEMENT` | Countertrend bar's retracement depth `< QB_TPV2_MIN_RETRACEMENT_DEPTH`; stays `IMPULSE_ACTIVE` (this is the explicit "shallow pause" non-classification path -- see `TP_V2_SPEC.md`). |
| `ARM_REJECT_DEPTH_OUT_OF_BAND` | Retracement depth `> QB_TPV2_MAX_RETRACEMENT_DEPTH`; stays `PULLBACK_ACTIVE` (not invalidated -- depth alone never invalidates, see `TP_V2_STATE_MACHINE.md`). |
| `ARM_REJECT_LOCAL_CONDITION_NOT_ENDING` | Local pullback condition does not yet indicate the retracement ending; stays `PULLBACK_ACTIVE`. |
| `TRIG_REJECT_NOT_CONFIRMED` | No configured trigger condition met on this bar; stays `RESUMPTION_ARMED`. |
| `TRIG_REJECT_RETEST_TIMEOUT` | Break-retest variant only: `QB_TPV2_RETEST_MAX_BARS` elapsed since the micro-break without a qualifying retest; stays `RESUMPTION_ARMED` (does not itself invalidate -- a missed retest window is not evidence the trend broke). |

## Invalidation / expiry codes

| Code | Meaning |
|---|---|
| `INV_TREND_FLIPPED` | `regime.trend` flipped to the opposite direction's `TREND_STRONG_*`/`TREND_WEAK_*`. |
| `INV_TREND_EXHAUSTED` | `regime.trend` became `TREND_EXHAUSTED_*` in the nominated direction. |
| `INV_EVENT_STATE_ABNORMAL` | `regime.event_state != EVENT_NORMAL`. |
| `INV_PRICE_BEYOND_INVALIDATION_LEVEL` | A completed bar closed beyond the explicit `QB_TPV2_INVALIDATION_ATR` price level frozen at impulse start. |
| `EXP_MAX_LIFECYCLE_AGE` | `lifecycle_bars > QB_TPV2_MAX_LIFECYCLE_AGE` at any state from `IMPULSE_ACTIVE` onward. |

Explicitly **not** a reason code anywhere in this list: a bare
`regime.structure == STRUCTURE_BALANCED` (or any other single-bar structural
classification) reading during `PULLBACK_ACTIVE`. That reading is expected
and does not by itself produce any transition -- the direct fix for V1's
11/16 rejection mode.

## Geometry / signal-construction codes (all only reachable from `TRIGGERED`)

| Code | Meaning |
|---|---|
| `GEOM_REJECT_INSUFFICIENT_RR` | Computed stop/target fail the shared `CheckRiskReward` gate. |
| `GEOM_REJECT_SPREAD` | `market.spread_points > QB_TPV2_MAX_SPREAD_PTS`. |
| `GEOM_REJECT_LOW_CONFIDENCE` | Computed confidence fails the shared `CheckConfidence` gate. |
| `TPV2_EXPERIMENTAL_DISABLED` | Geometry and confidence both passed, but `InpEnableTPV2Experimental == false` -- signal forced `valid=false`, never reaches arbitration. This is the last-checked gate, specifically so that when it is the sole rejection reason, that fact is directly evidence TP V2's non-geometric criteria are organically reachable (the promotion evidence `TP_V2_SPEC.md` requires). |
| `GEOM_ACCEPT` | All gates passed and `InpEnableTPV2Experimental == true` -- `valid=true`, handed to arbitration like any other strategy's signal. |

## Journal fields carrying these codes

- Every `StrategySignal.reason` (rejected or accepted) carries
  `lifecycleVersion=2 lifecycle=<state> lifecycleBars=<n> ... reasonCode=<code>`,
  mirroring V1's tag format exactly (`MakeLifecycleRejected()` equivalent for
  V2) so existing parsing tools (`tp_structure_report.py`'s regex family)
  extend rather than fork.
- A V2-specific outcome/lifecycle journal (separate file from V1's
  `TPOutcomeJournal.csv`, per `../tp_v1_freeze/README.md`'s isolation
  guarantee) records every entry-code transition per episode, not just the
  terminal one, so a full state history is reconstructable per episode ID
  without replaying the tester run.
