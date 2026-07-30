# D031 Known Limitations

1. **Not compiled in this session.** `mcp__mt5-bridge__compile_mql5` failed
   to produce a compiler-log update across four consecutive attempts,
   including against `Tests/MultiSpeedZigZag/Test_MSZZ_CandidateHandoff.mq5`
   (a file the log shows compiled cleanly at 14:59:31 the same day) --
   `mt5_status` shows no MT5/MetaEditor process running and the bridge
   port unreachable, consistent with an environment/display issue under
   Wine rather than a code defect. Mitigated by:
   - a manual, field-by-field cross-check of every `Evaluate()`/`Emit()`
     call site against its actual declared signature (all match);
   - a brace/paren balance check on every new file (all balanced);
   - removing the one real risk found (`DBL_MAX`, not used anywhere else
     in this codebase) in favor of a self-seeding min/max pattern;
   - independently verifying ID uniqueness/non-collision via `grep`+Python
     rather than relying on the compiler to catch a collision;
   - one real logic bug WAS found this way, by hand-tracing the
     Range Rotation test fixture: `Evaluate()` computed `range_high`/
     `range_low` from a window that already included the current bar,
     making the breakout-arm check (`bar.high>range_high`) structurally
     unsatisfiable (a bar that sets a new high always ties, never exceeds,
     a range_high computed including itself). Fixed by moving `PushWindow()`
     to the end of `Evaluate()`, so range stats reflect only prior bars --
     see the comment left in `RangeRotation.mqh` at the fix site.
   **This is a real gap.** `Test_MSZZ_D031_SixFamilies.mq5` must be
   compiled and run, and the existing `Tests/MultiSpeedZigZag/*.mq5` suite
   re-run, before D032 begins.
2. **No backtest-based P4 candidate-stream parity check.** Requires the
   same compile bridge. Static audit only (`shadow_safety_audit.md`) --
   proves the new code path cannot reach execution by construction and
   confirms the wiring is behind a default-`false` flag, but does not
   prove bar-for-bar output identity via an actual run.
3. **"Existing 29-suite regression remains green"**: not run, same
   blocker. `Tests/MultiSpeedZigZag/` contains the existing suite; none of
   its files were modified by D031.
4. **Range Rotation's "lack of an accepted medium-structure breakout"**
   gate is a live per-bar check (`!m.bullish_break && !m.bearish_break`
   on the current bar only), not a full-window history scan. Documented
   simplification, not a scan over all 48 window bars for a break that
   might have occurred and since rolled out of the window.
5. **Trend Pullback's VWAP** is day-anchored (resets at broker calendar-day
   boundary), not session-anchored. The handoff's Family 5 section doesn't
   specify which; day-anchoring was chosen as the simpler, more standard
   convention and should be treated as part of the frozen canonical
   definition (`MSZZ_TP_CANONICAL_VARIANT_ID = "TP-CANON-1"`), not
   changed without a new variant ID.
6. **Compression Breakout (Research)'s ATR-ratio threshold (0.80)**
   deliberately reuses `RegimeClassifier.mqh`'s own
   `MSZZ_REGIME_VOL_CONTRACT_MAX` constant value rather than an
   independently chosen one, since both are describing the same
   short/long ATR contraction concept. If that classifier constant is
   ever retuned, this family's threshold will silently diverge from it
   (it is a separate `#define`, not a shared reference) -- acceptable for
   D031 (freezing before any screening), worth a comment if D032+ ever
   revisits either constant.
7. **Only a representative test subset per family** was written (canonical
   long, canonical short, one missing-prerequisite case, one stale/expiry
   case; boundary-condition and duplicate-suppression coverage is
   concentrated in the shared factory tests plus Momentum Continuation's
   retracement-fraction path, not repeated identically across all six).
   Full 1:1 coverage of the handoff's 11-item per-family test list across
   all six families was not completed in this pass.
