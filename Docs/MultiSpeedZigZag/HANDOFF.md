# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

## Branch

`feature/mszz-standalone-suite`

Quant Beast work on `main` remains isolated from this branch.

## Current implementation

### Structural engine

- `Include/MultiSpeedZigZag/Core/Types.mqh`
- `Include/MultiSpeedZigZag/Core/TripleZigZagEngine.mqh`

The engine rebuilds three closed-bar ATR-reversal ZigZags, stores immutable confirmed pivots, pivot and confirmation times, HH/HL/LH/LL labels, projected lines, close-confirmed breaks, and stable identities.

### Strategy suite

- `Include/MultiSpeedZigZag/Strategies/StrategySuite.mqh`

Implemented strategies:

- Fast breakout
- Medium breakout
- Slow breakout
- Fast + medium confluence with slow alignment
- Fast breakout with medium context
- Medium breakout with slow context
- Nested pullback continuation
- Weighted three-speed ensemble

Every emitted candidate now consistently includes:

- `origin_type`
- `origin_id`
- strategy-specific `event_id`
- `evidence_mask`

Related interpretations now share the same structural origin while retaining separate strategy event IDs.

### Opportunity clustering

- `Include/MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5`

The engine groups compatible candidates by origin and direction, creates stable cluster IDs, merges evidence, tracks support count and stop disagreement, chooses a canonical owner, and selects the strongest cluster.

### Standalone EA

- `Experts/MultiSpeedZigZagEA.mq5`, version `0.30`

The EA now executes or shadows **selected opportunity clusters**, not raw candidates.

Flow:

1. Rebuild structural engine from closed history.
2. Emit all enabled raw strategy candidates.
3. Journal raw candidates.
4. Build opportunity clusters.
5. Select strongest cluster.
6. Resolve canonical owner candidate.
7. Apply score, duplicate, spread, stop, volume, position, and permission gates.
8. Persist the cluster ID after shadow selection or execution.

This prevents multiple strategy interpretations of the same structural event from becoming duplicate independent trades.

Live execution still requires all three gates:

- `InpShadowOnly=false`
- `InpAllowLiveExecution=true`
- `InpAcknowledgeRisk=true`

The EA remains not production-authorized.

### Persistence and execution guards

- `Include/MultiSpeedZigZag/Execution/EventStore.mqh`
- `Include/MultiSpeedZigZag/Execution/ExecutionGuard.mqh`

Implemented persistent cluster/event deduplication, broker volume normalization, permission checks, spread control, and stop/freeze validation. Runtime verification remains pending.

### Parity tooling

- `Include/MultiSpeedZigZag/Diagnostics/ParityExporter.mqh`
- `Tests/MultiSpeedZigZag/Export_MSZZ_Parity.mq5`

The exporter writes manifest, bars, pivots, snapshots, candidates, and clusters. Pivot, candidate, and cluster records now have in-run emitted-ID deduplication.

### Specifications and tests

- `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5`
- `Docs/MultiSpeedZigZag/SYNTHETIC_FIXTURES.md`
- `Docs/MultiSpeedZigZag/STATE_MACHINES.md`
- `Docs/MultiSpeedZigZag/OPPORTUNITY_CLUSTERING.md`
- `Docs/MultiSpeedZigZag/PARITY_EXPORT_SCHEMA.md`
- `Docs/MultiSpeedZigZag/RESEARCH_JOURNAL_SCHEMA.md`

## Canonical behavior

- Wick extremes define candidate legs.
- ATR reversal confirms pivots.
- Closed prices confirm line breaks.
- Forming bars are excluded.
- Confirmed pivots are immutable.
- Equal highs/lows use latest-equal-wins.
- Strategy candidates sharing one structural origin are clustered.
- One selected cluster may produce at most one action unless staged entry is explicitly added later.

## 2026-07-25 worklog — compile, repair, and shadow-test pass

