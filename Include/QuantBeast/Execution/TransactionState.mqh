//+------------------------------------------------------------------+
//|                              QuantBeast/TransactionState.mqh      |
//| Deferred, idempotent broker transaction reconciliation           |
//+------------------------------------------------------------------+
#property strict

#ifndef QB_TRANSACTIONSTATE_MQH
#define QB_TRANSACTIONSTATE_MQH

#include "../Core/Constants.mqh"

#define QB_MAX_CLOSE_CANDIDATES 32

struct QBCloseCandidate
{
   ulong position_identifier;
   ulong exit_deal;
};

bool QBShouldFinalizeCloseCandidate(bool positionStillExists)
{
   return !positionStillExists;
}

bool QBIsSupportedLiveMarginMode(long marginMode)
{
   // DEAL_ENTRY_INOUT reversal semantics are intentionally unsupported.
   // Until explicitly implemented and tested, live operation is hedge-only.
   return marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}

bool QBIsOwnedDealForReconciliation(ENUM_DEAL_ENTRY entryType,
                                    bool magicOwned, bool contextOwned)
{
   if(entryType == DEAL_ENTRY_IN)
      return magicOwned;
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
      return magicOwned || contextOwned;
   return false;
}

class CTransactionState
{
private:
   QBCloseCandidate m_close[QB_MAX_CLOSE_CANDIDATES];
   int m_closeCount;

public:
   CTransactionState() { Clear(); }

   void Clear()
   {
      m_closeCount = 0;
      for(int i = 0; i < QB_MAX_CLOSE_CANDIDATES; i++)
         ZeroMemory(m_close[i]);
   }

   int Count() const { return m_closeCount; }

   bool QueueClose(ulong positionIdentifier, ulong exitDeal)
   {
      if(positionIdentifier == 0 || exitDeal == 0) return false;
      for(int i = 0; i < m_closeCount; i++)
      {
         if(m_close[i].position_identifier == positionIdentifier)
         {
            // A later exit deal for the same position carries the final reason.
            m_close[i].exit_deal = exitDeal;
            return true;
         }
      }
      if(m_closeCount >= QB_MAX_CLOSE_CANDIDATES) return false;
      m_close[m_closeCount].position_identifier = positionIdentifier;
      m_close[m_closeCount].exit_deal = exitDeal;
      m_closeCount++;
      return true;
   }

   bool Get(int index, QBCloseCandidate &candidate) const
   {
      if(index < 0 || index >= m_closeCount) return false;
      candidate = m_close[index];
      return true;
   }

   bool RemoveAt(int index)
   {
      if(index < 0 || index >= m_closeCount) return false;
      for(int i = index; i < m_closeCount - 1; i++)
         m_close[i] = m_close[i + 1];
      m_closeCount--;
      ZeroMemory(m_close[m_closeCount]);
      return true;
   }
};

#endif // QB_TRANSACTIONSTATE_MQH
