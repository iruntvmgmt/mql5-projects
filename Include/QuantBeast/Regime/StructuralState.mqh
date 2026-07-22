//+------------------------------------------------------------------+
//|                                     QuantBeast/StructuralState.mqh|
//|                          XAUUSD Quant Beast EA - Structure Classifier|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_STRUCTURALSTATE_MQH
#define QB_STRUCTURALSTATE_MQH

#include "../Core/Types.mqh"
#include "../Core/MathUtils.mqh"

//+------------------------------------------------------------------+
//| Structural State Classifier                                       |
//+------------------------------------------------------------------+
class CStructuralState
{
private:
   double m_trendSlopeThreshold;
   double m_impulseMinDisplacement;

public:
   CStructuralState()
   {
      m_trendSlopeThreshold = 0.3;
      m_impulseMinDisplacement = 1.0;
   }

   void Init(double trendSlopeThreshold, double impulseMinDisplacement = 1.0)
   {
      m_trendSlopeThreshold = MathMax(0.0001, trendSlopeThreshold);
      m_impulseMinDisplacement = MathMax(0.0, impulseMinDisplacement);
   }

   //+------------------------------------------------------------------+
   //| Classify market structure from features                           |
   //+------------------------------------------------------------------+
   ENUM_STRUCTURE_REGIME Classify(const FeatureSnapshot &feat, double &score)
   {
      score = 0.5;

      // Breakout detection
      if(feat.breakout_dist > 0 && feat.bars_beyond_level > 0 && !feat.failed_breakout)
      {
         if(feat.bars_beyond_level >= 3 && feat.higher_high)
         {
            score = 0.8;
            return STRUCTURE_ACCEPTED_BREAKOUT;
         }
         score = 0.6;
         return STRUCTURE_BREAKOUT_ATTEMPT;
      }

      // Failed breakout
      if(feat.failed_breakout && feat.reclaim_detected)
      {
         score = 0.75;
         return STRUCTURE_FAILED_BREAKOUT;
      }

      // Use the same configured slope threshold as TrendState so calibration
      // cannot label a bar directional while structure retains a stale fixed
      // threshold. Quality remains independently enforced by efficiency and
      // displacement.
      if(MathAbs(feat.slope_norm) > m_trendSlopeThreshold &&
         feat.dir_efficiency > 0.4 &&
         feat.displacement > m_impulseMinDisplacement)
      {
         score = 0.85;
         return STRUCTURE_IMPULSE;
      }

      // Pullback (trend exists but retracing)
      if(MathAbs(feat.slope_norm) > m_trendSlopeThreshold &&
         MathAbs(feat.dist_from_equil) > 0.5 &&
         feat.returning_to_value)
      {
         score = 0.65;
         return STRUCTURE_PULLBACK;
      }

      // Exhaustion
      if(feat.trend_maturity > 2.0 && MathAbs(feat.slope_norm) < 0.2)
      {
         score = 0.7;
         return STRUCTURE_EXHAUSTION;
      }

      // Balanced (default)
      score = Clamp(1.0 - MathAbs(feat.slope_norm), 0.3, 0.6);
      return STRUCTURE_BALANCED;
   }

   //+------------------------------------------------------------------+
   //| Check if structure supports breakout trading                      |
   //+------------------------------------------------------------------+
   bool SupportsBreakout(ENUM_STRUCTURE_REGIME structure)
   {
      return (structure == STRUCTURE_BREAKOUT_ATTEMPT ||
              structure == STRUCTURE_ACCEPTED_BREAKOUT);
   }

   //+------------------------------------------------------------------+
   //| Check if structure supports mean reversion                        |
   //+------------------------------------------------------------------+
   bool SupportsMeanReversion(ENUM_STRUCTURE_REGIME structure)
   {
      return (structure == STRUCTURE_BALANCED);
   }

   //+------------------------------------------------------------------+
   //| Check if structure supports trend following                       |
   //+------------------------------------------------------------------+
   bool SupportsTrend(ENUM_STRUCTURE_REGIME structure)
   {
      return (structure == STRUCTURE_IMPULSE || structure == STRUCTURE_PULLBACK);
   }
};

#endif // QB_STRUCTURALSTATE_MQH
