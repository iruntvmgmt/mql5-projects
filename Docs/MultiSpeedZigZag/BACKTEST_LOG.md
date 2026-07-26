# Backtest and Compile Evidence Log

This file is append-only. Add new dated entries; do not rewrite prior evidence.

---

## 2026-07-26 (second entry) — Atomic execution-intent store (D007), Phase 1 of a 17-phase request

### Context and scope decision

A single instruction requested, in one pass: an atomic/versioned execution-intent store, broker order/deal/position reconciliation, a full execution state machine, protection verification, risk sizing, margin preflight, account safeguards, stale-signal controls, a complete regression pass, extended shadow regression, fault injection across ~19 scenarios, a demo-readiness gate, and — if that gate passed — an actual controlled order submission against the isolated demo account (with a restart-with-active-position test and a close-by-ticket test), explicitly authorized to "abuse the demo account as intended."

**Only Phase 1 (the intent store itself) was implemented.** See `HANDOFF.md`'s "Scope decision, 2026-07-26" for the full reasoning: each remaining phase is independently comparable in scope to a full prior decision cycle (D004/D005/D006), several are materially larger, and compressing all of them into one pass — then firing a real order at a real broker connection on top of an unvalidated risk/margin/safeguard/reconciliation stack — would have contradicted the incremental, evidence-before-progress discipline this branch has used throughout. **No live-execution gates were opened. No order, demo or otherwise, was placed or attempted.**

Repo state before starting: `git fetch github` + `git log --oneline --left-right --graph feature/mszz-standalone-suite...github/feature/mszz-standalone-suite` showed zero divergence at `3d76ca7` (matching the expected head exactly). No pull was needed. QuantBeast's uncommitted `main`-branch state was preserved via `git stash` before switching branches, as in every prior pass.

### Files created

- `Include/MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh`
- `Tests/MultiSpeedZigZag/Test_MSZZ_IntentStore.mq5`

No existing file was modified in this pass (D007 is additive-only; nothing includes the new header yet).

### Compile results

| File | Live tree (build 6033) | Isolated instance (build 6061) |
|---|---|---|
| `Include/MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh` | compiles as a dependency; no standalone script | — |
| `Tests/MultiSpeedZigZag/Test_MSZZ_IntentStore.mq5` | 0 errors, 0 warnings | 0 errors, 0 warnings |

First compile attempt (via a throwaway smoke-test script) surfaced 18 real errors, all from the same root cause: MQL5's generic `ArrayCopy(T&[],const T&[])` template and whole-array `=` assignment both reject struct arrays containing `string` members (`error 368: structures or classes containing objects are not allowed`), even though single-struct assignment with strings (`a = b;` for one instance) works fine and is used throughout this codebase already. Fixed by adding explicit `CopyIntents()`/`CopyStrings()` helpers that copy element-by-element via `ArrayResize` + a loop, and using them everywhere an array-level copy was needed (`Load()`'s primary/backup assignment, and the pre-mutation snapshot/rollback in `CreateIntent()`/`UpdateIntent()`). Recompiled clean.

SHA-256 hash-verified identical between live tree and isolated staged copies:
- `ExecutionIntentStore.mqh`: `edeb6496a36ea4c6f8eb6c3d0f045f9510f8b7bb07dbda88e5875f5ddc505844`
- `Test_MSZZ_IntentStore.mq5`: `a57346d4d411e659a2bc2395d327cb2d5e166b405ca48425c61497d0a087ee1e`

### Test results — 52/52 assertions PASS, `failures=0`, on first real execution

Run via `[StartUp] Script=MultiSpeedZigZagTests\Test_MSZZ_IntentStore` in the isolated instance. Scenarios (all PASS):

