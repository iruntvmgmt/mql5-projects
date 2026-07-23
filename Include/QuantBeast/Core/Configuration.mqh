//+------------------------------------------------------------------+
//|                                        QuantBeast/Configuration.mqh |
//|                          XAUUSD Quant Beast EA - Input Parameters |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_CONFIGURATION_MQH
#define QB_CONFIGURATION_MQH

#include "Enums.mqh"
#include "Constants.mqh"

//+------------------------------------------------------------------+
//| === GROUP: General ===                                            |
//+------------------------------------------------------------------+
input group "══════════ General ══════════"
input ENUM_QB_MODE InpMode = QB_MODE_SHADOW;  // Operating Mode: Diagnostic|Shadow|Conservative Live|Challenge Live
input bool     InpAcknowledgeLiveBrokerRisk = false; // Acknowledge Live Broker Risk: Must be TRUE before Conservative/Challenge broker transmission
input bool     InpAcknowledgeChallengeRisk = false; // Acknowledge Challenge Risk: Must be TRUE to enable Challenge Mode

//+------------------------------------------------------------------+
//| === GROUP: Strategy-Aware Demo/Live Allowlist ===                  |
//| Per-strategy broker-submission authorization, separate from        |
//| InpXX_Enabled. A strategy only reaches the broker in Conservative/ |
//| Challenge modes if ALL SIX allowlist conditions hold:              |
//|   StrategyEnabled AND StrategyMechanicallyReady (code-level, not   |
//|   operator-settable -- see QBStrategyMechanicallyReady in          |
//|   QuantBeastEA.mq5) AND StrategyDemoAuthorized (this group) AND    |
//|   ModeAllowsStrategy (only the Conservative Demo tier -- Live mode |
//|   connected to a verified DEMO account -- is currently sanctioned) |
//|   AND GlobalLiveRiskAcknowledged (InpAcknowledgeLiveBrokerRisk)    |
//|   AND BrokerPathAllowed (account/mode combination classifiable).  |
//| TP V1 has no authorization input: it is permanently excluded from  |
//| broker submission at the code level regardless of any flag here.   |
//+------------------------------------------------------------------+
input group "══════════ Strategy-Aware Demo/Live Allowlist ══════════"
input bool     InpBO_DemoAuthorized   = false; // BO Demo/Live Authorized: separate from InpBO_Enabled, fail-closed default
input bool     InpFBO_DemoAuthorized  = true;  // FBO Demo/Live Authorized: preserves the pre-existing FBO-only live candidate default
input bool     InpMR_DemoAuthorized   = false; // MR Demo/Live Authorized: separate from InpMR_Enabled, fail-closed default
input bool     InpTPV2_DemoAuthorized = false; // TP V2 Demo/Live Authorized: separate from InpTPV2_Enabled, fail-closed default

//+------------------------------------------------------------------+
//| === GROUP: Symbol and Broker ===                                  |
//+------------------------------------------------------------------+
input group "══════════ Symbol and Broker ══════════"
input string   InpPrimarySymbol = "";         // Primary Symbol Override: Leave empty to use chart symbol
input int      InpBrokerUTCOffsetHours = 2;   // Broker Server UTC Offset (hours): For session time calculation
input bool     InpBrokerIsDST = true;         // Broker Observes DST: May affect session times seasonally
input int      InpMaxSpreadPoints = 50;       // Maximum Spread (points): Block entries above this spread
input int      InpStaleQuoteMs = 5000;        // Stale Quote Threshold (ms): Max quote age before blocking

//+------------------------------------------------------------------+
//| === GROUP: Timeframes ===                                         |
//+------------------------------------------------------------------+
input group "══════════ Timeframes ══════════"
input ENUM_TIMEFRAMES InpPrimaryTF = PERIOD_M5;     // Primary Execution Timeframe
input ENUM_TIMEFRAMES InpShortTF   = PERIOD_M1;     // Short-term Reference TF
input ENUM_TIMEFRAMES InpMediumTF  = PERIOD_M15;    // Medium-term Reference TF
input ENUM_TIMEFRAMES InpLongTF    = PERIOD_H1;     // Long-term Reference TF
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H4;     // Higher Timeframe
input ENUM_TIMEFRAMES InpDailyTF   = PERIOD_D1;     // Daily Timeframe

