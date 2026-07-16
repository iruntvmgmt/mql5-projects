# QuantBeast Repair Audit — 2026-07-15

## Executive verdict

**CONDITIONAL PASS — READY FOR SHADOW MODE (BROKER-FREE RESEARCH ONLY)**

The original audit correctly failed the generated project at 23 errors and 15 warnings. The repaired source now compiles to `QuantBeastEA.ex5` with **0 errors and 0 warnings**. The repair removed the confirmed compile blockers and corrected multiple critical safety, accounting, indexing, execution, recovery, and strategy-unit defects.

This is not a profitability verdict. The latest Shadow Strategy Tester fixture completed with **51 startup checks passed and 0 failed**, including direction-preserving rejected signals, regime/arbitration policies, arbitration persistence, a deterministic broker-fault matrix, centralized protection-close ownership, final-decision signal-writer proof, performance updates when file trade journaling is disabled, live-mode strategy/execution gates, live broker-transmission acknowledgement gating, state symbol scoping, live recovery no-passive-flatten gating, unknown-position no-adoption behavior, alert-routing behavior, entry preflight controls, session/rollover exit policy, self-test detail logging control, chart-object toggle policy, fill/reconciliation alert categories, and strategy-counter same-day restore policy. Local agent logs are authoritative. The EA is not cleared for Conservative Live or Challenge modes.

## Final evidence

- Source: `QuantBeastEA.mq5`
- Source SHA-256: `8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49`
- EX5 SHA-256: `e64f3f8ce8b201b7614d13c3a6ea4129677883657c01af4528a35735f4e6f859`
- Shadow module SHA-256: `05885359c865d3c56d738a7ededcd13a49b46b3c8d74dc07c7d040ebece560bb`
- Compiler: MetaEditor build 6002, X64 Regular
- Compile result: `0 errors, 0 warnings`
- Runtime result: deterministic `51 passed, 0 failed`; organic true-tick Shadow run `417423 ticks`, `276 bars`; tester balance unchanged at `10000.00`
- Evidence: prior folders plus `TestEvidence/broker_fault_matrix_20260715/`, `TestEvidence/organic_pipeline_20260715/`, `TestEvidence/arbitration_journal_20260715/`, `TestEvidence/audit_final_20260716/`, `TestEvidence/organic_true_ticks_20260716/`, `TestEvidence/performance_readiness_20260716/`, `TestEvidence/live_strategy_gate_20260716/`, `TestEvidence/selftest_detail_control_20260716/`, `TestEvidence/chart_object_toggle_20260716/`, `TestEvidence/alert_category_routing_20260716/`, `TestEvidence/preset_gate_alignment_20260716/`, `TestEvidence/arbitration_modes_20260716/`, `TestEvidence/strategy_counter_persistence_20260716/`, `TestEvidence/arbitration_persistence_20260716/`, `TestEvidence/demo_broker_lifecycle_20260716/`, `TestEvidence/live_broker_ack_gate_20260716/`, `TestEvidence/current_regression_20260716/`, `TestEvidence/bo_compression_pct_20260716/`, `TestEvidence/tp_pullback_age_20260716/`, and `FINAL_ADVERSARIAL_AUDIT_20260716.md`

## Critical repairs completed

1. **Compilation and type system**
   - Removed collisions with MQL5 order-state identifiers.
   - Centralized lot-mode enums and added the missing MR trigger input.
   - Corrected array-reference, const, account, symbol, pointer, and conversion errors.

2. **Closed-bar and multi-timeframe validity**
   - Corrected BarCache array functions to return copied counts rather than booleans.
   - Added explicit closed-bar retrieval and consistent shift-1 feature calculation.
   - Reversed newest-first regression orientation so rising markets produce positive slopes.
   - Excluded the breakout trigger bar from prior range boundaries.
   - Replaced rolling placeholders for session/opening/previous-day levels with closed-bar session/day calculations.

3. **Structural features and strategy reachability**
   - Populated directional failed-auction, reclaim, penetration, sweep, displacement, and structural fields.
   - Added directional HTF slope and side-specific BO checks.
   - Corrected BO, FBO, TP, and MR executable entry quotes to bid/ask where appropriate.
   - Added real weighted VWAP standard deviation and directional upper/lower wick features.
   - Wired TP and MR trigger-mode inputs into their entry logic.

