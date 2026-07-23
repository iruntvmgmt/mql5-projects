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
#include "../Analytics/TPOutcomeTracker.mqh"
#include "../Execution/RecoveryEngine.mqh"
#include "../Strategies/BreakoutEngine.mqh"
#include "../Strategies/FailedBreakoutEngine.mqh"
#include "../Strategies/TrendPullbackEngine.mqh"
#include "../Strategies/TrendPullbackV2Engine.mqh"
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

   FeatureSnapshot thresholdProbe;
   ZeroMemory(thresholdProbe);
   thresholdProbe.slope_norm = 0.25;
   thresholdProbe.dir_efficiency = 0.5;
   thresholdProbe.trend_persistence = 6;
   thresholdProbe.displacement = 1.2;
   thresholdProbe.atr_ratio = 1.0;
   thresholdProbe.spread_percentile = 10.0;
   thresholdProbe.tick_freq = 10.0;
   thresholdProbe.quote_stable = true;
   RegimeState baselineThreshold = engine.Classify(thresholdProbe, SESSION_LONDON_OPEN, EVENT_NORMAL);

   CRegimeEngine lowered;
   lowered.Init(true, 0.2, 20.0, 3.0, 3);
   RegimeState loweredThreshold = lowered.Classify(thresholdProbe, SESSION_LONDON_OPEN, EVENT_NORMAL);
   bool coherentThreshold = baselineThreshold.structure == STRUCTURE_BALANCED &&
                            loweredThreshold.structure == STRUCTURE_IMPULSE;

   thresholdProbe.displacement = 0.8;
   CRegimeEngine defaultDisplacement;
   defaultDisplacement.Init(true, 0.2, 20.0, 3.0, 3, 1.0);
   RegimeState defaultDispState = defaultDisplacement.Classify(thresholdProbe, SESSION_LONDON_OPEN, EVENT_NORMAL);
   CRegimeEngine loweredDisplacement;
   loweredDisplacement.Init(true, 0.2, 20.0, 3.0, 3, 0.6);
   RegimeState loweredDispState = loweredDisplacement.Classify(thresholdProbe, SESSION_LONDON_OPEN, EVENT_NORMAL);
   bool coherentDisplacement = defaultDispState.structure == STRUCTURE_BALANCED &&
                               loweredDispState.structure == STRUCTURE_IMPULSE;

   f.abnormal_candle = true;
   RegimeState shock = engine.Classify(f, SESSION_LONDON_OPEN, EVENT_NORMAL);
   bool shockSafe = engine.IsSafeForTrading();

   detail = "healthy=" + EnumToString(healthy.trend) + "/" +
            EnumToString(healthy.volatility) + "/" +
            EnumToString(healthy.liquidity) + "/" +
            EnumToString(healthy.structure) +
            " shock=" + EnumToString(shock.volatility) +
            " threshold=" + EnumToString(baselineThreshold.structure) + "->" +
            EnumToString(loweredThreshold.structure) +
            " displacement=" + EnumToString(defaultDispState.structure) + "->" +
            EnumToString(loweredDispState.structure);
   return healthy.trend == TREND_STRONG_UP &&
          healthy.volatility == VOL_NORMAL &&
          healthy.liquidity == LIQUIDITY_GOOD &&
          healthy.structure == STRUCTURE_ACCEPTED_BREAKOUT &&
          healthySafe && shock.volatility == VOL_SHOCK && !shockSafe &&
          coherentThreshold && coherentDisplacement;
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
   // Regression for the fifth-strategy cardinality audit (2026-07-23):
   // QBIsKnownStrategyId() initially omitted STRATEGY_ID_TREND_PULLBACK_V2,
   // meaning any real TPV2-owned position/order comment would resolve to
   // UNKNOWN at both live-fill and restart time -- never actively managed.
   if(QBStrategyIdFromComment("QB_TPV2") != "TPV2")
   { detail = "TPV2 plain comment failed"; return false; }
   if(QBStrategyIdFromComment("QB_TPV2_fixture") != "TPV2")
   { detail = "TPV2 suffixed comment failed"; return false; }

   detail = "plain=FBO suffixed=FBO multi=BO noPrefix=UNKNOWN unknownId=UNKNOWN tpv2=TPV2";
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
      strategy.Init(STRATEGY_ID_BREAKOUT, "BO batch", true, 0.0, adapter,
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
      strategy.Init(STRATEGY_ID_FAILED_BREAKOUT, "FBO batch", true, 0.0, adapter,
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
      strategy.Init(STRATEGY_ID_TREND_PULLBACK, "TP batch", true, 0.0, adapter,
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
      strategy.Init(STRATEGY_ID_MEAN_REVERSION, "MR batch", true, 0.0, adapter,
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
      strategy.Init(STRATEGY_ID_BREAKOUT, "BO ORB batch", true, 0.0, adapter,
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
              StringFind(sig.strategy_tags, "level=opening_range") >= 0 &&
              strategy.GetStrategyTemplate() == "opening_range_breakout";
   }

   // Session breakout variant: same BO family, session level source.
   {
      CBreakoutEngine strategy;
      strategy.Init(STRATEGY_ID_BREAKOUT, "BO session batch", true, 0.0, adapter,
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
              StringFind(sig.strategy_tags, "level=session") >= 0 &&
              strategy.GetStrategyTemplate() == "session_breakout";
   }

   // Session-sourced failed breakout: overlap candidate for SSR-style work.
   {
      CFailedBreakoutEngine strategy;
      strategy.Init(STRATEGY_ID_FAILED_BREAKOUT, "FBO session batch", true, 0.0, adapter,
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
              StringFind(sig.strategy_tags, "level=session") >= 0 &&
              strategy.GetStrategyFamily() == "failed_breakout";
   }

   bool overlapOk = orbOk && brcOk && ssrOk;

   detail = "ORB=" + (orbOk ? "ok" : "FAIL") +
            " BRC=" + (brcOk ? "ok" : "FAIL") +
            " SSR=" + (ssrOk ? "ok" : "FAIL") +
            " overlap=" + (overlapOk ? "yes" : "no");
   return overlapOk;
}

//+------------------------------------------------------------------+
//| TEST 63: near-value location and movement diagnostics remain      |
//| distinct. Eligibility still consumes the legacy location flag;   |
//| these fields support evidence before a strategy-behavior change. |
//+------------------------------------------------------------------+
bool QBTestValueReturnDiagnostics(string &detail)
{
   FeatureSnapshot approaching; ZeroMemory(approaching);
   approaching.previous_norm_dist_vwap = 0.8;
   approaching.norm_dist_vwap = 0.5;
   approaching.value_return_progress = MathAbs(approaching.previous_norm_dist_vwap) -
                                       MathAbs(approaching.norm_dist_vwap);
   approaching.moving_toward_value = approaching.value_return_progress > QB_EPSILON;
   approaching.returning_to_value = MathAbs(approaching.norm_dist_vwap) < 0.3;

   FeatureSnapshot departing; ZeroMemory(departing);
   departing.previous_norm_dist_vwap = 0.1;
   departing.norm_dist_vwap = 0.2;
   departing.value_return_progress = MathAbs(departing.previous_norm_dist_vwap) -
                                     MathAbs(departing.norm_dist_vwap);
   departing.moving_toward_value = departing.value_return_progress > QB_EPSILON;
   departing.returning_to_value = MathAbs(departing.norm_dist_vwap) < 0.3;

   FeatureSnapshot crossing; ZeroMemory(crossing);
   crossing.previous_norm_dist_vwap = -0.6;
   crossing.norm_dist_vwap = -0.2;
   crossing.crossed_into_value = MathAbs(crossing.previous_norm_dist_vwap) >= 0.3 &&
                                 MathAbs(crossing.norm_dist_vwap) < 0.3;

   bool ok = approaching.moving_toward_value && !approaching.returning_to_value &&
             !departing.moving_toward_value && departing.returning_to_value &&
             crossing.crossed_into_value;
   detail = "approach=" + (approaching.moving_toward_value ? "moving" : "FAIL") +
            " depart=" + (!departing.moving_toward_value ? "distinct" : "FAIL") +
            " cross=" + (crossing.crossed_into_value ? "yes" : "FAIL");
   return ok;
}

//+------------------------------------------------------------------+
//| TEST 64: observational TP lifecycle advances once per closed bar  |
//| and does not itself authorize a signal.                           |
//+------------------------------------------------------------------+
bool QBTestTPLifecycleObservation(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   strategy.Init("TP_LIFECYCLE_TEST", "TP lifecycle", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 0.4, 5, false, 0.618, 3, 1.5, 0.5);
   MarketSnapshot market; double d;
   QBMakeSyntheticMarket(adapter, market, d);
   RegimeState regime; QBMakeNormalRegime(regime);
   regime.trend = TREND_STRONG_UP;
   FeatureSnapshot f; ZeroMemory(f);
   f.atr = d; f.dir_efficiency = 0.8; f.trend_persistence = 10;
   f.current_range_low = market.mid - 4.0 * d;
   f.current_range_high = market.mid + 2.0 * d;
   f.swing_high = f.current_range_high; f.swing_low = f.current_range_low;

   f.calc_time = 1; f.closed_open = market.mid; f.closed_close = market.mid + d;
   regime.structure = STRUCTURE_IMPULSE;
   strategy.EvaluateLong(market, f, regime);
   bool impulse = strategy.GetLifecyclePhase() == "impulse";

   f.calc_time = 2; f.moving_toward_value = true;
   f.closed_open = market.mid + d; f.closed_close = market.mid;
   regime.structure = STRUCTURE_BALANCED;
   strategy.EvaluateLong(market, f, regime);
   int barsAfterLong = strategy.GetLifecycleBars();
   strategy.EvaluateShort(market, f, regime); // same bar must not advance twice
   bool retracing = strategy.GetLifecyclePhase() == "retracing" &&
                    strategy.GetLifecycleBars() == barsAfterLong;

   f.calc_time = 3; f.moving_toward_value = false;
   f.closed_open = market.mid; f.closed_close = market.mid + d;
   strategy.EvaluateLong(market, f, regime);
   bool resumed = strategy.GetLifecyclePhase() == "resume_candidate";

   f.calc_time = 4;
   regime.trend = TREND_STRONG_DOWN;
   strategy.EvaluateLong(market, f, regime);
   bool invalidated = strategy.GetLifecyclePhase() == "invalidated";

   CTrendPullbackEngine tpSpecific;
   tpSpecific.Init("TP_SPECIFIC_SEED_TEST", "TP specific seed", true, 0.0, adapter,
                   TRIGGER_CANDLE_CLOSE_BREAK, 0.4, 5, false, 0.618, 3, 1.5, 0.5);
   RegimeState seedRegime; QBMakeNormalRegime(seedRegime);
   seedRegime.trend = TREND_WEAK_UP;
   seedRegime.structure = STRUCTURE_BALANCED;
   FeatureSnapshot seed; ZeroMemory(seed);
   seed.calc_time = 10; seed.atr = d; seed.dir_efficiency = 0.6;
   seed.trend_persistence = 6; seed.displacement = 0.4;
   seed.closed_open = market.mid; seed.closed_close = market.mid + 0.4 * d;
   seed.closed_high = market.mid + 0.5 * d; seed.closed_low = market.mid - 0.1 * d;
   tpSpecific.EvaluateLong(market, seed, seedRegime);
   bool specificSeed = tpSpecific.GetLifecyclePhase() == "impulse" &&
                       tpSpecific.GetLifecycleDirection() == "up" &&
                       tpSpecific.GetLifecycleSeedSource() == "tp_specific" &&
                       tpSpecific.GetImpulseStartTime() == 10 &&
                       MathAbs(tpSpecific.GetImpulseStartPrice() - seed.closed_open) <= QB_EPSILON &&
                       tpSpecific.GetImpulseSpanATR() >= 0.49;

   detail = "impulse=" + (impulse ? "yes" : "FAIL") +
            " retrace=" + (retracing ? "yes" : "FAIL") +
            " resume=" + (resumed ? "yes" : "FAIL") +
            " invalid=" + (invalidated ? "yes" : "FAIL") +
            " tpSeed=" + (specificSeed ? "yes" : "FAIL");
   return impulse && retracing && resumed && invalidated && specificSeed;
}

//+------------------------------------------------------------------+
//| Shared fixtures for the TP outcome tracker tests (65-74) below.   |
//| Both drive a fresh CTrendPullbackEngine deterministically through |
//| impulse -> retracing -> resume_candidate, mirroring Test 64's own |
//| bar-by-bar recipe (STRUCTURE_IMPULSE seed, then moving_toward_    |
//| value=true for one bar, then an aligned candle with                |
//| moving_toward_value=false to resume).                              |
//+------------------------------------------------------------------+
void QBDriveTPToResumeCandidate(CSymbolAdapter &adapter, CTrendPullbackEngine &strategy,
                                MarketSnapshot &market, FeatureSnapshot &f, RegimeState &regime,
                                int direction, datetime baseTime)
{
   strategy.Init("TP_OUTCOME_TEST", "TP outcome test", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 0.4, 5, false, 0.618, 3, 1.5, 0.5);
   double d;
   QBMakeSyntheticMarket(adapter, market, d);
   QBMakeNormalRegime(regime);
   regime.trend = (direction > 0) ? TREND_STRONG_UP : TREND_STRONG_DOWN;

   ZeroMemory(f);
   f.atr = d; f.dir_efficiency = 0.8; f.trend_persistence = 10;
   f.current_range_low = market.mid - 4.0 * d;
   f.current_range_high = market.mid + 2.0 * d;
   f.swing_high = f.current_range_high; f.swing_low = f.current_range_low;

   // Bar 1: shared STRUCTURE_IMPULSE seed, aligned candle in trend direction.
   f.calc_time = baseTime;
   f.closed_open = market.mid;
   f.closed_close = market.mid + direction * d;
   regime.structure = STRUCTURE_IMPULSE;
   strategy.EvaluateLong(market, f, regime);

   // Bar 2: moving toward value -> retracing. Counter-trend candle.
   f.calc_time = baseTime + 1;
   f.moving_toward_value = true;
   f.closed_open = market.mid + direction * d;
   f.closed_close = market.mid;
   regime.structure = STRUCTURE_BALANCED;
   strategy.EvaluateLong(market, f, regime);

   // Bar 3: pullback ends, aligned candle -> resume_candidate.
   f.calc_time = baseTime + 2;
   f.moving_toward_value = false;
   f.closed_open = market.mid;
   f.closed_close = market.mid + direction * d;
   strategy.EvaluateLong(market, f, regime);
}

//+------------------------------------------------------------------+
//| Same recipe, but with bar 1's close and bar 3's open/close placed |
//| at explicit ATR offsets from market.mid, so a test can target a   |
//| precise impulse_extreme/impulse_start_price/ref_price triple --   |
//| used only by the retracement-depth table test (74). Always the up |
//| direction; depth math is direction-symmetric.                     |
//+------------------------------------------------------------------+
void QBDriveTPToResumeCandidateCustom(CSymbolAdapter &adapter, CTrendPullbackEngine &strategy,
                                      MarketSnapshot &market, FeatureSnapshot &f, RegimeState &regime,
                                      datetime baseTime, double bar1CloseOffsetATR,
                                      double bar3OpenOffsetATR, double bar3CloseOffsetATR)
{
   strategy.Init("TP_OUTCOME_TEST", "TP outcome test", true, 0.0, adapter,
                 TRIGGER_CANDLE_CLOSE_BREAK, 0.4, 5, false, 0.618, 3, 1.5, 0.5);
   double d;
   QBMakeSyntheticMarket(adapter, market, d);
   QBMakeNormalRegime(regime);
   regime.trend = TREND_STRONG_UP;

   ZeroMemory(f);
   f.atr = d; f.dir_efficiency = 0.8; f.trend_persistence = 10;
   f.current_range_low = market.mid - 4.0 * d;
   f.current_range_high = market.mid + 2.0 * d;
   f.swing_high = f.current_range_high; f.swing_low = f.current_range_low;

   f.calc_time = baseTime;
   f.closed_open = market.mid;
   f.closed_close = market.mid + bar1CloseOffsetATR * d;
   regime.structure = STRUCTURE_IMPULSE;
   strategy.EvaluateLong(market, f, regime);

   f.calc_time = baseTime + 1;
   f.moving_toward_value = true;
   f.closed_open = f.closed_close;
   f.closed_close = market.mid;
   regime.structure = STRUCTURE_BALANCED;
   strategy.EvaluateLong(market, f, regime);

   f.calc_time = baseTime + 2;
   f.moving_toward_value = false;
   f.closed_open = market.mid + bar3OpenOffsetATR * d;
   f.closed_close = market.mid + bar3CloseOffsetATR * d;
   strategy.EvaluateLong(market, f, regime);
}

//+------------------------------------------------------------------+
//| TEST 65: deterministic event IDs.                                  |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeEventID(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine s1, s2, s3;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;

   CTPOutcomeTracker t1;
   t1.Init(true, true);
   QBDriveTPToResumeCandidate(adapter, s1, m, f, r, 1, 100);
   t1.CheckAndRegister(s1, m, f, r, "XAUUSD");
   string id1 = t1.GetPending(0).event_id;

   CTPOutcomeTracker t2;
   t2.Init(true, true);
   QBDriveTPToResumeCandidate(adapter, s2, m, f, r, 1, 100);
   t2.CheckAndRegister(s2, m, f, r, "XAUUSD");
   string id2 = t2.GetPending(0).event_id;

   CTPOutcomeTracker t3;
   t3.Init(true, true);
   QBDriveTPToResumeCandidate(adapter, s3, m, f, r, 1, 200);
   t3.CheckAndRegister(s3, m, f, r, "XAUUSD");
   string id3 = t3.GetPending(0).event_id;

   bool sameInputsSameID = (id1 == id2) && id1 != "";
   bool differentTimeDifferentID = (id1 != id3);

   detail = "id1=" + id1 + " id3=" + id3 +
            " sameInputsSameID=" + (sameInputsSameID ? "yes" : "FAIL") +
            " differentTimeDifferentID=" + (differentTimeDifferentID ? "yes" : "FAIL");
   return sameInputsSameID && differentTimeDifferentID;
}

//+------------------------------------------------------------------+
//| TEST 66: exactly one event registers despite a hypothetical extra |
//| same-bar invocation (BUY/SELL pairing risk), via the tracker's own |
//| internal dedupe -- independent of the EA's call-site placement.    |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeRegistrationDedup(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 300);

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");   // simulates the real post-EvaluateShort hook
   strategy.EvaluateShort(m, f, r);                    // same-bar no-op per ObserveLifecycle's own guard
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");   // hypothetical duplicate invocation

   int total = t.PendingCount() + (int)t.TotalFinalized();
   bool onlyOne = (total == 1) && (t.TotalRegistered() == 1);
   detail = "pending=" + IntegerToString(t.PendingCount()) +
            " finalized=" + IntegerToString((int)t.TotalFinalized()) +
            " registered=" + IntegerToString((int)t.TotalRegistered()) +
            " onlyOne=" + (onlyOne ? "yes" : "FAIL");
   return onlyOne;
}

//+------------------------------------------------------------------+
//| TEST 67: MFE/MAE sign orientation is correct for both directions -- |
//| the same relative bar shape (bigger rally than dip) is favorable    |
//| for an up-nominated event and adverse for a down-nominated one.     |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeSignOrientation(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine sUp;
   MarketSnapshot mUp; FeatureSnapshot fUp; RegimeState rUp;
   QBDriveTPToResumeCandidate(adapter, sUp, mUp, fUp, rUp, 1, 400);
   CTPOutcomeTracker tUp;
   tUp.Init(true, true);
   tUp.CheckAndRegister(sUp, mUp, fUp, rUp, "XAUUSD");
   double refUp = tUp.GetPending(0).ref_price;
   double atrUp = tUp.GetPending(0).atr_ref;
   FeatureSnapshot barUp; ZeroMemory(barUp);
   barUp.calc_time = 1000;
   barUp.closed_high = refUp + 0.6 * atrUp;
   barUp.closed_low  = refUp - 0.3 * atrUp;
   barUp.closed_close = refUp + 0.1 * atrUp;
   tUp.UpdatePending(barUp);
   TPOutcomeEvent up = tUp.GetPending(0);
   bool upOK = MathAbs(up.mfe_atr[0] - 0.6) <= 0.01 && MathAbs(up.mae_atr[0] - 0.3) <= 0.01;

   CTrendPullbackEngine sDown;
   MarketSnapshot mDown; FeatureSnapshot fDown; RegimeState rDown;
   QBDriveTPToResumeCandidate(adapter, sDown, mDown, fDown, rDown, -1, 500);
   CTPOutcomeTracker tDown;
   tDown.Init(true, true);
   tDown.CheckAndRegister(sDown, mDown, fDown, rDown, "XAUUSD");
   double refDown = tDown.GetPending(0).ref_price;
   double atrDown = tDown.GetPending(0).atr_ref;
   FeatureSnapshot barDown; ZeroMemory(barDown);
   barDown.calc_time = 1000;
   barDown.closed_high = refDown + 0.6 * atrDown;
   barDown.closed_low  = refDown - 0.3 * atrDown;
   barDown.closed_close = refDown + 0.1 * atrDown;
   tDown.UpdatePending(barDown);
   TPOutcomeEvent down = tDown.GetPending(0);
   bool downOK = MathAbs(down.mfe_atr[0] - 0.3) <= 0.01 && MathAbs(down.mae_atr[0] - 0.6) <= 0.01;

   detail = "up.mfe=" + DoubleToString(up.mfe_atr[0], 3) + " up.mae=" + DoubleToString(up.mae_atr[0], 3) +
            " down.mfe=" + DoubleToString(down.mfe_atr[0], 3) + " down.mae=" + DoubleToString(down.mae_atr[0], 3) +
            " upOK=" + (upOK ? "yes" : "FAIL") + " downOK=" + (downOK ? "yes" : "FAIL");
   return upOK && downOK;
}

//+------------------------------------------------------------------+
//| TEST 68: direction is frozen at registration -- invalidating the   |
//| live engine afterward must not retroactively change the stored     |
//| event.                                                              |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeDirectionImmutability(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 600);

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");
   string before = t.GetPending(0).direction;

   f.calc_time = 603;
   r.trend = TREND_STRONG_DOWN;
   strategy.EvaluateLong(m, f, r);
   bool engineInvalidated = strategy.GetLifecyclePhase() == "invalidated";

   FeatureSnapshot bar; ZeroMemory(bar);
   bar.calc_time = 1000;
   bar.closed_high = m.mid + 0.1; bar.closed_low = m.mid - 0.1; bar.closed_close = m.mid;
   t.UpdatePending(bar);
   string after = t.GetPending(0).direction;

   bool unchanged = (before == after) && (before == "up");
   detail = "before=" + before + " after=" + after +
            " engineInvalidated=" + (engineInvalidated ? "yes" : "FAIL") +
            " unchanged=" + (unchanged ? "yes" : "FAIL");
   return unchanged && engineInvalidated;
}

//+------------------------------------------------------------------+
//| TEST 69: only genuinely future bars are folded into MFE/MAE. The   |
//| registration bar itself is untouched (bars_elapsed==0, MFE/MAE==0  |
//| immediately after registration), and the EA's real per-bar order   |
//| (UpdatePending runs in Step 7 before that bar's own registration   |
//| can happen in EvaluateAndTrade) is mirrored explicitly here.       |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeOnlyFutureBars(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 700);   // resumes at calc_time=702

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.UpdatePending(f);                                // mirrors Step 7 running before registration
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");    // registers at bar 702

   bool untouchedAtRegistration = (t.GetPending(0).bars_elapsed == 0) &&
                                  MathAbs(t.GetPending(0).mfe_atr[0]) <= QB_EPSILON &&
                                  MathAbs(t.GetPending(0).mae_atr[0]) <= QB_EPSILON;

   FeatureSnapshot bar703; ZeroMemory(bar703);
   bar703.calc_time = 703;
   double refPrice = t.GetPending(0).ref_price;
   double atrRef = t.GetPending(0).atr_ref;
   bar703.closed_high = refPrice + 0.2 * atrRef;
   bar703.closed_low  = refPrice - 0.05 * atrRef;
   bar703.closed_close = refPrice + 0.1 * atrRef;
   t.UpdatePending(bar703);

   TPOutcomeEvent e = t.GetPending(0);
   bool onlyForwardBarCounted = (e.bars_elapsed == 1) && MathAbs(e.mfe_atr[0] - 0.2) <= 0.01;

   detail = "untouchedAtRegistration=" + (untouchedAtRegistration ? "yes" : "FAIL") +
            " bars@703=" + IntegerToString(e.bars_elapsed) +
            " mfe@703=" + DoubleToString(e.mfe_atr[0], 3) +
            " onlyForwardBarCounted=" + (onlyForwardBarCounted ? "yes" : "FAIL");
   return untouchedAtRegistration && onlyForwardBarCounted;
}

