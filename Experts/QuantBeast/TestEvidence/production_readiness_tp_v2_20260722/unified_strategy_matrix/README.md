# Unified all-strategy window matrix (Part E)

**Status: IN PROGRESS.** Updated as each window completes.

Six XAUUSD M5 Model=4 (real-tick) windows, run sequentially last in this
sprint (per the user's explicit build-then-test instruction), after TP V2,
the infrastructure audit, and the demo candidate were all fully built and
documented. Window list fixed in advance -- see `DECISION_LOG.md` D007 --
never expanded or altered based on results seen mid-run.

For every window, four reports are generated from the exact same
byte-bounded journal slices (one tester run, multiple analysis angles, per
the "unified pipeline" instruction -- not re-running the tester per
question):

- `<window>_funnel.md` -- `acceptance_funnel_report.py`: per-strategy
  (BO/FBO/MR/TP/TPV2) eligibility/arbitration/risk/sizing/broker/accepted
  breakdown, first-rejection-reason categories.
- `<window>_tpv1_structure.md` -- `tp_structure_report.py`: TP V1's
  observational lifecycle phase distribution (unchanged tool, frozen
  engine -- see `../tp_v1_freeze/`).
- `<window>_tpv2_structure.md` -- `tpv2_structure_report.py` (new this
  sprint): TP V2's 8-state lifecycle phase distribution, reason codes per
  phase, retracement depth distribution, and TRIGGERED-row geometry
  reachability (the direct evidence for "did TP V2 organically reach its
  trigger and pass geometry gates").
- `<window>_performance.md` -- `strategy_performance_report.py` (new this
  sprint): completed-trade outcomes (win rate, mean/median R, MFE/MAE)
  joined candidate-through-exit, by strategy/direction/session/regime.

## Windows

| # | Window | Type | Status | Ticks | Bars |
|---|---|---|---|---:|---:|
| 1 | 2026-01-05 -- 2026-01-06 | Reused (regression reproduction) | Complete | 372,741 | 276 |
| 2 | 2025-01-06 -- 2025-01-07 | Reused (regression reproduction) | Complete | 240,447 | 276 |
| 3 | 2026-02-16 -- 2026-02-20 | Reused (largest V1 TP window) | Complete | 1,030,228 | 1,074 |
| 4 | 2026-06-20 -- 2026-06-24 | Reused (regression reproduction) | Complete | 863,499 | 552 |
| 5 | 2026-03-30 -- 2026-04-07 | Untouched | Running | -- | -- |
| 6 | 2026-06-22 -- 2026-06-23 | Untouched | Pending | -- | -- |

Run manifests: `../run_manifests/run0N_*.md`. All four completed runs finished
naturally (`Test passed`, `thread finished`, single Initializing/Deinitializing
pair each); several needed 2-8 launch-request retries before the tester agent
actually started (a known no-op quirk of this MCP integration, not a data
-quality issue -- confirmed via zero journal growth and no `metatester64`
process on each no-op).

## Pooled summary (4 of 6 windows; updated again once all 6 complete)

**Organic acceptance funnel, pooled across runs 1-4 (2,932 total per-strategy decision rows):**

| Strategy | Accepted (run01/02/03/04) | Total accepted | Windows with >=1 acceptance |
|---|---|---:|---:|
| BO | 0 / 0 / 0 / 1 | 1 | 1 of 4 |
| FBO | 3 / 5 / 12 / 7 | 27 | 4 of 4 |
| MR | 3 / 1 / 2 / 3 | 9 | 4 of 4 |
| TP (V1) | 0 / 0 / 0 / 0 | 0 | 0 of 4 |
| TP V2 | 0 / 0 / 0 / 0 (experimental gate forces this; see lifecycle table) | 0 | n/a -- see TRIGGERED reachability below |

FBO and MR organically reach `ACCEPTED` in every window tested so far,
consistent with `KNOWN_LIMITATIONS.md`'s existing finding. TP V1 reaches
zero acceptances in all four, consistent with its frozen conclusion (no
regression from adding TP V2 to the roster). BO reaches one acceptance in
one window -- consistent with it being a real but infrequent path, not
proof of a stable edge.

**TP V2 lifecycle reachability, pooled across runs 1-4:**

| Phase reached | run01 | run02 | run03 | run04 |
|---|---:|---:|---:|---:|
| trend_qualified | yes (14) | yes (60) | yes (304) | yes (128) |
| impulse_active | yes (4) | yes (16) | yes (34) | yes (8) |
| pullback_active | yes (22) | yes (28) | yes (86) | yes (8) |
| resumption_armed | no | yes (30) | yes (70) | no |
| **triggered** | **no** | **yes (4 rows = 2 unique episodes)** | **yes (6 rows = 3 unique episodes)** | **no** |
| expired | no | no | yes (2) | no |

Every state in the TP V2 lifecycle is organically reachable, including
`TRIGGERED` (5 unique episodes across 2 of 4 windows so far) -- this is
real evidence, not a unit-fixture artifact. Of those 5 TRIGGERED episodes'
geometry outcomes (nominated-direction side only): 2 x `TPV2_EXPERIMENTAL_DISABLED`
(geometry/spread/confidence all passed -- would have traded if the
experimental flag were on) and 3 x `GEOM_REJECT_LOW_CONFIDENCE` (trigger
fired but confidence gate failed). No `GEOM_REJECT_SPREAD` or
`GEOM_REJECT_INSUFFICIENT_RR` observed yet in this sample.

**Not yet claimed:** any edge, win rate, or profitability for TP V2 -- n=5
triggered episodes across 2 windows is far too small, and none were ever
live/experimental-enabled. This table is reachability evidence only.

_(Final pooled numbers across all 6 windows, plus the strategy-performance
join and readiness labels, follow in the final production-readiness
report once runs 5-6 complete.)_
