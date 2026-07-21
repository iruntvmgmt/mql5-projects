//+------------------------------------------------------------------+
//|                                      QuantBeast/PositionManager.mqh|
//|                          XAUUSD Quant Beast EA - Position Manager |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_POSITIONMANAGER_MQH
#define QB_POSITIONMANAGER_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/MathUtils.mqh"
#include "../Data/MarketData.mqh"
#include "BrokerAdapter.mqh"

bool QBUnknownPositionShouldBeManaged(ENUM_UNKNOWN_POS_POLICY unknownPolicy)
{
   // Unknown ownership must never enter active management. REPORT and
   // QUARANTINE are observational policies; IGNORE is explicitly unmanaged;
   // FLATTEN requests a broker close and, if that close is not confirmed, the
   // position still remains unmanaged to avoid accidental trailing, partial
   // close, or stop modification against an unknown strategy context.
   return false;
}

bool QBIsKnownStrategyId(const string strategyId)
{
   return strategyId == STRATEGY_ID_BREAKOUT ||
          strategyId == STRATEGY_ID_FAILED_BREAKOUT ||
          strategyId == STRATEGY_ID_TREND_PULLBACK ||
          strategyId == STRATEGY_ID_MEAN_REVERSION;
}

// Single source of truth for recovering a strategy id from a QB_<id>[_...]
// order/deal comment. Used by both restart reconstruction and live-fill
// transaction handling so the two paths never disagree on the same comment.
string QBStrategyIdFromComment(const string comment)
{
   string prefix = QB_COMMENT_PREFIX + "_";
   if(StringFind(comment, prefix) != 0) return "UNKNOWN";
   string strategyId = StringSubstr(comment, StringLen(prefix));
   int suffix = StringFind(strategyId, "_");
   if(suffix > 0) strategyId = StringSubstr(strategyId, 0, suffix);
   return QBIsKnownStrategyId(strategyId) ? strategyId : "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Position Manager - manages open positions independently           |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   CSymbolAdapter*   m_adapter;
   CBrokerAdapter*   m_broker;

   // Tracked positions
   enum { POSITION_TRACK_CAPACITY = 64 };
   PositionContext   m_positions[POSITION_TRACK_CAPACITY];
   int               m_positionCount;

   // Management config
   bool   m_enableBreakeven;
   double m_breakevenTriggerR;
   double m_breakevenPlusPts;
   bool   m_enablePartialClose;
   double m_partialClosePct;
   double m_partialCloseTriggerR;
   bool   m_enableATRTrail;
   double m_atrTrailMult;
   double m_atrTrailStartR;
   bool   m_enableTimeStop;
   int    m_timeStopMinutes;
   bool   m_enableMomentumExit;
   int    m_momentumMinutes;
   double m_momentumMinR;
   bool   m_enableRegimeExit;

   string StrategyFromComment(const string comment) const
   {
      return QBStrategyIdFromComment(comment);
   }

   // Recover immutable entry metadata from broker history. This prevents a
   // restart after breakeven/trailing from treating the moved stop as the
   // original risk denominator.
   bool RecoverEntryMetadata(ulong positionIdentifier, string &strategyId,
                             ulong &orderTicket, double &originalStop,
                             double &initialTarget, double &initialVolume)
   {
      if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier))
         return false;

      datetime earliest = 0;
      bool found = false;
      for(int i = 0; i < HistoryOrdersTotal(); i++)
      {
         ulong ticket = HistoryOrderGetTicket(i);
         if(ticket == 0) continue;
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE);
         if(type != ORDER_TYPE_BUY && type != ORDER_TYPE_SELL &&
            type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP &&
            type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
            continue;

         datetime setup = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
         if(found && setup >= earliest) continue;

         earliest = setup;
         orderTicket = ticket;
         originalStop = HistoryOrderGetDouble(ticket, ORDER_SL);
         initialTarget = HistoryOrderGetDouble(ticket, ORDER_TP);
         initialVolume = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
         strategyId = StrategyFromComment(HistoryOrderGetString(ticket, ORDER_COMMENT));
         found = true;
      }
      return found;
   }

