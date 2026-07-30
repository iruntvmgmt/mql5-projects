#ifndef __MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2_MQH__
#define __MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Core/StructuralEventRecord.mqh>

#define MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2 "MSZZ_RESEARCH_CANDIDATE_V2"
#define MSZZ_RESEARCH_RAW_BROKER_AUTHORITY_V2 "MSZZ_TIME_RAW_BROKER_V1"

enum ENUM_MSZZ_RESEARCH_CLOCK_DOMAIN_V2
{
   MSZZ_RESEARCH_CLOCK_NONE=0,
   MSZZ_RESEARCH_CLOCK_BROKER_SERVER_RAW=1,
   MSZZ_RESEARCH_CLOCK_UTC_CONVERTED=2
};

enum ENUM_MSZZ_RESEARCH_REFERENCE_V2
{
   MSZZ_RESEARCH_REFERENCE_NONE=0,
   MSZZ_RESEARCH_REFERENCE_SESSION_RANGE=1,
   MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT=2,
   MSZZ_RESEARCH_REFERENCE_COMPRESSION_WINDOW=3,
   MSZZ_RESEARCH_REFERENCE_VALUE=4,
   MSZZ_RESEARCH_REFERENCE_RANGE=5
};

enum ENUM_MSZZ_RESEARCH_TERMINAL_STATE_V2
{
   MSZZ_RESEARCH_TERMINAL_NONE=0,
   MSZZ_RESEARCH_TERMINAL_EXPIRED=1,
   MSZZ_RESEARCH_TERMINAL_INVALIDATED=2,
   MSZZ_RESEARCH_TERMINAL_EMITTED=3,
   MSZZ_RESEARCH_TERMINAL_SESSION_RESET=4,
   MSZZ_RESEARCH_TERMINAL_DAY_RESET=5
};

enum ENUM_MSZZ_RESEARCH_RESET_V2
{
   MSZZ_RESEARCH_RESET_NONE=0,
   MSZZ_RESEARCH_RESET_FRESH_CROSS=1,
   MSZZ_RESEARCH_RESET_NEUTRAL=2,
   MSZZ_RESEARCH_RESET_SESSION=3,
   MSZZ_RESEARCH_RESET_DAY=4,
   MSZZ_RESEARCH_RESET_NEW_STRUCTURE=5,
   MSZZ_RESEARCH_RESET_NEW_EPISODE=6
};

enum ENUM_MSZZ_RESEARCH_VALUE_V2
{
   MSZZ_RESEARCH_VALUE_NONE=0,
   MSZZ_RESEARCH_VALUE_VWAP_SESSION=1,
   MSZZ_RESEARCH_VALUE_ALMA=2
};

struct MSZZResearchCandidateSSRFieldsV2
{
   string ssr_clock_rule_id;
   string ssr_range_id;
   double ssr_range_high;
   double ssr_range_low;
   double ssr_sweep_extreme;
   double ssr_reclaim_close;
};

struct MSZZResearchCandidateMCFieldsV2
{
   string mc_structural_event_id;
   double mc_impulse_origin_price;
   double mc_impulse_extreme_price;
   double mc_impulse_distance_atr;
   double mc_efficiency;
   int    mc_pause_bars;
   double mc_pullback_fraction;
};

struct MSZZResearchCandidateBRCFieldsV2
{
   string   brc_break_event_id;
   string   brc_broken_level_id;
   double   brc_broken_level_price;
   datetime brc_first_touch_time;
   datetime brc_rejection_time;
   double   brc_penetration_atr;
   int      brc_test_count;
};

struct MSZZResearchCandidateCBRFieldsV2
{
   datetime cbr_window_start;
   datetime cbr_window_end;
   string   cbr_window_hash;
   double   cbr_short_atr;
   double   cbr_long_atr;
   double   cbr_range_atr;
   double   cbr_extension_atr;
   double   cbr_obstruction_r;
};

struct MSZZResearchCandidateTPFieldsV2
{
   string                      tp_impulse_event_id;
   ENUM_MSZZ_RESEARCH_VALUE_V2 tp_value_type;
   string                      tp_value_anchor_id;
   double                      tp_distance_start_atr;
   double                      tp_distance_min_atr;
   double                      tp_distance_trigger_atr;
};