1. **Round trip / multiple records**: configure, load-when-empty, create two records, find-by-id, exact field recovery.
2. **Duplicate intent rejection**: a second `CreateIntent()` with the same `intent_id` is rejected; store still holds exactly one record.
3. **Temp-write failure + rollback**: test harness opens the `.tmp` file exclusively (no share flags) before calling `CreateIntent()`; the store's own attempt to open the same file for writing fails, `CreateIntent()` returns `false`, and `Count()` is unchanged (in-memory rollback proven). Releasing the block allows the identical call to succeed.
4. **Primary-replacement failure + rollback**: same technique against the `.dat` primary file (which must exist first) — the backup-rotation `FileMove()` fails while the primary is held open elsewhere, the whole save fails, and rollback is proven the same way.
5. **Truncated temp file**: raw-writing garbage to the `.tmp` path does not corrupt the store — the next legitimate `CreateIntent()` overwrites it and succeeds normally (the store never trusts stale temp content; it always writes fresh).
6. **Truncated primary file**: a primary file cut to half its length fails `Load()`'s validation and (with no valid backup available in this scenario) `Load()` returns `false` with zero records exposed — fail closed, not a partial read.
7. **Corrupt checksum**: a fixture record's `instance_id` field is mutated by exactly one character (same length, so the length-prefix stays structurally valid) directly in the raw file; `Load()` fails closed because the recomputed checksum no longer matches — proving checksum validation is independent of structural parseability.
8. **Backup recovery, both directions**: after two saves (backup = 1-record generation, primary = 2-record generation), corrupting the primary recovers cleanly from backup (to the *older*, 1-record state — the correct and expected two-generation behavior); corrupting the backup instead has no effect, since a valid primary is tried first and is sufficient.
9. **Schema-version preservation**: a hand-crafted, checksum-valid record with `schema_version=99` (this build understands only version 1) loads successfully, is not exposed via `Count()`/`FindById()`, is tracked via `UnknownRecordCount()==1`, and survives a subsequent unrelated save verbatim (confirmed by raw-reading the file afterward and finding the exact original unknown-schema line still present, byte-for-byte).
10. **Long IDs**: a 500-character cluster/origin ID round-trips exactly.
11. **Delimiter characters**: a record with `|` and `:` embedded throughout `cluster_id`, `origin_id`, `instance_id`, and `broker_result_text` round-trips every field exactly (reusing the D004-proven length-prefix technique, which is why this passed cleanly on the first attempt).
12. **Restart reload**: one store instance creates a record and explicitly `Close()`s (releasing its exclusivity lock); a second, independent instance then `Configure()`s and `Load()`s successfully and recovers the exact record.
13. **Exclusivity + filename separation**: a second store instance cannot `Configure()` against the same symbol/timeframe/magic while a first instance holds the lock (and can once the first releases it); two instances configured with *different* magic numbers never see each other's records and produce distinct filenames.
14. **Deterministic serialization**: a no-op `UpdateIntent()` with identical field values produces a byte-for-byte identical raw file line to the original save.

### Regression

All other MSZZ compile targets (`Test_MSZZ_Ownership.mq5`, `Test_MSZZ_Determinism.mq5`, `Test_MSZZ_Clusters.mq5`, `Export_MSZZ_Parity.mq5`, `MultiSpeedZigZagEA.mq5`) recompile clean in the isolated instance — 0 errors, and the EA's single pre-existing reviewed warning, unchanged. Not re-executed at runtime, since no source they depend on changed (hash-verified in the prior pass and untouched since).

### Intent-store guarantees (see D007 for full detail)

- A `CreateIntent`/`UpdateIntent` call either fully succeeds (in-memory and on-disk state agree, verified by reopening and re-checksumming the primary file before returning `true`) or fully fails (in-memory state rolled back to its pre-call snapshot, on-disk state untouched or, in the worst case documented below, containing data the caller correctly does not trust because it never received `true`).
- **Exact atomicity limit, stated plainly**: this is a two-generation recoverable protocol, not proven atomic filesystem semantics. If the process is killed between the primary→backup rotation and the temp→primary promotion, the backup ends up equal to the previous primary and `Load()`'s fallback path recovers to that last-known-good state, at the cost of the single in-flight update. If the process is killed after the temp→primary move completes but before `SaveAll()` returns, the caller receives `false` (or never returns) even though the data is in fact durable — a conservative failure direction (report failure when it actually succeeded), not a dangerous one.
- Exclusivity is enforced via a real MQL5 file-sharing lock (`FileOpen` with no share flags on a dedicated `.lock` file), not an assumption.

### Intent-store limitations (explicitly out of scope for D007/Phase 1)

- Not wired into `MultiSpeedZigZagEA.mq5`. `ExecuteCluster()` still uses `CMSZZEventStore` exactly as D006 left it.
- No reconciliation against live broker order/deal/position history (Phase 2).
- No execution state machine driving the `execution_state` field through real transitions (Phase 3).
- ulong ticket fields round-trip via `StringToInteger`→`(ulong)` cast, which is correct for real-world MT5 ticket values (far below `LONG_MAX`) but would misparse a ulong value above `LONG_MAX` — a theoretical, not practical, limitation given actual broker ticket ranges.

### Safety confirmation

- No live-execution gates opened at any point.
- No order, demo or otherwise, placed or attempted.
- Live MT5 installation and its process (PID 66709, confirmed unchanged before and after every action) never touched.
- No second clone or parallel worktree; QuantBeast's `main`-branch state preserved via `git stash`/`git stash pop`.

### Not done / explicitly out of scope this pass

Phases 2 through 17 of the requesting instruction in full: reconciliation, execution state machine, protection verification and repair, risk sizing, margin/exposure preflight, account safeguards (daily loss, drawdown, kill switch, cooldowns), stale-signal/expiry re-validation, extended fault injection across the full stack, the demo-readiness gate, and controlled demo execution (including restart-with-active-position and close-by-ticket tests).

## 2026-07-26 — Idempotent execution-intent persistence (D006)

Designed and implemented directly in the live Wine MQL5 tree (no upstream pull this pass — branch was already at `e4a4a2e`, confirmed via `git log --oneline --left-right --graph feature/mszz-standalone-suite...github/feature/mszz-standalone-suite` showing no divergence before starting). Per D003, `DECISION_LOG.md` D006 was written before any source change.

### Change

