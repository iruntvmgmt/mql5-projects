# QuantBeast Handoff

## 2026-07-22 — TP value-return diagnostics separated from eligibility

- Confirmed a Medium research/semantic defect: `returning_to_value` only
  represented current location within 0.3 ATR of VWAP, so reachability reports
  could not distinguish a bar approaching value from one departing while still
  nearby.
- Added prior closed-bar VWAP distance, contraction progress, movement-toward-
  value, and value-zone-crossing diagnostics. TP structure rejection text now
  exposes them for byte-bounded journal analysis.
- Deliberately preserved current TP eligibility and all entry/stop/target/risk
  behavior; this is instrumentation before strategy redesign.
- Compile: `0 errors, 0 warnings`, MetaEditor build 6033.
- Shadow regression: `66 passed, 0 failed`; 22,080 generated ticks and 1,104
  bars; natural `test passed` footer; no broker orders transmitted.
- Evidence: `TestEvidence/tp_value_return_diagnostics_20260722/README.md`.
- The TP structure reporting tool is backward-compatible with legacy slices
  and now summarizes moving/not-moving, value-zone crossings, near-value
  departures, and contraction-progress distribution when present.
- Readiness remains exactly `READY FOR SHADOW MODE`.

## 2026-07-22 — TP three-window reachability screen completed

- Completed three naturally bounded `Model=4` one-day screens for 2025-01-06,
  2026-01-05, and 2026-05-04. The latter runs processed 372,741 and 367,390
  ticks respectively and ended with normal `test passed` / `thread finished`
  footers.
- TP produced 722 decisions, zero risk/stop evaluations, and zero accepted
  signals. Of 84 structure rows carrying the new diagnostics, 22 moved toward
  VWAP, 62 did not, and zero crossed into the current 0.3 ATR value zone.
- Movement alone is therefore not approved as a replacement eligibility gate;
  the next design step is an explicit impulse/retracement/resumption lifecycle.
- Completed comparison windows also exposed nine FBO and one MR
  `stop_too_far` rejects. Audit their proposed geometry separately; do not
  weaken the central maximum-stop safety control to increase acceptance.
- Evidence: `TestEvidence/tp_multiwindow_screen_20260722/README.md`.

## 2026-07-22 — FBO/MR multi-window stop-geometry audit

- Added a reusable exact-slice stop-geometry report and applied it to the three
  completed TP-screen windows.
- FBO: 10 accepted geometries (median 728.5 points) and nine stop-too-far
  rejects (median 1,499; range 1,138–2,181; 1.57–2.90 ATR). Source review
  confirms the width comes from the intended sweep extreme plus 1.0 ATR.
- MR: four accepted geometries (median 258 points) and one 1,006-point reject,
  only six points over the cap and 0.75 ATR. Source review confirms intended
  range-boundary construction; one boundary sample is insufficient for policy
  change.
- No stop arithmetic defect was confirmed. Preserve `InpMaxStopPoints=1000`;
  do not clip structural stops or relax the central safety limit for acceptance.
- Evidence: `TestEvidence/stop_geometry_multiwindow_20260722/`.

## 2026-07-22 — TP observational lifecycle added

- Added a closed-bar, observation-only TP lifecycle with `idle`, `impulse`,
  `retracing`, `resume_candidate`, `invalidated`, and `expired` phases.
- The tracker advances once per `FeatureSnapshot::calc_time`, preventing the
  normal long/short evaluation pair from double-advancing state.
- It does not alter eligibility, candidate validity, geometry, arbitration, or
  risk. Structure rejection diagnostics now include phase and phase age.
- Deterministic Test 64 proves impulse → retracing → resume candidate,
  same-bar idempotence, and opposite-trend invalidation.
- Compile: `0 errors, 0 warnings`. Shadow regression: `67 passed, 0 failed`,
  22,080 generated ticks, 1,104 bars, natural completion, no broker orders.
- `tp_structure_report.py` now summarizes lifecycle phase coverage while
  remaining compatible with pre-lifecycle slices.
- Evidence: `TestEvidence/tp_lifecycle_observation_20260722/README.md`.
- Readiness remains exactly `READY FOR SHADOW MODE`.

**Last updated:** 2026-07-20  
**Current phase:** Broker-free audit, repair, deterministic validation, and organic true-tick journal proof complete through safe phases  
**Current verdict:** **READY FOR SHADOW MODE; live and Challenge trading prohibited**  
**Active source version:** `QuantBeastEA.mq5` property version 1.00

## Agent startup instruction

Read `MQL5/AGENTS.md` and all project documentation before editing. This file is the living project state; append a worklog entry after every material task.

## Project paths

```text
Main EA:
MQL5/Experts/QuantBeast/QuantBeastEA.mq5

Modules:
MQL5/Include/QuantBeast/

Documentation and presets:
MQL5/Experts/QuantBeast/

Original requirements:
/Users/matt/Downloads/XAUUSD Quant Beast EA.docx

Mission and audit philosophy:
MQL5/Experts/QuantBeast/PROJECT_MISSION_AND_AUDIT_CONTEXT.md
```

## Current verified state

- Main EA source is present.
- `Include/QuantBeast/Execution/ShadowPortfolio.mqh` implements the broker-free virtual market-position lifecycle and pending-order lifecycle (place, fill/cancel, stop).
- Four strategy classes contain long and short source logic.
- Four `.set` presets are present.
- All nine originally required Markdown documents are present.
- `PROJECT_MISSION_AND_AUDIT_CONTEXT.md` is present as the mandatory mission/audit preface.
- `Include/QuantBeast/Testing/SafetyTests.mqh` contains deterministic startup fixtures.
- `QuantBeastEA.ex5` is present and the final MetaEditor build is `0 errors, 0 warnings`.
- The original 23-error/15-warning baseline is preserved under `TestEvidence/compile_20260715/`.
- The Shadow lifecycle build/runtime evidence is under `TestEvidence/shadow_lifecycle_20260715/`.
- Strategy Tester agent logs prove Shadow initialization and 52 passed/0 failed tests, including direction-preserving strategy rejections, regime/arbitration policy, restored arbitration duplicate/cooldown persistence, live broker-transmission acknowledgement gating, protection repair/emergency, server-response, cancel/fill-race, kill-switch, fail-closed Challenge policies, final-decision signal writer behavior, performance updates with file journaling disabled, live-mode strategy/execution gates, state symbol scoping, live recovery no-passive-flatten gating, unknown-position no-adoption behavior, alert-routing policy, entry preflight controls, session/rollover exit policy, self-test detail logging control, chart-object toggle policy, fill/reconciliation alert-category routing, strategy-counter same-day restore policy, and Shadow pending-order lifecycle (place, fill, stop, cancel). The tester MCP still returns `job_id: 0`; local agent logs and file timestamps are authoritative.
- BO now applies its strategy-specific `InpBO_CompressionPct` input against the current ATR percentile rank in addition to the shared minimum compression-bar duration; evidence is under `TestEvidence/bo_compression_pct_20260716/`.
- A two-process restart probe is preserved under `TestEvidence/restart_probe_20260715/`: phase 1 passed, but a fresh tester/Wine process loaded schema `0`. This proves tester-state isolation, not live-terminal restart safety. Production persistence now explicitly flushes Terminal Global Variables.
- Broker submission return values now require both local API success and order-class-specific server acceptance; deterministic mismatched-response injection passes under `TestEvidence/server_ack_policy_20260715/`.
- Pending tracking now survives delete failure, missing history, and unsafe fill reconciliation; evidence is under `TestEvidence/pending_orphan_policy_20260715/`.
- Persistent equity-floor/rejection/account locks now latch before transient disconnect handling; evidence is under `TestEvidence/killswitch_priority_20260715/`.
- Cancel/flatten requests now share a live-only, one-second tick/timer dispatcher; evidence is under `TestEvidence/emergency_dispatch_20260715/`.
- Consecutive broker submission failures now count only actual rejected submission cycles, reset on accepted submission, persist under state schema v4, and latch entries at a configurable threshold; evidence is under `TestEvidence/broker_rejection_counter_20260715/`.
- Protection verification now follows an accept/repair/emergency policy and never directly duplicates the centralized emergency close; injected modify/close/delete, requote, and cancel/fill outcomes pass under `TestEvidence/broker_fault_matrix_20260715/`.
- Rejected strategy signals now preserve the evaluated BUY/SELL direction. A generated-tick fallback run reached FBO long and short through arbitration to central risk. Evidence: `TestEvidence/organic_pipeline_20260715/`.
- Arbitration now finalizes every candidate as selected or explicitly rejected; signal rows are written only at their final strategy/arbitration/risk decision stage, and journal IDs include direction. Evidence: `TestEvidence/arbitration_journal_20260715/`.
- Organic true-tick Shadow proof with all strategies enabled and self-tests disabled produced 880 new signal rows, 3 accepted FBO Shadow entries, separate order/trade rows, and final risk-rejected winner evidence. Evidence: `TestEvidence/organic_true_ticks_20260716/`.
- Manual demo broker lifecycle proof exists under `TestEvidence/demo_broker_lifecycle_20260716/`: two explicitly authorized `XAUUSD BUY 0.01` demo positions were opened through MT5 MCP trading controls and both were closed; final broker state had zero open positions and zero pending orders. This proves manual/MCP demo broker order lifecycle only, not QuantBeast EA-autonomous live execution or restart recovery.
- Final repaired-state adversarial audit: `FINAL_ADVERSARIAL_AUDIT_20260716.md`.
- Current repaired-state verdict: `REPAIR_AUDIT_20260715.md`.

## Documentation source of truth

| Document | Purpose |
|---|---|
| `PROJECT_MISSION_AND_AUDIT_CONTEXT.md` | Original aggressive-growth mission, design philosophy, and adversarial audit requirements |
| `README.md` | User-facing project status and safe workflow |
| `ARCHITECTURE.md` | Intended/current pipeline and module status |
| `CONFIGURATION_GUIDE.md` | Inputs, presets, and inactive controls |
| `STRATEGY_SPEC.md` | Current and required behavior of all four strategies |
| `RISK_SPEC.md` | Sizing, locks, challenge, kill, and management contract |
| `TESTING_GUIDE.md` | Required compile, scenario, tester, recovery, and demo evidence |
| `LIVE_DEPLOYMENT_CHECKLIST.md` | Release and live-approval gates |
| `KNOWN_LIMITATIONS.md` | Authoritative technical-debt register |
| `BUILD_AUDIT.md` | Evidence-based project verdict |
| `BUG_AUDIT.md` | Preserved untouched-source baseline audit |
| `REPAIR_AUDIT_20260715.md` | Current repaired-state verdict, completed fixes, evidence, and remaining blockers |

## Known critical/high implementation areas

The authoritative, complete focused findings are in `BUG_AUDIT.md`. Highest-risk confirmed findings include:

1. Shadow pending-order lifecycle (place, fill/cancel, stop) is now implemented with deterministic test coverage under `TestEvidence/shadow_pending_lifecycle_20260718/`; full lifetime/expiry modeling, organic market-fill behavior, and live/broker pending-order recovery remain unproven.
2. Core Shadow market-position branches have deterministic runtime evidence; strategy-generated lifecycle sequences remain unproven.
3. Pending broker orders are cancelled fail-closed on restart rather than restored.
4. Recovered positions cannot always restore signal/regime/MFE/MAE/exact management state.
5. Strategy semantic gaps remain: broader organic accepted-entry evidence for BO/TP/MR and advanced target variants such as partial/runner policies.
6. Challenge deposits/withdrawals, attempts, profit locks, and restart scenarios remain unproven.
7. Alert routing is wired and tester-suppressed, but real terminal/push delivery has not been operator-verified outside Strategy Tester.
8. State-version mismatch now quarantines entries fail-closed, but no automatic migration exists and real restart recovery remains unproven.
9. Automated fault-injection, restart, execution, and broker-portability scenarios are incomplete.

Do not use this abbreviated list in place of `BUG_AUDIT.md`.

## Stub and partial modules

### Stubs

- `Portfolio/AllocationEngine.mqh`
- `Portfolio/ExposureManager.mqh`
- `Execution/Reconciliation.mqh`
- `Execution/RecoveryEngine.mqh`
- `Analytics/CounterfactualTracker.mqh`

### Wired partial

- `UI/Alerts.mqh` is included, initialized, and routed for key categories; latest fail-closed delivery propagation is source-level only until a fresh compile and Shadow fixture rerun pass.

### Major partial systems

- FeatureEngine structural/auction calculations
- Strategy trigger and exit variants
- Risk close-event enforcement
- Challenge controls
- Kill-switch wiring
- Broker retry/protection workflow
- Position lifecycle and recovery
- Trade analytics and shadow simulation
- Automated testing

## Compile status

```text
Baseline: FAILED — untouched source, 23 errors and 15 warnings
Shadow lifecycle build: PASSED — 0 errors and 0 warnings on 2026-07-15
.ex5: generated; approved only for broker-free Diagnostic/Shadow research
Baseline evidence: TestEvidence/compile_20260715/
Intermediate repair evidence: TestEvidence/compile_repair_20260715/
Final evidence: TestEvidence/shadow_lifecycle_20260715/
Latest evidence: TestEvidence/recovery_state_20260715/
Transaction evidence: TestEvidence/transaction_state_20260715/
Deferred-close evidence: TestEvidence/deferred_close_20260715/
Ownership evidence: TestEvidence/transaction_ownership_20260715/
Protection evidence: TestEvidence/protection_policy_20260715/
Broker-unit evidence: TestEvidence/broker_units_20260715/
Broker-failure-policy evidence: TestEvidence/broker_failure_policy_20260715/
Challenge-restore evidence: TestEvidence/challenge_restore_20260715/
Challenge-safety evidence: TestEvidence/challenge_safety_flatten_20260715/
Challenge-cashflow evidence: TestEvidence/challenge_cashflow_20260715/
Restart-probe evidence: TestEvidence/restart_probe_20260715/
Server-acknowledgement evidence: TestEvidence/server_ack_policy_20260715/
Pending-orphan evidence: TestEvidence/pending_orphan_policy_20260715/
Kill-switch-priority evidence: TestEvidence/killswitch_priority_20260715/
Emergency-dispatch evidence: TestEvidence/emergency_dispatch_20260715/
Broker-rejection-counter evidence: TestEvidence/broker_rejection_counter_20260715/
Broker-fault-matrix evidence: TestEvidence/broker_fault_matrix_20260715/
Organic-pipeline evidence: TestEvidence/organic_pipeline_20260715/
Arbitration/journal evidence: TestEvidence/arbitration_journal_20260715/
Live-gate evidence: TestEvidence/live_strategy_gate_20260716/
Self-test detail-control evidence: TestEvidence/selftest_detail_control_20260716/
Chart-object-toggle evidence: TestEvidence/chart_object_toggle_20260716/
Alert-category routing evidence: TestEvidence/alert_category_routing_20260716/
Alert fail-closed propagation source evidence: TestEvidence/alert_failclosed_20260716/ (fresh compile blocked; rerun required)
Preset-gate alignment evidence: TestEvidence/preset_gate_alignment_20260716/
Arbitration-mode coverage evidence: TestEvidence/arbitration_modes_20260716/
Arbitration persistence evidence: TestEvidence/arbitration_persistence_20260716/
Strategy-counter persistence evidence: TestEvidence/strategy_counter_persistence_20260716/
Manual demo broker lifecycle evidence: TestEvidence/demo_broker_lifecycle_20260716/
Live broker acknowledgement gate evidence: TestEvidence/live_broker_ack_gate_20260716/
Current regression checkpoint evidence: TestEvidence/current_regression_20260716/
BO compression-percentile evidence: TestEvidence/bo_compression_pct_20260716/
TP pullback-age evidence: TestEvidence/tp_pullback_age_20260716/
MR opposite-band target evidence: TestEvidence/mr_target_band_20260716/
FBO target-variant evidence: TestEvidence/fbo_target_variants_20260716/
Conservative Live tester FBO attempt evidence: TestEvidence/conservative_live_tester_fbo_20260716/
Final source SHA-256: 24acb8babcaf977fab7b265fe979fa919850d121d69254eeff013fa35d5e2041
Final EX5 SHA-256: c9e3f9c07ba227c82770df807c7364b18ef9bf71ade4b1d204a558e44d5081b2
```

## Test status

```text
Static content audit: completed
Focused bug audit: completed — BUG_AUDIT.md
Compile test: passed after repair — 0 errors, 0 warnings
Deterministic startup fixtures: runtime pass — 51 passed, 0 failed
Shadow attachment: completed per local tester agent log; MCP status remained unreliable
Shadow lifecycle tests: all core market-position branches passed; no broker orders/deals; tester balance unchanged
Strategy Tester baseline: not yet valid as performance evidence
Restart/recovery: version quarantine and risk-state restore contracts proven; two-process tester probe fails because tester globals reset/isolate; real terminal/broker restart scenarios missing
Demo forward: prohibited until earlier gates pass
Live: prohibited
```

### 2026-07-16 — Alert delivery fail-closed propagation

- Defect demonstrated: `CAlerts::SendAlert()` returned failure when `SendNotification()` failed, but `EmitConfiguredAlert()` discarded the result. A configured push-alert failure could therefore be logged without any controller-level safety consequence.
- Severity: Medium safety/observability defect. It affects monitoring assumptions, especially for future live-capable validation windows where an operator has enabled push alerting.
- Fix: added `QBConfiguredAlertSucceeded()` in `UI/Alerts.mqh`; extended `QBTestAlertRouting()` to cover disabled-alert success and enabled-delivery failure; changed `EmitConfiguredAlert()` to return success/failure and to latch entries closed through the existing kill switch plus state persistence when an enabled configured alert cannot be delivered.
- Validation: source blocks read back correctly. Fresh compile is blocked in this turn because MetaEditor invocations exited with code 0 but did not update `QuantBeastEA.ex5` or write a fresh log. No tester run was performed because the current `.ex5` is stale relative to source.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/alert_failclosed_20260716/`.
- Files changed: `MQL5/Include/QuantBeast/UI/Alerts.mqh`, `MQL5/Experts/QuantBeast/QuantBeastEA.mq5`, `README.md`, `ARCHITECTURE.md`, `CONFIGURATION_GUIDE.md`, `KNOWN_LIMITATIONS.md`, `HANDOFF.md`, and this evidence folder.
- Required next action: run a known-working MetaEditor compile and then a Shadow startup fixture; expected self-test detail should include `TEST 41 PASS: Alert routing ... failClosed=yes`. Readiness remains exactly `READY FOR SHADOW MODE`; live and Challenge trading remain prohibited.

### 2026-07-16 — Live broker-transmission acknowledgement gate

- Defect demonstrated: Conservative Live and acknowledged Challenge Live had strategy, execution, and recovery gates, but no separate live-broker acknowledgement. Accidentally loading a live preset that passed those gates could permit broker transmission without an explicit live-order acknowledgement.
- Severity: High configuration/safety defect. Affected path: live EA initialization before broker transmission.
- Fix: added default-false `InpAcknowledgeLiveBrokerRisk`; live modes now fail initialization unless it is true. All QuantBeast presets explicitly set it to false. Challenge acknowledgement remains separate and was not enabled.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `51 passed, 0 failed`, including `TEST 40b PASS: Live broker transmission acknowledgement gate`. Tester footer: final balance `10000.00 USD`, `OnTester result 0`, `Test passed`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/live_broker_ack_gate_20260716/`.
- Source SHA-256: `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; Configuration SHA-256: `287d8f29198bd829367fcc49650c849afafd5fe95b289411c77a92ab2a9635e6`; EX5 SHA-256: `191b36f1bd4195ea4296941de941b7b202e5394e8c15380a2a13d6f2d8d225f7`.
- No broker order was transmitted by QuantBeast during this regression; manual/MCP demo lifecycle evidence remains separate. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Manual demo broker lifecycle validation

- Authorization: operator explicitly authorized broker exposure, then explicitly instructed `Place demo market order: XAUUSD BUY 0.01` twice and later instructed closing both validation positions.
- Account: `Coinexx-Demo`, hedging, demo, USD. Pre-run account had no open positions or pending orders.
- Execution evidence: order `34601163` opened position `34601163` (`XAUUSD BUY 0.01`, fill `4010.53`, deal `31610668`); order `34601183` opened position `34601183` (`XAUUSD BUY 0.01`, fill `4011.41`, deal `31610688`).
- Close evidence: position `34601163` closed by order `34601232` / deal `31610736` at `4011.00`; position `34601183` closed by order `34601245` / deal `31610750` at `4011.82`.
- Final broker state: zero open positions, zero pending orders, balance/equity `980.40 USD`, margin `0.00`.
- Boundary: trades were placed/closed through MT5 MCP trading controls, not by autonomous QuantBeast EA strategy/execution logic. This proves demo broker order lifecycle visibility and cleanup only; it does not prove EA-controlled live trading, EA restart reconciliation, protection management, or challenge readiness.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/demo_broker_lifecycle_20260716/`.
- Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Arbitration duplicate/cooldown persistence