//+------------------------------------------------------------------+
//| TEST 70: an incomplete horizon is never silently treated as         |
//| complete -- it is explicitly TRUNCATED with no fabricated close     |
//| return, while a horizon that did complete keeps its real value.     |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeTruncatedHorizon(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 800);   // resumes at calc_time=802

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");
   double refPrice = t.GetPending(0).ref_price;
   double atrRef = t.GetPending(0).atr_ref;

   for(int i = 1; i <= 5; i++)
   {
      FeatureSnapshot bar; ZeroMemory(bar);
      bar.calc_time = 802 + i;
      bar.closed_high = refPrice + 0.1 * atrRef;
      bar.closed_low  = refPrice - 0.05 * atrRef;
      bar.closed_close = refPrice + 0.05 * atrRef;
      t.UpdatePending(bar);
   }

   bool stillPending = (t.PendingCount() == 1);
   bool h3CompleteBeforeClose = t.GetPending(0).status[0] == "COMPLETE";

   t.Close();

   TPOutcomeEvent finalized = t.GetLastFinalized();
   bool h3Complete = finalized.status[0] == "COMPLETE";
   bool h6Truncated = finalized.status[1] == "TRUNCATED";
   bool h12Truncated = finalized.status[2] == "TRUNCATED";
   bool h24Truncated = finalized.status[3] == "TRUNCATED";

   detail = "h3=" + finalized.status[0] + " h6=" + finalized.status[1] +
            " h12=" + finalized.status[2] + " h24=" + finalized.status[3] +
            " stillPendingBeforeClose=" + (stillPending ? "yes" : "FAIL") +
            " h3CompleteBeforeClose=" + (h3CompleteBeforeClose ? "yes" : "FAIL");
   return stillPending && h3CompleteBeforeClose && h3Complete && h6Truncated && h12Truncated && h24Truncated;
}

