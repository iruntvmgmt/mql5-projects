#ifndef __MSZZ_BOOK_EXIT_MANAGER_MQH__
#define __MSZZ_BOOK_EXIT_MANAGER_MQH__

// D028 Stage 5: per-book exit-management decisions (SR0-SR5). Pure,
// deterministic, no-MT5-API where possible -- reuses D026's already-tested
// CMSZZResearchTrailPolicy primitives (favorable-R, monotonic tightening,
// confirmed-swing trail candidates) rather than duplicating them, exactly
// as the D028 handoff instructs ("No exit variation may alter... signal
// timing... clustering... canonical costs/execution" -- these functions
// touch only stop/target/volume decisions for an already-open position).
// Every threshold below is frozen in DECISION_LOG.md D028 Stage 5 BEFORE
// any SR1-SR5 result is inspected, per the anti-overfitting rules. Callers
// (the EA) are responsible for actually invoking PositionModify/
// PositionClosePartial and only then persisting the returned decision via
// CMSZZStrategyBook::UpdateExitManagementState().

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>
#include <MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh>

// D028 Stage 5 frozen constants -- see DECISION_LOG.md D028 Stage 5 for the
// reasoning behind each, recorded before any SRx backtest ran.
#define MSZZ_SR_BREAKEVEN_ACTIVATION_R   1.0
#define MSZZ_SR_STRUCTURE_ACTIVATION_R   1.0
#define MSZZ_SR_PARTIAL_ACTIVATION_R     1.0
#define MSZZ_SR_PARTIAL_FRACTION         0.5
#define MSZZ_SR_TIME_STOP_THRESHOLD_R    0.5
#define MSZZ_SR_TIME_STOP_BARS           48 // 4 hours of M5 bars -- see DECISION_LOG.md D028 Stage 5

struct MSZZBookExitDecision
{
   bool   modify_stop;
   double new_stop;
   bool   partial_close;
   double partial_fraction;
   bool   remove_target;   // SR4 only: remainder rides with no fixed target
   bool   force_close;     // SR5 only
   string reason;
};

class CMSZZBookExitManager
{
public:
   static double FavorableR(const ENUM_MSZZ_DIRECTION dir,const double entry,const double risk,
                             const double bar_high,const double bar_low)
   {
      return CMSZZResearchTrailPolicy::FavorableR(dir,entry,risk,bar_high,bar_low);
   }

   // One-shot activation test shared by breakeven (SR1) and the partial
   // triggers (SR3/SR4): fires exactly once, the first bar fav_r reaches
   // activation_r, never again for this position.
   static bool CrossesActivation(const double fav_r,const bool already_done,const double activation_r)
   {
      if(already_done) return false;
      return fav_r>=activation_r;
   }

   // SR1: move stop to exactly entry (no cost offset -- the D028 handoff's
   // own wording is "move stop to entry", not "entry plus costs", unlike
   // this project's earlier D026 breakeven design; followed literally here
   // rather than silently importing D026's convention).
   static double BreakevenStop(const double entry)
   {
      return entry;
   }

   // SR2 (full position) / SR4 (remainder after partial): trail behind the
   // latest confirmed Fast swing, monotonic tightening only, broker-
   // distance-valid only. Returns false (no update) if the candidate is
   // stale/wrong-side (reuses D024's Bug-1 guard verbatim via
   // SwingTrailCandidate) or not strictly tighter than the current stop.
   static bool StructuralTrailCandidate(const ENUM_MSZZ_DIRECTION dir,const double current_close,
                                        const MSZZSpeedSnapshot &fast,const double effective_stop,
                                        const double market_price,const double min_distance,
                                        double &new_stop)
   {
      double candidate;
      bool valid=CMSZZResearchTrailPolicy::SwingTrailCandidate(dir,current_close,
                    (dir==MSZZ_DIR_LONG ? fast.last_low.valid : fast.last_high.valid),
                    (dir==MSZZ_DIR_LONG ? fast.last_low.price : fast.last_high.price),
                    candidate);
      if(!valid) return false;
      double tightened;
      if(!CMSZZResearchTrailPolicy::ResolveTightening(dir,effective_stop,candidate,market_price,min_distance,tightened))
         return false;
      new_stop=tightened;
      return true;
   }

