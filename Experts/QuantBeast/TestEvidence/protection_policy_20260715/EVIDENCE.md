# Protective Stop Policy Evidence — 2026-07-15

## Confirmed defect

Initial protection required the broker SL to equal the requested SL within roughly half a tick. A broker-adjusted SL that was tighter and therefore safer was classified as failure. The repair path then attempted to loosen it back to the requested value, which the anti-loosening guard rejected, potentially causing an unnecessary emergency liquidation.

## Repair

- Protection is now directional: a buy SL at or above the requested SL is at least as protective; a sell SL at or below the requested SL is at least as protective.
- Missing or looser stops remain failures.
- Target mismatches still trigger one repair attempt.
- A tighter existing stop is preserved during target repair.
- If the requested target cannot be restored but the protective stop is valid, the position remains protected and the mismatch is logged instead of forcing liquidation.
- If no adequate SL can be established, the existing fail-safe close and latched emergency behavior remain unchanged.

## Evidence

- Compile: `0 errors, 0 warnings, 7949 ms`, X64 Regular
- Source SHA-256: `51449232784d5ed0203e622dc085e8067e772d59d01d584fa2b38afd7404a2f4`
- EX5 SHA-256: `08303d242541a1eddcc3342b09c9044d84451295c2789aa7fe9404fedab32218`
- BrokerAdapter SHA-256: `262a940d953eb97c7f895eef5084580328296c3a5589289c21ccc2347dbcefa6`
- SafetyTests SHA-256: `899acf56337c4db8303c9bccfd2bb0ecb3f8afcc3f6ae68f6b51cfa6d596ff7d`
- New fixture: `TEST 25 PASS: Protective stop policy buy=safe sell=safe missing=rejected`
- Complete suite: `27 passed, 0 failed`
- Tester: `38041` ticks, `1903` bars, `17.864 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic stop classification. Actual broker modification rejection, freeze-level behavior, fail-safe close failure, and repeated emergency flattening still require controlled demo/fault-injection evidence.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
