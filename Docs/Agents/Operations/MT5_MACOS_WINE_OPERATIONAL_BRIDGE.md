# MT5 macOS/Wine Operational Bridge

## 1. Scope

This document is the canonical agent procedure for operating MetaTrader 5 on the repository's macOS/Wine environment without relying on GUI interaction.

It covers:

- isolated MetaEditor compilation;
- isolated MQL5 Script execution;
- isolated Strategy Tester execution;
- process ownership;
- startup configuration;
- log and artifact verification;
- delayed startup and cold compile behavior;
- safe cleanup;
- evidence requirements.

It does not authorize:

- live trading;
- broker-order mutation;
- changes to strategy behavior;
- migration of isolated test assets into the main terminal;
- secret extraction or disclosure.

## 2. Execution architecture

### 2.1 Main terminal

The main installed terminal may already be running and connected. It can expose native MCP and may be used for ticket-authorized main-terminal inspection.

The main terminal is not the default execution location for isolated tests.

### 2.2 Isolated portable terminal

An isolated MT5 root contains its own:

- `terminal64.exe`;
- `metaeditor64.exe`;
- `MQL5/` tree;
- logs;
- tester agents;
- profiles/configuration;
- runtime file sandboxes.

The current MultiSpeedZigZag validation root is:

```text
/Users/matt/MT5-MSZZ-TEST
```

Launch with `/portable` so the isolated root remains the data directory.

### 2.3 Bridge selection table

| Required operation | Required bridge |
|---|---|
| Compile MQ5 | isolated MetaEditor via Wine `start /Unix` |
| Execute MQL5 Script | isolated terminal + `/portable /config:` + `[StartUp]` |
| Run EA backtest | isolated terminal + `/portable /config:` + `[Tester]` |
| Check main terminal MCP health | HTTP/native MCP health request |
| Inspect supported main terminal state | MCP only when ticket-authorized |

Do not substitute one bridge for another without written authorization and proof that semantics remain unchanged.

## 3. Session preflight

Before any runtime operation:

1. Read the active ticket and required documents.
2. Record canonical branch and HEAD.
3. Record exact source paths, hashes, sizes, and mtimes.
4. Record the isolated runtime path.
5. Verify `terminal64.exe` and `metaeditor64.exe` exist in the isolated root.
6. Identify all currently running `terminal64.exe` processes and their full command lines.
7. Record the preexisting main-terminal PID outside the repository.
8. Verify no prior ticket-owned portable terminal remains active.
9. Verify source, includes, fixtures, INI, and output directories.
10. Record pre-run log and artifact boundaries.

A runtime launch without this preflight is invalid evidence.

## 4. Source staging

Only ticket-listed files may be staged.

For each file record:

```text
source path
source SHA-256
source size
source mtime
destination path
destination preexisting state/hash
copy timestamp
destination SHA-256
match result
ticket ID
authorizer
```

Rules:

- create the manifest before copying;
- preserve unrelated destination files;
- quarantine only ticket-owned stale outputs;
- never broad-delete the isolated runtime;
- never silently copy test sources into the main terminal;
- fail if post-copy SHA differs from source SHA;
- inspect include dependency chains before compile.

## 5. Isolated compilation

### 5.1 Proven compile pattern

Run from the isolated MT5 root:

```bash
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
ISO="/Users/matt/MT5-MSZZ-TEST"

cd "$ISO"
"$WINE" start /Unix metaeditor64.exe \
  /portable \
  /compile:"MQL5\\Scripts\\MultiSpeedZigZagTests\\Test_Name.mq5" \
  /log
```

Use the exact relative MQL path required by the ticket. Quote paths containing spaces.

### 5.2 Compile proof

A valid compile requires:

- source SHA and mtime recorded before launch;
- exact command recorded;
- fresh MetaEditor log;
- explicit `Result:` line;
- task-required error/warning count;
- newly written EX5 or verified current binary;
- binary SHA, size, and mtime;
- compiler/build version when available.

Exit code zero is not compile proof.

### 5.3 Cold-start behavior

The first isolated compile may have delayed process startup or delayed log creation.

Required recovery sequence:

1. wait a bounded initial period;
2. poll for the expected source-adjacent compile log;
3. inspect MetaEditor process state;
4. decode and inspect any newly created log;
5. retry only the specific compile once when the first invocation produced no evidence and no active compile remains;
6. stop if duplicate compilers or ambiguous output exist.

Do not launch repeated compiles blindly.

## 6. MQL5 Script execution

### 6.1 Startup INI

Create a task-specific INI in the isolated root:

```ini
[StartUp]
Script=MultiSpeedZigZagTests\Test_Name
Symbol=XAUUSD
Period=M5
```

The script name omits `MQL5/Scripts/` and the `.ex5` extension.

### 6.2 Launch pattern

```bash
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
ISO="/Users/matt/MT5-MSZZ-TEST"
INI="test_name_start.ini"

"$WINE" "$ISO/terminal64.exe" /portable /config:"$INI" &
TEST_PID=$!
```

Depending on Wine process wrapping, `$!` may identify the launcher rather than the final Windows process. Therefore also locate the resulting process by full command line containing:

```text
/portable /config:test_name_start.ini
```

Record both launcher PID and final terminal PID when they differ.

### 6.3 Completion behavior

`[StartUp] Script=` may leave the portable terminal running after `OnStart()` finishes.

Therefore:

