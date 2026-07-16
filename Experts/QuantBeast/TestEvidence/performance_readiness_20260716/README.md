# Performance Readiness Configs - 2026-07-16

These configs are reproducible Shadow-mode baselines. They are not optimization runs and do not claim profitability.

Common settings:

- Symbol/timeframe: XAUUSD M5.
- Tester model: `4`, every tick based on real ticks.
- Deposit/leverage: 10000 USD, 1:500.
- Mode: Shadow (`InpMode=1`).
- Challenge acknowledgement: false.
- Self-tests, persistence, global variables, news, dashboard, and debug logging disabled.
- Signal/order/trade journals enabled for evidence.

Windows:

- Training: 2026.06.22 to 2026.06.26.
- Untouched holdout: 2026.06.29 to 2026.07.03.

Created configs:

- `QuantBeast.Perf.Combined.Train.XAUUSD.M5.20260622_20260626.ini`
- `QuantBeast.Perf.Combined.Holdout.XAUUSD.M5.20260629_20260703.ini`
- `QuantBeast.Perf.BO.Train.XAUUSD.M5.20260622_20260626.ini`
- `QuantBeast.Perf.FBO.Train.XAUUSD.M5.20260622_20260626.ini`
- `QuantBeast.Perf.FBO.Holdout.XAUUSD.M5.20260629_20260703.ini`
- `QuantBeast.Perf.TP.Train.XAUUSD.M5.20260622_20260626.ini`
- `QuantBeast.Perf.MR.Train.XAUUSD.M5.20260622_20260626.ini`

Boundaries:

- These configs are under project evidence, not MT5 profile state.
- Temporary `Profiles/Tester` launcher copies may be created only for a run and should be removed afterward.
- Do not optimize against the holdout.
- Do not promote readiness from any profitable result in these windows.
