//+------------------------------------------------------------------+
//|                                  QuantBeast/TrendPullbackEngine.mqh|
//|                          XAUUSD Quant Beast EA - Strategy 3: TP  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TRENDPULLBACKENGINE_MQH
#define QB_TRENDPULLBACKENGINE_MQH

#include "StrategyBase.mqh"

enum ENUM_TP_LIFECYCLE_PHASE
{
   TP_LIFECYCLE_IDLE = 0,
   TP_LIFECYCLE_IMPULSE,
   TP_LIFECYCLE_RETRACING,
   TP_LIFECYCLE_RESUME_CANDIDATE,
   TP_LIFECYCLE_INVALIDATED,
   TP_LIFECYCLE_EXPIRED
};

string QBTPLifecycleLabel(ENUM_TP_LIFECYCLE_PHASE phase)
{
   switch(phase)
   {
      case TP_LIFECYCLE_IMPULSE:          return "impulse";
      case TP_LIFECYCLE_RETRACING:        return "retracing";
      case TP_LIFECYCLE_RESUME_CANDIDATE: return "resume_candidate";
      case TP_LIFECYCLE_INVALIDATED:      return "invalidated";
      case TP_LIFECYCLE_EXPIRED:          return "expired";
      case TP_LIFECYCLE_IDLE:
      default:                            return "idle";
   }
}

//+------------------------------------------------------------------+
//| Trend Pullback Strategy - Enters after controlled pullback        |
//+------------------------------------------------------------------+
class CTrendPullbackEngine : public CStrategyBase
{
private:
   double   m_minDirEfficiency;
   int      m_minTrendPersistence;
   bool     m_requireHTFAgreement;
   double   m_maxPullbackDepth;    // Fib retracement of impulse
   int      m_maxPullbackBars;
   double   m_targetExtensionR;    // Impulse extension target
   double   m_stopBeyondStruct;    // ATR multiple beyond structure
   ENUM_STOP_MODE   m_stopMode;
   ENUM_TARGET_MODE m_targetMode;
   double           m_maxSpreadPts;
   ENUM_TP_LIFECYCLE_PHASE m_lifecyclePhase;
   int              m_lifecycleDirection;
   int              m_lifecycleBars;
   datetime         m_lifecycleCalcTime;

   int TrendDirection(const RegimeState &regime) const
   {
      if(regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP) return 1;
      if(regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN) return -1;
      return 0;
   }

