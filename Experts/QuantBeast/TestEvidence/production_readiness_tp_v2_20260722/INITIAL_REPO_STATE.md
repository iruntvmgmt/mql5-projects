# Initial repository state -- production_readiness_tp_v2_20260722

Captured 2026-07-22, before any change in this session.

## Branch / HEAD / sync

- Branch: `main`
- HEAD: `953c2d057ed4578b18244a1b24fab9a5c78f20e1`
- Remote: `github` (remote name in this repo, not `origin`)
- `git rev-list --left-right --count github/main...HEAD`: `0  0` (fully synced, nothing unpushed)

## Pre-existing modified tracked files (not touched by this session)

```
 M Include/QuantBeast/Core/Configuration.mqh
 M Indicators/Tradingview_Indicators/SmokeTest/obj/Debug/net8.0/SmokeTest.AssemblyInfo.cs
 M Indicators/Tradingview_Indicators/SmokeTest/obj/Debug/net8.0/SmokeTest.AssemblyInfoInputs.cache
 D Profiles/Charts/Default/chart01.chr
 M Profiles/Tester/QuantBeastEA.XAUUSD.M5.20260518_20260522.100.ini
 D Profiles/deleted/01.chr
 D Profiles/deleted/02.chr
 M Profiles/deleted/09.chr
 D Profiles/deleted/10.chr
 D Profiles/deleted/12.chr
 D Profiles/deleted/17.chr
 M Profiles/deleted/19.chr
 M experts.dat
```

`Configuration.mqh`'s modification is a pre-existing, unrelated MR/FBO
risk-parameter tuning hunk (`InpPartialCloseTriggerR`/`InpATRTrailStartR`
1.0->0.7, from an earlier session), left staged-out of every commit in
this session exactly as found.

## Pre-existing untracked files (not touched by this session)

~50 untracked `Profiles/Tester/*.ini` files (a mix of prior sessions'
research profiles across XAUUSD/BTCUSD, multiple date windows) plus
`Experts/QuantBeast/Tools/__pycache__/`. Full list captured via
`git status --porcelain` at session start; several of the untracked
`QuantBeastEA.XAUUSD.M5.*.400.ini` profiles are reused **read-only** by this
session (see `tp_v1_freeze/README.md` hash table) -- never edited or deleted.

## Safety preflight

- `get_trading_open_positions`: `positions: []`, `orders: []` (confirmed
  multiple times throughout the session, before every terminal-sensitive
  action).
- No `metatester64` process running at session start.
- MT5 terminal (`terminal64.exe`) already running; not restarted at any point
  in this session.

## Scope note

This directory tree (`production_readiness_tp_v2_20260722/`) was created by
this session and is new; everything else above predates it.
