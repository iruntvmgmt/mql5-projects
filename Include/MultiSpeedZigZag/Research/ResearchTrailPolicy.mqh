#ifndef __MSZZ_RESEARCH_TRAIL_POLICY_MQH__
#define __MSZZ_RESEARCH_TRAIL_POLICY_MQH__

// D026: trailing-stop validation on top of the proven full-EA
// FastMedConfluence behavior (structural stop, InpExitOwnedOpposite=true
// close/reverse) -- see DECISION_LOG.md D026. Pure, deterministic,
// no-MT5-API policy class, same shape as every other component in this
// series. Structure-trail candidates are evaluated against whatever
// MSZZPivot the caller supplies -- in the live EA this is always the
// CMSZZTripleZigZagEngine's own per-bar snapshot (already computed every
// closed bar for signal evaluation), never an offline replay duplicate,
// per D026's explicit instruction not to repeat D024's mistake of
// validating a mechanism against something that isn't the live EA's own
// structural state.

#include <MultiSpeedZigZag/Core/Types.mqh>

#define MSZZ_TRAIL_MAX_RUNGS 5

enum ENUM_MSZZ_TRAIL_STRUCTURE
{
   MSZZ_TRAIL_STRUCT_NONE = 0,
   MSZZ_TRAIL_STRUCT_FAST_SWING,
   MSZZ_TRAIL_STRUCT_MEDIUM_SWING,
   MSZZ_TRAIL_STRUCT_CHANDELIER
};

struct MSZZTrailFloorRung
{
   double trigger_r;
   double floor_r;
};

struct MSZZTrailConfig
{
   bool                      enabled;
   int                       rung_count;
   MSZZTrailFloorRung        rungs[MSZZ_TRAIL_MAX_RUNGS];
   double                    cost_r_estimate;
   ENUM_MSZZ_TRAIL_STRUCTURE structure_mode;
   double                    structure_activation_r;
   int                       chandelier_atr_len;
   double                    chandelier_atr_mult;
};

struct MSZZTrailState
{
   bool                active;
   ulong               ticket;
   ENUM_MSZZ_DIRECTION direction;
   double              entry;
   double              original_stop;
   double              initial_risk;
   double              max_favorable_r;
   double              effective_stop;
   int                 next_rung_index;
   bool                structure_activated;
   double              highest_since_activation;
   double              lowest_since_activation;
   datetime            last_modification_time;
   bool                last_modification_ok;
   string              last_modification_reason;
};

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// every other component in this series (D005/D009/D010/D011/D012/D013/
// D024's ExitModelsPhase2).
class CMSZZResearchTrailPolicy
{
public:
   static void InitState(MSZZTrailState &state,const ulong ticket,const ENUM_MSZZ_DIRECTION direction,
                          const double entry,const double original_stop,const double current_broker_stop)
   {
      state.active=true;
      state.ticket=ticket;
      state.direction=direction;
      state.entry=entry;
      state.original_stop=original_stop;
      state.initial_risk=MathAbs(entry-original_stop);
      state.max_favorable_r=0.0;
      // D026 restart-safety: always seeded from the CURRENT broker-side
      // stop, never a remembered value, so a freshly (re)created state can
      // never propose a "tightening" that actually widens today's real
      // stop. See DECISION_LOG.md D026 "restart persistence" note.
      state.effective_stop=current_broker_stop;
      state.next_rung_index=0;
      state.structure_activated=false;
      state.highest_since_activation=0.0;
      state.lowest_since_activation=0.0;
      state.last_modification_time=0;
      state.last_modification_ok=false;
      state.last_modification_reason="";
   }

   // Favorable excursion in R, from the bar's own favorable extreme --
   // matches this EA's existing closed-bar cadence (D025 ProcessPartialCloses).
   // risk<=0 returns 0.0 rather than dividing by zero -- defensive, callers
   // are expected to have already validated initial_risk>0 before tracking
   // a ticket at all.
   static double FavorableR(const ENUM_MSZZ_DIRECTION direction,const double entry,
                             const double risk,const double bar_high,const double bar_low)
   {
      if(risk<=0.0) return 0.0;
      double favorable=(direction==MSZZ_DIR_LONG ? bar_high : bar_low);
      return (direction==MSZZ_DIR_LONG ? (favorable-entry) : (entry-favorable))/risk;
   }

