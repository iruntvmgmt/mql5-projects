# QuantBeast Research Trial Ledger — Level-1 Edge Certification Sprint

**Purpose:** pure evidence inventory. No conclusions about edge are drawn here.
This ledger exists to let a future certification pass identify calendar
windows and parameter/strategy configurations that have **already been
observed** by this project's authors (human or agent), so they can be
excluded from any claimed "clean" out-of-sample or holdout test.

**Sources read in full:** `TestEvidence/production_readiness_tp_v2_20260722/DECISION_LOG.md`
(827 lines, decisions D001–D017), `HANDOFF.md` (1453 lines, full worklog from
2026-07-15 session start through the 2026-07-24 correction entry). Sources
sampled/grepped: all `TestEvidence/` subfolder README.md/EVIDENCE.md files
(83 folders), `git log` (115 commits, `MQL5/` repo root), all
`Profiles/Tester/*.ini` files whose `Expert=` targets `QuantBeast\QuantBeastEA.ex5`
(cross-checked `FromDate=`/`ToDate=`/`Model=`/`Symbol=` fields directly —
note: some are ASCII, some UTF-16LE; both were decoded), and the live
`Common/Files/QuantBeast/Tester/SignalJournal.csv` (92,893 rows) to confirm
outcomes for the one pair of windows the task specifically asked to verify.
Unrelated EA projects sharing the same `Profiles/Tester/` directory
(`XAUUSD_Scalper*`, `NAS100_Nexus_EA*`, `MS-ZZ-BO-V2*`) were identified by
their different `Expert=` path and **excluded** — they are not QuantBeast
history.

---

## 1. Chronological window ledger

Legend: **Model=4** = real historical tick data (MT5 "Every tick based on
real ticks"). **Model=1** = 1-minute-OHLC-derived synthetic ticks (real bar
structure, but not raw real-tick data) — used throughout this project only
for deterministic engineering/self-test fixtures, never for strategy
threshold calibration. Confidence: **Documented** = a DECISION_LOG/HANDOFF/
TestEvidence entry narrates what happened and why. **Ini-only** = a
`Profiles/Tester/*.ini` file with that exact date range exists (proving the
window was at minimum prepared, and in several cases confirmed executed via
Tester Agent log/journal cross-check below) but no narrative document was
found describing its purpose or result — a real gap in the written record,
not proof the window was never touched.

### 1a. XAUUSD / BTCUSD real-tick (Model=4) windows

