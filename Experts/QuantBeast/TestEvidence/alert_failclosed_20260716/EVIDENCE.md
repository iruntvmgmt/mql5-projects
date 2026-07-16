# Alert delivery fail-closed propagation evidence - 2026-07-16

## Defect

`CAlerts::SendAlert()` returned `false` when `SendNotification()` failed, but `QuantBeastEA.mq5` discarded the result in `EmitConfiguredAlert()`. That meant a configured push-alert delivery failure could be logged by the helper while the controller continued with no control-flow consequence.

## Severity

Medium safety/observability defect.

If an operator intentionally enables a critical alert category with push notifications, silent delivery failure undermines monitoring assumptions. It does not by itself transmit broker orders or alter strategy selection.

## Affected paths

- `MQL5/Include/QuantBeast/UI/Alerts.mqh`
- `MQL5/Experts/QuantBeast/QuantBeastEA.mq5`

## Fix

- Added `QBConfiguredAlertSucceeded(enabled, sendResult)` as a pure helper.
- Extended `QBTestAlertRouting()` to verify disabled alerts are considered OK and enabled delivery failure is interpreted as fail-closed.
- Changed `EmitConfiguredAlert()` to return `bool` and skip disabled alerts as success.
- When an enabled configured alert returns failure, the EA logs an error, activates the existing entry kill, persists runtime state, and returns `false`.
- Strategy Tester behavior remains unchanged because tester-mode alert emission is suppressed and returns success.

## Compile status

Fresh compile evidence is blocked in this turn.

Attempts made:

```text
metaeditor64.exe /compile:'C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\QuantBeastEA.mq5' /log:'C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\TestEvidence\alert_failclosed_20260716\compile.log'
metaeditor64.exe '/compile:C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\QuantBeastEA.mq5' '/log:C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\TestEvidence\alert_failclosed_20260716\compile.log'
metaeditor64.exe '/compile:MQL5\Experts\QuantBeast\QuantBeastEA.mq5' /log
```

Each invocation exited at process code 0, but neither `QuantBeastEA.ex5` nor any compile log timestamp changed. Therefore no fresh compiler result is claimed.

Last observed artifact timestamps after attempts:

```text
QuantBeastEA.mq5 modified: 2026-07-16T20:27:00Z
QuantBeastEA.ex5 modified: 2026-07-16T18:50:08Z
QuantBeastEA.log modified: 2026-07-15T22:23:14Z
```

## Validation status

- Source inspection: edited blocks read back correctly.
- Compile: blocked/unknown, no fresh compiler artifact.
- Tester: not run because current `.ex5` is stale relative to source.
- Broker orders: none transmitted.

## Required next action

Run a fresh MetaEditor compile through the known working local workflow or expose/use an MCP compile endpoint. Only after a current `0 errors, 0 warnings` compile should the Shadow startup fixture be rerun to confirm `TEST 41 PASS` includes `failClosed=yes`.