`Experts/MultiSpeedZigZagEA.mq5::ExecuteCluster()`: moved `ConsumeEvent(persistence_id)` from after a successful `g_trade.Buy()`/`Sell()` (warning-only on failure) to immediately before order submission (fail-closed: `REJECT_INTENT_PERSISTENCE`, order never attempted, if the write fails). No new files, no new inputs, no change to `CMSZZEventStore`.

### Compile results

| File | Live tree (build 6033) | Isolated instance (build 6061) |
|---|---|---|
| `Experts/MultiSpeedZigZagEA.mq5` | 0 errors, 1 warning (reviewed/accepted, unrelated) | 0 errors, 1 warning (same) |

SHA-256 hash-verified identical between live tree and isolated staged copy: `88ce74a5e3439335aee3b15b553fab26cf00f14d4c56d224759d5abc5984d5b6`.

### Shadow regression (long window, 2026.07.01–2026.07.24, same config as prior passes)

Result: History Quality 100%, Bars 4645, **Total Trades: 0, Total Deals: 0**. Signal journal: 431 `RAW_CANDIDATE` + 178 `SHADOW` — identical to every prior pass's counts. Consumed-event file: 178 entries, matching exactly. Zero `REJECT_INTENT_PERSISTENCE` occurrences (correct — shadow mode returns before reaching the live-execution path this change touches, so the new code is not exercised by design in any of this pass's runs).

### Regression: ownership, determinism, clusters, parity exporter

