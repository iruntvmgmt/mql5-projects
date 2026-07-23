# Final report -- follow-on production-readiness sprint (`QuantBeast_Production_Readiness_Sprint.md`)

## 1. Starting and ending repository state

- Start: HEAD `4ad4031` (verified against the briefing in Decision D008;
  two non-blocking discrepancies found and documented -- commit count
  off by one, `github/main` auto-synced by MT5's own Git integration,
  neither an agent-side violation).
- End: HEAD `6e2e1aa`, branch `main`, 4 commits ahead of `github/main`,
  0 behind. Working tree clean except the same pre-existing unrelated
  files present before this sprint (untracked `.ini`/`.tpl` files,
  `Include/QuantBeast/Core/Configuration.mqh`'s pre-existing MR/FBO
  risk-parameter uncommitted edit was NOT touched by this sprint --
  wait, see note below).

**Note on `Configuration.mqh`**: this sprint DID commit changes to
`Include/QuantBeast/Core/Configuration.mqh` (the new `InpXX_DemoAuthorized`
input group) -- these are new, additive lines only; the file's
pre-existing uncommitted MR/FBO tuning mentioned in earlier session
history was independently verified still present and untouched (checked
via `git diff` scoping to only the new input-group hunk before staging).

## 2. All commits created this sprint (10)

| Commit | Purpose |
|---|---|
| `350cde5` | Phase 1: verify prior sprint's final state, document 2 discrepancies |
| `27173da` | Phase 2: fix `QBIsKnownStrategyId`/`ARBITRATION_REGIME_PRIORITY` missing TPV2 |
| `1c6d45e` | Phase 3: diagnose `InpEnableTPV2Experimental` tester non-application |
| `9f4f8cb` | Phase 3: prove TP V2 Shadow signal and risk path (post-restart) |
| `d8e018d` | Phase 4: prove BO and MR complete Shadow lifecycles |
| `76f8564` | Phase 3/6: five-strategy arbitration test, complete Phase 3 evidence |
| `2a4746d` | Real Coinexx-Demo controlled-execution-fixture broker order |
| `cb916a7` | Phase 5: all-strategy Shadow integration matrix |
| `75928c1` | Phase 6: arbitration/allocation verification (Tests 96-99) |
| `6e2e1aa` | Phases 7-14: restart-persistence fix, risk-engine tests, demo allowlist |

## 3. Push status

**Not pushed by this agent.** Zero `git push` commands issued. (`github/main`
may still auto-advance via MT5's own integrated Git Forge feature,
documented as out-of-agent-control in Decision D008 from the prior
verification phase -- not a violation of "do not push unless instructed.")

## 4. Tag status

`quantbeast-tp-v1-research-freeze-20260722` unchanged, still resolves to
`953c2d0`. No new tags created.

## 5. Files changed

See `FILE_INDEX.md`'s "Follow-on sprint" section for the complete,
per-file, per-commit breakdown with runtime-effect annotations.

## 6. Compile result