//+------------------------------------------------------------------+
//| === GROUP: Sessions ===                                           |
//+------------------------------------------------------------------+
input group "══════════ Sessions ══════════"
input int InpAsiaStartHour       = 0;   // Asia Start (server hour)
input int InpAsiaStartMin        = 0;   // Asia Start (min)
input int InpLondonPreopenHour   = 6;   // London Pre-open (server hour)
input int InpLondonPreopenMin    = 0;   // London Pre-open (min)
input int InpLondonOpenHour      = 8;   // London Open (server hour)
input int InpLondonOpenMin       = 0;   // London Open (min)
input int InpNYPreopenHour       = 12;  // NY Pre-open (server hour)
input int InpNYPreopenMin        = 0;   // NY Pre-open (min)
input int InpNYOpenHour          = 13;  // NY/COMEX Open (server hour)
input int InpNYOpenMin           = 30;  // NY/COMEX Open (min)
input int InpNYAfternoonHour     = 17;  // NY Afternoon (server hour)
input int InpNYAfternoonMin      = 0;   // NY Afternoon (min)
input int InpRolloverHour        = 22;  // Rollover Start (server hour)
input int InpRolloverMin         = 0;   // Rollover Start (min)
input int InpFridayCloseHour     = 21;  // Friday Close (server hour)
input int InpFridayCloseMin      = 0;   // Friday Close (min)

//+------------------------------------------------------------------+
//| === GROUP: Data Quality ===                                       |
//+------------------------------------------------------------------+
input group "══════════ Data Quality ══════════"
input bool InpRequireDataQuality   = true;  // Require Data Quality Checks
input int  InpMaxPriceJumpPoints   = 200;   // Max Single-Tick Price Jump (points): Triggers warning
input bool InpCheckBarSequence     = true;  // Verify Bar Chronological Order
input int  InpMinBarsRequired      = 100;   // Minimum Bars Required Before Trading
input int  InpBarWarmup            = 50;    // Bar Warmup Count: Bars to skip at start

//+------------------------------------------------------------------+
//| === GROUP: Regime Engine ===                                      |
//+------------------------------------------------------------------+
input group "══════════ Regime Engine ══════════"
input bool   InpRegimeEnabled        = true;    // Enable Regime Detection
input int    InpRegimeATRPeriod      = 14;      // ATR Period
input double InpTrendSlopeThreshold  = 0.3;     // Trend Slope Threshold (normalized)
input double InpStructureImpulseMinDisplacement = 1.0; // Structural impulse minimum displacement (ATR)
input int    InpTrendLookback        = 20;      // Trend Lookback Bars
input double InpCompressionPct       = 20.0;    // Compression Percentile Threshold
input int    InpCompressionLookback  = 50;      // Compression Lookback Bars
input int    InpExpansionMinBars     = 3;       // Min Bars for Expansion Detection
input double InpShockVolMultiplier   = 3.0;     // Vol Shock Multiplier vs Average

