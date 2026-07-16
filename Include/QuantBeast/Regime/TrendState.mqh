//+------------------------------------------------------------------+
//|                                           QuantBeast/TrendState.mqh|
//|                          XAUUSD Quant Beast EA - Trend Classifier |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TRENDSTATE_MQH
#define QB_TRENDSTATE_MQH

#include "../Core/Types.mqh"
#include "../Core/MathUtils.mqh"

//+------------------------------------------------------------------+
//| Trend State Classifier                                            |
//+------------------------------------------------------------------+
class CTrendState
{
private:
   double   m_slopeThreshold;

public:
   CTrendState() { m_slopeThreshold = 0.3; }

   void Init(double slopeThreshold)
   {
      m_slopeThreshold = slopeThreshold;
   }

   //+------------------------------------------------------------------+
   //| Classify trend from features                                      |
   //+------------------------------------------------------------------+
   ENUM_TREND_REGIME Classify(const FeatureSnapshot &feat, double &score)
   {
      double slopeNorm     = feat.slope_norm;
      double dirEff        = feat.dir_efficiency;
      double persistence   = feat.trend_persistence;
      double trendMaturity = feat.trend_maturity;

      score = 0.5; // Default neutral

      // Strong up
      if(slopeNorm > m_slopeThreshold * 2 && dirEff > 0.6 && persistence > 5)
      {
         score = Clamp((slopeNorm / (m_slopeThreshold * 2) + dirEff) / 2.0, 0.7, 1.0);
         if(trendMaturity > 2.0)
            return TREND_EXHAUSTED_UP;
         return TREND_STRONG_UP;
      }

      // Weak up
      if(slopeNorm > m_slopeThreshold * 0.5 && dirEff > 0.3)
      {
         score = Clamp((slopeNorm / m_slopeThreshold + dirEff) / 2.0, 0.5, 0.7);
         return TREND_WEAK_UP;
      }

      // Strong down
      if(slopeNorm < -m_slopeThreshold * 2 && dirEff > 0.6 && persistence > 5)
      {
         score = Clamp((-slopeNorm / (m_slopeThreshold * 2) + dirEff) / 2.0, 0.7, 1.0);
         if(trendMaturity > 2.0)
            return TREND_EXHAUSTED_DOWN;
         return TREND_STRONG_DOWN;
      }

      // Weak down
      if(slopeNorm < -m_slopeThreshold * 0.5 && dirEff > 0.3)
      {
         score = Clamp((-slopeNorm / m_slopeThreshold + dirEff) / 2.0, 0.5, 0.7);
         return TREND_WEAK_DOWN;
      }

      // Neutral
      score = 1.0 - MathAbs(slopeNorm) / (m_slopeThreshold * 2);
      score = Clamp(score, 0.0, 0.5);
      return TREND_NEUTRAL;
   }

   //+------------------------------------------------------------------+
   //| Check if trend is directional (up or down, not neutral)           |
   //+------------------------------------------------------------------+
   bool IsDirectional(ENUM_TREND_REGIME trend)
   {
      return (trend == TREND_STRONG_UP || trend == TREND_WEAK_UP ||
              trend == TREND_STRONG_DOWN || trend == TREND_WEAK_DOWN);
   }

   //+------------------------------------------------------------------+
   //| Check if trend is exhausted                                       |
   //+------------------------------------------------------------------+
   bool IsExhausted(ENUM_TREND_REGIME trend)
   {
      return (trend == TREND_EXHAUSTED_UP || trend == TREND_EXHAUSTED_DOWN);
   }
};

#endif // QB_TRENDSTATE_MQH
