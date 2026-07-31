#property strict

// Shared, side-effect-free execution contract for six-family screening.
// This type does not submit orders and does not depend on family code.
enum ENUM_MSZZ_SCREEN_EXIT_V2
{
   MSZZ_SCREEN_EXIT_STOP=0,
   MSZZ_SCREEN_EXIT_TARGET,
   MSZZ_SCREEN_EXIT_TEST_END
};

enum ENUM_MSZZ_SCREEN_REJECT_V2
{
   MSZZ_SCREEN_ACCEPT=0,
   MSZZ_SCREEN_REJECT_FAMILY_OPEN,
   MSZZ_SCREEN_REJECT_EXPIRED,
   MSZZ_SCREEN_REJECT_INVALID_GEOMETRY
};

struct MSZZScreeningPolicyV2
{
   string policy_id;
   int    schema_version;
   int    entry_offset_bars;
   bool   entry_uses_next_ask_for_long;
   bool   entry_uses_next_bid_for_short;
   bool   spread_embedded_once;
   bool   conservative_stop_rounding;
   bool   conservative_target_rounding;
   bool   one_position_per_family;
   bool   reject_signals_while_open;
   bool   opposite_signal_closes;
   bool   immediate_reversal;
   bool   stop_first_same_bar;
   bool   expiry_is_entry_only;
   bool   include_test_end_in_metrics;
   bool   include_commission_in_gross_r;
};

class CMSZZScreeningExecutionPolicyV2
{
public:
   static MSZZScreeningPolicyV2 Canonical()
   {
      MSZZScreeningPolicyV2 p;
      p.policy_id="MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST";
      p.schema_version=2;
      p.entry_offset_bars=1;
      p.entry_uses_next_ask_for_long=true;
      p.entry_uses_next_bid_for_short=true;
      p.spread_embedded_once=true;
      p.conservative_stop_rounding=true;
      p.conservative_target_rounding=true;
      p.one_position_per_family=true;
      p.reject_signals_while_open=true;
      p.opposite_signal_closes=false;
      p.immediate_reversal=false;
      p.stop_first_same_bar=true;
      p.expiry_is_entry_only=true;
      p.include_test_end_in_metrics=true;
      p.include_commission_in_gross_r=false;
      return p;
   }

   static bool Validate(const MSZZScreeningPolicyV2 &p,string &reason)
   {
      reason="";
      if(p.policy_id!="MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST") { reason="wrong policy id"; return false; }
      if(p.schema_version!=2 || p.entry_offset_bars!=1) { reason="wrong version or entry offset"; return false; }
      if(!p.entry_uses_next_ask_for_long || !p.entry_uses_next_bid_for_short || !p.spread_embedded_once) { reason="entry/spread policy mismatch"; return false; }
      if(!p.conservative_stop_rounding || !p.conservative_target_rounding) { reason="normalization policy mismatch"; return false; }
      if(!p.one_position_per_family || !p.reject_signals_while_open || p.opposite_signal_closes || p.immediate_reversal) { reason="occupancy policy mismatch"; return false; }
      if(!p.stop_first_same_bar || !p.expiry_is_entry_only || !p.include_test_end_in_metrics || p.include_commission_in_gross_r) { reason="exit/accounting policy mismatch"; return false; }
      return true;
   }

   static double NormalizeStop(const int direction,const double raw_stop,const double entry,const double tick_size)
   {
      if(tick_size<=0.0 || entry<=0.0 || raw_stop<=0.0) return 0.0;
      double n=(direction>0 ? MathFloor(raw_stop/tick_size+1.0e-9) : MathCeil(raw_stop/tick_size-1.0e-9))*tick_size;
      if(direction>0 && n>=entry) n=MathFloor((entry-tick_size)/tick_size)*tick_size;
      if(direction<0 && n<=entry) n=MathCeil((entry+tick_size)/tick_size)*tick_size;
      return NormalizeDouble(n,8);
   }

   static double NormalizeTarget(const int direction,const double raw_target,const double entry,const double tick_size)
   {
      if(tick_size<=0.0 || entry<=0.0 || raw_target<=0.0) return 0.0;
      double n=(direction>0 ? MathFloor(raw_target/tick_size+1.0e-9) : MathCeil(raw_target/tick_size-1.0e-9))*tick_size;
      if(direction>0 && n<=entry) n=MathCeil((entry+tick_size)/tick_size)*tick_size;
      if(direction<0 && n>=entry) n=MathFloor((entry-tick_size)/tick_size)*tick_size;
      return NormalizeDouble(n,8);
   }

   static ENUM_MSZZ_SCREEN_REJECT_V2 CandidateStatus(const bool family_open,const datetime entry_time,const datetime expiry_time)
   {
      if(family_open) return MSZZ_SCREEN_REJECT_FAMILY_OPEN;
      if(expiry_time>0 && entry_time>expiry_time) return MSZZ_SCREEN_REJECT_EXPIRED;
      return MSZZ_SCREEN_ACCEPT;
   }

   static ENUM_MSZZ_SCREEN_EXIT_V2 ResolveBar(const int direction,const double stop,const double target,const double high,const double low)
   {
      bool hit_stop=(direction>0 ? low<=stop : high>=stop);
      bool hit_target=(direction>0 ? high>=target : low<=target);
      if(hit_stop) return MSZZ_SCREEN_EXIT_STOP;
      if(hit_target) return MSZZ_SCREEN_EXIT_TARGET;
      return MSZZ_SCREEN_EXIT_TEST_END;
   }

   static double GrossR(const int direction,const double entry,const double exit_price,const double stop)
   {
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) return 0.0;
      return (direction>0 ? exit_price-entry : entry-exit_price)/risk;
   }
};