//+------------------------------------------------------------------+
//| === GROUP: Breakout Strategy ===                                  |
//+------------------------------------------------------------------+
input group "══════════ Breakout Strategy ══════════"
input bool   InpBO_Enabled           = true;    // Enable Breakout Strategy
input int    InpBO_MinCompressionBars = 5;      // Minimum Compression Duration (bars)
input ENUM_TRIGGER_TYPE InpBO_TriggerMode = TRIGGER_CANDLE_CLOSE_BREAK; // Trigger Mode
input double InpBO_MinDisplacement   = 2.0;     // Min Displacement (ATR multiples) for displacement trigger
input double InpBO_StopATRMultiplier = 1.5;     // Stop ATR Multiplier
input double InpBO_TargetR           = 1.5;     // Target R Multiple
input double InpBO_MinConfidence     = 0.6;     // Minimum Signal Confidence
input bool   InpBO_RequireHTFBias    = true;    // Require HTF Directional Bias
input ENUM_LEVEL_SOURCE InpBO_LevelSource = LEVEL_SRC_RANGE; // Breakout Level Source: Range|PrevDay|Session|OpeningRange|Swing
input ENUM_STOP_MODE   InpBO_StopMode   = STOP_MODE_DEFAULT;   // BO Stop Mode: Default|ATR|Swing|Structural|Sweep
input ENUM_TARGET_MODE InpBO_TargetMode = TARGET_MODE_DEFAULT; // BO Target Mode: Default|FixedR|VWAP|RangeMid|OppBoundary
input double InpBO_MaxSpreadPts      = 40.0;    // Max Spread for Eligibility (points, symbol-scaled -- was hardcoded)

//+------------------------------------------------------------------+
//| === GROUP: Failed Breakout Strategy ===                           |
//+------------------------------------------------------------------+
input group "══════════ Failed Breakout Strategy ══════════"
input bool   InpFBO_Enabled          = true;    // Enable Failed Breakout Strategy
input double InpFBO_MinPenetration   = 3.0;     // Min Penetration Beyond Level (points)
input int    InpFBO_MaxBarsBeyond    = 3;       // Max Bars Beyond Level Before Invalid
input double InpFBO_ReclaimThreshold = 0.3;     // Reclaim Threshold (ATR multiple back)
input ENUM_TRIGGER_TYPE InpFBO_TriggerMode = TRIGGER_CANDLE_CLOSE_BREAK; // Trigger Mode
input double InpFBO_StopBeyondSweep  = 1.0;     // Stop Beyond Sweep Extreme (ATR multiple)
input double InpFBO_TargetMidR       = 1.0;     // Target: Range Midpoint (R multiple)
input double InpFBO_TargetVWAPR      = 1.5;     // Target: VWAP (R multiple)
input double InpFBO_MinConfidence    = 0.55;    // Minimum Signal Confidence
input ENUM_STOP_MODE   InpFBO_StopMode   = STOP_MODE_DEFAULT;   // FBO Stop Mode: Default|ATR|Swing|Structural|Sweep
input ENUM_TARGET_MODE InpFBO_TargetMode = TARGET_MODE_DEFAULT; // FBO Target Mode: Default|FixedR|VWAP|RangeMid|OppBoundary
input double InpFBO_MaxSpreadPts     = 40.0;    // Max Spread for Eligibility (points, symbol-scaled -- was hardcoded)

//+------------------------------------------------------------------+
//| === GROUP: Trend Pullback Strategy ===                            |
//+------------------------------------------------------------------+
input group "══════════ Trend Pullback Strategy ══════════"
input bool   InpTP_Enabled            = true;   // Enable Trend Pullback Strategy
input double InpTP_MinDirEfficiency   = 0.4;    // Minimum Directional Efficiency
input int    InpTP_MinTrendPersistence = 5;     // Minimum Trend Persistence (bars)
input bool   InpTP_RequireHTFAgreement = true;  // Require HTF Agreement
input double InpTP_MaxPullbackDepth   = 0.618;  // Max Pullback Depth (fib retracement of impulse)
input int    InpTP_MaxPullbackBars    = 20;     // Max Pullback Duration (bars)
input double InpTP_TargetExtensionR   = 1.618;  // Target: Impulse Extension (R multiple)
input double InpTP_StopBeyondStruct   = 0.5;    // Stop Beyond Structure (ATR multiple)
input ENUM_TRIGGER_TYPE InpTP_TriggerMode = TRIGGER_CANDLE_CLOSE_BREAK; // Trigger Mode
input double InpTP_MinConfidence      = 0.55;   // Minimum Signal Confidence
input ENUM_STOP_MODE   InpTP_StopMode   = STOP_MODE_DEFAULT;   // TP Stop Mode: Default|ATR|Swing|Structural|Sweep
input ENUM_TARGET_MODE InpTP_TargetMode = TARGET_MODE_DEFAULT; // TP Target Mode: Default|FixedR|VWAP|RangeMid|OppBoundary
input double InpTP_MaxSpreadPts      = 35.0;    // Max Spread for Eligibility (points, symbol-scaled -- was hardcoded)

