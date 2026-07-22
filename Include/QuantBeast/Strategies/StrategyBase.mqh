//+------------------------------------------------------------------+
//|                                         QuantBeast/StrategyBase.mqh|
//|                          XAUUSD Quant Beast EA - Strategy Interface|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_STRATEGYBASE_MQH
#define QB_STRATEGYBASE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/MathUtils.mqh"
#include "../Data/MarketData.mqh"

//+------------------------------------------------------------------+
//| Base Strategy Class - all strategies inherit from this            |
//+------------------------------------------------------------------+
class CStrategyBase
{
protected:
   string             m_strategyId;
   string             m_strategyName;
   string             m_strategyFamily;
   string             m_strategyTemplate;
   string             m_strategyTags;
   bool               m_enabled;
   double             m_minConfidence;
   CSymbolAdapter*    m_adapter;
   ENUM_TRIGGER_TYPE  m_triggerMode;

   // Helpers
   double NormalizeEntry(double price) const
   {
      return m_adapter.NormalizePrice(price);
   }

public:
   //+------------------------------------------------------------------+
   CStrategyBase()
   {
      m_strategyId   = "";
      m_strategyName = "";
      m_strategyFamily = "";
      m_strategyTemplate = "";
      m_strategyTags  = "";
      m_enabled      = false;
      m_minConfidence = 0.5;
      m_adapter      = NULL;
      m_triggerMode  = TRIGGER_CANDLE_CLOSE_BREAK;
   }

   //+------------------------------------------------------------------+
   virtual ~CStrategyBase() {}

   //+------------------------------------------------------------------+
   virtual void Init(string id, string name, bool enabled,
                     double minConfidence, CSymbolAdapter &adapter,
                     ENUM_TRIGGER_TYPE triggerMode,
                     string family = "",
                     string templateName = "",
                     string tags = "")
   {
      m_strategyId    = id;
      m_strategyName  = name;
      m_strategyFamily = family;
      m_strategyTemplate = templateName;
      m_strategyTags  = tags;
      m_enabled       = enabled;
      m_minConfidence = minConfidence;
      m_adapter       = &adapter;
      m_triggerMode   = triggerMode;
   }

   //+------------------------------------------------------------------+
   virtual bool IsEligible(const MarketSnapshot &market,
                           const FeatureSnapshot &features,
                           const RegimeState &regime) = 0;

   //+------------------------------------------------------------------+
   virtual StrategySignal EvaluateLong(const MarketSnapshot &market,
                                        const FeatureSnapshot &features,
                                        const RegimeState &regime) = 0;

   //+------------------------------------------------------------------+
   virtual StrategySignal EvaluateShort(const MarketSnapshot &market,
                                         const FeatureSnapshot &features,
                                         const RegimeState &regime) = 0;

   //+------------------------------------------------------------------+
   virtual void OnPositionOpened(const PositionContext &ctx) {}

   virtual void OnPositionUpdated(const PositionContext &ctx) {}

   virtual void OnPositionClosed(const PositionContext &ctx, ENUM_EXIT_REASON reason) {}

   //+------------------------------------------------------------------+
   string GetStrategyId()   const { return m_strategyId; }
   string GetStrategyName() const { return m_strategyName; }
   string GetStrategyFamily() const { return m_strategyFamily; }
   string GetStrategyTemplate() const { return m_strategyTemplate; }
   string GetStrategyTags() const { return m_strategyTags; }
   bool   IsEnabled()       const { return m_enabled; }

   //+------------------------------------------------------------------+
   //| Create a rejected signal with reason                              |
   //+------------------------------------------------------------------+
   StrategySignal MakeRejected(ENUM_ORDER_TYPE dir, int rejectionCode, string reason) const
   {
      StrategySignal sig;
      ZeroMemory(sig);
      sig.valid = false;
      sig.strategy_id = m_strategyId;
      sig.strategy_family = m_strategyFamily;
      sig.strategy_template = m_strategyTemplate;
      sig.strategy_tags = m_strategyTags;
      sig.direction = dir;
      sig.signal_time = TimeCurrent();
      sig.rejection_code = rejectionCode;
      sig.reason = reason;
      return sig;
   }

