//+------------------------------------------------------------------+
//|                                           QuantBeast/Constants.mqh |
//|                          XAUUSD Quant Beast EA - Global Constants |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_CONSTANTS_MQH
#define QB_CONSTANTS_MQH

//+------------------------------------------------------------------+
//| EA Identity                                                       |
//+------------------------------------------------------------------+
#define QB_EA_NAME           "QuantBeast"
#define QB_VERSION           "1.00"
#define QB_VERSION_MAJOR     1
#define QB_VERSION_MINOR     0
#define QB_MAGIC_BASE        20260701  // Base magic: YYYYMMDD format

//+------------------------------------------------------------------+
//| Symbol Recognition                                                |
//+------------------------------------------------------------------+
// Primary symbol patterns (case-insensitive matching used)
#define QB_PRIMARY_SYMBOL_XAUUSD  "XAUUSD"
#define QB_PRIMARY_SYMBOL_GOLD    "GOLD"

//+------------------------------------------------------------------+
//| Magic Number Scheme                                               |
//+------------------------------------------------------------------+
// Magic = QB_MAGIC_BASE + (strategy_index * 100)
// BO=0, FBO=1, TP=2, MR=3
#define QB_MAGIC_BO    (QB_MAGIC_BASE + 0)
#define QB_MAGIC_FBO   (QB_MAGIC_BASE + 100)
#define QB_MAGIC_TP    (QB_MAGIC_BASE + 200)
#define QB_MAGIC_MR    (QB_MAGIC_BASE + 300)

//+------------------------------------------------------------------+
//| Default Timeframe Indices                                         |
//+------------------------------------------------------------------+
#define QB_TF_PRIMARY   PERIOD_M5     // Default primary execution TF
#define QB_TF_SHORT     PERIOD_M1     // Short-term reference
#define QB_TF_MEDIUM    PERIOD_M15    // Medium-term
#define QB_TF_LONG      PERIOD_H1     // Long-term
#define QB_TF_HTF       PERIOD_H4     // Higher timeframe
#define QB_TF_DAILY     PERIOD_D1     // Daily

//+------------------------------------------------------------------+
//| Buffer Sizes                                                      |
//+------------------------------------------------------------------+
#define QB_MAX_BARS           2000     // Max bars to cache per TF
#define QB_MIN_BARS_REQUIRED  100      // Minimum bars needed to start
#define QB_BAR_WARMUP         50       // Warmup bars before trading

//+------------------------------------------------------------------+
//| Magic String Prefix                                               |
//+------------------------------------------------------------------+
#define QB_COMMENT_PREFIX     "QB"

//+------------------------------------------------------------------+
//| File Paths                                                        |
//+------------------------------------------------------------------+
#define QB_LOG_DIR            "QuantBeast\\"
#define QB_SIGNAL_LOG          "SignalJournal.csv"
#define QB_ORDER_LOG           "OrderJournal.csv"
#define QB_TRADE_LOG           "TradeJournal.csv"
#define QB_STATE_FILE          "QB_State.bin"
#define QB_PERF_LOG            "Performance.csv"
#define QB_COUNTERFACTUAL_LOG  "CounterfactualJournal.csv"
#define QB_TP_OUTCOME_LOG      "TPOutcomeJournal.csv"
// Flat key=value text, not JSON -- MQL5 has no built-in JSON parser and the
// schema is a fixed handful of scalar fields, so a hand-rolled parser would
// be unjustified complexity. See QBDeploymentLeaseValid() for the reader.
#define QB_DEPLOYMENT_LEASE_FILE "DeploymentLease.cfg"

//+------------------------------------------------------------------+
//| Price/Volume Constants                                            |
//+------------------------------------------------------------------+
#define QB_PRICE_INVALID       -1.0
#define QB_VOLUME_INVALID      -1.0
#define QB_SPREAD_UNSAFE_DEFAULT  50.0   // Default max spread in points
#define QB_STALE_QUOTE_MS_DEFAULT  5000  // Default stale quote threshold ms

//+------------------------------------------------------------------+
//| Strategy Indices                                                  |
//+------------------------------------------------------------------+
#define QB_STRAT_IDX_BO    0
#define QB_STRAT_IDX_FBO   1
#define QB_STRAT_IDX_TP    2
#define QB_STRAT_IDX_MR    3
#define QB_STRAT_IDX_TPV2  4
#define QB_STRAT_COUNT     5

//+------------------------------------------------------------------+
//| Tick Size Multipliers                                             |
//+------------------------------------------------------------------+
#define QB_TICK_MULT_ENTRY   10       // Entry price must be multiple of N ticks
#define QB_TICK_MULT_STOP    10       // Stop distance must be multiple of N ticks

//+------------------------------------------------------------------+
//| Pi and Math                                                       |
//+------------------------------------------------------------------+
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define QB_EPSILON  0.00000001

#endif // QB_CONSTANTS_MQH
