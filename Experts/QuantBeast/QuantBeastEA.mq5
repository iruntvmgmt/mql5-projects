//+------------------------------------------------------------------+
//|                                                  QuantBeastEA.mq5 |
//|                          XAUUSD Quant Beast EA - Main Entry Point |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property description "XAUUSD Quant Beast EA - Multi-Strategy Trading System"
#property description "Focus: XAUUSD | Modes: Diagnostic | Shadow | Live | Challenge"
#property description "Build: 2026-07-15 v1.00"
#property link      "https://github.com/quantbeast"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include <QuantBeast/Core/Enums.mqh>
#include <QuantBeast/Core/Types.mqh>
#include <QuantBeast/Core/Constants.mqh>
#include <QuantBeast/Core/Configuration.mqh>
#include <QuantBeast/Core/TimeUtils.mqh>
#include <QuantBeast/Core/MathUtils.mqh>
#include <QuantBeast/Core/Diagnostics.mqh>
#include <QuantBeast/Core/StateStore.mqh>
#include <QuantBeast/Data/MarketData.mqh>
#include <QuantBeast/Data/BarCache.mqh>
#include <QuantBeast/Data/TickState.mqh>
#include <QuantBeast/Data/SessionEngine.mqh>
#include <QuantBeast/Data/DataQuality.mqh>
#include <QuantBeast/Data/FeatureEngine.mqh>
#include <QuantBeast/Data/NewsInterface.mqh>
#include <QuantBeast/Regime/RegimeEngine.mqh>
#include <QuantBeast/Strategies/StrategyBase.mqh>
#include <QuantBeast/Strategies/BreakoutEngine.mqh>
#include <QuantBeast/Strategies/FailedBreakoutEngine.mqh>
#include <QuantBeast/Strategies/TrendPullbackEngine.mqh>
#include <QuantBeast/Strategies/MeanReversionEngine.mqh>
#include <QuantBeast/Portfolio/SignalArbitrator.mqh>
#include <QuantBeast/Risk/PositionSizer.mqh>
#include <QuantBeast/Risk/RiskEngine.mqh>
#include <QuantBeast/Risk/ChallengeMode.mqh>
#include <QuantBeast/Risk/KillSwitch.mqh>
#include <QuantBeast/Execution/BrokerAdapter.mqh>
#include <QuantBeast/Execution/PositionManager.mqh>
#include <QuantBeast/Execution/TransactionState.mqh>
#include <QuantBeast/Execution/ShadowPortfolio.mqh>
#include <QuantBeast/Analytics/TradeJournal.mqh>
#include <QuantBeast/UI/Dashboard.mqh>
#include <QuantBeast/UI/Alerts.mqh>
#include <QuantBeast/Testing/SafetyTests.mqh>

//+------------------------------------------------------------------+
//| Global Objects                                                    |
//+------------------------------------------------------------------+
// Core
CSymbolAdapter        g_Adapter;
CMarketSnapshotFactory g_SnapFactory(g_Adapter);
CTickState            g_TickState;
CBarCache             g_BarCache;
CSessionEngine        g_SessionEngine;
CDataQualityChecker   g_DataQuality;
CFeatureEngine        g_FeatureEngine;
CNewsInterface        g_NewsInterface;
CRegimeEngine         g_RegimeEngine;

// Strategies
CBreakoutEngine        g_StrategyBO;
CFailedBreakoutEngine  g_StrategyFBO;
CTrendPullbackEngine   g_StrategyTP;
CMeanReversionEngine   g_StrategyMR;
CStrategyBase*         g_Strategies[QB_STRAT_COUNT];

// Portfolio & Risk
CSignalArbitrator     g_Arbitrator;
CPositionSizer        g_Sizer;
CRiskEngine           g_RiskEngine;
CChallengeMode        g_Challenge;
CKillSwitch           g_KillSwitch;

// Execution
CBrokerAdapter        g_Broker;
CPositionManager      g_PosManager;
CShadowPortfolio      g_Shadow;

// Analytics & UI
CTradeJournal         g_Journal;
CDashboard            g_Dashboard;
CAlerts               g_Alerts;

//+------------------------------------------------------------------+
//| State Variables                                                   |
//+------------------------------------------------------------------+
datetime   g_LastBarTime = 0;
datetime   g_LastTickTime = 0;
bool       g_StartupReconciled = false;
bool       g_StateStoreCompatible = true;
string     g_LastRejection = "";
string     g_LastSignal = "";
int        g_SelfTestPassed = 0;
int        g_SelfTestFailed = 0;
int        g_StrategyTradesToday[QB_STRAT_COUNT];
datetime   g_StrategyTradeDay = 0;
MarketSnapshot g_CurrentSnap;
FeatureSnapshot g_CurrentFeat;
RegimeState  g_CurrentRegime;
ENUM_QB_MODE g_EffectiveMode;

// Order state machine tracking
ExecutionRecord g_ActiveOrder;
bool            g_OrderPending = false;
bool            g_ActiveOrderTradeCounted = false;
CTransactionState g_TransactionState;
ulong             g_LastBrokerActionAttemptMsc = 0;
int               g_ConsecutiveBrokerSubmissionFailures = 0;

bool PersistenceEnabled()
{
   return InpPersistState && InpUseGlobalVars &&
          (g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
           g_EffectiveMode == QB_MODE_CHALLENGE_LIVE);
}

double EffectiveBalance()
{
   return (g_EffectiveMode == QB_MODE_SHADOW) ?
          g_Shadow.GetBalance() : AccountInfoDouble(ACCOUNT_BALANCE);
}

double EffectiveEquity()
{
   return (g_EffectiveMode == QB_MODE_SHADOW) ?
          g_Shadow.GetEquity(g_CurrentSnap) : AccountInfoDouble(ACCOUNT_EQUITY);
}

double EffectiveExposure()
{
   return (g_EffectiveMode == QB_MODE_SHADOW) ?
          g_Shadow.GetExposure() : g_Broker.GetTotalExposure();
}

void EffectivePositionCounts(int &longCount, int &shortCount)
{
   if(g_EffectiveMode == QB_MODE_SHADOW)
      g_Shadow.CountPositions(longCount, shortCount);
   else
      g_Broker.CountPositions(longCount, shortCount);
}

int EffectiveStrategyCount(const string strategyId)
{
   return (g_EffectiveMode == QB_MODE_SHADOW) ?
          g_Shadow.GetStrategyCount(strategyId) :
          g_PosManager.GetStrategyCount(strategyId);
}

void ProcessShadowCloseEvents(ShadowCloseEvent &events[])
{
   for(int i = 0; i < ArraySize(events); i++)
   {
      PositionContext ctx;
      ZeroMemory(ctx);
      ctx.strategy_id = events[i].strategy_id;
      ctx.signal_id = events[i].signal_id;
      ctx.position_type = events[i].position_type;
      ctx.original_entry = events[i].original_entry;
      ctx.original_stop = events[i].original_stop;
      ctx.initial_target = events[i].initial_target;
      ctx.initial_volume = events[i].initial_volume;
      ctx.mfe = events[i].mfe;
      ctx.mae = events[i].mae;
      ctx.entry_regime_trend = events[i].entry_regime_trend;
      ctx.entry_regime_vol = events[i].entry_regime_vol;
      ctx.entry_session = events[i].entry_session;
      ctx.entry_spread = events[i].entry_spread;
      ctx.entry_slippage = events[i].entry_slippage;
      ctx.entry_time = events[i].entry_time;
      g_Journal.LogTrade(ctx, events[i].exit_price,
                         events[i].gross_pnl, events[i].commission,
                         events[i].swap, events[i].exit_reason,
                         g_CurrentRegime.trend, g_CurrentRegime.volatility);
      g_RiskEngine.UpdateAfterClose(events[i].net_pnl, g_Shadow.GetEquity(g_CurrentSnap));
      QBLogInfo("SHADOW CLOSED: " + events[i].strategy_id +
                " net=" + DoubleToString(events[i].net_pnl, 2) +
                " reason=" + EnumToString(events[i].exit_reason));
   }
}

void PersistRuntimeState();

void EmitConfiguredAlert(bool enabled, const string message)
{
   g_Alerts.SendIfEnabled(enabled, message);
}

// Service persistent cancel/flatten requests from both OnTick and OnTimer.
// Only explicitly live modes may transmit broker actions, and retries share a
// bounded cadence so a fast tick stream cannot hammer the trade server.
bool ProcessKillSwitchActions()
{
   bool flattenRequested = g_KillSwitch.IsFlattenAll();
   bool cancelRequested = g_KillSwitch.IsCancelAll();
   if(!flattenRequested && !cancelRequested) return false;

   if(g_EffectiveMode == QB_MODE_SHADOW)
   {
      if(flattenRequested)
      {
         ShadowCloseEvent events[];
         g_Shadow.CloseAll(g_CurrentSnap, events);
         ProcessShadowCloseEvents(events);
         g_KillSwitch.ClearFlattenRequest();
      }
      else
         g_KillSwitch.ClearCancelRequest();
      return true;
   }

   // Diagnostic and any future non-live modes must never transmit orders.
   if(!QBModeAllowsBrokerActions(g_EffectiveMode)) return true;

   if(!QBBrokerActionAttemptDue(GetTickCount64(), 1000,
                                g_LastBrokerActionAttemptMsc))
      return true;

   if(flattenRequested)
   {
      g_Broker.CancelAllPending();
      g_Broker.CloseAllPositions();

      int longRemaining = 0;
      int shortRemaining = 0;
      g_Broker.CountPositions(longRemaining, shortRemaining);
      int ordersRemaining = g_Broker.CountPendingOrders();
      if(QBShouldRetainBrokerAction(longRemaining + shortRemaining,
                                    ordersRemaining))
      {
         QBLogError("Flatten request retained: positions=" +
                    IntegerToString(longRemaining + shortRemaining) +
                    " pending=" + IntegerToString(ordersRemaining));
         PersistRuntimeState();
         return true;
      }
      g_KillSwitch.ClearFlattenRequest();
      PersistRuntimeState();
      return true;
   }

   g_Broker.CancelAllPending();
   int ordersRemaining = g_Broker.CountPendingOrders();
   if(QBShouldRetainBrokerAction(0, ordersRemaining))
   {
      QBLogError("Cancel request retained: pending=" +
                 IntegerToString(ordersRemaining));
      PersistRuntimeState();
      return true;
   }
   g_KillSwitch.ClearCancelRequest();
   PersistRuntimeState();
   return true;
}

// Fail closed when ownership/protection cannot be proven after a fill.
void ActivateProtectionEmergency(string reason)
{
   g_KillSwitch.Emergency(reason);
   EmitConfiguredAlert(InpAlertKillSwitch || InpAlertUnprotectedPos,
                       "Protection emergency: " + reason);
   if(QBModeAllowsBrokerActions(g_EffectiveMode))
   {
      g_Broker.CancelAllPending();
      g_Broker.CloseAllPositions();
   }
   PersistRuntimeState();
}

