# Organic true-tick evidence — 2026-07-19

## Purpose

HANDOFF item #3: organic BO/FBO/TP/MR and full Shadow lifecycle coverage on true real ticks. Inspect post-repair CSV status/ID rows.

## Configuration

- Config: `QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260620_20260624.ini`
- Symbol/timeframe: XAUUSD M5
- Model: `4`, every tick based on real ticks
- Window: 2026.06.20 to 2026.06.24 (5 days)
- Deposit/currency/leverage: 10000, USD, 500
- Mode: Shadow (InpMode=1)
- BO/FBO/TP/MR: all enabled
- Self-tests: disabled
- Signal/order/trade journals: enabled

## Runtime result

```text
final balance 10000.00 USD
OnTester result 0
XAUUSD,M5: 863499 ticks, 552 bars generated
Test passed in 0:28:51.422
```

## CSV journal growth

```text
SignalJournal.csv: 5765442 → 6294832 bytes (+529390), 20071 → 21911 lines (+1840)
OrderJournal.csv:  9084 → 10628 bytes (+1544), 41 → 48 lines (+7)
TradeJournal.csv:  14440 → 16868 bytes (+2428), 42 → 49 lines (+7)
```

## Signal summary by strategy/status

```text
 460 TP,REJECTED
 460 MR,REJECTED
 459 BO,REJECTED
 453 FBO,REJECTED
   7 FBO,ACCEPTED
```

Total new signal rows: 1840. Only FBO reached accepted state (7 entries: 5 BUY, 2 SELL). BO/TP/MR were rejected only. This matches the prior 2026-07-16 single-day finding on a broader 5-day window.

## Accepted FBO entries

```csv
2026.06.22 07:05:00,FBO,BUY,FBO_BUY_1782111900
2026.06.22 11:05:00,FBO,BUY,FBO_BUY_1782126300
2026.06.22 12:15:00,FBO,SELL,FBO_SELL_1782130500
2026.06.22 13:20:00,FBO,SELL,FBO_SELL_1782134400
2026.06.22 14:55:00,FBO,BUY,FBO_BUY_1782140100
2026.06.23 06:15:00,FBO,BUY,FBO_BUY_1782195300
2026.06.23 07:40:00,FBO,BUY,FBO_BUY_1782200400
```

## Trade outcomes (7 FBO trades)

```csv
FBO,LONG,4174.14→4185.59,+115.26 net,R=1.43
FBO,LONG,4192.29→4203.65,+113.70 net,R=1.45
FBO,SHORT,4205.13→4213.97,-98.01 net,R=-1.04
FBO,SHORT,4210.21→4210.33,-2.66 net,R=-0.02
FBO,LONG,4205.77→4205.70,-1.54 net,R=-0.01
FBO,LONG,4142.35→4132.17,-102.50 net,R=-1.03
FBO,LONG,4139.32→4130.63,-105.12 net,R=-1.09
```

Both BUY and SELL directions preserved. Signal IDs include direction. Accepted rows appear only after final decision. Order/fill outcomes journaled separately.

## Evidence files

- `pre_run_boundary.txt` — CSV sizes before run
- `new_signal_rows.csv` — 1840 new signal rows (decoded from UTF-16)
- `new_order_rows.csv` — 7 new order rows
- `new_trade_rows.csv` — 7 new trade rows with PnL
- `QuantBeast.OrganicTrueTicks.XAUUSD.M5.20260620_20260624.ini` — tester config

## Readiness impact

Readiness remains exactly `READY FOR SHADOW MODE`. This run proves organic true-tick signal generation, arbitration, risk gating, and Shadow lifecycle accounting for all 4 strategies. It does NOT prove BO/TP/MR organic accepted entries (strategies remain too selective for this window), broker execution, or profitability.
