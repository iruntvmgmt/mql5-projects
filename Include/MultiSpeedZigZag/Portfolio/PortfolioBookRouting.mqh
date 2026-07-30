#ifndef __MSZZ_PORTFOLIO_BOOK_ROUTING_MQH__
#define __MSZZ_PORTFOLIO_BOOK_ROUTING_MQH__

#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>

class CMSZZPortfolioBookRouting
{
public:
   // D033: added a third single-book option (Session Sweep Reversal)
   // WITHOUT touching the existing two-strategy pair case at all --
   // enabled_count==2 still requires exactly {fastmed, sweep}, unchanged.
   // SSR is standalone-only in D033 (no SSR+fastmed or SSR+sweep pair is
   // supported yet); combining it with P4 is D034's job, not this one.
   static bool IsSupportedSelection(const int enabled_count,
                                    const bool fastmed_enabled,
                                    const bool sweep_enabled,
                                    const bool ssr_enabled=false)
   {
      if(enabled_count==1)
      {
         int on=(fastmed_enabled?1:0)+(sweep_enabled?1:0)+(ssr_enabled?1:0);
         return on==1;
      }
      return enabled_count==2 && fastmed_enabled && sweep_enabled && !ssr_enabled;
   }

   static string ConsumedKey(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                             const string cluster_id)
   {
      if((strategy_id!=MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE &&
          strategy_id!=MSZZ_STRAT_SWEEP_RECLAIM) || cluster_id=="")
         return "";
      return IntegerToString((int)strategy_id)+"|"+cluster_id;
   }

   static bool OwnsPositionTicket(const MSZZStrategyBookState &book,
                                  const ulong ticket)
   {
      return book.valid && book.position_open && ticket>0 &&
             book.broker_position_ticket==ticket;
   }

   static string CloseReason(const bool own_family_close)
   {
      return own_family_close ? "OWN_FAMILY_OPPOSITE" :
                                "BROKER_SL_TP_OR_TEST_END";
   }

   static ENUM_MSZZ_STRATEGY_ID FirstStrategy()
   {
      return MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE;
   }

   static ENUM_MSZZ_STRATEGY_ID SecondStrategy()
   {
      return MSZZ_STRAT_SWEEP_RECLAIM;
   }
};

#endif