struct MSZZResearchCandidateRRFieldsV2
{
   string rr_range_id;
   double rr_width_cv;
   string rr_high_touch_ids;
   string rr_low_touch_ids;
   int    rr_min_touch_separation_bars;
   double rr_rotation_away_atr;
   bool   rr_medium_contained;
   double rr_midpoint;
};

struct MSZZResearchStructuralBindingV2
{
   bool                      bound;
   MSZZStructuralEventRecord record;
};

struct MSZZResearchCandidateV2
{
   bool                                  valid;
   string                                validation_reason;
   string                                schema_version;
   int                                   strategy_id;
   int                                   family_id;
   string                                hypothesis_version;
   string                                canonical_variant_id;
   string                                origin_id;
   string                                sequence_id;
   string                                event_id;
   ENUM_MSZZ_RESEARCH_CLOCK_DOMAIN_V2    clock_domain;
   string                                time_authority_id;
   datetime                              signal_time;
   datetime                              expiry_time;
   ENUM_MSZZ_DIRECTION                   direction;
   double                                entry;
   double                                stop;
   double                                target;
   double                                score;
   ENUM_MSZZ_RESEARCH_REFERENCE_V2       reference_type;
   string                                reference_id;
   double                                reference_price;
   datetime                              arm_time;
   datetime                              trigger_time;
   int                                   bars_armed;
   ENUM_MSZZ_RESEARCH_TERMINAL_STATE_V2  terminal_prior_state;
   ENUM_MSZZ_RESEARCH_RESET_V2           reset_classification;
   double                                atr_at_arm;
   double                                atr_at_trigger;
   double                                stop_distance_points;
   double                                target_r;
   int                                   spread_points;
   double                                spread_to_risk_ratio;
   string                                session_id;
   string                                regime_id;
   string                                diagnostic_json;
   MSZZResearchCandidateSSRFieldsV2      ssr;
   MSZZResearchCandidateMCFieldsV2       mc;
   MSZZResearchCandidateBRCFieldsV2      brc;
   MSZZResearchCandidateCBRFieldsV2      cbr;
   MSZZResearchCandidateTPFieldsV2       tp;
   MSZZResearchCandidateRRFieldsV2       rr;
   MSZZResearchStructuralBindingV2       structural_binding;
};

class CMSZZResearchCandidateSchemaV2
{
private:
   static bool Finite(const double value)
   {
      return MathIsValidNumber(value);
   }

   static bool CloseEnough(const double a,const double b,const double tolerance)
   {
      return MathAbs(a-b)<=tolerance;
   }

   static void BlankStorage(MSZZResearchCandidateV2 &candidate)
   {
      ZeroMemory(candidate);
      candidate.schema_version="";
      candidate.validation_reason="";
      candidate.hypothesis_version="";
      candidate.canonical_variant_id="";
      candidate.origin_id="";
      candidate.sequence_id="";
      candidate.event_id="";
      candidate.time_authority_id="";
      candidate.reference_id="";
      candidate.session_id="";
      candidate.regime_id="";
      candidate.diagnostic_json="";
      candidate.ssr.ssr_clock_rule_id="";
      candidate.ssr.ssr_range_id="";
      candidate.mc.mc_structural_event_id="";
      candidate.brc.brc_break_event_id="";
      candidate.brc.brc_broken_level_id="";
      candidate.cbr.cbr_window_hash="";
      candidate.tp.tp_impulse_event_id="";
      candidate.tp.tp_value_anchor_id="";
      candidate.rr.rr_range_id="";
      candidate.rr.rr_high_touch_ids="";
      candidate.rr.rr_low_touch_ids="";
      candidate.structural_binding.bound=false;
      CMSZZStructuralEventPolicy::Blank(candidate.structural_binding.record);
   }

   static void BlankInvalid(MSZZResearchCandidateV2 &candidate,
                            const string reason)
   {
      BlankStorage(candidate);
      candidate.valid=false;
      candidate.schema_version=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2;
      candidate.validation_reason=reason;
   }

   static bool Fail(MSZZResearchCandidateV2 &candidate,const string reason)
   {
      BlankInvalid(candidate,reason);
      return false;
   }