   //+------------------------------------------------------------------+
   //| Create a valid signal                                             |
   //+------------------------------------------------------------------+
   StrategySignal MakeSignal(ENUM_ORDER_TYPE dir, double entry,
                              double stop, double target,
                              double confidence, double rewardR,
                              int setupCode, int triggerCode,
                              string reason) const
   {
      StrategySignal sig;
      ZeroMemory(sig);
      sig.valid = true;
      sig.strategy_id = m_strategyId;
      sig.strategy_family = m_strategyFamily;
      sig.strategy_template = m_strategyTemplate;
      sig.strategy_tags = m_strategyTags;
      sig.direction = dir;
      sig.signal_time = TimeCurrent();
      sig.proposed_entry = NormalizeEntry(entry);
      sig.proposed_stop = NormalizeEntry(stop);
      sig.proposed_target = NormalizeEntry(target);
      sig.confidence = confidence;
      sig.expected_reward_r = rewardR;
      sig.setup_code = setupCode;
      sig.trigger_code = triggerCode;
      sig.reason = reason;

      // Defense in depth: never emit structurally invalid geometry. A long
      // must have stop below and target above entry (and vice versa); anything
      // else is downgraded to a rejection here rather than relying solely on
      // the central risk engine's geometry check.
      bool geomOK = (dir == ORDER_TYPE_BUY &&
                     sig.proposed_stop < sig.proposed_entry &&
                     sig.proposed_target > sig.proposed_entry) ||
                    (dir == ORDER_TYPE_SELL &&
                     sig.proposed_stop > sig.proposed_entry &&
                     sig.proposed_target < sig.proposed_entry);
      if(!geomOK)
      {
         sig.valid = false;
         sig.rejection_code = REJECT_NO_SETUP;
         sig.reason = reason + " [rejected: invalid stop/target geometry]";
      }
      return sig;
   }

   //+------------------------------------------------------------------+
   //| Default risk/reward check                                         |
   //+------------------------------------------------------------------+
   bool CheckRiskReward(ENUM_ORDER_TYPE dir, double entry, double stop, double target,
                         double minRR, double &rewardR) const
   {
      double risk    = MathAbs(entry - stop);
      double reward  = MathAbs(target - entry);
      if(risk <= 0) return false;
      rewardR = reward / risk;
      return (rewardR >= minRR);
   }

   //+------------------------------------------------------------------+
   //| Check spread is acceptable                                        |
   //+------------------------------------------------------------------+
   bool CheckSpread(const MarketSnapshot &market, double maxSpread) const
   {
      return (market.spread_points <= maxSpread);
   }

   //+------------------------------------------------------------------+
   //| Check confidence threshold                                        |
   //+------------------------------------------------------------------+
   bool CheckConfidence(double confidence) const
   {
      return (confidence >= m_minConfidence);
   }

   //+------------------------------------------------------------------+
   //| Candle-based directional trigger confirmation. Used by strategies |
   //| that key off candle behavior (TP/MR) and by level strategies for  |
   //| the non-level modes. Fail-closed on unsupported modes.            |
   //+------------------------------------------------------------------+
   bool ConfirmCandleTrigger(bool isLong, const FeatureSnapshot &features) const
   {
      bool candleDir = isLong ? (features.closed_close > features.closed_open)
                              : (features.closed_close < features.closed_open);
      double band = (features.atr > 0) ? 0.25 * features.atr : 0.0;
      switch(m_triggerMode)
      {
         // Even "immediate" entries require the just-closed bar to point in
         // the trade direction rather than firing unconditionally.
         case TRIGGER_IMMEDIATE_BREAK:
         case TRIGGER_CANDLE_CLOSE_BREAK:
            return candleDir;
         case TRIGGER_DISPLACEMENT:
            return candleDir && features.displacement >= 1.0;
         case TRIGGER_PROBE_CONFIRM:
         {
            double wickToExtreme = isLong ? (features.closed_high - features.closed_close)
                                          : (features.closed_close - features.closed_low);
            return candleDir && features.displacement >= 1.0 &&
                   (features.atr <= 0 || wickToExtreme <= band);
         }
         case TRIGGER_REJECTION:
         {
            double rejWick = isLong ? features.rejection_wick_lower
                                    : features.rejection_wick_upper;
            return candleDir && rejWick >= 0.3;
         }
         case TRIGGER_BREAK_RETEST:
            // No level context for candle-only strategies; a confirmed
            // directional close is the closest available proxy.
            return candleDir;
      }
      return false; // unsupported -> fail closed
   }

   //+------------------------------------------------------------------+
   //| Level-aware trigger confirmation for level-break strategies       |
   //| (BO/FBO). `level` is the broken/reference level. Non-level modes  |
   //| defer to the candle helper.                                       |
   //+------------------------------------------------------------------+
   bool ConfirmLevelTrigger(bool isLong, double level, const FeatureSnapshot &features) const
   {
      double band = (features.atr > 0) ? 0.25 * features.atr : 0.0;
      switch(m_triggerMode)
      {
         case TRIGGER_BREAK_RETEST:
            // Closed beyond the level after wicking back to retest it.
            if(isLong)  return features.closed_close > level && features.closed_low  <= level + band;
            else        return features.closed_close < level && features.closed_high >= level - band;
         case TRIGGER_PROBE_CONFIRM:
         {
            bool beyond = isLong ? (features.closed_close > level)
                                 : (features.closed_close < level);
            double wickToExtreme = isLong ? (features.closed_high - features.closed_close)
                                          : (features.closed_close - features.closed_low);
            return beyond && features.displacement >= 1.0 &&
                   (features.atr <= 0 || wickToExtreme <= band);
         }
      }
      return ConfirmCandleTrigger(isLong, features);
   }

