# Screening Simulator V2 — Journal-Binding Design Record

Required pre-implementation design record for the certification-hardening
correction (candidate→journal binding, two-layer no-bypass architecture).
Produced after auditing JournalTransportV2, ResearchCandidateSchemaV2, and the
current simulator. Nothing here requires changing canonical JournalTransportV2
bytes or ResearchCandidateSchemaV2 semantics.

## Audit summary

- **Python** `research_journal_transport_v2.validate_journal_bytes()` validates
  canonical bytes and returns `row_count / journal_sha256 / event_ids /
  sequence_ids`. It does **not** reconstruct typed candidates and returns **no
  rows**.
- **MQL5** `CMSZZResearchJournalTransportV2::ValidateJournalBytes()`
  reconstructs `MSZZResearchCandidateV2` per row (with canonical round-trip)
  but **discards** them, returning only `row_count / journal_sha256 / reason`.
  Its `ReconstructCandidate()`, `SplitDocument()`, `ParseRecord()` are public.
- Current simulator binding (`screening_simulator_v2.py` `_dataset_identity`)
  only checks `_is_sha256(journal_sha256)` — syntactic. F01–F58 candidates are
  synthetic, not journal-derived.
- ResearchCandidateSchemaV2 IDs are **printable UTF-8** (schema doc line 24),
  not ASCII-only → explicit UTF-8 byte comparator required (Correction 2).
- Journal **row order is hash-significant**: the transport never reorders
  rows; it hashes the exact file bytes. A permutation changes the bytes and
  therefore the SHA.

## 1. Additive Python transport API (authorized, narrow)

New, purely additive, in / beside `research_journal_transport_v2.py`. No
existing function, accepted/rejected byte, canonical serialization, or manifest
rule changes. Internally reuses the certified validator + private helpers;
external callers use only the new public symbol.

```python
@dataclass(frozen=True)
class VerifiedJournalRowsV2:
    transport_version: str          # MSZZ_RESEARCH_MANIFEST_V2 family / module version tag
    schema_version: str             # MSZZ_RESEARCH_CANDIDATE_V2
    journal_sha256: str             # from the certified validator (not caller-supplied)
    row_count: int
    rows: tuple[tuple[str, ...], ...]   # validated data rows (header excluded), immutable
    event_ids: tuple[str, ...]
    sequence_ids: tuple[str, ...]

def reconstruct_verified_rows(data: bytes, header: list[str]) -> VerifiedJournalRowsV2:
    """Run the certified validate_journal_bytes(), then return the already-
    validated rows immutably. Additive; does not alter existing behavior."""
```

`validate_journal_bytes()` is extended **only additively** to also place `rows`
in its returned dict (existing keys unchanged), so `reconstruct_verified_rows`
does not re-parse. JournalTransportV2's own test suite is re-run to prove no
regression. Dependency direction stays JournalTransportV2 → adapter →
ScreeningSimulatorV2 (transport never imports simulator types).

## 2. MQL5 verified-bundle construction path

`CMSZZScreeningJournalBindingV2` (new adapter, research tooling layer) builds a
verified bundle **only after**, in order:
1. `ValidateJournalBytes(data,row_count,journal_sha256,reason)` succeeds
   (retains the transport-returned `journal_sha256`, never a caller value);
2. manifest parse + `VerifyManifest`-equivalent binding succeeds;
3. `SplitDocument` + `ParseRecord` per row;
4. `ReconstructCandidate` succeeds for every row (canonical round-trip inside);
5. row count matches manifest and reconstructed count;
6. each reconstructed `MSZZResearchCandidateV2` is projected to a simulator
   candidate; the projection digest is computed and retained.
No canonical MQL5 transport behavior changes.

## 3. Named field projection (ResearchCandidateSchemaV2 → simulator candidate)

By column **name** (constants), never bare indices, rejecting any row that
cannot supply a field without inference:

| simulator field | journal column | notes |
|---|---|---|
| strategy_id | 1 strategy_id | int |
| family_id | 2 family_id | int |
| hypothesis_version | 3 hypothesis_version | |
| canonical_variant_id | 4 canonical_variant_id | |
| origin_id | 5 origin_id | |
| sequence_id | 6 sequence_id | |
| event_id | 7 event_id | |
| clock_domain | 8 clock_domain | BROKER_SERVER_RAW |
| time_authority_id | 9 time_authority_id | MSZZ_TIME_RAW_BROKER_V1 |
| signal_time | 10 signal_time_raw | int |
| expiry_time | 11 expiry_time_raw | int |
| direction | 12 direction | LONG→+1, SHORT→−1 |
| entry | 13 entry | journal-owned |
| stop | 14 stop | journal-owned |
| target | 15 target | journal-owned (preserved as candidate evidence) |
| target_r | 28 target_r | journal-owned |
| stop_distance_points | 27 stop_distance_points | journal-owned |

**Target handling:** the journal owns both an explicit `target` (col 15) and
`target_r` (col 28); the projection preserves **both** verbatim. The simulator's
policy-based *executable* target reconstruction (after entry) is unchanged and
is separate from preserving this raw candidate evidence — no journal-owned
field is recomputed then claimed as bound.

