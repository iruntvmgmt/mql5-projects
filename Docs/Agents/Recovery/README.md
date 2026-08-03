# MC-CANON-2 Recovery Agent Pack

**Status:** Active recovery operating model  
**Repository:** `iruntvmgmt/mql5-projects`  
**Applies to:** current MultiSpeedZigZag MC-CANON-2 checkpoint-2 recovery only  
**Branch containing this pack:** `docs/openclaw-mc-recovery-team-v2`

## Purpose

This pack defines the temporary three-agent organization authorized to recover and complete MC-CANON-2 checkpoint 2 without disturbing the inherited working tree, changing frozen strategy behavior, migrating test workloads into the main MT5 installation, or producing false evidence.

The current checkpoint requires independently MQL5-authored CertifiedJournal output before historical screening may begin.

## Active team

| Role | Authority | Canonical repository writes | Isolated runtime writes | Verdict authority |
|---|---|---:|---:|---:|
| MultiSpeedZigZag Lead | Coordinator and canonical source owner | Yes, sole writer | Through explicit ticket only | No final approval |
| MT5 Runtime Engineer | Stage, compile, launch, collect evidence | No | Yes, only ticketed isolated paths and external evidence | No |
| Independent Reviewer | Adversarial evidence review | Never | Never generates or overwrites evidence | Authorized checkpoint verdict only |

## Paused work

All work outside the active MC-CANON-2 checkpoint remains inactive until the checkpoint is independently reviewed and the user explicitly authorizes a new task.

No adapter implementation, QuantBeast source change, historical screening, optimization, or unrelated strategy work is authorized under this recovery pack.

## Canonical source tree

```text
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

Only the MultiSpeedZigZag Lead may modify this tree during recovery.

## Isolated runtime

The checkpoint workload executes only in:

```text
/Users/matt/MT5-MSZZ-TEST
```

The main installed terminal may remain running, but the CertifiedJournal workload, sources, binary, fixtures, logs, and outputs remain isolated.

## Canonical operational bridge

All Runtime Engineer activity must follow:

```text
Docs/Agents/Operations/README.md
Docs/Agents/Operations/MT5_MACOS_WINE_OPERATIONAL_BRIDGE.md
Docs/Agents/Operations/INI_CONFIG_REFERENCE.md
Docs/Agents/Operations/PROCESS_AND_PID_PROTOCOL.md
Docs/Agents/Operations/LOG_AND_ARTIFACT_PROTOCOL.md
Docs/Agents/Operations/FAILURE_RECOVERY_MATRIX.md
Docs/Agents/Operations/COMMAND_COOKBOOK.md
Docs/Agents/Operations/RUNTIME_EVIDENCE_TEMPLATE.md
```

The proven execution routes are:

```text
MQL5 compile
  -> isolated MetaEditor via Wine `start /Unix`

CertifiedJournal MQL5 Script
  -> isolated terminal64.exe `/portable /config:`
  -> `[StartUp] Script=MultiSpeedZigZagTests\Test_MSZZ_MC_CANON2_CertifiedJournal`

Strategy Tester, when separately authorized
  -> isolated terminal64.exe `/portable /config:`
  -> `[Tester] Expert=...`
```

MCP is not the Script execution bridge.

## Current authorized task

```text
MC-CANON-2 checkpoint 2:
independent MQL5 CertifiedJournal runtime evidence and complete cross-language parity
```

Historical SER export is forbidden until all checkpoint-2 gates are green.

## Non-negotiable rules

1. One canonical source writer.
2. No automatic commits or pushes.
3. No branch switches, resets, cleans, stashes, restores, rebases, amends, or broad formatting.
4. No changes to frozen MC-CANON-2 behavior.
5. Runtime Engineer does not edit harness, fixtures, assertions, schemas, or expectations.
6. No main-terminal fallback.
7. Every staged file has source/destination provenance and SHA-256.
8. Every output has authorship, fresh-boundary, and hash evidence.
9. Same-process copies are not cross-language parity.
10. Reviewer remains read-only.
11. No historical screening, optimization, or profitability claims.
12. Preserve the preexisting main terminal PID; kill only ticket-owned portable processes.
13. Do not print or read out MCP bearer tokens.
14. Stop after the checkpoint verdict.

## Document index

### Recovery governance

- `TEAM_CONSTITUTION.md`
- `MSZZ_LEAD.md`
- `MT5_RUNTIME_ENGINEER.md`
- `INDEPENDENT_REVIEWER.md`
- `OWNERSHIP_AND_GIT_PROTOCOL.md`
- `TASK_AND_MESSAGE_PROTOCOL.md`
- `SESSION_INVENTORY_STANDARD.md`
- `STAGING_AND_PROVENANCE_STANDARD.md`
- `EVIDENCE_AND_CHECKPOINT_STANDARD.md`
- `BLOCKED_AND_ESCALATION_PROTOCOL.md`

### Runtime operations

- `../Operations/README.md`
- `../Operations/MT5_MACOS_WINE_OPERATIONAL_BRIDGE.md`
- `../Operations/INI_CONFIG_REFERENCE.md`
- `../Operations/PROCESS_AND_PID_PROTOCOL.md`
- `../Operations/LOG_AND_ARTIFACT_PROTOCOL.md`
- `../Operations/FAILURE_RECOVERY_MATRIX.md`
- `../Operations/COMMAND_COOKBOOK.md`
- `../Operations/RUNTIME_EVIDENCE_TEMPLATE.md`

## Activation sequence

### Phase 1 — Lead inventory and ticket

The Lead verifies Git guardrails, inventories active MC files, hashes dependencies, and issues one exact runtime ticket.

### Phase 2 — Isolated runtime

The Runtime Engineer stages only ticketed files, compiles in isolated MetaEditor, creates a ticket-specific `[StartUp]` INI, launches one portable isolated terminal, collects fresh logs and MQL-authored artifacts, and terminates only the ticket-owned process.

### Phase 3 — Lead parity

The Lead verifies authorship, compares independent Python/MQL artifacts, closes Lead-owned parity gates, and builds the evidence index.

### Phase 4 — Independent review

The Reviewer verifies provenance and issues one authorized checkpoint verdict.

### Phase 5 — Stop

Do not begin later work until explicitly authorized.
