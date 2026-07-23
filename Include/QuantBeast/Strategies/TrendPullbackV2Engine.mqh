//+------------------------------------------------------------------+
//|                                QuantBeast/TrendPullbackV2Engine.mqh|
//|                    XAUUSD Quant Beast EA - Strategy 3b: TP V2     |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TRENDPULLBACKV2ENGINE_MQH
#define QB_TRENDPULLBACKV2ENGINE_MQH

#include "StrategyBase.mqh"

//+------------------------------------------------------------------+
//| Pre-registered research defaults. See                            |
//| TestEvidence/production_readiness_tp_v2_20260722/tp_v2_spec/     |
//| TP_V2_PARAMETER_CONTRACT.md for the empirical grounding of each  |
//| value -- none were chosen to maximize trade frequency.           |
//+------------------------------------------------------------------+
#define QB_TPV2_LIFECYCLE_VERSION          2
#define QB_TPV2_MIN_TREND_PERSISTENCE      5
#define QB_TPV2_MIN_DIR_EFFICIENCY         0.40
#define QB_TPV2_MIN_IMPULSE_DISPLACEMENT   0.30
#define QB_TPV2_MIN_RETRACEMENT_DEPTH      0.10
#define QB_TPV2_MAX_RETRACEMENT_DEPTH      0.618
#define QB_TPV2_MAX_LIFECYCLE_AGE          20
#define QB_TPV2_INVALIDATION_ATR           0.5
#define QB_TPV2_MAX_SPREAD_PTS             35.0
#define QB_TPV2_REJECTION_WICK_ATR         0.30
#define QB_TPV2_RETEST_TOLERANCE_ATR       0.15
#define QB_TPV2_RETEST_MAX_BARS            5
#define QB_TPV2_TARGET_EXTENSION_R         1.618

enum ENUM_TPV2_LIFECYCLE_PHASE
{
   TPV2_IDLE = 0,
   TPV2_TREND_QUALIFIED,
   TPV2_IMPULSE_ACTIVE,
   TPV2_PULLBACK_ACTIVE,
   TPV2_RESUMPTION_ARMED,
   TPV2_TRIGGERED,
   TPV2_INVALIDATED,
   TPV2_EXPIRED
};

string QBTPV2LifecycleLabel(ENUM_TPV2_LIFECYCLE_PHASE phase)
{
   switch(phase)
   {
      case TPV2_TREND_QUALIFIED:  return "trend_qualified";
      case TPV2_IMPULSE_ACTIVE:   return "impulse_active";
      case TPV2_PULLBACK_ACTIVE:  return "pullback_active";
      case TPV2_RESUMPTION_ARMED: return "resumption_armed";
      case TPV2_TRIGGERED:        return "triggered";
      case TPV2_INVALIDATED:      return "invalidated";
      case TPV2_EXPIRED:          return "expired";
      case TPV2_IDLE:
      default:                    return "idle";
   }
}

// Trigger set (ENUM_TPV2_TRIGGER_MODE) lives in Core/Enums.mqh -- it is
// referenced by an `input` in Core/Configuration.mqh, which is included
// before this file, so the enum type must be declared early too.

string QBTPV2TriggerModeLabel(ENUM_TPV2_TRIGGER_MODE mode)
{
   switch(mode)
   {
      case TPV2_TRIGGER_MICROBREAK:           return "microbreak";
      case TPV2_TRIGGER_DISPLACEMENT_RECLAIM: return "displacement_reclaim";
      case TPV2_TRIGGER_BREAK_RETEST:         return "break_retest";
      case TPV2_TRIGGER_REJECTION_CONFIRM:
      default:                                return "rejection_confirm";
   }
}