//+------------------------------------------------------------------+
//| === GROUP: Trend Pullback V2 (experimental) ===                   |
//| See TestEvidence/production_readiness_tp_v2_20260722/tp_v2_spec/  |
//| InpTPV2_Enabled keeps the lifecycle observing bars (same           |
//| convention as V1's InpTP_Enabled); InpEnableTPV2Experimental is    |
//| the SOLE gate on whether a TRIGGERED episode's signal can ever be  |
//| marked valid and reach arbitration. Default false: zero reachable  |
//| path into signal generation until organic evidence supports it.   |
//+------------------------------------------------------------------+
input group "══════════ Trend Pullback V2 (Experimental) ══════════"
input bool   InpTPV2_Enabled          = true;   // Enable TP V2 Lifecycle Observation
input bool   InpEnableTPV2Experimental = false; // Allow TP V2 to emit valid (tradeable) signals
input ENUM_TPV2_TRIGGER_MODE InpTPV2_TriggerMode = TPV2_TRIGGER_REJECTION_CONFIRM; // Resumption trigger (default per Decision D004)
input double InpTPV2_MinConfidence    = 0.55;   // Minimum Signal Confidence
input ENUM_TARGET_MODE InpTPV2_TargetMode = TARGET_MODE_DEFAULT; // TPV2 Target Mode: Default|FixedR|VWAP|RangeMid|OppBoundary
input double InpTPV2_MaxSpreadPts    = 35.0;    // Max Spread for Eligibility (points)

//+------------------------------------------------------------------+
//| === GROUP: Mean Reversion Strategy ===                            |
//+------------------------------------------------------------------+
input group "══════════ Mean Reversion Strategy ══════════"
input bool   InpMR_Enabled            = true;   // Enable Mean Reversion Strategy
input ENUM_TRIGGER_TYPE InpMR_TriggerMode = TRIGGER_CANDLE_CLOSE_BREAK; // Entry confirmation mode
input double InpMR_MaxTrendStrength   = 0.25;   // Max Trend Strength for Eligibility
input double InpMR_MinDeviationSD     = 1.5;    // Minimum Deviation from VWAP (SD)
input double InpMR_MinRejectionWick   = 0.3;    // Minimum Rejection Wick (ATR multiple)
input double InpMR_TargetVWAPR        = 1.0;    // Target: Return to VWAP (R)
input double InpMR_EmergencyStopR     = 1.0;    // Emergency Stop (R from entry)
input double InpMR_MinConfidence      = 0.5;    // Minimum Signal Confidence
input ENUM_STOP_MODE   InpMR_StopMode   = STOP_MODE_DEFAULT;   // MR Stop Mode: Default|ATR|Swing|Structural|Sweep
input ENUM_TARGET_MODE InpMR_TargetMode = TARGET_MODE_DEFAULT; // MR Target Mode: Default|FixedR|VWAP|RangeMid|OppBoundary
input double InpMR_MaxSpreadPts      = 30.0;    // Max Spread for Eligibility (points, symbol-scaled -- was hardcoded)

