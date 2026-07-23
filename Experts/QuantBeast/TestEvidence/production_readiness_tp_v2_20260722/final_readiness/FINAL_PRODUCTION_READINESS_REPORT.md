# Final production-readiness report -- production_readiness_tp_v2_20260722

**Session:** 2026-07-22/23. **Objective:** coordinated production-readiness
closure sprint -- TP V1 preservation, TP V2 specification/implementation,
all-strategy organic evidence, production infrastructure audit, restricted
all-strategy demo-candidate preparation, and an exact remaining-blocker list.

## 1. Branch, HEAD, sync, working-tree state

Branch `main`, HEAD `a17484c`, 1 ahead / 0 behind `github/main` (not
pushed). Working tree clean except pre-existing, unrelated items present
at session start. See `FINAL_REPO_STATE.md` for full detail.

## 2. Commits created (9)

See `FINAL_REPO_STATE.md` for the full list with hashes. Summary: TP V1
freeze (1), TP V2 spec (1), TP V2 implementation+tests (1), evidence-doc
sync (1), config validation fix (1), infrastructure audit (1), demo
candidate config (1), unified matrix in two parts (2).

## 3. TP V1 preservation method

Annotated Git tag `quantbeast-tp-v1-research-freeze-20260722` at the exact
evidence-producing commit `953c2d0` (zero file diff from the tag).
`LifecycleVersion` now stamped on every V1 diagnostic/outcome row
(`QB_TP_LIFECYCLE_VERSION=1`) so V1 and V2 evidence can never be silently
pooled, as defense in depth on top of V1/V2 being physically separate
engines with separate journals. V1's engine and tracker remain wired,
unchanged in trading behavior, for future passive larger-window
verification. Full record: `tp_v1_freeze/README.md`.

## 4. Final TP V2 definition

An 8-state lifecycle (`IDLE -> TREND_QUALIFIED -> IMPULSE_ACTIVE ->
PULLBACK_ACTIVE -> RESUMPTION_ARMED -> TRIGGERED`, plus `INVALIDATED`/
`EXPIRED`) with its own decoupled trend-integrity check and an explicit
price-based invalidation level frozen at impulse start -- no single
instantaneous `regime.structure` reading is ever the sole authority over a
transition (the direct, structural fix for V1's documented 11/16
rejection mode). Four predefined resumption triggers share identical
upstream logic; default is rejection+directional-confirmation (Decision
D004, chosen from the hypothesis wording, not trade-count). Full spec:
`tp_v2_spec/TP_V2_SPEC.md`, `TP_V2_PARAMETER_CONTRACT.md`,
`TP_V2_REASON_CODES.md`.

## 5. TP V2 state-transition diagram

See `tp_v2_spec/TP_V2_STATE_MACHINE.md` for the full diagram and per-state
entry/exit criteria. Summary:

```
IDLE --[trend qualifies]--> TREND_QUALIFIED --[impulse displaces]--> IMPULSE_ACTIVE
   --[countertrend retracement measured]--> PULLBACK_ACTIVE
   --[retracement in band, local condition ending]--> RESUMPTION_ARMED
   --[trigger confirms]--> TRIGGERED (geometry computed here only)

Any state (from TREND_QUALIFIED on) --[trend flips/exhausts, event abnormal,
   or price beyond the frozen invalidation level]--> INVALIDATED
Any state with an active episode --[age > 20 bars]--> EXPIRED
INVALIDATED / EXPIRED / TRIGGERED --[next bar]--> IDLE (fresh check)
```

## 6. Tests and compile status

Compile: **0 errors, 0 warnings** (final build, commit `a17484c`'s
preceding source commit `acefa09`). Self-tests: **96 passed, 0 failed**
(Model=1 regression, `Profiles/Tester/QuantBeast.SelfTestDetail.20260722.ini`).
Tests 75-93 are new this sprint (TP V2 lifecycle/trigger/geometry/isolation
coverage, Test 93 config-validation boundary coverage). Two genuine defects
found and fixed during test development: a lifecycle reset-ordering bug
(Tests 79/81/84 initially failed -- fixed by reordering the terminal-state
reset ahead of the invalidation re-check) and a pre-existing tracker
bookkeeping defect (`CTPOutcomeTracker::WriteRow()`, unrelated to TP V2
itself, found via Wine file-handle flakiness in the self-test harness).

## 7. Unified window matrix

