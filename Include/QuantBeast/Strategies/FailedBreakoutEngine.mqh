//+------------------------------------------------------------------+
//|                                QuantBeast/FailedBreakoutEngine.mqh|
//|                          XAUUSD Quant Beast EA - Strategy 2: FBO |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_FAILEDBREAKOUTENGINE_MQH
#define QB_FAILEDBREAKOUTENGINE_MQH

#include "StrategyBase.mqh"

//+------------------------------------------------------------------+
//| Failed Breakout Strategy - Trades failed auctions beyond levels   |
//+------------------------------------------------------------------+
class CFailedBreakoutEngine : public CStrategyBase
{
private:
   double   m_minPenetration;       // Min points beyond level
   int      m_maxBarsBeyond;        // Max bars beyond before invalid
   double   m_reclaimThreshold;     // ATR multiple back for reclaim
   double   m_stopBeyondSweep;      // ATR multiple beyond sweep extreme
   double   m_targetMidR;           // Target to range midpoint R
   double   m_targetVWAPR;          // Target to VWAP R
   ENUM_STOP_MODE   m_stopMode;
   ENUM_TARGET_MODE m_targetMode;
   double           m_maxSpreadPts;

public:
   //+------------------------------------------------------------------+
   CFailedBreakoutEngine() : CStrategyBase()
   {
      m_minPenetration    = 3.0;
      m_maxBarsBeyond     = 3;
      m_reclaimThreshold  = 0.3;
      m_stopBeyondSweep   = 1.0;
      m_targetMidR        = 1.0;
      m_targetVWAPR       = 1.5;
      m_stopMode          = STOP_MODE_DEFAULT;
      m_targetMode        = TARGET_MODE_DEFAULT;
      m_maxSpreadPts      = 40.0;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             double minPenetration, int maxBarsBeyond, double reclaimThreshold,
             double stopBeyondSweep, double targetMidR, double targetVWAPR,
             ENUM_STOP_MODE stopMode = STOP_MODE_DEFAULT,
             ENUM_TARGET_MODE targetMode = TARGET_MODE_DEFAULT,
             double maxSpreadPts = 40.0)
   {
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode);
      m_minPenetration   = minPenetration;
      m_maxBarsBeyond    = maxBarsBeyond;
      m_reclaimThreshold = reclaimThreshold;
      m_stopBeyondSweep  = stopBeyondSweep;
      m_targetMidR       = targetMidR;
      m_targetVWAPR      = targetVWAPR;
      m_stopMode         = stopMode;
      m_targetMode       = targetMode;
      m_maxSpreadPts     = maxSpreadPts;
   }

   //+------------------------------------------------------------------+
   bool IsEligible(const MarketSnapshot &market,
                   const FeatureSnapshot &features,
                   const RegimeState &regime)
   {
      if(!m_enabled) return false;

      // Must have a failed breakout signal
      if(!features.failed_breakout && !features.reclaim_detected)
         return false;

      // Spread acceptable
      if(market.spread_points > m_maxSpreadPts)
         return false;

      // Event state normal
      if(regime.event_state != EVENT_NORMAL)
         return false;

      // Not shock/extreme volatility
      if(regime.volatility == VOL_SHOCK || regime.volatility == VOL_EXTREME)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateLong(const MarketSnapshot &market,
                                const FeatureSnapshot &features,
                                const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "FBO: not eligible");

      if(!features.failed_breakout_down)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "FBO Long: no downside failed auction");

      double mid = market.mid;

      // FBO Long: Price broke below a level, now reclaiming upward
      // Check: price was below prev_day_low or session_low, now reclaiming

      double level = features.reclaim_level;
      if(level <= 0) return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "FBO Long: no valid level");

      // Price is currently above the level (reclaim)
      if(mid <= level)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "FBO Long: price not reclaimed yet");

      // Check penetration happened recently (within max bars)
      if(features.bars_beyond_level > m_maxBarsBeyond)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "FBO Long: penetration too old");

      // Check minimum penetration occurred
      double penetration = features.breakout_dist / m_adapter.Point();
      if(penetration < m_minPenetration)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "FBO Long: insufficient penetration");

      if(m_reclaimThreshold > 0 && features.atr > 0 &&
         features.closed_close - level < m_reclaimThreshold * features.atr)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "FBO Long: reclaim depth too small");

      // Optional trigger confirmation layered on the reclaim: the default
      // (immediate/candle-close) keeps the proven reclaim-only behavior;
      // stronger modes add a confirming-candle requirement.
      if((m_triggerMode == TRIGGER_DISPLACEMENT || m_triggerMode == TRIGGER_PROBE_CONFIRM ||
          m_triggerMode == TRIGGER_BREAK_RETEST) && !ConfirmCandleTrigger(true, features))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "FBO Long: trigger mode not confirmed");

      // Entry at current mid
      double entry = market.ask;

      // Stop beyond the sweep low (selectable stop mode; default = sweep-based).
      double defaultStop = features.sweep_extreme - m_stopBeyondSweep * features.atr;
      double stop = ComputeStop(m_stopMode, true, entry, defaultStop, features, m_stopBeyondSweep);

      // Target: range midpoint or VWAP. If either level is unavailable or on
      // the wrong side of entry, fall back to that target's configured R.
      double risk = MathAbs(entry - stop);
      double targetVWAP = features.vwap;
      if(targetVWAP <= entry)
         targetVWAP = entry + risk * m_targetVWAPR;
      double targetMid  = features.range_midpoint;
      if(targetMid <= entry)
         targetMid = entry + risk * m_targetMidR;
      double defaultTarget = MathMax(targetVWAP, targetMid); // Higher of the two
      double target = ComputeTarget(m_targetMode, true, entry, stop, defaultTarget, features, m_targetVWAPR);

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_BUY, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "FBO Long: insufficient R:R");

      double confidence = Clamp(features.reclaim_detected ? 0.7 : 0.5, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "FBO Long: low confidence");

      return MakeSignal(ORDER_TYPE_BUY, entry, stop, target,
                        confidence, rewardR,
                        SETUP_FBO_PD_LOW, TRIGGER_FBO_RECLAIM,
                        "FBO Long: reclaim above " + DoubleToString(level, m_adapter.Digits()) +
                        " targetMidR=" + DoubleToString(m_targetMidR, 2) +
                        " targetVWAPR=" + DoubleToString(m_targetVWAPR, 2));
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market,
                                 const FeatureSnapshot &features,
                                 const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "FBO: not eligible");

      if(!features.failed_breakout_up)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "FBO Short: no upside failed auction");

      double mid = market.mid;

      // FBO Short: Price broke above a level, now reclaiming downward
      double level = features.reclaim_level;
      if(level <= 0) return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "FBO Short: no valid level");

      if(mid >= level)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "FBO Short: price not reclaimed yet");

      if(features.bars_beyond_level > m_maxBarsBeyond)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "FBO Short: penetration too old");

      double penetration = features.breakout_dist / m_adapter.Point();
      if(penetration < m_minPenetration)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "FBO Short: insufficient penetration");

      if(m_reclaimThreshold > 0 && features.atr > 0 &&
         level - features.closed_close < m_reclaimThreshold * features.atr)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "FBO Short: reclaim depth too small");

      // Optional trigger confirmation layered on the reclaim (see EvaluateLong).
      if((m_triggerMode == TRIGGER_DISPLACEMENT || m_triggerMode == TRIGGER_PROBE_CONFIRM ||
          m_triggerMode == TRIGGER_BREAK_RETEST) && !ConfirmCandleTrigger(false, features))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "FBO Short: trigger mode not confirmed");

      double entry = market.bid;
      double defaultStop = features.sweep_extreme + m_stopBeyondSweep * features.atr;
      double stop = ComputeStop(m_stopMode, false, entry, defaultStop, features, m_stopBeyondSweep);
      double risk = MathAbs(entry - stop);

      double targetVWAP = features.vwap;
      if(targetVWAP <= 0 || targetVWAP >= entry)
         targetVWAP = entry - risk * m_targetVWAPR;
      double targetMid  = features.range_midpoint;
      if(targetMid <= 0 || targetMid >= entry)
         targetMid = entry - risk * m_targetMidR;
      double defaultTarget = MathMin(targetVWAP, targetMid);
      double target = ComputeTarget(m_targetMode, false, entry, stop, defaultTarget, features, m_targetVWAPR);

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_SELL, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "FBO Short: insufficient R:R");

      double confidence = Clamp(features.reclaim_detected ? 0.7 : 0.5, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "FBO Short: low confidence");

      return MakeSignal(ORDER_TYPE_SELL, entry, stop, target,
                        confidence, rewardR,
                        SETUP_FBO_PD_HIGH, TRIGGER_FBO_RECLAIM,
                        "FBO Short: reclaim below " + DoubleToString(level, m_adapter.Digits()) +
                        " targetMidR=" + DoubleToString(m_targetMidR, 2) +
                        " targetVWAPR=" + DoubleToString(m_targetVWAPR, 2));
   }
};

#endif // QB_FAILEDBREAKOUTENGINE_MQH
