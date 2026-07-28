#property strict
//+------------------------------------------------------------------+
//| ExitModelsPhase2.mqh                                              |
//| D024: FastMedConfluence Phase 2 exit and holding-tail study.       |
//| 11 causal structural/composite exit models (a 12th, TRAIL_AFTER_1R,|
//| is D021/D022's already-implemented TRAIL_0_5R_AFTER_1R, reused     |
//| verbatim by the caller rather than duplicated here).                |
//|                                                                     |
//| Every model inherits D022's exact same-bar sequencing discipline:   |
//| the stop is evaluated as it stood at bar OPEN against the old       |
//| stop/target/discrete-exit-condition first (pessimistic: adverse     |
//| wins on ambiguity); only a bar that survives may compute a          |
//| candidate new stop, which becomes executable no earlier than the    |
//| NEXT bar and never widens. See DECISION_LOG.md D024.                |
//+------------------------------------------------------------------+

#include <MultiSpeedZigZag/Research/ExitSimulatorPolicy.mqh>
#include <MultiSpeedZigZag/Research/StructuralReplay.mqh>

enum ENUM_MSZZ_PHASE2_MODEL
{
   MSZZ_P2_CHANDELIER_TRAIL=0,
   MSZZ_P2_FAST_SWING_TRAIL,
   MSZZ_P2_MEDIUM_SWING_TRAIL,
   MSZZ_P2_HL_LH_TRAIL,
   MSZZ_P2_OPPOSITE_FAST_EXIT,
   MSZZ_P2_TIME_8H,
   MSZZ_P2_TIME_12H,
   MSZZ_P2_TIME_24H,
   MSZZ_P2_FIXED_2R_PLUS_TIMEOUT,
   MSZZ_P2_BE_1R_PLUS_TRAIL,
   MSZZ_P2_SESSION_OVERNIGHT,
   MSZZ_P2_MODEL_COUNT
};

struct MSZZPhase2Params
{
   ENUM_MSZZ_PHASE2_MODEL model;
   double   chandelier_atr_mult;   // model 1: multiple of Medium ATR
   long     timeout_seconds;       // models 6-9: max holding time
};

class CMSZZPhase2ExitPolicy
{
public:
   // Chandelier candidate: highest-high-since-entry (long) minus
   // atr_mult*ATR(MedATRLen) at this bar, mirror for shorts. Caller
   // maintains extreme_since_entry across bars (updated with THIS bar's
   // own high/low before the candidate for the NEXT bar is computed --
   // same timing discipline as D022's favorable-extreme trail).
   static double ChandelierCandidate(const int direction,const double extreme_since_entry,
                                       const double atr_now,const double atr_mult)
   {
      if(atr_now<=0.0) return (direction>0 ? -1.0e9 : 1.0e9);
      return (direction>0) ? extreme_since_entry-atr_mult*atr_now
                            : extreme_since_entry+atr_mult*atr_now;
   }

   // Fast/Medium swing-trail candidate: the relevant speed's most
   // recently confirmed same-direction swing extreme, causally known as
   // of this bar (hist[i] already only reflects up-to-and-including
   // bar i, see StructuralReplay.mqh). require_constructive_label
   // implements model 4 (HL for longs / LH for shorts only); false
   // implements models 2/3 (any new same-direction extreme).
   //
   // Sanity guard (bug found empirically during D024 verification): the
   // engine's "last confirmed low/high" can legitimately be STALE --
   // e.g. if price has been falling for a long, sustained stretch
   // without yet confirming a new (lower) low, "last_low" still holds
   // the OLDER, higher swing from before the decline began, which can
   // sit ABOVE current price. Using such a level as a long's trailing
   // stop is nonsensical (it would sit above the market, guaranteeing
   // an immediate "stop-out" that actually computes as a huge fake
   // profit via RMultiple). A trail candidate is only structurally
   // valid if it is on the correct side of the CURRENT bar's own close
   // -- below it for a long, above it for a short.
   static bool SwingTrailCandidate(const int direction,const MSZZSpeedBarState &state,
                                     const bool require_constructive_label,const double current_close,
                                     double &out_candidate)
   {
      if(direction>0)
      {
         if(!state.last_low.valid) return false;
         if(require_constructive_label && state.last_low.structure_label!=MSZZ_STRUCT_HL) return false;
         if(state.last_low.price>=current_close) return false; // stale/wrong-side swing, reject
         out_candidate=state.last_low.price;
         return true;
      }
      else
      {
         if(!state.last_high.valid) return false;
         if(require_constructive_label && state.last_high.structure_label!=MSZZ_STRUCT_LH) return false;
         if(state.last_high.price<=current_close) return false; // stale/wrong-side swing, reject
         out_candidate=state.last_high.price;
         return true;
      }
   }