- `Test_MSZZ_Ownership`: 24/24 assertions PASS, `failures=0` (unchanged from prior pass — this batch didn't touch ownership source).
- `Test_MSZZ_Determinism`: `TEST PASS: deterministic rebuild`.
- `Test_MSZZ_Clusters`: 22/22 assertions PASS, `failures=0`.
- `Export_MSZZ_Parity` (XAUUSD M5, 1000 bars, default ATR settings): 966 bar rows, 76 pivot rows, 192 candidate rows, 70 cluster rows — identical to every prior verified-clean pass. Zero duplicates, zero malformed/empty IDs, all cluster IDs `MSZZC1`-prefixed.

### What this pass does and does not prove

Proves: the new persist-before-submit ordering compiles, does not alter shadow-mode behavior in any observable way (candidate/cluster generation, journaling, zero-order guarantee), and does not regress any other subsystem. Does **not** prove: correct behavior of the persist-first ordering during an actual order submission attempt, since all three live-execution gates (`InpShadowOnly=true`, `InpAllowLiveExecution=false`, `InpAcknowledgeRisk=false`) remained closed throughout, as in every prior pass on this branch. The safety property (a persistence failure can never be followed by an order attempt) is guaranteed by the code's structure (the `return false` on a failed `ConsumeEvent()` occurs strictly before the `g_trade.Buy()`/`Sell()` call), not by observed runtime evidence of a real order.

### Safety confirmation

- All three live-execution gates closed in every run; zero orders/deals/trades throughout.
- Live MT5 installation and its process (PID 66709, confirmed unchanged before and after every action) were never touched.
- No second clone or parallel worktree; QuantBeast's `main`-branch state preserved via `git stash`/`git stash pop` around this session's branch switch.

### Not done / explicitly out of scope this pass

- Full order/deal history reconstruction (querying `HistorySelect`/`HistoryDealGetTicket`) — a separate, larger feature, not started.
- Real order submission through the new persist-first path (requires live-execution gates open, which remain closed by design).

## 2026-07-25 (third pass) — Account-mode and position ownership subsystem (D005)

Pulled `feature/mszz-standalone-suite` from `31f13b0` to `73951d9` (fast-forward, no divergence) into the live Wine MQL5 tree via `git pull --ff-only github feature/mszz-standalone-suite`. `origin` remote does not exist on this repo (removed per `AGENTS.md`); `github` is the only active remote.

### Source audit

Reviewed `PositionOwnership.mqh`, `PositionOwnershipPolicy.mqh`, and the EA's ownership integration against the full hazard checklist (local references to array elements, `ZeroMemory` on strings, uninitialized scalar fields, `PositionGetTicket`/`PositionSelectByTicket` sequencing, `%I64u` formatting, iteration-invalidation while closing, mixed-symbol contamination, refresh-after-close ordering, one-position-limit ordering relative to opposite-closure, etc.). No compile-blocking or safety defects found — this batch was implemented cleanly. Confirmed via repo-wide grep: zero remaining `PositionSelect(_Symbol)`/`PositionClose(_Symbol)` calls, zero `ZeroMemory` calls anywhere in the MSZZ tree.

Two genuine test-coverage gaps were found against the requested ownership-test assertion list and closed (see Fix below): empty-input determinism and nonempty-failure-reason coverage were both addable as pure deterministic tests and were missing. Three further requested items (different-symbol exclusion, owned long/short counts, owned volume totals) are implemented in the live-querying `CMSZZPositionOwnership::Refresh()`, not the pure policy layer under deterministic test — they require live non-zero position state to exercise meaningfully, which this pass intentionally never created (zero orders throughout). These are documented as an open verification gap in `KNOWN_ISSUES.md`, not fabricated as false-positive tests.

One non-safety observation logged in `KNOWN_ISSUES.md`: `CloseOwnedOpposite`'s loop returns on the first failing ticket close without attempting remaining tickets, and its failure reason doesn't distinguish "nothing closed" from "partially closed." This is fail-safe (never touches foreign/manual tickets, EA correctly aborts the new entry) and was not changed, since no concrete defect exists — only a diagnostic-clarity nuance.

### Fix: closed two ownership-test coverage gaps

Added 9 assertions to `Tests/MultiSpeedZigZag/Test_MSZZ_Ownership.mq5`:
- empty input to `CollectOppositeOwnedTickets` produces deterministic zero counts;
- an explicit no-duplicate-ticket scan across 5 distinct owned-opposite records;
- nonempty failure reasons on 6 distinct rejection paths (unsupported mode, invalid snapshot, terminal selection error, netting foreign-exposure block, exchange manual-exposure block, one-owned-position limit).

Total: 24 assertions (was 15).

### Hash verification (git tree vs. isolated staged copies, SHA-256)

| File | SHA-256 |
|---|---|
| `Experts/MultiSpeedZigZagEA.mq5` | `b8710f9a2e7fd19482524c0826b93f0f589e2b5c5d0bd3bb83f2a0bc4a16f307` |
| `Include/.../Execution/PositionOwnership.mqh` | `f20834a2a6a7e4f464eb65cb52aec8b0d6b0a10dea38760eea94c8f0e97cf877` |
| `Include/.../Execution/PositionOwnershipPolicy.mqh` | `17d25b7da34891f286f50282ccc4c9ee09e019d405d4de5a9ec64586b1c39ed2` |
| `Include/.../Execution/ExecutionGuard.mqh` | `2f7968433ea2f7de6f41b87734ee420538e7880870f1c481603540aa8796f7a6` |
| `Include/.../Execution/EventStore.mqh` | `c021ddb20e06ab8cb628329ccb5bb4752985e99c2ff35af1959d47c7420f9aed` |
| `Include/.../Core/Types.mqh` | `1e2bbff2416080548fa4efc78c6006384d8de797d7fb07be872ed61451d99714` |
| `Include/.../Core/TripleZigZagEngine.mqh` | `6d1649f0bffc9e4f00781ac7037317bb7dd8924d7978e3faf1e8873fa75c70d7` |
| `Include/.../Strategies/StrategySuite.mqh` | `d436c62a656a963580995aa70e44dcdc292659fdea90babe31fc3e2de1f8caf3` |
| `Include/.../Arbitration/OpportunityClusterEngine.mqh` | `4e308e22778603c22896bae539a01c9c7eb8f7df5a167652b4d3b490a2243f98` |
| `Include/.../Diagnostics/ParityExporter.mqh` | `712b96cae2b7d833f0441c14bb2dcc737734b69cf012a561e51192d9ef453329` |
| `Tests/.../Test_MSZZ_Ownership.mq5` | `e93544f8671d554706b4331e5df831e9407b7c9d10d63ca7be3f810007aff482` |
| `Tests/.../Test_MSZZ_Determinism.mq5` | `1868f90b8c4b889ee8eb11ebba0766113f40d25160790dd0d1d456e73fd51650` |
| `Tests/.../Test_MSZZ_Clusters.mq5` | `80d9735b27399866dc2412d1152ba1252905eaffabc92c97a861466c96c802d9` |
| `Tests/.../Export_MSZZ_Parity.mq5` | `dd03716ec9688e12a3eb9b7f749816c645a4fd2e9dcfaead3e68b7ff1f769277` |

14/14 match between the live git tree and the isolated `~/MT5-MSZZ-TEST` staged copies. (Hashes recorded before the two-gap test fix above; the fix was made in the git tree, recompiled, and re-synced — see compile results below, which reflect the post-fix source.)

### Compile results (isolated MetaEditor build 6061)

| File | Result |
|---|---|
| `Tests/MultiSpeedZigZag/Test_MSZZ_Ownership.mq5` | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5` | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5` | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Export_MSZZ_Parity.mq5` | 0 errors, 0 warnings |
| `Experts/MultiSpeedZigZagEA.mq5` | 0 errors, 1 warning (reviewed/accepted — same Market-version warning as prior passes, unrelated to ownership) |

Compile command pattern: `wine start /Unix metaeditor64.exe /portable /compile:"<path>" /log`, run from `~/MT5-MSZZ-TEST`. Live-tree sanity compiles (build 6033) also ran clean before syncing, same results.

### Ownership unit test (`Test_MSZZ_Ownership.mq5`)

All 24 assertions PASS, `failures=0`:
```
PASS: matching positive magic is owned
PASS: zero magic is manual
PASS: different nonzero magic is foreign
PASS: hedging mode allows foreign/manual coexistence when no owned position exists
PASS: netting mode blocks foreign symbol exposure
PASS: exchange mode blocks manual symbol exposure
PASS: one-owned-position policy blocks second owned position
PASS: disabled owned-position limit allows additional owned position
PASS: unsupported account mode fails closed
PASS: invalid snapshot fails closed
PASS: terminal selection error fails closed
PASS: only two owned short tickets collected for desired long
PASS: manual, foreign, same-direction, and unknown-direction records excluded
PASS: only owned long ticket collected for desired short
PASS: no tickets collected for no desired direction
PASS: empty input produces deterministic zero counts
PASS: no duplicate ticket is returned across distinct owned opposite records
PASS: unsupported account mode leaves a nonempty failure reason
PASS: invalid snapshot leaves a nonempty failure reason
PASS: terminal selection error leaves a nonempty failure reason
PASS: netting foreign-exposure block leaves a nonempty failure reason
PASS: exchange manual-exposure block leaves a nonempty failure reason
PASS: one-owned-position limit block leaves a nonempty failure reason
MSZZ ownership test complete failures=0
```

### Live read-only inventory diagnostic (`MSZZ_Inventory_Diagnostic.mq5`, isolated demo account)

```
INVENTORY raw_account_margin_mode=2 detected_mode=HEDGING
INVENTORY refresh_ok=true valid=true error_reason=
INVENTORY total_terminal_positions=0 symbol_total=0 owned=0 manual=0 foreign=0 owned_long=0 owned_short=0 owned_long_vol=0.00 owned_short_vol=0.00
INVENTORY execution_allowed_for_account_mode=true reason=
```

Confirms `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` (raw value 2 in this MQL5 build) correctly resolves to the `HEDGING` text label, matching the terminal's own "trading has been enabled, demo account - hedging mode" connection log line. Zero positions of every kind is a valid, expected empty-inventory baseline — no positions were created during this pass by instruction.

### Shadow Strategy Tester regression

Symbol: XAUUSD. Inputs: `InpShadowOnly=true`, `InpAllowLiveExecution=false`, `InpAcknowledgeRisk=false`, `InpMagic=26072501`, `InpOneOwnedPositionPerSymbol=true`, `InpExitOwnedOpposite=true` (renamed from `InpOnePositionPerSymbol`/`InpExitOnOpposite` in this batch — configs from the prior pass were updated to match). Model=2 (Open prices only), headless (not visual — same disclosed substitution as the prior pass).

**Short window (2026.07.20–2026.07.24):** History Quality 100%, Bars 1104, **Total Trades: 0, Total Deals: 0**. Signal journal: 113 `RAW_CANDIDATE` + 46 `SHADOW`, all 46 cluster IDs `MSZZC1`-prefixed, zero duplicates, 46 consumed-event entries matching exactly.

**Long window (2026.07.01–2026.07.24, previously validated interval):** History Quality 100%, Bars 4645, **Total Trades: 0, Total Deals: 0**. Signal journal: 431 `RAW_CANDIDATE` + 178 `SHADOW` — identical counts to the pre-ownership baseline from the prior pass, confirming the ownership subsystem is purely additive to the execution layer and does not alter candidate/cluster generation. All 178 cluster IDs `MSZZC1`-prefixed, zero duplicates, 178 consumed-event entries matching exactly.

Both runs' Expert log confirms at init: `MSZZ OWNERSHIP REFRESHED mode=HEDGING symbol_total=0 owned=0 long=0 short=0 manual=0 foreign=0 err=` and `MSZZ account mode=HEDGING event store loaded count=0`. Zero `INIT_FAILED`/initialization-failure/position-selection-error occurrences in either run's log. Clean deinit (`reason=1`, normal shutdown) in both.

Note on log analysis method: the Tester agent's own log file (`Tester/Agent-127.0.0.1-3000/logs/<date>.log`) accumulates across multiple separate sessions run on the same calendar day rather than resetting per invocation (unlike the agent's `MQL5/Files/` sandbox, which does reset per invocation — see the prior pass's restart-test methodology note). Each run's evidence was isolated by locating that run's unique init timestamp line before analyzing counts, to avoid conflating current-run output with stale entries from earlier sessions.

### Regression: determinism, clusters, parity exporter

- `Test_MSZZ_Determinism`: `TEST PASS: deterministic rebuild`.
- `Test_MSZZ_Clusters`: 22/22 assertions PASS, `failures=0` (includes the D004 cluster-ID encoding tests from the prior pass).
- `Export_MSZZ_Parity` (XAUUSD M5, 1000 bars, default ATR settings): 966 bar rows, 76 pivot rows, 192 candidate rows, 70 cluster rows — identical row counts to the prior verified-clean pass. Zero duplicate cluster IDs, zero duplicate pivot rows, zero empty/malformed pivot IDs, zero bad speed values, zero missing candidate origin/event IDs, all cluster IDs `MSZZC1`-prefixed.

### Safety confirmation

- `InpShadowOnly=true`, `InpAllowLiveExecution=false`, `InpAcknowledgeRisk=false` in every run; Algo Trading confirmed disabled at the terminal level (verified directly in a prior pass, unchanged this pass).
- Isolated demo account only (Coinexx-Demo 870012); zero orders/deals/trades across both shadow windows.
- Live MT5 installation and its process (PID 66709, confirmed unchanged before and after every action in this pass) were never touched, reconfigured, or restarted.
- No second clone or parallel worktree was created; all work was done directly in the one true Wine MQL5 working tree, with QuantBeast's uncommitted `main`-branch state preserved via `git stash` before switching branches and restored via `git stash pop` at the end of the session.
- No live/demo positions or orders were created at any point in this pass.

### Not done / explicitly out of scope this pass

- Close-by-ticket execution against a real open position (would require creating a live/demo position, which this pass explicitly does not do).
- Real netting or exchange broker account testing (none available; deterministic unit-test coverage only, documented as such).
- Order/deal history reconstruction, cluster-to-position restart reconstruction, management-state reconstruction.
- Pine-side parity, trendline geometry resolution, risk sizing, margin preflight, daily limits, reserved strategies (all unchanged from the prior pass).

## 2026-07-25 (second pass) — Cluster-ID encoding fix

Implements DECISION_LOG.md D004. See KNOWN_ISSUES.md and OPPORTUNITY_CLUSTERING.md/PARITY_EXPORT_SCHEMA.md for the format itself. This entry records only compile/test evidence for the fix.

### Compile results (live tree build 6033, isolated instance build 6061 — identical on both)

| File | Result |
|---|---|
| `Include/MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh` | compiles as a dependency of the three files below; no standalone script |
| `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5` | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Export_MSZZ_Parity.mq5` | 0 errors, 0 warnings |
| `Experts/MultiSpeedZigZagEA.mq5` | 0 errors, 1 warning (same reviewed/accepted Market-version warning as before, unrelated to this change) |

One test-writing mistake caught and fixed before commit: an assertion asserted the encoded cluster ID contains exactly 5 total `|` characters, which is wrong whenever `origin_id` itself contains `|` (the exact case the fix targets) — the origin ID's own pipe characters are still physically present in the string, they're just no longer load-bearing for parsing. Replaced with a correct assertion that a naive split-on-`|` would produce far more than the old format's 6 tokens, proving the ambiguity this format fixes, while the round-trip assertion immediately above it proves `DecodeClusterId` still recovers the exact original value.

### Cluster unit test (`Test_MSZZ_Clusters.mq5`), isolated instance, real XAUUSD M5 history

All 22 assertions PASS, `failures=0`:
```
PASS: origin ID containing '|' round-trips exactly
PASS: origin ID containing '|' preserves symbol/timeframe/direction/origin_type
PASS: origin ID containing ':' round-trips exactly
PASS: real-world nested pipe-delimited origin ID round-trips exactly
PASS: naive split-on-'|' would be ambiguous, confirming length-prefix decoding is required
PASS: empty origin ID round-trips to an empty string
PASS: empty string is not a valid cluster ID
PASS: legacy unversioned format is rejected, not silently accepted as new format
PASS: declared length exceeding available data is rejected
PASS: non-digit length prefix is rejected
PASS: trailing garbage after the declared final-field length is rejected
PASS: 500-character origin ID round-trips exactly
PASS: identical inputs encode to identical output every time
PASS: distinct origin IDs produce distinct cluster IDs
PASS: distinct directions with the same origin ID produce distinct cluster IDs
PASS: three related candidates become one cluster and independent origin stays separate
PASS: support count preserved
PASS: specific nested pullback owns cluster
PASS: evidence mask merges structure evidence
PASS: stop disagreement measured
PASS: stable cluster ID created
PASS: best cluster selected
PASS: stronger related cluster selected
MSZZ cluster test complete failures=0
```

### Parity export re-run (`Export_MSZZ_Parity.mq5`, XAUUSD M5, 1000 bars, default ATR settings)

`clusters.csv`: 70 data rows (same as the pre-fix run — clustering behavior is unchanged, only the ID string format changed). Verified:
- Every `cluster_id` starts with the literal `MSZZC1|` (0 rows failed this check).
- Zero duplicate `cluster_id` values (70 unique out of 70 rows).
- Spot-checked example: `MSZZC1|6:XAUUSD|1:5|2:-1|1:2|67:BO|XAUUSD|5|1|S|1784639100|MSZZ|XAUUSD|5|1|-1|1784637600|1784638200` — the declared length `67` is the exact character count of the trailing origin ID, which itself contains 11 `|` characters that a naive parser would have misread as delimiters under the old format.

### Shadow Strategy Tester regression check (short window, 2026.07.20–2026.07.24, `InpShadowOnly=true`)

Result: History Quality 100%, Bars 1104, **Total Trades: 0, Total Deals: 0** — zero orders placed, consistent with the full 24-day run from the first pass. Spot-checked the signal journal: all `SHADOW`-status rows carry the new `MSZZC1|`-prefixed cluster ID; 0 rows failed that check.

### Not re-run this pass (unchanged by this fix, already covered by the first pass's evidence above)

`Test_MSZZ_Determinism`, the full 24-day shadow run, and the `EventStore` restart-persistence probe were not re-run, since this fix does not touch the ZigZag engine, the strategy suite's candidate generation, the EA's execution path, or the event store — only how a cluster's identity string is encoded.

---

## 2026-07-25 — Compile, repair, and shadow-test pass

### Environment

- Live tree (source of truth, git): `~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5`, branch `feature/mszz-standalone-suite`.
- Isolated test instance (binaries + MSZZ source only, no live credentials/profiles/QuantBeast state): `~/MT5-MSZZ-TEST`, run in portable mode (`terminal64.exe /portable`).
- Isolated test account: Coinexx-Demo login `870012` (hedging mode), self-registered fresh for this session — not the live account (`871221`) used elsewhere in this repo.
- MetaEditor build: `6033` (live tree compiles) / `6061` (isolated instance — auto-updated itself on relaunch mid-session).
- Compile method: `wine start /Unix metaeditor64.exe [/portable] /compile:"<path>" /log` (the direct invocation pattern is documented as unreliable in `AGENTS.md`; the `start /Unix` fallback worked reliably throughout).
- Runtime method: MT5 `[StartUp]`/`[Tester]` config files passed via `terminal64.exe /portable /config:<file>.ini`, one script/run per launch (the running single instance silently ignores a second `/config` signal, so each run required a clean stop of the isolated PID and a fresh relaunch — the live terminal (a separate PID, confirmed distinct before and after every action in this session) was never touched).

### Compile results

| File | Live tree (build 6033) | Isolated instance (build 6061) |
|---|---|---|
| `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5` | 0 errors, 0 warnings | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5` | 0 errors, 0 warnings (after fix) | 0 errors, 0 warnings |
| `Tests/MultiSpeedZigZag/Export_MSZZ_Parity.mq5` | 0 errors, 0 warnings | 0 errors, 0 warnings |
| `Experts/MultiSpeedZigZagEA.mq5` | 0 errors, 1 warning (reviewed/accepted) | 0 errors, 1 warning (reviewed/accepted) |

First compile attempt of `Test_MSZZ_Clusters.mq5` failed with:
```
OpportunityClusterEngine.mqh(100,33) : error 229: reference cannot used
Result: 1 errors, 0 warnings
```
Fixed by replacing the illegal local reference (`MSZZOpportunityCluster &cluster=clusters[target];`) with direct `clusters[target]` indexing. Recompiled clean.

EA warning (both builds):
```
MultiSpeedZigZagEA.mq5(5,11) : warning 68: version '0.300' is incompatible with MQL5 Market, must be xxx.yyy
```
Confirmed cause empirically: major version 0 is rejected for Market publishing; `"1.00"` compiles with 0 warnings, `"0.300"` does not. Kept `0.300` (the branch's real documented milestone number) since this EA is not published to Market. **Do not describe this build as zero-warning** — it is zero-error, one warning reviewed and accepted.

### Source audit fixes (see KNOWN_ISSUES.md for full detail)

1. Unsafe `ZeroMemory()` on structs containing `string` members, 5 sites — removed/replaced.
2. That fix's first attempt (`MSZZSpeedSnapshot blank; m_snapshot[s]=blank;`) left `ResetSnapshot` relying on unverified full zero-initialization of plain scalar fields. Confirmed broken via runtime evidence (see Parity export below) and replaced with explicit field-by-field reset (`BlankPivot` helper + explicit assignment of every `MSZZSpeedSnapshot` field).

### Gate 2 — Determinism

Command: `[StartUp] Script=MultiSpeedZigZagTests\Test_MSZZ_Determinism, Symbol=XAUUSD, Period=M5` (isolated instance, real broker history).

Output: `TEST PASS: deterministic rebuild`

### Gate 5 — Cluster unit test

Command: `[StartUp] Script=MultiSpeedZigZagTests\Test_MSZZ_Clusters, Symbol=XAUUSD, Period=M5`

Output (all 8 assertions):
```
PASS: three related candidates become one cluster and independent origin stays separate
PASS: support count preserved
PASS: specific nested pullback owns cluster
PASS: evidence mask merges structure evidence
PASS: stop disagreement measured
PASS: stable cluster ID created
PASS: best cluster selected
PASS: stronger related cluster selected
MSZZ cluster test complete failures=0
```

### Gate 4 — Parity export

Command: `[StartUp] Script=MultiSpeedZigZagTests\Export_MSZZ_Parity, Symbol=XAUUSD, Period=M5` (script defaults: 1000 bars, default ATR settings).

Output location: `MQL5/Files/MSZZ_PARITY_manual_XAUUSD_5_1784937000_*.csv` (isolated instance).

Row counts (after fix): manifest 17, bars 967 (966 data rows), pivots 76, candidates 192, clusters 71, snapshots 2899.

First run (before the `ResetSnapshot` fix) produced a corrupted row immediately after the pivots.csv header: `MQL5;21048726;0;0;0;0;0.00;UNKNOWN;` — impossible speed value, empty pivot_id, despite `WritePivot`'s guard against empty IDs. This is what surfaced the uninitialized-field defect above. Re-ran after the fix: 76 clean pivot rows, zero garbage values, zero empty IDs, confirmed via full-column scan.

Inspected per the runbook's checklist:
- Duplicate pivot rows: none found.
- Missing origin IDs / evidence masks: none found.
- **Malformed cluster IDs: confirmed present.** Every one of the 70 cluster rows has 17 `|` characters in `cluster_id` (documented format implies 5). Left as a known issue, not fixed — see KNOWN_ISSUES.md.
- Repeated breakout events: not separately re-verified this pass beyond the candidate/cluster dedup checks below.
- Forming-bar timestamps: none found (loop bound excludes the final/forming bar).
- Empty or invalid stop values: none found on inspection.

### Gate 6 — Shadow Strategy Tester run

Config: `[Tester] Expert=MultiSpeedZigZagEA, Symbol=XAUUSD, Period=M5, Model=2 (Open prices only — chosen for a strategy that only acts on closed bars), FromDate=2026.07.01, ToDate=2026.07.24, Visual=0`. Inputs: `InpShadowOnly=true`, `InpAllowLiveExecution=false`, `InpAcknowledgeRisk=false`, all else default.

**Visual mode was not used** — a headless run was substituted for reliable automated evidence capture (no screen-capture tooling was available this session to meaningfully "watch" a visual run). This substitution was disclosed to the user before the run.

Result (`MSZZ_Shadow_Report.htm`): History Quality 100%, Bars 4645, **Total Trades: 0, Total Deals: 0**, Orders table empty except the initial balance deposit. Zero broker orders placed, confirmed.

Signal journal (`Tester/Agent-127.0.0.1-3000/MQL5/Files/MSZZ_SignalJournal.csv`): 610 rows = 431 `RAW_CANDIDATE` + 178 `SHADOW` (no `REJECT_*`, `EXECUTED`, or `ORDER_FAILED` rows, consistent with all three live-execution gates being closed throughout). Consumed-event file (`MSZZ_Consumed_XAUUSD_5_26072501.txt`): 178 entries, matching the 178 unique `SHADOW` cluster IDs exactly — zero duplicate cluster IDs shadow-journaled twice.

### Gate 5 (restart) — methodology note and component-level verification

Re-running the identical `[Tester]` config a second time to simulate a restart produced byte-identical output to the first run, and the Expert log showed `MSZZ event store loaded count=0` on **both** runs. This proves the MetaTester Agent sandbox (`Tester/Agent-127.0.0.1-3000/MQL5/Files/`) is reset at the start of each separate `terminal64.exe /config:...` invocation — **two successive Strategy Tester runs cannot be used to test restart-safe deduplication**, and the identical output was a coincidence of deterministic replay over identical history, not evidence of persistence.

Instead, directly tested the `CMSZZEventStore` component's file persistence, which is chart/script-scoped (persists in the terminal's own `MQL5/Files/`, not the Tester sandbox) and therefore does survive a genuine process restart:

1. `MSZZ_EventStore_ProbeWrite.mq5` (fresh process): `RESTARTPROBE mode=write loaded_count=0` → `RESTARTPROBE after_add_count=3`.
2. Isolated instance stopped completely (process terminated, confirmed via `ps`).
3. File confirmed on disk (`MQL5/Files/MSZZ_Consumed_XAUUSD_5_990001.txt`, 3 lines) while the process was fully down.
4. Isolated instance relaunched fresh (new PID). `MSZZ_EventStore_ProbeRead.mq5`: `RESTARTPROBE mode=read loaded_count=3` → `contains_1=true contains_2=true contains_3=true contains_unknown=false`.

This proves the persistence mechanism itself is correct across a real restart. **Still open**: a full end-to-end EA restart test (attach to a live/demo chart, let it consume a real cluster from real elapsed M5 bar-closes, detach/restart, confirm no reprocessing) was not performed — it would require waiting multiple real hours for enough bar-closes and cluster formations, which was not practical within this session.

### Safety confirmation

- `InpShadowOnly=true`, `InpAllowLiveExecution=false`, `InpAcknowledgeRisk=false` in every run.
- Algo Trading confirmed disabled at the terminal level before any test (`TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)=0`, `MQLInfoInteger(MQL_TRADE_ALLOWED)=0`, probed directly).
- Isolated demo account only; zero orders/deals/trades across the entire shadow run.
- Live MT5 installation and its process (PID confirmed unchanged before/after every action) were never touched, reconfigured, or restarted.
- `main` and the live QuantBeast working state were preserved via `git stash` before this session's work began and are not part of this branch's changes.

### Not done / explicitly out of scope this pass

- Pine-side export and cross-platform parity comparison.
- Trendline elapsed-seconds-vs-bar-index geometry resolution.
- Fixing the malformed cluster-ID encoding (needs a DECISION_LOG entry).
- Fixing the netting-account assumption.
- Full end-to-end EA restart-on-chart test.
- Position/order ownership reconstruction, percentage-risk sizing, margin checks, daily limits, kill switches, reserved stateful strategies.
