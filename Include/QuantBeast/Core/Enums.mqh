//+------------------------------------------------------------------+
//|                                               QuantBeast/Enums.mqh |
//|                          XAUUSD Quant Beast EA - Enum Definitions |
//| Project: QuantBeast                                              |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_ENUMS_MQH
#define QB_ENUMS_MQH

//+------------------------------------------------------------------+
//| Operating Modes                                                   |
//+------------------------------------------------------------------+
enum ENUM_QB_MODE
{
   QB_MODE_DIAGNOSTIC        = 0,  // Diagnostic - no orders
   QB_MODE_SHADOW            = 1,  // Shadow - simulate only
   QB_MODE_CONSERVATIVE_LIVE = 2,  // Conservative Live
   QB_MODE_CHALLENGE_LIVE    = 3   // Challenge Live
};

//+------------------------------------------------------------------+
//| Trend Regime                                                      |
//+------------------------------------------------------------------+
enum ENUM_TREND_REGIME
{
   TREND_STRONG_UP      = 0,
   TREND_WEAK_UP        = 1,
   TREND_NEUTRAL        = 2,
   TREND_WEAK_DOWN      = 3,
   TREND_STRONG_DOWN    = 4,
   TREND_EXHAUSTED_UP   = 5,
   TREND_EXHAUSTED_DOWN = 6
};

//+------------------------------------------------------------------+
//| Volatility Regime                                                 |
//+------------------------------------------------------------------+
enum ENUM_VOLATILITY_REGIME
{
   VOL_COMPRESSION = 0,
   VOL_NORMAL      = 1,
   VOL_EXPANSION   = 2,
   VOL_EXTREME     = 3,
   VOL_SHOCK       = 4
};

//+------------------------------------------------------------------+
//| Liquidity Regime                                                  |
//+------------------------------------------------------------------+
enum ENUM_LIQUIDITY_REGIME
{
   LIQUIDITY_GOOD       = 0,
   LIQUIDITY_ACCEPTABLE = 1,
   LIQUIDITY_THIN       = 2,
   LIQUIDITY_UNSAFE     = 3
};

//+------------------------------------------------------------------+
//| Structural Regime                                                 |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_REGIME
{
   STRUCTURE_BALANCED           = 0,
   STRUCTURE_BREAKOUT_ATTEMPT   = 1,
   STRUCTURE_ACCEPTED_BREAKOUT  = 2,
   STRUCTURE_FAILED_BREAKOUT    = 3,
   STRUCTURE_PULLBACK           = 4,
   STRUCTURE_IMPULSE            = 5,
   STRUCTURE_EXHAUSTION         = 6
};

//+------------------------------------------------------------------+
//| Session Type                                                      |
//+------------------------------------------------------------------+
enum ENUM_SESSION_TYPE
{
   SESSION_ASIA              = 0,
   SESSION_LONDON_PREOPEN    = 1,
   SESSION_LONDON_OPEN       = 2,
   SESSION_LONDON            = 3,
   SESSION_NY_PREOPEN        = 4,
   SESSION_NY_OPEN           = 5,
   SESSION_LONDON_NY_OVERLAP = 6,
   SESSION_NY_AFTERNOON      = 7,
   SESSION_ROLLOVER          = 8,
   SESSION_FRIDAY_CLOSE      = 9,
   SESSION_WEEKEND           = 10,
   SESSION_UNKNOWN           = 11
};

//+------------------------------------------------------------------+
//| Event State                                                       |
//+------------------------------------------------------------------+
enum ENUM_EVENT_STATE
{
   EVENT_NORMAL               = 0,
   EVENT_PRE_NEWS_LOCKOUT     = 1,
   EVENT_POST_NEWS_DISCOVERY  = 2,
   EVENT_MANUAL_LOCKOUT       = 3
};

//+------------------------------------------------------------------+
//| Arbitration Method                                                |
//+------------------------------------------------------------------+
enum ENUM_ARBITRATION_METHOD
{
   ARBITRATION_HIGHEST_SCORE       = 0,
   ARBITRATION_REGIME_PRIORITY     = 1,
   ARBITRATION_REQUIRE_CONFLUENCE  = 2,
   ARBITRATION_REJECT_CONFLICTS    = 3
};

