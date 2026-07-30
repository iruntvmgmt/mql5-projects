# D031 Certification Checkpoint — STATUS: ALL GATES PASSED

All seven required gates below were actually run and verified — not
assumed, not fabricated. This supersedes the earlier BLOCKED version of
this file (preserved in git history): the MCP `compile_mql5` bridge tool
remains broken, but the direct Wine CLI route this codebase's own
`AGENTS.md` documents (and which the earlier BLOCKED attempt had not yet
tried) works reliably once the correct completion signal is used.

## Root cause of the earlier BLOCKED status

`mcp__mt5-bridge__compile_mql5` uses the exact invocation pattern
`AGENTS.md`'s "Known MetaEditor compilation issue (2026-07-16)" section
documents as broken: *"The direct `wine metaeditor64.exe /compile:"<path>"`
invocation can silently stop working without any error, log, or `.ex5`
update — the process exits cleanly with code 0 but does nothing."* That is
exactly what was observed. The documented fallback —
`wine start /Unix metaeditor64.exe /compile:"<path>" /log` — worked on the
first real attempt.

A second, separate gotcha was found and worked around during this
checkpoint: for **Tester** (backtest) runs specifically, the GUI
`terminal64.exe` process launched via `/portable /config:` exits almost
immediately after *dispatching* the job — the actual computation continues
in a separate `metatester64.exe` process that must be waited on directly
(by PID, `kill -0`) rather than by watching `terminal64.exe`. Waiting on
the wrong process produced two false "run complete" reads early in this
checkpoint (trade counts of 31 and 151 instead of the true 330) before
this was diagnosed and fixed.

## Gate 1 — Compile: PASS

Both changed source files compile with 0 errors, 0 warnings, in both the
live install tree and the isolated `MT5-MSZZ-TEST` tree used for gates
5-7. Full detail: `compile_summary.csv`.

| File | Errors | Warnings |
|---|---:|---:|
| `MultiSpeedZigZagEA.mq5` | 0 | 0 |
| `Test_MSZZ_D031_SixFamilies.mq5` | 0 | 0 |

## Gate 2 — `Test_MSZZ_D031_SixFamilies.mq5` compiles: PASS

Same evidence as Gate 1.

## Gate 3 — D031 test suite passes: PASS (39/39, after one real bug fixed)

First run: **39 tests, 1 failure**. The failure was in the test fixture
itself, not the production code — `TestSessionSweepReversal`'s expiry
case fed the family 7 identical "still swept" bars; because the same bar
that lets the original setup expire also still satisfies the re-arm
threshold, a *new* setup legitimately re-armed in the same instant, and
the "decisive post-expiry" bar then triggered *that* new setup — proving
nothing about true expiry. Fixed by keeping the loop bars' low above the
re-arm threshold (`Tests/MultiSpeedZigZag/Test_MSZZ_D031_SixFamilies.mq5`,
`TestSessionSweepReversal`, see the comment at the fix site). Recompiled
and reran: **39 tests, 0 failures.**

This is exactly the kind of finding this checkpoint exists to catch, and
it was only found by actually running the suite — the manual review in
the prior (uncompiled) pass could not have caught it.

## Gate 4 — Existing regression suite passes: PASS (32/32 suites, 0 failures)

Every `regress_*.ini` script in `MT5-MSZZ-TEST/` (31 pre-existing suites
plus the new D031 suite) was run against the isolated instance. Full
per-suite detail, timestamps, and exact result lines: `test_summary.csv`.
Verified by reading the raw terminal log directly and matching each
script's own most recent output lines by name — not by trusting a
first-pass automation script's inline capture, which turned out to have a
real flaw (it grepped the whole cumulative log for the last
`TEST_SUMMARY` line, so any suite using an older `"... test complete
failures=0"` format instead of `TEST_SUMMARY` silently inherited the
previous suite's result in that script's own output). All 32 suites: 0
failures. (`Export_MSZZ_Parity` is an export tool, not a test — it has no
failure count, only a completion line, correctly recorded as such.)

## Gate 5 — Shadow-enabled backtest, zero execution activity: PASS

Config B (`InpEnableSixFamilyResearch=true`) produced 3,234 real research
candidates in `MSZZ_SixFamilyResearchJournal.csv`, and **zero** trace of
any of them in any execution-facing journal:

