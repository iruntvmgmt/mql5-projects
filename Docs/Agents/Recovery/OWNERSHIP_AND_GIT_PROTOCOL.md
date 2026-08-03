# Ownership and Git Protection Protocol

## 1. Purpose

This protocol prevents agent collisions, loss of inherited uncommitted work, accidental branch movement, mixed artifact provenance, and unauthorized history creation during MC-CANON-2 checkpoint-2 recovery.

## 2. Canonical tree

The canonical repository tree is:

```text
/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

This tree is also the installed MT5 source location. Ordinary secondary Git worktrees must not be treated as interchangeable compile/runtime roots.

## 3. Single-writer assignment

The MultiSpeedZigZag Lead is the only agent permitted to modify the canonical tree.

The Runtime Engineer and Reviewer are read-only with respect to the canonical tree.

## 4. Prohibited Git operations

No recovery agent may run:

```text
git reset
git clean
git stash
git restore
git checkout -- <path>
git switch
git checkout <branch>
git rebase
git commit --amend
git merge
git cherry-pick
git revert
git tag
git push
git push --force
git update-ref
```

No recovery agent may delete lock files or manually rewrite `.git` metadata.

## 5. No commits during recovery

Agents may prepare:

- proposed commit grouping;
- proposed commit messages;
- proposed changed-file inventory.

They may not create commits.

A higher-capability reviewer must audit the complete inherited and recovery diff before the user authorizes history creation.

## 6. Session guardrail record

At session start, the Lead records:

```text
absolute_working_directory
current_branch
current_HEAD
remote_recovery_HEAD
origin_main_HEAD
backup_precert_HEAD
git_status_short
git_diff_stat
git_diff_name_only
session_start_utc
```

Write this outside the repository.

At session end, record the same fields and compare them.

## 7. File ownership table

### MultiSpeedZigZag Lead

May write only active MC-CANON-2 source, tests, tools, and documentation explicitly required by checkpoint 2.

### MT5 Runtime Engineer

May write:

- external evidence directories;
- isolated-runtime staging destinations;
- isolated-runtime task-specific quarantine;
- explicitly authorized runtime-tool scripts outside the canonical tree.

May not write canonical source.

### Independent Reviewer

May not write repository or isolated-runtime content.

May write review reports externally.

## 8. Ownership transfer

If the Lead must transfer one file temporarily, create an ownership-transfer record containing:

```text
transfer_id
from_role
to_role
exact_path
allowed_operation
reason
starting_sha256
starting_mtime
transfer_start_utc
transfer_expiry_condition
required_return_evidence
```

The receiving agent may modify only that exact path and only for the specified operation.

After return, the Lead records:

```text
ending_sha256
ending_mtime
diff_summary
accept_or_reject
transfer_close_utc
```

Directory-wide transfers are forbidden.

## 9. Concurrent-edit detection

Before every write, the Lead checks the target file’s current hash against the session inventory or last accepted write.

If the hash changed unexpectedly:

1. stop;
2. do not overwrite;
3. identify the external writer if possible;
4. record current hash and mtime;
5. escalate.

## 10. Dirty-tree preservation

The inherited uncommitted tree is evidence.

Do not:

- normalize line endings globally;
- run project-wide formatters;
- regenerate broad outputs;
- delete untracked files;
- replace files from remote copies;
- use `git checkout` to restore expected content.

When a generated artifact must be replaced, preserve the prior version externally or in authorized isolated quarantine with hashes.

## 11. Branch mismatch

If current branch or HEAD differs from the handoff:

- do not switch branches;
- do not reset;
- record actual and expected refs;
- inspect whether the handoff is stale;
- ask the user or coordinator for resolution.

## 12. Protected refs

The following refs are treated as protected during this recovery:

- current recovery branch ref;
- `origin/main`;
- `backup-precert`.

No agent may move, delete, recreate, or force-update them.

## 13. External report directory

Use:

```text
~/OpenClawEvidence/MC_CANON2/
```

Recommended structure:

```text
session/
runtime/
lead/
reviews/
transfers/
quarantine_indexes/
```

External reports must include task ID and UTC timestamp.

## 14. End-of-recovery Git report

The Lead’s evidence index must state:

- branch and HEAD unchanged or exact authorized change;
- no commits;
- no pushes;
- protected refs unchanged;
- list of modified tracked files;
- list of untracked files;
- files changed during this recovery versus inherited changes;
- no unrelated QuantBeast production changes;
- no historical screening outputs.
