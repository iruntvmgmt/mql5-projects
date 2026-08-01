# Screening Simulator V2 — Status

**Phase status: `SCREENING_SIMULATOR_V2_CERTIFIED_BINDING_PARITY_HARDENED` —
the certification-hardening correction (candidate→journal binding, UTF-8
ordering, fail-closed evidence) is certified: hardened 95-fixture MQL run,
collector V2 self-tests, coverage provenance, one clean full regression, and
exact P4 all pass. No family is authorized by this work.**

The standalone screening simulator reproduces byte-identical canonical
outcomes across Python and MQL5 over the full fixture matrix, on top of the
certified market/instrument transport (commit 1) and the shared
ScreeningExecutionPolicyV2. It remains research tooling: it is not wired into
any production path and authorizes no family.

## Commits

- Starting HEAD: `784d2493429282ee83147ea948294cf5884fd6b7`
- Branch: `recovery/research-journal-manifest-parser-v2`
- Policy consumed: `MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST` (MQL5 `.mqh` unchanged)
- `87e53f1`, `7159e4d` — commit 1: integer market/instrument transport
- bounded policy correction — Python tick-boundary epsilon aligned to the
  certified MQL5 behavior (see below); its own commit, immediately before this
  one
- commit 2 (this commit) — the simulator loop, fixtures, parity, evidence

## Bounded policy correction

The certified MQL5 `NormalizeStop`/`NormalizeTarget` apply a `+/-1e-9`
grid-boundary epsilon; the Python `_ticks` helper did not, producing a
one-tick divergence at exact tick boundaries (fixture F15: short target
`raw/tick=1996.0000000000002` → `99.85` Python vs `99.80` MQL5). Frozen as
parity fixture `short_tick_boundary`, then fixed in `screening_execution_v2.py`
only (floor `+1e-9`, ceil `-1e-9`; minimum-distance fallbacks stay
epsilon-free). MQL5 source unchanged. The epsilon sign is hard-bound to the
rounding direction via explicit `_floor_ticks`/`_ceil_ticks` helpers (no
`mode is math.floor` callable-identity check), so no caller can supply the
wrong sign. Policy re-certified: Python tests pass; MQL5
`Test_MSZZ_ScreeningExecutionPolicyV2` 12/12. Recorded in
`Docs/MultiSpeedZigZag/SCREENING_EXECUTION_CONTRACT_V2.md`.

## Files added (commit 2, no existing production file modified)

```text
MQL5/Include/MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh
MQL5/Tests/MultiSpeedZigZag/Test_MSZZ_ScreeningSimulatorV2.mq5
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/screening_simulator_v2.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/simulator_fixtures.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/make_simulator_fixtures.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/test_screening_simulator_v2.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/collect_mql5_results.py
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/simulator_fixtures.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/expected_outcomes.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/fixture_coverage.csv
MQL5/Tools/SixFamilyRecovery/ScreeningSimulatorV2/mql5_results.csv
```

## Fixture matrix

58 language-neutral fixtures (F01–F58) in `simulator_fixtures.py`, serialized
to `simulator_fixtures.csv` (+ `expected_outcomes.csv`) consumed identically by
both languages. Coverage in `fixture_coverage.csv`: 58/58 PASS in
`python_result`, `mql5_result`, and `parity_result`.

## Evidence (fresh, this session, 2026-07-31)

- **Compiles** (`wine start /Unix metaeditor64 /compile /log`): policy test
  `0 errors, 0 warnings` (ex5 8782 B); simulator test `0 errors, 0 warnings`
  (ex5 60066 B). Production `MultiSpeedZigZagEA` not recompiled (unchanged).
- **Python**: `test_screening_execution_v2` pass; `test_screening_simulator_v2`
  58/58 (incl. shuffled-determinism re-run).
- **MQL5 isolated `/portable` (login 870012)**: policy `TEST_SUMMARY tests=12
  failures=0` (11:49); simulator `TEST_SUMMARY tests=114 failures=0` (11:53) —
  per-fixture run-status + byte-identical canonical outcome SHA-256 vs the
  Python reference.
