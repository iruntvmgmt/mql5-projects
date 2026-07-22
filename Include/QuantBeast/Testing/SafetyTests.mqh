//+------------------------------------------------------------------+
//|                                      QuantBeast/SafetyTests.mqh   |
//| Deterministic safety fixtures used by OnInit self-tests.          |
//+------------------------------------------------------------------+
#property strict

#ifndef QB_SAFETYTESTS_MQH
#define QB_SAFETYTESTS_MQH

#include "../Core/MathUtils.mqh"
#include "../Core/StateStore.mqh"
#include "../Data/BarCache.mqh"
#include "../Data/SessionEngine.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/RiskEngine.mqh"
#include "../Risk/ChallengeMode.mqh"
#include "../Risk/KillSwitch.mqh"
#include "../Execution/BrokerAdapter.mqh"
#include "../Execution/PositionManager.mqh"
#include "../Execution/ShadowPortfolio.mqh"
#include "../Execution/TransactionState.mqh"
#include "../Analytics/TradeJournal.mqh"
#include "../Regime/RegimeEngine.mqh"
#include "../Portfolio/SignalArbitrator.mqh"
#include "../Portfolio/AllocationEngine.mqh"
#include "../Analytics/CounterfactualTracker.mqh"
#include "../Execution/RecoveryEngine.mqh"
#include "../Strategies/BreakoutEngine.mqh"
#include "../Strategies/FailedBreakoutEngine.mqh"
#include "../Strategies/TrendPullbackEngine.mqh"
#include "../Strategies/MeanReversionEngine.mqh"

void QBMakeSyntheticMarket(CSymbolAdapter &adapter, MarketSnapshot &market,
                           double &distance)
{
   ZeroMemory(market);
   double point = adapter.Point();
   distance = MathMax(100.0, adapter.StopLevel() + 20.0) * point;
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   if(bid <= 0) bid = adapter.NormalizePrice(2500.0);
   market.time = TimeCurrent();
   market.bid = adapter.NormalizePrice(bid);
   market.ask = adapter.NormalizePrice(market.bid + 10.0 * point);
   market.mid = (market.bid + market.ask) * 0.5;
   market.spread_points = 10.0;
   market.is_fresh = true;
   market.is_tradeable = true;
}

void QBMakeNormalRegime(RegimeState &regime)
{
   ZeroMemory(regime);
   regime.trend = TREND_NEUTRAL;
   regime.volatility = VOL_NORMAL;
   regime.liquidity = LIQUIDITY_GOOD;
   regime.structure = STRUCTURE_BALANCED;
   regime.event_state = EVENT_NORMAL;
   regime.confidence = 0.8;
}

bool QBTestRegimeClassification(string &detail)
{
   CRegimeEngine engine;
   engine.Init(true, 0.3, 20.0, 3.0, 3);

   FeatureSnapshot f;
   ZeroMemory(f);
   f.slope_norm = 0.8;
   f.dir_efficiency = 0.8;
   f.trend_persistence = 8;
   f.atr_ratio = 1.0;
   f.spread_percentile = 10.0;
   f.tick_freq = 10.0;
   f.quote_stable = true;
   f.breakout_dist = 1.0;
   f.bars_beyond_level = 3;
   f.higher_high = true;

   RegimeState healthy = engine.Classify(f, SESSION_LONDON_OPEN, EVENT_NORMAL);
   bool healthySafe = engine.IsSafeForTrading();

   f.abnormal_candle = true;
   RegimeState shock = engine.Classify(f, SESSION_LONDON_OPEN, EVENT_NORMAL);
   bool shockSafe = engine.IsSafeForTrading();

   detail = "healthy=" + EnumToString(healthy.trend) + "/" +
            EnumToString(healthy.volatility) + "/" +
            EnumToString(healthy.liquidity) + "/" +
            EnumToString(healthy.structure) +
            " shock=" + EnumToString(shock.volatility);
   return healthy.trend == TREND_STRONG_UP &&
          healthy.volatility == VOL_NORMAL &&
          healthy.liquidity == LIQUIDITY_GOOD &&
          healthy.structure == STRUCTURE_ACCEPTED_BREAKOUT &&
          healthySafe && shock.volatility == VOL_SHOCK && !shockSafe;
}

void QBMakeArbitrationSignal(StrategySignal &signal, string strategy,
                             ENUM_ORDER_TYPE direction, datetime when,
                             double entry, double confidence)
{
   ZeroMemory(signal);
   signal.valid = true;
   signal.strategy_id = strategy;
   signal.direction = direction;
   signal.signal_time = when;
   signal.proposed_entry = entry;
   signal.proposed_stop = (direction == ORDER_TYPE_BUY) ? entry - 1.0 : entry + 1.0;
   signal.proposed_target = (direction == ORDER_TYPE_BUY) ? entry + 2.0 : entry - 2.0;
   signal.confidence = confidence;
   signal.expected_reward_r = 2.0;
}

