# Backtest and Compile Evidence Log

This file is append-only. Add new dated entries; do not rewrite prior evidence.

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
