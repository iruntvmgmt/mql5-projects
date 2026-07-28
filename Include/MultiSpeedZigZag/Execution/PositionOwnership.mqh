#ifndef __MSZZ_POSITION_OWNERSHIP_MQH__
#define __MSZZ_POSITION_OWNERSHIP_MQH__

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/Types.mqh>

enum ENUM_MSZZ_ACCOUNT_MODE
{
   MSZZ_ACCOUNT_UNSUPPORTED = 0,
   MSZZ_ACCOUNT_NETTING,
   MSZZ_ACCOUNT_HEDGING,
   MSZZ_ACCOUNT_EXCHANGE
};

enum ENUM_MSZZ_POSITION_OWNER
{
   MSZZ_OWNER_UNKNOWN = 0,
   MSZZ_OWNER_MANUAL,
   MSZZ_OWNER_OWNED,
   MSZZ_OWNER_FOREIGN_EA
};

struct MSZZPositionRecord
{
   bool                     valid;
   ulong                    ticket;
   string                   symbol;
   long                     magic;
   ENUM_POSITION_TYPE       position_type;
   ENUM_MSZZ_DIRECTION      direction;
   ENUM_MSZZ_POSITION_OWNER owner;
   double                   volume;
   double                   price_open;
   double                   stop_loss;
   double                   take_profit;
   datetime                 time_open;
   string                   comment;
};

struct MSZZOwnershipSnapshot
{
   bool                   valid;
   ENUM_MSZZ_ACCOUNT_MODE account_mode;
   int                    total_symbol_positions;
   int                    owned_positions;
   int                    owned_longs;
   int                    owned_shorts;
   int                    manual_positions;
   int                    foreign_positions;
   double                 owned_long_volume;
   double                 owned_short_volume;
   bool                   terminal_selection_error;
   string                 error_reason;
};

class CMSZZPositionOwnership
{
private:
   string                   m_symbol;
   long                     m_magic;
   ENUM_MSZZ_ACCOUNT_MODE   m_account_mode;
   MSZZPositionRecord       m_records[];
   MSZZOwnershipSnapshot    m_snapshot;

   void ResetSnapshot()
   {
      m_snapshot.valid=false;
      m_snapshot.account_mode=m_account_mode;
      m_snapshot.total_symbol_positions=0;
      m_snapshot.owned_positions=0;
      m_snapshot.owned_longs=0;
      m_snapshot.owned_shorts=0;
      m_snapshot.manual_positions=0;
      m_snapshot.foreign_positions=0;
      m_snapshot.owned_long_volume=0.0;
      m_snapshot.owned_short_volume=0.0;
      m_snapshot.terminal_selection_error=false;
      m_snapshot.error_reason="";
   }

   ENUM_MSZZ_DIRECTION DirectionFromPositionType(const ENUM_POSITION_TYPE type) const
   {
      if(type==POSITION_TYPE_BUY) return MSZZ_DIR_LONG;
      if(type==POSITION_TYPE_SELL) return MSZZ_DIR_SHORT;
      return MSZZ_DIR_NONE;
   }

   ENUM_MSZZ_POSITION_OWNER ClassifyOwner(const long magic) const
   {
      if(magic==m_magic) return MSZZ_OWNER_OWNED;
      if(magic==0) return MSZZ_OWNER_MANUAL;
      return MSZZ_OWNER_FOREIGN_EA;
   }

   void AppendRecord(const MSZZPositionRecord &record)
   {
      int n=ArraySize(m_records);
      ArrayResize(m_records,n+1);
      m_records[n]=record;
   }

public:
   CMSZZPositionOwnership(void)
   {
      m_symbol="";
      m_magic=0;
      m_account_mode=MSZZ_ACCOUNT_UNSUPPORTED;
      ArrayResize(m_records,0);
      ResetSnapshot();
   }

