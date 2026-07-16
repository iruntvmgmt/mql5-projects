# QuantBeast Known Limitations

**Status date:** 2026-07-16  
**Current readiness:** `READY FOR SHADOW MODE` for broker-free mechanical research only. Live and Challenge operation prohibited.

## Runtime and testing

- The final source compiles at `0 errors, 0 warnings`, but compilation is not runtime proof.
- The native MT5 tester API still returns the invalid/ambiguous identifier `job_id: 0` and reports `tester stopped`; local agent logs must be inspected to confirm completion.
- A Shadow fixture completed with 51 startup tests passed and 0 failed, including rejected-direction, regime, all arbitration enum modes, broker-fault, centralized protection-close, final-decision signal-writer, performance-without-file-journal, live-mode gate, live broker-transmission acknowledgement gate, recovery, alert, preflight, session-exit, self-test detail-control, chart-object toggle, fill/reconciliation alert-category, strategy-counter restore, and arbitration persistence policies. Latest boundary/regression proof is under `TestEvidence/current_regression_20260716/`, with follow-on wiring proof under `TestEvidence/bo_compression_pct_20260716/`, `TestEvidence/tp_pullback_age_20260716/`, `TestEvidence/mr_target_band_20260716/`, and `TestEvidence/fbo_target_variants_20260716/`.
- Organic true-tick Shadow evidence reached FBO accepted BUY/SELL entries and BO/FBO/TP/MR BUY/SELL rejections through feature, regime, strategy, arbitration, and central risk. A combined true-tick training baseline completed, the first holdout attempt was invalid/incomplete, a clean holdout retry completed normally, and independent BO/FBO/TP/MR train and holdout baselines completed. Only FBO reached accepted trade state in those baseline windows. BO/TP/MR accepted organic entries, broader holdouts, stress, normal-terminal restart, live-path fault-injection, and demo-forward results remain unproven.
- Conservative Live and acknowledged Challenge Live are currently gated to FBO-only, market-order-only initialization with pending orders disabled. This is intentional safety debt: BO, TP, MR, and pending orders remain research-only for broker transmission until accepted-entry, lifecycle, pending-order, and restart evidence exists.
- No profitability claim is supported.

## Shadow mode

Shadow mode now maintains market-entry virtual positions through:

- bid/ask fills and costs;
- stop and target hits;
- partial exits;
- breakeven or trailing;
- time exits;
- MFE/MAE;
- hypothetical equity, drawdown, or risk locks.

Remaining Shadow limitations:

- Pending-order intents are rejected; stop/limit activation and expiry are not simulated.
- Session-close and rollover-close policy has deterministic Shadow coverage under `TestEvidence/session_exit_policy_20260716/`; live broker flatten behavior remains unproven and requires explicit authorization before use.
- Virtual positions are intentionally not persisted across terminal restart.
- Swap is recorded as zero; overnight financing is not modeled.
- Commission is a configured per-lot estimate rather than broker-history truth.
- Core market-position Shadow branches and direct strategy-class signal paths now have deterministic evidence. Organic true-tick evidence reached accepted FBO BUY/SELL entries and completed FBO trade rows; broader accepted BO/TP/MR lifecycle sequences and long-run accounting still need validation.
- Strategy performance remains unvalidated. The completed combined training baseline, clean holdout retry, and per-strategy train/holdout runs are observational only, not proof of edge. Direct class reachability and Shadow results must not be treated as evidence of an edge.

## Recovery and persistence

- Open broker positions recover strategy ownership, entry order, original stop/target, and initial volume where broker history permits.
- Signal ID, original regime, MFE/MAE, exact partial count, and management state may not be fully recoverable.
- Owned pending orders are cancelled fail-closed at startup; they are not restored.
- Incompatible nonzero state versions are quarantined fail-closed: entries are latched off and stale state is not overwritten or loaded. There is no automatic migration workflow; operator review/reset is required.
- The version-policy and risk-state restore contracts have deterministic tests, but a real terminal/VPS restart with broker positions or pending orders has not been executed as evidence.
- Persistence currently uses Terminal Global Variables only; `InpUseGlobalVars=false` disables it. Production saves now call `GlobalVariablesFlush()` explicitly, and state keys are scoped by account login plus effective adapter symbol rather than chart symbol.
- A two-process Strategy Tester probe lost all probe globals after the tester/Wine process tree was replaced. Strategy Tester agent globals are isolated/reset in this environment, so this cannot validate or invalidate persistence in the normal live terminal.
- Strategy daily counts are persisted and restored only for the same broker day. Arbitration cooldown and duplicate memory are persisted as bounded timestamp/hash state and restore only while fresh. Full position-management context, virtual positions, and live broker restart reconciliation remain unproven.
- Manual/MCP demo broker orders were opened and closed successfully, but QuantBeast EA-autonomous demo execution is still unproven. Live modes now require explicit `InpAcknowledgeLiveBrokerRisk=true` in addition to the existing live gates, with current fail-closed tester evidence under `TestEvidence/conservative_live_tester_fbo_20260716/` and demo lifecycle evidence under `TestEvidence/demo_broker_lifecycle_20260716/`.
- A broker-free Conservative Live Strategy Tester attempt could not reach order-routing because the native tester did not apply/expose `InpAcknowledgeLiveBrokerRisk=true` through inline, `.set`, or plain `[TesterInputs]` overrides. The EA failed closed at initialization, which is correct safety behavior, but EA-autonomous Conservative Live tester execution remains unproven.
- Unknown ownership applies `InpUnknownPosPolicy`; runtime behavior still needs scenario proof.

