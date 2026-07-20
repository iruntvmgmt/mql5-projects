# QuantBeast Agent Instructions

## Working directory

This file and the entire project tree live at:

```text
~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

This is the **one true working tree**. All edits, compiles, and tests
always happen here. A second clone of this repository must never be
used in parallel — doing so caused the 2026-07-16 hash-drift incident
where commits from two different working copies diverged silently.
Always verify you are in this exact directory before touching any file.

The `origin` remote (forge.mql5.io/matious/mql5) was removed on
2026-07-16. It was an unused MQL5 Algo Forge skeleton with a single
"Initial commit" and an unrelated git history. The only active remote
is `github` (iruntvmgmt/mql5-projects). Do not re-add `origin` or any
other remote without explicit instruction.

## Scope

This file exists to govern work on the QuantBeast project only.

Unless the user explicitly expands scope, agents may edit:

- `MQL5/Experts/QuantBeast/**`
- `MQL5/Include/QuantBeast/**`
- This `MQL5/AGENTS.md`
- Any other file that clearly exists to support QuantBeast
  development -- e.g. `MQL5/Scripts/QuantBeast*.mq5` test/fixture
  scripts, `MQL5/Profiles/Tester/QuantBeast*.ini` tester configs --
  identifiable by a `QuantBeast`/`QB` name prefix or by content that
  plainly references the QuantBeast project.

Do not modify, rename, move, compile over, delete, or reformat
unrelated indicators, Expert Advisors, profiles, presets, logs, or
MetaTrader installation files -- including ones that happen to sit
near QuantBeast files but are not part of it.

## Project status

QuantBeast is an incomplete framework and is **not approved for live trading**. Source presence is not proof of correct behavior. `Experts/QuantBeast/BUILD_AUDIT.md` and `BUG_AUDIT.md` preserve the generated-code baseline; the current repaired-state verdict is in `Experts/QuantBeast/REPAIR_AUDIT_20260715.md`.

The living task state is in `Experts/QuantBeast/HANDOFF.md`. Read it before every task and update it after every task that changes source, configuration, documentation, test evidence, or project status.

## Required reading order

Before changing code, read these files in order:

1. `Experts/QuantBeast/HANDOFF.md`
2. `Experts/QuantBeast/PROJECT_MISSION_AND_AUDIT_CONTEXT.md`
3. `Experts/QuantBeast/README.md`
4. `Experts/QuantBeast/ARCHITECTURE.md`
5. `Experts/QuantBeast/KNOWN_LIMITATIONS.md`
6. `Experts/QuantBeast/BUILD_AUDIT.md`
7. `Experts/QuantBeast/REPAIR_AUDIT_20260715.md`
8. The document relevant to the task:
   - `CONFIGURATION_GUIDE.md`
   - `STRATEGY_SPEC.md`
   - `RISK_SPEC.md`
   - `TESTING_GUIDE.md`
   - `LIVE_DEPLOYMENT_CHECKLIST.md`

The original requirements are in `/Users/matt/Downloads/XAUUSD Quant Beast EA.docx`. If implementation and documentation disagree, report the discrepancy rather than silently choosing one.

## Safety rules

- Never enable Conservative Live or Challenge Live on a real account.
- Never change `InpAcknowledgeChallengeRisk` to `true` in a delivered default or preset.
- Never weaken spread, stop, margin, drawdown, equity-floor, ownership, or kill-switch controls merely to generate trades.
- Never add martingale, averaging down, unlimited grid behavior, loss-recovery sizing, hidden-stop-only trading, or unbounded retries.
- Never transmit orders as part of compilation, static analysis, or ordinary testing.
- Strategy Tester execution must use tester configuration and must not attach the EA to a live chart.
- Treat broker positions and orders as external state. Do not cancel, close, or modify them without explicit user authorization.
- Preserve the default safe operating mode as Shadow unless the user explicitly approves another default after validation.

## Change discipline

Work in small defect groups. One defect group should have one clearly stated purpose and one verification result.

For each group:

1. Reproduce or demonstrate the problem with exact file/line evidence.
2. Classify severity: Critical, High, Medium, Low, or Documentation.
3. Identify affected runtime paths and safety implications.
4. Make the smallest coherent fix.
5. Compile immediately when compilation is available.
6. Run the narrowest relevant deterministic test.
7. Inspect the diff and ensure unrelated behavior was not changed.
8. Update `HANDOFF.md` with files, evidence, results, and remaining work.
9. Update specification documents when behavior or supported configuration changes.

Do not combine bug repair, strategy redesign, parameter optimization, and performance tuning in one change.

## Source-editing rules

- Preserve user changes and unrelated dirty files.
- Prefer focused patches; avoid whole-file rewrites unless required and explained.
- Do not create duplicate implementations to bypass a broken component.
- Remove or explicitly reject unsupported configuration paths; do not silently fall back to another behavior.
- Keep strategies isolated from `CTrade`, `OrderSend`, position modification, and final sizing.
- Keep broker transmission centralized in the execution layer.
- Keep position management independent of signal generation.
- Use confirmed data only; document bar indexes and array-series direction for market-data logic.
- Use correct MQL5 ticket, price, volume, enum, and retcode types.
- Normalize price and volume through broker-aware helpers.
- Validate ownership before modifying any order or position.
- Bound arrays, histories, retries, journal growth, and loops.
- Do not suppress compiler warnings without resolving their cause.

## Documentation contract

The original specification requires nine technical project documents. QuantBeast also has a mandatory mission/audit-context document that governs interpretation of those technical documents:

- `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`
- `README.md`
- `ARCHITECTURE.md`
- `CONFIGURATION_GUIDE.md`
- `STRATEGY_SPEC.md`
- `RISK_SPEC.md`
- `TESTING_GUIDE.md`
- `LIVE_DEPLOYMENT_CHECKLIST.md`
- `KNOWN_LIMITATIONS.md`
- `BUILD_AUDIT.md`

When code changes behavior:

- Update the relevant specification document.
- Update `KNOWN_LIMITATIONS.md` if a limitation is added, changed, or removed.
- Update `BUILD_AUDIT.md` only when evidence changes the status.
- Update `README.md` only for user-facing status or workflow changes.
- Never mark an item complete solely because code was written. Require compile and test evidence.

## Bug-audit protocol

The bug audit is a read-only phase unless the user explicitly asks for fixes in the same task.

Audit in this order:

1. Compile blockers and MQL5 API/type misuse
2. Order ownership and destructive-action safety
3. Unprotected-fill and stop-management safety
4. Risk sizing and account-lock enforcement
5. Transaction lifecycle and position tracking
6. Persistence, restart, and reconciliation
7. Future leakage, indexing, cache, and feature correctness
8. Strategy eligibility, triggers, stops, and targets
9. Arbitration, cooldown, duplicates, and exposure
10. Shadow simulation, journals, performance, and `OnTester`
11. Dashboard, alerts, presets, and inactive inputs
12. Performance, bounded storage, and maintainability

Report each defect with severity, evidence, consequence, reproduction or reasoning, and recommended fix. Separate confirmed defects from suspected risks requiring runtime evidence.

The completed audit must use the output structure required by `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`, including architecture, per-strategy, regime, arbitration, risk, execution, persistence/recovery, test-evidence, known-limitations, and final-readiness sections. Finish with exactly one readiness class:

```text
NOT SAFE TO TEST
READY FOR DIAGNOSTIC MODE
READY FOR SHADOW MODE
READY FOR CONSERVATIVE MICRO-LIVE
READY FOR CHALLENGE-MODE RESEARCH
READY FOR CHALLENGE LIVE
```

The aggressive-growth mission is a design requirement, not permission to weaken safety or assume profitability. Preserve separate strategy engines and Challenge Mode while auditing whether they are mathematically meaningful, reachable, deterministic, bounded, and testable.

## Compilation contract

Target source:

```text
C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\QuantBeastEA.mq5
```

Expected macOS/Wine environment:

```text
WINEPREFIX=/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5
WINE=/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine
METAEDITOR=C:\Program Files\MetaTrader 5\metaeditor64.exe
```

Compilation acceptance requires:

- Zero errors
- Zero warnings
- A newly generated `QuantBeastEA.ex5`
- A compile log tied to the current source timestamp/hash

Do not claim compilation from an old `.ex5` or stale log. If MetaEditor is unavailable or automation is unreliable, record compilation as blocked/unknown.

### Known MetaEditor compilation issue (2026-07-16)

The direct `wine metaeditor64.exe /compile:"<path>"` invocation can
silently stop working without any error, log, or `.ex5` update — the
process exits cleanly with code 0 but does nothing. This was confirmed
against a built-in MetaQuotes example script (not just QuantBeast
code). The working pattern is to use `wine start /Unix` with a relative
path from the MT5 installation directory:

```bash
cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
"$WINE" start /Unix metaeditor64.exe /compile:"MQL5\\Scripts\\ScriptName.mq5" /log
```

The compile result still appears in `logs/metaeditor.log`.

If compilation produces no log entry and no `.ex5` when using the
direct invocation, switch to the `wine start /Unix` pattern before
assuming the source has errors.

## MCP terminal fallback recipes

Two MT5 MCP servers are available. Either or both may be
misconfigured, disconnected, or return stale results. When an MCP
tool call fails or returns untrustworthy output, use the terminal
commands below to diagnose and recover. These are the same patterns
that Codex sessions used successfully during QuantBeast repair work.

### Server locations

| Server | Transport | Address | Auth | Requires |
|--------|-----------|---------|------|----------|
| Native MT5 MCP | HTTP | `127.0.0.1:22346/mcp` | Bearer token | MT5 terminal running |
| Bridge MCP | stdio | `/Users/matt/Tools/mt5-mcp/bin/Release/net8.0/mt5-mcp` | None | MT5 + MtApi5 EA attached (port 8228) |

### Health checks

```bash
# Is the native MCP server listening?
lsof -i :22346 -P -n | grep LISTEN

# Is the MtApi5 bridge port open?
lsof -i :8228 -P -n | grep LISTEN

# Is MT5 running?
pgrep -fl terminal64

# Unauthenticated probe (expect 401 — proves the server is alive)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:22346/mcp
```

### Starting MT5 when it is not running

```bash
open "/Applications/MetaTrader 5.app"

# Poll until the native MCP server responds:
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:22346/mcp 2>/dev/null)
  if echo "$code" | grep -q "40[013]"; then
    echo "MCP server responding after ${i}s (HTTP $code)"; break
  fi
  sleep 2
done
```

### Raw curl to the native MCP endpoint

When the MCP client integration is unreliable but the server is
listening, you can call tools directly:

```bash
# 1. Initialize a session and capture the session ID
BEARER="UqaByo2n1nSzwFQZSOeUQqTyuj4txku2+971VxPj1V"
INIT=$(curl -s -i -X POST http://127.0.0.1:22346/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"shell","version":"1.0"}}}')

SID=$(echo "$INIT" | grep -i "Mcp-Session-Id:" | tr -d '\r' | sed 's/.*Mcp-Session-Id: //')

# 2. Send the initialized notification
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST http://127.0.0.1:22346/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER" \
  -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# 3. Call get_workspace_info
curl -s -X POST http://127.0.0.1:22346/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER" \
  -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_workspace_info","arguments":{}}}'

# 4. Call any other tool (example: list_directory)
curl -s -X POST http://127.0.0.1:22346/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER" \
  -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_directory","arguments":{"path":"MQL5\\\\Experts\\\\QuantBeast"}}}'
```

**Important:** Never print, copy, or commit the bearer token. Token
rotation requires the MT5 GUI: **Tools → Options → MCP tab →
regenerate**. If the token in this document has been rotated, extract
the new one from `~/Library/Application Support/Code/User/mcp.json`.

### Tester evidence when MCP returns job_id: 0

The native tester MCP (`tester_run_backtest`, `tester_get_status`)
is known to return `job_id: 0` even when a test runs locally. Do not
trust it as the sole source of truth. Instead:

```bash
# Inspect the local tester agent log:
ls -lt "Tester/Agent-127.0.0.1-3000/logs/"
tail -50 "Tester/Agent-127.0.0.1-3000/logs/$(date +%Y%m%d).log"

# Or use Python to decode UTF-16LE and find test sections:
python3 -c "
import re
path = '/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/Tester/Agent-127.0.0.1-3000/logs/$(date +%Y%m%d).log'
with open(path, 'rb') as f:
    text = f.read().decode('utf-16-le', errors='replace')
markers = [(m.start(), m.group(0)) for m in re.finditer(r'(\d+:\d+:\d+\.\d+).*testing of Experts', text)]
print(f'Found {len(markers)} test section(s)')
for i, (pos, marker) in enumerate(markers[-3:]):
    print(f'--- section {i+1}: {marker.strip()} ---')
    print(text[pos:pos+500])
"
```

### Broker state verification (read-only)

```bash
# Check Coinexx-Demo positions/orders (read-only):
ls -la "Bases/Coinexx-Demo/trades/871221/"

# Check terminal log for recent disconnects/shutdowns:
grep -i "shutdown\|disconnect\|MCP\|server start\|server stop" "logs/$(date +%Y%m%d).log" | tail -20
```

### Compilation fallback

When `compile_mql5` (either native or bridge) produces no `.ex5` or
no log entry, use the documented `wine start /Unix` pattern:

```bash
WINEPREFIX="/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5"
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"

cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
"$WINE" start /Unix metaeditor64.exe /compile:"MQL5\\Experts\\QuantBeast\\QuantBeastEA.mq5" /log

# Check the result:
tail -20 "logs/metaeditor.log"
shasum -a 256 "MQL5/Experts/QuantBeast/QuantBeastEA.ex5"
```

### Token rotation

The bearer token cannot be rotated through any MCP tool. When the
token expires or has been exposed:

1. Open the MT5 application GUI.
2. **Tools → Options → MCP tab**.
3. Click **Regenerate** (or **Copy** to get the new key).
4. Update the token in **all** of these files:
   - `~/Library/Application Support/Code/User/mcp.json`
   - `~/.codex/config.toml` (if Codex is used)
   - `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`
   - This document's recipes above
5. Do **not** update `assistant.ini` — that file uses an encrypted
   form the server handles internally.

## Test contract

Follow `TESTING_GUIDE.md`. Preserve evidence under `Experts/QuantBeast/TestEvidence/` when testing begins.

- Diagnostic mode must send no orders.
- Shadow mode must send no broker orders.
- Tester runs must have unique, verified configuration, dates, and output evidence.
- Do not accept cached tester output as a new run.
- Record symbol specification, deposit, leverage, model, dates, inputs, trade count, drawdown, and log/report paths.
- A profitable result does not override safety, correctness, or holdout failures.

## Handoff requirements

Before ending a source-changing task, update `Experts/QuantBeast/HANDOFF.md` with:

- Current phase and verdict
- Exact files changed
- Defects fixed and still open
- Compile command/result and warning count
- Tests run and evidence paths
- Assumptions and blockers
- Exact recommended next action
- Any instructions for the next agent

Do not erase prior worklog entries. Add a dated entry and keep the current-state sections concise.

Every HANDOFF.md worklog entry must be paired with a git commit whose
one-line summary matches the entry title, so the hash recorded in
HANDOFF.md and `git log` always agree.

## Session scope

`HANDOFF.md`'s "Next task" list may contain multiple open items. Treat that
list as sequential, not parallel: pick exactly one item per session, state
which one and why before starting, and complete its full loop (evidence →
compile → test → HANDOFF.md entry) before touching a different item — even
if the other item looks unrelated or quick. If a session ends with an item
incomplete, say so explicitly in the worklog entry rather than leaving it
ambiguous which item is "in progress."

This applies across agents and tools, not just within one session: if you
are picking up work from a different agent/tool that hit a limit or stopped
mid-item, resume that same item first rather than starting a new one from
the list.

## Documentation during active work

When something worth documenting comes up mid-task (a tooling quirk, a
stale reference, a scope-limiting finding), distinguish two cases:

**Blocking** — the current task cannot produce valid evidence without
this being resolved first (e.g. discovering the compile command is
silently failing, discovering the task is testing the wrong code path).
Stop, resolve or document immediately, then continue. This is rare.

**Non-blocking** — worth recording, but the current task can still
proceed and produce valid evidence without it (e.g. a doc cross-reference
is stale, a different section could use a pointer, a tangential cleanup
opportunity). Do NOT stop to fix it. Instead, append one line to a
running list under a `## Session notes (pending write-up)` heading at
the bottom of HANDOFF.md — no commit, just a plain note. Continue the
task.

At the end of the session, convert that list into one proper HANDOFF.md
worklog entry (or a short follow-up task list) in the same pass as your
end-of-session update — not as N separate stop-and-commit cycles during
the session.

If the pending-notes list would take real time to act on (new files,
multi-file edits, source changes), do not act on it in this session even
at the end — just leave it queued as a clearly stated follow-up item for
a dedicated session.

## Completion standard

The project is complete only when every applicable item in `LIVE_DEPLOYMENT_CHECKLIST.md` has evidence, the build is zero-error/zero-warning, required tests pass, restart recovery is demonstrated, all live positions are protected and tracked, and `BUILD_AUDIT.md` can honestly be changed to PASS.
