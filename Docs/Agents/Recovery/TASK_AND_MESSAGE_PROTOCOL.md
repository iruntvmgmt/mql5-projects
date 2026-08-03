# Task and Message Protocol

## 1. Purpose

This protocol prevents vague delegation, hidden assumptions, scope drift, and agents acting on incomplete verbal instructions.

Every cross-agent request must be a written ticket. Every response must reference that ticket.

## 2. Ticket states

```text
DRAFT
ISSUED
ACCEPTED
REJECTED_INCOMPLETE
EXECUTING
EVIDENCE_READY
RETURNED_FOR_REPAIR
CLOSED
BLOCKED
```

Only one runtime ticket may be active at a time.

## 3. Ticket identifier

Use:

```text
MC2-<UTC_DATE>-<SEQUENCE>-<SHORT_PURPOSE>
```

Example:

```text
MC2-20260802-001-CERTIFIED_JOURNAL_RUNTIME
```

## 4. Runtime ticket template

```md
# Runtime Ticket

## Identity
- ticket_id:
- issued_by: MultiSpeedZigZag Lead
- issued_at_utc:
- state: ISSUED

## Objective
One sentence describing the exact runtime proof required.

## Authorized runtime
- runtime_root: /Users/matt/MT5-MSZZ-TEST
- main_terminal_fallback: FORBIDDEN

## Canonical source identity
| role | canonical_path | sha256 | size | mtime_utc |
|---|---|---|---:|---|

## Required isolated destinations
| source_path | destination_path | purpose | replace_policy |
|---|---|---|---|

## Compile instruction
- exact_source:
- expected_binary:
- compile_method_primary:
- compile_method_fallback:
- required_result: 0 errors / 0 warnings

## Runtime input
- config_path:
- fixture_path:
- other_inputs:

## Expected fresh markers
- start markers:
- completion markers:
- failure markers:

## Expected counts
- fixtures:
- assertions:
- emitting_rows:
- expected_output_rows:

## Expected outputs
| output_path | author | format | expected_rows | pre-run handling |
|---|---|---|---:|---|

## Allowed actions
Explicitly list allowed staging, quarantine, compile, launch, and read-only inspection actions.

## Forbidden actions
Explicitly list source edits, harness edits, main-terminal staging, duplicate launch, generator execution, commit, push, and historical screening prohibitions.

## Timeout
- readiness_timeout:
- runtime_timeout:
- synchronization_policy:

## Required return package
List every required report, manifest, log range, hash, and classification.
```

## 5. Ticket acceptance

The Runtime Engineer must respond before acting:

```text
TICKET_ACCEPTED <ticket_id>
```

or:

```text
TICKET_REJECTED_INCOMPLETE <ticket_id>
missing_fields:
- ...
conflicts:
- ...
```

Silence is not acceptance.

## 6. Runtime response template

```md
# Runtime Ticket Result

## Identity
- ticket_id:
- executed_by: MT5 Runtime Engineer
- started_at_utc:
- ended_at_utc:
- classification:

## Preflight
- canonical source hashes matched ticket: yes/no
- isolated runtime verified: yes/no
- active process conflicts: none/list

## Staging
- staging_manifest_path:
- files copied:
- files quarantined:
- unexpected files: none/list

## Compilation
- source_sha256:
- prior_binary_sha256:
- post_binary_sha256:
- compile_log_path:
- errors:
- warnings:
- binary_freshness:

## Launch
- command:
- fresh_log_path:
- fresh_log_start_offset:
- start_marker:
- completion_marker:
- launched_once: yes/no

## Results
- fixtures:
- assertions:
- failures:
- emitting_rows:
- harness_failures:

## Outputs
Artifact manifest table.

## Authorship conclusion
Explain why outputs are or are not independently MQL-authored.

## Blocker or source defect
Exact evidence only; no source repair.

## Evidence package
- directory:
- files:
```

## 7. Lead repair ticket

When runtime evidence proves a harness/source defect, the Runtime Engineer returns the ticket. The Lead creates a separate repair record:

```text
REPAIR-<ticket_id>-<sequence>
```

The repair record must include:

- exact failing evidence;
- canonical rule involved;
- target file;
- smallest repair;
- tests required before rerun;
- new source hash;
- replacement runtime ticket ID.

## 8. Reviewer submission

The Lead submits:

```md
# Checkpoint Review Submission
- checkpoint:
- submitted_by:
- submitted_at_utc:
- evidence_index_path:
- session_inventory_path:
- runtime_ticket_path:
- runtime_result_path:
- staging_manifest_path:
- artifact_manifest_path:
- parity_report_path:
- negative_matrix_path:
- git_guardrail_report_path:
- proposed_non_authoritative_verdict:
```

The Reviewer may reject incomplete submissions without searching for missing evidence.

## 9. Message discipline

Messages must distinguish:

```text
FACT
INFERENCE
PROPOSAL
BLOCKER
AUTHORIZATION_REQUIRED
```

Do not present inference as fact.

Do not use phrases such as “should be fine,” “looks good,” or “probably passed” in evidence reports.

## 10. No hidden continuation

An agent may not continue into a new phase because the next action seems obvious.

Examples:

- Runtime pass does not authorize parity certification.
- Checkpoint green does not authorize historical export.
- Historical export does not authorize screening.
- A profitable screen does not authorize optimization or deployment.

Every phase requires a new written authorization.
