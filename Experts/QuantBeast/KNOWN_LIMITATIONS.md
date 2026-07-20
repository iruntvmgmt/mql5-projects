# QuantBeast Known Limitations

**Status date:** 2026-07-20  
**Current readiness:** `READY FOR SHADOW MODE` for broker-free mechanical research only. Live and Challenge operation prohibited.

## Runtime and testing

- The final source compiles at `0 errors, 0 warnings`, but compilation is not runtime proof.
- The native MT5 tester API still returns the invalid/ambiguous identifier `job_id: 0` and reports `tester stopped`; local agent logs must be inspected to confirm completion.
- A Shadow fixture completed with 52 startup tests passed and 0 failed, including rejected-direction, regime, all arbitration enum modes, broker-fault, centralized protection-close, final-decision signal-writer, performance-without-file-journal, live-mode gate, live broker-transmission acknowledgement gate, recovery, alert, preflight, session-exit, self-test detail-control, chart-object toggle, fill/reconciliation alert-category, strategy-counter restore, arbitration persistence, and Shadow pending-order lifecycle policies. Latest boundary/regression proof is under `TestEvidence/current_regression_20260716/`, with follow-on wiring proof under `TestEvidence/bo_compression_pct_20260716/`, `TestEvidence/tp_pullback_age_20260716/`, `TestEvidence/mr_target_band_20260716/`, `TestEvidence/fbo_target_variants_20260716/`, and `TestEvidence/shadow_pending_lifecycle_20260718/`.
- Organic true-tick Shadow evidence reached FBO accepted BUY/SELL entries and BO/FBO/TP/MR BUY/SELL rejections through feature, regime, strategy, arbitration, and central risk. A combined true-tick training baseline completed, the first holdout attempt was invalid/incomplete, a clean holdout retry completed normally, and independent BO/FBO/TP/MR train and holdout baselines completed. Only FBO reached accepted trade state in those baseline windows. As of 2026-07-19, 6 distinct organic windows (2 isolated single-strategy, 4 combined, spanning Feb-Jul 2026 in visibly different volatility/trend regimes) have now been tested and BO/TP/MR have never reached ACCEPTED; 88-100% of their rejections are the generic eligibility-gate failure in every window, indicating this is unlikely to be a window-selection artifact. See `TestEvidence/organic_multiwindow_20260719/EVIDENCE.md`. Whether the eligibility gates are miscalibrated or correctly modeling genuinely rare conditions is unresolved and requires a dedicated strategy-parameter review, not further window coverage. Broader holdouts, stress, normal-terminal restart, live-path fault-injection, and demo-forward results remain unproven.
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

- Pending-order lifecycle simulation (place, fill/cancel, stop) is now implemented in the Shadow layer with deterministic test coverage. Broker-side restart recovery is now implemented and proven as of 2026-07-20 (see `TestEvidence/pending_order_reconstruction_20260720/EVIDENCE.md`, which also organically demonstrated the expiry-deletion path). Live activation, cancellation, fill-during-cancel race, and organic market-fill behavior for ordinary (non-restart) pending-order trading remain unproven; the live-mode gate (`QBLiveExecutionSetAllowed()`) still blocks pending orders entirely until that evidence exists.
- Session-close and rollover-close policy has deterministic Shadow coverage under `TestEvidence/session_exit_policy_20260716/`; live broker flatten behavior remains unproven and requires explicit authorization before use.
- Virtual positions are intentionally not persisted across terminal restart.
- Swap is recorded as zero; overnight financing is not modeled.
- Commission is a configured per-lot estimate rather than broker-history truth.
- Core market-position Shadow branches and direct strategy-class signal paths now have deterministic evidence. Organic true-tick evidence reached accepted FBO BUY/SELL entries and completed FBO trade rows; broader accepted BO/TP/MR lifecycle sequences and long-run accounting still need validation.
- Strategy performance remains unvalidated. The completed combined training baseline, clean holdout retry, and per-strategy train/holdout runs are observational only, not proof of edge. Direct class reachability and Shadow results must not be treated as evidence of an edge.

## Recovery and persistence