//+------------------------------------------------------------------+
//| Order State                                                       |
//+------------------------------------------------------------------+
enum ENUM_ORDER_STATE_QB
{
   QB_ORDER_STATE_NEW                = 0,
   QB_ORDER_STATE_VALIDATED          = 1,
   QB_ORDER_STATE_SUBMITTED          = 2,
   QB_ORDER_STATE_ACKNOWLEDGED       = 3,
   QB_ORDER_STATE_PARTIALLY_FILLED   = 4,
   QB_ORDER_STATE_FILLED             = 5,
   QB_ORDER_STATE_PROTECTED          = 6,
   QB_ORDER_STATE_CANCEL_PENDING     = 7,
   QB_ORDER_STATE_CANCELLED          = 8,
   QB_ORDER_STATE_REJECTED           = 9,
   QB_ORDER_STATE_EXPIRED            = 10,
   QB_ORDER_STATE_CLOSED             = 11
};

//+------------------------------------------------------------------+
//| Lot Sizing Mode                                                   |
//+------------------------------------------------------------------+
enum ENUM_MODE_LOTS
{
   LOTS_MODE_FIXED      = 0,
   LOTS_MODE_RISK_FIXED = 1,
   LOTS_MODE_RISK_PCT   = 2,
   LOTS_MODE_VOL_ADJ    = 3
};

//+------------------------------------------------------------------+
//| Trigger Type (for breakout/failed-breakout strategies)            |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_TYPE
{
   TRIGGER_IMMEDIATE_BREAK    = 0,  // Any bar in the trade direction (no wait)
   TRIGGER_CANDLE_CLOSE_BREAK = 1,  // Confirmed directional close beyond level
   TRIGGER_DISPLACEMENT       = 2,  // Directional close with >=1 ATR body
   TRIGGER_BREAK_RETEST       = 3,  // Broke a level, wicked back to retest, held
   TRIGGER_PROBE_CONFIRM      = 4,  // Strong body closing near the extreme beyond level
   TRIGGER_REJECTION          = 5   // Entry on a directional rejection wick (TP/MR)
};

//+------------------------------------------------------------------+
//| Level Source (which objective level a strategy references)        |
//+------------------------------------------------------------------+
enum ENUM_LEVEL_SOURCE
{
   LEVEL_SRC_RANGE         = 0,  // Prior confirmed range high/low (default)
   LEVEL_SRC_PREV_DAY      = 1,  // Previous-day high/low
   LEVEL_SRC_SESSION       = 2,  // Current session high/low
   LEVEL_SRC_OPENING_RANGE = 3,  // Opening-range high/low
   LEVEL_SRC_SWING         = 4   // Most recent confirmed swing high/low
};

//+------------------------------------------------------------------+
//| Allocation mode — how the risk budget is split across strategies  |
//+------------------------------------------------------------------+
enum ENUM_ALLOCATION_MODE
{
   ALLOC_EQUAL       = 0,  // Equal weight (1.0x each) -- no behavior change
   ALLOC_CONFIDENCE  = 1,  // Weight by rolling average signal confidence
   ALLOC_PERFORMANCE = 2   // Weight by rolling average realized R
};

//+------------------------------------------------------------------+
//| Stop placement mode (STOP_MODE_DEFAULT keeps each engine's own)   |
//+------------------------------------------------------------------+
enum ENUM_STOP_MODE
{
   STOP_MODE_DEFAULT    = 0,  // Engine's native stop (unchanged behavior)
   STOP_MODE_ATR        = 1,  // Fixed ATR multiple from entry
   STOP_MODE_SWING      = 2,  // Beyond most recent swing +/- ATR buffer
   STOP_MODE_STRUCTURAL = 3,  // Beyond the prior range boundary +/- ATR buffer
   STOP_MODE_SWEEP      = 4   // Beyond the sweep extreme +/- ATR buffer
};

