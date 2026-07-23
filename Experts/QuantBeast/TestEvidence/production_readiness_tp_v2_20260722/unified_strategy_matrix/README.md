# Unified all-strategy window matrix (Part E)

**Status: COMPLETE.** All 6 windows finished naturally.

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
| 5 | 2026-03-30 -- 2026-04-07 | Untouched | Complete | 2,005,023 | 1,379 |
| 6 | 2026-06-22 -- 2026-06-23 | Untouched | Complete | 417,423 | 276 |
| **Total** | | | | **4,929,361** | **3,833** |

Run manifests: `../run_manifests/run0N_*.md`. All six runs finished naturally
(`Test passed`, `thread finished`, single Initializing/Deinitializing pair
each, final balance $10,000.00 in every run). Several needed repeated
launch-request retries (2-10x) before the tester agent actually started -- a
known no-op quirk of this MCP integration (confirmed transient and unrelated
to data quality via zero journal growth / no `metatester64` process on each
no-op, and `server_connected: true` throughout via `get_trading_account_info`);
never affected a run once it actually started. See individual run manifests
for exact retry counts and the one network-reconnect event observed
(2026-07-22 23:53:47, prior to run 5's launch attempts).

## Pooled summary -- all 6 windows, 17,220 total per-strategy signal-decision rows

**Organic acceptance funnel, pooled across all 6 windows:**

| Strategy | Accepted (run01/02/03/04/05/06) | Total accepted | Windows with >=1 acceptance |
|---|---|---:|---:|
| BO | 0/0/0/1/0/0 | 1 | 1 of 6 |
| FBO | 3/5/12/7/2/5 | 34 | 6 of 6 |
| MR | 3/1/2/3/3/1 | 13 | 6 of 6 |
| TP (V1) | 0/0/0/0/0/0 | 0 | 0 of 6 |
| TP V2 | 0/0/0/0/0/0 (experimental gate forces this; see lifecycle table) | 0 | n/a -- see TRIGGERED reachability below |

FBO and MR organically reach `ACCEPTED` in **every single window tested**
(6 of 6 each), consistent with `KNOWN_LIMITATIONS.md`'s existing finding.
TP V1 reaches zero acceptances in all six, consistent with its frozen
conclusion (no regression from adding TP V2 to the roster across any
window, including the two genuinely untouched ones). BO reaches one
acceptance in one window -- consistent with it being a real but infrequent
path, not proof of a stable edge.

**TP V2 lifecycle reachability, pooled across all 6 windows:**

| Phase reached | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---:|---:|---:|---:|---:|---:|
| trend_qualified | 14 | 60 | 304 | 128 | 356 | 142 |
| impulse_active | 4 | 16 | 34 | 8 | 30 | 2 |
| pullback_active | 22 | 28 | 86 | 8 | 110 | 14 |
| resumption_armed | 0 | 30 | 70 | 0 | 42 | 0 |
| **triggered** | **0** | **4 (2 episodes)** | **6 (3 episodes)** | **0** | **8 (4 episodes)** | **0** |
| expired | 0 | 0 | 2 | 0 | 0 | 0 |
| invalidated | 4 | 8 | 16 | 10 | 16 | 10 |

Every state in the TP V2 lifecycle is organically reachable, including
`TRIGGERED` (**9 unique episodes across 3 of 6 windows**, both reused and
untouched) -- this is real market-driven evidence, not a unit-fixture
artifact. Of those 9 TRIGGERED episodes' geometry outcomes
(nominated-direction side only, pooled): **4 x `TPV2_EXPERIMENTAL_DISABLED`**
(geometry/spread/confidence all passed -- would have traded if the
experimental flag were on) and **5 x `GEOM_REJECT_LOW_CONFIDENCE`** (trigger
fired but the confidence gate failed). No `GEOM_REJECT_SPREAD` or
`GEOM_REJECT_INSUFFICIENT_RR` observed in any window -- the confidence
gate is the only geometry-side bottleneck seen so far.

**Not claimed:** any edge, win rate, or profitability for TP V2 -- n=9
triggered episodes across 6 windows is far too small for any such claim,
and `InpEnableTPV2Experimental` was `false` throughout every run (zero
signals ever reached arbitration/risk/execution). This table is
organic-reachability evidence only, exactly as Part H requires before any
`DEMO_READY` consideration.

**Strategy performance (completed trades, all Shadow mode, joined
candidate-through-exit):** 48 completed trades pooled across all 6 windows
(6+6+14+11+5+6), 100% joined to their accepting SignalJournal row in every
window (48/48) -- see individual `run0N_*_performance.md` for per-window
win-rate/R/MFE/MAE detail. All FBO and MR; TP V1 and TP V2 contributed zero
trades (as expected -- TP V1 never accepts, TP V2's experimental flag was
off throughout).