   static bool ValidateStructuralBinding(MSZZResearchCandidateV2 &candidate,
                                         const double point_size)
   {
      if(!candidate.structural_binding.bound)
         return Fail(candidate,"MISSING_STRUCTURAL_BINDING");
      MSZZStructuralEventRecord certified=candidate.structural_binding.record;
      string reason="";
      if(!CMSZZStructuralEventPolicy::Validate(certified,point_size,reason))
         return Fail(candidate,"INVALID_STRUCTURAL_BINDING_"+reason);
      MSZZStructuralEventRecord record=candidate.structural_binding.record;
      double tolerance=MathMax(point_size*0.1,1.0e-10);
      if(!record.valid || record.event_id=="" ||
         StringFind(record.event_id,"MSZZSE2|")!=0)
         return Fail(candidate,"STRUCTURAL_BINDING_NOT_CERTIFIED");
      if(candidate.direction!=record.direction)
         return Fail(candidate,"STRUCTURAL_DIRECTION_MISMATCH");
      if(record.event_time>candidate.arm_time)
         return Fail(candidate,"STRUCTURAL_EVENT_AFTER_ARM");
      if(candidate.reference_type!=MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT ||
         candidate.reference_id!=record.event_id ||
         !CloseEnough(candidate.reference_price,
                      record.projected_level_event_bar,tolerance))
         return Fail(candidate,"STRUCTURAL_REFERENCE_MISMATCH");
      return true;
   }

   static bool ValidateCommon(MSZZResearchCandidateV2 &candidate,const double point_size)
   {
      if(candidate.schema_version!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2)
         return Fail(candidate,"UNSUPPORTED_SCHEMA_VERSION");
      if(candidate.strategy_id<=0 || candidate.family_id<=0)
         return Fail(candidate,"INVALID_ID_ALLOCATION");
      if(candidate.hypothesis_version=="" || candidate.canonical_variant_id=="")
         return Fail(candidate,"MISSING_HYPOTHESIS_IDENTITY");
      if(candidate.origin_id=="" || candidate.sequence_id=="" || candidate.event_id=="")
         return Fail(candidate,"MISSING_EVENT_IDENTITY");
      if(candidate.clock_domain!=MSZZ_RESEARCH_CLOCK_BROKER_SERVER_RAW ||
         candidate.time_authority_id!=MSZZ_RESEARCH_RAW_BROKER_AUTHORITY_V2)
         return Fail(candidate,"UNSUPPORTED_TIME_AUTHORITY");
      if(candidate.signal_time<=0 || candidate.trigger_time!=candidate.signal_time ||
         candidate.arm_time<=0 || candidate.arm_time>candidate.trigger_time ||
         candidate.expiry_time<=candidate.signal_time)
         return Fail(candidate,"INVALID_LIFECYCLE_TIME");
      if(candidate.direction!=MSZZ_DIR_LONG && candidate.direction!=MSZZ_DIR_SHORT)
         return Fail(candidate,"INVALID_DIRECTION");
      if(!Finite(candidate.entry) || !Finite(candidate.stop) || !Finite(candidate.target) ||
         candidate.entry<=0.0 || candidate.stop<=0.0 || candidate.target<=0.0)
         return Fail(candidate,"INVALID_GEOMETRY");
      if(candidate.direction==MSZZ_DIR_LONG &&
         (candidate.stop>=candidate.entry || candidate.target<=candidate.entry))
         return Fail(candidate,"INVALID_LONG_GEOMETRY");
      if(candidate.direction==MSZZ_DIR_SHORT &&
         (candidate.stop<=candidate.entry || candidate.target>=candidate.entry))
         return Fail(candidate,"INVALID_SHORT_GEOMETRY");
      if(!Finite(candidate.score))
         return Fail(candidate,"INVALID_SCORE");
      if(candidate.reference_type<MSZZ_RESEARCH_REFERENCE_NONE ||
         candidate.reference_type>MSZZ_RESEARCH_REFERENCE_RANGE)
         return Fail(candidate,"INVALID_REFERENCE_TYPE");
      if(candidate.reference_type!=MSZZ_RESEARCH_REFERENCE_NONE &&
         (candidate.reference_id=="" || !Finite(candidate.reference_price) ||
          candidate.reference_price<=0.0))
         return Fail(candidate,"INVALID_REFERENCE");
      if(candidate.bars_armed<0)
         return Fail(candidate,"INVALID_BARS_ARMED");
      if(candidate.terminal_prior_state<MSZZ_RESEARCH_TERMINAL_NONE ||
         candidate.terminal_prior_state>MSZZ_RESEARCH_TERMINAL_DAY_RESET)
         return Fail(candidate,"INVALID_TERMINAL_STATE");
      if(candidate.reset_classification<MSZZ_RESEARCH_RESET_NONE ||
         candidate.reset_classification>MSZZ_RESEARCH_RESET_NEW_EPISODE)
         return Fail(candidate,"INVALID_RESET_CLASSIFICATION");
      if(!Finite(candidate.atr_at_arm) || candidate.atr_at_arm<=0.0 ||
         !Finite(candidate.atr_at_trigger) || candidate.atr_at_trigger<=0.0)
         return Fail(candidate,"INVALID_ATR");
      if(point_size<=0.0 || !Finite(point_size))
         return Fail(candidate,"INVALID_POINT_SIZE");

      double risk=MathAbs(candidate.entry-candidate.stop);
      double expected_stop_points=risk/point_size;
      double expected_target_r=MathAbs(candidate.target-candidate.entry)/risk;
      double expected_spread_ratio=(candidate.spread_points*point_size)/risk;
      double tolerance=MathMax(1.0e-9,point_size*1.0e-6);
      if(!Finite(candidate.stop_distance_points) ||
         !CloseEnough(candidate.stop_distance_points,expected_stop_points,tolerance))
         return Fail(candidate,"STOP_DISTANCE_MISMATCH");
      if(!Finite(candidate.target_r) ||
         !CloseEnough(candidate.target_r,expected_target_r,1.0e-9))
         return Fail(candidate,"TARGET_R_MISMATCH");
      if(candidate.spread_points<0 || !Finite(candidate.spread_to_risk_ratio) ||
         !CloseEnough(candidate.spread_to_risk_ratio,expected_spread_ratio,1.0e-9))
         return Fail(candidate,"SPREAD_RISK_MISMATCH");
      if(candidate.session_id=="" || candidate.regime_id=="")
         return Fail(candidate,"MISSING_CONTEXT_ID");
      return true;
   }

