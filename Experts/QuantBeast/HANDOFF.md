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
- `Include/QuantBeast/Execution/ShadowPortfolio.mqh` implements the broker-free virtual market-position lifecycle.
- Four strategy classes contain long and short source logic.
- Four `.set` presets are present.
- All nine originally required Markdown documents are present.
- `PROJECT_MISSION_AND_AUDIT_CONTEXT.md` is present as the mandatory mission/audit preface.
- `Include/QuantBeast/Testing/SafetyTests.mqh` contains deterministic startup fixtures.
- `QuantBeastEA.ex5` is present and the final MetaEditor build is `0 errors, 0 warnings`.
- The original 23-error/15-warning baseline is preserved under `TestEvidence/compile_20260715/`.
- The Shadow lifecycle build/runtime evidence is under `TestEvidence/shadow_lifecycle_20260715/`.
- Strategy Tester agent logs prove Shadow initialization and 43 passed/0 failed tests, including direction-preserving strategy rejections, regime/arbitration policy, protection repair/emergency, server-response, cancel/fill-race, kill-switch, fail-closed Challenge policies, final-decision signal writer behavior, performance updates with file journaling disabled, live-mode strategy/execution gates, state symbol scoping, live recovery no-passive-flatten gating, unknown-position no-adoption behavior, and alert-routing policy. The tester MCP still returns `job_id: 0`; local agent logs and file timestamps are authoritative.
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

1. Shadow pending-order activation/expiry is unsupported; pending intents are rejected.
2. Core Shadow market-position branches have deterministic runtime evidence; strategy-generated lifecycle sequences remain unproven.
3. Pending broker orders are cancelled fail-closed on restart rather than restored.
4. Recovered positions cannot always restore signal/regime/MFE/MAE/exact management state.
5. Strategy semantic gaps remain: BO local compression threshold, FBO target variants, TP pullback age, MR opposite-band target.
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

### Disconnected partial

- `UI/Alerts.mqh`

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
Final source SHA-256: 2b1dead892b25081d026d63b696776f201f9d2c132e5ea641f2588dcc529685a
Final EX5 SHA-256: bed035a8f6b03fe73defde9fac0dd7e641e4b18b3b7f3e09691bb9b507dceb3b
```

## Test status

```text
Static content audit: completed
Focused bug audit: completed — BUG_AUDIT.md
Compile test: passed after repair — 0 errors, 0 warnings
Deterministic startup fixtures: runtime pass — 43 passed, 0 failed
Shadow attachment: completed per local tester agent log; MCP status remained unreliable
Shadow lifecycle tests: all core market-position branches passed; no broker orders/deals; tester balance unchanged
Strategy Tester baseline: not yet valid as performance evidence
Restart/recovery: version quarantine and risk-state restore contracts proven; two-process tester probe fails because tester globals reset/isolate; real terminal/broker restart scenarios missing
Demo forward: prohibited until earlier gates pass
Live: prohibited
```

## Next task

1. Run controlled demo/fault-adapter scenarios for actual modify/close/delete rejection, requotes, disconnect/reconnect, and fill-during-cancel callback ordering. The deterministic policies are covered; actual broker behavior is not.
2. Run an actual normal-terminal restart fixture with owned positions, pending orders, unknown positions, and incompatible/corrupt state. Do not reuse Strategy Tester global persistence as a substitute and do not optimize profitability yet.
3. Repeat organic BO/FBO/TP/MR and full Shadow lifecycle coverage on true real ticks when history is available; inspect post-repair CSV status/ID rows.
4. Decide whether to implement Shadow pending orders or keep the explicit rejection as a documented design limit; production live modes are currently market-order-only until pending-order broker evidence exists.

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
- No broker runtime evidence yet exists for fill protection, actual transaction callback ordering, or real terminal/broker restart recovery; deterministic state transitions only are proven.

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
- Shadow pending intents are rejected explicitly; no incomplete stop/limit simulation is implied.
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
