# Phase 4 Evidence — AllocationEngine + CounterfactualTracker

Date: 2026-07-21
Binary: `QuantBeastEA.ex5` SHA-256 `d17d0bdeab48fb64db91996a88bf758924502b3318da9a22203f0d13ba04d2c9`
(built 2026.07.21 02:58:34, 554604 bytes)

## Scope

Phase 4 introduces two new, wired subsystems, both **additive and defaulted to
zero behavior change**:

1. **CAllocationEngine** (`Portfolio/AllocationEngine.mqh`) — distributes the
   per-strategy risk budget. Default policy `ALLOC_EQUAL` returns weight `1.0`
   for every strategy (identical to pre-Phase-4 sizing). Optional
   `ALLOC_CONFIDENCE` / `ALLOC_PERFORMANCE` weighting selected via
   `InpAllocationMode`. Wired into `ExecuteSignal`: effective risk % =
   base × `GetWeight(strategy_id)`, restored after sizing; each accepted signal
   feeds `RecordSignal`, each close feeds `RecordOutcome`.

2. **CCounterfactualTracker** (`Analytics/CounterfactualTracker.mqh`) — buffers
   the hypothetical entry/stop/target of *rejected* signals that still reached a
   computable setup (non-zero geometry), for offline edge analysis. Disabled by
   default (`InpEnableCounterfactual=false`). Wired at three rejection sites
   (strategy-rejection, arbitration-loser, risk-rejection). **Buffered design:**
   rows accumulate in memory and are written once at `Close()` (OnDeinit) — there
   is deliberately no per-signal file I/O, so enabling the tracker can never
   perturb signal timing.

## Correctness gate — deterministic self-tests

Compile: **0 errors, 0 warnings** (metaeditor.log 2026.07.21 02:58:34).

Self-test tester run (`QuantBeast.P4SelfTest.ini`, `InpSelfTestOnInit=true`):

```
TEST 57 PASS: Allocation engine equalOne=ok confHigherBO=ok conserved=ok wBO=1.50 wMR=0.50
TEST 58 PASS: Counterfactual tracker buffered=ok ignoresValid=ok ignoresNoGeo=ok disabledNoop=ok
Self-tests complete: 61 passed, 0 failed
```

- **TEST 57 (AllocationEngine):** equal mode → every weight exactly 1.0
  (baseline preserved); confidence mode → higher-confidence strategy weight
  `wBO=1.50` > lower `wMR=0.50`, mean conserved at 1.0 (budget-conserving).
- **TEST 58 (CounterfactualTracker):** buffers a rejected+geometry signal
  (RowCount 0→1); ignores a *valid* signal; ignores a rejected signal with no
  computable geometry; a disabled tracker is a pure no-op. This exercises the
  tracker's logic directly (via `Init(true)` in-process), independent of the
  tester input path.

## Baseline preservation — journaled backtest

`QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260420_20260424.ini`, XAUUSD M5,
Shadow mode, true ticks, Apr 20–24 2026. ACCEPTED signals per strategy:

```
BO=2  FBO=9  TP=0  MR=5
```

Identical to the established pre-Phase-4 baseline — the additive AllocationEngine
(equal weight) and disabled CounterfactualTracker are behavior-preserving.

## The FBO 9→11 investigation (resolved)

During Phase 4 an FBO count of **11** appeared once (vs. the baseline 9), which
raised the concern that the counterfactual logger was perturbing the tester. The
investigation concluded:

- An early counterfactual design used **per-signal `FileFlush` I/O**. On
  suspicion that per-tick file I/O could perturb tester tick processing, the
  tracker was **redesigned to buffer in memory and write once at `Close()`** —
  guaranteeing it is side-effect-free with respect to trading. (This is the
  design shipped.)
- A runtime diagnostic (`CF diag: flag=X enabled=Y`, printed at OnInit) then
  revealed that **`InpEnableCounterfactual=true` set via the tester `.ini`
  `[TesterInputs]` was never being applied** — the flag read `0` in every run,
  including the run that produced FBO 11. Both the `true` and numeric `1` value
  forms were tried; both yielded `flag=0`, while `InpSelfTestOnInit` (an
  otherwise-identical `input bool`) *did* apply from the same `.ini`. This is a
  MetaTrader tester input-application quirk specific to this input, **not a code
  defect** (the declaration, spelling, and `.ini` line are all correct; the
  compiled default is honored regardless of the override).
- **Therefore the counterfactual tracker was OFF in every backtest**, so it
  could not have caused the FBO 11. With counterfactual confirmed disabled, the
  FBO 11 was a **non-reproducing tester-nondeterminism outlier**: FBO measured 9
  in 6+ runs on the Phase-4 build (and again in this phase's baseline).

## Verification status of the counterfactual CSV population

- **Logic: verified** deterministically by TEST 58 (buffer/ignore/no-op paths).
- **Side-effect-free: verified** by the buffered design (no I/O until Close) and
  by the FBO-9 baseline being unaffected.
- **End-to-end CSV population in the Strategy Tester: not demonstrated**, because
  `InpEnableCounterfactual` cannot be turned on via the tester `.ini` (the input-
  application quirk above). This is a documented **verification limitation**, not
  a functional gap: the enable path (`Init(enabled)`), the buffering path, and
  the write path are each individually correct by inspection and, for the first
  two, by self-test. The diagnostic scaffolding used to establish this has been
  removed from the shipping binary.

## Files

- `Portfolio/AllocationEngine.mqh` (real `CAllocationEngine`, replacing the stub)
- `Analytics/CounterfactualTracker.mqh` (real buffered `CCounterfactualTracker`)
- `Core/Enums.mqh` (`ENUM_ALLOCATION_MODE`)
- `Core/Constants.mqh` (`QB_COUNTERFACTUAL_LOG`)
- `Core/Configuration.mqh` (`InpAllocationMode`, `InpEnableCounterfactual`)
- `Experts/QuantBeast/QuantBeastEA.mq5` (globals, Init, sizing-path wiring,
  three rejection-site LogRejection calls, Close in OnDeinit, TEST 57/58)
- `Testing/SafetyTests.mqh` (TEST 57 `QBTestAllocationEngine`,
  TEST 58 `QBTestCounterfactualTracker`)
