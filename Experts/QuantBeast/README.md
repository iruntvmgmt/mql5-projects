# QuantBeast EA

**Version:** 1.00 research framework  
**Current status:** **READY FOR SHADOW MODE — mechanical research only**  
**Live and Challenge trading:** prohibited; live broker transmission requires explicit `InpAcknowledgeLiveBrokerRisk=true`

QuantBeast is a modular MT5 XAUUSD research EA with separate market-data, feature, regime, strategy, arbitration, risk, execution, position-management, persistence, analytics, and dashboard layers.

The repaired source compiles at **0 errors and 0 warnings**. The current code now stamps family/template/tags onto every strategy signal, includes a batch strategy metadata/reachability self-test (TEST 61), and writes the metadata into the tester signal/counterfactual journals so BO, FBO, TP, and MR can be validated together instead of only one-by-one. The latest tester rerun confirms `TEST 61 PASS` and `Self-tests complete: 63 passed, 0 failed`; the tester-specific CSV headers now include `StrategyFamily`, `StrategyTemplate`, and `StrategyTags`. A batch gap-map report script now summarizes those tester journals into `TestEvidence/gap_map_report.md` for overlap and rejection analysis. Manual/MCP demo broker open-close lifecycle evidence exists, but QuantBeast EA-autonomous demo execution is not yet proven. Production persistence explicitly flushes saved globals. A fresh-process Strategy Tester probe did not retain those globals, which documents tester isolation but does not prove normal-terminal restart safety. These results prove isolated mechanics, not profitability, live restart recovery, or live safety.

The aggressive small-account mission is documented in `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`. It is a bounded-risk research objective, not a profit promise or authorization to bypass central safety controls.

## Current pipeline

```text
Market data -> data quality -> closed-bar features -> regimes
-> BO/FBO/TP/MR strategies -> arbitration -> hard risk + sizing
-> Shadow virtual portfolio or broker adapter -> position management
-> transactions, journals, persistence, dashboard
```

## Status

| Area | Current state |
|---|---|
| Compile | Pass: 0 errors, 0 warnings |
| Closed-bar indexing and trend direction | Statically repaired |
| Four strategy classes | Direct long, short, and direction-preserving rejection paths proven; organic true-tick Shadow evidence accepted FBO BUY/SELL and produced BO/FBO/TP/MR BUY/SELL rejections; BO/TP/MR accepted entries remain pending |
| Arbitration and signal decisions | Deterministic ranking, regime-priority, require-confluence, reject-conflicts, duplicate, restored duplicate/cooldown, conflict, exposure, and lower-ranked rejection paths pass; signal rows are emitted at their final strategy/arbitration/risk decision and IDs include direction. Organic true-tick CSV proof is under `TestEvidence/organic_true_ticks_20260716/`. |
| Broker-aware sizing and risk | Repaired with `OrderCalcProfit`; scenario proof pending |
| Execution/protection | Retcodes, position reconciliation, SL/TP verification, fail-closed path implemented; runtime proof pending |
| Trade lifecycle | `OnTradeTransaction` processes owned fills/closes and analytics; runtime proof pending |
| Persistence/recovery | Incompatible state versions fail closed; deterministic risk-state restoration passes; saves explicitly flush; fresh-process tester globals reset/isolate; normal-terminal broker-position/pending-order restart recovery remains unproven |
| Shadow mode | Virtual market fills, stop/target, partial, breakeven, ATR trail, time stop, costs, equity, exposure, MFE/MAE, and close journaling implemented |
| Diagnostic/Shadow runtime | Strategy Tester initialized Shadow mode; 51 tests passed, 0 failed; broker balance unchanged |
| Live approval | Prohibited |

## Operating modes

| Mode | Broker orders | Approval |
|---|---:|---|
| Diagnostic | No | Approved for attachment and startup/self-test evidence |
| Shadow | No | Approved for mechanical and strategy research; performance baselines are started but not validated as an edge |
| Conservative Live | Yes | Not approved |
| Challenge Live | Yes after acknowledgment | Not approved; high probability of loss |

