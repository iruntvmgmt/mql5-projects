# Research Candidate Schema v2

Schema identifier: `MSZZ_RESEARCH_CANDIDATE_V2`.

The shared type, validator, derived-field policy, certified structural-event
handoff and canonical CSV writer are implemented in
`ResearchCandidateSchemaV2.mqh` and `ResearchCandidateCsvV2.mqh`. This is
additive infrastructure: no six-family generator emits v2 yet, and the legacy
D031 journal remains unchanged evidence.

## Common record

The common record is write-once after emission. Required fields are dedicated typed members and dedicated journal columns: schema/version and family identifiers; `origin_id`, `sequence_id`, `event_id`; clock domain and time-authority ID; signal/expiry/direction and geometry; typed reference; arm/trigger lifecycle; reset/prior terminal state; arm/trigger ATR and cost; session/regime IDs.

`structural_context` is removed as a required evidence carrier. A final optional `diagnostic_json` column may contain supplemental escaped diagnostics, never data required to validate, simulate, attribute, or reconcile a candidate.

## Identity and lifecycle

- `origin_id` identifies the immutable market source.
- `sequence_id` identifies one arm-to-terminal lifecycle.
- `event_id` identifies its one final emission.
- `arm_time <= trigger_time == signal_time < expiry_time`.
- `bars_armed` is the number of fully closed timeframe bars after the arm bar through the trigger bar; same-bar trigger is zero.
- IDs are nonempty printable UTF-8, deterministic, and unique at their defined scope.

## Clock contract

Until `MSZZ_TIME_AUTH_C1` has an implemented, committed dataset conversion
table, candidate times are `BROKER_SERVER_RAW` only. Every time column is the
raw integer `datetime` value and the record carries authority
`MSZZ_TIME_RAW_BROKER_V1`. The writer must not decompose this value and append
`Z`. `UTC_CONVERTED` fails validation until the time-authority phase supplies a
certified conversion service.

## Structural binding

MC, BRC and TP require an embedded copy of one valid
`MSZZStructuralEventRecord`. The binding is populated through
`BindCertifiedStructuralEvent`, revalidated at candidate validation, and
serialized as dedicated ownership columns.

The following must agree with that single record:

- candidate direction;
- structural reference ID and event-bar projected reference price;
- MC event ID, impulse origin, impulse extreme and normalized impulse distance;
- BRC event ID, broken pivot ID and event-bar projected broken level;
- TP impulse event ID.

An `MSZZSE2`-prefixed string without the typed binding is invalid.
Independently supplied or current-snapshot geometry cannot be mixed with the
binding.

## Validation

Enums must be known. Required strings are nonempty. Prices and ATR are finite and positive; stop and target are directionally valid; `stop_distance_points` equals absolute entry-stop divided by point size; `target_r` equals absolute target-entry divided by risk; spread is nonnegative; spread/risk is recomputable. Reference ID/price are required whenever reference type is not `NONE`.

Missing or invalid required evidence rejects the candidate before journaling and fails a study if encountered in an input journal. No default may make malformed evidence appear valid.

## Serialization

Canonical journal format is UTF-8 RFC 4180 CSV:

- comma delimiter, CRLF records, double-quote escaping by doubled quotes;
- raw integer timestamps plus explicit clock domain and time-authority ID;
- decimal point `.` and locale-independent round-trip precision;
- enums serialized by frozen uppercase token;
- booleans `true`/`false`;
- empty field only for explicitly optional data;
- fixed column order from `candidate_schema_v2.csv`;
- header contains exact column names; schema version occurs in every row;
- companion manifest records row count, SHA-256, writer version, symbol, timeframe and data hash.

Column-count mismatch, invalid quoting/UTF-8, unsupported version, invalid enum/number/time, duplicate event ID, missing required value, hash/row mismatch, or failed invariant terminates the study. Parsers must never stitch, infer, or reconstruct malformed rows.

## Migration

V1 rows are not silently promoted. A separate offline migration tool may emit v2 only when every required value is directly recoverable from typed v1 columns. It records source hash and per-row provenance. Rows requiring `structural_context` parsing, guessed sequence/reset/ownership, or heuristic delimiter repair are `UNMIGRATABLE` and exclude the dataset from certification.

## Family extensions

Extensions are fixed columns following common columns, prefixed `ssr_`, `mc_`, `brc_`, `cbr_`, `tp_`, or `rr_`. Columns for other families remain empty. Each family validates its required extension set before emission.

MC, BRC and TP structural extension identities accept only certified
`MSZZSE2` IDs. `MSZZSE1` is historical infrastructure evidence and cannot
enter a v2 record.

## Invalid candidate contract

Validation failure blanks every consumable identity, time, geometry,
extension, and structural-binding field. Only
`schema_version=MSZZ_RESEARCH_CANDIDATE_V2` and `validation_reason` remain.
Invalid candidates cannot be serialized or journaled. Attempted forensic
values require a future separate diagnostic type and may never share the
candidate interface.

- SSR: authoritative clock rule/version, range and level IDs/prices, reset, sweep extreme, reclaim.
- MC: immutable structural event, impulse endpoints/ATR, efficiency, pause/pullback, medium invalidation.
- BRC: immutable break/level, first touch, rejection, penetration and test count.
- CBR: window bounds/hash, ATR/range compression statistics, medium alignment, extension and obstruction.
- TP: owned trend impulse, value anchor/reference and distance trajectory, proximity and resumption.
- RR: frozen range, width stability, confirmed pivot touches/separation/rotation, lifetime containment and midpoint.

The complete field registry is machine-readable in `candidate_schema_v2.csv` and `family_extension_fields.csv`.
