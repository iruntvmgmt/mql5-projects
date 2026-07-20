# Strategy-comment parsing consistency fix — 2026-07-20

## Defect

Found during the `fault_adapter_20260720` session (Finding 3): `OnTradeTransaction()`'s
live entry-handling comment parsing in `QuantBeastEA.mq5` did not match
`PositionManager.mqh`'s `StrategyFromComment()` (used by restart's
`ReconstructFromBroker()`). The live path stripped the `QB_` prefix via
`StringSubstr` but did not truncate at a further `_`, so a comment like
`QB_FBO_fixture` resolved to `FBO` on restart but to the unrecognized
`FBO_fixture` when the same position was picked up live via
`OnTradeTransaction`. Three call sites had ad-hoc copies of this logic:
`QuantBeastEA.mq5` lines ~1605 (pending-fill reconciliation), ~1734
(live entry, active-order match), and ~1741 (live entry, no active-order
match — the one that actually produced the wrong result observed).

Severity: Medium (data-integrity/strategy-attribution defect in
journaling and strategy-count tracking; does not affect order safety,
magic-based ownership classification, or protection verification, which
key off other fields).

## Fix

Extracted the correct logic (strip `QB_` prefix, then truncate at the
first remaining `_`, then validate against the four known strategy ids)
into a single free function `QBStrategyIdFromComment()` in
`PositionManager.mqh`, alongside a `QBIsKnownStrategyId()` helper.
`CPositionManager::StrategyFromComment()` now delegates to it (removing
its own duplicate `IsKnownStrategyId` private method, now dead code).
All three call sites in `QuantBeastEA.mq5` now call
`QBStrategyIdFromComment()` directly instead of their own inline
`StringSubstr`/`StringFind` logic. `SafetyTests.mqh` now explicitly
includes `PositionManager.mqh` (previously relied on include order from
`QuantBeastEA.mq5` alone).

Added `QBTestStrategyIdFromComment()` (TEST 50) covering: plain comment
(`QB_FBO`), suffixed comment (`QB_FBO_fixture`), multi-suffix comment
(`QB_BO_fixture_owned`), missing-prefix (`QB fixture owned`), no-prefix
(`FIXTURE_UNKNOWN`), and unrecognized strategy id (`QB_NOTASTRATEGY`) --
all asserting the exact expected resolution.

## Verification

- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, 2026.07.20 00:17:57.
- Source SHA-256: `36760c8f30f0ac822f1a273375b4b5ac9d9708f9069598121943df6488a97a84`
- EX5 SHA-256: `3c87a3947acb69cefc6217854e90d58f64cf779d7f24cb7d24258458d23422b5`
- `PositionManager.mqh` SHA-256: `90d3099c0fe2bf348e6cf3f8ddb983572574deabbe7e029d061ca041dd519c66`
- `SafetyTests.mqh` SHA-256: `693bc3653a4a13885cf9ab0796c332ded965c5ddf12f10472638e08eedb86059`
- Shadow regression (Model=4, self-tests enabled, no journals): `Self-tests complete: 53 passed, 0 failed` (52 prior + new TEST 50), including `TEST 50 PASS: Strategy id comment parsing plain=FBO suffixed=FBO multi=BO noPrefix=UNKNOWN unknownId=UNKNOWN`. Final balance unchanged at 10000.00, `OnTester result 0`, normal tester footer.
- No broker orders transmitted by this test run.

## Scope discipline

This was a small, well-understood, single-purpose fix (comment-parsing
consistency only) per AGENTS.md change discipline -- no strategy logic,
risk parameters, or execution behavior were touched. Readiness remains
exactly `READY FOR SHADOW MODE`.
