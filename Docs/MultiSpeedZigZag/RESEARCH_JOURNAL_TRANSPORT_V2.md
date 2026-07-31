# Research Journal Transport v2

## Scope

This phase certifies the evidence boundary between a validated
`MSZZResearchCandidateV2` and downstream research tools. It does not modify a
family generator, signal formula, simulator, production adapter, or execution
path.

## Canonical journal

The only accepted journal encoding is:

- UTF-8 without a BOM;
- the exact 116-column Schema V2 header;
- CRLF record terminators, including the final record;
- every data field double-quoted;
- embedded quotes doubled;
- writer-canonical integer, floating-point, enum, Boolean, and raw-time text;
- `MSZZ_RESEARCH_CANDIDATE_V2` in every row.

The parser does not accept an alternate RFC-4180 spelling and normalize it.
Every parsed row must reserialize byte-for-byte through
`CMSZZResearchCandidateCsvV2`.

## Typed reconstruction

The MQL parser reconstructs the common record, optional certified structural
binding, and the owning family extension. It derives point size from initial
risk and the recorded stop distance, then reruns
`CMSZZResearchCandidateSchemaV2::Validate`. A row fails if typed validation or
canonical reserialization differs.

Non-owning family extensions must be empty. MC, BRC, and TP require the full
structural binding; other families must not carry one. Duplicate `event_id` or
`sequence_id` values fail the complete dataset.

The Python parser independently enforces the byte transport, common typed
fields, extension partition, and family extension invariants. Shared fixtures
require the same accept/reject classification. The MQL-produced canonical
journal is then consumed by Python, and both implementations must emit an
identical manifest.

## Manifest

Manifest version `MSZZ_RESEARCH_MANIFEST_V2` contains:

```text
manifest_version
writer_version
schema_version
symbol
timeframe
row_count
journal_sha256
source_data_sha256
```

The writer version is `MSZZ_RESEARCH_CSV_WRITER_V2`. Hashes are SHA-256 over
the exact bytes. Verification requires the caller-supplied symbol, timeframe,
and independently known source-data hash to match before the journal is
accepted.

## Fail-closed conditions

The study fails on invalid UTF-8, BOM, bare CR/LF, missing final CRLF, invalid
quoting, header or column mismatch, noncanonical text, unsupported schema,
invalid enum/number/time, typed candidate validation failure, unexpected
extension data, duplicate lifecycle/event identity, row-count mismatch, file
hash mismatch, market mismatch, or source-data hash mismatch.

No V1 repair, row stitching, delimiter inference, or reconstruction from free
text is permitted.

## Authorization

This transport certification does not authorize a family. All six adapters
remain blocked by their existing specification, service, and invariant gates.
The next shared phase is the executable screening-policy implementation.
