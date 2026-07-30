#ifndef __MSZZ_RESEARCH_CANDIDATE_CSV_V2_MQH__
#define __MSZZ_RESEARCH_CANDIDATE_CSV_V2_MQH__

#include <MultiSpeedZigZag/Research/ResearchCandidateSchemaV2.mqh>

class CMSZZResearchCandidateCsvV2
{
private:
   static string Quote(const string value)
   {
      string escaped="";
      int length=StringLen(value);
      for(int i=0;i<length;i++)
      {
         string character=StringSubstr(value,i,1);
         escaped+=(character=="\"" ? "\"\"" : character);
      }
      return "\""+escaped+"\"";
   }

   static string Number(const double value,const int digits=16)
   {
      return DoubleToString(value,digits);
   }

   static string TimeRaw(const datetime value)
   {
      return IntegerToString((long)value);
   }

   static void Add(string &row,const string value)
   {
      if(row!="") row+=",";
      row+=Quote(value);
   }

   static void Empty(string &row,const int count)
   {
      for(int i=0;i<count;i++) Add(row,"");
   }

public:
   static string Header()
   {
      return "schema_version,strategy_id,family_id,hypothesis_version,canonical_variant_id,"
             "origin_id,sequence_id,event_id,clock_domain,time_authority_id,"
             "signal_time_raw,expiry_time_raw,direction,entry,stop,target,"
             "score,reference_type,reference_id,reference_price,arm_time_raw,trigger_time_raw,bars_armed,"
             "terminal_prior_state,reset_classification,atr_at_arm,atr_at_trigger,"
             "stop_distance_points,target_r,spread_points,spread_to_risk_ratio,session_id,regime_id,"
             "diagnostic_json,structural_event_id,structural_speed,structural_direction,"
             "structural_event_time_raw,structural_previous_bar_time_raw,"
             "structural_origin_pivot_id,structural_origin_pivot_speed,"
             "structural_origin_pivot_kind,structural_origin_price,"
             "structural_origin_pivot_time_raw,structural_origin_confirmation_time_raw,"
             "structural_broken_pivot_id,structural_broken_pivot_speed,"
             "structural_broken_pivot_kind,structural_broken_pivot_price,"
             "structural_broken_pivot_time_raw,structural_broken_confirmation_time_raw,"
             "structural_anchor_1_id,structural_anchor_1_speed,structural_anchor_1_kind,"
             "structural_anchor_1_price,structural_anchor_1_time_raw,"
             "structural_anchor_1_confirmation_time_raw,structural_anchor_2_id,"
             "structural_anchor_2_speed,structural_anchor_2_kind,structural_anchor_2_price,"
             "structural_anchor_2_time_raw,structural_anchor_2_confirmation_time_raw,"
             "structural_projected_level_previous_bar,structural_projected_level_event_bar,"
             "structural_break_close_previous_bar,structural_break_close_price,"
             "structural_break_distance,structural_break_distance_atr,"
             "structural_impulse_origin_price,structural_impulse_extreme_price,"
             "structural_impulse_distance,structural_impulse_distance_atr,"
             "structural_atr_at_event,"
             "ssr_clock_rule_id,ssr_range_id,ssr_range_high,ssr_range_low,"
             "ssr_sweep_extreme,ssr_reclaim_close,mc_structural_event_id,mc_impulse_origin_price,"
             "mc_impulse_extreme_price,mc_impulse_distance_atr,mc_efficiency,mc_pause_bars,"
             "mc_pullback_fraction,brc_break_event_id,brc_broken_level_id,brc_broken_level_price,"
             "brc_first_touch_time_raw,brc_rejection_time_raw,brc_penetration_atr,brc_test_count,"
             "cbr_window_start_raw,cbr_window_end_raw,cbr_window_hash,cbr_short_atr,cbr_long_atr,"
             "cbr_range_atr,cbr_extension_atr,cbr_obstruction_r,tp_impulse_event_id,tp_value_type,"
             "tp_value_anchor_id,tp_distance_start_atr,tp_distance_min_atr,tp_distance_trigger_atr,"
             "rr_range_id,rr_width_cv,rr_high_touch_ids,rr_low_touch_ids,"
             "rr_min_touch_separation_bars,rr_rotation_away_atr,rr_medium_contained,rr_midpoint";
   }

