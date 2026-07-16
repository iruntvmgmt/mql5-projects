# QuantBeast alert routing evidence — 2026-07-16

## Defect

Alert inputs were declared and documented, and `Include/QuantBeast/UI/Alerts.mqh` existed, but the EA did not include, initialize, or call the alert component. As a result, `InpAlertSignalAccepted`, `InpAlertSignalRejected`, `InpAlertOrderRejected`, `InpAlertKillSwitch`, `InpAlertUnprotectedPos`, and `InpSendPushNotifications` were disconnected controls.

## Severity

Medium operational defect. The issue did not create broker exposure, but it made operator-facing safety controls misleading because configured warnings could never fire.

## Fix

- Included and initialized `CAlerts` in `QuantBeastEA.mq5`.
- Added tester-safe alert suppression so Strategy Tester validation records routing without sending terminal or push alerts.
- Routed key signal-rejection, signal-acceptance, order-rejection, and protection-emergency events through configured alert flags.
- Added deterministic alert-routing self-test coverage.

## Validation

- Compile: `0 errors, 0 warnings` at `2026-07-16 10:26:35`
- Shadow regression: `43 passed, 0 failed`
- Model: generated ticks, broker-free Shadow only
- Ticks/bars: `22080` ticks, `1104` bars
- Final balance: `10000.00 USD`
- Tester result: `OnTester result 0`

## Hashes

- Source SHA-256: `2b1dead892b25081d026d63b696776f201f9d2c132e5ea641f2588dcc529685a`
- Alerts SHA-256: `7e517231b8a037761627ad687c7364e089d6c8a1d8634ee0ed6038b824433778`
- EX5 SHA-256: `bed035a8f6b03fe73defde9fac0dd7e641e4b18b3b7f3e09691bb9b507dceb3b`

No broker orders were transmitted.