4. **Broker-aware sizing and hard risk**
   - Replaced point/tick-value approximations with `OrderCalcProfit()` loss estimation.
   - Included estimated commission and slippage in risk.
   - Rejects unaffordable sub-minimum volume instead of forcing broker minimum.
   - Floors risk-constrained lot sizes to broker step and supports 0.001 steps.
   - Revalidates actual sized risk and proposed total exposure.
   - Centrally rejects inverted stop/target geometry and broker-invalid volume, stop, or target distance.

5. **Execution and protection**
   - Requires successful server retcodes and reconciles deals to stable position identifiers.
   - Verifies broker-side SL/TP after market fills; attempts one repair and closes fail-closed if protection cannot be proven.
   - Limits retries to known no-fill price conditions and revalidates market state before retry.
   - Enforces order-class and filling-mode permissions.
   - Prevents duplicate pending submissions while one local pending lifecycle is tracked.
   - Requires the raw API boolean and order-class-specific server retcode to agree before returning submission success; rejected acknowledgements cannot create phantom local order state.
   - Retains pending tracking and cancel-all intent when expiry deletion fails, history is unavailable, or a fill cannot be safely reconciled; only confirmed terminal state or a protected registered fill retires it.
   - Broker stop modifications now reject wrong-side, freeze/stop-invalid, and risk-loosening changes.

6. **Trade lifecycle and analytics**
   - `OnTradeTransaction()` now resolves owned entries/exits, aggregates all position deals, journals completed trades, updates consecutive losses/HWM, and removes final local context.
   - Journal net PnL now uses signed commission/swap correctly.
   - Performance summary calculates averages, expectancy, average R, streak maxima, and curve drawdown.

7. **Risk-state persistence and kill behavior**
   - Account/symbol-scoped state keys persist period dates, equity baselines, locks, consecutive losses, HWM, challenge state, and kill state.
   - Open equity updates daily, weekly, and HWM/drawdown state every tick.
   - Entry/symbol/strategy kills and central unsafe-regime/session gates are enforced.
   - Existing positions remain managed even when new-entry data quality fails.
   - `InpUseGlobalVars=false` now actually disables Global Variable persistence.
   - Persistent equity-floor, daily/weekly, stop-failure, and repeated-rejection decisions execute before transient disconnection handling, so connectivity loss cannot suppress hard locks.
   - Cancel/flatten work is serviced from tick and timer paths with one shared retry cadence; only explicit live modes may transmit broker actions, and protection emergencies persist immediately.
   - Repeated broker rejection now derives from a persisted consecutive failed-submission-cycle counter instead of a constant false input. Local pre-transmission rejection is excluded, accepted submission resets the streak, and the configurable threshold latches entries fail-closed.
   - Protection verification no longer closes directly before its caller invokes the emergency path. Missing/looser stops follow a deterministic repair-then-emergency policy, and the centralized persistent flatten dispatcher is the sole immediate close owner.

8. **Restart reconciliation**
   - Recovers original order, strategy comment, initial stop/target/volume from broker position history.
   - Does not mistake a moved breakeven/trailing stop for original risk.
   - Applies `InpUnknownPosPolicy`; quarantine activates an entry kill and flatten requests broker closure.
   - Owned pending orders are cancelled fail-closed on restart because their detailed local lifecycle is not yet persisted.

9. **Position management**
   - R remains based on immutable original stop.
   - Breakeven is no longer disabled merely because a partial close happened first.
   - Same-cycle breakeven/trailing uses the updated stop and cannot loosen it.
   - Partial-close volume rounds down and never exceeds the requested fraction.

10. **Configuration and self-tests**
    - Fixed misspelled `InpRiskPercent` keys in both live/challenge example presets.
    - Removed the always-passing feature test.
    - Added deterministic series, bar-order, session-boundary, and broker-risk fixtures.
    - Populates BarCache before startup data-quality validation.

11. **Arbitration and signal-decision integrity**
    - Position-conflict and stacking rejections now invalidate candidates instead of leaving them apparently selectable.
    - Every non-selected valid candidate receives an explicit arbitration rejection reason, including lower-ranked, confluence, duplicate, opposing, and exposure paths.
    - The controller journals valid candidates only after arbitration and central risk produce the final signal decision; broker order/fill outcomes remain in the order journal.
    - Signal IDs include direction, preventing same-strategy BUY and SELL evaluations at one timestamp from sharing an identifier.
    - Deterministic arbitration coverage now includes every enum mode and the full 48/0 Shadow regression pass; completed organic post-repair true-tick CSV inspection is under `TestEvidence/organic_true_ticks_20260716/`.

