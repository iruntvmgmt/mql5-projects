# TP V2 state machine

`TP_V2_LIFECYCLE_VERSION=2`. Advances at most once per completed bar (same
`calc_time` dedupe idiom as V1's `ObserveLifecycle()` -- `EvaluateLong` and
`EvaluateShort` both call the observer for the same bar; the second call is a
no-op). All inputs are `features.closed_*` / shift-1 ATR only; nothing reads
a forming bar or current tick for state advancement (current tick is used
only at `TRIGGERED` for the entry price itself, exactly like every other
strategy's `market.ask`/`market.bid` usage).

## Diagram

```
                    trend integrity breaks (any state) ---------------------> INVALIDATED
                                                                                    |
                    max lifecycle age exceeded (any state after                    |
                    TREND_QUALIFIED) ------------------------------------------> EXPIRED
                                                                                    |
                                                                            (both reset to IDLE
                                                                             on the next bar)
IDLE --[trend qualifies]--> TREND_QUALIFIED --[impulse displaces]--> IMPULSE_ACTIVE
                                                                            |
                                                            [countertrend retracement measured]
                                                                            v
                                                                    PULLBACK_ACTIVE
                                                                            |
                                                        [retracement depth in research band,
                                                         local pullback condition holding]
                                                                            v
                                                                  RESUMPTION_ARMED
                                                                            |
                                                          [one of 4 trigger types confirms]
                                                                            v
                                                                       TRIGGERED
                                                            (geometry computed HERE, only here;
                                                             emits StrategySignal iff
                                                             InpEnableTPV2Experimental)
```

`TRIGGERED` is terminal for that episode (the next bar's observation begins a
fresh `IDLE` search) -- it is not re-entered or extended.

## States

### `IDLE`

No active episode. Every bar, checks whether `TREND_QUALIFIED` entry
conditions hold; if so, advances immediately (no bar is "wasted" idling once
qualification exists, matching V1's pattern of same-bar seed detection).

### `TREND_QUALIFIED`

**Entry:** directional `regime.trend` (`TREND_STRONG_*`/`TREND_WEAK_*`, not
`EXHAUSTED`), `features.trend_persistence >= QB_TPV2_MIN_TREND_PERSISTENCE`
bars **before** any impulse candle is considered, and `features.dir_efficiency
>= QB_TPV2_MIN_DIR_EFFICIENCY`. Records `trend_qualified_time`,
`trend_qualified_bars` (running count), and the nominated `direction` (frozen
from this point forward -- see Direction immutability below).

This is the explicit fix for V1's ordering gap: V1's TP-specific seed checked
persistence/efficiency at the *same bar* as the impulse candle, so a strong
single bar occurring without genuine prior trend context could still seed an
impulse. V2 requires the trend to have already been qualified for
`QB_TPV2_MIN_TREND_PERSISTENCE` bars *strictly before* impulse detection
begins.

**Exit forward:** an impulse candle is detected (see `IMPULSE_ACTIVE` entry) ->
`IMPULSE_ACTIVE`.
**Exit to invalidation:** trend integrity breaks (see Trend integrity below)
-> `INVALIDATED`.
**Exit to expiry:** none (no age limit while merely qualified and searching;
the age limit begins at `IMPULSE_ACTIVE`, since that is when a specific,
time-bound episode begins).

### `IMPULSE_ACTIVE`

**Entry:** while `TREND_QUALIFIED`, a completed candle aligned with the
nominated direction displaces `>= QB_TPV2_MIN_IMPULSE_DISPLACEMENT` ATR
(candle range, not just close-to-close). Records `impulse_start_time`,
`impulse_start_price` (the candle's open), and begins tracking
`impulse_extreme` (running max/min of `closed_high`/`closed_low` in the
nominated direction, updated every bar while `IMPULSE_ACTIVE`, exactly like
V1's `m_impulseExtreme`).

**Exit forward:** a countertrend bar (closes against the nominated direction)
measures a retracement depth `>= QB_TPV2_MIN_RETRACEMENT_DEPTH` of the
impulse's own range (`|impulse_extreme - impulse_start_price|`) -> `PULLBACK_ACTIVE`.
**Exit to invalidation:** trend integrity breaks, or price closes beyond the
explicit invalidation level (see below) -> `INVALIDATED`.
**Exit to expiry:** `lifecycle_bars > QB_TPV2_MAX_LIFECYCLE_AGE` -> `EXPIRED`.

A shallow 1-2 bar non-continuation that never reaches the minimum retracement
depth simply stays `IMPULSE_ACTIVE` (the impulse extreme keeps extending on
any new favorable bar) -- this is the structural reason Momentum Continuation
is out of scope for V2 (see `TP_V2_SPEC.md`), not a post-hoc filter.

### `PULLBACK_ACTIVE`

**Entry:** as above.

**Local pullback condition** (bar-level, re-evaluated every bar): the most
recent completed bar continues to move counter to the nominated direction,
OR `features.moving_toward_value`/`features.crossed_into_value` (the real
bar-over-bar contraction fields, not the legacy same-bar-proximity
`returning_to_value` proxy V1 relied on -- see
`tp_value_return_diagnostics_20260722`). This is evaluated **separately**
from trend integrity below; a bar that is locally balanced/consolidating
(low `dir_efficiency` on that single bar, or `regime.structure ==
STRUCTURE_BALANCED`) does *not* by itself invalidate the episode -- only the
higher-order trend-integrity check can invalidate. This is the direct fix for
V1's Known Limitation (`../tp_v1_freeze/README.md`): local balance no longer
silently destroys a valid higher-order trend context.

**Retracement depth** (tracked continuously, same formula as V1's outcome
tracker so V1/V2 depth numbers stay comparable): `depth = |impulse_extreme -
current_closed_close| / |impulse_extreme - impulse_start_price|`, clamped to
report but not gated above `QB_TPV2_MAX_RETRACEMENT_DEPTH` -- a retracement
deeper than the max band is **not** an invalidation by itself (deep
retracements are common and not inherently trend-breaking); it only affects
whether depth is "in band" for advancing to `RESUMPTION_ARMED`.

**Exit forward:** retracement depth is within
`[QB_TPV2_MIN_RETRACEMENT_DEPTH, QB_TPV2_MAX_RETRACEMENT_DEPTH]` AND the
local pullback condition indicates the retracement is ending (mirrors V1's
"returning to value ending the pullback" concept, but built on the
bar-over-bar fields) -> `RESUMPTION_ARMED`.
**Exit to invalidation:** trend integrity breaks, or price closes beyond the
explicit invalidation level -> `INVALIDATED`.
**Exit to expiry:** `lifecycle_bars > QB_TPV2_MAX_LIFECYCLE_AGE` -> `EXPIRED`.

### `RESUMPTION_ARMED`

**Entry:** as above. No new displacement/depth tracking beyond what
`PULLBACK_ACTIVE` already recorded -- this state exists specifically to
isolate "the setup is complete, now watching for a trigger" from "the setup
is still forming," so a trigger firing on the very same bar the setup
completes and a trigger firing several bars later are both handled by the
same downstream logic.

**Exit forward:** one of the four predefined trigger types (see
`TP_V2_PARAMETER_CONTRACT.md` Part C) confirms on a completed bar ->
`TRIGGERED`.
**Exit to invalidation:** trend integrity breaks, or price closes beyond the
explicit invalidation level -> `INVALIDATED`.
**Exit to expiry:** `lifecycle_bars > QB_TPV2_MAX_LIFECYCLE_AGE` -> `EXPIRED`.

### `TRIGGERED`

**Entry:** as above. Geometry (entry/stop/target) is computed **only here**,
never in any earlier state -- earlier states may not construct or expose a
proposed entry/stop/target at all. Stop is placed beyond the pullback's own
invalidation level (never a fixed ATR offset chosen independently of where
the setup would actually be wrong); target uses the configured target mode
consistent with the shared `ComputeTarget`/`ENUM_TARGET_MODE` framework
already used by BO/FBO/MR/TP V1. If `InpEnableTPV2Experimental` is `false`,
a `StrategySignal` is still constructed for diagnostic/journaling purposes
but its `valid` flag is forced `false` and it is journaled as a rejection
with reason `TPV2_EXPERIMENTAL_DISABLED` -- it is never handed to arbitration.

**Exit:** terminal for the episode. The next bar's observation begins fresh
from whatever `IDLE`/`TREND_QUALIFIED` state naturally applies -- `TRIGGERED`
is not held open waiting for a fill or re-checked next bar.

### `INVALIDATED` / `EXPIRED`

Terminal-for-one-bar observations, exactly like V1: the *next* bar's
observation always resets to `IDLE` (with direction cleared) before any new
`TREND_QUALIFIED` check, so an invalidation or expiry can never be read
twice and never blocks a fresh episode from starting on a later bar.

## Trend integrity vs. local pullback condition (the core V1 fix)

Two independently-evaluated checks, both of which can trigger
`INVALIDATED`, but neither of which is the other:

1. **Trend integrity** (higher-order, evaluated at every state from
   `TREND_QUALIFIED` onward): `regime.trend` flips to the opposite
   direction's `TREND_STRONG_*`/`TREND_WEAK_*`, OR `regime.trend` becomes
   `TREND_EXHAUSTED_*` in the nominated direction, OR `regime.event_state !=
   EVENT_NORMAL`. This is a statement about the *broader multi-bar trend*,
   not about any single bar's local character.
2. **Explicit invalidation level** (price-based, evaluated from
   `IMPULSE_ACTIVE` onward): a fixed price level set the instant
   `IMPULSE_ACTIVE` begins -- `impulse_start_price -
   QB_TPV2_INVALIDATION_ATR * atr_at_impulse_start` for a long episode
   (mirrored for short). If any completed bar closes beyond this level, the
   episode is invalidated regardless of what `regime.trend` currently says.
   This level is frozen at impulse start (like V1's `impulse_start_price`)
   and never trails or tightens as the pullback develops -- it answers
   "did this specific impulse's premise get falsified," not "is price
   currently uncomfortable."

Local pullback condition (bar-level: is this individual bar/structure
locally balanced or contracting) is evaluated **only** to gate
`PULLBACK_ACTIVE -> RESUMPTION_ARMED`, never to invalidate. A `regime.structure
== STRUCTURE_BALANCED` bar during `PULLBACK_ACTIVE` is expected and normal
(a pullback often *is* locally balanced) and does not by itself end the
episode -- this is the literal fix for the 11/16 V1 rejection mode documented
in `../tp_v1_freeze/README.md`.

## Deterministic event identity

Same construction as V1's `BuildEventID()`, with the lifecycle version baked
in so V1/V2 IDs can never collide even if compared side by side:
`"TPV2_" + impulseStartTime + "_" + direction + "_" + triggerTime`.

## No-lookahead guarantee

Every field read by every state transition is `features.closed_*`,
shift-1 `atr`, or a `RegimeState` computed from those same closed-bar
features (identical guarantee to V1, verified the same way: Test coverage in
`../tp_v2_tests/` asserts the registration bar's own extreme is never folded
into any subsequent measurement, and that advancing the lifecycle produces
identical results regardless of what any *future* bar's data would be, since
future data is never read at all).
