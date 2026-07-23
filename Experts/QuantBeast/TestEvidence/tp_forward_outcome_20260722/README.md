# TP resume-candidate forward outcome validation — 2026-07-22

## Question

After a TP lifecycle nominates a direction and reaches `resume_candidate`, does
price subsequently produce favorable excursion in that nominated direction
more reliably than adverse excursion? This evidence batch builds and runs the
observation-only forward-outcome tracker needed to answer that, without
enabling TP to trade.

## Source, build, and test status

- Commit at start of this work: `f87af79`.
- Tracker + tests commit: `0dbc43c` (`Include/QuantBeast/Analytics/TPOutcomeTracker.mqh`,
  `SafetyTests.mqh` Tests 65-74, `QuantBeastEA.mq5` wiring, `Constants.mqh`,
  `Configuration.mqh`).
- Reporting tool commit: `26b9e1b` (`Tools/tp_outcome_report.py`).
- `QuantBeastEA.mq5` SHA-256: `5ac554dde1088d0b5e2d466cce1bb5ca8c3b48c10b15175e81f63fb1ebb5e566`
- `QuantBeastEA.ex5` SHA-256: `166fea8b5859e5a0084f45db85d96ce64ffeab775db87d7ccac1aa71ab8ff454`
- `TPOutcomeTracker.mqh` SHA-256: `868a5f4966f28b305cee8c36db0f14dea2011a1344839bf042d51eeb553b8b28`
- MetaEditor compile: **0 errors, 0 warnings**, 47,443 ms.
- Shadow self-test regression: **77 passed, 0 failed** (67 baseline + Tests 65-74),
  `QuantBeast.CurrentRegression.XAUUSD.M5.20260722_2210.ini`, Model=1, 22,080
  ticks, 1,104 bars, natural completion (`OnTester result 0`, `test passed`,
  `thread finished`).

## Phase 1 audit result (no code change)

`TrendPullbackEngine.mqh`'s `ObserveLifecycle()` was re-audited for future
leakage, forming-bar use, duplicate event generation, and BUY/SELL shared-state
risk. All impulse/extreme fields and ATR come from `features.closed_*` /
shift-1 ATR only. The BUY/SELL shared-state risk is real in principle (one
engine instance, `m_lifecycleDirection` is a scalar) but is neutralized by two
independent mechanisms: the `calc_time` dedupe guard, and `RESUME_CANDIDATE`
being structurally a single-bar phase (the very next call always resets
`INVALIDATED`/`EXPIRED`/`RESUME_CANDIDATE` → `IDLE` before any new seed check).
**No defect found; no fix made.**

## Evidence windows

All windows are XAUUSD M5, Model=4 (real-tick), exact byte-bounded slices from
the same continuously-appended journal files on the same terminal/broker
(Coinexx-Demo). Reruns use the same untracked `.ini` profiles as the prior
session (read-only, unmodified). New windows reuse existing untracked
`QuantBeastEA.XAUUSD.M5.*.400.ini` profiles not previously used to design or
validate the lifecycle.

| Window | Profile | Ticks | Bars | Runtime | SignalJournal slice | TPOutcomeJournal slice |
| --- | --- | ---: | ---: | --- | --- | --- |
| 2026-01-05 (rerun) | `QuantBeastEA.XAUUSD.M5.20260105_20260106.400.ini` | 372,741 | 276 | 6m07s | `[18597518,19180466)` | (no events) |
| 2025-01-06 (rerun) | `QuantBeastEA.XAUUSD.M5.20250106_20250107.400.ini` | 240,447 | 276 | 3m40s | `[19180466,19990606)` | `[7992,11914)` |
| 2026-05-04 (rerun) | `QuantBeastEA.XAUUSD.M5.20260504_20260505.400.ini` | 367,390 | 276 | 7m26s | `[19990606,20901338)` | `[11914,12964)` |
| 2026-01-26..30 (new) | `QuantBeastEA.XAUUSD.M5.20260126_20260130.400.ini` | 1,740,398 | 1,104 | 26m47s | `[20901338,23666224)` | `[12964,15970)` |
| 2026-02-16..20 (new) | `QuantBeastEA.XAUUSD.M5.20260216_20260220.400.ini` | 1,030,228 | 1,074 | 17m51s | `[23666224,26656686)` | `[15970,22742)` |
| 2026-06-20..24 (new) | `QuantBeastEA.XAUUSD.M5.20260620_20260624.400.ini` | 863,499 | 552 | 14m22s | `[26656686,28003054)` | `[22742,23708)` |