//+------------------------------------------------------------------+
//| Target selection mode (TARGET_MODE_DEFAULT keeps each engine's)   |
//+------------------------------------------------------------------+
enum ENUM_TARGET_MODE
{
   TARGET_MODE_DEFAULT      = 0,  // Engine's native target (unchanged behavior)
   TARGET_MODE_FIXED_R      = 1,  // Fixed R multiple of the stop distance
   TARGET_MODE_VWAP         = 2,  // Session VWAP (fair value)
   TARGET_MODE_RANGE_MID    = 3,  // Range midpoint
   TARGET_MODE_OPP_BOUNDARY = 4   // Opposite range boundary
};

//+------------------------------------------------------------------+
//| Exit Reason                                                       |
//+------------------------------------------------------------------+
enum ENUM_EXIT_REASON
{
   EXIT_TARGET_HIT         = 0,
   EXIT_STOP_LOSS          = 1,
   EXIT_TRAIL_STOP         = 2,
   EXIT_TIME_STOP          = 3,
   EXIT_SESSION_END        = 4,
   EXIT_PRE_NEWS           = 5,
   EXIT_REGIME_DETERIORATE = 6,
   EXIT_FAILED_MOMENTUM    = 7,
   EXIT_EMERGENCY_FLATTEN  = 8,
   EXIT_MANUAL             = 9,
   EXIT_RECOVERY           = 10,
   EXIT_UNKNOWN            = 11
};

//+------------------------------------------------------------------+
//| Kill Switch Type                                                  |
//+------------------------------------------------------------------+
enum ENUM_KILL_SWITCH
{
   KILL_NONE           = 0,
   KILL_STRATEGY       = 1,
   KILL_ENTRIES        = 2,
   KILL_SYMBOL         = 3,
   KILL_CANCEL_ALL     = 4,
   KILL_FLATTEN_ALL    = 5,
   KILL_EMERGENCY      = 6
};

//+------------------------------------------------------------------+
//| Position Management Method                                        |
//+------------------------------------------------------------------+
enum ENUM_MANAGEMENT_METHOD
{
   MGMT_FIXED_STOP          = 0,
   MGMT_BREAKEVEN           = 1,
   MGMT_BREAKEVEN_PLUS      = 2,
   MGMT_PARTIAL_CLOSE       = 3,
   MGMT_ATR_TRAIL           = 4,
   MGMT_SWING_TRAIL         = 5,
   MGMT_CHANDELIER_TRAIL    = 6,
   MGMT_TIME_STOP           = 7,
   MGMT_SESSION_END         = 8,
   MGMT_REGIME_EXIT         = 9
};

//+------------------------------------------------------------------+
//| Unknown Position Policy                                           |
//+------------------------------------------------------------------+
enum ENUM_UNKNOWN_POS_POLICY
{
   UNKNOWN_IGNORE    = 0,
   UNKNOWN_REPORT    = 1,
   UNKNOWN_QUARANTINE = 2,
   UNKNOWN_FLATTEN   = 3
};

//+------------------------------------------------------------------+
//| Challenge Stage                                                   |
//+------------------------------------------------------------------+
enum ENUM_CHALLENGE_STAGE
{
   CHALLENGE_STAGE_0 = 0,   // $100-$130
   CHALLENGE_STAGE_1 = 1,   // $130-$200
   CHALLENGE_STAGE_2 = 2,   // $200-$350
   CHALLENGE_STAGE_3 = 3,   // $350-$600
   CHALLENGE_STAGE_4 = 4,   // $600-$1000
   CHALLENGE_STAGE_FAILED = 5,
   CHALLENGE_STAGE_COMPLETE = 6
};

//+------------------------------------------------------------------+
//| Setup Codes (for signal generation)                               |
//+------------------------------------------------------------------+
enum ENUM_SETUP_CODE
{
   SETUP_NONE                       = 0,
   // Breakout setups
   SETUP_BO_COMPRESSION             = 100,
   SETUP_BO_OR_BOUNDARY             = 101,
   SETUP_BO_SESSION_BOUNDARY        = 102,
   SETUP_BO_RANGE_BOUNDARY          = 103,
   // Failed breakout setups
   SETUP_FBO_PD_HIGH                = 200,
   SETUP_FBO_PD_LOW                 = 201,
   SETUP_FBO_SESSION_HIGH           = 202,
   SETUP_FBO_SESSION_LOW            = 203,
   SETUP_FBO_SWING_HIGH             = 204,
   SETUP_FBO_SWING_LOW              = 205,
   SETUP_FBO_OR_BOUNDARY            = 206,
   // Trend pullback setups
   SETUP_TP_TREND_QUALIFIED         = 300,
   SETUP_TP_PULLBACK_DEPTH_OK       = 301,
   SETUP_TP_MICRO_REVERSAL          = 302,
   // Mean reversion setups
   SETUP_MR_BALANCED_MARKET         = 400,
   SETUP_MR_DEVIATION_EXTREME       = 401,
   SETUP_MR_REJECTION_VISIBLE       = 402
};