   //+------------------------------------------------------------------+
   //| Select an objective reference level for a given source, falling   |
   //| back to the supplied range level when the source is unavailable.  |
   //+------------------------------------------------------------------+
   double SelectLevel(ENUM_LEVEL_SOURCE src, bool upper,
                      const FeatureSnapshot &f, double rangeLevel) const
   {
      double lvl = 0.0;
      switch(src)
      {
         case LEVEL_SRC_PREV_DAY:      lvl = upper ? f.prev_day_high : f.prev_day_low; break;
         case LEVEL_SRC_SESSION:       lvl = upper ? f.session_high  : f.session_low;  break;
         case LEVEL_SRC_OPENING_RANGE: lvl = upper ? f.or_high       : f.or_low;       break;
         case LEVEL_SRC_SWING:         lvl = upper ? f.swing_high    : f.swing_low;    break;
         case LEVEL_SRC_RANGE:
         default:                      lvl = rangeLevel;                               break;
      }
      if(lvl <= 0.0) lvl = rangeLevel; // fail-safe fallback
      return lvl;
   }

   //+------------------------------------------------------------------+
   //| Stop placement dispatch. `defaultStop` is the engine's native     |
   //| stop; STOP_MODE_DEFAULT returns it unchanged (baseline-preserving).|
   //| Alternative modes are validated to sit on the correct side of     |
   //| entry, falling back to defaultStop otherwise.                     |
   //+------------------------------------------------------------------+
   double ComputeStop(ENUM_STOP_MODE mode, bool isLong, double entry,
                      double defaultStop, const FeatureSnapshot &f, double atrMult) const
   {
      double dir = isLong ? 1.0 : -1.0;
      double stop = defaultStop;
      switch(mode)
      {
         case STOP_MODE_ATR:
            stop = entry - dir * atrMult * f.atr;
            break;
         case STOP_MODE_SWING:
         {
            double sw = isLong ? f.swing_low : f.swing_high;
            if(sw <= 0) sw = isLong ? f.current_range_low : f.current_range_high;
            stop = sw - dir * atrMult * f.atr;
            break;
         }
         case STOP_MODE_STRUCTURAL:
         {
            double lvl = isLong ? f.current_range_low : f.current_range_high;
            stop = lvl - dir * atrMult * f.atr;
            break;
         }
         case STOP_MODE_SWEEP:
            stop = (f.sweep_extreme > 0) ? f.sweep_extreme - dir * atrMult * f.atr
                                         : defaultStop;
            break;
         case STOP_MODE_DEFAULT:
         default:
            stop = defaultStop;
            break;
      }
      // Stop must be on the protective side of entry.
      if((isLong && stop >= entry) || (!isLong && stop <= entry))
         stop = defaultStop;
      return stop;
   }

   //+------------------------------------------------------------------+
   //| Target selection dispatch. `defaultTarget` is the engine's native |
   //| target; TARGET_MODE_DEFAULT returns it unchanged. Alternatives    |
   //| are validated on the profit side of entry, else fall back.        |
   //+------------------------------------------------------------------+
   double ComputeTarget(ENUM_TARGET_MODE mode, bool isLong, double entry, double stop,
                        double defaultTarget, const FeatureSnapshot &f, double rMult) const
   {
      double dir = isLong ? 1.0 : -1.0;
      double risk = MathAbs(entry - stop);
      double target = defaultTarget;
      switch(mode)
      {
         case TARGET_MODE_FIXED_R:
            target = entry + dir * risk * rMult;
            break;
         case TARGET_MODE_VWAP:
            target = (f.vwap > 0) ? f.vwap : defaultTarget;
            break;
         case TARGET_MODE_RANGE_MID:
            target = (f.range_midpoint > 0) ? f.range_midpoint : defaultTarget;
            break;
         case TARGET_MODE_OPP_BOUNDARY:
            target = isLong ? f.current_range_high : f.current_range_low;
            if(target <= 0) target = defaultTarget;
            break;
         case TARGET_MODE_DEFAULT:
         default:
            target = defaultTarget;
            break;
      }
      // Target must be on the profit side of entry.
      if((isLong && target <= entry) || (!isLong && target >= entry))
         target = defaultTarget;
      return target;
   }
};

#endif // QB_STRATEGYBASE_MQH
