# Organic True-Tick Evidence - 2026-07-16

## Configuration

- Config: `QuantBeast.OrganicTrueTicks.Strategies.XAUUSD.M5.20260622_20260623.ini`.
- Symbol/timeframe: XAUUSD M5.
- Model: `4`, every tick based on real ticks.
- Window: 2026.06.22 00:00 to 2026.06.23 00:00.
- Mode: Shadow (`InpMode=1`).
- Challenge acknowledgement: false.
- BO/FBO/TP/MR: all explicitly enabled.
- Self-tests: disabled, so new signal rows are organic pipeline rows, not fixture rows.
- Persistence/global variables/news/dashboard: disabled.
- Signal, order, and trade journals: enabled.

## Boundaries

- Pre-run agent log size: 341794 bytes.
- Post-run agent log size: 349640 bytes.
- Pre-run `SignalJournal.csv` size: 94740 bytes.
- Post-run `SignalJournal.csv` size: 348570 bytes.
- Pre-run `OrderJournal.csv` size: 260 bytes.
- Post-run `OrderJournal.csv` size: 924 bytes.
- Pre-run `TradeJournal.csv` size: 368 bytes.
- Post-run `TradeJournal.csv` size: 1400 bytes.

## Runtime result

- Tester synchronized real ticks from 2026.06.19 to 2026.07.09.
- Tester ran `generating based on real ticks`.
- Run completed normally.
- Result: `417423 ticks`, `276 bars`, `Test passed in 0:03:06.272`.
- Final tester balance: `10000.00 USD`.
- `OnTester result 0` is expected because this evidence class is journal-routing proof, not performance proof.

## Signal suffix summary

```text
Total new signal rows: 880
Accepted: FBO BUY = 1, FBO SELL = 2
Central-risk rejected winner: FBO BUY = 1
Strategy/arbitration rejected rows include BO, FBO, TP, MR and both BUY/SELL directions.
```

Condensed count by strategy/direction/status/reason:

```csv
count,strategy,direction,status,reason_code
1,FBO,BUY,ACCEPTED,0
2,FBO,SELL,ACCEPTED,0
1,FBO,BUY,REJECTED,8
4,FBO,BUY,REJECTED,24
1,FBO,SELL,REJECTED,24
13,FBO,BUY,REJECTED,23
14,FBO,SELL,REJECTED,23
91,FBO,BUY,REJECTED,5
91,FBO,SELL,REJECTED,5
2,FBO,SELL,REJECTED,25
7,BO,SELL,REJECTED,24
9,BO,SELL,REJECTED,23
110,BO,BUY,REJECTED,5
94,BO,SELL,REJECTED,5
1,TP,BUY,REJECTED,23
1,TP,SELL,REJECTED,23
109,TP,BUY,REJECTED,5
109,TP,SELL,REJECTED,5
10,MR,BUY,REJECTED,23
10,MR,SELL,REJECTED,23
100,MR,BUY,REJECTED,5
100,MR,SELL,REJECTED,5
```

Accepted signal rows:

```csv
2026.06.22 07:05:00,XAUUSD,1,FBO,BUY,FBO_BUY_1782111900,201,210,ACCEPTED,0,FBO Long: reclaim above 4170.75,...
2026.06.22 12:15:00,XAUUSD,1,FBO,SELL,FBO_SELL_1782130500,200,210,ACCEPTED,0,FBO Short: reclaim below 4209.44,...
2026.06.22 13:20:00,XAUUSD,1,FBO,SELL,FBO_SELL_1782134400,200,210,ACCEPTED,0,FBO Short: reclaim below 4212.42,...
```

Risk-rejected winner:

```csv
2026.06.22 18:55:00,XAUUSD,1,FBO,BUY,FBO_BUY_1782154500,201,210,REJECTED,8,Risk: Stop too far: 1585.0 > 1000,...
```

Order rows are separate:

```csv
2026.06.22 07:05:00,ORDER_TYPE_BUY,4174.04000,0.12,4166.14000,4185.69000,0,4174.14000,10.0,0,6,QB_FBO_SHADOW
2026.06.22 12:15:00,ORDER_TYPE_SELL,4205.23000,0.11,4213.65000,4195.39000,0,4205.13000,10.0,0,6,QB_FBO_SHADOW
2026.06.22 13:20:00,ORDER_TYPE_SELL,4210.31000,0.14,4216.96000,4199.40000,0,4210.21000,10.0,0,6,QB_FBO_SHADOW
```

Trade rows are separate:

```csv
FBO,48318009,2026.06.22 07:05:00,2026.06.22 08:10:33,LONG,4174.14000,4185.59000,0.12,4166.14000,4185.69000,116.10,-0.84,0.00,115.26,1.43,11.86000,-0.60000,0,3,2,19.0,10.0
FBO,86759083,2026.06.22 12:15:00,2026.06.22 13:11:49,SHORT,4205.13000,4213.97000,0.11,4213.65000,4195.39000,-97.24,-0.77,0.00,-98.01,-1.04,3.62000,-8.74000,1,1,1,20.0,10.0
FBO,94212491,2026.06.22 13:20:00,2026.06.22 14:04:45,SHORT,4210.21000,4210.33000,0.14,4216.96000,4199.40000,-1.68,-0.98,0.00,-2.66,-0.02,6.35000,-4.29000,1,1,2,20.0,10.0
```

## Verdict for this evidence item

The organic post-repair signal-journal blocker is closed. BUY and SELL directions are preserved; signal IDs include direction; strategy-level rejections remain rejected; arbitration/risk rejections remain rejected; accepted rows appear only after final decision; and order/fill outcomes are journaled separately.