   static bool ValidateFamily(MSZZResearchCandidateV2 &candidate,
                              const double point_size)
   {
      bool structural_family=(candidate.family_id==9 ||
                              candidate.family_id==10 ||
                              candidate.family_id==12);
      if(!structural_family && candidate.structural_binding.bound)
         return Fail(candidate,"UNEXPECTED_STRUCTURAL_BINDING");
      switch(candidate.family_id)
      {
         case 8:
            if(candidate.ssr.ssr_clock_rule_id=="" || candidate.ssr.ssr_range_id=="" ||
               candidate.ssr.ssr_range_high<=candidate.ssr.ssr_range_low ||
               candidate.ssr.ssr_sweep_extreme<=0.0 || candidate.ssr.ssr_reclaim_close<=0.0)
               return Fail(candidate,"INVALID_SSR_EXTENSION");
            return true;
         case 9:
            if(!ValidateStructuralBinding(candidate,point_size)) return false;
            {
               MSZZStructuralEventRecord record=
                  candidate.structural_binding.record;
               double tolerance=MathMax(point_size*0.1,1.0e-10);
               if(candidate.mc.mc_structural_event_id!=record.event_id ||
                  !CloseEnough(candidate.mc.mc_impulse_origin_price,
                               record.impulse_origin_price,tolerance) ||
                  !CloseEnough(candidate.mc.mc_impulse_extreme_price,
                               record.impulse_extreme_price,tolerance) ||
                  !CloseEnough(candidate.mc.mc_impulse_distance_atr,
                               record.impulse_distance_atr,1.0e-9))
                  return Fail(candidate,"MC_STRUCTURAL_BINDING_MISMATCH");
            }
            if(candidate.mc.mc_impulse_origin_price<=0.0 ||
               candidate.mc.mc_impulse_extreme_price<=0.0 ||
               candidate.mc.mc_impulse_distance_atr<=0.0 ||
               candidate.mc.mc_efficiency<0.0 || candidate.mc.mc_efficiency>1.0 ||
               candidate.mc.mc_pause_bars<0 ||
               candidate.mc.mc_pullback_fraction<0.0 || candidate.mc.mc_pullback_fraction>1.0)
               return Fail(candidate,"INVALID_MC_EXTENSION");
            return true;
         case 10:
            if(!ValidateStructuralBinding(candidate,point_size)) return false;
            {
               MSZZStructuralEventRecord record=
                  candidate.structural_binding.record;
               double tolerance=MathMax(point_size*0.1,1.0e-10);
               if(candidate.brc.brc_break_event_id!=record.event_id ||
                  candidate.brc.brc_broken_level_id!=record.broken_pivot_id ||
                  !CloseEnough(candidate.brc.brc_broken_level_price,
                               record.projected_level_event_bar,tolerance))
                  return Fail(candidate,"BRC_STRUCTURAL_BINDING_MISMATCH");
            }
            if(candidate.brc.brc_broken_level_id=="" ||
               candidate.brc.brc_broken_level_price<=0.0 ||
               candidate.brc.brc_first_touch_time<=candidate.arm_time ||
               candidate.brc.brc_rejection_time<candidate.brc.brc_first_touch_time ||
               candidate.brc.brc_penetration_atr<0.0 || candidate.brc.brc_test_count<0)
               return Fail(candidate,"INVALID_BRC_EXTENSION");
            return true;
         case 11:
            if(candidate.cbr.cbr_window_start<=0 ||
               candidate.cbr.cbr_window_end<=candidate.cbr.cbr_window_start ||
               candidate.cbr.cbr_window_end>=candidate.trigger_time ||
               candidate.cbr.cbr_window_hash=="" || candidate.cbr.cbr_short_atr<=0.0 ||
               candidate.cbr.cbr_long_atr<=0.0 || candidate.cbr.cbr_range_atr<=0.0 ||
               candidate.cbr.cbr_extension_atr<0.0 || candidate.cbr.cbr_obstruction_r<0.0)
               return Fail(candidate,"INVALID_CBR_EXTENSION");
            return true;
         case 12:
            if(!ValidateStructuralBinding(candidate,point_size)) return false;
            if(candidate.tp.tp_impulse_event_id!=
               candidate.structural_binding.record.event_id)
               return Fail(candidate,"TP_STRUCTURAL_BINDING_MISMATCH");
            if(candidate.tp.tp_value_type==MSZZ_RESEARCH_VALUE_NONE ||
               candidate.tp.tp_value_anchor_id=="" ||
               candidate.tp.tp_distance_start_atr<0.0 ||
               candidate.tp.tp_distance_min_atr<0.0 ||
               candidate.tp.tp_distance_trigger_atr<0.0)
               return Fail(candidate,"INVALID_TP_EXTENSION");
            return true;
         case 13:
            if(candidate.rr.rr_range_id=="" || candidate.rr.rr_width_cv<0.0 ||
               candidate.rr.rr_high_touch_ids=="" || candidate.rr.rr_low_touch_ids=="" ||
               candidate.rr.rr_min_touch_separation_bars<0 ||
               candidate.rr.rr_rotation_away_atr<0.0 ||
               !candidate.rr.rr_medium_contained || candidate.rr.rr_midpoint<=0.0)
               return Fail(candidate,"INVALID_RR_EXTENSION");
            return true;
      }
      return Fail(candidate,"UNKNOWN_RESEARCH_FAMILY");
   }

public:
   static void Initialize(MSZZResearchCandidateV2 &candidate)
   {
      BlankStorage(candidate);
      candidate.schema_version=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2;
      candidate.validation_reason="NOT_VALIDATED";
      candidate.clock_domain=MSZZ_RESEARCH_CLOCK_BROKER_SERVER_RAW;
      candidate.time_authority_id=MSZZ_RESEARCH_RAW_BROKER_AUTHORITY_V2;
   }

