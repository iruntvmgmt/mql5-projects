# Conservative Live Strategy Tester FBO attempt — 2026-07-16

## Purpose

Attempt a broker-free Strategy Tester run of QuantBeast in `QB_MODE_CONSERVATIVE_LIVE` with the current live gates:

- FBO only;
- market orders only;
- no pending orders;
- Challenge acknowledgement false;
- live broker-transmission acknowledgement true, intended for Strategy Tester only.

This was intended to exercise EA-autonomous live-order routing inside the Strategy Tester without touching the connected demo broker account.

## Pre-run broker state

The connected Coinexx demo broker account had:

```text
positions=[]
orders=[]
balance/equity=980.40 USD
```

## Attempts

Three launcher variants were tried:

1. Inline optimization-style `[TesterInputs]` override with `InpAcknowledgeLiveBrokerRisk=true`.
2. Separate `.set` file passed through the MT5 tester API `inputs_path`.
3. Plain `[TesterInputs]` key/value override with `InpAcknowledgeLiveBrokerRisk=true`.

In all three cases, the tester applied `InpMode=2`, but the live-ack input was not applied/exposed in the tester input log. QuantBeast failed closed at startup:

```text
Live broker-transmission gate blocked initialization: Live broker transmission requires explicit InpAcknowledgeLiveBrokerRisk=true
tester stopped because OnInit returns non-zero code 1
```

## Evidence files

- `gate_block_agent_log_suffix.txt`
- `set_retry_gate_block_agent_log_suffix.txt`
- `plain_gate_block_agent_log_suffix.txt`
- `gate_block_summary.txt`
- launcher configs and attempted `.set` file preserved in this evidence directory

Temporary files copied into `MQL5/Profiles/Tester` were removed after the attempts.

## Result

Blocked.

The attempt proves the production live broker-transmission acknowledgement gate fails closed in Strategy Tester when the acknowledgement is not effectively applied. It does not prove EA-autonomous Conservative Live order execution, broker callback handling, protection management, or restart recovery.

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

No broker orders were transmitted and no demo broker positions/orders were opened by these tester attempts.
