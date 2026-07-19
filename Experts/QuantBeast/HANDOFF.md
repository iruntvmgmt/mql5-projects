# QuantBeast Handoff

**Last updated:** 2026-07-16  
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


## Next task

1. Run controlled demo/fault-adapter scenarios for actual modify/close/delete rejection, requotes, disconnect/reconnect, and fill-during-cancel callback ordering. The deterministic policies are covered; actual broker behavior is not.
2. Run an actual normal-terminal restart fixture with owned positions, pending orders, unknown positions, and incompatible/corrupt state. Do not reuse Strategy Tester global persistence as a substitute and do not optimize profitability yet.
3. Organic true-tick CSV evidence captured 2026-07-19 (see `TestEvidence/organic_true_ticks_20260718/`): 7 FBO accepted entries across a 5-day window, BO/TP/MR rejected only. REMAINING: BO/TP/MR organic accepted entries remain unproven (strategies too selective for this window); broader multi-window coverage or strategy-parameter review may be needed.
4. Implement broker-side live pending-order lifecycle and recovery (Shadow layer completed 2026-07-18 with deterministic test evidence; see `TestEvidence/shadow_pending_lifecycle_20260718/`). Production live modes remain market-order-only until pending-order broker evidence exists; the Shadow pending-order test fixture provides the simulation baseline.

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
- **⚠ Journal file-lock collision (2026-07-19)** — The live terminal on Coinexx-Demo holds write locks on the Common/Files/QuantBeast CSV journals. Any tester run with journals enabled hits error 5004 (`FILE_CANNOT_OPEN`). **FIX IMPLEMENTED** (4-file change, compiles 0/0): new `InpJournalTesterPrefix` input routes tester journals to `QuantBeast\Tester\` subdirectory. **Operational blocker remains**: the MT5 terminal caches the old .ex5; it must be restarted to pick up the new build, then re-run the organic true-tick backtest with `InpJournalTesterPrefix=true`. See HANDOFF worklog 2026-07-19.

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
- **Finding — ReconstructFromBroker() ownership classification requires comment-prefix parsing, not magic alone:** Conservative Live init ran `ReconstructFromBroker()` for the first time on real terminal evidence (22:15:05). The fixture's position #34619645 (magic `20260701`, comment `"QB fixture owned"`) was classified as **unknown** despite passing the magic-range check, because `StrategyFromComment()` at `PositionManager.mqh:67` requires the comment to start with `QB_` (underscore, not space) followed by a known strategy ID (`BO`, `FBO`, `TP`, `MR`). This is stronger evidence than a naive magic-only check — ownership depends on comment format integrity surviving to broker history. The EA's own order-placement path (`QuantBeastEA.mq5:1324`) always produces `QB_<STRATEGY_ID>` format deterministically, so real QuantBeast-placed orders are not at risk. The fixture script comment has been corrected to `"QB_FBO_fixture"` for future attempts. The entry-kill on unknown-position detection also confirms `RISK_SPEC.md`'s UNKNOWN_QUARANTINE behavior correctly latches at startup.