//+------------------------------------------------------------------+
//| TEST 71: the tracker only reads the engine it observes -- every     |
//| public lifecycle accessor is byte-identical before/after            |
//| CheckAndRegister/UpdatePending. Its API takes no broker/risk/       |
//| arbitration object at all, so there is no execution surface to      |
//| touch in the first place.                                           |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeNoTradingSideEffects(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 900);   // resumes at calc_time=902

   string phaseBefore = strategy.GetLifecyclePhase();
   int barsBefore = strategy.GetLifecycleBars();
   string dirBefore = strategy.GetLifecycleDirection();
   string seedBefore = strategy.GetLifecycleSeedSource();
   datetime impStartTimeBefore = strategy.GetImpulseStartTime();
   double impStartPriceBefore = strategy.GetImpulseStartPrice();
   double impExtremeBefore = strategy.GetImpulseExtreme();
   double impSpanBefore = strategy.GetImpulseSpanATR();

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");

   FeatureSnapshot bar; ZeroMemory(bar);
   bar.calc_time = 903;
   bar.closed_high = t.GetPending(0).ref_price + 0.1;
   bar.closed_low  = t.GetPending(0).ref_price - 0.1;
   bar.closed_close = t.GetPending(0).ref_price;
   t.UpdatePending(bar);

   bool identical = (strategy.GetLifecyclePhase() == phaseBefore) &&
                    (strategy.GetLifecycleBars() == barsBefore) &&
                    (strategy.GetLifecycleDirection() == dirBefore) &&
                    (strategy.GetLifecycleSeedSource() == seedBefore) &&
                    (strategy.GetImpulseStartTime() == impStartTimeBefore) &&
                    MathAbs(strategy.GetImpulseStartPrice() - impStartPriceBefore) <= QB_EPSILON &&
                    MathAbs(strategy.GetImpulseExtreme() - impExtremeBefore) <= QB_EPSILON &&
                    MathAbs(strategy.GetImpulseSpanATR() - impSpanBefore) <= QB_EPSILON;

   detail = "phase=" + phaseBefore + " identicalAfterTrackerCalls=" + (identical ? "yes" : "FAIL");
   return identical;
}

//+------------------------------------------------------------------+
//| TEST 72: reinitialization clears in-memory state without touching   |
//| any persistence layer, so it cannot duplicate already-registered    |
//| events within the same run.                                         |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeReinitNoDuplication(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine strategy;
   MarketSnapshot m; FeatureSnapshot f; RegimeState r;
   QBDriveTPToResumeCandidate(adapter, strategy, m, f, r, 1, 1000);   // resumes at calc_time=1002

   CTPOutcomeTracker t;
   t.Init(true, true);
   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");
   string idBeforeReinit = t.GetPending(0).event_id;
   bool registeredOnce = (t.PendingCount() == 1) && (t.TotalRegistered() == 1);

   t.Init(true, true);   // simulates an OnInit re-entry within the same terminal session
   bool clearedOnReinit = (t.PendingCount() == 0) && (t.TotalRegistered() == 0) && (t.TotalFinalized() == 0);

   t.CheckAndRegister(strategy, m, f, r, "XAUUSD");
   string idAfterReinit = t.GetPending(0).event_id;
   bool freshRegistration = (t.PendingCount() == 1) && (t.TotalRegistered() == 1) &&
                            (idAfterReinit == idBeforeReinit);

   detail = "registeredOnce=" + (registeredOnce ? "yes" : "FAIL") +
            " clearedOnReinit=" + (clearedOnReinit ? "yes" : "FAIL") +
            " freshRegistration=" + (freshRegistration ? "yes" : "FAIL");
   return registeredOnce && clearedOnReinit && freshRegistration;
}

//+------------------------------------------------------------------+
//| TEST 73: a bar whose high and low both cross a threshold is         |
//| recorded as genuinely ambiguous rather than arbitrarily resolved,   |
//| while a bar crossing only one side stays unambiguous.                |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeThresholdAmbiguity(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine s1;
   MarketSnapshot m1; FeatureSnapshot f1; RegimeState r1;
   QBDriveTPToResumeCandidate(adapter, s1, m1, f1, r1, 1, 1100);
   CTPOutcomeTracker t1;
   t1.Init(true, true);
   t1.CheckAndRegister(s1, m1, f1, r1, "XAUUSD");
   double ref1 = t1.GetPending(0).ref_price;
   double atr1 = t1.GetPending(0).atr_ref;
   FeatureSnapshot bothBar; ZeroMemory(bothBar);
   bothBar.calc_time = 1200;
   bothBar.closed_high = ref1 + 0.4 * atr1;
   bothBar.closed_low  = ref1 - 0.4 * atr1;
   bothBar.closed_close = ref1;
   t1.UpdatePending(bothBar);
   TPOutcomeEvent e1 = t1.GetPending(0);
   bool ambiguous = (e1.first_threshold[0] == "AMBIGUOUS_SAME_BAR") &&
                    e1.reached_p25[0] > 0 && e1.reachedNeg_p25[0] > 0;

   CTrendPullbackEngine s2;
   MarketSnapshot m2; FeatureSnapshot f2; RegimeState r2;
   QBDriveTPToResumeCandidate(adapter, s2, m2, f2, r2, 1, 1300);
   CTPOutcomeTracker t2;
   t2.Init(true, true);
   t2.CheckAndRegister(s2, m2, f2, r2, "XAUUSD");
   double ref2 = t2.GetPending(0).ref_price;
   double atr2 = t2.GetPending(0).atr_ref;
   FeatureSnapshot favOnlyBar; ZeroMemory(favOnlyBar);
   favOnlyBar.calc_time = 1400;
   favOnlyBar.closed_high = ref2 + 0.4 * atr2;
   favOnlyBar.closed_low  = ref2 - 0.05 * atr2;
   favOnlyBar.closed_close = ref2;
   t2.UpdatePending(favOnlyBar);
   TPOutcomeEvent e2 = t2.GetPending(0);
   bool unambiguousFavorable = (e2.first_threshold[0] == "FAVORABLE") && (e2.reachedNeg_p25[0] == 0);

   detail = "case1=" + e1.first_threshold[0] + " case2=" + e2.first_threshold[0] +
            " ambiguous=" + (ambiguous ? "yes" : "FAIL") +
            " unambiguousFavorable=" + (unambiguousFavorable ? "yes" : "FAIL");
   return ambiguous && unambiguousFavorable;
}

//+------------------------------------------------------------------+
//| TEST 74: retracement depth is computed correctly across a partial,  |
//| near-full, and overshoot retrace, and a degenerate (zero-span)      |
//| impulse is skipped entirely rather than recording an undefined      |
//| depth.                                                               |
//+------------------------------------------------------------------+
bool QBTestTPOutcomeRetracementDepth(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine s1; MarketSnapshot m1; FeatureSnapshot f1; RegimeState r1;
   QBDriveTPToResumeCandidateCustom(adapter, s1, m1, f1, r1, 1500, 1.0, 0.0, 0.5);
   CTPOutcomeTracker t1; t1.Init(true, true);
   t1.CheckAndRegister(s1, m1, f1, r1, "XAUUSD");
   bool partial = (t1.PendingCount() == 1) && MathAbs(t1.GetPending(0).retracement_depth - 0.5) <= 0.02;

   CTrendPullbackEngine s2; MarketSnapshot m2; FeatureSnapshot f2; RegimeState r2;
   QBDriveTPToResumeCandidateCustom(adapter, s2, m2, f2, r2, 1600, 1.0, -0.5, 0.001);
   CTPOutcomeTracker t2; t2.Init(true, true);
   t2.CheckAndRegister(s2, m2, f2, r2, "XAUUSD");
   bool full = (t2.PendingCount() == 1) && MathAbs(t2.GetPending(0).retracement_depth - 1.0) <= 0.02;

   CTrendPullbackEngine s3; MarketSnapshot m3; FeatureSnapshot f3; RegimeState r3;
   QBDriveTPToResumeCandidateCustom(adapter, s3, m3, f3, r3, 1700, 1.0, -0.5, -0.2);
   CTPOutcomeTracker t3; t3.Init(true, true);
   t3.CheckAndRegister(s3, m3, f3, r3, "XAUUSD");
   bool overshoot = (t3.PendingCount() == 1) && (t3.GetPending(0).retracement_depth > 1.0);

   CTrendPullbackEngine s4; MarketSnapshot m4; FeatureSnapshot f4; RegimeState r4;
   QBDriveTPToResumeCandidateCustom(adapter, s4, m4, f4, r4, 1800, 0.0, -0.1, 0.1);
   bool degenerateReachedResume = (s4.GetLifecyclePhase() == "resume_candidate");
   CTPOutcomeTracker t4; t4.Init(true, true);
   t4.CheckAndRegister(s4, m4, f4, r4, "XAUUSD");
   bool degenerateSkipped = (t4.PendingCount() == 0) && (t4.TotalRegistered() == 0);

   detail = "partialDepth=" + DoubleToString(t1.GetPending(0).retracement_depth, 3) +
            " fullDepth=" + DoubleToString(t2.GetPending(0).retracement_depth, 3) +
            " overshootDepth=" + DoubleToString(t3.GetPending(0).retracement_depth, 3) +
            " degenerateReachedResume=" + (degenerateReachedResume ? "yes" : "FAIL") +
            " degenerateSkipped=" + (degenerateSkipped ? "yes" : "FAIL") +
            " partial=" + (partial ? "yes" : "FAIL") + " full=" + (full ? "yes" : "FAIL") +
            " overshoot=" + (overshoot ? "yes" : "FAIL");
   return partial && full && overshoot && degenerateReachedResume && degenerateSkipped;
}