   static bool PopulateDerived(MSZZResearchCandidateV2 &candidate,
                               const double point_size)
   {
      if(point_size<=0.0 || !Finite(point_size) ||
         candidate.entry<=0.0 || candidate.stop<=0.0 ||
         candidate.entry==candidate.stop || candidate.spread_points<0)
         return Fail(candidate,"DERIVED_FIELD_INPUT_INVALID");
      double risk=MathAbs(candidate.entry-candidate.stop);
      candidate.stop_distance_points=risk/point_size;
      candidate.target_r=MathAbs(candidate.target-candidate.entry)/risk;
      candidate.spread_to_risk_ratio=(candidate.spread_points*point_size)/risk;
      return true;
   }

   static bool BindCertifiedStructuralEvent(MSZZResearchCandidateV2 &candidate,
                                            const MSZZStructuralEventRecord &record,
                                            const double point_size)
   {
      MSZZStructuralEventRecord certified=record;
      string reason="";
      if(!record.valid ||
         !CMSZZStructuralEventPolicy::Validate(certified,point_size,reason))
      {
         return Fail(candidate,"STRUCTURAL_BIND_FAILED_"+reason);
      }
      candidate.structural_binding.bound=true;
      candidate.structural_binding.record=certified;
      candidate.reference_type=MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT;
      candidate.reference_id=certified.event_id;
      candidate.reference_price=certified.projected_level_event_bar;
      return true;
   }

