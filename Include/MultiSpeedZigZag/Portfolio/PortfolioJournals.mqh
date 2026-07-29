#ifndef __MSZZ_PORTFOLIO_JOURNALS_MQH__
#define __MSZZ_PORTFOLIO_JOURNALS_MQH__

#include <MultiSpeedZigZag/Portfolio/ExecutionCoordinator.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioRiskManager.mqh>
#include <MultiSpeedZigZag/Portfolio/PositionSizing.mqh>

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

   // D028 Stage 5: one row per applied (or attempted) exit-management
   // action -- breakeven/trail/partial/time-stop -- across SR1-SR5. Used
   // for Stage 5's activation counts and exit-inventory analysis.
   bool JournalExitManagement(const datetime time,const long book_id,const int policy_id,
                              const string action,const double fav_r,const double old_stop,
                              const double new_stop,const double partial_volume,
                              const bool modify_ok,const string reason)
   {
      int h=OpenAppend("MSZZ_SweepExitManagementJournal.csv",
         "time;book_id;policy_id;action;fav_r;old_stop;new_stop;partial_volume;modify_ok;reason");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),book_id,policy_id,action,
                DoubleToString(fav_r,4),DoubleToString(old_stop,8),DoubleToString(new_stop,8),
                DoubleToString(partial_volume,2),(modify_ok?"true":"false"),reason);
      FileFlush(h); FileClose(h);
      return true;
   }

   // D029 Phase 3: exact partial-close accounting, one row per executed
   // (or attempted) SR3-PCT/SR4-PCT partial close. Complements
   // JournalExitManagement's PARTIAL_CLOSE row (kept unchanged, still
   // fired) with the fields needed for full parent/child volume and
   // weighted-R reconciliation: original volume, requested/normalized/
   // executed partial volume, remaining volume, the actual broker deal
   // ticket and fill price. Partial and remainder realized-R and weighted
   // total R are deliberately computed downstream in the Phase 3 analysis
   // script from this price/volume data plus the already-proven D025
   // volume-weighted blended close price in MSZZ_TradeAnalytics.csv/
   // MSZZ_PortfolioTradeAnalytics.csv, rather than duplicating R-calculation
   // logic in MQL5. See DECISION_LOG.md D029 Phase 3.
   bool JournalPartialClose(const datetime time,const long book_id,const int policy_id,
                            const double original_volume,const double partial_fraction,
                            const double requested_partial_volume,
                            const double normalized_partial_volume,
                            const double executed_partial_volume,
                            const double remaining_volume,
                            const ulong partial_deal_ticket,const double partial_price,
                            const bool modify_ok,const string reason)
   {
      int h=OpenAppend("MSZZ_PartialCloseJournal.csv",
         "time;book_id;policy_id;original_volume;partial_fraction;requested_partial_volume;"
         "normalized_partial_volume;executed_partial_volume;remaining_volume;"
         "partial_deal_ticket;partial_price;modify_ok;reason");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),book_id,policy_id,
                DoubleToString(original_volume,2),DoubleToString(partial_fraction,4),
                DoubleToString(requested_partial_volume,4),
                DoubleToString(normalized_partial_volume,2),
                DoubleToString(executed_partial_volume,2),
                DoubleToString(remaining_volume,2),
                partial_deal_ticket,DoubleToString(partial_price,8),
                (modify_ok?"true":"false"),reason);
      FileFlush(h); FileClose(h);
      return true;
   }

   // D029 Phase 1: one row per position-sizing decision (accepted or
   // rejected) when InpSizingMode=MSZZ_SIZE_PERCENT_EQUITY. `run_id` is
   // deliberately omitted -- this project's established convention is that
   // the output CSV/Report filename itself is the run identifier (see every
   // other journal above), so a redundant per-row run_id column would carry
   // no information not already in the file path. `partial_requested_volume`
   // / `partial_normalized_volume` / `remaining_volume` are always 0.0 here
   // in Phase 1/2 (no partial mechanism exists yet); Phase 3 populates them
   // without needing a schema change. See DECISION_LOG.md D029 Phase 1.
   bool JournalSizing(const datetime time,const string logical_position_id,
                      const ENUM_MSZZ_STRATEGY_ID strategy_id,const long book_id,
                      const long magic,const MSZZSizingResult &sizing,
                      const double partial_requested_volume,
                      const double partial_normalized_volume,
                      const double remaining_volume)
   {
      int h=OpenAppend("MSZZ_SizingJournal.csv",
         "time;logical_position_id;strategy_id;book_id;magic;equity_snapshot;"
         "requested_risk_pct;requested_risk_money;entry_price;stop_price;"
         "stop_distance_points;tick_size;tick_value;raw_volume;normalized_volume;"
         "actual_risk_money;actual_risk_pct;risk_underallocation_pct;partial_capable;"
         "partial_requested_volume;partial_normalized_volume;remaining_volume;"
         "sizing_result;reject_reason");
      if(h==INVALID_HANDLE) return !m_enabled;
      double underallocation_pct=(sizing.requested_risk_pct>0.0) ?
         (sizing.normalization_error/sizing.equity_snapshot*100.0) : 0.0;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),logical_position_id,
                (int)strategy_id,book_id,magic,
                DoubleToString(sizing.equity_snapshot,2),
                DoubleToString(sizing.requested_risk_pct,4),
                DoubleToString(sizing.requested_risk_money,2),
                DoubleToString(sizing.entry_price,8),DoubleToString(sizing.stop_price,8),
                DoubleToString(sizing.stop_distance_points,8),
                DoubleToString(sizing.tick_size,8),DoubleToString(sizing.tick_value,8),
                DoubleToString(sizing.raw_volume,6),DoubleToString(sizing.normalized_volume,2),
                DoubleToString(sizing.actual_risk_money,2),
                DoubleToString(sizing.actual_risk_pct,4),
                DoubleToString(underallocation_pct,4),
                (sizing.partial_capable?"true":"false"),
                DoubleToString(partial_requested_volume,2),
                DoubleToString(partial_normalized_volume,2),
                DoubleToString(remaining_volume,2),
                (sizing.sizing_result==MSZZ_SIZING_OK?"OK":"REJECTED"),
                sizing.reject_reason);
      FileFlush(h); FileClose(h);
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

   // D029 audit remediation, Finding B: one row per broker deal (entry or
   // exit) for a position, so an offline script can independently
   // reconstruct sum(exit volumes)==opening filled volume, the
   // volume-weighted exit price, and price-based R -- without trusting the
   // EA's own in-line computation of the same numbers. Written from
   // exactly the same HistoryDealsTotal()/HistoryDealGetTicket() scan the
   // caller already performs to compute exit_price/realized_r for
   // JournalTrade() above -- this adds a journal row per deal already
   // being read, it does not add a new broker query or change what any
   // function decides to do. See DECISION_LOG.md D029 audit remediation.
   bool JournalDeal(const datetime time,const long book_id,
                    const ENUM_MSZZ_STRATEGY_ID strategy_id,
                    const ulong position_ticket,const ulong deal_ticket,
                    const string entry_type,const double volume,
                    const double price,const double commission,
                    const double swap,const double profit)
   {
      int h=OpenAppend("MSZZ_DealJournal.csv",
         "time;book_id;strategy_id;position_ticket;deal_ticket;entry_type;"
         "volume;price;commission;swap;profit");
      if(h==INVALID_HANDLE) return !m_enabled;
      FileWrite(h,TimeToString(time,TIME_DATE|TIME_SECONDS),book_id,(int)strategy_id,
                position_ticket,deal_ticket,entry_type,volume,price,
                commission,swap,profit);
      FileFlush(h); FileClose(h);
      return true;
   }
};

#endif
