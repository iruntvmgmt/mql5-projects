# Level-1 Edge Certification -- Window Selection (Stage 1b)

## CORRECTION (2026-07-24, same evening, before any certification window was run)

**Everything below this point was written on the assumption that real-tick
history was available back to 2018, based on `get_chart_history`'s
`data_available_from: 2018.04.25` field. That assumption is wrong for
real-tick (Model=4) data specifically, and the entire certification-set
selection below is invalidated as a result.**

Two real Strategy Tester probe runs (not the direct MCP tick-query endpoint,
which had already given an inconclusive empty result for both an old and a
known-good recent date -- the Tester's own internal log is the authoritative
signal) both returned the identical line:

```
Ticks   XAUUSD : real ticks begin from 2026.06.05 00:00:00, every tick generation used
```

This appeared for a request against **2019.06.03** (this document's window
C1) *and* for a request against **2026.06.01** -- a date this project's own
`RESEARCH_TRIAL_LEDGER.md` (item #25, BO BUY-side search window 2) recorded
as a confirmed real-tick Model=4 run earlier the same day. The message was
identical both times (fixed boundary, not a rolling window that shifted in
the ~2 hours between the two probes), and MT5 silently substituted
generated/synthetic ticks ("every tick generation used") rather than
failing loudly when real ticks were requested but unavailable.

**What this means:** this broker/feed's actual retained real-tick history
is only **~7 weeks deep (2026.06.05 to present)**, not back to 2018.
`data_available_from` on the bar-history endpoints describes *bar* history
(aggregated, backfilled by MetaQuotes' data service), which is unrelated to
this Coinexx-Demo account's real-tick retention window. **All 7 certification
windows (C1-C7) and the 2024 holdout below are unusable for real-tick
certification and must be discarded as originally scoped.**

**Secondary finding, not chased further here but worth flagging**: if this
boundary already sat at/near 2026.06.05 earlier today, the ledger's own
item #25 (2026.06.01-2026.06.12 BO BUY-side search) may itself have silently
mixed real ticks (06.05-06.12) with generated ticks (06.01-06.04) despite
being logged as a clean Model=4 run -- the negative BO BUY-side finding
itself is very likely still valid (0 accepted either way), but the "clean
Model=4 real-tick" characterization of that window's first 4 days should be
considered unconfirmed, not disproven.

**Real clean, real-tick calendar space, per `RESEARCH_TRIAL_LEDGER.md`
Section 4's disqualified list intersected with the 2026.06.05-present
window:**

- 2026.06.13 - 2026.06.14 (2 days)
- 2026.06.27 - 2026.06.28 (2 days)
- 2026.07.04 - 2026.07.18 (15 days)
- 2026.07.21 - present (a few days as of 2026-07-24, growing forward, but
  this period overlaps the currently-live `qb-live-20260724-05-longrun`
  deployment's own forward observation window -- a historical *backtest*
  over these dates is not the same data as that deployment's actual live
  trades, but using both as independent evidence needs to stay clearly
  separated, never pooled)

**Correction (same evening, before any real backtest data was used):** the
2026.06.13-14 and 2026.06.27-28 gaps are both pure weekends (Sat/Sun) --
confirmed via a live Tester probe against 2026.06.13 returning "0 ticks, 0
bars generated." Zero market data exists for either gap; they contribute
nothing usable. The only gap containing real trading weekdays is
2026.07.04-2026.07.18 (10 weekdays: 07.06-07.10 and 07.13-07.17). **Actual
usable clean real-tick trading days: 10, not ~19.**

**Total: ~19 fixed calendar days, of which only 10 are actual trading
weekdays, plus a few accruing forward.** This is far
short of the 12-18 month certification + 3-6 month holdout this document
originally planned, and not enough for the sprint's own predeclared gates
(>=100 holdout trades, 3+ regimes, monthly non-negativity across many
months) to be evaluated meaningfully on real-tick data at all. This is
reported to the user as a genuine infrastructure constraint requiring a
scope decision, not something patched over silently. See the conversation
for the options presented and the user's choice; a superseding window
selection (or an explicit lower-fidelity Model=1 methodology, clearly
labeled as such) will be recorded in a new dated section below once decided.

---

## Original (now superseded) selection follows

**Selected and recorded: 2026-07-24, before any Stage 3 backtest run touches
these dates.** Per the sprint's own anti-leakage rule, this list must not be
revised after seeing any result. Any change after this point requires a new,
dated addendum explaining why, not a silent edit.

Selection method: dates were chosen from `RESEARCH_TRIAL_LEDGER.md`'s
disqualified-window list (Section 4) plus real MT5 monthly-bar OHLC history
(`get_chart_history`, period=MN1, 2018-01 through 2026-07 -- attached call
log below), never from this EA's own backtest output. Regime labels
(bullish/bearish/range/high-vol/low-vol/event) are assigned from the
publicly-known macro price record for XAUUSD over this period (COVID crash,
2022 Ukraine-invasion spike, 2023 SVB banking-crisis spike, etc.) and from
mechanical inspection of the monthly OHLC closes/ranges fetched above -- not
from watching how QuantBeast itself performs in any of these windows, which
has not been run against any of them.

## Why pre-2024 data at all

`RESEARCH_TRIAL_LEDGER.md` Section 4 shows every touched window falls
between **2024.10.07 and 2026.07.20**. Nothing before 2024.10.07 has ever
been examined, tuned against, or backtested by this project in any form.
MT5's local history reports XAUUSD data availability from **2018.04.25**
(`get_chart_history` response field `data_available_from`), which is
~6.5 years of entirely untouched calendar space -- far more than the
scattered, fragmented clean gaps remaining inside 2025/2026 (the largest of
which is ~15 days, per the ledger's own "few large contiguous untouched
gaps" observation). Using this older data is the only way to get genuinely
broad, multi-regime, multi-month clean windows without threading through a
handful of single-week gaps.

## Two-tier structure (per the sprint plan)

- **Certification set**: 7 windows, 2019-2023, chosen for regime diversity,
  totaling ~17 months.
- **Final holdout**: one contiguous block, chronologically *after* every
  certification window and closer to the present, still fully untouched.
  2024 is the only calendar year with just one small disqualified slice
  (2024.10.07-2024.10.18, an untraced `.ini`-only window per the ledger) --
  the holdout below avoids it entirely.

## Certification set (2019-2023, ~17 months, all regime categories covered)

| # | Window | Symbol | Regime label | Basis |
|---|---|---|---|---|
| C1 | 2019.06.01 - 2019.08.31 | XAUUSD | Bullish trend | Monthly close 1307.73 -> 1412.14 (+8.0%), steady grind with a trade-war-driven acceleration in June-July |
| C2 | 2020.02.15 - 2020.04.15 | XAUUSD | High volatility / major event | COVID-19 crash and V-shaped recovery: Feb high 1687 -> Mar low 1451 -> Apr high 1747, the widest intramonth range in the whole 2018-2024 record |
| C3 | 2020.05.01 - 2020.07.31 | XAUUSD | Bullish trend (continuation) | Monthly close 1727.77 -> 1975.44 (+14.3%), post-crash melt-up |
| C4 | 2021.06.01 - 2021.08.31 | XAUUSD | Range / low volatility | Monthly close 1769.80 -> 1813.20 (~flat, +2.4%), choppy 1684-1919 band, no sustained directional move |
| C5 | 2022.02.01 - 2022.03.31 | XAUUSD | High volatility / major event | Russia's invasion of Ukraine: monthly high 1797 -> 2070 spike -> settling 1937, sharpest 2-month geopolitical repricing in the record |
| C6 | 2022.05.01 - 2022.08.31 | XAUUSD | Bearish trend | Monthly close 1836.80 -> 1710.85 (-6.9%) with a continued leg down into September (close 1660.15 by month-end, included as the trend's continuation), steady decline off the March 2022 high |
| C7 | 2023.02.15 - 2023.04.15 | XAUUSD | Range / low volatility + secondary event | Choppy Jan-Feb range (1824-1959) punctuated by the March 2023 SVB/Credit Suisse banking-crisis spike (monthly high 2009 vs. Feb close 1826.89), then settling back into range by mid-April |

Total certification span: **~17.3 months** (3 + 2 + 3 + 3 + 2 + 4 + 2 months,
approximately -- exact day counts above), within the sprint's 12-18 month
guideline.

## Final holdout (2024, ~5 months, fully untouched, most recent large clean block)

| Window | Symbol | Regime label | Basis |
|---|---|---|---|
| 2024.01.01 - 2024.05.31 | XAUUSD | Mixed: range into a bullish breakout event | Jan-Feb choppy (2039-2066), then a sharp March 2024 breakout to new all-time highs (close 2043.56 -> 2233.22, +9.3% in one month) continuing through April-May (-> 2326.78). Does not overlap the only 2024 disqualified slice (2024.10.07-2024.10.18). |

This is the **only** data this sprint's Level-1 verdict may treat as a true
holdout. It must stay completely unexamined -- no report, no chart, no
backtest run against it -- until every certification-set run, every
robustness test, and every reporting script is finalized and frozen, per
the sprint's explicit rule ("do not search additional windows after seeing
results merely to obtain a pass" applies equally to the holdout itself).

## Regime coverage check

- Bullish trend: C1, C3 (two independent episodes, different years)
- Bearish trend: C6
- Range / low volatility: C4, C7
- High volatility / major event: C2 (COVID crash), C5 (Ukraine invasion), C7 secondary (SVB crisis)
- Mixed / breakout event: holdout window

All 6 categories from the sprint's own requirement list are represented at
least once in the certification set alone, independent of the holdout.

## Open verification item for Stage 3 (not resolved here, not a blocker for this document)

A direct `get_chart_ticks_history`/`get_chart_history` (M5) probe against
one certification window (2019.06.03) and, as a control, against
**2026.07.20** -- a date this project has already successfully backtested
with real-tick Model=4 data (`TestEvidence/comment_parsing_fix_20260720/`,
ledger item #31) -- both returned an empty `history` array, even though
monthly-bar (MN1) data for the same 2019 window returned real OHLC values.
Since the known-good 2026.07.20 control also came back empty, this is
**inconclusive evidence of local cache state, not proof pre-2024 tick data
is unavailable** -- every prior real-tick run in this project's history was
obtained by letting the Strategy Tester itself download/cache the range on
first run (or, per this session's own established finding, a fresh
terminal/tester process may be needed), never by this direct MCP tick-query
endpoint. Confirming actual tick-level data availability for C1-C7 and the
holdout is therefore the **first action of Stage 3**, before any statistics
are computed. If any certification window turns out to have no obtainable
tick history that far back, the fallback is documented here in advance
(again, before seeing any result): substitute the *nearest available*
short clean gap identified in `RESEARCH_TRIAL_LEDGER.md` Section 4's
surrounding white space (e.g. 2026.07.04-2026.07.18, ~15 days) for that one
regime category, explicitly labeled as a shorter/weaker substitute, not a
silent swap.

## Provenance

- `get_chart_history` (period=MN1, XAUUSD, 2015-01-01 to 2026-08-01):
  returned `data_available_from: 2018.04.25 00:00:00` and 95 monthly bars
  used for the regime classification above.
- Cross-checked against `RESEARCH_TRIAL_LEDGER.md` Section 4's consolidated
  disqualified-date union -- none of C1-C7 or the holdout window overlap it.
- No QuantBeastEA backtest, self-test, or MCP trade/signal query has been
  run against any date in this document as of the time it was written.
