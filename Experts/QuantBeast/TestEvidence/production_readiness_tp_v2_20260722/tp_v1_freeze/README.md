# TP_LIFECYCLE_V1 research freeze

**Tag:** `quantbeast-tp-v1-research-freeze-20260722` (annotated, points exactly at
commit `953c2d0`, no files differ from that commit).

**Frozen commit:** `953c2d057ed4578b18244a1b24fab9a5c78f20e1`
(2026-07-22 20:35:56 -0400, `QuantBeast: validate TP forward outcomes across 6
windows -- no reliable directional information found`).

## Why this is frozen now

TP V2 (a from-scratch, richer lifecycle -- see `../tp_v2_spec/`) is being built
alongside V1. V1 must stay a stable, reproducible reference point: its own
evidence, conclusions, and code must never silently drift or get overwritten
while V2 development proceeds. This freeze exists so V1 can always be checked
out, rebuilt, and reproduced exactly as it was evaluated, independent of
whatever V2 becomes.

## V1 hypothesis (as evaluated)

An observation-only forward-outcome question, not a trading rule: *does price
move further favorably than adversely, in the nominated direction, after a
TP `resume_candidate` event naturally fires under the existing (structural or
TP-specific) impulse/pullback lifecycle?* V1 never placed a trade based on
this -- it only measured whether the lifecycle *contains* a forward-testable
hypothesis worth converting into one.

## Lifecycle definition (V1, `ENUM_TP_LIFECYCLE_PHASE`)

`Include/QuantBeast/Strategies/TrendPullbackEngine.mqh`, `QB_TP_LIFECYCLE_VERSION = 1`:

```
IDLE -> IMPULSE -> RETRACING -> RESUME_CANDIDATE
                 \-> INVALIDATED
                 \-> EXPIRED
```

- Advances at most once per completed bar (`calc_time` dedupe in `ObserveLifecycle()`).
- Seed: shared `STRUCTURE_IMPULSE` (primary) or a TP-specific observation-only
  fallback (nominates a directional completed candle once TP's own
  persistence/efficiency floors hold and displacement >= 0.30 ATR) --
  `seed_source` field records which.
- `RESUME_CANDIDATE` is structurally single-bar: the very next call always
  resets to `IDLE` before any new seed check, so a resumption can never be
  read twice.
- **Never alters `EligibilityFailure()`** -- the lifecycle is pure
  observation; TP's actual trade eligibility gate is unchanged by it.
- No forming-bar or lookahead data anywhere: ATR and all impulse/extreme
  fields come from `features.closed_*` / shift-1 ATR.

## Forward-outcome tracker schema

`Include/QuantBeast/Analytics/TPOutcomeTracker.mqh`, class `CTPOutcomeTracker`,
writes `TPOutcomeJournal.csv`. Observation-only and side-effect-free: its API
surface takes no broker/risk/arbitration/portfolio reference at all, so there
is no reachable execution path from this class.

- Registers exactly one event per naturally reached `resume_candidate` bar.
- Measures forward MFE/MAE/close-return/threshold-reaches (+-0.25/0.50/1.00
  ATR) over 3/6/12/24-bar horizons, all pre-declared before evidence was
  collected.
- `SchemaVersion` (journal-row schema) is currently **2** (bumped from 1 at
  this freeze to add the `LifecycleVersion` column below). Schema v1 rows (76
  fields, no `LifecycleVersion` column) are exactly the rows already captured
  in `../../tp_forward_outcome_20260722/`; nothing schema-v1 was regenerated
  or altered by this freeze.
- **New at this freeze:** every row now carries `LifecycleVersion` (from
  `CTrendPullbackEngine::GetLifecycleVersion()`, currently always `1` for this
  engine) so V1 and V2 evidence can never be silently pooled even if journals
  were ever concatenated. V2 uses a separate engine/tracker pair and a
  separate journal file (see `../tp_v2_spec/`), so this is defense in depth,
  not the primary separation mechanism.
- Every TP rejection-reason diagnostic tag (`MakeLifecycleRejected()`) now
  also carries `lifecycleVersion=1` ahead of the existing `lifecycle=...`
  block, for the same reason.

## Genuine defect found and fixed as part of this freeze

