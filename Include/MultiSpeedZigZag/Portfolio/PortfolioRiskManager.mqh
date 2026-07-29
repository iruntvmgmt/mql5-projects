#ifndef __MSZZ_PORTFOLIO_RISK_MANAGER_MQH__
#define __MSZZ_PORTFOLIO_RISK_MANAGER_MQH__

#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>

struct MSZZPortfolioRiskConfig
{
   double max_total_initial_risk_pct;
   double max_risk_per_book_pct;
   double max_risk_per_family_pct;
   double max_same_direction_risk_pct;
   double max_opposing_direction_risk_pct;
   int    max_logical_books;
   int    max_books_per_strategy;
   int    max_physical_positions;
   double daily_loss_cap_pct;
   double drawdown_cap_pct;
   double symbol_exposure_cap_lots;
   bool   allow_opposing_books;
   bool   allow_same_direction_stacking;
};

struct MSZZPortfolioRiskSnapshot
{
   bool                 valid;
   int                  open_books;
   int                  physical_positions;
   double               total_initial_risk_pct;
   double               long_risk_pct;
   double               short_risk_pct;
   double               gross_volume;
   double               net_volume;
   double               realized_daily_loss_pct;
   double               portfolio_drawdown_pct;
   string               reason;
};

class CMSZZPortfolioRiskManager
{
private:
   MSZZPortfolioRiskConfig m_config;
   bool                    m_configured;

public:
   CMSZZPortfolioRiskManager(void)
   {
      ZeroMemory(m_config);
      m_configured=false;
   }

   bool Configure(const MSZZPortfolioRiskConfig &config,string &reason)
   {
      reason="";
      if(config.max_total_initial_risk_pct<=0.0 ||
         config.max_risk_per_book_pct<=0.0 ||
         config.max_risk_per_family_pct<=0.0 ||
         config.max_same_direction_risk_pct<=0.0 ||
         config.max_opposing_direction_risk_pct<=0.0 ||
         config.max_logical_books<1 || config.max_books_per_strategy<1 ||
         config.max_physical_positions<1)
      { reason="portfolio risk limits must be positive"; return false; }
      if(config.max_risk_per_book_pct>config.max_total_initial_risk_pct)
      { reason="per-book risk exceeds total risk"; return false; }
      m_config=config;
      m_configured=true;
      return true;
   }

   MSZZPortfolioRiskConfig Config() const { return m_config; }

   bool BuildSnapshot(const MSZZStrategyBookState &books[],const int count,
                      const int physical_positions,
                      const double realized_daily_loss_pct,
                      const double portfolio_drawdown_pct,
                      MSZZPortfolioRiskSnapshot &snapshot) const
   {
      ZeroMemory(snapshot);
      if(!m_configured || count<0 || count>ArraySize(books))
      { snapshot.reason="risk manager unconfigured or book count invalid"; return false; }
      for(int i=0;i<count;i++)
      {
         if(!books[i].valid) { snapshot.reason=StringFormat("invalid book index=%d",i); return false; }
         if(!books[i].position_open) continue;
         snapshot.open_books++;
         snapshot.total_initial_risk_pct+=books[i].allocated_risk_pct;
         snapshot.gross_volume+=MathAbs(books[i].logical_volume);
         if(books[i].direction==MSZZ_DIR_LONG)
         {
            snapshot.long_risk_pct+=books[i].allocated_risk_pct;
            snapshot.net_volume+=books[i].logical_volume;
         }
         else if(books[i].direction==MSZZ_DIR_SHORT)
         {
            snapshot.short_risk_pct+=books[i].allocated_risk_pct;
            snapshot.net_volume-=books[i].logical_volume;
         }
      }
      snapshot.physical_positions=physical_positions;
      snapshot.realized_daily_loss_pct=realized_daily_loss_pct;
      snapshot.portfolio_drawdown_pct=portfolio_drawdown_pct;
      snapshot.valid=true;
      return true;
   }

