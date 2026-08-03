# Blocked-State and Escalation Protocol

## 1. Purpose

This protocol prevents agents from declaring a task blocked merely because the first command failed, MT5 was initially stopped, an MCP response was ambiguous, or a documented fallback was not attempted.

It also prevents agents from improvising across protected boundaries when a real blocker exists.

## 2. Valid blocked categories

Use exactly one primary category:

```text
BLOCKED_SPEC_CONFLICT
BLOCKED_UNEXPECTED_SOURCE_CHANGE
BLOCKED_GIT_STATE_MISMATCH
BLOCKED_HOST_PERMISSION
BLOCKED_MISSING_DEPENDENCY
BLOCKED_COMPILE_AFTER_FALLBACKS
BLOCKED_ISOLATED_RUNTIME_LAUNCH
BLOCKED_RUNTIME_TIMEOUT
BLOCKED_ARTIFACT_AUTHORSHIP
BLOCKED_EVIDENCE_CORRUPTION
BLOCKED_REQUIRED_SECRET_ROTATION
BLOCKED_OWNERSHIP_CONFLICT
```

## 3. Invalid blocker statements

The following are not sufficient:

```text
MT5 is not running.
MCP returned job_id 0.
The process exited.
The EX5 already exists.
The direct compile command did nothing.
The log did not immediately appear.
A dependency appears to be missing.
The task is difficult.
```

Each must be followed by the documented recovery sequence before blocker classification.

## 4. Required blocked report

Every blocked report must include:

```text
blocker_category
role
ticket_id
time_utc
exact_operation
exact_command_or_tool_call
working_directory
exit_code_or_error
stdout
stderr
relevant_log_path
fresh_log_boundary
expected_behavior
actual_behavior
recovery_steps_attempted
recovery_steps_not_attempted_and_why
protected_boundary_preventing_further_action
risk_of_continuing
required_owner
exact_next_action
```

## 5. MT5 stopped procedure

Before `BLOCKED_ISOLATED_RUNTIME_LAUNCH` or `BLOCKED_HOST_PERMISSION`:

1. check `pgrep -fl terminal64`;
2. check native MCP port;
3. run the documented macOS application launch command;
4. poll the endpoint for the documented interval;
5. record process and HTTP responses;
6. retry only within the documented procedure;
7. report exact host or sandbox denial if present.

A stopped initial process is not a blocker.

## 6. Compile procedure

Before `BLOCKED_COMPILE_AFTER_FALLBACKS`:

1. record source hash and prior EX5 state;
2. attempt the approved compile method;
3. inspect fresh MetaEditor log evidence;
4. if direct invocation no-ops, use `wine start /Unix` with the relative path;
5. verify new EX5 mtime and hash;
6. preserve commands and logs.

Do not alter source unless the Lead receives and owns a source-repair task.

## 7. Missing dependency procedure

Before `BLOCKED_MISSING_DEPENDENCY`:

1. compare the runtime ticket to the staging manifest;
2. inspect the canonical dependency graph;
3. determine whether the file exists in the canonical tree;
4. determine whether staging was omitted;
5. if staging omission, Runtime Engineer corrects staging;
6. if source includes a nonexistent dependency, return to Lead as a source defect.

Do not copy guessed files from the main terminal.

## 8. Runtime timeout procedure

Before `BLOCKED_RUNTIME_TIMEOUT`:

- confirm launch occurred once;
- confirm no duplicate request cancelled synchronization;
- inspect process state;
- inspect fresh log growth;
- distinguish history synchronization from hung execution;
- wait the ticketed timeout;
- preserve the final fresh log range;
- do not kill unrelated MT5 processes.

## 9. Authorship blocker

Use `BLOCKED_ARTIFACT_AUTHORSHIP` when:

- MQL output existed unchanged before run;
- Python wrote the output location;
- staging or builder behavior makes authorship ambiguous;
- output mtime cannot be tied to launch;
- log lacks output-generation markers;
- same-process copies were compared.

The correct response is a clean isolated rerun with quarantined outputs—not relabeling existing files.

## 10. Source-change blocker

Use `BLOCKED_UNEXPECTED_SOURCE_CHANGE` when an active file hash differs from the session inventory without a recorded Lead delta.

Do not overwrite or restore. Report:

- inventory hash;
- current hash;
- mtimes;
- diff summary if read-only inspection is safe;
- possible concurrent writer.

## 11. Specification conflict

Use `BLOCKED_SPEC_CONFLICT` when:

- canonical spec and audit disagree;
- handoff requires behavior contrary to the canonical spec;
- Python and MQL authorities disagree about ownership;
- a required repair changes frozen semantics.

Do not resolve by majority or convenience. Escalate to the user or designated architecture authority.

## 12. Ownership conflict

Use `BLOCKED_OWNERSHIP_CONFLICT` when two roles need to edit the same canonical file.

The Lead must either:

- retain ownership and perform the repair;
- issue a narrow written ownership transfer;
- defer the task.

Agents may not edit concurrently.

## 13. Secret exposure

If a live token or credential appears in tracked files or output:

1. do not reproduce it;
2. redact it from reports;
3. stop secret-dependent automation if exposure creates risk;
4. report file and exposure type without value;
5. recommend rotation;
6. do not commit any remediation under this recovery pack.

## 14. Escalation order

```text
Runtime issue
→ Runtime Engineer documents
→ MultiSpeedZigZag Lead decides staging repair vs source repair
→ Independent Reviewer remains uninvolved until evidence submission
→ User decides protected/spec/secret/authorization conflicts
```

The Reviewer does not become an implementation coordinator.

## 15. No workaround across forbidden boundaries

A blocker never authorizes:

- main-terminal fallback;
- canonical spec changes;
- harness assertion weakening;
- fixture rewriting;
- QuantBeast edits;
- historical screening;
- commits or pushes;
- live broker actions.

## 16. Unblock record

When resolved, append:

```text
original_blocker_category
resolution_owner
resolution_action
files_changed
pre_and_post_hashes
new_ticket_id
resolution_time_utc
verification
```

Do not erase the original blocked report.

## 17. End state

A blocked task remains blocked until the exact missing capability or evidence is restored.

Confidence, manual inspection, or a plausible explanation does not convert blocked evidence into passing evidence.