//+------------------------------------------------------------------+
//| === GROUP: Signal Arbitration ===                                 |
//+------------------------------------------------------------------+
input group "══════════ Signal Arbitration ══════════"
input ENUM_ARBITRATION_METHOD InpArbitrationMethod = ARBITRATION_HIGHEST_SCORE; // Arbitration Method
input ENUM_ALLOCATION_MODE InpAllocationMode = ALLOC_EQUAL; // Risk Allocation Mode: Equal|Confidence|Performance
input int  InpCooldownSeconds          = 300;   // Signal Cooldown (seconds): Min time between signals
input int  InpDuplicateWindowSeconds   = 600;   // Duplicate Prevention Window (seconds)
input bool InpAllowOppositeSignals     = false; // Allow Simultaneous Long and Short
input bool InpAllowSameDirectionStack  = false; // Allow Multiple Same-Direction Entries

//+------------------------------------------------------------------+
//| === GROUP: Position Sizing ===                                    |
//+------------------------------------------------------------------+
input group "══════════ Position Sizing ══════════"
input ENUM_MODE_LOTS InpLotMode       = LOTS_MODE_RISK_PCT; // Lot Sizing Mode: Fixed|Fixed Risk Currency|Risk %|Volatility Adjusted
input double InpFixedLots             = 0.01;  // Fixed Lot Size (if mode=Fixed)
input double InpFixedRiskCurrency     = 20.0;  // Fixed Risk Currency (if mode=Fixed Risk)
input double InpRiskPercent           = 1.0;   // Risk Percent Per Trade (if mode=Risk %)
input double InpVolAdjRiskTarget      = 1.0;   // Volatility-Adjusted Risk Target (ATR multiples)
input double InpMaxLotSize            = 1.0;   // Maximum Lot Size
input double InpMinLotSize            = 0.01;  // Minimum Lot Size (override if broker min is lower)
input double InpSlippageAllowancePts  = 10.0;  // Slippage Allowance (points)
input double InpCommissionEstimate    = 7.0;   // Commission Estimate (per lot per round-turn, account currency)

//+------------------------------------------------------------------+
//| === GROUP: Trade Risk ===                                         |
//+------------------------------------------------------------------+
input group "══════════ Trade Risk ══════════"
input double InpMaxRiskPerTrade       = 2.0;   // Max Risk Per Trade (%)
input double InpMinRewardRisk         = 1.0;   // Minimum Reward:Risk Ratio
input int    InpMinStopPoints         = 50;    // Minimum Stop Distance (points)
input int    InpMaxStopPoints         = 1000;  // Maximum Stop Distance (points)
input int    InpMaxHoldingMinutes     = 1440;  // Max Holding Time (minutes, 0=unlimited)
input int    InpMaxPendingMinutes     = 60;    // Max Pending Order Duration (minutes)

//+------------------------------------------------------------------+
//| === GROUP: Account Risk ===                                       |
//+------------------------------------------------------------------+
input group "══════════ Account Risk ══════════"
input double InpDailyLossLimitPct     = 5.0;   // Daily Loss Limit (% of equity)
input double InpWeeklyLossLimitPct    = 10.0;  // Weekly Loss Limit (% of equity)
input double InpMaxDrawdownPct        = 20.0;  // Max Total Drawdown (% from high-water mark)
input int    InpMaxConsecLosses       = 5;     // Max Consecutive Losses Before Lock
input double InpMinMarginLevelPct     = 200.0; // Min Margin Level (%)
input double InpEmergencyEquityFloor  = 50.0;  // Emergency Equity Floor (account currency)
input int    InpMaxPositions          = 3;     // Maximum Concurrent Positions
input int    InpMaxPendingOrders      = 2;     // Maximum Pending Orders
input double InpMaxTotalExposureLots  = 2.0;   // Max Total Lot Exposure

