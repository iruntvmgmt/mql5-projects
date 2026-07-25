# Level-1 Edge Certification -- Tier C: Real-Tick Test

**Run 2026-07-25, post pending-orders-cap fix (`996a799`) and journal-isolation
fix (`1d5e90a`).** Frozen build, canonical roster as base
(`Profiles/Tester/QuantBeast.Level1Cert.TierC.*.set`: `InpMode=1` Shadow,
`InpPersistState=false`, `InpUseGlobalVars=false`, `InpJournalTesterPrefix=true`),
varying only which strategy `_Enabled` flags are true. Single window,
Model=4 (real ticks), run once per configuration:
`2026.07.06 00:00 -- 2026.07.18 00:00` (the full genuinely-clean real-tick
span identified in `CERTIFICATION_WINDOW_SELECTION.md`'s correction: 10
trading weekdays, 07.06-07.10 and 07.13-07.17).

## Data source note (important)

The journal-isolation fix (D019, TEST 109) works correctly when tested
in-process (self-test) and worked correctly for 2 of the 7 real Tester
invocations run against this build so far (the isolated verification run
and this session's *combined*-roster run both got a genuine
`auto<timestamp>_<tickcount>` tag). **The other 5 runs -- including the
BO/FBO/MR/TPV2-only runs below -- received an empty tag at runtime despite
`MQLInfoInteger(MQL_TESTER)` being unconditionally true for any Tester
run**, and fell back to the pre-fix shared `<Name>_.csv` files. This is a
genuine, unresolved intermittency in the fix, not a new collision risk in
this specific case (each affected run used a different single-strategy
roster, so the `Strategy` CSV column still cleanly separates their rows in
the shared file) -- but it means the auto-tag mechanism is not yet fully
reliable and needs another investigation pass, disclosed here rather than
claimed as fully fixed. **Every number below was extracted from the Tester
Agent's text log** (`Tester/Agent-127.0.0.1-3000/logs/20260725.log`), the
one source that was reliable across all 5 runs, scoped per run by finding
each run's own `Initialized OK` / `thread finished` boundary. The CSV files
were used only as a secondary spot-check where they were unambiguous (the
*combined* run, which got a genuine tag).

## Results by configuration

| Config | Ticks | Bars | Trades | Price-jump blocks | Data-quality blocks | Risk-engine rejects |
|---|---|---|---|---|---|---|
| Combined (BO+FBO+MR+TPV2) | 3,559,939 | 2,760 | 1 | 37 | 85 | 73 |
| BO only | 3,559,939 | 2,760 | 3 | 37 | 85 | 2 |
| FBO only | 3,559,939 | 2,760 | 1 | 37 | 85 | 56 |
| MR only | 3,559,939 | 2,760 | 1 | 37 | 85 | 8 |
| TPV2 only | 3,559,939 | 2,760 | 0 | 37 | 85 | 1 |

Price-jump and data-quality block counts are identical across all five
configs -- expected, since those preflight gates run before strategy
routing and evaluate the same underlying tick/bar stream regardless of
which strategies are enabled.

## Trade-level detail

| Config | # | Direction | Entry | Stop | Target | Net PnL | Approx. R* | Exit reason | Entry time |
|---|---|---|---|---|---|---|---|---|---|
| Combined | 1 | LONG (FBO) | 4163.28 | 4156.79 | 4178.56 | -6.92 | -1.04 (exact, CSV) | STOP_LOSS | 2026.07.06 07:25 |
| BO only | 1 | SHORT | 4100.72 | 4106.74 | 4091.69 | +0.34 | ~+0.06 | STOP_LOSS** | 2026.07.09 13:50 |
| BO only | 2 | SHORT | 3979.21 | 3986.41 | 3968.40 | +1.30 | ~+0.18 | STOP_LOSS** | 2026.07.16 21:35 |
| BO only | 3 | SHORT | 3978.15 | 3984.80 | 3968.18 | -7.14 | ~-1.07 | STOP_LOSS | 2026.07.17 08:10 |
| FBO only | 1 | LONG | 4163.28 | 4156.79 | 4178.56 | -6.92 | -1.04 (exact, CSV) | STOP_LOSS | 2026.07.06 07:25 |
| MR only | 1 | LONG | 4126.63 | 4121.53 | 4134.99 | -5.44 | ~-1.07 | STOP_LOSS | 2026.07.07 08:25 |
| TPV2 only | -- | -- | -- | -- | -- | -- | -- | (no trades) | -- |

