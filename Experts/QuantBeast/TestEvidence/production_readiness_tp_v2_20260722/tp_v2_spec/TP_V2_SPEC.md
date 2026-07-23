# TP V2 specification

```
TP_V2_SPEC_VERSION=1
TP_V2_LIFECYCLE_VERSION=2
TP_V2_OUTCOME_SCHEMA_VERSION=1
```

**Status:** Pre-registration. This document, `TP_V2_STATE_MACHINE.md`,
`TP_V2_PARAMETER_CONTRACT.md`, and `TP_V2_REASON_CODES.md` are committed
*before* any TP V2 implementation exists. Any later change to the hypothesis,
state model, or research-default thresholds must be recorded as a version
change here (bump `TP_V2_SPEC_VERSION`), never silently edited in place.

## Economic hypothesis

> An established directional XAUUSD auction produces a valid impulse,
> undergoes a measurable countertrend correction without invalidating the
> broader trend structure, then demonstrates renewed directional control
> through an explicit resumption trigger with economically valid stop/target
> geometry.

This is a claim about a specific, ordered sequence of market behavior, not
about any single feature crossing a threshold. Four things must all be true,
in order, for the hypothesis to even be tested by a given episode:

1. A trend already existed **before** the impulse (trend does not begin with
   the impulse -- see V1's Known Limitation below, which V2 directly
   addresses).
2. The impulse itself is a genuine displacement, not incidental drift.
3. The correction is a genuine countertrend retracement (price actually
   travels backward by a measurable amount), not merely "a bar or two of
   non-continuation."
4. The correction does not break the higher-order trend structure that
   qualified it in step 1 -- a pullback that invalidates the trend is not a
   pullback, it is a trend change.

## Why TP V2, not a V1 parameter tweak

TP V1's own evidence (`../tp_v1_freeze/README.md`) already shows the defect
this addresses concretely: of 16 naturally-reached V1 `resume_candidate`
events, **11/16 were rejected purely because `regime.structure` (a single
instantaneous, shared, non-TP-specific classifier) disagreed with the
TP-specific lifecycle's own nomination** -- not because the market behavior
was economically wrong. `regime.structure` is a single-bar classification
shared across all four strategies; it was never designed to arbitrate a
multi-bar sequential hypothesis like "impulse, then retracement, then
resumption." Lowering thresholds on that shared classifier (tried and
rejected across three prior sessions -- `tp_displacement_matrix_20260722`,
`structural_threshold_coherence_20260722`, `tp_structure_decomposition_20260722`,
summarized in `TP_V2_PARAMETER_CONTRACT.md`) does not fix this, because the
mismatch is architectural, not a threshold-tuning problem: a shared
single-bar classifier cannot correctly arbitrate a multi-bar sequential claim.

V2 is not a re-tuning of V1. It is a from-scratch lifecycle that builds its
**own** decoupled trend-integrity and invalidation model (an explicit price
level, and a persistence-based trend-integrity check -- see
`TP_V2_STATE_MACHINE.md`), using `regime.trend`/`regime.structure` only as
contextual filters at specific gates, never as the sole authority over
whether a resumption is real.

## Explicitly distinct from

- **BO (initial boundary expansion):** BO trades the *first* break of
  compression/a boundary. TP V2 requires a *pre-existing, already-qualified*
  trend and only trades a *resumption* after a pullback -- it never trades an
  initial expansion.
- **FBO (failed boundary acceptance):** FBO's edge is the level *failing* and
  price reversing away from it. TP V2's edge is the level (the pullback) NOT
  failing the broader trend and price *continuing* in the original direction.
  These are close to opposite claims about the same kind of price action.
- **MR (rotation back toward value):** MR trades reversion *in balanced,
  non-expanding* regimes and is explicitly blocked by a strong opposing
  trend. TP V2 requires a strong pre-existing trend and trades *continuation*
  of it, not reversion away from it.
- **Momentum Continuation (a shallow pause, not modeled by any current
  strategy):** a brief 1-2 bar non-continuation with no measurable retracement
  is explicitly NOT what TP V2 measures. `PULLBACK_ACTIVE` requires a real,
  measured retracement depth (see `TP_V2_PARAMETER_CONTRACT.md`) -- a shallow
  pause that never crosses the minimum retracement floor never leaves
  `IMPULSE_ACTIVE`, and is out of scope for TP V2 by construction, not by a
  post-hoc filter.

## Evidence requirements before TP V2 can trade anything

TP V2 ships **default OFF** behind a new experimental input
(`InpEnableTPV2Experimental`, default `false`) and is wired so that with it
off, TP V2 has zero reachable code path into signal generation, arbitration,
risk, or execution -- identical in structural guarantee to V1's tracker
(`../tp_v1_freeze/README.md`), except TP V2 additionally *can* produce a real
`StrategySignal` once triggered, which is why the off-switch must be airtight
(verified by Test coverage in `TP_V2_PARAMETER_CONTRACT.md` / `../tp_v2_tests/`).

Per the decision rules (`Part H` of the audit protocol): TP V2 cannot become
`DEMO_READY` merely because a unit fixture generates a signal. It needs
organic true-tick lifecycle, trigger, geometry, arbitration, and risk
reachability demonstrated in independent XAUUSD M5 windows -- gathered in
`../unified_strategy_matrix/` at the end of this sprint, per the user's
explicit build-then-test sequencing. Promotion beyond `MECHANICALLY_READY`
requires that evidence; no threshold in `TP_V2_PARAMETER_CONTRACT.md` may be
adjusted afterward to increase trade frequency without new evidence
justifying the change as a decision-logged event.

## Non-goals of this spec

- Not claiming an edge. No profitability claim is made or implied anywhere in
  this document.
- Not a replacement for V1. V1 stays wired, frozen, and available for future
  passive larger-window verification (`../tp_v1_freeze/README.md`).
- Not tuned to produce trades. Every threshold in
  `TP_V2_PARAMETER_CONTRACT.md` is derived from observed XAUUSD M5 feature
  distributions recorded *before* this spec was written, not chosen to hit a
  target trade count.