bool QBTestArbitrationPolicy(string &detail)
{
   RegimeState regime;
   QBMakeNormalRegime(regime);
   FeatureSnapshot f;
   ZeroMemory(f);
   f.spread_percentile = 10.0;
   f.htf_slope = -1.0;

   datetime now = TimeCurrent();
   StrategySignal ranked[2];
   QBMakeArbitrationSignal(ranked[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2500.0, 0.5);
   QBMakeArbitrationSignal(ranked[1], STRATEGY_ID_FAILED_BREAKOUT,
                           ORDER_TYPE_SELL, now, 2500.0, 0.9);

   CSignalArbitrator highest;
   highest.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   StrategySignal best = highest.Arbitrate(ranked, 2, regime, f);
   bool lowerRankRejected = !ranked[0].valid &&
                            ranked[0].rejection_code == REJECT_ARBITRATION_LOST;
   highest.CommitAccepted(best);

   StrategySignal duplicate[1];
   duplicate[0] = ranked[1];
   StrategySignal duplicateBest = highest.Arbitrate(duplicate, 1, regime, f);

   datetime persistedLastAccept = 0;
   double persistedHashes[];
   datetime persistedTimes[];
   int persistedCount = 0;
   highest.ExportPersistence(persistedLastAccept, persistedHashes, persistedTimes,
                             persistedCount, 20);
   CSignalArbitrator restoredDuplicate;
   restoredDuplicate.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   restoredDuplicate.RestorePersistence(persistedLastAccept, persistedHashes,
                                        persistedTimes, persistedCount, TimeCurrent());
   StrategySignal restoredDup[1];
   restoredDup[0] = ranked[1];
   StrategySignal restoredDupBest = restoredDuplicate.Arbitrate(restoredDup, 1,
                                                                regime, f);

   StrategySignal conflict[2];
   QBMakeArbitrationSignal(conflict[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2501.0, 0.8);
   QBMakeArbitrationSignal(conflict[1], STRATEGY_ID_FAILED_BREAKOUT,
                           ORDER_TYPE_SELL, now, 2501.0, 0.8);
   CSignalArbitrator rejectConflicts;
   rejectConflicts.Init(ARBITRATION_REJECT_CONFLICTS, 0, 600, true, true);
   StrategySignal conflictBest = rejectConflicts.Arbitrate(conflict, 2, regime, f);

   bool duplicateRejected = !duplicateBest.valid && !duplicate[0].valid &&
                            duplicate[0].rejection_code == REJECT_DUPLICATE_SIGNAL;
   bool restoredDuplicateRejected = !restoredDupBest.valid && !restoredDup[0].valid &&
                                    restoredDup[0].rejection_code == REJECT_DUPLICATE_SIGNAL;
   bool conflictRejected = !conflictBest.valid && !conflict[0].valid &&
                           !conflict[1].valid &&
                           conflict[0].rejection_code == REJECT_CONFLICTING_SIGNAL &&
                           conflict[1].rejection_code == REJECT_CONFLICTING_SIGNAL;

   StrategySignal exposure[1];
   QBMakeArbitrationSignal(exposure[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2502.0, 0.8);
   CSignalArbitrator noStack;
   noStack.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, false, false);
   noStack.SetPositionCounts(1, 0);
   StrategySignal exposureBest = noStack.Arbitrate(exposure, 1, regime, f);
   bool exposureRejected = !exposureBest.valid && !exposure[0].valid &&
                           exposure[0].rejection_code == REJECT_EXPOSURE_LIMIT;

   StrategySignal regimePriority[2];
   RegimeState breakoutRegime = regime;
   breakoutRegime.structure = STRUCTURE_ACCEPTED_BREAKOUT;
   FeatureSnapshot neutralFeat = f;
   neutralFeat.htf_slope = 0.0;
   QBMakeArbitrationSignal(regimePriority[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2503.0, 0.5);
   QBMakeArbitrationSignal(regimePriority[1], STRATEGY_ID_FAILED_BREAKOUT,
                           ORDER_TYPE_SELL, now, 2503.0, 0.6);
   CSignalArbitrator regimeArb;
   regimeArb.Init(ARBITRATION_REGIME_PRIORITY, 0, 600, true, true);
   StrategySignal regimeBest = regimeArb.Arbitrate(regimePriority, 2,
                                                   breakoutRegime, neutralFeat);
   bool regimePrioritySelected = regimeBest.valid &&
                                 regimeBest.strategy_id == STRATEGY_ID_BREAKOUT &&
                                 !regimePriority[1].valid &&
                                 regimePriority[1].rejection_code == REJECT_ARBITRATION_LOST;

   StrategySignal confluence[2];
   QBMakeArbitrationSignal(confluence[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2504.0, 0.5);
   QBMakeArbitrationSignal(confluence[1], STRATEGY_ID_TREND_PULLBACK,
                           ORDER_TYPE_BUY, now, 2504.0, 0.7);
   CSignalArbitrator confluenceArb;
   confluenceArb.Init(ARBITRATION_REQUIRE_CONFLUENCE, 0, 600, true, true);
   StrategySignal confluenceBest = confluenceArb.Arbitrate(confluence, 2,
                                                           regime, f);
   bool confluenceSelected = confluenceBest.valid &&
                             confluenceBest.strategy_id == STRATEGY_ID_TREND_PULLBACK &&
                             !confluence[0].valid &&
                             confluence[0].rejection_code == REJECT_ARBITRATION_LOST;

   StrategySignal noConfluence[1];
   QBMakeArbitrationSignal(noConfluence[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2505.0, 0.8);
   CSignalArbitrator noConfluenceArb;
   noConfluenceArb.Init(ARBITRATION_REQUIRE_CONFLUENCE, 0, 600, true, true);
   StrategySignal noConfluenceBest = noConfluenceArb.Arbitrate(noConfluence, 1,
                                                               regime, f);
   bool noConfluenceRejected = !noConfluenceBest.valid &&
                               !noConfluence[0].valid &&
                               noConfluence[0].rejection_code == REJECT_ARBITRATION_LOST;

   StrategySignal coolFirst[1];
   QBMakeArbitrationSignal(coolFirst[0], STRATEGY_ID_BREAKOUT,
                           ORDER_TYPE_BUY, now, 2506.0, 0.9);
   CSignalArbitrator cooldownSrc;
   cooldownSrc.Init(ARBITRATION_HIGHEST_SCORE, 300, 600, true, true);
   StrategySignal coolSelected = cooldownSrc.Arbitrate(coolFirst, 1, regime, f);
   cooldownSrc.CommitAccepted(coolSelected);
   datetime coolLastAccept = 0;
   double coolHashes[];
   datetime coolTimes[];
   int coolCount = 0;
   cooldownSrc.ExportPersistence(coolLastAccept, coolHashes, coolTimes,
                                 coolCount, 20);
   CSignalArbitrator cooldownRestored;
   cooldownRestored.Init(ARBITRATION_HIGHEST_SCORE, 300, 600, true, true);
   cooldownRestored.RestorePersistence(coolLastAccept, coolHashes, coolTimes,
                                       coolCount, TimeCurrent());
   StrategySignal coolSecond[1];
   QBMakeArbitrationSignal(coolSecond[0], STRATEGY_ID_FAILED_BREAKOUT,
                           ORDER_TYPE_SELL, now, 2507.0, 0.9);
   StrategySignal coolBest = cooldownRestored.Arbitrate(coolSecond, 1, regime, f);
   bool restoredCooldownRejected = !coolBest.valid && !coolSecond[0].valid &&
                                   coolSecond[0].rejection_code == REJECT_COOLDOWN_ACTIVE;

   detail = "best=" + best.strategy_id + "/" +
            (best.direction == ORDER_TYPE_SELL ? "SELL" : "BUY") +
            " lower=" + (lowerRankRejected ? "rejected" : "FAILED") +
            " duplicate=" + (duplicateRejected ? "rejected" : "FAILED") +
            " restoredDuplicate=" + (restoredDuplicateRejected ? "rejected" : "FAILED") +
            " conflict=" + (conflictRejected ? "rejected" : "FAILED") +
            " exposure=" + (exposureRejected ? "rejected" : "FAILED") +
            " regime=" + (regimePrioritySelected ? "selected" : "FAILED") +
            " confluence=" + (confluenceSelected ? "selected" : "FAILED") +
            " noConfluence=" + (noConfluenceRejected ? "rejected" : "FAILED") +
            " restoredCooldown=" + (restoredCooldownRejected ? "rejected" : "FAILED");
   return best.valid && best.strategy_id == STRATEGY_ID_FAILED_BREAKOUT &&
          best.direction == ORDER_TYPE_SELL && lowerRankRejected &&
          duplicateRejected && restoredDuplicateRejected &&
          conflictRejected && exposureRejected && regimePrioritySelected &&
          confluenceSelected && noConfluenceRejected && restoredCooldownRejected;
}

bool QBTestBreakoutReachability(CSymbolAdapter &adapter, string &detail)
{
   CBreakoutEngine strategy;
   strategy.Init("BO_TEST", "BO test", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 5, 2.0, 1.0, 1.5, true);
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.preceding_compression_bars = 8; f.htf_aligned = true;
   f.atr_percentile_rank = 10.0;

   f.htf_slope = 1.0;
   f.current_range_low = market.ask - 4.0 * d;
   f.current_range_high = market.ask - d;
   f.closed_close = market.ask - 0.5 * d;
   StrategySignal longSig = strategy.EvaluateLong(market, f, regime);

   f.htf_slope = -1.0;
   f.current_range_low = market.bid + d;
   f.current_range_high = market.bid + 4.0 * d;
   f.closed_close = market.bid + 0.5 * d;
   StrategySignal shortSig = strategy.EvaluateShort(market, f, regime);

   f.preceding_compression_bars = 0;
   StrategySignal rejected = strategy.EvaluateShort(market, f, regime);
   f.preceding_compression_bars = 8;
   detail = "L=" + (longSig.valid ? "valid" : longSig.reason) +
            " S=" + (shortSig.valid ? "valid" : shortSig.reason) +
            " gate=" + (!rejected.valid ? "rejected" : "FAILED");
   return longSig.valid && longSig.direction == ORDER_TYPE_BUY &&
          shortSig.valid && shortSig.direction == ORDER_TYPE_SELL &&
          !rejected.valid && rejected.direction == ORDER_TYPE_SELL;
}

bool QBTestFailedBreakoutReachability(CSymbolAdapter &adapter, string &detail)
{
   CFailedBreakoutEngine strategy;
   strategy.Init("FBO_TEST", "FBO test", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 3.0, 3, 0.3, 0.5, 1.0, 1.5);
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);
   regime.structure = STRUCTURE_FAILED_BREAKOUT;
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.failed_breakout = true; f.reclaim_detected = true;
   f.bars_beyond_level = 1; f.breakout_dist = 5.0 * adapter.Point();

   f.failed_breakout_down = true;
   f.reclaim_level = market.ask - 2.0 * d;
   f.sweep_extreme = f.reclaim_level - d;
   f.closed_close = market.ask;
   f.vwap = market.ask + 6.0 * d; f.range_midpoint = market.ask + 5.0 * d;
   StrategySignal longSig = strategy.EvaluateLong(market, f, regime);
   f.vwap = 0.0; f.range_midpoint = 0.0;
   StrategySignal longFallback = strategy.EvaluateLong(market, f, regime);
   bool longUsesVWAPR = longFallback.valid &&
                        longFallback.proposed_target > longFallback.proposed_entry +
                                                        MathAbs(longFallback.proposed_entry -
                                                                longFallback.proposed_stop) * 1.4;

   f.failed_breakout_down = false; f.failed_breakout_up = true;
   f.reclaim_level = market.bid + 2.0 * d;
   f.sweep_extreme = f.reclaim_level + d;
   f.closed_close = market.bid;
   f.vwap = market.bid - 6.0 * d; f.range_midpoint = market.bid - 5.0 * d;
   StrategySignal shortSig = strategy.EvaluateShort(market, f, regime);
   f.vwap = 0.0; f.range_midpoint = 0.0;
   StrategySignal shortFallback = strategy.EvaluateShort(market, f, regime);
   bool shortUsesVWAPR = shortFallback.valid &&
                         shortFallback.proposed_target < shortFallback.proposed_entry -
                                                          MathAbs(shortFallback.proposed_entry -
                                                                  shortFallback.proposed_stop) * 1.4;

   f.failed_breakout = false; f.reclaim_detected = false;
   StrategySignal rejected = strategy.EvaluateShort(market, f, regime);
   detail = "L=" + (longSig.valid ? "valid" : longSig.reason) +
            " S=" + (shortSig.valid ? "valid" : shortSig.reason) +
            " targetL=" + (longUsesVWAPR ? "vwapR" : "FAILED") +
            " targetS=" + (shortUsesVWAPR ? "vwapR" : "FAILED") +
            " gate=" + (!rejected.valid ? "rejected" : "FAILED");
   return longSig.valid && longSig.direction == ORDER_TYPE_BUY &&
          shortSig.valid && shortSig.direction == ORDER_TYPE_SELL &&
          longUsesVWAPR && shortUsesVWAPR &&
          !rejected.valid && rejected.direction == ORDER_TYPE_SELL;
}

bool QBTestTrendPullbackReachability(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   strategy.Init("TP_TEST", "TP test", true, 0.0, adapter,
                 TRIGGER_IMMEDIATE_BREAK, 0.4, 5, true, 0.618, 20, 1.5, 0.5);
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);
   regime.structure = STRUCTURE_PULLBACK;
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.dir_efficiency = 0.8; f.trend_persistence = 10;
   f.htf_aligned = true; f.returning_to_value = true;

   regime.trend = TREND_STRONG_UP;
   f.swing_high = market.mid + d;
   f.swing_high_bars = 6;
   f.swing_low = market.mid - 4.0 * d;
   f.swing_low_bars = 6;
   f.current_range_high = f.swing_high; f.current_range_low = f.swing_low;
   f.closed_open = market.mid - 0.2 * d; f.closed_close = market.mid + 0.2 * d; // up candle
   StrategySignal longSig = strategy.EvaluateLong(market, f, regime);

   regime.trend = TREND_STRONG_DOWN;
   f.swing_low = market.mid - d;
   f.swing_low_bars = 6;
   f.swing_high = market.mid + 4.0 * d;
   f.swing_high_bars = 6;
   f.current_range_low = f.swing_low; f.current_range_high = f.swing_high;
   f.closed_open = market.mid + 0.2 * d; f.closed_close = market.mid - 0.2 * d; // down candle
   StrategySignal shortSig = strategy.EvaluateShort(market, f, regime);

   f.swing_low_bars = 25;
   StrategySignal ageRejected = strategy.EvaluateShort(market, f, regime);
   f.swing_low_bars = 6;

   regime.structure = STRUCTURE_BALANCED;
   StrategySignal rejected = strategy.EvaluateShort(market, f, regime);
   detail = "L=" + (longSig.valid ? "valid" : longSig.reason) +
            " S=" + (shortSig.valid ? "valid" : shortSig.reason) +
            " age=" + (!ageRejected.valid ? "rejected" : "FAILED") +
            " gate=" + (!rejected.valid ? "rejected" : "FAILED");
   return longSig.valid && longSig.direction == ORDER_TYPE_BUY &&
          shortSig.valid && shortSig.direction == ORDER_TYPE_SELL &&
          !ageRejected.valid && ageRejected.direction == ORDER_TYPE_SELL &&
          !rejected.valid && rejected.direction == ORDER_TYPE_SELL;
}

bool QBTestMeanReversionReachability(CSymbolAdapter &adapter, string &detail)
{
   CMeanReversionEngine strategy;
   strategy.Init("MR_TEST", "MR test", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 0.25, 1.5, 0.3, 1.0, 1.0);
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.slope_norm = 0.0; f.rejection_wick = 0.6;

   f.sd_dist = -2.0; f.rejection_wick_lower = 0.6;
   f.closed_open = market.ask - 0.2 * d; f.closed_close = market.ask;
   f.current_range_low = market.ask - 2.0 * d;
   f.vwap = market.ask + 2.0 * d; f.range_midpoint = market.ask + d;
   f.vwap_sd = d;
   StrategySignal longSig = strategy.EvaluateLong(market, f, regime);
   // Corrected mean-reversion target: return to the VWAP mean (above entry,
   // at/near VWAP) rather than the opposite SD band beyond VWAP.
   bool longMeanTarget = longSig.valid &&
                         longSig.proposed_target > longSig.proposed_entry &&
                         longSig.proposed_target <= f.vwap + adapter.Point();

   f.sd_dist = 2.0; f.rejection_wick_upper = 0.6;
   f.closed_open = market.bid + 0.2 * d; f.closed_close = market.bid;
   f.current_range_high = market.bid + 2.0 * d;
   f.vwap = market.bid - 2.0 * d; f.range_midpoint = market.bid - d;
   f.vwap_sd = d;
   StrategySignal shortSig = strategy.EvaluateShort(market, f, regime);
   bool shortMeanTarget = shortSig.valid &&
                          shortSig.proposed_target < shortSig.proposed_entry &&
                          shortSig.proposed_target >= f.vwap - adapter.Point();

   regime.structure = STRUCTURE_ACCEPTED_BREAKOUT;
   StrategySignal rejected = strategy.EvaluateShort(market, f, regime);
   detail = "L=" + (longSig.valid ? "valid" : longSig.reason) +
            " S=" + (shortSig.valid ? "valid" : shortSig.reason) +
            " meanL=" + (longMeanTarget ? "ok" : "FAILED") +
            " meanS=" + (shortMeanTarget ? "ok" : "FAILED") +
            " gate=" + (!rejected.valid ? "rejected" : "FAILED");
   return longSig.valid && longSig.direction == ORDER_TYPE_BUY &&
          shortSig.valid && shortSig.direction == ORDER_TYPE_SELL &&
          longMeanTarget && shortMeanTarget &&
          !rejected.valid && rejected.direction == ORDER_TYPE_SELL;
}

bool QBTestSeriesRegressionDirection(string &detail)
{
   double risingSeries[5] = {5, 4, 3, 2, 1}; // newest first
   double fallingSeries[5] = {1, 2, 3, 4, 5};
   double up = RegressionSlopeSeries(risingSeries, 0, 5);
   double down = RegressionSlopeSeries(fallingSeries, 0, 5);
   detail = "up=" + DoubleToString(up, 3) + " down=" + DoubleToString(down, 3);
   return up > 0 && down < 0;
}

bool QBTestClosedBarOrdering(CBarCache &cache, ENUM_TIMEFRAMES tf, string &detail)
{
   MqlRates forming, closed;
   if(!cache.GetLatestBar(tf, forming) || !cache.GetLatestClosedBar(tf, closed))
   {
      detail = "bars unavailable";
      return false;
   }
   detail = "forming=" + IntegerToString(forming.time) +
            " closed=" + IntegerToString(closed.time);
   return forming.time > closed.time;
}

bool QBTestSessionBoundaries(const SessionConfig &cfg, string &detail)
{
   CSessionEngine engine;
   engine.Init(cfg);
   MqlDateTime dt;
   TimeToStruct(D'2026.07.15 00:00:00', dt);
   dt.hour = cfg.londonOpenHour;
   dt.min = cfg.londonOpenMin;
   dt.sec = 0;
   datetime londonOpen = StructToTime(dt);
   ENUM_SESSION_TYPE atOpen = engine.Classify(londonOpen);
   detail = EnumToString(atOpen);
   return atOpen == SESSION_LONDON_OPEN;
}

bool QBTestSizerRiskBound(CPositionSizer &sizer, CSymbolAdapter &adapter,
                         double equity, string &detail)
{
   double entry = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(entry <= 0) { detail = "quote unavailable"; return false; }
   double stop = entry - MathMax(100.0, adapter.StopLevel() + 10.0) * adapter.Point();
   string reason = "";
   double lots = sizer.CalculateLots(entry, stop, equity, 100, reason);
   if(lots == 0)
   {
      detail = "safely rejected: " + reason;
      return true;
   }
   double risk = sizer.EstimateRisk(lots, entry, stop);
   double budget = equity * sizer.GetRiskPercent() / 100.0;
   detail = "lots=" + DoubleToString(lots, 4) + " risk=" + DoubleToString(risk, 2) +
            " budget=" + DoubleToString(budget, 2);
   return risk <= budget + 0.01;
}

bool QBTestShadowLifecycle(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid)
   {
      detail = "quote unavailable";
      return false;
   }

   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               false, 0.0, 0.0,
               false, 0.0, 0.0,
               false, 0.0, 0.0,
               false, 0);

   MarketSnapshot entrySnap;
   ZeroMemory(entrySnap);
   entrySnap.time = TimeCurrent();
   entrySnap.bid = bid;
   entrySnap.ask = ask;
   entrySnap.mid = (bid + ask) * 0.5;
   entrySnap.spread_points = (ask - bid) / adapter.Point();
   entrySnap.is_fresh = true;
   entrySnap.is_tradeable = true;

   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   StrategySignal signal;
   ZeroMemory(signal);
   signal.valid = true;
   signal.strategy_id = "SELFTEST";
   signal.direction = ORDER_TYPE_BUY;
   signal.signal_time = TimeCurrent();
   signal.proposed_entry = ask;
   signal.proposed_stop = adapter.NormalizePrice(ask - distance);
   signal.proposed_target = adapter.NormalizePrice(ask + distance * 2.0);

   RegimeState regime;
   ZeroMemory(regime);
   double volume = adapter.NormalizeVolume(adapter.MinLot());
   string reason = "";
   if(!shadow.Open(signal, volume, regime, entrySnap, 1, reason))
   {
      detail = "open failed: " + reason;
      return false;
   }
   if(shadow.GetPositionCount() != 1)
   {
      detail = "virtual position count did not increment";
      return false;
   }

   MarketSnapshot exitSnap = entrySnap;
   exitSnap.bid = signal.proposed_target + adapter.Point();
   exitSnap.ask = exitSnap.bid + (ask - bid);
   exitSnap.mid = (exitSnap.bid + exitSnap.ask) * 0.5;
   FeatureSnapshot features;
   ZeroMemory(features);
   ShadowCloseEvent events[];
   int closed = shadow.Update(exitSnap, features, events);
   if(closed != 1 || ArraySize(events) != 1 || shadow.GetPositionCount() != 0)
   {
      detail = "target did not close exactly one virtual position";
      return false;
   }

   detail = "net=" + DoubleToString(events[0].net_pnl, 2) +
            " balance=" + DoubleToString(shadow.GetBalance(), 2);
   return events[0].exit_reason == EXIT_TARGET_HIT &&
          events[0].net_pnl > 0 && shadow.GetBalance() > 10000.0;
}

bool QBTestShadowStopAndFlatten(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }

   MarketSnapshot snap;
   ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5;
   snap.spread_points = (ask - bid) / adapter.Point();
   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   double volume = adapter.NormalizeVolume(adapter.MinLot());
   RegimeState regime; ZeroMemory(regime);
   FeatureSnapshot features; ZeroMemory(features);
   StrategySignal signal; ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_BUY;
   signal.proposed_stop = adapter.NormalizePrice(ask - distance);
   signal.proposed_target = adapter.NormalizePrice(ask + 2.0 * distance);

   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               false, 0.0, 0.0, false, 0.0, 0.0,
               false, 0.0, 0.0, false, 0);
   string reason = "";
   if(!shadow.Open(signal, volume, regime, snap, 2, reason))
   { detail = "stop fixture open failed: " + reason; return false; }

   MarketSnapshot stopSnap = snap;
   stopSnap.bid = signal.proposed_stop - adapter.Point();
   stopSnap.ask = stopSnap.bid + (ask - bid);
   ShadowCloseEvent events[];
   if(shadow.Update(stopSnap, features, events) != 1 ||
      events[0].exit_reason != EXIT_STOP_LOSS || events[0].net_pnl >= 0)
   { detail = "virtual stop did not realize a loss"; return false; }

   ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_SELL;
   signal.proposed_stop = adapter.NormalizePrice(bid + distance);
   signal.proposed_target = adapter.NormalizePrice(bid - 2.0 * distance);
   if(!shadow.Open(signal, volume, regime, snap, 3, reason))
   { detail = "flatten fixture open failed: " + reason; return false; }
   if(shadow.CloseAll(snap, events) != 1 || shadow.GetPositionCount() != 0 ||
      events[0].exit_reason != EXIT_EMERGENCY_FLATTEN)
   { detail = "forced flatten did not close exactly one position"; return false; }

   detail = "stop=" + DoubleToString(shadow.GetBalance() - 10000.0, 2) +
            " flatten=closed";
   return true;
}