//+------------------------------------------------------------------+
//| Trigger Codes                                                     |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_CODE
{
   TRIGGER_NONE                     = 0,
   // Breakout triggers
   TRIGGER_BO_LEVEL_BREAK           = 110,
   TRIGGER_BO_CLOSE_BEYOND          = 111,
   TRIGGER_BO_DISPLACEMENT_OK       = 112,
   TRIGGER_BO_RETEST_PASSED         = 113,
   // Failed breakout triggers
   TRIGGER_FBO_RECLAIM              = 210,
   TRIGGER_FBO_CONFIRMATION_CLOSE   = 211,
   TRIGGER_FBO_RETEST_ACCEPTED      = 212,
   // Trend pullback triggers
   TRIGGER_TP_MICRO_BREAK           = 310,
   TRIGGER_TP_MOMENTUM_RESUME       = 311,
   TRIGGER_TP_VALUE_RECLAIM         = 312,
   // Mean reversion triggers
   TRIGGER_MR_DEVIATION_PEAK        = 410,
   TRIGGER_MR_RETURN_START          = 411
};

//+------------------------------------------------------------------+
//| Rejection Codes                                                   |
//+------------------------------------------------------------------+
enum ENUM_REJECTION_CODE
{
   REJECT_NONE                      = 0,
   REJECT_SPREAD_TOO_HIGH           = 1,
   REJECT_STALE_QUOTE               = 2,
   REJECT_SESSION_INVALID           = 3,
   REJECT_EVENT_LOCKOUT             = 4,
   REJECT_REGIME_INELIGIBLE         = 5,
   REJECT_VOLATILITY_UNSAFE         = 6,
   REJECT_LIQUIDITY_UNSAFE          = 7,
   REJECT_RISK_LIMIT                = 8,
   REJECT_DAILY_LOSS_LOCK           = 9,
   REJECT_WEEKLY_LOSS_LOCK          = 10,
   REJECT_DRAWDOWN_LOCK             = 11,
   REJECT_KILL_SWITCH_ACTIVE        = 12,
   REJECT_DUPLICATE_SIGNAL          = 13,
   REJECT_CONFLICTING_SIGNAL        = 14,
   REJECT_COOLDOWN_ACTIVE           = 15,
   REJECT_STRATEGY_DISABLED         = 16,
   REJECT_STRATEGY_LIMIT            = 17,
   REJECT_MARGIN_INSUFFICIENT       = 18,
   REJECT_INVALID_STOP              = 19,
   REJECT_INVALID_VOLUME            = 20,
   REJECT_ENTRY_DISPLACED           = 21,
   REJECT_ARBITRATION_LOST          = 22,
   REJECT_NO_SETUP                  = 23,
   REJECT_NO_TRIGGER                = 24,
   REJECT_EXPOSURE_LIMIT            = 25,
   REJECT_RECONCILIATION_ACTIVE     = 26,
   REJECT_SYMBOL_DISABLED           = 27,
   REJECT_SELF_TEST_FAILED          = 28,
   REJECT_MAX_RETRIES               = 29,
   REJECT_ORDER_FAILED              = 30
};

//+------------------------------------------------------------------+
//| Strategy IDs                                                      |
//+------------------------------------------------------------------+
#define STRATEGY_ID_BREAKOUT        "BO"
#define STRATEGY_ID_FAILED_BREAKOUT "FBO"
#define STRATEGY_ID_TREND_PULLBACK  "TP"
#define STRATEGY_ID_MEAN_REVERSION  "MR"

#endif // QB_ENUMS_MQH