   static bool Validate(MSZZResearchCandidateV2 &candidate,const double point_size)
   {
      candidate.valid=false;
      candidate.validation_reason="NOT_VALIDATED";
      if(!ValidateCommon(candidate,point_size)) return false;
      if(!ValidateFamily(candidate,point_size)) return false;
      candidate.valid=true;
      candidate.validation_reason="OK";
      return true;
   }

   static string ReferenceToken(const ENUM_MSZZ_RESEARCH_REFERENCE_V2 value)
   {
      switch(value)
      {
         case MSZZ_RESEARCH_REFERENCE_NONE: return "NONE";
         case MSZZ_RESEARCH_REFERENCE_SESSION_RANGE: return "SESSION_RANGE";
         case MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT: return "STRUCTURAL_EVENT";
         case MSZZ_RESEARCH_REFERENCE_COMPRESSION_WINDOW: return "COMPRESSION_WINDOW";
         case MSZZ_RESEARCH_REFERENCE_VALUE: return "VALUE";
         case MSZZ_RESEARCH_REFERENCE_RANGE: return "RANGE";
      }
      return "INVALID";
   }

   static string TerminalToken(const ENUM_MSZZ_RESEARCH_TERMINAL_STATE_V2 value)
   {
      switch(value)
      {
         case MSZZ_RESEARCH_TERMINAL_NONE: return "NONE";
         case MSZZ_RESEARCH_TERMINAL_EXPIRED: return "EXPIRED";
         case MSZZ_RESEARCH_TERMINAL_INVALIDATED: return "INVALIDATED";
         case MSZZ_RESEARCH_TERMINAL_EMITTED: return "EMITTED";
         case MSZZ_RESEARCH_TERMINAL_SESSION_RESET: return "SESSION_RESET";
         case MSZZ_RESEARCH_TERMINAL_DAY_RESET: return "DAY_RESET";
      }
      return "INVALID";
   }

   static string ResetToken(const ENUM_MSZZ_RESEARCH_RESET_V2 value)
   {
      switch(value)
      {
         case MSZZ_RESEARCH_RESET_NONE: return "NONE";
         case MSZZ_RESEARCH_RESET_FRESH_CROSS: return "FRESH_CROSS";
         case MSZZ_RESEARCH_RESET_NEUTRAL: return "NEUTRAL";
         case MSZZ_RESEARCH_RESET_SESSION: return "SESSION";
         case MSZZ_RESEARCH_RESET_DAY: return "DAY";
         case MSZZ_RESEARCH_RESET_NEW_STRUCTURE: return "NEW_STRUCTURE";
         case MSZZ_RESEARCH_RESET_NEW_EPISODE: return "NEW_EPISODE";
      }
      return "INVALID";
   }

   static string ValueToken(const ENUM_MSZZ_RESEARCH_VALUE_V2 value)
   {
      switch(value)
      {
         case MSZZ_RESEARCH_VALUE_NONE: return "NONE";
         case MSZZ_RESEARCH_VALUE_VWAP_SESSION: return "VWAP_SESSION";
         case MSZZ_RESEARCH_VALUE_ALMA: return "ALMA";
      }
      return "INVALID";
   }

   static string ClockDomainToken(const ENUM_MSZZ_RESEARCH_CLOCK_DOMAIN_V2 value)
   {
      switch(value)
      {
         case MSZZ_RESEARCH_CLOCK_NONE: return "NONE";
         case MSZZ_RESEARCH_CLOCK_BROKER_SERVER_RAW: return "BROKER_SERVER_RAW";
         case MSZZ_RESEARCH_CLOCK_UTC_CONVERTED: return "UTC_CONVERTED";
      }
      return "INVALID";
   }
};

#endif
