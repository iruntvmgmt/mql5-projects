#property strict
//+------------------------------------------------------------------+
//| ExitSimulatorPolicy.mqh                                           |
//| D021: pure, deterministic exit-model resolution for the Exit-     |
//| Efficiency Study Phase 1. No MT5 API calls -- every input is      |
//| passed in explicitly so this is directly unit-testable against   |
//| hand-built synthetic bar arrays.                                  |
//| D022: fixed a same-bar activation-sequencing bug -- see            |
//| DECISION_LOG.md D022. Breakeven/trail activation now evaluates    |
//| the stop as it stood at bar OPEN before any update, and a newly  |
//| computed stop only becomes active starting the NEXT bar.          |
//+------------------------------------------------------------------+

enum ENUM_MSZZ_EXIT_MODEL
{
   MSZZ_EXIT_FIXED_1R=0,
   MSZZ_EXIT_FIXED_1_5R,
   MSZZ_EXIT_FIXED_2R,
   MSZZ_EXIT_FIXED_3R,
   MSZZ_EXIT_BE_0_5R,
   MSZZ_EXIT_BE_0_75R,
   MSZZ_EXIT_BE_1R,
   MSZZ_EXIT_BE_PLUS_COSTS,
   MSZZ_EXIT_TRAIL_0_5R_AFTER_1R,
   MSZZ_EXIT_TIME_4H,
   MSZZ_EXIT_TIME_8H,
   MSZZ_EXIT_TIME_12H,
   MSZZ_EXIT_TIME_24H,
   MSZZ_EXIT_SESSION_CLOSE,
   MSZZ_EXIT_MODEL_COUNT
};

enum ENUM_MSZZ_AMBIGUITY_MODE
{
   // D022: these are now genuinely different code paths, not one path
   // with which-level-wins flipped -- see SimulateExit().
   MSZZ_AMBIG_PESSIMISTIC=0,
   MSZZ_AMBIG_OPTIMISTIC=1
};

enum ENUM_MSZZ_REPLAY_PRICE_MODE
{
   MSZZ_REPLAY_TICK_RESOLVED=0,
   MSZZ_REPLAY_OHLC_PESSIMISTIC=1,
   MSZZ_REPLAY_OHLC_OPTIMISTIC=2
};

// One bar of the post-entry forward path. Deliberately minimal (not a
// full MqlRates) -- only what exit resolution needs.
struct MSZZExitBar
{
   datetime time;
   double   high;
   double   low;
   double   close;
};

struct MSZZExitParams
{
   ENUM_MSZZ_EXIT_MODEL model;
   double   fixed_r_multiple;   // FIXED_* models: 1.0/1.5/2.0/3.0
   double   be_trigger_r;       // BE_* models: 0.5/0.75/1.0
   double   be_offset_price;    // added past entry in the favorable direction; 0 for exact breakeven,
                                 // >0 (in price units) for BE_PLUS_COSTS
   double   trail_trigger_r;    // TRAIL model: 1.0
   double   trail_distance_r;   // TRAIL model: 0.5 (in R, converted to price via initial_risk)
   long     time_limit_seconds; // TIME_* models
   datetime session_boundary;   // SESSION_CLOSE: precomputed by the caller (entry-time-dependent)
};

struct MSZZExitResult
{
   bool     resolved;
   datetime exit_time;
   double   exit_price;
   string   exit_reason;        // "TP","SL","BE_TRAIL","TIME","SESSION_CLOSE"
   double   final_stop;
   int      number_of_trail_updates;
   bool     ambiguous_bar_used;      // old stop AND target both touched the same bar
   // D022: same-bar sequencing ambiguity -- a bar survived against the
   // old stop and armed/ratcheted a new one, but that same bar's adverse
   // extreme would ALSO have touched the new (not-yet-active) stop. The
   // primary result still defers the new stop to the next bar; this
   // records the alternate immediate-exit bound rather than discarding it.
   bool     sequencing_ambiguous;
   datetime alt_bound_exit_time;
   double   alt_bound_exit_price;
   // D022: excursion truncated at THIS model's own resolved exit, as
   // opposed to the shared reference-horizon MFE/MAE the caller computes
   // separately via ComputeMfeMae() over the full forward window.
   double   mfe_until_exit_r;
   double   mae_until_exit_r;
};

class CMSZZExitSimulatorPolicy
{
public:
   // (price-entry)/risk, sign-correct per direction. direction: +1 long, -1 short.
   static double RMultiple(const double price,const double entry,const double risk,const int direction)
   {
      if(risk<=0.0) return 0.0;
      double raw=(direction>0 ? (price-entry) : (entry-price));
      return raw/risk;
   }

   static double FavorablePrice(const MSZZExitBar &bar,const int direction)
   {
      return (direction>0 ? bar.high : bar.low);
   }

   static double AdversePrice(const MSZZExitBar &bar,const int direction)
   {
      return (direction>0 ? bar.low : bar.high);
   }