## Evidence and audits

- `BUG_AUDIT.md` — preserved untouched-source baseline FAIL audit
- `REPAIR_AUDIT_20260715.md` — current repaired-state verdict and remaining risks
- `TestEvidence/compile_20260715/` — original failed compile
- `TestEvidence/compile_repair_20260715/` — intermediate clean compile
- `TestEvidence/repair_final_20260715/` — final compile and Diagnostic launch evidence
- `TestEvidence/shadow_lifecycle_20260715/` — clean build plus broker-free Shadow lifecycle runtime evidence
- `TestEvidence/strategy_reachability_20260715/` — clean build plus BO/FBO/TP/MR long, short, and rejection evidence
- `TestEvidence/recovery_state_20260715/` — clean build plus state-version quarantine and risk-state restoration evidence
- `TestEvidence/transaction_state_20260715/` — clean build plus pending partial-fill tracking/count-once transition evidence
- `TestEvidence/deferred_close_20260715/` — deferred/deduplicated close reconciliation and hedge-only admission evidence
- `TestEvidence/transaction_ownership_20260715/` — tracked-position manual-exit ownership/accounting evidence
- `TestEvidence/protection_policy_20260715/` — directional protective-stop classification evidence
- `TestEvidence/broker_units_20260715/` — tick-grid and configured live-deviation evidence
- `TestEvidence/broker_failure_policy_20260715/` — retry-anchor and persistent broker-action policy evidence
- `TestEvidence/challenge_restore_20260715/` — Challenge restore validation/config-authority evidence
- `TestEvidence/challenge_safety_flatten_20260715/` — Challenge floor-to-flatten policy evidence
- `TestEvidence/challenge_cashflow_20260715/` — external cash-flow quarantine evidence
- `TestEvidence/restart_probe_20260715/` — two-process tester persistence probe, explicit-flush repair, and post-repair regression evidence
- `TestEvidence/server_ack_policy_20260715/` — fail-closed API/server acknowledgement contract and runtime fixture
- `TestEvidence/pending_orphan_policy_20260715/` — fail-closed pending deletion/history/fill-retirement evidence
- `TestEvidence/killswitch_priority_20260715/` — hard-risk priority over transient disconnection evidence
- `TestEvidence/emergency_dispatch_20260715/` — live-only, timer-serviced, bounded cancel/flatten dispatcher evidence
- `TestEvidence/broker_rejection_counter_20260715/` — production rejection-streak wiring, state-schema v4, and fail-closed threshold evidence
- `TestEvidence/broker_fault_matrix_20260715/` — protection repair/emergency, server-response, cancel/fill-race, and centralized-close policy evidence
- `TestEvidence/organic_pipeline_20260715/` — rejected-direction repair, generated-fallback FBO pipeline reachability, and blocked true-real-tick boundary probe
- `TestEvidence/arbitration_journal_20260715/` — finalized arbitration outcomes, direction-qualified signal IDs, clean compile, and 36/0 Shadow regression evidence
- `TestEvidence/audit_final_20260716/` — final clean compile evidence, 38/0 deterministic regression, final-decision writer proof, and performance-without-file-journal proof
- `TestEvidence/organic_true_ticks_20260716/` — organic true-tick Shadow CSV proof with all strategies enabled and self-tests disabled
- `TestEvidence/performance_readiness_20260716/` — reproducible Shadow performance-readiness configs, completed combined true-tick training baseline, invalid first holdout attempt, completed clean holdout retry, and independent BO/FBO/TP/MR train and holdout baselines
- `TestEvidence/current_regression_20260716/` — latest clean compile, 51/0 Shadow regression, and current boundary evidence
- `TestEvidence/arbitration_modes_20260716/` — regime-priority and require-confluence arbitration coverage
- `TestEvidence/arbitration_persistence_20260716/` — arbitration duplicate/cooldown restart persistence
- `TestEvidence/strategy_counter_persistence_20260716/` — same-day strategy daily counter persistence
- `TestEvidence/preset_gate_alignment_20260716/` — live/challenge preset gate alignment
- `TestEvidence/live_broker_ack_gate_20260716/` — explicit live broker-transmission acknowledgement gating
- `TestEvidence/live_strategy_gate_20260716/` — production live-mode gates limiting live initialization to FBO-only and market-order-only until BO/TP/MR and pending-order evidence exists
- `TestEvidence/live_recovery_gate_20260716/` — production live-mode recovery gate blocking passive startup flatten of unknown positions
- `TestEvidence/state_scope_20260716/` — effective-symbol persistence scope repair and 40/0 Shadow regression evidence
- `TestEvidence/bo_compression_pct_20260716/` — BO compression-percentile gating against ATR percentile rank
- `TestEvidence/tp_pullback_age_20260716/` — TP pullback-age gating against completed-bar swing age
- `TestEvidence/mr_target_band_20260716/` — MR opposite VWAP SD-band target coverage
- `TestEvidence/fbo_target_variants_20260716/` — FBO midpoint/VWAP target fallback variants
- `TestEvidence/demo_broker_lifecycle_20260716/` — operator-authorized demo broker open/close lifecycle proof
- `TestEvidence/conservative_live_tester_fbo_20260716/` — Conservative Live tester fail-closed live-ack gate evidence
- `TestEvidence/selftest_detail_control_20260716/` — self-test detail logging control
- `TestEvidence/chart_object_toggle_20260716/` — chart-object rendering toggle behavior
- `TestEvidence/alert_category_routing_20260716/` — fill/reconciliation alert category wiring
- `TestEvidence/alert_failclosed_20260716/` — source-level enabled-alert delivery failure propagation; fresh compile and Shadow fixture still pending
- `FINAL_ADVERSARIAL_AUDIT_20260716.md` — final safe-phase adversarial audit and readiness classification
- `HANDOFF.md` — living status and next task
- `KNOWN_LIMITATIONS.md` — authoritative remaining-debt register

