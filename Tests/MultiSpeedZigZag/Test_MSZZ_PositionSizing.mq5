//+------------------------------------------------------------------+
//| Test_MSZZ_PositionSizing.mq5                                     |
//| Covers DECISION_LOG.md D029 Phase 1 requirements (deterministic  |
//| sizing core + integration with the existing, unmodified          |
//| CMSZZPortfolioRiskManager).                                      |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Portfolio/PositionSizing.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioRiskManager.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void AssertNear(const double a,const double b,const double tol,const string message)
{
   AssertTrue(MathAbs(a-b)<=tol,StringFormat("%s (a=%.8f b=%.8f tol=%.8f)",message,a,b,tol));
}

// XAUUSD-like canonical metadata (matches D029 Phase 0's captured values).
#define TICK_SIZE 0.01
#define TICK_VALUE 1.00
#define VOL_MIN 0.01
#define VOL_STEP 0.01
#define VOL_MAX 100.00

//--- Basic sizing ---------------------------------------------------

void TestLongShortSymmetry()
{
   MSZZSizingResult r_long,r_short;
   bool ok_long=CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
                   TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r_long);
   bool ok_short=CMSZZPositionSizing::Calculate(100000.0,0.25,1990.0,2000.0,
                   TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r_short);
   AssertTrue(ok_long && ok_short,"long and short sizing both succeed for a 10-point stop");
   AssertNear(r_long.normalized_volume,r_short.normalized_volume,1e-9,
              "long and short produce identical normalized volume for the same |entry-stop|");
   AssertNear(r_long.stop_distance_points,r_short.stop_distance_points,1e-9,
              "long and short produce identical stop_distance_points (MathAbs symmetry)");
}

void TestExactStopDistanceCalculation()
{
   MSZZSizingResult r;
   CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertNear(r.stop_distance_points,10.0,1e-9,"stop distance is exactly |2000-1990|=10");
}

void TestCorrectTickValueUse()
{
   MSZZSizingResult r_tv1,r_tv2;
   CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
      TICK_SIZE,1.0,VOL_MIN,VOL_STEP,VOL_MAX,r_tv1);
   CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
      TICK_SIZE,2.0,VOL_MIN,VOL_STEP,VOL_MAX,r_tv2);
   AssertNear(r_tv1.loss_per_lot,1000.0,1e-6,"loss_per_lot=(10/0.01)*1.00=1000 for tick_value=1.00");
   AssertNear(r_tv2.loss_per_lot,2000.0,1e-6,"doubling tick_value doubles loss_per_lot (2000)");
   AssertTrue(r_tv2.normalized_volume<r_tv1.normalized_volume,
              "doubling tick_value strictly reduces normalized volume for the same requested risk");
}

