# D029 Audit Remediation — Final Certification Report

Branch `feature/d029-audit-remediation`, forked from D029's final SHA
`64f2e29f20a20f3fe362e073c8873262f2183d3e`. Full narrative and per-finding
detail in `D029_AUDIT_REMEDIATION.md`; this document is the top-level
21-point certification summary. **This certification is based only on the
final, twice-patched rerun evidence in `D029_Audit_Results/`** — no
conclusion below is carried forward from D029's original report by
assumption.

## 1. Starting and final commit SHA

Starting: `64f2e29f20a20f3fe362e073c8873262f2183d3e` (D029's final SHA).
Prior checkpoint going into this report: `1ef3dec78c0b7b9366b24771188f0990b846ea68`
(Finding B fix). Final: the commit that adds this report and its
supporting evidence files (see push log after this document is committed).

## 2. Branch verification

`feature/d029-audit-remediation`, forked correctly from the above SHA
(confirmed exact match at branch creation). No merge to `main` at any
point in this pass.

## 3. Candidate-stream method and hashes

Finding A: canonical field-by-field comparison with SHA-256 hashing over
`(time, strategy_id, setup, direction, score, entry, stop, target,
origin_id, event_id, strategy_family)`, tolerances `price=1e-8`,
`score=1e-10`. Pre-rerun result: all three streams (`D29_SR0`/`SR3_PCT`/
`SR4_PCT`) byte-identical. **Final rerun result (`candidate_stream_summary_rerun.csv`):
identical again** — `all_pairwise_streams_identical=True`,
`all_canonical_hashes_equal=True`, all three variants hash to
`9f880ec104c2c30253db9e7a40559c8878d605ab5cd062f2748304d7bb25a065`
over 376 raw-candidate rows each. Confirms the ordered signal-generation
stream is unaffected by any Finding B/C/D/E patch, on the final binary.

## 4. Mismatches found

- Finding C: 1 unprotected partial per run in the pre-rerun evidence
  (`SR3_PCT`/`SR4_PCT`/`P3_SR3`/`P4_SR3`), same underlying trade — the
  atomicity check's same-bar-only design does not credit a later-bar
  retry, so this figure is unchanged after the patch and is **expected**,
  not a regression (the retry is confirmed firing via
  `MSZZ_SweepExitManagementJournal.csv`'s `PROTECTION_RETRY` rows — see
  §7-9).
- Finding B: 1 real R-computation mismatch per run in `P3_SR3`/`P4_SR3`
  (same underlying trade), found via independent deal-level
  reconciliation. **Fixed**, and the final rerun's reconciliation
  confirms 0 mismatches across all 7 variants (§5).

## 5. Deal-level / portfolio R reconciliation

Final (post-Finding-B-fix) `reconcile_deals_and_r.py` run against
`D029_Audit_Results` — **0 mismatches in all 7 variants**:

| variant | trades checked | volume mismatches | price mismatches | R mismatches | ok |
|---|---|---|---|---|---|
| D29_SR0 | 190 | 0 | 0 | 0 | True |
| D29_P3 | 341 | 0 | 0 | 0 | True |
| D29_P4 | 329 | 0 | 0 | 0 | True |
| SR3_PCT | 194 | 0 | 0 | 0 | True |
| SR4_PCT | 186 | 0 | 0 | 0 | True |
| P3_SR3 | 345 | 0 | 0 | 0 | True |
| P4_SR3 | 333 | 0 | 0 | 0 | True |

See `trade_level_r_reconciliation.csv`, `r_reconciliation_summary.csv`,
`portfolio_r_reconciliation.csv`. ("Trades checked" is slightly below
each variant's portfolio-row count because the script only reconciles
broker tickets it can resolve to both an entry and an exit deal; this is
a coverage limit of the check, not a defect — see
`D029_AUDIT_REMEDIATION.md`.)

## 6. Corrected split statistics

Finding G: exact 50.0000% / within 1pp / within 2pp / outside 2pp
breakdown, final rerun (`corrected_partial_fraction_summary_rerun.csv`):

| variant | partials | exact 50% | within 1pp | within 2pp | outside 2pp | mean fraction |
|---|---|---|---|---|---|---|
| SR3_PCT | 86 | 42 (48.84%) | 26 (30.23%) | 9 (10.47%) | 9 (10.47%) | 0.4932 |
| SR4_PCT | 82 | 36 (43.90%) | 25 (30.49%) | 9 (10.98%) | 12 (14.63%) | 0.4918 |
| P3_SR3 | 64 | 37 (57.81%) | 15 (23.44%) | 9 (14.06%) | 3 (4.69%) | 0.4955 |
| P4_SR3 | 63 | 32 (50.79%) | 16 (25.40%) | 11 (17.46%) | 4 (6.35%) | 0.4946 |

Consistent with the pre-rerun figures in shape (broker-quantized partial
fills cluster near, not exactly at, the requested 50% split — expected
given `volume_step` rounding, not a defect).

## 7. Historical protection success/failure counts

Final rerun (`partial_protection_summary_rerun.csv`):

| variant | total partials | matched protection | missing/failed | duplicate same-bar |
|---|---|---|---|---|
| SR3_PCT | 86 | 85 | 1 | 0 |
| SR4_PCT | 82 | 81 | 1 | 0 |
| P3_SR3 | 64 | 63 | 1 | 0 |
| P4_SR3 | 63 | 62 | 1 | 0 |

Identical to the pre-rerun figures — **expected**: this is the
same-bar-only atomicity check, and the state-machine patch's retry
happens on a *later* bar, so it doesn't get same-bar credit here. The
retry itself is confirmed via the journal (§8-9), and its eventual
failure is the honest, disclosed result for this one historical trade —
not a discrepancy in this check.

## 8. State-machine patch

`ENUM_MSZZ_PARTIAL_PROTECTION_STATE` + retry (max 3) + emergency-close,
wired into `MultiSpeedZigZagEA.mq5`'s `ProcessOneBookExit()`/
`ProcessPendingProtection()`. See `D029_AUDIT_REMEDIATION.md` "Finding C".
Confirmed firing on the final rerun: `MSZZ_SweepExitManagementJournal.csv`
shows an identical `PROTECTION_RETRY` event (`2025.03.25 15:30:00`,
attempt 2 of 3, `success=false`) in all 4 partial-close variants.

## 9. Retry/emergency-close policy

3 retries on subsequent closed bars; on exhaustion, `PositionClose()`
attempted; on failure, `g_recovery_required=true` (blocks new entries via
the existing D009 mechanism, extended to the multi-book path). For the
one historical trade that exercises this path, retry attempt 2 also
fails; the position closes via an unrelated broker-side trigger
(`BROKER_SL_TP_OR_TEST_END`) before a 3rd retry or emergency-close could
be attempted — see §14/CHANGED PARTIAL TRADES for the full trade-level
account.

## 10. Restart persistence

`ReconstructProtectionStateOnRestart()` implemented and unit-tested
(19 assertions), but **not reachable in the live EA** — a pre-existing,
now-documented gap: `CMSZZStrategyBook::Configure()` zeroes all book state
on every restart and nothing in the multi-book architecture rehydrates
`position_open`/`status` from broker positions afterward. **This
limitation is real, disclosed, and NOT solved** — restart-safety for the
partial-protection sub-state (and the broader book state it depends on)
remains an open production gap. Zero effect on this certification since
no rerun involved a restart.

## 11. Volume-minimum fix

Finding D: `ComputePartialSplit()` now takes `volume_min` independently of
`volume_step`. All 10 required test cases pass. No effect on any D029 run
(confirmed: `SR3_PCT`/`SR4_PCT`/`P3_SR3`/`P4_SR3` partial-fraction and
protection-count figures are unchanged pre- vs. post-rerun) — XAUUSD's
`volume_min==volume_step` on this account, so this fix is a correctness
improvement with no measurable effect on the historical evidence.

## 12. Broker-authoritative sizing

Finding E: `CalculateBrokerLossPerLot()` via `OrderCalcProfit()`. Verified
empirically (live probe on the isolated demo): zero difference from the
old formula for XAUUSD long/short. Confirmed again by the final rerun's
headline sizing/risk figures matching the pre-rerun figures exactly for
every variant except the two Finding-B-affected trades (§15).

## 13. Backward compatibility

Fixed-lot mode (`MSZZ_SIZE_FIXED_LOT`) never calls `Calculate()` — byte-
identical, unaffected by any Finding C/D/E/B change. Not exercised by any
of the 7 D029 audit configs (all use percent-equity sizing), so this is a
static-code guarantee rather than an empirical result of this pass.

## 14. Rerun decision and all reruns

Per the 7-point gate, rerun was **required** (Finding C's historical
atomicity audit found real failures, and Finding B independently found a
second, unrelated real defect). All 7 configs
(`D29_SR0, SR3_PCT, SR4_PCT, D29_P3, D29_P4, P3_SR3, P4_SR3`) were rerun —
twice: once after the Finding C/D/E architecture patch, and again after
Finding B's independent reconciliation caught and required a fix for a
second real defect (`ExportClosedPortfolioBookFromTrade()`'s R
computation). **All final numbers in this report come from the second
(final) rerun**, on the fully-patched binary. No selective reruns of
favorable variants — every variant was rerun both times regardless of
whether its own evidence showed a defect. Output in
`/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/` — original
`D029_Phase{2,3,4}_Results/` evidence never overwritten (verified: every
control-variant byte-diff investigated in §15/`D029_AUDIT_REMEDIATION.md`
was read directly from the untouched original directories).

## 15. Updated results

Headline expectancy/PF/maxDD per variant, pre-patch (original D029
evidence, untouched) vs. patched rerun (final binary), both computed
identically from `MSZZ_PortfolioTradeAnalytics.csv` (`headline_pre_post_comparison.csv`):

| variant | era | trades | win rate | expectancy R | PF(R) | total R | max DD (R) |
|---|---|---|---|---|---|---|---|
| D29_SR0 | PRE | 190 | 0.3684 | 0.1506 | 1.2688 | 28.6117 | 18.2941 |
| D29_SR0 | POST | 190 | 0.3684 | 0.1506 | 1.2688 | 28.6117 | 18.2941 |
| D29_P3 | PRE | 342 | 0.3655 | 0.1217 | 1.2218 | 41.6064 | 23.9365 |
| D29_P3 | POST | 342 | 0.3655 | 0.1217 | 1.2218 | 41.6064 | 23.9365 |
| D29_P4 | PRE | 330 | 0.3303 | 0.1443 | 1.2472 | 47.6083 | 24.2455 |
| D29_P4 | POST | 330 | 0.3303 | 0.1443 | 1.2472 | 47.6083 | 24.2455 |
| SR3_PCT | PRE | 194 | 0.4897 | 0.0807 | 1.1776 | 15.6564 | 14.9477 |
| SR3_PCT | POST | 194 | 0.4897 | 0.0807 | 1.1776 | 15.6564 | 14.9477 |
| SR4_PCT | PRE | 186 | 0.4892 | 0.0795 | 1.1752 | 14.7804 | 19.5857 |
| SR4_PCT | POST | 186 | 0.4892 | 0.0795 | 1.1752 | 14.7804 | 19.5857 |
| P3_SR3 | PRE | 347 | 0.4150 | 0.0860 | 1.1709 | 29.8514 | 20.8497 |
| P3_SR3 | POST | 347 | 0.4150 | **0.0855** | **1.1698** | **29.6655** | 20.8497 |
| P4_SR3 | PRE | 335 | 0.3791 | 0.1063 | 1.1972 | 35.6172 | 22.6597 |
| P4_SR3 | POST | 335 | 0.3791 | **0.1058** | **1.1961** | **35.4281** | 22.6597 |

Trade counts, win rates, and max drawdown are unchanged in every variant.
Only `P3_SR3`/`P4_SR3` move, and only via the one Finding B trade — see
CHANGED PARTIAL TRADES below.

## 16. Robustness windows / concentration

From `audit_portfolios_rerun.py` (final rerun):

| variant | top-1 excl. | top-3 excl. | top-5 excl. | best-quarter excl. | dev R (n) | val R (n) | hold R (n) | long R (n) | short R (n) |
|---|---|---|---|---|---|---|---|---|---|
| D29_SR0 | 26.6117 | 22.6117 | 18.6117 | 13.3449 (2025Q2) | 17.5829 (123) | 4.4695 (29) | 6.5593 (38) | 7.7530 (96) | 20.8587 (94) |
| D29_P3 | 39.6064 | 35.6064 | 31.6064 | 29.8478 (2025Q3) | 22.1910 (210) | 6.8796 (69) | 12.5358 (63) | 33.3885 (168) | 8.2179 (174) |
| D29_P4 | 44.6083 | 38.6083 | 32.6083 | 34.6803 (2025Q1) | 19.7909 (203) | 12.8796 (67) | 14.9378 (60) | 31.6050 (161) | 16.0034 (169) |
| SR3_PCT | 13.6564 | 9.6564 | 5.6564 | 4.2023 (2025Q2) | 11.4536 (126) | 0.6197 (30) | 3.5831 (38) | -0.3451 (99) | 16.0015 (95) |
| SR4_PCT | 1.3579 | -13.1990 | -20.8970 | -5.2287 (2025Q2) | 5.2991 (120) | 3.5033 (29) | 5.9780 (37) | 6.4761 (92) | 8.3043 (94) |
| P3_SR3 | 27.6655 | 23.6655 | 19.6655 | 19.2293 (2025Q2) | 19.1556 (213) | 3.1975 (70) | 7.3124 (64) | 26.2192 (171) | 3.4463 (176) |
| P4_SR3 | 32.4281 | 26.4281 | 20.4281 | 23.4976 (2026Q1) | 17.7945 (206) | 9.1789 (68) | 8.4547 (61) | 25.4709 (164) | 9.9572 (171) |

`SR4_PCT` remains top/best-quarter-concentrated (top-3-exclusion and
best-quarter-exclusion both push it negative) — a pre-existing D029
finding, unchanged by this audit's patches (byte-identical evidence, see
§15). `SR3_PCT`/`P3_SR3`/`P4_SR3` remain robust to the same exclusions
post-patch (all stay solidly positive), consistent with D029's original
conclusion for those variants.

