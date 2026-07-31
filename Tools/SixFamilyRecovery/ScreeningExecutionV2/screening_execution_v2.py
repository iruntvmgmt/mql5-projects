from dataclasses import dataclass
from enum import IntEnum
import math

POLICY_ID = "MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST"

class Exit(IntEnum):
    STOP = 0
    TARGET = 1
    TEST_END = 2

class Reject(IntEnum):
    ACCEPT = 0
    FAMILY_OPEN = 1
    EXPIRED = 2
    INVALID_GEOMETRY = 3

@dataclass(frozen=True)
class Policy:
    policy_id: str = POLICY_ID
    schema_version: int = 2
    entry_offset_bars: int = 1
    entry_uses_next_ask_for_long: bool = True
    entry_uses_next_bid_for_short: bool = True
    spread_embedded_once: bool = True
    conservative_stop_rounding: bool = True
    conservative_target_rounding: bool = True
    one_position_per_family: bool = True
    reject_signals_while_open: bool = True
    opposite_signal_closes: bool = False
    immediate_reversal: bool = False
    stop_first_same_bar: bool = True
    expiry_is_entry_only: bool = True
    include_test_end_in_metrics: bool = True
    include_commission_in_gross_r: bool = False

def canonical() -> Policy:
    return Policy()

def validate(p: Policy) -> None:
    if p != canonical():
        raise ValueError("policy is not the frozen V2 contract")

# Grid rounding with the certified MQL5 boundary epsilon
# (ScreeningExecutionPolicyV2.mqh NormalizeStop/NormalizeTarget). The epsilon
# sign is hard-bound to the rounding direction so no caller can supply the
# wrong sign: floor(value/tick + 1e-9), ceil(value/tick - 1e-9). Only the
# primary normalization carries the epsilon; the minimum-distance fallbacks
# below are epsilon-free (matching MQL5). Long geometry (direction > 0) uses
# the floor helper, short geometry (direction < 0) uses the ceil helper, for
# both stop and target.
def _floor_ticks(value: float, tick: float) -> float:
    if tick <= 0 or value <= 0:
        return 0.0
    return math.floor(value / tick + 1.0e-9) * tick

def _ceil_ticks(value: float, tick: float) -> float:
    if tick <= 0 or value <= 0:
        return 0.0
    return math.ceil(value / tick - 1.0e-9) * tick

def normalize_stop(direction: int, raw_stop: float, entry: float, tick: float) -> float:
    if tick <= 0 or entry <= 0 or raw_stop <= 0:
        return 0.0
    n = _floor_ticks(raw_stop, tick) if direction > 0 else _ceil_ticks(raw_stop, tick)
    if direction > 0 and n >= entry:
        n = math.floor((entry - tick) / tick) * tick
    if direction < 0 and n <= entry:
        n = math.ceil((entry + tick) / tick) * tick
    return round(n, 8)

def normalize_target(direction: int, raw_target: float, entry: float, tick: float) -> float:
    if tick <= 0 or entry <= 0 or raw_target <= 0:
        return 0.0
    n = _floor_ticks(raw_target, tick) if direction > 0 else _ceil_ticks(raw_target, tick)
    if direction > 0 and n <= entry:
        n = math.ceil((entry + tick) / tick) * tick
    if direction < 0 and n >= entry:
        n = math.floor((entry - tick) / tick) * tick
    return round(n, 8)

def candidate_status(family_open: bool, entry_time: int, expiry_time: int) -> Reject:
    if family_open:
        return Reject.FAMILY_OPEN
    if expiry_time > 0 and entry_time > expiry_time:
        return Reject.EXPIRED
    return Reject.ACCEPT

def resolve_bar(direction: int, stop: float, target: float, high: float, low: float) -> Exit:
    hit_stop = low <= stop if direction > 0 else high >= stop
    hit_target = high >= target if direction > 0 else low <= target
    if hit_stop:
        return Exit.STOP
    if hit_target:
        return Exit.TARGET
    return Exit.TEST_END

def gross_r(direction: int, entry: float, exit_price: float, stop: float) -> float:
    risk = abs(entry - stop)
    if risk <= 0:
        return 0.0
    return ((exit_price - entry) if direction > 0 else (entry - exit_price)) / risk
