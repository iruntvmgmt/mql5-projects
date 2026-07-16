# MT5 MCP first-pass report — 2026-07-13

## Scope

- EA source: `NAS100_Nexus_EA.mq5`
- Compiled artifact: `NAS100_Nexus_EA.ex5`
- Intended screen baseline: NASUSD, M5, 2025-01-01 through 2025-03-01, one-minute OHLC, USD 100 deposit, 1:100 leverage.
- No live trading was enabled and no orders were placed.

## Outcome

A new baseline for the current build was **not completed**. The MCP server process answers tool calls, but the live bridge, compilation path, and automated Strategy Tester launch are not yet reliable. The final blocker is that MT5 no longer has a usable saved Coinexx account session, so Strategy Tester reports `tester not started because the account is not specified`.

The user must sign back into the desired MT5 account through the normal MT5 application before the automated tester can be retried. Credentials were not requested, read, or modified by the agent.

## What worked

- MCP tool discovery worked. Tools for status, compilation, tester launch/status, log tailing, report parsing, and Nexus daily-result parsing were callable.
- `backtest_status` accurately reported that no MetaTester process was running.
- `tail_mt5_log` successfully read both terminal and tester logs.
- `read_daily_results` found and parsed an older Nexus daily CSV.
- MT5 paths and the EA allow-list were recognized correctly.
- MT5 previously recognized `NASUSD`, and earlier tester logs contain NASUSD M5 research events.

## Access and server challenges

### 1. Live bridge unavailable

`mt5_status` returned:

- `bridge_connected: false`
- host `localhost`
- port `8228`

Consequences:

- `list_charts` failed to connect.
- Current quotes, account metadata, symbol contract properties, and chart operations could not be obtained through the MCP bridge.

Recommended fix:

- Confirm the MT5 bridge EA/service is installed, attached, allowed to run, and listening on port 8228.
- Add a bridge health/startup diagnostic that distinguishes “terminal absent,” “bridge EA absent,” and “port unavailable.”

### 2. Compilation did not produce a verifiable result

`compile_mql5` returned process exit code 0 but reported:

- `success: false`
- `output_updated: false`
- `MetaEditor did not update its compiler log.`

The existing EX5 was newer than the source, so a runnable artifact existed, but this MCP compile call could not prove that the current source compiled cleanly.

Recommended fix:

- Use a unique per-run compiler log or record the compiler log timestamp before launch.
- Verify the output hash as well as modification time.
- Capture MetaEditor stdout/log output even when MetaEditor exits with code 0.

### 3. `start_backtest` timed out while a terminal instance was open

The first automated launch returned:

`MT5 did not start a MetaTester agent within 20 seconds. The running single-instance terminal may have ignored /config.`

Closing the normal terminal allowed the generated configuration to be read, but a tester agent still did not start.

Recommended fix:

- Detect an existing terminal before launching and return a specific actionable status.
- Support a safe “request terminal shutdown and retry” workflow.
- Allow a startup timeout longer than 20 seconds, particularly under Wine.

### 4. Generated tester configuration needs validation

The generated file initially contained:

- `Expert=NAS100_Nexus/NAS100_Nexus_EA`
- `Leverage=100`
- no `Login` field
- an absolute report path

MT5’s documented startup format uses a Windows-style expert path, leverage such as `1:100`, and an emulated tester login. The diagnostic copy was changed to:

- `Expert=NAS100_Nexus\NAS100_Nexus_EA`
- `Leverage=1:100`
- `Login=1001470`
- a relative report path

MT5 then accepted the configuration but still refused the test because the account was unavailable.

Recommended fix:

- Add schema-level validation and an optional `login` argument to `start_backtest`.
- Serialize leverage as `1:N`.
- Serialize EA paths with Windows separators.
- After launch, parse terminal errors such as `account is not specified` instead of returning only the generic 20-second timeout.

### 5. Account/security state became unusable during command-line fallback

During direct Wine-prefix diagnostics, terminal logs reported:

- `Accounts deleted due security reason`
- `users.dat file encryption invalid [13]`
- `chats.dat file encryption invalid [13]`

The normal MT5 application subsequently opened without reconnecting to Coinexx. This fallback should not be used again. It demonstrates that launching MT5 outside its normal macOS application context can invalidate encrypted terminal state.

Required recovery:

1. Open the normal MetaTrader 5 application.
2. Sign back into the desired Coinexx account manually.
3. Confirm NASUSD quotes are updating.
4. Do not provide credentials to the agent.

Recommended server fix:

