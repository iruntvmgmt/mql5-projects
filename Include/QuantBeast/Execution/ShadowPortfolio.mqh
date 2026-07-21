//+------------------------------------------------------------------+
//|                                  QuantBeast/ShadowPortfolio.mqh   |
//| Broker-order-free virtual position lifecycle for Shadow mode.    |
//+------------------------------------------------------------------+
#property strict

#ifndef QB_SHADOWPORTFOLIO_MQH
#define QB_SHADOWPORTFOLIO_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Data/MarketData.mqh"

struct ShadowCloseEvent
{
   string strategy_id;
   ulong signal_id;
   ENUM_POSITION_TYPE position_type;
   double original_entry;
   double original_stop;
   double initial_target;
   double initial_volume;
   double mfe;
   double mae;
   ENUM_TREND_REGIME entry_regime_trend;
   ENUM_VOLATILITY_REGIME entry_regime_vol;
   ENUM_SESSION_TYPE entry_session;
   double entry_spread;
   double entry_slippage;
   datetime entry_time;
   double exit_price;
   double gross_pnl;
   double commission;
   double swap;
   double net_pnl;
   ENUM_EXIT_REASON exit_reason;
};

struct ShadowPendingOrder
{
   string strategy_id;
   ulong signal_id;
   ENUM_ORDER_TYPE order_type;
   double price;
   double stop;
   double target;
   double volume;
   datetime placed_time;
   datetime expiry_time;
   bool is_active;
   bool is_filled;
   bool is_expired;
   bool is_cancelled;
   ulong position_ticket;
};

struct ShadowPendingEvent
{
   ulong pending_id;
   string strategy_id;
   ENUM_ORDER_TYPE order_type;
   double price;
   double volume;
   datetime time;
   string action;
};

class CShadowPortfolio
{
private:
   CSymbolAdapter *m_adapter;
   PositionContext m_contexts[20];
   double m_currentVolumes[20];
   double m_realizedGross[20];
   int m_count;
   ulong m_nextId;
   double m_balance;
   double m_initialBalance;
   double m_commissionPerLot;
   double m_slippagePoints;

   bool m_enableBreakeven;
   double m_beTriggerR;
   double m_bePlusPoints;
   bool m_enablePartial;
   double m_partialPct;
   double m_partialTriggerR;
   bool m_enableTrail;
   double m_trailATRMult;
   double m_trailStartR;
   bool m_enableTimeStop;
   int m_timeStopMinutes;
   bool m_enableMomentumExit;
   int m_momentumMinutes;
   double m_momentumMinR;
   bool m_enableRegimeExit;
   double m_shockMult;

   ShadowPendingOrder m_pendingOrders[10];
   int m_pendingCount;
   ulong m_nextPendingId;

   double ExitQuote(ENUM_POSITION_TYPE type, const MarketSnapshot &snap) const
   {
      return (type == POSITION_TYPE_BUY) ? snap.bid : snap.ask;
   }

