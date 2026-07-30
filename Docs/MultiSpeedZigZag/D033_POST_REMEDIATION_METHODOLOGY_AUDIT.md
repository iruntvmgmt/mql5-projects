# D033 post-remediation methodology audit

## Status

The event-scoped identity repair at `467155e` remains accepted evidence
for the current production policy. This audit does not overwrite it and
does not tune SSR.

Three classifications apply:

1. **`SSR_VALID_REJECTION`**
2. **`D032_D033_METHODOLOGY_MISMATCH`**
3. **`D031_D032_EVENT_SEMANTICS_DEFECT`**

**D034 remains blocked.**

## D032 versus D033 execution policy

Source inspection proves that `Tools/D032/simulate_and_screen.py` resolves
each accepted trade only by walking future bars to its emitted stop or
target. While that family trade remains open, every later candidate is
rejected without regard to direction. It contains no opposite-signal
close or immediate reversal path.

| Behavior | D032 simulator | Old D033 | Corrected D033 `467155e` |
|---|---|---|---|
| Same-direction candidate while open | Reject | Reject ownership | Reject ownership |
| Opposite candidate while open | Reject | Close and reverse | Close and reverse |
| Stop / target exit | Yes / yes | Yes / yes | Yes / yes |
| Opposite-signal exit | No | Yes | Yes |
| Immediate reversal | No | Yes | Yes |
| Test-end position | Excluded | Broker test-end close | Broker test-end close |

The 30 `OTHER` exits at `467155e` are all own-family opposite closes and
all 30 immediately entered the opposite SSR trade. Under a stop/target-only
counterfactual, 17 would later hit target and 13 would hit stop. Their
actual opposite-close sum was +15.7062R versus +21R for those individual
counterfactual outcomes, though portfolio sequencing prevents treating
that difference alone as the parity portfolio result.

Therefore the 906-trade `467155e` result is valid for current production
behavior but is not an apples-to-apples reproduction of D032.

## Controlled stop/target-only parity run

The controlled configuration changes only:

```text
InpExitOwnedOpposite=false
InpSuppressReversalEntry=true
```

Report name and magic are isolated. Candidate validity, target, risk,
dates, symbol, timeframe, and every signal threshold remain unchanged.
All 2,650 runtime candidates match the preserved `467155e` geometry and
identity evidence field-for-field.

| Metric | D032 synthetic | Controlled broker parity |
|---|---:|---:|
| Candidates | 2,650 | 2,650 |
| Trades | 822 | 822 |
| Stop exits | modeled | 543 |
| Target exits | modeled | 279 |
| Opposite exits / reversals | 0 / 0 | 0 / 0 |
| PF | 1.079 | 1.0276 |
| Expectancy | +0.051R | +0.01825R |
| Total | not carried in headline | +14.9991R |
| Maximum drawdown | D032 evidence | 35.0125R |

Broker entry, spread, normalized protection and other executable mechanics
explain why identical trade count does not imply identical R.

### Promotion gates

| Gate | Result |
|---|---|
| PF > 1.05 | **FAIL** |
| Expectancy > 0 | PASS |
| Development > 0 | PASS: +2.9949R |
| Validation > 0 | PASS: +16.9943R |
| Holdout > 0 | **FAIL: -4.9901R** |
| Top-three exclusion > 0 | PASS: +8.9806R |
| Best-quarter exclusion > 0 | **FAIL: -13.9981R** |

Thus the implemented D032 stop/target-only hypothesis receives a valid
broker-executable rejection without carrying forward the opposite-exit
methodology mismatch.

## Re-arm semantics

The audit replay duplicates production ordering without changing it:

```text
Evaluate1Side()
terminal state sets active=false
same Evaluate() call reaches Arm()
```

It reproduced all 2,650 emitted sequence origins exactly.

| Re-arm classification | Candidates | Current-policy trades | Current total / PF / expectancy | Parity trades | Parity total / PF / expectancy |
|---|---:|---:|---|---:|---|
| `FRESH_CROSS_FROM_INSIDE` | 376 | 256 | +16.1657R / 1.0991 / +0.06315R | 228 | +15.0321R / 1.1023 / +0.06593R |
| `FRESH_CROSS_AFTER_NEUTRAL_RESET` | 449 | 116 | -5.8044R / 0.9259 / -0.05004R | 103 | +4.9888R / 1.0745 / +0.04843R |
| `SAME_TRIGGER_BAR_REARM` | 1,825 | 534 | -12.6712R / 0.9638 / -0.02373R | 491 | -5.0218R / 0.9847 / -0.01023R |
| Still outside after expiry/invalidation | 0 | 0 | — | 0 | — |
| Other | 0 | 0 | — | 0 | — |

The state machine made 32,586 total arm calls; 2,650 later emitted
candidates. Of emitted candidates, 68.9% were armed on the same bar that
the preceding setup triggered, expired, or invalidated. Deterministic
tests independently prove same-bar re-arm after expiry and invalidation.

Timestamp identity is therefore technically unique but does not establish
a fresh economic excursion. This is material and warrants
`D031_D032_EVENT_SEMANTICS_DEFECT`. No state-machine repair is attempted
in this audit.

## Canonical configuration enforcement

When production SSR is enabled, initialization now fails closed unless:

```text
InpSignalValidityBars == 3
InpSSRBookTargetR == 2.0
```

The strategy also retains its validity constant internally as
defense-in-depth. Other strategies preserve their existing configurable
behavior. Tests cover canonical acceptance and rejection of both invalid
values.

## Verification and integrity

- EA: 0 errors, 0 warnings at `2026.07.30 08:11:10.823`.
- SSR test: 0 errors, 0 warnings at `2026.07.30 08:12:26.446`.
- Expanded SSR tests: 22/22.
- Complete regression: 32/32 with fresh raw logs, zero no-ops and zero
  shutdown timeouts.
- P4: 330 trades, +47.6083R, PF 1.2472, canonical SHA-256
  `9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f`.
- Parity run: zero unresolved positions, duplicate identities/intents,
  unknown exits, opposite exits, reversals, volume/weighted-price/R
  mismatches, risk overruns, or ownership violations.

## Decision

The production plumbing remains safe. The D032/D033 exit-policy mismatch
is now quantified and controlled. Canonical inputs cannot drift. The
controlled parity run fails mandatory promotion gates, so SSR is validly
rejected as implemented.

Separately, the prevalence and negative contribution of same-trigger-bar
re-arms means economic event uniqueness is not proven and the D031/D032
event model itself is defective. No redesign is authorized here.

**D034 is not authorized.**

Machine-readable evidence is under `Tools/D033/Methodology/`.
