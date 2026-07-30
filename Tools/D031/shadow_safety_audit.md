# D031 Shadow Safety Audit

Static, tool-independent audit (grep, no MQL5 compiler required) proving the
six-family research layer cannot reach execution. Re-run the commands below
to reproduce.

## 1. No trade-function calls anywhere in the new files

```bash
grep -nE "OrderSend|OrderCheck|OrderModify|PositionClose|PositionModify|CTrade" \
  Include/MultiSpeedZigZag/Research/Families/*.mqh \
  Include/MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh
```

Result: no matches (only the safety-contract comment in
`SixFamilyResearchSuite.mqh` mentions these names in prose).

## 2. No includes of Execution/* or Portfolio/* from the new files

```bash
grep -n "#include.*Execution/\|#include.*Portfolio/" \
  Include/MultiSpeedZigZag/Research/Families/*.mqh \
  Include/MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh
```

Result: no matches. The research layer's `#include` graph is
`Core/Types.mqh` + `Research/RegimeClassifier.mqh` +
`Research/Families/ResearchCandidateTypes.mqh` only -- never touches
`Execution/*` or `Portfolio/*`, unlike `Diagnostics/TradeAnalyticsExporter.mqh`
(deliberately not included here for exactly this reason -- see
`SixFamilyResearchSuite.mqh`'s `MSZZResearchSessionId()` comment).

## 3. New files never construct or reference `MSZZCandidate` (the production, execution-feeding type)

```bash
grep -n "MSZZCandidate " Include/MultiSpeedZigZag/Research/Families/*.mqh \
  Include/MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh | grep -v MSZZResearchCandidate
```

Result: no matches outside comments. Every family and the suite aggregator
build and emit `MSZZResearchCandidate` only -- a disjoint struct (see
`ResearchCandidateTypes.mqh`), not the production `MSZZCandidate`
`CandidateHandoff`/`ClusterEngine`/`ExecuteCluster` require.

## 4. EA wiring: the suite's output is never handed to the production pipeline

`Experts/MultiSpeedZigZagEA.mq5`, `ProcessClosedBar()`:

```cpp
if(InpEnableSixFamilyResearch)
{
   MSZZResearchCandidate six_family_candidates[];
   g_six_family_suite.Evaluate(fast,med,slow,g_last_regime,rates[closed_count-1],six_family_candidates);
}
```

`six_family_candidates` is declared, populated, and goes out of scope --
never appended to `candidates[]`/`d027_candidates[]`, never passed to
`CMSZZCandidateHandoff`, `g_cluster_engine`, or `ExecuteCluster`. This is
also structurally enforced by the type system: `MSZZResearchCandidate` is
not `MSZZCandidate`, so passing it to any of those functions would not
compile.

## 5. Default-disabled

`input bool InpEnableSixFamilyResearch=false;` -- every existing
configuration's behavior is unchanged unless a config explicitly opts in,
same convention as the five D027 research strategies before it.

## Not covered by this static audit (blocked, see known_limitations.md)

- An actual compiled build and a real backtest run proving the certified
  P4 candidate stream is byte-identical with the flag on vs off.
- Running `Tests/MultiSpeedZigZag/Test_MSZZ_D031_SixFamilies.mq5` and the
  existing test suite to confirm "existing regression remains green".

Both require MetaEditor's compile bridge, which did not produce a
compiler-log update across four attempts in this session (including
against a previously-known-good file) -- an environment issue, not
evidence of a defect in this change.