bool QBTestShadowPartialThenBreakeven(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }

   MarketSnapshot snap;
   ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5;
   snap.spread_points = (ask - bid) / adapter.Point();
   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   double volume = adapter.NormalizeVolume(adapter.MinLot() * 2.0);

   StrategySignal signal; ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_BUY;
   signal.proposed_stop = adapter.NormalizePrice(ask - distance);
   signal.proposed_target = adapter.NormalizePrice(ask + 4.0 * distance);
   RegimeState regime; ZeroMemory(regime);
   FeatureSnapshot features; ZeroMemory(features);

   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               true, 1.0, 0.0, true, 50.0, 0.5,
               false, 0.0, 0.0, false, 0);
   string reason = "";
   if(!shadow.Open(signal, volume, regime, snap, 4, reason))
   { detail = "open failed: " + reason; return false; }

   ShadowCloseEvent events[];
   MarketSnapshot partialSnap = snap;
   partialSnap.bid = ask + 0.6 * distance;
   partialSnap.ask = partialSnap.bid + (ask - bid);
   if(shadow.Update(partialSnap, features, events) != 0 ||
      shadow.GetExposure() >= volume - QB_EPSILON)
   { detail = "partial close did not reduce virtual exposure"; return false; }

   MarketSnapshot beSnap = snap;
   beSnap.bid = ask + 1.1 * distance;
   beSnap.ask = beSnap.bid + (ask - bid);
   if(shadow.Update(beSnap, features, events) != 0)
   { detail = "breakeven activation closed prematurely"; return false; }

   MarketSnapshot reversalSnap = snap;
   reversalSnap.bid = ask - 0.1 * distance;
   reversalSnap.ask = reversalSnap.bid + (ask - bid);
   int closed = shadow.Update(reversalSnap, features, events);
   detail = "net=" + (closed == 1 ? DoubleToString(events[0].net_pnl, 2) : "open");
   return closed == 1 && events[0].exit_reason == EXIT_STOP_LOSS &&
          shadow.GetPositionCount() == 0 && events[0].net_pnl > 0;
}

bool QBTestShadowTrailAndTimeStop(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }
   double spread = ask - bid;
   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   double volume = adapter.NormalizeVolume(adapter.MinLot());

   MarketSnapshot snap; ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5; snap.spread_points = spread / adapter.Point();
   StrategySignal signal; ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_BUY;
   signal.proposed_stop = adapter.NormalizePrice(ask - distance);
   signal.proposed_target = adapter.NormalizePrice(ask + 4.0 * distance);
   RegimeState regime; ZeroMemory(regime);
   FeatureSnapshot features; ZeroMemory(features); features.atr = distance;
   string reason = "";
   ShadowCloseEvent events[];

   CShadowPortfolio trail;
   trail.Init(adapter, 10000.0, 0.0, 0.0,
              false, 0.0, 0.0, false, 0.0, 0.0,
              true, 0.25, 1.0, false, 0);
   if(!trail.Open(signal, volume, regime, snap, 5, reason))
   { detail = "trail open failed: " + reason; return false; }
   MarketSnapshot advance = snap;
   advance.bid = ask + 1.5 * distance; advance.ask = advance.bid + spread;
   if(trail.Update(advance, features, events) != 0)
   { detail = "trail activation closed prematurely"; return false; }
   MarketSnapshot reversal = snap;
   reversal.bid = ask + 1.0 * distance; reversal.ask = reversal.bid + spread;
   if(trail.Update(reversal, features, events) != 1 ||
      events[0].exit_reason != EXIT_STOP_LOSS || events[0].net_pnl <= 0)
   { detail = "ATR trail did not lock positive P/L"; return false; }
   double trailNet = events[0].net_pnl;

   CShadowPortfolio timed;
   timed.Init(adapter, 10000.0, 0.0, 0.0,
              false, 0.0, 0.0, false, 0.0, 0.0,
              false, 0.0, 0.0, true, 5);
   if(!timed.Open(signal, volume, regime, snap, 6, reason))
   { detail = "time-stop open failed: " + reason; return false; }
   datetime future = TimeCurrent() + 301;
   MarketSnapshot flatSnap = snap;
   flatSnap.bid = ask; flatSnap.ask = ask + spread;
   flatSnap.mid = (flatSnap.bid + flatSnap.ask) * 0.5;
   if(timed.Update(flatSnap, features, events, future) != 1 ||
      events[0].exit_reason != EXIT_TIME_STOP)
   { detail = "time stop did not close after five minutes"; return false; }

   detail = "trailNet=" + DoubleToString(trailNet, 2) + " time=closed";
   return true;
}

bool QBTestShadowCostsAndMultiplePositions(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }
   double spread = ask - bid;
   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   double volume = adapter.NormalizeVolume(adapter.MinLot());
   MarketSnapshot snap; ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5; snap.spread_points = spread / adapter.Point();
   RegimeState regime; ZeroMemory(regime);
   FeatureSnapshot features; ZeroMemory(features);
   StrategySignal buy; ZeroMemory(buy);
   buy.valid = true; buy.strategy_id = "SELFTEST"; buy.direction = ORDER_TYPE_BUY;
   buy.proposed_stop = adapter.NormalizePrice(ask - distance);
   buy.proposed_target = adapter.NormalizePrice(ask + 2.0 * distance);
   string reason = "";
   ShadowCloseEvent events[];

   CShadowPortfolio costed;
   costed.Init(adapter, 10000.0, 10.0, 5.0,
               false, 0.0, 0.0, false, 0.0, 0.0,
               false, 0.0, 0.0, false, 0);
   if(!costed.Open(buy, volume, regime, snap, 7, reason))
   { detail = "cost fixture open failed: " + reason; return false; }
   MarketSnapshot target = snap;
   target.bid = buy.proposed_target + 10.0 * adapter.Point();
   target.ask = target.bid + spread;
   if(costed.Update(target, features, events) != 1 ||
      events[0].commission >= 0 || events[0].entry_slippage != 5.0 ||
      events[0].net_pnl >= events[0].gross_pnl)
   { detail = "configured costs were not charged"; return false; }
   double costDelta = events[0].gross_pnl - events[0].net_pnl;

   CShadowPortfolio multiple;
   multiple.Init(adapter, 10000.0, 0.0, 0.0,
                 false, 0.0, 0.0, false, 0.0, 0.0,
                 false, 0.0, 0.0, false, 0);
   if(!multiple.Open(buy, volume, regime, snap, 8, reason))
   { detail = "multi buy failed: " + reason; return false; }
   StrategySignal sell; ZeroMemory(sell);
   sell.valid = true; sell.strategy_id = "SELFTEST2"; sell.direction = ORDER_TYPE_SELL;
   sell.proposed_stop = adapter.NormalizePrice(bid + distance);
   sell.proposed_target = adapter.NormalizePrice(bid - 2.0 * distance);
   if(!multiple.Open(sell, volume, regime, snap, 9, reason) ||
      multiple.GetPositionCount() != 2 ||
      MathAbs(multiple.GetExposure() - 2.0 * volume) > QB_EPSILON)
   { detail = "multi-position count/exposure mismatch"; return false; }
   if(multiple.CloseAll(snap, events) != 2 || ArraySize(events) != 2 ||
      multiple.GetPositionCount() != 0)
   { detail = "multi-position flatten mismatch"; return false; }

   detail = "cost=" + DoubleToString(costDelta, 2) + " multi=2";
   return true;
}

bool QBTestShadowDrawdownLock(CSymbolAdapter &adapter, CPositionSizer &sizer,
                              string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }
   MarketSnapshot snap; ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5; snap.spread_points = (ask - bid) / adapter.Point();
   StrategySignal signal; ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_BUY;
   signal.proposed_stop = adapter.NormalizePrice(ask - 100.0);
   signal.proposed_target = adapter.NormalizePrice(ask + 200.0);
   RegimeState regime; ZeroMemory(regime);
   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               false, 0.0, 0.0, false, 0.0, 0.0,
               false, 0.0, 0.0, false, 0);
   string reason = "";
   if(!shadow.Open(signal, 1.0, regime, snap, 10, reason))
   { detail = "drawdown fixture open failed: " + reason; return false; }
   MarketSnapshot adverse = snap;
   adverse.bid = ask - 6.0; adverse.ask = adverse.bid + (ask - bid);
   double equity = shadow.GetEquity(adverse);

   CRiskEngine risk;
   risk.Init(adapter, sizer, 2.0, 1.0, 1, 100000, 1440, 60,
             50.0, 50.0, 5.0, 100, 0.0, 1.0,
             20, 20, 100.0, 20, 100);
   risk.InitDailyTracking(10000.0, 0, 0, 0, 0, 0,
                          false, false, false, 0);
   risk.UpdateEquityState(equity, TimeCurrent());
   detail = "equity=" + DoubleToString(equity, 2) +
            " dd=" + DoubleToString(risk.GetCurrentDrawdown(), 1);
   return equity < 9500.0 && risk.IsDrawdownLock();
}

