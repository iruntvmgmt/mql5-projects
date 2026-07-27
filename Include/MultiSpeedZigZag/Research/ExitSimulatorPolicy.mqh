#property strict
//+------------------------------------------------------------------+
//| ExitSimulatorPolicy.mqh                                           |
//| D021: pure, deterministic exit-model resolution for the Exit-     |
//| Efficiency Study Phase 1. No MT5 API calls -- every input is      |
//| passed in explicitly so this is directly unit-testable against   |
//| hand-built synthetic bar arrays. See DECISION_LOG.md D021.       |
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
   MSZZ_AMBIG_PESSIMISTIC=0,   // adverse level (stop) assumed hit first when both are in-range same bar
   MSZZ_AMBIG_OPTIMISTIC=1     // favorable level (target) assumed hit first -- upper bound only, never headline
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
   string   exit_reason;        // "TP","SL","BE","TRAIL","TIME","SESSION_CLOSE","OPEN"
   double   final_stop;
   int      number_of_trail_updates;
   bool     ambiguous_bar_used; // true if any bar had both stop and target/threshold in [low,high]
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

   // surrender_r = mfe_r - realized_r. percent_mfe_captured is only
   // meaningful (non-null) when mfe_r exceeds min_mfe_threshold -- caller
   // is responsible for treating the bool return as "field is null" when
   // false, never dividing by a near-zero mfe_r.
   static bool PercentMfeCaptured(const double realized_r,const double mfe_r,
                                   const double min_mfe_threshold,double &out_pct)
   {
      out_pct=0.0;
      if(mfe_r<=min_mfe_threshold) return false;
      out_pct=realized_r/mfe_r;
      return true;
   }

   // Core exit resolution. bars[] must start at the first bar AFTER entry
   // (the entry bar itself is not part of the forward path) and be in
   // strictly increasing time order -- the loop only ever reads bars[j]
   // for j<=i at decision time i, so causality is structural, not just
   // asserted (see Test_MSZZ_ExitSimulator.mq5 case 13).
   static void SimulateExit(const int direction,const double entry_price,
                             const double initial_stop,const double initial_risk,
                             const double original_target,
                             const MSZZExitBar &bars[],const int bar_count,
                             const MSZZExitParams &params,
                             const ENUM_MSZZ_AMBIGUITY_MODE ambiguity,
                             MSZZExitResult &out)
   {
      out.resolved=false; out.exit_time=0; out.exit_price=0.0;
      out.exit_reason="OPEN"; out.final_stop=initial_stop;
      out.number_of_trail_updates=0; out.ambiguous_bar_used=false;

      bool is_fixed=(params.model==MSZZ_EXIT_FIXED_1R || params.model==MSZZ_EXIT_FIXED_1_5R ||
                      params.model==MSZZ_EXIT_FIXED_2R || params.model==MSZZ_EXIT_FIXED_3R);
      bool is_be=(params.model==MSZZ_EXIT_BE_0_5R || params.model==MSZZ_EXIT_BE_0_75R ||
                   params.model==MSZZ_EXIT_BE_1R || params.model==MSZZ_EXIT_BE_PLUS_COSTS);
      bool is_trail=(params.model==MSZZ_EXIT_TRAIL_0_5R_AFTER_1R);
      bool is_time=(params.model==MSZZ_EXIT_TIME_4H || params.model==MSZZ_EXIT_TIME_8H ||
                     params.model==MSZZ_EXIT_TIME_12H || params.model==MSZZ_EXIT_TIME_24H);
      bool is_session=(params.model==MSZZ_EXIT_SESSION_CLOSE);

      double target = is_fixed
         ? (direction>0 ? entry_price+initial_risk*params.fixed_r_multiple
                        : entry_price-initial_risk*params.fixed_r_multiple)
         : original_target;

      double stop=initial_stop;
      bool armed=false; // breakeven or trail armed

      for(int i=0;i<bar_count;i++)
      {
         // Breakeven activation (checked before this bar's touch test, using
         // the PREVIOUS bar's confirmed excursion would be more strictly
         // causal, but activation on the same bar the trigger is reached is
         // the standard, intended behavior for this class of exit -- the
         // trigger and the stop move happen atomically once the excursion
         // is observed on this bar).
         if(is_be && !armed)
         {
            double fav_r=RMultiple(FavorablePrice(bars[i],direction),entry_price,initial_risk,direction);
            if(fav_r>=params.be_trigger_r)
            {
               double be_price = direction>0 ? entry_price+params.be_offset_price
                                              : entry_price-params.be_offset_price;
               stop=be_price;
               armed=true;
               out.number_of_trail_updates++;
            }
         }

         if(is_trail)
         {
            double fav_r=RMultiple(FavorablePrice(bars[i],direction),entry_price,initial_risk,direction);
            if(!armed && fav_r>=params.trail_trigger_r) armed=true;
            if(armed)
            {
               double trail_price = direction>0
                  ? FavorablePrice(bars[i],direction)-params.trail_distance_r*initial_risk
                  : FavorablePrice(bars[i],direction)+params.trail_distance_r*initial_risk;
               // Stop may only move in the profitable direction, never widen.
               bool improves = direction>0 ? (trail_price>stop) : (trail_price<stop);
               if(improves) { stop=trail_price; out.number_of_trail_updates++; }
            }
         }

         bool stop_hit   = direction>0 ? (bars[i].low<=stop)   : (bars[i].high>=stop);
         bool target_hit = direction>0 ? (bars[i].high>=target): (bars[i].low<=target);

         if(stop_hit && target_hit)
         {
            out.ambiguous_bar_used=true;
            if(ambiguity==MSZZ_AMBIG_PESSIMISTIC)
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=stop;
               out.exit_reason=(armed && MathAbs(stop-initial_stop)>0.0 ? "BE_TRAIL" : "SL");
               out.final_stop=stop;
               return;
            }
            else
            {
               out.resolved=true; out.exit_time=bars[i].time; out.exit_price=target;
               out.exit_reason="TP"; out.final_stop=stop;
               return;
            }
         }
         if(stop_hit)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=stop;
            out.exit_reason=(armed && MathAbs(stop-initial_stop)>0.0 ? "BE_TRAIL" : "SL");
            out.final_stop=stop;
            return;
         }
         if(target_hit)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=target;
            out.exit_reason="TP"; out.final_stop=stop;
            return;
         }

         // time_limit_seconds is a duration (e.g. 14400 for 4h); bars[0]
         // is the first post-entry bar, at most one bar-period after the
         // actual entry_time, so anchoring the boundary to bars[0].time
         // is accurate to within one bar (M5 granularity in this study).
         if(is_time && (long)(bars[i].time)>=(long)(bars[0].time)+params.time_limit_seconds)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
            out.exit_reason="TIME"; out.final_stop=stop;
            return;
         }
         if(is_session && params.session_boundary>0 && bars[i].time>=params.session_boundary)
         {
            out.resolved=true; out.exit_time=bars[i].time; out.exit_price=bars[i].close;
            out.exit_reason="SESSION_CLOSE"; out.final_stop=stop;
            return;
         }
      }
      // Path exhausted without resolution -- genuinely unresolved (not a
      // bug to paper over with a fabricated exit); caller must treat
      // resolved==false as "insufficient forward data," not as OPEN==loss.
   }
};