- Open broker positions recover strategy ownership, entry order, original stop/target, and initial volume where broker history permits. CLOSED 2026-07-20: reconstructed positions are now verified for an actual protective stop (`EnsurePositionProtection()`, same contract as live fills), escalating to `ActivateProtectionEmergency()` if none is found -- previously a reconstructed position with no stop loss was silently accepted as protected. Proven against a real terminal restart with a deliberately unprotected fixture position; see `TestEvidence/protection_verification_reconstruction_20260720/EVIDENCE.md`.
- Signal ID, original regime, MFE/MAE, exact partial count, and management state may not be fully recoverable.
- CLOSED 2026-07-20: owned pending orders are now reconstructed from live broker state at startup (mirroring `ReconstructFromBroker()` for positions; no new persisted schema) when exactly one is found and its comment resolves to a known strategy. Proven against a real terminal restart, see `TestEvidence/pending_order_reconstruction_20260720/EVIDENCE.md`. Cancellation fail-closed is preserved only for the unresolvable-comment and more-than-one-found cases (the in-memory model tracks only one pending order at a time). `request_id` uses the order ticket as a stable substitute for the original (non-recoverable) local id, the same accepted gap as `PositionContext.signal_id`.
- Incompatible nonzero state versions are quarantined fail-closed: entries are latched off and stale state is not overwritten or loaded. There is no automatic migration workflow; operator review/reset is required.
- CLOSED 2026-07-20: the version-policy and risk-state restore contracts had deterministic tests only until this date. A real terminal restart with an owned position, a pending order, an unknown position, and a corrupted state version was executed in `QB_MODE_CONSERVATIVE_LIVE` (the 2026-07-16 attempt was invalidated because it ran in `QB_MODE_SHADOW`, which never reaches `ReconstructFromBroker()`). All 4 scenarios passed: owned-position strategy/entry/stop recovery, fail-closed pending-order cancellation, unknown-position non-adoption, and fail-closed state-version quarantine. See `TestEvidence/restart_recovery_20260719/EVIDENCE.md`. Remaining gaps: durable signal ID beyond the journal string, exact partial-exit/scale-in count, and full position-management context (trailing state, management-branch history) still do not survive restart -- only original entry/stop/target and strategy ownership do.
- Persistence currently uses Terminal Global Variables only; `InpUseGlobalVars=false` disables it. Production saves now call `GlobalVariablesFlush()` explicitly, and state keys are scoped by account login plus effective adapter symbol rather than chart symbol.
- A two-process Strategy Tester probe lost all probe globals after the tester/Wine process tree was replaced. Strategy Tester agent globals are isolated/reset in this environment, so this cannot validate or invalidate persistence in the normal live terminal.
- Strategy daily counts are persisted and restored only for the same broker day. Arbitration cooldown and duplicate memory are persisted as bounded timestamp/hash state and restore only while fresh; real-restart evidence for this specific state has not been gathered. CLOSED 2026-07-20 for daily/weekly start equity and HWM: proven against a real terminal restart using deliberately distinguishable injected values, then explicitly restored to the real captured baseline (`TestEvidence/risk_state_restart_20260720/EVIDENCE.md`). Daily/weekly/drawdown lock booleans and consecutive-loss count share the identical load path but were not independently re-verified. Challenge-stage persistence needs separate Challenge Live authorization and remains unproven against a real restart. Full position-management context and virtual positions remain unproven.
- Manual/MCP demo broker orders were opened and closed successfully, but QuantBeast EA-autonomous demo execution is still unproven. Live modes now require explicit `InpAcknowledgeLiveBrokerRisk=true` in addition to the existing live gates, with current fail-closed tester evidence under `TestEvidence/conservative_live_tester_fbo_20260716/` and demo lifecycle evidence under `TestEvidence/demo_broker_lifecycle_20260716/`.
- A broker-free Conservative Live Strategy Tester attempt could not reach order-routing because the native tester did not apply/expose `InpAcknowledgeLiveBrokerRisk=true` through inline, `.set`, or plain `[TesterInputs]` overrides. The EA failed closed at initialization, which is correct safety behavior, but EA-autonomous Conservative Live tester execution remains unproven.
- Unknown ownership applies `InpUnknownPosPolicy`; runtime behavior proven 2026-07-20 for `UNKNOWN_REPORT` against a real restart (see `TestEvidence/restart_recovery_20260719/EVIDENCE.md`). `UNKNOWN_QUARANTINE`'s additional `KillEntries()` call remains unit-tested only, not yet proven against a real restart.

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

- Deterministic transaction, protective-stop repair/emergency, API/server-acknowledgement, modify/close/delete response, pending-retirement, cancel/fill-race, consecutive-rejection counting, disconnect-priority, and emergency-dispatch policies pass. Protection failure has one immediate close owner and retains bounded flatten retries. As of 2026-07-20, requotes and modify/close/delete rejection are confirmed structurally blocked on this broker (XAUUSD has `Stop Level (pts) = 0` and `Freeze Level (pts) = 0`, market execution, every order fills immediately at retcode 10009) -- deterministic unit coverage remains the only valid evidence for these. Disconnect/reconnect was tested against a real ~0.64s outage and revealed that connectivity is only checked inside `OnTick()`, not `OnTimer()`, so a short or unluckily-timed outage may never be observed by that kill parameter (see `TestEvidence/fault_adapter_20260720/EVIDENCE.md`). Fill-during-cancel race, timer-driven broker retries, and actual rejection streaks remain unproven against real broker behavior.
- CLOSED 2026-07-20: `OnTradeTransaction()`'s live entry-handling comment parsing previously did not match `PositionManager.mqh`'s `StrategyFromComment()` (used by restart's `ReconstructFromBroker()`), so a comment like `QB_FBO_fixture` could resolve to an unrecognized strategy id via a live fill but correctly to `FBO` via restart. Fixed by extracting a single shared `QBStrategyIdFromComment()` function used by both paths, with new deterministic coverage (TEST 50). See `TestEvidence/comment_parsing_fix_20260720/EVIDENCE.md`.
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
2. Prove accepted BO/TP/MR organic feature/regime-to-strategy reachability without lookahead on true real ticks; FBO accepted BUY/SELL has multi-window true-tick Shadow evidence. BO/TP/MR remain unreached across 6 distinct windows as of 2026-07-19; closing this blocker now requires a dedicated eligibility-gate/parameter review rather than additional window coverage.
3. Expand realistic-cost tester baselines, additional holdouts, and stress tests without optimizing against holdout data.
4. Complete broker-specific demo validation before considering micro-live.