bool QBTestTransientEntryGate(string &detail)
{
   CKillSwitch kill;
   kill.CheckConditions(false, false, false, false,
                        false, false, false, true);
   bool spreadBlocked = kill.IsEntryKill();
   kill.CheckConditions(false, false, false, false,
                        false, false, false, false);
   bool recovered = !kill.IsEntryKill();
   kill.KillEntries("self-test manual lock");
   kill.CheckConditions(false, false, false, false,
                        false, false, false, false);
   bool manualStayedLatched = kill.IsEntryKill();
   detail = "spread=" + (spreadBlocked ? "true" : "false") +
            " recovered=" + (recovered ? "true" : "false") +
            " manual=" + (manualStayedLatched ? "true" : "false");
   return spreadBlocked && recovered && manualStayedLatched;
}

bool QBTestRecoveredRiskState(CSymbolAdapter &adapter, CPositionSizer &sizer,
                              string &detail)
{
   CRiskEngine risk;
   risk.Init(adapter, sizer, 2.0, 1.0, 1, 100000, 1440, 60,
             5.0, 10.0, 20.0, 5, 0.0, 1.0,
             20, 20, 100.0, 20, 100);
   datetime now = TimeCurrent();
   risk.InitDailyTracking(9500.0,
                          10000.0, now,
                          11000.0, now,
                          12000.0, true, true, true, 4);
   detail = "daily=" + (risk.IsDailyLock() ? "locked" : "FAILED") +
            " weekly=" + (risk.IsWeeklyLock() ? "locked" : "FAILED") +
            " dd=" + (risk.IsDrawdownLock() ? "locked" : "FAILED") +
            " losses=" + IntegerToString(risk.GetConsecLosses());
   return risk.IsDailyLock() && risk.IsWeeklyLock() && risk.IsDrawdownLock() &&
          risk.GetConsecLosses() == 4 &&
          MathAbs(risk.GetDailyStartEquity() - 10000.0) < 0.01 &&
          MathAbs(risk.GetWeeklyStartEquity() - 11000.0) < 0.01 &&
          MathAbs(risk.GetHighWaterMark() - 12000.0) < 0.01;
}

bool QBTestPendingPartialFillTransition(string &detail)
{
   bool counted = false;
   bool countNow = false;

   bool firstPartial = QBPendingFillTransition(true, ORDER_STATE_PARTIAL, 0.60,
                                                counted, countNow);
   bool firstCounted = countNow && counted;

   bool secondPartial = QBPendingFillTransition(true, ORDER_STATE_PARTIAL, 0.25,
                                                 counted, countNow);
   bool noDuplicateCount = !countNow && counted;

   bool finalFill = QBPendingFillTransition(false, ORDER_STATE_FILLED, 0.0,
                                             counted, countNow);
   bool noFinalDuplicate = !countNow;

   detail = "first=" + string(firstPartial ? "tracked" : "lost") +
            " second=" + string(secondPartial ? "tracked" : "lost") +
            " final=" + string(finalFill ? "tracked" : "closed") +
            " once=" + string(firstCounted && noDuplicateCount && noFinalDuplicate ?
                               "true" : "false");
   return firstPartial && secondPartial && !finalFill && firstCounted &&
          noDuplicateCount && noFinalDuplicate;
}

bool QBTestDeferredCloseTransactionState(string &detail)
{
   CTransactionState state;
   bool first = state.QueueClose(101, 1001);
   bool duplicatePosition = state.QueueClose(101, 1002);
   bool second = state.QueueClose(202, 2001);

   QBCloseCandidate firstCandidate;
   bool gotFirst = state.Get(0, firstCandidate);
   bool latestDealWins = gotFirst && firstCandidate.position_identifier == 101 &&
                         firstCandidate.exit_deal == 1002;
   bool partialDeferred = !QBShouldFinalizeCloseCandidate(true);
   bool closedFinalized = QBShouldFinalizeCloseCandidate(false);

   bool removed = state.RemoveAt(0);
   QBCloseCandidate remaining;
   bool shifted = state.Get(0, remaining) && remaining.position_identifier == 202 &&
                  state.Count() == 1;

   bool hedgeAllowed = QBIsSupportedLiveMarginMode(ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   bool nettingRejected = !QBIsSupportedLiveMarginMode(ACCOUNT_MARGIN_MODE_RETAIL_NETTING) &&
                          !QBIsSupportedLiveMarginMode(ACCOUNT_MARGIN_MODE_EXCHANGE);

   detail = "dedup=" + string(latestDealWins ? "true" : "false") +
            " partial=" + string(partialDeferred ? "deferred" : "wrong") +
            " close=" + string(closedFinalized ? "finalized" : "wrong") +
            " hedge=" + string(hedgeAllowed && nettingRejected ? "only" : "FAILED");
   return first && duplicatePosition && second && state.Count() == 1 &&
          latestDealWins && partialDeferred && closedFinalized && removed && shifted &&
          hedgeAllowed && nettingRejected;
}

bool QBTestTransactionOwnershipPolicy(string &detail)
{
   bool ownedEntry = QBIsOwnedDealForReconciliation(DEAL_ENTRY_IN, true, false);
   bool foreignEntryRejected = !QBIsOwnedDealForReconciliation(DEAL_ENTRY_IN, false, false) &&
                               !QBIsOwnedDealForReconciliation(DEAL_ENTRY_IN, false, true);
   bool ownedExit = QBIsOwnedDealForReconciliation(DEAL_ENTRY_OUT, true, false);
   bool manualTrackedExit = QBIsOwnedDealForReconciliation(DEAL_ENTRY_OUT, false, true);
   bool foreignExitRejected = !QBIsOwnedDealForReconciliation(DEAL_ENTRY_OUT, false, false);
   bool reversalRejected = !QBIsOwnedDealForReconciliation(DEAL_ENTRY_INOUT, true, true);

   detail = "entry=" + string(ownedEntry && foreignEntryRejected ? "strict" : "FAILED") +
            " exit=" + string(ownedExit && manualTrackedExit && foreignExitRejected ?
                              "position-owned" : "FAILED") +
            " inout=" + string(reversalRejected ? "rejected" : "FAILED");
   return ownedEntry && foreignEntryRejected && ownedExit && manualTrackedExit &&
          foreignExitRejected && reversalRejected;
}

bool QBTestProtectiveStopPolicy(string &detail)
{
   double tolerance = 0.001;
   bool buyExact = QBIsStopAtLeastAsProtective(POSITION_TYPE_BUY,
                                                99.0, 99.0, tolerance);
   bool buyTighter = QBIsStopAtLeastAsProtective(POSITION_TYPE_BUY,
                                                  99.5, 99.0, tolerance);
   bool buyLooserRejected = !QBIsStopAtLeastAsProtective(POSITION_TYPE_BUY,
                                                          98.5, 99.0, tolerance);
   bool sellExact = QBIsStopAtLeastAsProtective(POSITION_TYPE_SELL,
                                                 101.0, 101.0, tolerance);
   bool sellTighter = QBIsStopAtLeastAsProtective(POSITION_TYPE_SELL,
                                                   100.5, 101.0, tolerance);
   bool sellLooserRejected = !QBIsStopAtLeastAsProtective(POSITION_TYPE_SELL,
                                                           101.5, 101.0, tolerance);
   bool missingRejected = !QBIsStopAtLeastAsProtective(POSITION_TYPE_BUY,
                                                        0.0, 99.0, tolerance);

   detail = "buy=" + string(buyExact && buyTighter && buyLooserRejected ?
                            "safe" : "FAILED") +
            " sell=" + string(sellExact && sellTighter && sellLooserRejected ?
                              "safe" : "FAILED") +
            " missing=" + string(missingRejected ? "rejected" : "FAILED");
   return buyExact && buyTighter && buyLooserRejected && sellExact &&
          sellTighter && sellLooserRejected && missingRejected;
}

bool QBTestBrokerUnitPolicy(CSymbolAdapter &adapter, string &detail)
{
   double synthetic = QBNormalizePriceToTick(100.13, 0.25, 2);
   bool syntheticAligned = MathAbs(synthetic - 100.25) <= 1e-9;

   double tickSize = adapter.TickSize();
   double raw = 2500.0 + tickSize * 0.37;
   double normalized = adapter.NormalizePrice(raw);
   double tickCount = (tickSize > 0.0) ? normalized / tickSize : 0.0;
   bool liveAligned = tickSize > 0.0 &&
                      MathAbs(tickCount - MathRound(tickCount)) <= 1e-7;

   bool deviationExact = QBDeviationPoints(10.0) == 10;
   bool deviationCeiling = QBDeviationPoints(10.1) == 11;
   bool deviationSafeZero = QBDeviationPoints(-1.0) == 0;

   detail = "tick=" + string(syntheticAligned && liveAligned ? "aligned" : "FAILED") +
            " deviation=" + string(deviationExact && deviationCeiling && deviationSafeZero ?
                                     "configured" : "FAILED");
   return syntheticAligned && liveAligned && deviationExact && deviationCeiling &&
          deviationSafeZero;
}

bool QBTestBrokerFailurePolicy(string &detail)
{
   double tolerance = 0.01;
   bool buySame = QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_BUY,
                                                        100.0, 100.0, tolerance);
   bool buyFavorable = QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_BUY,
                                                             100.0, 99.5, tolerance);
   bool buyAdverseRejected = !QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_BUY,
                                                                    100.0, 100.5, tolerance);
   bool sellSame = QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_SELL,
                                                         100.0, 100.0, tolerance);
   bool sellFavorable = QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_SELL,
                                                              100.0, 100.5, tolerance);
   bool sellAdverseRejected = !QBIsMarketEntryNotAdverselyDisplaced(ORDER_TYPE_SELL,
                                                                     100.0, 99.5, tolerance);

   bool clearWhenEmpty = !QBShouldRetainBrokerAction(0, 0);
   bool retainPosition = QBShouldRetainBrokerAction(1, 0);
   bool retainOrder = QBShouldRetainBrokerAction(0, 1);

   bool marketAccepted = QBMarketTransmissionAccepted(true, TRADE_RETCODE_DONE);
   bool marketPartial = QBMarketTransmissionAccepted(true, TRADE_RETCODE_DONE_PARTIAL);
   bool marketApiFail = !QBMarketTransmissionAccepted(false, TRADE_RETCODE_DONE);
   bool marketServerReject = !QBMarketTransmissionAccepted(true, TRADE_RETCODE_REJECT);
   bool pendingAccepted = QBPendingTransmissionAccepted(true, TRADE_RETCODE_PLACED);
   bool pendingApiFail = !QBPendingTransmissionAccepted(false, TRADE_RETCODE_PLACED);
   bool pendingServerReject = !QBPendingTransmissionAccepted(true, TRADE_RETCODE_INVALID);
   bool missingHistoryRetained = !QBPendingHistoryResolved(false, ORDER_STATE_FILLED, true);
   bool unsafeFillRetained = !QBPendingHistoryResolved(true, ORDER_STATE_FILLED, false);
   bool safeFillResolved = QBPendingHistoryResolved(true, ORDER_STATE_FILLED, true);
   bool canceledResolved = QBPendingHistoryResolved(true, ORDER_STATE_CANCELED, false);
   bool deleteFailureRetained = QBPendingTrackingAfterDelete(true, false);
   bool deleteSuccessCleared = !QBPendingTrackingAfterDelete(true, true);
   int failureCount = 0;
   failureCount = QBNextConsecutiveBrokerFailures(failureCount, false, false);
   bool localRejectIgnored = failureCount == 0;
   failureCount = QBNextConsecutiveBrokerFailures(failureCount, true, false);
   failureCount = QBNextConsecutiveBrokerFailures(failureCount, true, false);
   failureCount = QBNextConsecutiveBrokerFailures(failureCount, true, false);
   bool rejectionThreshold = QBBrokerFailureThresholdReached(failureCount, 3);
   failureCount = QBNextConsecutiveBrokerFailures(failureCount, true, true);
   bool acceptanceResets = failureCount == 0;

   bool entryPolicy = buySame && buyFavorable && buyAdverseRejected &&
                      sellSame && sellFavorable && sellAdverseRejected;
   bool actionPolicy = clearWhenEmpty && retainPosition && retainOrder;
   bool transmissionPolicy = marketAccepted && marketPartial && marketApiFail &&
                             marketServerReject && pendingAccepted &&
                             pendingApiFail && pendingServerReject;
   bool pendingStatePolicy = missingHistoryRetained && unsafeFillRetained &&
                             safeFillResolved && canceledResolved &&
                             deleteFailureRetained && deleteSuccessCleared;
   bool rejectionCounterPolicy = localRejectIgnored && rejectionThreshold &&
                                 acceptanceResets;
   detail = "entry=" + string(entryPolicy ? "bounded" : "FAILED") +
            " broker_action=" + string(actionPolicy ? "retained" : "FAILED") +
            " transmission=" + string(transmissionPolicy ? "server-confirmed" : "FAILED") +
            " pending_state=" + string(pendingStatePolicy ? "fail-closed" : "FAILED") +
            " reject_counter=" + string(rejectionCounterPolicy ? "latched" : "FAILED");
   return entryPolicy && actionPolicy && transmissionPolicy && pendingStatePolicy &&
          rejectionCounterPolicy;
}