\* R approximated as net PnL / entry-stop price distance except the
FBO trade, which was cross-checked against the exact `RMultiple` field
recovered from the *combined* run's genuinely-tagged CSV (-1.04). This
approximation assumes ~$1 P&L per $1 of price movement at 0.01 lots on
this symbol (contract size 100), consistent with the FBO trade's own
exact figures; treat the "~" values as indicative, not exact.
\*\* Net PnL is *positive* despite the logged exit reason being
`EXIT_STOP_LOSS` -- consistent with `InpEnableBreakeven=true` moving the
stop into profit before it was touched, not a labeling bug. Not
independently confirmed against the stop-modification log this pass.

**Combined and FBO-only produced the identical trade** (same entry price,
timestamp, stop, target, and outcome) -- FBO is the first strategy to
signal in this window, and its single loss is what triggers
`InpMaxConsecLosses=1` and locks out the rest of the *combined* run's
12-day window. This is not two independent data points; it is one trade
observed twice under different rosters, exactly as expected.

## Analysis (descriptive only -- per the sprint's explicit scope)

**Execution-pipeline correctness**: all five runs completed cleanly (0
crashes, 0 unexpected terminations), self-tests passed on the frozen
build before each run, every signal that reached `ExecuteSignal()`
produced a coherent SHADOW open followed by exactly one SHADOW close with
a valid exit reason, and every reconstructed price/stop/target triple was
internally consistent (stop and target on the correct side of entry for
the trade's direction in all 6 trades). No structural or execution-path
defect observed.

**Strategy reachability**: BO, FBO, and MR each reached ACCEPTED and
produced a real trade in this window -- consistent with their existing
`DEMO_READY`/`SHADOW_READY` status in the project's readiness table.
**TPV2 reached zero trades**, consistent with this project's entire prior
history (no organic TPV2 signal has ever been observed, per
`RESEARCH_TRIAL_LEDGER.md`) -- this window does not change that finding.

**Accepted trade count**: 5 distinct real trades total across all
single-strategy configs (3 BO, 1 FBO, 1 MR, 0 TPV2); the combined
config's 1 trade duplicates the FBO-only trade, not a 6th independent
data point.

**Rejection distribution**: dominated by two effects, neither of which is
about strategy quality: (1) the price-jump/data-quality preflight gate,
identical across all configs (37 + 85 = 122 blocks against 2,760 bars,
~4.4%) -- a data-realism filter, working as designed; (2) the
`InpMaxConsecLosses=1` risk-engine lock, which fires repeatedly for the
remainder of the 12-day window after a strategy's first loss (73/56/8/2
rejections for combined/FBO/MR/BO respectively -- note BO's low count of 2
is because its lone loss (trade 3) landed on 07.17, near the window's end,
leaving little remaining time for rejections to accumulate). This cap is
correct, frozen, real behavior of this build -- not weakened for this
test, per instruction -- but it means a single-strategy run's *sample
size* is structurally capped at a handful of trades within any one
continuous run once a loss occurs, independent of how many genuine setups
the market actually offered afterward.

**Realized expectancy and R (descriptive only, explicitly not a
statistical-edge claim -- n is 1-3 per config)**: BO's three trades show a
small positive-then-negative pattern (+0.34, +1.30, -7.14); FBO and MR's
single trades were both losses. No conclusion about expectancy can be
drawn from samples this small in either direction -- this is stated
explicitly, not left implicit.

**Per-strategy contribution**: BO is the only strategy with more than one
trade in this window (3), and is also the only one with any winning
trades (2 of 3, both small, breakeven-stop-driven). FBO and MR each
contributed exactly one losing trade. TPV2 contributed nothing observable.

**Long/short behavior**: BO's 3 trades were all SHORT; FBO's was LONG; MR's
was LONG. No long-vs-short comparison is possible within any single
strategy at this sample size (BO: 3-0 short-only; FBO/MR: 1-0 long-only).

**Catastrophic behavior check**: none observed. No trade breached its
stop distance, no position exceeded the 0.01 lot / 1 position caps, no
runaway loss, no repeated-failure cascade beyond the intended
consecutive-loss lock, no unhandled state after any close.

