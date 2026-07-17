# QuantBeast Agent Instructions

## Working directory

This file and the entire project tree live at:

```text
~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5
```

This is the **one true working tree**. All edits, compiles, and tests
always happen here. A second clone of this repository must never be
used in parallel — doing so caused the 2026-07-16 hash-drift incident
where commits from two different working copies diverged silently.
Always verify you are in this exact directory before touching any file.

The `origin` remote (forge.mql5.io/matious/mql5) was removed on
2026-07-16. It was an unused MQL5 Algo Forge skeleton with a single
"Initial commit" and an unrelated git history. The only active remote
is `github` (iruntvmgmt/mql5-projects). Do not re-add `origin` or any
other remote without explicit instruction.

## Scope

This file exists to govern work on the QuantBeast project only.

Unless the user explicitly expands scope, agents may edit only:

- `MQL5/Experts/QuantBeast/**`
- `MQL5/Include/QuantBeast/**`
- This `MQL5/AGENTS.md`

Do not modify, rename, move, compile over, delete, or reformat unrelated indicators, Expert Advisors, profiles, presets, logs, or MetaTrader installation files.

## Project status

QuantBeast is an incomplete framework and is **not approved for live trading**. Source presence is not proof of correct behavior. `Experts/QuantBeast/BUILD_AUDIT.md` and `BUG_AUDIT.md` preserve the generated-code baseline; the current repaired-state verdict is in `Experts/QuantBeast/REPAIR_AUDIT_20260715.md`.

The living task state is in `Experts/QuantBeast/HANDOFF.md`. Read it before every task and update it after every task that changes source, configuration, documentation, test evidence, or project status.

## Required reading order

Before changing code, read these files in order:

1. `Experts/QuantBeast/HANDOFF.md`
2. `Experts/QuantBeast/PROJECT_MISSION_AND_AUDIT_CONTEXT.md`
3. `Experts/QuantBeast/README.md`
4. `Experts/QuantBeast/ARCHITECTURE.md`
5. `Experts/QuantBeast/KNOWN_LIMITATIONS.md`
6. `Experts/QuantBeast/BUILD_AUDIT.md`
7. `Experts/QuantBeast/REPAIR_AUDIT_20260715.md`
8. The document relevant to the task:
   - `CONFIGURATION_GUIDE.md`
   - `STRATEGY_SPEC.md`
   - `RISK_SPEC.md`
   - `TESTING_GUIDE.md`
   - `LIVE_DEPLOYMENT_CHECKLIST.md`

The original requirements are in `/Users/matt/Downloads/XAUUSD Quant Beast EA.docx`. If implementation and documentation disagree, report the discrepancy rather than silently choosing one.

## Safety rules

- Never enable Conservative Live or Challenge Live on a real account.
- Never change `InpAcknowledgeChallengeRisk` to `true` in a delivered default or preset.
- Never weaken spread, stop, margin, drawdown, equity-floor, ownership, or kill-switch controls merely to generate trades.
- Never add martingale, averaging down, unlimited grid behavior, loss-recovery sizing, hidden-stop-only trading, or unbounded retries.
- Never transmit orders as part of compilation, static analysis, or ordinary testing.
- Strategy Tester execution must use tester configuration and must not attach the EA to a live chart.
- Treat broker positions and orders as external state. Do not cancel, close, or modify them without explicit user authorization.
- Preserve the default safe operating mode as Shadow unless the user explicitly approves another default after validation.

## Change discipline

Work in small defect groups. One defect group should have one clearly stated purpose and one verification result.

For each group:

1. Reproduce or demonstrate the problem with exact file/line evidence.
2. Classify severity: Critical, High, Medium, Low, or Documentation.
3. Identify affected runtime paths and safety implications.
4. Make the smallest coherent fix.
5. Compile immediately when compilation is available.
6. Run the narrowest relevant deterministic test.
7. Inspect the diff and ensure unrelated behavior was not changed.
8. Update `HANDOFF.md` with files, evidence, results, and remaining work.
9. Update specification documents when behavior or supported configuration changes.

Do not combine bug repair, strategy redesign, parameter optimization, and performance tuning in one change.

## Source-editing rules

- Preserve user changes and unrelated dirty files.
- Prefer focused patches; avoid whole-file rewrites unless required and explained.
- Do not create duplicate implementations to bypass a broken component.
- Remove or explicitly reject unsupported configuration paths; do not silently fall back to another behavior.
- Keep strategies isolated from `CTrade`, `OrderSend`, position modification, and final sizing.
- Keep broker transmission centralized in the execution layer.
- Keep position management independent of signal generation.
- Use confirmed data only; document bar indexes and array-series direction for market-data logic.
- Use correct MQL5 ticket, price, volume, enum, and retcode types.
- Normalize price and volume through broker-aware helpers.
- Validate ownership before modifying any order or position.
- Bound arrays, histories, retries, journal growth, and loops.
- Do not suppress compiler warnings without resolving their cause.

## Documentation contract

The original specification requires nine technical project documents. QuantBeast also has a mandatory mission/audit-context document that governs interpretation of those technical documents:

- `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`
- `README.md`
- `ARCHITECTURE.md`
- `CONFIGURATION_GUIDE.md`
- `STRATEGY_SPEC.md`
- `RISK_SPEC.md`
- `TESTING_GUIDE.md`
- `LIVE_DEPLOYMENT_CHECKLIST.md`
- `KNOWN_LIMITATIONS.md`
- `BUILD_AUDIT.md`