public:
   //+------------------------------------------------------------------+
   CPositionManager()
   {
      m_adapter     = NULL;
      m_broker      = NULL;
      m_positionCount = 0;

      m_enableBreakeven     = true;
      m_breakevenTriggerR   = 0.5;
      m_breakevenPlusPts    = 3.0;
      m_enablePartialClose  = true;
      m_partialClosePct     = 50.0;
      m_partialCloseTriggerR = 1.0;
      m_enableATRTrail      = true;
      m_atrTrailMult        = 2.0;
      m_atrTrailStartR      = 1.0;
      m_enableTimeStop      = false;
      m_timeStopMinutes     = 240;
      m_enableMomentumExit  = false;
      m_momentumMinutes     = 0;
      m_momentumMinR        = 0.0;
      m_enableRegimeExit    = false;
   }

   //+------------------------------------------------------------------+
   void Init(CSymbolAdapter &adapter, CBrokerAdapter &broker,
             bool breakeven, double beTriggerR, double bePlusPts,
             bool partialClose, double partialPct, double partialTriggerR,
             bool atrTrail, double atrMult, double atrStartR,
             bool timeStop, int timeStopMin)
   {
      m_adapter = &adapter;
      m_broker  = &broker;

      m_enableBreakeven      = breakeven;
      m_breakevenTriggerR    = beTriggerR;
      m_breakevenPlusPts     = bePlusPts;
      m_enablePartialClose   = partialClose;
      m_partialClosePct      = partialPct;
      m_partialCloseTriggerR = partialTriggerR;
      m_enableATRTrail       = atrTrail;
      m_atrTrailMult         = atrMult;
      m_atrTrailStartR       = atrStartR;
      m_enableTimeStop       = timeStop;
      m_timeStopMinutes      = timeStopMin;
   }

   //+------------------------------------------------------------------+
   //| Configure the additive momentum-failure and regime-deterioration  |
   //| exits on the live path (both off by default).                     |
   //+------------------------------------------------------------------+
   void SetExtendedExits(bool momentumExit, int momentumMinutes, double momentumMinR,
                         bool regimeExit)
   {
      m_enableMomentumExit = momentumExit;
      m_momentumMinutes    = momentumMinutes;
      m_momentumMinR       = momentumMinR;
      m_enableRegimeExit   = regimeExit;
   }

   //+------------------------------------------------------------------+
   //| Register a newly opened position                                  |
   //+------------------------------------------------------------------+
   bool RegisterPosition(ulong positionTicket, ulong orderTicket,
                          string strategyId, ulong signalId,
                          double entry, double stop, double target,
                          const RegimeState &regime, const MarketSnapshot &snap,
                          ulong positionIdentifier = 0)
   {
      if(positionTicket == 0)
      {
         QBLogError("Cannot register position with ticket 0");
         return false;
      }

      for(int i = 0; i < m_positionCount; i++)
      {
         if(m_positions[i].position_ticket == positionTicket ||
            (positionIdentifier > 0 && m_positions[i].position_identifier == positionIdentifier))
         {
            // Enrich a transaction-created placeholder when the originating
            // signal/order path arrives later in the same event cycle.
            if(strategyId != "" && strategyId != "UNKNOWN")
               m_positions[i].strategy_id = strategyId;
            if(orderTicket > 0) m_positions[i].order_ticket = orderTicket;
            if(signalId > 0) m_positions[i].signal_id = signalId;
            if(entry > 0) m_positions[i].original_entry = entry;
            if(stop > 0 && m_positions[i].original_stop <= 0)
            {
               m_positions[i].original_stop = stop;
               m_positions[i].current_stop = stop;
            }
            if(target > 0) m_positions[i].initial_target = target;
            return true;
         }
      }

      if(m_positionCount >= POSITION_TRACK_CAPACITY)
      {
         QBLogError("Max position tracking limit reached");
         return false;
      }

      if(!PositionSelectByTicket(positionTicket))
      {
         QBLogError("Cannot register missing broker position: ticket=" + IntegerToString(positionTicket));
         return false;
      }

      int idx = m_positionCount;
      ZeroMemory(m_positions[idx]);

      m_positions[idx].position_ticket   = positionTicket;
      m_positions[idx].position_identifier = (positionIdentifier > 0) ? positionIdentifier :
                                              (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      m_positions[idx].order_ticket      = orderTicket;
      m_positions[idx].position_type     = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      m_positions[idx].strategy_id       = strategyId;
      m_positions[idx].signal_id         = signalId;
      m_positions[idx].original_entry    = (entry > 0) ? entry : PositionGetDouble(POSITION_PRICE_OPEN);
      m_positions[idx].original_stop     = (stop > 0) ? stop : PositionGetDouble(POSITION_SL);
      m_positions[idx].current_stop      = m_positions[idx].original_stop;
      m_positions[idx].initial_target    = (target > 0) ? target : PositionGetDouble(POSITION_TP);
      m_positions[idx].initial_volume    = PositionGetDouble(POSITION_VOLUME);
      m_positions[idx].entry_time        = (datetime)PositionGetInteger(POSITION_TIME);
      m_positions[idx].last_update       = TimeCurrent();
      m_positions[idx].entry_regime_trend = regime.trend;
      m_positions[idx].entry_regime_vol   = regime.volatility;
      m_positions[idx].entry_session      = regime.session;
      m_positions[idx].entry_spread       = snap.spread_points;
      m_positions[idx].mgmt_state         = MGMT_FIXED_STOP;

      // Calculate original risk
      double riskDist = MathAbs(m_positions[idx].original_entry - m_positions[idx].original_stop);
      // Risk estimate simplified
      m_positions[idx].original_risk = riskDist;

      m_positionCount++;
      QBLogInfo("Position registered: ticket=" + IntegerToString(positionTicket) +
                " strategy=" + strategyId + " entry=" + DoubleToString(entry, m_adapter.Digits()));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update all positions (call on new bar or timer)                   |
   //+------------------------------------------------------------------+
   void UpdateAll(const MarketSnapshot &snap, const FeatureSnapshot &feat,
                   const RegimeState &regime)
   {
      for(int i = m_positionCount - 1; i >= 0; i--)
      {
         // Verify position still exists
         if(!PositionSelectByTicket(m_positions[i].position_ticket))
         {
            // Position was closed externally
            RemovePosition(i);
            continue;
         }

         UpdatePosition(i, snap, feat, regime);
      }
   }

   //+------------------------------------------------------------------+
   //| Update a single position                                          |
   //+------------------------------------------------------------------+
   void UpdatePosition(int idx, const MarketSnapshot &snap,
                        const FeatureSnapshot &feat, const RegimeState &regime)
   {
      if(idx < 0 || idx >= m_positionCount) return;

      ulong ticket = m_positions[idx].position_ticket;
      if(!PositionSelectByTicket(ticket)) return;

      double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                             snap.bid : snap.ask;
      double entry    = m_positions[idx].original_entry;
      double stop     = m_positions[idx].current_stop;
      double atr      = feat.atr;
      int    direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

      // Calculate current R
      double riskDist = MathAbs(entry - m_positions[idx].original_stop);
      double currentR = 0;
      if(riskDist > 0)
         currentR = (currentPrice - entry) * direction / riskDist;

      m_positions[idx].current_r = currentR;

      // Update MFE/MAE
      double excursion = (currentPrice - entry) * direction;
      if(excursion > m_positions[idx].mfe)
         m_positions[idx].mfe = excursion;
      if(excursion < m_positions[idx].mae)
         m_positions[idx].mae = excursion;

      // --- Management Logic ---

      // 1. Breakeven
      if(m_enableBreakeven && m_positions[idx].mgmt_state == MGMT_FIXED_STOP)
      {
         if(currentR >= m_breakevenTriggerR)
         {
            double beStop = entry + direction * m_breakevenPlusPts * m_adapter.Point();
            if((direction == 1 && beStop > stop) || (direction == -1 && beStop < stop))
            {
               if(m_broker.ModifyPosition(ticket, beStop, m_positions[idx].initial_target))
               {
                  m_positions[idx].current_stop = beStop;
                  stop = beStop;
                  m_positions[idx].mgmt_state = MGMT_BREAKEVEN_PLUS;
                  QBLogDebug("Position " + IntegerToString(ticket) + " moved to breakeven+");
               }
            }
         }
      }

      // 2. Partial close
      if(m_enablePartialClose && !m_positions[idx].partial_exit_done &&
         currentR >= m_partialCloseTriggerR)
      {
         double partialVol = m_adapter.NormalizeVolumeDown(
            PositionGetDouble(POSITION_VOLUME) * m_partialClosePct / 100.0);

         if(partialVol >= m_adapter.MinLot() && partialVol < PositionGetDouble(POSITION_VOLUME))
         {
            if(m_broker.ClosePosition(ticket, partialVol))
            {
               m_positions[idx].partial_exit_done = true;
               m_positions[idx].partial_exit_count++;
               m_positions[idx].mgmt_state = MGMT_PARTIAL_CLOSE;
               QBLogInfo("Position " + IntegerToString(ticket) + " partial close: " +
                         DoubleToString(partialVol, 2) + " lots at R=" + DoubleToString(currentR, 2));
            }
         }
      }

      // 3. ATR Trailing
      if(m_enableATRTrail && currentR >= m_atrTrailStartR)
      {
         double trailStop = currentPrice - direction * m_atrTrailMult * atr;
         // Only move stop in favorable direction
         stop = m_positions[idx].current_stop;
         if((direction == 1 && trailStop > stop) || (direction == -1 && trailStop < stop))
         {
            double newStop = m_adapter.NormalizePrice(trailStop);
            if(m_broker.ModifyPosition(ticket, newStop, m_positions[idx].initial_target))
            {
               m_positions[idx].current_stop = newStop;
               m_positions[idx].mgmt_state = MGMT_ATR_TRAIL;
            }
         }
      }

      // 4. Momentum-failure exit: open past the window with insufficient
      //    progress (current R below the configured minimum).
      if(m_enableMomentumExit && m_momentumMinutes > 0 &&
         TimeCurrent() - m_positions[idx].entry_time >= m_momentumMinutes * 60 &&
         currentR < m_momentumMinR)
      {
         QBLogInfo("Momentum-failure exit for position " + IntegerToString(ticket) +
                   " at R=" + DoubleToString(currentR, 2));
         m_broker.ClosePosition(ticket);
         return;
      }

      // 5. Regime-deterioration exit: dangerous volatility, or the trend has
      //    flipped hard against the open position.
      if(m_enableRegimeExit)
      {
         bool dangerousVol = (regime.volatility == VOL_SHOCK || regime.volatility == VOL_EXTREME);
         bool trendAgainst = (direction == 1 && regime.trend == TREND_STRONG_DOWN) ||
                             (direction == -1 && regime.trend == TREND_STRONG_UP);
         if(dangerousVol || trendAgainst)
         {
            QBLogInfo("Regime-deterioration exit for position " + IntegerToString(ticket));
            m_broker.ClosePosition(ticket);
            return;
         }
      }

      // 6. Time stop
      if(m_enableTimeStop && m_timeStopMinutes > 0)
      {
         if(TimeCurrent() - m_positions[idx].entry_time > m_timeStopMinutes * 60)
         {
            QBLogInfo("Time stop triggered for position " + IntegerToString(ticket));
            m_broker.ClosePosition(ticket);
            return;
         }
      }

      m_positions[idx].last_update = TimeCurrent();
   }

   //+------------------------------------------------------------------+
   //| Force close a specific position                                   |
   //+------------------------------------------------------------------+
   bool ForceClose(int idx)
   {
      if(idx < 0 || idx >= m_positionCount) return false;

      ulong ticket = m_positions[idx].position_ticket;
      if(!PositionSelectByTicket(ticket)) return false;

      bool result = m_broker.ClosePosition(ticket);
      return result;
   }

   //+------------------------------------------------------------------+
   //| Force close all tracked positions                                 |
   //+------------------------------------------------------------------+
   int ForceCloseAll()
   {
      int closed = 0;
      for(int i = m_positionCount - 1; i >= 0; i--)
      {
         if(ForceClose(i))
            closed++;
      }
      return closed;
   }

   //+------------------------------------------------------------------+
   //| Remove a position from tracking                                   |
   //+------------------------------------------------------------------+
   void RemovePosition(int idx)
   {
      if(idx < 0 || idx >= m_positionCount) return;

      QBLogDebug("Position removed from tracking: " + IntegerToString(m_positions[idx].position_ticket));

      // Shift remaining
      for(int i = idx; i < m_positionCount - 1; i++)
         m_positions[i] = m_positions[i + 1];
      m_positionCount--;
   }

   //+------------------------------------------------------------------+
   //| Reconstruct positions on startup                                  |
   //+------------------------------------------------------------------+
   int ReconstructFromBroker(ulong magicBase, ENUM_UNKNOWN_POS_POLICY unknownPolicy,
                             int &unknownCount, int &unprotectedCount)
   {
      m_positionCount = 0;
      unknownCount = 0;
      unprotectedCount = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            string comment = PositionGetString(POSITION_COMMENT);

            if(magic >= magicBase && magic < magicBase + 1000)
            {
               PositionContext ctx;
               ZeroMemory(ctx);
               ctx.position_ticket = ticket;
               ctx.position_identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
               ctx.position_type   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               ctx.original_entry  = PositionGetDouble(POSITION_PRICE_OPEN);
               ctx.current_stop    = PositionGetDouble(POSITION_SL);
               ctx.original_stop   = ctx.current_stop;
               double currentVolume = PositionGetDouble(POSITION_VOLUME);
               ctx.initial_volume  = currentVolume;
               ctx.entry_time      = (datetime)PositionGetInteger(POSITION_TIME);
               ctx.initial_target  = PositionGetDouble(POSITION_TP);
               ctx.last_update     = TimeCurrent();

               ctx.strategy_id = StrategyFromComment(comment);
               ulong entryOrder = 0;
               RecoverEntryMetadata(ctx.position_identifier, ctx.strategy_id,
                                    entryOrder, ctx.original_stop,
                                    ctx.initial_target, ctx.initial_volume);
               ctx.order_ticket = entryOrder;
               ctx.partial_exit_done = (ctx.initial_volume > currentVolume + 1e-8);
               ctx.partial_exit_count = ctx.partial_exit_done ? 1 : 0;
               ctx.mgmt_state  = MGMT_FIXED_STOP;

               if(ctx.strategy_id == "UNKNOWN")
               {
                  unknownCount++;
                  QBLogWarn("Unknown QuantBeast position ownership: ticket=" +
                            IntegerToString(ticket) + " comment=" + comment);

                  if(unknownPolicy == UNKNOWN_FLATTEN)
                  {
                     if(m_broker.ClosePosition(ticket))
                     {
                        QBLogWarn("Unknown position flatten requested: ticket=" + IntegerToString(ticket));
                        continue;
                     }
                     QBLogError("Unknown position flatten FAILED: ticket=" + IntegerToString(ticket));
                  }
                  else if(unknownPolicy == UNKNOWN_IGNORE)
                  {
                     QBLogWarn("Unknown position ignored by configured policy: ticket=" + IntegerToString(ticket));
                  }

                  if(!QBUnknownPositionShouldBeManaged(unknownPolicy))
                  {
                     QBLogWarn("Unknown position left unmanaged by configured policy: ticket=" +
                               IntegerToString(ticket));
                     continue;
                  }
               }

               // A recovered position must have an actual protective stop,
               // the same guarantee EnsurePositionProtection() enforces on
               // every live fill (OnTradeTransaction). Passing the
               // position's own current SL/TP as both actual and expected
               // means this never attempts a repair modification here (they
               // trivially match if non-zero) -- it purely verifies a
               // protective stop exists at all, failing closed if it is
               // missing (e.g. removed manually while the EA was down).
               if(!m_broker.EnsurePositionProtection(ticket, ctx.current_stop, ctx.initial_target))
               {
                  unprotectedCount++;
                  QBLogError("Reconstructed position has no verified protective stop: ticket=" +
                             IntegerToString(ticket) + " strategy=" + ctx.strategy_id +
                             " sl=" + DoubleToString(ctx.current_stop, m_adapter.Digits()));
               }

               if(m_positionCount < POSITION_TRACK_CAPACITY)
               {
                  m_positions[m_positionCount] = ctx;
                  m_positionCount++;
                  QBLogInfo("Reconstructed position: ticket=" + IntegerToString(ticket) +
                            " strategy=" + ctx.strategy_id +
                            " entry=" + DoubleToString(ctx.original_entry, m_adapter.Digits()) +
                            " originalSL=" + DoubleToString(ctx.original_stop, m_adapter.Digits()));
               }
            }
         }
      }

      return m_positionCount;
   }

   //+------------------------------------------------------------------+
   //| Get counts per strategy and direction                             |
   //+------------------------------------------------------------------+
   int GetPositionCount() const { return m_positionCount; }

   int FindByIdentifier(ulong positionIdentifier) const
   {
      for(int i = 0; i < m_positionCount; i++)
         if(m_positions[i].position_identifier == positionIdentifier)
            return i;
      return -1;
   }

   int FindByTicket(ulong positionTicket) const
   {
      for(int i = 0; i < m_positionCount; i++)
         if(m_positions[i].position_ticket == positionTicket)
            return i;
      return -1;
   }

   bool GetContextByIdentifier(ulong positionIdentifier, PositionContext &ctx) const
   {
      int idx = FindByIdentifier(positionIdentifier);
      if(idx < 0) return false;
      ctx = m_positions[idx];
      return true;
   }

   bool RemoveByIdentifier(ulong positionIdentifier)
   {
      int idx = FindByIdentifier(positionIdentifier);
      if(idx < 0) return false;
      RemovePosition(idx);
      return true;
   }

   int GetLongCount() const
   {
      int count = 0;
      for(int i = 0; i < m_positionCount; i++)
      {
         if(PositionSelectByTicket(m_positions[i].position_ticket))
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               count++;
         }
      }
      return count;
   }

   int GetShortCount() const
   {
      int count = 0;
      for(int i = 0; i < m_positionCount; i++)
      {
         if(PositionSelectByTicket(m_positions[i].position_ticket))
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               count++;
         }
      }
      return count;
   }

   int GetStrategyCount(string strategyId) const
   {
      int count = 0;
      for(int i = 0; i < m_positionCount; i++)
      {
         if(m_positions[i].strategy_id == strategyId)
            count++;
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get all position contexts for journaling/logging                  |
   //+------------------------------------------------------------------+
   void GetAllContexts(PositionContext &ctxs[], int &count)
   {
      count = m_positionCount;
      ArrayResize(ctxs, count);
      for(int i = 0; i < count; i++)
         ctxs[i] = m_positions[i];
   }
};

#endif // QB_POSITIONMANAGER_MQH