//+------------------------------------------------------------------+
//| TP V2 (see TP_V2_STATE_MACHINE.md) deterministic fixtures.        |
//| Drives a fresh engine through IDLE -> TREND_QUALIFIED ->           |
//| IMPULSE_ACTIVE -> PULLBACK_ACTIVE -> RESUMPTION_ARMED -> TRIGGERED |
//| (default rejection_confirm trigger) in exactly 6 bars. `barsToRun` |
//| lets a test stop early to inspect an intermediate phase. All      |
//| offsets are direction-multiplied so the identical bar template     |
//| produces a symmetric up/down episode.                              |
//+------------------------------------------------------------------+
void QBDriveTPV2(CSymbolAdapter &adapter, CTrendPullbackV2Engine &strategy,
                 MarketSnapshot &market, FeatureSnapshot &f, RegimeState &regime,
                 int direction, datetime baseTime, int barsToRun,
                 bool experimentalEnabled = false,
                 ENUM_TPV2_TRIGGER_MODE triggerMode = TPV2_TRIGGER_REJECTION_CONFIRM)
{
   strategy.Init("TPV2_TEST", "TPV2 test", true, 0.0, adapter, triggerMode, experimentalEnabled);
   double d;
   QBMakeSyntheticMarket(adapter, market, d);
   QBMakeNormalRegime(regime);
   regime.trend = (direction > 0) ? TREND_STRONG_UP : TREND_STRONG_DOWN;

   ZeroMemory(f);
   f.dir_efficiency = 0.8;
   f.trend_persistence = 10;
   double M = market.mid;

   for(int bar = 0; bar < barsToRun && bar < 6; bar++)
   {
      f.calc_time = baseTime + bar;
      f.atr = d;
      f.rejection_wick_lower = 0.0;
      f.rejection_wick_upper = 0.0;
      switch(bar)
      {
         case 0: // TREND_QUALIFIED entry
            f.closed_open = M; f.closed_close = M; f.closed_high = M; f.closed_low = M;
            f.displacement = 0.0;
            break;
         case 1: // IMPULSE_ACTIVE entry -- aligned candle, displacement 0.5 ATR
            f.closed_open = M;
            f.closed_close = M + direction * 1.0 * d;
            f.closed_high = (direction > 0) ? M + 1.0 * d : M;
            f.closed_low  = (direction > 0) ? M : M - 1.0 * d;
            f.displacement = 0.5;
            break;
         case 2: // PULLBACK_ACTIVE entry -- counter candle, depth 0.5
            f.closed_open = M + direction * 1.0 * d;
            f.closed_close = M + direction * 0.5 * d;
            f.closed_high = (direction > 0) ? M + 1.0 * d : M - 0.5 * d;
            f.closed_low  = (direction > 0) ? M + 0.4 * d : M - 1.0 * d;
            f.moving_toward_value = true;
            f.displacement = 0.0;
            break;
         case 3: // RESUMPTION_ARMED entry -- aligned candle, retracement ending
            f.closed_open = M + direction * 0.5 * d;
            f.closed_close = M + direction * 0.6 * d;
            f.closed_high = (direction > 0) ? M + 0.65 * d : M - 0.45 * d;
            f.closed_low  = (direction > 0) ? M + 0.45 * d : M - 0.65 * d;
            f.moving_toward_value = false;
            break;
         case 4: // default trigger step 1: rejection wick bar (arms pending confirm)
            f.closed_open = M + direction * 0.55 * d;
            f.closed_close = M + direction * 0.5 * d;
            if(direction > 0) f.rejection_wick_lower = 0.35; else f.rejection_wick_upper = 0.35;
            break;
         case 5: // default trigger step 2: confirming close -> TRIGGERED
            f.closed_open = M + direction * 0.5 * d;
            f.closed_close = M + direction * 0.55 * d;
            break;
      }
      if(direction > 0) strategy.EvaluateLong(market, f, regime);
      else              strategy.EvaluateShort(market, f, regime);
   }
}

//+------------------------------------------------------------------+
//| TEST 75: trend must predate impulse -- persistence below floor    |
//| never qualifies regardless of candle strength; the qualifying bar |
//| itself never also detects an impulse; only a strictly later bar   |
//| can.                                                                |
//+------------------------------------------------------------------+
bool QBTestTPV2TrendPredatesImpulse(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy;
   MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   strategy.Init("TPV2_T75", "t75", true, 0.0, adapter, TPV2_TRIGGER_REJECTION_CONFIRM, false);
   double d;
   QBMakeSyntheticMarket(adapter, market, d);
   QBMakeNormalRegime(regime);
   regime.trend = TREND_STRONG_UP;
   ZeroMemory(f);
   f.atr = d;

   f.calc_time = 1000; f.trend_persistence = 2; f.dir_efficiency = 0.8;
   f.closed_open = market.mid; f.closed_close = market.mid + 2.0 * d;
   f.closed_high = market.mid + 2.0 * d; f.closed_low = market.mid;
   f.displacement = 1.0;
   strategy.EvaluateLong(market, f, regime);
   bool stillIdleWhenBelowFloor = (strategy.GetLifecyclePhase() == "idle");

   f.calc_time = 1001; f.trend_persistence = 10; // qualifying bar
   f.closed_open = market.mid; f.closed_close = market.mid + 2.0 * d;
   f.closed_high = market.mid + 2.0 * d; f.closed_low = market.mid;
   f.displacement = 1.0;
   strategy.EvaluateLong(market, f, regime);
   bool qualifiedNotImpulseSameBar = (strategy.GetLifecyclePhase() == "trend_qualified");

   f.calc_time = 1002; // strictly later bar
   f.closed_open = market.mid; f.closed_close = market.mid + 1.0 * d;
   f.closed_high = market.mid + 1.0 * d; f.closed_low = market.mid;
   f.displacement = 0.5;
   strategy.EvaluateLong(market, f, regime);
   bool impulseOnLaterBar = (strategy.GetLifecyclePhase() == "impulse_active");

   detail = "belowFloorStillIdle=" + (stillIdleWhenBelowFloor ? "yes" : "FAIL") +
            " qualifiedNotImpulseSameBar=" + (qualifiedNotImpulseSameBar ? "yes" : "FAIL") +
            " impulseOnLaterBar=" + (impulseOnLaterBar ? "yes" : "FAIL");
   return stillIdleWhenBelowFloor && qualifiedNotImpulseSameBar && impulseOnLaterBar;
}

//+------------------------------------------------------------------+
//| TEST 76: impulse direction and anchor correctness, both directions.|
//+------------------------------------------------------------------+
bool QBTestTPV2ImpulseAnchor(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine up; MarketSnapshot mu; FeatureSnapshot fu; RegimeState ru;
   QBDriveTPV2(adapter, up, mu, fu, ru, 1, 2000, 2);
   bool upOK = (up.GetLifecyclePhase() == "impulse_active") &&
               (up.GetLifecycleDirection() == "up") &&
               (up.GetImpulseStartTime() == 2001) &&
               MathAbs(up.GetImpulseStartPrice() - mu.mid) < 0.0001 &&
               (up.GetImpulseExtreme() > up.GetImpulseStartPrice());

   CTrendPullbackV2Engine dn; MarketSnapshot md; FeatureSnapshot fd; RegimeState rd;
   QBDriveTPV2(adapter, dn, md, fd, rd, -1, 2100, 2);
   bool downOK = (dn.GetLifecyclePhase() == "impulse_active") &&
                 (dn.GetLifecycleDirection() == "down") &&
                 (dn.GetImpulseStartTime() == 2101) &&
                 MathAbs(dn.GetImpulseStartPrice() - md.mid) < 0.0001 &&
                 (dn.GetImpulseExtreme() < dn.GetImpulseStartPrice());

   detail = "upOK=" + (upOK ? "yes" : "FAIL") + " downOK=" + (downOK ? "yes" : "FAIL");
   return upOK && downOK;
}

//+------------------------------------------------------------------+
//| TEST 77: actual countertrend pullback detection with measured      |
//| depth (not a same-bar proximity proxy).                            |
//+------------------------------------------------------------------+
bool QBTestTPV2PullbackDetection(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2200, 3);
   bool inPullback = (strategy.GetLifecyclePhase() == "pullback_active");
   bool depthOK = MathAbs(strategy.GetRetracementDepth() - 0.5) <= 0.02;
   detail = "phase=" + strategy.GetLifecyclePhase() +
            " depth=" + DoubleToString(strategy.GetRetracementDepth(), 3);
   return inPullback && depthOK;
}

//+------------------------------------------------------------------+
//| TEST 78: a shallow 1-bar non-continuation (depth below the floor)  |
//| is not misclassified as a pullback -- stays IMPULSE_ACTIVE, and    |
//| the impulse can still resume normally afterward.                   |
//+------------------------------------------------------------------+
bool QBTestTPV2ShallowPauseNotPullback(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2300, 2); // through IMPULSE_ACTIVE entry
   double d = f.atr; double M = market.mid;
   // A trivial 0.02-ATR counter tick -- depth ~0.02, below QB_TPV2_MIN_RETRACEMENT_DEPTH (0.10).
   f.calc_time = 2303;
   f.closed_open = M + 1.0 * d;
   f.closed_close = M + 0.98 * d;
   f.closed_high = M + 1.0 * d; f.closed_low = M + 0.97 * d;
   strategy.EvaluateLong(market, f, regime);
   bool stillImpulse = (strategy.GetLifecyclePhase() == "impulse_active");
   bool reasonOK = (strategy.GetLastReasonCode() == "PB_REJECT_INSUFFICIENT_RETRACEMENT");

   // Impulse can still resume/extend normally afterward.
   f.calc_time = 2304;
   f.closed_open = M + 0.98 * d;
   f.closed_close = M + 1.2 * d;
   f.closed_high = M + 1.2 * d; f.closed_low = M + 0.98 * d;
   strategy.EvaluateLong(market, f, regime);
   bool stillImpulseAfterExtend = (strategy.GetLifecyclePhase() == "impulse_active");

   detail = "stillImpulse=" + (stillImpulse ? "yes" : "FAIL") +
            " reasonOK=" + (reasonOK ? "yes" : "FAIL") +
            " stillImpulseAfterExtend=" + (stillImpulseAfterExtend ? "yes" : "FAIL");
   return stillImpulse && reasonOK && stillImpulseAfterExtend;
}

//+------------------------------------------------------------------+
//| TEST 79: deep structural invalidation -- a trend flip invalidates  |
//| the episode and the following bar resets cleanly to IDLE.          |
//+------------------------------------------------------------------+
bool QBTestTPV2DeepInvalidation(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2400, 3); // through PULLBACK_ACTIVE
   double d = f.atr; double M = market.mid;

   f.calc_time = 2403;
   regime.trend = TREND_STRONG_DOWN; // trend flips against the nominated "up" episode
   f.closed_open = M; f.closed_close = M - 0.2 * d; f.closed_high = M; f.closed_low = M - 0.2 * d;
   strategy.EvaluateLong(market, f, regime);
   bool invalidated = (strategy.GetLifecyclePhase() == "invalidated");
   bool reasonOK = (strategy.GetLastReasonCode() == "INV_TREND_FLIPPED");

   // Reset is observed on a bar where the trend is genuinely non-directional
   // -- a directional bar here would legitimately re-qualify a fresh episode
   // on this same bar (correct behavior, not what this assertion isolates).
   f.calc_time = 2404;
   regime.trend = TREND_NEUTRAL;
   strategy.EvaluateLong(market, f, regime);
   bool resetToIdle = (strategy.GetLifecyclePhase() == "idle") &&
                      (strategy.GetLifecycleDirection() == "none");

   detail = "invalidated=" + (invalidated ? "yes" : "FAIL") +
            " reasonOK=" + (reasonOK ? "yes" : "FAIL") +
            " resetToIdle=" + (resetToIdle ? "yes" : "FAIL");
   return invalidated && reasonOK && resetToIdle;
}

