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
   double   m_emergencyStopR;      // Emergency stop in R
   ENUM_STOP_MODE   m_stopMode;
   ENUM_TARGET_MODE m_targetMode;
   double           m_maxSpreadPts;

public:
   //+------------------------------------------------------------------+
   CMeanReversionEngine() : CStrategyBase()
   {
      m_maxTrendStrength   = 0.25;
      m_minDeviationSD     = 1.5;
      m_minRejectionWick   = 0.3;
      m_targetVWAPR        = 1.0;
      m_emergencyStopR     = 1.0;
      m_stopMode           = STOP_MODE_DEFAULT;
      m_targetMode         = TARGET_MODE_DEFAULT;
      m_maxSpreadPts       = 30.0;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             double maxTrendStrength, double minDeviationSD,
             double minRejectionWick, double targetVWAPR,
             double emergencyStopR,
             ENUM_STOP_MODE stopMode = STOP_MODE_DEFAULT,
             ENUM_TARGET_MODE targetMode = TARGET_MODE_DEFAULT,
             double maxSpreadPts = 30.0)
   {
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode);
      m_maxTrendStrength  = maxTrendStrength;
      m_minDeviationSD    = minDeviationSD;
      m_minRejectionWick  = minRejectionWick;
      m_targetVWAPR       = targetVWAPR;
      m_emergencyStopR    = emergencyStopR;
      m_stopMode          = stopMode;
      m_targetMode        = targetMode;
      m_maxSpreadPts      = maxSpreadPts;
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
      if(market.spread_points > m_maxSpreadPts)
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

      if(!ConfirmCandleTrigger(true, features))
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "MR Long: configured trigger not confirmed");

      // Check we're not in a strong downtrend
      if(regime.trend == TREND_STRONG_DOWN)
         return MakeRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "MR Long: strong downtrend, rejecting");

      // Entry at current mid
      double entry = market.ask;

      // Stop below the recent low plus emergency buffer, floored at a minimum
      // ATR distance so a range low sitting near entry cannot produce a
      // pathologically tight stop and an inflated reward:risk.
      double stopLevel = features.current_range_low;
      double defaultStop = entry - MathAbs(entry - stopLevel) * m_emergencyStopR;
      if(defaultStop > stopLevel) defaultStop = stopLevel; // Don't place stop above the low
      double minStopDist = 0.5 * features.atr;
      if(features.atr > 0 && entry - defaultStop < minStopDist)
         defaultStop = entry - minStopDist;
      double stop = ComputeStop(m_stopMode, true, entry, defaultStop, features, m_emergencyStopR);
      double risk = MathAbs(entry - stop);

      // Target: return to the VWAP mean (fair value) -- the classic
      // mean-reversion objective. (Previously targeted the OPPOSITE SD band,
      // a full-range overshoot that produced unrealistic R multiples and made
      // InpMR_TargetVWAPR unreachable; the opposite-SD-band target input was
      // removed.) Fall back to range midpoint, then fixed R.
      double defaultTarget = features.vwap;
      if(defaultTarget <= 0 || defaultTarget <= entry)
      {
         defaultTarget = features.range_midpoint;
         if(defaultTarget <= entry) defaultTarget = entry + risk * m_targetVWAPR;
      }
      double target = ComputeTarget(m_targetMode, true, entry, stop, defaultTarget, features, m_targetVWAPR);

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
                        ", targetVWAP=" + DoubleToString(target, m_adapter.Digits()));
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

      if(!ConfirmCandleTrigger(false, features))
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "MR Short: configured trigger not confirmed");

      if(regime.trend == TREND_STRONG_UP)
         return MakeRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "MR Short: strong uptrend, rejecting");

      double entry = market.bid;

      // Stop above the recent high plus emergency buffer, floored at a minimum
      // ATR distance (see EvaluateLong).
      double stopLevel = features.current_range_high;
      double defaultStop = entry + MathAbs(stopLevel - entry) * m_emergencyStopR;
      if(defaultStop < stopLevel) defaultStop = stopLevel;
      double minStopDist = 0.5 * features.atr;
      if(features.atr > 0 && defaultStop - entry < minStopDist)
         defaultStop = entry + minStopDist;
      double stop = ComputeStop(m_stopMode, false, entry, defaultStop, features, m_emergencyStopR);
      double risk = MathAbs(stop - entry);

      // Target: return to the VWAP mean (fair value); fall back to range
      // midpoint, then fixed R.
      double defaultTarget = features.vwap;
      if(defaultTarget <= 0 || defaultTarget >= entry)
      {
         defaultTarget = features.range_midpoint;
         if(defaultTarget >= entry) defaultTarget = entry - risk * m_targetVWAPR;
      }
      double target = ComputeTarget(m_targetMode, false, entry, stop, defaultTarget, features, m_targetVWAPR);

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
                        ", targetVWAP=" + DoubleToString(target, m_adapter.Digits()));
   }
};

#endif // QB_MEANREVERSIONENGINE_MQH