## Project layout

```text
MQL5/
├── AGENTS.md
├── Experts/QuantBeast/
│   ├── QuantBeastEA.mq5
│   ├── QuantBeastEA.ex5
│   ├── XAUUSD_Diagnostic.set
│   ├── XAUUSD_Shadow.set
│   ├── XAUUSD_Conservative_Live.set
│   ├── XAUUSD_Challenge_Example.set
│   ├── TestEvidence/
│   └── documentation
└── Include/QuantBeast/
    ├── Core/ Data/ Regime/ Strategies/
    ├── Portfolio/ Risk/ Execution/
    ├── Analytics/ Testing/ UI/
```

## Safe next sequence

1. Run deterministic live-path transaction, sizing, duplicate, protection, and unknown-position scenarios without real-money exposure; run restart recovery in the normal terminal because tester globals reset/isolate here. Live startup currently rejects `UNKNOWN_FLATTEN`; use `UNKNOWN_QUARANTINE` until an explicit operator-approved close workflow is implemented and proven.
2. Expand organic BO/TP/MR accepted-entry plus complete Shadow lifecycle coverage across more true-tick windows; live-mode initialization is currently gated to FBO-only.
3. Add or explicitly reject Shadow pending-order simulation; current Shadow mode supports market intents only.
4. Expand realistic-cost stress tests and additional untouched windows without optimizing against holdout data; treat the completed train/holdout and per-strategy train/holdout results as baseline observations only.
5. Require prolonged demo validation before considering micro-live.

## Risk warning

QuantBeast has not demonstrated a trading edge, stable expectancy, restart safety under real broker events, or broker portability. XAUUSD leverage can erase a small account rapidly. A clean compile and modular architecture do not make the EA profitable or safe for real money.
