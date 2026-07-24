# Phase 0 -- bounded `/config` terminal-startup diagnostic

**Question:** can `terminal64.exe /config:"<file.ini>"` reliably auto-attach an EA
to a chart on this Wine/macOS install, as an alternative to manual GUI attach?

**Target:** fully disposable, non-QuantBeast -- the stock example
`Examples\Moving Average\Moving Average.ex5` on `EURUSD,M1`, via a throwaway
config file at `MQL5\Profiles\QuantBeast_Deploy_Diagnostics\phase0_config_test.ini`:

```ini
[Startup]
Symbol=EURUSD
Period=M1
Expert=Examples\Moving Average\Moving Average
ExpertParameters=
```

Chosen deliberately outside QuantBeast's own scope so the experiment could not
affect QuantBeast's real config/state, and run only while confirmed flat
(0 positions, 0 orders) with QuantBeastEA already manually detached from every
chart.

## Attempt 1 -- `wine start /Unix` wrapper (the pattern proven for metaeditor64.exe)

```bash
cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
"$WINE" start /Unix terminal64.exe /config:"MQL5\Profiles\QuantBeast_Deploy_Diagnostics\phase0_config_test.ini"
```

Baseline before: `Logs/20260724.log` at 8154 bytes, 2 charts open (`XAUUSD,H1`,
`XAUUSD,M1`), one `terminal64.exe` process (PID 97586).

Result after ~45s of polling: log grew only from unrelated MCP tool-call
records (my own `find_files_by_glob`/`create_new_file` calls being logged by
the Native MT5 MCP server) -- **zero** new chart-open or expert-load log
line. `ps aux` still showed exactly one `terminal64.exe`, same PID 97586,
same start time. No observable effect of any kind.

## Attempt 2 -- direct invocation (no `start /Unix` wrapper)

```bash
"$WINE" terminal64.exe /config:"MQL5\Profiles\QuantBeast_Deploy_Diagnostics\phase0_config_test.ini"
```

Run backgrounded with a manual 12-second bound (macOS has no `timeout(1)`).
The process printed normal Wine startup `fixme:`/`err:` noise (consistent
with a genuinely new process attempting to start, not an IPC hand-off to the
existing instance) and **exited on its own within 12 seconds** -- no hang.
After exit: still exactly one `terminal64.exe` process (same PID 97586), chart
count unchanged by this attempt, no new expert-load log line anywhere in
`Logs/20260724.log`.

## Conclusion

**Negative result, both invocation styles.** Neither `wine start /Unix
terminal64.exe /config:...` nor a direct `wine terminal64.exe /config:...`
produced any observable effect -- no second process, no new chart, no EA
attach -- while the primary terminal instance was already running. This is
consistent with (and stronger than) the one prior precedent in this project
(`HANDOFF.md:1104`, 2026-07-15), which at least opened the terminal UI without
starting what was intended; here neither attempt did even that much.

**Root-caused, not fully:** the most likely explanation is that MT5's
`/config` auto-attach is designed for a *fresh terminal launch* (no existing
instance running), and this install's single already-running instance
absorbs or ignores a second invocation's arguments via Wine's process model
rather than forwarding them via any Windows single-instance IPC mechanism.
This was not tested further (would require fully closing the primary
instance first, which is out of scope for a "bounded, non-disruptive"
diagnostic) -- if a future session wants to pursue this further, that is the
next experiment to try, but it stops being "disposable" once the primary
instance must be closed.

**Decision: fall back exactly per the original spec's own contingency** --
one manual initial template/`.set` attachment via the GUI (unchanged from
how every prior QuantBeast live/demo activation has worked), thereafter
relying on MT5's own behavior of restoring the last-attached EA state across
terminal restarts, combined with the deployment lease gate
(`QBDeploymentLeaseValid()`, `Include/QuantBeast/Core/Types.mqh` +
`Diagnostics.mqh` + `QuantBeastEA.mq5`) which works identically regardless of
*how* the EA got attached -- manual GUI or (if ever made to work) `/config`.
No further `/config` automation is attempted in this pass.

**Cleanup:** the disposable test config
(`MQL5\Profiles\QuantBeast_Deploy_Diagnostics\phase0_config_test.ini`) is left
in place as part of this evidence record rather than deleted, since it is
inert (references a stock example EA, not QuantBeast) and documents exactly
what was tried.
