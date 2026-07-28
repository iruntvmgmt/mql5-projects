# Strategy State Machines

This document defines compile-independent behavioral contracts for the five reserved strategies. Implementations must preserve these states and transitions exactly unless a later decision log entry supersedes them.

## Shared state vocabulary

Every stateful setup stores:

- `setup_id`
- strategy ID and version
- symbol and timeframe
- direction
- origin event ID
- created bar/time
- current state
- expiry bar/time
- invalidation price
- trigger price
- structural stop candidate
- last transition reason

Allowed terminal states:

- `TRIGGERED`
- `EXPIRED`
- `INVALIDATED`
- `CANCELLED_CONFLICT`
- `CONSUMED`

A setup may trigger once only.

---

## 1031 — Aligned Fast Pullback Continuation

This D027 S1 trigger is deliberately stateless. Slow structure defines the
primary direction, medium must be non-neutral (aligned or the active
correction), and a confirmed fast HL/LH plus its close-confirmed reversal
break emits one candidate. The confirmed fast pullback pivot is the structural
stop. Candidate and family identity are `1031` and `PULLBACK`; the strategy is
disabled by default.

---

## 1020 — Sequential Confirmation

### Hypothesis

A fast structural break provides early information, while a medium break within a bounded window confirms that the move is not merely fast-scale noise.

### States

`IDLE → FAST_ARMED → CONFIRMED | EXPIRED | INVALIDATED`

### Long transitions

1. `IDLE → FAST_ARMED`
   - New fast bullish breakout.
   - Store fast event ID, fast breakout bar, structural stop, and expiry bar.
2. `FAST_ARMED → CONFIRMED`
   - Medium bullish breakout occurs within `confirmation_window_bars`.
   - Slow context requirement is applied according to configuration.
3. `FAST_ARMED → INVALIDATED`
   - Price closes below the stored structural invalidation level.
   - Opposite fast breakout occurs before medium confirmation.
4. `FAST_ARMED → EXPIRED`
   - Confirmation window closes without medium confirmation.

Short logic is mirrored.

### Deduplication

The opportunity origin is the fast breakout. The later medium event strengthens the same opportunity and must not create a second independent entry.

---

## 1040 — Breakout Retest

### Hypothesis

A confirmed projected-line break that revisits and holds the broken line offers a better entry location and filters weak continuation attempts.

### States

`IDLE → BREAK_CONFIRMED → RETEST_ZONE → TRIGGERED | EXPIRED | INVALIDATED`

### Long transitions

1. `IDLE → BREAK_CONFIRMED`
   - A configured speed produces a bullish close-confirmed break.
   - Freeze the line identity and breakout geometry.
2. `BREAK_CONFIRMED → RETEST_ZONE`
   - Price touches or enters the configured ATR/point tolerance around the projected broken resistance.
3. `RETEST_ZONE → TRIGGERED`
   - Closed bar rejects upward and closes above the retest line/tolerance.
4. `BREAK_CONFIRMED or RETEST_ZONE → INVALIDATED`
   - Price closes materially back below the line beyond invalidation tolerance.
   - Opposite structural breakout invalidates the original thesis.
5. `BREAK_CONFIRMED or RETEST_ZONE → EXPIRED`
   - Maximum retest wait bars exceeded.

### Important geometry rule

The retest must use either:

- the line value projected to the retest bar, or
- a frozen breakout-level mode.

These are separate variants and must not be mixed silently.

D027 freezes the implemented variant before Stage 4 results: frozen breakout
level, 12-bar maximum wait, 0.15 fast-ATR touch/reclaim tolerance, and 0.30
fast-ATR close invalidation. An opposite fast breakout also invalidates it.
The setup is serialized after every closed-bar evaluation.

---

## 1050 — Sweep and Reclaim

### Hypothesis

A temporary violation of a confirmed pivot shelf or structural line followed by a close back through it represents failed continuation and liquidity rejection.