//+------------------------------------------------------------------+
//| === GROUP: Challenge Mode ===                                     |
//+------------------------------------------------------------------+
input group "══════════ Challenge Mode ══════════"
input double InpChal_Stage0_Target    = 130.0;  // Stage 0 Target Equity
input double InpChal_Stage1_Target    = 200.0;  // Stage 1 Target Equity
input double InpChal_Stage2_Target    = 350.0;  // Stage 2 Target Equity
input double InpChal_Stage3_Target    = 600.0;  // Stage 3 Target Equity
input double InpChal_Stage4_Target    = 1000.0; // Stage 4 Target Equity
input double InpChal_Stage0_RiskPct   = 3.0;    // Stage 0 Risk %
input double InpChal_Stage1_RiskPct   = 2.5;    // Stage 1 Risk %
input double InpChal_Stage2_RiskPct   = 2.0;    // Stage 2 Risk %
input double InpChal_Stage3_RiskPct   = 1.5;    // Stage 3 Risk %
input double InpChal_Stage4_RiskPct   = 1.0;    // Stage 4 Risk %
input double InpChal_MaxStageDD       = 30.0;   // Max Stage Drawdown (%)
input int    InpChal_MaxAttempts      = 3;      // Max Attempts Per Stage
input double InpChal_ProfitLockPct    = 50.0;   // Profit Lock (% of gain locked)
input bool   InpChal_AllowPyramiding  = false;  // Allow Pyramiding (winning positions only)

//+------------------------------------------------------------------+
//| === GROUP: Execution ===                                          |
//+------------------------------------------------------------------+
input group "══════════ Execution ══════════"
input int    InpMaxRetries            = 2;      // Max Order Retries
input int    InpMaxConsecutiveBrokerFailures = 3; // Entry kill after failed submission cycles
input int    InpRetryDelayMs          = 500;    // Retry Delay (ms)
input int    InpOrderExpirySeconds    = 60;     // Pending Order Expiry (seconds)
input bool   InpUseMarketOrders       = true;   // Allow Market Orders
input bool   InpUseStopOrders         = true;   // Allow Stop Orders
input bool   InpUseLimitOrders        = false;  // Allow Limit Orders
input int    InpFillMode              = 0;      // Preferred Fill Mode: 0=Auto, 1=IOC, 2=FOK, 3=Return

//+------------------------------------------------------------------+
//| === GROUP: Position Management ===                                |
//+------------------------------------------------------------------+
input group "══════════ Position Management ══════════"
input bool   InpEnableBreakeven       = true;    // Enable Breakeven Stops
input double InpBreakevenTriggerR     = 0.5;     // Breakeven Trigger (R multiple)
input double InpBreakevenPlusPips     = 3.0;     // Breakeven Plus (points above entry)
input bool   InpEnablePartialClose    = true;    // Enable Partial Close
input double InpPartialClosePct       = 50.0;    // Partial Close (% of position)
input double InpPartialCloseTriggerR  = 0.7;     // Partial Close Trigger (R multiple) -- data-derived from measured MFE distribution (was 1.0, only reached by 22% of trades; 0.7 ~ p60)
input bool   InpEnableATRTrail        = true;    // Enable ATR Trailing Stop
input double InpATRTrailMultiplier    = 2.0;     // ATR Trail Multiplier
input double InpATRTrailStartR        = 0.7;     // ATR Trail Start (R multiple) -- data-derived from measured MFE distribution (was 1.0, only reached by 22% of trades; 0.7 ~ p60)
input bool   InpEnableTimeStop        = false;   // Enable Time Stop
input int    InpTimeStopMinutes       = 240;     // Time Stop (minutes)
input bool   InpEnableMomentumExit    = false;   // Enable Momentum-Failure Exit
input int    InpMomentumExitMinutes   = 60;      // Momentum-Failure Window (minutes)
input double InpMomentumExitMinR      = 0.0;     // Momentum-Failure Min R (exit if below after window)
input bool   InpEnableRegimeExit      = false;   // Enable Regime-Deterioration Exit
input bool   InpCloseBeforeSessionEnd = false;   // Close Before Session End
input bool   InpCloseBeforeRollover   = false;   // Close Before Rollover

