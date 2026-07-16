//+------------------------------------------------------------------+
//|                                                QuantBeast/Types.mqh |
//|                          XAUUSD Quant Beast EA - Type Definitions |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TYPES_MQH
#define QB_TYPES_MQH

#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Market Snapshot - current tick/quote state                        |
//+------------------------------------------------------------------+
struct MarketSnapshot
{
   datetime time;            // Server time of snapshot
   double   bid;             // Current bid
   double   ask;             // Current ask
   double   mid;             // (bid+ask)/2
   double   spread_points;   // Spread in symbol points
   double   spread_price;    // Spread in account currency terms
   long     tick_volume;     // Tick volume from last tick
   double   real_volume;     // Real volume (may be 0 on OTC)
   bool     is_fresh;        // Quote is recent
   bool     is_tradeable;    // Symbol allows trading
};

//+------------------------------------------------------------------+
//| Feature Snapshot - all calculated features at a point in time      |
//+------------------------------------------------------------------+
struct FeatureSnapshot
{
   datetime calc_time;       // When features were calculated

   // Volatility features
   double atr;               // Average True Range (price units)
   double atr_points;        // ATR in symbol points
   double realized_vol;      // Realized standard deviation
   double short_atr;         // Short-term ATR
   double long_atr;          // Long-term ATR
   double atr_ratio;         // Short/Long ATR ratio
   double range_percentile;  // Current range vs lookback percentile
   double bb_bandwidth;      // Bollinger bandwidth
   int    compression_bars;  // Bars spent in compression
   bool   is_compressing;    // Compression detected
   bool   is_expanding;      // Expansion detected
   double vol_of_vol;        // Volatility of volatility
   bool   abnormal_candle;   // Abnormal candle detected

   // Trend features
   double trend_slope;       // Regression slope
   double slope_norm;        // Slope normalized by ATR
   double dir_efficiency;    // Directional efficiency ratio
   double fast_ma;           // Fast MA value
   double slow_ma;           // Slow MA value
   bool   fast_slow_aligned; // Fast/slow trend agreement
   bool   htf_aligned;       // Higher-timeframe agreement
   double htf_slope;         // Directional HTF slope (positive=up)
   int    trend_persistence; // Bars trend has persisted
   double trend_accel;       // Trend acceleration
   double dist_from_equil;   // Distance from equilibrium
   double trend_maturity;    // Trend maturity estimate

   // Structural features
   double swing_high;        // Confirmed swing high
   double swing_low;         // Confirmed swing low
   int    swing_high_bars;   // Bars since swing high
   int    swing_low_bars;    // Bars since swing low
   bool   higher_high;       // Recent higher high
   bool   higher_low;        // Recent higher low
   bool   lower_high;        // Recent lower high
   bool   lower_low;         // Recent lower low
   double current_range_high; // Current range high
   double current_range_low;  // Current range low
   double closed_open;       // Just-completed primary bar open
   double closed_high;       // Just-completed primary bar high
   double closed_low;        // Just-completed primary bar low
   double closed_close;      // Just-completed primary bar close
   double prev_day_high;     // Previous day high
   double prev_day_low;      // Previous day low
   double session_high;      // Current session high
   double session_low;       // Current session low
   double or_high;           // Opening range high
   double or_low;            // Opening range low
   double breakout_dist;     // Distance beyond nearest breakout level
   int    bars_beyond_level; // Bars spent beyond a broken level
   bool   failed_breakout;   // Failed breakout detected
   bool   reclaim_detected;  // Level reclaim detected
   bool   failed_breakout_up;   // Upside sweep reclaimed downward
   bool   failed_breakout_down; // Downside sweep reclaimed upward
   double reclaim_level;        // Objective level reclaimed
   double sweep_extreme;        // Extreme of failed auction
   double rejection_wick;    // Rejection wick size
   double rejection_wick_upper; // Upper wick normalized by ATR
   double rejection_wick_lower; // Lower wick normalized by ATR
   double displacement;      // Displacement measurement

   // Auction/equilibrium features
   double vwap;              // Session VWAP
   double rolling_vwap;      // Rolling VWAP
   double vwap_sd;           // Weighted standard deviation around VWAP
   double range_midpoint;    // Range midpoint
   double norm_dist_vwap;    // Normalized distance from VWAP
   double sd_dist;           // Standard deviation distance from VWAP
   bool   returning_to_value; // Return to value area detected