`CTPOutcomeTracker::WriteRow()` incremented `m_totalFinalized` and set
`m_lastFinalized` only *after* successfully writing the CSV row, inside the
same early-return guarded by `if(m_handle == INVALID_HANDLE) return;`. That
means if the journal file could not be opened for any reason (disk full,
permissions, file-handle exhaustion), the tracker's own in-memory
finalized-event bookkeeping went silently blind -- `TotalFinalized()` would
read 0 forever and `GetLastFinalized()` would stay empty, even though events
were completing their lifecycle correctly in memory. This is a real
observability defect independent of any particular environment: a component
whose whole purpose is honest measurement must not silently misreport its own
state just because a downstream write failed.

Found via Test 70 (`QBTestTPOutcomeTruncatedHorizon`) failing deterministically
and reproducibly in this session's Wine sandbox, which hits a `FileOpen`
failure (`error=5004`) specifically when ten separate `CTPOutcomeTracker`
instances each `Init()`/reopen the same journal filename back-to-back within
one process (a pattern unique to this ten-test self-test block; the real
production/evidence-run pattern -- one global tracker, `Init()` once per run
-- is unaffected and has never shown this). Fixed by moving the bookkeeping
above the handle check so it always reflects true in-memory finalization
state regardless of file-write success. Verified: self-test regression
returned to **77 passed, 0 failed** after the fix. No eligibility, signal,
risk, or arbitration logic was touched.

## Test total (at this freeze)

**77 passed, 0 failed** (Model=1, `InpSelfTestOnInit=true`,
`Profiles/Tester/QuantBeast.SelfTestDetail.20260722.ini`, 2026-05-18..22
window). Tests 65-74 cover the outcome tracker specifically (dedup, sign
orientation, direction immutability, no-lookahead, truncation, no trading
side effects, reinit safety, deterministic IDs, threshold ambiguity,
retracement depth).

## Compile status

0 errors, 0 warnings (`MQL5\Experts\QuantBeast\QuantBeastEA.mq5`,
MetaEditor CLI, build 6033).

## Evidence

All V1 evidence lives in
`Experts/QuantBeast/TestEvidence/tp_forward_outcome_20260722/` (six
independent XAUUSD M5 Model=4 windows, exact byte-bounded journal slices, 16
unique registered `resume_candidate` events, pooled + per-window MFE/MAE
reports, Baseline B, and Phase 6 production-rejection attribution). That
directory is **not modified** by this freeze -- see hashes below for the
tools/evidence as they stood at commit `953c2d0`.

**Conclusion (unchanged, this is what is frozen):** Outcome A -- no reliable
directional information. The two largest-n contributing windows (2025-01-06
n=4, favorable; 2026-02-16 n=7, adverse) point in opposite directions, so the
pooled H24 fav/adv ratio is not a stable lifecycle property. All 16 events
were rejected at `EligibilityFailure()` before geometry was ever computed
(11/16 on the `regime.structure` mismatch, 5/16 on the directional-efficiency
floor) -- see `tp_forward_outcome_20260722/README.md` for the full
attribution.

## Known limitations (carried forward, unchanged)

- Baselines A/C/D (random bars, trend-direction-without-lifecycle,
  non-resuming impulse) were not computed -- chart-history retrieval worked
  for 2026-dated windows but not 2025-01-06, and with n=16 already
  inconclusive, full baseline construction was judged disproportionate scope
  for that pass. Documented as an explicit gap, not silently omitted.
- Sample size is small (n=16 total, largest single window n=7); no claim of
  edge is made or should be inferred from this evidence.
- The TP-specific lifecycle seed and the shared `STRUCTURE_IMPULSE`/
  `EligibilityFailure()` structural classifier remain in documented tension
  (see code comment in `ObserveLifecycle()`): the lifecycle can nominate a
  resumption that the production eligibility gate still rejects on structure
  grounds. This freeze does not resolve that tension -- V2 is a from-scratch
  attempt to do so with an explicit, decoupled invalidation model instead of
  reusing the single instantaneous `regime.structure` enum as sole authority.

## Reproducing V1 exactly

```bash
git checkout quantbeast-tp-v1-research-freeze-20260722
# (or: git checkout 953c2d0)
export WINEPREFIX="/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5"
WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
"$WINE" metaeditor64.exe /compile:"MQL5\Experts\QuantBeast\QuantBeastEA.mq5" /log
# then run Profiles/Tester/QuantBeast.CurrentRegression.*.ini (or any
# InpSelfTestOnInit=true profile) for the deterministic regression, or the
# six Profiles/Tester/QuantBeastEA.XAUUSD.M5.*.400.ini profiles listed in
# tp_forward_outcome_20260722/README.md for the organic evidence windows.
git checkout main   # return to the current branch afterward
```

