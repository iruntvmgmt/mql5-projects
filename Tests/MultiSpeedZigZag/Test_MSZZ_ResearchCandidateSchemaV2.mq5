#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ResearchCandidateSchemaV2.mqh>
#include <MultiSpeedZigZag/Research/ResearchCandidateCsvV2.mqh>

int g_failures=0;

void Check(const bool condition,const string name)
{
   if(condition) Print("PASS: ",name);
   else { Print("FAIL: ",name); g_failures++; }
}

void Common(MSZZResearchCandidateV2 &c,const int family_id)
{
   CMSZZResearchCandidateSchemaV2::Initialize(c);
   c.strategy_id=1200+(family_id-8);
   c.family_id=family_id;
   c.hypothesis_version="V2-FROZEN";
   c.canonical_variant_id="CANONICAL";
   c.origin_id="ORIGIN";
   c.sequence_id="SEQUENCE";
   c.event_id="EVENT|FINAL";
   c.arm_time=D'2026.01.05 09:55:00';
   c.trigger_time=D'2026.01.05 10:00:00';
   c.signal_time=c.trigger_time;
   c.expiry_time=D'2026.01.05 10:15:00';
   c.direction=MSZZ_DIR_LONG;
   c.entry=100.0;
   c.stop=99.0;
   c.target=102.0;
   c.score=1.0;
   c.reference_type=MSZZ_RESEARCH_REFERENCE_SESSION_RANGE;
   c.reference_id="REFERENCE";
   c.reference_price=99.5;
   c.bars_armed=1;
   c.terminal_prior_state=MSZZ_RESEARCH_TERMINAL_NONE;
   c.reset_classification=MSZZ_RESEARCH_RESET_FRESH_CROSS;
   c.atr_at_arm=2.0;
   c.atr_at_trigger=2.1;
   c.spread_points=10;
   c.session_id="SESSION_TABLE_V1|LONDON";
   c.regime_id="REGIME|1";
   c.diagnostic_json="{\"note\":\"comma,quote\\\"\"}";
   CMSZZResearchCandidateSchemaV2::PopulateDerived(c,0.01);
}

void ValidSSR()
{
   MSZZResearchCandidateV2 c; Common(c,8);
   c.ssr.ssr_clock_rule_id="SESSION_TABLE_V1";
   c.ssr.ssr_range_id="ASIA|20260105";
   c.ssr.ssr_range_high=101.0;
   c.ssr.ssr_range_low=99.0;
   c.ssr.ssr_sweep_extreme=98.8;
   c.ssr.ssr_reclaim_close=100.0;
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),"valid SSR v2 candidate");
   Check(c.valid && c.validation_reason=="OK","successful validation certifies candidate");

   string row=CMSZZResearchCandidateCsvV2::Row(c);
   Check(StringFind(row,"\"MSZZ_RESEARCH_CANDIDATE_V2\"")==0,"row begins with quoted schema");
   Check(StringFind(row,"\"2026-01-05T10:00:00Z\"")>=0,"timestamps use ISO-8601 UTC form");
   Check(StringFind(row,"comma,quote")>=0 && StringFind(row,"\"\"")>=0,
         "RFC-4180 quotes embedded evidence");
}

void CommonFailures()
{
   MSZZResearchCandidateV2 c; Common(c,8);
   c.ssr.ssr_clock_rule_id="CLOCK"; c.ssr.ssr_range_id="RANGE";
   c.ssr.ssr_range_high=2.0; c.ssr.ssr_range_low=1.0;
   c.ssr.ssr_sweep_extreme=1.0; c.ssr.ssr_reclaim_close=1.5;

   c.sequence_id="";
   Check(!CMSZZResearchCandidateSchemaV2::Validate(c,0.01) &&
         c.validation_reason=="MISSING_EVENT_IDENTITY","missing sequence fails closed");

   Common(c,8); c.ssr.ssr_clock_rule_id="CLOCK"; c.ssr.ssr_range_id="RANGE";
   c.ssr.ssr_range_high=2.0; c.ssr.ssr_range_low=1.0;
   c.ssr.ssr_sweep_extreme=1.0; c.ssr.ssr_reclaim_close=1.5;
   c.stop_distance_points+=1.0;
   Check(!CMSZZResearchCandidateSchemaV2::Validate(c,0.01) &&
         c.validation_reason=="STOP_DISTANCE_MISMATCH","derived geometry mismatch fails closed");

   Common(c,8); c.ssr.ssr_clock_rule_id="CLOCK"; c.ssr.ssr_range_id="RANGE";
   c.ssr.ssr_range_high=2.0; c.ssr.ssr_range_low=1.0;
   c.ssr.ssr_sweep_extreme=1.0; c.ssr.ssr_reclaim_close=1.5;
   c.expiry_time=c.signal_time;
   Check(!CMSZZResearchCandidateSchemaV2::Validate(c,0.01) &&
         c.validation_reason=="INVALID_LIFECYCLE_TIME","invalid lifecycle fails closed");
}