   static string Row(const MSZZResearchCandidateV2 &c)
   {
      string row="";
      Add(row,c.schema_version); Add(row,IntegerToString(c.strategy_id));
      Add(row,IntegerToString(c.family_id)); Add(row,c.hypothesis_version);
      Add(row,c.canonical_variant_id); Add(row,c.origin_id); Add(row,c.sequence_id);
      Add(row,c.event_id);
      Add(row,CMSZZResearchCandidateSchemaV2::ClockDomainToken(c.clock_domain));
      Add(row,c.time_authority_id);
      Add(row,TimeRaw(c.signal_time)); Add(row,TimeRaw(c.expiry_time));
      Add(row,MSZZDirectionText(c.direction)); Add(row,Number(c.entry)); Add(row,Number(c.stop));
      Add(row,Number(c.target)); Add(row,Number(c.score));
      Add(row,CMSZZResearchCandidateSchemaV2::ReferenceToken(c.reference_type));
      Add(row,c.reference_id); Add(row,Number(c.reference_price));
      Add(row,TimeRaw(c.arm_time)); Add(row,TimeRaw(c.trigger_time));
      Add(row,IntegerToString(c.bars_armed));
      Add(row,CMSZZResearchCandidateSchemaV2::TerminalToken(c.terminal_prior_state));
      Add(row,CMSZZResearchCandidateSchemaV2::ResetToken(c.reset_classification));
      Add(row,Number(c.atr_at_arm)); Add(row,Number(c.atr_at_trigger));
      Add(row,Number(c.stop_distance_points)); Add(row,Number(c.target_r));
      Add(row,IntegerToString(c.spread_points)); Add(row,Number(c.spread_to_risk_ratio));
      Add(row,c.session_id); Add(row,c.regime_id); Add(row,c.diagnostic_json);
      if(c.structural_binding.bound)
      {
         MSZZStructuralEventRecord r=c.structural_binding.record;
         Add(row,r.event_id); Add(row,IntegerToString((int)r.speed));
         Add(row,MSZZDirectionText(r.direction)); Add(row,TimeRaw(r.event_time));
         Add(row,TimeRaw(r.previous_bar_time)); Add(row,r.source_origin_pivot_id);
         Add(row,IntegerToString((int)r.source_origin_pivot_speed));
         Add(row,IntegerToString((int)r.source_origin_pivot_kind));
         Add(row,Number(r.source_origin_price)); Add(row,TimeRaw(r.source_origin_pivot_time));
         Add(row,TimeRaw(r.source_origin_confirmation_time)); Add(row,r.broken_pivot_id);
         Add(row,IntegerToString((int)r.broken_pivot_speed));
         Add(row,IntegerToString((int)r.broken_pivot_kind));
         Add(row,Number(r.broken_pivot_price)); Add(row,TimeRaw(r.broken_pivot_time));
         Add(row,TimeRaw(r.broken_pivot_confirmation_time));
         Add(row,r.projection_anchor_1_id);
         Add(row,IntegerToString((int)r.projection_anchor_1_speed));
         Add(row,IntegerToString((int)r.projection_anchor_1_kind));
         Add(row,Number(r.projection_anchor_1_price));
         Add(row,TimeRaw(r.projection_anchor_1_time));
         Add(row,TimeRaw(r.projection_anchor_1_confirmation_time));
         Add(row,r.projection_anchor_2_id);
         Add(row,IntegerToString((int)r.projection_anchor_2_speed));
         Add(row,IntegerToString((int)r.projection_anchor_2_kind));
         Add(row,Number(r.projection_anchor_2_price));
         Add(row,TimeRaw(r.projection_anchor_2_time));
         Add(row,TimeRaw(r.projection_anchor_2_confirmation_time));
         Add(row,Number(r.projected_level_previous_bar));
         Add(row,Number(r.projected_level_event_bar));
         Add(row,Number(r.break_close_previous_bar)); Add(row,Number(r.break_close_price));
         Add(row,Number(r.break_distance)); Add(row,Number(r.break_distance_atr));
         Add(row,Number(r.impulse_origin_price)); Add(row,Number(r.impulse_extreme_price));
         Add(row,Number(r.impulse_distance)); Add(row,Number(r.impulse_distance_atr));
         Add(row,Number(r.atr_at_event));
      }
      else Empty(row,40);
      if(c.family_id==8)
      {
         Add(row,c.ssr.ssr_clock_rule_id); Add(row,c.ssr.ssr_range_id);
         Add(row,Number(c.ssr.ssr_range_high)); Add(row,Number(c.ssr.ssr_range_low));
         Add(row,Number(c.ssr.ssr_sweep_extreme)); Add(row,Number(c.ssr.ssr_reclaim_close));
      }
      else Empty(row,6);
      if(c.family_id==9)
      {
         Add(row,c.mc.mc_structural_event_id); Add(row,Number(c.mc.mc_impulse_origin_price));
         Add(row,Number(c.mc.mc_impulse_extreme_price)); Add(row,Number(c.mc.mc_impulse_distance_atr));
         Add(row,Number(c.mc.mc_efficiency)); Add(row,IntegerToString(c.mc.mc_pause_bars));
         Add(row,Number(c.mc.mc_pullback_fraction));
      }
      else Empty(row,7);
      if(c.family_id==10)
      {
         Add(row,c.brc.brc_break_event_id); Add(row,c.brc.brc_broken_level_id);
         Add(row,Number(c.brc.brc_broken_level_price)); Add(row,TimeRaw(c.brc.brc_first_touch_time));
         Add(row,TimeRaw(c.brc.brc_rejection_time)); Add(row,Number(c.brc.brc_penetration_atr));
         Add(row,IntegerToString(c.brc.brc_test_count));
      }
      else Empty(row,7);
      if(c.family_id==11)
      {
         Add(row,TimeRaw(c.cbr.cbr_window_start)); Add(row,TimeRaw(c.cbr.cbr_window_end));
         Add(row,c.cbr.cbr_window_hash); Add(row,Number(c.cbr.cbr_short_atr));
         Add(row,Number(c.cbr.cbr_long_atr)); Add(row,Number(c.cbr.cbr_range_atr));
         Add(row,Number(c.cbr.cbr_extension_atr)); Add(row,Number(c.cbr.cbr_obstruction_r));
      }
      else Empty(row,8);
      if(c.family_id==12)
      {
         Add(row,c.tp.tp_impulse_event_id);
         Add(row,CMSZZResearchCandidateSchemaV2::ValueToken(c.tp.tp_value_type));
         Add(row,c.tp.tp_value_anchor_id); Add(row,Number(c.tp.tp_distance_start_atr));
         Add(row,Number(c.tp.tp_distance_min_atr)); Add(row,Number(c.tp.tp_distance_trigger_atr));
      }
      else Empty(row,6);
      if(c.family_id==13)
      {
         Add(row,c.rr.rr_range_id); Add(row,Number(c.rr.rr_width_cv));
         Add(row,c.rr.rr_high_touch_ids); Add(row,c.rr.rr_low_touch_ids);
         Add(row,IntegerToString(c.rr.rr_min_touch_separation_bars));
         Add(row,Number(c.rr.rr_rotation_away_atr));
         Add(row,(c.rr.rr_medium_contained ? "true" : "false"));
         Add(row,Number(c.rr.rr_midpoint));
      }
      else Empty(row,8);
      return row;
   }

   static bool AppendValidated(const string file_name,MSZZResearchCandidateV2 &candidate,
                               const double point_size)
   {
      if(!CMSZZResearchCandidateSchemaV2::Validate(candidate,point_size)) return false;
      int handle=FileOpen(file_name,FILE_READ|FILE_WRITE|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(handle==INVALID_HANDLE)
      {
         candidate.valid=false;
         candidate.validation_reason="JOURNAL_OPEN_FAILED";
         return false;
      }
      if(FileSize(handle)==0)
         FileWriteString(handle,Header()+"\r\n");
      FileSeek(handle,0,SEEK_END);
      FileWriteString(handle,Row(candidate)+"\r\n");
      FileFlush(handle);
      FileClose(handle);
      return true;
   }
};

#endif
