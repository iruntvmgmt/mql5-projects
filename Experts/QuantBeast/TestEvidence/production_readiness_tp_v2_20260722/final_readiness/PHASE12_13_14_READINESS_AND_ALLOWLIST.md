# Phase 12 -- Readiness criteria

Using the exact required labels (MECHANICALLY_READY / SHADOW_READY /
DEMO_READY / NOT_READY):

| Strategy | Label | Basis |
|---|---|---|
| BO | **SHADOW_READY** | One organic complete Shadow lifecycle proven (`PHASE4_BO_MR_LIFECYCLE_PROOF.md`, SHORT only). BUY-side organic acceptance still an open, honestly-declared gap. Arbitration/risk/ownership/analytics all correct (Phases 6,7,10). Not yet DEMO_READY: repeated, both-direction organic acceptance is missing. |
| FBO | **DEMO_READY** (reconfirmed) | 34 organic acceptances pooled across 6 windows, both directions, richest evidence of any strategy. Fifth-strategy addition caused no regression (Phase 2/5/6 audits all clean for FBO). |
| MR | **DEMO_READY** | Both directions organically proven, both exit classes (`EXIT_TARGET_HIT` and `EXIT_STOP_LOSS`), multiple independent windows, central risk/position-management/ownership/analytics all correct. Meets every Phase 12 MR criterion explicitly. |
| TP V2 | **SHADOW_READY** | Organic `TRIGGERED` events become valid signals with the experimental gate on (Phase 3, real evidence). One complete organic Shadow trade lifecycle proven (`run_p3_03`). Arbitration/risk/ownership/recovery/analytics all recognize TP V2 correctly (Phases 2,6,7,9,10 -- including two real persistence defects found and fixed this phase). Stop/target geometry valid, no threshold tuning used. Not yet DEMO_READY: only one organic complete trade lifecycle exists (n=1); Phase 12's TP V2 DEMO_READY bar implicitly expects more than a single organic instance before broker-money promotion, matching this sprint's own "do not claim edge from n=1" discipline. |
| TP V1 | **NOT_READY** (by design) | Frozen, permanently not promoted, per protocol. |

## Overall EA readiness

**READY FOR SHADOW MODE**, unchanged from the prior sprint's conclusion --
now with a materially larger and more rigorously verified evidence base
(102 deterministic tests, two real restart-persistence defects found and
fixed, one real CONTROLLED_EXECUTION_FIXTURE broker-order proof
obtained). No strategy's readiness label regressed; MR and TP V2 both
strengthened relative to the prior sprint's conclusions.

---

# Phase 13 -- Demo allowlist architecture

## Design

Replaced the prior hardcoded FBO-only live gate (`QBLiveStrategySetAllowed`
in `QuantBeastEA.mq5`) with a general, fail-closed, six-condition
per-strategy contract, exactly as specified:

    StrategyEnabled
    AND StrategyMechanicallyReady   (code-level, QBStrategyMechanicallyReady)
    AND StrategyDemoAuthorized      (new InpXX_DemoAuthorized inputs)
    AND ModeAllowsStrategy          (QBCurrentBrokerTier)
    AND GlobalLiveRiskAcknowledged  (InpAcknowledgeLiveBrokerRisk, unchanged)
    AND BrokerPathAllowed           (classifiable account/mode combination)

**StrategyMechanicallyReady** is a code-level function
(`QBStrategyMechanicallyReady`), not an operator input, because it is a
claim about evidence completeness (this sprint's own Phase 12
conclusions), not a risk preference -- an operator cannot simply toggle a
strategy into "mechanically ready." It returns `false` permanently for TP
V1 and `true` for BO/FBO/MR/TP V2 per the Phase 12 table above.

**StrategyDemoAuthorized** is the new `InpBO_DemoAuthorized` /
`InpFBO_DemoAuthorized` / `InpMR_DemoAuthorized` / `InpTPV2_DemoAuthorized`
input group (`Configuration.mqh`). TP V1 has no such input at all --
structurally impossible to authorize, not merely defaulted off.

**ModeAllowsStrategy** is `QBCurrentBrokerTier(mode) == QB_BROKER_TIER_CONSERVATIVE_DEMO`.
This EA has no separate "Conservative Demo" `ENUM_QB_MODE` value --
`QBCurrentBrokerTier()` derives the tier from `(mode, ACCOUNT_TRADE_MODE)`:
Shadow/Diagnostic always map to the Shadow tier; `QB_MODE_CONSERVATIVE_LIVE`
maps to Conservative Demo only if the connected account's
`ACCOUNT_TRADE_MODE` is `ACCOUNT_TRADE_MODE_DEMO`, otherwise Conservative
Live; `QB_MODE_CHALLENGE_LIVE` always maps to the Challenge tier. Only the
Conservative Demo tier is currently sanctioned by `ModeAllowsStrategy` --
Conservative Live and Challenge Live are structurally reachable through
the same function once a future, separately-decided change extends it,
but are **not** sanctioned today.

