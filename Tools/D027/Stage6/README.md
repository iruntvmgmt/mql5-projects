# D027 Stage 6 — actual combined portfolio analysis

This checkpoint compares SweepReclaim with canonical FastMedConfluence A and
E using actual shared-EA backtests. The EA has one global reward/risk input,
so the comparisons are target matched:

- A alone, SweepReclaim alone, and A+SweepReclaim at fixed 2R.
- E alone, SweepReclaim alone, and E+SweepReclaim at fixed 3R.

Standalone results are never arithmetically combined. The two combined runs
exercise the EA's real clustering, ownership, opposite-signal exits, costs,
and position serialization.

Run:

```bash
python3 Tools/D027/Stage6/analyze_stage6_portfolio.py
```

The tool reuses certified standalone artifacts from D027 Stages 2, 4, and 5
and D026, and reads the two completed combined runs from:

```text
/Users/matt/MT5-MSZZ-TEST/D027_Stage6_Results
```

It verifies config identity, HTML/RunSummary/analytics agreement, unique
executed-signal joins, original entry-time regime joins, window
reconciliation, arbitration counts, and exit classification. Outputs cover
full and frozen-window results, incremental portfolio effects, owner
contribution, unique trades, outlier checks, correlations, rolling
correlations, weak-core months, arbitration, exits, and deterministic hashes.

Raw MT5 reports remain outside the repository under the established artifact
size policy. This checkpoint changes no EA code, frozen trigger, regime
definition, canonical A, or canonical E.