   // Model-independent: MFE/MAE over a FIXED reference window (the full
   // bars[] array supplied by the caller), so every exit model applied to
   // the same trade is compared against the identical excursion ceiling --
   // otherwise an early-exiting model would report a smaller "MFE" than a
   // late-exiting one purely as an artifact of its own exit timing.
   static void ComputeMfeMae(const double entry,const double risk,const int direction,
                              const MSZZExitBar &bars[],const int bar_count,
                              double &out_mfe_r,double &out_mae_r,
                              int &out_bars_to_mfe,datetime &out_time_to_mfe)
   {
      out_mfe_r=0.0; out_mae_r=0.0; out_bars_to_mfe=0; out_time_to_mfe=0;
      double best=-1.0e9, worst=1.0e9;
      for(int i=0;i<bar_count;i++)
      {
         double fav_r=RMultiple(FavorablePrice(bars[i],direction),entry,risk,direction);
         double adv_r=RMultiple(AdversePrice(bars[i],direction),entry,risk,direction);
         if(fav_r>best) { best=fav_r; out_bars_to_mfe=i; out_time_to_mfe=bars[i].time; }
         if(adv_r<worst) worst=adv_r;
      }
      if(bar_count<=0) return;
      out_mfe_r=best;
      out_mae_r=worst; // signed: negative means adverse excursion below entry (long) -- caller takes abs if needed
   }

   // Only meaningful (non-null) when the chosen denominator exceeds
   // min_mfe_threshold -- caller treats the bool return as "field is
   // null" when false, never dividing by a near-zero denominator.
   static bool PercentMfeCaptured(const double realized_r,const double mfe_r,
                                   const double min_mfe_threshold,double &out_pct)
   {
      out_pct=0.0;
      if(mfe_r<=min_mfe_threshold) return false;
      out_pct=realized_r/mfe_r;
      return true;
   }

   // Given the stop as it stood at this bar's open and this bar's own
   // favorable extreme, returns the candidate stop after BE/trail
   // activation or ratcheting -- WITHOUT touching whether that candidate
   // gets tested against this same bar (the caller decides that,
   // differently for pessimistic vs optimistic mode). armed is updated
   // in place and persists across bars.
   static double ComputeCandidateStop(const MSZZExitParams &params,const int direction,
                                       const double entry_price,const double initial_risk,
                                       const double stop_at_open,const MSZZExitBar &bar,
                                       bool &armed,int &trail_updates_counter)
   {
      bool is_be=(params.model==MSZZ_EXIT_BE_0_5R || params.model==MSZZ_EXIT_BE_0_75R ||
                   params.model==MSZZ_EXIT_BE_1R || params.model==MSZZ_EXIT_BE_PLUS_COSTS);
      bool is_trail=(params.model==MSZZ_EXIT_TRAIL_0_5R_AFTER_1R);
      double fav_r=RMultiple(FavorablePrice(bar,direction),entry_price,initial_risk,direction);

      if(is_be)
      {
         if(!armed && fav_r>=params.be_trigger_r)
         {
            double be_price = direction>0 ? entry_price+params.be_offset_price
                                           : entry_price-params.be_offset_price;
            armed=true;
            trail_updates_counter++;
            return be_price;
         }
         return stop_at_open;
      }
      if(is_trail)
      {
         if(!armed && fav_r>=params.trail_trigger_r) armed=true;
         if(armed)
         {
            double trail_price = direction>0
               ? FavorablePrice(bar,direction)-params.trail_distance_r*initial_risk
               : FavorablePrice(bar,direction)+params.trail_distance_r*initial_risk;
            bool improves = direction>0 ? (trail_price>stop_at_open) : (trail_price<stop_at_open);
            if(improves) { trail_updates_counter++; return trail_price; }
         }
         return stop_at_open;
      }
      return stop_at_open; // FIXED/TIME/SESSION models never move the stop
   }