   void ObserveLifecycle(const FeatureSnapshot &features, const RegimeState &regime)
   {
      // EvaluateLong and EvaluateShort are both called for the same completed
      // bar. Advance the observational lifecycle exactly once per snapshot.
      if(features.calc_time == m_lifecycleCalcTime) return;
      m_lifecycleCalcTime = features.calc_time;

      int direction = TrendDirection(regime);
      bool invalidContext = (regime.event_state != EVENT_NORMAL || direction == 0);
      if(invalidContext || (m_lifecycleDirection != 0 && direction != m_lifecycleDirection))
      {
         m_lifecyclePhase = (m_lifecyclePhase == TP_LIFECYCLE_IDLE)
                            ? TP_LIFECYCLE_IDLE : TP_LIFECYCLE_INVALIDATED;
         m_lifecycleDirection = 0;
         m_lifecycleBars = 0;
         return;
      }

      if(m_lifecyclePhase == TP_LIFECYCLE_INVALIDATED ||
         m_lifecyclePhase == TP_LIFECYCLE_EXPIRED ||
         m_lifecyclePhase == TP_LIFECYCLE_RESUME_CANDIDATE)
      {
         m_lifecyclePhase = TP_LIFECYCLE_IDLE;
         m_lifecycleDirection = 0;
         m_lifecycleBars = 0;
      }

      if(regime.structure == STRUCTURE_IMPULSE)
      {
         m_lifecyclePhase = TP_LIFECYCLE_IMPULSE;
         m_lifecycleDirection = direction;
         m_lifecycleBars = 0;
         return;
      }

      if(m_lifecyclePhase == TP_LIFECYCLE_IDLE) return;

      m_lifecycleBars++;
      if(m_lifecycleBars > m_maxPullbackBars)
      {
         m_lifecyclePhase = TP_LIFECYCLE_EXPIRED;
         m_lifecycleDirection = 0;
         return;
      }

      if((m_lifecyclePhase == TP_LIFECYCLE_IMPULSE ||
          m_lifecyclePhase == TP_LIFECYCLE_RETRACING) &&
         features.moving_toward_value)
      {
         m_lifecyclePhase = TP_LIFECYCLE_RETRACING;
         return;
      }

      bool alignedCandle = (direction > 0 && features.closed_close > features.closed_open) ||
                           (direction < 0 && features.closed_close < features.closed_open);
      if(m_lifecyclePhase == TP_LIFECYCLE_RETRACING &&
         !features.moving_toward_value && alignedCandle)
      {
         m_lifecyclePhase = TP_LIFECYCLE_RESUME_CANDIDATE;
      }
   }

public:
   //+------------------------------------------------------------------+
   CTrendPullbackEngine() : CStrategyBase()
   {
      m_minDirEfficiency     = 0.4;
      m_minTrendPersistence  = 5;
      m_requireHTFAgreement  = true;
      m_maxPullbackDepth     = 0.618;
      m_maxPullbackBars      = 20;
      m_targetExtensionR     = 1.618;
      m_stopBeyondStruct     = 0.5;
      m_stopMode             = STOP_MODE_DEFAULT;
      m_targetMode           = TARGET_MODE_DEFAULT;
      m_maxSpreadPts         = 35.0;
      m_lifecyclePhase       = TP_LIFECYCLE_IDLE;
      m_lifecycleDirection   = 0;
      m_lifecycleBars        = 0;
      m_lifecycleCalcTime    = 0;
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TRIGGER_TYPE triggerMode,
             double minDirEff, int minTrendPersist, bool requireHTF,
             double maxPullbackDepth, int maxPullbackBars,
             double targetExtensionR, double stopBeyondStruct,
             ENUM_STOP_MODE stopMode = STOP_MODE_DEFAULT,
             ENUM_TARGET_MODE targetMode = TARGET_MODE_DEFAULT,
             double maxSpreadPts = 35.0)
   {
      string family = "trend_pullback";
      string templateName = "pullback_resume";
      string tags = QBComposeStrategyTags(id, family, templateName,
                                          QBTriggerLabel(triggerMode),
                                          "unknown",
                                          QBStopModeLabel(stopMode),
                                          QBTargetModeLabel(targetMode));
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter, triggerMode,
                          family, templateName, tags);
      m_minDirEfficiency    = minDirEff;
      m_minTrendPersistence = minTrendPersist;
      m_requireHTFAgreement = requireHTF;
      m_maxPullbackDepth    = maxPullbackDepth;
      m_maxPullbackBars     = maxPullbackBars;
      m_targetExtensionR    = targetExtensionR;
      m_stopBeyondStruct    = stopBeyondStruct;
      m_stopMode            = stopMode;
      m_targetMode          = targetMode;
      m_maxSpreadPts        = maxSpreadPts;
      m_lifecyclePhase      = TP_LIFECYCLE_IDLE;
      m_lifecycleDirection  = 0;
      m_lifecycleBars       = 0;
      m_lifecycleCalcTime   = 0;
   }

   string GetLifecyclePhase() const { return QBTPLifecycleLabel(m_lifecyclePhase); }
   int GetLifecycleBars() const { return m_lifecycleBars; }

   StrategySignal MakeLifecycleRejected(ENUM_ORDER_TYPE direction,
                                        int rejectionCode,
                                        string reason) const
   {
      if(StringFind(reason, "lifecycle=") < 0)
         reason += " lifecycle=" + GetLifecyclePhase() +
                   " lifecycleBars=" + IntegerToString(m_lifecycleBars);
      return MakeRejected(direction, rejectionCode, reason);
   }

   //+------------------------------------------------------------------+
   string EligibilityFailure(const MarketSnapshot &market,
                             const FeatureSnapshot &features,
                             const RegimeState &regime)
   {
      if(!m_enabled) return "disabled";

      // Must have a directional trend (up or down)
      bool trendUp   = (regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP);
      bool trendDown = (regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN);
      if(!trendUp && !trendDown) return "trend not directional";

      // Not exhausted
      if(regime.trend == TREND_EXHAUSTED_UP || regime.trend == TREND_EXHAUSTED_DOWN)
         return "trend exhausted";

      // Directional efficiency minimum
      if(features.dir_efficiency < m_minDirEfficiency)
         return "directional efficiency " + DoubleToString(features.dir_efficiency, 2) +
                " below " + DoubleToString(m_minDirEfficiency, 2);

      // Trend persistence minimum
      if(features.trend_persistence < m_minTrendPersistence)
         return "trend persistence " + IntegerToString(features.trend_persistence) +
                " below " + IntegerToString(m_minTrendPersistence);

      // HTF agreement (optional)
      if(m_requireHTFAgreement && !features.htf_aligned)
         return "HTF not aligned";

      // Spread
      if(market.spread_points > m_maxSpreadPts)
         return "spread " + DoubleToString(market.spread_points, 1) +
                " above " + DoubleToString(m_maxSpreadPts, 1);

      // Structure should support trend (impulse or pullback)
      if(!(regime.structure == STRUCTURE_IMPULSE || regime.structure == STRUCTURE_PULLBACK))
         return "structure not impulse/pullback state=" + EnumToString(regime.structure) +
                " slope=" + DoubleToString(MathAbs(features.slope_norm), 3) +
                " dirEff=" + DoubleToString(features.dir_efficiency, 3) +
                " displacement=" + DoubleToString(features.displacement, 3) +
                " equilibrium=" + DoubleToString(MathAbs(features.dist_from_equil), 3) +
                " returning=" + (features.returning_to_value ? "yes" : "no") +
                " movingToward=" + (features.moving_toward_value ? "yes" : "no") +
                " valueProgress=" + DoubleToString(features.value_return_progress, 3) +
                " crossedValue=" + (features.crossed_into_value ? "yes" : "no") +
                " lifecycle=" + GetLifecyclePhase() +
                " lifecycleBars=" + IntegerToString(m_lifecycleBars);

      // Event normal
      if(regime.event_state != EVENT_NORMAL) return "event state not normal";

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
      ObserveLifecycle(features, regime);
      string eligibility = EligibilityFailure(market, features, regime);
      if(eligibility != "")
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE, "TP eligibility: " + eligibility);

      // Must be in an uptrend
      if(!(regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP))
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "TP Long: not uptrend");

      // Must be pulling back (price below recent high)
      double recentHigh = features.swing_high;
      if(recentHigh <= 0) recentHigh = features.current_range_high;
      double mid = market.mid;

      // Pullback age is measured from the most recent swing high in a long
      // pullback. A zero value means the feature is unavailable and is not
      // treated as proof of stale age.
      if(features.swing_high_bars > 0 && features.swing_high_bars > m_maxPullbackBars)
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "TP Long: pullback age " +
                             IntegerToString(features.swing_high_bars) + " exceeds maximum");

      // Check pullback depth
      double pullbackDepth = (recentHigh - mid) / MathMax(recentHigh - features.current_range_low, 0.0001);
      if(pullbackDepth < 0.1 || pullbackDepth > m_maxPullbackDepth)
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "TP Long: pullback depth " +
                             DoubleToString(pullbackDepth, 2) + " outside range");

      // Check we're returning to value (pullback ending)
      if(!features.returning_to_value && pullbackDepth < 0.3)
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "TP Long: pullback not ending");

      if(!ConfirmCandleTrigger(true, features))
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_TRIGGER, "TP Long: configured trigger not confirmed");

      double entry = market.ask;

      // Stop beyond structural invalidation (below recent swing low or range
      // low), floored at a minimum ATR distance so a structure sitting near
      // entry cannot produce a pathologically tight stop and inflated R.
      double structLow = features.swing_low;
      if(structLow <= 0) structLow = features.current_range_low;
      double defaultStop = structLow - m_stopBeyondStruct * features.atr;
      double minStopDist = 0.5 * features.atr;
      if(features.atr > 0 && entry - defaultStop < minStopDist)
         defaultStop = entry - minStopDist;
      double stop = ComputeStop(m_stopMode, true, entry, defaultStop, features, m_stopBeyondStruct);

      // Target: extension of prior impulse
      double risk = MathAbs(entry - stop);
      double defaultTarget = entry + risk * m_targetExtensionR;
      double target = ComputeTarget(m_targetMode, true, entry, stop, defaultTarget, features, m_targetExtensionR);

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_BUY, entry, stop, target, 1.0, rewardR))
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "TP Long: insufficient R:R");

      double confidence = Clamp((features.dir_efficiency + (pullbackDepth / m_maxPullbackDepth)) / 2.0, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_NO_SETUP, "TP Long: low confidence");

      return MakeSignal(ORDER_TYPE_BUY, entry, stop, target,
                        confidence, rewardR,
                        SETUP_TP_TREND_QUALIFIED, TRIGGER_TP_MOMENTUM_RESUME,
                        "TP Long: depth=" + DoubleToString(pullbackDepth, 2) +
                        " age=" + IntegerToString(features.swing_high_bars) +
                        " dirEff=" + DoubleToString(features.dir_efficiency, 2));
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market,
                                 const FeatureSnapshot &features,
                                 const RegimeState &regime)
   {
      ObserveLifecycle(features, regime);
      string eligibility = EligibilityFailure(market, features, regime);
      if(eligibility != "")
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE, "TP eligibility: " + eligibility);

      if(!(regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN))
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "TP Short: not downtrend");

      double recentLow = features.swing_low;
      if(recentLow <= 0) recentLow = features.current_range_low;
      double mid = market.mid;

      // Pullback age is measured from the most recent swing low in a short
      // pullback. A zero value means the feature is unavailable and is not
      // treated as proof of stale age.
      if(features.swing_low_bars > 0 && features.swing_low_bars > m_maxPullbackBars)
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "TP Short: pullback age " +
                             IntegerToString(features.swing_low_bars) + " exceeds maximum");

      double pullbackDepth = (mid - recentLow) / MathMax(features.current_range_high - recentLow, 0.0001);
      if(pullbackDepth < 0.1 || pullbackDepth > m_maxPullbackDepth)
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "TP Short: pullback depth " +
                             DoubleToString(pullbackDepth, 2) + " outside range");

      if(!features.returning_to_value && pullbackDepth < 0.3)
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "TP Short: pullback not ending");

      if(!ConfirmCandleTrigger(false, features))
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_TRIGGER, "TP Short: configured trigger not confirmed");

      double entry = market.bid;

      double structHigh = features.swing_high;
      if(structHigh <= 0) structHigh = features.current_range_high;
      double defaultStop = structHigh + m_stopBeyondStruct * features.atr;
      double minStopDist = 0.5 * features.atr;
      if(features.atr > 0 && defaultStop - entry < minStopDist)
         defaultStop = entry + minStopDist;
      double stop = ComputeStop(m_stopMode, false, entry, defaultStop, features, m_stopBeyondStruct);

      double risk = MathAbs(entry - stop);
      double defaultTarget = entry - risk * m_targetExtensionR;
      double target = ComputeTarget(m_targetMode, false, entry, stop, defaultTarget, features, m_targetExtensionR);

      double rewardR;
      if(!CheckRiskReward(ORDER_TYPE_SELL, entry, stop, target, 1.0, rewardR))
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "TP Short: insufficient R:R");

      double confidence = Clamp((features.dir_efficiency + (pullbackDepth / m_maxPullbackDepth)) / 2.0, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;

      if(!CheckConfidence(confidence))
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_NO_SETUP, "TP Short: low confidence");

      return MakeSignal(ORDER_TYPE_SELL, entry, stop, target,
                        confidence, rewardR,
                        SETUP_TP_TREND_QUALIFIED, TRIGGER_TP_MOMENTUM_RESUME,
                        "TP Short: depth=" + DoubleToString(pullbackDepth, 2) +
                        " age=" + IntegerToString(features.swing_low_bars) +
                        " dirEff=" + DoubleToString(features.dir_efficiency, 2));
   }
};

#endif // QB_TRENDPULLBACKENGINE_MQH
