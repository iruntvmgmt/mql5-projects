# Restart Recovery Evidence — 2026-07-16

## Status: INVALID / NON-EXERCISING

This evidence directory preserves a 2026-07-16 attempt to construct real-
terminal restart-recovery scenarios on the Coinexx-Demo account. The data
does **not** count toward the restart-recovery gate in
`LIVE_DEPLOYMENT_CHECKLIST.md`.

## What happened

On 2026-07-16, a fixture script (`Scripts/QuantBeastRestartFixture.mq5`)
placed position #34615308 (XAUUSD BUY 0.01, magic 20260701, SL 3000, TP 5000)
on Coinexx-Demo. The MT5 terminal was then force-killed and restarted.
QuantBeastEA reattached on XAUUSD H1, and the position survived the restart
(terminal sync: `1 positions, 0 orders`). No destructive action was observed.

## Why this does not constitute restart-recovery evidence

QuantBeastEA loaded in **QB_MODE_SHADOW** (confirmed by Expert journal:
`Mode: QB_MODE_SHADOW | Symbol: XAUUSD | TF: PERIOD_M5` at 20:30:39.642).

Source inspection confirms that `ReconstructFromBroker()` at
`QuantBeastEA.mq5` ~line 910 is guarded:
```cpp
   // Diagnostic and Shadow must never inspect, cancel, close, or adopt
   // broker positions/orders.
```

Shadow mode by design never calls `ReconstructFromBroker()`, never inspects
broker positions, and never exercises the ownership-classification,
pending-order-cancellation, or position-adoption code paths that the restart-
recovery gate requires.

The observed "no destructive action on position #34615308" is **expected
Shadow-mode passivity**, not evidence of correct ownership classification.

## Affected scenarios

| Scenario | Magic | Outcome |
|---|---|---|
| 1 — Owned position | 20260701 (QB range) | **INVALID** — Shadow mode never reached ReconstructFromBroker() |
| 2 — Pending orders | 20260801 (QB range) | Not yet executed |
| 3 — Unknown position | 99999999 (outside QB range) | **Blocked** — same structural problem as Scenario 1 |
| 4 — Corrupt state | N/A (globals) | Not yet executed |

## Unresolved question

What is the minimum mode/acknowledgement configuration that reaches
`ReconstructFromBroker()` on the live Coinexx-Demo terminal, and does using
it conflict with `AGENTS.md`'s live-mode restrictions (Conservative Live or
Challenge Live prohibition on real accounts, demo-account scope)?

This question must be answered before Scenarios 1 and 3 can be meaningfully
retried.

## Preserved artifacts

- `scenario1_pre_restart.txt` — pre-restart position state
- `pre_compile_hashes.txt` — pre-compile source/ex5 SHA-256
- MetaEditor compile log: `metaeditor.log` entries at 17:21:14 (EA) and 20:13:28 (fixture script)
- Terminal log: `logs/20260716.log` (UTF-16 LE), entries 20:25–20:31
- Expert journal: provided by operator from Experts tab, 20:30:38–20:30:39

## Compile boundary

- Source SHA-256: `24acb8babcaf977fab7b265fe979fa919850d121d69254eeff013fa35d5e2041`
- EX5 SHA-256: `c9e3f9c07ba227c82770df807c7364b18ef9bf71ade4b1d204a558e44d5081b2`
- Fixture script SHA-256: `cb32f28d2c2425573ec16fe7805ee5f442b5b4e4ca7acb7c96966ae2cf4905ce`
- Fixture EX5 SHA-256: `8f2d97feab2a36ae0465e666fa583a2ec74f2bb6a1200c647fc5bd942b84c237`
