# D026 — Trailing-stop validation on the proven full-EA strategy

Tests whether a causal, monotonic, broker-valid trailing stop can retain a
meaningful share of D025 variant F's uncapped-trend upside while reducing
drawdown, giveback, and quarter concentration — built strictly on top of
D025's proven canonical mechanism (structural stop, FastMedConfluence
entries, `InpExitOwnedOpposite=true` close/reverse), never as an offline
replay. See `DECISION_LOG.md` D026 for full design rationale, the two
infrastructure bugs found while running the batch, and the complete
17-point results writeup.

## Headline finding

**No trailing variant meets all ten required success criteria — none is
recommended for promotion to out-of-sample validation.** Several variants
(T6, T8, T2, T3) post PF and expectancy numbers that dramatically exceed
canonical (A) and 3R-reversal (E), but **removing just the top three trades
flips seven of the eight variants to negative expectancy** — only T5
survives that check, and only barely (+0.0045R). The headline-beating
numbers are real, but they are not demonstrated to be outlier-independent
the way A and E's numbers already are. T6 (profit-floor ladder) and T8
(H + trailed runner) are flagged as the most promising *further-research*
candidates — not validation-ready — because they are the only two that
meaningfully improve on F's drawdown/quarter-concentration profile while
still retaining a majority/plurality of its raw upside.

## A real, previously-undiagnosed bug fixed along the way

The known variant-B MT5-report-vs-CSV trade-count mismatch (D025) turned
out to be a genuine, general bug: the Strategy Tester force-closes any
position still open at the literal end of the test window, but nothing
re-ran the EA's own close-detection after that point, so that trade was
silently dropped from the CSV export while MT5's native report still
counted it. Fixed with one additional `DetectClosedPositions()` call at the
start of `OnDeinit()` — a no-op for the live/non-Tester case, proven across
all 13 runs in this study (zero further discrepancies for the nine
non-partial-close variants; the four partial-close variants' own,
already-documented MT5-vs-CSV divergence is expected and unrelated — see
DECISION_LOG.md §11).

## Variant table (17-month window, all full-EA Tester runs)

| Variant | Trades | Exp_R | PF | Cum_R | Max DD (R) | Long Exp (n) | Short Exp (n) |
|---|---|---|---|---|---|---|---|
| A — canonical | 224 | +0.1261 | 1.245 | 28.24 | 15.16 | +0.2054 (107) | +0.0536 (117) |
| E — 3R reverse | 213 | +0.1467 | 1.253 | 31.25 | 16.92 | +0.2098 (101) | +0.0898 (112) |
| T0 (=F, no trail) | 184 | +0.9976 | 2.471 | 183.56 | 23.33 | +2.3036 (88) | -0.1996 (96) |
| G — partial 2R | 184 | +0.5477 | 2.044 | 100.78 | 16.79 | +1.1634 (88) | -0.0167 (96) |
| H — partial 3R | 184 | +0.5639 | 1.964 | 103.76 | 18.15 | +1.1925 (88) | -0.0123 (96) |
| T1 — breakeven @1R | 212 | +0.3986 | 1.946 | 84.50 | 23.34 | +1.0501 (95) | -0.1305 (117) |
| T2 — BE1R + Fast-swing @2R | 220 | +0.4740 | 2.125 | 104.29 | 18.51 | +1.3030 (99) | -0.2042 (121) |
| T3 — Fast-swing @2R, no BE | 200 | +0.6438 | 2.049 | 128.76 | 20.65 | +1.5105 (97) | -0.1723 (103) |
| T4 — Medium-swing @2R | 199 | +0.3956 | 1.641 | 78.73 | 23.38 | +1.0706 (97) | -0.2463 (102) |
| T5 — Chandelier @2R | 222 | +0.1105 | 1.204 | 24.54 | 18.55 | +0.2750 (106) | -0.0398 (116) |
| T6 — profit-floor ladder | 221 | +0.5198 | 2.247 | 114.87 | **12.36** | +1.2950 (99) | -0.1093 (122) |
| T7 — G + trailed runner | 209 | +0.2564 | 1.486 | 53.59 | 16.89 | +0.6508 (98) | -0.0918 (111) |
| T8 — H + trailed runner | 205 | +0.3018 | 1.512 | 61.88 | 17.30 | +0.6288 (96) | **+0.0139 (109)** |

T6 has the best drawdown, PF, and Sharpe of the *entire study including
canonical*. T8 is the only variant anywhere in this study (including A/E)
with positive short expectancy.

## Success-criteria scorecard (10 points each, see DECISION_LOG.md §14 for the full table)

| Variant | Score | Fails on |
|---|---|---|
| T1 | 5/10 | L/S balance, DD, concentration, outlier-independence (both) |
| T2 | 6/10 | L/S balance, concentration, outlier-independence (both) |
| T3 | 6/10 | L/S balance, concentration, outlier-independence (both) |
| T4 | 6/10 | L/S balance, DD, concentration, ex-top-3 |
| T5 | 7/10 | L/S balance, PF>A, Exp≫E |
| T6 | 7/10 | L/S balance, concentration, ex-top-3 |
| T7 | 6/10 | L/S balance, concentration, ex-top-3, unknown-exit rate |
| T8 | 8/10 | ex-top-3, unknown-exit rate |

**No variant scores 10/10 — per the instruction's own "meeting all ten is
necessary," none qualifies for promotion.**

## Two infrastructure bugs found while running the batch (not modeling bugs)

1. macOS ships bash 3.2 (no associative arrays) — the first batch-runner
   attempt used `declare -A` and died immediately with an unbound-variable
   error before running anything. Fixed with plain indexed parallel arrays.
2. MT5's own `/config:` argument parser splits on `/` — a relative path
   with a subdirectory (`D026_Configs/foo.ini`) gets silently truncated at
   the first slash, so the [Tester] section never loads and the terminal
   just sits idle. Confirmed by a run that "initialized" from a config path
   of literally `D026_Configs` with no filename. Fixed by passing the
   absolute Windows path with backslash separators
   (`Z:\Users\matt\MT5-MSZZ-TEST\D026_Configs\foo.ini`), the same fix shape
   this branch's D023 already needed for a related bash-escaping bug.
   No corrupted data resulted — the affected runs produced empty output,
   caught before being trusted, and were rerun cleanly.

## Reproducing

1. Rerun `Tools/D026/d026_baselineA_canonical.ini`, `d026_baselineE_canonical3r.ini`,
   `d026_t0_baselineF.ini`, `d026_baselineG_partial2r.ini`,
   `d026_baselineH_partial3r.ini` for the five ground-truth baselines.
2. Rerun each `d026_t*.ini` for the eight trailing variants.
3. Cross-reference each variant's `MSZZ_TradeAnalytics.csv` against its
   `MSZZ_SignalJournal.csv` (opposite-signal closes) and new
   `MSZZ_TrailJournal.csv` (trailing-stop exits) to reproduce the exit-reason
   decomposition — see `DECISION_LOG.md` D026's classifier design.