//+------------------------------------------------------------------+
//| TEST 80: temporary local balance (a single bar's regime.structure  |
//| reading STRUCTURE_BALANCED) does not by itself invalidate a valid  |
//| higher-order trend context -- the direct fix for V1's 11/16        |
//| rejection mode (see tp_v1_freeze/README.md).                       |
//+------------------------------------------------------------------+
bool QBTestTPV2LocalBalanceSurvives(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2500, 3); // through PULLBACK_ACTIVE
   double d = f.atr; double M = market.mid;

   f.calc_time = 2503;
   regime.structure = STRUCTURE_BALANCED; // local balance reading -- regime.trend untouched
   f.closed_open = M + 0.5 * d; f.closed_close = M + 0.45 * d; // still within retracement band
   f.closed_high = M + 0.5 * d; f.closed_low = M + 0.4 * d;
   f.moving_toward_value = true;
   strategy.EvaluateLong(market, f, regime);
   bool notInvalidated = (strategy.GetLifecyclePhase() != "invalidated");
   bool stillPullbackOrArmed = (strategy.GetLifecyclePhase() == "pullback_active" ||
                                strategy.GetLifecyclePhase() == "resumption_armed");

   detail = "phase=" + strategy.GetLifecyclePhase() +
            " notInvalidated=" + (notInvalidated ? "yes" : "FAIL") +
            " stillPullbackOrArmed=" + (stillPullbackOrArmed ? "yes" : "FAIL");
   return notInvalidated && stillPullbackOrArmed;
}

//+------------------------------------------------------------------+
//| TEST 81: lifecycle expiry after QB_TPV2_MAX_LIFECYCLE_AGE bars     |
//| without a completed transition, followed by a clean reset to IDLE. |
//+------------------------------------------------------------------+
bool QBTestTPV2Expiry(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2600, 2); // through IMPULSE_ACTIVE entry
   double d = f.atr; double M = market.mid;

   ENUM_TPV2_LIFECYCLE_PHASE lastPhase = TPV2_IMPULSE_ACTIVE;
   bool expired = false;
   for(int i = 0; i < QB_TPV2_MAX_LIFECYCLE_AGE + 2; i++)
   {
      f.calc_time = 2602 + i;
      // Keep extending the impulse (aligned candle) so it never completes a
      // pullback and never invalidates -- only age can end this episode.
      f.closed_open = M + (1.0 + i * 0.01) * d;
      f.closed_close = M + (1.01 + i * 0.01) * d;
      f.closed_high = f.closed_close; f.closed_low = f.closed_open;
      strategy.EvaluateLong(market, f, regime);
      if(strategy.GetLifecyclePhase() == "expired") { expired = true; break; }
   }
   bool reasonOK = (strategy.GetLastReasonCode() == "EXP_MAX_LIFECYCLE_AGE");

   // Reset is observed on a bar where the trend is genuinely non-directional
   // -- a directional bar here would legitimately re-qualify a fresh episode
   // on this same bar (correct behavior, not what this assertion isolates).
   f.calc_time += 1;
   regime.trend = TREND_NEUTRAL;
   strategy.EvaluateLong(market, f, regime);
   bool resetToIdle = (strategy.GetLifecyclePhase() == "idle");

   detail = "expired=" + (expired ? "yes" : "FAIL") +
            " reasonOK=" + (reasonOK ? "yes" : "FAIL") +
            " resetToIdle=" + (resetToIdle ? "yes" : "FAIL");
   return expired && reasonOK && resetToIdle;
}

//+------------------------------------------------------------------+
//| TEST 82: one lifecycle update per bar -- calling Evaluate twice    |
//| with the same calc_time is a no-op the second time.                |
//+------------------------------------------------------------------+
bool QBTestTPV2OneUpdatePerBar(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2700, 2);
   string phaseAfterFirst = strategy.GetLifecyclePhase();
   int barsAfterFirst = strategy.GetLifecycleBars();

   strategy.EvaluateLong(market, f, regime); // identical f.calc_time as the last driven bar
   bool unchanged = (strategy.GetLifecyclePhase() == phaseAfterFirst) &&
                    (strategy.GetLifecycleBars() == barsAfterFirst);

   detail = "phase=" + strategy.GetLifecyclePhase() + " unchanged=" + (unchanged ? "yes" : "FAIL");
   return unchanged;
}

//+------------------------------------------------------------------+
//| TEST 83: BUY/SELL deduplication -- EvaluateShort called on the     |
//| same bar as a prior EvaluateLong does not reprocess the lifecycle. |
//+------------------------------------------------------------------+
bool QBTestTPV2BuySellDedup(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2800, 1); // one bar -> trend_qualified
   string phaseAfterLong = strategy.GetLifecyclePhase();

   strategy.EvaluateShort(market, f, regime); // same f.calc_time, opposite-direction call
   bool unchanged = (strategy.GetLifecyclePhase() == phaseAfterLong);

   detail = "phaseAfterLong=" + phaseAfterLong + " phaseAfterShort=" + strategy.GetLifecyclePhase() +
            " unchanged=" + (unchanged ? "yes" : "FAIL");
   return unchanged;
}

//+------------------------------------------------------------------+
//| TEST 84: immutable direction -- frozen from TREND_QUALIFIED through|
//| invalidation, only clearing to "none" after the reset-to-IDLE bar. |
//+------------------------------------------------------------------+
bool QBTestTPV2ImmutableDirection(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 2900, 3); // through PULLBACK_ACTIVE
   bool upThroughout = (strategy.GetLifecycleDirection() == "up");

   f.calc_time = 2903;
   regime.trend = TREND_STRONG_DOWN;
   strategy.EvaluateLong(market, f, regime);
   bool stillUpAtInvalidation = (strategy.GetLifecyclePhase() == "invalidated") &&
                                (strategy.GetLifecycleDirection() == "up");

   // Reset is observed on a bar where the trend is genuinely non-directional
   // -- a directional bar here would legitimately re-qualify a fresh episode
   // on this same bar (correct behavior, not what this assertion isolates).
   f.calc_time = 2904;
   regime.trend = TREND_NEUTRAL;
   strategy.EvaluateLong(market, f, regime);
   bool clearedAfterReset = (strategy.GetLifecycleDirection() == "none");

   detail = "upThroughout=" + (upThroughout ? "yes" : "FAIL") +
            " stillUpAtInvalidation=" + (stillUpAtInvalidation ? "yes" : "FAIL") +
            " clearedAfterReset=" + (clearedAfterReset ? "yes" : "FAIL");
   return upThroughout && stillUpAtInvalidation && clearedAfterReset;
}

//+------------------------------------------------------------------+
//| TEST 85: resumption trigger success and failure (default           |
//| rejection_confirm trigger).                                        |
//+------------------------------------------------------------------+
bool QBTestTPV2TriggerSuccessAndFailure(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine ok; MarketSnapshot mo; FeatureSnapshot fo; RegimeState ro;
   QBDriveTPV2(adapter, ok, mo, fo, ro, 1, 3000, 6);
   bool triggeredOK = (ok.GetLifecyclePhase() == "triggered") &&
                      (ok.GetLastReasonCode() == "TRIG_ENTER_TRIGGERED_REJECTION_CONFIRM");

   CTrendPullbackV2Engine fail; MarketSnapshot mf; FeatureSnapshot ff; RegimeState rf;
   QBDriveTPV2(adapter, fail, mf, ff, rf, 1, 3100, 5); // through the rejection wick bar (armed pending)
   double d = ff.atr; double M = mf.mid;
   ff.calc_time = 3105;
   ff.closed_open = M + 0.5 * d;
   ff.closed_close = M + 0.3 * d; // closes AGAINST the nominated direction -- must not confirm
   fail.EvaluateLong(mf, ff, rf);
   bool notTriggered = (fail.GetLifecyclePhase() == "resumption_armed") &&
                       (fail.GetLastReasonCode() == "TRIG_REJECT_NOT_CONFIRMED");

   detail = "triggeredOK=" + (triggeredOK ? "yes" : "FAIL") +
            " notTriggered=" + (notTriggered ? "yes" : "FAIL");
   return triggeredOK && notTriggered;
}

//+------------------------------------------------------------------+
//| TEST 86: stop is placed exactly at the episode's own invalidation  |
//| level (never an independently-chosen offset).                      |
//+------------------------------------------------------------------+
bool QBTestTPV2StopAtInvalidationLevel(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3200, 6, true); // experimental ON
   StrategySignal sig = strategy.EvaluateLong(market, f, regime);
   bool valid = sig.valid;
   bool stopMatches = MathAbs(sig.proposed_stop - strategy.GetInvalidationLevel()) < 0.0001;
   bool stopBelowEntry = (sig.proposed_stop < sig.proposed_entry);

   detail = "valid=" + (valid ? "yes" : "FAIL") +
            " stop=" + DoubleToString(sig.proposed_stop, 5) +
            " invalidationLevel=" + DoubleToString(strategy.GetInvalidationLevel(), 5) +
            " stopMatches=" + (stopMatches ? "yes" : "FAIL") +
            " stopBelowEntry=" + (stopBelowEntry ? "yes" : "FAIL");
   return valid && stopMatches && stopBelowEntry;
}

//+------------------------------------------------------------------+
//| TEST 87: target geometry -- fixed R extension of the stop distance,|
//| and the reported expected_reward_r matches QB_TPV2_TARGET_EXTENSION_R.|
//+------------------------------------------------------------------+
bool QBTestTPV2TargetGeometry(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3300, 6, true);
   StrategySignal sig = strategy.EvaluateLong(market, f, regime);
   double risk = MathAbs(sig.proposed_entry - sig.proposed_stop);
   double expectedTarget = sig.proposed_entry + risk * QB_TPV2_TARGET_EXTENSION_R;
   bool targetMatches = MathAbs(sig.proposed_target - expectedTarget) < 0.01;
   bool rewardMatches = MathAbs(sig.expected_reward_r - QB_TPV2_TARGET_EXTENSION_R) < 0.05;

   detail = "valid=" + (sig.valid ? "yes" : "FAIL") +
            " target=" + DoubleToString(sig.proposed_target, 5) +
            " expectedTarget=" + DoubleToString(expectedTarget, 5) +
            " rewardR=" + DoubleToString(sig.expected_reward_r, 3) +
            " targetMatches=" + (targetMatches ? "yes" : "FAIL") +
            " rewardMatches=" + (rewardMatches ? "yes" : "FAIL");
   return sig.valid && targetMatches && rewardMatches;
}

//+------------------------------------------------------------------+
//| TEST 88: spread/cost guard rejects a triggered episode when spread |
//| exceeds QB_TPV2_MAX_SPREAD_PTS, even though the lifecycle itself   |
//| fully completed.                                                    |
//+------------------------------------------------------------------+
bool QBTestTPV2SpreadGuard(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3400, 6, true);
   market.spread_points = QB_TPV2_MAX_SPREAD_PTS + 5.0;
   StrategySignal sig = strategy.EvaluateLong(market, f, regime);
   bool rejected = !sig.valid;
   bool reasonOK = (StringFind(sig.reason, "GEOM_REJECT_SPREAD") >= 0);

   detail = "rejected=" + (rejected ? "yes" : "FAIL") + " reasonOK=" + (reasonOK ? "yes" : "FAIL");
   return rejected && reasonOK;
}