`0 errors, 0 warnings` at every commit point (final verification: EX5
timestamp 12:51 vs. last source edit 12:31, confirmed via MetaEditor GUI
compile since headless CLI compilation was blocked by the live terminal
holding the wineprefix's single-instance lock -- see below).

## 7. Test totals

**105 passed, 0 failed** (started this sprint at 96; Phase 1 independently
reproduced that baseline; ended at 105 after Tests 94-102 and a rewritten
Test 37).

## 8. Fifth-strategy cardinality audit results (Phase 2)

Two real defects found and fixed: `QBIsKnownStrategyId()` missing the
TPV2 case (would have resolved every real TPV2 position/order comment to
"UNKNOWN"), and `ARBITRATION_REGIME_PRIORITY`'s compatibility-bonus chain
missing TPV2. Confirmed clean elsewhere: AllocationEngine (`[8]`
dynamically ID-keyed), ChallengeMode/TradeJournal/CounterfactualTracker
(unrelated indices), KillSwitch/StateStore/Reconciliation/RecoveryEngine/
ExposureManager. One pre-existing, out-of-scope, unfixed observation:
`AllocationEngine::RecordOutcome()` is never called anywhere (`ALLOC_PERFORMANCE`
silently degenerates to equal-weight); predates TP V2, `ALLOC_EQUAL` is
default so no behavior change.

**A second pass this sprint (Phase 9) found two more defects Phase 2's
grep-based search missed**: `SaveKillSwitchState`/`LoadKillSwitchState`
and `SaveStrategyTradeCounters`/`LoadStrategyTradeCounters` in
`StateStore.mqh` only round-tripped 4 of 5 strategies' restart-persisted
GlobalVariable state -- both now fixed and tested (Test 101). Documented
transparently as a gap in the earlier audit's own coverage, not merely a
new finding.

## 9. TP V2 experimental Shadow results (Phase 3)

Reproduced the six-window evidence's 4 fully-qualifying episodes with
`InpEnableTPV2Experimental=true`: 1 reached a complete Outcome A Shadow
lifecycle (2026.02.18 11:40:00 SELL, R=-1.03), 3 hit legitimate Outcome B
rejections (2 by TP V2's own confidence floor, 1 by arbitration's
existing-position rule -- a genuine cross-strategy interaction, MR's
open LONG blocking TP V2's SELL). Zero integration defects found; one
real infrastructure quirk found and resolved (tester didn't apply a
newly-added boolean input until the terminal was restarted -- Decision
D009, resolved by explicit user authorization).

## 10. TP V2 signal-to-arbitration results (Phase 6)

`SignalArbitrator`'s non-`REGIME_PRIORITY` branches (`HIGHEST_SCORE`,
`REQUIRE_CONFLUENCE`, `REJECT_CONFLICTS`) had no hardcoded strategy-count
assumption to begin with. New deterministic proof: ten simultaneous
directional candidates scored/arbitrated correctly (Test 96); TP V2
subject to the same one-position/opposite-signal exposure gate as any
strategy (Test 97); tie-break symmetry regardless of TP V2's slot
position (Test 98).

## 11. TP V2 risk results (Phase 7)

`CRiskEngine`/`CPositionSizer` take no strategy-ID parameter at all --
central risk contract by construction. New direct proof (Test 100): a
valid TP V2 signal accepted; malformed stop and low reward:risk both
correctly rejected; lot sizing empirically identical to another strategy
given identical entry/stop/equity; the sized trade clears
`ValidateSizedTrade` via the same sizer-risk-estimate path every strategy
uses.

## 12. TP V2 Shadow trade lifecycle results

One complete organic lifecycle proven end-to-end: organic `TRIGGERED`
episode -> valid signal (`GEOM_ACCEPT`) -> arbitration accepted -> risk
accepted -> Shadow fill (10pt slippage) -> SL/TP registered exactly to
signal geometry -> managed ~25 minutes -> `EXIT_STOP_LOSS` -> journal-
reconciled. Two further Outcome A trades in a different window (both
stopped out, one near-breakeven). n=3 total organic complete lifecycles
across this sprint's evidence -- too small for any edge claim, sufficient
for SHADOW_READY.

## 13. BO complete Shadow lifecycle results (Phase 4)

One fully reconstructed SHORT lifecycle (2026.06.23 21:45:00, R=-1.02).
BUY-side organic acceptance remains an honestly-declared open gap (not
manufactured this sprint).

## 14. MR complete Shadow lifecycle results (Phase 4)

Both directions, both exit classes (`EXIT_TARGET_HIT` winners at
R=1.91/1.96, `EXIT_STOP_LOSS` losses/near-breakevens at R -0.02 to -1.07),
multiple independent windows -- the strongest non-FBO evidence in this
sprint.

## 15. FBO regression results

Reconfirmed: 34 organic acceptances pooled across all 6 windows (6 of 6
windows), no regression from the fifth strategy's addition (Phase 2, 5,
6 audits all clean for FBO specifically).