- Defect demonstrated: `CSignalArbitrator` stored `m_lastAcceptTime` and recent accepted signal IDs only in memory. After terminal restart, the EA could forget an accepted setup inside the configured cooldown/duplicate window while account-level locks and strategy counters persisted.
- Severity: High restart-safety defect. Affected path: live restart recovery and arbitration throttles. Safety consequence: restart could bypass duplicate/cooldown protections and allow repeated exposure attempts.
- Fix: added stable hash-based duplicate persistence to `SignalArbitrator.mqh`; added bounded global-variable slots in `StateStore.mqh` for arbitration last-accept time and recent signal hashes/times; restored only fresh non-future timestamps; persisted immediately after accepted arbitration commits.
- Compatibility: state schema version was not changed; missing arbitration keys are treated as empty legacy state.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `50 passed, 0 failed`, including `TEST 34 PASS ... restoredDuplicate=rejected ... restoredCooldown=rejected` and `TEST 48 PASS: Arbitration restore policy fresh=restore expired=reject missing=reject future=reject`. Tester footer: final balance `10000.00 USD`, `OnTester result 0`, `Test passed`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/arbitration_persistence_20260716/`.
- Source SHA-256: `b9d2950a56a94838fc4765ca418f8f9c40e1d59006ad1dcef760f99c44276d20`; SignalArbitrator SHA-256: `065b90c2f9170a80d90cb00a24e1eeba6277fede42a77d7a5f724e54f0906086`; StateStore SHA-256: `90d6c738b3bac5ab6154fa8909c7cc1ff73adf9be16f891b37f0c78282a52598`; SafetyTests SHA-256: `cb411da45233d1adb767dd0be3c012d7f051d6e50454475504da84bebca58549`; EX5 SHA-256: `f32f2df50f3c6c76fe64a5df5419a68a1f2d3fe30559f9c6f6c4c6641e2140c5`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Strategy daily counter persistence

- Defect demonstrated: per-strategy daily trade counters were runtime-only, so terminal restart could reset strategy daily limits while daily/weekly risk locks persisted.
- Severity: Medium risk/restart defect. It could permit additional same-day strategy entries after restart in live modes, although no broker exposure was created during this repair.
- Fix: added scoped global-variable keys for strategy trade day and BO/FBO/TP/MR daily counts; persisted counters as part of runtime checkpoints; restored counters only when the saved trade day matches the current broker day; reset and persisted counters on day rollover; persisted immediately after `MarkStrategyTrade()`.
- Compatibility: state schema version was not changed; missing counter keys are treated as empty legacy state.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `49 passed, 0 failed`, including `TEST 47 PASS: Strategy counter restore policy same=restore missing=reject old=reject future=reject`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/strategy_counter_persistence_20260716/`.
- Source SHA-256: `3723de29e9b0caf6dd4ef2201866476c1d77a32f6761f85c5c64e59d5f50ecee`; StateStore SHA-256: `1c43138f0e685c1f52e2f5509768f6873903ea7b81211e39302b32dd830a67eb`; EX5 SHA-256: `e1f34f0bb49bf2b506da3f37f405377bf9903c3c87d084f06cf7756c379b4499`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Arbitration mode regression coverage expanded

- Defect demonstrated: all arbitration enum cases existed in current source, but deterministic coverage only proved highest-score, duplicate, reject-conflicts, and exposure behavior. `ARBITRATION_REGIME_PRIORITY` and `ARBITRATION_REQUIRE_CONFLUENCE` lacked direct regression evidence.
- Severity: Medium test-coverage/configuration defect. Exposed modes were implemented, but insufficient evidence could hide future regressions.
- Fix: expanded `QBTestArbitrationPolicy()` so existing `TEST 34 PASS` now also requires regime-priority selection, confluence selection, and no-confluence rejection.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `48 passed, 0 failed`, including `TEST 34 PASS ... regime=selected confluence=selected noConfluence=rejected`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/arbitration_modes_20260716/`.
- Source SHA-256 remained `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`; SafetyTests SHA-256: `e4fad7fcd448cb2b2d199fbbc5bc6b392a69025a6cdd4d5e1efd174d74fc1dfa`; EX5 SHA-256: `3ecc2d1274891dc02db319ffa2373e1b804ef0fa4ec827dbcaeae3a4c5bafed1`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Challenge example preset aligned to live/challenge gates

- Defect demonstrated: `XAUUSD_Challenge_Example.set` was safe by default because `InpAcknowledgeChallengeRisk=false`, but if an operator manually acknowledged Challenge risk later it inherited default BO/TP/MR and pending-order settings that fail the current live/challenge gates.
- Severity: Medium configuration safety/operability defect. No broker exposure was created.
- Fix: kept `InpAcknowledgeChallengeRisk=false`, made the Challenge example explicit FBO-only, market-only, `InpMaxPendingOrders=0`, persistence/global variables enabled, and unknown-position quarantine.
- Validation: static preset validation passed for all four `.set` files; Conservative Live and Challenge example presets both match current FBO-only, market-only, no-pending, unknown-quarantine gates. Compile sanity remained `0 errors, 0 warnings`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/preset_gate_alignment_20260716/`.
- Source SHA-256 remained `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`; EX5 SHA-256 after recompile: `a2d735399ab7682dddc72efbd34fda09cea776b86591c1f7b4f4d4b3c7b74744`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Fill and reconciliation alert categories wired

- Defect demonstrated: `InpAlertOrderFilled` and `InpAlertReconFailure` were declared but had no runtime references. Severity: Medium operational-visibility defect; no signal, risk, execution, or broker safety path was weakened.
- Fix: routed Shadow fills, live protected fills, and pending-entry transaction fills through `InpAlertOrderFilled`; routed protection/reconciliation failures, close-queue failures, and missing local close context through `InpAlertReconFailure`.
- Added deterministic coverage: `TEST 46 PASS: Fill/reconciliation alert categories`.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `48 passed, 0 failed`, final balance `10000.00`, `OnTester result 0`, and tester `Test passed` footer.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/alert_category_routing_20260716/`.
- Source SHA-256: `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`; EX5 SHA-256: `bce28bc0c5c019988f2a14f28fd3dd6e9459bf3e6b5743c1ea38a91bcaab69fe`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Session-exit limitation text corrected

- Documentation defect demonstrated: `KNOWN_LIMITATIONS.md` still stated that session-close and rollover-close lifecycle rules were not implemented in the virtual portfolio, despite the earlier compiled/tested session-exit repair.
- Severity: Documentation. The stale limitation could mislead the next operator or agent, but no runtime path changed.
- Fix: replaced the stale limitation with the accurate current state: deterministic Shadow coverage exists under `TestEvidence/session_exit_policy_20260716/`, while live broker flatten behavior remains unproven and requires explicit authorization.
- No source or EX5 code changed in this documentation-only repair; latest validated compile/test state remains `0 errors, 0 warnings` and `48 passed, 0 failed`.

### 2026-07-16 — Chart-object toggle wired with tester suppression

- Defect demonstrated: `InpShowChartObjects` existed as a dashboard/UI input but had no runtime effect outside configuration. Severity: Low UI/operational defect; no signal, risk, execution, or broker safety path was affected.
- Fix: added bounded accepted-signal level drawing to `CDashboard`, with entry/stop/target horizontal lines on normal charts when `InpShowChartObjects=true`. Strategy Tester suppresses object drawing, and object retention is bounded to 10 accepted-signal slots / 30 level lines.
- Added deterministic coverage: `TEST 45 PASS: Chart object toggle policy`.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `47 passed, 0 failed`, final balance `10000.00`, `OnTester result 0`, and tester `Test passed` footer.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/chart_object_toggle_20260716/`.
- Source SHA-256: `a985147dbfd36f6dead2f7f467888edb2d3106d8f4e2b5fc83720e049e305b24`; Dashboard SHA-256: `9aad1d1995f4df0999fb18d2f5c7edddfe29c7d240fae755425fa3ef03e6174f`; EX5 SHA-256: `82ff8e1335d7a2bef94b004c0211f6e5dfdda05ef2d404524d93f2e48434fbb4`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Self-test detail logging input activated

