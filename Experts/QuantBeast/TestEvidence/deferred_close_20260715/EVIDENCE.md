# Deferred Close Reconciliation Evidence — 2026-07-15

## Confirmed defect

`OnTradeTransaction(DEAL_ADD)` classified an exit as partial whenever the position was still visible at that instant. MT5 does not guarantee transaction arrival order, so a fully closed position could remain visible until the following position transaction. That race could skip final journal, performance, consecutive-loss, high-water, and persistence updates; the next tick then removed the context silently.

## Repair

- Exit deals are queued by stable position identifier.
- Multiple exit deals for one position collapse to one candidate with the latest deal retained for the final exit reason.
- Reconciliation occurs on the subsequent tick/timer after the transaction burst.
- A still-existing position is classified as a partial exit; its PnL is retained in broker history for final aggregation.
- An absent position is finalized once, journaled, applied to risk, removed from tracking, and persisted.
- Live mode now explicitly accepts hedging accounts only. Netting/exchange accounts fail initialization because `DEAL_ENTRY_INOUT` reversal semantics are not yet implemented.

## Evidence

- Compile: `0 errors, 0 warnings, 7883 ms`, X64 Regular
- Source SHA-256: `b54542ab7967b829b53adbb6cba4f32a027e31556a8914fc25fbfea8c6d2ea51`
- EX5 SHA-256: `6cc32dc289e22dee2f790d07abc7df83f9bb99a0fca37aa6405ef9e6f996e8bc`
- TransactionState SHA-256: `c398696d82f1ef57608fc294f14140dd988d2957b0aacc764099cb8f8e205b12`
- SafetyTests SHA-256: `26d257c0871c73b8dd9f25faf52754db294728985e2bcfe59233b1c4ee2fc47b`
- New fixture: `TEST 23 PASS: Deferred close state dedup=true partial=deferred close=finalized hedge=only`
- Complete suite: `25 passed, 0 failed`
- Tester: `27600` ticks, `1380` bars, `14.302 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic queue, deduplication, partial/final decision, and hedge-only admission contracts. This is not evidence from a real broker close callback sequence. Controlled demo/fault-injection evidence remains required.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
