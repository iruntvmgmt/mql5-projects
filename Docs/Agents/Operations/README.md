# MT5 macOS/Wine Operational Bridge

**Status:** Canonical operational procedure for agent-driven MT5 work on this repository  
**Applies to:** QuantBeast, MultiSpeedZigZag, and any future repository-authorized MQL5 work  
**Authority:** Supplements root `AGENTS.md`, active project handoffs, frozen specifications, agent role files, and task tickets

## Purpose

This directory documents the proven non-GUI operating bridge used to compile and execute MQL5 code on the repository's macOS/Wine MetaTrader 5 environment.

The central rule is:

> MCP is not the universal execution bridge. MQL5 compilation, scripts, and Strategy Tester runs use separate proven paths.

Agents must choose the bridge that matches the artifact:

```text
MQL5 compile
  -> isolated MetaEditor via Wine `start /Unix`

MQL5 Script
  -> isolated `terminal64.exe /portable /config:<ini>`
  -> `[StartUp] Script=...`

Expert Advisor Strategy Tester
  -> isolated `terminal64.exe /portable /config:<ini>`
  -> `[Tester] Expert=...`

Main terminal inspection or supported terminal operations
  -> native MCP, only when the active ticket targets that terminal
```

## Environment map

### Canonical source tree

```text
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

### Wine executable

```text
/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine
```

### Main installed MT5 root

```text
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5
```

### Current isolated MultiSpeedZigZag runtime

```text
/Users/matt/MT5-MSZZ-TEST
```

A task may authorize another isolated runtime. The ticket must name it explicitly.

## Mandatory reading order for runtime work

1. Root `AGENTS.md`
2. Active project handoff
3. Active ticket
4. Role document
5. `MT5_MACOS_WINE_OPERATIONAL_BRIDGE.md`
6. `INI_CONFIG_REFERENCE.md`
7. `PROCESS_AND_PID_PROTOCOL.md`
8. `LOG_AND_ARTIFACT_PROTOCOL.md`
9. `FAILURE_RECOVERY_MATRIX.md`
10. `RUNTIME_EVIDENCE_TEMPLATE.md`

## Files in this directory

- `MT5_MACOS_WINE_OPERATIONAL_BRIDGE.md` — authoritative end-to-end procedures.
- `INI_CONFIG_REFERENCE.md` — script and tester configuration formats.
- `PROCESS_AND_PID_PROTOCOL.md` — main/isolated terminal ownership and safe termination.
- `LOG_AND_ARTIFACT_PROTOCOL.md` — log encodings, fresh boundaries, output locations, and provenance.
- `FAILURE_RECOVERY_MATRIX.md` — known failure modes and required recovery sequence.
- `COMMAND_COOKBOOK.md` — copyable shell patterns with safety notes.
- `RUNTIME_EVIDENCE_TEMPLATE.md` — required runtime report format.

## Non-negotiable rules

- Do not route MQL5 Script execution through Strategy Tester merely because MCP lacks a script tool.
- Do not copy isolated-test harnesses into the main MT5 installation as a fallback.
- Do not use process exit as proof of compile or runtime success.
- Do not trust stale logs, reports, binaries, or output files.
- Do not issue duplicate tester or portable-terminal launches while a prior run is active.
- Do not kill a terminal process unless its PID and command line prove it belongs to the active ticket.
- Do not print or commit bearer tokens, account credentials, or private configuration.
- Do not claim cross-language parity unless Python and MQL artifacts were independently authored.
- Do not assume one universal `MQL5/Files` output directory; execution mode determines the sandbox.
- Do not modify strategy semantics in order to make the runtime bridge work.

## Provenance

These procedures are derived from successful repository work in which isolated MetaEditor builds compiled through `wine start /Unix`, portable terminal processes executed `[StartUp] Script=` configurations, Strategy Tester runs used `[Tester]` configurations, UTF-16LE logs were decoded, cumulative logs were sliced to the fresh run, and staged source files were SHA-256 verified before execution.