The EX5 hash below is from the **current** (post-freeze-prep, main-branch)
build, not a saved binary from the exact `953c2d0` tree -- no historical EX5
artifact was preserved from the original evidence-gathering session, so
exact reproduction requires the recompile step above, which is deterministic
given the source hashes recorded here.

## Hashes

See `HASHES.sha256` (same directory tree, one level up) for the full
machine-checkable manifest. Key entries, source files as committed at
`953c2d0`:

| File | SHA-256 |
|---|---|
| `Include/QuantBeast/Strategies/TrendPullbackEngine.mqh` | `c61451ec8cd8b926a9d6443d3ab97c9e4b43ff8349a2575536fea872ce38e181` |
| `Experts/QuantBeast/QuantBeastEA.mq5` | `5ac554dde1088d0b5e2d466cce1bb5ca8c3b48c10b15175e81f63fb1ebb5e566` |
| `Include/QuantBeast/Analytics/TPOutcomeTracker.mqh` | `868a5f4966f28b305cee8c36db0f14dea2011a1344839bf042d51eeb553b8b28` |
| `Experts/QuantBeast/Tools/tp_outcome_report.py` | `6aa7e7500f55b515f973cb2f6cabaeb3573ddc77e12c454af3d03d55b1fc563f` |
| `Experts/QuantBeast/Tools/tp_rejection_attribution_report.py` | `480b29201e253983e69bdb353bfadbf389866ae7514260c975303c90843ac5f6` |
| `Experts/QuantBeast/Tools/tp_structure_report.py` | `aa58703fc43025822120b9c5806d558fef78271eeea011f1980a48a7dc22e7d0` |

Current build (post-freeze-prep, includes `LifecycleVersion` tagging + the
`WriteRow` bookkeeping fix described above):

| File | SHA-256 |
|---|---|
| `Experts/QuantBeast/QuantBeastEA.ex5` (compiled) | `6d730eea4a7283b36da4df172fc00e5acf01a6cf7c415e3676b652edd8d7cc8a` |

Six evidence-window tester profiles (`Profiles/Tester/`, untracked, unchanged
since evidence generation):

| Profile | SHA-256 |
|---|---|
| `QuantBeastEA.XAUUSD.M5.20260105_20260106.400.ini` | `87eeb0ffc5c811358322ec96af247b1df26166a5fd61ec63c91e86f5d3bcfded` |
| `QuantBeastEA.XAUUSD.M5.20250106_20250107.400.ini` | `85272d227ada50f5ea1f7fa0edb8e90e6e51aa685266fc14610aa213fbba7a24` |
| `QuantBeastEA.XAUUSD.M5.20260504_20260505.400.ini` | `b0589af841bbce681061e54be4ac60e55e059869e153291d49fedb52aa89e00b` |
| `QuantBeastEA.XAUUSD.M5.20260126_20260130.400.ini` | `295620a98758b4f6a3c10b81447868d66e43e3da83e9bb27f1489bd72c374065` |
| `QuantBeastEA.XAUUSD.M5.20260216_20260220.400.ini` | `070e09e9c29b375d7294430fc1444aa66243fa45a6ce97685cbfd304f4ee555e` |
| `QuantBeastEA.XAUUSD.M5.20260620_20260624.400.ini` | `205e12868baeb72b7666ee6364f2ae1457f04d5538ef45df51f38d9b90ceb627` |

## V1/V2 evidence isolation guarantee

1. **Physically separate journal files.** V1 writes `TPOutcomeJournal.csv`
   (via the global `g_TPOutcomeTracker` / `CTrendPullbackEngine`). V2 will
   write a distinct filename from its own engine/tracker pair -- never the
   same file.
2. **`LifecycleVersion` column** on every row and diagnostic tag, as defense
   in depth, in case anyone ever concatenates journals by hand.
3. **This freeze tag** so V1's exact source is always independently
   reproducible and never overwritten by V2 development.
4. V1's tracker (`CTPOutcomeTracker` / `CTrendPullbackEngine`) remains wired
   into `QuantBeastEA.mq5` unchanged in behavior going forward -- available
   for future passive larger-window verification -- while V2 is added
   alongside it, not in place of it.