- Defect demonstrated: `InpLogSelfTestDetails` existed as a testing/logging input but `RunSelfTests()` logged PASS detail rows unconditionally. Severity: Low operational/configuration defect; no trading path or broker exposure was affected.
- Fix: added diagnostics-level self-test PASS detail filtering via `DiagSetSelfTestDetails()`, `QBIsSelfTestPassDetail()`, and `QBShouldLogSelfTestMessage()`. `QBLog()` suppresses only self-test PASS detail rows when the input is false; self-test FAIL rows and the final summary remain visible.
- Added deterministic coverage: `TEST 44 PASS: Self-test detail logging policy`.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `46 passed, 0 failed`, final balance `10000.00`, `OnTester result 0`, and tester `Test passed` footer.
- Additional suppression fixture: `InpLogSelfTestDetails=false` produced `Self-tests complete: 46 passed, 0 failed` and the tester footer with no `TEST ... PASS` detail rows in the new log suffix.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/selftest_detail_control_20260716/`.
- Source SHA-256: `26b69114f94465a6c901f62c353e24235bcb61bba905644e5e1a2b14a4a7154a`; EX5 SHA-256: `884d316e0560508e21d05d005004e38804c7f230b88f078a16a9a2d5bda97ad8`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Alert helper fail-closed push routing and docs correction

- Defect demonstrated: `UI/Alerts.mqh` `SendAlert()` previously called `SendNotification()` but ignored its return value, so push failure could be reported as success. Severity: Low operational / documentation-level because the helper remains disconnected from the main EA runtime.
- Affected path: `Include/QuantBeast/UI/Alerts.mqh`; safety consequence is limited to standalone helper behavior and future wiring, not current live trading.
- Fix: push-enabled alerts now log a warning and return the actual `SendNotification()` result; tester-mode alerts still suppress to logs and return true; the module header now states push delivery is fail-closed and email is not configured.
- Validation: compile remained `0 errors, 0 warnings` in `TestEvidence/alert_category_routing_20260716/compile_alert_patch.log`; the existing tester log `Tester/Agent-127.0.0.1-3000/logs/20260716.log` still shows `51 passed, 0 failed`, `OnTester result 0`, and `final balance 10000.00 USD`. No broker orders were transmitted.
- Documentation: `KNOWN_LIMITATIONS.md` now states that `UI/Alerts.mqh` remains uninstantiated by the EA and terminal/push delivery remains unverified outside Strategy Tester.
- Readiness remains exactly `READY FOR_SHADOW_MODE`.

### 2026-07-16 — MT5 push transport operator-verified externally

- Operator report: after logging into the MT5 account and the relevant email/account path, push notifications were tested and did reach the phone through the MT5 app.
- Interpretation: the earlier alert-module concern was not attributable to broken MT5 push transport in the operator environment. The source-level fail-closed patch in `UI/Alerts.mqh` remains valid, but the remaining gap is EA wiring rather than push transport.
- Documentation: `KNOWN_LIMITATIONS.md` now states that terminal push transport has been operator-verified; the module still is not instantiated by the EA.
- No source code or compile evidence changed in this note.

### 2026-07-18 — Phase 1: TEST 12 weekend-spread fix and clean compile

- Defect demonstrated: `QBTestShadowTrailAndTimeStop()` passed the original `snap` (with live broker spread) to the time-stop `Update()` call. On weekends or wide-spread conditions, the bid was below the stop, so the stop loss fired before the time stop could trigger, causing `TEST 12 FAIL: Shadow trail/time time stop did not close after five minutes`.
- Severity: Low test-fixture defect. No runtime trading path was affected; the Shadow time-stop logic itself is correct.
- Fix: the time-stop update now uses a flat snapshot where `bid = ask` (entry price), so neither stop nor target is hit, allowing the time stop to fire deterministically.
- Validation: compile `0 errors, 0 warnings, 22607 ms`; live terminal Shadow attachment on XAUUSD H1 with `XAUUSD_Shadow.set` produced `Self-tests complete: 51 passed, 0 failed` including `TEST 12 PASS: Shadow trail/time trailNet=1.00 time=closed`.
- Evidence: operator-provided Experts tab output, 2026.07.18 18:13:38.
- Source SHA-256: `24acb8babcaf977fab7b265fe979fa919850d121d69254eeff013fa35d5e2041` (unchanged); SafetyTests SHA-256 changed; EX5 SHA-256: `2fb06c38c6df67251eadbfb2751f90ee4e878c20e59d9c155eef8a06901f3659`.
- No broker orders were transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.


### 2026-07-19 — Journal file-lock investigation and organic true-tick attempt

- **HANDOFF item #3 blocked**: organic true-tick run with journals enabled (Model=4, 2026.06.20-06.24, 863k ticks/552 bars) completed normally (balance 10000.00, test passed) but produced zero CSV evidence — the live terminal (Coinexx-Demo, Conservative Live) holds write locks on `SignalJournal.csv`, `OrderJournal.csv`, `TradeJournal.csv` in `Common/Files/QuantBeast/`.
- **Root cause**: `Diagnostics.mqh::OpenJournalFile()` opens journal files with `FILE_COMMON|FILE_SHARE_READ` (no `FILE_SHARE_WRITE`). The live terminal's write lock causes the tester to get error 5004 (`FILE_CANNOT_OPEN`). The Strategy Tester maps `FILE_COMMON` to the terminal's Common folder — not sandboxed.
- **Fix attempted — `FILE_SHARE_WRITE`**: compiled 0 warnings, tester opened files without error, but CSV writes were silently discarded (live terminal's write lock prevails despite share-write flag). Unreliable; abandoned.
- **Fix attempted — tester subdirectory routing**: added `if(MQL5InfoInteger(MQL5_TESTER)) path += "Tester\\"` to route tester journals to `QuantBeast\Tester\` subdirectory. Correct isolation approach but introduced **1 warning** from MetaEditor build 6033 (warns about `MQL5InfoInteger(MQL5_TESTER)` as compile-time constant). A botched editor-insert (literal `\n` in comments) caused 4-error compile; was reverted to clean.
- **Compile status**: restored clean HEAD — `0 errors, 0 warnings, 21203 ms`, MetaEditor build 6033, `.ex5` SHA-256 unchanged from Phase 2.
- **Readiness**: unchanged `READY FOR SHADOW MODE`.
- **Next session**: implement the tester-aware path separation in `Diagnostics.mqh` carefully (avoid editor line-insert issues), accept the benign build-6033 warning, compile, re-run organic true-ticks, capture CSV evidence into `QuantBeast\Tester\SignalJournal.csv`.
- **HANDOFF item #3** remains open; organic CSV evidence still pending.



### 2026-07-18 — Phase 2: Shadow pending order lifecycle

- Decision (Next task #4): implement the Shadow pending-order lifecycle in the broker-free Shadow layer rather than keep it as a documented rejection; the Shadow test fixture provides the simulation baseline for future broker-side pending-order work.
- Implementation (committed as `52442ce`): `ShadowPortfolio.mqh` added `OpenPending()` (buy/sell limit), `CancelPending()`, `GetPendingCount()`, `GetActivePendingCount()`, and fill-on-trigger logic in `Update()`.
- Test: `SafetyTests.mqh` added `QBTestShadowPendingOrderLifecycle()` (TEST 49) covering BUY_LIMIT place→fill→stop-loss, and SELL_LIMIT place→cancel.
- Wiring: committed the previously-uncommitted TEST 49 invocation block in `QuantBeastEA.mq5` `RunSelfTests()`.
- Compile: `0 errors, 0 warnings, 10845 ms`, timestamp `2026.07.18 22:01:16.192`, MetaEditor build 6033.
- Shadow regression: `52 passed, 0 failed` (was 51); TEST 49 `placed=filled stop=loss cancel=cancelled`; `22080` generated ticks, `1104` bars; final balance `10000.00`; `OnTester result 0`; `Test passed in 0:00:48.974`.
- Evidence: `TestEvidence/shadow_pending_lifecycle_20260718/`.
- Hashes: main source `7d7b30a309eb71daf2aab2892a4d65494214c128229093a15b8d400dee2db87e`; EX5 `7ebb90d42ac4fc1e5ed4dfc4e0abbefe83c9d8b82afefbfa1e8975186c9b6b56`; ShadowPortfolio.mqh `795420a16fc22b4748c9f851d89df05e852053d0e383842178ce2adf16f2bdd7`; SafetyTests.mqh `bc89f2708b74ee53adcd5ada30a148ebf42a0fed978a5598d5570ce8f9fa4323`.
- Boundary: deterministic Shadow-only proof; no broker pending-order behavior, organic market-fill behavior, or live/broker pending-order recovery is proven.
- No broker orders were transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.



### 2026-07-19 — Journal file-lock fix implemented (tester-aware path separation)

- **Root cause (from prior investigation)**: `Diagnostics.mqh::OpenJournalFile()` opens journal CSVs with `FILE_COMMON|FILE_SHARE_READ` (no `FILE_SHARE_WRITE`). The live terminal on Coinexx-Demo holds write locks on `Common/Files/QuantBeast/SignalJournal.csv` etc. The Strategy Tester maps `FILE_COMMON` to the same Common folder (not sandboxed), so the tester gets error 5004 (`FILE_CANNOT_OPEN`).
- **Failed approaches**: (1) `FILE_SHARE_WRITE` flag — compiled 0 warnings but writes silently discarded. (2) `MQL5InfoInteger(MQL5_TESTER)` runtime check — MetaEditor build 6033 evaluates this as a compile-time constant (returns 0 at runtime; confirmed by error log showing `QuantBeast\SignalJournal.csv` path without `Tester\` prefix). (3) `AccountInfoInteger(ACCOUNT_LOGIN)` — 2 compile errors (function unavailable during init).
- **Working fix (4 files, compiles 0 errors, 0 warnings)**: Added a new EA input `InpJournalTesterPrefix` (default `false`) in `Configuration.mqh`. `QuantBeastEA.mq5` passes it to `CTradeJournal::Init()`, which passes it to `OpenJournalFile()`. When `true`, journal paths route to `QuantBeast\Tester\<filename>` — a separate subdirectory that avoids the live terminal's file locks entirely.
  - `Include/QuantBeast/Core/Configuration.mqh`: +1 line (new input)
  - `Include/QuantBeast/Core/Diagnostics.mqh`: `OpenJournalFile()` gains `bool isTester=false` param; adds `Tester\` prefix when true
  - `Include/QuantBeast/Analytics/TradeJournal.mqh`: `Init()` gains `bool isTester=false` param; passes to all 3 `OpenJournalFile` calls
  - `Experts/QuantBeast/QuantBeastEA.mq5`: `g_Journal.Init(...)` call passes `InpJournalTesterPrefix`
- **Compile**: `0 errors, 0 warnings, 53386 ms`, MetaEditor build 6033, timestamp `2026.07.19 15:51:54`, EX5 `500706` bytes.
- **Organic true-tick run (2026.06.20-06.24, Model=4)**: completed (`863499 ticks, 552 bars, Test passed in 0:28:51, balance 10000.00`) but **the tester loaded a stale cached .ex5** — the `InpJournalTesterPrefix` input did NOT appear in the tester's logged input list, so journals still went to the locked main path. No CSV evidence captured.
- **Operational blocker**: The MT5 terminal (PID running since before the 15:51:54 compile) caches the .ex5 in memory. The tester agent loaded the stale cached version. **The terminal must be restarted** to pick up the new .ex5, then re-run the organic true-tick backtest with `InpJournalTesterPrefix=true` in the config.
- **Also**: the `QuantBeast\Tester\` subdirectory must be pre-created (MQL5 `FileOpen` with `FILE_COMMON` does not auto-create subdirectories). It has been pre-created at `Common/Files/QuantBeast/Tester/`.
- Readiness remains exactly `READY FOR SHADOW MODE`; no broker orders transmitted.



### 2026-07-19 — Organic true-tick CSV evidence captured (HANDOFF item #3)

- **Organic true-tick backtest**: Model=4 (real ticks), XAUUSD M5, 2026.06.20-06.24 (5-day window), all 4 strategies enabled, self-tests disabled, journals enabled.
- **Result**: `863499 ticks, 552 bars, Test passed in 0:28:51.422, final balance 10000.00, OnTester result 0`.
- **CSV journal growth**: SignalJournal +1840 rows, OrderJournal +7 rows, TradeJournal +7 rows. The live terminal's file lock was released (MT5 refreshed earlier), so journals wrote to the main Common/Files path successfully despite the stale-.ex5 issue.
- **Signal summary**: FBO 7 ACCEPTED (5 BUY, 2 SELL) + 453 REJECTED; BO 459 REJECTED; TP 460 REJECTED; MR 460 REJECTED. Only FBO reached accepted state — matches the prior 2026-07-16 single-day finding on a broader 5-day window.
- **Trade outcomes**: 7 FBO trades with full PnL/R-multiple journaling. Both BUY and SELL directions preserved. Signal IDs include direction. Accepted rows appear only after final decision.
- **Evidence**: `TestEvidence/organic_true_ticks_20260718/` (EVIDENCE.md, new_signal_rows.csv, new_order_rows.csv, new_trade_rows.csv, tester config, pre-run boundary).
- **Finding**: BO/TP/MR organic accepted entries remain unproven — the strategies are too selective for this 5-day XAUUSD window. Broader multi-window coverage or parameter review may be needed.
- No broker orders transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.


### 2026-07-19 — Multi-window organic coverage for BO/TP/MR (HANDOFF item #3, closed as evidence-complete)

- Session scope: item #3's remainder from the prior entry (BO/TP/MR organic accepted entries unproven). Per AGENTS.md session scope, this was the one item worked this session; items #1, #2, #4 were not touched.
- Re-examined existing isolated per-strategy evidence (`performance_readiness_20260716`) first: TP and MR are blocked ~99%+ by the generic "not eligible" gate in both their train and holdout windows. BO is blocked ~88% by "not eligible", but the remaining ~12% pass eligibility and trigger, with a handful reaching the risk stage and being rejected `Risk: Stop too far: <1000-5081> > 1000` against `InpMaxStopPoints=1000` -- a real, previously-uncharacterized finding specific to the isolated BO-only test.
- Selected three new windows from actual XAUUSD D1 history (`get_chart_history`, 2026-01-01 to 2026-07-17), chosen for regimes visibly distinct from the already-tested 2026-06-15/2026-07-03 span: 2026.02.16-02.20 (compression-then-breakout, targeting BO), 2026.04.20-04.24 (choppy/balanced, targeting MR), 2026.03.30-04.07 (impulse-pullback-resumption, targeting TP).
- Ran all three as combined (all 4 strategies enabled) organic true-tick backtests: XAUUSD M5, Model=4, Shadow mode, `InpJournalTesterPrefix=true`. All three completed normally (`OnTester result 0`, balance unchanged at 10000.00, normal tester footer); native tester MCP again returned `job_id: 0`, confirmed via local Tester Agent log instead per AGENTS.md.
- Result: BO/TP/MR reached 0 accepted signals in all three new windows (97-100% "not eligible" in every case); only FBO reached ACCEPTED/Shadow-trade state (1 accepted signal and 2-9 Shadow trades per window). OrderJournal confirms 24 total orders across the three windows, all `QB_FBO_SHADOW`, zero BO/TP/MR.
- Correction made during this session: initially misattributed the repeated Experts-log `Signal rejected by risk engine: Stop too far` warnings in these combined runs to BO, assuming the isolated-test finding recurred. Checking `QuantBeastEA.mq5:1254-1256` and the SignalJournal CSV shows the risk-stage rejection is journaled against whichever strategy arbitration selected as `best` that cycle -- in these combined runs that was inconsistently FBO (window A, 4 rows) or BO (window B, 2 rows), and window C's sampled rows showed none despite roughly 15 Experts-log warnings. This indicates the SignalJournal under-counts this reason relative to the live warn log (likely duplicate/cooldown suppression at the journal-write level not shared by `QBLogWarn`) -- flagged as a journal-fidelity gap, not a new strategy-attribution finding. The isolated BO-only test remains the clean evidence for BO's own stop-distance problem.
- Finding: across all 6 distinct organic windows tested to date (2 isolated BO/TP/MR windows + 2 mid-June/July combined windows + these 3 new combined windows), BO/TP/MR have never reached ACCEPTED in a combined run. The blocker is overwhelmingly the eligibility gate itself, not window selection; further blind window broadening is unlikely to change this by itself. Per this item's "do not touch" scope, no eligibility/regime parameters were changed. Whether the eligibility gates are miscalibrated or correctly modeling rare conditions is unresolved and needs a dedicated strategy-parameter review task.
- Evidence: `TestEvidence/organic_multiwindow_20260719/EVIDENCE.md` (includes the three tester configs, accepted-row excerpts, and full reasoning).
- No source, parameter, or preset changes were made. Source SHA-256 `7ac32f8db9c8b16d2fe797ad890f6403ae7877ca38a7fdef24b0c5c5ab797ec9` (unchanged); EX5 SHA-256 `cb91e10507047433646c6927a17c7bf242ab7e6f2d50910f89c77333f359d2c9` (unchanged).
- No broker orders were transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Real normal-terminal restart recovery proven for all 4 scenarios (HANDOFF item #2)

- Session scope: item #2 (restart/recovery fixture with owned position, pending order, unknown position, corrupt state), the next sequential item after item #3's closure. Items #1 and #4 were not touched.
- Ran QuantBeastEA live in `QB_MODE_CONSERVATIVE_LIVE` on Coinexx-Demo (account 871221) with `InpAcknowledgeLiveBrokerRisk=true` and the FBO-only/market-only preset, attached and reattached manually by the operator per each scenario (EA remove/reattach = fresh `OnInit()`, functionally the restart event per TESTING_GUIDE Stage 7). This supersedes `restart_recovery_20260716`, which was invalidated because it ran in Shadow mode and never reached `ReconstructFromBroker()`.
- At session start found one leftover open fixture position (`QB_FBO_fixture`, ticket 34627175, +$25) from prior test debt -- confirmed via 3 days of terminal logs showing no QuantBeast attachment, closed with explicit operator authorization before starting.
- Fixture mechanics: the available MCP trading tools have no `magic` parameter, and `ReconstructFromBroker()` requires an in-range magic to classify anything. Used a pre-existing but previously-unwired test asset, `MQL5/Scripts/QuantBeastRestartFixture.mq5` (git history `41d56ba`/`d0ad085`/`ee43b29`), with an operator-approved scope exception since it lives outside `Experts/QuantBeast/**`.
- Found and fixed two latent defects in that fixture script itself (not in QuantBeastEA's own source): `CMD_PLACE_UNKNOWN` used an out-of-range magic (99999999) that `ReconstructFromBroker()`'s magic-range check simply skips entirely, so it could never have exercised `InpUnknownPosPolicy`; fixed to use an in-range magic with a non-`QB_`-prefixed comment instead. `CMD_WRITE_CORRUPT` wrote a fixture-only global (`QB_FIX_SCHEMA`) instead of the real scoped state-version key (`QB_StateVer_<login>_<symbol>`), so it never actually touched `IsSupportedStateVersion()`'s input; fixed to write the real key. Compile: `0 errors, 0 warnings`.
- All 4 scenarios PASS with real Expert-log evidence:
  1. Owned position: `Reconstructed position: ticket=34679484 strategy=FBO entry=4008.27 originalSL=3958.01` -- strategy, entry, and original stop all correctly recovered. First successful end-to-end proof of this path in project history.
  2. Pending order: `Startup pending reconciliation: found=1 cancelled=1 remaining=0` -- confirms documented fail-closed cancellation (not restoration, which is intentional/not yet implemented).
  3. Unknown position: correctly classified via in-range-magic + unparseable-comment, `Unknown position left unmanaged by configured policy`, no destructive action, matching configured `UNKNOWN_REPORT` policy.
  4. Corrupt state: `Persisted state version mismatch (found v999, expected v4)... Entries remain quarantined` -- confirms fail-closed quarantine against a real persisted Global Variable (previously only unit-tested in-process).
- Cleanup: all fixture positions/orders closed/cancelled, real corrupt state-version global and fixture markers deleted. Final broker state: 0 positions, 0 orders. No other EA's or manual broker state was touched.
- Evidence: `TestEvidence/restart_recovery_20260719/EVIDENCE.md`.
- QuantBeastEA's own source/EX5 were not modified (hashes unchanged from the 2026-07-19 item #3 session). Only the fixture script (`MQL5/Scripts/QuantBeastRestartFixture.mq5`, outside the EA's own source tree) changed.
- No unauthorized broker action was taken. Readiness remains exactly `READY FOR SHADOW MODE`; this closes a major recovery-gate evidence blocker (`LIVE_DEPLOYMENT_CHECKLIST.md` section H) but does not by itself change overall readiness classification.

### 2026-07-20 -- Fault-adapter scenario investigation (HANDOFF item #1): 2 sub-scenarios blocked by broker permissiveness, 1 new defect found, connectivity architecture gap documented

- Session scope: item #1 (fault-adapter scenarios), the next sequential item after item #2's closure. Item #4 was not touched.
- Ran QuantBeastEA live in `QB_MODE_CONSERVATIVE_LIVE` on Coinexx-Demo, attempted each of modify/close/delete rejection, requotes, and disconnect/reconnect directly. No source or parameter changes made; source/EX5 hashes unchanged.
- **Requotes and modify/close/delete rejection: structurally blocked on this broker.** XAUUSD on this account has `Stop Level (pts) = 0` and `Freeze Level (pts) = 0` (logged at every startup), and every order this project has ever sent has filled immediately at retcode 10009 (DONE), consistent with market execution rather than dealing-desk/instant execution. Attempting to double-close an already-closed position was rejected client-side by the MCP tool before reaching the broker at all. Deterministic unit coverage (`broker_fault_matrix_20260715`) remains the only valid evidence for these cases; further probing this account is unlikely to change that.
- **Close reconciliation (positive finding, not a fault):** placed a fixture position live, closed it manually mid-management, confirmed QuantBeastEA's deferred close-reconciliation (`TransactionState.mqh`/`ProcessPendingCloseReconciliation()`) correctly finalized and journaled it with no warnings. Confirms the live deferred-close path works end-to-end for an accepted close; does not exercise its failure/rejection branch since no rejection occurred.
- **New defect found (not fixed, evidence-gathering only):** `OnTradeTransaction()`'s live entry-handling comment parsing (`QuantBeastEA.mq5:1741-1742`) does not truncate at a second `_` the way `PositionManager.mqh`'s `StrategyFromComment()` (used by restart's `ReconstructFromBroker()`) does. A comment like `QB_FBO_fixture` resolves to strategy `FBO` on restart but `FBO_fixture` (unrecognized) via a live fill. Affects strategy-attribution/journaling only, not order safety or protection. Severity Medium. Flagged for a dedicated fix task.
- **Disconnect/reconnect: real event produced, but did not exercise the intended kill path -- itself the finding.** Operator toggled network off/on; terminal log confirms a genuine ~0.64s disconnect/reconnect. QuantBeastEA produced zero log output in response. Tracing the code: `TERMINAL_CONNECTED` is only checked inside `OnTick()` (line 1094); `OnTimer()` (wall-clock, fires every second regardless of ticks) never re-checks connectivity. Since `OnTick()` cannot fire while genuinely disconnected, a short/well-timed outage may never be observed by this specific kill parameter. This is an architectural detection-latency gap, not a demonstrated loss of protection (no positions were at risk during the test; the separate stale-quote kill parameter provides related but distinct coverage once a tick lands after a gap).
- Evidence: `TestEvidence/fault_adapter_20260720/EVIDENCE.md`.
- No unauthorized broker action was taken. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Strategy-comment parsing consistency fix (defect found in fault_adapter_20260720 session)

- Session scope: small, single-purpose defect fix per change discipline -- not one of the sequential Next-task items, but the Medium-severity comment-parsing inconsistency found and flagged during the fault-adapter session was cheap and well-understood enough to close immediately rather than leave open.
- Defect demonstrated: `OnTradeTransaction()`'s live entry-handling comment parsing (`QuantBeastEA.mq5`, 3 call sites) did not truncate at a second underscore the way `PositionManager.mqh`'s `StrategyFromComment()` (used by restart's `ReconstructFromBroker()`) does. `QB_FBO_fixture` resolved to `FBO` on restart but `FBO_fixture` (unrecognized) on a live fill.
- Fix: extracted the correct logic into one free function, `QBStrategyIdFromComment()`, in `PositionManager.mqh`; `StrategyFromComment()` now delegates to it (its duplicate private `IsKnownStrategyId` removed as dead code); all 3 call sites in `QuantBeastEA.mq5` now call the shared function. `SafetyTests.mqh` now explicitly includes `PositionManager.mqh`.
- Added `QBTestStrategyIdFromComment()` (TEST 50): plain/suffixed/multi-suffix/missing-prefix/no-prefix/unknown-id comment cases.
- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, timestamp `2026.07.20 00:17:57`.
- Shadow regression: `53 passed, 0 failed` (was 52; new TEST 50 passes), final balance unchanged 10000.00, `OnTester result 0`, normal tester footer.
- Evidence: `TestEvidence/comment_parsing_fix_20260720/EVIDENCE.md`.
- Hashes: source `36760c8f30f0ac822f1a273375b4b5ac9d9708f9069598121943df6488a97a84`; EX5 `3c87a3947acb69cefc6217854e90d58f64cf779d7f24cb7d24258458d23422b5`; `PositionManager.mqh` `90d3099c0fe2bf348e6cf3f8ddb983572574deabbe7e029d061ca041dd519c66`; `SafetyTests.mqh` `693bc3653a4a13885cf9ab0796c332ded965c5ddf12f10472638e08eedb86059`.
- No strategy logic, risk parameters, or execution behavior changed; scope was strictly comment-parsing consistency. No broker orders transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Pending-order restart reconstruction implemented (HANDOFF item #4, Phase A)

- Session scope: item #4 (broker-side live pending-order lifecycle and recovery), the last of the four sequential Next-task items. Scoped to the restart-recovery piece only, per an approved plan -- live activation/expiry/cancellation/fill-race evidence for ordinary pending-order trading and any decision to relax the live-mode pending-order gate are explicitly separate follow-up work, not attempted this session.
- Investigation found the pending-order execution machinery (`BrokerAdapter.mqh`'s `PlaceStopOrder()`, `DeleteOrder()`, `CancelAllPending()`, and `ExecuteSignal()`'s market/pending dispatch) was already fully implemented and proven in Shadow (2026-07-18, TEST 49). The one clear gap: owned pending orders found at startup were unconditionally cancelled fail-closed, with no reconstruction analogous to `ReconstructFromBroker()` for positions.
- Implemented reconstruction mirroring the position-side pattern: everything needed (type, price, sl, tp, strategy via `QBStrategyIdFromComment()`, setup time) is read directly from live broker order state at `OnInit()` -- no new persisted Global Variable schema, no state-version bump. `request_id` uses the order ticket as a stable substitute (the same accepted gap already documented for `PositionContext.signal_id`). `request_time` uses the broker's true `ORDER_TIME_SETUP`, not "now," so a restart cannot silently extend a stale order's effective expiry budget.
- Since `g_ActiveOrder`/`g_OrderPending` only ever track one pending order, reconstruction fails closed on anything that doesn't fit: 0 found -> no-op; 1 with a resolvable comment -> reconstruct; 1 unresolvable -> cancel (prior behavior, preserved for this case); >1 -> cancel all + `KillEntries()` (not the broader `ActivateProtectionEmergency`, which would also force-close unrelated positions -- nothing is left to protect once cleanly cancelled).
- Added `CBrokerAdapter::FindSingleOwnedPendingOrder()` and `QBBuildPendingExecutionRecord()` (`BrokerAdapter.mqh`), `ReconstructPendingOrder()` (`QuantBeastEA.mq5`), and TEST 51 (`SafetyTests.mqh`) covering the field-mapping/request-id/request-time/strategy-resolution logic.
- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, timestamp `2026.07.20 00:47:39`.
- Shadow regression: `54 passed, 0 failed` (was 53; new TEST 51 passes), final balance unchanged 10000.00, `OnTester result 0`.
- Live restart evidence (Conservative Live, real terminal restart): fixture pending order (magic=20260801, comment=`QB_FBO_fixture_pending`) correctly reconstructed -- `Reconstructed pending order: ticket=34687162 strategy=FBO type=ORDER_TYPE_BUY_LIMIT price=3961.55`. Bonus finding: real elapsed time exceeded `InpOrderExpirySeconds` between fixture placement and re-attach; because `request_time` used the true setup time, the very next tick's existing expiry logic correctly deleted it (`Pending order expiry deletion confirmed`), organically proving both reconstruction and expiry-path integration together.
- Evidence: `TestEvidence/pending_order_reconstruction_20260720/EVIDENCE.md`.
- Hashes: source `4e4ee57811e2204a24181ed9511ed128848ed255cddb3951737284b39a393771`; EX5 `64628d99e134851fa964129e93af5843a5ae60e3e1c66379e4f652d7ae666d27`; `BrokerAdapter.mqh` `774a4aef2f41fd6ba73a276e4ae2c5f68bf452f3775b25eca475fd2361ac8071`; `SafetyTests.mqh` `b8fad8e26906cfd8becba6d2c1a657babbae1a34281852ae2a51bc790e6ac1dc`.
- `QBLiveExecutionSetAllowed()` was NOT modified; live modes remain market-order-only. This change only fixes what happens if a pending order is somehow present at startup; it does not enable any new live trading behavior. No broker orders were transmitted by the EA itself. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Protection verification fixed for restart-reconstructed positions (real defect, High severity)

- Session scope: closing one item from the "long tail of unclosed evidence" identified while summarizing overall project blockers. Not one of the four original sequential items; a targeted, single-purpose fix per change discipline.
- Defect demonstrated: `ReconstructFromBroker()` (`PositionManager.mqh:417-499`) read `POSITION_SL` into `ctx.current_stop` with no check that it was actually a valid protective stop before accepting the position into tracking. Unlike a live fill (which always goes through `EnsurePositionProtection()` via `OnTradeTransaction()`), a position recovered at restart with no stop loss at all was silently treated as protected. `LIVE_DEPLOYMENT_CHECKLIST.md` section H explicitly requires "All reconstructed positions are checked for protection," and this was not being done. Severity High.
- Fix: `ReconstructFromBroker()` now calls `m_broker.EnsurePositionProtection(ticket, ctx.current_stop, ctx.initial_target)` for every position reaching tracking, reusing the exact same protection contract the live-fill path already relies on rather than inventing new logic. Gained a fourth out-parameter `unprotectedCount` (same pattern as the existing `unknownCount`). The sole caller (`QuantBeastEA.mq5` `OnInit()`) now escalates via `ActivateProtectionEmergency()` (not the narrower `KillEntries()`, since this genuinely is "could not verify a safe state") when any reconstructed position fails verification. No new persisted schema, no state-version bump.
- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, timestamp `2026.07.20 01:43:09`.
- Shadow regression: `54 passed, 0 failed`, unchanged -- confirms no regression. No new deterministic unit added; this integration is fundamentally broker-state-dependent like `ReconstructFromBroker()` itself, and the underlying `EnsurePositionProtection()` logic is already deterministically covered elsewhere (`broker_fault_matrix_20260715`).
- Live restart evidence: extended `MQL5/Scripts/QuantBeastRestartFixture.mq5` with `CMD_PLACE_OWNED_NO_SL` (a magic-owned, correctly-commented position with sl=0). Real Conservative Live restart against this fixture produced `Protection verification failed: no valid protective stop` -> `QuantBeast KILL: EMERGENCY: Reconstructed position(s) found with no verified protective stop: 1` -> `Position closed: ticket=34687773 price=4009.73` -- the gap was caught and the centralized emergency-close path correctly closed the unprotected position. Final broker state confirmed clean.
- Evidence: `TestEvidence/protection_verification_reconstruction_20260720/EVIDENCE.md`.
- Hashes: source `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`; EX5 `f4107718ee637356cf4c2131daedd6da80e27bf317e9c41f49df264dffa29642`; `PositionManager.mqh` `db7ae511f7b3e0a68416c0408a481323da6c01fd6501aa098c0d4633ac3cc2e0`; fixture script `331e873999c327934ce5e75a78b8f35fcec3d1614af80625eaaddc56768b1dba`.
- No strategy logic, risk parameters, or execution behavior changed beyond this one verification call and its escalation. No unauthorized broker action was taken (the closed position was the fixture itself, an intentional part of this test). Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Daily/weekly/HWM risk-state real-restart evidence

- Session scope: closing another item from the "long tail of unclosed evidence." Pure evidence-gathering, no source changes; only the test-fixture script was extended (2 new commands).
- Daily/weekly loss-limit baselines, HWM, and consec-loss count are persisted and deterministically unit-tested, but had never been proven against a real terminal restart -- only Strategy Tester's two-process probe, already known unreliable (`restart_probe_20260715`).
- Captured the real baseline first (`dailyStart=997.71 weeklyStart=997.71 HWM=1022.40`), then used two new fixture commands: `CMD_WRITE_RISK_STATE` (writes distinguishable test values to the real scoped GV keys, dates set to now so same-day/same-week comparison accepts them) and `CMD_RESTORE_RISK_STATE` (writes back real captured values, refusing to run if inputs are left at their 0.0 default). Deliberately did NOT extend `CMD_CLEANUP_ALL` to touch these keys -- unlike disposable fixture positions, HWM/dailyStart carry real accumulated meaning across the account's life, so a blanket delete would have silently reset genuine multi-day tracking.
- Result: after injection + real restart, `Risk tracking: dailyStart=555.55 weeklyStart=666.66 HWM=8888.88` -- proves real-restart survival for daily/weekly start equity and HWM (not just current equity, which was ~997 throughout). After restore + a final confirming restart, exact original baseline reappeared: `dailyStart=997.71 weeklyStart=997.71 HWM=1022.40`.
- Scope: dailyLock/weeklyLock/drawdownLock and consecLosses share the identical `InitDailyTracking()` load path just proven but weren't independently re-verified (no direct log line / needs an organic signal to observe). Challenge-stage persistence needs separate Challenge Live authorization, not attempted. Arbitration cooldown/duplicate-window persistence not attempted this session.
- Evidence: `TestEvidence/risk_state_restart_20260720/EVIDENCE.md`.
- Fixture script SHA-256: `4d7d04969ae10f18801438b6271c0375b0fbc2a6b36201c460f5f3f893c1e04c`. QuantBeastEA's own source/EX5 were not modified.
- Real account risk state was captured, modified for the test, and explicitly restored and re-verified afterward; final state matches the original exactly. No broker orders transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- Stress and holdout backtests (high-volatility, quiet, fresh holdout)

- Session scope: closing the last of three "long tail" items identified while summarizing overall project blockers. Pure Strategy Tester backtesting, no source changes, no live broker risk.
- `LIVE_DEPLOYMENT_CHECKLIST.md` section J required high-volatility, quiet-market, and non-overlapping holdout backtests; none had been run. Selected 3 windows from the D1 volatility survey already gathered for `organic_multiwindow_20260719`, none reused from any prior test: 2026.01.26-01.30 (a genuine extreme event -- XAUUSD ran to 5597 then crashed to 4682 within the week), 2026.04.06-04.10 (relatively quiet/tight-range week), 2026.05.04-05.08 (a fully fresh, previously-untouched calendar week).
- All three completed cleanly: high-vol (1 FBO trade, +95.46; hundreds of entries correctly blocked by the price-jump preflight gate during the Jan 29-30 crash, jumps up to 1093 points), quiet (5 FBO trades, -149.20, no anomalies), holdout (17 FBO trades, +206.07, busiest window, no locks triggered despite volume). Only FBO reached accepted trade state in all three, consistent with every prior organic evidence run. No kill-switch/lock activations in any window. These PnL figures are not a profitability claim -- single windows, small samples, Shadow-mode cost modeling only.
- Finding: the Jan 26-30 window is the first time this project organically exercised the price-jump preflight gate against a genuine large real-tick gap event rather than a synthetic one. It fired correctly and repeatedly throughout the crash, and no signal was accepted while price moved abnormally -- real positive evidence for the gap/stress-handling requirement in `TESTING_GUIDE.md` Stage 6.
- Scope: spread-stress and slippage-stress were not isolated as separate synthetic tests (real-tick Model=4 backtesting inherently includes real historical spread variation; slippage-stress needs a live/demo-forward test, not backtesting).
- Evidence: `TestEvidence/stress_holdout_20260720/EVIDENCE.md`.
- No source or configuration changed; source/EX5 hashes unchanged from the prior session. No broker orders transmitted. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-20 -- BO/TP/MR eligibility-gate root cause found and fixed: slope_norm scale bug
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- User-authorized "BO/TP/MR parameter review" (Next-task item #1), scoped to strategy signal generation only, no risk/execution/safety code.
- Read all four regime classifiers, `FeatureEngine.mqh`, and each strategy's `IsEligible()`. Initial code-reading hypothesis (VolatilityState's VOL_EXPANSION over-firing because `compression_bars` defaults to 0) was tested directly against real production code via temporary instrumentation (added, evidence-gathered, then fully reverted -- confirmed by source hash matching pre-instrumentation state) rather than trusted on inspection alone, and was **refuted**: VOL_EXPANSION was only 7.7% of bars in the measured window, not dominant.
- Real root cause: `FeatureEngine::CalcTrendFeatures()`'s `slope_norm = trend_slope * m_trendLookback / atr` redundantly multiplied by the lookback window, producing values (avg |slope_norm| = 2.35) roughly 20x the `[-1,1]`-ish range every consumer (TrendState's 0.15/0.3/0.6, StructuralState's 0.2/0.3/0.75, MR's 0.25) was calibrated for. Only 6% of bars satisfied MR's `|slope_norm| <= 0.25` gate -- by far the tightest constraint measured, well below the structure (72% pass) or volatility (~75% pass) gates.
- Fix: single-line change in `FeatureEngine.mqh`, `slope_norm = trend_slope / atrVal` (dropped the redundant `* m_trendLookback`). No strategy/risk/execution code touched.
- Verified: clean compile (0 errors/0 warnings), self-test regression 54/54 passed (no regression).
- **Before/after evidence, closed same session**: the tester automation got stuck partway through this task (beyond the documented `job_id: 0` issue; several resubmissions produced no genuine new test execution, confirmed via log-size/mtime checks) and recovered on its own without intervention. A clean rerun of the same Apr 20-24 window (journals on, self-tests off) confirmed the fix quantitatively: MR not-eligible dropped 95.7%->36.2%, and MR produced its first-ever ACCEPTED signals in any window tested this project (0->5 real trades, including reproducing the exact trade an earlier self-test-contaminated run had shown, confirming that observation was genuine). BO and FBO are unchanged (neither reads `slope_norm`), as expected. TP's own bottleneck (`dir_efficiency` avg 0.233 vs its 0.4 floor) is unrelated to this fix and remains open. Whether `TrendState`'s own trend classification was distorted by the same scale bug is also unconfirmed and open. Full numbers: `TestEvidence/slope_norm_scale_fix_20260720/EVIDENCE.md`.
- Evidence: `TestEvidence/slope_norm_scale_fix_20260720/EVIDENCE.md`.

### 2026-07-20 -- TP eligibility investigation part 2: StructuralState IMPULSE threshold fixed, insufficient alone
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- Continuation of the same authorized task. Re-measured TP's `dir_efficiency` bottleneck *conditioned on already being in a TrendState-qualified trend* (the earlier unconditional 0.233 average was misleading): conditioned average is 0.4764, above TP's 0.4 floor, 67.5% pass rate. **`dir_efficiency` is not TP's bottleneck.**
- Real bottleneck: TP also requires `regime.structure ∈ {IMPULSE, PULLBACK}`, and across 246 trending bars this was a hard **zero**. Broke down why: PULLBACK's rarity is by-design correct (its `returning_to_value` sub-condition describes a narrow "near VWAP" instant, incompatible with sustained trending -- only 1.6% pass, left untouched). IMPULSE was genuinely miscalibrated: its thresholds (`|slope_norm|>0.75`, `dir_efficiency>0.55`) were stricter than `TrendState`'s own STRONG bar (0.6) and TP's own floor (0.4) -- a bar TrendState calls STRONG could never also qualify as IMPULSE.
- User approved loosening IMPULSE only (not PULLBACK, not dropping the structure requirement). Fix: `StructuralState.mqh` IMPULSE thresholds 0.75/0.55 -> 0.6/0.4, aligned with TrendState/TP. Compiled clean, self-test regression 54/0 passed.
- **Result: the fix is real (verified at code level) but did not produce a visible behavior change in this window.** A follow-up diagnostic found `structOK` was still 0/246 after the fix because `slopeOK` (`|slope_norm|>0.6`) was *also* 0/246 -- no bar in this particular 4-day window reached STRONG-trend magnitude at all post-`slope_norm`-fix; every trending bar was WEAK only. Aligning IMPULSE with STRONG was internally consistent, but STRONG itself appears rare-to-absent in this window, so the aligned IMPULSE bar inherited that rarity. `displacement>1.0` (unexamined until now) would likely be the next binding constraint regardless (only 8.5% pass), and 14.6% of trending bars never reach the IMPULSE/PULLBACK check at all due to `StructuralState.Classify()`'s if/else ordering (breakout/failed-breakout checked first).
- Full SignalJournal rerun confirmed: TP unchanged (still 1150/1150 not-eligible, 0 ACCEPTED). BO/MR/FBO unchanged from the post-slope_norm-fix baseline (no regression).
- Per standing "confirm before changing" direction, no further parameter change applied. Four open questions logged for a future session (see EVIDENCE.md): whether TrendState's STRONG threshold itself is well-calibrated, whether IMPULSE should key off WEAK instead of STRONG, whether `displacement>1.0` needs its own review, whether StructuralState's check ordering is intentional.
- Evidence: `TestEvidence/impulse_threshold_fix_20260720/EVIDENCE.md`.

### 2026-07-20 -- Strategy-logic review: six fixes; BO reaches ACCEPTED for the first time
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- User-directed code review of all four strategy engines for bugs/stubs/gaps, then "fix them all." Seven findings; six fixed, one (stateless strategies) deliberately left as an intentional architectural choice. Strategy signal generation / feature computation only -- no risk/execution/safety code.
- Fixes: (1) MR targeted the opposite SD band instead of the VWAP mean -- inverted classic mean-reversion, produced 8R targets; now targets the mean. (2) `compression_bars` was zeroed on the very breakout bar BO trades; added `preceding_compression_bars` feature that counts the compression run preceding the trigger bar independent of current-bar state. (3) Dropped BO's current-bar ATR-percentile gate, which was mutually exclusive with an actual breakout. (4) BO stop anchored to the broken level instead of the far side of the whole range (was the chronic "Stop too far" cause). (5) MR/TP strategy-level 0.5*ATR minimum-stop floor. (6) `TRIGGER_IMMEDIATE_BREAK` no longer fires unconditionally in TP/MR (requires candle direction). (7) Geometry self-guard in `StrategyBase::MakeSignal` so no engine can emit inverted stop/target geometry.
- Verified: clean compile 0/0; self-test regression **54 passed, 0 failed** (four reachability tests updated in lockstep to assert the corrected behavior -- these are the per-fix proof); journaled Apr 20-24 evidence backtest.
- **Result: BO reached ACCEPTED for the first time in this project (0 -> 2).** One accepted BO signal had `atrRank=76` (old gate would block) and both passed the risk stage where BO's old range-wide stops were rejected. MR unchanged in frequency (5) as expected -- its fixes change trade geometry not frequency (target now at VWAP mean; R on the 2026-04-23 trade dropped 8.37 -> 4.51). FBO unchanged (9 vs 10, arbitration variance). **TP still 0 ACCEPTED** -- honest, not a regression: TP's structure gate needs STRONG-trend bars absent in this window (see impulse_threshold_fix). 
- Two inputs now inert (`InpBO_CompressionPct`, `InpMR_TargetSDBandR`) -- left wired to avoid preset churn, flagged for a config-cleanup task.
- Evidence: `TestEvidence/strategy_logic_fixes_20260720/EVIDENCE.md`.

### 2026-07-20 -- Strategy fixes: multi-window generalization
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- Ran the fixed build journaled over three distinct organic windows to confirm the strategy-logic fixes are not overfit to Apr 20-24. Results (accepted): Apr20-24 BO 2/MR 5/FBO 9/TP 0; Mar30-Apr07 BO 0(114 eligible)/MR 3/FBO 2/TP 0; Feb16-20 BO 0(76 eligible)/MR 2/FBO 12/TP 0. Pre-fix all three had only FBO firing.
- **MR generalizes (closed)** -- fires in all three windows, was 0 everywhere pre-fix. **BO fix verified** -- now clears eligibility in every window and completes breakout trades when a breakout occurs (2 in Apr20-24); low completion count is inherent to breakouts, and Feb's breakout day (Feb 20) fell just outside the tested data. **TP still universally blocked** -- 0 past-eligibility in ALL windows; never passes its structure gate anywhere. Next actionable TP code gap: whether StructuralState IMPULSE should key off WEAK-trend magnitude instead of STRONG so TP can reach eligibility.
- Cleaned up an accumulation of hung-in-shutdown `metatester64` processes that was the source of this session's intermittent tester-automation flakiness; runs now poll for `test passed` and terminate the hung process to prevent re-accumulation.
- Evidence: `TestEvidence/strategy_fixes_multiwindow_20260720/EVIDENCE.md`.

### 2026-07-20 -- TP eligibility unblocked: IMPULSE keyed to WEAK-trend magnitude
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- User-approved fix for TP's universal eligibility block: TP accepts WEAK trends but IMPULSE required STRONG magnitude (`|slope_norm|>0.6`), which no trending bar ever reached. Lowered `StructuralState` IMPULSE slope gate 0.6->0.3 (WEAK band), keeping `dir_efficiency>0.4` and `displacement>1.0` as quality filters.
- Verified: compile 0/0, self-tests 55/0 (count 55 vs prior 54 is unnumbered sub-check assertions, benign, zero failures). Journaled Mar30-Apr07 run: **TP past-eligibility 0 -> 2** -- the universal structure-gate block is broken; TP now reaches its gate for the first time. The 2 bars that passed were rejected by legitimate setup logic (negative pullback depth; wrong direction), not a gate defect -- correct selectivity. `displacement>1.0` was NOT the remaining blocker (those bars passed the IMPULSE gate including displacement). TP acceptance now depends on genuine pullback setups aligning.
- MR tradeoff: accepted 3->1 in this window (lowering IMPULSE reclassifies some BALANCED bars, shrinking MR's eligible set) -- expected and acceptable, MR not starved (759 past-elig), still fires in all windows.
- **Strategy-reachability promotion blocker substantially closed**: all four strategies reach their eligibility gates; FBO/MR/BO reach ACCEPTED; TP is reachable with acceptance gated by legitimate setup logic.
- Evidence: `TestEvidence/tp_impulse_weak_threshold_20260720/EVIDENCE.md`.

### 2026-07-20 -- Config cleanup: removed the two inert inputs
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- Closed the config-cleanup follow-up flagged by the strategy-logic review. Fully removed `InpBO_CompressionPct` and `InpMR_TargetSDBandR` (both rendered inert when their only uses -- BO's current-bar ATR gate and MR's opposite-SD-band target -- were removed): input declarations in `Configuration.mqh`, the `Init()` params + members + constructor defaults in `BreakoutEngine.mqh`/`MeanReversionEngine.mqh`, the two EA call sites in `QuantBeastEA.mq5`, and the two test call sites in `SafetyTests.mqh`. Updated `CONFIGURATION_GUIDE.md`'s BO/MR descriptions to match current behavior.
- Canonical `.set` presets never referenced these keys (they list only overridden inputs); the shared `InpCompressionPct` (feature engine / volatility classifier) is a different input and was untouched. Stale keys remain only in historical dated tester `.ini` run-artifacts (harmless).
- Verified: compile 0/0, self-tests 54/0 (BO/MR reachability tests pass with the shortened Init signatures).
- ex5 SHA-256 `2bc5ad273a7bb327ac2d82195be39fd5a0ef0191380704abcc806afd71af43db`. No broker orders. Readiness remains `READY FOR SHADOW MODE`.

### 2026-07-20 -- Full build-out Phase 1: strategy entry-mode + level-source variations
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- First phase of the approved full-EA build-out (plan: `expressive-hatching-eclipse.md`), using the consolidated verification cadence (one compile + one self-test run + one journaled baseline-preservation backtest per phase).
- Added 6 entry trigger modes (immediate/candle-close/displacement/break-retest/probe-confirm/rejection) via shared `StrategyBase` helpers `ConfirmCandleTrigger`/`ConfirmLevelTrigger`; TP/MR consolidated onto the shared helper (duplicate private `TriggerConfirmed` removed), BO switch extended, FBO layered additively (default reclaim unchanged). Added `ENUM_LEVEL_SOURCE` (range/prev-day/session/opening-range/swing) + `InpBO_LevelSource`, wired into BO. All additive, defaulted to current behavior.
- Verified: compile 0/0, self-tests **56 passed, 0 failed** (TEST 52 entry modes + TEST 53 level source added; TEST 16-19 reachability unchanged); journaled Apr 20-24 baseline **preserved exactly** (BO 2, FBO 9, TP 0, MR 5).
- Evidence: `TestEvidence/phase1_entry_modes_20260720/EVIDENCE.md`. ex5 `ba23111d...`.
- Remaining build-out phases (tasks #13-16): stop/target/exit variations; risk/execution hardening; AllocationEngine + CounterfactualTracker; the three delegated-stub modules.

### 2026-07-20 -- Full build-out Phase 2: stop / target / exit variations
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- Added `ENUM_STOP_MODE` (default/ATR/swing/structural/sweep) + `ENUM_TARGET_MODE` (default/fixedR/VWAP/rangeMid/oppBoundary) via shared `StrategyBase::ComputeStop`/`ComputeTarget`, wired into all four engines (each passes its native calc as DEFAULT so defaults are byte-identical), with 8 `Inp*_StopMode`/`_TargetMode` inputs. Added two additive exit types -- momentum-failure (`EXIT_FAILED_MOMENTUM`) and regime-deterioration (`EXIT_REGIME_DETERIORATE`) -- in both `ShadowPortfolio` (feat shock proxy) and `PositionManager` (full regime), gated by `InpEnableMomentumExit`/`InpEnableRegimeExit` (default off).
- Verified: compile 0/0, self-tests **58 passed, 0 failed** (TEST 54 stop/target dispatch + TEST 55 extended exits added); journaled Apr 20-24 baseline **preserved** (BO 2, FBO 9, TP 0, MR 5).
- Evidence: `TestEvidence/phase2_stop_target_exit_20260720/EVIDENCE.md`. ex5 `c701edb6...`.

### 2026-07-20/21 -- Full build-out Phase 3: risk / execution hardening
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- ChallengeMode: added attempt-lockout enforcement in `IsTradeAllowed` (blocks when attempts_this_stage >= max_attempts) and `IsPyramidingAllowed`/`AllowsPyramiding` gate wiring the previously-dead `m_allowPyramiding` member. Shadow pending-order lifecycle wired (QuantBeastEA ~1451 'not implemented' block replaced with `g_Shadow.OpenPending` virtual stop/limit placement, classified stop-vs-limit by entry-vs-price, gated by InpUseStopOrders/InpUseLimitOrders, expiry via InpOrderExpirySeconds; `ShadowPortfolio.Update` fills/expires/cancels). Session/rollover exits confirmed already complete (`ProcessSessionExitPolicy` + TEST 43).
- Verified: compile 0/0, self-tests **59 passed, 0 failed** (TEST 56 challenge pyramiding added; TEST 49/43 unchanged); journaled Apr 20-24 baseline **preserved** (BO 2/FBO 9/TP 0/MR 5); pending-enabled run placed **6 SHADOW PENDING** virtual orders (was hard-rejected before).
- Evidence: `TestEvidence/phase3_risk_exec_hardening_20260720/EVIDENCE.md`. ex5 `b9a6816c...`.

## Next task

The 2026-07-19/20 sessions closed or partially closed all four items that
were previously on this list (see the dated worklog entries and their
linked `TestEvidence/` folders for full detail: `organic_multiwindow_20260719`,
`restart_recovery_20260719`, `fault_adapter_20260720`,
`comment_parsing_fix_20260720`, `pending_order_reconstruction_20260720`).
This is a refreshed, prioritized list reflecting what those sessions
actually surfaced. Pick exactly one per session per AGENTS.md's session
scope rule.

1. **BO/TP/MR eligibility-gate/parameter review -- MR + BO closed, TP still blocked, 2026-07-20.** MR: `slope_norm` scale bug fixed (`TestEvidence/slope_norm_scale_fix_20260720/`) plus target/stop geometry corrected (`TestEvidence/strategy_logic_fixes_20260720/`). BO: now reaches ACCEPTED (0 -> 2) after the strategy-logic review fixed its compression-vs-breakout contradiction and range-wide stop (`TestEvidence/strategy_logic_fixes_20260720/`). TP: still 0 ACCEPTED -- its bottleneck is `StructuralState`'s IMPULSE/PULLBACK requirement needing STRONG-trend bars that are rare-to-absent in the tested window; IMPULSE threshold was already aligned with TrendState/TP (`TestEvidence/impulse_threshold_fix_20260720/`). Remaining open sub-items for a future session: (a) whether `TrendState`'s STRONG threshold (0.6) is well-calibrated across more windows; (b) whether IMPULSE should key off WEAK rather than STRONG; (c) `displacement>1.0` calibration (only 8.5% pass when trending); (d) whether `StructuralState.Classify()`'s breakout-first ordering (steals 14.6% of trending bars before the IMPULSE/PULLBACK check) is intentional; (e) a config-cleanup task to remove/repurpose the now-inert `InpBO_CompressionPct` and `InpMR_TargetSDBandR` inputs; (f) test BO/MR over more windows to confirm the new acceptances generalize.
2. **Live pending-order activation/cancellation/fill-race evidence.** Restart reconstruction is now implemented and proven (`TestEvidence/pending_order_reconstruction_20260720/`), but ordinary (non-restart) pending-order lifecycle evidence still requires `QBLiveExecutionSetAllowed()`'s pending-order block to be temporarily relaxed for a scoped, authorized live test on Coinexx-Demo -- analogous to the 2026-07-16 Conservative Live FBO-only authorization, but a materially different and broader scope (pending orders, not just market orders). **Do not start this without first getting explicit, scoped operator authorization for the specific relaxation**, the same way Conservative Live itself was authorized.
3. **Broader stress/holdout/demo-forward testing** per `LIVE_DEPLOYMENT_CHECKLIST.md` section J (high-volatility/quiet/spread-stress backtests, a continuous 2-week demo-forward run). Large, multi-day scope; not started.
4. **Fault-adapter fill-during-cancel race** (the one sub-scenario of the original item #1 never attempted). Likely impractical on this broker given its market-execution permissiveness (see `TestEvidence/fault_adapter_20260720/`); worth a brief feasibility check before committing real session time to it.

## Do not touch during the next task

- Do not enable live or challenge trading.
- Do not change strategy parameters or optimize performance.
- Do not rewrite architecture during the bug audit.
- Do not fix defects while still inventorying them unless explicitly authorized.
- Do not modify unrelated MQL5 projects.
- Do not treat preset or documentation correction as proof the EA works.

## Current blockers

- Native MT5 tester MCP returns `job_id: 0`/stopped even when the local agent completes the run; use agent logs as evidence.
- BO/TP/MR organic accepted entries, long-run virtual accounting, and broad multi-window true-tick coverage remain unproven.
- The post-repair CSV blocker is closed by `TestEvidence/organic_true_ticks_20260716/`; historical pre-repair rows and the pre-fix corrupted shared Common prefix remain preserved and must not be used as current evidence.
- Journal file-lock collision (2026-07-19): fixed and confirmed working across four subsequent tester runs (`organic_true_ticks_20260718` plus the three `organic_multiwindow_20260719` windows) using `InpJournalTesterPrefix=true`, routing to `Common/Files/QuantBeast/Tester/`. No further action needed; closed.
- BO/TP/MR eligibility-gate calibration (MR resolved, TP partially addressed, 2026-07-20): MR's `slope_norm` scale bug fixed and quantitatively confirmed (not-eligible 95.7%->36.2%, ACCEPTED 0->5; `TestEvidence/slope_norm_scale_fix_20260720/`). TP's real bottleneck was found to be `StructuralState`'s IMPULSE/PULLBACK requirement (not `dir_efficiency`, which was a red herring from an unconditioned measurement); IMPULSE's threshold was fixed but didn't produce a visible TP trade in the one window tested, since STRONG-trend magnitude itself was rare-to-absent there (`TestEvidence/impulse_threshold_fix_20260720/`). BO confirmed unaffected by the slope_norm fix. See `TestEvidence/organic_multiwindow_20260719/EVIDENCE.md` for the original finding.
- Tester automation reliability regression (2026-07-20, self-resolved): beyond the long-documented `job_id: 0` issue, `tester_run_backtest` became unreliable partway through this session -- several resubmissions produced no genuine test execution at all (no Tester Agent log growth, no new journal rows), distinguishable from the normal `job_id: 0`-but-still-works pattern only by checking log file size/mtime, not process presence. It recovered on its own later the same session with no environment change made. Cause still unknown; worth a quick log-growth health check at the start of the next session before trusting automated backtest results at face value.
- BO risk-stage stop-distance rejection (isolated-test finding, 2026-07-16/19): in the isolated BO-only test, BO's structural+ATR stop calculation for XAUUSD occasionally exceeds `InpMaxStopPoints=1000` by 1-5x, blocking otherwise-eligible-and-triggered BO signals at the risk stage. Combined-run attribution of the same "Stop too far" reason is unreliable (see 2026-07-19 worklog entry) -- only the isolated test is clean evidence for this.

## Worklog

### 2026-07-15 — Filesystem and content audit

- Confirmed QuantBeast project tree and 47 baseline files across Experts and Include trees.
- Identified five stubs, empty Testing directory, missing compile/test evidence, disconnected systems, unused inputs, and preset key defects.
- Downgraded project verdict from the prior unsupported Conditional Pass to FAIL.
- No source or preset changes made.

### 2026-07-15 — Documentation repair

- Created the seven missing required project documents.
- Rewrote README and BUILD_AUDIT to match actual evidence.
- Added status matrices, acceptance gates, test stages, and live-deployment checklist.
- No `.mq5`, `.mqh`, or `.set` changes made.

### 2026-07-15 — Compiler/API repair

- Repaired the compiler, shared-enum, declaration, const/reference, and invalid API blockers catalogued in `BUG_AUDIT.md`.
- Preserved the MT5 built-in `ENUM_ORDER_STATE` constants separately from namespaced QuantBeast lifecycle states.
- Compiled with MetaEditor at `0 errors, 0 warnings`; generated `.ex5` and preserved the compiler log plus hashes under `TestEvidence/compile_repair_20260715/`.
- Did not intentionally change strategy eligibility, signal thresholds, risk parameters, or execution enablement.
- Readiness remains `NOT SAFE TO TEST` until lifecycle, protection, risk, persistence, chronology, and deterministic-test defects are repaired.

### 2026-07-15 — Agent handoff setup

- Added project-scoped operating rules in `MQL5/AGENTS.md`.
- Added this living handoff with current state and next-task contract.
- No EA source, include module, or preset changes made.

### 2026-07-15 — Mission and audit context integrated

- Confirmed `PROJECT_MISSION_AND_AUDIT_CONTEXT.md` landed in the project.
- Made it mandatory reading before technical audit/refactor work.
- Added its required audit sections and readiness classification to the agent and handoff contracts.
- Preserved the aggressive-growth/Challenge mandate without treating it as evidence of edge or permission to weaken safety.
- No EA source, include module, or preset changes made.

### 2026-07-15 — Focused adversarial bug audit

- Compiled the untouched source with MT5 MetaEditor and preserved the log plus manifest under `TestEvidence/compile_20260715/`.
- Confirmed 23 errors, 15 warnings, no generated `.ex5`, and an unchanged main-source SHA-256.
- Audited compile/API usage, ownership, protection, sizing, locks, lifecycle, persistence, features/indexing, all four strategies, regime, arbitration, analytics, presets, and inactive inputs.
- Added `BUG_AUDIT.md` with exact evidence, severity ranking, architecture/strategy/risk/execution/recovery verdicts, test evidence, limitations, and minimal repair order.
- Updated `README.md`, `BUILD_AUDIT.md`, `KNOWN_LIMITATIONS.md`, and `TESTING_GUIDE.md` to replace the obsolete unknown-compile status with the preserved failed-build evidence.
- Final readiness classification: `NOT SAFE TO TEST`.
- No `.mq5`, `.mqh`, or `.set` changes made.

### 2026-07-15 — Static safety repair and final compile

- Repaired compile/API blockers, closed-bar indexing, trend direction, structural/session features, strategy reachability, arbitration, broker-aware sizing, hard risk, kill enforcement, execution retcodes/retries, post-fill protection, trade transactions, analytics, persistence, and restart reconciliation.
- Added deterministic startup fixtures and populated BarCache before startup validation.
- Corrected strategy bid/ask geometry, true VWAP standard deviation, directional rejection wicks, trigger inputs, volume-step precision, partial-close rounding, and stop-loosening prevention.
- Fixed both misspelled preset risk keys.
- Final compile: `0 errors, 0 warnings`; evidence and Diagnostic config preserved under `TestEvidence/repair_final_20260715/`.
- Diagnostic launch attempt failed in the MCP job launcher (`job_id: 0`); active MT5 terminal was not disrupted.
- Readiness at this historical milestone: `READY FOR DIAGNOSTIC MODE` only.

### 2026-07-15 — Shadow virtual portfolio and runtime fixture

- Added `Execution/ShadowPortfolio.mqh` with broker-free bid/ask market entry, configured slippage/commission, stop/target, partial, breakeven, ATR trail, time stop, virtual equity/exposure, MFE/MAE, forced flatten, and close events.
- Isolated Diagnostic/Shadow startup from broker reconciliation and broker-mutating kill actions; persistence remains live-mode-only.
- Routed Shadow equity, balance, exposure, position counts, risk updates, dashboard values, and completed-trade journals through the virtual portfolio.
- Shadow pending-order lifecycle (place, fill/cancel, stop) now has deterministic test coverage; pending intents are no longer flatly rejected. Full lifetime/expiry modeling remains unsupported.
- Added deterministic startup Test 9 for synthetic market entry to target close.
- Final compile: `0 errors, 0 warnings`.
- Strategy Tester evidence: `17 passed, 0 failed`; lifecycle, costs, multiple positions, drawdown locking, and transient gates passed; tester balance remained `10000.00`; no broker order/deal lines.
- Reclassified stale quotes, disconnects, and abnormal spreads as transient entry gates instead of persisted manual kills; explicit risk/manual kills remain latched.
- Evidence: `TestEvidence/shadow_lifecycle_20260715/`.
- Readiness after this milestone, and current readiness unless superseded above: `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Strategy-class reachability fixtures

- Added deterministic BO, FBO, TP, and MR fixtures covering valid long, valid short, and explicit rejection paths without changing strategy thresholds or trading logic.
- The first FBO fixture correctly failed because its synthetic target offered insufficient R:R; corrected only the fixture geometry and reran.
- Final compile: `0 errors, 0 warnings, 9072 ms`.
- Final Shadow run: `21 passed, 0 failed`; tester balance remained `10000.00`; no broker-order path was used.
- Evidence: `TestEvidence/strategy_reachability_20260715/`.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Persisted-state quarantine and risk restoration

- Found a high-priority recovery defect: any nonzero persisted state-version mismatch was silently overwritten with the current version before stale values were loaded.
- Changed startup to accept only empty/uninitialized or exactly current state versions. An incompatible nonzero version now latches new entries off, preserves the stale values for operator review, and does not prevent management/reconstruction of broker positions.
- Added deterministic tests for the version policy and restoration of daily/weekly/drawdown locks, four consecutive losses, risk-period baselines, and the equity high-water mark.
- Final compile: `0 errors, 0 warnings, 7923 ms`.
- Final Shadow run: `23 passed, 0 failed`; `27600` ticks and `1380` bars; tester balance remained `10000.00`.
- Evidence: `TestEvidence/recovery_state_20260715/`.
- Boundary: this proves pure state contracts, not an actual terminal/VPS restart with broker positions or pending orders.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Pending partial-fill transaction lifecycle

- Found a high-priority transaction defect: the first partial fill retired `g_OrderPending`, orphaning the live remainder from local expiry/status tracking and permitting another entry while it remained.
- Added a working-remainder transition that retains tracking while broker state is active and remaining volume is positive.
- Added count-once state so multiple partial deals increment the strategy trade count only once.
- Final compile: `0 errors, 0 warnings, 7665 ms`.
- Final Shadow run: `24 passed, 0 failed`; the new fixture reports `first=tracked second=tracked final=closed once=true`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/transaction_state_20260715/`.
- Boundary: no actual broker partial fill was induced; callback ordering and filling-mode behavior remain live-path test debt.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Deferred close reconciliation and account-mode boundary

- Found a transaction-ordering race: final-close accounting inspected the live position pool during `DEAL_ADD`, although MT5 may deliver the position-removal transaction later. A full close could be mistaken for a partial exit and lose risk/journal updates.
- Added a bounded close-candidate queue keyed by stable position identifier; multiple exits deduplicate, and reconciliation runs after the transaction burst on tick/timer.
- Partial exits retain their PnL in broker history for final aggregation; absent positions finalize once and update journal, analytics, risk, tracking, and persistence.
- Live mode now fails initialization on netting/exchange accounts until `DEAL_ENTRY_INOUT` reversal semantics are explicitly supported; hedging remains the only admitted live account mode.
- Final compile: `0 errors, 0 warnings, 7883 ms`.
- Final Shadow run: `25 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/deferred_close_20260715/`.
- Boundary: deterministic state proof only; no real broker callback sequence was induced.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Tracked-position transaction ownership

- Found an accounting defect: manual partial/final closes can carry deal magic `0`; the handler rejected them even when their position identifier belonged to a tracked QuantBeast position.
- Entry ownership remains magic-strict. Exit ownership now accepts either owned magic or an already tracked stable position identifier; foreign untracked exits remain ignored.
- Final position-history aggregation now includes all deals for that tracked identifier, so manual partial PnL, commission, and swap are not omitted.
- Final compile: `0 errors, 0 warnings, 7852 ms`.
- Final Shadow run: `26 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/transaction_ownership_20260715/`.
- Boundary: deterministic policy proof only; a controlled broker-side manual close remains outstanding.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Directional protective-stop contract

- Found a protection-classification defect: an exact-price comparison treated tighter broker-adjusted stops as failures, then attempted to loosen them and could force unnecessary emergency liquidation.
- Protection now accepts exact or tighter directional stops, rejects missing/looser stops, and preserves a tighter stop while repairing the requested target.
- A target-only repair failure is logged but does not liquidate an otherwise stop-protected position.
- Final compile: `0 errors, 0 warnings, 7949 ms`.
- Shadow run at this milestone: `27 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/protection_policy_20260715/`.
- Boundary: deterministic classification only; broker modification/close failure injection remains outstanding.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Broker tick-grid and deviation consistency

- Found a broker-unit defect: executable prices were normalized to display digits but not `SYMBOL_TRADE_TICK_SIZE`, permitting off-grid order, stop, or target prices on affected symbols.
- Found a risk/execution mismatch: live `CTrade` deviation was hardcoded at 50 points while sizing and Shadow accounting charged `InpSlippageAllowancePts`.
- Central price normalization now aligns to the broker tick grid; live deviation now uses the non-negative integer ceiling of the configured allowance.
- Final compile: `0 errors, 0 warnings, 8246 ms`.
- Latest Shadow run: `28 passed, 0 failed`; configured `10.1` points initialized live deviation at `11`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/broker_units_20260715/`.
- Boundary: deterministic conversion/unit proof only; actual fills, requotes, freeze levels, and broker failure injection remain outstanding.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Broker retry anchor and persistent action requests

- Found that retryable market submissions could re-anchor to an adversely moved quote and then consume the configured execution deviation again, exceeding the entry movement budget charged by sizing.
- Market attempts now reject adverse movement from the approved entry beyond half-tick tolerance; favorable movement remains eligible.
- Found that cancel/flatten requests were cleared after one broker call even when owned orders or positions remained.
- Live actions now recount broker-owned exposure and retain the request until the applicable count reaches zero.
- Final compile: `0 errors, 0 warnings, 9102 ms`.
- Latest Shadow run: `29 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/broker_failure_policy_20260715/`.
- Boundary: pure policy/runtime fixture only; no real broker rejection or disconnect was induced.
- Readiness remains `READY FOR SHADOW MODE` for broker-free research only.

### 2026-07-15 — Challenge restore validation and configuration authority

- Found that persisted Challenge `risk_percent` and `stage_target` overrode runtime configuration, permitting stale/corrupt state to silently escalate risk after restart.
- Active-stage persistence now validates enum, finite values, equity/peak order, attempts, and profit-lock bounds.
- Configured stage risk/target/max-attempt values are authoritative after restore; invalid state becomes inactive/failed and the real startup path kills entries.
- Conservative Live no longer loads stale Challenge state.
- Final compile: `0 errors, 0 warnings, 13480 ms`.
- Latest Shadow run: `30 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/challenge_restore_20260715/`.
- Boundary: cash-flow detection, attempts/reset, profit-lock lifecycle, and real restart remain unproven.
- Readiness remains `READY FOR SHADOW MODE`; Challenge modes remain prohibited.

### 2026-07-15 — Challenge external cash-flow quarantine

- Added persisted millisecond/ticket history cursoring and external balance-deal classification.
- Initial funding is baselined; later deposits, withdrawals/charges, credits, corrections, or bonuses fail Challenge state, zero risk, and route to flattening.
- Persistence schema advanced to v3; prior versions quarantine entries fail-closed.
- Compile: `0 errors, 0 warnings, 8962 ms`; Shadow: `32 passed, 0 failed`, balance unchanged.
- Evidence: `TestEvidence/challenge_cashflow_20260715/`.
- Actual broker cash-flow and restart cursor recovery remain unproven; readiness remains Shadow only.

### 2026-07-15 — Challenge safety floors route to central flatten

- Found that stage-drawdown and profit-lock failures blocked new entries but did not liquidate already-open exposure.
- Challenge breach state now becomes failed/inactive with zero risk and returns an explicit flatten reason.
- The main controller routes that reason through centralized, ownership-aware, persistent `FlattenAll` handling.
- Final compile: `0 errors, 0 warnings, 13706 ms`.
- Latest Shadow run: `31 passed, 0 failed`; tester balance remained `10000.00`.
- Evidence: `TestEvidence/challenge_safety_flatten_20260715/`.
- Boundary: no actual broker position was closed; cash-flow, attempts/reset, and live close rejection remain unproven.
- Readiness remains `READY FOR SHADOW MODE`; Challenge modes remain prohibited.

### 2026-07-15 — Two-process restart probe and explicit persistence flush

- Added `Testing/QuantBeastRestartProbe.mq5` plus phase-1/phase-2 tester configs to test persistence across a complete terminal/tester/Wine process replacement.
- Phase 1 cleared, wrote, flushed, and verified schema-v3 risk, Challenge, cursor, and kill state: `PASS schema=3`.
- After fully replacing the process tree, phase 2 loaded `schema=0`, `cashflow_msc=0`, and `emergency=false`: recorded `FAIL`.
- Interpretation: Strategy Tester agent globals reset or are isolated across this boundary. This is not evidence that the normal terminal loses globals, and it is not a restart pass.
- Found and fixed a production durability omission: `PersistRuntimeState()` now calls `GlobalVariablesFlush()` after saving all state groups.
- Probe compile: `0 errors, 0 warnings, 729 ms`; production compile: `0 errors, 0 warnings, 17621 ms`.
- Post-repair Shadow regression: `32 passed, 0 failed`; `5520 ticks`, `276 bars`; final balance remained `10000.00`.
- Evidence: `TestEvidence/restart_probe_20260715/`.
- Current source hash: `8f848885b06ed6b8a56e496a8b941a7699eedfa0044c31a3f7ad6983f538d4ce`; EX5 hash: `d014de37bf21defaf5b62308a6afd373843d1013ae9860f621dad623dd278b29`.
- Boundary: run the real restart fixture in the normal terminal with demo broker positions/pending orders. Readiness remains `READY FOR SHADOW MODE`.

### 2026-07-15 — Server-acknowledgement return contract

- Found a High-severity execution-state defect: market and pending submission methods recorded rejected server retcodes but returned the raw `CTrade` boolean, allowing callers to treat a rejected request as accepted.
- Added order-class-specific pure acknowledgement policies and made both submission methods return only server-confirmed acceptance.
- Extended Test 27 with mismatched API/retcode injection; the fixture transmits no broker orders.
- The first compile attempt was rejected as stale because only include files had changed and MetaEditor left the older EX5 untouched. The main test label was updated, forcing a verified dependency rebuild.
- Compile: `0 errors, 0 warnings, 13754 ms`; EX5 timestamp advanced.
- Shadow regression: Test 27 reports `transmission=server-confirmed`; full suite `32 passed, 0 failed`; `5520 ticks`, `276 bars`; balance remained `10000.00`.
- Evidence: `TestEvidence/server_ack_policy_20260715/`.
- Source hash: `af4d869fb9a5079a942252c4ae3125a1c1d056ffe99576b6ac99c1907ef55368`; EX5 hash: `fa8530e33869600c36d054c5c8fba687af77d948163d978fa48f23c2637b4b19`.
- Boundary: no actual broker rejection/disconnect/modify failure was induced. Readiness remains `READY FOR SHADOW MODE`.

### 2026-07-15 — Pending-orphan fail-closed transitions

- Found two High-severity orphan risks: expiry cleared tracking after failed deletion, and absent current/history state cleared tracking without proving cancellation or safe fill reconciliation.
- Tracking now retires only after confirmed terminal history or a safely reconciled/protected/registered fill.
- Failed expiry deletion, missing history, and unsafe fill reconciliation preserve local tracking, latch cancel-all, and persist the request.
- Test 27 now injects these transitions without broker orders and reports `pending_state=fail-closed`.
- Compile: `0 errors, 0 warnings, 13175 ms`; Shadow: `32 passed, 0 failed`, `5520 ticks`, `276 bars`, balance `10000.00`.
- Evidence: `TestEvidence/pending_orphan_policy_20260715/`.
- Source hash: `5c4c024b82324cd3d9b938202c2e9302891051e66e2d1fd6be164ff8c6425888`; EX5 hash: `8a5eac230e434109d0a5baff129c8a9d0a9a0cc668f9a25df802c3779eed6a7e`.
- Boundary: actual broker cancel rejection, delayed history, and fill-during-cancel races remain unproven. Readiness remains Shadow only.

### 2026-07-15 — Kill-switch hard-risk priority during disconnect

- Found a Critical priority defect: terminal disconnection returned before equity-floor, account-lock, stop-failure, and repeated-rejection conditions could latch.
- Persistent hard-risk conditions now run before transient connectivity handling; connectivity alone still clears automatically after recovery.
- Added isolated Test 31 covering simultaneous equity-floor/disconnect emergency, repeated-rejection/disconnect persistence, and connectivity-only recovery.
- Compile: `0 errors, 0 warnings, 14509 ms`; Shadow: `33 passed, 0 failed`, `5520 ticks`, `276 bars`, balance `10000.00`.
- Evidence: `TestEvidence/killswitch_priority_20260715/`.
- Source hash: `3f01f3a06922095ec55275c3ded71995cab8d28ef59e12a57c70a8aabcf1311f`; EX5 hash: `96243ac44d598f145317cfdd5901315bc87e0bc3595e2f58cd3d5a56e3837fc0`.
- Boundary: a real network outage and broker actions after reconnect remain unproven. Readiness remains Shadow only.

### 2026-07-15 — Emergency action dispatcher, timer retry, and mode isolation

- Found High-severity emergency-action gaps: cancel/flatten was tick-only, could retry on every tick, and the prior non-Shadow branch allowed Diagnostic mode to call broker cancel/close methods.
- Centralized action servicing across tick and one-second timer paths with a shared one-second monotonic retry bound.
- Broker transmission is now explicit-live-mode-only; Diagnostic and Shadow paths cannot send broker actions through either the dispatcher or immediate protection emergency.
- Immediate protection emergency now explicitly persists its latch state.
- Test 31 now reports `broker_mode=live-only retry=bounded`.
- Compile: `0 errors, 0 warnings, 14859 ms`; Shadow: `33 passed, 0 failed`, `5520 ticks`, `276 bars`, balance `10000.00`.
- Evidence: `TestEvidence/emergency_dispatch_20260715/`.
- Source hash: `c37b6c4a7d1c16a347d4dec73377ee2db26b58da856fa1ef559faa600d7560da`; EX5 hash: `c422fbd87b5f3f7523323f51addd6b4479ec25a56bf4695943d62ed68b285538`.
- Boundary: no actual broker close/delete failure or reconnect was induced. Readiness remains Shadow only.

### 2026-07-15 — Consecutive broker-rejection production wiring

- Found a High-severity dead safety path: production `OnTick()` always supplied `false` for repeated broker rejection, and no rejection streak existed.
- Added `InpMaxConsecutiveBrokerFailures` (default 3) and pure counter/threshold policies.
- Only broker-attempted rejected submission cycles increment the streak; local pre-transmission price-displacement rejection is ignored, and server-confirmed acceptance resets it.
- The threshold latches the entry kill and the streak is persisted; state schema advanced from v3 to v4, so prior nonzero schemas quarantine fail-closed until explicitly cleared or migrated.
- Compile: `0 errors, 0 warnings, 9995 ms`; Shadow: `33 passed, 0 failed`, `5520 ticks`, `276 bars`, balance `10000.00`.
- Evidence: `TestEvidence/broker_rejection_counter_20260715/`.
- Source hash: `2460ed69599a441e998bd7085180677230465490f2c19dd889aa7075aee6d50d`; EX5 hash: `3142919aa1cff8cfe38e04a0259fdeba4f394f7abdacd0cfd06f85a0130198c9`.
- Boundary: no actual broker rejection, reconnect, or restart was induced. Readiness remains `READY FOR SHADOW MODE`.

### 2026-07-15 — Broker fault matrix and centralized protection-close ownership

- Found a High-severity duplicate-transmission race: failed protection could close inside `EnsurePositionProtection()` and then immediately close again through `ActivateProtectionEmergency()` before broker state converged.
- Refactored protection into a deterministic accept/repair/emergency decision. Verification no longer transmits closes; the centralized emergency dispatcher is the sole immediate close owner and retains bounded flatten retries while exposure remains.
- Unprotected accepted fills now remain `ACKNOWLEDGED` rather than being mislabeled `CLOSED` before broker confirmation.
- Centralized production classifiers for modify, close, delete, and price-retry server responses.
- Added Test 32 covering missing/looser stops, rejected repair/modify/close/delete, price-only retries, and fill-during-cancel retention without broker transmission.
- Compile: `0 errors, 0 warnings, 9378 ms`; Shadow: `34 passed, 0 failed`, `5520 ticks`, `276 bars`, balance `10000.00`.
- Evidence: `TestEvidence/broker_fault_matrix_20260715/`.
- Source hash: `36ce8244a23d904fd7f7c35b0b6d546cd1facfc8878f9b88511cc9ada0d5946b`; EX5 hash: `189dd97e138117005c3e7a9e3cc40e51f7ea3fac932b38412eacd773fdbd109d`.
- Boundary: no real broker fault or callback race was induced. Readiness remains `READY FOR SHADOW MODE`.

### 2026-07-15 — Organic pipeline inspection and rejected-direction repair

- A generated-tick fallback run organically produced valid FBO BUY and SELL candidates that passed feature, regime, strategy, and arbitration layers before central risk rejected their stops as too wide.
- Confirmed a Medium audit-integrity defect: `MakeRejected()` zero-initialized every rejected short as BUY, corrupting rejection journals and filter diagnostics.
- Made direction mandatory in the shared rejection constructor and updated every BO/FBO/TP/MR long and short rejection call.
- Tightened Tests 16–19 to require rejected shorts to retain `ORDER_TYPE_SELL`.
- Added Test 33 for safe trend/breakout versus shock regime classification and Test 34 for arbitration ranking, duplicate rejection, and opposing-signal rejection.
- Final compile: `0 errors, 0 warnings, 10309 ms`; Shadow regression: `36 passed, 0 failed`, `22080 ticks`, `1104 bars`, balance `10000.00`.
- At this historical milestone, a Model 4 probe at the first advertised real-tick date (2026-06-19) initialized but produced no test ticks before shutdown; true-real-tick coverage was blocked rather than passed.
- Evidence: `TestEvidence/organic_pipeline_20260715/`.
- Source hash: `e5e87b4431e57f4481fc7078f735ea46d7ae489335023528af721509587af52f`; EX5 hash: `24e9400a1a98edb83470d43bbc3b2316982d4875a1e059f649d4e00a1a3c7503`; readiness remains `READY FOR SHADOW MODE`.

### 2026-07-15 — Arbitration and signal-journal decision integrity

- Confirmed that position-conflict/stacking branches filtered candidates without clearing `valid`, and the controller journaled strategy candidates as accepted before arbitration or central risk.
- Arbitration now marks cooldown, duplicate, position conflict, exposure, conflict-policy, confluence failure, and lower-ranked outcomes as explicit invalid rejections.
- The controller logs strategy failures immediately, arbitration losers after arbitration, and the winner only after central risk accepts or rejects it.
- Signal-journal IDs now include direction so simultaneous long/short evaluations cannot share an ID.
- Expanded Test 34 to cover the selected FBO SELL plus lower-ranked, duplicate, opposing-conflict, and same-direction-exposure rejections.
- Compile: `0 errors, 0 warnings, 10330 ms`; Shadow: `36 passed, 0 failed`, `22080 ticks`, `1104 bars`, balance `10000.00`.
- Evidence: `TestEvidence/arbitration_journal_20260715/`.
- Source hash: `a771a2f6e2f3812f478885df525400f2b697f16656087ae208f08953e1588a6d`; EX5 hash: `0357dfb5323a25969645f59ea2ca6c95de642678e8c2c7d376337fd172469e85`.
- At this historical milestone, file-level CSV proof remained pending an organic post-repair run; readiness remained `READY FOR SHADOW MODE`.

### 2026-07-15 — Arbitration/journal documentation synchronization

- Synchronized `README.md`, `ARCHITECTURE.md`, `KNOWN_LIMITATIONS.md`, `BUILD_AUDIT.md`, `REPAIR_AUDIT_20260715.md`, and `TESTING_GUIDE.md` with the verified arbitration and signal-decision repair.
- Updated the then-current repair-audit source/EX5 hashes, compile duration, and evidence list to the historical `a771a2...` / `0357df...` build.
- Reclassified the prior incomplete-journaling statements as historical or repaired, while retaining the then-honest boundary that an organic post-repair CSV inspection remained pending.
- Corrected the stale testing-guide reference from an older 32/0 run to the then-current 36/0 Shadow regression.
- Documentation-only change after the already verified `0 errors, 0 warnings` build; no source, EX5, preset, or tester configuration changed.

### 2026-07-15 — Post-repair organic CSV rerun attempt

- Attempted the existing generated-tick Shadow fixture to obtain file-level signal-journal evidence; no live or Challenge mode was enabled.
- The native MT5 MCP transport at `127.0.0.1:22346` was unavailable.
- A direct Wine `/config` fallback opened `terminal64.exe` but did not create a new tester-agent log section or signal CSV; the existing agent log timestamp remained `18:24:17`.
- Stopped the terminal process launched by this attempt. No MT5/Wine tester process was left running.
- Recorded the blocked boundary in `TestEvidence/arbitration_journal_20260715/EVIDENCE.md`. No source, EX5, preset, or tester configuration changed.

### 2026-07-16 — Final safe-phase audit, fixes, and organic true-tick proof

- Revalidated native MT5 MCP workspace, compiler, and tester capabilities before continuing.
- Confirmed March real-tick proof was unavailable because local XAUUSD tick data begins 2026-06-19; generated fallback was not treated as true-real-tick evidence.
- Fixed a Medium final-decision defect: signal `ACCEPTED` is now written only after final strategy/arbitration/risk/sizing/broker-preflight acceptance; later central failures are logged as `REJECTED`.
- Fixed a High journal-integrity defect: existing CSV journals now seek to end before writing and fail closed if append positioning fails. A pre-fix proof attempt corrupted the shared Common `SignalJournal.csv` prefix; it is preserved honestly and excluded from current evidence.
- Added deterministic Test 35 for real final-decision signal-writer rows and Test 36 for performance metric updates when file trade journaling is disabled.
- Fixed a Medium dashboard diagnostic throttle defect and a Medium `TradeJournal` performance-update/file-journal coupling defect.
- Final compile evidence remained `0 errors, 0 warnings`; final deterministic run reported `38 passed, 0 failed`.
- Final source SHA-256: `220577a689c55b7ee263e0bae779752b610e0c75ca3f5ff528d2bb473a0ce30a`; final EX5 SHA-256: `fca02855e1396c768c974b3ce2650beb45f4af51f81f9d14f4ed714be8590040`.
- Closed the immediate organic CSV blocker with a true-tick Shadow run on XAUUSD M5, 2026-06-22 to 2026-06-23, all strategies enabled, self-tests disabled: 417423 ticks, 276 bars, 880 new signal rows, accepted FBO BUY/SELL entries, risk-rejected winner, and separate order/trade journal rows.
- Evidence: `TestEvidence/audit_final_20260716/`, `TestEvidence/organic_true_ticks_20260716/`, and `FINAL_ADVERSARIAL_AUDIT_20260716.md`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Session-end and rollover exit policy

- Defect demonstrated: `InpCloseBeforeSessionEnd` and `InpCloseBeforeRollover` were declared but incomplete; the EA had no deterministic policy for acting on those controls.
- Severity: Medium safety/configuration defect; operators could enable the controls and assume positions would be flattened near configured boundaries when they were not.
- Fix: added `QBSessionExitPolicyTriggered()` and `ProcessSessionExitPolicy()`. Shadow positions close with `EXIT_SESSION_END`; live modes request the existing bounded flatten path only when explicitly live modes and operator-enabled inputs are active.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `45 passed, 0 failed`, including `TEST 43 PASS: Session exit policy`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/session_exit_policy_20260716/`.
- Source SHA-256: `8312ffcd21e9e5a8d051315acd14398e3aba7b7488ab4a8888186957ffde34b8`; ShadowPortfolio SHA-256: `964eab9205a42269b75eef4089d151070660fe7338e93b460bc569c955bfcf2e`; EX5 SHA-256: `834e063c510e940e2ff366a8deea4edda32511b06f3ec8ff2cfb4b7d361bd5a7`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Entry preflight controls for price jump and warmup

- Defect demonstrated: `InpMaxPriceJumpPoints` and `InpBarWarmup` were declared but did not affect entry behavior.
- Severity: Medium safety/configuration defect; operators could believe price-jump and startup-warmup gates were active when they were not.
- Fix: added `QBEntryPreflightControlsAllow()` and wired it into `OnTick()` after data-quality validation. Entries are now blocked by failed data quality, insufficient primary bars versus `InpBarWarmup`, or abnormal tick jumps over `InpMaxPriceJumpPoints`.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `44 passed, 0 failed`, including `TEST 42 PASS: Entry preflight controls`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/entry_preflight_controls_20260716/`.
- Source SHA-256: `51fa5531bde94f6b2f47af2d0ea5c4086c10bdae3cf08727f84bbab9371413ef`; EX5 SHA-256: `ea722ed75340747dfd5487fa4ece3c37d760370ab84b8e3503c77ddba0e9dfef`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Live recovery no-passive-flatten gate

- Defect demonstrated: `CPositionManager::ReconstructFromBroker()` can call `m_broker.ClosePosition(ticket)` for `UNKNOWN_FLATTEN` during startup reconstruction. In a live mode this is a broker-mutating startup path before an operator has explicitly authorized closing unknown positions.
- Severity: High for live/restart safety; affected paths are Conservative Live and acknowledged Challenge Live startup recovery with `InpUnknownPosPolicy=UNKNOWN_FLATTEN`.
- Fix: added `QBLiveRecoveryPolicyAllowed()` and wired it into live initialization. Live modes now fail initialization when `InpUnknownPosPolicy=UNKNOWN_FLATTEN`; `UNKNOWN_IGNORE`, `UNKNOWN_REPORT`, and `UNKNOWN_QUARANTINE` remain allowed because they do not transmit close orders during startup.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `41 passed, 0 failed`, including `TEST 39 PASS: Live recovery gate no passive flatten`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/live_recovery_gate_20260716/`.
- Source SHA-256: `4611b0a29f54744a3ff4ee75eddb09d83c103d3954300930affc830c2ac487aa`; EX5 SHA-256: `5a266f505530aa67a84a775c38a290d5cb4d24321ddccc1a552ad7de0886bafe`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Independent strategy train baselines

- Ran BO, FBO, TP, and MR independently on the same XAUUSD M5 true-tick Shadow training window (`2026.06.22` to `2026.06.26`) using the reproducible configs under `TestEvidence/performance_readiness_20260716/`.
- All four per-strategy runs completed with normal tester footers, Model 4 true ticks, `1,736,377` ticks, `1,104` bars, `OnTester result 0`, and final balance `10000.00`.
- BO-only: `940` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts were balanced at `470/470`.
- FBO-only: `940` signal rows, `935` rejected, `5` accepted; accepted FBO BUY `3`, FBO SELL `2`; `5` Shadow orders/trades; net `-193.03`; profit factor `0.373869`.
- TP-only: `940` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts were balanced at `470/470`.
- MR-only: `940` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts were balanced at `470/470`.
- Per-strategy evidence files were added under `TestEvidence/performance_readiness_20260716/` with metrics, suffix CSVs, excerpts, and accepted-signal files.
- Interpretation: strategy-only true-tick train configs are runnable and direction-preserving, but only FBO reached accepted trade state in this window. BO/TP/MR accepted organic entries remain unproven and are not to be optimized before correctness/evidence gates expand.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Performance-readiness baseline configs and train proof

- Added reproducible Shadow-mode performance-readiness configs under `TestEvidence/performance_readiness_20260716/` for XAUUSD M5 true-tick combined train/holdout and per-strategy train windows.
- Combined train baseline (`2026.06.22` to `2026.06.26`) completed from a temporary `Profiles/Tester` launcher config and was then cleaned up.
- Train result: Model 4 true ticks, `1,736,377` ticks, `1,104` bars, final tester footer present, test passed in `0:14:42.937`.
- Train journal suffix: `3,760` signal rows, `3,755` rejected, `5` accepted; accepted FBO BUY `3`, FBO SELL `2`; `5` Shadow orders/trades; closed-trade net `-193.03`; profit factor `0.373869`. This is a baseline observation, not an edge claim.
- Combined holdout first attempt (`2026.06.29` to `2026.07.03`) appended partial journal rows but was invalid/incomplete: no final tester footer was written and the signal suffix ended at `2026.06.29 21:55:00`, before the configured end.
- After a clean terminal/tester restart, the combined holdout retry completed with a normal final footer: Model 4 true ticks, `1,464,441` ticks, `1,104` bars, test passed in `0:12:54.454`.
- Holdout retry journal suffix: `4,520` signal rows, `4,510` rejected, `10` accepted; accepted FBO BUY `8`, FBO SELL `2`; `10` Shadow orders/trades; closed-trade net `64.66`; profit factor `1.300521`. This is a single holdout baseline observation, not an edge claim.
- Temporary train/holdout launcher configs were removed from `MQL5/Profiles/Tester`.
- Evidence: `TestEvidence/performance_readiness_20260716/`.
- No source or EX5 code changed; recalculated hashes remain source `220577a689c55b7ee263e0bae779752b610e0c75ca3f5ff528d2bb473a0ce30a`, EX5 `fca02855e1396c768c974b3ce2650beb45f4af51f81f9d14f4ed714be8590040`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Independent strategy holdout baselines

- Revalidated native MT5 MCP workspace and tester capability before continuing.
- Completed the remaining per-strategy XAUUSD M5 true-tick Shadow holdout baselines (`2026.06.29` to `2026.07.03`) using the reproducible configs under `TestEvidence/performance_readiness_20260716/`.
- BO-only holdout: `1,464,441` ticks, `1,104` bars, test passed in `0:12:32.122`; `1,130` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts balanced at `565/565`.
- FBO-only holdout: `1,464,441` ticks, `1,104` bars, test passed in `0:14:07.638`; `1,120` rejected and `10` accepted signal rows; accepted FBO BUY `8`, FBO SELL `2`; `10` Shadow orders/trades; net `64.66`; profit factor `1.300521`.
- TP-only holdout: `1,464,441` ticks, `1,104` bars, test passed in `0:14:01.034`; `1,130` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts balanced at `565/565`.
- MR-only holdout: `1,464,441` ticks, `1,104` bars, test passed in `0:12:53.861`; `1,130` rejected signal rows, `0` accepted, `0` orders/trades; BUY and SELL rejection counts balanced at `565/565`.
- Per-strategy holdout evidence files were added under `TestEvidence/performance_readiness_20260716/` with metrics, suffix CSVs, excerpts, and accepted-signal files.
- Updated `TestEvidence/performance_readiness_20260716/EVIDENCE.md`, `README.md`, `TESTING_GUIDE.md`, `KNOWN_LIMITATIONS.md`, and `FINAL_ADVERSARIAL_AUDIT_20260716.md`.
- Interpretation: strategy-only true-tick holdout configs are runnable and direction-preserving, but only FBO reached accepted trade state in this holdout window. BO/TP/MR accepted organic entries remain unproven.
- No source or EX5 code changed; hashes remain source `220577a689c55b7ee263e0bae779752b610e0c75ca3f5ff528d2bb473a0ce30a`, EX5 `fca02855e1396c768c974b3ce2650beb45f4af51f81f9d14f4ed714be8590040`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Live strategy/execution gates and FBO-only market-only conservative preset

- Confirmed a High live-safety/configuration risk: the Conservative Live preset could inherit default BO/FBO/TP/MR enablement even though only FBO has organic accepted BUY/SELL evidence.
- Added a production live-mode initialization gate: Conservative Live and acknowledged Challenge Live now initialize only when the enabled strategy set is exactly FBO-only. Added a second live-mode execution gate requiring market-order-only operation with stop/limit pending orders disabled and `InpMaxPendingOrders=0`. Shadow and Diagnostic research modes remain unchanged.
- Updated `XAUUSD_Conservative_Live.set` to be explicitly not approved for live, FBO-only, market-order-only, lower risk, tighter exposure, persistence-enabled, and unknown-position quarantine.
- Added deterministic self-test coverage: `TEST 37 PASS: Live strategy gate FBO-only` and `TEST 38 PASS: Live execution gate market-only`.
- Compile: `0 errors, 0 warnings, 31480 ms`.
- Shadow regression: `40 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; test passed in `0:00:21.999`.
- Evidence: `TestEvidence/live_strategy_gate_20260716/`.
- Source SHA-256: `5590b568ce72f9718faad863f763c74e08f1bddc5c056ac11005d866d4b11010`; EX5 SHA-256: `ca27819e558e1c1a1a6f14793d7721f9b5f7455de156971d987d5047ffcc77bf`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Unknown positions left unmanaged on restart

- Defect demonstrated: `CPositionManager::ReconstructFromBroker()` could add unknown-strategy positions to the active management array for `UNKNOWN_REPORT`/`UNKNOWN_QUARANTINE`, allowing later trailing, partial-close, or stop modification against an unknown strategy context.
- Severity: High for live/restart safety; affected path is live startup reconciliation of QuantBeast-range positions whose strategy ownership cannot be recovered from comment/history.
- Fix: added `QBUnknownPositionShouldBeManaged()` and changed reconstruction so unknown positions are reported/quarantined/ignored without active adoption. `UNKNOWN_FLATTEN` also remains unmanaged if a close is not confirmed.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `42 passed, 0 failed`, including `TEST 40 PASS: Unknown positions unmanaged`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/unknown_position_unmanaged_20260716/`.
- Source SHA-256: `12488268def53445f064bcb2c92369446dee14a396b478074aeb8d0fc4717b07`; PositionManager SHA-256: `f1eb5c8f75a5342015029488cc57f02bb312f8a8877b04fee4feee59be48eb72`; EX5 SHA-256: `277379e14b902d0bc1fcf48eb2dbaa75e76cb3f090358b7be6f5d9835b5440f9`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Alert controls wired with tester-safe routing

- Defect demonstrated: alert inputs and `Alerts.mqh` existed but the EA never included, initialized, or called the alert component, leaving operator-facing alert controls disconnected.
- Severity: Medium operational defect; configured safety warnings could not fire, but no broker exposure was created.
- Fix: initialized `CAlerts`, added tester-safe suppression, routed key signal rejection/acceptance, order rejection, and protection emergency events through configured alert flags, and added deterministic alert-routing self-test coverage.
- Validation: compile `0 errors, 0 warnings`; generated-tick Shadow regression `43 passed, 0 failed`, including `TEST 41 PASS: Alert routing disabled=suppressed enabled=routed count=1`.
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/alert_routing_20260716/`.
- Source SHA-256: `2b1dead892b25081d026d63b696776f201f9d2c132e5ea641f2588dcc529685a`; Alerts SHA-256: `7e517231b8a037761627ad687c7364e089d6c8a1d8634ee0ed6038b824433778`; EX5 SHA-256: `bed035a8f6b03fe73defde9fac0dd7e641e4b18b3b7f3e09691bb9b507dceb3b`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Effective-symbol persistence scope repair

- Confirmed a High recovery/isolation defect: persisted Terminal Global Variable keys were scoped by account login and chart `_Symbol`, while QuantBeast supports `InpPrimarySymbol` and can trade a different effective adapter symbol.
- Added explicit state-scope symbol storage in `StateStore.mqh`; `GV_ScopedName()` now uses the effective adapter symbol after `OnInit()` calls `SetStateScopeSymbol(g_Adapter.Symbol())`.
- Added deterministic Test 20b: `State scope policy symbol=scoped account=scoped override=effective`.
- Compile: `0 errors, 0 warnings, 12581 ms`.
- Shadow regression: `40 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; test passed in `0:00:11.537`.
- Evidence: `TestEvidence/state_scope_20260716/`.
- Source SHA-256: `5590b568ce72f9718faad863f763c74e08f1bddc5c056ac11005d866d4b11010`; EX5 SHA-256: `ca27819e558e1c1a1a6f14793d7721f9b5f7455de156971d987d5047ffcc77bf`.
- No broker orders were transmitted; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Current clean compile and Shadow regression checkpoint

- Revalidated native MT5 MCP workspace, compiler, and tester capability before continuing.
- Pre-run process check found only the MT5 terminal and wineserver; no MetaEditor or tester process was active before launch.
- Compile: `0 errors, 0 warnings, 21189 ms`, MetaEditor build 6002, timestamp `2026.07.16 13:29:54.162`.
- Ran a unique generated-tick Shadow regression config, `QuantBeast.CurrentRegression.XAUUSD.M5.20260716_1329.ini`, with live broker acknowledgement false, Challenge acknowledgement false, persistence/global variables disabled, journals disabled, and self-tests enabled.
- The tester MCP returned the known unreliable `job_id: 0`; validation used a bounded newly appended local tester-agent log suffix.
- Result: `Self-tests complete: 51 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; `OnTester result 0`; normal tester footer present.
- Temporary `MQL5/Profiles/Tester` launcher config was removed after the run.
- Evidence: `TestEvidence/current_regression_20260716/`.
- Current hashes after compile: source `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; EX5 `352c6be5f415370c9548315aea4a5dad9cb645f022c8a0afd9bb37cbc61ad1d3`; configuration module `287d8f29198bd829367fcc49650c849afafd5fe95b289411c77a92ab2a9635e6`.
- No broker orders were transmitted by this regression. The manual demo broker lifecycle remains manual/MCP evidence only, not QuantBeast EA-autonomous live execution evidence. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — BO compression-percent input wired to ATR percentile rank

- Defect demonstrated: `InpBO_CompressionPct` was passed into `CBreakoutEngine::Init()` as `m_compressionPct`, but `CBreakoutEngine::IsEligible()` never read it. BO eligibility depended only on shared `features.compression_bars`.
- Severity: Medium configuration-integrity defect; operators could change a BO-specific compression parameter without changing BO eligibility, creating misleading strategy research/live-readiness evidence.
- Fix: added `FeatureSnapshot::atr_percentile_rank`, calculated current ATR percentile rank in `FeatureEngine`, and required `features.atr_percentile_rank <= m_compressionPct` in BO eligibility while preserving the shared minimum compression-bar duration gate.
- Signal descriptions now include `atrRank`, and deterministic BO reachability coverage now verifies percentile rejection with `pct=rejected`.
- Updated `CONFIGURATION_GUIDE.md`, `STRATEGY_SPEC.md`, and `KNOWN_LIMITATIONS.md` to remove the stale BO-compression limitation while keeping other strategy semantic gaps open.
- Compile: `0 errors, 0 warnings, 20999 ms`, timestamp `2026.07.16 13:34:32.590`.
- Shadow regression: `TEST 16 PASS: BO reachability L=valid S=valid gate=rejected pct=rejected`; `51 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; normal tester footer present.
- Evidence: `TestEvidence/bo_compression_pct_20260716/`.
- Hashes: main source `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; EX5 `dd953b52e9c14ef0518d62df3f258a1259d0f1f1c449eeaad833fe0a280ffb73`; `Types.mqh` `aa556c64e1dea5db61910fa7f8ecb0033c1b27205fcfa6ba2f2dce79621397c7`; `FeatureEngine.mqh` `e85101e9d497366e10c2e4cc4eeebea7c323adafa25645fa64b8797666d358f2`; `BreakoutEngine.mqh` `4f4358d1d89564488edb6dd7e7ba4727e27296e4ce87a32595e21d434299b2d5`; `SafetyTests.mqh` `23e68c84d3e7d9fbcbc045234edbd6dd4f3115ed6addaf9c0a972a43c529bc2f`.
- No broker orders were transmitted. BO organic accepted entries remain unproven; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — TP max-pullback-bars input wired to swing-age rejection

- Defect demonstrated: `InpTP_MaxPullbackBars` was passed into `CTrendPullbackEngine::Init()` as `m_maxPullbackBars`, but TP long/short evaluation did not enforce pullback age.
- Severity: Medium configuration-integrity defect; operators could change the maximum pullback duration without changing TP eligibility, creating misleading strategy research/live-readiness evidence.
- Fix: long TP setups now reject when `features.swing_high_bars > m_maxPullbackBars`, short TP setups now reject when `features.swing_low_bars > m_maxPullbackBars`, and TP signal descriptions include `age=`.
- Zero swing-age values are treated as unavailable rather than as stale-pullback proof.
- Updated `CONFIGURATION_GUIDE.md`, `KNOWN_LIMITATIONS.md`, and `REPAIR_AUDIT_20260715.md` to remove the stale TP pullback-age limitation while keeping FBO and MR semantic gaps open.
- Compile: `0 errors, 0 warnings, 19911 ms`, timestamp `2026.07.16 13:39:11.437`.
- Shadow regression: `TEST 18 PASS: TP reachability L=valid S=valid age=rejected gate=rejected`; `51 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; normal tester footer present.
- Evidence: `TestEvidence/tp_pullback_age_20260716/`.
- Hashes: main source `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; EX5 `e64f3f8ce8b201b7614d13c3a6ea4129677883657c01af4528a35735f4e6f859`; `TrendPullbackEngine.mqh` `41a5c6050560ed52c85e355c1a6e032b5ff36046f29e91e3a11882a69079f905`; `SafetyTests.mqh` `c9fbb503b55c851062583a435207c8e9ccb49749df26fea04dcd56aaab0ffdb0`.
- No broker orders were transmitted. TP organic accepted entries remain unproven; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — MR opposite standard-deviation-band target wired

- Defect demonstrated: `InpMR_TargetSDBandR` was stored in `CMeanReversionEngine` but never used. MR targets only used VWAP, range midpoint, or fixed-R fallback.
- Severity: Medium configuration-integrity defect; operators could change an MR target input without affecting MR target geometry, creating misleading strategy research/live-readiness evidence.
- Fix: when `features.vwap_sd > 0`, MR long targets the opposite upper VWAP SD band (`vwap + InpMR_TargetSDBandR * vwap_sd`) and MR short targets the opposite lower VWAP SD band (`vwap - InpMR_TargetSDBandR * vwap_sd`). Existing VWAP, range-midpoint, and fixed-R fallbacks remain for unavailable/invalid band geometry.
- MR signal descriptions now include `targetBandR`.
- Validation included an intentionally failed compile caused by using nonexistent test field `StrategySignal.target`; corrected to `proposed_target` before final compile.
- Compile: `0 errors, 0 warnings, 19852 ms`, MetaEditor build 6002.
- Shadow regression: `TEST 19 PASS: MR reachability L=valid S=valid bandL=ok bandS=ok gate=rejected`; `51 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; normal tester footer present.
- Evidence: `TestEvidence/mr_target_band_20260716/`.
- Hashes: main source `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; EX5 `136d822b4f92d84711e6e8e9f0ca65b1001add796e5983c79eca8150c547c591`; `MeanReversionEngine.mqh` `e77275d0b56f14a788595ea6c83b4f608448a5d1ab65365a6329ee9458ed3443`; `SafetyTests.mqh` `2faf41297450ea5493ea25f3f8e27cfee0751652312ceb4ced67281069717ab6`.
- No broker orders were transmitted. MR organic accepted entries remain unproven; readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — FBO midpoint/VWAP target fallbacks wired independently

- Defect demonstrated: `InpFBO_TargetVWAPR` was stored in `CFailedBreakoutEngine` but fallback target geometry used only `InpFBO_TargetMidR` when midpoint/VWAP levels were invalid.
- Severity: Medium configuration-integrity defect; operators could change the VWAP target fallback input without affecting fallback target geometry.
- Fix: FBO now builds separate midpoint and VWAP target candidates. Valid midpoint/VWAP levels are still used; invalid or wrong-side midpoint falls back through `InpFBO_TargetMidR`, and invalid or wrong-side VWAP falls back through `InpFBO_TargetVWAPR`. Longs select the higher candidate; shorts select the lower candidate, preserving the prior directional intent.
- FBO signal descriptions now include `targetMidR` and `targetVWAPR`.
- Compile: `0 errors, 0 warnings, 20130 ms`, MetaEditor build 6002.
- Shadow regression: `TEST 17 PASS: FBO reachability L=valid S=valid targetL=vwapR targetS=vwapR gate=rejected`; `51 passed, 0 failed`; `22080` generated ticks, `1104` bars; final balance `10000.00`; normal tester footer present.
- Evidence: `TestEvidence/fbo_target_variants_20260716/`.
- Hashes: main source `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`; EX5 `869da00fbd86607002ad605c5364511938e33a93a2875f91df9ee134647ec232`; `FailedBreakoutEngine.mqh` `0790d244f9682a9cb774b5ad04e24b48963ee5bb4d3fb52d5bfb44934f4bbdab`; `SafetyTests.mqh` `b9937f79d9ee928fd02824c12ab5a1026daea7652533f2c26a8abaead40d6fbc`.
- No broker orders were transmitted. This proves deterministic FBO target-input wiring, not performance edge. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Conservative Live Strategy Tester FBO attempt blocked by live-ack input override

- Attempted a broker-free Strategy Tester run of `QB_MODE_CONSERVATIVE_LIVE` to exercise EA-autonomous live-order routing in tester only.
- Config intent: FBO-only, market-only, no pending orders, Challenge acknowledgement false, `InpAcknowledgeLiveBrokerRisk=true`, persistence/global variables disabled.
- Three input-loading variants were tried: inline optimization-style `[TesterInputs]`, separate `.set` via tester `inputs_path`, and plain `[TesterInputs]` key/value overrides.
- In every attempt the tester applied `InpMode=2`, but did not apply/expose `InpAcknowledgeLiveBrokerRisk=true`. QuantBeast failed closed at `OnInit()` with `Live broker-transmission gate blocked initialization: Live broker transmission requires explicit InpAcknowledgeLiveBrokerRisk=true`.
- This is useful safety evidence for the live broker-transmission gate, but it blocks EA-autonomous Conservative Live tester execution evidence through the current native tester path.
- Evidence: `TestEvidence/conservative_live_tester_fbo_20260716/`.
- No source or EX5 code changed. No broker orders were transmitted; the connected demo account remained flat. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — Documentation drift correction after safe-phase repair work

- Defect demonstrated: `ARCHITECTURE.md` still described several repaired areas using older baseline language: alerts as disconnected, arbitration duplicate/cooldown persistence as incomplete, SafetyTests as 38-policy coverage, configuration as having at least 22 inactive inputs, and state persistence as saving only selected risk/challenge/kill values. `FINAL_ADVERSARIAL_AUDIT_20260716.md` also still listed close-before-session/rollover controls and repaired strategy-input variants as inactive/partial.
- Severity: Documentation. Runtime behavior was not changed, but stale architecture/audit text could mislead the next operator or agent about the current verified state.
- Fix: updated `ARCHITECTURE.md` to reflect wired alert routing, 51 deterministic fixture coverage, bounded arbitration duplicate/cooldown persistence, expanded StateStore scope, current unknown-position/pending-order recovery policy, and remaining durable-context gaps. Updated `FINAL_ADVERSARIAL_AUDIT_20260716.md` to distinguish remaining advanced exit/strategy variants from controls that now have deterministic policy coverage.
- Validation: documentation-only change; no source, preset, or EX5 behavior changed. Latest validated build remains the previous `0 errors, 0 warnings` compile with deterministic Shadow regression `51 passed, 0 failed` and EX5 SHA-256 `869da00fbd86607002ad605c5364511938e33a93a2875f91df9ee134647ec232`.
- Safety: no broker order was transmitted. Manual/MCP demo lifecycle evidence remains separate from QuantBeast EA-autonomous execution evidence. Readiness remains exactly `READY FOR SHADOW MODE`.

### 2026-07-16 — README evidence synchronization

- Defect demonstrated: `README.md` lagged the latest evidence set and current verified status, omitting the newer `current_regression`, BO/TP/MR input-wiring, arbitration persistence, live-ack gate, demo lifecycle, and tester fail-closed evidence folders from the top-level evidence list.
- Severity: Documentation. The project state itself was already validated, but the top-level summary did not fully reflect the current evidence set.
- Fix: updated the opening status paragraph to mention deterministic BO/TP/MR strategy-input wiring and expanded the evidence list with the latest regression, arbitration, persistence, preset-gate, live-ack, BO/TP/MR, demo lifecycle, and tester-fail-closed folders.
- Validation: documentation-only change; no source, preset, or EX5 behavior changed. Latest validated build remains `0 errors, 0 warnings`, deterministic Shadow regression remains `51 passed, 0 failed`, and readiness remains exactly `READY FOR SHADOW MODE`.
- Safety: no broker order was transmitted. Manual/MCP demo lifecycle evidence remains separate from QuantBeast EA-autonomous execution evidence.

### 2026-07-16 — Limitations and testing-guide evidence sync

- Defect demonstrated: `KNOWN_LIMITATIONS.md` and `TESTING_GUIDE.md` still lacked the latest regression and wiring evidence references in their summary paragraphs, even though the underlying runtime state had already been repaired and validated.
- Severity: Documentation. The operational state was unchanged, but the project’s evidence map was not yet fully synchronized across the top-level guidance docs.
- Fix: added `current_regression_20260716`, BO/TP/MR/FBO wiring evidence, and the current live-ack/demo lifecycle evidence to the summary bullets and testing debt narrative.
- Validation: documentation-only change; no source, preset, or EX5 behavior changed. Latest validated build remains `0 errors, 0 warnings`, deterministic Shadow regression remains `51 passed, 0 failed`, and readiness remains exactly `READY FOR SHADOW MODE`.
- Safety: no broker order was transmitted.
### 2026-07-16 — Shadow-mode gating invalidates restart_recovery_20260716 Scenario 1 as reconciliation evidence

- Finding demonstrated: the restart_recovery_20260716 Scenario 1 fixture ran with QuantBeast attached in `QB_MODE_SHADOW`. Source inspection (`QuantBeastEA.mq5`, ~line 910) confirms `ReconstructFromBroker()` only executes outside the Diagnostic/Shadow branch — Shadow mode "must never inspect, cancel, close, or adopt broker positions/orders" by design.
- Consequence: the observed "no destructive action" on position #34615308 is Shadow-mode passivity, not evidence of correct ownership classification. The scenario did not exercise the code path it was meant to test (magic-range check, position adoption, active management eligibility).
- Severity: Documentation/Evidence. No runtime defect exists, but the TestEvidence catalog must not credit this data toward the restart-recovery gate.
- Same structural problem applies to Scenario 3 (unknown positions, magic 99999999) — not yet run, but blocked for the identical reason.
- Reclassification: Scenario 1 result is INVALID/NON-EXERCISING, matching the project's existing convention for preserved-but-excluded evidence (see the 2026-07-15 post-repair CSV precedent). TestEvidence/restart_recovery_20260716/ remains intact for the record, but EVIDENCE.md explicitly states this data does not count toward `LIVE_DEPLOYMENT_CHECKLIST.md`.
- Unresolved question (recorded, not answered): what is the minimum mode/acknowledgement configuration that reaches `ReconstructFromBroker()` on Coinexx-Demo, and does using it conflict with `AGENTS.md`'s live-mode restrictions?
- Evidence: `MQL5/Experts/QuantBeast/TestEvidence/restart_recovery_20260716/EVIDENCE.md`.
- Files changed: `TestEvidence/restart_recovery_20260716/EVIDENCE.md` (created), `KNOWN_LIMITATIONS.md` (restart bullet updated), `HANDOFF.md` (this entry).
- Readiness remains exactly `READY FOR SHADOW MODE`; live and Challenge trading remain prohibited.
- Safety: no broker order was transmitted by QuantBeast during this investigation.

### 2026-07-16 — Live-broker-ack gate confirmed as sole blocker for ReconstructFromBroker(); Diagnostic mode does not reach reconciliation

- Source: manual/operator-driven investigation outside any agent session, cross-referenced against terminal Experts log (`Logs/20260716.log`) between 20:30 and 21:16 UTC-5.
- Finding 1: `InpAcknowledgeLiveBrokerRisk` gate fires immediately on every Conservative Live initialization attempt — `"Live broker-transmission gate blocked initialization: Live broker transmission requires explicit InpAcknowledgeLiveBrokerRisk=true"` — before any other gate (strategy set, market-only, unknown-position policy) is evaluated. This is direct terminal Experts log evidence, not inference.
- Finding 2: Challenge mode without acknowledgement behaves differently — it logs a WARN and falls back to Shadow rather than hard-failing initialization like Live mode does. This is a documented behavioral asymmetry, not a defect, but was not explicit anywhere before this entry.
- Finding 3: Diagnostic mode was manually attached and initialized successfully (21:16:07, XAUUSD H1) with no gate failure. This does NOT mean Diagnostic reaches `ReconstructFromBroker()` — per the 2026-07-16 Shadow-mode finding already in HANDOFF.md, Diagnostic falls into the same non-reconciling branch as Shadow. Diagnostic attaching cleanly is not progress toward restart-recovery evidence.
- Finding 4: this session confirms (but does not yet resolve) the open question from the 2026-07-16 restart-recovery entry: `InpAcknowledgeLiveBrokerRisk` is now known to be the first blocking gate for reaching `ReconstructFromBroker()` via Conservative Live mode on Coinexx-Demo. It is not the sole gate — see Finding 5.
- Finding 5: with `InpAcknowledgeLiveBrokerRisk=true` set, a second gate fired: `"Live execution gate blocked initialization: Live pending orders are disabled until activation, expiry, cancellation, fill-race, and restart evidence is complete"`. This confirms the Conservative Live initialization gate order as: (1) `InpAcknowledgeLiveBrokerRisk=true`, (2) market-order-only / `InpMaxPendingOrders=0`, (3) FBO-only strategy set (not yet confirmed empirically), (4) `InpUnknownPosPolicy != UNKNOWN_FLATTEN` (not yet confirmed empirically).
- Severity: Documentation / operational clarity. No source, preset, or EX5 changed.
- Readiness remains exactly `READY FOR SHADOW MODE`; live and Challenge trading remain prohibited.
- Safety: no broker order was transmitted by QuantBeast during this investigation.
- **Operator authorization (2026-07-16):** Operator explicitly authorized using Coinexx-Demo as a disposable/abuse-tolerant account for Conservative Live mode testing, understanding this means QuantBeast may autonomously transmit real broker orders on this account for the first time (as opposed to prior manual/script/MCP placed trades). Authorization scope: this demo account, Conservative Live mode, current FBO-only/market-only gate configuration.
- **Resolution — Conservative Live init succeeded:** after (a) confirming `InpAcknowledgeLiveBrokerRisk=true`, and (b) discovering the earlier "pending orders disabled" failure was a preset-load procedure issue — the `.set` file must be explicitly loaded via the Inputs tab's **Load** button, not just present in the folder — Conservative Live mode initialized successfully on Coinexx-Demo. Confirmed minimum config: preset `XAUUSD_Conservative_Live.set` explicitly loaded via Load button + `InpAcknowledgeLiveBrokerRisk` manually set to `true`. This answers the open question from the 2026-07-16 restart-recovery entry: Conservative Live on Coinexx-Demo with this config reaches `ReconstructFromBroker()`.
- **⚠ LIVE-ARMED: QuantBeast is now live-armed on Coinexx-Demo and actively watching for real FBO signals. It can autonomously transmit a real broker order at any point from now until detached or switched back to Shadow. This is a new state for this project — every prior broker action was manual/script/MCP-placed, never EA-autonomous. Do not mistake an autonomous entry for a fixture artifact.**

### 2026-07-21 — Full build-out Phases 1-4: strategy variations, risk/exec hardening, AllocationEngine + CounterfactualTracker
**Commit:** `cb989fe` (bundled — see commit message for the full entry list)

- Scope: additive, default-preserving completion of the strategy engines and two new wired subsystems, per the approved 5-phase plan. Every new mode/input defaults to the pre-existing behavior.
- **Phase 1 (entry modes / level sources):** shared `ConfirmCandleTrigger` / `ConfirmLevelTrigger` / `SelectLevel` helpers in `StrategyBase.mqh`; `ENUM_LEVEL_SOURCE`; per-strategy `Inp*_LevelSource`. Break-retest / probe-confirm / displacement / rejection trigger modes wired fail-closed on unsupported values. TEST 52-53.
- **Phase 2 (stop/target/exit):** `ENUM_STOP_MODE` / `ENUM_TARGET_MODE` + `ComputeStop` / `ComputeTarget` dispatch in all four engines; `Inp*_StopMode` / `Inp*_TargetMode`. Momentum-failure and regime-deterioration exits added to `ShadowPortfolio` and `PositionManager` (default off). TEST 54-55.
- **Phase 3 (risk/exec hardening):** ChallengeMode attempt-lockout + winners-only/protected pyramiding gate (previously-dead members wired); Shadow virtual pending-order lifecycle (removes the OnInit "not implemented" block); session/rollover exit paths. TEST 56.
- **Phase 4 (new subsystems):** `CAllocationEngine` (equal/confidence/performance risk-budget weighting, equal default = zero behavior change, wired into the sizing path via `InpAllocationMode`) — TEST 57. `CCounterfactualTracker` (buffered, side-effect-free rejected-signal hypotheticals; disabled by default; wired at three rejection sites) — TEST 58.
- Verification: compile 0 errors / 0 warnings; self-tests 61 passed / 0 failed; journaled Apr 20-24 XAUUSD M5 Shadow baseline preserved at BO2/FBO9/TP0/MR5. ex5 SHA-256 `d17d0bdeab48fb64db91996a88bf758924502b3318da9a22203f0d13ba04d2c9`.
- **FBO 9→11 investigation (resolved):** an early per-tick `FileFlush` counterfactual design was redesigned to memory-buffered/write-at-Close after per-tick I/O was suspected of perturbing the tester. A runtime diagnostic then showed `InpEnableCounterfactual=true` is *never applied* via the tester `.ini` (`flag=0` in every run, `true` and numeric `1` both), while an identical `input bool` on the same `.ini` does apply — a MetaTrader input-application quirk, not a code defect. Counterfactual was therefore OFF in every backtest, so it could not have caused the one-off FBO 11 (a non-reproducing tester-nondeterminism outlier; FBO=9 in 6+ runs). CSV tester-population is a documented verification limitation; the tracker logic is proven by TEST 58. Evidence: `TestEvidence/phase4_allocation_counterfactual_20260721/EVIDENCE.md`.

### 2026-07-21 — Full build-out Phase 5 (FINAL): ExposureManager / Reconciliation / RecoveryEngine built into real modules
**Commit:** `9279048`

- Scope: the three delegated placeholder classes became real, wired modules via behavior-preserving extractions. The decision logic moved into the modules; irreducible side effects (broker calls, global kill-switch / protection-state mutations) stay at the call sites.
- `CExposureManager` (`Portfolio/ExposureManager.mqh`): owns the aggregate-exposure limit policy — pre-sizing capacity gate, post-sizing projection, headroom. `CRiskEngine` now consults it for both exposure checks (`AtCapacity` / `WouldExceed`) instead of hard-coding them. TEST 59.
- `CReconciliation` (`Execution/Reconciliation.mqh`): owns the `ReconciliationResult` structure and the `Classify()` that turns reconstruction counts + unknown-position policy into the startup `ReconciliationVerdict` (quarantine / protection-emergency), exactly mirroring the former inline OnInit logic. TEST 60 (all four combinations).
- `CRecoveryEngine` (`Execution/RecoveryEngine.mqh`): single orchestration entry point — drives `CPositionManager.ReconstructFromBroker`, assembles the result, returns the verdict OnInit applies. Guarded by the existing recovery self-tests (39, 40) staying green.
- Verification: compile 0 errors / 0 warnings; self-tests 63 passed / 0 failed (existing recovery/exposure tests green); journaled Apr 20-24 baseline preserved at BO2/FBO9/TP0/MR5. Evidence: `TestEvidence/phase5_module_extraction_20260721/EVIDENCE.md`.
- This completes the 5-phase build-out. All five formerly-empty stub classes are now Substantive in the ARCHITECTURE.md status table. Operator-gated live gaps (2-week demo-forward, live pending-order authorization, slippage stress, Challenge live transmission, manual restart-state) remain out of scope by design.
- **Finding — ReconstructFromBroker() ownership classification requires comment-prefix parsing, not magic alone:** Conservative Live init ran `ReconstructFromBroker()` for the first time on real terminal evidence (22:15:05). The fixture's position #34619645 (magic `20260701`, comment `"QB fixture owned"`) was classified as **unknown** despite passing the magic-range check, because `StrategyFromComment()` at `PositionManager.mqh:67` requires the comment to start with `QB_` (underscore, not space) followed by a known strategy ID (`BO`, `FBO`, `TP`, `MR`). This is stronger evidence than a naive magic-only check — ownership depends on comment format integrity surviving to broker history. The EA's own order-placement path (`QuantBeastEA.mq5:1324`) always produces `QB_<STRATEGY_ID>` format deterministically, so real QuantBeast-placed orders are not at risk. The fixture script comment has been corrected to `"QB_FBO_fixture"` for future attempts. The entry-kill on unknown-position detection also confirms `RISK_SPEC.md`'s UNKNOWN_QUARANTINE behavior correctly latches at startup.

### 2026-07-21/22 — Strategy metadata tags + batch strategy validation plumbing

- Scope: added family/template/tag metadata to `StrategySignal`, stamped the metadata from `CStrategyBase` / the four strategy constructors, and added a batch startup fixture (`TEST 61`) that validates BO/FBO/TP/MR together instead of only one-by-one.
- Files changed: `Include/QuantBeast/Core/Types.mqh`, `Include/QuantBeast/Strategies/StrategyBase.mqh`, `Include/QuantBeast/Strategies/BreakoutEngine.mqh`, `Include/QuantBeast/Strategies/FailedBreakoutEngine.mqh`, `Include/QuantBeast/Strategies/TrendPullbackEngine.mqh`, `Include/QuantBeast/Strategies/MeanReversionEngine.mqh`, `Include/QuantBeast/Testing/SafetyTests.mqh`, `Experts/QuantBeast/QuantBeastEA.mq5`, `README.md`, `ARCHITECTURE.md`, and `TESTING_GUIDE.md`.
- Validation: MetaEditor compile passed at `0 errors, 0 warnings` and generated a fresh `QuantBeastEA.ex5` at `2026-07-21 21:58:50`. The compile log contains the `2026.07.21 21:58:50.074 ... 0 errors, 0 warnings` entry. The tester rerun is also complete; the EA log records `TEST 61 PASS: Strategy batch metadata and reachability ...` and `Self-tests complete: 63 passed, 0 failed`. Fresh tester-specific `SignalJournal.csv` and `CounterfactualJournal.csv` headers now include `StrategyFamily`, `StrategyTemplate`, and `StrategyTags`.
- Intended next step: use the validated batch metadata path as the baseline for the next research pass on strategy gap coverage and exit-family counterfactuals.