| Check | Result |
|---|---|
| Deals attributed to strategy_id 1200-1205 | 0 of 659 |
| StrategyBookJournal rows for strategy_id 1200-1205 / family_id 8-13 | 0 of 660 (only 1010/1050 present) |
| PortfolioRiskJournal book_ids | only 1 and 2 (the two production books) |

Full detail: `shadow_runtime_safety.csv`.

## Gate 6 — Shadow-disabled P4 rerun reproduces the certified reference: PASS

Config A (`InpEnableSixFamilyResearch=false`, otherwise the exact D029
Phase 2 P4 config) against the D031-modified, freshly-compiled EA:

```text
trades:      330   (certified: 330)
total_r:     +47.6083   (certified: +47.6083)
PF:          1.2472     (certified: 1.2472)
last entry:  2026.07.21 04:10:00  (certified: 2026.07.21 04:10:00)
```

`MSZZ_PortfolioTradeAnalytics.csv` SHA-256 is **byte-for-byte identical**
to `D029_Audit_Results/D29_P4/MSZZ_PortfolioTradeAnalytics.csv`:
`9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.

## Gate 7 — Shadow-enabled P4 run leaves the production stream identical: PASS

Config B's `MSZZ_PortfolioTradeAnalytics.csv` SHA-256 is **also**
`9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f` —
identical to both Config A and the certified reference. Enabling the
six-family shadow research suite has zero effect on the production
candidate/trade stream, empirically, not just by type-system construction.

Full detail: `production_candidate_hashes.csv`, `production_candidate_diff.csv`.

## An honest observation, not a failure

Of the six families, five emitted candidates over this real 17-month
XAUUSD M5 window (1200 Session Sweep Reversal=2,650, 1203 Compression
Breakout=281, 1205 Range Rotation=149, 1202 Break-Retest Continuation=142,
1204 Trend Pullback=12) — **1201 Momentum Continuation emitted zero.**
This is not a certification failure (Gate 3's synthetic tests already
proved the family's logic can and does emit under controlled conditions),
but it is worth flagging plainly rather than burying: Momentum
Continuation's frozen arm conditions (`regime.fast_swing_amplitude_r>=1.5`
AND `regime.directional_efficiency>=0.55` AND fast/medium alignment,
simultaneously) may be stricter than this specific instrument/timeframe's
real regime distribution supports. Worth a specific look before or during
D032 screening — not a reason to change the frozen definition now (that
would be exactly the "tune after seeing results" the handoff prohibits).

## Commands and completion signals that actually worked

```bash
WINEPREFIX="/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5"
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"   # or MT5-MSZZ-TEST for the isolated tree
"$WINE" start /Unix metaeditor64.exe /compile:"MQL5\\...\\File.mq5" /log
# poll: iconv -f UTF-16LE -t UTF-8 logs/metaeditor.log | tail

cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"     # for /portable to bind to the isolated tree,
# the launch itself must cd into the ISOLATED data folder, not the live install:
cd /Users/matt/MT5-MSZZ-TEST
"$WINE" terminal64.exe /portable /config:"Z:\Users\matt\MT5-MSZZ-TEST\some_config.ini" &
# for SCRIPTS: wait for terminal64.exe itself to exit (ps aux, or better: capture its PID at launch)
# for TESTER runs: terminal64.exe exits almost immediately after dispatch -- wait on
# metatester64.exe by PID instead: until ! kill -0 "$PID" 2>/dev/null; do sleep 20; done
```

Also: `.ex5` files are **not** auto-recompiled on script/EA launch even
when the `.mq5` source is newer — delete the stale `.ex5` first (or
explicitly recompile) before trusting a run's results.

## Confirmations

- No family definitions or thresholds were altered during this checkpoint
  (Gate 3's fix was to the test fixture, not to any family's canonical
  definition or frozen constants).
- No FastMedConfluence, SweepReclaim, P4 exit logic, or
  `OWN_FAMILY_OPPOSITE` behavior was touched.
- All work targeted the isolated `MT5-MSZZ-TEST` instance (Coinexx-Demo
  870012) only; the live terminal was never used for compilation execution
  or trading.

**D031 is certified. D032 (standalone synthetic screening) may begin.**