## Strategy semantics still incomplete

- Trigger implementations are intentionally simple closed-candle/displacement confirmations; direct class reachability is proven, but organic market-feature reachability still requires testing.
- Fixed confidence and spread sub-gates may make strategies too restrictive or permissive; this is unmeasured.

## Challenge mode

- Deposits and withdrawals are classified as external cash flows and fail closed in the deterministic policy test; actual broker cash-flow events and restart cursor recovery remain unproven.
- Stage-attempt reset semantics are incomplete.
- Profit-lock and pyramiding behavior have not been proven against every open-equity/restart scenario.
- Challenge risk remains subordinate to central hard risk by design.
- Challenge Mode is research-only and must not be enabled live.

## Execution and broker portability

- Deterministic transaction, protective-stop repair/emergency, API/server-acknowledgement, modify/close/delete response, pending-retirement, cancel/fill-race, consecutive-rejection counting, disconnect-priority, and emergency-dispatch policies pass. Protection failure has one immediate close owner and retains bounded flatten retries. No captured broker runtime evidence yet proves actual callback ordering, filling-mode behavior, requotes, freeze levels, stop repair, cancel rejection/fill races, fail-safe close failure, timer-driven broker retries, actual rejection streaks, or real reconnect behavior on this broker.
- Per-strategy magic constants exist, but current orders use a common owned magic range plus short strategy comments.
- Fixed local capacity is 20 tracked positions.
- Live operation is explicitly hedge-account-only. Netting/exchange accounts fail initialization until `DEAL_ENTRY_INOUT` reversal reconciliation is implemented and tested.
- Close-before-session and close-before-rollover controls now have deterministic policy coverage, but real broker live flatten behavior remains unverified.
- `InpMaxHoldingMinutes` and `InpMaxPendingMinutes` are not the authoritative management/expiry inputs in all paths.
- Persistence schema v4 includes the consecutive broker-submission failure streak. Older nonzero schemas quarantine entries fail-closed; no automatic migration exists.

## Data, sessions, and events

- XAUUSD tick volume is only an OTC activity proxy.
- No COMEX futures confirmation exists.
- News lockout uses manual broker-time timestamps; there is no automated economic calendar feed.
- Session inputs are interpreted as broker-server times. Stored UTC/DST settings do not automatically convert them.
- FeatureEngine still performs some direct historical reads in addition to BarCache.
- Broker-history availability limits recovery fidelity.

## Analytics and UI

- Performance metrics include tracked manual exit deals by stable position identifier, but broker-side runtime validation is still absent.
- No per-strategy/direction/session/regime report exists.
- Final strategy/arbitration/risk decision routing is implemented and deterministically tested, rejected signals preserve BUY/SELL direction, and signal IDs include direction. File-level proof from a completed organic post-repair true-tick run is under `TestEvidence/organic_true_ticks_20260716/`. The shared historical journal intentionally retains pre-repair rows and a pre-fix corrupted prefix; only byte-bounded suffixes should be treated as current evidence.
- Counterfactual tracking remains a stub.
- `UI/Alerts.mqh` now fail-closes push delivery on `SendNotification()` failure and the EA wrapper now latches entries closed when an enabled configured alert cannot be delivered. This source-level propagation still requires a fresh compile and Shadow fixture rerun; current evidence is under `TestEvidence/alert_failclosed_20260716/`. Push delivery itself has been operator-verified through the MT5 app, but end-to-end EA alert behavior remains unproven outside Strategy Tester.
- Dashboard values have not been verified against broker state in runtime.

## Architectural stubs

These files are intentionally non-operational placeholders and must not be described as implemented systems:

- `Portfolio/AllocationEngine.mqh`
- `Portfolio/ExposureManager.mqh`
- `Execution/Reconciliation.mqh`
- `Execution/RecoveryEngine.mqh`
- `Analytics/CounterfactualTracker.mqh`

Active reconciliation and recovery logic currently lives in `QuantBeastEA.mq5`, `BrokerAdapter.mqh`, and `PositionManager.mqh`.

## Promotion blockers

Before promotion beyond Diagnostic Mode:

1. Run deterministic live-path sizing, stop, transaction, duplicate, restart, unknown-position, pending-order, and protection-failure scenarios.
2. Prove accepted BO/TP/MR organic feature/regime-to-strategy reachability without lookahead on true real ticks; FBO accepted BUY/SELL has one-day true-tick Shadow evidence.
3. Expand realistic-cost tester baselines, additional holdouts, and stress tests without optimizing against holdout data.
4. Complete broker-specific demo validation before considering micro-live.
