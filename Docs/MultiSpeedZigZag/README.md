# Multi-Speed ZigZag Standalone Suite

## Purpose

This directory is the documentation home for the standalone Multi-Speed ZigZag EA and its reusable strategy engine.

The suite is intentionally developed outside Quant Beast while remaining compatible with a future thin adapter into Quant Beast. The goal is to preserve one shared source of truth for pivot detection, trendline projection, signal generation, event clustering, and strategy research.

## Source references

The original behavior references currently live under:

- `Indicators/Tradingview_Indicators/MULTI_SPEED_ZIGZAG/MS-ZZ-BO-V2-STRAT.pine`
- `Indicators/Tradingview_Indicators/MULTI_SPEED_ZIGZAG/MS-ZZ-BO-V2.pine`
- `Indicators/Tradingview_Indicators/MULTI_SPEED_ZIGZAG/MS-ZZ-BO-V2.mq5`
- `Indicators/Tradingview_Indicators/MULTI_SPEED_ZIGZAG/ZZ-LUX-TRENDLINE-BREAK...`

These files are reference specifications until parity and repaint behavior are formally audited.

## Documentation set

- `HANDOFF.md` — current state, next actions, blockers, and agent continuation instructions.
- `ARCHITECTURE.md` — subsystem boundaries, data flow, and adapter design.
- `STRATEGY_CATALOG.md` — strategy IDs, hypotheses, triggers, invalidations, and overlap rules.
- `NON_REPAINTING_CONTRACT.md` — pivot confirmation semantics and forbidden future leakage.
- `TEST_PLAN.md` — deterministic, parity, replay, backtest, and execution tests.
- `DECISION_LOG.md` — append-only record of important design and research decisions.
- `RESEARCH_PROTOCOL.md` — rules for testing edge without contaminating results through curve fitting.

## Documentation rule

No material code change is complete until the related documentation is updated in the same branch. At minimum, every meaningful change must update one or more of:

- architecture
- strategy catalog
- test plan
- decision log
- handoff status

## Current branch

`feature/mszz-standalone-suite`

Do not merge into `main` until the milestone being reviewed has deterministic evidence and a coherent handoff.