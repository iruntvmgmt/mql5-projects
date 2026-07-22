//+------------------------------------------------------------------+
//|                                     QuantBeast/BreakoutEngine.mqh |
//|                          XAUUSD Quant Beast EA - Strategy 1: BO  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_BREAKOUTENGINE_MQH
#define QB_BREAKOUTENGINE_MQH

#include "StrategyBase.mqh"

//+------------------------------------------------------------------+
//| Breakout Strategy - Trades volatility expansion after compression |
//+------------------------------------------------------------------+
class CBreakoutEngine : public CStrategyBase
{
private:
   int              m_minCompressionBars;
   double           m_minDisplacement;
   double           m_stopATRMult;
   double           m_targetR;
   bool             m_requireHTFBias;
   ENUM_LEVEL_SOURCE m_levelSource;
   ENUM_STOP_MODE    m_stopMode;
   ENUM_TARGET_MODE  m_targetMode;
   double            m_maxSpreadPts;

public:
   //+------------------------------------------------------------------+
   CBreakoutEngine() : CStrategyBase()
   {
      m_minCompressionBars   = 5;
      m_minDisplacement       = 2.0;
      m_stopATRMult          = 1.5;
      m_targetR              = 1.5;
      m_requireHTFBias       = true;
      m_levelSource          = LEVEL_SRC_RANGE;
      m_stopMode             = STOP_MODE_DEFAULT;
      m_targetMode           = TARGET_MODE_DEFAULT;
      m_maxSpreadPts         = 40.0;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             int minCompBars, double minDisplacement,
             double stopATRMult, double targetR, bool requireHTFBias,
             ENUM_LEVEL_SOURCE levelSource = LEVEL_SRC_RANGE,
             ENUM_STOP_MODE stopMode = STOP_MODE_DEFAULT,
             ENUM_TARGET_MODE targetMode = TARGET_MODE_DEFAULT,
             double maxSpreadPts = 40.0)
   {
      string family = "breakout";
      string templateName = "range_breakout";
      if(levelSource == LEVEL_SRC_PREV_DAY)      templateName = "prev_day_breakout";
      else if(levelSource == LEVEL_SRC_SESSION)  templateName = "session_breakout";
      else if(levelSource == LEVEL_SRC_OPENING_RANGE) templateName = "opening_range_breakout";
      else if(levelSource == LEVEL_SRC_SWING)    templateName = "swing_breakout";
      string tags = QBComposeStrategyTags(id, family, templateName,
                                          QBTriggerLabel(triggerMode),
                                          QBLevelSourceLabel(levelSource),
                                          QBStopModeLabel(stopMode),
                                          QBTargetModeLabel(targetMode));
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode,
                          family, templateName, tags);
      m_minCompressionBars  = minCompBars;
      m_minDisplacement      = minDisplacement;
      m_stopATRMult         = stopATRMult;
      m_targetR             = targetR;
      m_requireHTFBias      = requireHTFBias;
      m_levelSource         = levelSource;
      m_stopMode            = stopMode;
      m_targetMode          = targetMode;
      m_maxSpreadPts        = maxSpreadPts;
   }

   //+------------------------------------------------------------------+
   string EligibilityFailure(const MarketSnapshot &market,
                             const FeatureSnapshot &features,
                             const RegimeState &regime)
   {
      if(!m_enabled) return "disabled";

      // Compression must PRECEDE the completed breakout bar. Use the
      // preceding-compression run (independent of the trigger bar's own
      // volatility) rather than compression_bars, which the feature engine
      // zeroes on the very expansion bar a breakout occurs on -- the old
      // current-bar ATR-percentile gate was mutually exclusive with an actual
      // breakout and is intentionally dropped here (VOL_SHOCK/VOL_EXTREME
      // still block dangerous expansion below). The old BO-specific
      // compression-percentile input was removed together with that gate.
      if(features.preceding_compression_bars < m_minCompressionBars)
         return "compression bars " + IntegerToString(features.preceding_compression_bars) +
                " below " + IntegerToString(m_minCompressionBars);

      // Spread acceptable
      if(market.spread_points > m_maxSpreadPts)
         return "spread " + DoubleToString(market.spread_points, 1) +
                " above " + DoubleToString(m_maxSpreadPts, 1);

      // Event state must be normal
      if(regime.event_state != EVENT_NORMAL)
         return "event state not normal";

      // Not in shock or extreme volatility
      if(regime.volatility == VOL_SHOCK || regime.volatility == VOL_EXTREME)
         return "volatility shock/extreme";

      // Liquidity must be tradeable
      if(regime.liquidity == LIQUIDITY_UNSAFE)
         return "liquidity unsafe";

      // HTF bias check (optional)
      if(m_requireHTFBias && !features.htf_aligned)
         return "HTF not aligned";

      return "";
   }

   bool IsEligible(const MarketSnapshot &market,
                   const FeatureSnapshot &features,
                   const RegimeState &regime)
   {
      return EligibilityFailure(market, features, regime) == "";
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateLong(const MarketSnapshot &market,
                                const FeatureSnapshot &features,
                                const RegimeState &regime)
   {
      string eligibility = EligibilityFailure(market, features, regime);
      if(eligibility != "")
         return MakeRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "Breakout eligibility: " + eligibility);

      if(m_requireHTFBias && features.htf_slope <= 0)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "Breakout Long: HTF bias is not up");

      // Price must be near upper boundary of compression range
      double rangeHigh = features.current_range_high;
      double rangeLow  = features.current_range_low;
      double triggerPrice = features.closed_close;

      // Check proximity to range high
      double proximityPct = (triggerPrice - rangeLow) / MathMax(rangeHigh - rangeLow, 0.0001);
      if(proximityPct < 0.7)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "Breakout: price not near upper boundary");

      // The breakout level may come from a configurable objective source
      // (default = the prior range high); proximity and stop stay range-based.
      double boLevel = SelectLevel(m_levelSource, true, features, rangeHigh);

      // Check for breakout signal based on trigger mode
      bool triggered = false;
      int triggerCode = TRIGGER_NONE;

      switch(m_triggerMode)
      {
         case TRIGGER_IMMEDIATE_BREAK:
            triggered = (market.ask > boLevel);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
         case TRIGGER_CANDLE_CLOSE_BREAK:
            triggered = (features.closed_close > boLevel);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_DISPLACEMENT:
            triggered = (features.closed_close > boLevel &&
                         features.displacement >= m_minDisplacement);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         case TRIGGER_BREAK_RETEST:
            triggered = ConfirmLevelTrigger(true, boLevel, features);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_PROBE_CONFIRM:
            triggered = ConfirmLevelTrigger(true, boLevel, features);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         default:
            triggered = false; // fail-closed on unsupported mode (e.g. rejection)
            break;
      }

      if(!triggered)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "Breakout: no trigger");

      // Entry at current mid
      double entry = market.ask;

      // Stop below the broken level (range high, which should now act as
      // support) with an ATR buffer -- bounded by the breakout level rather
      // than the far side of the entire compression range. Selectable stop
      // mode; default reproduces this native placement.
      double defaultStop = rangeHigh - m_stopATRMult * features.atr;
      double stop = ComputeStop(m_stopMode, true, entry, defaultStop, features, m_stopATRMult);

      // Target based on R multiple (selectable target mode; default = fixed R).
      double risk = MathAbs(entry - stop);
      double defaultTarget = entry + risk * m_targetR;
      double target = ComputeTarget(m_targetMode, true, entry, stop, defaultTarget, features, m_targetR);

      // Validate risk/reward
      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_BUY, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "Breakout: insufficient R:R");

      // Confidence based on compression duration and proximity
      double confidence = Clamp(features.preceding_compression_bars / 20.0 + proximityPct, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "Breakout: low confidence");

      return MakeSignal(ORDER_TYPE_BUY, entry, stop, target,
                        confidence, rewardR,
                        SETUP_BO_COMPRESSION, triggerCode,
                        "Breakout Long: precComp=" + IntegerToString(features.preceding_compression_bars) +
                        " bars, atrRank=" + DoubleToString(features.atr_percentile_rank, 1) +
                        ", prox=" + DoubleToString(proximityPct, 2));
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market,
                                 const FeatureSnapshot &features,
                                 const RegimeState &regime)
   {
      string eligibility = EligibilityFailure(market, features, regime);
      if(eligibility != "")
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "Breakout eligibility: " + eligibility);

      if(m_requireHTFBias && features.htf_slope >= 0)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "Breakout Short: HTF bias is not down");

      double rangeHigh = features.current_range_high;
      double rangeLow  = features.current_range_low;
      double triggerPrice = features.closed_close;

      // Check proximity to range low
      double proximityPct = (rangeHigh - triggerPrice) / MathMax(rangeHigh - rangeLow, 0.0001);
      if(proximityPct < 0.7)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: price not near lower boundary");

      double boLevel = SelectLevel(m_levelSource, false, features, rangeLow);

      bool triggered = false;
      int triggerCode = TRIGGER_NONE;

      switch(m_triggerMode)
      {
         case TRIGGER_IMMEDIATE_BREAK:
            triggered = (market.bid < boLevel);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
         case TRIGGER_CANDLE_CLOSE_BREAK:
            triggered = (features.closed_close < boLevel);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_DISPLACEMENT:
            triggered = (features.closed_close < boLevel &&
                         features.displacement >= m_minDisplacement);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         case TRIGGER_BREAK_RETEST:
            triggered = ConfirmLevelTrigger(false, boLevel, features);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_PROBE_CONFIRM:
            triggered = ConfirmLevelTrigger(false, boLevel, features);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         default:
            triggered = false; // fail-closed on unsupported mode
            break;
      }

      if(!triggered)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "Breakout Short: no trigger");

      double entry = market.bid;
      // Stop above the broken level (range low, now resistance) with an ATR
      // buffer -- bounded by the breakout level, not the far side of the range.
      double defaultStop = rangeLow + m_stopATRMult * features.atr;
      double stop = ComputeStop(m_stopMode, false, entry, defaultStop, features, m_stopATRMult);
      double risk = MathAbs(entry - stop);
      double defaultTarget = entry - risk * m_targetR;
      double target = ComputeTarget(m_targetMode, false, entry, stop, defaultTarget, features, m_targetR);

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_SELL, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: insufficient R:R");

      double confidence = Clamp(features.preceding_compression_bars / 20.0 + proximityPct, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: low confidence");

      return MakeSignal(ORDER_TYPE_SELL, entry, stop, target,
                        confidence, rewardR,
                        SETUP_BO_COMPRESSION, triggerCode,
                        "Breakout Short: precComp=" + IntegerToString(features.preceding_compression_bars) +
                        " bars, atrRank=" + DoubleToString(features.atr_percentile_rank, 1) +
                        ", prox=" + DoubleToString(proximityPct, 2));
   }
};

#endif // QB_BREAKOUTENGINE_MQH
