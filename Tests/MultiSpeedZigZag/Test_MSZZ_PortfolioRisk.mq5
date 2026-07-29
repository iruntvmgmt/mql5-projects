#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/PortfolioRiskManager.mqh>

void Check(const bool ok,const string message,int &failures)
{
   if(ok) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

MSZZPortfolioRiskConfig Config()
{
   MSZZPortfolioRiskConfig c; ZeroMemory(c);
   c.max_total_initial_risk_pct=0.50;
   c.max_risk_per_book_pct=0.25;
   c.max_risk_per_family_pct=0.25;
   c.max_same_direction_risk_pct=0.50;
   c.max_opposing_direction_risk_pct=0.50;
   c.max_logical_books=2;
   c.max_books_per_strategy=1;
   c.max_physical_positions=2;
   c.symbol_exposure_cap_lots=0.02;
   c.allow_opposing_books=false;
   c.allow_same_direction_stacking=false;
   return c;
}

MSZZStrategyBookState OpenBook(const long id,const ENUM_MSZZ_STRATEGY_ID strategy,
                               const ENUM_MSZZ_STRATEGY_FAMILY family,
                               const ENUM_MSZZ_DIRECTION direction)
{
   MSZZStrategyBookState b; ZeroMemory(b);
   b.valid=true; b.enabled=true; b.position_open=true; b.status=MSZZ_BOOK_OPEN;
   b.book_id=id; b.strategy_id=strategy; b.family_id=family; b.direction=direction;
   b.allocated_risk_pct=0.25; b.logical_volume=0.01;
   return b;
}

void OnStart()
{
   int failures=0;
   string reason;
   CMSZZPortfolioRiskManager risk;
   MSZZPortfolioRiskConfig config=Config();
   Check(risk.Configure(config,reason),"risk manager configures",failures);
   MSZZStrategyBookState books[];
   ArrayResize(books,0);
   MSZZPortfolioRiskSnapshot snap;
   Check(risk.BuildSnapshot(books,0,0,0.0,0.0,snap),"empty snapshot builds",failures);
   Check(risk.ApproveOpen(snap,books,0,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                          MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_LONG,0.25,0.01,reason),
         "first book approved",failures);

   ArrayResize(books,1);
   books[0]=OpenBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                     MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_LONG);
   Check(risk.BuildSnapshot(books,1,1,0.0,0.0,snap),"open snapshot builds",failures);
   Check(!risk.ApproveOpen(snap,books,1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                           MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_LONG,0.25,0.01,reason) &&
         reason=="maximum books per strategy reached",
         "per-strategy limit rejects deterministically",failures);
   Check(!risk.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_LONG,0.25,0.01,reason) &&
         reason=="same-direction stacking disabled",
         "same-direction stacking rejects",failures);
   Check(!risk.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason) &&
         reason=="opposing books disabled",
         "opposing exposure rejects",failures);

   config.allow_opposing_books=true;
   config.allow_same_direction_stacking=true;
   Check(risk.Configure(config,reason),"stacking policy reconfigures",failures);
   Check(risk.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                          MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason),
         "opposing exposure approves when enabled",failures);
   Check(risk.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                          MSZZ_FAMILY_REVERSAL,MSZZ_DIR_LONG,0.25,0.01,reason),
         "same-direction book approves when enabled",failures);
   Check(!risk.ApproveOpen(snap,books,1,MSZZ_STRAT_FAST_BREAKOUT,
                           MSZZ_FAMILY_BREAKOUT,MSZZ_DIR_SHORT,0.25,0.01,reason) &&
         reason=="maximum family risk exceeded",
         "per-family risk rejects deterministically",failures);
   Check(!risk.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.26,0.01,reason),
         "per-book risk excess rejects",failures);
   Check(!risk.ApproveOpen(snap,books,2,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason) &&
         reason=="book count invalid","oversized book count fails closed",failures);
   MSZZPortfolioRiskSnapshot physical=snap;
   physical.physical_positions=2;
   Check(!risk.ApproveOpen(physical,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason) &&
         reason=="maximum physical positions reached",
         "physical-position cap rejects",failures);
   MSZZPortfolioRiskSnapshot full=snap;
   full.open_books=2;
   full.total_initial_risk_pct=0.50;
   Check(!risk.ApproveOpen(full,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason) &&
         reason=="maximum logical books reached",
         "maximum logical-book cap rejects",failures);
   MSZZPortfolioRiskSnapshot invalid=snap; invalid.valid=false;
   Check(!risk.ApproveOpen(invalid,books,1,MSZZ_STRAT_SWEEP_RECLAIM,
                           MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,0.25,0.01,reason),
         "invalid snapshot fails closed",failures);

   PrintFormat("TEST_SUMMARY tests=15 failures=%d",failures);
}