## 17. Risk-cap / cross-family integrity

From `portfolio_integrity_audit_rerun.csv` — every variant: native/logical
trade counts consistent, no duplicate `logical_position_id` values,
strategy/family attribution consistent, risk-cap sequence intact (max
simultaneous open risk `0.25%`-`0.4997%`, all under the frozen D029
Phase-0 cap of `0.50%`). **No integrity findings for any of the 7
variants.**

## 18. Unknown exits

Exit-reason inventories (final rerun) contain only known, expected
categories in every variant: `broker position closed` (native single-book
runs), `BROKER_SL_TP_OR_TEST_END`/`OWN_FAMILY_OPPOSITE` (multi-book
runs), plus exit-management actions `PARTIAL_CLOSE`/`STOP_MODIFY`/
`PROTECTION_RETRY`/`STRUCTURAL_TRAIL` where applicable. **No `UNKNOWN` or
unrecognized exit-reason value appears in any of the 7 variants.**

## 19. Remaining production gaps

- **Restart persistence for book state** (§10) — real, unresolved, blocks
  production-safety certification. `ReconstructProtectionStateOnRestart()`
  exists and is unit-tested but is not wired to anything that runs on
  restart, because the broader book-state rehydration it would depend on
  doesn't exist either.
- Finding F's itemized production guards (max lots/order, max gross
  lots/symbol, max gross notional, max margin utilization, max slippage
  guard, stop-distance anomaly guard) — documented, not built.