//+------------------------------------------------------------------+
//| Trend Pullback V2 -- from-scratch lifecycle with its own decoupled|
//| trend-integrity/invalidation model (see TP_V2_STATE_MACHINE.md).  |
//| No single instantaneous regime.structure reading is ever the sole |
//| authority over a transition; regime.trend/structure are used only |
//| as contextual filters at specific gates (TREND_QUALIFIED entry,   |
//| trend-integrity check). Ships gated by InpEnableTPV2Experimental: |
//| with it false, a TRIGGERED episode still constructs a signal (for |
//| journaling/evidence) but it is always forced invalid before        |
//| reaching arbitration (GEOM step, see TP_V2_REASON_CODES.md).       |
//+------------------------------------------------------------------+
class CTrendPullbackV2Engine : public CStrategyBase
{
private:
   // Configuration
   ENUM_TPV2_TRIGGER_MODE m_tpv2TriggerMode;
   bool             m_experimentalEnabled;
   ENUM_TARGET_MODE m_targetMode;
   double           m_maxSpreadPts;

   // Lifecycle state
   ENUM_TPV2_LIFECYCLE_PHASE m_phase;
   int              m_direction;         // 1 up, -1 down, 0 none -- frozen once TREND_QUALIFIED
   int              m_lifecycleBars;     // age since IMPULSE_ACTIVE began
   datetime         m_calcTime;          // one-update-per-bar dedupe
   string           m_lastReasonCode;    // most recent TP_V2_REASON_CODES.md code

   datetime         m_trendQualifiedTime;
   datetime         m_impulseStartTime;
   double           m_impulseStartPrice;
   double           m_impulseExtreme;      // running extreme of the impulse itself
   double           m_impulseATR;          // atr frozen at impulse start
   double           m_invalidationLevel;   // frozen at impulse start, never trails
   double           m_retracementDepth;    // continuously reported, only gates ARM

   double           m_pullbackExtreme;          // deepest counter-trend point reached
   double           m_pullbackRecoveryExtreme;   // running high-water mark of the recovery attempt

   // Trigger #0 (rejection+confirm, default) 2-bar pending state
   bool             m_rejectionPending;
   double           m_rejectionBarClose;

   // Trigger #3 (break-retest) 2-phase pending state
   bool             m_microBreakPending;
   double           m_microBreakLevel;
   int              m_microBreakBars;

   datetime         m_triggerTime;

   //+------------------------------------------------------------------+
   int TrendDirection(const RegimeState &regime) const
   {
      if(regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP) return 1;
      if(regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN) return -1;
      return 0;
   }

   //+------------------------------------------------------------------+
   double ComputeRetracementDepth(double extreme, double start, double refPrice) const
   {
      double span = MathAbs(extreme - start);
      if(span <= QB_EPSILON) return -1.0;
      return MathAbs(extreme - refPrice) / span;
   }

   //+------------------------------------------------------------------+
   void ResetEpisode()
   {
      m_phase = TPV2_IDLE;
      m_direction = 0;
      m_lifecycleBars = 0;
      m_trendQualifiedTime = 0;
      m_impulseStartTime = 0;
      m_impulseStartPrice = 0.0;
      m_impulseExtreme = 0.0;
      m_impulseATR = 0.0;
      m_invalidationLevel = 0.0;
      m_retracementDepth = 0.0;
      m_pullbackExtreme = 0.0;
      m_pullbackRecoveryExtreme = 0.0;
      m_rejectionPending = false;
      m_rejectionBarClose = 0.0;
      m_microBreakPending = false;
      m_microBreakLevel = 0.0;
      m_microBreakBars = 0;
      m_triggerTime = 0;
      m_lastReasonCode = "";
   }

   //+------------------------------------------------------------------+
   void CheckTrendQualification(int direction, const FeatureSnapshot &features, const RegimeState &regime)
   {
      bool trendUp   = (regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP);
      bool trendDown = (regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN);
      if(!trendUp && !trendDown) { m_lastReasonCode = "TQ_REJECT_TREND_NOT_DIRECTIONAL"; return; }
      if(regime.trend == TREND_EXHAUSTED_UP || regime.trend == TREND_EXHAUSTED_DOWN)
         { m_lastReasonCode = "TQ_REJECT_TREND_EXHAUSTED"; return; }
      if(features.trend_persistence < QB_TPV2_MIN_TREND_PERSISTENCE)
         { m_lastReasonCode = "TQ_REJECT_PERSISTENCE_BELOW_FLOOR"; return; }
      if(features.dir_efficiency < QB_TPV2_MIN_DIR_EFFICIENCY)
         { m_lastReasonCode = "TQ_REJECT_EFFICIENCY_BELOW_FLOOR"; return; }

      m_phase = TPV2_TREND_QUALIFIED;
      m_direction = direction;
      m_trendQualifiedTime = features.calc_time;
      m_lastReasonCode = "TQ_ENTER_TREND_QUALIFIED";
   }

