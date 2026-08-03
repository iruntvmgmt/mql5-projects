# MC-CANON-2 Recovery Agent Pack

**Status:** Active recovery operating model  
**Repository:** `iruntvmgmt/mql5-projects`  
**Applies to:** the current uncommitted MultiSpeedZigZag MC-CANON-2 checkpoint-2 recovery only  
**Branch containing this pack:** `docs/openclaw-mc-recovery-team-v2`

## Purpose

This pack defines the temporary three-agent organization authorized to recover and complete MC-CANON-2 checkpoint 2 without disturbing the current dirty working tree, migrating tests into the main MT5 installation, changing frozen strategy behavior, or producing false evidence.

It exists because the current work is unusually fragile:

- Claude left valuable uncommitted MC-CANON-2 implementation, fixtures, tests, and documentation.
- The active canonical working tree is the installed MT5 `MQL5` directory.
- A prior recovery attempt correctly discovered that apparently identical Python/MQL journals were all Python-authored, but then began copying harness files and dependencies into the main MT5 installation.
- MT5 runtime and MetaEditor automation have known no-op and stale-evidence failure modes.
- The current checkpoint requires independent MQL5 runtime output before historical screening may begin.

The solution is not five autonomous agents working in parallel. The solution is one coordinator/writer, one isolated-runtime operator, and one read-only reviewer.

## Active team

| Role | Authority | Repository writes | Runtime writes | Verdict authority |
|---|---|---:|---:|---:|
| MultiSpeedZigZag Lead | Coordinator and canonical source owner | Yes, sole writer | No, except through an explicit runtime ticket | No final approval |
| MT5 Runtime Engineer | Compile, stage, launch, collect evidence | No canonical source edits | Yes, only inside `/Users/matt/MT5-MSZZ-TEST` and external evidence directories | No |
| Independent Reviewer | Adversarial evidence review | Never | Never generates or overwrites evidence | Yes, only authorized checkpoint token |

## Paused roles

The following roles remain inactive until checkpoint 2 is independently reviewed and the user explicitly authorizes broader work:

- QuantBeast Architect
- QuantBeast Platform Lead
- Triple MA Engine Lead
- NQ Breakout Engine Lead
- Statistical Research Agent
- Portfolio Integration Agent

No adapter design, QuantBeast integration, historical screening, or unrelated strategy-family work is authorized under this recovery pack.

## Canonical source tree

The one canonical repository working tree is:

```text
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

Only the MultiSpeedZigZag Lead may modify this tree during the recovery session.

Other agents may:

- read the canonical tree;
- hash files;
- write reports under `~/OpenClawEvidence/`;
- operate the explicitly designated isolated MT5 runtime;
- prepare proposed patches outside the repository.

They may not apply patches to the canonical tree without a written ownership transfer from the Lead.

## Isolated runtime

For checkpoint 2, the only authorized execution environment is:

```text
/Users/matt/MT5-MSZZ-TEST
```

The CertifiedJournal harness, required includes, fixture inputs, and outputs must not be copied into or executed from the main MetaTrader installation as a fallback.

If the isolated runtime cannot launch, the Runtime Engineer must repair the isolated launch path or report a fully evidenced blocker. “MT5 is not running” is not a blocker; the repository documents how to launch MT5 and poll readiness.

## Current authorized task

The current authorized item is:

```text
MC-CANON-2 checkpoint 2:
independent MQL5 certified-journal runtime evidence and full cross-language parity
```

Historical SER export is forbidden until all checkpoint-2 gates are green.

## Non-negotiable recovery rules

1. One canonical source writer only.
2. No automatic commits or pushes.
3. No branch switches, resets, cleans, stashes, restores, rebases, amends, or project-wide formatting.
4. No changes to the frozen MC-CANON-2 specification.
5. No edits to the CertifiedJournal harness by the Runtime Engineer.
6. No migration to the main MT5 terminal.
7. Every staged file requires a provenance manifest.
8. Every output artifact requires authorship and hash evidence.
9. Existing identical files are not cross-language parity unless independently produced.
10. The Reviewer remains completely non-writing.
11. No historical screening, optimization, or profitability claims.
12. Stop after the checkpoint verdict and wait for a higher-capability audit before commit/push.

## Document index

- `TEAM_CONSTITUTION.md` — team authority, sequencing, and universal rules.
- `MSZZ_LEAD.md` — sole writer and checkpoint coordinator instructions.
- `MT5_RUNTIME_ENGINEER.md` — isolated runtime, compile, launch, and evidence instructions.
- `INDEPENDENT_REVIEWER.md` — read-only review and verdict rules.
- `OWNERSHIP_AND_GIT_PROTOCOL.md` — source ownership, prohibited Git operations, and transfer procedure.
- `TASK_AND_MESSAGE_PROTOCOL.md` — exact runtime ticket and agent-to-agent messaging format.
- `SESSION_INVENTORY_STANDARD.md` — mandatory dirty-tree inventory and hash baseline.
- `STAGING_AND_PROVENANCE_STANDARD.md` — file-copy manifest and artifact authorship rules.
- `EVIDENCE_AND_CHECKPOINT_STANDARD.md` — checkpoint gates, evidence index, and verdict criteria.
- `BLOCKED_AND_ESCALATION_PROTOCOL.md` — exact requirements for blocked states and escalation.

## Activation sequence

### Phase 1 — Lead inventory and runtime ticket

The MultiSpeedZigZag Lead:

- verifies Git guardrails;
- inventories every active MC file by path, size, mtime, and SHA-256;
- inspects the harness and its dependency graph;
- writes one exact runtime ticket;
- does not launch MT5 or modify the isolated runtime.

### Phase 2 — Runtime execution

The Runtime Engineer:

- accepts only the Lead’s ticket;
- creates a staging manifest before copying anything;
- stages only ticketed files into `/Users/matt/MT5-MSZZ-TEST`;
- compiles the exact source;
- verifies a newly generated EX5;
- establishes a fresh log boundary;
- launches exactly once;
- collects fresh runtime evidence;
- makes no source or harness changes.

### Phase 3 — Lead parity and evidence index

The Lead:

- verifies output authorship;
- compares independently produced Python and MQL artifacts;
- completes any Lead-owned missing parity work;
- creates the checkpoint evidence index;
- does not issue the final approval token.

### Phase 4 — Independent review

The Reviewer:

- reads the diff and evidence index;
- independently verifies hashes and provenance;
- confirms protected refs and files are unchanged;
- issues exactly one authorized checkpoint verdict token.

### Phase 5 — Stop

After the verdict:

- do not begin historical screening;
- do not commit;
- do not push;
- do not activate paused roles;
- wait for explicit user authorization and a frontier-model audit.
