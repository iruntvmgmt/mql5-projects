# QuantBeast acceptance matrix

This matrix uses XAUUSD M5 real ticks from 2026-06-22 through 2026-06-23 in Shadow mode. All four current strategies are enabled. Persistence, news, dashboard, and startup self-tests are disabled; signal, counterfactual, order, and trade journals are enabled with tester-prefix routing.

| Profile | Isolated change | Purpose |
| --- | --- | --- |
| `00_Baseline` | None | Control |
| `01_NoPriceJump` | `InpMaxPriceJumpPoints=0` | Measure preflight suppression |
| `02_RelaxedStops` | Stop bounds `1..10000` points | Measure stop-distance rejection |
| `03_RelaxedLocks` | Loss/drawdown limits and consecutive-loss lock relaxed | Measure account-lock rejection |
| `04_AllRelaxed` | All three changes | Detect gate interaction and establish an upper-bound reachability control |

Only one-factor variants may be compared directly with baseline for attribution. `04_AllRelaxed` is a diagnostic upper bound, not a proposed production configuration. All profiles remain Shadow-only and do not authorize broker transmission.

The MT5 journals are append-only shared files. For valid evidence, capture the byte offsets of `SignalJournal.csv`, `CounterfactualJournal.csv`, `OrderJournal.csv`, and `TradeJournal.csv` before each run, then preserve only the newly appended suffix under this directory. A tester submission is valid only when the local tester-agent log grows and contains a matching normal footer; `job_id: 0` alone is not evidence.

## Operational baseline probe

The baseline profile completed on the local tester agent with 417,423 real ticks and 276 bars. The matching log section recorded five FBO Shadow entries, one MR Shadow entry, and two central-risk rejections for stops of 1,212 and 1,585 points against the 1,000-point maximum. It also recorded early data-quality preflight blocks and one 208-point price-jump block. The normal footer reported `OnTester result 1.491453478133252` and completion in 5:33.944.

This proves the profile and terminal path are reachable and confirms both preflight and stop-distance gates can suppress entries in the same window. Its shared journal rows are excluded from comparative evidence because an earlier incomplete attempt may have appended to the same files before offsets were captured.

An experimental per-run journal-label input compiled and passed its internal helper test but did not appear in the tester agent's effective external-input schema. It was removed rather than retained as unverified infrastructure. Restarting only the idle local tester agent did not refresh that schema and temporarily returned the MCP launcher to its documented no-run state; the main MT5 terminal was not restarted.