- Finding C's own restart-persistence runtime tests (restart-after-
  partial-before-protection) could not be exercised for the same reason
  as §10.
- The one historical protection-retry failure (§7-9) demonstrates the
  retry mechanism *works as designed* but does not guarantee eventual
  success — a broker-side or transient failure can still exhaust all 3
  retries. This is a known, accepted limitation of a bounded-retry
  design, not a bug; production deployment would still need the
  emergency-close path's own reliability characterized further before
  being trusted unattended.

## 20. Final certification / research conclusion

Based on the full evidence above:

- **Findings A, D, E, F/G**: closed. No material effect on any of the 7
  D029 configurations; each is a genuine correctness/completeness
  improvement with an empirically confirmed null impact on this
  dataset.
- **Finding C** (partial-close/protection atomicity): the state-machine
  patch is architecturally sound, unit-tested, and confirmed firing
  correctly against real historical and live-runtime data (§8, and the
  live-runtime scenario tests against the isolated demo broker). It does
  **not** eliminate the possibility of an unrecovered protection failure
  (retries can still be exhausted) — this is disclosed, not hidden.
- **Finding B** (deal-level R reconciliation): found and fixed a second,
  independent, real defect in the ORIGINAL D029 evidence's R computation
  for own-family-opposite exits following an earlier partial close.
  Materiality was small (~-0.19R out of ~30-36R portfolio totals, under
  1%) but the defect was real and is now fixed and independently
  reconciled to 0 mismatches across all 7 variants.