   static void SimulatePhase2Exit(const int direction,const double entry_price,const double initial_stop,
                                    const double initial_risk,const double fixed_target_2r,
                                    const datetime entry_time,
                                    const MSZZExitBar &bars[],const MSZZSpeedBarState &fast_hist[],
                                    const MSZZSpeedBarState &med_hist[],const double &atr_med[],
                                    const int bar_count,const MSZZPhase2Params &params,
                                    const ENUM_MSZZ_AMBIGUITY_MODE ambiguity,
                                    MSZZExitResult &out)
   {
      out.resolved=false; out.exit_time=0; out.exit_price=0.0;
      out.exit_reason="OPEN"; out.final_stop=initial_stop;
      out.number_of_trail_updates=0; out.ambiguous_bar_used=false;
      out.sequencing_ambiguous=false; out.alt_bound_exit_time=0; out.alt_bound_exit_price=0.0;
      out.mfe_until_exit_r=0.0; out.mae_until_exit_r=0.0;

      bool is_time_only=(params.model==MSZZ_P2_TIME_8H || params.model==MSZZ_P2_TIME_12H || params.model==MSZZ_P2_TIME_24H);
      bool is_fixed_plus_timeout=(params.model==MSZZ_P2_FIXED_2R_PLUS_TIMEOUT);
      bool is_discrete_exit=(params.model==MSZZ_P2_OPPOSITE_FAST_EXIT || params.model==MSZZ_P2_SESSION_OVERNIGHT);
      bool is_chandelier=(params.model==MSZZ_P2_CHANDELIER_TRAIL);
      bool is_fast_swing=(params.model==MSZZ_P2_FAST_SWING_TRAIL);
      bool is_med_swing=(params.model==MSZZ_P2_MEDIUM_SWING_TRAIL);
      bool is_hl_lh=(params.model==MSZZ_P2_HL_LH_TRAIL);
      bool is_be_plus_trail=(params.model==MSZZ_P2_BE_1R_PLUS_TRAIL);
      bool has_trail_logic=(is_chandelier || is_fast_swing || is_med_swing || is_hl_lh || is_be_plus_trail);

      // fixed_target_2r is precomputed by the caller (entry +/- 2*risk);
      // FIXED_2R_PLUS_TIMEOUT and the trail models (which never move the
      // target, only the stop) all share it as "the" target.
      double target=fixed_target_2r;

      double stop=initial_stop;
      bool armed=false; // BE_1R_PLUS_TRAIL: has +1R breakeven armed yet
      double extreme_since_entry=(direction>0 ? bars[0].high : bars[0].low);
      double best_r=-1.0e9, worst_r=1.0e9;
      int last_session_hour=-1;

      for(int i=0;i<bar_count;i++)
      {
         double stop_at_open=stop;

         double fav_r=CMSZZExitSimulatorPolicy::RMultiple(
            (direction>0?bars[i].high:bars[i].low),entry_price,initial_risk,direction);
         double adv_r=CMSZZExitSimulatorPolicy::RMultiple(
            (direction>0?bars[i].low:bars[i].high),entry_price,initial_risk,direction);
         if(fav_r>best_r) best_r=fav_r;
         if(adv_r<worst_r) worst_r=adv_r;

         if(direction>0) extreme_since_entry=MathMax(extreme_since_entry,bars[i].high);
         else            extreme_since_entry=MathMin(extreme_since_entry,bars[i].low);

         string stop_reason=(MathAbs(stop_at_open-initial_stop)>0.0) ? "TRAIL" : "SL";

         bool stop_hit_old = direction>0 ? (bars[i].low<=stop_at_open) : (bars[i].high>=stop_at_open);
         // Trail models and FIXED_2R_PLUS_TIMEOUT keep the original 2R
         // target as an upside cap (only the stop ever moves). The
         // discrete-exit models (opposite-structure, session-overnight)
         // also still respect it as a bound. Pure time-only models have
         // no fixed target at all.
         bool has_target=(is_fixed_plus_timeout || has_trail_logic || is_discrete_exit);
         bool target_hit = has_target && (direction>0 ? (bars[i].high>=target) : (bars[i].low<=target));

         bool discrete_exit_fires=false; string discrete_reason="";
         if(params.model==MSZZ_P2_OPPOSITE_FAST_EXIT)
         {
            if(direction>0 && fast_hist[i].bearish_break) { discrete_exit_fires=true; discrete_reason="OPPOSITE_STRUCTURE"; }
            if(direction<0 && fast_hist[i].bullish_break) { discrete_exit_fires=true; discrete_reason="OPPOSITE_STRUCTURE"; }
         }
         else if(params.model==MSZZ_P2_SESSION_OVERNIGHT)
         {
            MqlDateTime dtm; TimeToStruct(bars[i].time,dtm);
            if(dtm.hour==0 && last_session_hour!=0) { discrete_exit_fires=true; discrete_reason="SESSION_OVERNIGHT"; }
            last_session_hour=dtm.hour;
         }

         if(ambiguity==MSZZ_AMBIG_PESSIMISTIC)
         {
            if(stop_hit_old && (target_hit || discrete_exit_fires))
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
            if(discrete_exit_fires)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
               out.exit_reason=discrete_reason; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }

            // survived this bar -- may compute a candidate new stop,
            // executable no earlier than next bar.
            if(has_trail_logic)
            {
               double candidate=stop_at_open; bool have_candidate=false;
               if(is_chandelier)
               {
                  double atr_now=(i<ArraySize(atr_med))?atr_med[i]:0.0;
                  double c=ChandelierCandidate(direction,extreme_since_entry,atr_now,params.chandelier_atr_mult);
                  have_candidate=(atr_now>0.0); candidate=c;
               }
               else if(is_fast_swing)
               {
                  have_candidate=SwingTrailCandidate(direction,fast_hist[i],false,bars[i].close,candidate);
               }
               else if(is_med_swing)
               {
                  have_candidate=SwingTrailCandidate(direction,med_hist[i],false,bars[i].close,candidate);
               }
               else if(is_hl_lh)
               {
                  have_candidate=SwingTrailCandidate(direction,med_hist[i],true,bars[i].close,candidate);
               }
               else if(is_be_plus_trail)
               {
                  if(!armed && fav_r>=1.0) { armed=true; candidate=entry_price; have_candidate=true; }
                  else if(armed)
                  {
                     double sc;
                     if(SwingTrailCandidate(direction,med_hist[i],false,bars[i].close,sc))
                     { candidate=sc; have_candidate=true; }
                  }
               }

               if(have_candidate)
               {
                  bool improves = direction>0 ? (candidate>stop_at_open) : (candidate<stop_at_open);
                  if(improves)
                  {
                     bool would_hit_new = direction>0 ? (bars[i].low<=candidate) : (bars[i].high>=candidate);
                     if(would_hit_new)
                     {
                        out.sequencing_ambiguous=true;
                        out.alt_bound_exit_time=bars[i].time;
                        out.alt_bound_exit_price=candidate;
                     }
                     stop=candidate;
                     out.number_of_trail_updates++;
                  }
               }
            }
         }
         else // MSZZ_AMBIG_OPTIMISTIC -- favorable-first, genuinely different path
         {
            if(target_hit)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=target;
               out.exit_reason="TP"; out.final_stop=stop_at_open;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }

            double effective_stop=stop_at_open;
            if(has_trail_logic)
            {
               double candidate=stop_at_open; bool have_candidate=false;
               if(is_chandelier)
               {
                  double atr_now=(i<ArraySize(atr_med))?atr_med[i]:0.0;
                  candidate=ChandelierCandidate(direction,extreme_since_entry,atr_now,params.chandelier_atr_mult);
                  have_candidate=(atr_now>0.0);
               }
               else if(is_fast_swing) have_candidate=SwingTrailCandidate(direction,fast_hist[i],false,bars[i].close,candidate);
               else if(is_med_swing)  have_candidate=SwingTrailCandidate(direction,med_hist[i],false,bars[i].close,candidate);
               else if(is_hl_lh)      have_candidate=SwingTrailCandidate(direction,med_hist[i],true,bars[i].close,candidate);
               else if(is_be_plus_trail)
               {
                  if(!armed && fav_r>=1.0) { armed=true; candidate=entry_price; have_candidate=true; }
                  else if(armed) { double sc; if(SwingTrailCandidate(direction,med_hist[i],false,bars[i].close,sc)) { candidate=sc; have_candidate=true; } }
               }
               if(have_candidate)
               {
                  bool improves = direction>0 ? (candidate>effective_stop) : (candidate<effective_stop);
                  if(improves) { effective_stop=candidate; stop=candidate; out.number_of_trail_updates++; }
               }
            }

            bool stop_hit_effective = direction>0 ? (bars[i].low<=effective_stop) : (bars[i].high>=effective_stop);
            if(stop_hit_effective)
            {
               string reason=(MathAbs(effective_stop-initial_stop)>0.0) ? "TRAIL" : "SL";
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=effective_stop;
               out.exit_reason=reason; out.final_stop=effective_stop;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }
            if(discrete_exit_fires)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
               out.exit_reason=discrete_reason; out.final_stop=effective_stop;
               out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
               return;
            }
         }

         if((is_time_only || is_fixed_plus_timeout) &&
            (long)(bars[i].time)>=(long)(entry_time)+params.timeout_seconds)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
            out.exit_reason=(is_time_only?"TIME":"TIMEOUT"); out.final_stop=stop;
            out.mfe_until_exit_r=best_r; out.mae_until_exit_r=worst_r;
            return;
         }
      }
   }
};
