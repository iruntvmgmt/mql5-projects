#property script_show_inputs
#include <Trade/Trade.mqh>
CTrade g_trade;

void OnStart()
{
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO || AccountInfoInteger(ACCOUNT_LOGIN)!=870012)
   {
      Print("CleanupLiveProtectionTestPositions REFUSED: not the expected isolated demo account");
      return;
   }
   int total=PositionsTotal();
   int closed=0;
   for(int i=total-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_COMMENT)=="LiveProtectionTest" ||
         PositionGetString(POSITION_COMMENT)=="LiveProtectionTest-SR4" ||
         PositionGetInteger(POSITION_MAGIC)==990029)
      {
         double vol=PositionGetDouble(POSITION_VOLUME);
         PrintFormat("Closing leftover ticket=%I64u volume=%.2f comment=%s",ticket,vol,PositionGetString(POSITION_COMMENT));
         if(g_trade.PositionClose(ticket)) closed++;
      }
   }
   PrintFormat("CleanupLiveProtectionTestPositions: closed %d leftover position(s)",closed);
}