- **Full regression (split)**: legacy D033 suite **32/32 PASS**; newly added
  suites **4/4 PASS** (`D032_ExportRates`, `Export_MSZZ_Parity`,
  `ScreeningMarketV2`, `ScreeningSimulatorV2`); expanded total **36/36 PASS**,
  **0 failures, 0 tooling no-ops**. No legacy suite was dropped or renamed
  (verified against the D033 roster `Tools/D033/Remediation/test_summary.csv`).
  Evidence source: the **corrected** harness — `run_full_regression.sh` was
  rebuilt to derive each suite's result from a per-suite byte-offset window,
  its own script name, its own fresh completion line, PID lifecycle, and an
  explicit `TOOLING_NO_OP` when no fresh matching summary appears (the prior
  harness used `tail -1` of the whole shared daily log; classification now
  lives in the testable `classify_regression.py`, validated against a
  TEST_SUMMARY suite, `Determinism`, `PositionSizing`, `ScreeningMarketV2`,
  `ScreeningSimulatorV2`, and a negative control). Fresh isolated `/portable`
  run 2026-07-31 12:15–12:40, distinct PID per suite; see
  `Tools_D031_regression_results.txt`.
- **P4 parity (fresh backtest, 2026-07-31 11:54)**: 330 trades,
  `+47.6083336413R`, PF `1.2472234619`, canonical journal
  `MSZZ_PortfolioTradeAnalytics.csv` SHA-256
  `9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f` —
  **byte-identical** to the certified reference.

## Family authorization / D034-D035

Unchanged. All six families remain `implementation_authorized=false`. No family
generator, production path, or P4 logic was touched. D034 and D035 remain
unauthorized.

## Certification-hardening correction — evidence (2026-07-31)

Final certification. Remote pre-finalization HEAD `d13f3749f7e1234a763b410b7fdd0fc64db97c73`
(the three hardened commits, committed-blob-verified and pushed). This signoff
commit finalizes only the status token and evidence ledger. All gates pass:

- **Python**: transport, policy, market, screening_simulator (F01-F58),
  journal_binding (JB01-JB24), ordering (OR01-OR13), certification-fixtures
  generator self-tests (5), collector-V2 self-tests (20), coverage-V2 — all green.
- **MQL5 fresh compile 0/0**: ResearchJournalTransportV2, ScreeningSimulatorV2
  (F markers), ScreeningJournalBindingV2 (JB), ScreeningOrderingV2 (OR),
  certified + fixture compile probes. **Negative probe fails to compile**
  (`error 256: undeclared identifier 'RunScreeningCoreForFixtures'`) — the
  execution core is unreachable on an ordinary include.
- **MQL5 isolated /portable (login 870012)**, all bound to one cert run
  `MSZZ_SCREENING_CERT_RUN_V2_d5226c1c671ae1e9`:
  - F `tests=114 failures=0 f=58 markers=58 fixture_failures=0 harness_failures=0`
  - JB `tests=92 failures=0 jb=24 markers=24 fixture_failures=0 harness_failures=0`
  - OR `tests=13 failures=0 or=13 markers=13 fixture_failures=0 harness_failures=0`
  - Total **95 markers, 0 failures, 0 harness failures**.
- **Cross-language SHA parity**: journal SHA `be0d32db…` and projection SHA
  `1c855e6399…` byte-identical (Python == MQL5).
- **Collector V2** (`MSZZ_MQL5_RESULT_COLLECTOR_V2`): 95 markers, shared cert
  run, exact ID sets, fail-closed + atomic. **Coverage V2**
  (`MSZZ_SCREENING_COVERAGE_V2`): 95/95 (58/24/13) python/mql5/parity all PASS,
  with provenance; rejects tampered results.
- **Full regression — one clean unified run** `REG_20260731_225841`: **39/39
  PASS, 0 failures, 0 tooling no-ops** (no retries required, no manual
  reconciliation; each suite launched in the same execution and classified from
  its own fresh byte window). Roster split: legacy D033 32 + newly added 7
  (`ScreeningMarketV2`, `ScreeningSimulatorV2`, `ScreeningJournalBindingV2`,
  `ScreeningOrderingV2`, `ResearchJournalTransportV2`, `D032_ExportRates`,
  `Export_MSZZ_Parity`) = 39. (A prior run showed one transient launch-race
  no-op resolved on re-run; retained only as historical diagnostic, not
  certification evidence.)
- **P4 exact (fresh run 2026-07-31 22:30)**: 330 trades, +47.6083336413R,
  PF 1.2472234619, canonical journal SHA
  `9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.
- **F01-F58 outcome SHAs unchanged**; production EA ex5
  `e739e76e6de5a13e8fb210b13480339cdba9a7ae6fa73de80acda796b40daa16`,
  ScreeningExecutionPolicyV2.mqh, and family generators all unchanged.

All six families remain unauthorized. D034 and D035 remain blocked.
