# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

## Branch

`feature/mszz-standalone-suite`

Quant Beast work on `main` remains isolated from this branch.

## Validated baseline through commit `31f13b0`

- Determinism test passed.
- Cluster test passed, including D004 cluster-ID tests.
- MQL5 parity export generated clean IDs.
- Shadow Strategy Tester runs placed zero orders/deals/trades.
- Event-store component persistence survived a process restart.
- EA compiled with zero errors and one reviewed Market-version warning.

## Current compile-pending batch — ownership foundation

### Decision

`DECISION_LOG.md` D005 defines account-mode-aware, magic-safe, ticket-specific ownership behavior.

### New files

- `Include/MultiSpeedZigZag/Execution/PositionOwnership.mqh`
- `Include/MultiSpeedZigZag/Execution/PositionOwnershipPolicy.mqh`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Ownership.mq5`

### EA integration

`Experts/MultiSpeedZigZagEA.mq5` is now version `0.310` and replaces symbol-wide ownership logic with:

- explicit `ACCOUNT_MARGIN_MODE` detection;
- live position inventory by ticket;
- symbol and magic-number ownership classification;
- manual/foreign-position protection;
- ticket-specific closure of owned opposite positions only;
- fail-closed behavior on terminal selection ambiguity;
- netting/exchange rejection when foreign or manual symbol exposure exists;
- hedging coexistence with foreign/manual positions;
- one-position limit applied only to owned MSZZ positions;
- startup ownership snapshot and diagnostic logging.

The previous `PositionSelect(_Symbol)` and `CTrade::PositionClose(_Symbol)` execution behavior has been removed from the EA.

### Deterministic ownership test

`Test_MSZZ_Ownership.mq5` covers:

- matching magic classified as owned;
- zero magic classified as manual;
- other nonzero magic classified as foreign;
- hedging coexistence policy;
- netting/exchange foreign-exposure rejection;
- one-owned-position policy;
- unsupported/invalid/error snapshots failing closed;
- opposite-ticket selection excluding manual, foreign, same-direction, and unknown-direction records.

## Validated through commit `73951d9` — ownership batch (2026-07-25 second pass)

Pulled `73951d9` into the live Wine MQL5 working tree (`git pull --ff-only`), synced into the isolated `~/MT5-MSZZ-TEST` instance with hash-verified source (14/14 files identical), and validated end-to-end:

- **Compile**: `Test_MSZZ_Ownership.mq5`, `Test_MSZZ_Determinism.mq5`, `Test_MSZZ_Clusters.mq5`, `Export_MSZZ_Parity.mq5` all 0 errors/0 warnings; `MultiSpeedZigZagEA.mq5` 0 errors, 1 reviewed/accepted warning (Market-version, unrelated to ownership) — isolated MetaEditor/terminal build 6061.
- **Source audit**: no compile-blocking or safety defects found in the new ownership subsystem itself. Two genuine test-coverage gaps against the requested assertion list were closed by adding 9 new assertions to `Test_MSZZ_Ownership.mq5` (empty input → deterministic zero counts, no-duplicate-ticket check, and nonempty failure reasons on every rejection path) — now 24/24 assertions pass. Three other requested assertions (different-symbol exclusion, owned long/short counts, owned volume totals) are `Refresh()`-level behaviors that need live non-zero position state to exercise meaningfully; they're covered by source review instead (every `MSZZPositionRecord` field is set explicitly — no reliance on implicit struct-default zeroing, the exact defect class found in an earlier pass) and documented as an open verification gap in `KNOWN_ISSUES.md`.
- **Ownership unit test**: 24/24 assertions pass, `failures=0`.
- **Live read-only inventory diagnostic**: on the isolated demo account (Coinexx-Demo 870012), `ACCOUNT_MARGIN_MODE` correctly resolves to `HEDGING`, ownership snapshot valid, zero positions of every kind (a valid empty baseline), execution allowed.
- **Shadow regression**: zero orders/deals/trades on both the short (2026.07.20–2026.07.24) and long (2026.07.01–2026.07.24) windows; account mode logged as `HEDGING` at init; candidate/cluster counts identical to the pre-ownership baseline (431/178 on the long window); all cluster IDs `MSZZC1`-prefixed, zero duplicates.
- **Regression**: determinism, cluster (22/22), and parity exporter all re-ran clean on hash-identical source.

This resolves the old "netting-account assumption" blocker in `KNOWN_ISSUES.md`. It does **not** authorize demo execution — see the narrower remaining issues there (close-by-ticket not yet tested against a real position, order/deal history reconciliation absent, post-order persistence failure and full restart reconstruction unchanged).

## Remaining production blockers

1. Post-order persistence failure and idempotent execution intent.
2. Full order/deal/cluster restart reconstruction.
3. Close-by-ticket execution not yet demo-tested against a real open position.
4. Percentage-risk sizing and broker-correct risk calculations.
5. Margin preflight and exposure limits.
6. Daily loss, trade-count, cooldown, and kill-switch controls.
7. Five reserved stateful strategies.
8. Pine-side parity and trendline-geometry decision.
9. Long-duration forward shadow and demo evidence.

## Startup reconciliation scope (explicit boundary, 2026-07-25)

Current startup behavior: EA initializes → account mode detected → live open-position inventory refreshes (by ticket, symbol- and magic-filtered) → snapshot logs → execution stays blocked if the inventory is invalid. This is **open-position inventory only**. The following are **not implemented** and must not be described as complete:

- order history reconstruction;
- deal history reconstruction;
- cluster-to-position reconstruction after restart;
- management-state reconstruction (stops/targets/trailing state tied to a specific cluster after restart).

## Agent procedure

Read `DECISION_LOG.md`, `KNOWN_ISSUES.md`, `TEST_PLAN.md`, and this file before modifying the batch. Fix compile defects without weakening D005 invariants. Any behavioral change requires documentation and, where material, a new decision entry. Keep live execution gates closed and do not merge into `main`.

## Next recommended subsystem

Continue shadow testing and begin idempotent execution-intent persistence plus order/deal reconstruction (see "Remaining production blockers" above, items 1–2). Do not recommend demo execution yet.