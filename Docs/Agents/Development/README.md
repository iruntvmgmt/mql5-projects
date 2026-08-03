# OpenClaw Permanent Development Team

**Status:** Draft operating system for post-recovery activation  
**Repository:** `iruntvmgmt/mql5-projects`  
**Branch:** `docs/openclaw-mc-recovery-team-v2`

## Purpose

This directory defines the permanent OpenClaw engineering organization for QuantBeast and independently certified strategy engines.

At present, the only independently named strategy engine covered by repository facts is MultiSpeedZigZag. Future engines are intentionally unnamed until they have an authorized research proposal, canonical specification, and repository presence.

This operating system must not treat roadmap ideas, informal discussions, possible indicators, possible markets, or possible strategy families as established architecture.

It remains inactive during MC-CANON-2 recovery unless the user explicitly activates it after the recovery evidence package and independent checkpoint verdict.

## Architectural facts

QuantBeast is a centralized MT5 platform:

```text
market snapshot
→ bar/tick/session cache
→ feature engine
→ regime engine
→ independent strategy engines
→ signal arbitration
→ centralized risk validation
→ position sizing
→ shadow portfolio or broker adapter
→ position manager
→ reconciliation, journals, persistence, dashboard, alerts
```

Independent engines remain independently specifiable and certifiable. They connect through reviewed adapters and never bypass QuantBeast arbitration, allocation, exposure, risk, sizing, execution, kill-switch, persistence, or reconciliation controls.

## Repository-derived scope rule

Permanent instructions may contain only:

- current repository facts;
- generic engineering/research policy;
- authorized ticket behavior;
- approved or frozen specifications.

They must not predeclare future indicators, instruments, markets, strategy families, parameters, or hypotheses.

## Canonical MT5 operational bridge

Every agent that compiles or executes MQL5 must read and follow:

```text
Docs/Agents/Operations/README.md
Docs/Agents/Operations/MT5_MACOS_WINE_OPERATIONAL_BRIDGE.md
Docs/Agents/Operations/INI_CONFIG_REFERENCE.md
Docs/Agents/Operations/PROCESS_AND_PID_PROTOCOL.md
Docs/Agents/Operations/LOG_AND_ARTIFACT_PROTOCOL.md
Docs/Agents/Operations/FAILURE_RECOVERY_MATRIX.md
Docs/Agents/Operations/COMMAND_COOKBOOK.md
Docs/Agents/Operations/RUNTIME_EVIDENCE_TEMPLATE.md
```

The operating bridge distinguishes:

- isolated MetaEditor compilation;
- isolated portable MQL5 Script execution;
- isolated Strategy Tester execution;
- main-terminal MCP operations.

MCP is not a universal substitute for portable Script or Tester launch.

## Permanent roles

1. `LEAD_DEVELOPER.md`
2. `QUANTBEAST_ARCHITECT.md`
3. `QUANTBEAST_PLATFORM_ENGINEER.md`
4. `STRATEGY_ENGINE_LEAD.md`
5. `MT5_RUNTIME_ENGINEER.md`
6. `RESEARCH_STATISTICIAN.md`
7. `INDEPENDENT_REVIEWER.md`
8. `OPERATING_PROTOCOL.md`
9. `SECURITY_AND_SECRETS.md`

## Activation gate

The permanent team may begin only when:

- active recovery has an explicit verdict;
- inherited work is inventoried and preserved;
- user names active branch and task;
- each active agent has unique ownership;
- no two agents edit the same file or share one runtime without explicit isolation;
- runtime/reviewer roles remain non-authoritative over semantics;
- no live deployment authority is implied;
- required operational bridge documents are locally available.

## Permanent team rule

OpenClaw may work continuously only on `AUTHORIZED` tickets.

The system optimizes for correctness, evidence, reproducibility, maintainability, measurable expectancy, low operational risk, and honest negative outcomes.

It does not optimize for green tests, attractive backtests, commit count, code volume, or speculative roadmap expansion.