   // Liquidity/execution features
   double current_spread;    // Current spread in points
   double avg_spread;        // Rolling average spread
   double spread_percentile; // Spread percentile
   double tick_freq;         // Tick frequency estimate
   int    quote_age_ms;      // Quote age in milliseconds
   bool   quote_stable;      // Quote stability flag
   double exp_exec_cost;     // Expected execution cost in points
   double max_entry_displacement; // Max acceptable entry displacement
   bool   stale_market;      // Stale market detected
};

//+------------------------------------------------------------------+
//| Regime State - combined market classification                     |
//+------------------------------------------------------------------+
struct RegimeState
{
   ENUM_TREND_REGIME      trend;
   ENUM_VOLATILITY_REGIME volatility;
   ENUM_LIQUIDITY_REGIME  liquidity;
   ENUM_STRUCTURE_REGIME  structure;
   ENUM_SESSION_TYPE      session;
   ENUM_EVENT_STATE       event_state;

   double trend_score;       // 0.0-1.0 trend confidence
   double volatility_score;  // 0.0-1.0 volatility classification confidence
   double liquidity_score;   // 0.0-1.0 liquidity assessment confidence
   double structure_score;   // 0.0-1.0 structure classification confidence
   double confidence;        // Overall regime confidence
};

//+------------------------------------------------------------------+
//| Strategy Signal - unified signal from any strategy                |
//+------------------------------------------------------------------+
struct StrategySignal
{
   bool     valid;              // Signal is valid for consideration
   string   strategy_id;        // STRATEGY_ID_* constant
   ENUM_ORDER_TYPE direction;   // ORDER_TYPE_BUY or ORDER_TYPE_SELL

   datetime signal_time;        // When signal was generated
   double   proposed_entry;     // Proposed entry price
   double   proposed_stop;      // Proposed stop loss
   double   proposed_target;    // Proposed take profit

   double   confidence;         // 0.0-1.0 signal confidence
   double   expected_reward_r;  // Expected reward in R multiples
   double   expected_cost_points; // Expected transaction cost in points
   double   invalidation_price; // Price that invalidates the signal

   int      setup_code;         // ENUM_SETUP_CODE
   int      trigger_code;       // ENUM_TRIGGER_CODE
   int      rejection_code;     // ENUM_REJECTION_CODE

   string   reason;             // Human-readable signal reason
};

//+------------------------------------------------------------------+
//| Order Intent - approved order to be transmitted                   |
//+------------------------------------------------------------------+
struct OrderIntent
{
   bool     approved;           // Order passed all checks
   string   strategy_id;        // Owning strategy
   ulong    signal_id;          // Unique signal identifier

   ENUM_ORDER_TYPE order_type;  // Market, stop, limit
   double   volume;             // Lot size
   double   requested_price;    // Requested entry price
   double   stop_loss;          // Stop loss price
   double   take_profit;        // Take profit price
   double   max_slippage_points; // Max acceptable slippage

   datetime expiry;             // Pending order expiry
   string   comment;            // Order comment with magic info
};

//+------------------------------------------------------------------+
//| Position Context - tracked state for each EA-owned position       |
//+------------------------------------------------------------------+
struct PositionContext
{
   string   strategy_id;        // Strategy that owns this position
   ulong    signal_id;          // Signal that created this position
   ulong    order_ticket;       // Entry order ticket
   ulong    position_ticket;    // Position ticket in MT5
   ulong    position_identifier;// Stable POSITION_IDENTIFIER / DEAL_POSITION_ID
   ENUM_POSITION_TYPE position_type; // Direction retained after broker close

   double   original_entry;     // Original fill price
   double   original_stop;      // Initial protective stop (never changes)
   double   current_stop;       // Current stop loss
   double   initial_volume;     // Entry volume retained after broker close
   double   original_risk;      // Original risk in account currency
   double   current_risk;       // Current risk in account currency
   double   initial_target;     // Initial take profit
   double   current_r;          // Current R multiple

   double   mfe;                // Maximum favorable excursion
   double   mae;                // Maximum adverse excursion

   ENUM_TREND_REGIME      entry_regime_trend;
   ENUM_VOLATILITY_REGIME entry_regime_vol;
   ENUM_SESSION_TYPE      entry_session;
   double   entry_spread;       // Spread at entry
   double   entry_slippage;     // Realized slippage

   int      scale_in_count;     // Number of scale-in additions
   int      partial_exit_count; // Number of partial exits
   bool     partial_exit_done;  // At least one partial exit done

