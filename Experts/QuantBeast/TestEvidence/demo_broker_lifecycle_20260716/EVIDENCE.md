# Demo Broker Lifecycle Evidence — 2026-07-16

## Scope

This evidence records the first explicitly authorized broker-exposure validation for QuantBeast development.

Account:

- Broker/server: `Coinexx Limited` / `Coinexx-Demo`
- Account type: demo
- Login: `871221`
- Margin mode: hedging
- Currency: USD
- Terminal build: 6002
- Symbol: `XAUUSD`

Boundary:

- These trades were placed through the native MT5 MCP trading controls after explicit operator authorization.
- This proves demo broker order placement, fill, close, account-history visibility, and no-exposure cleanup.
- This does **not** yet prove autonomous QuantBeast EA strategy-to-order live execution, EA restart reconciliation, EA protection management, or challenge/live readiness.

## Pre-trade state

Before the first authorized order:

```text
positions: []
orders: []
account balance/equity: 979.56 / 979.56 USD
```

Before the second authorized order:

```text
position_id=34601163 XAUUSD BUY 0.01 open_price=4010.53
orders: []
```

## Authorized entries

### Entry 1

Operator instruction:

```text
Place demo market order: XAUUSD BUY 0.01
```

Broker result:

```text
retcode=10009
order=34601163
deal=31610668
position_id=34601163
symbol=XAUUSD
side=BUY
volume=0.01
fill_price=4010.53
open_time=2026.07.16 18:51:01
commission=-0.01
comment=QB demo validation
```

### Entry 2

Operator instruction:

```text
Place demo market order: XAUUSD BUY 0.01
```

Broker result:

```text
retcode=10009
order=34601183
deal=31610688
position_id=34601183
symbol=XAUUSD
side=BUY
volume=0.01
fill_price=4011.41
open_time=2026.07.16 18:51:53
commission=-0.01
comment=QB demo validation
```

## Authorized closes

Operator instruction:

```text
Close both validation positions and record the full broker lifecycle evidence.
```

### Close 1

```text
closed_position=34601163
close_order=34601232
close_deal=31610736
retcode=10009
close_side=SELL
volume=0.01
close_price=4011.00
close_time=2026.07.16 18:53:19
gross_profit=0.47
total_commission=-0.02
```

### Close 2

```text
closed_position=34601183
close_order=34601245
close_deal=31610750
retcode=10009
close_side=SELL
volume=0.01
close_price=4011.82
close_time=2026.07.16 18:53:25
gross_profit=0.41
total_commission=-0.02
```

## Final broker state

After both closes:

```text
positions: []
orders: []
balance=980.40
equity=980.40
margin=0.00
margin_free=980.40
floating_profit=0.00
```

## Position history summary

```text
position_id=34601163 type=buy symbol=XAUUSD open=2026.07.16 18:51:01 volume=0.01 open_price=4010.53 close=2026.07.16 18:53:19 close_price=4011.00 commission=-0.0200 profit=0.4700
position_id=34601183 type=buy symbol=XAUUSD open=2026.07.16 18:51:53 volume=0.01 open_price=4011.41 close=2026.07.16 18:53:25 close_price=4011.82 commission=-0.0200 profit=0.4100
```

## Current build hashes at evidence capture

```text
Experts/QuantBeast/QuantBeastEA.mq5	sha256=b9d2950a56a94838fc4765ca418f8f9c40e1d59006ad1dcef760f99c44276d20	bytes=99454
Experts/QuantBeast/QuantBeastEA.ex5	sha256=f32f2df50f3c6c76fe64a5df5419a68a1f2d3fe30559f9c6f6c4c6641e2140c5	bytes=482994
```

## Readiness impact

This evidence removes the blanket claim that no demo broker order has ever been transmitted during the audit. It proves only the manual/MCP demo broker lifecycle.

Readiness remains:

```text
READY FOR SHADOW MODE
```

Promotion beyond Shadow still requires QuantBeast EA-controlled demo execution, protection management, restart reconciliation, and fault/recovery validation under bounded risk.