void PersistRuntimeState()
{
   if(!PersistenceEnabled() || !g_StateStoreCompatible || !g_StartupReconciled) return;

   GV_WriteDatetime(GV_DAILY_DATE, g_RiskEngine.GetDailyPeriodStart());
   GV_WriteDouble(GV_DAILY_START_EQUITY, g_RiskEngine.GetDailyStartEquity());
   GV_WriteDatetime(GV_WEEKLY_DATE, g_RiskEngine.GetWeeklyPeriodStart());
   GV_WriteDouble(GV_WEEKLY_START_EQUITY, g_RiskEngine.GetWeeklyStartEquity());
   GV_WriteDouble(GV_HIGH_WATER_MARK, g_RiskEngine.GetHighWaterMark());
   GV_WriteDouble(GV_DAILY_LOCK, g_RiskEngine.IsDailyLock() ? 1.0 : 0.0);
   GV_WriteDouble(GV_WEEKLY_LOCK, g_RiskEngine.IsWeeklyLock() ? 1.0 : 0.0);
   GV_WriteDouble(GV_DRAWDOWN_LOCK, g_RiskEngine.IsDrawdownLock() ? 1.0 : 0.0);
   GV_WriteDouble(GV_CONSEC_LOSSES, g_RiskEngine.GetConsecLosses());
   GV_WriteDouble(GV_BROKER_FAILURES,
                  g_ConsecutiveBrokerSubmissionFailures);
   SaveKillSwitchState(g_KillSwitch.GetState());
   SaveChallengeState(g_Challenge.GetState());
   // Make each material checkpoint durable before a terminal/VPS crash.
   // Strategy Tester agents isolate globals across jobs, but live-terminal
   // persistence must not rely only on deferred autosave.
   GlobalVariablesFlush();
}

// Close deals are deferred until after MT5's transaction burst. At DEAL_ADD
// time the position pool may still expose a position that has actually closed.
void ProcessPendingCloseReconciliation()
{
   for(int idx = g_TransactionState.Count() - 1; idx >= 0; idx--)
   {
      QBCloseCandidate candidate;
      if(!g_TransactionState.Get(idx, candidate)) continue;

      ulong remainingTicket = 0;
      bool positionStillExists = g_Broker.ResolvePositionByIdentifier(
                                    candidate.position_identifier, remainingTicket);
      if(!QBShouldFinalizeCloseCandidate(positionStillExists))
      {
         // The deal was a partial exit. Its PnL will be included when the final
         // close is reconciled from complete position history.
         g_TransactionState.RemoveAt(idx);
         continue;
      }

      PositionContext ctx;
      if(!g_PosManager.GetContextByIdentifier(candidate.position_identifier, ctx))
      {
         QBLogWarn("Closed owned position was not present in local context: id=" +
                   IntegerToString(candidate.position_identifier));
         g_TransactionState.RemoveAt(idx);
         continue;
      }

      if(!HistoryDealSelect(candidate.exit_deal))
         continue; // history may not be synchronized yet; retry next tick/timer

      double grossPnL = 0, commission = 0, swap = 0;
      if(!HistorySelect(ctx.entry_time - 60, TimeCurrent() + 60))
         continue;

      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 ||
            (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != candidate.position_identifier)
            continue;

         grossPnL += HistoryDealGetDouble(deal, DEAL_PROFIT);
         commission += HistoryDealGetDouble(deal, DEAL_COMMISSION);
         swap += HistoryDealGetDouble(deal, DEAL_SWAP);
      }

      ENUM_EXIT_REASON exitReason = EXIT_UNKNOWN;
      ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(
                                      candidate.exit_deal, DEAL_REASON);
      if(dealReason == DEAL_REASON_SL) exitReason = EXIT_STOP_LOSS;
      else if(dealReason == DEAL_REASON_TP) exitReason = EXIT_TARGET_HIT;
      else if(dealReason == DEAL_REASON_EXPERT) exitReason = EXIT_MANUAL;

      double exitPrice = HistoryDealGetDouble(candidate.exit_deal, DEAL_PRICE);
      g_Journal.LogTrade(ctx, exitPrice, grossPnL, commission, swap,
                         exitReason, g_CurrentRegime.trend, g_CurrentRegime.volatility);
      g_RiskEngine.UpdateAfterClose(grossPnL + commission + swap,
                                    AccountInfoDouble(ACCOUNT_EQUITY));
      g_PosManager.RemoveByIdentifier(candidate.position_identifier);
      g_TransactionState.RemoveAt(idx);
      PersistRuntimeState();
   }
}

int StrategyIndexFromId(string strategyId)
{
   if(strategyId == STRATEGY_ID_BREAKOUT) return QB_STRAT_IDX_BO;
   if(strategyId == STRATEGY_ID_FAILED_BREAKOUT) return QB_STRAT_IDX_FBO;
   if(strategyId == STRATEGY_ID_TREND_PULLBACK) return QB_STRAT_IDX_TP;
   if(strategyId == STRATEGY_ID_MEAN_REVERSION) return QB_STRAT_IDX_MR;
   return -1;
}

void MarkStrategyTrade(string strategyId)
{
   int idx = StrategyIndexFromId(strategyId);
   if(idx >= 0 && idx < QB_STRAT_COUNT) g_StrategyTradesToday[idx]++;
}

bool QBLiveStrategySetAllowed(bool boEnabled, bool fboEnabled,
                              bool tpEnabled, bool mrEnabled,
                              string &reason)
{
   if(!fboEnabled)
   {
      reason = "FBO must be enabled for the current live candidate scope";
      return false;
   }

   if(boEnabled || tpEnabled || mrEnabled)
   {
      reason = "Live modes are currently restricted to FBO-only; "
               "BO/TP/MR accepted-entry evidence is not complete";
      return false;
   }

   reason = "FBO-only live candidate";
   return true;
}

bool QBLiveExecutionSetAllowed(bool useMarketOrders, bool useStopOrders,
                               bool useLimitOrders, int maxPendingOrders,
                               string &reason)
{
   if(!useMarketOrders)
   {
      reason = "Live modes require market orders until pending lifecycle "
               "and restart evidence is complete";
      return false;
   }

   if(useStopOrders || useLimitOrders || maxPendingOrders > 0)
   {
      reason = "Live pending orders are disabled until activation, expiry, "
               "cancellation, fill-race, and restart evidence is complete";
      return false;
   }

   reason = "market-order-only live candidate";
   return true;
}

bool QBLiveRecoveryPolicyAllowed(ENUM_UNKNOWN_POS_POLICY unknownPolicy,
                                 string &reason)
{
   if(unknownPolicy == UNKNOWN_FLATTEN)
   {
      reason = "Live startup UNKNOWN_FLATTEN is disabled until explicit "
               "operator authorization exists; startup must not transmit "
               "broker close orders passively";
      return false;
   }

   reason = "non-transmitting unknown-position startup policy";
   return true;
}