//+------------------------------------------------------------------+
//| TEST 89: no-lookahead -- the impulse extreme after bar N reflects  |
//| only bars up to and including N, never a later bar's data.         |
//+------------------------------------------------------------------+
bool QBTestTPV2NoLookahead(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3500, 2); // IMPULSE_ACTIVE entry, bar1 high = M+1.0*d
   double extremeAfterEntry = strategy.GetImpulseExtreme();
   double d = f.atr; double M = market.mid;
   bool extremeMatchesEntryOnly = MathAbs(extremeAfterEntry - (M + 1.0 * d)) < 0.0001;

   // Feed a much higher future bar -- extreme must NOT reflect it until processed.
   f.calc_time = 3502;
   f.closed_open = M + 1.0 * d;
   f.closed_close = M + 5.0 * d; // far higher
   f.closed_high = M + 5.0 * d; f.closed_low = M + 1.0 * d;
   double extremeBeforeThisCall = strategy.GetImpulseExtreme();
   bool unchangedBeforeCall = MathAbs(extremeBeforeThisCall - extremeAfterEntry) < 0.0001;
   strategy.EvaluateLong(market, f, regime);
   bool updatedAfterCall = MathAbs(strategy.GetImpulseExtreme() - (M + 5.0 * d)) < 0.0001;

   detail = "extremeMatchesEntryOnly=" + (extremeMatchesEntryOnly ? "yes" : "FAIL") +
            " unchangedBeforeCall=" + (unchangedBeforeCall ? "yes" : "FAIL") +
            " updatedAfterCall=" + (updatedAfterCall ? "yes" : "FAIL");
   return extremeMatchesEntryOnly && unchangedBeforeCall && updatedAfterCall;
}

//+------------------------------------------------------------------+
//| TEST 90: restart/reset semantics -- re-Init mid-episode clears all |
//| residual state and a fresh episode can be driven cleanly.          |
//+------------------------------------------------------------------+
bool QBTestTPV2RestartResetSemantics(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine strategy; MarketSnapshot market; FeatureSnapshot f; RegimeState regime;
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3600, 3); // mid-episode: PULLBACK_ACTIVE
   bool midEpisode = (strategy.GetLifecyclePhase() == "pullback_active");

   strategy.Init("TPV2_T90_RESTART", "t90", true, 0.0, adapter, TPV2_TRIGGER_REJECTION_CONFIRM, false);
   bool resetClean = (strategy.GetLifecyclePhase() == "idle") &&
                     (strategy.GetLifecycleDirection() == "none") &&
                     (strategy.GetLifecycleBars() == 0) &&
                     (strategy.GetImpulseStartTime() == 0);

   // A fresh episode drives identically to a never-used engine (no residue).
   QBDriveTPV2(adapter, strategy, market, f, regime, 1, 3700, 2);
   bool freshEpisodeWorks = (strategy.GetLifecyclePhase() == "impulse_active");

   detail = "midEpisode=" + (midEpisode ? "yes" : "FAIL") +
            " resetClean=" + (resetClean ? "yes" : "FAIL") +
            " freshEpisodeWorks=" + (freshEpisodeWorks ? "yes" : "FAIL");
   return midEpisode && resetClean && freshEpisodeWorks;
}

//+------------------------------------------------------------------+
//| TEST 91: V1/V2 lifecycle version and vocabulary isolation.         |
//+------------------------------------------------------------------+
bool QBTestTPV1V2Isolation(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackEngine v1;
   CTrendPullbackV2Engine v2;
   bool versionsDiffer = (v1.GetLifecycleVersion() == 1) && (v2.GetLifecycleVersion() == 2);

   MarketSnapshot m1; FeatureSnapshot f1; RegimeState r1;
   QBDriveTPToResumeCandidate(adapter, v1, m1, f1, r1, 1, 3800);
   StrategySignal rej1 = v1.EvaluateLong(m1, f1, r1);
   bool v1TagsVersion1 = (StringFind(rej1.reason, "lifecycleVersion=1") >= 0);

   MarketSnapshot m2; FeatureSnapshot f2; RegimeState r2;
   QBDriveTPV2(adapter, v2, m2, f2, r2, 1, 3900, 3);
   StrategySignal rej2 = v2.EvaluateLong(m2, f2, r2);
   bool v2TagsVersion2 = (StringFind(rej2.reason, "lifecycleVersion=2") >= 0);

   // Disjoint phase vocabularies -- V1's "resume_candidate" never appears in
   // V2's label set and V2's "resumption_armed"/"triggered" never appear in V1's.
   bool vocabDisjoint = (v1.GetLifecyclePhase() != "resumption_armed") &&
                        (v1.GetLifecyclePhase() != "triggered") &&
                        (v2.GetLifecyclePhase() != "resume_candidate");

   detail = "versionsDiffer=" + (versionsDiffer ? "yes" : "FAIL") +
            " v1TagsVersion1=" + (v1TagsVersion1 ? "yes" : "FAIL") +
            " v2TagsVersion2=" + (v2TagsVersion2 ? "yes" : "FAIL") +
            " vocabDisjoint=" + (vocabDisjoint ? "yes" : "FAIL");
   return versionsDiffer && v1TagsVersion1 && v2TagsVersion2 && vocabDisjoint;
}

//+------------------------------------------------------------------+
//| TEST 92: no trading side effects while InpEnableTPV2Experimental   |
//| (here, the constructor-level experimentalEnabled flag) is OFF --   |
//| a fully triggered episode still never emits a valid signal; the    |
//| identical bar sequence with the flag ON does.                      |
//+------------------------------------------------------------------+
bool QBTestTPV2NoSideEffectsWhenExperimentalOff(CSymbolAdapter &adapter, string &detail)
{
   CTrendPullbackV2Engine off; MarketSnapshot mo; FeatureSnapshot fo; RegimeState ro;
   QBDriveTPV2(adapter, off, mo, fo, ro, 1, 4000, 6, false);
   StrategySignal sigOff = off.EvaluateLong(mo, fo, ro);
   bool offNeverValid = !sigOff.valid;
   bool offReasonTagged = (StringFind(sigOff.reason, "TPV2_EXPERIMENTAL_DISABLED") >= 0);
   bool offReachedTriggered = (off.GetLifecyclePhase() == "triggered"); // lifecycle itself still completes

   CTrendPullbackV2Engine on; MarketSnapshot mn; FeatureSnapshot fn; RegimeState rn;
   QBDriveTPV2(adapter, on, mn, fn, rn, 1, 4100, 6, true);
   StrategySignal sigOn = on.EvaluateLong(mn, fn, rn);
   bool onValid = sigOn.valid;

   detail = "offNeverValid=" + (offNeverValid ? "yes" : "FAIL") +
            " offReasonTagged=" + (offReasonTagged ? "yes" : "FAIL") +
            " offReachedTriggered=" + (offReachedTriggered ? "yes" : "FAIL") +
            " onValid=" + (onValid ? "yes" : "FAIL");
   return offNeverValid && offReasonTagged && offReachedTriggered && onValid;
}

//+------------------------------------------------------------------+
//| TEST 93: production configuration boundary validation (Part F).   |
//| QBValidNumberInRange() is the primitive QBProductionConfiguration- |
//| Valid() (QuantBeastEA.mq5 OnInit gate) is built from -- rejects    |
//| NaN/infinite, zero, negative, and dangerously-permissive-above-max |
//| values, accepts a genuine mid-range value.                         |
//+------------------------------------------------------------------+
bool QBTestConfigBoundaryValidation(string &detail)
{
   bool rejectsNaN      = !QBValidNumberInRange(MathSqrt(-1.0), 0.0, 100.0);
   bool rejectsInfinite = !QBValidNumberInRange(DBL_MAX * 2.0, 0.0, 100.0);
   bool rejectsZero     = !QBValidNumberInRange(0.0, 0.0, 100.0);
   bool rejectsNegative = !QBValidNumberInRange(-5.0, 0.0, 100.0);
   bool rejectsAboveMax = !QBValidNumberInRange(150.0, 0.0, 100.0);
   bool acceptsMidRange = QBValidNumberInRange(5.0, 0.0, 100.0);
   bool acceptsAtMax    = QBValidNumberInRange(100.0, 0.0, 100.0);

   detail = "rejectsNaN=" + (rejectsNaN ? "yes" : "FAIL") +
            " rejectsInfinite=" + (rejectsInfinite ? "yes" : "FAIL") +
            " rejectsZero=" + (rejectsZero ? "yes" : "FAIL") +
            " rejectsNegative=" + (rejectsNegative ? "yes" : "FAIL") +
            " rejectsAboveMax=" + (rejectsAboveMax ? "yes" : "FAIL") +
            " acceptsMidRange=" + (acceptsMidRange ? "yes" : "FAIL") +
            " acceptsAtMax=" + (acceptsAtMax ? "yes" : "FAIL");
   return rejectsNaN && rejectsInfinite && rejectsZero && rejectsNegative &&
          rejectsAboveMax && acceptsMidRange && acceptsAtMax;
}

//+------------------------------------------------------------------+
//| Regression for the fifth-strategy cardinality audit (2026-07-23): |
//| ARBITRATION_REGIME_PRIORITY's compatibility bonus chain checked   |
//| STRATEGY_ID_TREND_PULLBACK but not _V2, so a TPV2 candidate always|
//| scored a 0.0 regime-compatibility bonus regardless of trend regime|
//| -- silently disadvantaging it against TP V1 in this arbitration   |
//| mode. Both represent the same trend-following compatibility claim|
//| (regime.trend != TREND_NEUTRAL), so TPV2 must score identically   |
//| to TP V1 here.                                                     |
//+------------------------------------------------------------------+
bool QBTestTPV2RegimePriorityCompatibility(string &detail)
{
   datetime now = TimeCurrent();
   RegimeState trendingRegime;
   ZeroMemory(trendingRegime);
   trendingRegime.trend = TREND_STRONG_UP;
   trendingRegime.structure = STRUCTURE_BALANCED;
   FeatureSnapshot f;
   ZeroMemory(f);

   StrategySignal cands[2];
   QBMakeArbitrationSignal(cands[0], STRATEGY_ID_TREND_PULLBACK,
                           ORDER_TYPE_BUY, now, 2600.0, 0.50);
   QBMakeArbitrationSignal(cands[1], STRATEGY_ID_TREND_PULLBACK_V2,
                           ORDER_TYPE_BUY, now + 1, 2601.0, 0.50);

   CSignalArbitrator arbV1First;
   arbV1First.Init(ARBITRATION_REGIME_PRIORITY, 0, 600, true, true);
   StrategySignal bestV1First = arbV1First.Arbitrate(cands, 2, trendingRegime, f);

   // Swap order and identical confidence so a tie only resolves in TPV2's
   // favor if it actually receives the same compatibility bonus as V1 --
   // proves the bonus is applied, not just that V1 happens to win first.
   StrategySignal cands2[2];
   QBMakeArbitrationSignal(cands2[0], STRATEGY_ID_TREND_PULLBACK_V2,
                           ORDER_TYPE_BUY, now, 2600.0, 0.50);
   QBMakeArbitrationSignal(cands2[1], STRATEGY_ID_TREND_PULLBACK,
                           ORDER_TYPE_BUY, now + 1, 2601.0, 0.50);
   CSignalArbitrator arbV2First;
   arbV2First.Init(ARBITRATION_REGIME_PRIORITY, 0, 600, true, true);
   StrategySignal bestV2First = arbV2First.Arbitrate(cands2, 2, trendingRegime, f);

   // Both candidates score identically (same confidence, same +0.20 trend
   // compatibility bonus) -- the highest-score loop keeps the FIRST seen on
   // a tie (strict '>' comparison), so whichever is listed first should win
   // in both orderings if and only if TPV2 gets the same bonus as V1.
   bool v1WinsWhenFirst = bestV1First.valid && bestV1First.strategy_id == STRATEGY_ID_TREND_PULLBACK;
   bool v2WinsWhenFirst = bestV2First.valid && bestV2First.strategy_id == STRATEGY_ID_TREND_PULLBACK_V2;

   detail = "v1WinsWhenFirst=" + (v1WinsWhenFirst ? "yes" : "FAIL") +
            " v2WinsWhenFirst=" + (v2WinsWhenFirst ? "yes" : "FAIL");
   return v1WinsWhenFirst && v2WinsWhenFirst;
}

