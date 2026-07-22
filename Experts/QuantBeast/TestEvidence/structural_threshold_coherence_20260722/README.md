# Structural threshold coherence — 2026-07-22

## Repair

`StructuralState` now receives the same `InpTrendSlopeThreshold` supplied to
`TrendState`. Its impulse and pullback slope gates no longer retain an
independent hard-coded `0.3` when the configured classifier threshold changes.
The default remains `0.3`.

## Deterministic verification

Test 33 now classifies a synthetic `slope_norm=0.25` trend probe under both
configurations. It must remain `STRUCTURE_BALANCED` at `0.3` and become
`STRUCTURE_IMPULSE` at `0.2`.

- Compile: **0 errors, 0 warnings**.
- Combined regression: **65 passed, 0 failed**, 22,080 ticks and 1,104 bars.
- No broker orders transmitted; all market comparisons ran in Shadow mode.

## Market verification

Both true-tick comparisons used 880 decisions over XAUUSD M5 on 2026-06-22:

- Fully pinned default baseline (`0.3`): `7,904,934..8,474,266`.
- Fully pinned TP combined variant (`0.2`, TP efficiency `0.3`, HTF agreement
  off): `8,474,266..9,043,702`.

The pinned default report is identical to the pre-repair baseline, proving the
default behavior did not change. The combined TP report is also identical to
its pre-repair counterpart: TP still produced no candidates, with first
failures distributed as 160 directional trend, 58 impulse/pullback structure,
and 2 trend persistence.

Therefore the hard-coded threshold was a real configuration-coherence defect,
but not the remaining TP reachability cause in this sample. The 58 structure
failures are now attributable to the other structure requirements—impulse
needs efficiency and displacement; pullback needs equilibrium distance and a
return-to-value state—not to a stale slope threshold.

An intermediate run using the older acceptance profile inherited TP values
from the preceding job and was excluded. `QuantBeast.Reachability.00_PinnedBaseline.ini`
is the canonical independently reproducible baseline for this matrix.