   static ENUM_MSZZ_ACCOUNT_MODE DetectAccountMode()
   {
      long raw=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(raw==ACCOUNT_MARGIN_MODE_RETAIL_NETTING) return MSZZ_ACCOUNT_NETTING;
      if(raw==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return MSZZ_ACCOUNT_HEDGING;
      if(raw==ACCOUNT_MARGIN_MODE_EXCHANGE) return MSZZ_ACCOUNT_EXCHANGE;
      return MSZZ_ACCOUNT_UNSUPPORTED;
   }

   static string AccountModeText(const ENUM_MSZZ_ACCOUNT_MODE mode)
   {
      switch(mode)
      {
         case MSZZ_ACCOUNT_NETTING: return "NETTING";
         case MSZZ_ACCOUNT_HEDGING: return "HEDGING";
         case MSZZ_ACCOUNT_EXCHANGE: return "EXCHANGE";
         default: return "UNSUPPORTED";
      }
   }

   void Configure(const string symbol,const long magic)
   {
      m_symbol=symbol;
      m_magic=magic;
      m_account_mode=DetectAccountMode();
      ResetSnapshot();
      ArrayResize(m_records,0);
   }

   bool Refresh()
   {
      ArrayResize(m_records,0);
      ResetSnapshot();
      m_snapshot.account_mode=m_account_mode;

      if(m_symbol=="")
      {
         m_snapshot.error_reason="ownership symbol is empty";
         return false;
      }
      if(m_magic<=0)
      {
         m_snapshot.error_reason="ownership magic must be positive";
         return false;
      }
      if(m_account_mode==MSZZ_ACCOUNT_UNSUPPORTED)
      {
         m_snapshot.error_reason="unsupported account margin mode";
         return false;
      }

      int total=PositionsTotal();
      for(int i=0;i<total;i++)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
         {
            m_snapshot.terminal_selection_error=true;
            m_snapshot.error_reason=StringFormat("PositionGetTicket failed index=%d error=%d",i,GetLastError());
            return false;
         }
         if(!PositionSelectByTicket(ticket))
         {
            m_snapshot.terminal_selection_error=true;
            m_snapshot.error_reason=StringFormat("PositionSelectByTicket failed ticket=%I64u error=%d",ticket,GetLastError());
            return false;
         }

         string symbol=PositionGetString(POSITION_SYMBOL);
         if(symbol!=m_symbol) continue;

         MSZZPositionRecord record;
         record.valid=true;
         record.ticket=ticket;
         record.symbol=symbol;
         record.magic=PositionGetInteger(POSITION_MAGIC);
         record.position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         record.direction=DirectionFromPositionType(record.position_type);
         record.owner=ClassifyOwner(record.magic);
         record.volume=PositionGetDouble(POSITION_VOLUME);
         record.price_open=PositionGetDouble(POSITION_PRICE_OPEN);
         record.stop_loss=PositionGetDouble(POSITION_SL);
         record.take_profit=PositionGetDouble(POSITION_TP);
         record.time_open=(datetime)PositionGetInteger(POSITION_TIME);
         record.comment=PositionGetString(POSITION_COMMENT);
         AppendRecord(record);

         m_snapshot.total_symbol_positions++;
         if(record.owner==MSZZ_OWNER_OWNED)
         {
            m_snapshot.owned_positions++;
            if(record.direction==MSZZ_DIR_LONG)
            {
               m_snapshot.owned_longs++;
               m_snapshot.owned_long_volume+=record.volume;
            }
            else if(record.direction==MSZZ_DIR_SHORT)
            {
               m_snapshot.owned_shorts++;
               m_snapshot.owned_short_volume+=record.volume;
            }
         }
         else if(record.owner==MSZZ_OWNER_MANUAL)
            m_snapshot.manual_positions++;
         else if(record.owner==MSZZ_OWNER_FOREIGN_EA)
            m_snapshot.foreign_positions++;
      }

      m_snapshot.valid=true;
      return true;
   }

   ENUM_MSZZ_ACCOUNT_MODE AccountMode() const { return m_account_mode; }
   int RecordCount() const { return ArraySize(m_records); }
   MSZZOwnershipSnapshot Snapshot() const { return m_snapshot; }

   bool RecordAt(const int index,MSZZPositionRecord &record) const
   {
      if(index<0 || index>=ArraySize(m_records)) return false;
      record=m_records[index];
      return true;
   }

   bool HasOwnedPosition() const { return m_snapshot.valid && m_snapshot.owned_positions>0; }
   bool HasOwnedDirection(const ENUM_MSZZ_DIRECTION direction) const
   {
      if(!m_snapshot.valid) return false;
      if(direction==MSZZ_DIR_LONG) return m_snapshot.owned_longs>0;
      if(direction==MSZZ_DIR_SHORT) return m_snapshot.owned_shorts>0;
      return false;
   }

   bool HasForeignOrManualSymbolPosition() const
   {
      return m_snapshot.valid && (m_snapshot.manual_positions>0 || m_snapshot.foreign_positions>0);
   }

   bool ExecutionAllowedForAccountMode(string &reason) const
   {
      reason="";
      if(!m_snapshot.valid)
      {
         reason=(m_snapshot.error_reason!="" ? m_snapshot.error_reason : "ownership snapshot is invalid");
         return false;
      }
      if(m_account_mode==MSZZ_ACCOUNT_UNSUPPORTED)
      {
         reason="unsupported account margin mode";
         return false;
      }
      if((m_account_mode==MSZZ_ACCOUNT_NETTING || m_account_mode==MSZZ_ACCOUNT_EXCHANGE) &&
         HasForeignOrManualSymbolPosition())
      {
         reason="foreign/manual symbol position blocks isolated MSZZ execution in netting/exchange mode";
         return false;
      }
      return true;
   }

   bool OneOwnedPositionLimitAllows(const bool enabled,string &reason) const
   {
      reason="";
      if(!enabled) return true;
      if(!m_snapshot.valid)
      {
         reason="ownership snapshot is invalid";
         return false;
      }
      if(m_snapshot.owned_positions>0)
      {
         reason=StringFormat("owned MSZZ position limit reached count=%d",m_snapshot.owned_positions);
         return false;
      }
      return true;
   }

   int CollectOwnedOppositeTickets(const ENUM_MSZZ_DIRECTION desired,ulong &tickets[]) const
   {
      ArrayResize(tickets,0);
      if(desired==MSZZ_DIR_NONE) return 0;
      int count=0;
      for(int i=0;i<ArraySize(m_records);i++)
      {
         if(!m_records[i].valid || m_records[i].owner!=MSZZ_OWNER_OWNED) continue;
         if(m_records[i].direction==desired || m_records[i].direction==MSZZ_DIR_NONE) continue;
         ArrayResize(tickets,count+1);
         tickets[count++]=m_records[i].ticket;
      }
      return count;
   }

   bool CloseOwnedOpposite(CTrade &trade,const ENUM_MSZZ_DIRECTION desired,const bool enabled,string &reason)
   {
      reason="";
      if(!enabled) return true;
      if(!m_snapshot.valid)
      {
         reason="ownership snapshot is invalid";
         return false;
      }

      ulong tickets[];
      int count=CollectOwnedOppositeTickets(desired,tickets);
      for(int i=0;i<count;i++)
      {
         if(!trade.PositionClose(tickets[i]))
         {
            reason=StringFormat("owned opposite close failed ticket=%I64u retcode=%u %s",
                                tickets[i],trade.ResultRetcode(),trade.ResultRetcodeDescription());
            return false;
         }
      }
      return true;
   }
};

#endif