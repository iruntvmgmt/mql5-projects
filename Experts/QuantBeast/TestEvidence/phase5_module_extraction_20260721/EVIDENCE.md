# Phase 5 Evidence — ExposureManager / Reconciliation / RecoveryEngine

Date: 2026-07-21
Binary: `QuantBeastEA.ex5` SHA-256 `76d4eed88f9f88810716cba5f59b1e5a19c7ef76c94af9f7a0fd7172846b8173`
(built 2026.07.21 03:26:56, 563668 bytes)

## Scope

The three delegated placeholder classes are built into real, wired modules via
**behavior-preserving extractions**: the decision logic moves into the module,
while the irreducible side effects (broker calls, global kill-switch /
protection-state mutations) remain at the call site. The existing recovery /
exposure self-tests — which now exercise the extracted modules — must stay green,
and the journaled baseline must be unchanged.

1. **CExposureManager** (`Portfolio/ExposureManager.mqh`) — owns the aggregate-
   exposure limit policy: the pre-sizing capacity gate (`AtCapacity`), the post-
   sizing projection (`WouldExceed`), and headroom (`Remaining`). `CRiskEngine`
   now holds a `CExposureManager` member and delegates both of its exposure
   comparisons to it (`ValidateTrade` → `AtCapacity(totalExposure)`;
   `ValidateSizedTrade` → `WouldExceed(totalExposure, lots)`), replacing the two
   hard-coded inline comparisons. The authoritative current aggregate remains the
   broker/Shadow query (`EffectiveExposure()`), passed in by the caller.

2. **CReconciliation** (`Execution/Reconciliation.mqh`) — owns the
   `ReconciliationResult` structure (reconstructed / unknown / unprotected) and a
   static `Classify(result, unknownPolicy)` that produces the
   `ReconciliationVerdict` (need_quarantine / need_emergency), mirroring the
   former inline OnInit logic exactly: `unknown > 0 && policy == UNKNOWN_QUARANTINE`
   → quarantine; `unprotected > 0` → protection emergency (independent flags).

3. **CRecoveryEngine** (`Execution/RecoveryEngine.mqh`) — single orchestration
   entry point: `RecoverPositions(pm, magicBase, policy, resultOut)` drives
   `CPositionManager.ReconstructFromBroker`, assembles the result, and returns the
   `CReconciliation` verdict. OnInit now calls this instead of the inline
   reconstruction sequence and applies the returned verdict to its global entry /
   protection state.

## Correctness gate — deterministic self-tests

Compile: **0 errors, 0 warnings** (metaeditor.log 2026.07.21 03:26:56).

Self-test tester run (`QuantBeast.P4SelfTest.ini`, `InpSelfTestOnInit=true`):

```
TEST 39 PASS: Live recovery gate no passive flatten
TEST 40 PASS: Unknown positions unmanaged
TEST 59 PASS: Exposure manager capGate=ok projUnder=ok projOver=ok projEdge=ok remOk=ok
TEST 60 PASS: Reconciliation verdict clean=ok unkQuarantine=ok unkIgnore=ok unprotected=ok both=ok
Self-tests complete: 63 passed, 0 failed
```

- **TEST 59 (CExposureManager):** the capacity gate fires at/over the cap and not
  below; the projection allows current+add up to exactly the cap and blocks
  beyond it; headroom is floored at zero. These assert the exact semantics of the
  two checks it replaced in CRiskEngine (`>=` gate, `+lots > cap + eps`
  projection).
- **TEST 60 (CReconciliation):** all four verdict combinations — clean, unknown
  under QUARANTINE (→ quarantine), unknown under IGNORE (→ no quarantine),
  unprotected (→ emergency regardless of policy), and both firing independently.
- **Existing recovery tests green:** TEST 39 (live recovery gate) and TEST 40
  (unknown positions unmanaged) still pass, and OnInit — which now routes startup
  position reconstruction through `CRecoveryEngine` every run — completed cleanly
  in every tester initialization. The recovery orchestration is thus covered both
  by its delegated decision core (TEST 60) and by the unchanged integration tests.

Full run: **63 passed, 0 failed**, no FAIL lines.

## Baseline preservation — journaled backtest

`QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260420_20260424.ini`, XAUUSD M5,
Shadow mode, true ticks, Apr 20–24 2026. ACCEPTED signals per strategy:

```
BO=2  FBO=11  TP=0  MR=5   (first Phase-5 run)
```

BO/TP/MR match the established baseline exactly. FBO measured **11** vs the modal
**9** — the same 9↔11 variance already documented on a pre-Phase-5 binary. This
was investigated to root cause and is **not** a Phase-5 regression:

- The two extra acceptances are the *second* signal of two near-adjacent
  same-direction FBO pairs (04.22 19:30→19:35 BUY, 04.23 14:10→14:15 SELL, one M5
  bar apart, near-identical geometry).
- In all five prior FBO-9 blocks those second signals were **REJECTED with code 25
  "Arbitration: same-direction stacking disabled"** — i.e. the first FBO position
  was still open. In this run they were ACCEPTED because the first position had
  already closed by then. The flip is entirely a function of the first position's
  *close timing* at the tick level.
- **Rejection code 25 is an arbitration decision that executes *before* risk /
  exposure validation.** Every Phase-5 change is either downstream of arbitration
  (the CExposureManager check, which CRiskEngine consults after arbitration) or
  unreachable in Shadow mode (CReconciliation / CRecoveryEngine run only in the
  broker-reconciling OnInit branch, which Shadow never enters). Phase 5 touched
  neither `SignalArbitrator` (which owns the code-25 stacking decision) nor
  `ShadowPortfolio` (which owns position open/close lifecycle). It is therefore
  logically impossible for Phase 5 to change this outcome.
- Conclusion: the 9→11 difference is tester tick-level nondeterminism at a
  position-close boundary (consistent with the documented pre-Phase-5 variance),
  not a behavior change from the module extractions. A re-run of the identical
  Phase-5 binary was performed to confirm the count varies without any code
  change (see below).

**Re-run of the identical binary (decisive):** the same Phase-5 ex5
(`76d4eed8…`) was run again, same config, back-to-back:

```
BO=2  FBO=9  TP=0  MR=5   (second Phase-5 run — exact modal baseline)
```

Same binary, two consecutive runs → FBO 11 then FBO 9. This is conclusive proof
that the 9↔11 difference is tester tick-level nondeterminism at the position-close
/ arbitration-stacking boundary, with zero dependence on any code change. The
second run reproduces the established BO2/FBO9/TP0/MR5 baseline exactly.

The behavior-preserving claim rests on: (1) the arbitration-ordering argument
(code-25 stacking precedes all Phase-5 code paths); (2) the identical-binary
re-run reproducing the exact baseline; and (3) the 63/0 self-tests including the
unchanged recovery tests 39/40.

## Files

- `Portfolio/ExposureManager.mqh` (real `CExposureManager`, replacing the stub)
- `Execution/Reconciliation.mqh` (real `CReconciliation` + result/verdict structs)
- `Execution/RecoveryEngine.mqh` (real `CRecoveryEngine` orchestrator)
- `Risk/RiskEngine.mqh` (holds + consults `CExposureManager` for both exposure checks)
- `Experts/QuantBeast/QuantBeastEA.mq5` (`g_Recovery` global; OnInit routes position
  reconstruction through `CRecoveryEngine`; TEST 59/60 registered)
- `Testing/SafetyTests.mqh` (TEST 59 `QBTestExposureManager`,
  TEST 60 `QBTestReconciliationVerdict`)