   double Profit(ENUM_POSITION_TYPE type, double volume,
                 double entry, double exitPrice) const
   {
      double pnl = 0;
      ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(orderType, m_adapter.Symbol(), volume, entry, exitPrice, pnl))
         return pnl;
      int direction = (type == POSITION_TYPE_BUY) ? 1 : -1;
      return m_adapter.CalculateProfit(volume, entry, exitPrice, direction);
   }

   double AdverseExit(ENUM_POSITION_TYPE type, double rawPrice) const
   {
      double slip = m_slippagePoints * m_adapter.Point();
      return m_adapter.NormalizePrice((type == POSITION_TYPE_BUY) ? rawPrice - slip : rawPrice + slip);
   }

   void RemoveAt(int idx)
   {
      for(int i = idx; i < m_count - 1; i++)
      {
         m_contexts[i] = m_contexts[i + 1];
         m_currentVolumes[i] = m_currentVolumes[i + 1];
         m_realizedGross[i] = m_realizedGross[i + 1];
      }
      m_count--;
   }

   void AppendCloseEvent(ShadowCloseEvent &events[], const PositionContext &ctx,
                         double realizedGross,
                         double exitPrice, double finalGross,
                         ENUM_EXIT_REASON reason)
   {
      int n = ArraySize(events);
      ArrayResize(events, n + 1);
      events[n].strategy_id = ctx.strategy_id;
      events[n].signal_id = ctx.signal_id;
      events[n].position_type = ctx.position_type;
      events[n].original_entry = ctx.original_entry;
      events[n].original_stop = ctx.original_stop;
      events[n].initial_target = ctx.initial_target;
      events[n].initial_volume = ctx.initial_volume;
      events[n].mfe = ctx.mfe;
      events[n].mae = ctx.mae;
      events[n].entry_regime_trend = ctx.entry_regime_trend;
      events[n].entry_regime_vol = ctx.entry_regime_vol;
      events[n].entry_session = ctx.entry_session;
      events[n].entry_spread = ctx.entry_spread;
      events[n].entry_slippage = ctx.entry_slippage;
      events[n].entry_time = ctx.entry_time;
      events[n].exit_price = exitPrice;
      events[n].gross_pnl = realizedGross + finalGross;
      events[n].commission = -m_commissionPerLot * ctx.initial_volume;
      events[n].swap = 0;
      events[n].net_pnl = events[n].gross_pnl + events[n].commission;
      events[n].exit_reason = reason;
   }

   bool CloseFull(int idx, double rawExitPrice, ENUM_EXIT_REASON reason,
                  ShadowCloseEvent &events[])
   {
      if(idx < 0 || idx >= m_count) return false;
      PositionContext ctx = m_contexts[idx];
      double exitPrice = AdverseExit(ctx.position_type, rawExitPrice);
      double finalGross = Profit(ctx.position_type, m_currentVolumes[idx],
                                 ctx.original_entry, exitPrice);

      double finalCommission = -m_commissionPerLot * m_currentVolumes[idx];
      m_balance += finalGross + finalCommission;
      AppendCloseEvent(events, ctx, m_realizedGross[idx], exitPrice, finalGross, reason);
      RemoveAt(idx);
      return true;
   }

   bool IsPendingTriggered(const ShadowPendingOrder &order, const MarketSnapshot &snap) const
   {
      double tolerance = 0.5 * m_adapter.Point();
      switch(order.order_type)
      {
         case ORDER_TYPE_BUY_LIMIT:
            return snap.bid <= order.price + tolerance;
         case ORDER_TYPE_SELL_LIMIT:
            return snap.ask >= order.price - tolerance;
         case ORDER_TYPE_BUY_STOP:
            return snap.ask >= order.price - tolerance;
         case ORDER_TYPE_SELL_STOP:
            return snap.bid <= order.price + tolerance;
         default:
            return false;
      }
   }

   bool FillPendingOrder(int pendingIdx, const MarketSnapshot &snap,
                         const RegimeState &regime, string &reason)
   {
      if(pendingIdx < 0 || pendingIdx >= m_pendingCount) return false;
      if(!m_pendingOrders[pendingIdx].is_active) return false;
      if(m_count >= 20)
      {
         reason = "Shadow position capacity reached";
         return false;
      }

      ENUM_POSITION_TYPE type;
      switch(m_pendingOrders[pendingIdx].order_type)
      {
         case ORDER_TYPE_BUY_LIMIT:
         case ORDER_TYPE_BUY_STOP:
            type = POSITION_TYPE_BUY;
            break;
         case ORDER_TYPE_SELL_LIMIT:
         case ORDER_TYPE_SELL_STOP:
            type = POSITION_TYPE_SELL;
            break;
         default:
            reason = "Unsupported pending order type";
            return false;
      }

      double slip = m_slippagePoints * m_adapter.Point();
      double fillPrice = (type == POSITION_TYPE_BUY) ?
                         m_pendingOrders[pendingIdx].price + slip :
                         m_pendingOrders[pendingIdx].price - slip;
      fillPrice = m_adapter.NormalizePrice(fillPrice);

      int idx = m_count;
      ZeroMemory(m_contexts[idx]);
      m_contexts[idx].strategy_id = m_pendingOrders[pendingIdx].strategy_id;
      m_contexts[idx].signal_id = m_pendingOrders[pendingIdx].signal_id;
      m_contexts[idx].order_ticket = m_nextId;
      m_contexts[idx].position_ticket = m_nextId;
      m_contexts[idx].position_identifier = m_nextId++;
      m_contexts[idx].position_type = type;
      m_contexts[idx].original_entry = fillPrice;
      m_contexts[idx].original_stop = m_pendingOrders[pendingIdx].stop;
      m_contexts[idx].current_stop = m_pendingOrders[pendingIdx].stop;
      m_contexts[idx].initial_target = m_pendingOrders[pendingIdx].target;
      m_contexts[idx].initial_volume = m_pendingOrders[pendingIdx].volume;
      m_contexts[idx].original_risk = MathAbs(fillPrice - m_pendingOrders[pendingIdx].stop);
      m_contexts[idx].entry_time = TimeCurrent();
      m_contexts[idx].last_update = TimeCurrent();
      m_contexts[idx].entry_regime_trend = regime.trend;
      m_contexts[idx].entry_regime_vol = regime.volatility;
      m_contexts[idx].entry_session = regime.session;
      m_contexts[idx].entry_spread = snap.spread_points;
      m_contexts[idx].entry_slippage = m_slippagePoints;
      m_contexts[idx].mgmt_state = MGMT_FIXED_STOP;
      m_currentVolumes[idx] = m_pendingOrders[pendingIdx].volume;
      m_realizedGross[idx] = 0;
      m_count++;

      m_pendingOrders[pendingIdx].is_active = false;
      m_pendingOrders[pendingIdx].is_filled = true;
      m_pendingOrders[pendingIdx].position_ticket = m_contexts[idx].position_ticket;

      reason = "Pending order filled";
      return true;
   }

   void RemovePendingAt(int idx)
   {
      for(int i = idx; i < m_pendingCount - 1; i++)
         m_pendingOrders[i] = m_pendingOrders[i + 1];
      m_pendingCount--;
   }