## 4. Journal row order

Hash-significant. The transport hashes exact file bytes and never reorders.
JB23 (permutation): a permutation honestly re-manifested (SHA over the permuted
bytes) still passes binding and yields identical outcomes because the simulator
re-sorts into the frozen order; a permutation that keeps the old SHA fails
binding (`REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH`).

## 5. JB fixture family: family 8 (SSR)

Chosen over family 11 (CBR). Both are non-structural (structural block cols
34–73 empty; no StructuralEventRecord coupling). Family 8 SSR extension (cols
74–79) needs only: `ssr_clock_rule_id`, `ssr_range_id` non-empty;
`ssr_range_high > ssr_range_low`; `ssr_sweep_extreme > 0`;
`ssr_reclaim_close > 0`. Family 11 additionally couples a window to the
lifecycle (`cbr_window_end_raw < trigger_time_raw`) and needs three positive
ATRs — more cross-field coupling for no benefit. Family 8's mandatory fields and
extension are representable canonically with the simplest standalone geometry,
so it is chosen; event_id is a plain printable-UTF-8 ID (non-structural
families do not require the `MSZZSE2|` structural-event prefix).

## 6. Projection document `MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2`

Canonical, byte-identical across Python and MQL5: one QUOTE_ALL RFC-4180 record
per projected candidate, fields in the order of §3 (17 fields), CRLF-terminated
including the final record, UTF-8 no BOM, prefixed by a version header line
`MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2`. Doubles serialized with the
schema's `.16f`; ints as decimal; direction as the projected ±1. The
**projection SHA-256** is taken over these exact bytes. Recorded **alongside**
the canonical journal SHA — journal SHA proves source bytes, projection SHA
proves the exact simulator input derived from them. In MQL5 the digest is
recomputed immediately before invoking the core and compared, catching any
mutation during the object lifecycle.

## 7. Public API — before / after

**Before (permissive; to be removed from the public surface):**
- Python: `run_screening(candidates, candidate_manifest, market, market_manifest, params, policy_id, test_end)`
- MQL5: `CMSZZScreeningSimulatorV2::RunScreening(cands, cm, bars, symbol, tf, sha, mm, params, policy_id, test_end, outcomes)`

**After:**
- Layer 1 core (mechanics only, not certified entry):
  - Python `_run_screening_core(candidates, candidate_manifest, market, market_manifest, params, policy_id, test_end)` — module-private; identical logic to today's `run_screening` (preserves F01–F58 outcome SHAs byte-for-byte).
  - MQL5 `RunScreeningCoreForFixtures(cands, cm, ...)` — documented test-only (MQL5 lacks module-private free functions); F suite calls this.
- Layer 2 certified public entry (bundle-only):
  - Python `run_screening(bundle: VerifiedCandidateJournalV2, market, market_manifest, params, policy_id, test_end)` — re-derives candidates from `bundle` journal bytes via the adapter, re-checks journal SHA + projection digest + manifest/market binding, then calls `_run_screening_core`. Rejects any mismatch with `REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH`, `outcomes=[]`.
  - MQL5 `RunScreening(bundle, bars, symbol, tf, sha, mm, params, policy_id, test_end, outcomes)` — same contract.

The public entry accepts no arbitrary candidate array, no detached manifest, no
caller-supplied journal SHA without bytes, no synthetic bundle, no
`skip_verification`/test-mode flag. An unbound run is structurally impossible on
the public path because candidates are reconstructed from the verified bytes.

## 8. Removal / isolation of the old permissive API

- Python: today's `run_screening` body becomes `_run_screening_core` (leading
  underscore = module-private by convention); the F01–F58 test switches to
  `_run_screening_core`. There is no public function taking a raw candidate
  list. `VerifiedCandidateJournalV2` is produced only by the adapter, and
  `run_screening` re-reconstructs from bytes so a hand-forged bundle cannot
  smuggle candidates.
- MQL5: the array-taking method is renamed `RunScreeningCoreForFixtures` and
  documented "TEST-ONLY — not the certified entry"; the certified `RunScreening`
  takes only the bundle. F suite → core; JB suite → public entry.

## Statuses & precedence

`REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH` covers: journal-SHA mismatch,
manifest journal binding, row-count mismatch, reconstructed-row identity
mismatch, projection-digest mismatch, post-verification mutation. Existing
specific statuses stay for symbol / timeframe / source-data-SHA / clock-domain /
time-authority mismatch and unsupported policy. **Precedence** (first failing
gate wins): (1) transport/manifest validity → binding-mismatch; (2) market
identity (symbol, timeframe, source-data, clock, authority, market hash,
params, policy) as today in the core. Binding is checked in Layer 2 before the
core's market-identity checks.

## Fixture taxonomy (reported separately)

- `EXECUTION` F01–F58 — core mechanics; unchanged expected SHAs.
- `JOURNAL_BINDING` JB01–JBxx — public bound path over real 116-column journals.
- `ORDERING` OR01–ORxx — UTF-8 comparator parity (incl. multibyte).

## Conclusion

No canonical JournalTransportV2 byte change and no ResearchCandidateSchemaV2
semantic change is required. Proceeding per authorization.
