#ifndef __MSZZ_PORTFOLIO_JOURNALS_MQH__
#define __MSZZ_PORTFOLIO_JOURNALS_MQH__

#include <MultiSpeedZigZag/Portfolio/ExecutionCoordinator.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioRiskManager.mqh>

class CMSZZPortfolioJournals
{
private:
   bool m_enabled;

   int OpenAppend(const string file,const string header)
   {
      if(!m_enabled) return INVALID_HANDLE;
      int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE) return INVALID_HANDLE;
      if(FileSize(h)==0) FileWriteString(h,header+"\r\n");
      FileSeek(h,0,SEEK_END);
      return h;
   }

public:
   CMSZZPortfolioJournals(void) { m_enabled=false; }
   void Configure(const bool enabled) { m_enabled=enabled; }

   bool JournalBook(const datetime time,const MSZZStrategyBookState &book,
                    const string action,const string exit_reason,
                    const ENUM_MSZZ_ACCOUNT_MODE account_mode,
                    const string regime_snapshot_id)
   {
      int h=OpenAppend("MSZZ_StrategyBookJournal.csv",
         "time;book_id;strategy_id;family_id;magic;logical_position_id;"
         "broker_position_ticket;account_margin_mode;direction;logical_volume;"
         "entry_price;stop_price;target_price;allocated_risk_pct;action;"
         "exit_policy;exit_reason;regime_snapshot_id");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),book.book_id,
                (int)book.strategy_id,(int)book.family_id,book.magic,
                book.logical_position_id,book.broker_position_ticket,
                CMSZZPositionOwnership::AccountModeText(account_mode),
                MSZZDirectionText(book.direction),book.logical_volume,
                book.entry_price,book.stop_price,book.target_price,
                book.allocated_risk_pct,action,book.exit_config.policy_id,
                exit_reason,regime_snapshot_id);
      FileFlush(h); FileClose(h);
      return true;
   }

   bool JournalRisk(const datetime time,const long book_id,const string action,
                    const bool approved,const string reason,
                    const MSZZPortfolioRiskSnapshot &before,
                    const double requested_risk_pct)
   {
      int h=OpenAppend("MSZZ_PortfolioRiskJournal.csv",
         "time;book_id;action;approved;reason;open_books;"
         "portfolio_open_risk_before;requested_risk_pct;"
         "portfolio_open_risk_after;long_risk_pct;short_risk_pct;"
         "gross_volume;net_volume");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),book_id,action,
                (approved?"true":"false"),reason,before.open_books,
                before.total_initial_risk_pct,requested_risk_pct,
                before.total_initial_risk_pct+(approved?requested_risk_pct:0.0),
                before.long_risk_pct,before.short_risk_pct,
                before.gross_volume,before.net_volume);
      FileFlush(h); FileClose(h);
      return true;
   }

   bool JournalAllocation(const datetime time,const MSZZExecutionPlan &plan,
                          const ulong broker_deal_ticket,const string action,
                          const string cross_family_action,const double execution_cost,
                          const double realized_r)
   {
      int h=OpenAppend("MSZZ_ExecutionAllocationJournal.csv",
         "time;book_id;magic;logical_position_id;broker_position_ticket;"
         "broker_deal_ticket;account_margin_mode;direction;logical_volume;"
         "broker_net_volume_before;broker_net_volume_after;stop_price;"
         "target_price;action;cross_family_action;execution_cost;realized_r");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),plan.book_id,plan.magic,
                plan.logical_position_id,plan.owned_ticket,broker_deal_ticket,
                CMSZZPositionOwnership::AccountModeText(plan.account_mode),
                MSZZDirectionText(plan.direction),plan.logical_volume,
                plan.broker_net_volume_before,plan.broker_net_volume_after,
                plan.stop_price,plan.target_price,action,cross_family_action,
                execution_cost,realized_r);
      FileFlush(h); FileClose(h);
      return true;
   }

   bool EnsureTradeAnalyticsHeader()
   {
      int h=OpenAppend("MSZZ_PortfolioTradeAnalytics.csv",
         "logical_position_id;book_id;strategy_id;family_id;magic;direction;"
         "entry_time;exit_time;entry_price;exit_price;logical_volume;"
         "initial_risk_price;execution_cost;realized_r;exit_policy;"
         "exit_reason;regime_snapshot_id");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileClose(h);
      return true;
   }

   bool JournalTrade(const MSZZStrategyBookState &book,
                     const datetime exit_time,const double exit_price,
                     const double execution_cost,const double realized_r,
                     const string exit_reason,const string regime_snapshot_id)
   {
      int h=OpenAppend("MSZZ_PortfolioTradeAnalytics.csv",
         "logical_position_id;book_id;strategy_id;family_id;magic;direction;"
         "entry_time;exit_time;entry_price;exit_price;logical_volume;"
         "initial_risk_price;execution_cost;realized_r;exit_policy;"
         "exit_reason;regime_snapshot_id");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,book.logical_position_id,book.book_id,(int)book.strategy_id,
                (int)book.family_id,book.magic,MSZZDirectionText(book.direction),
                TimeToString(book.entry_time,TIME_DATE|TIME_SECONDS),
                TimeToString(exit_time,TIME_DATE|TIME_SECONDS),
                book.entry_price,exit_price,book.logical_volume,
                book.initial_risk_price,execution_cost,realized_r,
                book.exit_config.policy_id,exit_reason,regime_snapshot_id);
      FileFlush(h); FileClose(h);
      return true;
   }
};

#endif
