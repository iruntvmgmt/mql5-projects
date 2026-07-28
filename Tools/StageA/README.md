# Edge Discovery Sprint — Stage A harness

Entry-edge screening for all 8 MSZZ strategies, canonical ATR settings
(Fast ATR14x1.0, Medium ATR14x2.0, Slow ATR14x3.5), structural stop with
1R/1.5R/2R/3R exits, XAUUSD M5, 2025.03.01-2026.07.24.

## Files

- `generate_configs.sh` — generates the 32 `.ini` files (8 strategies x 4
  RiskReward values) from a single template. Run from this directory;
  writes `stageA_<Strategy>_RR<value>.ini`.
- `stageA_*.ini` — the 32 generated Tester configs (kept in the repo so a
  regenerate isn't required to reproduce a specific run).
- `run_stageA.sh <config.ini>` — launches ONE config against the isolated
  MT5-MSZZ-TEST instance only, verifies the run actually completed (not
  just that the process exited — see "Known gotchas" below), and prints
  `ACTIVE_SANDBOX=<path>` pointing at wherever the Tester Agent actually
  wrote its output.
- `run_all_stageA.sh` — runs every `stageA_*.ini` not yet completed
  (skips configs that already have a result), retries up to 3x on a
  verification failure, copies each run's `MSZZ_TradeAnalytics.csv` /
  `MSZZ_RunSummary.csv` / `.htm` report into
  `~/MT5-MSZZ-TEST/StageA_Results/<name>/` before the next run's sandbox
  reset can overwrite them.
- `_master_trades.csv` / `_master_runsummary.csv` — the 32 runs' output
  merged (header once, rows concatenated). `_master_trades.csv` has 28
  strategy/RR combinations worth of rows; FastBreakout's 4 configs
  produced zero trades (see Known findings) and contribute nothing.

## Prerequisites

- The isolated MT5 instance at `~/MT5-MSZZ-TEST` must exist and be
  logged into its Coinexx-Demo account (credentials in
  `../MultiSpeedZigZag/ISOLATED_TEST_ACCOUNT.md`). If a run fails
  immediately with "account is not specified", the stored credentials
  were wiped — reopen the isolated terminal in normal GUI mode and log
  back in.
- Both `run_stageA.sh` and `run_all_stageA.sh` hardcode the wine binary
  path (`/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/...`)
  and `WINEPREFIX`. Adjust if the MetaTrader 5 Mac app is reinstalled
  elsewhere.
- These scripts NEVER touch the live MetaTrader 5 install — they only
  ever kill/launch processes whose command line does not contain
  "Program Files" (the live install's path signature).

## Known gotchas (discovered building this harness, D018-era)

1. **Tester Agent port can move.** The MetaTester Agent normally runs on
   `Agent-127.0.0.1-3000`, but if a prior agent process didn't tear down
   cleanly (e.g. a forceful `pkill` mid-batch), MT5 silently starts the
   next one on `-3001`, `-3002`, etc. Both scripts operate on ALL
   `Agent-*/MQL5/Files` directories that exist rather than assuming a
   fixed port — do not hardcode a port number if you modify these.
2. **A run can "look finished" without actually completing** (network
   hiccup, or the isolated terminal's own log/CSV flush taking longer
   than the polling loop's naive timeout). `run_stageA.sh` verifies
   completion by counting occurrences of `last test passed with result
   "successfully finished"` in the terminal's log BEFORE launching
   (baseline) and after (must have increased) — not just "does the
   string exist anywhere," which would trivially pass once any earlier
   run that day succeeded even if THIS run failed outright.
3. **Never trust file *existence* alone as proof of a fresh result.**
   Both scripts delete `MSZZ_TradeAnalytics.csv`/`MSZZ_RunSummary.csv`
   from every agent directory before launching, specifically so a failed
   run can't leave the PREVIOUS run's files sitting there to be
   mistaken for fresh output.
4. Sanity-check every accepted result's last trade's `close_time` lands
   in the config's `ToDate` month (`2026.07`) — a run that starts but
   gets truncated mid-simulation still produces a plausible-looking
   partial CSV.

## Known findings (Stage A baseline, D018)

FastBreakout's base score is a hardcoded literal `4.0` in
`StrategySuite.mqh`, structurally below the default `InpMinScore=5.0`.
Since Stage A isolates one strategy at a time, no cross-strategy
clustering can boost its score above threshold — it can never produce a
standalone trade under canonical settings. This is a real, reproducible
finding (confirmed across all 4 RR configs), not a harness bug.
