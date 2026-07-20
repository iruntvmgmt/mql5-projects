//+------------------------------------------------------------------+
//|                                       QuantBeast/BrokerAdapter.mqh|
//|                          XAUUSD Quant Beast EA - Broker Interface |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_BROKERADAPTER_MQH
#define QB_BROKERADAPTER_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Data/MarketData.mqh"
#include <Trade/Trade.mqh>

// A partial fill does not retire the pending order while the broker still
// exposes a positive remainder. These pure transitions are shared with the
// deterministic transaction fixture.
bool QBIsWorkingPendingOrder(bool orderSelectable, ENUM_ORDER_STATE state,
                             double remainingVolume)
{
   if(!orderSelectable || remainingVolume <= QB_EPSILON) return false;
   return state == ORDER_STATE_STARTED ||
          state == ORDER_STATE_PLACED ||
          state == ORDER_STATE_PARTIAL ||
          state == ORDER_STATE_REQUEST_ADD ||
          state == ORDER_STATE_REQUEST_MODIFY;
}

bool QBPendingFillTransition(bool orderSelectable, ENUM_ORDER_STATE state,
                             double remainingVolume, bool &tradeCounted,
                             bool &countTradeNow)
{
   countTradeNow = !tradeCounted;
   if(countTradeNow) tradeCounted = true;
   return QBIsWorkingPendingOrder(orderSelectable, state, remainingVolume);
}

// Pure field mapping for reconstructing a pending order's in-memory
// ExecutionRecord from broker order fields at restart. request_id is set to
// the order ticket as a stable substitute: the original locally-generated
// request_id (GetMicrosecondCount() in PlaceStopOrder) is never transmitted
// to the broker and cannot be recovered, the same accepted gap that already
// exists for PositionContext.signal_id on the position-recovery side.
// request_time uses the order's true ORDER_TIME_SETUP rather than "now" so
// repeated restarts cannot silently extend the order's effective
// InpOrderExpirySeconds budget.
ExecutionRecord QBBuildPendingExecutionRecord(ulong ticket, ENUM_ORDER_TYPE orderType,
                                              double price, double sl, double tp,
                                              string comment, datetime setupTime)
{
   ExecutionRecord rec;
   ZeroMemory(rec);
   rec.request_id       = ticket;
   rec.order_ticket      = ticket;
   rec.order_type        = orderType;
   rec.requested_price   = price;
   rec.stop_loss         = sl;
   rec.take_profit       = tp;
   rec.comment           = comment;
   rec.request_time      = setupTime;
   rec.state             = QB_ORDER_STATE_SUBMITTED;
   return rec;
}

bool QBIsStopAtLeastAsProtective(ENUM_POSITION_TYPE positionType,
                                 double actualSL, double expectedSL,
                                 double tolerance)
{
   if(actualSL <= 0 || expectedSL <= 0) return false;
   if(positionType == POSITION_TYPE_BUY)
      return actualSL >= expectedSL - tolerance;
   if(positionType == POSITION_TYPE_SELL)
      return actualSL <= expectedSL + tolerance;
   return false;
}

enum ENUM_QB_PROTECTION_DECISION
{
   QB_PROTECTION_ACCEPT = 0,
   QB_PROTECTION_REPAIR,
   QB_PROTECTION_EMERGENCY
};

// Protection is a two-pass state machine. Before a repair attempt, any
// missing/looser stop or missing/mismatched target requests one repair. After
// that attempt, a valid stop is sufficient to keep the position protected;
// a target mismatch is non-critical and may be managed later. A missing or
// looser stop always escalates to the centralized emergency dispatcher.
ENUM_QB_PROTECTION_DECISION QBProtectionDecision(
   ENUM_POSITION_TYPE positionType,
   double actualSL, double expectedSL,
   double actualTP, double expectedTP,
   double tolerance, bool repairAttempted)
{
   bool slOK = QBIsStopAtLeastAsProtective(positionType, actualSL,
                                            expectedSL, tolerance);
   bool tpOK = expectedTP <= 0.0 ||
               (actualTP > 0.0 && MathAbs(actualTP - expectedTP) <= tolerance);
   if(slOK && (tpOK || repairAttempted)) return QB_PROTECTION_ACCEPT;
   return repairAttempted ? QB_PROTECTION_EMERGENCY : QB_PROTECTION_REPAIR;
}

