# Runtime Evidence Report Template

Copy this template into the external evidence directory for each runtime ticket. Do not store secrets.

```md
# Runtime Evidence Report

## Identity

- ticket_id:
- role: MT5 Runtime Engineer
- repository:
- canonical_working_tree:
- branch:
- HEAD:
- task_objective:
- runtime_class: SCRIPT | TESTER | COMPILE | DIAGNOSTIC
- runtime_root:
- evidence_root:
- start_time_utc:
- end_time_utc:

## Authorization

- ticket_path:
- ticket_SHA256:
- authorizer:
- owned_runtime_paths:
- read_only_source_paths:
- forbidden_paths:
- allowed_commands:
- expected_markers:
- timeout_seconds:

## Preflight

- main_terminal_preexisting: yes/no
- main_terminal_PID:
- main_terminal_command:
- preexisting_portable_processes:
- preexisting_metaeditor_processes:
- isolated_terminal_exists:
- isolated_metaeditor_exists:
- output_directories_writable:
- preflight_result:

## Source inventory

| Logical file | Source path | Size | mtime | SHA-256 | Owner |
|---|---|---:|---|---|---|

## Staging manifest

| Source path | Source SHA | Destination path | Prior destination state/SHA | Copy time | Destination SHA | Match |
|---|---|---|---|---|---|---|

## Compile evidence

- source_path:
- source_SHA256:
- source_mtime:
- compile_command_redacted:
- compile_start:
- compile_end:
- metaeditor_PID:
- compile_log_path:
- compile_log_pre_boundary:
- compile_log_SHA256:
- compiler_build:
- errors:
- warnings:
- warning_disposition:
- EX5_path:
- EX5_size:
- EX5_mtime:
- EX5_SHA256:
- compile_result: PASS | FAIL | NO_OP | TIMEOUT | AMBIGUOUS

## INI identity

- INI_path:
- INI_type: StartUp | Tester
- INI_SHA256:
- script_or_expert:
- symbol:
- period:
- model/dates if tester:
- report path if tester:
- safety inputs verified:

## Launch evidence

- exact_command_redacted:
- launcher_PID:
- final_terminal_PID:
- executable_path:
- full_process_command_line:
- launch_time:
- unique_process_match_count:
- duplicate_launches: 0

## Fresh log boundary

| Log path | Preexisting | Pre-run bytes | Pre-run lines | Pre-run mtime | Pre-run SHA |
|---|---|---:|---:|---|---|

## Runtime markers

- start_marker_found:
- completion_marker_found:
- failure_markers:
- fixture_count:
- assertion_count:
- failure_count:
- timeout:
- runtime_result: RUNTIME_PASS | RUNTIME_FAIL | RUNTIME_TIMEOUT | RUNTIME_BLOCKED | RUNTIME_EVIDENCE_AMBIGUOUS

## Fresh log slice

- original_log_path:
- original_log_SHA256:
- extraction_method: byte offset | line offset | unique marker
- extracted_raw_path:
- extracted_raw_SHA256:
- decoded_path:
- decoded_encoding:
- first_relevant_line:
- last_relevant_line:

## Artifacts

| Logical name | Exact path | Author class | Created/mtime | Size | SHA-256 | Rows | Encoding | Line endings | Final newline | Validation |
|---|---|---|---|---:|---|---:|---|---|---|---|

Author class must be one of:

- MQL5_AUTHORED
- PYTHON_AUTHORED
- TOOL_AUTHORED
- COPIED_STAGED
- DERIVED_NORMALIZED
- UNKNOWN

## Tester evidence, if applicable

- tester_agent_path:
- tester_agent_log:
- tester_agent_log_SHA256:
- report_path:
- report_SHA256:
- history_quality:
- bars:
- ticks:
- orders:
- deals:
- trades:
- init_failures:
- execution_posture:
- current-run extraction boundary:

## Cleanup

- ticket_owned_PID_terminated:
- termination_time:
- orphaned_matching_processes:
- main_terminal_still_running:
- unexpected_files:
- quarantined_files:

## Deviations

List every deviation from the ticket or operational bridge. `None` is valid only after explicit review.

## Limitations

State what this run did not prove.

## Security

- secrets_printed: no
- account identifiers redacted:
- credential files read: no, unless explicitly authorized
- security incident:

## Runtime-only conclusion

- verdict:
- exact supporting evidence:
- blocker, if any:
- next owner:
- next required action:

This report does not certify strategy correctness, parity, profitability, checkpoint completion, or deployment readiness.
```