   // Core exit resolution. bars[] must start at the first bar AFTER entry
   // (the entry bar itself is not part of the forward path) and be in
   // strictly increasing time order -- the loop only ever reads bars[j]
   // for j<=i at decision time i, so causality is structural, not just
   // asserted. entry_time anchors time-based exits exactly (D022 --
   // previously approximated from bars[0].time).
   static void SimulateExit(const int direction,const double entry_price,
                             const double initial_stop,const double initial_risk,
                             const double original_target,const datetime entry_time,
                             const MSZZExitBar &bars[],const int bar_count,
                             const MSZZExitParams &params,
                             const ENUM_MSZZ_AMBIGUITY_MODE ambiguity,
                             MSZZExitResult &out)
   {
      out.resolved=false; out.exit_time=0; out.exit_price=0.0;
      out.exit_reason="OPEN"; out.final_stop=initial_stop;
      out.number_of_trail_updates=0; out.ambiguous_bar_used=false;
      out.sequencing_ambiguous=false; out.alt_bound_exit_time=0; out.alt_bound_exit_price=0.0;
      out.mfe_until_exit_r=0.0; out.mae_until_exit_r=0.0;

      bool is_be_or_trail=(params.model==MSZZ_EXIT_BE_0_5R || params.model==MSZZ_EXIT_BE_0_75R ||
                            params.model==MSZZ_EXIT_BE_1R || params.model==MSZZ_EXIT_BE_PLUS_COSTS ||
                            params.model==MSZZ_EXIT_TRAIL_0_5R_AFTER_1R);
      bool is_fixed=(params.model==MSZZ_EXIT_FIXED_1R || params.model==MSZZ_EXIT_FIXED_1_5R ||
                      params.model==MSZZ_EXIT_FIXED_2R || params.model==MSZZ_EXIT_FIXED_3R);
      bool is_time=(params.model==MSZZ_EXIT_TIME_4H || params.model==MSZZ_EXIT_TIME_8H ||
                     params.model==MSZZ_EXIT_TIME_12H || params.model==MSZZ_EXIT_TIME_24H);
      bool is_session=(params.model==MSZZ_EXIT_SESSION_CLOSE);

      double target = is_fixed
         ? (direction>0 ? entry_price+initial_risk*params.fixed_r_multiple
                        : entry_price-initial_risk*params.fixed_r_multiple)
         : original_target;

      double stop=initial_stop;
      bool armed=false;
      double best_r=-1.0e9, worst_r=1.0e9; // MFE/MAE until exit, updated every bar walked

      for(int i=0;i<bar_count;i++)
      {
         double stop_at_open=stop; // D022: the value tested against THIS bar's touch, before any update

         double fav_r=RMultiple(FavorablePrice(bars[i],direction),entry_price,initial_risk,direction);
         double adv_r=RMultiple(AdversePrice(bars[i],direction),entry_price,initial_risk,direction);
         if(fav_r>best_r) best_r=fav_r;
         if(adv_r<worst_r) worst_r=adv_r;

         string stop_reason = (MathAbs(stop_at_open-initial_stop)>0.0) ? "BE_TRAIL" : "SL";

         if(ambiguity==MSZZ_AMBIG_PESSIMISTIC)
         {
            bool stop_hit_old   = direction>0 ? (bars[i].low<=stop_at_open)  : (bars[i].high>=stop_at_open);
            bool target_hit     = direction>0 ? (bars[i].high>=target)      : (bars[i].low<=target);

            if(stop_hit_old && target_hit)
            {
               out.ambiguous_bar_used=true;
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=stop_at_open;
               out.exit_reason=stop_reason; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }
            if(stop_hit_old)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=stop_at_open;
               out.exit_reason=stop_reason; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }
            if(target_hit)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=target;
               out.exit_reason="TP"; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }

            // Survived this bar against the old stop -- only now may
            // favorable excursion arm or ratchet a new stop, and that new
            // stop is never tested against THIS bar's own range.
            if(is_be_or_trail)
            {
               double new_stop=ComputeCandidateStop(params,direction,entry_price,initial_risk,
                                                      stop_at_open,bars[i],armed,out.number_of_trail_updates);
               if(MathAbs(new_stop-stop_at_open)>0.0)
               {
                  bool would_hit_new_stop = direction>0 ? (bars[i].low<=new_stop) : (bars[i].high>=new_stop);
                  if(would_hit_new_stop)
                  {
                     out.sequencing_ambiguous=true;
                     out.alt_bound_exit_time=bars[i].time;
                     out.alt_bound_exit_price=new_stop;
                  }
               }
               stop=new_stop; // executable starting next bar only
            }
         }
         else // MSZZ_AMBIG_OPTIMISTIC -- genuinely separate logic, not pessimistic with levels swapped
         {
            bool target_hit = direction>0 ? (bars[i].high>=target) : (bars[i].low<=target);
            if(target_hit)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=target;
               out.exit_reason="TP"; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }

            double effective_stop=stop_at_open;
            if(is_be_or_trail)
            {
               effective_stop=ComputeCandidateStop(params,direction,entry_price,initial_risk,
                                                     stop_at_open,bars[i],armed,out.number_of_trail_updates);
               stop=effective_stop; // optimistic: the favorable-first update always commits
            }

            bool stop_hit_effective = direction>0 ? (bars[i].low<=effective_stop) : (bars[i].high>=effective_stop);
            if(stop_hit_effective)
            {
               string reason=(MathAbs(effective_stop-initial_stop)>0.0) ? "BE_TRAIL" : "SL";
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=effective_stop;
               out.exit_reason=reason; out.final_stop=effective_stop;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }
         }

         if(is_time && (long)(bars[i].time)>=(long)(entry_time)+params.time_limit_seconds)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
            out.exit_reason="TIME"; out.final_stop=stop;
            out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
            return;
         }
         if(is_session && params.session_boundary>0 && bars[i].time>=params.session_boundary)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
            out.exit_reason="SESSION_CLOSE"; out.final_stop=stop;
            out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
            return;
         }
      }
      // Path exhausted without resolution -- genuinely unresolved (not a
      // bug to paper over with a fabricated exit); caller must treat
      // resolved==false as "insufficient forward data," not as OPEN==loss.
   }
};