//+------------------------------------------------------------------+
//| === GROUP: News Lockout ===                                       |
//+------------------------------------------------------------------+
input group "══════════ News Lockout ══════════"
input bool   InpNewsEnabled           = true;    // Enable News Lockout
input int    InpPreNewsLockoutMinutes  = 15;     // Pre-News Lockout (minutes)
input int    InpPostNewsLockoutMinutes = 15;     // Post-News Lockout (minutes)
input string InpNewsTimes             = "";      // Manual News Times (comma-sep YYYY.MM.DD HH:MM)

//+------------------------------------------------------------------+
//| === GROUP: Persistence ===                                        |
//+------------------------------------------------------------------+
input group "══════════ Persistence ══════════"
input bool   InpPersistState          = true;    // Persist State to Disk
input bool   InpUseGlobalVars         = true;    // Use Terminal Global Variables

//+------------------------------------------------------------------+
//| === GROUP: Logging ===                                            |
//+------------------------------------------------------------------+
input group "══════════ Logging ══════════"
input bool   InpEnableSignalJournal   = true;    // Enable Signal Journal
input bool   InpEnableCounterfactual  = false;   // Enable Counterfactual Journal (rejected-signal hypotheticals)
input bool   InpEnableTPOutcomeJournal = true;   // Enable TP Resume-Candidate Outcome Journal (observation-only)
input bool   InpEnableOrderJournal    = true;    // Enable Order Journal
input bool   InpEnableTradeJournal    = true;    // Enable Trade Journal
input bool   InpJournalTesterPrefix  = false;   // Route journals to Tester\ subdirectory (set true in Strategy Tester)
input bool   InpEnableDebugLogging    = false;   // Enable Debug Logging

//+------------------------------------------------------------------+
//| === GROUP: Dashboard ===                                          |
//+------------------------------------------------------------------+
input group "══════════ Dashboard ══════════"
input bool   InpDashboardEnabled      = true;    // Enable On-Chart Dashboard
input int    InpDashboardX            = 10;      // Dashboard X Position
input int    InpDashboardY            = 20;      // Dashboard Y Position
input int    InpDashboardFontSize     = 8;       // Dashboard Font Size
input color  InpDashboardColor        = clrWhite; // Dashboard Text Color
input bool   InpShowChartObjects      = true;    // Show Chart Objects (levels, etc.)

//+------------------------------------------------------------------+
//| === GROUP: Alerts ===                                             |
//+------------------------------------------------------------------+
input group "══════════ Alerts ══════════"
input bool InpAlertSignalAccepted     = false;   // Alert on Signal Accepted
input bool InpAlertSignalRejected     = false;   // Alert on Signal Rejected
input bool InpAlertOrderFilled        = false;   // Alert on Order Filled
input bool InpAlertOrderRejected      = true;    // Alert on Order Rejected
input bool InpAlertPositionClosed     = false;   // Alert on Position Closed
input bool InpAlertKillSwitch         = true;    // Alert on Kill Switch
input bool InpAlertReconFailure       = true;    // Alert on Reconciliation Failure
input bool InpAlertUnprotectedPos     = true;    // Alert on Unprotected Position
input bool InpSendPushNotifications   = false;   // Send Push Notifications

//+------------------------------------------------------------------+
//| === GROUP: Testing ===                                            |
//+------------------------------------------------------------------+
input group "══════════ Testing ══════════"
input bool InpSelfTestOnInit          = true;    // Run Self-Tests on Init
input bool InpLogSelfTestDetails      = true;    // Log Self-Test Details

//+------------------------------------------------------------------+
//| === GROUP: Unknown Positions ===                                  |
//+------------------------------------------------------------------+
input group "══════════ Unknown Positions ══════════"
input ENUM_UNKNOWN_POS_POLICY InpUnknownPosPolicy = UNKNOWN_REPORT; // Unknown Position Policy: Ignore|Report|Quarantine|Flatten

#endif // QB_CONFIGURATION_MQH