// CTrade accepts an integer deviation while the public risk input is a
// double. Round upward so the live execution ceiling never understates the
// slippage allowance already charged by sizing and shadow accounting.
ulong QBDeviationPoints(double configuredPoints)
{
   if(!MathIsValidNumber(configuredPoints) || configuredPoints <= 0.0)
      return 0;
   return (ulong)MathCeil(configuredPoints - QB_EPSILON);
}

// The configured CTrade deviation is measured from the live quote submitted
// on each attempt. Do not let a retry move that quote adversely away from the
// already risk-approved entry, otherwise the same slippage budget is consumed
// twice. Favorable movement remains acceptable.
bool QBIsMarketEntryNotAdverselyDisplaced(ENUM_ORDER_TYPE direction,
                                          double approvedEntry,
                                          double liveEntry,
                                          double tolerance)
{
   if(approvedEntry <= 0.0 || liveEntry <= 0.0) return false;
   if(direction == ORDER_TYPE_BUY)
      return liveEntry <= approvedEntry + tolerance;
   if(direction == ORDER_TYPE_SELL)
      return liveEntry >= approvedEntry - tolerance;
   return false;
}

bool QBShouldRetainBrokerAction(int remainingPositions, int remainingOrders)
{
   return remainingPositions > 0 || remainingOrders > 0;
}