Every run confirmed via the tester agent log footer: exact ticks/bars,
`OnTester result 0`, `test passed`, `thread finished`, single
Initializing/Deinitializing pair (no mid-run reinit). No positions/orders were
open before any run; no broker orders were transmitted at any point.

`TPOutcomeJournal.csv` byte `[0,7992)` is the file's real header plus 8
synthetic rows written by Tests 65-74 during the regression run in this same
session (`TP_100_up_102` etc., `RegistrationTime` in 1970) — excluded from all
evidence slices below.

**Process note on evidence discipline:** the 2026-01-26 window's TPOutcomeJournal
slice was initially mis-bounded (recorded a mid-run snapshot, 14942, as the
start offset instead of the true prior-window end, 12964), which silently
dropped 2 of 3 real events from that window's first-pass report. This was
caught by cross-checking the phase-count total (6 `resume_candidate` rows / 2 =
3 expected events vs. 1 registered) against the raw file content, and
corrected before any of the numbers below were computed. Documented here per
the "every behavioral claim must point to evidence" rule — this was a
reporting-slice error, not a tracker defect; the tracker's own registration,
update, and finalize logic wrote all 3 events correctly and immediately.

## Lifecycle phase counts (reproducibility check)

| Window | Decisions | Idle | Invalidated | Impulse | Retracing | Resume candidate | Risk/stop evals | Accepted |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026-01-05 (rerun) | 196 | 114 | 64 | 14 | 4 | 0 | 0 | 0 |
| 2025-01-06 (rerun) | 264 | 80 | 122 | 30 | 24 | 8 | 0 | 0 |
| 2026-05-04 (rerun) | 304 | 104 | 166 | 30 | 2 | 2 | 0 | 0 |
| 2026-01-26..30 | 946 | 804 | 94 | 16 | 26 | 6 | 0 | 0 |
| 2026-02-16..20 | 1016 | 772 | 148 | 38 | 44 | 14 | 0 | 0 |
| 2026-06-20..24 | 460 | 430 | 10 | 14 | 4 | 2 | 0 | 0 |
| **Total** | **3186** | **2304** | **604** | **142** | **104** | **32** | **0** | **0** |

The three rerun windows reproduce the prior session's exact phase counts
byte-for-byte (114/64/14/4/0, 80/122/30/24/8, 104/166/30/2/2) — full
determinism confirmed given identical tick data and unchanged lifecycle logic.
32 `resume_candidate` rows across all 6 windows = **16 direction-paired
observations = 16 unique completed-bar events** (0+4+1+3+7+1 = 16 per window,
matching the registered-event counts below exactly — the tracker registered
every lifecycle-level resumption in these windows with no silent drops from
the degenerate-span or ATR guards). TP recorded **zero risk/stop evaluations
and zero accepted signals** in every window, confirming the production
blocker remains entirely upstream of risk management across all 6 windows,
not just the original 3.

## Forward outcome results

Full per-horizon tables: `pooled_tp_outcome_report.md` (cross-window pooled +
per-window breakdown + Baseline B) and `organic_<window>_tp_outcome_report.md`
(per-window detail, generated at the time each window ran).

**Pooled, n=16 events, 5 contributing windows:**

| Horizon | Median MFE (ATR) | Median MAE (ATR) | Fav/Adv ratio | Target-before-adverse rate | n ambiguous same-bar |
| --- | ---: | ---: | ---: | ---: | ---: |
| H3 | 0.751 | 0.666 | 1.13 | 0.50 | 5 |
| H6 | 0.838 | 1.147 | 0.73 | 0.50 | 5 |
| H12 | 1.762 | 1.418 | 1.24 | 0.50 | 5 |
| H24 | 2.330 | 1.577 | 1.48 | 0.50 | 5 |

**By window (H24):**

| Window | n | Fav/Adv ratio | Target-before-adverse rate | Direction |
| --- | ---: | ---: | ---: | --- |
| 2025-01-06 | 4 | 5.04 | 0.75 | strongly favorable |
| 2026-01-26 | 3 | 2.67 | 0.33 | favorable by ratio, mixed by rate |
| 2026-02-16 | 7 | 0.39 | 0.43 | adverse |
| 2026-05-04 | 1 | 0.45 | 0.00 | adverse |
| 2026-06-20 | 1 | 1.98 | 1.00 | favorable |

**Baseline B (direction-shuffled, pooled n=16):** target-before-adverse rate
0.19 at H3 vs. 0.50 real — the real pooled sample resolves favorable-first
more often than its own mirror-image relabeling at the shortest horizon, but
this gap narrows or reverses at longer horizons (see `pooled_tp_outcome_report.md`)
and is not independently informative beyond restating the same 16-event
asymmetry from the opposite side.

