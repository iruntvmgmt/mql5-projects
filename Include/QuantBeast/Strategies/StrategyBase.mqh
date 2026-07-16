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
                     ENUM_TRIGGER_TYPE triggerMode)
   {
      m_strategyId    = id;
      m_strategyName  = name;
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
};

#endif // QB_STRATEGYBASE_MQH