Six XAUUSD M5 Model=4 (real-tick) windows, run last per the user's explicit
build-then-test instruction. 4.93M total ticks, 3,833 total bars, 17,220
total per-strategy signal-decision rows. Four reused (regression
reproduction, including V1's largest-n TP window), two genuinely untouched.
All six completed naturally (`Test passed`, `thread finished`). Full detail:
`unified_strategy_matrix/README.md` and the 24 per-window report files.

## 8. Organic reachability by strategy

| Strategy | Windows with >=1 ACCEPTED | Total ACCEPTED | Notes |
|---|---:|---:|---|
| BO | 1 of 6 | 1 | Infrequent but real; matches prior sessions' finding. |
| FBO | 6 of 6 | 34 | Reaches ACCEPTED in every window tested. |
| MR | 6 of 6 | 13 | Reaches ACCEPTED in every window tested. |
| TP (V1) | 0 of 6 | 0 | Consistent with its frozen "no reliable directional information" conclusion; unchanged by adding TP V2 to the roster. |
| TP V2 | 0 of 6 (experimental gate forces this) | 0 | Full 8-state lifecycle including TRIGGERED reached organically in 3 of 6 windows (9 unique episodes); 4 of those 9 passed every geometry/spread/confidence gate and would have traded if the experimental flag were on. |

48 completed Shadow trades pooled across all 6 windows, 100% traceable
candidate-through-exit (48/48 joined via the new `strategy_performance_report.py`).

## 9. Infrastructure defects found and fixed

1. `KillSwitchState.strategy_kill` hardcoded `bool[4]` -> `[5]` (silent
   overrun once a 5th strategy existed).
2. Arbitration-loop `StrategySignal candidates[8]` -> `[10]` (same cause).
3. `CTPOutcomeTracker::WriteRow()` skipped its own finalized-event
   bookkeeping when the journal file couldn't be opened (pre-existing
   defect, unrelated to TP V2, found via test-harness file flakiness).
4. No safety-critical input validation existed anywhere in `OnInit`; no
   resolved-configuration startup log existed. Both added (Part F).

Full audit: `infrastructure_audit/INFRASTRUCTURE_AUDIT.md`, labeled
PROVEN/PARTIALLY PROVEN/UNPROVEN/BLOCKED per subsystem.

## 10. Restart/reconciliation readiness

**PROVEN** (real terminal restarts, prior sessions, re-verified by survey
not re-run this session): owned positions safely reconstructed and
protected (entry/stop/target, ownership, actual protective-stop
verification with emergency escalation); owned pending orders
reconstructed; unknown positions quarantined/reported per policy, never
silently adopted; corrupted state versions quarantine fail-closed.
**Explicitly does not survive restart** (documented, accepted safe-fallback
gap, not a defect): durable signal ID beyond the journal string, exact
partial-exit count, full position-management context, virtual Shadow
positions. **PARTIALLY PROVEN:** `UNKNOWN_QUARANTINE`'s `KillEntries()`
call and the daily/weekly/drawdown lock booleans share proven load paths
but weren't independently re-verified against a real restart this session.

## 11. Broker-execution readiness

