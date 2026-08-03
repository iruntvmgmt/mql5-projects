# MT5 Log and Artifact Protocol

## 1. Purpose

Prevent stale, cumulative, misdecoded, or wrongly attributed files from being accepted as current runtime evidence.

## 2. Encoding

MT5 and MetaEditor logs commonly use UTF-16LE.

Decode with:

```bash
iconv -f utf-16le -t utf-8 < "$LOG"
```

or:

```python
from pathlib import Path
raw = Path(log_path).read_bytes()
text = raw.decode("utf-16le", errors="replace")
```

Record the encoding actually observed. Do not normalize original evidence before hashing it.

## 3. Pre-run boundary

Before launch, record for each relevant file:

- path;
- existence;
- byte length;
- mtime;
- SHA-256;
- decoded line count when applicable.

If a file does not exist, record `ABSENT` rather than creating an empty placeholder.

## 4. Fresh run extraction

Preferred methods, in order:

1. byte-offset extraction from the pre-run size;
2. unique run ID marker emitted by the harness;
3. exact initialization marker and timestamp;
4. decoded line-offset extraction.

A cumulative daily log must be sliced to the current run. Do not count PASS/FAIL markers from the full file.

## 5. Delayed log creation

After portable launch:

- verify the process exists;
- poll the expected logs directory;
- discover actual dated files;
- allow bounded startup delay;
- stop only after timeout or definitive failure.

A temporary `FileNotFoundError` immediately after spawn is not sufficient evidence of failure.

## 6. Execution-specific locations

### Script terminal journal

```text
<ISO>/MQL5/logs/<date>.log
```

### Script file output

```text
<ISO>/MQL5/Files/
```

### Tester agent journal

```text
<ISO>/Tester/Agent-127.0.0.1-*/logs/<date>.log
```

### Tester output

```text
<ISO>/Tester/Agent-127.0.0.1-*/MQL5/Files/
```

### Tester report

```text
<ISO>/Reports/
```

### MetaEditor compile evidence

Typically source-adjacent `.log` plus source-adjacent `.ex5`.

Use bounded discovery:

```bash
find "$ISO/Tester" -maxdepth 5 -type f -name 'MSZZ_SignalJournal.csv' -print
```

Do not use unrestricted filesystem searches.

## 7. Original-byte preservation

For every output artifact:

1. hash original bytes immediately;
2. record size and mtime;
3. copy to evidence storage if required;
4. hash copied bytes;
5. only then decode or parse;
6. preserve the original file unchanged.

Line-ending or encoding conversion creates a derived artifact and must receive a different filename and provenance record.

## 8. Authorship classification

Every artifact must be labeled:

```text
MQL5_AUTHORED
PYTHON_AUTHORED
TOOL_AUTHORED
COPIED_STAGED
DERIVED_NORMALIZED
UNKNOWN
```

Independent parity requires independently authored authoritative artifacts. Two copies created by one process are not independent evidence.

## 9. Artifact identity fields

Record:

- logical artifact name;
- exact path;
- author process/language;
- source inputs;
- runtime PID;
- launch INI hash;
- creation time;
- size;
- SHA-256;
- row count if structured text;
- encoding;
- line endings;
- final-newline state;
- parser/validation result;
- copied/derived relationships.

## 10. Report plus journal plus data

For Strategy Tester, use all applicable layers:

- report for aggregate tester configuration/results;
- tester-agent journal for runtime behavior;
- terminal journal for launch context;
- generated CSV/journals for detailed output;
- source and binary hashes for identity.

No single layer substitutes for the others.

## 11. Quarantine

Before a rerun, stale ticket-owned outputs may be moved into:

```text
<EVIDENCE_DIR>/quarantine/<timestamp>/
```

Record original path, quarantine path, SHA, and reason.

Do not delete stale files merely to make output detection easier.

## 12. Completion markers

The ticket must define exact expected markers, such as:

```text
CERTIFIED_JOURNAL_START
CERTIFIED_JOURNAL_COMPLETE
failures=0
```

The Runtime Engineer may not invent substitute markers after the run.

## 13. Failure markers

Capture and report:

- init failure;
- include/input missing;
- assertion failure;
- fixture failure;
- file-open/write failure;
- invalid schema;
- timeout;
- terminal crash;
- no-op launch;
- stale-output ambiguity.

## 14. Evidence rejection conditions

Reject evidence when:

- the log slice cannot be isolated;
- output predates the launch;
- output hash matches a preexisting file without a documented rewrite;
- process authorship is unknown;
- expected completion marker is absent;
- source/binary/INI identity is incomplete;
- output appears in the main terminal during an isolated ticket;
- a parser silently repairs malformed output.
