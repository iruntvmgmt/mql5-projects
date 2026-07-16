# Restart Persistence Probe — 2026-07-15

## Purpose

Test whether QuantBeast's Terminal Global Variable state survives a true two-process boundary in the local MT5 Strategy Tester environment.

## Procedure

1. Compile `Testing/QuantBeastRestartProbe.mq5`.
2. Run phase 1 to clear state, write schema-v3 risk/Challenge/kill values, call `GlobalVariablesFlush()`, and verify the values immediately.
3. Stop `terminal64.exe`, `metatester64.exe`, and the Wine server.
4. Launch phase 2 in a new process tree and attempt to load the same values.
5. Compile the production EA after adding an explicit `GlobalVariablesFlush()` to `PersistRuntimeState()`.
6. Run the normal one-day Shadow regression.

## Results

- Probe compile: `0 errors, 0 warnings, 729 ms`.
- Phase 1: **PASS**, schema `3` was visible before process shutdown.
- Phase 2: **FAIL**, schema loaded as `0`; the cash-flow cursor and emergency kill were also absent.
- Production repair: runtime persistence now explicitly calls `GlobalVariablesFlush()` after all state groups are saved.
- Production compile: `0 errors, 0 warnings, 17621 ms`.
- Post-repair Shadow regression: `32 passed, 0 failed`; `5520 ticks`, `276 bars`; final balance unchanged at `10000.00`.

## Interpretation boundary

This result demonstrates that Terminal Global Variables created by the local Strategy Tester agent are not durable across the tested fresh agent/Wine process boundary. It does **not** prove that globals in the normal live MT5 terminal fail to persist, because Strategy Tester agents have isolated/reset terminal state.

It also is **not** a restart pass. A real terminal/VPS restart fixture using the normal terminal, with EA-owned broker positions and pending orders, remains required.

## Verdict

The probe harness behaved correctly and exposed both a test-environment boundary and a production durability omission. The explicit flush repair passed compile and regression. Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