   // SR5: force-close if, after N closed bars since entry, the position has
   // never yet reached the favorable-R threshold. Once the threshold has
   // been reached even once (tracked by the caller's own max_favorable_r,
   // not the current bar's fav_r), the time stop never applies again for
   // this position -- "If +0.5R has been reached, retain canonical 2R
   // management," per the frozen SR5 definition.
   static bool ShouldTimeStop(const int bars_since_entry,const double max_favorable_r_so_far)
   {
      if(max_favorable_r_so_far>=MSZZ_SR_TIME_STOP_THRESHOLD_R) return false;
      return bars_since_entry>=MSZZ_SR_TIME_STOP_BARS;
   }

   // Central dispatcher: given the book's exit policy and current state,
   // returns the single decision to apply this bar (a book can only take
   // one exit-management action per bar -- the same "no simultaneous
   // conflicting stop moves" discipline D026 followed).
   static bool Evaluate(const ENUM_MSZZ_SWEEP_EXIT_POLICY policy,
                         const MSZZStrategyBookState &book,
                         const MqlRates &bar,
                         const MSZZSpeedSnapshot &fast,
                         const double market_price,
                         const double min_distance,
                         const int bars_since_entry,
                         const double fav_r,
                         MSZZBookExitDecision &decision)
   {
      ZeroMemory(decision);
      decision.reason="no action";
      if(policy==MSZZ_SWEEP_EXIT_SR0_FIXED2R) return false;

      double risk=book.initial_risk_price;
      if(risk<=0.0) return false;

      if(policy==MSZZ_SWEEP_EXIT_SR1_BREAKEVEN)
      {
         if(!CrossesActivation(fav_r,book.breakeven_activated,MSZZ_SR_BREAKEVEN_ACTIVATION_R)) return false;
         double be=BreakevenStop(book.entry_price);
         double tightened;
         if(!CMSZZResearchTrailPolicy::ResolveTightening(book.direction,book.effective_stop,be,
                                                          market_price,min_distance,tightened))
            return false;
         decision.modify_stop=true; decision.new_stop=tightened; decision.reason="SR1 breakeven activated";
         return true;
      }

      if(policy==MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL)
      {
         if(fav_r<MSZZ_SR_STRUCTURE_ACTIVATION_R) return false;
         double new_stop;
         if(!StructuralTrailCandidate(book.direction,bar.close,fast,book.effective_stop,
                                      market_price,min_distance,new_stop))
            return false;
         decision.modify_stop=true; decision.new_stop=new_stop; decision.reason="SR2 structural trail";
         return true;
      }

      if(policy==MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED)
      {
         if(CrossesActivation(fav_r,book.partial_close_done,MSZZ_SR_PARTIAL_ACTIVATION_R))
         {
            decision.partial_close=true; decision.partial_fraction=MSZZ_SR_PARTIAL_FRACTION;
            decision.modify_stop=true; decision.new_stop=BreakevenStop(book.entry_price);
            decision.reason="SR3 partial 50% + breakeven remainder";
            return true;
         }
         return false;
      }

      if(policy==MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER)
      {
         if(!book.partial_close_done)
         {
            if(CrossesActivation(fav_r,false,MSZZ_SR_PARTIAL_ACTIVATION_R))
            {
               decision.partial_close=true; decision.partial_fraction=MSZZ_SR_PARTIAL_FRACTION;
               decision.modify_stop=true; decision.new_stop=BreakevenStop(book.entry_price);
               decision.remove_target=true;
               decision.reason="SR4 partial 50% + breakeven remainder, target removed for runner";
               return true;
            }
            return false;
         }
         // remainder already breakeven-protected and uncapped -- trail it
         double new_stop;
         if(!StructuralTrailCandidate(book.direction,bar.close,fast,book.effective_stop,
                                      market_price,min_distance,new_stop))
            return false;
         decision.modify_stop=true; decision.new_stop=new_stop; decision.reason="SR4 runner structural trail";
         return true;
      }

      if(policy==MSZZ_SWEEP_EXIT_SR5_TIME_STOP)
      {
         if(ShouldTimeStop(bars_since_entry,book.max_favorable_r))
         {
            decision.force_close=true; decision.reason="SR5 time stop -- never reached +0.5R within window";
            return true;
         }
         return false;
      }

      return false;
   }
};

#endif