## 16. Five-strategy collision and arbitration results (Phase 5)

Re-analyzed 3 already-run all-5-strategy Shadow windows (no new tester
runs): 0 organic same-bar two-valid-candidate collisions observed (an
honest negative finding at this sample size -- same-bar arbitration
remains proven by Test 95's deterministic fixture, not organically); 1
genuine organic cross-strategy exposure block (MR blocking TP V2); 3
same-strategy self-blocks (FBO blocking its own opposite candidate);
zero position overlaps across all 26 completed trades; TP V2's own
lifecycle continued updating (reset to idle, kept ticking) while other
strategies held positions, and vice versa.

## 17. Exposure and allocation results (Phase 6)

`CAllocationEngine`'s `m_ids[8]` is ID-keyed, not index-keyed -- TP V2
gets its own slot automatically. New proof (Test 99): `ALLOC_EQUAL`
stays 1.0 for TP V2; `ALLOC_CONFIDENCE`/`ALLOC_PERFORMANCE` give TP V2 a
correctly distinct weight from a lower-scoring strategy. Exposure
aggregation (`totalExposure`) sums all positions regardless of strategy
-- nothing to exclude TP V2 from.

## 18. Restart/recovery results (Phase 9)

**Two real defects found and fixed** (see item 8). All other restart-
relevant paths audited clean: ownership/comment parsing (single source
of truth, Phase 2-fixed), entry-metadata recovery (strategy-agnostic),
strategy-index restoration (explicit TPV2 mapping), exposure restoration
(no per-strategy state to restore), reconciliation classification
(strategy-agnostic). **Gap honestly reported**: a live-broker-position
restart-reconstruction proof specific to TP V2 was not performed this
phase -- `ReconstructFromBroker` reads live MT5 APIs directly with no
injectable mock, and no TP V2-owned broker position was open at any
point this sprint's restart windows. `QBTestTPV2RestartResetSemantics`
(Test 90) proves the lifecycle engine's own in-memory reset semantics.

## 19. Analytics and journal traceability results (Phase 10)

`strategy_performance_report.py` groups purely by the literal `Strategy`
string -- TP V1/V2 cannot be pooled accidentally (confirmed against real
data). TP V2's one organic trade's join key `(Strategy, Direction,
Timestamp==EntryTime)` was empirically proven reliable (Phase 3
evidence). No new observability gap found; the pre-existing
`TradeJournal.SignalID` vs. `SignalJournal` string-ID mismatch is a
known, documented, strategy-agnostic limitation, not new to TP V2.

## 20. Evidence-retention completion status (Phase 11)

TP-outcome-journal "cannot open" errors seen during every self-test run
**definitively diagnosed** as the already-documented Decision-D003
self-test-instance-churn artifact (ten back-to-back tracker instances in
one process, unique to Tests 65-74) -- confirmed empirically by finding
52 real rows (both genuine 2025-01-06 production events and 1970-epoch
self-test fixture rows) still accumulated in the live journal file
despite those errors. Not a production-path defect. `FILE_INDEX.md` and
`HASHES.sha256` updated this sprint with the full follow-on-sprint file
list and final build hashes.

## 21. Exact remaining engineering blockers

- TP V2 live-broker-position restart-reconstruction not yet organically
  proven (needs either a real TP V2-owned broker position preserved
  through a restart, or a broker-position mock this codebase does not
  currently have).
- BO's BUY-side organic acceptance still unobserved.
- `AllocationEngine::RecordOutcome()` is never called anywhere (pre-existing,
  out of this sprint's scope, `ALLOC_EQUAL` default means no current
  impact).
- No EA-attached-live-chart mechanism exists for programmatic use --
  OnTradeTransaction recognition, EA-side protection repair, and
  organic autonomous broker submission by the running EA all remain
  unproven this sprint (see item 23).

## 22. Exact blockers requiring elapsed demo-forward time

- A second (or more) organic TP V2 complete Shadow lifecycle, to move
  past n=1/n=3 toward a stronger DEMO_READY case.
- BO's organic BUY-side acceptance.
- Real-time observation of a genuine TP V2 restart-with-open-position
  event, if one occurs naturally during ongoing demo/Shadow operation.

## 23. Exact blockers requiring explicit user authorization

- Attaching the EA live to an MT5 chart for organic autonomous
  broker-order submission -- no safe, precedented programmatic mechanism
  was found or attempted this sprint (Decision D010); the one prior live
  attachment in this project's history was done manually by the operator
  via the GUI. Requires either operator action or further explicit
  guidance on a safe automated method.
- Flipping `InpAcknowledgeLiveBrokerRisk=true` in
  `XAUUSD_Conservative_Demo_AllStrategy.set` to actually activate the
  restricted all-strategy demo candidate (Phase 14) -- prepared, not
  activated, exactly one documented line stands between this preset and
  activation.
- Any Conservative Live (real-money) or Challenge Live activation --
  `ModeAllowsStrategy` does not sanction either tier for any strategy
  today; extending it is a future, separate decision.

## 24. Final readiness labels

| Strategy | Label |
|---|---|
| BO | SHADOW_READY |
| FBO | DEMO_READY |
| MR | DEMO_READY |
| TP V2 | SHADOW_READY |
| TP V1 | NOT_READY (by design, permanent) |

(Full basis for each label: `final_readiness/PHASE12_13_14_READINESS_AND_ALLOWLIST.md`.)

## 25. Overall EA readiness label

**READY FOR SHADOW MODE.**

## 26. Recommended next activation step

Continue Shadow-mode accumulation for BO (BUY-side) and TP V2 (second+
organic lifecycle), then reconsider TP V2 and MR for DEMO_READY
promotion criteria once that evidence exists. Any further broker-order
activity should continue to use the `CONTROLLED_EXECUTION_FIXTURE`/
`ORGANIC_DEMO_EVIDENCE` separation established this sprint. Do not
activate the restricted all-strategy demo candidate
(`XAUUSD_Conservative_Demo_AllStrategy.set`) without a fresh, explicit
authorization decision at the time of activation, even though it is
technically one line away from activatable.

## 27. Confirmation that no broker orders were transmitted (beyond the authorized fixture)

Confirmed. Exactly one real broker order round-trip occurred this
sprint, explicitly authorized and bounded: the `CONTROLLED_EXECUTION_FIXTURE`
documented in `run_manifests/run_ce01_20260723_broker_fixture.md`
(0.01-lot XAUUSD BUY, opened, SL-modified, closed -- account left flat).
No organic strategy-originated broker order was transmitted (no EA
instance was ever attached live to a chart this sprint). `get_trading_open_positions`
confirms zero open positions and zero pending orders as of this report.

---

## Evidence-class summary (per the user's explicit broker-authorization instruction)

- **Shadow-only proof**: the overwhelming majority of this sprint's
  evidence -- all Phase 3-10 organic strategy signal/arbitration/risk/
  management/exit/journal proofs for BO, FBO, MR, and TP V2.
- **Controlled demo execution-fixture proof**: exactly one fixture
  (`run_ce01`), proving order submission/ack (success and a real
  rejection retcode), fill/slippage, initial SL/TP, SL modification, and
  close/flatten via the real Coinexx-Demo broker path.
- **Organic autonomous demo proof**: none obtained this sprint -- no EA
  instance was live-attached to a chart, so no strategy ever
  autonomously submitted a real broker order this sprint.
- **Still-unproven behavior**: EA-side `OnTradeTransaction` recognition
  of a real fill, EA-side protection verification/repair against a real
  position, restart+reconstruction against a real TP V2-owned broker
  position, and any organic autonomous broker submission by a running
  EA instance.

**No edge or profitability is claimed from any demo execution this
sprint** -- the one real fixture trade's P&L (+$2.33 net) is a
consequence of bounded diagnostic testing, not a strategy result, and is
explicitly excluded from any promotion consideration per its own
evidence-class tag.