   bool ApproveOpen(const MSZZPortfolioRiskSnapshot &snapshot,
                    const MSZZStrategyBookState &books[],const int count,
                    const ENUM_MSZZ_STRATEGY_ID strategy_id,
                    const ENUM_MSZZ_STRATEGY_FAMILY family_id,
                    const ENUM_MSZZ_DIRECTION direction,
                    const double requested_risk_pct,const double requested_volume,
                    string &reason) const
   {
      reason="";
      if(!m_configured || !snapshot.valid) { reason="risk state invalid"; return false; }
      if(count<0 || count>ArraySize(books))
      { reason="book count invalid"; return false; }
      if(direction!=MSZZ_DIR_LONG && direction!=MSZZ_DIR_SHORT)
      { reason="requested direction invalid"; return false; }
      if(strategy_id==MSZZ_STRAT_NONE || family_id==MSZZ_FAMILY_NONE)
      { reason="requested strategy or family invalid"; return false; }
      if(requested_volume<=0.0)
      { reason="requested volume invalid"; return false; }
      if(requested_risk_pct<=0.0 || requested_risk_pct>m_config.max_risk_per_book_pct)
      { reason="requested book risk exceeds limit"; return false; }
      if(snapshot.open_books>=m_config.max_logical_books)
      { reason="maximum logical books reached"; return false; }
      if(snapshot.physical_positions>=m_config.max_physical_positions)
      { reason="maximum physical positions reached"; return false; }
      if(snapshot.total_initial_risk_pct+requested_risk_pct>
         m_config.max_total_initial_risk_pct+1e-12)
      { reason="maximum total initial risk exceeded"; return false; }
      if(snapshot.realized_daily_loss_pct>=m_config.daily_loss_cap_pct &&
         m_config.daily_loss_cap_pct>0.0)
      { reason="daily loss cap active"; return false; }
      if(snapshot.portfolio_drawdown_pct>=m_config.drawdown_cap_pct &&
         m_config.drawdown_cap_pct>0.0)
      { reason="portfolio drawdown cap active"; return false; }
      if(m_config.symbol_exposure_cap_lots>0.0 &&
         snapshot.gross_volume+requested_volume>m_config.symbol_exposure_cap_lots+1e-12)
      { reason="symbol exposure cap exceeded"; return false; }
      double same_direction_risk=(direction==MSZZ_DIR_LONG ?
                                  snapshot.long_risk_pct : snapshot.short_risk_pct);
      double opposing_direction_risk=(direction==MSZZ_DIR_LONG ?
                                      snapshot.short_risk_pct : snapshot.long_risk_pct);
      if(same_direction_risk+requested_risk_pct>
         m_config.max_same_direction_risk_pct+1e-12)
      { reason="maximum same-direction risk exceeded"; return false; }
      if(opposing_direction_risk>0.0 &&
         opposing_direction_risk+requested_risk_pct>
         m_config.max_opposing_direction_risk_pct+1e-12)
      { reason="maximum opposing-direction exposure exceeded"; return false; }

      int strategy_books=0;
      double family_risk=0.0;
      bool same_direction=false,opposing_direction=false;
      for(int i=0;i<count;i++)
      {
         if(!books[i].valid || !books[i].position_open) continue;
         if(books[i].strategy_id==strategy_id) strategy_books++;
         if(books[i].family_id==family_id) family_risk+=books[i].allocated_risk_pct;
         if(books[i].direction==direction) same_direction=true;
         else opposing_direction=true;
      }
      if(strategy_books>=m_config.max_books_per_strategy)
      { reason="maximum books per strategy reached"; return false; }
      if(family_risk+requested_risk_pct>m_config.max_risk_per_family_pct+1e-12)
      { reason="maximum family risk exceeded"; return false; }
      if(same_direction && !m_config.allow_same_direction_stacking)
      { reason="same-direction stacking disabled"; return false; }
      if(opposing_direction && !m_config.allow_opposing_books)
      { reason="opposing books disabled"; return false; }
      return true;
   }
};

#endif