   //+------------------------------------------------------------------+
   void CheckImpulseStart(int direction, const FeatureSnapshot &features)
   {
      if(direction != m_direction) { m_lastReasonCode = "IMP_REJECT_INSUFFICIENT_DISPLACEMENT"; return; }

      bool alignedCandle = (m_direction > 0 && features.closed_close > features.closed_open) ||
                           (m_direction < 0 && features.closed_close < features.closed_open);
      if(!alignedCandle || features.displacement < QB_TPV2_MIN_IMPULSE_DISPLACEMENT)
         { m_lastReasonCode = "IMP_REJECT_INSUFFICIENT_DISPLACEMENT"; return; }

      m_phase = TPV2_IMPULSE_ACTIVE;
      m_impulseStartTime = features.calc_time;
      m_impulseStartPrice = features.closed_open;
      m_impulseExtreme = (m_direction > 0) ? features.closed_high : features.closed_low;
      if(m_impulseExtreme <= 0) m_impulseExtreme = features.closed_close;
      m_impulseATR = features.atr;
      m_invalidationLevel = (m_direction > 0)
                            ? (m_impulseStartPrice - QB_TPV2_INVALIDATION_ATR * m_impulseATR)
                            : (m_impulseStartPrice + QB_TPV2_INVALIDATION_ATR * m_impulseATR);
      m_lastReasonCode = "IMP_ENTER_IMPULSE_ACTIVE";
   }

   //+------------------------------------------------------------------+
   void UpdateImpulseAndCheckPullback(const FeatureSnapshot &features)
   {
      double barExtreme = (m_direction > 0) ? features.closed_high : features.closed_low;
      if(barExtreme <= 0) barExtreme = features.closed_close;
      bool alignedCandle = (m_direction > 0 && features.closed_close > features.closed_open) ||
                           (m_direction < 0 && features.closed_close < features.closed_open);
      bool counterCandle = (m_direction > 0 && features.closed_close < features.closed_open) ||
                           (m_direction < 0 && features.closed_close > features.closed_open);

      if(alignedCandle)
      {
         if(m_direction > 0) m_impulseExtreme = MathMax(m_impulseExtreme, barExtreme);
         else                m_impulseExtreme = MathMin(m_impulseExtreme, barExtreme);
         return; // still extending the impulse -- no transition event
      }
      if(!counterCandle) return; // flat/doji bar -- no transition event either way

      double depth = ComputeRetracementDepth(m_impulseExtreme, m_impulseStartPrice, features.closed_close);
      if(depth < 0 || depth < QB_TPV2_MIN_RETRACEMENT_DEPTH)
         { m_lastReasonCode = "PB_REJECT_INSUFFICIENT_RETRACEMENT"; return; } // shallow pause -- stays IMPULSE_ACTIVE

      m_phase = TPV2_PULLBACK_ACTIVE;
      m_retracementDepth = depth;
      double counterExtreme = (m_direction > 0) ? features.closed_low : features.closed_high;
      if(counterExtreme <= 0) counterExtreme = features.closed_close;
      m_pullbackExtreme = counterExtreme;
      m_pullbackRecoveryExtreme = (m_direction > 0) ? features.closed_high : features.closed_low;
      if(m_pullbackRecoveryExtreme <= 0) m_pullbackRecoveryExtreme = features.closed_close;
      m_lastReasonCode = "PB_ENTER_PULLBACK_ACTIVE";
   }

