#ifndef __MSZZ_ACCOUNT_SAFEGUARD_MQH__
#define __MSZZ_ACCOUNT_SAFEGUARD_MQH__

// See DECISION_LOG.md D013. First increment of Phase 7 (account
// safeguards) -- a manual kill switch, a daily trade-count limit, and a
// daily realized-loss limit, all scoped to this EA's own symbol+magic
// trades. Cooldowns and floating-equity drawdown limits are explicitly
// deferred. See D013 for exactly what is and is not covered.

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// CMSZZPositionOwnershipPolicy (D005), CMSZZReconciliationPolicy (D009),
// CMSZZIntentStateMachine (D010), CMSZZProtectionPolicy (D011), and
// CMSZZMarginPolicy (D012).
class CMSZZAccountSafeguardPolicy
{
public:
   // A non-positive max_trades disables this check entirely, rather than
   // being interpreted as "zero trades allowed."
   static bool TradeCountLimitReached(const int today_count,const int max_trades)
   {
      if(max_trades<=0) return false;
      return today_count>=max_trades;
   }

   // loss_magnitude is expected as a non-negative number (the caller
   // converts a signed realized P&L into a loss magnitude before calling
   // this). A non-positive max_loss_amount disables this check entirely.
   static bool DailyLossLimitReached(const double loss_magnitude,const double max_loss_amount)
   {
      if(max_loss_amount<=0.0) return false;
      return loss_magnitude>=max_loss_amount;
   }
};

// Live wrapper: checks the kill switch, then queries today's deal history
// for this symbol+magic via HistorySelect, counting opening deals and
// summing realized P&L, delegating both comparisons to the policy class.
// A HistorySelect failure is treated as a breached limit, not skipped --
// "never assume a missing calculation means it's safe" applies here
// exactly as it has everywhere else in this series.
class CMSZZAccountSafeguardGuard
{
private:
   datetime StartOfToday() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      dt.hour=0; dt.min=0; dt.sec=0;
      return StructToTime(dt);
   }

public:
   bool CheckSafeguards(const string symbol,const long magic,
                         const int max_trades,const double max_daily_loss_amount,
                         const bool kill_switch_engaged,string &reason)
   {
      if(kill_switch_engaged)
      {
         reason="kill switch engaged";
         return false;
      }

      datetime from=StartOfToday();
      datetime to=TimeCurrent();
      if(!HistorySelect(from,to))
      {
         reason="failed to query today's trade history";
         return false;
      }

      int today_count=0;
      double realized_pnl=0.0;
      int deal_total=HistoryDealsTotal();
      for(int i=0;i<deal_total;i++)
      {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol || HistoryDealGetInteger(ticket,DEAL_MAGIC)!=magic) continue;

         if(HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN) today_count++;
         realized_pnl+=HistoryDealGetDouble(ticket,DEAL_PROFIT)
                       +HistoryDealGetDouble(ticket,DEAL_SWAP)
                       +HistoryDealGetDouble(ticket,DEAL_COMMISSION);
      }

      if(CMSZZAccountSafeguardPolicy::TradeCountLimitReached(today_count,max_trades))
      {
         reason=StringFormat("daily trade-count limit reached: %d/%d",today_count,max_trades);
         return false;
      }

      double loss_magnitude=MathMax(0.0,-realized_pnl);
      if(CMSZZAccountSafeguardPolicy::DailyLossLimitReached(loss_magnitude,max_daily_loss_amount))
      {
         reason=StringFormat("daily loss limit reached: %.2f/%.2f",loss_magnitude,max_daily_loss_amount);
         return false;
      }

      reason="";
      return true;
   }
};

#endif