- Launch through the signed macOS application wrapper or the same environment it establishes; do not invoke the Wine terminal binary in a security context that invalidates encrypted state.

### 6. No standard tester report was available

`read_backtest_summary` reported that no HTML/XML report existed in the Tester directory. The older test had been stopped by the user before completion, so it never produced a complete standard report.

### 7. Older daily results are not a current-build baseline

The parser found `NASUSD_M5_daily_v041.csv` with:

- 54 completed daily rows
- 6 outcomes
- 2 wins / 4 losses
- -0.6272 R
- end research equity USD 99.31
- -0.6856% simulated return
- 3.2709% maximum simulated drawdown

This run was interrupted on 2025-03-03 and used an older build/parameter set. Its wins were approximately +1.9 R after costs, inconsistent with the current source’s 1.5 R target. It must not be treated as evidence for the current EA.

Recommended parser fix:

- Include EA source/EX5 hash, EA version, input parameters, test dates, model, symbol, and run ID in every CSV and parser response.
- Avoid selecting an older CSV merely because it is the newest file present.

## Fast recovery sequence

After manual MT5 login is restored:

1. Verify the account and NASUSD through `mt5_status`/`get_quote` or terminal logs.
2. Restore/start the bridge on port 8228.
3. Retry compile and require an updated log or matching source/output hash.
4. Run a short 2025-01-01 through 2025-03-01 one-minute-OHLC screening pass.
5. Read the new daily CSV and standard report.
6. If the screen is not clearly negative, run a narrower real-tick confirmation window.

## EA-specific caution

The current EA is research-only. `InpEnableTrading` is reserved and there is no order-placement path. Its USD 100 equity is simulated through R-multiples; this does not prove that the broker’s minimum NASUSD volume can risk USD 0.50–1.00 per setup.

## Follow-up after MetaQuotes-Demo login

- Demo login was confirmed and MT5 synchronized successfully with MetaQuotes-Demo.
- The corrected tester configuration reached MT5 with an explicit demo `Login` value.
- MT5 then returned the definitive error: `symbol NASUSD not exist`.
- MetaQuotes-Demo therefore cannot provide a valid baseline for this NASUSD-specific EA. A broker demo offering the same NASUSD contract and history is required; substituting an unrelated forex pair or futures contract would not validate this strategy.
- MT5 updated to build 6002 and exposed a native MCP listener at `127.0.0.1:22346/mcp`. It responded correctly but requires a bearer key stored in a terminal-only encrypted form, so the existing external MCP server cannot reuse it directly.

## MCP server patch prepared

`/Users/matt/Tools/mt5-mcp/Tools/HostTools.cs` was updated to:

- accept an optional 64-bit tester `login` argument;
- emit the documented `Login=` tester field;
- serialize EA paths with Windows separators;
- serialize leverage as `1:N`;
- wait up to 60 seconds for MetaTester instead of 20 seconds;
- return a more useful timeout message directing the operator to account, symbol, EA-path, and single-instance errors.

Both Debug and Release builds completed with zero warnings and zero errors. The running MCP process must be restarted before its exposed tool schema includes the new `login` argument.

## Server repair completed (v0.2.0)

- Root cause of bridge disconnection: `MtApi5.ex5` and `MT5Connector.dll` were not installed in the active MT5 environment.
- Official MtApi v2.0.0 x64 payload was inspected and the two runtime files were installed. MSI SHA-256: `e1c2eac4c8d5e3fb9fb6043aa37c5940f81522274a3ed974ec9b84f4284a45f8`.
- `mt5_status` now probes port 8228, checks both bridge files, and returns exact bridge blockers.
- `compile_mql5` now watches the real installation-level UTF-16 compiler log, requires a source-specific `0 errors` summary, reports EX5 freshness and SHA-256, and fails truthfully when Wine cannot launch.
- `start_backtest` now verifies the EX5 exists, rejects a running single-instance terminal without killing it, shuts down only its dedicated terminal after a run, and returns new terminal-log errors instead of a generic timeout.
- `read_daily_results` no longer chooses an unfiltered newest CSV. It requires an explicit path or symbol filter and returns file timestamp/SHA-256 provenance.
- Release build completed with zero warnings and zero errors.

Remaining interactive step: attach `MtApi5` to one MT5 chart with DLL imports enabled and port 8228. The bridge port remains closed until that is done. In this Codex sandbox, direct child Wine processes cannot join the already-running Wine server; the corrected compile tool returns this as a failure with the real stderr. A normally launched VS Code host should be tested separately because it does not necessarily share this sandbox boundary.
