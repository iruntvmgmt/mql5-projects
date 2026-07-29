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

   bool IsValidAllocation(const MSZZVirtualBookAllocation &allocation) const
   {
      if(!allocation.valid || allocation.book_id<=0 ||
         allocation.strategy_id==MSZZ_STRAT_NONE ||
         allocation.family_id==MSZZ_FAMILY_NONE ||
         (allocation.direction!=MSZZ_DIR_LONG && allocation.direction!=MSZZ_DIR_SHORT) ||
         allocation.signed_volume==0.0 || allocation.entry_basis<=0.0 ||
         allocation.stop_price<=0.0 || allocation.logical_position_id=="")
         return false;
      if((allocation.direction==MSZZ_DIR_LONG && allocation.signed_volume<0.0) ||
         (allocation.direction==MSZZ_DIR_SHORT && allocation.signed_volume>0.0))
         return false;
      return true;
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

   static double AllocateCostProRata(const double total_cost,
                                     const double allocation_volume,
                                     const double total_volume)
   {
      if(total_cost<0.0 || allocation_volume<0.0 || total_volume<=0.0 ||
         allocation_volume>total_volume+1e-12)
         return -1.0;
      return total_cost*(allocation_volume/total_volume);
   }

   static bool SyntheticStopTriggered(const MSZZVirtualBookAllocation &allocation,
                                      const double bid,const double ask)
   {
      if(!allocation.valid || allocation.stop_price<=0.0 || bid<=0.0 || ask<=0.0)
         return false;
      if(allocation.direction==MSZZ_DIR_LONG) return bid<=allocation.stop_price;
      if(allocation.direction==MSZZ_DIR_SHORT) return ask>=allocation.stop_price;
      return false;
   }

   static bool SyntheticTargetTriggered(const MSZZVirtualBookAllocation &allocation,
                                        const double bid,const double ask)
   {
      if(!allocation.valid || allocation.target_price<=0.0 || bid<=0.0 || ask<=0.0)
         return false;
      if(allocation.direction==MSZZ_DIR_LONG) return bid>=allocation.target_price;
      if(allocation.direction==MSZZ_DIR_SHORT) return ask<=allocation.target_price;
      return false;
   }

   bool Upsert(const MSZZVirtualBookAllocation &allocation)
   {
      m_last_error="";
      if(!IsValidAllocation(allocation))
      {
         m_last_error="invalid virtual allocation identity";
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

   bool Reduce(const long book_id,const double close_volume,
               const double realized_r_delta,const double execution_cost_delta)
   {
      m_last_error="";
      int index=FindBook(book_id);
      if(index<0) { m_last_error="virtual book not found"; return false; }
      if(close_volume<=0.0 || execution_cost_delta<0.0)
      { m_last_error="invalid virtual reduction"; return false; }
      double current=MathAbs(m_allocations[index].signed_volume);
      if(close_volume>current+1e-12)
      { m_last_error="virtual reduction exceeds allocation"; return false; }
      m_allocations[index].realized_r+=realized_r_delta;
      m_allocations[index].allocated_cost+=execution_cost_delta;
      double remaining=current-close_volume;
      if(remaining<=1e-12)
      {
         MSZZVirtualBookAllocation removed;
         return Remove(book_id,removed);
      }
      m_allocations[index].signed_volume=
         (m_allocations[index].direction==MSZZ_DIR_LONG ? remaining : -remaining);
      m_allocations[index].last_update_time=TimeCurrent();
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

   bool Save()
   {
      m_last_error="";
      if(m_state_file=="") { m_last_error="virtual ledger not configured"; return false; }
      int h=FileOpen(m_state_file,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE) { m_last_error="cannot open virtual ledger state"; return false; }
      FileWrite(h,"MSZZVL1",m_symbol,ArraySize(m_allocations));
      for(int i=0;i<ArraySize(m_allocations);i++)
      {
         MSZZVirtualBookAllocation a=m_allocations[i];
         FileWrite(h,(a.valid?1:0),a.book_id,(int)a.strategy_id,(int)a.family_id,
                   (int)a.direction,a.signed_volume,a.entry_basis,a.stop_price,
                   a.target_price,a.realized_r,a.unrealized_r,a.allocated_cost,
                   a.logical_position_id,a.exit_reason,(long)a.last_update_time);
      }
      FileFlush(h); FileClose(h);
      return true;
   }

   bool Load()
   {
      m_last_error="";
      if(m_state_file=="") { m_last_error="virtual ledger not configured"; return false; }
      int h=FileOpen(m_state_file,FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE) { m_last_error="cannot open virtual ledger state"; return false; }
      string schema=FileReadString(h);
      string symbol=FileReadString(h);
      int count=(int)FileReadNumber(h);
      if(schema!="MSZZVL1" || symbol!=m_symbol || count<0 || count>1000)
      {
         FileClose(h); m_last_error="virtual ledger header invalid"; return false;
      }
      MSZZVirtualBookAllocation loaded[];
      ArrayResize(loaded,0);
      for(int i=0;i<count;i++)
      {
         if(FileIsEnding(h))
         {
            FileClose(h); m_last_error="virtual ledger truncated"; return false;
         }
         MSZZVirtualBookAllocation a; ZeroMemory(a);
         a.valid=((int)FileReadNumber(h)==1);
         a.book_id=(long)FileReadNumber(h);
         a.strategy_id=(ENUM_MSZZ_STRATEGY_ID)(int)FileReadNumber(h);
         a.family_id=(ENUM_MSZZ_STRATEGY_FAMILY)(int)FileReadNumber(h);
         a.direction=(ENUM_MSZZ_DIRECTION)(int)FileReadNumber(h);
         a.signed_volume=FileReadNumber(h);
         a.entry_basis=FileReadNumber(h);
         a.stop_price=FileReadNumber(h);
         a.target_price=FileReadNumber(h);
         a.realized_r=FileReadNumber(h);
         a.unrealized_r=FileReadNumber(h);
         a.allocated_cost=FileReadNumber(h);
         a.logical_position_id=FileReadString(h);
         a.exit_reason=FileReadString(h);
         a.last_update_time=(datetime)(long)FileReadNumber(h);
         int at=ArraySize(loaded);
         ArrayResize(loaded,at+1);
         loaded[at]=a;
      }
      FileClose(h);
      for(int i=0;i<ArraySize(loaded);i++)
      {
         if(!IsValidAllocation(loaded[i]))
         {
            m_last_error="virtual ledger record invalid";
            return false;
         }
      }
      ArrayResize(m_allocations,ArraySize(loaded));
      for(int i=0;i<ArraySize(loaded);i++) m_allocations[i]=loaded[i];
      return true;
   }
};

#endif
