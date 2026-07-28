#ifndef __MSZZ_POSITION_OWNERSHIP_POLICY_MQH__
#define __MSZZ_POSITION_OWNERSHIP_POLICY_MQH__

#include <MultiSpeedZigZag/Execution/PositionOwnership.mqh>

class CMSZZPositionOwnershipPolicy
{
public:
   static ENUM_MSZZ_POSITION_OWNER OwnerForMagic(const long record_magic,const long owned_magic)
   {
      if(owned_magic>0 && record_magic==owned_magic) return MSZZ_OWNER_OWNED;
      if(record_magic==0) return MSZZ_OWNER_MANUAL;
      return MSZZ_OWNER_FOREIGN_EA;
   }

   static bool ForeignExposureBlocks(const MSZZOwnershipSnapshot &snapshot)
   {
      if(!snapshot.valid) return true;
      if(snapshot.account_mode!=MSZZ_ACCOUNT_NETTING && snapshot.account_mode!=MSZZ_ACCOUNT_EXCHANGE)
         return false;
      return snapshot.manual_positions>0 || snapshot.foreign_positions>0;
   }

   static bool CanOpen(const MSZZOwnershipSnapshot &snapshot,const bool one_owned_position,
                       string &reason)
   {
      reason="";
      if(!snapshot.valid)
      {
         reason=(snapshot.error_reason!="" ? snapshot.error_reason : "ownership snapshot invalid");
         return false;
      }
      if(snapshot.account_mode==MSZZ_ACCOUNT_UNSUPPORTED)
      {
         reason="unsupported account mode";
         return false;
      }
      if(snapshot.terminal_selection_error)
      {
         reason=(snapshot.error_reason!="" ? snapshot.error_reason : "terminal position selection error");
         return false;
      }
      if(ForeignExposureBlocks(snapshot))
      {
         reason="foreign/manual symbol exposure blocks netting or exchange execution";
         return false;
      }
      if(one_owned_position && snapshot.owned_positions>0)
      {
         reason=StringFormat("owned position limit reached count=%d",snapshot.owned_positions);
         return false;
      }
      return true;
   }

   static int CollectOppositeOwnedTickets(const MSZZPositionRecord &records[],const int count,
                                          const ENUM_MSZZ_DIRECTION desired,ulong &tickets[])
   {
      ArrayResize(tickets,0);
      if(desired==MSZZ_DIR_NONE) return 0;
      int n=0;
      int limit=MathMin(count,ArraySize(records));
      for(int i=0;i<limit;i++)
      {
         if(!records[i].valid || records[i].owner!=MSZZ_OWNER_OWNED) continue;
         if(records[i].direction==MSZZ_DIR_NONE || records[i].direction==desired) continue;
         ArrayResize(tickets,n+1);
         tickets[n++]=records[i].ticket;
      }
      return n;
   }
};

#endif