# Six-Family Ambiguity Decisions

Freeze basis: economic meaning, determinism and auditability only. No performance output was inspected. These are prospective v2 formulas; they do not modify D031-D033 code.

Approval `FROZEN_SPEC` means the formula is approved for specification and invariant tests. It does not authorize implementation; ownership and shared infrastructure gates still apply.

## Shared decisions

- Structural ownership: only a valid `MSZZStructuralEventRecord` may supply break level or impulse fields. Current snapshot combinations are rejected.
- Candidate evidence: `MSZZ_RESEARCH_CANDIDATE_V2` plus the family extension registry is mandatory.
- Execution: policy `MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST` is mandatory in both languages.
- Bar convention: structural/comparison windows contain only closed bars strictly before the trigger bar.
- ATR notation: `ATR(n,t)` is the arithmetic mean true range over the `n` closed bars ending at `t`, with standard previous-close true range. The ATR value is copied when used.

## Momentum Continuation

- Event-owned impulse: one valid direction-matched fast structural event. Origin and extreme are its stored fields; mixing snapshot pivots is forbidden.
- Quality: `impulse_distance_atr >= 1.0` and directional efficiency `abs(close_end-close_origin)/sum(abs(close_i-close_i-1)) >= 0.60` across origin through event bar.
- Pause duration: 2 through 6 fully closed bars after the event bar.
- Pullback fraction: maximum adverse distance from impulse extreme divided by immutable impulse distance; valid interval `[0.20,0.50]`.
- Resumption: long closes above the preceding pause bar high; short closes below its low.
- Invalidation: any opposite-direction **medium** structural event confirmed after arm, pullback fraction above 0.50, or seventh pause bar. Terminal states require a new structural event.

## Break-Retest Continuation

- Broken level: `broken_level_price` and ID from one valid medium structural event.
- Break quality: close distance at least `0.10 * ATR(14,event)` and body at least `0.50` of event-bar range.
- Retest: first eligible touch after at least two completed bars and within ten bars. A touch intersects `level +/- 0.10*arm_ATR`.
- Rejection: freeze the first touch bar that closes back on the breakout side and whose body is at least half its range. Later touches cannot replace it.
- Penetration: maximum beyond-level penetration divided by arm ATR must not exceed `0.15`.
- Over-test: count distinct touch bars separated by at least one non-touch bar; third touch invalidates.
- Trigger: directionally breaks the frozen rejection-bar extreme. New lifecycle requires a new medium break event.

## Compression Breakout

- `short_ATR = ATR(5,t-1)`; `long_ATR = ATR(50,t-1)`.
- Prior construction window: 12 closed bars `[t-12,t-1]`, excluding trigger `t`.
- Range width: `max(high)-min(low)` over that window.
- Compression: `short_ATR/long_ATR <= 0.70` and range width `<= 1.50*long_ATR`.
- Maturity: both conditions hold on six consecutive evaluations; all belong to one episode until either fails.
- Direction: matching valid medium structural event/leg; slow direction is metadata only.
- Breakout: close beyond frozen window boundary. Extension `(abs(close-boundary)/ATR(14,t)) <= 0.50`.
- Obstruction: reject if the nearest owned opposing medium level lies at less than `1.0` proposed initial R from entry.
- Reset: at least one evaluation with either compression condition false.

## Trend Pullback

- Value: UTC-session anchored typical-price VWAP, reset at 00:00 UTC; anchor ID includes UTC date and time-authority ID.
- Pre-pullback trend impulse: valid direction-matched fast structural event, immutable.
- Pullback start: first bar after the event whose close moves toward VWAP.
- Distance: `abs(close-VWAP)/ATR(14,t)`.
- Minimum approach: distance decreases by at least `0.50 ATR` from event close to the best pullback close.
- Proximity band: best distance `<= 0.25 ATR`; crossing VWAP by more than `0.15 ATR` invalidates.
- Resumption: after proximity, long closes above prior bar high; short below prior bar low, while medium direction remains aligned.
- Reset: opposite medium event, invalidation, emission or expiry; new lifecycle requires a new owned impulse.

## Range Rotation

- Construction window: 24 prior closed bars, trigger excluded.
- Width series: high-low width of each trailing 24-bar window at the last six evaluations.
- Stability: population coefficient of variation of those six widths `<= 0.10`.
- Touch: a confirmed fast pivot within `0.10*ATR(14,pivot confirmation)` of a frozen boundary.
- Minimum touches: two highs and two lows; same-side confirmations separated by at least three bars.
- Rotation away: after each touch, a later close must move at least `0.50*ATR(14,touch)` toward midpoint before that side can count another touch.
- Lifetime containment: every confirmed medium pivot after range start is within frozen boundaries and no medium break event closes outside.
- Boundary excess: penetration `<= 0.15*arm_ATR`; acceptance is two consecutive closes outside and is terminal.
- Target: frozen midpoint. Geometry requires midpoint reward/risk `>= 1.0`.
- Reset: acceptance or lifetime-containment failure, followed by a completely new 24-bar construction window.

## Remaining blocked inputs

The formulas contain no qualitative guards, but MC/BRC/TP cannot consume them until the structural record is implemented and proven. CBR/RR obstruction/containment also require event-owned medium records. SSR requires a committed transition table for each dataset and a separately frozen range-completeness minimum. Therefore no family is authorized.