//+------------------------------------------------------------------+
//| Phase 6 (follow-on sprint): five simultaneous strategy candidates |
//| on one bar -- proves the fifth strategy is included in the         |
//| candidate loop (not omitted by any stale array bound), that TP V2  |
//| can win arbitration on merit (highest score), and that it can lose |
//| to a higher-confidence competitor from any of the other four       |
//| strategies -- all in the same ARBITRATION_HIGHEST_SCORE pass.      |
//+------------------------------------------------------------------+
bool QBTestFiveStrategyArbitration(string &detail)
{
   datetime now = TimeCurrent();
   RegimeState regime;
   ZeroMemory(regime);
   regime.trend = TREND_NEUTRAL;
   regime.structure = STRUCTURE_BALANCED;
   FeatureSnapshot f;
   ZeroMemory(f);

   // Case 1: TPV2 has the highest confidence among all five -- must win.
   StrategySignal five[5];
   QBMakeArbitrationSignal(five[0], STRATEGY_ID_BREAKOUT, ORDER_TYPE_BUY, now, 2700.0, 0.50);
   QBMakeArbitrationSignal(five[1], STRATEGY_ID_FAILED_BREAKOUT, ORDER_TYPE_BUY, now, 2701.0, 0.55);
   QBMakeArbitrationSignal(five[2], STRATEGY_ID_TREND_PULLBACK, ORDER_TYPE_BUY, now, 2702.0, 0.60);
   QBMakeArbitrationSignal(five[3], STRATEGY_ID_MEAN_REVERSION, ORDER_TYPE_BUY, now, 2703.0, 0.65);
   QBMakeArbitrationSignal(five[4], STRATEGY_ID_TREND_PULLBACK_V2, ORDER_TYPE_BUY, now, 2704.0, 0.90);
   CSignalArbitrator arbV2Wins;
   arbV2Wins.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   StrategySignal bestV2Wins = arbV2Wins.Arbitrate(five, 5, regime, f);
   bool tpv2Wins = bestV2Wins.valid && bestV2Wins.strategy_id == STRATEGY_ID_TREND_PULLBACK_V2;
   // All four others must be marked rejected-by-arbitration, proving the
   // loop actually evaluated all five, not just a subset.
   bool othersRejected = !five[0].valid && !five[1].valid && !five[2].valid && !five[3].valid &&
                         five[0].rejection_code == REJECT_ARBITRATION_LOST &&
                         five[1].rejection_code == REJECT_ARBITRATION_LOST &&
                         five[2].rejection_code == REJECT_ARBITRATION_LOST &&
                         five[3].rejection_code == REJECT_ARBITRATION_LOST;

   // Case 2: TPV2 has the LOWEST confidence -- each of the other four, in
   // turn, must be able to beat it (proves no accidental priority/ordering
   // bias toward or against TPV2).
   bool eachBeatsTPV2 = true;
   string ids[4] = {STRATEGY_ID_BREAKOUT, STRATEGY_ID_FAILED_BREAKOUT,
                     STRATEGY_ID_TREND_PULLBACK, STRATEGY_ID_MEAN_REVERSION};
   for(int k = 0; k < 4; k++)
   {
      StrategySignal pair[2];
      QBMakeArbitrationSignal(pair[0], STRATEGY_ID_TREND_PULLBACK_V2, ORDER_TYPE_BUY, now, 2705.0, 0.40);
      QBMakeArbitrationSignal(pair[1], ids[k], ORDER_TYPE_BUY, now + 1, 2706.0, 0.70);
      CSignalArbitrator arbPair;
      arbPair.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
      StrategySignal bestPair = arbPair.Arbitrate(pair, 2, regime, f);
      if(!(bestPair.valid && bestPair.strategy_id == ids[k]))
         eachBeatsTPV2 = false;
   }

   detail = "tpv2Wins=" + (tpv2Wins ? "yes" : "FAIL") +
            " othersRejected=" + (othersRejected ? "yes" : "FAIL") +
            " eachBeatsTPV2=" + (eachBeatsTPV2 ? "yes" : "FAIL");
   return tpv2Wins && othersRejected && eachBeatsTPV2;
}

//+------------------------------------------------------------------+
//| Phase 6 (follow-on sprint): ten directional candidates (5          |
//| strategies x BUY+SELL) in one Arbitrate call -- proves the buffer  |
//| and loop scale correctly beyond the 8-element bound several        |
//| pre-TPV2 arrays used to have, and that confidence comparison       |
//| genuinely spans every candidate regardless of direction.           |
//+------------------------------------------------------------------+
bool QBTestTenDirectionalCandidates(string &detail)
{
   datetime now = TimeCurrent();
   RegimeState regime;
   ZeroMemory(regime);
   regime.trend = TREND_NEUTRAL;
   regime.structure = STRUCTURE_BALANCED;
   FeatureSnapshot f;
   ZeroMemory(f);

   string ids[5] = {STRATEGY_ID_BREAKOUT, STRATEGY_ID_FAILED_BREAKOUT,
                     STRATEGY_ID_TREND_PULLBACK, STRATEGY_ID_MEAN_REVERSION,
                     STRATEGY_ID_TREND_PULLBACK_V2};
   StrategySignal ten[10];
   for(int i = 0; i < 5; i++)
   {
      QBMakeArbitrationSignal(ten[i * 2], ids[i], ORDER_TYPE_BUY, now,
                              2700.0 + i, 0.30 + i * 0.05);
      QBMakeArbitrationSignal(ten[i * 2 + 1], ids[i], ORDER_TYPE_SELL, now,
                              2700.0 + i, 0.30 + i * 0.05);
   }
   // Make the TPV2 SELL slot (index 9) the unambiguous highest score.
   ten[9].confidence = 0.95;

   CSignalArbitrator arb;
   arb.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   StrategySignal bst = arb.Arbitrate(ten, 10, regime, f);
   bool winnerCorrect = bst.valid && bst.strategy_id == STRATEGY_ID_TREND_PULLBACK_V2 &&
                        bst.direction == ORDER_TYPE_SELL;

   int rejectedCount = 0;
   for(int i = 0; i < 10; i++)
      if(!ten[i].valid && ten[i].rejection_code == REJECT_ARBITRATION_LOST) rejectedCount++;
   bool allNineRejected = (rejectedCount == 9);

   detail = "winnerCorrect=" + (winnerCorrect ? "yes" : "FAIL") +
            " rejectedCount=" + IntegerToString(rejectedCount) + "/9";
   return winnerCorrect && allNineRejected;
}

//+------------------------------------------------------------------+
//| Phase 6: one-position-limit / exposure-blocking behavior applies   |
//| to TP V2 exactly as it does to any other strategy -- a             |
//| deterministic counterpart to the organic MR-blocks-TPV2 collision  |
//| found in Phase 5's real evidence (see                              |
//| final_readiness/PHASE5_ALL_STRATEGY_SHADOW_MATRIX.md).             |
//+------------------------------------------------------------------+
bool QBTestArbitrationOnePositionLimit(string &detail)
{
   datetime now = TimeCurrent();
   RegimeState regime;
   ZeroMemory(regime);
   FeatureSnapshot f;
   ZeroMemory(f);

   // Case 1: an existing LONG (from any strategy) blocks a new TPV2 SELL
   // candidate when opposite-direction signals are disallowed.
   CSignalArbitrator arbOpp;
   arbOpp.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, false, true);
   arbOpp.SetPositionCounts(1, 0); // one existing long, zero short
   StrategySignal oppCand[1];
   QBMakeArbitrationSignal(oppCand[0], STRATEGY_ID_TREND_PULLBACK_V2,
                           ORDER_TYPE_SELL, now, 2700.0, 0.90);
   StrategySignal oppResult = arbOpp.Arbitrate(oppCand, 1, regime, f);
   bool oppBlocked = !oppResult.valid && !oppCand[0].valid &&
                      oppCand[0].rejection_code == REJECT_CONFLICTING_SIGNAL;

   // Case 2: an existing LONG blocks a new TPV2 BUY (same-direction stack)
   // when stacking is disallowed.
   CSignalArbitrator arbStack;
   arbStack.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, false);
   arbStack.SetPositionCounts(1, 0);
   StrategySignal stackCand[1];
   QBMakeArbitrationSignal(stackCand[0], STRATEGY_ID_TREND_PULLBACK_V2,
                           ORDER_TYPE_BUY, now, 2700.0, 0.90);
   StrategySignal stackResult = arbStack.Arbitrate(stackCand, 1, regime, f);
   bool stackBlocked = !stackResult.valid && !stackCand[0].valid &&
                       stackCand[0].rejection_code == REJECT_EXPOSURE_LIMIT;

   // Case 3: with zero existing positions, the identical TPV2 candidate
   // is accepted -- proving the block is specifically position-state
   // driven, not a hidden TPV2-specific rejection.
   CSignalArbitrator arbFree;
   arbFree.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, false, false);
   arbFree.SetPositionCounts(0, 0);
   StrategySignal freeCand[1];
   QBMakeArbitrationSignal(freeCand[0], STRATEGY_ID_TREND_PULLBACK_V2,
                           ORDER_TYPE_SELL, now, 2700.0, 0.90);
   StrategySignal freeResult = arbFree.Arbitrate(freeCand, 1, regime, f);
   bool freeAccepted = freeResult.valid && freeResult.strategy_id == STRATEGY_ID_TREND_PULLBACK_V2;

   detail = "oppBlocked=" + (oppBlocked ? "yes" : "FAIL") +
            " stackBlocked=" + (stackBlocked ? "yes" : "FAIL") +
            " freeAccepted=" + (freeAccepted ? "yes" : "FAIL");
   return oppBlocked && stackBlocked && freeAccepted;
}

//+------------------------------------------------------------------+
//| Phase 6: equal-score tie handling under the default                |
//| ARBITRATION_HIGHEST_SCORE method is deterministic (first-seen      |
//| wins, strict '>' comparison) regardless of which strategy occupies |
//| which slot -- proves no accidental priority for or against TPV2.   |
//+------------------------------------------------------------------+
bool QBTestArbitrationEqualScoreTieHighestScore(string &detail)
{
   datetime now = TimeCurrent();
   RegimeState regime;
   ZeroMemory(regime);
   FeatureSnapshot f;
   ZeroMemory(f);

   StrategySignal orderA[2];
   QBMakeArbitrationSignal(orderA[0], STRATEGY_ID_TREND_PULLBACK_V2, ORDER_TYPE_BUY, now, 2700.0, 0.60);
   QBMakeArbitrationSignal(orderA[1], STRATEGY_ID_MEAN_REVERSION, ORDER_TYPE_BUY, now, 2700.0, 0.60);
   CSignalArbitrator arbA;
   arbA.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   StrategySignal bstA = arbA.Arbitrate(orderA, 2, regime, f);
   bool firstWinsA = bstA.valid && bstA.strategy_id == STRATEGY_ID_TREND_PULLBACK_V2;

   StrategySignal orderB[2];
   QBMakeArbitrationSignal(orderB[0], STRATEGY_ID_MEAN_REVERSION, ORDER_TYPE_BUY, now, 2700.0, 0.60);
   QBMakeArbitrationSignal(orderB[1], STRATEGY_ID_TREND_PULLBACK_V2, ORDER_TYPE_BUY, now, 2700.0, 0.60);
   CSignalArbitrator arbB;
   arbB.Init(ARBITRATION_HIGHEST_SCORE, 0, 600, true, true);
   StrategySignal bstB = arbB.Arbitrate(orderB, 2, regime, f);
   bool firstWinsB = bstB.valid && bstB.strategy_id == STRATEGY_ID_MEAN_REVERSION;

   detail = "firstWinsA(TPV2 first)=" + (firstWinsA ? "yes" : "FAIL") +
            " firstWinsB(MR first)=" + (firstWinsB ? "yes" : "FAIL");
   return firstWinsA && firstWinsB;
}

