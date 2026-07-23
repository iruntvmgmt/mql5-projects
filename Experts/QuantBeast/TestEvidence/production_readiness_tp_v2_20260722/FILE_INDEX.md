# File index -- production_readiness_tp_v2_20260722

Updated per phase. "Runtime effect" = does this file change EA behavior at
runtime (vs. docs/tests/tooling only).

## Phase A: TP V1 freeze (commit `6ce0a41`)

| File | Purpose | Runtime effect | Commit | Evidence |
|---|---|---:|---|---|
| `Include/QuantBeast/Strategies/TrendPullbackEngine.mqh` | Add `QB_TP_LIFECYCLE_VERSION=1`, `GetLifecycleVersion()`, tag rejection reasons with `lifecycleVersion=` | No (diagnostic string only, no logic change) | `6ce0a41` | `tp_v1_freeze/README.md` |
| `Include/QuantBeast/Analytics/TPOutcomeTracker.mqh` | Add `LifecycleVersion` column (schema v1->v2); fix `WriteRow()` bookkeeping-before-handle-check defect | No (observation-only tracker; bugfix only affects tracker's own reported counts, not trading) | `6ce0a41` | `tp_v1_freeze/README.md`, self-test regression |
| `Experts/QuantBeast/Tools/tp_outcome_report.py` | Schema v1/v2 column-count-aware fallback | No (offline Python tool) | `6ce0a41` | n/a |
| `Experts/QuantBeast/Tools/tp_rejection_attribution_report.py` | Truncate rejection reason at ` lifecycleVersion=` instead of ` lifecycle=` | No (offline Python tool) | `6ce0a41` | n/a |
| `Profiles/Tester/QuantBeast.SelfTestDetail.20260722.ini` | New self-test-detail tester profile (InpLogSelfTestDetails=true) used to diagnose Test 70 | No (tester config, not committed to repo -- MT5 Profiles dir, untracked like all other `.ini` profiles) | n/a (untracked) | this phase's self-test logs |
| `TestEvidence/production_readiness_tp_v2_20260722/**` | Session evidence root (this sprint) | No | `6ce0a41`+ | self |

## Phase B: TP V2 specification (commit `ee7db48`, docs-only)

`tp_v2_spec/TP_V2_SPEC.md`, `TP_V2_STATE_MACHINE.md`, `TP_V2_PARAMETER_CONTRACT.md`, `TP_V2_REASON_CODES.md` -- no runtime effect, pre-registration only.

## Phase C/D: TP V2 implementation + tests (commit `026e91c`)

| File | Purpose | Runtime effect | Evidence |
|---|---|---:|---|
| `Include/QuantBeast/Strategies/TrendPullbackV2Engine.mqh` | New 8-state TP V2 engine | Yes, gated (`InpEnableTPV2Experimental=false` default -- no reachable signal path) | Tests 75-92 |
| `Include/QuantBeast/Core/Enums.mqh`, `Types.mqh`, `Constants.mqh` | New setup/trigger codes, `ENUM_TPV2_TRIGGER_MODE`; `KillSwitchState.strategy_kill[4]->[5]` fix; `QB_STRAT_COUNT` 4->5 | Yes (array-bounds fix; new enum values additive) | Test 93 covers boundary logic elsewhere |
| `Include/QuantBeast/Core/Configuration.mqh` | New `InpTPV2_*` / `InpEnableTPV2Experimental` inputs | Yes (new inputs, safe defaults) | n/a |
| `Experts/QuantBeast/QuantBeastEA.mq5` | Wire TPV2 as 5th strategy; `candidates[8]->[10]` fix | Yes (array-bounds fix; TPV2 wiring gated) | Tests 75-93 |
| `Include/QuantBeast/Testing/SafetyTests.mqh` | `QBDriveTPV2` fixture + Tests 75-93 | No (test-only) | self |

## Phase F: infrastructure audit (commits `acefa09`, `e04d8aa`)

| File | Purpose | Runtime effect | Evidence |
|---|---|---:|---|
| `Include/QuantBeast/Core/MathUtils.mqh` | `QBValidNumberInRange()` boundary primitive | No (pure function) | Test 93 |
| `Experts/QuantBeast/QuantBeastEA.mq5` | `QBProductionConfigurationValid()` + `QBLogResolvedProductionConfiguration()`, called from `OnInit` | Yes (fail-closed on genuinely invalid config only; no change for any valid config incl. all existing defaults/profiles) | Test 93, self-test regression log |
| `Experts/QuantBeast/Tools/strategy_performance_report.py` | New canonical per-strategy/direction/session/regime report | No (offline Python tool) | `infrastructure_audit/INFRASTRUCTURE_AUDIT.md` |
| `TestEvidence/.../infrastructure_audit/INFRASTRUCTURE_AUDIT.md` | Part F audit document | No | self |

## Phase G: restricted demo candidate (commit `8f33449`)

| File | Purpose | Runtime effect | Evidence |
|---|---|---:|---|
| `Experts/QuantBeast/XAUUSD_Conservative_Demo_AllStrategy.set` | Prepared, not-activatable demo candidate preset | No (cannot currently initialize in any live-armed mode -- `QBLiveStrategySetAllowed()` untouched) | Decision D006 |

## Phase E: unified all-strategy window matrix (in progress)

| File | Purpose | Runtime effect | Evidence |
|---|---|---:|---|
| `Experts/QuantBeast/Tools/tpv2_structure_report.py` | New TP V2 lifecycle decomposition report | No (offline Python tool) | `unified_strategy_matrix/` |
| `TestEvidence/.../run_manifests/*.md` | Per-run manifests | No | self |
| `TestEvidence/.../unified_strategy_matrix/*.md` | Per-window BO/FBO/MR/TPV1/TPV2 reports | No | self |

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