- process survival is not failure;
- process exit is not success;
- completion is proven by fresh terminal-journal markers and required artifacts;
- after evidence collection, terminate only the ticket-owned portable PID;
- confirm the main terminal PID still exists.

### 6.4 Script run proof

Require:

- pre-run journal boundary;
- isolated process identity and command line;
- script start marker;
- script completion marker;
- assertion/fixture counts;
- zero task-defined failures;
- output paths and hashes;
- MQL authorship evidence;
- no unexpected files outside the manifest.

## 7. Strategy Tester execution

### 7.1 Tester INI

A typical isolated tester configuration is:

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
Report=Reports\ticket-report
ReplaceReport=1
ShutdownTerminal=1
```

Only include settings authorized by the ticket and existing project presets. Do not invent trading inputs.

### 7.2 Tester launch

```bash
"$WINE" "$ISO/terminal64.exe" /portable /config:"tester_ticket.ini" &
```

Issue one launch only. Poll the process, report, tester-agent log, and artifacts. Do not send a duplicate launch while the first process is active.

### 7.3 Tester evidence locations

Common locations include:

```text
<ISO>/Tester/Agent-127.0.0.1-*/logs/<date>.log
<ISO>/Tester/Agent-127.0.0.1-*/MQL5/Files/
<ISO>/Reports/
```

Discover actual paths with bounded `find` commands. Do not assume one fixed agent port.

### 7.4 Tester proof

A report alone is insufficient. Validate applicable layers:

- terminal launch identity;
- tester-agent journal;
- exact fresh run slice;
- generated report;
- generated CSV/journal artifacts;
- order/deal/trade counts;
- initialization and posture markers;
- strategy-specific counts;
- output hashes.

## 8. Log handling

MT5 and MetaEditor logs may be UTF-16LE.

Use:

```bash
iconv -f utf-16le -t utf-8 < input.log
```

or Python:

```python
from pathlib import Path
text = Path(path).read_bytes().decode("utf-16le", errors="replace")
```

Never rely on raw `grep` against undecoded binary-looking text.

### 8.1 Fresh boundaries

Before launch record one or more of:

- file absent/present;
- byte length;
- line count after decoding;
- mtime;
- SHA-256;
- unique run marker.

After launch analyze only appended content or content after the current run's unique initialization marker.

Cumulative logs must not be evaluated as one run.

### 8.2 Delayed dated logs

The dated log may not exist immediately after process spawn.

Poll the directory and process state before declaring failure. The actual log date may follow terminal/server time rather than an assumption made by the shell.

## 9. Artifact sandbox map

### Terminal script

Typical output:

```text
<ISO>/MQL5/Files/
<ISO>/MQL5/logs/
```

### Strategy Tester

Typical output:

```text
<ISO>/Tester/Agent-*/MQL5/Files/
<ISO>/Tester/Agent-*/logs/
<ISO>/Reports/
```

### Compile

Typical output:

```text
source-adjacent `.log`
source-adjacent `.ex5`
```

Always discover and record the actual path.

## 10. Process cleanup

After a run:

1. confirm completion markers and collect artifacts;
2. hash outputs before transformation;
3. record the ticket-owned PID and command line;
4. terminate only that PID;
5. wait for exit;
6. confirm no orphaned `/portable /config:<ticket-ini>` process remains;
7. confirm preexisting main terminal remains alive;
8. preserve logs and outputs for review.

Never use broad commands such as `killall terminal64.exe`.

## 11. Diagnostic probes

A read-only diagnostic script may be used when a production class needs runtime observation not available through pure fixtures.

Requirements:

- implementation lead authorizes and writes it;
- runtime engineer only compiles/runs it;
- no order transmission;
- no account mutation;
- explicit start/completion/output markers;
- narrow includes;
- documented limitations;
- removal or archival policy after use.

A diagnostic probe does not convert an unavailable real-world state into full certification.

## 12. Shell safety

The host shell may be zsh even when commands resemble Bash.

Rules:

- use `#!/usr/bin/env bash` for Bash-specific scripts;
- quote every path;
- avoid reserved names such as `status` in zsh;
- use arrays for argument construction when practical;
- treat `grep` no-match exit code separately under `set -e`;
- do not use `eval` for paths or command construction;
- print commands with secrets redacted;
- use bounded polling and explicit timeouts.

## 13. Security

- Never read a credential merely to prove it exists.
- Never print bearer tokens.
- Never include secrets in command history, tickets, reports, or chat.
- MCP authentication belongs in approved local untracked configuration.
- If a token is printed, treat it as compromised and rotate it.
- Runtime evidence must redact account identifiers unless the active policy explicitly permits them.

## 14. Runtime verdicts

The Runtime Engineer may issue only runtime-local classifications:

```text
RUNTIME_PASS
RUNTIME_FAIL
RUNTIME_TIMEOUT
RUNTIME_BLOCKED
RUNTIME_EVIDENCE_AMBIGUOUS
```

The Runtime Engineer does not certify strategy correctness, parity, research validity, or checkpoint completion.

## 15. Stop conditions

Stop immediately when:

- the executable path differs from the ticket;
- the process command line does not contain the expected portable/config arguments;
- a main-terminal path receives isolated harness files;
- source or destination hashes change unexpectedly;
- multiple ticket-owned terminals are active;
- log authorship or run boundary is ambiguous;
- a secret appears in output;
- the harness requires semantic changes;
- output files appear outside authorized locations;
- the active branch, HEAD, or canonical inventory changes unexpectedly.