When code changes behavior:

- Update the relevant specification document.
- Update `KNOWN_LIMITATIONS.md` if a limitation is added, changed, or removed.
- Update `BUILD_AUDIT.md` only when evidence changes the status.
- Update `README.md` only for user-facing status or workflow changes.
- Never mark an item complete solely because code was written. Require compile and test evidence.

## Bug-audit protocol

The bug audit is a read-only phase unless the user explicitly asks for fixes in the same task.

Audit in this order:

1. Compile blockers and MQL5 API/type misuse
2. Order ownership and destructive-action safety
3. Unprotected-fill and stop-management safety
4. Risk sizing and account-lock enforcement
5. Transaction lifecycle and position tracking
6. Persistence, restart, and reconciliation
7. Future leakage, indexing, cache, and feature correctness
8. Strategy eligibility, triggers, stops, and targets
9. Arbitration, cooldown, duplicates, and exposure
10. Shadow simulation, journals, performance, and `OnTester`
11. Dashboard, alerts, presets, and inactive inputs
12. Performance, bounded storage, and maintainability

Report each defect with severity, evidence, consequence, reproduction or reasoning, and recommended fix. Separate confirmed defects from suspected risks requiring runtime evidence.

The completed audit must use the output structure required by `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`, including architecture, per-strategy, regime, arbitration, risk, execution, persistence/recovery, test-evidence, known-limitations, and final-readiness sections. Finish with exactly one readiness class:

```text
NOT SAFE TO TEST
READY FOR DIAGNOSTIC MODE
READY FOR SHADOW MODE
READY FOR CONSERVATIVE MICRO-LIVE
READY FOR CHALLENGE-MODE RESEARCH
READY FOR CHALLENGE LIVE
```

The aggressive-growth mission is a design requirement, not permission to weaken safety or assume profitability. Preserve separate strategy engines and Challenge Mode while auditing whether they are mathematically meaningful, reachable, deterministic, bounded, and testable.

## Compilation contract

Target source:

```text
C:\Program Files\MetaTrader 5\MQL5\Experts\QuantBeast\QuantBeastEA.mq5
```

Expected macOS/Wine environment:

```text
WINEPREFIX=/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5
WINE=/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine
METAEDITOR=C:\Program Files\MetaTrader 5\metaeditor64.exe
```

Compilation acceptance requires:

- Zero errors
- Zero warnings
- A newly generated `QuantBeastEA.ex5`
- A compile log tied to the current source timestamp/hash

Do not claim compilation from an old `.ex5` or stale log. If MetaEditor is unavailable or automation is unreliable, record compilation as blocked/unknown.

### Known MetaEditor compilation issue (2026-07-16)

The direct `wine metaeditor64.exe /compile:"<path>"` invocation can
silently stop working without any error, log, or `.ex5` update — the
process exits cleanly with code 0 but does nothing. This was confirmed
against a built-in MetaQuotes example script (not just QuantBeast
code). The working pattern is to use `wine start /Unix` with a relative
path from the MT5 installation directory:

```bash
cd "$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
"$WINE" start /Unix metaeditor64.exe /compile:"MQL5\\Scripts\\ScriptName.mq5" /log
```

The compile result still appears in `logs/metaeditor.log`.

If compilation produces no log entry and no `.ex5` when using the
direct invocation, switch to the `wine start /Unix` pattern before
assuming the source has errors.

## Test contract

Follow `TESTING_GUIDE.md`. Preserve evidence under `Experts/QuantBeast/TestEvidence/` when testing begins.

- Diagnostic mode must send no orders.
- Shadow mode must send no broker orders.
- Tester runs must have unique, verified configuration, dates, and output evidence.
- Do not accept cached tester output as a new run.
- Record symbol specification, deposit, leverage, model, dates, inputs, trade count, drawdown, and log/report paths.
- A profitable result does not override safety, correctness, or holdout failures.

## Handoff requirements

Before ending a source-changing task, update `Experts/QuantBeast/HANDOFF.md` with:

- Current phase and verdict
- Exact files changed
- Defects fixed and still open
- Compile command/result and warning count
- Tests run and evidence paths
- Assumptions and blockers
- Exact recommended next action
- Any instructions for the next agent

Do not erase prior worklog entries. Add a dated entry and keep the current-state sections concise.

Every HANDOFF.md worklog entry must be paired with a git commit whose
one-line summary matches the entry title, so the hash recorded in
HANDOFF.md and `git log` always agree.

## Session scope

`HANDOFF.md`'s "Next task" list may contain multiple open items. Treat that
list as sequential, not parallel: pick exactly one item per session, state
which one and why before starting, and complete its full loop (evidence →
compile → test → HANDOFF.md entry) before touching a different item — even
if the other item looks unrelated or quick. If a session ends with an item
incomplete, say so explicitly in the worklog entry rather than leaving it
ambiguous which item is "in progress."

This applies across agents and tools, not just within one session: if you
are picking up work from a different agent/tool that hit a limit or stopped
mid-item, resume that same item first rather than starting a new one from
the list.

## Completion standard

The project is complete only when every applicable item in `LIVE_DEPLOYMENT_CHECKLIST.md` has evidence, the build is zero-error/zero-warning, required tests pass, restart recovery is demonstrated, all live positions are protected and tracked, and `BUILD_AUDIT.md` can honestly be changed to PASS.