| # | Date range | Symbol | Used for | Tied to | Confidence |
|---|---|---|---|---|---|
| 1 | 2024.10.07–2024.10.18 | XAUUSD, BTCUSD | Unknown — `.ini` present, no narrative found | `Profiles/Tester/QuantBeast.Edge.20241007_20241018.ini`, `QuantBeastEA.XAUUSD.M5.20241007_20241018.401.ini`, `QuantBeastEA.BTCUSD.M5.20241007_20241018.401.ini` | Ini-only |
| 2 | 2024.10.10–2024.10.11 | BTCUSD | Unknown — `.ini` present, no narrative found | `QuantBeastEA.BTCUSD.M5.20241010_20241011.401.ini` | Ini-only |
| 3 | 2025.01.06–2025.01.07 | XAUUSD | TP forward-outcome tracker (6-window pooled study), TP-specific impulse seed organic run, TP lifecycle direction organic rerun (exact slice `[16093698,16891238)`), TP V2 unified-strategy-matrix window #2 (regression reproduction), D009 TP V2 Shadow-promotion-gate reproduction attempt | `TestEvidence/tp_forward_outcome_20260722/`, `tp_specific_impulse_seed_20260722/`, `tp_lifecycle_direction_20260722/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/`, DECISION_LOG D009 | Documented |
| 4 | 2025.01.06–2025.01.17 | XAUUSD, BTCUSD | Broader superset of #3; `.ini` present (`QuantBeast.Edge.20250106_20250117.ini`, `QuantBeast.TPScreen.20250106_20250117.ini`, `QuantBeastEA.XAUUSD.M5.20250106_20250117.401.ini`, BTCUSD equivalent) — narrative only confirms the narrower 01.06–01.07 sub-slice was organically run | (see #3) | Ini-only (superset) |
| 5 | 2025.06.02–2025.06.13 | XAUUSD, BTCUSD | Unknown — `.ini` present, no narrative found | `QuantBeast.Edge.20250602_20250613.ini`, `QuantBeastEA.XAUUSD.M5.20250602_20250613.401.ini`, BTCUSD equivalent | Ini-only |
| 6 | 2026.01.05–2026.01.06 | XAUUSD | TP three-window reachability screen (372,741 ticks, 276 bars); TP V2 unified-strategy-matrix window #1 (regression reproduction) | `TestEvidence/tp_multiwindow_screen_20260722/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/` | Documented |
| 7 | 2026.01.05–2026.01.16 | XAUUSD, BTCUSD | Broader superset of #6; `.ini` present, no narrative confirms the full range was run | `QuantBeast.Edge.20260105_20260116.ini` etc. | Ini-only (superset) |
| 8 | 2026.01.20–2026.01.31 | XAUUSD | **BO BUY-side bounded search, window 1.** All four strategies enabled, Model=4. Confirmed executed 2026-07-24 10:10:54 (Tester Agent log); confirmed via `SignalJournal.csv` (13,454 rows in-window): **0 BO BUY ACCEPTED** out of 1,440 BO BUY rows — negative. | `Profiles/Tester/QuantBeast.bo_buy_search_01.20260120_20260131.ini`; also mirrored by `QuantBeastEA.XAUUSD.M5.20260120_20260131.401.ini` | Documented (this session, confirmed via live journal cross-check) |
| 9 | 2026.01.26–2026.01.30 | XAUUSD | Stress/holdout: genuine extreme-volatility event (XAUUSD 5597→4682 in one week); price-jump preflight gate exercised organically for the first time against a real gap | `TestEvidence/stress_holdout_20260720/` | Documented |
| 10 | 2026.02.03–2026.02.09 | XAUUSD | Unknown — `.ini` present (`QuantBeast.TPV2ExperimentalShadow.20260203_20260209.ini`), no narrative found; plausibly the "second organic Outcome A TP V2 trade in a different window" referenced but not date-pinned in `FOLLOWON_SPRINT_FINAL_REPORT.md` §12 | — | Ini-only |
| 11 | 2026.02.16–2026.02.20 | XAUUSD | Organic multiwindow (BO target window), TP three-window screen, FBO/MR stop-geometry audit, TP V2 unified-strategy-matrix window #3, TPV2ExperimentalShadow run, strategy-fixes multiwindow generalization, TP V2 complete Shadow lifecycle (2026.02.18 11:40:00 SELL, R=-1.03), MR complete lifecycle (2026.02.17 12:25:00 and 14:40:00) | `TestEvidence/organic_multiwindow_20260719/`, `tp_multiwindow_screen_20260722/`, `stop_geometry_multiwindow_20260722/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/`, `final_readiness/PHASE4_BO_MR_LIFECYCLE_PROOF.md`, `strategy_fixes_multiwindow_20260720/` | Documented — one of the most heavily reused windows |
| 12 | 2026.02.16–2026.02.27 | XAUUSD | Broader superset of #11; `.ini` present, no narrative confirms the full range was run | `QuantBeastEA.XAUUSD.M5.20260216_20260227.401.ini` | Ini-only (superset) |
| 13 | 2026.03.01–2026.04.25 | XAUUSD | Unknown, multi-month — `.ini` present (created 2026-07-20), no narrative found | `QuantBeastEA.XAUUSD.M5.20260301_20260425.400.ini` | Ini-only |
| 14 | 2026.03.02–2026.03.03 | XAUUSD | Unknown — `.ini` present (created 2026-07-16), no narrative found | `QuantBeastEA.XAUUSD.M5.20260302_20260303.400.ini` | Ini-only |
| 15 | 2026.03.16–2026.03.27 | XAUUSD | Unknown — `.ini` present (created 2026-07-21, during the build-out phases), no narrative found | `QuantBeastEA.XAUUSD.M5.20260316_20260327.401.ini` | Ini-only |
| 16 | 2026.03.30–2026.04.07 | XAUUSD | Organic multiwindow (TP target window, chosen "impulse-pullback-resumption" regime), TP V2 unified-strategy-matrix window #5 (originally selected as "untouched", now itself contaminated), TPV2ExperimentalShadow run, strategy-fixes multiwindow generalization, TP-eligibility-unblocked (IMPULSE→WEAK) confirmation run | `TestEvidence/organic_multiwindow_20260719/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/`, `strategy_fixes_multiwindow_20260720/`, `tp_impulse_weak_threshold_20260720/` | Documented |
| 17 | 2026.04.06–2026.04.10 | XAUUSD | Stress/holdout: quiet/tight-range week comparison | `TestEvidence/stress_holdout_20260720/` | Documented |
| 18 | 2026.04.20–2026.04.21 | XAUUSD | Subset of #19, `.ini` present (`QuantBeastEA.XAUUSD.M5.20260420_20260421.400/401.ini`, `QuantBeast.P4SelfTest.ini`) — Phase-4 self-test spot check | — | Ini-only |
| 19 | 2026.04.20–2026.04.24 | XAUUSD | **The single most heavily reused window in this project.** Original organic multiwindow target (MR); primary window for the `slope_norm` scale-fix discovery and verification; the six-strategy-logic-fix review and its verification; the `InpBO_CompressionPct`/`InpMR_TargetSDBandR` config-cleanup verification; build-out Phases 1, 2, 3 baseline-preservation reruns (BO2/FBO9/TP0/MR5 pinned regression target, checked after every phase); base template for the BO BUY-side bounded-search `.ini` (dates later overridden to windows #8/#25) | `TestEvidence/slope_norm_scale_fix_20260720/`, `strategy_logic_fixes_20260720/`, `phase1_entry_modes_20260720/`, `phase2_stop_target_exit_20260720/`, `phase3_risk_exec_hardening_20260720/` | Documented |
| 20 | 2026.05.03–2026.05.09 | XAUUSD | Unknown — `.ini` present (`QuantBeast.TPV2ExperimentalShadow.20260503_20260509.ini`), no narrative found; plausibly a second TPV2 Outcome-A window per §12 of the follow-on report | — | Ini-only |
| 21 | 2026.05.04–2026.05.05 | XAUUSD | TP screen sub-window | `QuantBeast.TPScreen.20260504_20260515.ini` (dates overridden narrower) | Ini-only |
| 22 | 2026.05.04–2026.05.08 | XAUUSD | Stress/holdout: "fully fresh, previously-untouched calendar week" holdout backtest (17 FBO trades, +206.07) — **note: this window's "untouched" claim only held at the time it was run; it has since been reused, see below** | `TestEvidence/stress_holdout_20260720/` | Documented |
| 23 | 2026.05.04–2026.05.15 | XAUUSD, BTCUSD | Broader superset of #21/#22; `.ini` present (`QuantBeast.Edge.20260504_20260515.ini`, `QuantBeastEA.XAUUSD.M5.20260504_20260515.401.ini`, BTCUSD equivalent), no narrative confirms full range was run | — | Ini-only (superset) |
| 24 | 2026.06.01–2026.06.05 | XAUUSD | Diagnostic-mode `.ini` present, no narrative found | `QuantBeast.Diagnostic.XAUUSD.M5.20260601_20260605.ini` | Ini-only |
| 25 | 2026.06.01–2026.06.12 | XAUUSD | **BO BUY-side bounded search, window 2.** All four strategies enabled, Model=4. Confirmed executed 2026-07-24 11:03:35 (Tester Agent log); confirmed via `SignalJournal.csv` (10,880 rows in-window): **0 BO BUY ACCEPTED** out of 1,088 BO BUY rows — negative. | `Profiles/Tester/QuantBeast.bo_buy_search_02.20260601_20260612.ini`; also mirrored by `QuantBeastEA.XAUUSD.M5.20260601_20260612.401.ini` (auto-saved copy, same timestamp) | Documented (this session, confirmed via live journal cross-check) |
| 26 | 2026.06.15–2026.06.26 | XAUUSD, BTCUSD | Unknown — `.ini` present, no narrative found | `QuantBeast.Edge.20260615_20260626.ini`, `QuantBeastEA.XAUUSD.M5.20260615_20260626.401.ini`, BTCUSD equivalent | Ini-only |
| 27 | 2026.06.19 (single point) | XAUUSD | First advertised real-tick date probed at Model=4; initialized but produced zero test ticks before shutdown — blocked, not a passed run, no real data actually observed | HANDOFF.md, 2026-07-15 entry ("Organic pipeline inspection") | Documented (negative/blocked) |
| 28 | 2026.06.20–2026.06.24 | XAUUSD | Organic true-tick run (863,499 ticks, journal-lock fix verification, 2026-07-18/19), TP V2 unified-strategy-matrix window #4 (regression reproduction), restart/recovery real-terminal-restart evidence (all 4 scenarios, 2026-07-20), BO complete SHORT lifecycle (2026.06.23 21:45:00, R=-1.02) | `TestEvidence/organic_true_ticks_20260718/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/`, `restart_recovery_20260719/`, `final_readiness/PHASE4_BO_MR_LIFECYCLE_PROOF.md` | Documented |
| 29 | 2026.06.22–2026.06.23 | XAUUSD | **The second-most heavily reused window.** Original organic true-tick CSV-evidence run (2026-07-16, 880 signal rows, first accepted FBO entries), TP V2 unified-strategy-matrix window #6 (originally selected as "untouched", now contaminated), MR complete lifecycle (2026.06.22 19:15:00), and the entire 2026-07-22 threshold/acceptance-gate research suite run against this single window: `acceptance_matrix_20260722` (5 configs: baseline + no-price-jump + relaxed-stops + relaxed-locks + all-relaxed), `reachability_matrix_20260722` (7 configs: pinned-baseline + BOComp3 + BOComp1 + TPTrend02 + TPCombined + TPDisp08 + TPDisp06), `eligibility_diagnostics_20260722` (funnel diagnostic), `structural_threshold_coherence_20260722` (2 configs: untouched-baseline + tp_combined), `tp_displacement_matrix_20260722` (3 configs: disp08 + disp06 + disp06-structure), `tp_structure_decomposition_20260722` (structure funnel) | `TestEvidence/organic_true_ticks_20260716/`, `production_readiness_tp_v2_20260722/unified_strategy_matrix/`, `final_readiness/PHASE4_BO_MR_LIFECYCLE_PROOF.md`, `acceptance_matrix_20260722/`, `reachability_matrix_20260722/`, `eligibility_diagnostics_20260722/`, `structural_threshold_coherence_20260722/`, `tp_displacement_matrix_20260722/`, `tp_structure_decomposition_20260722/`; ini's `QuantBeast.AcceptanceMatrix.*.ini`, `QuantBeast.Reachability.*.ini` | Documented |
| 30 | 2026.06.29–2026.07.03 | XAUUSD | Performance-readiness holdout baseline: combined (4,520 rows) + per-strategy BO/FBO/TP/MR holdout runs | `TestEvidence/performance_readiness_20260716/` | Documented |
| 31 | 2026.07.19–2026.07.20 | XAUUSD | Comment-parsing-fix verification (real-tick evidence, Model=4) | `TestEvidence/comment_parsing_fix_20260720/` | Documented |

### 1b. XAUUSD Model=1 (synthetic-tick, self-test/fixture) windows

These share real OHLC bar structure for their date range but use MT5's
1-minute-interpolated synthetic tick generation, not raw historical ticks.
Throughout this project's history they were used exclusively for
deterministic engineering-fixture regression (kill-switch, persistence,
transaction/ownership, recovery-state, alert-routing, arbitration,
etc.) — **never** to calibrate a strategy threshold or economic parameter.
Lower contamination risk for a future certification, but still listed for
completeness per the task's explicit instruction not to undercount.

| Date range | Purpose (all Diagnostic/Shadow self-test regressions) |
|---|---|
| 2026.05.01–2026.05.05 | `ShadowSelfTest` |
| 2026.05.06–2026.05.10 | `ShadowBranches` |
| 2026.05.11–2026.05.15 | `ShadowFull` |
| 2026.05.18–2026.05.19 | `PersistenceFlush`, `RestartProbe.Phase1` |
| 2026.05.18–2026.05.20 | `RestartProbe.Phase2` |
| 2026.05.18–2026.05.22 | `ShadowFinal`, `StateScope`, `EntryPreflight`, `LiveRecoveryGate`, `UnknownUnmanaged`, `AlertCategoryRoutingPatch`, `CurrentRegression`, `SelfTestDetail.20260722` (12+ separate `.ini` variants, same window) |
| 2026.05.18–2026.05.23 | `RecoveryState` |
| 2026.05.18–2026.05.24 | `TransactionState` |
| 2026.05.18–2026.05.25 | `DeferredClose` |
| 2026.05.18–2026.05.26 | `Ownership` |
| 2026.05.18–2026.05.27 | `ProtectionPolicy` |
| 2026.05.18–2026.05.28 | `BrokerUnits` |
| 2026.05.18–2026.05.29 | `BrokerFailurePolicy` |
| 2026.05.18–2026.05.30 | `ChallengeRestore` |
| 2026.05.18–2026.05.31 | `ChallengeRestoreClean` |
| 2026.05.18–2026.06.01 | `ChallengeSafety` |
| 2026.05.18–2026.06.02 | `ChallengeCashFlow` |

---

## 2. Strategy / parameter / config variants tried

- **TP V1** ("Trend Pullback" original engine): live/wired since project
  inception; frozen and tagged `quantbeast-tp-v1-research-freeze-20260722`
  @ `953c2d0` on 2026-07-22 after its own forward-outcome research found "no
  reliable directional information" (n=16, cross-window-inconsistent). Kept
  wired but permanently excluded from any DEMO_READY/live path (D006, D014).
- **TP V2** (new 8-state lifecycle engine, `TrendPullbackV2Engine.mqh`):
  built 2026-07-22, `InpEnableTPV2Experimental` default-off.
  - 4 predefined trigger-type variants considered (closed-bar micro-structure
    break, rejection+directional-confirmation [chosen default, D004],
    displacement reclaim, break-retest) — only the default was
    implementation-verified against real data; the other 3 remain
    unevaluated research variants.
  - Threshold iterations on the shared `StructuralState` IMPULSE gate that
    TP (both V1 and V2) depend on: `|slope_norm|>0.75,dir_eff>0.55` (original)
    → `0.6/0.4` (aligned to TrendState STRONG, 2026-07-20, no visible effect
    in the tested window) → `0.3/0.4` (aligned to WEAK, 2026-07-20, unblocked
    TP eligibility for the first time). Each iteration was verified against
    window #16/#19.
  - Experimental-on Shadow runs: window #3 (2025-01-06, D009 — input failed
    to apply, diagnosed as a tester-cache quirk), window #11 (2026-02-16/20,
    complete Outcome A lifecycle + rejections), plausibly windows #10/#20
    (untraced ini's).
  - First live-armed with `InpEnableTPV2Experimental=true` 2026-07-24
    (`qb-live-20260724-02`, then the standing `qb-live-20260724-05-longrun`).
- **BO (Breakout)**: `InpBO_CompressionPct` current-bar ATR-percentile gate
  added 2026-07-16 (`bo_compression_pct_20260716`), then **removed** as
  contradictory 2026-07-20 (mutually exclusive with an actual breakout,
  "compression-vs-breakout contradiction" fix). Stop-anchor changed from
  broken-level to far-side-of-range 2026-07-20 (fixed the chronic
  "Stop too far" rejection). `InpBO_CompressionPct` input itself fully
  removed in the 2026-07-20 config-cleanup pass (rendered inert by the above
  two fixes). First reached ACCEPTED 2026-07-20 (0→2, window #19). SHORT-side
  organically confirmed (window #28, 2026.06.23). BUY-side never organically
  observed; explicit 2-window bounded search (windows #8, #25) both negative,
  this session. BO demo-authorized for live/demo transmission 2026-07-24
  despite being rated `SHADOW_READY` not `DEMO_READY` (D013, disclosed
  after-the-fact, user's informed choice to leave deployed).
- **FBO (Failed Breakout)**: target-fallback geometry (midpoint vs VWAP,
  `InpFBO_TargetMidR`/`InpFBO_TargetVWAPR`) wired independently 2026-07-16
  (`fbo_target_variants_20260716`). The only strategy with organic accepted
  evidence in essentially every window tested from 2026-07-15 onward (34
  acceptances pooled across the unified 6-window matrix). Rated `DEMO_READY`.
- **MR (Mean Reversion)**: opposite-SD-band target wired 2026-07-16
  (`mr_target_band_20260716`) — this was later found to be an **inverted
  classic mean-reversion bug** (targeted the opposite band instead of the
  VWAP mean, producing 8R targets) and fixed 2026-07-20 (now targets the
  mean). `slope_norm` scale bug (below) was MR's dominant eligibility
  blocker; fixing it dropped not-eligible 95.7%→36.2% and produced MR's
  first-ever ACCEPTED signals (0→5, window #19). `InpMR_TargetSDBandR`
  input fully removed in the 2026-07-20 config-cleanup pass. Rated
  `DEMO_READY`.
- **`slope_norm` scale fix** (2026-07-20, `slope_norm_scale_fix_20260720`):
  `FeatureEngine::CalcTrendFeatures()` redundantly multiplied by lookback
  window, producing values ~20x the calibrated range; single-line fix
  (`slope_norm = trend_slope / atrVal`). Root-cause finder for MR's near-total
  blockage; verified against window #19, re-verified windows #11/#16 (multi-
  window generalization).
- **Six-strategy-logic-fix review** (2026-07-20, `strategy_logic_fixes_20260720`,
  window #19, generalized against #11/#16): (1) MR opposite-band-target
  inversion fixed (target now mean, not opposite band). (2) BO
  compression-vs-breakout contradiction fixed (`preceding_compression_bars`
  added, decoupled from current-bar state). (3) BO current-bar ATR-percentile
  gate dropped (mutually exclusive with breakout). (4) BO range-wide stop
  fixed (anchored to far side of range, not broken level). (5) MR/TP
  strategy-level 0.5×ATR minimum-stop floor added. (6) `TRIGGER_IMMEDIATE_BREAK`
  no longer fires unconditionally in TP/MR (now requires candle direction).
  (7) Geometry self-guard added in `StrategyBase::MakeSignal` (no engine can
  emit inverted stop/target geometry). One further finding (stateless
  strategies) deliberately left as an intentional architectural choice, not
  fixed.
- **IMPULSE threshold fix** (2026-07-20, two-stage: `impulse_threshold_fix_20260720`
  then `tp_impulse_weak_threshold_20260720`): see TP V2 entry above — same
  underlying `StructuralState` gate shared by TP V1/V2. Second stage
  (0.6/0.4→0.3/0.4) is what actually unblocked TP eligibility.
- **Allocation engine**: `CAllocationEngine` built 2026-07-21 (equal/
  confidence/performance weighting, `InpAllocationMode`, default `ALLOC_EQUAL`
  = zero behavior change). `RecordOutcome()` found never called (dead code)
  until wired 2026-07-24 (D014) — before that date, `ALLOC_PERFORMANCE` mode
  silently degenerated to equal-weight for the entire project's history.
- **Arbitration**: modes `HIGHEST_SCORE` / `ARBITRATION_REGIME_PRIORITY` /
  `ARBITRATION_REQUIRE_CONFLUENCE` / `REJECT_CONFLICTS` all pre-existing;
  regression coverage expanded 2026-07-16; `ARBITRATION_REGIME_PRIORITY`'s
  compatibility-bonus chain found missing the TPV2 case and fixed 2026-07-22
  (Phase 2 of the follow-on sprint).
- **Entry-mode / level-source build-out** (2026-07-20, Phase 1): 6 entry
  trigger modes (immediate/candle-close/displacement/break-retest/
  probe-confirm/rejection) added for all 4 strategies via shared helpers;
  `ENUM_LEVEL_SOURCE` (range/prev-day/session/opening-range/swing) added for
  BO. All default to prior behavior; verified against window #19 baseline
  preservation only — the 5 non-default modes per strategy remain
  economically unevaluated.
- **Stop/target/exit build-out** (2026-07-20, Phase 2): `ENUM_STOP_MODE`
  (default/ATR/swing/structural/sweep) and `ENUM_TARGET_MODE`
  (default/fixedR/VWAP/rangeMid/oppBoundary) added for all 4 strategies;
  2 new exit types (momentum-failure, regime-deterioration), default off.
  Same evaluation boundary as above — non-default modes unevaluated.
- **Risk/execution hardening build-out** (2026-07-20/21, Phase 3): Challenge
  attempt-lockout + pyramiding gate wired; Shadow pending-order lifecycle
  wired (6 virtual pending orders placed in verification run).
- **Roster presets**: `XAUUSD_Conservative_Live.set` (FBO-only, market-only,
  live-gated since 2026-07-16), `XAUUSD_Challenge_Example.set` (aligned
  2026-07-16), `XAUUSD_Conservative_Demo_AllStrategy.set` (BO+FBO+MR+TPV2,
  prepared 2026-07-22, activated restricted FBO+MR-only 2026-07-23 per D011,
  then full canonical roster 2026-07-24 per D013/D014), and
  `Tools/quantbeast_deploy.py` roster presets added 2026-07-24: `canonical`
  (BO+FBO+MR+TPV2), `pending-orders` (adds stop/limit order routing, first
  live-armed 2026-07-24), `challenge` (Challenge-Demo tier, first live-armed
  2026-07-24).
- **Risk-setting changes**: none found that altered the economic risk
  percentages/limits themselves (0.10–1.0% risk-percent-class inputs were
  configured per-preset, not iteratively tuned against backtest results) —
  the changes found were all safety/gating logic (kill-switch restore
  warning D012, risk-lock restore warning D015, pending-order acknowledgment
  gate D014, Challenge-Demo tier D014), not profit-seeking parameter search.
- **Abandoned/reverted variants found**:
  - `FILE_SHARE_WRITE` journal-lock fix attempt (2026-07-19) — abandoned,
    writes silently discarded.
  - `MQL5InfoInteger(MQL5_TESTER)` compile-time-constant journal routing
    attempt (2026-07-19) — abandoned/reverted after a botched edit caused a
    4-error compile; replaced by the working `InpJournalTesterPrefix` input.
  - `AccountInfoInteger(ACCOUNT_LOGIN)`-based journal routing — abandoned,
    2 compile errors.
  - VOL_EXPANSION-over-firing hypothesis (2026-07-20) — tested via temporary
    instrumentation against real production code, then **refuted** and fully
    reverted (source hash confirmed matching pre-instrumentation state).
  - D011/D012's kill-switch re-acknowledgment gate (option (b)) — considered,
    deliberately not implemented, remains open.
- **BO BUY-side bounded search** (this session, confirmed above): windows
  `2026.01.20–2026.01.31` and `2026.06.01–2026.06.12`, all-4-strategies-
  enabled config, Model=4. **Both negative**: 0 BO BUY signals reached
  ACCEPTED in either window (1,440 and 1,088 BO BUY signal rows evaluated
  respectively, all rejected).

---

## 3. Conservative trial-count estimate

**Methodology.** A "trial" here means one distinct (strategy/parameter
configuration) × (calendar window) evaluation that could have informed a
design or threshold decision — the unit Deflated Sharpe Ratio multiple-
testing correction should count against. This is deliberately layered so
each layer's undercount risk is visible, and the final number takes the
**highest** defensible layer, not an average.

- **Layer A — distinct real-tick (Model=4) calendar windows found**: 31
  (Section 1a). 19 have a documented purpose; 12 are `.ini`-only with no
  matching narrative (items #1, #2, #4[superset], #5, #7[superset], #10,
  #12[superset], #13, #14, #15, #20, #23[superset], #24, #26 — several of
  these are supersets of an already-documented narrower window, so the
  *distinct untraced* count is closer to 9: #1, #2, #5, #10, #13, #14, #15,
  #20, #24, #26 — 10 windows).
- **Layer B — repeated evaluations of the same window under different
  configurations** (the classic threshold-mining pattern): windows #29
  (2026.06.22–23) and #19 (2026.04.20–24) alone account for roughly
  20 and 12 separate named configuration evaluations respectively (Section
  1a detail); windows #11 and #16 each saw ~6. Summing named
  sub-evaluations actually documented: 20 + 12 + 6 + 6 + ~2-average ×
  remaining 27 windows ≈ **98 real-tick evaluation instances**, before
  adding the 10 untraced ini-only windows (counted once each here) → **≥108**.
- **Layer C — self-test/deterministic-fixture growth**: the project's
  deterministic self-test suite grew from an initial handful to **110
  passing tests** by 2026-07-24, each added in response to a specific
  finding. These are unit-level code-correctness checks, not economic
  backtests, and are **not** added to the headline trial count — but each
  one represents a design decision made in response to an observed failure
  mode, so they are disclosed here as a lower-bound floor on "how many times
  this codebase's behavior was inspected and adjusted."
- **Layer D — Model=1 synthetic-tick regression windows**: ~18 distinct date
  ranges (Section 1b), each typically re-run 1–3 times as later fixes were
  verified against the still-open `2026.05.18–...` family. Lower
  contamination risk (no strategy threshold was ever tuned against these),
  but not zero, since real OHLC bar structure for those dates was still
  processed by the regime/feature classifiers on every run.

**Conservative combined estimate: ≥120 distinct trials** (Layer B's ~108
real-tick evaluation instances, rounded up for the several `.ini`-only
windows whose actual run count could not be confirmed and may be higher
than 1, e.g. windows with `.101`/`.retry`/`.plain` filename suffixes
indicating multiple attempts) **plus ≥25 additional lower-risk synthetic-
tick (Model=1) regression evaluations** (Layer D) **plus the ~110-test
deterministic self-test suite as a disclosed but uncounted floor** (Layer C).

**Explicit uncertainty:** this is a lower bound, not a point estimate, for
three reasons the task specifically asked to be surfaced:
1. **Manual/GUI-driven activity is invisible to file-based forensics.**
   Every live/demo attach in this project (2026-07-16 first Conservative
   Live activation, 2026-07-23 FBO+MR activation, four separate 2026-07-24
   deployments) required a human operator to click "Load" in the MT5 Inputs
   tab and manually attach the EA. Any exploratory clicking, temporary
   parameter edits made and reverted in the GUI before settling on a preset,
   or ad hoc chart-based visual inspection of these or other windows leaves
   **no file trace at all** and cannot be counted here.
2. **The 10 `.ini`-only windows' actual execution and outcome are unknown.**
   `INITIAL_REPO_STATE.md` (2026-07-22) itself describes "~50 untracked
   `Profiles/Tester/*.ini` files ... a mix of prior sessions' research
   profiles" as a known, acknowledged, never-fully-inventoried population —
   this ledger is the first attempt to enumerate them, and several remain
   unresolved to a specific purpose or result.
3. **Aggregate journal files are shared and cumulative**, making it
   impossible to retroactively attribute every historical row to a specific
   named session/decision with full confidence beyond the two windows this
   session explicitly cross-checked (items #8/#25 above). The live
   `SignalJournal.csv` (92,893 rows, 70MB) spans the entire project's
   tester activity undifferentiated by run except by embedded timestamp,
   meaning further forensic reconstruction of exactly which rows belong to
   which named `.ini`-only window is possible but was not exhaustively
   performed for all 10 untraced windows in this pass (only the two the
   task named explicitly were verified).

Given all three factors point toward undercounting rather than
overcounting, **treat 120 as a floor, not a ceiling**, when applying a
multiple-testing correction.

---

## 4. Contaminated window list (disqualified from clean certification use)

Every window in Section 1a (all 31 real-tick entries, items #1–#31) is
**DISQUALIFIED** from use as an untouched Level-1 certification/holdout
window — including items #22 and #16/#29, which were explicitly selected
*at the time* for being "untouched by prior TP research" and have since
been reused, which is itself the cautionary case for this whole exercise.
Section 1b's ~18 Model=1 windows are lower-risk (never used for threshold
calibration) but share calendar dates with several Section 1a real-tick
windows already disqualified on that basis anyway; they add no additional
distinct disqualified dates beyond `2026.05.01–2026.06.02`, which is now
folded into the same span as several Section 1a windows (#19, #21, #22,
#23) already disqualified.

**Consolidated disqualified date-range union (XAUUSD unless noted):**

- 2024.10.07 – 2024.10.18 (XAUUSD + BTCUSD)
- 2025.01.06 – 2025.01.17 (XAUUSD + BTCUSD)
- 2025.06.02 – 2025.06.13 (XAUUSD + BTCUSD)
- 2026.01.05 – 2026.01.16 (XAUUSD + BTCUSD)
- 2026.01.20 – 2026.01.31 (XAUUSD)
- 2026.02.03 – 2026.02.09 (XAUUSD)
- 2026.02.16 – 2026.02.27 (XAUUSD)
- 2026.03.01 – 2026.04.25 (XAUUSD) — **note: this single disqualified span
  subsumes #14, #16, #18, #19 by date range overlap**
- 2026.05.01 – 2026.06.02 (XAUUSD) — synthetic-tick self-test family, folded
  in for date-range completeness
- 2026.05.03 – 2026.05.15 (XAUUSD + BTCUSD)
- 2026.06.01 – 2026.06.12 (XAUUSD)
- 2026.06.15 – 2026.06.26 (XAUUSD + BTCUSD)
- 2026.06.29 – 2026.07.03 (XAUUSD)
- 2026.07.19 – 2026.07.20 (XAUUSD)

**Practical guidance for the next step:** because `2026.03.01–2026.04.25`
alone disqualifies almost two full months, and the touched ranges are
scattered across 2024.10 through 2026.07.20 with few large contiguous
untouched gaps, a future certification pass choosing "new" windows should
explicitly cross-check any candidate date range against this consolidated
list (not just against the smaller set of narratively-documented windows)
before treating it as clean.