### States

`IDLE → SWEPT → RECLAIMED | EXPIRED | INVALIDATED`

### Long transitions

1. `IDLE → SWEPT`
   - Price trades below a confirmed low shelf/support by at least the configured minimum sweep distance.
   - The origin level and deepest excursion are stored.
2. `SWEPT → RECLAIMED`
   - A closed bar returns above the swept level plus reclaim buffer.
   - Optional fast bullish structure confirmation is applied.
3. `SWEPT → INVALIDATED`
   - Price closes below the maximum allowed failure distance.
   - Supporting medium/slow structure changes against the reclaim thesis.
4. `SWEPT → EXPIRED`
   - Reclaim does not occur within the configured bars.

Short logic mirrors using high shelves/resistance.

### Separation rule

A wick through a level and a close through a level are distinct sweep variants. Results must be journaled separately.

D027 implements the confirmed-pivot-shelf variant only: minimum excursion
0.10 fast ATR, closed-bar reclaim buffer 0.05 fast ATR, maximum close failure
0.50 fast ATR, and six bars to reclaim. A wick alone never emits a candidate.

---

## 1060 — Compression Breakout

### Hypothesis

Contracted fast-scale structure inside stable medium/slow context can precede directional volatility expansion.

### States

`IDLE → COMPRESSING → ARMED → TRIGGERED | INVALIDATED`

### Compression measurements

At least two of the following must be available as raw journal features:

- fast support/resistance width divided by ATR
- median fast pivot spacing
- fast pivot count inside a rolling window
- realized range divided by ATR
- medium bars since pivot

### Transitions

1. `IDLE → COMPRESSING`
   - Compression score crosses the entry threshold.
2. `COMPRESSING → ARMED`
   - Compression persists for the minimum duration and context is valid.
3. `ARMED → TRIGGERED`
   - Price closes outside the compression boundary with required direction/context.
4. `COMPRESSING or ARMED → INVALIDATED`
   - Compression dissolves without a qualifying directional break.
   - Context flips before trigger.

### Research rule

Raw compression features must be journaled before optimizing a composite threshold.

D027 uses the already-frozen causal classifier features rather than a new
optimized score: three consecutive `COMPRESSION` bars arm confirmed fast
support/resistance boundaries, followed by a close outside within six bars.
The boundaries are frozen at arming and medium/slow context must support the
release. The classifier's raw compression ratio, normalized ATR, swing
amplitudes, and swing durations remain in the regime journal.

---

## 1070 — Structure Transition

### Hypothesis

A confirmed sequence change in HH/HL/LH/LL conveys more structural information than a projected-line cross alone.

### Bullish transition variants

- `LL/LH → HL/HH`
- first confirmed HL followed by break/confirmation of HH
- fast bullish transition while medium shifts bearish-to-neutral and slow remains bullish

### States

`IDLE → EARLY_TRANSITION → CONFIRMED | FAILED | EXPIRED`

### Long transitions

1. `IDLE → EARLY_TRANSITION`
   - A fast HL forms after bearish fast structure, or a fast HH appears after an HL candidate sequence.
2. `EARLY_TRANSITION → CONFIRMED`
   - Required HH/HL sequence completes according to the selected variant.
3. `EARLY_TRANSITION → FAILED`
   - New LL forms before confirmation.
4. `EARLY_TRANSITION → EXPIRED`
   - Maximum transition duration exceeded.

Short logic mirrors.

D027 implements the classifier's strict four-pivot sequence only:
`LL,LH,HL,HH` or `HH,HL,LH,LL`, with medium direction validating the new
direction. One pivot change cannot emit a candidate. The confirmed fast
opposite-side pivot is the structural stop.

## Persistence contract

All nonterminal setups must survive restart. Reconstruction from closed history is acceptable only if it reproduces the exact same setup ID, state, transition timestamps, and expiry. Otherwise the setup state must be serialized explicitly.