void TestCorrectPercentToMoneyConversion()
{
   MSZZSizingResult r;
   CMSZZPositionSizing::Calculate(50000.0,1.0,2000.0,1990.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertNear(r.requested_risk_money,500.0,1e-6,"1.0% of 50000 equity = 500 requested risk money");
}

void TestNormalizationDown()
{
   // stop_distance=27 -> loss_per_lot=2700; risk_money=250 -> raw=0.0925925...
   MSZZSizingResult r;
   bool ok=CMSZZPositionSizing::Calculate(100000.0,0.25,2027.0,2000.0,
              TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertTrue(ok,"non-exact-step raw volume still produces a valid (rounded down) sizing result");
   AssertNear(r.raw_volume,0.0925925926,0.0001,"sanity: raw_volume = 250/2700 = 0.0925925926");
   AssertTrue(r.normalized_volume<r.raw_volume,
              "normalized volume is strictly less than raw volume when raw is not an exact step multiple");
   AssertNear(r.normalized_volume,0.09,1e-9,"0.0925925... normalizes DOWN to 0.09, not up to 0.10");
}

void TestNoNormalizationUp()
{
   // Exhaustive-ish sweep: normalized volume must never exceed raw volume.
   double stop_distances[5]={3.0,7.0,13.0,29.0,41.0};
   for(int i=0;i<5;i++)
   {
      MSZZSizingResult r;
      CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0+stop_distances[i],2000.0,
         TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
      AssertTrue(r.normalized_volume<=r.raw_volume+1e-9,
                 StringFormat("normalized volume never exceeds raw volume (stop_distance=%.1f)",stop_distances[i]));
   }
}

void TestMinimumVolumeRejection()
{
   // Tiny equity + huge stop distance -> raw volume far below 0.01.
   MSZZSizingResult r;
   bool ok=CMSZZPositionSizing::Calculate(1000.0,0.25,3000.0,2000.0,
              TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertTrue(!ok,"a raw volume far below the broker minimum is rejected, not silently floored to zero");
   AssertTrue(!r.minimum_volume_ok,"minimum_volume_ok is false on rejection");
   AssertTrue(r.sizing_result==MSZZ_SIZING_REJECTED,"sizing_result is MSZZ_SIZING_REJECTED");
   AssertTrue(StringFind(r.reject_reason,"minimum")>=0,
              "reject_reason names the minimum-volume cause: "+r.reject_reason);
}

void TestMinimumVolumeNeverSilentlyForcedUp()
{
   // A case that floors to exactly zero volume (well below one full step)
   // must reject, never silently substitute the broker minimum lot (which
   // would exceed the requested risk).
   MSZZSizingResult r;
   bool ok=CMSZZPositionSizing::Calculate(100.0,0.25,3000.0,1000.0,
              TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertTrue(!ok,"a near-zero raw volume case is rejected");
   AssertNear(r.normalized_volume,0.0,1e-9,
              "rejected sizing reports normalized_volume=0, never a silently-substituted minimum lot");
}

void TestInvalidMetadataRejection()
{
   MSZZSizingResult r1,r2,r3,r4;
   AssertTrue(!CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
                 0.0,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r1),
              "zero tick_size is rejected");
   AssertTrue(!CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
                 TICK_SIZE,0.0,VOL_MIN,VOL_STEP,VOL_MAX,r2),
              "zero tick_value is rejected");
   AssertTrue(!CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
                 TICK_SIZE,TICK_VALUE,0.0,VOL_STEP,VOL_MAX,r3),
              "zero volume_min is rejected");
   AssertTrue(!CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,1990.0,
                 TICK_SIZE,TICK_VALUE,VOL_MIN,0.0,VOL_MAX,r4),
              "zero volume_step is rejected");
}

void TestZeroStopDistanceRejection()
{
   MSZZSizingResult r;
   bool ok=CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0,2000.0,
              TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
   AssertTrue(!ok,"entry price equal to stop price (zero stop distance) is rejected");
   AssertTrue(StringFind(r.reject_reason,"stop distance")>=0,
              "reject_reason names the zero-stop-distance cause: "+r.reject_reason);
}

void TestActualRiskNeverExceedsRequested()
{
   double stop_distances[6]={1.0,5.5,10.0,17.3,50.0,99.9};
   for(int i=0;i<6;i++)
   {
      MSZZSizingResult r;
      bool ok=CMSZZPositionSizing::Calculate(100000.0,0.25,2000.0+stop_distances[i],2000.0,
                 TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r);
      if(ok)
         AssertTrue(r.actual_risk_money<=r.requested_risk_money+1e-6,
                    StringFormat("actual risk money never exceeds requested (stop_distance=%.1f, actual=%.4f requested=%.4f)",
                                 stop_distances[i],r.actual_risk_money,r.requested_risk_money));
   }
}

void TestInvalidEquityOrRiskPercentRejection()
{
   MSZZSizingResult r1,r2;
   AssertTrue(!CMSZZPositionSizing::Calculate(0.0,0.25,2000.0,1990.0,
                 TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r1),
              "zero equity is rejected");
   AssertTrue(!CMSZZPositionSizing::Calculate(100000.0,0.0,2000.0,1990.0,
                 TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r2),
              "zero risk percent is rejected");
}

void TestVolumeMaxClamp()
{
   // Enormous equity + tiny stop distance would otherwise produce a raw
   // volume far above the broker maximum.
   MSZZSizingResult r;
   bool ok=CMSZZPositionSizing::Calculate(100000000.0,0.25,2000.10,2000.0,
              TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,10.0,r);
   AssertTrue(ok,"an oversized raw volume clamps to volume_max rather than rejecting");
   AssertNear(r.normalized_volume,10.0,1e-9,"normalized volume clamps exactly to volume_max=10.0");
}