bool QBEntryPreflightControlsAllow(bool dataQualityOK, int barCount,
                                   int barWarmup, bool abnormalTick,
                                   double priceJumpPoints, string &reason)
{
   if(!dataQualityOK)
   {
      reason = "Data quality gate";
      return false;
   }

   if(barWarmup > 0 && barCount < barWarmup)
   {
      reason = "Bar warmup: " + IntegerToString(barCount) + " < " +
               IntegerToString(barWarmup);
      return false;
   }

   if(abnormalTick)
   {
      reason = "Price jump: " + DoubleToString(priceJumpPoints, 1) +
               " pts > configured maximum";
      return false;
   }

   reason = "entry preflight passed";
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   QBLogSeparator();
   QBLogInfo("══════════ " + QB_EA_NAME + " v" + QB_VERSION + " Initializing ══════════");

   // --- Determine effective mode ---
   g_EffectiveMode = InpMode;
   if(g_EffectiveMode == QB_MODE_CHALLENGE_LIVE && !InpAcknowledgeChallengeRisk)
   {
      QBLogWarn("Challenge mode requested but not acknowledged. Falling back to Shadow.");
      g_EffectiveMode = QB_MODE_SHADOW;
   }

   bool requestedLiveMode = (g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
                             g_EffectiveMode == QB_MODE_CHALLENGE_LIVE);
   if(requestedLiveMode)
   {
      string liveStrategyReason = "";
      if(!QBLiveStrategySetAllowed(InpBO_Enabled, InpFBO_Enabled,
                                   InpTP_Enabled, InpMR_Enabled,
                                   liveStrategyReason))
      {
         QBLogError("Live strategy gate blocked initialization: " +
                    liveStrategyReason);
         return INIT_FAILED;
      }

      string liveExecutionReason = "";
      if(!QBLiveExecutionSetAllowed(InpUseMarketOrders, InpUseStopOrders,
                                    InpUseLimitOrders, InpMaxPendingOrders,
                                    liveExecutionReason))
      {
         QBLogError("Live execution gate blocked initialization: " +
                    liveExecutionReason);
         return INIT_FAILED;
      }

      string liveRecoveryReason = "";
      if(!QBLiveRecoveryPolicyAllowed(InpUnknownPosPolicy,
                                      liveRecoveryReason))
      {
         QBLogError("Live recovery gate blocked initialization: " +
                    liveRecoveryReason);
         return INIT_FAILED;
      }
   }

   // --- Initialize Diagnostics ---
   DiagInit(InpEnableDebugLogging);
   DiagPrintBrokerInfo();

   // --- Initialize Symbol Adapter ---
   string symbol = (InpPrimarySymbol != "") ? InpPrimarySymbol : _Symbol;
   if(!g_Adapter.Init(symbol))
   {
      QBLogError("Symbol adapter initialization FAILED");
      return INIT_FAILED;
   }
   SetStateScopeSymbol(g_Adapter.Symbol());
   g_Adapter.PrintDiagnostics();

   // --- Initialize Tick State ---
   if(!g_TickState.Init(g_Adapter.Symbol()))
   {
      QBLogError("Tick state initialization FAILED");
      return INIT_FAILED;
   }

   // --- Initialize Bar Cache ---
   ENUM_TIMEFRAMES tfs[] = {InpPrimaryTF, InpShortTF, InpMediumTF, InpLongTF, InpHTF, InpDailyTF};
   if(!g_BarCache.Init(g_Adapter.Symbol(), tfs, 6))
   {
      QBLogError("Bar cache initialization FAILED");
      return INIT_FAILED;
   }

   // --- Initialize Session Engine ---
   SessionConfig sessCfg;
   sessCfg.asiaStartHour     = InpAsiaStartHour;    sessCfg.asiaStartMin     = InpAsiaStartMin;
   sessCfg.londonPreopenHour = InpLondonPreopenHour; sessCfg.londonPreopenMin = InpLondonPreopenMin;
   sessCfg.londonOpenHour    = InpLondonOpenHour;    sessCfg.londonOpenMin    = InpLondonOpenMin;
   sessCfg.nyPreopenHour     = InpNYPreopenHour;     sessCfg.nyPreopenMin     = InpNYPreopenMin;
   sessCfg.nyOpenHour        = InpNYOpenHour;        sessCfg.nyOpenMin        = InpNYOpenMin;
   sessCfg.nyAfternoonHour   = InpNYAfternoonHour;   sessCfg.nyAfternoonMin   = InpNYAfternoonMin;
   sessCfg.rolloverHour      = InpRolloverHour;      sessCfg.rolloverMin      = InpRolloverMin;
   sessCfg.fridayCloseHour   = InpFridayCloseHour;   sessCfg.fridayCloseMin   = InpFridayCloseMin;
   sessCfg.brokerUTCOffsetHours = InpBrokerUTCOffsetHours;
   sessCfg.brokerIsDST         = InpBrokerIsDST;
   g_SessionEngine.Init(sessCfg);

   // --- Initialize Data Quality ---
   if(!g_DataQuality.Init(g_Adapter, g_BarCache))
   {
      QBLogError("Data quality checker init FAILED");
      return INIT_FAILED;
   }

   // Populate the cache before validating history or running startup tests.
   // Without this update, a cold start can falsely report insufficient data
   // even when the terminal already has the required series available.
   g_BarCache.Update();

   bool livePermissionsRequired = (g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
                                   g_EffectiveMode == QB_MODE_CHALLENGE_LIVE);
   if(!g_DataQuality.RunAllChecks(InpPrimaryTF, InpMinBarsRequired,
                                  InpCheckBarSequence, livePermissionsRequired))
   {
      QBLogError("Data quality checks FAILED");
      if(InpRequireDataQuality) return INIT_FAILED;
      QBLogWarn("Continuing despite data quality failures (InpRequireDataQuality=false)");
   }

   // --- Initialize Feature Engine ---
   if(!g_FeatureEngine.Init(g_Adapter, g_BarCache, g_SessionEngine, g_TickState,
                             InpPrimaryTF, InpHTF, InpRegimeATRPeriod, InpTrendLookback,
                             InpTrendSlopeThreshold, InpCompressionLookback,
                             InpCompressionPct, InpShockVolMultiplier))
   {
      QBLogError("Feature engine init FAILED");
      return INIT_FAILED;
   }

   // --- Initialize News Interface ---
   g_NewsInterface.Init(InpNewsEnabled, InpPreNewsLockoutMinutes,
                         InpPostNewsLockoutMinutes, InpNewsTimes);

   // --- Initialize Regime Engine ---
   if(!g_RegimeEngine.Init(InpRegimeEnabled, InpTrendSlopeThreshold,
                            InpCompressionPct, InpShockVolMultiplier, InpExpansionMinBars))
   {
      QBLogError("Regime engine init FAILED");
      return INIT_FAILED;
   }

   // --- Initialize Strategies ---
   g_StrategyBO.Init(STRATEGY_ID_BREAKOUT, "Breakout", InpBO_Enabled, InpBO_MinConfidence,
                     g_Adapter, InpBO_TriggerMode,
                     InpBO_CompressionPct, InpBO_MinCompressionBars, InpBO_MinDisplacement,
                     InpBO_StopATRMultiplier, InpBO_TargetR, InpBO_RequireHTFBias);

   g_StrategyFBO.Init(STRATEGY_ID_FAILED_BREAKOUT, "Failed Breakout", InpFBO_Enabled,
                      InpFBO_MinConfidence, g_Adapter, InpFBO_TriggerMode,
                      InpFBO_MinPenetration, InpFBO_MaxBarsBeyond, InpFBO_ReclaimThreshold,
                      InpFBO_StopBeyondSweep, InpFBO_TargetMidR, InpFBO_TargetVWAPR);

   g_StrategyTP.Init(STRATEGY_ID_TREND_PULLBACK, "Trend Pullback", InpTP_Enabled,
                     InpTP_MinConfidence, g_Adapter, InpTP_TriggerMode,
                     InpTP_MinDirEfficiency, InpTP_MinTrendPersistence, InpTP_RequireHTFAgreement,
                     InpTP_MaxPullbackDepth, InpTP_MaxPullbackBars,
                     InpTP_TargetExtensionR, InpTP_StopBeyondStruct);

   g_StrategyMR.Init(STRATEGY_ID_MEAN_REVERSION, "Mean Reversion", InpMR_Enabled,
                     InpMR_MinConfidence, g_Adapter, InpMR_TriggerMode,
                     InpMR_MaxTrendStrength, InpMR_MinDeviationSD, InpMR_MinRejectionWick,
                     InpMR_TargetVWAPR, InpMR_TargetSDBandR, InpMR_EmergencyStopR);

   g_Strategies[QB_STRAT_IDX_BO]  = &g_StrategyBO;
   g_Strategies[QB_STRAT_IDX_FBO] = &g_StrategyFBO;
   g_Strategies[QB_STRAT_IDX_TP]  = &g_StrategyTP;
   g_Strategies[QB_STRAT_IDX_MR]  = &g_StrategyMR;

   // --- Initialize Signal Arbitrator ---
   g_Arbitrator.Init(InpArbitrationMethod, InpCooldownSeconds,
                     InpDuplicateWindowSeconds, InpAllowOppositeSignals,
                     InpAllowSameDirectionStack);

   // --- Initialize Position Sizer ---
   g_Sizer.Init(g_Adapter, InpLotMode, InpFixedLots, InpFixedRiskCurrency,
                InpRiskPercent, InpVolAdjRiskTarget, InpMinLotSize,
                InpMaxLotSize, InpSlippageAllowancePts, InpCommissionEstimate);

   // --- Initialize Risk Engine ---
   g_RiskEngine.Init(g_Adapter, g_Sizer,
                     InpMaxRiskPerTrade, InpMinRewardRisk, InpMinStopPoints, InpMaxStopPoints,
                     InpMaxHoldingMinutes, InpMaxPendingMinutes,
                     InpDailyLossLimitPct, InpWeeklyLossLimitPct, InpMaxDrawdownPct,
                     InpMaxConsecLosses, InpMinMarginLevelPct, InpEmergencyEquityFloor,
                     InpMaxPositions, InpMaxPendingOrders, InpMaxTotalExposureLots,
                     2, 10);

   // --- Initialize Challenge Mode ---
   g_Challenge.Init(g_EffectiveMode == QB_MODE_CHALLENGE_LIVE, InpAcknowledgeChallengeRisk,
                    InpChal_Stage0_Target, InpChal_Stage1_Target, InpChal_Stage2_Target,
                    InpChal_Stage3_Target, InpChal_Stage4_Target,
                    InpChal_Stage0_RiskPct, InpChal_Stage1_RiskPct, InpChal_Stage2_RiskPct,
                    InpChal_Stage3_RiskPct, InpChal_Stage4_RiskPct,
                    InpChal_MaxStageDD, InpChal_MaxAttempts,
                    InpChal_ProfitLockPct, InpChal_AllowPyramiding);

   // --- Initialize Broker Adapter ---
   if(!g_Broker.Init(g_Adapter, QB_MAGIC_BASE, InpSlippageAllowancePts))
   {
      QBLogError("Broker adapter init FAILED");
      return INIT_FAILED;
   }
   g_Broker.SetPreferredFillMode(InpFillMode);

   // --- Initialize Position Manager ---
   g_PosManager.Init(g_Adapter, g_Broker,
                     InpEnableBreakeven, InpBreakevenTriggerR, InpBreakevenPlusPips,
                     InpEnablePartialClose, InpPartialClosePct, InpPartialCloseTriggerR,
                     InpEnableATRTrail, InpATRTrailMultiplier, InpATRTrailStartR,
                     InpEnableTimeStop, InpTimeStopMinutes);

   g_Shadow.Init(g_Adapter, AccountInfoDouble(ACCOUNT_BALANCE),
                 InpCommissionEstimate, InpSlippageAllowancePts,
                 InpEnableBreakeven, InpBreakevenTriggerR, InpBreakevenPlusPips,
                 InpEnablePartialClose, InpPartialClosePct, InpPartialCloseTriggerR,
                 InpEnableATRTrail, InpATRTrailMultiplier, InpATRTrailStartR,
                 InpEnableTimeStop, InpTimeStopMinutes);

   // --- Initialize Journal ---
   g_Journal.Init(InpEnableSignalJournal, InpEnableOrderJournal, InpEnableTradeJournal);

   // --- Initialize Dashboard ---
   g_Dashboard.Init(InpDashboardEnabled, InpDashboardX, InpDashboardY,
                    InpDashboardFontSize, InpDashboardColor);
   g_Alerts.Init(InpSendPushNotifications);

   // --- Persistence: State Store Init ---
   if(PersistenceEnabled())
      g_StateStoreCompatible = StateStoreInit();

   // --- Startup Reconciliation ---
   bool liveMode = requestedLiveMode;
   if(liveMode)
   {
      long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(!QBIsSupportedLiveMarginMode(marginMode))
      {
         QBLogError("Live mode requires a hedging account; netting/exchange "
                    "DEAL_ENTRY_INOUT reconciliation is not implemented");
         return INIT_FAILED;
      }

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      bool persist = PersistenceEnabled() && g_StateStoreCompatible;
      if(PersistenceEnabled() && !g_StateStoreCompatible)
         g_KillSwitch.KillEntries("Persisted state version mismatch; migration or explicit clear required");
      double savedDailyStart  = persist ? GV_ReadDouble(GV_DAILY_START_EQUITY, 0) : 0;
      double savedWeeklyStart = persist ? GV_ReadDouble(GV_WEEKLY_START_EQUITY, 0) : 0;
      double savedHWM         = persist ? GV_ReadDouble(GV_HIGH_WATER_MARK, 0) : 0;
      datetime savedDailyDate = persist ? GV_ReadDatetime(GV_DAILY_DATE, 0) : 0;
      datetime savedWeeklyDate = persist ? GV_ReadDatetime(GV_WEEKLY_DATE, 0) : 0;
      bool savedDailyLock = persist ? GV_ReadDouble(GV_DAILY_LOCK, 0) > 0.5 : false;
      bool savedWeeklyLock = persist ? GV_ReadDouble(GV_WEEKLY_LOCK, 0) > 0.5 : false;
      bool savedDrawdownLock = persist ? GV_ReadDouble(GV_DRAWDOWN_LOCK, 0) > 0.5 : false;
      int savedConsecLosses = persist ? (int)GV_ReadDouble(GV_CONSEC_LOSSES, 0) : 0;
      g_ConsecutiveBrokerSubmissionFailures = persist ?
         MathMax(0, (int)GV_ReadDouble(GV_BROKER_FAILURES, 0)) : 0;

      g_RiskEngine.InitDailyTracking(currentEquity,
                                     savedDailyStart, savedDailyDate,
                                     savedWeeklyStart, savedWeeklyDate,
                                     savedHWM, savedDailyLock, savedWeeklyLock,
                                     savedDrawdownLock, savedConsecLosses);

      // Load kill switch state
      if(persist)
      {
         KillSwitchState savedKill;
         LoadKillSwitchState(savedKill);
         g_KillSwitch.RestoreState(savedKill);
      }

      // Load challenge state
      if(persist && g_EffectiveMode == QB_MODE_CHALLENGE_LIVE)
      {
         ChallengeState savedChallenge;
         if(LoadChallengeState(savedChallenge))
         {
            if(!g_Challenge.RestoreState(savedChallenge))
               g_KillSwitch.KillEntries("Invalid persisted Challenge state");
         }
      }

      // Pending order state is not yet persisted. Fail closed on restart by
      // cancelling owned pending orders instead of allowing orphan triggers.
      int startupPending = g_Broker.CountPendingOrders();
      if(startupPending > 0)
      {
         int cancelled = g_Broker.CancelAllPending();
         int remaining = g_Broker.CountPendingOrders();
         QBLogWarn("Startup pending reconciliation: found=" + IntegerToString(startupPending) +
                   " cancelled=" + IntegerToString(cancelled) +
                   " remaining=" + IntegerToString(remaining));
         if(remaining > 0)
            ActivateProtectionEmergency("Unable to reconcile/cancel startup pending orders");
      }

      // Reconstruct positions from broker and apply the configured policy to
      // positions whose strategy ownership cannot be recovered from history.
      int unknownPositions = 0;
      int reconstructed = g_PosManager.ReconstructFromBroker(QB_MAGIC_BASE,
                                                              InpUnknownPosPolicy,
                                                              unknownPositions);
      QBLogInfo("Startup reconciliation: " + IntegerToString(reconstructed) + " positions reconstructed");
      if(unknownPositions > 0 && InpUnknownPosPolicy == UNKNOWN_QUARANTINE)
         g_KillSwitch.KillEntries("Unknown position ownership detected at startup");

      g_StartupReconciled = true;
      PersistRuntimeState();
   }
   else
   {
      // Diagnostic and Shadow must never inspect, cancel, close, or adopt
      // broker positions/orders. Their risk state begins from local equity.
      double localEquity = (g_EffectiveMode == QB_MODE_SHADOW) ?
                           g_Shadow.GetBalance() : AccountInfoDouble(ACCOUNT_EQUITY);
      g_RiskEngine.InitDailyTracking(localEquity, 0, 0, 0, 0, 0,
                                     false, false, false, 0);
      g_StartupReconciled = true;
   }

   // --- Self-Tests ---
   if(InpSelfTestOnInit)
   {
      RunSelfTests();
   }

   // --- Set timer for periodic tasks ---
   EventSetTimer(1); // 1-second timer

   QBLogInfo("══════════ " + QB_EA_NAME + " Initialized OK ══════════");
   QBLogInfo("Mode: " + EnumToString(g_EffectiveMode) +
             " | Symbol: " + g_Adapter.Symbol() +
             " | TF: " + EnumToString(InpPrimaryTF));
   QBLogSeparator();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   QBLogInfo("══════════ " + QB_EA_NAME + " Deinitializing ══════════");

   if(g_EffectiveMode == QB_MODE_SHADOW && g_Shadow.GetPositionCount() > 0)
   {
      ShadowCloseEvent events[];
      g_Shadow.CloseAll(g_CurrentSnap, events);
      ProcessShadowCloseEvents(events);
   }

   // Persist critical state
   if(PersistenceEnabled() && g_StartupReconciled)
   {
      PersistRuntimeState();
      QBLogInfo("State persisted");
   }

   // Release indicator handles
   g_FeatureEngine.ReleaseHandles();

   // Close journals
   g_Journal.CloseAll();

   // Clear dashboard
   g_Dashboard.Clear();

   // Kill timer
   EventKillTimer();

   QBLogInfo("══════════ " + QB_EA_NAME + " Deinitialized ══════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Step 1: Capture market snapshot ---
   g_CurrentSnap = g_SnapFactory.Capture(InpStaleQuoteMs);

   // --- Step 2: Update tick state ---
   g_TickState.Update(g_CurrentSnap);

   // --- Step 3: Update bar cache ---
   g_BarCache.Update();

   // --- Step 4: Update session classification ---
   g_SessionEngine.Update(TimeCurrent());

   // --- Step 5: New bar detection ---
   bool isNewBar = false;
   {
      MqlRates r;
      if(g_BarCache.GetLatestBar(InpPrimaryTF, r))
      {
         if(r.time != g_LastBarTime)
         {
            isNewBar = true;
            g_LastBarTime = r.time;
         }
      }
   }

   // --- Step 6: Pre-trade validation (entry gate only) ---
   bool livePermissionsRequired = (g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
                                   g_EffectiveMode == QB_MODE_CHALLENGE_LIVE);
   bool dataQualityOK = g_DataQuality.PreTradeValidation(g_CurrentSnap,
                                                          InpMaxSpreadPoints,
                                                          livePermissionsRequired);
   double priceJumpPoints = 0.0;
   bool abnormalTick = (InpMaxPriceJumpPoints > 0) &&
                       g_TickState.IsAbnormalTick(priceJumpPoints,
                                                  InpMaxPriceJumpPoints);
   string entryPreflightReason = "";
   if(!QBEntryPreflightControlsAllow(dataQualityOK,
                                     g_BarCache.GetBarCount(InpPrimaryTF),
                                     InpBarWarmup,
                                     abnormalTick,
                                     priceJumpPoints,
                                     entryPreflightReason))
   {
      dataQualityOK = false;
      g_LastRejection = entryPreflightReason;
      if(abnormalTick)
         QBLogWarn("Entry preflight blocked: " + entryPreflightReason);
   }

   // --- Step 7: Calculate features (on new bar only for heavy calcs) ---
   if(dataQualityOK && (isNewBar || !g_StartupReconciled))
   {
      g_CurrentFeat = g_FeatureEngine.Calculate(InpPrimaryTF, InpHTF, InpDailyTF, g_CurrentSnap);
   }

   // --- Step 8: Classify regime ---
   ENUM_EVENT_STATE eventState = g_NewsInterface.GetEventState(TimeCurrent());
   g_CurrentRegime = g_RegimeEngine.Classify(g_CurrentFeat,
                                               g_SessionEngine.GetCurrentSession(),
                                               eventState);

   // --- Step 8b: Broker-free Shadow position lifecycle ---
   if(g_EffectiveMode == QB_MODE_SHADOW)
   {
      ShadowCloseEvent events[];
      g_Shadow.Update(g_CurrentSnap, g_CurrentFeat, events);
      ProcessShadowCloseEvents(events);
   }

   // --- Step 9: Update challenge mode ---
   if(g_Challenge.IsActive())
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_Challenge.Update(equity, AccountInfoDouble(ACCOUNT_BALANCE));

      string challengeSafetyReason = "";
      if(g_Challenge.ConsumeSafetyBreach(equity, challengeSafetyReason))
         g_KillSwitch.FlattenAll(challengeSafetyReason);

      // Update sizer risk percent for challenge mode
      if(g_Challenge.IsActive())
         g_Sizer.SetRiskPercent(g_Challenge.GetRiskPercent());
   }

   g_RiskEngine.UpdateEquityState(EffectiveEquity(), TimeCurrent());

   datetime tradeDay = GetDayStart(TimeCurrent());
   if(g_StrategyTradeDay != tradeDay)
   {
      ArrayInitialize(g_StrategyTradesToday, 0);
      g_StrategyTradeDay = tradeDay;
   }

   // --- Step 10: Position management (every tick for protection) ---
   if(g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
      g_EffectiveMode == QB_MODE_CHALLENGE_LIVE)
   {
      ProcessPendingCloseReconciliation();
      g_PosManager.UpdateAll(g_CurrentSnap, g_CurrentFeat, g_CurrentRegime);
   }

   // --- Step 11: Kill switch checks ---
   g_KillSwitch.CheckConditions(
      g_CurrentSnap.is_fresh ? false : true,  // stale quote
      QBBrokerFailureThresholdReached(g_ConsecutiveBrokerSubmissionFailures,
                                      InpMaxConsecutiveBrokerFailures),
      false,  // Initial protection failures call ActivateProtectionEmergency directly.
      EffectiveEquity() < InpEmergencyEquityFloor,
      false, // Daily/weekly locks are enforced directly by RiskEngine
      false,
      !TerminalInfoInteger(TERMINAL_CONNECTED),
      g_CurrentSnap.spread_points > InpMaxSpreadPoints * 2
   );

   // Handle kill switch actions. A true result means an action was serviced
   // or remains pending, so no strategy work may continue this cycle.
   if(ProcessKillSwitchActions()) return;

   // --- Step 12: Strategy evaluation (only on new bar or significant tick) ---
   if(dataQualityOK && isNewBar && g_StartupReconciled)
   {
      EvaluateAndTrade();
   }

   // --- Step 13: Update dashboard ---
   UpdateDashboard();

   // --- Step 14: Manage active order ---
   if(g_OrderPending)
   {
      CheckOrderStatus();
   }

   g_LastTickTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Evaluate strategies and execute trades                             |
//+------------------------------------------------------------------+
void EvaluateAndTrade()
{
   // Don't trade in diagnostic mode
   if(g_EffectiveMode == QB_MODE_DIAGNOSTIC) return;
   if(g_OrderPending)
   {
      g_LastRejection = "One active pending order is already tracked";
      return;
   }
   if(g_KillSwitch.IsEntryKill() || g_KillSwitch.IsSymbolKill())
   {
      g_LastRejection = "Kill switch blocks entries";
      return;
   }

   if(!g_SessionEngine.IsTradeableSession())
   {
      g_LastRejection = "Session is not tradeable";
      return;
   }
   if(!g_RegimeEngine.IsSafeForTrading())
   {
      g_LastRejection = "Central regime safety gate";
      return;
   }

   if(g_EffectiveMode == QB_MODE_CHALLENGE_LIVE)
   {
      string challengeReason = "";
      if(!g_Challenge.IsTradeAllowed(AccountInfoDouble(ACCOUNT_EQUITY), challengeReason))
      {
         g_LastRejection = "Challenge: " + challengeReason;
         return;
      }
   }

   // Count position state
   int longCount, shortCount;
   EffectivePositionCounts(longCount, shortCount);
   g_Arbitrator.SetPositionCounts(longCount, shortCount);

   int totalPositions = longCount + shortCount;
   int pendingOrders   = (g_EffectiveMode == QB_MODE_SHADOW) ? 0 : g_Broker.CountPendingOrders();
   double totalExposure = EffectiveExposure();

   // Gather all strategy signals
   StrategySignal candidates[8]; // 4 strategies x 2 directions max
   int candidateCount = 0;

   for(int i = 0; i < QB_STRAT_COUNT; i++)
   {
      if(!g_Strategies[i].IsEnabled()) continue;
      if(g_KillSwitch.IsStrategyKilled(i)) continue;

      // Evaluate long
      StrategySignal sigLong = g_Strategies[i].EvaluateLong(g_CurrentSnap, g_CurrentFeat, g_CurrentRegime);
      if(!sigLong.valid && sigLong.rejection_code != REJECT_NONE)
      {
         g_Journal.LogSignal(sigLong, g_CurrentSnap, g_CurrentRegime, g_CurrentFeat,
                             g_Adapter.Symbol(), g_EffectiveMode);

         if(!sigLong.valid && sigLong.rejection_code != REJECT_NONE)
            g_LastRejection = sigLong.strategy_id + ": " + sigLong.reason;
      }
      if(sigLong.valid)
      {
         candidates[candidateCount++] = sigLong;
      }

      // Evaluate short
      StrategySignal sigShort = g_Strategies[i].EvaluateShort(g_CurrentSnap, g_CurrentFeat, g_CurrentRegime);
      if(!sigShort.valid && sigShort.rejection_code != REJECT_NONE)
      {
         g_Journal.LogSignal(sigShort, g_CurrentSnap, g_CurrentRegime, g_CurrentFeat,
                             g_Adapter.Symbol(), g_EffectiveMode);

         if(!sigShort.valid && sigShort.rejection_code != REJECT_NONE)
            g_LastRejection = sigShort.strategy_id + ": " + sigShort.reason;
      }
      if(sigShort.valid)
      {
         candidates[candidateCount++] = sigShort;
      }
   }

   // Arbitrate
   if(candidateCount > 0)
   {
      StrategySignal best = g_Arbitrator.Arbitrate(candidates, candidateCount,
                                                     g_CurrentRegime, g_CurrentFeat);

      // Arbitration mutates every non-winner into an explicit rejection.
      // Log those final decisions now; the winner is logged after central
      // risk approval or rejection below.
      for(int i = 0; i < candidateCount; i++)
      {
         if(candidates[i].valid) continue;
         g_Journal.LogSignal(candidates[i], g_CurrentSnap, g_CurrentRegime,
                             g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
         g_LastRejection = candidates[i].strategy_id + ": " + candidates[i].reason;
      }

      if(best.valid)
      {
         g_LastSignal = best.strategy_id + " " +
                        (best.direction == ORDER_TYPE_BUY ? "LONG" : "SHORT");

         // Risk validation
         string rejectReason = "";
         int stratPosCount = EffectiveStrategyCount(best.strategy_id);
         int stratIdx = StrategyIndexFromId(best.strategy_id);
         int stratTradesToday = (stratIdx >= 0) ? g_StrategyTradesToday[stratIdx] : 0;

         if(g_RiskEngine.ValidateTrade(best,
                                        EffectiveEquity(),
                                        EffectiveBalance(),
                                        AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),
                                        totalPositions, pendingOrders, totalExposure,
                                        stratPosCount, stratTradesToday,
                                        rejectReason))
         {
            ExecuteSignal(best);
         }
         else
         {
            g_LastRejection = "Risk: " + rejectReason;
            best.valid = false;
            best.rejection_code = REJECT_RISK_LIMIT;
            best.reason = "Risk: " + rejectReason;
            g_Journal.LogSignal(best, g_CurrentSnap, g_CurrentRegime,
                                g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
            QBLogWarn("Signal rejected by risk engine: " + rejectReason);
            EmitConfiguredAlert(InpAlertSignalRejected,
                                "Signal rejected by risk engine: " + rejectReason);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute an approved signal                                        |
//+------------------------------------------------------------------+
void ExecuteSignal(StrategySignal &signal)
{
   // Calculate position size
   string sizeReason = "";
   double equity = EffectiveEquity();
   double lots = g_Sizer.CalculateLots(signal.proposed_entry, signal.proposed_stop,
                                         equity, g_CurrentFeat.atr_points, sizeReason);

   if(lots <= 0)
   {
      g_LastRejection = "Size: " + sizeReason;
      signal.valid = false;
      signal.rejection_code = REJECT_INVALID_VOLUME;
      signal.reason = g_LastRejection;
      g_Journal.LogSignal(signal, g_CurrentSnap, g_CurrentRegime,
                          g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
      QBLogWarn("Position sizing failed: " + sizeReason);
      EmitConfiguredAlert(InpAlertSignalRejected,
                          "Position sizing failed: " + sizeReason);
      return;
   }

   string sizedRiskReason = "";
   if(!g_RiskEngine.ValidateSizedTrade(signal, lots, equity,
                                        EffectiveExposure(), sizedRiskReason))
   {
      g_LastRejection = "Sized risk: " + sizedRiskReason;
      signal.valid = false;
      signal.rejection_code = REJECT_RISK_LIMIT;
      signal.reason = g_LastRejection;
      g_Journal.LogSignal(signal, g_CurrentSnap, g_CurrentRegime,
                          g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
      QBLogWarn("Sized trade rejected: " + sizedRiskReason);
      EmitConfiguredAlert(InpAlertSignalRejected,
                          "Sized trade rejected: " + sizedRiskReason);
      return;
   }

   string brokerConstraintReason = "";
   if(!g_DataQuality.ValidateVolume(lots, brokerConstraintReason) ||
      !g_DataQuality.ValidateStopDistance(signal.proposed_entry,
                                          signal.proposed_stop,
                                          brokerConstraintReason) ||
      !g_DataQuality.ValidateTargetDistance(signal.proposed_entry,
                                            signal.proposed_target,
                                            brokerConstraintReason))
   {
      g_LastRejection = "Broker constraints: " + brokerConstraintReason;
      signal.valid = false;
      signal.rejection_code = REJECT_INVALID_STOP;
      signal.reason = g_LastRejection;
      g_Journal.LogSignal(signal, g_CurrentSnap, g_CurrentRegime,
                          g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
      QBLogWarn(g_LastRejection);
      EmitConfiguredAlert(InpAlertSignalRejected, g_LastRejection);
      return;
   }

   // Build order comment with magic+strategy+signal info
   string comment = QB_COMMENT_PREFIX + "_" + signal.strategy_id;

   // Check margin
   string marginReason = "";
   bool marginOK = true;
   if(g_EffectiveMode == QB_MODE_SHADOW)
   {
      double margin = 0;
      marginOK = OrderCalcMargin(signal.direction, g_Adapter.Symbol(), lots,
                                 signal.proposed_entry, margin) &&
                 margin <= EffectiveEquity() * 0.95;
      if(!marginOK) marginReason = "Shadow margin exceeds synthetic equity";
   }
   else
      marginOK = g_DataQuality.ValidateMargin(lots, signal.direction,
                                              signal.proposed_entry, marginReason);
   if(!marginOK)
   {
      g_LastRejection = "Margin: " + marginReason;
      signal.valid = false;
      signal.rejection_code = REJECT_MARGIN_INSUFFICIENT;
      signal.reason = g_LastRejection;
      g_Journal.LogSignal(signal, g_CurrentSnap, g_CurrentRegime,
                          g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);
      QBLogWarn("Margin check failed: " + marginReason);
      EmitConfiguredAlert(InpAlertSignalRejected,
                          "Margin check failed: " + marginReason);
      return;
   }

   // This is the final signal-decision boundary: strategy, arbitration,
   // unsized risk, sizing, sized risk, broker legality, and margin all pass.
   // Broker request/fill outcomes remain exclusively in OrderJournal.csv.
   g_Journal.LogSignal(signal, g_CurrentSnap, g_CurrentRegime,
                       g_CurrentFeat, g_Adapter.Symbol(), g_EffectiveMode);

   // Execute based on mode
   if(g_EffectiveMode == QB_MODE_SHADOW)
   {
      if(!InpUseMarketOrders)
      {
         g_LastRejection = "Shadow pending-order lifecycle is not implemented";
         QBLogWarn(g_LastRejection);
         return;
      }

      // Shadow mode: open a broker-free virtual position.
      ExecutionRecord shadowRec;
      ZeroMemory(shadowRec);
      shadowRec.request_id = GetMicrosecondCount();
      shadowRec.order_type = signal.direction;
      shadowRec.requested_volume = lots;
      shadowRec.requested_price = signal.proposed_entry;
      shadowRec.stop_loss = signal.proposed_stop;
      shadowRec.take_profit = signal.proposed_target;
      shadowRec.request_time = TimeCurrent();
      string shadowReason = "";
      if(!g_Shadow.Open(signal, lots, g_CurrentRegime, g_CurrentSnap,
                        shadowRec.request_id, shadowReason))
      {
         g_LastRejection = "Shadow: " + shadowReason;
         QBLogWarn(g_LastRejection);
         return;
      }
      shadowRec.state = QB_ORDER_STATE_PROTECTED;
      shadowRec.fill_price = (signal.direction == ORDER_TYPE_BUY) ?
                             g_CurrentSnap.ask + InpSlippageAllowancePts * g_Adapter.Point() :
                             g_CurrentSnap.bid - InpSlippageAllowancePts * g_Adapter.Point();
      shadowRec.slippage_points = InpSlippageAllowancePts;
      shadowRec.comment = comment + "_SHADOW";

      g_Journal.LogOrder(shadowRec);
      MarkStrategyTrade(signal.strategy_id);
      g_Arbitrator.CommitAccepted(signal);
      EmitConfiguredAlert(InpAlertSignalAccepted,
                          "Shadow signal accepted: " + signal.strategy_id);
      QBLogInfo("SHADOW: " + signal.strategy_id + " " +
                EnumToString(signal.direction) + " lots=" + DoubleToString(lots, 2) +
                " entry=" + DoubleToString(signal.proposed_entry, g_Adapter.Digits()) +
                " sl=" + DoubleToString(signal.proposed_stop, g_Adapter.Digits()) +
                " tp=" + DoubleToString(signal.proposed_target, g_Adapter.Digits()));
   }
   else
   {
      // Live execution
      ExecutionRecord rec;
      ZeroMemory(rec);
      bool result = false;
      bool useMarket = InpUseMarketOrders;
      bool brokerAttempted = false;

      if(!useMarket)
      {
         double ask = SymbolInfoDouble(g_Adapter.Symbol(), SYMBOL_ASK);
         double bid = SymbolInfoDouble(g_Adapter.Symbol(), SYMBOL_BID);
         bool isStopClass = (signal.direction == ORDER_TYPE_BUY) ?
                            signal.proposed_entry > ask : signal.proposed_entry < bid;
         if((isStopClass && !InpUseStopOrders) || (!isStopClass && !InpUseLimitOrders))
         {
            g_LastRejection = isStopClass ? "Stop orders disabled" : "Limit orders disabled";
            QBLogWarn(g_LastRejection);
            EmitConfiguredAlert(InpAlertOrderRejected, g_LastRejection);
            return;
         }
      }

      int maxAttempts = MathMax(0, InpMaxRetries) + 1;
      for(int attempt = 0; attempt < maxAttempts; attempt++)
      {
         if(useMarket)
         {
            double liveEntry = (signal.direction == ORDER_TYPE_BUY) ?
                               SymbolInfoDouble(g_Adapter.Symbol(), SYMBOL_ASK) :
                               SymbolInfoDouble(g_Adapter.Symbol(), SYMBOL_BID);
            double entryTolerance = MathMax(g_Adapter.TickSize(),
                                            g_Adapter.Point()) * 0.51;
            if(!QBIsMarketEntryNotAdverselyDisplaced(signal.direction,
                                                      signal.proposed_entry,
                                                      liveEntry,
                                                      entryTolerance))
            {
               g_LastRejection = "Exec: market entry adversely displaced";
               rec.order_type = signal.direction;
               rec.requested_price = signal.proposed_entry;
               rec.request_time = TimeCurrent();
               rec.state = QB_ORDER_STATE_REJECTED;
               rec.retcode = TRADE_RETCODE_PRICE_CHANGED;
               rec.retry_count = attempt;
               QBLogWarn(g_LastRejection + " approved=" +
                         DoubleToString(signal.proposed_entry, g_Adapter.Digits()) +
                         " live=" + DoubleToString(liveEntry, g_Adapter.Digits()));
               g_Journal.LogOrder(rec);
               EmitConfiguredAlert(InpAlertOrderRejected, g_LastRejection);
               break;
            }
            result = g_Broker.PlaceMarketOrder(signal.direction, lots,
                                                signal.proposed_stop, signal.proposed_target,
                                                comment, rec);
            brokerAttempted = true;
         }
         else
         {
            datetime expiry = TimeCurrent() + InpOrderExpirySeconds;
            result = g_Broker.PlaceStopOrder(signal.direction, lots,
                                             signal.proposed_entry,
                                             signal.proposed_stop, signal.proposed_target,
                                             expiry, comment, rec);
            brokerAttempted = true;
         }

         rec.retry_count = attempt;
         g_Journal.LogOrder(rec);
         if(result) break;
         if(rec.state != QB_ORDER_STATE_REJECTED ||
            !g_Broker.IsRetryableRetcode(rec.retcode) || attempt + 1 >= maxAttempts)
            break;

         bool permissionsRequired = (g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
                                     g_EffectiveMode == QB_MODE_CHALLENGE_LIVE);
         MarketSnapshot retrySnap = g_SnapFactory.Capture(InpStaleQuoteMs);
         if(!g_DataQuality.PreTradeValidation(retrySnap, InpMaxSpreadPoints,
                                              permissionsRequired))
            break;
         if(!MQLInfoInteger(MQL_TESTER) && InpRetryDelayMs > 0)
            Sleep(InpRetryDelayMs);
      }

      if(result)
      {
         g_ConsecutiveBrokerSubmissionFailures =
            QBNextConsecutiveBrokerFailures(g_ConsecutiveBrokerSubmissionFailures,
                                            brokerAttempted, true);
         PersistRuntimeState();
         // Register position
         if(rec.state == QB_ORDER_STATE_PROTECTED)
         {
            if(!g_PosManager.RegisterPosition(rec.position_ticket, rec.order_ticket,
                                               signal.strategy_id, rec.request_id,
                                               rec.fill_price,
                                               rec.stop_loss, rec.take_profit,
                                               g_CurrentRegime, g_CurrentSnap,
                                               rec.position_identifier))
            {
               ActivateProtectionEmergency("Filled position could not be registered");
            }
            else
            {
               MarkStrategyTrade(signal.strategy_id);
               g_Arbitrator.CommitAccepted(signal);
            }

            // Update risk engine consecutive losses tracking
            // (will be updated on close)
         }
         else
         {
            // Pending order - track it
            g_OrderPending = true;
            g_ActiveOrder = rec;
            g_ActiveOrderTradeCounted = false;
            g_Arbitrator.CommitAccepted(signal);
         }
      }
      else
      {
         // Handle rejection
         g_LastRejection = "Exec: " + IntegerToString((long)rec.retcode);

         if(rec.state == QB_ORDER_STATE_ACKNOWLEDGED || rec.state == QB_ORDER_STATE_CLOSED)
            ActivateProtectionEmergency("Entry fill could not be safely protected/reconciled");

         if(brokerAttempted && rec.state == QB_ORDER_STATE_REJECTED)
         {
            g_ConsecutiveBrokerSubmissionFailures =
               QBNextConsecutiveBrokerFailures(g_ConsecutiveBrokerSubmissionFailures,
                                               true, false);
            if(QBBrokerFailureThresholdReached(g_ConsecutiveBrokerSubmissionFailures,
                                               InpMaxConsecutiveBrokerFailures))
               g_KillSwitch.KillEntries("Repeated broker submission failure threshold reached");
            PersistRuntimeState();
         }

         QBLogWarn("Order submission failed after " +
                   IntegerToString(rec.retry_count + 1) + " attempt(s)");
         EmitConfiguredAlert(InpAlertOrderRejected,
                             "Order submission failed: " + IntegerToString((long)rec.retcode));
      }
   }
}

//+------------------------------------------------------------------+
//| Check status of active order                                      |
//+------------------------------------------------------------------+
void CheckOrderStatus()
{
   if(!g_OrderPending) return;

   if(OrderSelect(g_ActiveOrder.order_ticket))
   {
      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);

      if(state == ORDER_STATE_REJECTED || state == ORDER_STATE_CANCELED ||
              state == ORDER_STATE_EXPIRED)
      {
         g_OrderPending = false;
         g_ActiveOrderTradeCounted = false;
         QBLogWarn("Pending order " + EnumToString(state) +
                   ": ticket=" + IntegerToString(g_ActiveOrder.order_ticket));
      }
   }
   else
   {
      // Filled/terminal orders leave the current pool; reconcile from history.
      bool historySelected = HistoryOrderSelect(g_ActiveOrder.order_ticket);
      ENUM_ORDER_STATE historyState = historySelected ?
         (ENUM_ORDER_STATE)HistoryOrderGetInteger(g_ActiveOrder.order_ticket,
                                                   ORDER_STATE) :
         ORDER_STATE_REQUEST_ADD;
      bool fillSafelyReconciled = false;

      if(historySelected &&
         (historyState == ORDER_STATE_FILLED || historyState == ORDER_STATE_PARTIAL))
      {
         ulong identifier = (ulong)HistoryOrderGetInteger(
                               g_ActiveOrder.order_ticket, ORDER_POSITION_ID);
         ulong positionTicket = 0;
         if(g_Broker.ResolvePositionByIdentifier(identifier, positionTicket) &&
            g_Broker.EnsurePositionProtection(positionTicket,
                                               g_ActiveOrder.stop_loss,
                                               g_ActiveOrder.take_profit))
         {
            string strategyId = StringSubstr(g_ActiveOrder.comment,
                                              StringLen(QB_COMMENT_PREFIX) + 1);
            if(g_PosManager.RegisterPosition(positionTicket, g_ActiveOrder.order_ticket,
                                             strategyId, g_ActiveOrder.request_id,
                                             PositionGetDouble(POSITION_PRICE_OPEN),
                                             g_ActiveOrder.stop_loss,
                                             g_ActiveOrder.take_profit,
                                             g_CurrentRegime, g_CurrentSnap, identifier))
            {
               if(!g_ActiveOrderTradeCounted)
               {
                  MarkStrategyTrade(strategyId);
                  g_ActiveOrderTradeCounted = true;
               }
               fillSafelyReconciled = true;
            }
         }
         if(!fillSafelyReconciled)
            ActivateProtectionEmergency("Pending fill could not be safely reconciled/protected");
      }

      if(QBPendingHistoryResolved(historySelected, historyState,
                                  fillSafelyReconciled))
      {
         g_OrderPending = false;
         g_ActiveOrderTradeCounted = false;
      }
      else
      {
         QBLogError("Pending order state unresolved; retaining tracking and cancel-all: ticket=" +
                    IntegerToString(g_ActiveOrder.order_ticket));
         g_KillSwitch.CancelAll("Pending order state unresolved");
         PersistRuntimeState();
         return;
      }
   }

   // Expiry check
   if(g_OrderPending && TimeCurrent() - g_ActiveOrder.request_time > InpOrderExpirySeconds)
   {
      bool deleteConfirmed = g_Broker.DeleteOrder(g_ActiveOrder.order_ticket);
      g_OrderPending = QBPendingTrackingAfterDelete(g_OrderPending,
                                                     deleteConfirmed);
      if(g_OrderPending)
      {
         QBLogError("Pending expiry delete failed; retaining tracking and cancel-all: ticket=" +
                    IntegerToString(g_ActiveOrder.order_ticket));
         g_KillSwitch.CancelAll("Pending expiry delete failed");
         PersistRuntimeState();
         return;
      }
      g_ActiveOrderTradeCounted = false;
      QBLogWarn("Pending order expiry deletion confirmed: ticket=" +
                IntegerToString(g_ActiveOrder.order_ticket));
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_EffectiveMode == QB_MODE_CONSERVATIVE_LIVE ||
      g_EffectiveMode == QB_MODE_CHALLENGE_LIVE)
      ProcessPendingCloseReconciliation();

   // Continue emergency cancel/flatten work even when the market is quiet and
   // OnTick is not firing. The common handler enforces mode and retry bounds.
   if(ProcessKillSwitchActions()) return;

   // Periodic tasks
   static datetime lastPeriodicCheck = 0;

   if(TimeCurrent() - lastPeriodicCheck >= 60) // Every 60 seconds
   {
      // Connectivity is a transient entry gate evaluated on every tick by
      // KillSwitch::CheckConditions; it must not become a persisted manual kill.

      // Save state periodically
      if(PersistenceEnabled() && g_StartupReconciled)
      {
         PersistRuntimeState();
      }

      lastPeriodicCheck = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if(symbol != g_Adapter.Symbol()) return;

   ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong identifier = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   bool magicOwned = magic >= QB_MAGIC_BASE && magic < QB_MAGIC_BASE + 1000;
   PositionContext ownershipContext;
   bool contextOwned = identifier > 0 &&
                       g_PosManager.GetContextByIdentifier(identifier, ownershipContext);
   if(!QBIsOwnedDealForReconciliation(entryType, magicOwned, contextOwned)) return;

   if(entryType == DEAL_ENTRY_IN)
   {
      ulong positionTicket = 0;
      if(!g_Broker.ResolvePositionByIdentifier(identifier, positionTicket))
      {
         ActivateProtectionEmergency("Entry deal has no resolvable live position");
         return;
      }

      double expectedSL = PositionGetDouble(POSITION_SL);
      double expectedTP = PositionGetDouble(POSITION_TP);
      string strategyId = "UNKNOWN";
      ulong signalId = trans.deal;
      ulong orderTicket = trans.order;
      bool activeOrderMatch = g_OrderPending && g_ActiveOrder.order_ticket == trans.order;

      if(activeOrderMatch)
      {
         expectedSL = g_ActiveOrder.stop_loss;
         expectedTP = g_ActiveOrder.take_profit;
         strategyId = StringSubstr(g_ActiveOrder.comment, StringLen(QB_COMMENT_PREFIX) + 1);
         signalId = g_ActiveOrder.request_id;
      }
      else
      {
         string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
         if(StringFind(dealComment, QB_COMMENT_PREFIX + "_") == 0)
            strategyId = StringSubstr(dealComment, StringLen(QB_COMMENT_PREFIX) + 1);
      }

      if(!g_Broker.EnsurePositionProtection(positionTicket, expectedSL, expectedTP))
      {
         ActivateProtectionEmergency("Broker entry transaction lacks verified protection");
         return;
      }

      if(!g_PosManager.RegisterPosition(positionTicket, orderTicket, strategyId, signalId,
                                         PositionGetDouble(POSITION_PRICE_OPEN), expectedSL,
                                         expectedTP, g_CurrentRegime, g_CurrentSnap, identifier))
      {
         ActivateProtectionEmergency("Broker entry transaction could not be registered");
         return;
      }

      if(activeOrderMatch)
      {
         bool selected = OrderSelect(trans.order);
         ENUM_ORDER_STATE orderState = selected ?
            (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE) : ORDER_STATE_FILLED;
         double remainingVolume = selected ? OrderGetDouble(ORDER_VOLUME_CURRENT) : 0.0;
         bool countTradeNow = false;
         bool remainsWorking = QBPendingFillTransition(selected, orderState,
                                                        remainingVolume,
                                                        g_ActiveOrderTradeCounted,
                                                        countTradeNow);
         if(countTradeNow) MarkStrategyTrade(strategyId);
         g_ActiveOrder.state = remainsWorking ? QB_ORDER_STATE_PARTIALLY_FILLED :
                                                QB_ORDER_STATE_FILLED;
         g_OrderPending = remainsWorking;
         if(!remainsWorking) g_ActiveOrderTradeCounted = false;
      }
      return;
   }

   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;
   if(!g_TransactionState.QueueClose(identifier, trans.deal))
   {
      g_KillSwitch.KillEntries("Close reconciliation queue rejected/capacity exceeded");
      PersistRuntimeState();
      QBLogError("Unable to queue close reconciliation: position=" +
                 IntegerToString(identifier) + " deal=" + IntegerToString(trans.deal));
   }
}

//+------------------------------------------------------------------+
//| Update dashboard with current state                                |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpDashboardEnabled) return;

   double equity = EffectiveEquity();
   double dailyPnL = equity - g_RiskEngine.GetDailyStartEquity();
   double dailyLossRemain = 0;
   if(g_RiskEngine.GetDailyStartEquity() > 0)
      dailyLossRemain = g_RiskEngine.GetDailyStartEquity() * InpDailyLossLimitPct / 100.0 - MathMax(0, -dailyPnL);

   int posCount = (g_EffectiveMode == QB_MODE_SHADOW) ?
                  g_Shadow.GetPositionCount() : g_PosManager.GetPositionCount();
   int pendCount = (g_EffectiveMode == QB_MODE_SHADOW) ? 0 : g_Broker.CountPendingOrders();

   g_Dashboard.Update(g_Adapter.Symbol(), g_EffectiveMode,
                       g_CurrentRegime.session,
                       g_CurrentRegime.trend, g_CurrentRegime.volatility,
                       g_CurrentRegime.liquidity, g_CurrentRegime.structure,
                       g_CurrentSnap.spread_points,
                       posCount, pendCount,
                       dailyPnL, g_RiskEngine.GetCurrentDrawdown(),
                       dailyLossRemain,
                       g_KillSwitch.GetStatusString(),
                       g_Challenge.GetStageInfo(),
                       g_LastSignal, g_LastRejection);

   if(g_EffectiveMode == QB_MODE_DIAGNOSTIC)
   {
      g_Dashboard.UpdateDiagnostic(g_Adapter,
                                    TerminalInfoInteger(TERMINAL_CONNECTED),
                                    AccountInfoInteger(ACCOUNT_TRADE_ALLOWED),
                                    AccountInfoInteger(ACCOUNT_TRADE_EXPERT),
                                    g_SelfTestPassed, g_SelfTestFailed);
   }
}

//+------------------------------------------------------------------+
//| Run automated self-tests                                          |
//+------------------------------------------------------------------+
void RunSelfTests()
{
   QBLogSection("Running Self-Tests");
   g_SelfTestPassed = 0;
   g_SelfTestFailed = 0;

   // Test 1: Symbol properties
   {
      if(g_Adapter.Point() > 0)
      { g_SelfTestPassed++; QBLogInfo("TEST 1 PASS: Point valid"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 1 FAIL: Point invalid"); }

      if(g_Adapter.TickSize() > 0)
      { g_SelfTestPassed++; QBLogInfo("TEST 1b PASS: TickSize valid"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 1b FAIL: TickSize invalid"); }

      if(g_Adapter.MinLot() > 0 && g_Adapter.MaxLot() >= g_Adapter.MinLot())
      { g_SelfTestPassed++; QBLogInfo("TEST 1c PASS: Lot limits valid"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 1c FAIL: Lot limits invalid"); }
   }

   // Test 2: Volume normalization
   {
      double testVol = g_Adapter.NormalizeVolume(0.05);
      if(testVol >= g_Adapter.MinLot() && testVol <= g_Adapter.MaxLot())
      { g_SelfTestPassed++; QBLogInfo("TEST 2 PASS: Volume normalization"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 2 FAIL: Volume normalization"); }
   }

   // Test 3: Price normalization
   {
      double testPrice = g_Adapter.NormalizePrice(2650.123456);
      if(testPrice > 0)
      { g_SelfTestPassed++; QBLogInfo("TEST 3 PASS: Price normalization"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 3 FAIL: Price normalization"); }
   }

   // Test 4: Stop distance
   {
      double entry = 2650.00;
      double stop  = 2645.00;
      double dist = MathAbs(entry - stop) / g_Adapter.Point();
      if(dist >= g_Adapter.StopLevel())
      { g_SelfTestPassed++; QBLogInfo("TEST 4 PASS: Stop distance check"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 4 FAIL: Stop distance check"); }
   }

   // Test 5: Series chronology and trend sign
   {
      string detail = "";
      if(QBTestSeriesRegressionDirection(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 5 PASS: Series regression " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 5 FAIL: Series regression " + detail); }
   }

   // Test 6: Closed-bar ordering
   {
      string detail = "";
      if(QBTestClosedBarOrdering(g_BarCache, InpPrimaryTF, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 6 PASS: Closed-bar ordering " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 6 FAIL: Closed-bar ordering " + detail); }
   }

   // Test 7: Session boundary classification
   {
      SessionConfig cfg;
      cfg.asiaStartHour = InpAsiaStartHour; cfg.asiaStartMin = InpAsiaStartMin;
      cfg.londonPreopenHour = InpLondonPreopenHour; cfg.londonPreopenMin = InpLondonPreopenMin;
      cfg.londonOpenHour = InpLondonOpenHour; cfg.londonOpenMin = InpLondonOpenMin;
      cfg.nyPreopenHour = InpNYPreopenHour; cfg.nyPreopenMin = InpNYPreopenMin;
      cfg.nyOpenHour = InpNYOpenHour; cfg.nyOpenMin = InpNYOpenMin;
      cfg.nyAfternoonHour = InpNYAfternoonHour; cfg.nyAfternoonMin = InpNYAfternoonMin;
      cfg.rolloverHour = InpRolloverHour; cfg.rolloverMin = InpRolloverMin;
      cfg.fridayCloseHour = InpFridayCloseHour; cfg.fridayCloseMin = InpFridayCloseMin;
      cfg.brokerUTCOffsetHours = InpBrokerUTCOffsetHours; cfg.brokerIsDST = InpBrokerIsDST;
      string detail = "";
      if(QBTestSessionBoundaries(cfg, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 7 PASS: Session boundary " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 7 FAIL: Session boundary " + detail); }
   }

   // Test 8: Broker-aware position sizing cannot exceed its budget
   {
      string detail = "";
      if(QBTestSizerRiskBound(g_Sizer, g_Adapter,
                              MathMax(100.0, AccountInfoDouble(ACCOUNT_EQUITY)), detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 8 PASS: Sizer risk bound " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 8 FAIL: Sizer risk bound " + detail); }
   }

   // Test 9: Shadow mode can open and complete a broker-free lifecycle
   {
      string detail = "";
      if(QBTestShadowLifecycle(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 9 PASS: Shadow lifecycle " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 9 FAIL: Shadow lifecycle " + detail); }
   }

   // Test 10: Shadow stop-loss and forced flatten close virtual positions
   {
      string detail = "";
      if(QBTestShadowStopAndFlatten(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 10 PASS: Shadow stop/flatten " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 10 FAIL: Shadow stop/flatten " + detail); }
   }

   // Test 11: A partial exit cannot suppress a later breakeven move
   {
      string detail = "";
      if(QBTestShadowPartialThenBreakeven(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 11 PASS: Shadow partial/breakeven " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 11 FAIL: Shadow partial/breakeven " + detail); }
   }

   // Test 12: ATR trailing and time-stop exits are deterministic
   {
      string detail = "";
      if(QBTestShadowTrailAndTimeStop(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 12 PASS: Shadow trail/time " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 12 FAIL: Shadow trail/time " + detail); }
   }

   // Test 13: Configured costs and multiple virtual positions are accounted
   {
      string detail = "";
      if(QBTestShadowCostsAndMultiplePositions(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 13 PASS: Shadow costs/multi " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 13 FAIL: Shadow costs/multi " + detail); }
   }

   // Test 14: Synthetic open-equity loss activates central drawdown lock
   {
      string detail = "";
      if(QBTestShadowDrawdownLock(g_Adapter, g_Sizer, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 14 PASS: Shadow drawdown lock " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 14 FAIL: Shadow drawdown lock " + detail); }
   }

   // Test 15: Market-condition gates auto-clear; explicit kills remain latched
   {
      string detail = "";
      if(QBTestTransientEntryGate(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 15 PASS: Transient entry gate " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 15 FAIL: Transient entry gate " + detail); }
   }

   // Tests 16-19: Every independent strategy reaches long, short, and rejection paths
   {
      string detail = "";
      if(QBTestBreakoutReachability(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 16 PASS: BO reachability " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 16 FAIL: BO reachability " + detail); }
   }
   {
      string detail = "";
      if(QBTestFailedBreakoutReachability(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 17 PASS: FBO reachability " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 17 FAIL: FBO reachability " + detail); }
   }
   {
      string detail = "";
      if(QBTestTrendPullbackReachability(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 18 PASS: TP reachability " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 18 FAIL: TP reachability " + detail); }
   }
   {
      string detail = "";
      if(QBTestMeanReversionReachability(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 19 PASS: MR reachability " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 19 FAIL: MR reachability " + detail); }
   }

   // Test 20: incompatible persisted-state versions fail closed
   {
      string detail = "";
      if(QBTestStateVersionPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 20 PASS: State version policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 20 FAIL: State version policy " + detail); }
   }

   // Test 20b: persisted-state keys are scoped by account and effective symbol
   {
      string detail = "";
      if(QBTestStateScopePolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 20b PASS: State scope policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 20b FAIL: State scope policy " + detail); }
   }

   // Test 21: persisted account locks/counters restore without resetting
   {
      string detail = "";
      if(QBTestRecoveredRiskState(g_Adapter, g_Sizer, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 21 PASS: Risk state restore " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 21 FAIL: Risk state restore " + detail); }
   }

   // Test 22: partial pending fills retain remainder tracking and count once
   {
      string detail = "";
      if(QBTestPendingPartialFillTransition(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 22 PASS: Pending partial fill " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 22 FAIL: Pending partial fill " + detail); }
   }

   // Test 23: close events defer until position-state convergence and dedup
   {
      string detail = "";
      if(QBTestDeferredCloseTransactionState(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 23 PASS: Deferred close state " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 23 FAIL: Deferred close state " + detail); }
   }

   // Test 24: manual exits of tracked positions remain owned for accounting
   {
      string detail = "";
      if(QBTestTransactionOwnershipPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 24 PASS: Transaction ownership " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 24 FAIL: Transaction ownership " + detail); }
   }

   // Test 25: tighter broker stops satisfy the protection contract
   {
      string detail = "";
      if(QBTestProtectiveStopPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 25 PASS: Protective stop policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 25 FAIL: Protective stop policy " + detail); }
   }

   // Test 26: executable prices and live deviation share broker/config units
   {
      string detail = "";
      if(QBTestBrokerUnitPolicy(g_Adapter, detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 26 PASS: Broker unit policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 26 FAIL: Broker unit policy " + detail); }
   }

   // Test 27: retries, server acknowledgement, and failed broker actions are fail-closed
   {
      string detail = "";
      if(QBTestBrokerFailurePolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 27 PASS: Broker failure/transmission policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 27 FAIL: Broker failure/transmission policy " + detail); }
   }

   // Test 28: persisted Challenge state cannot escalate configured risk
   {
      string detail = "";
      if(QBTestChallengeRestorePolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 28 PASS: Challenge restore policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 28 FAIL: Challenge restore policy " + detail); }
   }

   // Test 29: Challenge drawdown/profit floors require exposure flattening
   {
      string detail = "";
      if(QBTestChallengeSafetyFlattenPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 29 PASS: Challenge safety flatten " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 29 FAIL: Challenge safety flatten " + detail); }
   }

   // Test 30: external account cash flows fail Challenge mode closed
   {
      string detail = "";
      if(QBTestChallengeCashFlowPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 30 PASS: Challenge cash-flow policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 30 FAIL: Challenge cash-flow policy " + detail); }
   }

   // Test 31: disconnection cannot suppress persistent hard-risk decisions
   {
      string detail = "";
      if(QBTestKillSwitchFailurePriority(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 31 PASS: Kill-switch priority " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 31 FAIL: Kill-switch priority " + detail); }
   }

   // Test 32: injected broker fault outcomes remain fail-closed without orders
   {
      string detail = "";
      if(QBTestBrokerFaultMatrix(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 32 PASS: Broker fault matrix " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 32 FAIL: Broker fault matrix " + detail); }
   }

   // Test 33: regime classifiers distinguish a safe trend/breakout from shock
   {
      string detail = "";
      if(QBTestRegimeClassification(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 33 PASS: Regime classification " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 33 FAIL: Regime classification " + detail); }
   }

   // Test 34: arbitration ranks, deduplicates, and rejects conflicts
   {
      string detail = "";
      if(QBTestArbitrationPolicy(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 34 PASS: Arbitration policy " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 34 FAIL: Arbitration policy " + detail); }
   }

   // Test 35: production SignalJournal writer preserves final decisions.
   // Tester-only so synthetic audit rows can never pollute terminal/live data.
   if(MQLInfoInteger(MQL_TESTER) && InpEnableSignalJournal)
   {
      MarketSnapshot snap = g_CurrentSnap;
      FeatureSnapshot feat = g_CurrentFeat;
      RegimeState regime = g_CurrentRegime;
      datetime fixtureTime = TimeCurrent();
      bool wrote = true;

      StrategySignal fixture;
      ZeroMemory(fixture);
      fixture.signal_time = fixtureTime;
      fixture.strategy_id = "FIX_STRATEGY_LONG_REJECT";
      fixture.direction = ORDER_TYPE_BUY;
      fixture.valid = false;
      fixture.rejection_code = REJECT_NO_SETUP;
      fixture.reason = "Fixture: strategy rejection";
      wrote = g_Journal.LogSignal(fixture, snap, regime, feat,
                                  g_Adapter.Symbol(), g_EffectiveMode) && wrote;

      fixture.strategy_id = "FIX_STRATEGY_SHORT_REJECT";
      fixture.direction = ORDER_TYPE_SELL;
      wrote = g_Journal.LogSignal(fixture, snap, regime, feat,
                                  g_Adapter.Symbol(), g_EffectiveMode) && wrote;

      fixture.strategy_id = "FIX_ARBITRATION_LOSER";
      fixture.direction = ORDER_TYPE_BUY;
      fixture.rejection_code = REJECT_ARBITRATION_LOST;
      fixture.reason = "Fixture: arbitration loser";
      wrote = g_Journal.LogSignal(fixture, snap, regime, feat,
                                  g_Adapter.Symbol(), g_EffectiveMode) && wrote;

      fixture.strategy_id = "FIX_RISK_REJECT";
      fixture.direction = ORDER_TYPE_SELL;
      fixture.rejection_code = REJECT_RISK_LIMIT;
      fixture.reason = "Fixture: central risk rejection";
      wrote = g_Journal.LogSignal(fixture, snap, regime, feat,
                                  g_Adapter.Symbol(), g_EffectiveMode) && wrote;

      fixture.strategy_id = "FIX_ACCEPTED";
      fixture.direction = ORDER_TYPE_BUY;
      fixture.valid = true;
      fixture.rejection_code = REJECT_NONE;
      fixture.reason = "Fixture: final accepted decision";
      wrote = g_Journal.LogSignal(fixture, snap, regime, feat,
                                  g_Adapter.Symbol(), g_EffectiveMode) && wrote;

      if(wrote)
      { g_SelfTestPassed++; QBLogInfo("TEST 35 PASS: Signal journal final-decision writer"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 35 FAIL: Signal journal final-decision writer"); }
   }

   // Test 36: disabling CSV output must not disable OnTester performance state.
   {
      string detail = "";
      if(QBTestPerformanceWithoutFileJournal(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 36 PASS: Performance without file journal " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 36 FAIL: Performance without file journal " + detail); }
   }

   // Test 37: live-mode strategy set remains restricted to current evidence.
   {
      string reason = "";
      bool fboOnlyAccepted = QBLiveStrategySetAllowed(false, true, false, false, reason);
      bool allStrategiesRejected = !QBLiveStrategySetAllowed(true, true, true, true, reason);
      bool fboDisabledRejected = !QBLiveStrategySetAllowed(false, false, false, false, reason);
      bool boOnlyRejected = !QBLiveStrategySetAllowed(true, false, false, false, reason);

      if(fboOnlyAccepted && allStrategiesRejected &&
         fboDisabledRejected && boOnlyRejected)
      { g_SelfTestPassed++; QBLogInfo("TEST 37 PASS: Live strategy gate FBO-only"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 37 FAIL: Live strategy gate"); }
   }

   // Test 38: live-mode execution remains market-only until pending evidence exists.
   {
      string reason = "";
      bool marketOnlyAccepted = QBLiveExecutionSetAllowed(true, false, false, 0, reason);
      bool noMarketRejected = !QBLiveExecutionSetAllowed(false, false, false, 0, reason);
      bool stopRejected = !QBLiveExecutionSetAllowed(true, true, false, 0, reason);
      bool limitRejected = !QBLiveExecutionSetAllowed(true, false, true, 0, reason);
      bool pendingCapacityRejected = !QBLiveExecutionSetAllowed(true, false, false, 1, reason);

      if(marketOnlyAccepted && noMarketRejected && stopRejected &&
         limitRejected && pendingCapacityRejected)
      { g_SelfTestPassed++; QBLogInfo("TEST 38 PASS: Live execution gate market-only"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 38 FAIL: Live execution gate"); }
   }

   // Test 39: live startup must not passively transmit close orders for unknown positions.
   {
      string reason = "";
      bool ignoreAccepted = QBLiveRecoveryPolicyAllowed(UNKNOWN_IGNORE, reason);
      bool reportAccepted = QBLiveRecoveryPolicyAllowed(UNKNOWN_REPORT, reason);
      bool quarantineAccepted = QBLiveRecoveryPolicyAllowed(UNKNOWN_QUARANTINE, reason);
      bool flattenRejected = !QBLiveRecoveryPolicyAllowed(UNKNOWN_FLATTEN, reason);

      if(ignoreAccepted && reportAccepted && quarantineAccepted && flattenRejected)
      { g_SelfTestPassed++; QBLogInfo("TEST 39 PASS: Live recovery gate no passive flatten"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 39 FAIL: Live recovery gate"); }
   }

   // Test 40: unknown positions must never be adopted into active management.
   {
      bool ignoreUnmanaged = !QBUnknownPositionShouldBeManaged(UNKNOWN_IGNORE);
      bool reportUnmanaged = !QBUnknownPositionShouldBeManaged(UNKNOWN_REPORT);
      bool quarantineUnmanaged = !QBUnknownPositionShouldBeManaged(UNKNOWN_QUARANTINE);
      bool flattenUnmanaged = !QBUnknownPositionShouldBeManaged(UNKNOWN_FLATTEN);

      if(ignoreUnmanaged && reportUnmanaged && quarantineUnmanaged && flattenUnmanaged)
      { g_SelfTestPassed++; QBLogInfo("TEST 40 PASS: Unknown positions unmanaged"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 40 FAIL: Unknown position management policy"); }
   }

   // Test 41: alert configuration routes enabled alerts and suppresses disabled ones.
   {
      string detail = "";
      if(QBTestAlertRouting(detail))
      { g_SelfTestPassed++; QBLogInfo("TEST 41 PASS: Alert routing " + detail); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 41 FAIL: Alert routing " + detail); }
   }

   // Test 42: entry preflight controls enforce bar warmup and price-jump gates.
   {
      string reason = "";
      bool passOK = QBEntryPreflightControlsAllow(true, 100, 50, false, 0.0, reason);
      bool dataQualityRejected = !QBEntryPreflightControlsAllow(false, 100, 50, false, 0.0, reason);
      bool warmupRejected = !QBEntryPreflightControlsAllow(true, 49, 50, false, 0.0, reason);
      bool jumpRejected = !QBEntryPreflightControlsAllow(true, 100, 50, true, 250.0, reason);

      if(passOK && dataQualityRejected && warmupRejected && jumpRejected)
      { g_SelfTestPassed++; QBLogInfo("TEST 42 PASS: Entry preflight controls"); }
      else
      { g_SelfTestFailed++; QBLogError("TEST 42 FAIL: Entry preflight controls " + reason); }
   }

   QBLogInfo("Self-tests complete: " + IntegerToString(g_SelfTestPassed) + " passed, " +
             IntegerToString(g_SelfTestFailed) + " failed");
}

//+------------------------------------------------------------------+
//| Tester function                                                    |
//+------------------------------------------------------------------+
double OnTester()
{
   if(g_EffectiveMode == QB_MODE_SHADOW && g_Shadow.GetPositionCount() > 0)
   {
      ShadowCloseEvent events[];
      g_Shadow.CloseAll(g_CurrentSnap, events);
      ProcessShadowCloseEvents(events);
   }

   // Return a custom fitness value for optimization
   PerformanceSummary perf = g_Journal.GetPerformance();

   if(perf.total_trades < 5) return 0;

   // Composite fitness: expectancy + profit factor - drawdown penalty
   double fitness = perf.expectancy * perf.total_trades * 0.1 +
                    perf.profit_factor * 10.0 -
                    perf.max_drawdown * 0.5;

   return MathMax(0, fitness);
}

//+------------------------------------------------------------------+
//| Chart event handler                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Chart event handling for interactive dashboard elements
   // Reserved for future interactive controls
}