   //+------------------------------------------------------------------+
   void UpdatePullbackAndCheckArm(const FeatureSnapshot &features)
   {
      double barCounter = (m_direction > 0) ? features.closed_low : features.closed_high;
      if(barCounter <= 0) barCounter = features.closed_close;
      m_pullbackExtreme = (m_direction > 0) ? MathMin(m_pullbackExtreme, barCounter)
                                             : MathMax(m_pullbackExtreme, barCounter);

      double barRecovery = (m_direction > 0) ? features.closed_high : features.closed_low;
      if(barRecovery <= 0) barRecovery = features.closed_close;
      m_pullbackRecoveryExtreme = (m_direction > 0) ? MathMax(m_pullbackRecoveryExtreme, barRecovery)
                                                     : MathMin(m_pullbackRecoveryExtreme, barRecovery);

      double depth = ComputeRetracementDepth(m_impulseExtreme, m_impulseStartPrice, features.closed_close);
      if(depth >= 0) m_retracementDepth = depth; // depth alone never invalidates -- see TP_V2_STATE_MACHINE.md

      if(depth > QB_TPV2_MAX_RETRACEMENT_DEPTH)
         { m_lastReasonCode = "ARM_REJECT_DEPTH_OUT_OF_BAND"; return; }
      if(depth < QB_TPV2_MIN_RETRACEMENT_DEPTH)
         return; // dropped below floor again -- remain PULLBACK_ACTIVE, no code needed (not a rejection of a real attempt)

      bool alignedCandle = (m_direction > 0 && features.closed_close > features.closed_open) ||
                           (m_direction < 0 && features.closed_close < features.closed_open);
      bool endingRetracement = (!features.moving_toward_value) && alignedCandle;
      if(!endingRetracement)
         { m_lastReasonCode = "ARM_REJECT_LOCAL_CONDITION_NOT_ENDING"; return; }

      m_phase = TPV2_RESUMPTION_ARMED;
      m_lastReasonCode = "ARM_ENTER_RESUMPTION_ARMED";
   }

   //+------------------------------------------------------------------+
   bool CheckMicroBreak(const FeatureSnapshot &features)
   {
      bool fired = (m_direction > 0) ? (features.closed_close > m_pullbackRecoveryExtreme)
                                      : (features.closed_close < m_pullbackRecoveryExtreme);
      double barRecovery = (m_direction > 0) ? features.closed_high : features.closed_low;
      if(barRecovery <= 0) barRecovery = features.closed_close;
      m_pullbackRecoveryExtreme = (m_direction > 0) ? MathMax(m_pullbackRecoveryExtreme, barRecovery)
                                                     : MathMin(m_pullbackRecoveryExtreme, barRecovery);
      return fired;
   }

