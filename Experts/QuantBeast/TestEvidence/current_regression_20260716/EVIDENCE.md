# Current regression evidence — 2026-07-16

## Purpose

Revalidate the current QuantBeast source after the manual demo broker lifecycle evidence and live broker-transmission acknowledgement gate work.

This is a broker-free Strategy Tester Shadow regression. It is not live/demo EA-autonomous execution evidence.

## Startup and environment

- Required MT5 MCP `get_workspace_info` call succeeded.
- Compiler capability: available, MetaEditor build 6002.
- Tester capability: available.
- Pre-run process check found MT5 terminal and wineserver only; no MetaEditor/tester process was active before launch.
- Temporary tester launcher config was copied to `MQL5/Profiles/Tester` for the run and removed after the run.

## Compile

```text
2026.07.16 13:29:54.162 Compile MQL5\Experts\QuantBeast\QuantBeastEA.mq5 - 0 errors, 0 warnings, 21189 ms elapsed, cpu='X64 Regular'
```

## Tester configuration

- Evidence config: `QuantBeast.CurrentRegression.XAUUSD.M5.20260716_1329.ini`
- EA: `QuantBeast\QuantBeastEA.ex5`
- Symbol/timeframe: `XAUUSD`, `M5`
- Model: `1` generated ticks
- Window: `2026.05.18` to `2026.05.22`
- Deposit/currency/leverage: `10000`, `USD`, `500`
- Mode: Shadow (`InpMode=1`)
- Live broker acknowledgement: `false`
- Challenge acknowledgement: `false`
- Persistence/global variables: disabled
- File journals: disabled
- Self-tests: enabled

## Boundary

The tester MCP returned the known unreliable result:

```text
{ "ok": true, "job_id": 0 }
```

The pass is therefore based on the newly appended local tester-agent log suffix, bounded by `pre_run_boundary.txt`.

## Result

```text
Self-tests complete: 51 passed, 0 failed
Tester final balance 10000.00 USD
Tester OnTester result 0
XAUUSD,M5: 22080 ticks, 1104 bars generated
Test passed in 0:00:22.242
```

No broker orders were transmitted by this run.

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5 sha256=8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49 bytes=100657
MQL5/Experts/QuantBeast/QuantBeastEA.ex5 sha256=352c6be5f415370c9548315aea4a5dad9cb645f022c8a0afd9bb37cbc61ad1d3 bytes=484760
MQL5/Include/QuantBeast/Core/Configuration.mqh sha256=287d8f29198bd829367fcc49650c849afafd5fe95b289411c77a92ab2a9635e6 bytes=21932
```

## Evidence files

- `pre_run_boundary.txt`
- `agent_log_suffix.txt`
- `regression_summary.txt`
- `hashes_post_test.txt`
- `QuantBeast.CurrentRegression.XAUUSD.M5.20260716_1329.ini`

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

The run does not prove QuantBeast EA-autonomous demo execution, live broker protection management, real broker fault handling, or normal-terminal restart recovery.