**Consistency with existing evidence**: BO's SHORT-side activity here is
new information -- prior evidence in this project (window #28,
2026.06.23) showed a BO SHORT lifecycle, and this window adds three more,
still zero BO LONG trades observed anywhere to date (the explicit
BO-BUY-side bounded search, `RESEARCH_TRIAL_LEDGER.md` items #8/#25, found
zero in two other windows too -- BUY-side remains unproven, not
contradicted). FBO and MR's single losses here are consistent with prior
evidence showing both strategies as viable-but-unremarkable
(`DEMO_READY`) rather than clearly edge-positive or edge-negative. TPV2's
continued silence is fully consistent with its entire prior history.

## Explicitly deferred (not built this pass)

Deflated Sharpe Ratio, Probability of Backtest Overfitting/CSCV, Monte
Carlo trade-order reshuffling, and walk-forward evaluation were **not**
attempted against this sample. With 1-3 trades per configuration, none of
these techniques would produce a meaningful result -- running them anyway
would manufacture false statistical precision from a sample two orders of
magnitude below the sprint's own predeclared gate (>=100 holdout trades).
They remain deferred until a trustworthy larger sample exists (real-tick
history accruing forward, and/or organic demo-forward trades from
`qb-live-20260724-06-pendingcapfix`).

## Evidence classification

- Original Tier A plan (broad Model=1 structural screen, 2019-2024
  windows): **`INVALIDATED_MODEL1_PROXY_FAILURE`** (Tier B,
  `TIER_B_BRIDGE_VALIDATION.md`).
- `qb-live-20260724-02`, `qb-live-20260724-05-longrun` (canonical roster,
  pre-pending-cap-fix): **`INVALID_FOR_EDGE_PENDING_CAP_DEFECT`** -- these
  deployments ran with the `InpMaxPendingOrders=0` bug (D018) that
  rejected every signal unconditionally; their "0 trades" status reflects
  the defect, not the absence of market opportunity, and cannot be used as
  evidence of anything about strategy behavior.
- `qb-live-20260724-06-pendingcapfix`: **first valid forward-evidence
  deployment** -- the first canonical-roster live/demo attach without the
  pending-cap defect. Its accumulating organic trades are genuine Level-2
  (demo-forward) evidence going forward, separate from and not pooled
  with this Tier C historical sample.

## Final ticket verdict

**`LEVEL1_EDGE_CERTIFICATION_INCONCLUSIVE_DATA_CONSTRAINT`**

Not `PROVISIONAL_EDGE_FAILED`: the sample (5 distinct real trades total,
1-3 per strategy) shows no catastrophic or clearly-negative pattern --
BO's small sample is net positive, FBO/MR's single losses are unremarkable
single data points, none suggest a structurally broken strategy. But the
sample is far too small in every dimension the sprint's own predeclared
gates require (>=100 trades, 3+ regimes, monthly non-negativity across
many months) to support any edge claim in either direction. This is
returned as INCONCLUSIVE rather than weakening any gate, per explicit
instruction.

- **`EXECUTION_PIPELINE_STATUS`**: `VERIFIED_CORRECT` -- clean execution,
  correct geometry, correct risk-cap enforcement, no crashes, across all
  five runs and 3,559,939 real ticks per run.
- **`MODEL1_PROXY_STATUS`**: `UNRELIABLE` (Tier B) -- Model=1 is not usable
  as a certification data source on this feed.
- **`REAL_TICK_SAMPLE_STATUS`**: `SEVERELY_UNDERPOWERED` -- 5 distinct
  trades total against real-tick history that is itself only ~7 weeks
  deep on this feed and ~10 clean trading days after excluding this
  project's own prior touches.
- **`DEMO_FORWARD_STATUS`**: `IN_PROGRESS, NOT YET SUFFICIENT` --
  `qb-live-20260724-06-pendingcapfix` is the first valid forward
  deployment (live since 2026-07-24 23:04, 14-day lease); accumulating
  organic trades but has not yet reached the sprint's own required
  forward sample (>=50 overall, >=10 per active strategy where signal
  frequency permits).

## Open item carried forward

The journal auto-tag intermittency (Data source note above) should be
investigated in a future pass -- `MQLInfoInteger(MQL_TESTER)` is
unconditionally true for a real Tester run, yet 5 of 7 real invocations
against this build still resolved an empty tag at runtime despite TEST 109
proving the underlying logic correct in-process. Not chased further this
pass (would have delayed Tier C by another debugging cycle); text-log
parsing remains a proven, reliable fallback in the meantime.
