# TP impulse displacement matrix — 2026-07-22

## Change

The structural impulse displacement threshold is now configurable through
`InpStructureImpulseMinDisplacement`, defaulting to the prior value `1.0`.
`RegimeEngine` passes it to `StructuralState`; deterministic Test 33 proves a
`0.8` displacement probe remains balanced at threshold `1.0` and becomes
impulse at `0.6`.

## MT5 schema verification

The first attempted `0.8` run was invalid: MT5 omitted the new input from its
effective schema and reproduced the `1.0` funnel. The connected terminal had
no open positions or orders, so it was safely restarted. After restart, the
effective-input log explicitly recorded `0.8` and later `0.6`. The invalid
pre-restart slice is excluded.

## Controlled result

Both valid variants used the pinned TP combined configuration on XAUUSD M5
true ticks for 2026-06-22, with 880 decisions each:

- `0.8`: `10,199,990..10,778,134`
- `0.6`: `10,778,134..11,356,278`
- `0.6` classifier-state rerun: `11,356,278..11,937,582`

Neither `0.8` nor `0.6` changed the acceptance funnel. TP remained at zero
candidates: 160 directional-trend failures, 58 structure failures, and 2
trend-persistence failures.

The state-aware rerun explains why. The 58 structure rows were classified as:

| Structural state | Rows |
| --- | ---: |
| Balanced | 40 |
| Failed breakout | 14 |
| Breakout attempt | 4 |

At threshold `0.6`, four rows passed all impulse numeric predicates but were
preempted by the higher-priority `STRUCTURE_FAILED_BREAKOUT` state. Six rows
were otherwise impulse-qualified but still had displacement `0.203..0.419`.
Thus the moderate matrix correctly produced no migration; reaching those rows
would require an aggressive threshold near `0.4`, and would still not override
the classifier's deliberate breakout-state precedence.

## Decision

Keep the configurable threshold and its `1.0` default, but do not lower the
production default from this sample. TP absence is now evidence of missing
complete trend-pullback/impulse states in this window, not a risk/stop defect.
The next research step should broaden the market windows before testing `0.4`.

## Verification

- Compile: **0 errors, 0 warnings**.
- Combined regression before market runs: **65 passed, 0 failed**.
- Shadow mode only; no broker orders transmitted.