Compiled all four MSZZ files for the first time (previously unverified). Fixed one real compile blocker (illegal local reference to an array element in `OpportunityClusterEngine.mqh`) and one crash-risk defect (`ZeroMemory()` on string-containing structs in five sites) — the fix for the latter itself introduced an uninitialized-field bug that was caught via runtime evidence (a garbage pivot row in a real parity export) and corrected with explicit field-by-field resets. Ran `Test_MSZZ_Determinism` (PASS) and `Test_MSZZ_Clusters` (8/8 PASS, failures=0) against real XAUUSD M5 history on an isolated demo account. Ran `Export_MSZZ_Parity` (1000 bars, default ATR settings) and found a real defect: cluster IDs are malformed (pipe-delimited origin IDs nested inside another pipe-delimited ID). Ran the EA in the Strategy Tester in shadow mode over 2026.07.01–2026.07.24: zero orders/deals/trades, 178 clusters correctly shadow-journaled and consumed with zero duplicates. Directly verified the `CMSZZEventStore` component persists across a genuine process restart; a full EA-level restart test on a live/demo chart remains open (see KNOWN_ISSUES.md and BACKTEST_LOG.md for why the Tester-based attempt was invalid). Full evidence, exact commands, and file paths are in `BACKTEST_LOG.md`.

All work was done in an isolated portable MT5 test instance (`~/MT5-MSZZ-TEST`) on a freshly self-registered demo account, per explicit instruction, to avoid touching the live/main MT5 installation or its QuantBeast state.

## Known blockers

1. ~~MetaEditor compile remains unverified.~~ Resolved 2026-07-25 — all four files compile (0 errors; EA has one reviewed/accepted warning, see KNOWN_ISSUES.md).
2. ~~Determinism, cluster, event-store, and parity scripts have not been executed.~~ Resolved 2026-07-25 for determinism/cluster/parity; event-store persistence verified at the component level. Full EA restart-on-chart test still open.
3. Full-history rebuild performance has not been measured.
4. Position/order ownership reconstruction is absent.
5. Account-risk sizing, margin preflight, daily limits, trade-count limits, and emergency kill controls are absent.
6. Fixed strategy scores are placeholders, not edge estimates.
7. Reserved strategies remain specifications only.
8. Pine bar-for-bar parity has not been run.
9. Elapsed-time versus bar-index trendline geometry remains unresolved.
10. Cluster persistence currently records consumed cluster IDs, not complete open cluster lifecycle state.

## Next actions

1. ~~Compile every EA, header, and test script in MetaEditor.~~ Done 2026-07-25.
2. ~~Fix all errors and review every warning.~~ Done 2026-07-25 (one warning reviewed and accepted, not eliminated — see KNOWN_ISSUES.md).
3. ~~Run deterministic and cluster tests.~~ Done 2026-07-25 — both PASS.
4. Add executable tests for synthetic pivot fixtures (F01–F12 in SYNTHETIC_FIXTURES.md are still specifications only, not executable tests).
5. ~~Run the MQL5 parity exporter on a fixed XAUUSD interval.~~ Done 2026-07-25 (1000 bars, default ATR settings). Found and left open: malformed cluster IDs (KNOWN_ISSUES.md).
6. Produce the matching Pine export and run the actual cross-platform comparison — still not done.
7. Resolve trendline geometry from parity evidence — still open.
8. Add position/order ownership reconstruction.
9. Add percentage-risk sizing, margin checks, daily limits, and kill switches.
10. Implement reserved stateful strategies one at a time.
11. ~~Collect shadow evidence before demo execution.~~ Done 2026-07-25 — shadow Strategy Tester run over 24 days, zero orders, 178 clusters journaled/consumed with zero duplicates.
12. New: fix the malformed cluster-ID encoding (needs a DECISION_LOG entry first).
13. New: add an `ACCOUNT_MARGIN_MODE` check or otherwise resolve the netting-account assumption in `CloseOppositeIfNeeded`/`InpOnePositionPerSymbol` before any hedging-account live/demo use.
14. New: run a full EA restart test on a live/demo chart across real elapsed bar-closes (the Tester-based attempt in this pass was methodologically invalid — see KNOWN_ISSUES.md).

## Agent procedure

At session start, read this file, `DECISION_LOG.md`, `TEST_PLAN.md`, `NON_REPAINTING_CONTRACT.md`, `SYNTHETIC_FIXTURES.md`, and `STATE_MACHINES.md`.

At session end, update this handoff, append decisions, update tests, and record unresolved defects. Do not call the branch production-ready without compile, parity, restart, safety, and evidence gates.