**Baselines A/C/D (random bars, trend-direction-without-lifecycle, non-resuming
impulse):** attempted per-window via the read-only `get_chart_history` MCP
call. It returned genuine M5 bar history for the 2026-dated windows (confirmed
for 2026-02-16) but still returned an empty payload for the 2025-01-06 window,
reproducing the exact failure documented in the prior session. Given the
sample is already small (n=16) and — critically — the two largest-n
contributing windows (2025-01-06, n=4; 2026-02-16, n=7) point in **opposite**
directions, full construction of baselines A/C/D was judged disproportionate
to what it could add to that verdict and was not completed in this pass. This
is an honest scope decision, not a silent omission: chart-history availability
for 2026 windows is a new, usable finding for a future pass that wants to
build these baselines out.

## Phase 6 — production rejection-path attribution

Per-event tables: `tp_rejection_attribution_<window>.md`. Join key
(`TPOutcomeJournal.RegistrationTime` == `SignalJournal.Timestamp`) matched
exactly for all 16 events on both the BUY and SELL side.

**Every one of the 16 events was rejected at `EligibilityFailure()` on the
side matching its nominated direction** — never past that first gate, so
geometry (Entry/Stop/Target) was never computed for any of them. The failing
reason splits into two categories:

| Failing reason (nominated side) | Count |
| --- | ---: |
| `structure not impulse/pullback state=STRUCTURE_BALANCED` (or `STRUCTURE_BREAKOUT_ATTEMPT`) | 11 |
| `directional efficiency X below 0.40` | 5 |

**Diagnosis:** the dominant cause (11/16) is **lifecycle/production
eligibility defining different hypotheses, via structural-state preemption**.
`TrendPullbackEngine.mqh`'s own comment states the TP-specific seed path is
"observation-only and deliberately does not alter `EligibilityFailure()`" —
so the lifecycle can nominate a resumption using its own criteria
(`trend_persistence`, `dir_efficiency`, `displacement`≥0.30 ATR) on a bar that
the *shared* `regime.structure` classifier still calls `STRUCTURE_BALANCED`,
not `STRUCTURE_IMPULSE`/`STRUCTURE_PULLBACK`. `EligibilityFailure()` requires
the latter unconditionally. These are two different definitions of "is this a
valid trend-resumption moment," evaluated independently, and by construction
they frequently disagree at the exact bar the lifecycle calls a resumption.
The remaining 5/16 are more plausibly **a true quality filter**: raw
`directional efficiency` 0.32-0.36, meaningfully below the 0.40 floor, not an
obvious structural artifact.

HTF alignment and trigger-confirmation status were never observed for any of
the 16 events (`EligibilityFailure()` returns before reaching those checks),
and pullback depth was never computed for any of them either — both are
downstream of the actual rejection point and are reported as
`not observed (rejected upstream)` rather than a misleading blank.

## Phase 7 — decision

**Outcome A: no reliable directional information (inconclusive).**

- n=16 events is far too small for statistical significance on its own — the
  assignment's own threshold language ("do not claim significance from tiny
  samples") applies directly.
- The effect is **not consistent across windows**: the two largest-n windows
  (2025-01-06, n=4, favorable; 2026-02-16, n=7, adverse) point in opposite
  directions. A pooled H24 fav/adv ratio of 1.48 is entirely a product of one
  favorable window; it does not represent a stable property of the lifecycle.
- Production TP rejects every one of these events at the very first
  eligibility gate, for a structural reason (lifecycle vs. regime-structure
  disagreement) that is a genuine architectural tension, not evidence of a
  hidden edge being wrongly filtered out.

Per the assignment's Outcome A guidance: **no candidate logic is proposed;
the tracker is preserved as-is; evidence collection should be expanded in a
future pass (more windows, ideally enough to get double-digit events per
window) before revisiting this question.** No TP eligibility, risk,
arbitration, or geometry logic was modified in this pass. Readiness remains
exactly `READY FOR SHADOW MODE`.

## Files in this evidence directory

- `organic_<window>_tp_structure_report.md` — lifecycle phase counts per window.
- `tp_outcome_slice_<window>.csv` — extracted, header-restored TPOutcomeJournal.csv rows per window (for reproducible reanalysis without re-running the tester).
- `organic_<window>_tp_outcome_report.md` — per-window forward-outcome report.
- `pooled_tp_outcome_report.md` — cross-window pooled report + Baseline B.
- `tp_rejection_attribution_<window>.md` — per-event Phase 6 production rejection-path table.