   //+------------------------------------------------------------------+
   bool CheckRejectionConfirm(const FeatureSnapshot &features)
   {
      if(m_rejectionPending)
      {
         bool confirmed = (m_direction > 0) ? (features.closed_close > m_rejectionBarClose)
                                             : (features.closed_close < m_rejectionBarClose);
         m_rejectionPending = false; // consumed either way -- must be the very next bar
         if(confirmed) return true;
      }

      double rejWick = (m_direction > 0) ? features.rejection_wick_lower : features.rejection_wick_upper;
      if(rejWick >= QB_TPV2_REJECTION_WICK_ATR)
      {
         m_rejectionPending = true;
         m_rejectionBarClose = features.closed_close;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   bool CheckDisplacementReclaim(const FeatureSnapshot &features)
   {
      bool alignedCandle = (m_direction > 0 && features.closed_close > features.closed_open) ||
                           (m_direction < 0 && features.closed_close < features.closed_open);
      if(!alignedCandle || features.displacement < QB_TPV2_MIN_IMPULSE_DISPLACEMENT) return false;
      double mid = (m_impulseExtreme + m_impulseStartPrice) / 2.0;
      return (m_direction > 0) ? (features.closed_close > mid) : (features.closed_close < mid);
   }

   //+------------------------------------------------------------------+
   bool CheckBreakRetest(const FeatureSnapshot &features)
   {
      if(!m_microBreakPending)
      {
         if(CheckMicroBreak(features))
         {
            m_microBreakPending = true;
            m_microBreakLevel = m_pullbackRecoveryExtreme;
            m_microBreakBars = 0;
         }
         return false;
      }

      m_microBreakBars++;
      if(m_microBreakBars > QB_TPV2_RETEST_MAX_BARS)
      {
         m_microBreakPending = false;
         m_lastReasonCode = "TRIG_REJECT_RETEST_TIMEOUT";
         return false;
      }

      double tolerance = QB_TPV2_RETEST_TOLERANCE_ATR * features.atr;
      bool retested = (m_direction > 0) ? (features.closed_low <= m_microBreakLevel + tolerance)
                                         : (features.closed_high >= m_microBreakLevel - tolerance);
      bool holdsAboveLevel = (m_direction > 0) ? (features.closed_close >= m_microBreakLevel)
                                                : (features.closed_close <= m_microBreakLevel);

      if(retested && holdsAboveLevel)
      {
         m_microBreakPending = false;
         return true;
      }
      if(!holdsAboveLevel)
         m_microBreakPending = false; // failed to hold -- look for a fresh break later, not an invalidation
      return false;
   }

   //+------------------------------------------------------------------+
   void CheckTrigger(const FeatureSnapshot &features)
   {
      bool fired = false;
      string enterCode = "";
      switch(m_tpv2TriggerMode)
      {
         case TPV2_TRIGGER_MICROBREAK:
            fired = CheckMicroBreak(features);
            enterCode = "TRIG_ENTER_TRIGGERED_MICROBREAK";
            break;
         case TPV2_TRIGGER_DISPLACEMENT_RECLAIM:
            fired = CheckDisplacementReclaim(features);
            enterCode = "TRIG_ENTER_TRIGGERED_DISPLACEMENT_RECLAIM";
            break;
         case TPV2_TRIGGER_BREAK_RETEST:
            fired = CheckBreakRetest(features);
            enterCode = "TRIG_ENTER_TRIGGERED_BREAK_RETEST";
            break;
         case TPV2_TRIGGER_REJECTION_CONFIRM:
         default:
            fired = CheckRejectionConfirm(features);
            enterCode = "TRIG_ENTER_TRIGGERED_REJECTION_CONFIRM";
            break;
      }

      if(fired)
      {
         m_phase = TPV2_TRIGGERED;
         m_triggerTime = features.calc_time;
         m_lastReasonCode = enterCode;
      }
      else if(m_lastReasonCode != "TRIG_REJECT_RETEST_TIMEOUT")
      {
         m_lastReasonCode = "TRIG_REJECT_NOT_CONFIRMED";
      }
   }

   //+------------------------------------------------------------------+
   void ObserveLifecycle(const FeatureSnapshot &features, const RegimeState &regime)
   {
      // EvaluateLong and EvaluateShort are both called for the same completed
      // bar -- advance exactly once per snapshot (mirrors V1's dedupe).
      if(features.calc_time == m_calcTime) return;
      m_calcTime = features.calc_time;

      // Terminal-for-one-bar states always reset to IDLE first, before any
      // new check runs. This must happen BEFORE the invalidation check below:
      // otherwise a still-adverse condition (e.g. regime.trend still flipped)
      // on the very bar that should reset would immediately re-invalidate
      // using the stale pre-reset direction, and the reset would never be
      // observed.
      if(m_phase == TPV2_INVALIDATED || m_phase == TPV2_EXPIRED || m_phase == TPV2_TRIGGERED)
         ResetEpisode();

      int direction = TrendDirection(regime);

      // Trend integrity (higher-order, independent of any single bar's local
      // character -- see TP_V2_STATE_MACHINE.md "Trend integrity vs. local
      // pullback condition").
      bool trendBroken = false;
      if(m_direction > 0 && (regime.trend == TREND_STRONG_DOWN || regime.trend == TREND_WEAK_DOWN ||
                             regime.trend == TREND_EXHAUSTED_UP))
         trendBroken = true;
      if(m_direction < 0 && (regime.trend == TREND_STRONG_UP || regime.trend == TREND_WEAK_UP ||
                             regime.trend == TREND_EXHAUSTED_DOWN))
         trendBroken = true;
      bool eventAbnormal = (regime.event_state != EVENT_NORMAL);

      // Explicit price-based invalidation level, frozen at impulse start.
      bool priceBeyondInvalidation = false;
      if(m_phase == TPV2_IMPULSE_ACTIVE || m_phase == TPV2_PULLBACK_ACTIVE || m_phase == TPV2_RESUMPTION_ARMED)
      {
         if(m_direction > 0) priceBeyondInvalidation = (features.closed_close < m_invalidationLevel);
         else if(m_direction < 0) priceBeyondInvalidation = (features.closed_close > m_invalidationLevel);
      }

      if(m_phase != TPV2_IDLE && (trendBroken || eventAbnormal || priceBeyondInvalidation))
      {
         m_phase = TPV2_INVALIDATED;
         if(priceBeyondInvalidation)      m_lastReasonCode = "INV_PRICE_BEYOND_INVALIDATION_LEVEL";
         else if(eventAbnormal)           m_lastReasonCode = "INV_EVENT_STATE_ABNORMAL";
         else if((m_direction > 0 && regime.trend == TREND_EXHAUSTED_UP) ||
                 (m_direction < 0 && regime.trend == TREND_EXHAUSTED_DOWN))
                                          m_lastReasonCode = "INV_TREND_EXHAUSTED";
         else                             m_lastReasonCode = "INV_TREND_FLIPPED";
         return;
      }

      // Lifecycle age (only meaningful once a time-bound episode exists).
      if(m_phase == TPV2_IMPULSE_ACTIVE || m_phase == TPV2_PULLBACK_ACTIVE || m_phase == TPV2_RESUMPTION_ARMED)
      {
         m_lifecycleBars++;
         if(m_lifecycleBars > QB_TPV2_MAX_LIFECYCLE_AGE)
         {
            m_phase = TPV2_EXPIRED;
            m_lastReasonCode = "EXP_MAX_LIFECYCLE_AGE";
            return;
         }
      }

      switch(m_phase)
      {
         case TPV2_IDLE:
            CheckTrendQualification(direction, features, regime);
            break;
         case TPV2_TREND_QUALIFIED:
            CheckImpulseStart(direction, features);
            break;
         case TPV2_IMPULSE_ACTIVE:
            UpdateImpulseAndCheckPullback(features);
            break;
         case TPV2_PULLBACK_ACTIVE:
            UpdatePullbackAndCheckArm(features);
            break;
         case TPV2_RESUMPTION_ARMED:
            CheckTrigger(features);
            break;
      }
   }

   //+------------------------------------------------------------------+
   ENUM_TRIGGER_CODE TriggerCodeFor(ENUM_TPV2_TRIGGER_MODE mode) const
   {
      switch(mode)
      {
         case TPV2_TRIGGER_MICROBREAK:           return TRIGGER_TPV2_MICROBREAK;
         case TPV2_TRIGGER_DISPLACEMENT_RECLAIM: return TRIGGER_TPV2_DISPLACEMENT_RECLAIM;
         case TPV2_TRIGGER_BREAK_RETEST:         return TRIGGER_TPV2_BREAK_RETEST;
         case TPV2_TRIGGER_REJECTION_CONFIRM:
         default:                                return TRIGGER_TPV2_REJECTION_CONFIRM;
      }
   }

public:
   //+------------------------------------------------------------------+
   CTrendPullbackV2Engine() : CStrategyBase()
   {
      m_tpv2TriggerMode = TPV2_TRIGGER_REJECTION_CONFIRM;
      m_experimentalEnabled = false;
      m_targetMode = TARGET_MODE_DEFAULT;
      m_maxSpreadPts = QB_TPV2_MAX_SPREAD_PTS;
      ResetEpisode();
   }

   //+------------------------------------------------------------------+
   void Init(string id, string name, bool enabled, double minConfidence,
             CSymbolAdapter &adapter, ENUM_TPV2_TRIGGER_MODE triggerMode,
             bool experimentalEnabled,
             ENUM_TARGET_MODE targetMode = TARGET_MODE_DEFAULT,
             double maxSpreadPts = QB_TPV2_MAX_SPREAD_PTS)
   {
      string family = "trend_pullback_v2";
      string templateName = "pullback_resume_v2";
      string tags = QBComposeStrategyTags(id, family, templateName,
                                          QBTPV2TriggerModeLabel(triggerMode),
                                          "unknown", QBStopModeLabel(STOP_MODE_DEFAULT),
                                          QBTargetModeLabel(targetMode));
      CStrategyBase::Init(id, name, enabled, minConfidence, adapter,
                          TRIGGER_CANDLE_CLOSE_BREAK, family, templateName, tags);
      m_tpv2TriggerMode = triggerMode;
      m_experimentalEnabled = experimentalEnabled;
      m_targetMode = targetMode;
      m_maxSpreadPts = maxSpreadPts;
      ResetEpisode();
   }

   // Test-only / diagnostic accessors -- purely read-only, no execution path.
   string   GetLifecyclePhase() const { return QBTPV2LifecycleLabel(m_phase); }
   int      GetLifecycleVersion() const { return QB_TPV2_LIFECYCLE_VERSION; }
   int      GetLifecycleBars() const { return m_lifecycleBars; }
   string   GetLifecycleDirection() const
   {
      if(m_direction > 0) return "up";
      if(m_direction < 0) return "down";
      return "none";
   }
   string   GetLastReasonCode() const { return m_lastReasonCode; }
   datetime GetImpulseStartTime() const { return m_impulseStartTime; }
   double   GetImpulseStartPrice() const { return m_impulseStartPrice; }
   double   GetImpulseExtreme() const { return m_impulseExtreme; }
   double   GetInvalidationLevel() const { return m_invalidationLevel; }
   double   GetRetracementDepth() const { return m_retracementDepth; }
   double   GetPullbackExtreme() const { return m_pullbackExtreme; }
   ENUM_TPV2_TRIGGER_MODE GetTriggerMode() const { return m_tpv2TriggerMode; }
   bool     IsExperimentalEnabled() const { return m_experimentalEnabled; }
   datetime GetTriggerTime() const { return m_triggerTime; }

   //+------------------------------------------------------------------+
   StrategySignal MakeLifecycleRejected(ENUM_ORDER_TYPE direction, int rejectionCode, string reason) const
   {
      if(StringFind(reason, "lifecycle=") < 0)
         reason += " lifecycleVersion=" + IntegerToString(QB_TPV2_LIFECYCLE_VERSION) +
                   " lifecycle=" + QBTPV2LifecycleLabel(m_phase) +
                   " lifecycleBars=" + IntegerToString(m_lifecycleBars) +
                   " lifecycleDirection=" + GetLifecycleDirection() +
                   " reasonCode=" + m_lastReasonCode +
                   " impulseStart=" + StringFormat("%I64d", (long)m_impulseStartTime) +
                   " retracementDepth=" + DoubleToString(m_retracementDepth, 3) +
                   " invalidationLevel=" + DoubleToString(m_invalidationLevel, 5);
      return MakeRejected(direction, rejectionCode, reason);
   }

   //+------------------------------------------------------------------+
   string EligibilityFailure(const MarketSnapshot &market, const FeatureSnapshot &features,
                             const RegimeState &regime)
   {
      if(!m_enabled) return "disabled";
      if(m_phase != TPV2_TRIGGERED) return "lifecycle not triggered phase=" + QBTPV2LifecycleLabel(m_phase);
      return "";
   }

   bool IsEligible(const MarketSnapshot &market, const FeatureSnapshot &features, const RegimeState &regime)
   {
      return EligibilityFailure(market, features, regime) == "";
   }

   //+------------------------------------------------------------------+
   StrategySignal BuildTriggeredSignal(ENUM_ORDER_TYPE dir, const MarketSnapshot &market,
                                       const FeatureSnapshot &features, const RegimeState &regime)
   {
      bool isLong = (dir == ORDER_TYPE_BUY);
      double entry = isLong ? market.ask : market.bid;

      // Stop is placed at the episode's own invalidation level -- never a
      // fixed offset chosen independently of where this specific impulse's
      // premise would actually be falsified (see TP_V2_STATE_MACHINE.md
      // TRIGGERED entry).
      double stop = m_invalidationLevel;
      double risk = MathAbs(entry - stop);
      double defaultTarget = isLong ? entry + risk * QB_TPV2_TARGET_EXTENSION_R
                                     : entry - risk * QB_TPV2_TARGET_EXTENSION_R;
      double target = ComputeTarget(m_targetMode, isLong, entry, stop, defaultTarget, features,
                                    QB_TPV2_TARGET_EXTENSION_R);

      if(market.spread_points > m_maxSpreadPts)
         return MakeLifecycleRejected(dir, REJECT_SPREAD_TOO_HIGH,
                     "TPV2: spread " + DoubleToString(market.spread_points, 1) +
                     " above " + DoubleToString(m_maxSpreadPts, 1) + " GEOM_REJECT_SPREAD");

      double rewardR;
      if(!CheckRiskReward(dir, entry, stop, target, 1.0, rewardR))
         return MakeLifecycleRejected(dir, REJECT_NO_SETUP, "TPV2: insufficient R:R GEOM_REJECT_INSUFFICIENT_RR");

      double confidence = Clamp((features.dir_efficiency +
                                 (1.0 - MathAbs(m_retracementDepth - 0.5) / 0.5)) / 2.0, 0.0, 1.0);
      confidence = (confidence + regime.confidence) / 2.0;
      if(!CheckConfidence(confidence))
         return MakeLifecycleRejected(dir, REJECT_NO_SETUP, "TPV2: low confidence GEOM_REJECT_LOW_CONFIDENCE");

      if(!m_experimentalEnabled)
         return MakeLifecycleRejected(dir, REJECT_STRATEGY_DISABLED,
                     "TPV2: experimental mode disabled TPV2_EXPERIMENTAL_DISABLED");

      return MakeSignal(dir, entry, stop, target, confidence, rewardR,
                        SETUP_TPV2_TRIGGERED, TriggerCodeFor(m_tpv2TriggerMode),
                        "TPV2 " + (isLong ? "Long" : "Short") + ": trigger=" +
                        QBTPV2TriggerModeLabel(m_tpv2TriggerMode) +
                        " depth=" + DoubleToString(m_retracementDepth, 2) +
                        " dirEff=" + DoubleToString(features.dir_efficiency, 2) + " GEOM_ACCEPT");
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateLong(const MarketSnapshot &market, const FeatureSnapshot &features,
                               const RegimeState &regime)
   {
      ObserveLifecycle(features, regime);
      if(m_phase != TPV2_TRIGGERED || m_direction <= 0)
         return MakeLifecycleRejected(ORDER_TYPE_BUY, REJECT_REGIME_INELIGIBLE,
                     "TPV2 Long: " + EligibilityFailure(market, features, regime));
      return BuildTriggeredSignal(ORDER_TYPE_BUY, market, features, regime);
   }

   //+------------------------------------------------------------------+
   StrategySignal EvaluateShort(const MarketSnapshot &market, const FeatureSnapshot &features,
                                const RegimeState &regime)
   {
      ObserveLifecycle(features, regime);
      if(m_phase != TPV2_TRIGGERED || m_direction >= 0)
         return MakeLifecycleRejected(ORDER_TYPE_SELL, REJECT_REGIME_INELIGIBLE,
                     "TPV2 Short: " + EligibilityFailure(market, features, regime));
      return BuildTriggeredSignal(ORDER_TYPE_SELL, market, features, regime);
   }
};

#endif // QB_TRENDPULLBACKV2ENGINE_MQH
