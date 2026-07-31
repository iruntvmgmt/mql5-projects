#!/usr/bin/env python3
"""Single language-neutral source for the 58 ScreeningSimulatorV2 fixtures.

Consumed by the Python test, the serializer (make_simulator_fixtures.py) and,
via the emitted simulator_fixtures.csv, by the MQL5 parity test. No fixture is
defined MQL-only. Each fixture carries its inputs plus the discriminating
expected fields asserted by the Python reference.
"""

from __future__ import annotations

from dataclasses import dataclass, field

SYMBOL = "XAUUSD"
TF = 5
PT = 0.01
POLICY = "MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST"
JSHA = "ab" * 32
P_STD = (1_000_000, 1_000_000, 0, 0)
P_TICK5 = (1_000_000, 5_000_000, 0, 0)
P_MIN = (1_000_000, 1_000_000, 0, 30)


@dataclass
class FCand:
    d: int          # +1 / -1
    signal: int
    expiry: int
    entry: float
    stop: float
    target_r: float
    fam: int = 9
    event: str = "E|1"
    seq: str = "S|1"


@dataclass
class Fixture:
    id: str
    behavior: str
    group: str
    bars: list          # (time, o, h, l, c, spread) integer points
    cands: list         # list[FCand]
    params: tuple = P_STD
    test_end: int | None = None
    policy_id: str = POLICY
    cm_symbol: str = SYMBOL
    cm_timeframe: int = TF
    cm_source: str | None = None       # None -> AUTO (= market sha); else override
    mm_sha_override: str | None = None  # None -> AUTO; else market-manifest sha override
    expect_run_status: str = "RUN_OK"
    expect: list = field(default_factory=list)  # per-candidate dict {field: value}


# common bar sets
B_LONG_TGT = [(100, 10000, 10010, 9990, 10000, 10),
              (200, 10000, 10020, 9995, 10010, 10),
              (300, 10010, 10060, 10005, 10050, 10)]
B_SHORT_COLL = [(100, 10000, 10010, 9990, 10000, 10),
                (200, 10000, 10015, 9945, 10000, 10)]
B2 = [(100, 10000, 10010, 9990, 10000, 10),
      (200, 10000, 10015, 9995, 10005, 10)]


def _long(entry=100.10, stop=99.90, tr=2.0, signal=100, expiry=100000, fam=9, event="E|1", seq="S|1"):
    return FCand(+1, signal, expiry, entry, stop, tr, fam, event, seq)


def _short(entry=100.00, stop=100.20, tr=2.0, signal=100, expiry=100000, fam=9, event="E|1", seq="S|1"):
    return FCand(-1, signal, expiry, entry, stop, tr, fam, event, seq)


