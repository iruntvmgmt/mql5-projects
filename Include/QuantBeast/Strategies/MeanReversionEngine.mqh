//+------------------------------------------------------------------+
//|                                  QuantBeast/MeanReversionEngine.mqh|
//|                          XAUUSD Quant Beast EA - Strategy 4: MR  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_MEANREVERSIONENGINE_MQH
#define QB_MEANREVERSIONENGINE_MQH

#include "StrategyBase.mqh"

//+------------------------------------------------------------------+
//| Mean Reversion Strategy - Trade deviations back to equilibrium    |
//+------------------------------------------------------------------+
class CMeanReversionEngine : public CStrategyBase
{
private:
   double   m_maxTrendStrength;    // Max trend strength for eligibility
   double   m_minDeviationSD;      // Min VWAP deviation in SD
   double   m_minRejectionWick;    // Min rejection wick (ATR multiple)
   double   m_targetVWAPR;         // R target for VWAP return
   double   m_targetSDBandR;       // R target for opposite SD band
   double   m_emergencyStopR;      // Emergency stop in R

   bool TriggerConfirmed(bool isLong, const FeatureSnapshot &features) const
   {
      bool candleDirection = isLong ?
                             (features.closed_close > features.closed_open) :
                             (features.closed_close < features.closed_open);
      if(m_triggerMode == TRIGGER_IMMEDIATE_BREAK) return true;
      if(m_triggerMode == TRIGGER_CANDLE_CLOSE_BREAK) return candleDirection;
      if(m_triggerMode == TRIGGER_DISPLACEMENT)
         return candleDirection && features.displacement >= 1.0;
      return false;
   }

public:
   //+------------------------------------------------------------------+
   CMeanReversionEngine() : CStrategyBase()
   {
      m_maxTrendStrength   = 0.25;
      m_minDeviationSD     = 1.5;
      m_minRejectionWick   = 0.3;
      m_targetVWAPR        = 1.0;
      m_targetSDBandR      = 1.5;
      m_emergencyStopR     = 1.0;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             double maxTrendStrength, double minDeviationSD,
             double minRejectionWick, double targetVWAPR,
             double targetSDBandR, double emergencyStopR)
   {
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode);
      m_maxTrendStrength  = maxTrendStrength;
      m_minDeviationSD    = minDeviationSD;
      m_minRejectionWick  = minRejectionWick;
      m_targetVWAPR       = targetVWAPR;
      m_targetSDBandR     = targetSDBandR;
      m_emergencyStopR    = emergencyStopR;
   }

   //+------------------------------------------------------------------+
   bool IsEligible(const MarketSnapshot &market,
                   const FeatureSnapshot &features,
                   const RegimeState &regime)
   {
      if(!m_enabled) return false;

      // Must be balanced market structure
      if(regime.structure != STRUCTURE_BALANCED)
         return false;

      // Trend strength must be low (below threshold)
      if(MathAbs(features.slope_norm) > m_maxTrendStrength)
         return false;

      // Not in expansion or shock volatility
      if(regime.volatility == VOL_EXPANSION || regime.volatility == VOL_EXTREME ||
         regime.volatility == VOL_SHOCK)
         return false;

      // Not exhausted trend
      if(regime.trend == TREND_EXHAUSTED_UP || regime.trend == TREND_EXHAUSTED_DOWN)
         return false;

      // No breakout acceptance active
      if(regime.structure == STRUCTURE_ACCEPTED_BREAKOUT || regime.structure == STRUCTURE_BREAKOUT_ATTEMPT)
         return false;

      // Spread acceptable (tighter for MR)
      if(market.spread_points > 30.0)
         return false;

      // Event normal
      if(regime.event_state != EVENT_NORMAL)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateLong(const MarketSnapshot &market,
                                const FeatureSnapshot &features,
                                const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "MR: not eligible");

      // Check deviation below VWAP (oversold)
      double deviation = features.sd_dist;
      if(deviation > -m_minDeviationSD)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "MR Long: insufficient deviation, sd=" +
                             DoubleToString(deviation, 2));

      // Need rejection evidence (wick showing buying pressure)
      if(features.rejection_wick_lower < m_minRejectionWick)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "MR Long: no rejection wick");

      if(!TriggerConfirmed(true, features))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "MR Long: configured trigger not confirmed");

      // Check we're not in a strong downtrend
      if(regime.trend == TREND_STRONG_DOWN)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "MR Long: strong downtrend, rejecting");

      // Entry at current mid
      double entry = market.ask;

      // Stop: below recent low plus emergency buffer
      double stopLevel = features.current_range_low;
      double risk = MathAbs(entry - stopLevel);
      double stop = entry - risk * m_emergencyStopR;
      if(stop > stopLevel) stop = stopLevel; // Don't place stop above the low

      // Target: opposite VWAP standard-deviation band when available.
      // Fall back to VWAP, then range midpoint, then fixed R.
      double target = features.vwap;
      if(features.vwap > 0 && features.vwap_sd > 0)
         target = features.vwap + m_targetSDBandR * features.vwap_sd;
      if(target <= 0 || target <= entry)
      {
         // Fallback: use range midpoint
         target = features.range_midpoint;
         if(target <= entry) target = entry + risk * m_targetVWAPR;
      }

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_BUY, entry, stop, target, 0.8, rewardR))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "MR Long: insufficient R:R");

      // Confidence based on deviation and rejection quality
      double confidence = Clamp((MathAbs(deviation) / (m_minDeviationSD * 2) +
                                  features.rejection_wick / 1.0) / 2.0, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "MR Long: low confidence");

      return MakeSignal(ORDER_TYPE_BUY, entry, stop, target,
                        confidence, rewardR,
                        SETUP_MR_DEVIATION_EXTREME, TRIGGER_MR_RETURN_START,
                        "MR Long: dev=" + DoubleToString(deviation, 2) +
                        "sd, wick=" + DoubleToString(features.rejection_wick_lower, 2) +
                        ", targetBandR=" + DoubleToString(m_targetSDBandR, 2));
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market,
                                 const FeatureSnapshot &features,
                                 const RegimeState &regime)
   {
      if(!IsEligible(market, features, regime))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "MR: not eligible");

      // Check deviation above VWAP (overbought)
      double deviation = features.sd_dist;
      if(deviation < m_minDeviationSD)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "MR Short: insufficient deviation, sd=" +
                             DoubleToString(deviation, 2));

      if(features.rejection_wick_upper < m_minRejectionWick)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "MR Short: no rejection wick");

      if(!TriggerConfirmed(false, features))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "MR Short: configured trigger not confirmed");

      if(regime.trend == TREND_STRONG_UP)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "MR Short: strong uptrend, rejecting");

      double entry = market.bid;

      double stopLevel = features.current_range_high;
      double risk = MathAbs(stopLevel - entry);
      double stop = entry + risk * m_emergencyStopR;
      if(stop < stopLevel) stop = stopLevel;

      double target = features.vwap;
      if(features.vwap > 0 && features.vwap_sd > 0)
         target = features.vwap - m_targetSDBandR * features.vwap_sd;
      if(target <= 0 || target >= entry)
      {
         target = features.range_midpoint;
         if(target >= entry) target = entry - risk * m_targetVWAPR;
      }

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_SELL, entry, stop, target, 0.8, rewardR))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "MR Short: insufficient R:R");

      double confidence = Clamp((deviation / (m_minDeviationSD * 2) +
                                  features.rejection_wick / 1.0) / 2.0, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "MR Short: low confidence");

      return MakeSignal(ORDER_TYPE_SELL, entry, stop, target,
                        confidence, rewardR,
                        SETUP_MR_DEVIATION_EXTREME, TRIGGER_MR_RETURN_START,
                        "MR Short: dev=" + DoubleToString(deviation, 2) +
                        "sd, wick=" + DoubleToString(features.rejection_wick_upper, 2) +
                        ", targetBandR=" + DoubleToString(m_targetSDBandR, 2));
   }
};

#endif // QB_MEANREVERSIONENGINE_MQH
