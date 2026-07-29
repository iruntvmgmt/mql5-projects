#ifndef __MSZZ_VIRTUAL_NETTING_LEDGER_MQH__
#define __MSZZ_VIRTUAL_NETTING_LEDGER_MQH__

#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>

struct MSZZVirtualBookAllocation
{
   bool                      valid;
   long                      book_id;
   ENUM_MSZZ_STRATEGY_ID     strategy_id;
   ENUM_MSZZ_STRATEGY_FAMILY family_id;
   ENUM_MSZZ_DIRECTION       direction;
   double                    signed_volume;
   double                    entry_basis;
   double                    stop_price;
   double                    target_price;
   double                    realized_r;
   double                    unrealized_r;
   double                    allocated_cost;
   string                    logical_position_id;
   string                    exit_reason;
   datetime                  last_update_time;
};

class CMSZZVirtualNettingLedger
{
private:
   string                    m_symbol;
   string                    m_state_file;
   MSZZVirtualBookAllocation m_allocations[];
   string                    m_last_error;

   int FindBook(const long book_id) const
   {
      for(int i=0;i<ArraySize(m_allocations);i++)
         if(m_allocations[i].valid && m_allocations[i].book_id==book_id) return i;
      return -1;
   }

public:
   CMSZZVirtualNettingLedger(void)
   {
      m_symbol="";
      m_state_file="";
      m_last_error="";
      ArrayResize(m_allocations,0);
   }

   bool Configure(const string symbol,const string state_file)
   {
      m_symbol=symbol;
      m_state_file=state_file;
      m_last_error="";
      ArrayResize(m_allocations,0);
      if(symbol=="" || state_file=="")
      {
         m_last_error="virtual ledger symbol/state file required";
         return false;
      }
      return true;
   }

   string LastError() const { return m_last_error; }
   int Count() const { return ArraySize(m_allocations); }

   bool AllocationAt(const int index,MSZZVirtualBookAllocation &allocation) const
   {
      if(index<0 || index>=ArraySize(m_allocations)) return false;
      allocation=m_allocations[index];
      return true;
   }

   double NetSignedVolume() const
   {
      double result=0.0;
      for(int i=0;i<ArraySize(m_allocations);i++)
         if(m_allocations[i].valid) result+=m_allocations[i].signed_volume;
      return result;
   }

   double GrossVolume() const
   {
      double result=0.0;
      for(int i=0;i<ArraySize(m_allocations);i++)
         if(m_allocations[i].valid) result+=MathAbs(m_allocations[i].signed_volume);
      return result;
   }

   bool Upsert(const MSZZVirtualBookAllocation &allocation)
   {
      m_last_error="";
      if(!allocation.valid || allocation.book_id<=0 ||
         allocation.strategy_id==MSZZ_STRAT_NONE ||
         allocation.family_id==MSZZ_FAMILY_NONE ||
         (allocation.direction!=MSZZ_DIR_LONG && allocation.direction!=MSZZ_DIR_SHORT) ||
         allocation.signed_volume==0.0 || allocation.entry_basis<=0.0 ||
         allocation.stop_price<=0.0 ||
         allocation.logical_position_id=="")
      {
         m_last_error="invalid virtual allocation identity";
         return false;
      }
      if((allocation.direction==MSZZ_DIR_LONG && allocation.signed_volume<0.0) ||
         (allocation.direction==MSZZ_DIR_SHORT && allocation.signed_volume>0.0))
      {
         m_last_error="virtual allocation direction/volume sign mismatch";
         return false;
      }
      int index=FindBook(allocation.book_id);
      if(index<0)
      {
         index=ArraySize(m_allocations);
         ArrayResize(m_allocations,index+1);
      }
      m_allocations[index]=allocation;
      return true;
   }

   bool Remove(const long book_id,MSZZVirtualBookAllocation &removed)
   {
      m_last_error="";
      int index=FindBook(book_id);
      if(index<0) { m_last_error="virtual book not found"; return false; }
      removed=m_allocations[index];
      for(int i=index+1;i<ArraySize(m_allocations);i++)
         m_allocations[i-1]=m_allocations[i];
      ArrayResize(m_allocations,ArraySize(m_allocations)-1);
      return true;
   }

   // Broker orders adjust only this difference. A zero result means logical
   // books changed but the consolidated broker position need not change.
   static double RequiredBrokerDelta(const double broker_net_before,
                                     const double desired_logical_net_after)
   {
      return desired_logical_net_after-broker_net_before;
   }
};

#endif