bool QBTestBrokerFaultMatrix(string &detail)
{
   double tolerance = 0.01;

   bool exactProtected = QBProtectionDecision(POSITION_TYPE_BUY,
                                               99.0, 99.0,
                                               102.0, 102.0,
                                               tolerance, false) ==
                         QB_PROTECTION_ACCEPT;
   bool missingRequestsRepair = QBProtectionDecision(POSITION_TYPE_BUY,
                                                       0.0, 99.0,
                                                       102.0, 102.0,
                                                       tolerance, false) ==
                                QB_PROTECTION_REPAIR;
   bool looserRequestsRepair = QBProtectionDecision(POSITION_TYPE_SELL,
                                                      101.5, 101.0,
                                                      98.0, 98.0,
                                                      tolerance, false) ==
                               QB_PROTECTION_REPAIR;
   bool failedRepairEmerges = QBProtectionDecision(POSITION_TYPE_BUY,
                                                     0.0, 99.0,
                                                     0.0, 102.0,
                                                     tolerance, true) ==
                              QB_PROTECTION_EMERGENCY;
   bool safeStopSurvivesTargetFailure =
      QBProtectionDecision(POSITION_TYPE_BUY, 99.5, 99.0,
                           0.0, 102.0, tolerance, true) ==
      QB_PROTECTION_ACCEPT;

   bool modifyReject = !QBModificationAccepted(true, TRADE_RETCODE_INVALID_STOPS) &&
                       !QBModificationAccepted(false, TRADE_RETCODE_DONE);
   bool closeReject = !QBCloseAccepted(true, TRADE_RETCODE_REJECT) &&
                      !QBCloseAccepted(false, TRADE_RETCODE_DONE);
   bool deleteReject = !QBDeleteAccepted(true, TRADE_RETCODE_REJECT) &&
                       !QBDeleteAccepted(false, TRADE_RETCODE_DONE);
   bool retryOnlyPrice = QBIsRetryableSubmissionRetcode(TRADE_RETCODE_REQUOTE) &&
                         QBIsRetryableSubmissionRetcode(TRADE_RETCODE_PRICE_CHANGED) &&
                         QBIsRetryableSubmissionRetcode(TRADE_RETCODE_PRICE_OFF) &&
                         !QBIsRetryableSubmissionRetcode(TRADE_RETCODE_INVALID_STOPS) &&
                         !QBIsRetryableSubmissionRetcode(TRADE_RETCODE_NO_MONEY);

   bool fillDuringCancelRetained =
      !QBPendingHistoryResolved(true, ORDER_STATE_FILLED, false);
   bool protectedFillResolves =
      QBPendingHistoryResolved(true, ORDER_STATE_FILLED, true);
   bool failedCloseRetainsFlatten = QBShouldRetainBrokerAction(1, 0);
   bool failedDeleteRetainsCancel = QBShouldRetainBrokerAction(0, 1);

   bool protectionPolicy = exactProtected && missingRequestsRepair &&
                           looserRequestsRepair && failedRepairEmerges &&
                           safeStopSurvivesTargetFailure;
   bool responsePolicy = modifyReject && closeReject && deleteReject &&
                         retryOnlyPrice;
   bool racePolicy = fillDuringCancelRetained && protectedFillResolves &&
                     failedCloseRetainsFlatten && failedDeleteRetainsCancel;

   detail = "protection=" + string(protectionPolicy ? "repair/emergency" : "FAILED") +
            " responses=" + string(responsePolicy ? "server-confirmed" : "FAILED") +
            " cancel_fill=" + string(racePolicy ? "retained" : "FAILED") +
            " close_owner=central";
   return protectionPolicy && responsePolicy && racePolicy;
}

bool QBTestPerformanceWithoutFileJournal(string &detail)
{
   CTradeJournal journal;
   PositionContext ctx;
   ZeroMemory(ctx);
   ctx.strategy_id = "PERF_FIXTURE";
   ctx.signal_id = 1;
   ctx.entry_time = TimeCurrent() - 60;
   ctx.position_type = POSITION_TYPE_BUY;
   ctx.original_entry = 100.0;
   ctx.original_stop = 99.0;
   ctx.initial_target = 102.0;
   ctx.initial_volume = 0.10;
   ctx.entry_regime_trend = TREND_NEUTRAL;

   journal.LogTrade(ctx, 101.0, 10.0, -1.0, 0.0,
                    EXIT_TARGET_HIT, TREND_NEUTRAL, VOL_NORMAL);
   PerformanceSummary perf = journal.GetPerformance();
   bool ok = perf.total_trades == 1 && perf.winning_trades == 1 &&
             MathAbs(perf.net_profit - 9.0) <= 1e-9 &&
             MathAbs(perf.avg_r - 1.0) <= 1e-9;
   detail = "trades=" + IntegerToString(perf.total_trades) +
            " net=" + DoubleToString(perf.net_profit, 2) +
            " avgR=" + DoubleToString(perf.avg_r, 2) +
            " file=disabled";
   return ok;
}

bool QBTestKillSwitchFailurePriority(string &detail)
{
   CKillSwitch equityFloor;
   equityFloor.CheckConditions(false, false, false, true,
                               false, false, true, false);
   bool floorLatched = equityFloor.IsEmergency() &&
                       equityFloor.IsEntryKill() &&
                       equityFloor.IsCancelAll() &&
                       equityFloor.IsFlattenAll();

   CKillSwitch rejection;
   rejection.CheckConditions(false, true, false, false,
                              false, false, true, false);
   bool rejectionLatched = rejection.IsEntryKill() &&
                           !rejection.IsEmergency();
   rejection.CheckConditions(false, false, false, false,
                              false, false, false, false);
   rejectionLatched = rejectionLatched && rejection.IsEntryKill();

   CKillSwitch connectivityOnly;
   connectivityOnly.CheckConditions(false, false, false, false,
                                     false, false, true, false);
   bool disconnectedBlocked = connectivityOnly.IsEntryKill() &&
                              !connectivityOnly.IsEmergency();
   connectivityOnly.CheckConditions(false, false, false, false,
                                     false, false, false, false);
   bool transientRecovered = !connectivityOnly.IsEntryKill();

   bool modePolicy = !QBModeAllowsBrokerActions(QB_MODE_DIAGNOSTIC) &&
                     !QBModeAllowsBrokerActions(QB_MODE_SHADOW) &&
                     QBModeAllowsBrokerActions(QB_MODE_CONSERVATIVE_LIVE) &&
                     QBModeAllowsBrokerActions(QB_MODE_CHALLENGE_LIVE);
   ulong lastAttempt = 0;
   bool firstAttempt = QBBrokerActionAttemptDue(1000, 1000, lastAttempt);
   bool earlyRetryBlocked = !QBBrokerActionAttemptDue(1500, 1000, lastAttempt);
   bool boundaryRetryAllowed = QBBrokerActionAttemptDue(2000, 1000, lastAttempt);
   bool retryPolicy = firstAttempt && earlyRetryBlocked && boundaryRetryAllowed;

   detail = "floor=" + string(floorLatched ? "emergency" : "FAILED") +
            " rejection=" + string(rejectionLatched ? "latched" : "FAILED") +
            " connectivity=" + string(disconnectedBlocked && transientRecovered ?
                                         "transient" : "FAILED") +
            " broker_mode=" + string(modePolicy ? "live-only" : "FAILED") +
            " retry=" + string(retryPolicy ? "bounded" : "FAILED");
   return floorLatched && rejectionLatched && disconnectedBlocked &&
          transientRecovered && modePolicy && retryPolicy;
}

bool QBTestChallengeRestorePolicy(string &detail)
{
   CChallengeMode challenge;
   challenge.Init(true, true,
                  130.0, 200.0, 350.0, 600.0, 1000.0,
                  3.0, 2.5, 2.0, 1.5, 1.0,
                  30.0, 3, 50.0, false);

   ChallengeState saved;
   ZeroMemory(saved);
   saved.stage = CHALLENGE_STAGE_1;
   saved.stage_start_equity = 130.0;
   saved.stage_peak = 160.0;
   saved.attempts_this_stage = 1;
   saved.stage_target = 1.0;
   saved.risk_percent = 99.0;
   saved.profit_locked = 145.0;

   bool restored = challenge.RestoreState(saved);
   ChallengeState actual = challenge.GetState();
   bool configAuthoritative = restored &&
                              MathAbs(actual.risk_percent - 2.5) <= QB_EPSILON &&
                              MathAbs(actual.stage_target - 200.0) <= QB_EPSILON &&
                              actual.max_attempts == 3;

   ChallengeState corrupt = saved;
   corrupt.stage_peak = 120.0;
   bool corruptRejected = !challenge.RestoreState(corrupt, false) && !challenge.IsActive();

   detail = "risk=" + string(configAuthoritative ? "configured" : "FAILED") +
            " corrupt=" + string(corruptRejected ? "rejected" : "FAILED");
   return configAuthoritative && corruptRejected;
}

bool QBTestChallengeSafetyFlattenPolicy(string &detail)
{
   CChallengeMode profitLock;
   profitLock.Init(true, true,
                   130.0, 200.0, 350.0, 600.0, 1000.0,
                   3.0, 2.5, 2.0, 1.5, 1.0,
                   30.0, 3, 50.0, false);
   profitLock.Update(100.0, 100.0);
   profitLock.Update(120.0, 120.0);
   string lockReason = "";
   bool lockFlatten = profitLock.ConsumeSafetyBreach(109.0, lockReason, false) &&
                      !profitLock.IsActive() &&
                      profitLock.GetState().stage == CHALLENGE_STAGE_FAILED;

   CChallengeMode drawdown;
   drawdown.Init(true, true,
                 130.0, 200.0, 350.0, 600.0, 1000.0,
                 3.0, 2.5, 2.0, 1.5, 1.0,
                 10.0, 3, 50.0, false);
   drawdown.Update(100.0, 100.0);
   drawdown.Update(120.0, 120.0);
   drawdown.Update(107.0, 107.0, false);
   string ddReason = "";
   bool ddFlatten = drawdown.ConsumeSafetyBreach(107.0, ddReason) &&
                    !drawdown.IsActive() &&
                    drawdown.GetState().stage == CHALLENGE_STAGE_FAILED;

   detail = "profit_lock=" + string(lockFlatten ? "flatten" : "FAILED") +
            " drawdown=" + string(ddFlatten ? "flatten" : "FAILED");
   return lockFlatten && ddFlatten;
}

bool QBTestChallengeCashFlowPolicy(string &detail)
{
   bool types = QBIsExternalCashFlowDealType(DEAL_TYPE_BALANCE) &&
                QBIsExternalCashFlowDealType(DEAL_TYPE_CREDIT) &&
                QBIsExternalCashFlowDealType(DEAL_TYPE_BONUS) &&
                !QBIsExternalCashFlowDealType(DEAL_TYPE_BUY) &&
                !QBIsExternalCashFlowDealType(DEAL_TYPE_SELL);

   CChallengeMode challenge;
   challenge.Init(true, true,
                  130.0, 200.0, 350.0, 600.0, 1000.0,
                  3.0, 2.5, 2.0, 1.5, 1.0,
                  30.0, 3, 50.0, false);
   challenge.Update(100.0, 100.0);
   string flowReason = "";
   bool contaminated = challenge.ApplyExternalCashFlow(25.0, flowReason, false);
   string flattenReason = "";
   bool flatten = challenge.ConsumeSafetyBreach(125.0, flattenReason, false);

   detail = "types=" + string(types ? "classified" : "FAILED") +
            " deposit=" + string(contaminated && flatten ? "fail-closed" : "FAILED");
   return types && contaminated && flatten && !challenge.IsActive() &&
          challenge.GetState().risk_percent == 0.0;
}