- **Restart persistence**: remains a genuine, unresolved production gap.

**Certification categories** (assigned only now, with full evidence in
hand):

- `CERTIFIED_WITH_ARCHITECTURAL_PATCH` — the partial-close/protection
  atomicity architecture (Finding C) is sound and empirically verified;
  certified for continued research use with the patch applied.
- `BROKER_PARTIAL_CLOSE_RECOMMENDED_WITH_STATE_PATCH` — SweepReclaim's
  broker-side partial-close mechanism is recommended for continued
  research/development, conditioned on carrying the Finding C state
  machine and Finding B's R-computation fix forward; both are now part
  of the codebase, not optional add-ons.
- `RESEARCH_RESULT_CERTIFIED` — the underlying strategy/portfolio
  research conclusions from D029 (percent-equity sizing behaves as
  designed; `SR3_PCT`/`P3_SR3`/`P4_SR3` remain robust to top/quarter
  exclusion; `SR4_PCT` remains concentration-sensitive) are **reconfirmed
  on the patched, reconciled rerun evidence** — not preserved by
  assumption. The only numeric change from D029's original report is the
  ~0.19R-per-portfolio Finding B correction in `P3_SR3`/`P4_SR3`, which
  does not change any of D029's qualitative conclusions.
- `RESTART_RECOVERY_REMAINS_UNRESOLVED` — explicitly disclosed, not
  solved. This alone is sufficient to withhold a full production-safety
  certification.
