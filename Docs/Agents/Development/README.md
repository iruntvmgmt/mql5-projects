# OpenClaw Permanent Development Team

**Status:** Draft operating system for post-recovery activation  
**Repository:** `iruntvmgmt/mql5-projects`  
**Branch:** `docs/openclaw-mc-recovery-team-v2`

## Purpose

This directory defines the permanent OpenClaw engineering organization for QuantBeast and independently certified strategy engines such as MultiSpeedZigZag, Triple MA, and NQ Breakout.

It is not active during the current MC-CANON-2 recovery unless the user explicitly activates it after the recovery team issues a complete evidence package and an independent reviewer closes the checkpoint.

## Architectural facts

QuantBeast is a centralized MT5 platform, not one monolithic signal rule. Its intended pipeline is:

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

Independent strategy engines must remain independently specifiable and certifiable. They connect to QuantBeast only through reviewed adapters. No external engine may bypass QuantBeast arbitration, allocation, exposure, risk, sizing, execution, kill-switch, persistence, or reconciliation controls.

## Permanent roles

1. `LEAD_DEVELOPER.md` — final coordinator for authorized development.
2. `QUANTBEAST_ARCHITECT.md` — contracts, boundaries, schemas, taxonomy, ADRs.
3. `QUANTBEAST_PLATFORM_ENGINEER.md` — platform implementation and integration.
4. `STRATEGY_ENGINE_LEAD.md` — standalone strategy-engine implementation.
5. `MT5_RUNTIME_ENGINEER.md` — compile, launch, tester, evidence automation.
6. `RESEARCH_STATISTICIAN.md` — validation, selection-bias controls, portfolio metrics.
7. `INDEPENDENT_REVIEWER.md` — read-only adversarial review.
8. `OPERATING_PROTOCOL.md` — tickets, ownership, branches, messages, gates.
9. `SECURITY_AND_SECRETS.md` — credentials, tokens, live-account boundaries.

## Activation gate

The permanent team may begin only when all are true:

- the active recovery checkpoint has an explicit verdict;
- uncommitted work has been inventoried and either committed or intentionally preserved;
- the user names the active branch and task;
- each active agent has a unique ownership scope;
- no two agents are authorized to edit the same file;
- runtime and reviewer roles remain non-authoritative over strategy semantics;
- no live deployment authority is implied.

## Permanent team rule

OpenClaw may work continuously, but only on `AUTHORIZED` tickets. Continuous execution does not mean unlimited discretion.

The system optimizes for:

- correctness;
- evidence;
- reproducibility;
- maintainability;
- measurable expectancy;
- low operational risk;
- honest negative research outcomes.

It does not optimize for green tests, impressive backtests, commit count, or code volume.