**PROVEN:** market-order path, fill reconciliation, protective-stop
repair/emergency, consecutive-rejection counting, disconnect-priority,
emergency-dispatch -- deterministic coverage plus real-broker confirmation
that requotes/rejections are structurally blocked on this broker (XAUUSD
Stop/Freeze level 0, market execution, immediate fills). **PARTIALLY
PROVEN:** disconnect is only checked inside `OnTick()`, not `OnTimer()` --
a short/unluckily-timed outage may go unobserved by the kill parameter
(found in a prior session via a real ~0.64s outage test; not fixed this
session -- real new logic, not a bounds-check fix, judged out of scope for
this pass's remaining time). **UNPROVEN:** fill-during-cancel race, actual
broker rejection streaks (deterministic-only, since the current broker
cannot organically produce these).

## 12. Alert and observability readiness

**PROVEN:** fail-closed alert delivery (entries latch closed if an enabled
alert can't be sent), category routing, all 8 required alert categories
now enabled in the prepared demo candidate. **PARTIALLY PROVEN:** a
complete live/demo-forward matrix that actually fires every required
category and confirms delivery has not been run (needs real forward-time
operation). **Was UNPROVEN, closed this session:** "no per-strategy/
direction/session/regime report exists" -- `strategy_performance_report.py`
now closes this, validated against 48 real trades across 6 windows.

## 13. Readiness labels

Per Part H's explicit rule: a unit fixture generating a signal is never
sufficient for `DEMO_READY` -- organic true-tick lifecycle, trigger,
geometry, arbitration, and risk reachability in independent windows are
required. Engineering safety defects were fixed immediately (see section
9); no economic threshold was changed without evidence; no gate was
weakened to manufacture a trade.

| Strategy | Label | Evidence basis |
|---|---|---|
| **BO** | `SHADOW_READY` | Mechanically sound, organically reaches ACCEPTED (1/6 windows this pass, consistent with prior sessions' single-window finding). Live gate (`QBLiveStrategySetAllowed`) still excludes it by the project's own standing, evidence-gated judgment -- not overridden this session. |
| **FBO** | `DEMO_READY` (already the standing project judgment) | Reaches ACCEPTED in 6/6 windows this pass; already the sole strategy the live gate permits, with prior real Conservative Live tester and demo-broker-lifecycle evidence. Re-confirmed, not newly promoted. |
| **MR** | `SHADOW_READY`, evidence-quality approaching `DEMO_READY` | Reaches ACCEPTED in 6/6 windows this pass (13 total), as consistently as FBO. Not labeled `DEMO_READY` because promoting it requires an evidence-justified update to `QBLiveStrategySetAllowed()` itself (currently FBO-only) -- a policy decision this session deliberately did not make unilaterally (see Decision D006). This is the strongest candidate for the next promotion decision. |
| **TP (V1)** | `NOT_READY` -- frozen, research-complete, by design | No reliable directional information found; zero production acceptances across 6 windows both before and after this sprint. Not a defect -- a completed negative research result. Remains wired for passive future verification only. |
| **TP V2** | `SHADOW_READY` | Mechanically sound (96/96 tests), full lifecycle including TRIGGERED organically reachable (9 episodes, 3/6 windows, both reused and untouched data) with real geometry construction. **Not `DEMO_READY`**: arbitration/risk reachability specifically has not been observed, since `InpEnableTPV2Experimental=false` meant no signal ever reached those subsystems. Next evidence step (not taken this session): a further Shadow-only run with the experimental flag enabled, still no broker orders, to observe arbitration/risk pass-through -- genuinely new evidence, not a rerun of what's already known. |

## 14. Exact remaining blockers

**Fixable now (engineering, no forward time required), NOT done this
session (explicitly out of scope for this pass's remaining budget):**

1. `OnTimer()`-driven connectivity checking, so a disconnect between
   `OnTick()` calls is never silently missed by the kill parameter.
2. Two inert inputs (`InpBO_CompressionPct`, `InpMR_TargetSDBandR`) --
   config cleanup, not a safety issue.
3. `InpMaxHoldingMinutes`/`InpMaxPendingMinutes` authoritative-path audit
   across every exit call site.
4. `UNKNOWN_QUARANTINE`'s `KillEntries()` path and the daily/weekly/
   drawdown lock booleans -- proven via unit test and a shared load path
   with proven fields, but not independently re-verified against a fresh
   real restart.
5. A Shadow-only (still no broker orders) TP V2 run with
   `InpEnableTPV2Experimental=true`, to gather arbitration/risk
   reachability evidence -- the one remaining gap between TP V2's current
   `SHADOW_READY` and `DEMO_READY`.
6. An evidence-justified decision on whether to update
   `QBLiveStrategySetAllowed()` to include MR (the strongest current
   candidate per this session's evidence) -- a policy decision, not an
   engineering task, requiring explicit operator authorization.

**Require genuinely elapsed forward time / explicit authorization (cannot
be closed by more code, tests, or backtesting):**

1. Complete live/demo-forward alert-category firing matrix (all 12
   required categories actually firing and confirmed delivered in a real
   running session).
2. Fill-during-cancel race and actual broker rejection-streak behavior
   (the current broker cannot organically produce these; only a different
   broker or a fault-injection harness against a live connection could).
3. Real rollover/swap-charge validation (currently swap is recorded as
   zero by design; only real overnight positions on a real account
   validate this).
4. Multi-month sampling to characterize BO/TP-family/MR/TPV2 true hit
   rates and any genuine edge -- inherently a forward-time or much-larger-
   backtest-sample question, not something six windows can answer.
5. Any live-money or Challenge-mode transmission -- explicitly prohibited
   without separate, explicit authorization regardless of any evidence
   gathered here.
6. Full demo-forward operator validation of the restricted all-strategy
   candidate (`XAUUSD_Conservative_Demo_AllStrategy.set`) once its
   remaining blockers (5, 6 above) are closed and the live gate question
   is resolved.

## 15. Confirmation: no broker orders transmitted

Confirmed repeatedly throughout this session: zero open positions/orders
verified before every terminal-sensitive action (start of session, before
every tester run, throughout). All evidence-gathering ran in `QB_MODE_SHADOW`
via the Strategy Tester. `InpEnableTPV2Experimental=false` throughout,
meaning TP V2 had zero reachable path to signal validity, arbitration,
risk, or execution at any point. No live or Challenge-mode run was
executed. **No broker orders were transmitted at any point in this session.**

## 16. Recommended restricted all-strategy demo activation sequence

1. Close blocker 5 above (Shadow-only TP V2 experimental-on run) --
   confirms arbitration/risk reachability without any broker risk.
2. Operator reviews this report's evidence and decides, as an explicit,
   decision-logged choice, whether to update `QBLiveStrategySetAllowed()`
   to include MR (strongest candidate) and/or TP V2 (pending step 1).
3. Close blockers 1-4 above (all pure engineering, no forward time
   needed) as a final infrastructure-hardening pass.
4. With explicit operator authorization (`InpAcknowledgeLiveBrokerRisk=true`,
   loaded via the Inputs tab's Load button per the established procedure),
   activate `XAUUSD_Conservative_Demo_AllStrategy.set` on the existing
   Coinexx-Demo account -- fake money, but EA-autonomous order
   transmission, exactly as the 2026-07-16 FBO-only Conservative Live
   activation required the same explicit authorization step.
5. Observe forward for a meaningful period (the project's own prior
   precedent: multi-week demo-forward) before considering any live-money
   step, which requires separate, explicit authorization regardless of
   demo results.

**Readiness label for the EA overall remains unchanged: `READY FOR SHADOW
MODE`.** Nothing in this session changed live/Challenge trading
authorization. FBO's existing Conservative Live demo-account authorization
(2026-07-16) is unaffected and unexpanded.