## Remaining critical/high risks

### Runtime proof is incomplete

Initialization, the core Shadow market-position lifecycle, direct BO/FBO/TP/MR class reachability, and final-decision journal routing now have captured runtime proof. Organic true-tick Shadow evidence reached FBO accepted BUY/SELL entries, completed FBO trades, BO/FBO/TP/MR BUY/SELL rejections, and a central-risk rejected winner. A combined true-tick training baseline and clean holdout retry completed; the first holdout attempt is preserved as invalid/incomplete evidence. BO/TP/MR accepted organic lifecycles, broker retcodes, protection repair, transaction ordering, restart recovery, broader holdouts, and tester/live agreement still require runtime evidence.

### Shadow mode supports market lifecycles, not pending orders

Shadow mode now maintains virtual market positions through bid/ask entry, configured slippage/commission, stop/target, partial close, breakeven, ATR trailing, time stop, MFE/MAE, virtual equity/exposure, risk updates, forced flattening, and completed-trade journaling. Pending-order intents are rejected rather than simulated. The core market-position branches have deterministic runtime proof. No expectancy or drawdown claim is made.

### Pending orders are cancelled, not restored

Startup now fails safe by cancelling owned pending orders. That is safer than orphan execution but is not the documented pending-order recovery feature.

### Recovery remains partial

Broker history can recover strategy, original stop/target, and initial volume. Signal ID, original entry regime, MFE/MAE, exact partial count, and management state cannot always be reconstructed. Unknown ownership follows policy, but full fidelity requires durable per-position context.

The production persistence path now calls `GlobalVariablesFlush()` explicitly after saving all state groups. A two-process Strategy Tester probe wrote and verified schema v3 in phase 1, then loaded schema 0 after a complete tester/Wine restart. This is recorded as tester-state isolation—not as proof of live-terminal failure and not as a restart pass. A normal-terminal/VPS restart with broker state is still required.

### Strategy semantics still needing research completion

- These are test-design gaps, not evidence of profitability.

### Challenge Mode remains research-only

Challenge transitions and locks are safer than the generated baseline, but deposits/withdrawals, attempt reset policy, profit-lock enforcement against all exposure, and restart scenarios have not been proven. Challenge Live is prohibited.

### Other limitations

- Manual news times only; no automated calendar feed.
- Alert routing is wired for key signal/order/protection events and tester-suppressed for validation; real terminal/push delivery remains unverified outside Strategy Tester.
- Fixed local capacity of 20 tracked positions.
- State-version mismatch has no formal migration/quarantine workflow.
- Per-strategy magic constants exist, but execution currently relies primarily on the common magic range plus short comments.
- Some configuration fields describe future architecture and remain unused; see `KNOWN_LIMITATIONS.md` and `HANDOFF.md`.

## Strategy-by-strategy verdict

| Strategy | Static reachability | Direction symmetry | Lookahead status | Runtime readiness |
|---|---|---|---|---|
| Breakout | Reachable in code after preceding compression and closed-range break | Long/short side-specific; rejected direction preserved | Closed ranges and confirmed-bar triggers repaired; immediate mode intentionally uses current quote | Direct fixture passed; organic reachability pending |
| Failed Breakout | Directional failed-auction features now populated | Long/short objective inverse logic; rejected direction preserved | Closed-bar sweep/reclaim | Direct fixture passed; generated fallback organically reached long/short through risk; true-real-tick lifecycle pending |
| Trend Pullback | Reachable when trend/structure/pullback filters align | Long/short mirrored with bid/ask entries; rejected direction preserved | Closed features; trigger input active | Direct fixture passed; organic reachability pending |
| Mean Reversion | Reachable in balanced regimes with true SD deviation | Directional wick and price geometry repaired; rejected direction preserved | Closed features; trigger input active | Direct fixture passed; organic reachability pending |

No strategy has a proven edge. Parameter values are research hypotheses.

## Readiness classification

```text
READY FOR SHADOW MODE
```

Not ready for:

- Conservative Micro-Live;
- Challenge-Mode Research using performance outputs;
- Challenge Live.

Promotion requires broader organic feature/regime coverage on true real ticks, accepted Shadow lifecycles, controlled live-path Strategy Tester scenarios, restart/reconciliation tests, and real broker fault evidence. Shadow results are research data only until realistic-cost baselines and holdouts establish an edge.
