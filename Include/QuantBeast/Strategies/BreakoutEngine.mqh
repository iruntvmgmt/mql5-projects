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
   double   m_compressionPct;
   int      m_minCompressionBars;
   double   m_minDisplacement;
   double   m_stopATRMult;
   double   m_targetR;
   bool     m_requireHTFBias;

public:
   //+------------------------------------------------------------------+
   CBreakoutEngine() : CStrategyBase()
   {
      m_compressionPct       = 15.0;
      m_minCompressionBars   = 5;
      m_minDisplacement       = 2.0;
      m_stopATRMult          = 1.5;
      m_targetR              = 1.5;
      m_requireHTFBias       = true;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             double compressionPct, int minCompBars, double minDisplacement,
             double stopATRMult, double targetR, bool requireHTFBias)
   {
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode);
      m_compressionPct      = compressionPct;
      m_minCompressionBars  = minCompBars;
      m_minDisplacement      = minDisplacement;
      m_stopATRMult         = stopATRMult;
      m_targetR             = targetR;
      m_requireHTFBias      = requireHTFBias;
   }

   //+------------------------------------------------------------------+
   bool IsEligible(const MarketSnapshot &market,
                   const FeatureSnapshot &features,
                   const RegimeState &regime)
   {
      if(!m_enabled) return false;

      // Compression must precede the completed breakout bar.
      if(features.compression_bars < m_minCompressionBars)
         return false;

      // Spread acceptable
      if(market.spread_points > 40.0)
         return false;

      // Event state must be normal
      if(regime.event_state != EVENT_NORMAL)
         return false;

      // Not in shock or extreme volatility
      if(regime.volatility == VOL_SHOCK || regime.volatility == VOL_EXTREME)
         return false;

      // Liquidity must be tradeable
      if(regime.liquidity == LIQUIDITY_UNSAFE)
         return false;

      // HTF bias check (optional)
      if(m_requireHTFBias && !features.htf_aligned)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateLong(const MarketSnapshot &market,
                                const FeatureSnapshot &features,
                                const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "Breakout: not eligible");

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

      // Check for breakout signal based on trigger mode
      bool triggered = false;
      int triggerCode = TRIGGER_NONE;

      switch(m_triggerMode)
      {
         case TRIGGER_IMMEDIATE_BREAK:
            triggered = (market.ask > rangeHigh);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
         case TRIGGER_CANDLE_CLOSE_BREAK:
            triggered = (features.closed_close > rangeHigh);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_DISPLACEMENT:
            triggered = (features.closed_close > rangeHigh &&
                         features.displacement >= m_minDisplacement);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         default:
            triggered = (features.closed_close > rangeHigh);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
      }

      if(!triggered)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "Breakout: no trigger");

      // Entry at current mid
      double entry = market.ask;

      // Stop at opposite side of compression structure (range low)
      double stop = rangeLow - m_stopATRMult * features.atr;

      // Target based on R multiple
      double risk = MathAbs(entry - stop);
      double target = entry + risk * m_targetR;

      // Validate risk/reward
      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_BUY, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "Breakout: insufficient R:R");

      // Confidence based on compression duration and proximity
      double confidence = Clamp(features.compression_bars / 20.0 + proximityPct, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "Breakout: low confidence");

      return MakeSignal(ORDER_TYPE_BUY, entry, stop, target,
                        confidence, rewardR,
                        SETUP_BO_COMPRESSION, triggerCode,
                        "Breakout Long: comp=" + IntegerToString(features.compression_bars) +
                        " bars, prox=" + DoubleToString(proximityPct, 2));
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market,
                                 const FeatureSnapshot &features,
                                 const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "Breakout: not eligible");

      if(m_requireHTFBias && features.htf_slope >= 0)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "Breakout Short: HTF bias is not down");

      double rangeHigh = features.current_range_high;
      double rangeLow  = features.current_range_low;
      double triggerPrice = features.closed_close;

      // Check proximity to range low
      double proximityPct = (rangeHigh - triggerPrice) / MathMax(rangeHigh - rangeLow, 0.0001);
      if(proximityPct < 0.7)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: price not near lower boundary");

      bool triggered = false;
      int triggerCode = TRIGGER_NONE;

      switch(m_triggerMode)
      {
         case TRIGGER_IMMEDIATE_BREAK:
            triggered = (market.bid < rangeLow);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
         case TRIGGER_CANDLE_CLOSE_BREAK:
            triggered = (features.closed_close < rangeLow);
            triggerCode = TRIGGER_BO_CLOSE_BEYOND;
            break;
         case TRIGGER_DISPLACEMENT:
            triggered = (features.closed_close < rangeLow &&
                         features.displacement >= m_minDisplacement);
            triggerCode = TRIGGER_BO_DISPLACEMENT_OK;
            break;
         default:
            triggered = (features.closed_close < rangeLow);
            triggerCode = TRIGGER_BO_LEVEL_BREAK;
            break;
      }

      if(!triggered)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "Breakout Short: no trigger");

      double entry = market.bid;
      double stop = rangeHigh + m_stopATRMult * features.atr;
      double risk = MathAbs(entry - stop);
      double target = entry - risk * m_targetR;

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_SELL, entry, stop, target, 1.0, rewardR))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: insufficient R:R");

      double confidence = Clamp(features.compression_bars / 20.0 + proximityPct, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "Breakout Short: low confidence");

      return MakeSignal(ORDER_TYPE_SELL, entry, stop, target,
                        confidence, rewardR,
                        SETUP_BO_COMPRESSION, triggerCode,
                        "Breakout Short: comp=" + IntegerToString(features.compression_bars) +
                        " bars, prox=" + DoubleToString(proximityPct, 2));
   }
};

#endif // QB_BREAKOUTENGINE_MQH
