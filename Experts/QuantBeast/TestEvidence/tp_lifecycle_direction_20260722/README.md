# TP lifecycle direction attribution — 2026-07-22

## Finding

Three organic windows produced 10 `resume_candidate` rows, representing five
completed-bar observations because the controller evaluates both BUY and SELL.
The lifecycle retained its nominated trend direction internally but did not
serialize it, so those observations could not be assigned to a valid
counterfactual side from the journal alone.

## Change

- Added `GetLifecycleDirection()` returning `up`, `down`, or `none`.
- Added `lifecycleDirection` to universal TP rejection diagnostics.
- Extended Test 64 to verify an upward TP-specific seed.
- Extended `tp_structure_report.py` compatibly to parse and count the field.
- No trading decision or broker path changed.

## Verification

- Parser syntax and directional synthetic row: passed.
- MetaEditor compile: **0 errors, 0 warnings**, 14,212 ms.
- Shadow regression: **67 passed, 0 failed**, 22,080 ticks, 1,104 bars, normal
  `test passed` and `thread finished` footer.

## Hashes

```text
QuantBeastEA.mq5                 95cda300c9d10558b00c18f121951972b79e5bf15a26dfe0347a160305aaea70
QuantBeastEA.ex5                 b36386631ef3d94bd31c8d3bb31ae39737429a33cafcef9c2d2a8a33305dfee7
TrendPullbackEngine.mqh          c61451ec8cd8b926a9d6443d3ab97c9e4b43ff8349a2575536fea872ce38e181
SafetyTests.mqh                  624a3cfb753484d002a6696c35c3ff1dd0fa76a61f44eb1a69e48d6747b452f5
tp_structure_report.py           aa58703fc43025822120b9c5806d558fef78271eeea011f1980a48a7dc22e7d0
```

Readiness remains `READY FOR SHADOW MODE`.