public:
   CShadowPortfolio()
   {
      m_adapter = NULL;
      m_count = 0;
      m_nextId = 1;
      m_balance = 0;
      m_initialBalance = 0;
      m_commissionPerLot = 0;
      m_slippagePoints = 0;
      m_enableBreakeven = false;
      m_beTriggerR = 0;
      m_bePlusPoints = 0;
      m_enablePartial = false;
      m_partialPct = 0;
      m_partialTriggerR = 0;
      m_enableTrail = false;
      m_trailATRMult = 0;
      m_trailStartR = 0;
      m_enableTimeStop = false;
      m_timeStopMinutes = 0;
      m_enableMomentumExit = false;
      m_momentumMinutes = 0;
      m_momentumMinR = 0.0;
      m_enableRegimeExit = false;
      m_shockMult = 3.0;
      m_pendingCount = 0;
      m_nextPendingId = 1;
   }

   //+------------------------------------------------------------------+
   //| Configure the additive momentum-failure and regime-deterioration  |
   //| exits (both off by default, so baseline behavior is unchanged).   |
   //+------------------------------------------------------------------+
   void SetExtendedExits(bool momentumExit, int momentumMinutes, double momentumMinR,
                         bool regimeExit, double shockMult)
   {
      m_enableMomentumExit = momentumExit;
      m_momentumMinutes = momentumMinutes;
      m_momentumMinR = momentumMinR;
      m_enableRegimeExit = regimeExit;
      if(shockMult > 0) m_shockMult = shockMult;
   }

   void Init(CSymbolAdapter &adapter, double startingBalance,
             double commissionPerLot, double slippagePoints,
             bool breakeven, double beTriggerR, double bePlusPoints,
             bool partialClose, double partialPct, double partialTriggerR,
             bool atrTrail, double trailATRMult, double trailStartR,
             bool timeStop, int timeStopMinutes)
   {
      m_adapter = &adapter;
      m_count = 0;
      m_nextId = 1;
      m_initialBalance = startingBalance;
      m_balance = startingBalance;
      m_commissionPerLot = MathMax(0.0, commissionPerLot);
      m_slippagePoints = MathMax(0.0, slippagePoints);
      m_enableBreakeven = breakeven;
      m_beTriggerR = beTriggerR;
      m_bePlusPoints = bePlusPoints;
      m_enablePartial = partialClose;
      m_partialPct = Clamp(partialPct, 0.0, 100.0);
      m_partialTriggerR = partialTriggerR;
      m_enableTrail = atrTrail;
      m_trailATRMult = trailATRMult;
      m_trailStartR = trailStartR;
      m_enableTimeStop = timeStop;
      m_timeStopMinutes = timeStopMinutes;
      m_pendingCount = 0;
      m_nextPendingId = 1;
   }

   bool Open(const StrategySignal &signal, double volume,
             const RegimeState &regime, const MarketSnapshot &snap,
             ulong signalId, string &reason)
   {
      if(m_adapter == NULL || m_count >= 20)
      {
         reason = "Shadow position capacity reached";
         return false;
      }
      if(volume <= 0)
      {
         reason = "Invalid shadow volume";
         return false;
      }

      ENUM_POSITION_TYPE type = (signal.direction == ORDER_TYPE_BUY) ?
                                POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double slip = m_slippagePoints * m_adapter.Point();
      double marketPrice = (type == POSITION_TYPE_BUY) ? snap.ask : snap.bid;
      double entry = m_adapter.NormalizePrice((type == POSITION_TYPE_BUY) ?
                                               marketPrice + slip : marketPrice - slip);
      bool geometry = (type == POSITION_TYPE_BUY && signal.proposed_stop < entry &&
                       signal.proposed_target > entry) ||
                      (type == POSITION_TYPE_SELL && signal.proposed_stop > entry &&
                       signal.proposed_target < entry);
      if(!geometry)
      {
         reason = "Slippage invalidated shadow stop/target geometry";
         return false;
      }

      int idx = m_count;
      ZeroMemory(m_contexts[idx]);
      m_contexts[idx].strategy_id = signal.strategy_id;
      m_contexts[idx].signal_id = signalId;
      m_contexts[idx].order_ticket = m_nextId;
      m_contexts[idx].position_ticket = m_nextId;
      m_contexts[idx].position_identifier = m_nextId++;
      m_contexts[idx].position_type = type;
      m_contexts[idx].original_entry = entry;
      m_contexts[idx].original_stop = signal.proposed_stop;
      m_contexts[idx].current_stop = signal.proposed_stop;
      m_contexts[idx].initial_target = signal.proposed_target;
      m_contexts[idx].initial_volume = volume;
      m_contexts[idx].original_risk = MathAbs(entry - signal.proposed_stop);
      m_contexts[idx].entry_time = TimeCurrent();
      m_contexts[idx].last_update = TimeCurrent();
      m_contexts[idx].entry_regime_trend = regime.trend;
      m_contexts[idx].entry_regime_vol = regime.volatility;
      m_contexts[idx].entry_session = regime.session;
      m_contexts[idx].entry_spread = snap.spread_points;
      m_contexts[idx].entry_slippage = m_slippagePoints;
      m_contexts[idx].mgmt_state = MGMT_FIXED_STOP;
      m_currentVolumes[idx] = volume;
      m_realizedGross[idx] = 0;
      m_count++;
      reason = "Shadow position opened";
      return true;
   }

   bool OpenPending(const string strategyId, ulong signalId,
                    ENUM_ORDER_TYPE orderType, double price,
                    double stop, double target, double volume,
                    datetime expiryTime, string &reason)
   {
      if(m_adapter == NULL)
      {
         reason = "Shadow portfolio not initialized";
         return false;
      }
      if(m_pendingCount >= 10)
      {
         reason = "Shadow pending order capacity reached";
         return false;
      }
      if(volume <= 0)
      {
         reason = "Invalid shadow volume";
         return false;
      }

      bool isLimit = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT);
      bool isStop = (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP);
      if(!isLimit && !isStop)
      {
         reason = "Unsupported pending order type";
         return false;
      }

      bool isBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
      bool geometry = (isBuy && stop < price && target > price) ||
                      (!isBuy && stop > price && target < price);
      if(!geometry)
      {
         reason = "Invalid pending stop/target geometry";
         return false;
      }

      int idx = m_pendingCount;
      ZeroMemory(m_pendingOrders[idx]);
      m_pendingOrders[idx].strategy_id = strategyId;
      m_pendingOrders[idx].signal_id = signalId;
      m_pendingOrders[idx].order_type = orderType;
      m_pendingOrders[idx].price = m_adapter.NormalizePrice(price);
      m_pendingOrders[idx].stop = m_adapter.NormalizePrice(stop);
      m_pendingOrders[idx].target = m_adapter.NormalizePrice(target);
      m_pendingOrders[idx].volume = volume;
      m_pendingOrders[idx].placed_time = TimeCurrent();
      m_pendingOrders[idx].expiry_time = expiryTime;
      m_pendingOrders[idx].is_active = true;
      m_pendingOrders[idx].is_filled = false;
      m_pendingOrders[idx].is_expired = false;
      m_pendingOrders[idx].is_cancelled = false;
      m_pendingOrders[idx].position_ticket = 0;
      m_pendingCount++;

      reason = "Pending order placed";
      return true;
   }

   bool CancelPending(ulong signalId, string &reason)
   {
      for(int i = 0; i < m_pendingCount; i++)
      {
         if(m_pendingOrders[i].signal_id == signalId && m_pendingOrders[i].is_active)
         {
            m_pendingOrders[i].is_active = false;
            m_pendingOrders[i].is_cancelled = true;
            reason = "Pending order cancelled";
            return true;
         }
      }
      reason = "Pending order not found or not active";
      return false;
   }

   int GetPendingCount() const { return m_pendingCount; }
   int GetActivePendingCount() const
   {
      int count = 0;
      for(int i = 0; i < m_pendingCount; i++)
         if(m_pendingOrders[i].is_active) count++;
      return count;
   }

   int Update(const MarketSnapshot &snap, const FeatureSnapshot &feat,
              ShadowCloseEvent &events[], datetime evaluationTime=0)
   {
      ArrayResize(events, 0);
      if(m_adapter == NULL) return 0;
      datetime now = (evaluationTime > 0) ? evaluationTime : TimeCurrent();

      for(int i = m_pendingCount - 1; i >= 0; i--)
      {
         if(!m_pendingOrders[i].is_active) continue;

         if(m_pendingOrders[i].expiry_time > 0 && now >= m_pendingOrders[i].expiry_time)
         {
            m_pendingOrders[i].is_active = false;
            m_pendingOrders[i].is_expired = true;
            continue;
         }

         if(IsPendingTriggered(m_pendingOrders[i], snap))
         {
            string fillReason = "";
            RegimeState regime; ZeroMemory(regime);
            if(FillPendingOrder(i, snap, regime, fillReason))
               continue;
         }
      }

      for(int i = m_count - 1; i >= 0; i--)
      {
         PositionContext ctx = m_contexts[i];
         double currentVolume = m_currentVolumes[i];
         double realizedGross = m_realizedGross[i];
         int direction = (ctx.position_type == POSITION_TYPE_BUY) ? 1 : -1;
         double quote = ExitQuote(ctx.position_type, snap);
         double riskDistance = MathAbs(ctx.original_entry - ctx.original_stop);
         if(riskDistance <= 0) continue;

         double excursion = (quote - ctx.original_entry) * direction;
         ctx.current_r = excursion / riskDistance;
         if(excursion > ctx.mfe) ctx.mfe = excursion;
         if(excursion < ctx.mae) ctx.mae = excursion;

         bool stopHit = (direction > 0) ? quote <= ctx.current_stop : quote >= ctx.current_stop;
         bool targetHit = (direction > 0) ? quote >= ctx.initial_target : quote <= ctx.initial_target;
         if(stopHit)
         {
            double raw = (direction > 0) ? MathMin(quote, ctx.current_stop) :
                                           MathMax(quote, ctx.current_stop);
            m_contexts[i] = ctx;
            CloseFull(i, raw, EXIT_STOP_LOSS, events);
            continue;
         }
         if(targetHit)
         {
            m_contexts[i] = ctx;
            CloseFull(i, ctx.initial_target, EXIT_TARGET_HIT, events);
            continue;
         }

         bool stopBehindBreakeven = (direction > 0) ? ctx.current_stop < ctx.original_entry :
                                                     ctx.current_stop > ctx.original_entry;
         if(m_enableBreakeven && ctx.current_r >= m_beTriggerR && stopBehindBreakeven)
         {
            double candidate = ctx.original_entry + direction * m_bePlusPoints * m_adapter.Point();
            if((direction > 0 && candidate > ctx.current_stop) ||
               (direction < 0 && candidate < ctx.current_stop))
            {
               ctx.current_stop = m_adapter.NormalizePrice(candidate);
               ctx.mgmt_state = MGMT_BREAKEVEN_PLUS;
            }
         }

         if(m_enablePartial && !ctx.partial_exit_done &&
            ctx.current_r >= m_partialTriggerR)
         {
            double closeVolume = m_adapter.NormalizeVolumeDown(currentVolume * m_partialPct / 100.0);
            if(closeVolume >= m_adapter.MinLot() && closeVolume < currentVolume - QB_EPSILON)
            {
               double exitPrice = AdverseExit(ctx.position_type, quote);
               double gross = Profit(ctx.position_type, closeVolume,
                                     ctx.original_entry, exitPrice);
               double commission = m_commissionPerLot * closeVolume;
               m_balance += gross - commission;
               realizedGross += gross;
               currentVolume = m_adapter.NormalizeVolumeDown(currentVolume - closeVolume);
               ctx.partial_exit_done = true;
               ctx.partial_exit_count++;
               ctx.mgmt_state = MGMT_PARTIAL_CLOSE;
            }
         }

         if(m_enableTrail && feat.atr > 0 && ctx.current_r >= m_trailStartR)
         {
            double candidate = quote - direction * m_trailATRMult * feat.atr;
            double minDistance = MathMax(m_adapter.StopLevel(), m_adapter.FreezeLevel()) * m_adapter.Point();
            bool legalSide = (direction > 0) ? candidate < snap.bid - minDistance :
                                              candidate > snap.ask + minDistance;
            bool improves = (direction > 0) ? candidate > ctx.current_stop :
                                              candidate < ctx.current_stop;
            if(legalSide && improves)
            {
               ctx.current_stop = m_adapter.NormalizePrice(candidate);
               ctx.mgmt_state = MGMT_ATR_TRAIL;
            }
         }

         // Momentum-failure exit: open past the window with insufficient
         // progress (current R below the configured minimum).
         if(m_enableMomentumExit && m_momentumMinutes > 0 &&
            now - ctx.entry_time >= m_momentumMinutes * 60 && ctx.current_r < m_momentumMinR)
         {
            m_contexts[i] = ctx;
            m_currentVolumes[i] = currentVolume;
            m_realizedGross[i] = realizedGross;
            CloseFull(i, quote, EXIT_FAILED_MOMENTUM, events);
            continue;
         }

         // Regime-deterioration exit: a shock candle or volatility spike while
         // the position is open (feat-derived proxy in the broker-free path).
         if(m_enableRegimeExit &&
            (feat.abnormal_candle || (m_shockMult > 0 && feat.atr_ratio > m_shockMult)))
         {
            m_contexts[i] = ctx;
            m_currentVolumes[i] = currentVolume;
            m_realizedGross[i] = realizedGross;
            CloseFull(i, quote, EXIT_REGIME_DETERIORATE, events);
            continue;
         }

         if(m_enableTimeStop && m_timeStopMinutes > 0 &&
            now - ctx.entry_time >= m_timeStopMinutes * 60)
         {
            m_contexts[i] = ctx;
            m_currentVolumes[i] = currentVolume;
            m_realizedGross[i] = realizedGross;
            CloseFull(i, quote, EXIT_TIME_STOP, events);
            continue;
         }
         ctx.last_update = now;
         m_contexts[i] = ctx;
         m_currentVolumes[i] = currentVolume;
         m_realizedGross[i] = realizedGross;
      }
      return ArraySize(events);
   }

   int CloseAll(const MarketSnapshot &snap, ShadowCloseEvent &events[],
                ENUM_EXIT_REASON reason = EXIT_EMERGENCY_FLATTEN)
   {
      ArrayResize(events, 0);
      for(int i = m_count - 1; i >= 0; i--)
         CloseFull(i, ExitQuote(m_contexts[i].position_type, snap), reason, events);
      return ArraySize(events);
   }

   double GetBalance() const { return m_balance; }
   double GetInitialBalance() const { return m_initialBalance; }
   int GetPositionCount() const { return m_count; }

   double GetEquity(const MarketSnapshot &snap) const
   {
      double equity = m_balance;
      for(int i = 0; i < m_count; i++)
      {
         double quote = ExitQuote(m_contexts[i].position_type, snap);
         equity += Profit(m_contexts[i].position_type,
                          m_currentVolumes[i],
                          m_contexts[i].original_entry, quote);
         equity -= m_commissionPerLot * m_currentVolumes[i];
      }
      return equity;
   }

   double GetExposure() const
   {
      double total = 0;
      for(int i = 0; i < m_count; i++) total += m_currentVolumes[i];
      return total;
   }

   void CountPositions(int &longCount, int &shortCount) const
   {
      longCount = 0; shortCount = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(m_contexts[i].position_type == POSITION_TYPE_BUY) longCount++;
         else shortCount++;
      }
   }

   int GetStrategyCount(const string strategyId) const
   {
      int count = 0;
      for(int i = 0; i < m_count; i++)
         if(m_contexts[i].strategy_id == strategyId) count++;
      return count;
   }
};

#endif // QB_SHADOWPORTFOLIO_MQH