- **`NO PRODUCTION DEPLOYMENT`** — this remains a research/paper-trading
  artifact. The restart gap, the unbuilt Finding F guard rail set, and
  the inherent possibility of retry-exhaustion on the protection path
  are all real, live risks for unattended real-money operation.

## 21. No-merge / no-live confirmation

No merge to `main`. No live deployment. All execution confined to the
isolated MT5-MSZZ-TEST instance (Coinexx-Demo 870012).

---

## PRE_PATCH RESULTS

From `D029_Phase{2,3,4}_Results/` — original, uncorrupted, never
overwritten. See §15 headline table (PRE rows) and §16/§17 (identical to
POST for every check except the two Finding-B-affected variants' R-based
metrics — original evidence was internally consistent by every check
except the one undetected Finding B defect this audit's own new
reconciliation tooling found).

## PATCHED RERUN RESULTS

From `D029_Audit_Results/` — final binary, both fixes (Finding C/D/E
architecture patch, then Finding B R-computation fix) applied, all 7
configs rerun to completion both times. See §15 headline table (POST
rows), §16 robustness/concentration, §17 integrity, §18 exit inventory.

## UNCHANGED CONTROLS

`D29_SR0`, `SR3_PCT`, `SR4_PCT`: **byte-identical** to the original
evidence, 0 diff lines in `MSZZ_PortfolioTradeAnalytics.csv` — these three
never exercise `ExportClosedPortfolioBookFromTrade()` (the function
Finding B's fix touches), so neither the instrumentation nor the fix can
affect them, and confirmed they don't.

`D29_P3`, `D29_P4`: **materially unchanged** — 5 and 6 rows respectively
differ from the original evidence, but every diffed row has
`exit_reason=OWN_FAMILY_OPPOSITE` and every diff is `exit_price`/
`realized_r` changing at the ~1e-13-relative-magnitude level (IEEE-754
last-ULP noise from the Finding B fix now computing a weighted average
even over a single exit deal, rather than passing the caller-supplied
price straight through). Headline stats for both variants are identical
to 4 decimal places pre- vs. post-fix (§15). Full row-by-row
investigation in `D029_AUDIT_REMEDIATION.md`.

## CHANGED PARTIAL TRADES

Two trades, from two different findings, both fully traced:

**1. Finding C retry trade** (`2025.03.25 15:20-15:34`, SweepReclaim
short; present in `SR3_PCT`/`SR4_PCT`/`P3_SR3`/`P4_SR3`): old outcome —
protection failed silently, no retry attempted. New: `PROTECTION_RETRY`
(attempt 2 of 3) fires identically in all four variants and also fails.
New exit outcome — **unchanged**: closes via an unrelated
`BROKER_SL_TP_OR_TEST_END` trigger before a further retry could matter.
R difference: **0**. Occupancy difference: **none**. Later
blocked/enabled entries: **none** — timing is byte-identical.
Portfolio-level cascade: **none**.

**2. Finding B R-recomputation trade** (`2026.05.28 21:35` →
`2026.05.29 01:05`, SweepReclaim short, own-family-opposite exit;
present in `P3_SR3`/`P4_SR3` only): old R `1.0433280182232252` (both
variants, computed from the remainder-close deal's price only, `4497.53`,
silently ignoring an earlier partial-close deal at `4499.19`). New R:
`P3_SR3` `0.8573135666006167` (`exit_price=4498.346393442623`),
`P4_SR3` `0.85421412300677` (`exit_price=4498.36`) — both volume-weighted
across the full deal history, both independently confirmed by
`reconcile_deals_and_r.py`. R difference: `P3_SR3` Δ≈-0.186R, `P4_SR3`
Δ≈-0.189R. Occupancy difference: **none** — only the reported price/R of
an already-closed position changed, not its timing. Later
blocked/enabled entries: **none**. Portfolio-level cascade: fully
explains both variants' total-R/expectancy/PF movement in §15; max
drawdown unaffected.

## DOWNSTREAM OCCUPANCY CASCADES

**None found.** Both confirmed affected trades leave open/close
timestamps unchanged, and MSZZ's one-owned-position-per-book occupancy
model keys strictly off those timestamps — verified directly (not
assumed) by confirming no other portfolio row differs between pre- and
post-fix evidence beyond the float-noise rows and the one real Finding B
trade, in any of the 7 variants.

## FINAL CERTIFIED CONCLUSIONS

1. Findings A/D/E/F/G: closed, empirically confirmed null effect on all
   7 D029 configurations.
2. Finding C: architecturally patched, unit-tested, confirmed firing on
   both historical replay and live-runtime broker tests; does not
   guarantee eventual protection-repair success (bounded retry can still
   exhaust) — disclosed, not solved.
3. Finding B: a second real, independent defect — found by this audit's
   own new deal-level reconciliation tooling, not by re-checking Finding
   C — fixed, and independently reconciled to 0 mismatches across all 7
   variants on the final rerun.
4. D029's original strategy/portfolio conclusions are **reconfirmed**,
   not assumed: `SR3_PCT`/`P3_SR3`/`P4_SR3` remain robust to top-N and
   best-quarter exclusion; `SR4_PCT` remains concentration-sensitive
   (unchanged, byte-identical evidence). The only numeric change
   anywhere in the 7-variant evidence set is the ~0.19R-per-portfolio
   Finding B correction in `P3_SR3`/`P4_SR3`, which does not alter any
   qualitative conclusion.
5. Restart-persistence for partial-protection (and the broader book
   state it depends on) remains a real, disclosed, unresolved production
   gap.

**Certification: `CERTIFIED_WITH_ARCHITECTURAL_PATCH` /
`BROKER_PARTIAL_CLOSE_RECOMMENDED_WITH_STATE_PATCH` /
`RESEARCH_RESULT_CERTIFIED` / `RESTART_RECOVERY_REMAINS_UNRESOLVED` /
`NO PRODUCTION DEPLOYMENT`.**
