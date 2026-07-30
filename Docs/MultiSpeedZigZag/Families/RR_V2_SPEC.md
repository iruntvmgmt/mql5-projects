# Range Rotation v2 — Prospective Specification

Status: formulas `FROZEN_SPEC`; input ownership not proven; implementation prohibited.

## Hypothesis and opportunity

A mature, width-stable, medium-contained range with separated confirmed boundary pivots and rotations away rejects a boundary and rotates toward its midpoint. Nearby bars are not confirmed touches. No-break-on-current-bar is not lifetime containment.

One range event starts when all maturity conditions first become true and ends on acceptance beyond a boundary, structural escape, expiry, or reset. One boundary rotation lifecycle may emit once.

## Construction and sequence

The construction/comparison window excludes the current trigger bar. Boundaries and midpoint freeze at range maturity; replacement requires a new range event.

| State | Guard | Next | Emit | Same-call re-arm |
|---|---|---|---|---|
| BUILD | confirmed separated touches and stable width/containment mature | READY | no | no |
| READY | eligible boundary rejection | ARMED | no | no |
| ARMED | rotation trigger and midpoint R pass | EMITTED | once | no |
| active | excess/acceptance/medium escape/expiry | WAIT_RESET | no | no |
| WAIT_RESET | old range invalid and new construction matures | BUILD | no | no |

## Frozen formulas and identity

`SIX_FAMILY_AMBIGUITY_DECISIONS.md` freezes the 24-bar construction, six-width CV `<=0.10`, pivot proximity, three-bar separation, `0.50 ATR` rotation, lifetime containment, `0.15 ATR` excess, two-close acceptance and midpoint `>=1R`. Lifetime containment remains blocked until the owned medium event stream exists.

```text
origin_id   = RR2|symbol|tf|range_start|range_end|boundary_hash
sequence_id = origin_id|side|REJECT|rejection_time
event_id    = sequence_id|ROTATE|trigger_time
```

Metadata types every boundary pivot ID/time, separation and rotation measure, rolling widths/stability, medium events over range life, rejection, midpoint and R. Target is frozen midpoint; entry/stop require reviewed formulas. Simulator/production parity and v2 production allocation remain blocked.