**GlobalLiveRiskAcknowledged** reuses the existing
`InpAcknowledgeLiveBrokerRisk` input unchanged.

**BrokerPathAllowed** is implicit in `QBCurrentBrokerTier` returning a
classifiable tier at all (`QB_BROKER_TIER_UNKNOWN` for any `ENUM_QB_MODE`
value the function doesn't recognize -- structurally unreachable today
since all four `ENUM_QB_MODE` values are handled, but the fail-closed
branch exists for defensive completeness).

## Deliberate behavior change, documented (not a casual gate removal)

The new `QBLiveStrategySetAllowed()` additionally requires the connected
account's `ACCOUNT_TRADE_MODE` to be DEMO for **any** strategy (including
FBO) to pass, in **any** Conservative Live mode session -- the prior code
had no account-type check at all and would have permitted FBO-only live
submission against a real account. This is a deliberate safety
tightening, consistent with Phase 13's explicit instruction to
distinguish Conservative Demo from Conservative Live authorization
(which the prior code did not), not a casual removal of the existing
gate. Default behavior for the existing FBO-only Conservative-Demo case
is otherwise unchanged (`InpFBO_DemoAuthorized` defaults `true`,
preserving the prior default-allowed outcome for that one specific,
already-evidenced case).

## Implementation

- `Include/QuantBeast/Core/Configuration.mqh`: new
  `InpBO_DemoAuthorized=false`, `InpFBO_DemoAuthorized=true`,
  `InpMR_DemoAuthorized=false`, `InpTPV2_DemoAuthorized=false`.
- `Experts/QuantBeast/QuantBeastEA.mq5`: `ENUM_QB_BROKER_TIER`,
  `QBCurrentBrokerTier()`, `QBStrategyMechanicallyReady()`,
  `QBStrategyAllowlistCheck()` (the six-condition contract),
  `QBLiveStrategySetAllowed()` rewritten to loop the new contract over
  every enabled strategy (TP V1 still an absolute, first-checked
  exclusion) instead of a hardcoded FBO special case. Call site updated
  to pass `InpTPV2_Enabled`, `g_EffectiveMode`,
  `InpAcknowledgeLiveBrokerRisk`. Startup config log
  (`QBLogResolvedProductionConfiguration`) extended to print the new
  `DemoAuthorized` flags and resolved `BrokerTier`.
- Test 37 rewritten (fbo-only-preserved, TP-always-rejected,
  fbo-disabled-rejected, an enabled-but-unauthorized strategy rejected
  even alongside an authorized one, Shadow mode never satisfies
  ModeAllowsStrategy, missing global risk-ack rejected, TP V2 reachable
  once explicitly authorized). New Test 102 (broker-tier classification
  and mechanical-readiness table correctness, environment-independent).

No hardcoded all-strategy bypass was introduced: every strategy is
individually evaluated by the same six-condition function; there is no
special-cased "if testing, allow everything" branch anywhere in this
change.

---

# Phase 14 -- Restricted all-strategy demo candidate (updated)

`Experts/QuantBeast/XAUUSD_Conservative_Demo_AllStrategy.set` updated for
the new architecture: `InpBO_DemoAuthorized=true`,
`InpFBO_DemoAuthorized=true`, `InpMR_DemoAuthorized=true`,
`InpTPV2_DemoAuthorized=true` added (roster unchanged: BO+FBO+MR+TPV2,
TP V1 excluded). `InpAcknowledgeLiveBrokerRisk` remains `false` -- the
single remaining, explicitly-documented blocker.

Documented directly in the preset's header comment (per Phase 14's exact
requirements):

- **What still blocks activation**: exactly one line,
  `InpAcknowledgeLiveBrokerRisk=false`, plus the account-context
  requirement that the connected account be verified DEMO when the
  preset is loaded (else `ModeAllowsStrategy` fails closed for a
  different, equally correct reason).
- **Exact change to permit activation**: flip that one line to `true`
  while connected to the intended Coinexx-Demo account -- no other file
  or source change required.
- **Operator acknowledgements required**: explicit authorization for
  this preset, this account (verified demo, not real), this strategy
  roster -- matching the bar the original FBO-only 2026-07-16 activation
  required.
- **How to revert immediately**: flip the same line back to `false`.
- **How to disable one strategy without changing code**: set that
  strategy's own `InpXX_Enabled=false` or `InpXX_DemoAuthorized=false` in
  the preset (either alone is sufficient).

**Not activated this session.** No broker order was transmitted via this
preset or via any EA-attached live/demo session -- consistent with every
prior phase's confirmation.
