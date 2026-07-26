//+------------------------------------------------------------------+
//| Test_MSZZ_Ownership.mq5                                          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/PositionOwnershipPolicy.mqh>

void AssertTrue(const bool condition,const string message,int &failures)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

MSZZOwnershipSnapshot Snapshot(const ENUM_MSZZ_ACCOUNT_MODE mode,const int owned,
                               const int manual,const int foreign,const bool valid=true)
{
   MSZZOwnershipSnapshot s;
   s.valid=valid;
   s.account_mode=mode;
   s.total_symbol_positions=owned+manual+foreign;
   s.owned_positions=owned;
   s.owned_longs=0;
   s.owned_shorts=0;
   s.manual_positions=manual;
   s.foreign_positions=foreign;
   s.owned_long_volume=0.0;
   s.owned_short_volume=0.0;
   s.terminal_selection_error=false;
   s.error_reason="";
   return s;
}

MSZZPositionRecord Record(const ulong ticket,const ENUM_MSZZ_POSITION_OWNER owner,
                          const ENUM_MSZZ_DIRECTION direction)
{
   MSZZPositionRecord r;
   r.valid=true;
   r.ticket=ticket;
   r.symbol="XAUUSD";
   r.magic=(owner==MSZZ_OWNER_MANUAL ? 0 : (owner==MSZZ_OWNER_OWNED ? 26072501 : 999));
   r.position_type=(direction==MSZZ_DIR_LONG ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   r.direction=direction;
   r.owner=owner;
   r.volume=0.01;
   r.price_open=100.0;
   r.stop_loss=90.0;
   r.take_profit=110.0;
   r.time_open=D'2026.07.25 10:00';
   r.comment="test";
   return r;
}

void OnStart()
{
   int failures=0;
   string reason;

   AssertTrue(CMSZZPositionOwnershipPolicy::OwnerForMagic(26072501,26072501)==MSZZ_OWNER_OWNED,
              "matching positive magic is owned",failures);
   AssertTrue(CMSZZPositionOwnershipPolicy::OwnerForMagic(0,26072501)==MSZZ_OWNER_MANUAL,
              "zero magic is manual",failures);
   AssertTrue(CMSZZPositionOwnershipPolicy::OwnerForMagic(77,26072501)==MSZZ_OWNER_FOREIGN_EA,
              "different nonzero magic is foreign",failures);

   MSZZOwnershipSnapshot hedging_foreign=Snapshot(MSZZ_ACCOUNT_HEDGING,0,1,1);
   AssertTrue(CMSZZPositionOwnershipPolicy::CanOpen(hedging_foreign,true,reason),
              "hedging mode allows foreign/manual coexistence when no owned position exists",failures);

   MSZZOwnershipSnapshot netting_foreign=Snapshot(MSZZ_ACCOUNT_NETTING,0,0,1);
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(netting_foreign,true,reason),
              "netting mode blocks foreign symbol exposure",failures);

   MSZZOwnershipSnapshot exchange_manual=Snapshot(MSZZ_ACCOUNT_EXCHANGE,0,1,0);
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(exchange_manual,true,reason),
              "exchange mode blocks manual symbol exposure",failures);

   MSZZOwnershipSnapshot hedging_owned=Snapshot(MSZZ_ACCOUNT_HEDGING,1,0,0);
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(hedging_owned,true,reason),
              "one-owned-position policy blocks second owned position",failures);
   AssertTrue(CMSZZPositionOwnershipPolicy::CanOpen(hedging_owned,false,reason),
              "disabled owned-position limit allows additional owned position",failures);

   MSZZOwnershipSnapshot unsupported=Snapshot(MSZZ_ACCOUNT_UNSUPPORTED,0,0,0);
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(unsupported,true,reason),
              "unsupported account mode fails closed",failures);

   MSZZOwnershipSnapshot invalid=Snapshot(MSZZ_ACCOUNT_HEDGING,0,0,0,false);
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(invalid,true,reason),
              "invalid snapshot fails closed",failures);

   MSZZOwnershipSnapshot selection_error=Snapshot(MSZZ_ACCOUNT_HEDGING,0,0,0,true);
   selection_error.terminal_selection_error=true;
   selection_error.error_reason="selection failed";
   AssertTrue(!CMSZZPositionOwnershipPolicy::CanOpen(selection_error,true,reason),
              "terminal selection error fails closed",failures);

   MSZZPositionRecord records[];
   ArrayResize(records,6);
   records[0]=Record(101,MSZZ_OWNER_OWNED,MSZZ_DIR_LONG);
   records[1]=Record(102,MSZZ_OWNER_OWNED,MSZZ_DIR_SHORT);
   records[2]=Record(103,MSZZ_OWNER_MANUAL,MSZZ_DIR_SHORT);
   records[3]=Record(104,MSZZ_OWNER_FOREIGN_EA,MSZZ_DIR_SHORT);
   records[4]=Record(105,MSZZ_OWNER_OWNED,MSZZ_DIR_SHORT);
   records[5]=Record(106,MSZZ_OWNER_OWNED,MSZZ_DIR_NONE);

   ulong tickets[];
   int count=CMSZZPositionOwnershipPolicy::CollectOppositeOwnedTickets(records,ArraySize(records),MSZZ_DIR_LONG,tickets);
   AssertTrue(count==2,"only two owned short tickets collected for desired long",failures);
   AssertTrue(count==2 && tickets[0]==102 && tickets[1]==105,
              "manual, foreign, same-direction, and unknown-direction records excluded",failures);

   count=CMSZZPositionOwnershipPolicy::CollectOppositeOwnedTickets(records,ArraySize(records),MSZZ_DIR_SHORT,tickets);
   AssertTrue(count==1 && tickets[0]==101,"only owned long ticket collected for desired short",failures);

   count=CMSZZPositionOwnershipPolicy::CollectOppositeOwnedTickets(records,ArraySize(records),MSZZ_DIR_NONE,tickets);
   AssertTrue(count==0,"no tickets collected for no desired direction",failures);

   PrintFormat("MSZZ ownership test complete failures=%d",failures);
}