bool QBTestShadowPendingOrderLifecycle(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(adapter.Symbol(), SYMBOL_ASK);
   if(bid <= 0 || ask <= bid) { detail = "quote unavailable"; return false; }
   double spread = ask - bid;
   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   double volume = adapter.NormalizeVolume(adapter.MinLot());
   MarketSnapshot snap; ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5; snap.spread_points = spread / adapter.Point();
   RegimeState regime; ZeroMemory(regime);
   FeatureSnapshot features; ZeroMemory(features);
   ShadowCloseEvent events[];
   string reason = "";

   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               false, 0.0, 0.0, false, 0.0, 0.0,
               false, 0.0, 0.0, false, 0);

   double limitPrice = bid - 2.0 * distance;
   if(!shadow.OpenPending("SELFTEST", 100, ORDER_TYPE_BUY_LIMIT,
                          limitPrice, limitPrice - distance, limitPrice + 2.0 * distance,
                          volume, 0, reason))
   { detail = "pending place failed: " + reason; return false; }

   if(shadow.GetPendingCount() != 1 || shadow.GetActivePendingCount() != 1)
   { detail = "pending count mismatch"; return false; }

   MarketSnapshot trigger = snap;
   trigger.bid = limitPrice - 0.5 * distance;
   trigger.ask = trigger.bid + spread;
   if(shadow.Update(trigger, features, events) != 0 ||
      shadow.GetPositionCount() != 1 ||
      shadow.GetActivePendingCount() != 0)
   { detail = "pending did not fill into position"; return false; }

   MarketSnapshot stopSnap = trigger;
   stopSnap.bid = limitPrice - distance - 0.5 * distance;
   stopSnap.ask = stopSnap.bid + spread;
   if(shadow.Update(stopSnap, features, events) != 1 ||
      events[0].exit_reason != EXIT_STOP_LOSS ||
      events[0].net_pnl >= 0)
   { detail = "pending-filled position stop failed"; return false; }

   CShadowPortfolio shadow2;
   shadow2.Init(adapter, 10000.0, 0.0, 0.0,
                false, 0.0, 0.0, false, 0.0, 0.0,
                false, 0.0, 0.0, false, 0);
   if(!shadow2.OpenPending("SELFTEST", 101, ORDER_TYPE_SELL_LIMIT,
                           ask + 2.0 * distance,
                           ask + 3.0 * distance,
                           ask + 2.0 * distance - 2.0 * distance,
                           volume, 0, reason))
   { detail = "sell limit place failed: " + reason; return false; }
   if(!shadow2.CancelPending(101, reason))
   { detail = "cancel failed: " + reason; return false; }
   if(shadow2.GetActivePendingCount() != 0 || shadow2.GetPositionCount() != 0)
   { detail = "cancel did not clear pending"; return false; }

   detail = "placed=filled stop=loss cancel=cancelled";
   return true;
}

// Regression for the 2026-07-20 live-fill vs restart comment-parsing
// inconsistency: QBStrategyIdFromComment() must be the single source of
// truth both paths use, and must truncate at a second underscore so a
// fixture-style comment (or any future annotated comment) still resolves
// to the real strategy id rather than an unrecognized string.
bool QBTestStrategyIdFromComment(string &detail)
{
   if(QBStrategyIdFromComment("QB_FBO") != "FBO")
   { detail = "plain comment failed"; return false; }
   if(QBStrategyIdFromComment("QB_FBO_fixture") != "FBO")
   { detail = "suffixed comment failed"; return false; }
   if(QBStrategyIdFromComment("QB_BO_fixture_owned") != "BO")
   { detail = "multi-suffix comment failed"; return false; }
   if(QBStrategyIdFromComment("QB fixture owned") != "UNKNOWN")
   { detail = "missing-prefix comment wrongly accepted"; return false; }
   if(QBStrategyIdFromComment("FIXTURE_UNKNOWN") != "UNKNOWN")
   { detail = "no-prefix comment wrongly accepted"; return false; }
   if(QBStrategyIdFromComment("QB_NOTASTRATEGY") != "UNKNOWN")
   { detail = "unknown strategy id wrongly accepted"; return false; }

   detail = "plain=FBO suffixed=FBO multi=BO noPrefix=UNKNOWN unknownId=UNKNOWN";
   return true;
}

// Regression for the 2026-07-20 pending-order restart reconstruction
// feature: QBBuildPendingExecutionRecord() must map every broker-recoverable
// field correctly, use the order ticket as a stable request_id substitute,
// preserve the true ORDER_TIME_SETUP as request_time (not "now"), and the
// resulting comment must still resolve through QBStrategyIdFromComment() the
// same way it would at live-fill or restart time.
bool QBTestPendingExecutionRecordBuild(string &detail)
{
   ulong ticket = 999888777;
   datetime setup = D'2026.07.20 00:00:00';
   ExecutionRecord rec = QBBuildPendingExecutionRecord(ticket, ORDER_TYPE_BUY_LIMIT,
                                                        4000.00, 3950.00, 4100.00,
                                                        "QB_FBO_fixture_pending", setup);

   if(rec.order_ticket != ticket || rec.request_id != ticket)
   { detail = "ticket/request_id mismatch"; return false; }
   if(rec.order_type != ORDER_TYPE_BUY_LIMIT)
   { detail = "order_type mismatch"; return false; }
   if(MathAbs(rec.requested_price - 4000.00) > QB_EPSILON ||
      MathAbs(rec.stop_loss - 3950.00) > QB_EPSILON ||
      MathAbs(rec.take_profit - 4100.00) > QB_EPSILON)
   { detail = "price/sl/tp mismatch"; return false; }
   if(rec.comment != "QB_FBO_fixture_pending")
   { detail = "comment mismatch"; return false; }
   if(rec.request_time != setup)
   { detail = "request_time not set from order setup time"; return false; }
   if(rec.state != QB_ORDER_STATE_SUBMITTED)
   { detail = "state mismatch"; return false; }
   if(QBStrategyIdFromComment(rec.comment) != "FBO")
   { detail = "reconstructed record's comment does not resolve to expected strategy"; return false; }

   detail = "ticket=matched type=matched prices=matched time=setup strategy=FBO";
   return true;
}

//+------------------------------------------------------------------+
//| TEST 52: new entry trigger modes — probe-confirm and rejection,  |
//| plus fail-closed on a mode the strategy does not support.        |
//+------------------------------------------------------------------+
bool QBTestTriggerModes(CSymbolAdapter &adapter, string &detail)
{
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);

   // BO PROBE_CONFIRM: strong body closing near the high beyond the range high.
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.preceding_compression_bars = 8; f.htf_aligned = true; f.htf_slope = 1.0;
   f.current_range_low = market.ask - 4.0 * d;
   f.current_range_high = market.ask - d;
   f.closed_open = market.ask - 1.5 * d;
   f.closed_close = market.ask - 0.4 * d;   // beyond range high, strong up bar
   f.closed_high = market.ask - 0.4 * d;    // close == high (tiny upper wick)
   f.closed_low = market.ask - 1.6 * d;
   f.displacement = 1.2;

   CBreakoutEngine boProbe;
   boProbe.Init("BO_PC", "BO probe", true, 0.0, adapter, TRIGGER_PROBE_CONFIRM,
                5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE);
   bool probeTriggers = boProbe.EvaluateLong(market, f, regime).valid;

   f.displacement = 0.5;                    // weak body -> probe must fail
   bool probeWeakRejected = !boProbe.EvaluateLong(market, f, regime).valid;

   // BO REJECTION is unsupported for a breakout -> fail-closed (no trigger).
   f.displacement = 1.2;
   CBreakoutEngine boRej;
   boRej.Init("BO_RJ", "BO rej", true, 0.0, adapter, TRIGGER_REJECTION,
              5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE);
   bool rejFailClosed = !boRej.EvaluateLong(market, f, regime).valid;

   // MR REJECTION: fires with a directional lower rejection wick present.
   FeatureSnapshot m; ZeroMemory(m);
   m.atr = d; m.slope_norm = 0.0; m.rejection_wick = 0.6;
   m.sd_dist = -2.0; m.rejection_wick_lower = 0.6;
   m.closed_open = market.ask - 0.2 * d; m.closed_close = market.ask; // up candle
   m.current_range_low = market.ask - 2.0 * d;
   m.vwap = market.ask + 2.0 * d; m.range_midpoint = market.ask + d; m.vwap_sd = d;
   CMeanReversionEngine mrRej;
   mrRej.Init("MR_RJ", "MR rej", true, 0.0, adapter, TRIGGER_REJECTION,
              0.25, 1.5, 0.3, 1.0, 1.0);
   bool mrRejTriggers = mrRej.EvaluateLong(market, m, regime).valid;

   detail = "probe=" + (probeTriggers ? "ok" : "FAIL") +
            " probeWeak=" + (probeWeakRejected ? "ok" : "FAIL") +
            " rejFailClosed=" + (rejFailClosed ? "ok" : "FAIL") +
            " mrRej=" + (mrRejTriggers ? "ok" : "FAIL");
   return probeTriggers && probeWeakRejected && rejFailClosed && mrRejTriggers;
}

//+------------------------------------------------------------------+
//| TEST 53: level-source selection — a breakout keyed to the        |
//| previous-day high triggers where a range-keyed one would not.    |
//+------------------------------------------------------------------+
bool QBTestLevelSource(CSymbolAdapter &adapter, string &detail)
{
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);

   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.preceding_compression_bars = 8; f.htf_aligned = true; f.htf_slope = 1.0;
   f.closed_open = market.ask - 1.0 * d;
   f.closed_close = market.ask - 0.3 * d;
   f.current_range_low = market.ask - 4.0 * d;
   f.current_range_high = market.ask + 0.5 * d;  // close is below range high
   f.prev_day_high = market.ask - 0.6 * d;       // close is above prev-day high
   f.prev_day_low = market.ask - 5.0 * d;

   CBreakoutEngine boRange;
   boRange.Init("BO_R", "BO range", true, 0.0, adapter, TRIGGER_CANDLE_CLOSE_BREAK,
                5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE);
   bool rangeNoTrigger = !boRange.EvaluateLong(market, f, regime).valid;

   CBreakoutEngine boPrev;
   boPrev.Init("BO_P", "BO prevday", true, 0.0, adapter, TRIGGER_CANDLE_CLOSE_BREAK,
               5, 2.0, 1.0, 1.5, true, LEVEL_SRC_PREV_DAY);
   bool prevTriggers = boPrev.EvaluateLong(market, f, regime).valid;

   detail = "rangeNoTrigger=" + (rangeNoTrigger ? "ok" : "FAIL") +
            " prevTriggers=" + (prevTriggers ? "ok" : "FAIL");
   return rangeNoTrigger && prevTriggers;
}

//+------------------------------------------------------------------+
//| TEST 54: stop/target mode dispatch — an alternative stop/target  |
//| mode produces a different, correct placement than the default.   |
//+------------------------------------------------------------------+
bool QBTestStopTargetModes(CSymbolAdapter &adapter, string &detail)
{
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);

   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.preceding_compression_bars = 8; f.htf_aligned = true; f.htf_slope = 1.0;
   f.current_range_low = market.ask - 4.0 * d;
   f.current_range_high = market.ask - d;
   f.closed_open = market.ask - 1.5 * d;
   f.closed_close = market.ask - 0.4 * d;   // beyond range high
   f.vwap = market.ask + 3.0 * d;           // above entry, for VWAP-target test

   // Default BO long: stop = rangeHigh - 1*atr = ask-2d.
   CBreakoutEngine boDef;
   boDef.Init("BO_D", "BO def", true, 0.0, adapter, TRIGGER_CANDLE_CLOSE_BREAK,
              5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE, STOP_MODE_DEFAULT, TARGET_MODE_DEFAULT);
   StrategySignal sDef = boDef.EvaluateLong(market, f, regime);

   // ATR stop mode: stop = entry - 1*atr = ask-d (differs from default).
   CBreakoutEngine boAtr;
   boAtr.Init("BO_A", "BO atr", true, 0.0, adapter, TRIGGER_CANDLE_CLOSE_BREAK,
              5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE, STOP_MODE_ATR, TARGET_MODE_DEFAULT);
   StrategySignal sAtr = boAtr.EvaluateLong(market, f, regime);
   bool atrDiffers = sAtr.valid && sDef.valid &&
                     MathAbs(sAtr.proposed_stop - sDef.proposed_stop) > 2 * adapter.Point();
   double expectAtr = adapter.NormalizePrice(sAtr.proposed_entry - 1.0 * d);
   bool atrCorrect = MathAbs(sAtr.proposed_stop - expectAtr) <= 2 * adapter.Point();

   // VWAP target mode: target == VWAP.
   CBreakoutEngine boVwap;
   boVwap.Init("BO_V", "BO vwap", true, 0.0, adapter, TRIGGER_CANDLE_CLOSE_BREAK,
               5, 2.0, 1.0, 1.5, true, LEVEL_SRC_RANGE, STOP_MODE_DEFAULT, TARGET_MODE_VWAP);
   StrategySignal sVwap = boVwap.EvaluateLong(market, f, regime);
   bool vwapTargetOK = sVwap.valid &&
                       MathAbs(sVwap.proposed_target - adapter.NormalizePrice(f.vwap)) <= 2 * adapter.Point();

   detail = "defValid=" + (sDef.valid ? "ok" : "FAIL") +
            " atrDiffers=" + (atrDiffers ? "ok" : "FAIL") +
            " atrCorrect=" + (atrCorrect ? "ok" : "FAIL") +
            " vwapTarget=" + (vwapTargetOK ? "ok" : "FAIL");
   return sDef.valid && atrDiffers && atrCorrect && vwapTargetOK;
}

