# MC-CANON-2 Recovery Team Constitution

## 1. Authority and scope

This constitution governs only the temporary recovery of the active MultiSpeedZigZag MC-CANON-2 checkpoint-2 work.

It supplements, and does not replace:

- repository-root `AGENTS.md`;
- the active MultiSpeedZigZag handoff;
- `Docs/MultiSpeedZigZag/MC_V2_CANONICAL_SPEC.md`;
- the canonical-spec audit;
- the current Git branch and protected refs;
- task-specific written authorization from the user.

When instructions conflict, stop and report the conflict. Do not choose whichever instruction makes completion easier.

## 2. Team structure

### 2.1 MultiSpeedZigZag Lead

The Lead is:

- task coordinator;
- sole canonical repository writer;
- owner of MC canonical implementation, harness, fixtures, Python reference, and checkpoint evidence assembly;
- issuer of runtime tickets;
- recipient of runtime evidence;
- preparer of the final evidence index.

The Lead is not the final checkpoint authority.

### 2.2 MT5 Runtime Engineer

The Runtime Engineer is:

- owner of isolated-runtime preparation;
- owner of compile invocation and compile provenance;
- owner of terminal launch and fresh-log boundaries;
- owner of runtime artifact collection;
- owner of staging and output provenance manifests.

The Runtime Engineer does not own strategy behavior, harness assertions, fixture semantics, schemas, or expected output.

### 2.3 Independent Reviewer

The Reviewer is:

- read-only;
- independent from implementation and runtime generation;
- responsible for adversarial verification;
- sole issuer of the authorized checkpoint verdict token.

The Reviewer may not rescue, repair, regenerate, or normalize evidence.

## 3. One-writer rule

There is one canonical source tree and one writer.

```text
Canonical source tree:
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5

Canonical source writer:
MultiSpeedZigZag Lead only
```

No other agent may write inside the canonical source tree unless the Lead issues a written ownership transfer naming:

- exact path;
- exact purpose;
- exact permitted change;
- start time;
- expected return artifact;
- expiration condition.

Ownership transfer must be narrow and temporary. Directory-wide transfer is prohibited.

## 4. No automatic commits or pushes

During this recovery:

- agents may inspect;
- the Lead may edit and test;
- agents may prepare proposed commit inventories and messages;
- no agent may commit, push, merge, amend, rebase, force-push, tag, or modify remote refs.

The reason is evidence preservation. The active work contains an inherited uncommitted chain that requires higher-capability review before history is created.

## 5. Current fixed objective

The only objective is:

```text
Close MC-CANON-2 checkpoint 2 by producing and independently verifying
MQL5 CertifiedJournal runtime evidence and complete Python/MQL parity.
```

The following are out of scope:

- historical SER export;
- development, validation, or holdout screening;
- robustness runs;
- strategy optimization;
- new family implementation;
- QuantBeast adapter design;
- QuantBeast source changes;
- live/demo deployment;
- commits and pushes.

## 6. Frozen behavior

The team must treat the canonical MC-CANON-2 specification as immutable.

No agent may change:

- structural authority;
- pause-path origin;
- pause-bar indexing;
- invalidation equality;
- trigger/invalidation/expiry precedence;
- pullback bounds;
- efficiency formula or range rules;
- entry, stop, or target definitions;
- fixture meaning;
- reason-token meaning;
- emitting fixture inventory;
- candidate schema projection.

If the implementation and spec disagree, the Lead reports the disagreement. The team does not silently choose or rewrite either side.

## 7. Required sequence

Work must proceed in this order:

1. Lead session inventory.
2. Lead dependency inspection.
3. Lead runtime ticket.
4. Runtime staging manifest.
5. Runtime compile and binary identity proof.
6. Runtime launch exactly once.
7. Runtime evidence manifest.
8. Lead parity comparison.
9. Lead evidence index.
10. Reviewer independent verification.
11. Authorized verdict.
12. Stop.

No phase may be skipped because a later artifact appears to exist.

## 8. Evidence integrity

Evidence must be:

- fresh;
- attributable to a specific process;
- tied to exact source and binary identity;
- generated in the authorized runtime;
- preserved without post-run normalization;
- accompanied by size, mtime, SHA-256, row count, and encoding details where applicable.

Two byte-identical files do not prove cross-language parity when the same Python process wrote both.

A process exit code does not prove test completion.

An EX5 existing on disk does not prove it was compiled from current source.

A profitable result does not prove correctness.

## 9. Isolated runtime boundary

For checkpoint 2, all CertifiedJournal execution is restricted to:

```text
/Users/matt/MT5-MSZZ-TEST
```

The main MT5 installation may be used only as documented infrastructure required to launch the application or MetaEditor process. It may not receive checkpoint-specific harness sources, binaries, fixtures, includes, journals, or manifests as a fallback execution location.

The Runtime Engineer must not copy checkpoint files into the main installation.

## 10. Safety and secrets

Agents must never:

- expose or commit MCP bearer tokens;
- copy credentials into reports;
- transmit broker orders;
- change live/challenge acknowledgements;
- alter broker positions or orders;
- weaken stops, risk controls, or execution protection;
- touch unrelated QuantBeast production code.

Secrets must be read from approved local untracked configuration or environment variables and redacted from output.

## 11. Blocked-state standard

A blocked state is valid only when all applicable documented recovery steps were attempted and the report includes:

- exact command;
- exit code;
- stdout/stderr;
- relevant logs;
- attempted fallbacks;
- missing permission, dependency, or capability;
- why continuing would invalidate evidence.

“MT5 is not running” is not a blocker.

“Direct compile produced no output” is not a blocker before the documented `wine start /Unix` fallback is attempted.

## 12. Completion standard

Checkpoint 2 may be green only if every mandatory gate in the active handoff is supported by independently verifiable evidence.

One missing gate means the checkpoint remains blocked or in progress.

No “mostly green” or “practically complete” classification is permitted.

## 13. Stop conditions

Stop immediately when:

- canonical files differ from the session inventory unexpectedly;
- another process edits the canonical tree;
- branch or HEAD changes;
- protected refs change;
- runtime files appear outside the staging manifest;
- artifact authorship is ambiguous;
- the harness requires source repair;
- a required secret is exposed;
- a test would require main-terminal migration;
- a specification conflict is discovered.

## 14. End-of-session requirement

Every role must return a structured handoff containing:

- role;
- task ticket ID;
- start/end time;
- files read;
- files written outside/inside repository;
- commands executed;
- evidence produced;
- blockers;
- exact next owner and next action.

No agent may leave an ambiguous “still working” state.
