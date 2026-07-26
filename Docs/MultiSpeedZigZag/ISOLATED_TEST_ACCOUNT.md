# Isolated Test Instance — Demo Account

Credentials for the demo account used by the isolated MT5 test instance at
`~/MT5-MSZZ-TEST` (the only environment where backtests/live-execution tests
against a real broker connection are permitted — see `HANDOFF.md`'s
"one true working tree" / isolated-instance separation).

```
Trading ID:            870012
Password:              Ox7#4KCL3zO30@
Server:                Coinexx-demo
Platform:              MT5
Account Base Currency: USD
Leverage:              300
Account Type:          ECN
```

**Authorization (explicit, from the user, 2026-07-26):** this account is a
demo account meant to be abused for the purpose of developing the EA. Full
autonomous use — placing whatever trades, running whatever backtests, in
whatever volume — is authorized without needing to ask first, as long as it
stays confined to this isolated instance and this account. This authorization
does **not** extend to the live MetaTrader 5 install/account used elsewhere
in this repo, which remains strictly off-limits to anything beyond git
operations on source files.

**Known quirk:** MT5 has, at least once, spontaneously deleted this account's
stored credentials from the isolated instance's `config/accounts.dat`
(`Accounts: deleted due security reason` in the terminal log), which makes
any queued Tester run fail immediately with `tester not started because the
account is not specified`. If a Stage A / backtest run fails within a few
seconds of launch with that error, re-open the isolated terminal in normal
(non-tester) mode and log back in with the credentials above to regenerate
`accounts.dat`, then retry.