//+------------------------------------------------------------------+
//| TEST 55: additive exit types — a regime-deterioration shock      |
//| closes an open shadow position; a normal bar leaves it open.     |
//+------------------------------------------------------------------+
bool QBTestExtendedExits(CSymbolAdapter &adapter, string &detail)
{
   double bid = SymbolInfoDouble(adapter.Symbol(), SYMBOL_BID);
   if(bid <= 0) bid = 2500.0;
   bid = adapter.NormalizePrice(bid);
   double ask = adapter.NormalizePrice(bid + 10.0 * adapter.Point());

   CShadowPortfolio shadow;
   shadow.Init(adapter, 10000.0, 0.0, 0.0,
               false, 0.0, 0.0, false, 0.0, 0.0,
               false, 0.0, 0.0, false, 0);
   shadow.SetExtendedExits(false, 0, 0.0, true, 3.0);  // regime-deterioration exit on

   double distance = MathMax(100.0, adapter.StopLevel() + 20.0) * adapter.Point();
   MarketSnapshot snap; ZeroMemory(snap);
   snap.time = TimeCurrent(); snap.bid = bid; snap.ask = ask;
   snap.mid = (bid + ask) * 0.5; snap.spread_points = (ask - bid) / adapter.Point();
   snap.is_fresh = true; snap.is_tradeable = true;

   StrategySignal signal; ZeroMemory(signal);
   signal.valid = true; signal.strategy_id = "SELFTEST"; signal.direction = ORDER_TYPE_BUY;
   signal.signal_time = TimeCurrent(); signal.proposed_entry = ask;
   signal.proposed_stop = adapter.NormalizePrice(ask - distance);
   signal.proposed_target = adapter.NormalizePrice(ask + distance * 3.0);
   RegimeState regime; ZeroMemory(regime);
   double volume = adapter.NormalizeVolume(adapter.MinLot());
   string reason = "";
   if(!shadow.Open(signal, volume, regime, snap, 1, reason))
   { detail = "open failed: " + reason; return false; }

   // Normal bar (no shock), price between stop and target -> stays open.
   FeatureSnapshot fq; ZeroMemory(fq);
   fq.atr = distance; fq.abnormal_candle = false; fq.atr_ratio = 1.0;
   ShadowCloseEvent ev1[];
   int c1 = shadow.Update(snap, fq, ev1);
   bool stayedOpen = (c1 == 0 && shadow.GetPositionCount() == 1);

   // Shock candle -> regime-deterioration exit closes the position.
   fq.abnormal_candle = true;
   ShadowCloseEvent ev2[];
   int c2 = shadow.Update(snap, fq, ev2);
   bool regimeClosed = (c2 == 1 && ArraySize(ev2) == 1 &&
                        ev2[0].exit_reason == EXIT_REGIME_DETERIORATE &&
                        shadow.GetPositionCount() == 0);

   detail = "stayedOpen=" + (stayedOpen ? "ok" : "FAIL") +
            " regimeExit=" + (regimeClosed ? "ok" : "FAIL");
   return stayedOpen && regimeClosed;
}

//+------------------------------------------------------------------+
//| TEST 56: challenge-mode pyramiding gate — only active + configured|
//| + winning + protected additions are permitted.                   |
//+------------------------------------------------------------------+
bool QBTestChallengePyramiding(string &detail)
{
   // Pyramiding OFF: never allowed, even for a winning protected position.
   CChallengeMode chalOff;
   chalOff.Init(true, true, 130, 200, 350, 600, 1000,
                3.0, 2.5, 2.0, 1.5, 1.0, 30.0, 3, 50.0, false);
   bool offBlocks = !chalOff.IsPyramidingAllowed(true, true);

   // Pyramiding ON: allowed only for winning + protected.
   CChallengeMode chalOn;
   chalOn.Init(true, true, 130, 200, 350, 600, 1000,
               3.0, 2.5, 2.0, 1.5, 1.0, 30.0, 3, 50.0, true);
   bool onWinProt   = chalOn.IsPyramidingAllowed(true, true);
   bool onLosing    = !chalOn.IsPyramidingAllowed(false, true);
   bool onUnprot    = !chalOn.IsPyramidingAllowed(true, false);

   // Inactive challenge (not acknowledged) never allows pyramiding.
   CChallengeMode chalInactive;
   chalInactive.Init(false, false, 130, 200, 350, 600, 1000,
                     3.0, 2.5, 2.0, 1.5, 1.0, 30.0, 3, 50.0, true);
   bool inactiveBlocks = !chalInactive.IsPyramidingAllowed(true, true);

   detail = "offBlocks=" + (offBlocks ? "ok" : "FAIL") +
            " onWinProt=" + (onWinProt ? "ok" : "FAIL") +
            " onLosing=" + (onLosing ? "ok" : "FAIL") +
            " onUnprot=" + (onUnprot ? "ok" : "FAIL") +
            " inactive=" + (inactiveBlocks ? "ok" : "FAIL");
   return offBlocks && onWinProt && onLosing && onUnprot && inactiveBlocks;
}

//+------------------------------------------------------------------+
//| TEST 57: allocation engine — equal weight is a no-op (1.0 each), |
//| confidence weighting reallocates while conserving the budget.    |
//+------------------------------------------------------------------+
bool QBTestAllocationEngine(string &detail)
{
   // Equal mode: every strategy weight is exactly 1.0 (baseline preserved).
   CAllocationEngine eq;
   eq.Init(ALLOC_EQUAL);
   eq.RecordSignal("BO", 0.9);
   eq.RecordSignal("MR", 0.5);
   bool equalOne = MathAbs(eq.GetWeight("BO") - 1.0) < 1e-9 &&
                   MathAbs(eq.GetWeight("MR") - 1.0) < 1e-9;

   // Confidence mode: the higher-confidence strategy gets weight > 1, the
   // lower gets < 1, and the mean of the two weights stays 1.0 (budget conserved).
   CAllocationEngine cf;
   cf.Init(ALLOC_CONFIDENCE);
   cf.RecordSignal("BO", 0.9);
   cf.RecordSignal("MR", 0.3);
   double wBO = cf.GetWeight("BO");
   double wMR = cf.GetWeight("MR");
   bool confHigherBO = (wBO > wMR) && (wBO > 1.0) && (wMR < 1.0);
   bool conserved = MathAbs((wBO + wMR) / 2.0 - 1.0) < 0.02;

   detail = "equalOne=" + (equalOne ? "ok" : "FAIL") +
            " confHigherBO=" + (confHigherBO ? "ok" : "FAIL") +
            " conserved=" + (conserved ? "ok" : "FAIL") +
            " wBO=" + DoubleToString(wBO, 2) + " wMR=" + DoubleToString(wMR, 2);
   return equalOne && confHigherBO && conserved;
}

//+------------------------------------------------------------------+
//| TEST 58: CounterfactualTracker buffers only rejected signals that|
//| carry a computable hypothetical trade, is a no-op when disabled, |
//| and is side-effect-free (no file I/O until Close).               |
//+------------------------------------------------------------------+
bool QBTestCounterfactualTracker(string &detail)
{
   MarketSnapshot  snap;      // zero-initialized context is sufficient;
   RegimeState     regime;    // LogRejection gates purely on the signal fields.
   FeatureSnapshot feat;
   ZeroMemory(snap);
   ZeroMemory(regime);
   ZeroMemory(feat);

   // Build a rejected signal that nonetheless has full geometry.
   StrategySignal rej;
   rej.valid           = false;
   rej.strategy_id     = "BO";
   rej.direction       = ORDER_TYPE_BUY;
   rej.signal_time     = D'2026.04.21 10:00:00';
   rej.proposed_entry  = 2000.0;
   rej.proposed_stop   = 1995.0;
   rej.proposed_target = 2010.0;
   rej.expected_reward_r = 2.0;
   rej.confidence      = 0.7;
   rej.rejection_code  = REJECT_ARBITRATION_LOST;
   rej.reason          = "arb-loss";

   // Enabled tracker buffers the rejected+geometry signal.
   CCounterfactualTracker t;
   t.Init(true, true);
   t.LogRejection(rej, snap, regime, feat, "XAUUSD");
   bool buffered = (t.RowCount() == 1);

   // A VALID signal (not rejected) must be ignored.
   StrategySignal valid = rej;
   valid.valid = true;
   t.LogRejection(valid, snap, regime, feat, "XAUUSD");
   bool ignoresValid = (t.RowCount() == 1);

   // A rejected signal with no computable geometry must be ignored.
   StrategySignal noGeo = rej;
   noGeo.proposed_stop = 0.0;
   t.LogRejection(noGeo, snap, regime, feat, "XAUUSD");
   bool ignoresNoGeo = (t.RowCount() == 1);

   // A disabled tracker is a pure no-op.
   CCounterfactualTracker off;
   off.Init(false, true);
   off.LogRejection(rej, snap, regime, feat, "XAUUSD");
   bool disabledNoop = (off.RowCount() == 0);

   detail = "buffered=" + (buffered ? "ok" : "FAIL") +
            " ignoresValid=" + (ignoresValid ? "ok" : "FAIL") +
            " ignoresNoGeo=" + (ignoresNoGeo ? "ok" : "FAIL") +
            " disabledNoop=" + (disabledNoop ? "ok" : "FAIL");
   return buffered && ignoresValid && ignoresNoGeo && disabledNoop;
}

//+------------------------------------------------------------------+
//| TEST 59: CExposureManager owns the aggregate-exposure limit policy|
//| -- the pre-sizing capacity gate and the post-sizing projection --|
//| identically to the checks it replaced in CRiskEngine.            |
//+------------------------------------------------------------------+
bool QBTestExposureManager(string &detail)
{
   CExposureManager ex;
   ex.Init(2.0);   // cap = 2.0 lots (matches default InpMaxTotalExposureLots)

   // Pre-sizing gate: at/over the cap blocks; under the cap does not.
   bool capGate = ex.AtCapacity(2.0) && ex.AtCapacity(2.5) && !ex.AtCapacity(1.9);

   // Post-sizing projection: current + add must not breach the cap.
   bool projUnder = !ex.WouldExceed(1.5, 0.5);   // 2.0 == cap, allowed
   bool projOver  =  ex.WouldExceed(1.5, 0.6);    // 2.1 > cap, blocked
   bool projEdge  = !ex.WouldExceed(0.0, 2.0);    // exactly the cap, allowed

   // Headroom accounting, floored at zero.
   bool remOk = MathAbs(ex.Remaining(1.5) - 0.5) < 1e-9 &&
                MathAbs(ex.Remaining(3.0) - 0.0) < 1e-9;

   detail = "capGate=" + (capGate ? "ok" : "FAIL") +
            " projUnder=" + (projUnder ? "ok" : "FAIL") +
            " projOver=" + (projOver ? "ok" : "FAIL") +
            " projEdge=" + (projEdge ? "ok" : "FAIL") +
            " remOk=" + (remOk ? "ok" : "FAIL");
   return capGate && projUnder && projOver && projEdge && remOk;
}

