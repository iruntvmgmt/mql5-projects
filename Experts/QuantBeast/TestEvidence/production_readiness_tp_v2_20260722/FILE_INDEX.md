# File index -- production_readiness_tp_v2_20260722

Updated per phase. "Runtime effect" = does this file change EA behavior at
runtime (vs. docs/tests/tooling only).

## Phase A: TP V1 freeze

| File | Purpose | Runtime effect | Commit | Evidence |
|---|---|---:|---|---|
| `Include/QuantBeast/Strategies/TrendPullbackEngine.mqh` | Add `QB_TP_LIFECYCLE_VERSION=1`, `GetLifecycleVersion()`, tag rejection reasons with `lifecycleVersion=` | No (diagnostic string only, no logic change) | pending | `tp_v1_freeze/README.md` |
| `Include/QuantBeast/Analytics/TPOutcomeTracker.mqh` | Add `LifecycleVersion` column (schema v1->v2); fix `WriteRow()` bookkeeping-before-handle-check defect | No (observation-only tracker; bugfix only affects tracker's own reported counts, not trading) | pending | `tp_v1_freeze/README.md`, self-test regression |
| `Experts/QuantBeast/Tools/tp_outcome_report.py` | Schema v1/v2 column-count-aware fallback | No (offline Python tool) | pending | n/a |
| `Experts/QuantBeast/Tools/tp_rejection_attribution_report.py` | Truncate rejection reason at ` lifecycleVersion=` instead of ` lifecycle=` | No (offline Python tool) | pending | n/a |
| `Profiles/Tester/QuantBeast.SelfTestDetail.20260722.ini` | New self-test-detail tester profile (InpLogSelfTestDetails=true) used to diagnose Test 70 | No (tester config, not committed to repo -- MT5 Profiles dir, untracked like all other `.ini` profiles) | n/a (untracked) | this phase's self-test logs |
| `TestEvidence/production_readiness_tp_v2_20260722/**` | Session evidence root (this sprint) | No | pending | self |

Two live (untracked, non-evidence) runtime journal files were rotated as
part of this phase, not edited, after confirming their full byte ranges were
already captured in committed evidence (see Decision D002):
`Common/Files/QuantBeast/TPOutcomeJournal.csv` was renamed to
`TPOutcomeJournal.pre_v1_freeze_schema1.csv` (still present on disk, 2240
bytes, header-only) and not yet recreated (no terminal-side run has occurred
since). `Common/Files/QuantBeast/Tester/TPOutcomeJournal.csv` was likewise
renamed to `TPOutcomeJournal.pre_v1_freeze_schema1.csv` (still present, 23708
bytes -- fully covered by `tp_forward_outcome_20260722/`), and the fresh
`TPOutcomeJournal.csv` that self-test runs then recreated at that path was
additionally removed once (via the proper `mcp__mt5-native__delete_file`
tool, not host `mv`) while diagnosing the file-open flakiness in Decision
D003; a header-only file now sits at that path again, recreated automatically
by a subsequent tester run.
