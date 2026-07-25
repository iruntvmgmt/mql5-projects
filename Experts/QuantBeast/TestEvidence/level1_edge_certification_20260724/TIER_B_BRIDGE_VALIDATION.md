# Level-1 Edge Certification -- Tier B: Model=1 vs Model=4 Bridge Validation

**Run 2026-07-24, post pending-orders-cap fix (commit `996a799`).** Frozen
canonical roster (`Profiles/Tester/QuantBeast.Level1Cert.roster.set`:
`InpMode=1` Shadow, canonical BO/FBO/MR/TPV2 roster, `InpPersistState=false`,
`InpUseGlobalVars=false`), identical for every run below. Two windows, each
run once at Model=4 (real ticks) and once at Model=1 (generated ticks from
real M1 bars).

## Data source note

The shared `Common/Files/QuantBeast/Tester/{Signal,Order,Trade}Journal.csv`
files did not grow across any of these four runs despite real trades
occurring (confirmed via `wc -c` before/after) -- a pre-existing file-write
issue under this session's rapid back-to-back Tester invocations, consistent
with the previously-documented (2026-07-18/19, never fully resolved)
journal-lock defect; `TEST 35` failed on every run in this batch for the
same reason. Worked around at the time by parsing trade-level detail
directly from the Tester Agent's own text log
(`Tester/Agent-127.0.0.1-3000/logs/20260724.log`), which reliably records
every `SHADOW:` open and `SHADOW CLOSED:` line via a separate, unaffected
logging path.

**Resolved 2026-07-25, DECISION_LOG.md D019**: root cause was shared-filename
collision under rapid successive Tester runs (`error=5004`, confirmed 332
occurrences that day). Fixed with per-run auto-generated unique journal
filenames (TEST 109) -- confirmed via a real back-to-back integration test
that both the collision and `TPOutcomeJournal.csv`'s near-constant failures
are gone, and that genuine CSV persistence now works. All Tier C runs (and
any future Tier B/A reruns) use the fixed build and therefore have real,
byte-exact CSV evidence available -- text-log parsing is retained only as a
secondary audit cross-check per the user's instruction, not the primary
source going forward.

## Results

| Window | Model | Ticks | Bars | Trades | Price-jump blocks | Data-quality blocks | Risk-engine rejects |
|---|---|---|---|---|---|---|---|
| B1 (2026.07.06-07.08) | 4 (real) | 648,050 | 552 | 1 | 4 | 7 | 22 |
| B1 (2026.07.06-07.08) | 1 (generated) | 11,040 | 552 | 0 | 974 | 73 | 0 |
| B2 (2026.07.13-07.15) | 4 (real) | 795,342 | 552 | 2 | 16 | 54 | 14 |
| B2 (2026.07.13-07.15) | 1 (generated) | 11,024 | 552 | 0 | 978 | 232 | 0 |

**B1 Model=4 trade**: FBO BUY entry=4163.28 sl=4156.79 tp=4178.56, net=-6.92,
`EXIT_STOP_LOSS`. Then `InpMaxConsecLosses=1` correctly blocked further
entries for the rest of both days.

**B2 Model=4 trades**: MR BUY entry=4057.29 sl=4050.30 tp=4070.76, net=+13.20,
`EXIT_TARGET_HIT`. FBO BUY entry=4076.66 sl=4067.63 tp=4090.20, net=-9.37,
`EXIT_STOP_LOSS`.

**Both Model=1 runs**: zero trades, zero risk-engine-level rejections --
essentially every candidate bar was blocked at the *preflight* stage before
strategy/arbitration/risk logic ever ran.

## Interpretation

Model=1's "every tick generation" produces ~59-72x fewer ticks than the real
feed for the identical calendar window (11,024-11,040 vs 648,050-795,342),
consistent with coarse interpolation from M1 bars rather than genuine
market microstructure. This manifests as frequent large synthetic price
jumps between generated ticks, which the EA's own `InpMaxPriceJumpPoints`/
data-quality preflight gates -- correctly, by design -- reject as suspicious.
In both windows this gate alone fired far more often than there were bars
(974 and 978 times against only 552 bars each), completely dominating the
run and leaving nothing for strategy/arbitration/risk logic to ever
evaluate. Trade-level comparison against Model=4 is not just weaker under
Model=1, it is impossible -- there are no Model=1 trades to compare.

This is not "Model=1 finds less edge than Model=4." It is "Model=1's own
tick-generation artifact gets filtered out by a legitimate, unrelated
safety gate before the question of edge is ever reached." Aggregate
net-profit similarity was never even reachable to check.

## Verdict

**`MODEL1_PROXY_UNRELIABLE`**

Per the sprint's own instruction ("do not assume Model=1 is a usable proxy
merely because aggregate net profit is similar" / "Before trusting broad
Model=1 results, run the bridge"), this result means **Tier A's originally-
scoped broad Model=1 structural screen across the 2019-2024 windows should
not proceed as designed** -- it would not measure strategy structural edge,
it would overwhelmingly measure how often `InpMaxPriceJumpPoints` rejects
Model=1's own synthetic noise, which is a property of the tick-generation
method, not of QuantBeast's strategies. Reported back to the user for a
scope decision rather than silently proceeding or silently abandoning Tier
A.