void TestPartialCapableFlag()
{
   MSZZSizingResult r_capable,r_not_capable;
   // stop_distance=10 -> loss_per_lot=1000; risk_money=250 -> raw=0.25 (>=0.02, partial-capable)
   CMSZZPositionSizing::Calculate(100000.0,0.25,2010.0,2000.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r_capable);
   AssertTrue(r_capable.partial_capable,"normalized_volume=0.25 is partial-capable (>=0.02)");
   // stop_distance=150 -> loss_per_lot=15000 -> raw=250/15000=0.01666...,
   // normalizes DOWN to exactly 0.01 (not partial-capable)
   CMSZZPositionSizing::Calculate(100000.0,0.25,2150.0,2000.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,r_not_capable);
   AssertNear(r_not_capable.normalized_volume,0.01,1e-9,"sanity: this case normalizes to exactly 0.01");
   AssertTrue(!r_not_capable.partial_capable,"normalized_volume=0.01 is NOT partial-capable (<0.02)");
}

//--- Portfolio risk integration (existing, unmodified CMSZZPortfolioRiskManager) ---

MSZZStrategyBookState MakeBook(const long book_id,const ENUM_MSZZ_STRATEGY_ID sid,
                               const ENUM_MSZZ_STRATEGY_FAMILY fam,const bool open,
                               const ENUM_MSZZ_DIRECTION dir,const double risk_pct)
{
   MSZZStrategyBookState b; ZeroMemory(b);
   b.valid=true; b.enabled=true; b.book_id=book_id;
   b.strategy_id=sid; b.family_id=fam;
   b.status=(open?MSZZ_BOOK_OPEN:MSZZ_BOOK_FLAT);
   b.position_open=open; b.direction=dir; b.allocated_risk_pct=risk_pct;
   b.logical_volume=0.01;
   return b;
}

CMSZZPortfolioRiskManager MakeConfiguredManager()
{
   CMSZZPortfolioRiskManager mgr;
   MSZZPortfolioRiskConfig cfg; ZeroMemory(cfg);
   cfg.max_total_initial_risk_pct=0.50;
   cfg.max_risk_per_book_pct=0.25;
   cfg.max_risk_per_family_pct=0.50;
   cfg.max_same_direction_risk_pct=0.50;
   cfg.max_opposing_direction_risk_pct=0.50;
   cfg.max_logical_books=2;
   cfg.max_books_per_strategy=1;
   cfg.max_physical_positions=2;
   cfg.allow_opposing_books=true;
   cfg.allow_same_direction_stacking=false;
   string reason;
   mgr.Configure(cfg,reason);
   return mgr;
}

void TestOneBookAtActualRiskApproved()
{
   MSZZSizingResult sizing;
   CMSZZPositionSizing::Calculate(100000.0,0.25,2010.0,2000.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,sizing);
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,1);
   books[0]=MakeBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,false,MSZZ_DIR_LONG,0.0);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,1,0,0.0,0.0,snap);
   string reason;
   bool approved=mgr.ApproveOpen(snap,books,1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,
                                 MSZZ_DIR_LONG,sizing.actual_risk_pct,sizing.normalized_volume,reason);
   AssertTrue(approved,"first book at actual computed risk (~0.25%) is approved: "+reason);
}

void TestSecondBookApprovedUpToCap()
{
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,2);
   books[0]=MakeBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,true,MSZZ_DIR_LONG,0.25);
   books[1]=MakeBook(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,false,MSZZ_DIR_SHORT,0.0);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,2,1,0.0,0.0,snap);
   AssertNear(snap.total_initial_risk_pct,0.25,1e-9,"snapshot reflects the one open book's 0.25% risk");
   string reason;
   bool approved=mgr.ApproveOpen(snap,books,2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,0.25,0.02,reason);
   AssertTrue(approved,"second 0.25% book is approved, bringing total to exactly the 0.50% cap: "+reason);
}

void TestAboveCapRejected()
{
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,2);
   books[0]=MakeBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,true,MSZZ_DIR_LONG,0.25);
   books[1]=MakeBook(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,false,MSZZ_DIR_SHORT,0.0);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,2,1,0.0,0.0,snap);
   string reason;
   // 0.25 (open) + 0.2501 (requested) > 0.50 cap
   bool approved=mgr.ApproveOpen(snap,books,2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,0.2501,0.02,reason);
   AssertTrue(!approved,"any amount pushing total actual risk above 0.50% is rejected");
}