void StructuralOwnership()
{
   MSZZResearchCandidateV2 c; Common(c,9);
   c.reference_type=MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT;
   c.reference_id="MSZZSE2|REFERENCE";
   c.mc.mc_structural_event_id="MSZZSE1|HISTORICAL";
   c.mc.mc_impulse_origin_price=98.0;
   c.mc.mc_impulse_extreme_price=101.0;
   c.mc.mc_impulse_distance_atr=1.5;
   c.mc.mc_efficiency=0.8;
   c.mc.mc_pause_bars=2;
   c.mc.mc_pullback_fraction=0.3;
   Check(!CMSZZResearchCandidateSchemaV2::Validate(c,0.01) &&
         c.validation_reason=="MC_REQUIRES_MSZZSE2","MSZZSE1 rejected as historical only");

   c.mc.mc_structural_event_id="MSZZSE2|CERTIFIED";
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),
         "MC extension consumes certified MSZZSE2 identity");

   MSZZStructuralEventRecord record; ZeroMemory(record);
   record.valid=true; record.event_id="MSZZSE2|COPIED";
   string copied="";
   Check(CMSZZResearchCandidateSchemaV2::CopyCertifiedStructuralEvent(record,copied) &&
         copied=="MSZZSE2|COPIED","certified structural event copy");
   record.event_id="MSZZSE1|OLD";
   Check(!CMSZZResearchCandidateSchemaV2::CopyCertifiedStructuralEvent(record,copied) &&
         copied=="","historical identity cannot enter v2 typed schema");
}

void AllFamilyExtensions()
{
   MSZZResearchCandidateV2 c;

   Common(c,10);
   c.brc.brc_break_event_id="MSZZSE2|BRC";
   c.brc.brc_broken_level_id="PIVOT|HIGH";
   c.brc.brc_broken_level_price=100.0;
   c.brc.brc_first_touch_time=D'2026.01.05 09:56:00';
   c.brc.brc_rejection_time=D'2026.01.05 09:57:00';
   c.brc.brc_penetration_atr=0.1; c.brc.brc_test_count=1;
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),"valid BRC extension");

   Common(c,11);
   c.cbr.cbr_window_start=D'2026.01.05 09:00:00';
   c.cbr.cbr_window_end=D'2026.01.05 09:50:00';
   c.cbr.cbr_window_hash="SHA256";
   c.cbr.cbr_short_atr=1.0; c.cbr.cbr_long_atr=2.0; c.cbr.cbr_range_atr=1.0;
   c.cbr.cbr_extension_atr=0.2; c.cbr.cbr_obstruction_r=1.5;
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),"valid CBR extension");

   Common(c,12);
   c.tp.tp_impulse_event_id="MSZZSE2|TP";
   c.tp.tp_value_type=MSZZ_RESEARCH_VALUE_VWAP_SESSION;
   c.tp.tp_value_anchor_id="VWAP|SESSION";
   c.tp.tp_distance_start_atr=1.0; c.tp.tp_distance_min_atr=0.2;
   c.tp.tp_distance_trigger_atr=0.4;
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),"valid TP extension");

   Common(c,13);
   c.rr.rr_range_id="RANGE"; c.rr.rr_width_cv=0.1;
   c.rr.rr_high_touch_ids="H1,H2"; c.rr.rr_low_touch_ids="L1,L2";
   c.rr.rr_min_touch_separation_bars=3; c.rr.rr_rotation_away_atr=0.5;
   c.rr.rr_medium_contained=true; c.rr.rr_midpoint=100.0;
   Check(CMSZZResearchCandidateSchemaV2::Validate(c,0.01),"valid RR extension");
}

void JournalGate()
{
   string file_name="MSZZ_ResearchCandidateSchemaV2_Test_Fresh.csv";
   FileDelete(file_name);
   MSZZResearchCandidateV2 invalid; Common(invalid,8);
   Check(!CMSZZResearchCandidateCsvV2::AppendValidated(file_name,invalid,0.01),
         "journal rejects missing family evidence");
   Check(!FileIsExist(file_name),"invalid evidence creates no journal");

   MSZZResearchCandidateV2 valid; Common(valid,8);
   valid.ssr.ssr_clock_rule_id="CLOCK"; valid.ssr.ssr_range_id="RANGE";
   valid.ssr.ssr_range_high=2.0; valid.ssr.ssr_range_low=1.0;
   valid.ssr.ssr_sweep_extreme=1.0; valid.ssr.ssr_reclaim_close=1.5;
   Check(CMSZZResearchCandidateCsvV2::AppendValidated(file_name,valid,0.01),
         "validated evidence writes journal");
   Check(FileIsExist(file_name),"validated journal exists");
}

void WriteSummary()
{
   int h=FileOpen("MSZZ_ResearchCandidateSchemaV2_TestSummary.csv",
                  FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"failures","result");
   FileWrite(h,g_failures,(g_failures==0 ? "PASS" : "FAIL"));
   FileClose(h);
}

void OnStart()
{
   Print("MSZZ ResearchCandidateSchemaV2 tests begin");
   ValidSSR();
   Print("MSZZ ResearchCandidateSchemaV2 ValidSSR complete");
   CommonFailures();
   Print("MSZZ ResearchCandidateSchemaV2 CommonFailures complete");
   StructuralOwnership();
   Print("MSZZ ResearchCandidateSchemaV2 StructuralOwnership complete");
   AllFamilyExtensions();
   Print("MSZZ ResearchCandidateSchemaV2 AllFamilyExtensions complete");
   JournalGate();
   Print("MSZZ ResearchCandidateSchemaV2 JournalGate complete");
   WriteSummary();
   Print("MSZZ ResearchCandidateSchemaV2 tests failures=",g_failures);
}
