# Session Inventory Standard

## 1. Purpose

The session inventory preserves the inherited dirty tree and creates an objective baseline for detecting accidental edits, external writers, stale artifacts, and false runtime provenance.

The inventory is mandatory before any recovery write or runtime staging.

## 2. Output location

Write outside the repository:

```text
~/OpenClawEvidence/MC_CANON2/session/<UTC_TIMESTAMP>/
```

Required files:

```text
git_guardrails.txt
active_files.csv
runtime_files.csv
process_state.txt
inventory_summary.md
```

## 3. Git guardrails

Record exact output from:

```bash
pwd
git branch --show-current
git rev-parse HEAD
git rev-parse origin/recovery/research-journal-manifest-parser-v2
git rev-parse origin/main
git rev-parse backup-precert
git status --short
git diff --stat
git diff --name-only
git ls-files --others --exclude-standard
```

Do not truncate output.

## 4. Active source inventory

For every current MC-CANON-2 file record:

```text
path
absolute_path
tracked_state
size_bytes
mtime_utc
sha256
file_type
line_count
owner_role
frozen_or_mutable
purpose
```

The inventory must include all files named by the active handoff plus any transitive harness dependencies discovered from includes/imports.

## 5. Required minimum canonical files

Inventory at least:

```text
Docs/MultiSpeedZigZag/MC_V2_CANONICAL_SPEC.md
Docs/MultiSpeedZigZag/MC_V2_CANONICAL_SPEC_AUDIT.md
Tools/SixFamilyRecovery/MomentumContinuationV2/mc_canon2_adapter.py
Tools/SixFamilyRecovery/MomentumContinuationV2/mc_canon2_fixtures.py
Tools/SixFamilyRecovery/MomentumContinuationV2/test_mc_canon2.py
Tools/SixFamilyRecovery/MomentumContinuationV2/make_mc_fixtures.py
Tools/SixFamilyRecovery/MomentumContinuationV2/test_make_mc_fixtures.py
Tools/SixFamilyRecovery/MomentumContinuationV2/ser_policy.py
Tools/SixFamilyRecovery/MomentumContinuationV2/candidate_schema_v2.py
Tools/SixFamilyRecovery/MomentumContinuationV2/mc_schema_projection.py
Tools/SixFamilyRecovery/MomentumContinuationV2/build_fixture_journal.py
Tools/SixFamilyRecovery/MomentumContinuationV2/test_mc_certified_journal.py
Include/MultiSpeedZigZag/Research/Families/MomentumContinuationV2.mqh
Tests/MultiSpeedZigZag/Test_MSZZ_MomentumContinuationV2.mq5
Tests/MultiSpeedZigZag/Test_MSZZ_MC_CANON2_CertifiedJournal.mq5
```

Add generated fixture, journal, manifest, and evidence files when present.

## 6. Isolated runtime inventory

For `/Users/matt/MT5-MSZZ-TEST`, record:

- relevant source and EX5 files;
- required include files;
- INI/config files;
- fixture inputs;
- preexisting journals and manifests;
- current logs;
- quarantine directories;
- file size, mtime, and SHA-256.

Do not assume a file is MQL-authored because it is under `MQL5/Files`.

## 7. Process inventory

Record read-only process and port state:

```bash
pgrep -fl terminal64
lsof -i :22346 -P -n
lsof -i :8228 -P -n
```

Record current time and timezone.

## 8. Dependency inventory

For the CertifiedJournal harness, produce a dependency table:

```text
dependency
source_path
include_or_runtime_input
expected_isolated_destination
source_sha256
required_for_compile
required_for_runtime
frozen
```

Resolve all direct and transitive includes. Do not stage from a guessed list.

## 9. Delta inventory

After each accepted Lead edit, append:

```text
change_id
path
pre_sha256
post_sha256
pre_mtime
post_mtime
reason
authorized_by
related_ticket
```

The original inventory is immutable. Deltas are appended separately.

## 10. Unexpected change detection

Before writing or issuing a runtime ticket, rehash every target and dependency.

If any hash differs from inventory without a recorded delta:

- stop;
- label `UNEXPECTED_CONCURRENT_CHANGE`;
- preserve both current and recorded metadata;
- do not overwrite;
- escalate.

## 11. Inventory summary

`inventory_summary.md` must state:

- branch and HEAD;
- expected versus actual refs;
- tracked modified count;
- untracked count;
- inherited active MC files;
- missing expected files;
- unexpected files;
- isolated-runtime status;
- current MT5 process state;
- whether it is safe to issue a runtime ticket.

## 12. Privacy and security

Do not include:

- bearer tokens;
- passwords;
- account credentials;
- private keys;
- complete broker account identifiers.

Redact sensitive command output before saving externally, while preserving enough structure to prove the check was performed.