   // Rungs must be supplied ascending by trigger_r (the EA validates this
   // at OnInit(), fail-closed, rather than sorting silently here). Scans
   // every rung strictly after the last-applied index and returns the
   // HIGHEST one whose trigger has been reached this bar -- so a bar that
   // gaps past more than one rung in a single step still lands on the
   // correct (furthest) rung, and next_rung_index guarantees no rung is
   // ever re-applied once superseded.
   static bool EvaluateFloorRung(const MSZZTrailConfig &config,MSZZTrailState &state,
                                  const double fav_r,double &candidate_stop)
   {
      int chosen=-1;
      for(int i=state.next_rung_index;i<config.rung_count;i++)
         if(fav_r>=config.rungs[i].trigger_r) chosen=i;
      if(chosen<0) return false;
      double floor_r=config.rungs[chosen].floor_r;
      double cost=(MathAbs(floor_r)<1e-9 ? config.cost_r_estimate : 0.0);
      double signed_offset=(state.direction==MSZZ_DIR_LONG ? (floor_r+cost) : -(floor_r+cost));
      candidate_stop=state.entry+signed_offset*state.initial_risk;
      state.next_rung_index=chosen+1;
      return true;
   }

   // Reuses D024's Bug-1 fix verbatim: a confirmed swing on the wrong side
   // of the current close is stale (e.g. a "last low" left over from before
   // a sustained rally), never a valid long trailing-stop candidate, and
   // vice versa for shorts. See DECISION_LOG.md D024 "Bug 1".
   static bool SwingTrailCandidate(const ENUM_MSZZ_DIRECTION direction,const double current_close,
                                    const bool swing_valid,const double swing_price,
                                    double &candidate_stop)
   {
      if(!swing_valid) return false;
      if(direction==MSZZ_DIR_LONG)
      {
         if(swing_price>=current_close) return false;
         candidate_stop=swing_price;
         return true;
      }
      if(direction==MSZZ_DIR_SHORT)
      {
         if(swing_price<=current_close) return false;
         candidate_stop=swing_price;
         return true;
      }
      return false;
   }

   // Closed-bar-only true-range average -- an explicit simplification
   // (plain average, not Wilder-smoothed), documented rather than claimed
   // to match any specific published Chandelier formula exactly. end_index
   // is the index of the last closed bar in a time-ascending array; needs
   // end_index>=len so every bar in the window has a valid prior close.
   static double SimpleATR(const double &high[],const double &low[],const double &close[],
                            const int end_index,const int len)
   {
      if(len<=0 || end_index<len) return 0.0;
      double sum=0.0;
      for(int i=end_index-len+1;i<=end_index;i++)
      {
         double tr1=high[i]-low[i];
         double tr2=MathAbs(high[i]-close[i-1]);
         double tr3=MathAbs(low[i]-close[i-1]);
         sum+=MathMax(tr1,MathMax(tr2,tr3));
      }
      return sum/len;
   }

   static double ChandelierCandidate(const ENUM_MSZZ_DIRECTION direction,const double extreme_since_activation,
                                      const double atr,const double mult)
   {
      return (direction==MSZZ_DIR_LONG) ? (extreme_since_activation-mult*atr)
                                         : (extreme_since_activation+mult*atr);
   }

   // The only place a stop is allowed to move. Monotonic tightening only
   // (long: candidate must be strictly higher than current; short: strictly
   // lower) -- anything else is rejected outright, never clamped, so an
   // applied stop is always exactly what the model proposed, not a
   // broker-distance-adjusted approximation of it. min_distance is the
   // broker's own minimum stop distance from the current market price on
   // the correct side; a candidate that doesn't clear it is rejected for
   // this bar (the caller may try again next bar), not forced closer.
   static bool ResolveTightening(const ENUM_MSZZ_DIRECTION direction,const double current_effective_stop,
                                  const double candidate_stop,const double market_price,
                                  const double min_distance,double &new_stop)
   {
      if(direction==MSZZ_DIR_LONG)
      {
         if(candidate_stop<=current_effective_stop) return false;
         if(market_price-candidate_stop<min_distance) return false;
         new_stop=candidate_stop;
         return true;
      }
      if(direction==MSZZ_DIR_SHORT)
      {
         if(candidate_stop>=current_effective_stop) return false;
         if(candidate_stop-market_price<min_distance) return false;
         new_stop=candidate_stop;
         return true;
      }
      return false;
   }
};

#endif
