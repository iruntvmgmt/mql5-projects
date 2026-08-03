# OpenClaw Development Operating Protocol

## 1. Canonical working tree

The installed MT5 `MQL5` directory is the canonical compile/runtime source tree unless the active ticket explicitly defines a different environment.

Only one agent may own a file at a time. Parallel work is permitted only when file ownership is disjoint and runtime provenance remains clear.

## 2. Session start inventory

Before edits, record outside the repository:

- absolute path;
- branch and HEAD;
- relevant remote refs;
- tracked modified files;
- untracked files;
- active owner for every changed file;
- path, size, mtime, and SHA-256 for inherited uncommitted work;
- current task state and authorization.

Do not reset, clean, restore, stash, rebase, amend, switch branches, or run broad formatters without explicit authorization.

## 3. Ticket contract

Every ticket must contain:

```text
ticket_id
state
objective
repository and branch
coordinator
writer
runtime operator
reviewer
owned files
read-only dependencies
protected files
required reading
canonical behavior
allowed commands
evidence gates
forbidden actions
stop conditions
expected deliverables
```

Implementation begins only in `AUTHORIZED` state.

## 4. Ownership transfer

Ownership transfers must name one file or explicit glob, outgoing owner, incoming owner, reason, starting hash, expected change, and expiration condition.

No implied ownership transfer exists because another agent is blocked or unavailable.

## 5. Agent communication

Agents communicate through structured tickets and evidence indexes, not informal assumptions.

A runtime ticket must specify exact source, binary, dependencies, fixture inputs, runtime, config, expected markers, output names, timeout, and forbidden fallback locations.

A review submission must contain exact diff, compile evidence, tests, runtime index, artifacts, known limitations, and proposed verdict.

## 6. Commit policy

During fragile recovery or inherited dirty work, agents may be prohibited from committing. When commits are authorized:

- one purpose per commit;
- matching handoff entry;
- no unrelated files;
- no secrets;
- no generated runtime artifacts unless evidence policy requires them;
- no force push;
- no direct push to main;
- no self-merge.

## 7. Runtime policy

The runtime operator receives a ticket and does not alter semantics. Every copied file requires a staging manifest. Every run requires a fresh log boundary. Every output requires provenance.

Do not issue duplicate tester-start calls. Do not trust ambiguous MCP job IDs as sole evidence. Do not use process exit alone as success.

## 8. Evidence policy

Evidence must link:

```text
source hash
→ compile command and fresh log
→ binary hash
→ runtime/config identity
→ fresh log markers
→ output artifact hashes
→ test or research report
```

Classify each artifact author as Python, MQL5, external tool, copied/staged, or unknown.

Unknown authorship blocks independent parity claims.

## 9. Documentation synchronization

When behavior changes, update the applicable specification, known limitations, build/audit status, and handoff in the same authorized change group.

Do not rewrite historical evidence to match current behavior.

## 10. Autonomous loop

The Lead Developer may run this loop:

```text
read authorized queue
→ choose highest-priority unblocked ticket
→ verify ownership
→ assign specialist
→ implement
→ compile/test
→ collect evidence
→ independent review
→ prepare commit/PR
→ update handoff
→ repeat
```

The loop stops when no ticket is authorized, a protected decision is required, evidence contradicts the specification, or user approval is required.

## 11. Live and account actions

No agent may enable live trading, acknowledge Challenge risk, attach an EA to a live chart, change broker positions/orders, rotate or expose credentials, purchase an account, or deploy without explicit user authorization and the repository’s documented approval gates.
