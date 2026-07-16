# Alert push fail-closed patch note

Date: 2026-07-16

Scope:
- `MQL5/Include/QuantBeast/UI/Alerts.mqh`

Change summary:
- `SendAlert()` now returns the actual `SendNotification()` result when push is enabled.
- Push failures emit a warning via `QBLogWarn()`.
- Tester-mode alerts remain suppressed and return true.
- Header comment now states push delivery is fail-closed and email is not configured.

Validation references:
- Compile log: `compile_alert_patch.log`
- Tester log: `C:\Program Files\MetaTrader 5\Tester\Agent-127.0.0.1-3000\logs\20260716.log`

Boundary:
- The helper remains disconnected from the main EA runtime, so this patch is a source-level correctness fix and documentation correction, not end-to-end alert delivery proof.