//+------------------------------------------------------------------+
//| Phase 6: CAllocationEngine correctly includes TP V2 as a fifth,   |
//| independently-keyed strategy (ID-keyed [8] array, not index-      |
//| keyed) under ALLOC_EQUAL (default, must stay 1.0), ALLOC_CONFIDENCE|
//| (must reflect TPV2's own recorded confidence, not another          |
//| strategy's), and ALLOC_PERFORMANCE (must reflect TPV2's own R).    |
//+------------------------------------------------------------------+
bool QBTestAllocationEngineIncludesTPV2(string &detail)
{
   CAllocationEngine eqEngine;
   eqEngine.Init(ALLOC_EQUAL);
   eqEngine.RecordSignal(STRATEGY_ID_TREND_PULLBACK_V2, 0.9);
   bool equalStaysOne = MathAbs(eqEngine.GetWeight(STRATEGY_ID_TREND_PULLBACK_V2) - 1.0) < 0.0001;

   CAllocationEngine confEngine;
   confEngine.Init(ALLOC_CONFIDENCE);
   confEngine.RecordSignal(STRATEGY_ID_BREAKOUT, 0.5);
   confEngine.RecordSignal(STRATEGY_ID_FAILED_BREAKOUT, 0.5);
   confEngine.RecordSignal(STRATEGY_ID_TREND_PULLBACK, 0.5);
   confEngine.RecordSignal(STRATEGY_ID_MEAN_REVERSION, 0.5);
   confEngine.RecordSignal(STRATEGY_ID_TREND_PULLBACK_V2, 0.9); // TPV2 above the others
   double tpv2Weight = confEngine.GetWeight(STRATEGY_ID_TREND_PULLBACK_V2);
   double boWeight    = confEngine.GetWeight(STRATEGY_ID_BREAKOUT);
   bool confidenceDistinct = tpv2Weight > boWeight;

   CAllocationEngine perfEngine;
   perfEngine.Init(ALLOC_PERFORMANCE);
   perfEngine.RecordOutcome(STRATEGY_ID_BREAKOUT, -0.5);
   perfEngine.RecordOutcome(STRATEGY_ID_FAILED_BREAKOUT, -0.5);
   perfEngine.RecordOutcome(STRATEGY_ID_TREND_PULLBACK, -0.5);
   perfEngine.RecordOutcome(STRATEGY_ID_MEAN_REVERSION, -0.5);
   perfEngine.RecordOutcome(STRATEGY_ID_TREND_PULLBACK_V2, 1.5); // TPV2 outperforms
   double tpv2PerfWeight = perfEngine.GetWeight(STRATEGY_ID_TREND_PULLBACK_V2);
   double boPerfWeight    = perfEngine.GetWeight(STRATEGY_ID_BREAKOUT);
   bool performanceDistinct = tpv2PerfWeight > boPerfWeight;

   detail = "equalStaysOne=" + (equalStaysOne ? "yes" : "FAIL") +
            " confidenceDistinct(tpv2=" + DoubleToString(tpv2Weight, 3) +
            ",bo=" + DoubleToString(boWeight, 3) + ")=" + (confidenceDistinct ? "yes" : "FAIL") +
            " performanceDistinct(tpv2=" + DoubleToString(tpv2PerfWeight, 3) +
            ",bo=" + DoubleToString(boPerfWeight, 3) + ")=" + (performanceDistinct ? "yes" : "FAIL");
   return equalStaysOne && confidenceDistinct && performanceDistinct;
}

//+------------------------------------------------------------------+
//| Phase 7 (follow-on sprint): TP V2 recognized correctly by the      |
//| central risk engine and sizer -- accepted on valid geometry,       |
//| rejected on malformed stop / low R:R, and sized identically to     |
//| another strategy given identical entry/stop/equity (proving the    |
//| "central risk contract" claim empirically, not just by reading     |
//| that CalculateLots/ValidateTrade take no strategy-specific branch).|
//+------------------------------------------------------------------+
bool QBTestTPV2RiskEngineAcceptance(CSymbolAdapter &adapter, CPositionSizer &sizer, string &detail)
{
   CRiskEngine risk;
   risk.Init(adapter, sizer, 2.0, 1.0, 1, 100000, 1440, 60,
             5.0, 10.0, 20.0, 5, 0.0, 1.0,
             20, 20, 100.0, 20, 100);
   risk.InitDailyTracking(10000.0, 10000.0, TimeCurrent(),
                          10000.0, TimeCurrent(), 10000.0,
                          false, false, false, 0);

   string reason = "";

   // Case 1: valid TPV2 SELL signal (correct geometry, R:R above minimum,
   // reasonable stop distance, confidence above the floor) is accepted.
   StrategySignal validSig;
   ZeroMemory(validSig);
   validSig.valid = true;
   validSig.strategy_id = STRATEGY_ID_TREND_PULLBACK_V2;
   validSig.direction = ORDER_TYPE_SELL;
   validSig.proposed_entry = 2700.0;
   validSig.proposed_stop = 2706.0;
   validSig.proposed_target = 2688.0;
   validSig.expected_reward_r = 2.0;
   validSig.confidence = 0.60;
   bool acceptedValid = risk.ValidateTrade(validSig, 10000.0, 10000.0, 500.0,
                                            0, 0, 0.0, 0, 0, reason);

   // Case 2: malformed stop -- for a SELL, stop must be ABOVE entry; here
   // it is below, an invalid geometry that must be rejected regardless of
   // strategy.
   StrategySignal badStopSig = validSig;
   badStopSig.proposed_stop = 2694.0; // wrong side for a SELL
   bool rejectedBadStop = !risk.ValidateTrade(badStopSig, 10000.0, 10000.0, 500.0,
                                               0, 0, 0.0, 0, 0, reason);
   bool badStopReasonCorrect = (StringFind(reason, "geometry") >= 0);

   // Case 3: low expected reward:risk must be rejected.
   StrategySignal lowRSig = validSig;
   lowRSig.expected_reward_r = 0.5; // below m_minRewardRisk=1.0
   bool rejectedLowR = !risk.ValidateTrade(lowRSig, 10000.0, 10000.0, 500.0,
                                            0, 0, 0.0, 0, 0, reason);
   bool lowRReasonCorrect = (StringFind(reason, "Reward") >= 0);

   // Case 4: sizing consistency -- an identical entry/stop/equity produces
   // the identical lot size whether the signal is TPV2 or BO (CalculateLots
   // takes no strategy_id at all; this proves it empirically).
   string sizeReason = "";
   double lotsForTPV2 = sizer.CalculateLots(validSig.proposed_entry, validSig.proposed_stop,
                                             10000.0, 50.0, sizeReason);
   StrategySignal boSig = validSig;
   boSig.strategy_id = STRATEGY_ID_BREAKOUT;
   double lotsForBO = sizer.CalculateLots(boSig.proposed_entry, boSig.proposed_stop,
                                           10000.0, 50.0, sizeReason);
   bool sizingIdentical = MathAbs(lotsForTPV2 - lotsForBO) < 0.0000001;

   // Case 5: the sized TPV2 trade also clears ValidateSizedTrade using the
   // same central sizer-risk-estimate path as any other strategy.
   bool sizedAccepted = risk.ValidateSizedTrade(validSig, lotsForTPV2, 10000.0, 0.0, reason);

   detail = "acceptedValid=" + (acceptedValid ? "yes" : "FAIL") +
            " rejectedBadStop=" + (rejectedBadStop && badStopReasonCorrect ? "yes" : "FAIL") +
            " rejectedLowR=" + (rejectedLowR && lowRReasonCorrect ? "yes" : "FAIL") +
            " sizingIdentical(tpv2=" + DoubleToString(lotsForTPV2, 3) +
            ",bo=" + DoubleToString(lotsForBO, 3) + ")=" + (sizingIdentical ? "yes" : "FAIL") +
            " sizedAccepted=" + (sizedAccepted ? "yes" : "FAIL");
   return acceptedValid && rejectedBadStop && badStopReasonCorrect &&
          rejectedLowR && lowRReasonCorrect && sizingIdentical && sizedAccepted;
}

//+------------------------------------------------------------------+
//| Phase 9 (follow-on sprint): restart-persistence round-trip for TP  |
//| V2's kill-switch flag and daily trade counter. Both               |
//| Save/LoadKillSwitchState and Save/LoadStrategyTradeCounters wrote  |
//| and read exactly four strategies' GlobalVariables (BO/FBO/TP/MR)   |
//| even after TP V2 became a fifth strategy -- silently losing TP     |
//| V2's kill state and daily count across every restart. Fixed in     |
//| this same commit; this test proves the fix and guards against      |
//| regression.                                                        |
//+------------------------------------------------------------------+
bool QBTestTPV2RestartPersistence(string &detail)
{
   string originalScope = GetStateScopeSymbol();
   SetStateScopeSymbol("QBTEST_RESTART_PERSIST_" + IntegerToString((int)TimeCurrent()));

   // --- Kill-switch round trip ---
   KillSwitchState saved;
   ZeroMemory(saved);
   saved.strategy_kill[QB_STRAT_IDX_BO]   = false;
   saved.strategy_kill[QB_STRAT_IDX_FBO]  = false;
   saved.strategy_kill[QB_STRAT_IDX_TP]   = false;
   saved.strategy_kill[QB_STRAT_IDX_MR]   = false;
   saved.strategy_kill[QB_STRAT_IDX_TPV2] = true; // only TPV2 killed
   SaveKillSwitchState(saved);

   KillSwitchState loaded;
   LoadKillSwitchState(loaded);
   bool tpv2KillSurvived = loaded.strategy_kill[QB_STRAT_IDX_TPV2] == true;
   bool othersStillFalse = !loaded.strategy_kill[QB_STRAT_IDX_BO] &&
                           !loaded.strategy_kill[QB_STRAT_IDX_FBO] &&
                           !loaded.strategy_kill[QB_STRAT_IDX_TP] &&
                           !loaded.strategy_kill[QB_STRAT_IDX_MR];

   // --- Daily trade counter round trip ---
   int savedCounts[];
   ArrayResize(savedCounts, QB_STRAT_COUNT);
   ArrayInitialize(savedCounts, 0);
   savedCounts[QB_STRAT_IDX_BO]   = 1;
   savedCounts[QB_STRAT_IDX_FBO]  = 2;
   savedCounts[QB_STRAT_IDX_TP]   = 3;
   savedCounts[QB_STRAT_IDX_MR]   = 4;
   savedCounts[QB_STRAT_IDX_TPV2] = 7;
   SaveStrategyTradeCounters(TimeCurrent(), savedCounts);

   datetime loadedDay;
   int loadedCounts[];
   ArrayResize(loadedCounts, QB_STRAT_COUNT);
   bool loadedOk = LoadStrategyTradeCounters(loadedDay, loadedCounts);
   bool tpv2CountSurvived = loadedOk && loadedCounts[QB_STRAT_IDX_TPV2] == 7;
   bool othersCountCorrect = loadedOk &&
                             loadedCounts[QB_STRAT_IDX_BO] == 1 &&
                             loadedCounts[QB_STRAT_IDX_FBO] == 2 &&
                             loadedCounts[QB_STRAT_IDX_TP] == 3 &&
                             loadedCounts[QB_STRAT_IDX_MR] == 4;

   ClearAllState();
   SetStateScopeSymbol(originalScope);

   detail = "tpv2KillSurvived=" + (tpv2KillSurvived ? "yes" : "FAIL") +
            " othersStillFalse=" + (othersStillFalse ? "yes" : "FAIL") +
            " tpv2CountSurvived=" + (tpv2CountSurvived ? "yes" : "FAIL") +
            " othersCountCorrect=" + (othersCountCorrect ? "yes" : "FAIL");
   return tpv2KillSurvived && othersStillFalse && tpv2CountSurvived && othersCountCorrect;
}

#endif // QB_SAFETYTESTS_MQH
