# MT5 INI Configuration Reference

## 1. Purpose

MT5 uses different configuration sections for different execution modes. Agents must not confuse script startup with Strategy Tester execution.

## 2. MQL5 Script configuration

Use `[StartUp]` for an MQL5 Script:

```ini
[StartUp]
Script=MultiSpeedZigZagTests\Test_MSZZ_MC_CANON2_CertifiedJournal
Symbol=XAUUSD
Period=M5
```

Rules:

- `Script=` is relative to `MQL5/Scripts/`.
- Omit `.mq5` and `.ex5`.
- Use Windows-style backslashes inside the MT5 configuration.
- The corresponding EX5 must already exist in the isolated runtime.
- A script may complete while the terminal process remains running.
- Determine completion through fresh log markers and output artifacts.

## 3. Read-only diagnostic script configuration

```ini
[StartUp]
Script=MSZZ_Inventory_Diagnostic
Symbol=XAUUSD
Period=M5
```

A diagnostic script must be authorized by the implementation owner and must not place, modify, or close orders.

## 4. Strategy Tester configuration

Use `[Tester]` for Expert Advisor backtests:

```ini
[Tester]
Expert=MultiSpeedZigZagEA
Symbol=XAUUSD
Period=M5
Optimization=0
Model=2
FromDate=2026.07.20
ToDate=2026.07.24
ForwardMode=0
Deposit=10000
Currency=USD
Leverage=100
ExecutionMode=0
Report=Reports\MC2_ticket_report
ReplaceReport=1
ShutdownTerminal=1
```

The ticket or existing approved preset must define all settings. Do not infer dates, model, deposit, leverage, execution mode, or EA inputs.

## 5. Inputs

When an approved test requires inputs, use the repository's established configuration convention. Record every input in the runtime evidence report.

Do not:

- change parameters to force activity;
- enable live execution;
- alter safety acknowledgements;
- substitute a different preset without authorization;
- use a production account configuration.

## 6. File placement

Place task-specific INI files in the isolated MT5 root unless an existing proven task procedure specifies another location.

Example:

```text
/Users/matt/MT5-MSZZ-TEST/certified_journal_start.ini
```

Then launch with:

```text
/config:certified_journal_start.ini
```

Record the INI path and SHA-256 before launch.

## 7. Naming standard

Use ticket-specific names:

```text
<ticket-short-name>_start.ini
<ticket-short-name>_tester.ini
```

Avoid generic names such as `test.ini`, which make process ownership and artifact attribution ambiguous.

## 8. Validation checklist

Before launch verify:

- correct section: `[StartUp]` or `[Tester]`;
- correct script/expert identifier;
- correct symbol and period;
- exact ticket dates and model;
- safe execution inputs;
- report path does not overwrite unrelated evidence;
- `ShutdownTerminal` behavior is understood;
- INI SHA is recorded;
- no credentials are embedded.

## 9. Forbidden substitutions

- Do not run a Script as an Expert merely because MCP exposes tester functions.
- Do not create an EA wrapper without specification-owner authorization.
- Do not copy the INI into the main terminal as a fallback.
- Do not use a `[Tester]` configuration to claim Script-runtime parity.
- Do not assume a successful terminal spawn means the requested artifact executed.
