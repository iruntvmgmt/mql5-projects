# Test Plan and Release Gates

## Gate 1 — Compile

- `Experts/MultiSpeedZigZagEA.mq5` compiles with zero errors.
- Core headers compile through both the EA and test script.
- Warnings are reviewed; none may hide truncation, uninitialized state, or enum conversion defects.

## Gate 2 — Determinism

- Run `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`.
- Two independent rebuilds over identical closed-bar history must produce identical pivot IDs, labels, directions, and breakout IDs.

## Gate 3 — Closed-bar integrity

- Confirm the forming bar is excluded.
- Compare tick-by-tick tester output against open-prices-only output for closed-bar signal timestamps.
- No signal may move earlier when more future data becomes available.

## Gate 4 — Pine/MQL5 parity

For a fixed symbol, timeframe, history window, and parameter set, export:

- confirmed pivots and confirmation bars
- structure labels
- projected line values
- breakout timestamps
- strategy candidates

Classify mismatches as intentional specification differences or defects.

## Gate 5 — Duplicate suppression

- One structural event may produce many raw candidates.
- At most one selected action may be emitted per event ID.
- Restart reconstruction must not retrade an already executed event once persistence is added.

## Gate 6 — Shadow evidence

Run shadow mode before any broker execution. Journal raw candidates, selection, rejected candidates, stop, target, spread, and strategy ID.

## Gate 7 — Execution safety

Before enabling execution:

- symbol volume limits normalized
- stop-level and freeze-level validation
- spread guard
- daily loss and trade-count controls
- persistent consumed-event store
- restart-safe ownership reconstruction
- explicit demo authorization

## Current gate status (2026-07-25)

- Gate 1 (Compile): **PASS**. All four files compile with 0 errors on MetaEditor build 6033 (live tree) and build 6061 (isolated verification instance). One reviewed/accepted warning remains on the EA (see KNOWN_ISSUES.md). Two real defects were found and fixed during this pass: a compile-blocking local reference bound to an array element in `OpportunityClusterEngine.mqh`, and an unsafe `ZeroMemory()` call on structs containing `string` members across five sites (crash risk per MetaQuotes docs).
- Gate 2 (Determinism): **PASS**. `Test_MSZZ_Determinism` ran against real XAUUSD M5 history (isolated demo account) and reported `TEST PASS: deterministic rebuild`.
- Gate 3 (Closed-bar integrity): Verified by source review (forming bar is excluded from `BuildSpeed`'s loop bound). Not separately verified via tick-by-tick vs. open-prices tester comparison this pass.
- Gate 4 (Pine/MQL5 parity): MQL5-side export **PASS** — `Export_MSZZ_Parity` produced all 6 CSV files (manifest/bars/pivots/candidates/clusters/snapshots) for XAUUSD M5, 1000 closed bars, default ATR settings, with no duplicate pivot rows, no missing origin/event IDs, and no forming-bar timestamps found on inspection. The matching Pine-side export/comparison has not been produced — parity is not yet certified end-to-end. One real defect found: cluster IDs are malformed (see KNOWN_ISSUES.md).
- Gate 5 (Duplicate suppression): **PASS** at the single-run level — `Test_MSZZ_Clusters` reported `failures=0` (8/8 assertions), and the shadow Strategy Tester run journaled 178 unique clusters with 178 matching consumed-event entries and zero duplicate cluster IDs shadow-journaled twice. Restart reconstruction is **partially verified**: the `CMSZZEventStore` component was directly proven to persist and reload consumed events across a genuine process restart (see BACKTEST_LOG.md), but a full end-to-end EA restart test (attached to a live/demo chart across real elapsed bar-closes) was not performed — the MetaTester Agent sandbox resets its `MQL5/Files/` on every separate invocation, so two successive Strategy Tester runs cannot be used to prove this end-to-end.
- Gate 6 (Shadow evidence): **PASS**. Shadow run journaled all raw candidates, cluster selection, and rejected/duplicate paths were exercised at the unit level (`Test_MSZZ_Clusters`); zero broker orders were placed (Strategy Tester report: 0 orders, 0 deals, 0 trades).
- Gate 7 (Execution safety): **NOT YET CERTIFIED**. Symbol volume/stop/freeze validation and spread guard exist and compile, but were not exercised (`InpAllowLiveExecution=false` in every run, by design, so `ExecuteCluster`'s live-order path never ran). Daily loss/trade-count controls remain absent. Restart-safe ownership reconstruction (open-position inventory) and the persistent consumed-event store are both implemented (D005, D006) and pass compile/shadow/deterministic-test evidence, but neither has been exercised against a real order submission — see BACKTEST_LOG.md 2026-07-26 entry. Order/deal history reconstruction remains absent per KNOWN_ISSUES.md.

The branch is an implementation milestone with real compile and shadow-test evidence behind it now, but it is still not production authorization. See BACKTEST_LOG.md for full evidence.

## Gate 8 — Account-mode-aware, magic-safe position ownership (D005, 2026-07-25 second pass)

- **Compile: PASS.** `Test_MSZZ_Ownership.mq5`, `PositionOwnership.mqh`, `PositionOwnershipPolicy.mqh`, and the EA (version `0.310`) compile with 0 errors on isolated MetaEditor build 6061. EA carries the same single reviewed/accepted Market-version warning as before (unrelated to ownership).
- **Deterministic ownership policy test: PASS.** 24/24 assertions, `failures=0` — magic classification (owned/manual/foreign), hedging coexistence, netting/exchange foreign-exposure blocking, one-owned-position limit (including that manual/foreign exposure never triggers it), opposite-ticket collection (excludes manual, foreign, same-direction, unknown-direction, no duplicates), empty-input determinism, and nonempty failure reasons on every rejection path.
- **Live inventory diagnostic (read-only): PASS.** On the isolated demo account (Coinexx-Demo 870012): `ACCOUNT_MARGIN_MODE` raw value correctly resolves to `HEDGING` (matches the terminal's own connection log), ownership snapshot valid, zero positions of every kind (a valid empty-inventory baseline), execution allowed.
- **Shadow Strategy Tester regression: PASS**, both the short window (2026.07.20–2026.07.24) and the previously-validated long window (2026.07.01–2026.07.24): zero orders/deals/trades in both, account mode logged as `HEDGING` at init, zero init failures, zero position-selection errors, candidate/cluster counts identical to the pre-ownership baseline (431 candidates / 178 clusters on the long window), all cluster IDs `MSZZC1`-prefixed with zero duplicates.
- **Regression (determinism/clusters/parity): PASS, no change.** All three re-ran clean on hash-identical source to the prior verified pass.
- **Not verified this pass** (see KNOWN_ISSUES.md): actual close-by-ticket execution against a real open position (no positions were created, per instruction); netting/exchange account modes were validated only via deterministic unit tests, not a real netting/exchange broker account (none available); `owned_longs`/`owned_shorts`/volume totals and same-symbol/different-symbol exclusion are implemented in `CMSZZPositionOwnership::Refresh()` but only exercisable with live non-zero position state, which did not exist during this pass — verified instead by source review (every `MSZZPositionRecord` field is set explicitly, no reliance on implicit struct defaults) and the read-only inventory diagnostic's zero-position baseline.