//+------------------------------------------------------------------+
//| TEST 60: CReconciliation turns reconstruction counts + the        |
//| unknown-position policy into the startup recovery verdict, exactly|
//| as the former inline OnInit logic did. This is the decision core  |
//| CRecoveryEngine delegates to.                                     |
//+------------------------------------------------------------------+
bool QBTestReconciliationVerdict(string &detail)
{
   ReconciliationResult clean;   clean.reconstructed=2; clean.unknown=0; clean.unprotected=0;
   ReconciliationResult unkQ;    unkQ.reconstructed=1;  unkQ.unknown=1;  unkQ.unprotected=0;
   ReconciliationResult unkI;    unkI.reconstructed=1;  unkI.unknown=1;  unkI.unprotected=0;
   ReconciliationResult unprot;  unprot.reconstructed=1; unprot.unknown=0; unprot.unprotected=1;
   ReconciliationResult both;    both.reconstructed=0;  both.unknown=1;  both.unprotected=1;

   ReconciliationVerdict vClean = CReconciliation::Classify(clean,  UNKNOWN_QUARANTINE);
   ReconciliationVerdict vUnkQ  = CReconciliation::Classify(unkQ,   UNKNOWN_QUARANTINE);
   ReconciliationVerdict vUnkI  = CReconciliation::Classify(unkI,   UNKNOWN_IGNORE);
   ReconciliationVerdict vUnpr  = CReconciliation::Classify(unprot, UNKNOWN_QUARANTINE);
   ReconciliationVerdict vBoth  = CReconciliation::Classify(both,   UNKNOWN_QUARANTINE);

   bool cleanOk = !vClean.need_quarantine && !vClean.need_emergency;
   // unknown under QUARANTINE -> quarantine; under IGNORE -> no quarantine.
   bool unkQok  =  vUnkQ.need_quarantine && !vUnkQ.need_emergency;
   bool unkIok  = !vUnkI.need_quarantine && !vUnkI.need_emergency;
   // unprotected always forces emergency, independent of ownership policy.
   bool unprOk  = !vUnpr.need_quarantine &&  vUnpr.need_emergency;
   // both conditions fire independently.
   bool bothOk  =  vBoth.need_quarantine &&  vBoth.need_emergency;

   detail = "clean=" + (cleanOk ? "ok" : "FAIL") +
            " unkQuarantine=" + (unkQok ? "ok" : "FAIL") +
            " unkIgnore=" + (unkIok ? "ok" : "FAIL") +
            " unprotected=" + (unprOk ? "ok" : "FAIL") +
            " both=" + (bothOk ? "ok" : "FAIL");
   return cleanOk && unkQok && unkIok && unprOk && bothOk;
}

//+------------------------------------------------------------------+
//| TEST 61: batch metadata and reachability proof for all four      |
//| current strategy families. Validates family/template tags in one |
//| pass so the workflow can inspect the full set together.          |
//+------------------------------------------------------------------+
bool QBTestStrategyBatchMetadata(CSymbolAdapter &adapter, string &detail)
{
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);

   bool boOk = false;
   bool fboOk = false;
   bool tpOk = false;
   bool mrOk = false;

   // Breakout: range breakout template.
   {
      CBreakoutEngine strategy;
      strategy.Init("BO_BATCH", "BO batch", true, 0.0, adapter,
                    TRIGGER_CANDLE_CLOSE_BREAK, 5, 2.0, 1.0, 1.5, true,
                    LEVEL_SRC_RANGE, STOP_MODE_DEFAULT, TARGET_MODE_DEFAULT);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d; f.preceding_compression_bars = 8; f.htf_aligned = true;
      f.htf_slope = 1.0;
      f.current_range_low = market.ask - 4.0 * d;
      f.current_range_high = market.ask - d;
      f.closed_open = market.ask - 1.5 * d;
      f.closed_close = market.ask - 0.4 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      boOk = sig.valid && sig.strategy_id == STRATEGY_ID_BREAKOUT &&
             sig.strategy_family == "breakout" &&
             sig.strategy_template == "range_breakout" &&
             StringFind(sig.strategy_tags, "family=breakout") >= 0 &&
             StringFind(sig.strategy_tags, "template=range_breakout") >= 0 &&
             strategy.GetStrategyFamily() == "breakout" &&
             strategy.GetStrategyTemplate() == "range_breakout";
   }

   // Failed breakout: reclaim reversal template.
   {
      CFailedBreakoutEngine strategy;
      strategy.Init("FBO_BATCH", "FBO batch", true, 0.0, adapter,
                    TRIGGER_CANDLE_CLOSE_BREAK, 3.0, 3, 0.3, 0.5, 1.0, 1.5);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d; f.failed_breakout = true; f.reclaim_detected = true;
      f.failed_breakout_down = true; f.bars_beyond_level = 1;
      f.breakout_dist = 5.0 * adapter.Point();
      f.reclaim_level = market.ask - 2.0 * d;
      f.sweep_extreme = f.reclaim_level - d;
      f.closed_close = market.ask;
      f.vwap = market.ask + 6.0 * d; f.range_midpoint = market.ask + 5.0 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      fboOk = sig.valid && sig.strategy_id == STRATEGY_ID_FAILED_BREAKOUT &&
              sig.strategy_family == "failed_breakout" &&
              sig.strategy_template == "reclaim_reversal" &&
              StringFind(sig.strategy_tags, "family=failed_breakout") >= 0 &&
              StringFind(sig.strategy_tags, "template=reclaim_reversal") >= 0 &&
              strategy.GetStrategyFamily() == "failed_breakout" &&
              strategy.GetStrategyTemplate() == "reclaim_reversal";
   }

   // Trend pullback: pullback-resume template.
   {
      CTrendPullbackEngine strategy;
      strategy.Init("TP_BATCH", "TP batch", true, 0.0, adapter,
                    TRIGGER_IMMEDIATE_BREAK, 0.4, 5, true, 0.618, 20, 1.5, 0.5);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d; f.dir_efficiency = 0.8; f.trend_persistence = 10;
      f.htf_aligned = true; f.returning_to_value = true;
      regime.trend = TREND_STRONG_UP;
      regime.structure = STRUCTURE_PULLBACK;
      f.swing_high = market.mid + d; f.swing_high_bars = 6;
      f.swing_low = market.mid - 4.0 * d; f.swing_low_bars = 6;
      f.current_range_high = f.swing_high; f.current_range_low = f.swing_low;
      f.closed_open = market.mid - 0.2 * d; f.closed_close = market.mid + 0.2 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      tpOk = sig.valid && sig.strategy_id == STRATEGY_ID_TREND_PULLBACK &&
             sig.strategy_family == "trend_pullback" &&
             sig.strategy_template == "pullback_resume" &&
             StringFind(sig.strategy_tags, "family=trend_pullback") >= 0 &&
             StringFind(sig.strategy_tags, "template=pullback_resume") >= 0 &&
             strategy.GetStrategyFamily() == "trend_pullback" &&
             strategy.GetStrategyTemplate() == "pullback_resume";
   }

   // Mean reversion: value reversion template.
   {
      QBMakeNormalRegime(regime);
      CMeanReversionEngine strategy;
      strategy.Init("MR_BATCH", "MR batch", true, 0.0, adapter,
                    TRIGGER_REJECTION, 0.25, 1.5, 0.3, 1.0, 1.0);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d; f.slope_norm = 0.0; f.rejection_wick = 0.6;
      f.sd_dist = -2.0; f.rejection_wick_lower = 0.6;
      f.closed_open = market.ask - 0.2 * d; f.closed_close = market.ask;
      f.current_range_low = market.ask - 2.0 * d;
      f.vwap = market.ask + 2.0 * d; f.range_midpoint = market.ask + d; f.vwap_sd = d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      mrOk = sig.valid && sig.strategy_id == STRATEGY_ID_MEAN_REVERSION &&
             sig.strategy_family == "mean_reversion" &&
             sig.strategy_template == "value_reversion" &&
             StringFind(sig.strategy_tags, "family=mean_reversion") >= 0 &&
             StringFind(sig.strategy_tags, "template=value_reversion") >= 0 &&
             strategy.GetStrategyFamily() == "mean_reversion" &&
             strategy.GetStrategyTemplate() == "value_reversion";
   }

   bool tagOk = boOk && fboOk && tpOk && mrOk;

   detail = "BO=" + (boOk ? "ok" : "FAIL") +
            " FBO=" + (fboOk ? "ok" : "FAIL") +
            " TP=" + (tpOk ? "ok" : "FAIL") +
            " MR=" + (mrOk ? "ok" : "FAIL") +
            " tagged=" + (tagOk ? "yes" : "no");
   return boOk && fboOk && tpOk && mrOk && tagOk;
}

//+------------------------------------------------------------------+
//| TEST 62: batch overlap map for the current expansion candidates.  |
//| Validates that opening-range/session breakout variants and a      |
//| session-sourced failed-breakout candidate can all be exercised in |
//| one synthetic pass, which is the batch substrate for later gap    |
//| analysis and ML feature export.                                   |
//+------------------------------------------------------------------+
bool QBTestStrategyOverlapMap(CSymbolAdapter &adapter, string &detail)
{
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);

   bool orbOk = false;
   bool brcOk = false;
   bool ssrOk = false;

   // Opening-range breakout variant: same BO family, different level source.
   {
      CBreakoutEngine strategy;
      strategy.Init("BO_ORB_BATCH", "BO ORB batch", true, 0.0, adapter,
                    TRIGGER_CANDLE_CLOSE_BREAK, 5, 2.0, 1.5, 1.5, true,
                    LEVEL_SRC_OPENING_RANGE, STOP_MODE_DEFAULT, TARGET_MODE_DEFAULT);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d;
      f.preceding_compression_bars = 8;
      f.htf_aligned = true;
      f.htf_slope = 1.0;
      f.current_range_low = market.ask - 2.0 * d;
      f.current_range_high = market.ask + 0.4 * d;
      f.closed_open = market.ask + 0.1 * d;
      f.closed_close = market.ask + 0.25 * d;
      f.or_low = market.ask - 3.0 * d;
      f.or_high = market.ask - 0.15 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      orbOk = sig.valid &&
              sig.strategy_id == STRATEGY_ID_BREAKOUT &&
              sig.strategy_template == "opening_range_breakout" &&
              StringFind(sig.strategy_tags, "level_source=opening_range") >= 0 &&
              strategy.GetStrategyTemplate() == "opening_range_breakout";
   }

   // Session breakout variant: same BO family, session level source.
   {
      CBreakoutEngine strategy;
      strategy.Init("BO_SESSION_BATCH", "BO session batch", true, 0.0, adapter,
                    TRIGGER_CANDLE_CLOSE_BREAK, 5, 2.0, 1.5, 1.5, true,
                    LEVEL_SRC_SESSION, STOP_MODE_DEFAULT, TARGET_MODE_DEFAULT);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d;
      f.preceding_compression_bars = 8;
      f.htf_aligned = true;
      f.htf_slope = 1.0;
      f.current_range_low = market.ask - 2.0 * d;
      f.current_range_high = market.ask + 0.4 * d;
      f.closed_open = market.ask + 0.1 * d;
      f.closed_close = market.ask + 0.25 * d;
      f.session_low = market.ask - 3.0 * d;
      f.session_high = market.ask - 0.1 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      brcOk = sig.valid &&
              sig.strategy_id == STRATEGY_ID_BREAKOUT &&
              sig.strategy_template == "session_breakout" &&
              StringFind(sig.strategy_tags, "level_source=session") >= 0 &&
              strategy.GetStrategyTemplate() == "session_breakout";
   }

   // Session-sourced failed breakout: overlap candidate for SSR-style work.
   {
      CFailedBreakoutEngine strategy;
      strategy.Init("FBO_SESSION_BATCH", "FBO session batch", true, 0.0, adapter,
                    TRIGGER_CANDLE_CLOSE_BREAK, 3.0, 3, 0.3, 0.5, 1.0, 1.5,
                    STOP_MODE_DEFAULT, TARGET_MODE_DEFAULT, LEVEL_SRC_SESSION);
      FeatureSnapshot f; ZeroMemory(f);
      f.atr = d;
      f.failed_breakout = true;
      f.reclaim_detected = true;
      f.failed_breakout_down = true;
      f.bars_beyond_level = 1;
      f.breakout_dist = 5.0 * adapter.Point();
      f.reclaim_level = market.ask - 2.0 * d;
      f.sweep_extreme = f.reclaim_level - d;
      f.closed_close = market.ask;
      f.vwap = market.ask + 6.0 * d;
      f.range_midpoint = market.ask + 5.0 * d;
      StrategySignal sig = strategy.EvaluateLong(market, f, regime);
      ssrOk = sig.valid &&
              sig.strategy_id == STRATEGY_ID_FAILED_BREAKOUT &&
              sig.strategy_family == "failed_breakout" &&
              sig.strategy_template == "reclaim_reversal" &&
              StringFind(sig.strategy_tags, "level_source=session") >= 0 &&
              strategy.GetStrategyFamily() == "failed_breakout";
   }

   bool overlapOk = orbOk && brcOk && ssrOk;

   detail = "ORB=" + (orbOk ? "ok" : "FAIL") +
            " BRC=" + (brcOk ? "ok" : "FAIL") +
            " SSR=" + (ssrOk ? "ok" : "FAIL") +
            " overlap=" + (overlapOk ? "yes" : "no");
   return overlapOk;
}

#endif // QB_SAFETYTESTS_MQH