   ENUM_MANAGEMENT_METHOD mgmt_state; // Current management state
   datetime entry_time;         // Entry timestamp
   datetime last_update;        // Last state update timestamp
};

//+------------------------------------------------------------------+
//| Daily Risk State - persisted daily counters                       |
//+------------------------------------------------------------------+
struct DailyRiskState
{
   datetime date;               // Date this state applies to
   double   starting_equity;    // Equity at start of day
   double   current_equity;     // Current equity
   double   daily_pnl;          // Today's PnL
   double   daily_loss_remaining; // Remaining before daily lock
   int      trades_today;       // Trades executed today
   int      losing_streak;      // Consecutive losing trades
   bool     daily_lock_active;  // Daily loss lock triggered
   bool     weekly_lock_active; // Weekly loss lock triggered
};

//+------------------------------------------------------------------+
//| Challenge State - persisted challenge mode tracking               |
//+------------------------------------------------------------------+
struct ChallengeState
{
   ENUM_CHALLENGE_STAGE stage;   // Current stage
   double   stage_start_equity;  // Equity at stage start
   double   stage_target;        // Target equity for stage completion
   double   stage_drawdown_limit;// Max drawdown from stage peak
   double   stage_peak;          // Peak equity this stage
   double   daily_loss_limit;    // Daily loss limit for current stage
   int      attempts_this_stage; // Attempts at current stage
   int      max_attempts;        // Max attempts allowed
   double   risk_percent;        // Risk per trade this stage
   double   profit_locked;       // Amount locked/protected
   double   max_exposure;        // Max open exposure this stage
   long     cashflow_time_msc;    // Last account-history deal cursor
   ulong    cashflow_ticket;      // Tie-breaker for deals at same millisecond
};

//+------------------------------------------------------------------+
//| Kill Switch State                                                 |
//+------------------------------------------------------------------+
struct KillSwitchState
{
   bool strategy_kill[4];       // Per-strategy kill (BO,FBO,TP,MR)
   bool entry_kill;             // Block all new entries
   bool symbol_kill;            // Block XAUUSD
   bool cancel_all;             // Cancel all pending
   bool flatten_all;            // Close all positions
   bool emergency;              // Emergency mode
   string emergency_reason;     // Reason for emergency
};

//+------------------------------------------------------------------+
//| Execution Record - tracks an order through its lifecycle           |
//+------------------------------------------------------------------+
struct ExecutionRecord
{
   ulong    request_id;         // Internal request ID
   ulong    order_ticket;       // MT5 order ticket
   ulong    deal_ticket;        // Entry deal ticket, if filled
   ulong    position_ticket;    // Resolved broker position ticket, if filled
   ulong    position_identifier;// Stable DEAL_POSITION_ID / POSITION_IDENTIFIER
   ENUM_ORDER_STATE_QB state;   // Current state
   ENUM_ORDER_TYPE order_type;  // Order type
   double   requested_volume;   // Requested lot size
   double   filled_volume;      // Actually filled
   double   requested_price;    // Requested price
   double   fill_price;         // Actual fill price
   double   slippage_points;    // Realized slippage
   double   stop_loss;          // SL at submission
   double   take_profit;        // TP at submission
   int      retry_count;        // Number of retries
   uint     retcode;            // Last broker retcode
   datetime request_time;       // Submission time
   datetime fill_time;          // Fill/acknowledge time
   string   comment;            // Order comment
};

//+------------------------------------------------------------------+
//| Self-Test Result                                                  |
//+------------------------------------------------------------------+
struct SelfTestResult
{
   string   test_name;          // Name of the test
   bool     passed;             // Test passed
   string   detail;             // Detail on pass/fail
   string   error_msg;          // Error message if failed
};

//+------------------------------------------------------------------+
//| Performance Summary                                               |
//+------------------------------------------------------------------+
struct PerformanceSummary
{
   int      total_trades;
   int      winning_trades;
   int      losing_trades;
   double   win_rate;           // 0.0-1.0
   double   avg_winner;         // Average winning trade
   double   avg_loser;          // Average losing trade
   double   expectancy;         // Expected value per trade
   double   profit_factor;      // Gross profit / gross loss
   double   gross_profit;
   double   gross_loss;
   double   net_profit;
   double   max_drawdown;       // Maximum drawdown
   int      consec_wins;        // Max consecutive wins
   int      consec_losses;      // Max consecutive losses
   double   avg_r;              // Average R multiple
};

#endif // QB_TYPES_MQH