void TestActualNormalizedRiskUsedNotRequested()
{
   // A sizing result whose actual risk under-allocates relative to the flat
   // requested 0.25% (e.g. 0.243% due to volume-step rounding) must be the
   // number that gets summed into the portfolio snapshot -- proving the
   // caller is expected to pass sizing.actual_risk_pct, not a flat assumed
   // value, exactly as D029's wiring in the EA does.
   MSZZSizingResult sizing;
   CMSZZPositionSizing::Calculate(100000.0,0.25,2027.0,2000.0,
      TICK_SIZE,TICK_VALUE,VOL_MIN,VOL_STEP,VOL_MAX,sizing);
   AssertTrue(sizing.actual_risk_pct<0.25,
              StringFormat("this sizing case genuinely under-allocates vs the flat 0.25%% requested (actual=%.4f%%)",
                           sizing.actual_risk_pct));
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,1);
   books[0]=MakeBook(1,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,true,MSZZ_DIR_LONG,sizing.actual_risk_pct);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,1,1,0.0,0.0,snap);
   AssertNear(snap.total_initial_risk_pct,sizing.actual_risk_pct,1e-9,
              "portfolio snapshot sums the ACTUAL under-allocated risk, not the flat 0.25% requested");
}

void TestClosedBookReleasesRisk()
{
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,2);
   books[0]=MakeBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,false,MSZZ_DIR_LONG,0.25);
   books[1]=MakeBook(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,false,MSZZ_DIR_SHORT,0.0);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,2,0,0.0,0.0,snap);
   AssertNear(snap.total_initial_risk_pct,0.0,1e-9,
              "a book marked position_open=false contributes zero risk to the snapshot (closed book releases risk)");
}

void TestOpposingBooksAllowed()
{
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,2);
   books[0]=MakeBook(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_FAMILY_BREAKOUT,true,MSZZ_DIR_LONG,0.25);
   books[1]=MakeBook(2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,false,MSZZ_DIR_SHORT,0.0);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,2,1,0.0,0.0,snap);
   string reason;
   bool approved=mgr.ApproveOpen(snap,books,2,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,0.25,0.02,reason);
   AssertTrue(approved,"an opposing-direction second book is approved when allow_opposing_books=true: "+reason);
}

void TestSameStrategySecondBookRejected()
{
   CMSZZPortfolioRiskManager mgr=MakeConfiguredManager();
   MSZZStrategyBookState books[]; ArrayResize(books,1);
   books[0]=MakeBook(1,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,true,MSZZ_DIR_LONG,0.25);
   MSZZPortfolioRiskSnapshot snap; mgr.BuildSnapshot(books,1,1,0.0,0.0,snap);
   string reason;
   bool approved=mgr.ApproveOpen(snap,books,1,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,
                                 MSZZ_DIR_SHORT,0.10,0.01,reason);
   AssertTrue(!approved,"a second book for the SAME strategy is rejected (max_books_per_strategy=1): "+reason);
}

void OnStart()
{
   TestLongShortSymmetry();
   TestExactStopDistanceCalculation();
   TestCorrectTickValueUse();
   TestCorrectPercentToMoneyConversion();
   TestNormalizationDown();
   TestNoNormalizationUp();
   TestMinimumVolumeRejection();
   TestMinimumVolumeNeverSilentlyForcedUp();
   TestInvalidMetadataRejection();
   TestZeroStopDistanceRejection();
   TestActualRiskNeverExceedsRequested();
   TestInvalidEquityOrRiskPercentRejection();
   TestVolumeMaxClamp();
   TestPartialCapableFlag();

   TestOneBookAtActualRiskApproved();
   TestSecondBookApprovedUpToCap();
   TestAboveCapRejected();
   TestActualNormalizedRiskUsedNotRequested();
   TestClosedBookReleasesRisk();
   TestOpposingBooksAllowed();
   TestSameStrategySecondBookRejected();

   PrintFormat("Test_MSZZ_PositionSizing: failures=%d",g_failures);
}