FIXTURES = [
    # ---- Entry / eligibility ----
    Fixture("F01", "long next-bar entry", "entry", B_LONG_TGT, [_long()],
            expect=[{"status": "ACCEPTED", "entry_time_raw": 200, "exit_reason": "TARGET"}]),
    Fixture("F02", "short next-bar entry", "entry", B_SHORT_COLL, [_short()],
            expect=[{"status": "ACCEPTED", "executable_entry_points": 10000}]),
    Fixture("F03", "no signal-bar entry", "entry", B_LONG_TGT, [_long()],
            expect=[{"entry_time_raw": 200}]),
    Fixture("F04", "entry exactly at expiry", "entry", B2, [_long(stop=99.80, expiry=200)],
            expect=[{"status": "ACCEPTED", "entry_time_raw": 200}]),
    Fixture("F05", "entry after expiry", "entry", B2, [_long(stop=99.80, expiry=150)],
            expect=[{"status": "REJECT_EXPIRED"}]),
    Fixture("F06", "no next executable bar", "entry", B2, [_long(stop=99.80, signal=500)],
            expect=[{"status": "REJECT_NO_NEXT_EXECUTABLE_BAR"}]),
    Fixture("F07", "next bar after test end", "entry", B2, [_long(stop=99.80)], test_end=150,
            expect=[{"status": "REJECT_ENTRY_AFTER_TEST_END"}]),
    Fixture("F08", "invalid spread rejected at transport", "entry",
            [(100, 10000, 10010, 9990, 10000, -1)], [], expect_run_status="TRANSPORT_REJECT",
            expect=[]),
    Fixture("F09", "invalid bar rejected at transport", "entry",
            [(100, 10000, 9900, 9990, 10000, 10)], [], expect_run_status="TRANSPORT_REJECT",
            expect=[]),
    Fixture("F10", "deterministic same-time ordering", "entry", B2,
            [_long(stop=99.80, fam=9, event="E|b", seq="S|2"),
             _long(stop=99.80, fam=8, event="E|a", seq="S|1")],
            expect=[{"family_id": 8}, {"family_id": 9}]),

    # ---- Geometry ----
    Fixture("F11", "long ask entry incl spread", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 30),
             (300, 10030, 10120, 10025, 10100, 30)],
            [_long(entry=100.30, stop=100.10)],
            expect=[{"executable_entry_points": 10030, "spread_points_at_entry": 30}]),
    Fixture("F12", "short bid entry", "geometry", B_SHORT_COLL, [_short()],
            expect=[{"executable_entry_points": 10000}]),
    Fixture("F13", "variable spread affects entry", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 30),
             (300, 10030, 10120, 10025, 10100, 30)],
            [_long(entry=100.30, stop=100.10)],
            expect=[{"executable_entry_points": 10030}]),
    Fixture("F14", "long stop grid normalization", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10120, 10005, 10100, 10)],
            [_long(entry=100.10, stop=99.93)], params=P_TICK5,
            expect=[{"normalized_stop_points": 9990}]),
    Fixture("F15", "short stop grid normalization", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10005, 9990, 10000, 10)],
            [_short(entry=100.00, stop=100.07)], params=P_TICK5,
            expect=[{"normalized_stop_points": 10010}]),
    Fixture("F16", "minimum-distance widening", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10120, 10005, 10100, 10)],
            [_long(entry=100.10, stop=100.05)], params=P_MIN,
            expect=[{"initial_risk_points": 30}]),
    Fixture("F17", "target reconstructed after entry", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10120, 10005, 10100, 10)],
            [_long(entry=100.10, stop=100.05)], params=P_MIN,
            expect=[{"reconstructed_target_points": 10070}]),  # entry10010 + 2*risk30
    Fixture("F18", "off-grid candidate rejected", "geometry", B_LONG_TGT,
            [_long(entry=100.205, stop=100.10)],
            expect=[{"status": "REJECT_CANDIDATE_OFF_GRID"}]),
    Fixture("F19", "risk always positive (nonpositive guard defensive)", "geometry",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10020, 9995, 10010, 10)],
            [_long(entry=100.10, stop=100.09)],
            expect=[{"status": "ACCEPTED", "initial_risk_points": 1}]),

    # ---- Occupancy ----
    Fixture("F20", "same-family same-dir rejected", "occupancy",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10080, 10005, 10070, 10),
             (400, 10005, 10015, 9995, 10005, 10),
             (500, 10005, 10015, 9995, 10005, 10)],
            [_long(stop=99.80, fam=9, event="E|1", seq="S|1"),
             _long(stop=99.80, signal=250, fam=9, event="E|2", seq="S|2")],
            expect=[{"status": "ACCEPTED"}, {"status": "REJECT_FAMILY_OPEN"}]),
    Fixture("F21", "same-family opposite-dir rejected", "occupancy",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10080, 10005, 10070, 10),
             (400, 10005, 10015, 9995, 10005, 10),
             (500, 10005, 10015, 9995, 10005, 10)],
            [_long(stop=99.80, fam=9, event="E|1", seq="S|1"),
             _short(signal=250, fam=9, event="E|2", seq="S|2")],
            expect=[{"status": "ACCEPTED"}, {"status": "REJECT_FAMILY_OPEN"}]),
    Fixture("F22", "acceptance after prior close", "occupancy",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10080, 10005, 10070, 10),
             (400, 10005, 10015, 9995, 10005, 10),
             (500, 10005, 10015, 9995, 10005, 10)],
            [_long(stop=99.80, fam=9, event="E|1", seq="S|1"),
             _long(stop=99.80, signal=350, fam=9, event="E|3", seq="S|3")],
            expect=[{"status": "ACCEPTED"}, {"status": "ACCEPTED"}]),
    Fixture("F23", "different families coexist", "occupancy",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10080, 10005, 10070, 10),
             (400, 10005, 10015, 9995, 10005, 10),
             (500, 10005, 10015, 9995, 10005, 10)],
            [_long(stop=99.80, fam=9, event="E|1", seq="S|1"),
             _long(stop=99.80, signal=250, fam=10, event="E|2", seq="S|2")],
            expect=[{"status": "ACCEPTED"}, {"status": "ACCEPTED"}]),
    Fixture("F24", "simultaneous same-family deterministic winner", "occupancy",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10010, 10080, 10005, 10070, 10),
             (400, 10005, 10015, 9995, 10005, 10),
             (500, 10005, 10015, 9995, 10005, 10)],
            [_long(stop=99.80, fam=9, event="E|2", seq="S|2"),
             _long(stop=99.80, fam=9, event="E|1", seq="S|1")],
            expect=[{"event_id": "E|1", "status": "ACCEPTED"},
                    {"event_id": "E|2", "status": "REJECT_FAMILY_OPEN"}]),

    # ---- Exits ----
    Fixture("F25", "long target", "exit", B_LONG_TGT, [_long()],
            expect=[{"exit_reason": "TARGET", "executable_exit_points": 10050}]),
    Fixture("F26", "long stop", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10015, 9985, 10000, 10)],
            [_long()], expect=[{"exit_reason": "STOP", "executable_exit_points": 9990}]),
    Fixture("F27", "short target", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10005, 9930, 10000, 10)],
            [_short()], expect=[{"exit_reason": "TARGET", "executable_exit_points": 9960}]),
    Fixture("F28", "short stop", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10025, 9995, 10000, 10)],
            [_short()], expect=[{"exit_reason": "STOP", "executable_exit_points": 10020}]),
    Fixture("F29", "long same-bar collision stop-first", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10060, 9985, 10000, 10)],
            [_long()], expect=[{"exit_reason": "STOP", "stop_first_collision": "true"}]),
    Fixture("F30", "short same-bar collision stop-first", "exit", B_SHORT_COLL, [_short()],
            expect=[{"exit_reason": "STOP", "stop_first_collision": "true"}]),
    Fixture("F31", "long stop gap fills at open", "exit",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10015, 9995, 10005, 10),
             (300, 9970, 9975, 9960, 9965, 10)],
            [_long()], expect=[{"exit_reason": "STOP", "executable_exit_points": 9970}]),
    Fixture("F32", "short stop gap fills at ask open", "exit",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10005, 9995, 10000, 10),
             (300, 10040, 10060, 10035, 10050, 10)],
            [_short()], expect=[{"exit_reason": "STOP", "executable_exit_points": 10050}]),
    Fixture("F33", "favorable target capped", "exit",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10020, 9995, 10010, 10),
             (300, 10080, 10090, 10075, 10085, 10)],
            [_long()], expect=[{"exit_reason": "TARGET", "executable_exit_points": 10050}]),
    Fixture("F34", "long test-end bid close", "exit", B2, [_long(stop=99.80)],
            expect=[{"exit_reason": "TEST_END", "executable_exit_points": 10005}]),
    Fixture("F35", "short test-end ask close", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10005, 9995, 10000, 10)],
            [_short(stop=100.50)], expect=[{"exit_reason": "TEST_END", "executable_exit_points": 10010}]),
    Fixture("F36", "same-bar entry and exit", "exit",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10060, 9995, 10050, 10)],
            [_long()], expect=[{"entry_time_raw": 200, "exit_time_raw": 200, "holding_bars": 1}]),

    # ---- Accounting ----
    Fixture("F37", "long winner R + MFE/MAE + holding", "accounting", B_LONG_TGT, [_long()],
            expect=[{"gross_r_1e9": 2_000_000_000, "holding_bars": 2,
                     "mfe_r_1e9": 2_000_000_000, "mae_r_1e9": 750_000_000}]),
    Fixture("F38", "long loser R", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10015, 9985, 10000, 10)],
            [_long()], expect=[{"gross_r_1e9": -1_000_000_000, "holding_bars": 1}]),
    Fixture("F39", "short winner R", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10005, 9930, 10000, 10)],
            [_short()], expect=[{"gross_r_1e9": 2_000_000_000}]),
    Fixture("F40", "short loser R", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10025, 9995, 10000, 10)],
            [_short()], expect=[{"gross_r_1e9": -1_000_000_000}]),
    Fixture("F41", "partial-R test-end", "accounting", B2, [_long(stop=99.80)],
            expect=[{"exit_reason": "TEST_END"}]),
    Fixture("F42", "MFE/MAE long", "accounting", B_LONG_TGT, [_long()],
            expect=[{"mfe_r_1e9": 2_000_000_000, "mae_r_1e9": 750_000_000}]),
    Fixture("F43", "MFE/MAE short", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10005, 9930, 10000, 10)],
            [_short()], expect=[{"mfe_r_1e9": 2_000_000_000}]),
    Fixture("F44", "MFE/MAE changing spread short", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10),
             (200, 10000, 10010, 9970, 10000, 20),
             (300, 10000, 10010, 9930, 10000, 30)],
            [_short()], expect=[{"status": "ACCEPTED"}]),
    Fixture("F45", "MFE/MAE exit-bar capped", "accounting", B_LONG_TGT, [_long()],
            expect=[{"mfe_r_1e9": 2_000_000_000}]),
    Fixture("F46", "holding same-bar = 1", "accounting",
            [(100, 10000, 10010, 9990, 10000, 10), (200, 10000, 10015, 9985, 10000, 10)],
            [_long()], expect=[{"holding_bars": 1}]),
    Fixture("F47", "multi-bar holding count", "accounting", B_LONG_TGT, [_long()],
            expect=[{"holding_bars": 2}]),
    Fixture("F48", "integer R vs policy GrossR within 1e-9", "accounting", B_LONG_TGT, [_long()],
            expect=[{"status": "ACCEPTED"}]),

    # ---- Integrity / determinism ----
    Fixture("F49", "unsupported policy aborts", "integrity", B2, [_long(stop=99.80)],
            policy_id="OTHER", expect_run_status="REJECT_UNSUPPORTED_POLICY"),
    Fixture("F50", "source hash mismatch aborts", "integrity", B2, [_long(stop=99.80)],
            cm_source="0" * 64, expect_run_status="REJECT_SOURCE_HASH_MISMATCH"),
    Fixture("F51", "market hash mismatch aborts", "integrity", B2, [_long(stop=99.80)],
            mm_sha_override="1" * 64, expect_run_status="REJECT_MARKET_HASH_MISMATCH"),
    Fixture("F52", "symbol mismatch aborts", "integrity", B2, [_long(stop=99.80)],
            cm_symbol="EURUSD", expect_run_status="REJECT_SYMBOL_MISMATCH"),
    Fixture("F53", "timeframe mismatch aborts", "integrity", B2, [_long(stop=99.80)],
            cm_timeframe=1, expect_run_status="REJECT_TIMEFRAME_MISMATCH"),
    Fixture("F54", "clock domain mismatch aborts", "integrity", B2,
            [FCand(+1, 100, 100000, 100.10, 99.80, 2.0)], expect_run_status="REJECT_CLOCK_DOMAIN_MISMATCH",
            expect=[{"__clock__": "UTC_CONVERTED"}]),
    Fixture("F55", "time authority mismatch aborts", "integrity", B2,
            [FCand(+1, 100, 100000, 100.10, 99.80, 2.0)], expect_run_status="REJECT_TIME_AUTHORITY_MISMATCH",
            expect=[{"__auth__": "OTHER_AUTH"}]),
    Fixture("F56", "instrument params contradiction aborts", "integrity", B2,
            [FCand(+1, 100, 100000, 100.10, 99.80, 2.0)], expect_run_status="REJECT_INSTRUMENT_PARAMS_MISMATCH",
            expect=[{"__stop_distance__": 99.0}]),
    Fixture("F57", "shuffled candidates identical output", "integrity", B_LONG_TGT,
            [_long(fam=9, event="E|2", seq="S|2"), _long(fam=8, event="E|1", seq="S|1")],
            expect=[{"family_id": 8}, {"family_id": 9}]),
    Fixture("F58", "repeated run identical bytes/SHA", "integrity", B_LONG_TGT,
            [_long(fam=9, event="E|2", seq="S|2"), _long(fam=8, event="E|1", seq="S|1")],
            expect=[{"family_id": 8}, {"family_id": 9}]),
]


def build_candidate(fc: FCand, clock="BROKER_SERVER_RAW", auth="MSZZ_TIME_RAW_BROKER_V1",
                    stop_distance=None):
    import screening_simulator_v2 as sim
    sd = abs(fc.entry - fc.stop) / PT if stop_distance is None else stop_distance
    return sim.Candidate(1200, fc.fam, "H", "V", "O", fc.seq, fc.event, clock, auth,
                         fc.signal, fc.expiry, fc.d, fc.entry, fc.stop,
                         fc.entry + fc.d * abs(fc.entry - fc.stop) * fc.target_r, fc.target_r, sd)
