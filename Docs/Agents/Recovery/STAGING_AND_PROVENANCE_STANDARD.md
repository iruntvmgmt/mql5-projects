# Staging and Provenance Standard

## 1. Purpose

This standard proves exactly which files entered the isolated runtime, which process produced each output, and whether Python and MQL artifacts were independently generated.

It directly prevents the prior failure mode where Python wrote identical journal copies into several directories and those copies were mistaken for MQL output.

## 2. Authorized runtime

All checkpoint-2 staging and execution is restricted to:

```text
/Users/matt/MT5-MSZZ-TEST
```

No checkpoint-specific fallback to the main MT5 installation is permitted.

## 3. Staging manifest location

```text
~/OpenClawEvidence/MC_CANON2/runtime/<TICKET_ID>/staging_manifest.csv
```

The manifest must exist before the first copy or move.

## 4. Required staging columns

```text
ticket_id
sequence
source_path
source_role
source_sha256
source_size_bytes
source_mtime_utc
destination_path
destination_existed_before
destination_preexisting_sha256
destination_preexisting_size_bytes
destination_preexisting_mtime_utc
action
reason
authorized_by
action_time_utc
destination_postaction_sha256
destination_postaction_size_bytes
destination_postaction_mtime_utc
verification_result
```

## 5. Allowed actions

```text
NO_ACTION_IDENTICAL
COPY_NEW
COPY_AUTHORIZED_REPLACEMENT
QUARANTINE_TASK_OUTPUT
CREATE_DIRECTORY
```

Prohibited actions:

```text
DELETE_UNRECORDED
COPY_TO_MAIN_TERMINAL
OVERWRITE_WITHOUT_PREHASH
GENERATE_MQL_OUTPUT_WITH_PYTHON
NORMALIZE_AFTER_RUN
```

## 6. Copy verification

After every copy:

- hash destination;
- compare source and destination size;
- compare source and destination SHA-256;
- record destination mtime;
- fail immediately on mismatch.

Do not batch-copy a directory without per-file manifest rows.

## 7. Quarantine policy

Preexisting task-specific outputs must be moved, not deleted, to:

```text
/Users/matt/MT5-MSZZ-TEST/MQL5/Files/_quarantine/<TICKET_ID>/
```

The quarantine manifest must preserve:

- original path;
- original hash;
- original mtime;
- quarantine path;
- post-move hash;
- reason.

Unrelated files may not be quarantined.

## 8. Compile provenance

Record:

```text
compile_source_path
compile_source_sha256
compile_source_mtime
compile_command
compile_start_utc
compile_end_utc
compile_log_path
compile_log_fresh_offset
error_count
warning_count
binary_path
binary_preexisting_sha256
binary_preexisting_mtime
binary_postcompile_sha256
binary_postcompile_mtime
binary_size_bytes
```

The binary post-compile mtime must be after compile start. A stale unchanged binary is not accepted.

## 9. Runtime provenance

Before launch, record:

- runtime executable/process path;
- runtime root;
- config path and hash;
- fixture input path and hash;
- EX5 path and hash;
- log path, size, hash, and fresh offset;
- output paths and pre-run state.

After launch, record:

- process ID where available;
- launch time;
- first fresh marker time;
- completion time;
- completion marker;
- output creation/mtime sequence.

## 10. Artifact manifest

Create:

```text
~/OpenClawEvidence/MC_CANON2/runtime/<TICKET_ID>/artifact_manifest.csv
```

Required columns:

```text
artifact_id
path
expected_author
existed_before
pre_run_sha256
pre_run_size
pre_run_mtime
post_run_sha256
post_run_size
post_run_mtime
row_count
column_count
encoding
bom
line_endings
final_newline
first_fresh_log_reference
authorship_basis
authorship_status
```

Authorship status values:

```text
MQL_AUTHORED_CONFIRMED
PYTHON_AUTHORED_CONFIRMED
AUTHORSHIP_AMBIGUOUS
UNCHANGED_STALE
MISSING
```

## 11. Independent-output requirement

To qualify as independent MQL evidence:

- the MQL-designated output must be absent or quarantined before launch;
- no Python process may write that output path during the run;
- the output mtime must be after launch;
- the harness log must identify journal creation or completion;
- the output must be linked to the ticketed EX5;
- the artifact must remain unmodified after the run.

## 12. Python reference isolation

Python reference artifacts should be generated in their canonical tool directory or an external evidence directory, not inside the isolated MQL output location.

When Python code intentionally copies reference files elsewhere, those copies must be labeled Python-authored and excluded from independent parity evidence.

## 13. Post-run immutability

After output collection:

- do not open/save artifacts in editors that may normalize line endings;
- do not run formatters;
- do not rewrite manifests;
- compute hashes immediately;
- copy evidence externally using a manifest-recorded operation;
- preserve original isolated-runtime outputs until review completes.

## 14. Provenance failure

If any artifact’s author cannot be proven, classify:

```text
RUNTIME_AUTHORSHIP_AMBIGUOUS
```

Do not use the artifact for checkpoint parity.

## 15. Reviewer requirements

The Reviewer must independently verify:

- staging rows cover every destination file;
- hashes match;
- no main-terminal destination exists;
- quarantine occurred before launch;
- binary identity is fresh;
- output mtimes follow launch;
- Python did not write MQL output paths;
- compared files are independently authored.
