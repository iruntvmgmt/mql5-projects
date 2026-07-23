# Phase 5 -- All-strategy Shadow integration matrix

**No new tester runs were needed.** Phase 3's three runs
(`run_p3_02_20250106_20250107`, `run_p3_03_20260216_20260220`,
`run_p3_04_20260330_20260407`) were already launched with the full
five-strategy roster enabled simultaneously (`InpBO_Enabled=true`,
`InpFBO_Enabled=true`, `InpTP_Enabled=true` (observational V1),
`InpMR_Enabled=true`, `InpTPV2_Enabled=true`,
`InpEnableTPV2Experimental=true`), `InpMode=1` (Shadow), one contiguous
`SignalJournal` byte range `[43107752, 53543326)` across all three. This
is exactly the Phase 5 configuration intent, so this phase re-analyzes
those exact already-committed journal slices rather than re-running the
tester, consistent with this sprint's "one run, multiple analysis
angles" precedent (Phase 4).

## Candidate volume by strategy (pooled, 3 windows, 2568 bar-direction pairs each)

| Strategy | Candidates emitted | Accepted |
|---|---:|---:|
| BO | 2568 | 0 |
| FBO | 2568 | 18 |
| TP (V1, observational) | 2568 | 0 |
| MR | 2568 | 5 |
| TP V2 | 2568 | 3 |

Every strategy produced exactly one row per direction per completed bar
in every window (no strategy silently skipped a bar), confirming the
fifth strategy did not disturb the per-bar evaluation loop for any other
strategy.

## Same-bar candidate collisions (literal same-timestamp emissions)

1284 of 2568 bars (per-window pooled) had rows from >=2 distinct
strategies at the same timestamp (expected -- all 5 strategies evaluate
every bar). Narrowing to bars where >=2 strategies each produced a real,
internally-valid `StrategySignal` (reached at least arbitration/risk,
not merely their own eligibility gate): **0 such bars in these 3
windows.** No organic same-bar two-valid-candidate collision occurred in
187,647 XAUUSD ticks' worth of Shadow evaluation across these windows.
This is an honest negative finding, not a defect -- true multi-strategy
same-bar conflict is evidently rare at this sample size. Same-bar,
multi-valid-candidate arbitration correctness therefore remains proven
by deterministic fixture (`SafetyTests.mqh` Test 95, five simultaneous
synthetic candidates) rather than organic evidence; this gap is recorded
honestly rather than manufactured.

## Cross-strategy position-blocking events (real, organic)

Four bars where a candidate was rejected specifically by arbitration's
existing-position rule (`RejectionReason` contains "existing long/short
positions"):

| Window | Timestamp | Blocked candidate | Reason | Blocking position |
|---|---|---|---|---|
| run_p3_02 | 2025.01.06 07:15:00 | TPV2 SELL | existing long positions | **MR LONG**, open 07:00:00-07:30:02 -- genuine cross-strategy block |
| run_p3_03 | 2026.02.19 10:10:00 | FBO BUY | existing short positions | FBO's own SHORT, open 10:05:00-10:29:35 -- same-strategy self-block |
| run_p3_03 | 2026.02.19 14:10:00 | FBO SELL | existing long positions | FBO's own LONG, open 13:50:00-14:36:26 -- same-strategy self-block |
| run_p3_03 | 2026.02.19 14:35:00 | FBO SELL | existing long positions | FBO's own LONG, open 13:50:00-14:36:26 -- same-strategy self-block |

One genuine **cross-strategy** interaction is organically captured: MR's
open LONG position correctly blocked a TP V2 SELL candidate that was
otherwise internally valid (this is the same episode documented in
`run_manifests/run_p3_02_20250106_20250107.md` as an Outcome B legitimate
rejection). This directly answers Phase 5's "whether one strategy's
state mutates another strategy's lifecycle" at the *position/exposure*
level: yes, correctly, via the shared one-position/no-opposite-signal
gate -- not via any direct cross-strategy state coupling (TP V2's own
lifecycle object is untouched; only the arbitration-level exposure check
rejected it).

## Concurrent-evaluation proof (TP V2's own trade window)

During TP V2's one real organic Shadow trade in this dataset
(2026.02.18 11:40:00 SELL, open until 12:05:05, see
`run_manifests/run_p3_03_20260216_20260220.md`), the raw journal for
11:40-11:55 shows BO, FBO, TP (V1), and MR all continuing to emit full
per-bar candidate rows on their own merits (BO: compression eligibility;
FBO: no failed breakout/reclaim; TP V1: trend not directional; MR:
deviation/rejection-wick checks) while TP V2 held its position. No other
strategy was blocked by TP V2's open position in this specific window
(none show an "existing position" rejection during 11:40-12:05) --
consistent with FBO/MR/BO/TP simply not producing an opposite-conflicting
candidate at that moment, not with an evaluation freeze. **TP V2's own
lifecycle also kept updating post-trigger** (resets to `idle` and
continues bar-by-bar rather than freezing in `TRIGGERED`), confirmed by
the 11:45/11:50/11:55 rows showing `lifecycle=idle` in both directions.

## One-position-limit verification

All 26 completed trades across the 3 windows (FBO 18, MR 5, TP V2 3) were
checked pairwise for time-overlap: **zero overlapping positions found**
-- the one-active-position cap held for every strategy combination
observed, with no strategy ever opening while another strategy's Shadow
position was still active.

## Rejection-code distribution by strategy (pooled)

| Strategy | Dominant rejection code(s) | Notes |
|---|---|---|
| BO | 5 (own eligibility, 2468), 23 (63), 24 (35) | rarely reaches downstream gates |
| FBO | 5 (2190), 23 (211), 24 (95), 8/risk (47) | reaches risk/arbitration most often of all 5 |
| TP (V1) | 5 (2566), 23 (2) | almost entirely own-eligibility, consistent with frozen conclusion |
| MR | 23 (1607), 5 (836), 24 (113), 8/risk (5) | most candidates fail MR's own deviation/wick thresholds before eligibility |
| TP V2 | 5 (2559), 23 (5), 0/accepted (3) | overwhelmingly own-lifecycle gating, as expected pre-trigger |

No strategy shows an unexpected rejection-code distribution (e.g., a
code that should be unreachable given its own gate ordering), and none
show zero downstream-gate rows at all except by their own economics (BO,
TP V1) -- not starved by the presence of the other four strategies.

## Strategy starvation check

BO and TP V1 reached zero acceptances in these 3 windows specifically,
consistent with (not a regression from) the broader 6-window pooled
matrix (BO: 1/6 windows; TP V1: 0/6 windows) -- rarity, not starvation
caused by TP V2's addition to the roster.

## Conclusion

Five-strategy coexistence in Shadow mode is proven organically, reusing
already-committed evidence: correct per-bar independent evaluation for
all 5 strategies, correct one-position enforcement across all strategy
pairs actually observed, a genuine organic cross-strategy exposure block
(MR blocking TP V2), continued per-bar lifecycle updates for both the
holding and non-holding strategies, and no rejection-code anomaly for
any strategy. The one honest gap: no organic same-bar two-valid-candidate
collision was observed at this sample size, so that specific scenario
remains proven only by the Test 95 deterministic fixture, not organically
-- recorded here rather than manufactured by loosening any threshold.

**Broker orders transmitted for this phase: none** (Shadow mode
throughout; this phase is pure re-analysis of already-existing Shadow
evidence).