// CTrade's boolean reports local request construction/transmission, not final
// server acceptance. Callers must only enter position/order tracking when both
// the API result and the order-class-specific server retcode agree.
bool QBMarketTransmissionAccepted(bool apiResult, uint retcode)
{
   if(!apiResult) return false;
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

bool QBPendingTransmissionAccepted(bool apiResult, uint retcode)
{
   if(!apiResult) return false;
   return retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

bool QBModificationAccepted(bool apiResult, uint retcode)
{
   return apiResult && (retcode == TRADE_RETCODE_DONE ||
                        retcode == TRADE_RETCODE_NO_CHANGES);
}

bool QBCloseAccepted(bool apiResult, uint retcode)
{
   return apiResult && (retcode == TRADE_RETCODE_DONE ||
                        retcode == TRADE_RETCODE_DONE_PARTIAL);
}

bool QBDeleteAccepted(bool apiResult, uint retcode)
{
   return apiResult && retcode == TRADE_RETCODE_DONE;
}

bool QBIsRetryableSubmissionRetcode(uint retcode)
{
   return retcode == TRADE_RETCODE_REQUOTE ||
          retcode == TRADE_RETCODE_PRICE_CHANGED ||
          retcode == TRADE_RETCODE_PRICE_OFF;
}

// Pending tracking is retired only after a confirmed terminal history state
// or a fill whose resulting position was safely reconciled and protected.
bool QBPendingHistoryResolved(bool historySelectable, ENUM_ORDER_STATE state,
                              bool fillSafelyReconciled)
{
   if(!historySelectable) return false;
   if(state == ORDER_STATE_CANCELED || state == ORDER_STATE_EXPIRED ||
      state == ORDER_STATE_REJECTED)
      return true;
   if(state == ORDER_STATE_FILLED || state == ORDER_STATE_PARTIAL)
      return fillSafelyReconciled;
   return false;
}

bool QBPendingTrackingAfterDelete(bool wasTracked, bool deleteConfirmed)
{
   return wasTracked && !deleteConfirmed;
}

int QBNextConsecutiveBrokerFailures(int currentFailures,
                                    bool brokerAttempted,
                                    bool submissionAccepted)
{
   if(submissionAccepted) return 0;
   if(!brokerAttempted) return MathMax(0, currentFailures);
   if(currentFailures >= INT_MAX - 1) return INT_MAX;
   return MathMax(0, currentFailures) + 1;
}

bool QBBrokerFailureThresholdReached(int failures, int configuredThreshold)
{
   return failures >= MathMax(1, configuredThreshold);
}

//+------------------------------------------------------------------+
//| Broker Adapter - wraps CTrade with validation and logging         |
//+------------------------------------------------------------------+
class CBrokerAdapter
{
private:
   CTrade            m_trade;
   CSymbolAdapter*   m_adapter;
   ulong             m_magicBase;

   // Tracking
   ExecutionRecord   m_lastOrder;
   bool              m_orderActive;

public:
   //+------------------------------------------------------------------+
   CBrokerAdapter()
   {
      m_adapter      = NULL;
      m_magicBase    = QB_MAGIC_BASE;
      m_orderActive  = false;
      ZeroMemory(m_lastOrder);
   }

   //+------------------------------------------------------------------+
   bool Init(CSymbolAdapter &adapter, ulong magicBase, double deviationPoints)
   {
      m_adapter   = &adapter;
      m_magicBase = magicBase;

      // Configure CTrade
      m_trade.SetExpertMagicNumber((int)m_magicBase);
      m_trade.SetDeviationInPoints(QBDeviationPoints(deviationPoints));
      m_trade.SetAsyncMode(false);
      m_trade.SetTypeFillingBySymbol(m_adapter.Symbol());

      QBLogInfo("BrokerAdapter initialized. Magic=" + IntegerToString(m_magicBase) +
                " deviation_pts=" + IntegerToString((long)QBDeviationPoints(deviationPoints)));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Set fill mode based on broker capabilities                        |
   //+------------------------------------------------------------------+
   void DetectFillMode()
   {
      m_trade.SetTypeFillingBySymbol(m_adapter.Symbol());
   }

   void SetPreferredFillMode(int preferredMode)
   {
      if(preferredMode == 0)
      {
         DetectFillMode();
         return;
      }

      long modes = SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_FILLING_MODE);
      if(preferredMode == 1 && (modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else if(preferredMode == 2 && (modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if(preferredMode == 3 &&
              (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_TRADE_EXEMODE) !=
              SYMBOL_TRADE_EXECUTION_MARKET)
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      else
      {
         QBLogWarn("Requested filling mode unsupported; using symbol default");
         DetectFillMode();
      }
   }

   bool IsRetryableRetcode(uint retcode) const
   {
      return QBIsRetryableSubmissionRetcode(retcode);
   }

   //+------------------------------------------------------------------+
   //| Resolve a live position from its stable broker identifier         |
   //+------------------------------------------------------------------+
   bool ResolvePositionByIdentifier(ulong positionIdentifier, ulong &positionTicket)
   {
      positionTicket = 0;
      if(positionIdentifier == 0) return false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;

         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionIdentifier &&
            PositionGetString(POSITION_SYMBOL) == m_adapter.Symbol())
         {
            positionTicket = ticket;
            return true;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Resolve position ticket and identifier from an entry deal         |
   //+------------------------------------------------------------------+
   bool ResolvePositionFromDeal(ulong dealTicket, ulong &positionTicket,
                                ulong &positionIdentifier)
   {
      positionTicket = 0;
      positionIdentifier = 0;
      if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return false;

      positionIdentifier = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      return ResolvePositionByIdentifier(positionIdentifier, positionTicket);
   }

   //+------------------------------------------------------------------+
   //| Verify initial SL/TP; repair once, otherwise close fail-safe       |
   //+------------------------------------------------------------------+
   bool EnsurePositionProtection(ulong positionTicket, double expectedSL,
                                 double expectedTP)
   {
      expectedSL = m_adapter.NormalizePrice(expectedSL);
      expectedTP = (expectedTP > 0) ? m_adapter.NormalizePrice(expectedTP) : 0;
      double tolerance = MathMax(m_adapter.TickSize(), m_adapter.Point()) * 0.51;

      if(positionTicket == 0 || !PositionSelectByTicket(positionTicket))
      {
         QBLogError("Protection verification failed: invalid position");
         return false;
      }

      if(expectedSL <= 0)
      {
         QBLogError("Protection verification failed: no valid protective stop");
         return false;
      }

      double actualSL = PositionGetDouble(POSITION_SL);
      double actualTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE positionType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_QB_PROTECTION_DECISION decision =
         QBProtectionDecision(positionType, actualSL, expectedSL,
                              actualTP, expectedTP, tolerance, false);
      if(decision == QB_PROTECTION_ACCEPT) return true;

      QBLogWarn("Initial protection mismatch; attempting repair for position " +
                IntegerToString(positionTicket));
      // Never loosen a stop that the broker made tighter. Repair only the
      // missing/looser stop and independently restore the requested target.
      bool slWasSafe = QBIsStopAtLeastAsProtective(positionType, actualSL,
                                                    expectedSL, tolerance);
      double repairSL = slWasSafe ? actualSL : expectedSL;
      ModifyPosition(positionTicket, repairSL, expectedTP);

      if(PositionSelectByTicket(positionTicket))
      {
         actualSL = PositionGetDouble(POSITION_SL);
         actualTP = PositionGetDouble(POSITION_TP);
         positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         decision = QBProtectionDecision(positionType, actualSL, expectedSL,
                                         actualTP, expectedTP, tolerance, true);
         if(decision == QB_PROTECTION_ACCEPT)
         {
            bool tpOK = expectedTP <= 0 ||
                        (actualTP > 0 && MathAbs(actualTP - expectedTP) <= tolerance);
            if(!tpOK)
               QBLogWarn("Protective stop verified but requested target could not be restored for position " +
                         IntegerToString(positionTicket));
            return true;
         }
      }

      QBLogError("Unable to establish protective stop for position " +
                 IntegerToString(positionTicket));
      // Do not close here. Every production caller routes this failure into
      // ActivateProtectionEmergency(), which owns the single immediate close
      // attempt, persistent flatten latch, and bounded timer/tick retries.
      return false;
   }

   //+------------------------------------------------------------------+
   //| Place a market order                                              |
   //+------------------------------------------------------------------+
   bool PlaceMarketOrder(ENUM_ORDER_TYPE type, double volume,
                          double sl, double tp, string comment,
                          ExecutionRecord &record)
   {
      ZeroMemory(record);
      record.request_id    = GetMicrosecondCount();
      record.order_type    = type;
      record.requested_volume = volume;
      record.request_time  = TimeCurrent();
      record.state         = QB_ORDER_STATE_NEW;
      record.comment       = comment;

      double price = (type == ORDER_TYPE_BUY) ?
                     SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_ASK) :
                     SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_BID);

      record.requested_price = price;
      record.stop_loss   = sl;
      record.take_profit = tp;

      // Normalize
      price = m_adapter.NormalizePrice(price);
      sl    = m_adapter.NormalizePrice(sl);
      tp    = m_adapter.NormalizePrice(tp);
      record.requested_price = price;
      record.stop_loss = sl;
      record.take_profit = tp;

      m_trade.SetExpertMagicNumber((int)m_magicBase);

      bool result = false;
      if(type == ORDER_TYPE_BUY)
         result = m_trade.Buy(volume, m_adapter.Symbol(), price, sl, tp, comment);
      else
         result = m_trade.Sell(volume, m_adapter.Symbol(), price, sl, tp, comment);

      record.retcode = m_trade.ResultRetcode();
      record.order_ticket = m_trade.ResultOrder();
      record.deal_ticket = m_trade.ResultDeal();

      bool accepted = QBMarketTransmissionAccepted(result, record.retcode);
      if(accepted)
      {
         record.fill_price = m_trade.ResultPrice();
         record.filled_volume = m_trade.ResultVolume();
         record.fill_time  = TimeCurrent();
         record.slippage_points = MathAbs(record.fill_price - record.requested_price) /
                                   m_adapter.Point();

         if(!ResolvePositionFromDeal(record.deal_ticket, record.position_ticket,
                                     record.position_identifier))
         {
            record.state = QB_ORDER_STATE_ACKNOWLEDGED;
            QBLogError("Filled deal could not be reconciled to a live position: deal=" +
                       IntegerToString(record.deal_ticket));
            m_lastOrder = record;
            return false;
         }

         if(!EnsurePositionProtection(record.position_ticket, sl, tp))
         {
            record.state = QB_ORDER_STATE_ACKNOWLEDGED;
            m_lastOrder = record;
            return false;
         }

         record.state = QB_ORDER_STATE_PROTECTED;
         QBLogInfo("Order filled and protected: order=" + IntegerToString(record.order_ticket) +
                   " position=" + IntegerToString(record.position_ticket) +
                   " " + EnumToString(type) + " vol=" + DoubleToString(volume, 2) +
                   " price=" + DoubleToString(record.fill_price, m_adapter.Digits()) +
                   " slip=" + DoubleToString(record.slippage_points, 1) + "pts");
      }
      else
      {
         record.state = QB_ORDER_STATE_REJECTED;
         record.retry_count++;
         QBLogError("Order rejected: retcode=" + IntegerToString((long)record.retcode) +
                    " " + m_trade.ResultRetcodeDescription());
      }

      m_lastOrder = record;
      return accepted;
   }

   //+------------------------------------------------------------------+
   //| Place a pending (stop) order                                      |
   //+------------------------------------------------------------------+
   bool PlaceStopOrder(ENUM_ORDER_TYPE type, double volume,
                        double price, double sl, double tp,
                        datetime expiry, string comment,
                        ExecutionRecord &record)
   {
      ZeroMemory(record);
      record.request_id    = GetMicrosecondCount();
      record.order_type    = type;
      record.requested_volume = volume;
      record.requested_price = price;
      record.stop_loss     = sl;
      record.take_profit   = tp;
      record.request_time  = TimeCurrent();
      record.state         = QB_ORDER_STATE_NEW;
      record.comment       = comment;

      price = m_adapter.NormalizePrice(price);
      sl    = m_adapter.NormalizePrice(sl);
      tp    = m_adapter.NormalizePrice(tp);

      m_trade.SetExpertMagicNumber((int)m_magicBase);

      // For stop orders: Buy Stop if entry > current ask, Sell Stop if entry < current bid
      double currentAsk = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_ASK);
      double currentBid = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_BID);

      ENUM_ORDER_TYPE orderType;
      if(type == ORDER_TYPE_BUY)
      {
         if(price > currentAsk)
            orderType = ORDER_TYPE_BUY_STOP;
         else
            orderType = ORDER_TYPE_BUY_LIMIT;
      }
      else
      {
         if(price < currentBid)
            orderType = ORDER_TYPE_SELL_STOP;
         else
            orderType = ORDER_TYPE_SELL_LIMIT;
      }

      bool result = m_trade.OrderOpen(m_adapter.Symbol(), orderType, volume,
                                       0, price, sl, tp,
                                       ORDER_TIME_SPECIFIED, expiry, comment);

      record.retcode = m_trade.ResultRetcode();
      record.order_ticket = m_trade.ResultOrder();

      bool accepted = QBPendingTransmissionAccepted(result, record.retcode);
      if(accepted)
      {
         record.order_type = orderType;
         record.state = QB_ORDER_STATE_SUBMITTED;
         QBLogInfo("Pending order placed: ticket=" + IntegerToString(record.order_ticket) +
                   " " + EnumToString(orderType) + " at " + DoubleToString(price, m_adapter.Digits()));
      }
      else
      {
         record.state = QB_ORDER_STATE_REJECTED;
         QBLogError("Pending order rejected: " + m_trade.ResultRetcodeDescription());
      }

      m_lastOrder = record;
      return accepted;
   }

   //+------------------------------------------------------------------+
   //| Modify position stop loss and take profit                         |
   //+------------------------------------------------------------------+
   bool ModifyPosition(ulong positionTicket, double sl, double tp)
   {
      if(!PositionSelectByTicket(positionTicket))
      {
         QBLogError("Position modify failed: broker position not found ticket=" +
                    IntegerToString(positionTicket));
         return false;
      }

      sl = m_adapter.NormalizePrice(sl);
      tp = m_adapter.NormalizePrice(tp);

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double existingSL = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_BID);
      double ask = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_ASK);
      double minDistance = MathMax(m_adapter.StopLevel(), m_adapter.FreezeLevel()) * m_adapter.Point();

      if(sl > 0)
      {
         bool correctSide = (posType == POSITION_TYPE_BUY) ?
                            (sl < bid - minDistance + QB_EPSILON) :
                            (sl > ask + minDistance - QB_EPSILON);
         bool notLooser = (existingSL <= 0) ||
                          (posType == POSITION_TYPE_BUY && sl >= existingSL - QB_EPSILON) ||
                          (posType == POSITION_TYPE_SELL && sl <= existingSL + QB_EPSILON);
         if(!correctSide || !notLooser)
         {
            QBLogError("Position modify blocked: invalid/looser stop ticket=" +
                       IntegerToString(positionTicket) +
                       " oldSL=" + DoubleToString(existingSL, m_adapter.Digits()) +
                       " newSL=" + DoubleToString(sl, m_adapter.Digits()));
            return false;
         }
      }

      if(tp > 0)
      {
         bool targetSide = (posType == POSITION_TYPE_BUY) ?
                           (tp > ask + minDistance - QB_EPSILON) :
                           (tp < bid - minDistance + QB_EPSILON);
         if(!targetSide)
         {
            QBLogError("Position modify blocked: invalid target ticket=" +
                       IntegerToString(positionTicket));
            return false;
         }
      }

      m_trade.SetExpertMagicNumber((int)m_magicBase);

      bool apiResult = m_trade.PositionModify(positionTicket, sl, tp);
      bool result = QBModificationAccepted(apiResult, m_trade.ResultRetcode());

      if(!result)
         QBLogError("Position modify failed: ticket=" + IntegerToString(positionTicket) +
                    " error=" + m_trade.ResultRetcodeDescription());

      return result;
   }

   //+------------------------------------------------------------------+
   //| Close a position                                                  |
   //+------------------------------------------------------------------+
   bool ClosePosition(ulong positionTicket, double volume = 0)
   {
      m_trade.SetExpertMagicNumber((int)m_magicBase);

      bool result;
      if(volume > 0)
         result = m_trade.PositionClosePartial(positionTicket, volume);
      else
         result = m_trade.PositionClose(positionTicket);
      result = QBCloseAccepted(result, m_trade.ResultRetcode());

      if(!result)
         QBLogError("Position close failed: ticket=" + IntegerToString(positionTicket) +
                    " error=" + m_trade.ResultRetcodeDescription());
      else
         QBLogInfo("Position closed: ticket=" + IntegerToString(positionTicket) +
                   " price=" + DoubleToString(m_trade.ResultPrice(), m_adapter.Digits()));

      return result;
   }

   //+------------------------------------------------------------------+
   //| Delete a pending order                                            |
   //+------------------------------------------------------------------+
   bool DeleteOrder(ulong orderTicket)
   {
      m_trade.SetExpertMagicNumber((int)m_magicBase);

      bool apiResult = m_trade.OrderDelete(orderTicket);
      bool result = QBDeleteAccepted(apiResult, m_trade.ResultRetcode());

      if(!result)
         QBLogError("Order delete failed: ticket=" + IntegerToString(orderTicket) +
                    " error=" + m_trade.ResultRetcodeDescription());

      return result;
   }

   //+------------------------------------------------------------------+
   //| Cancel all pending orders owned by this EA                        |
   //+------------------------------------------------------------------+
   int CancelAllPending()
   {
      int cancelled = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = OrderGetInteger(ORDER_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
            {
               if(DeleteOrder(ticket))
                  cancelled++;
            }
         }
      }
      QBLogInfo("CancelAll: cancelled " + IntegerToString(cancelled) + " pending orders");
      return cancelled;
   }

   //+------------------------------------------------------------------+
   //| Close all positions owned by this EA                              |
   //+------------------------------------------------------------------+
   int CloseAllPositions()
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
            {
               if(ClosePosition(ticket))
                  closed++;
            }
         }
      }
      QBLogInfo("CloseAll: closed " + IntegerToString(closed) + " positions");
      return closed;
   }

   //+------------------------------------------------------------------+
   //| Count positions by direction for this EA                          |
   //+------------------------------------------------------------------+
   void CountPositions(int &longCount, int &shortCount)
   {
      longCount = 0;
      shortCount = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
            {
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  longCount++;
               else
                  shortCount++;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Count pending orders for this EA                                  |
   //+------------------------------------------------------------------+
   int CountPendingOrders()
   {
      int count = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = OrderGetInteger(ORDER_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Find the single owned pending order, if exactly one exists.       |
   //| Returns the total count found (0, 1, or >1); foundTicket is only  |
   //| set when the count is exactly 1. The in-memory model              |
   //| (g_ActiveOrder/g_OrderPending) tracks only one pending order at a |
   //| time, so a count other than 0 or 1 must be treated as ambiguous   |
   //| by the caller rather than guessed at.                             |
   //+------------------------------------------------------------------+
   int FindSingleOwnedPendingOrder(ulong &foundTicket)
   {
      int count = 0;
      ulong lastTicket = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = OrderGetInteger(ORDER_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
            {
               count++;
               lastTicket = ticket;
            }
         }
      }
      foundTicket = (count == 1) ? lastTicket : 0;
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get total lot exposure for this EA                                |
   //+------------------------------------------------------------------+
   double GetTotalExposure()
   {
      double total = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(magic >= m_magicBase && magic < m_magicBase + 1000)
               total += PositionGetDouble(POSITION_VOLUME);
         }
      }
      return total;
   }

   //+------------------------------------------------------------------+
   CTrade* GetTrade() { return &m_trade; }
};

#endif // QB_BROKERADAPTER_MQH
