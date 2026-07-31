#ifndef __MSZZ_SCREENING_SIMULATOR_V2_MQH__
#define __MSZZ_SCREENING_SIMULATOR_V2_MQH__

// Family-neutral standalone historical screening simulator (MSZZ_SCREENING_OUTCOME_V2).
// Exact MQL5 mirror of screening_simulator_v2.py. Semantic authority is the
// certified ScreeningExecutionPolicyV2 (CandidateStatus, NormalizeStop,
// NormalizeTarget, ResolveBar, GrossR). The outcome record is integer-encoded
// (prices as point counts, R as 1e-9 units by exact integer arithmetic) so the
// canonical outcome bytes/SHA are byte-identical across MQL5 and Python.

#include <MultiSpeedZigZag/Research/ScreeningMarketV2.mqh>
#include <MultiSpeedZigZag/Research/ScreeningExecutionPolicyV2.mqh>

#define MSZZ_SCREENING_OUTCOME_V2 "MSZZ_SCREENING_OUTCOME_V2"
#define MSZZ_SCREENING_R_SCALE    1000000000
#define MSZZ_SCREENING_GRID_TOL_PTS 1.0e-6
#define MSZZ_SCREENING_R_TOL      1.0e-9

// per-candidate status / rejection tokens
#define MSZZ_SIM_ACCEPTED                    "ACCEPTED"
#define MSZZ_SIM_REJECT_FAMILY_OPEN          "REJECT_FAMILY_OPEN"
#define MSZZ_SIM_REJECT_EXPIRED              "REJECT_EXPIRED"
#define MSZZ_SIM_REJECT_INVALID_GEOMETRY     "REJECT_INVALID_GEOMETRY"
#define MSZZ_SIM_REJECT_CANDIDATE_OFF_GRID   "REJECT_CANDIDATE_OFF_GRID"
#define MSZZ_SIM_REJECT_NO_NEXT_EXECUTABLE_BAR "REJECT_NO_NEXT_EXECUTABLE_BAR"
#define MSZZ_SIM_REJECT_ENTRY_AFTER_TEST_END "REJECT_ENTRY_AFTER_TEST_END"
// dataset-level run-status tokens
#define MSZZ_SIM_RUN_OK                      "RUN_OK"
#define MSZZ_SIM_REJECT_UNSUPPORTED_POLICY   "REJECT_UNSUPPORTED_POLICY"
#define MSZZ_SIM_REJECT_SOURCE_HASH_MISMATCH "REJECT_SOURCE_HASH_MISMATCH"
#define MSZZ_SIM_REJECT_MARKET_HASH_MISMATCH "REJECT_MARKET_HASH_MISMATCH"
#define MSZZ_SIM_REJECT_JOURNAL_MANIFEST_INVALID "REJECT_JOURNAL_MANIFEST_INVALID"
#define MSZZ_SIM_REJECT_SYMBOL_MISMATCH      "REJECT_SYMBOL_MISMATCH"
#define MSZZ_SIM_REJECT_TIMEFRAME_MISMATCH   "REJECT_TIMEFRAME_MISMATCH"
#define MSZZ_SIM_REJECT_CLOCK_DOMAIN_MISMATCH "REJECT_CLOCK_DOMAIN_MISMATCH"
#define MSZZ_SIM_REJECT_TIME_AUTHORITY_MISMATCH "REJECT_TIME_AUTHORITY_MISMATCH"
#define MSZZ_SIM_REJECT_INSTRUMENT_PARAMS_MISMATCH "REJECT_INSTRUMENT_PARAMS_MISMATCH"
#define MSZZ_SIM_EXIT_STOP                   "STOP"
#define MSZZ_SIM_EXIT_TARGET                 "TARGET"
#define MSZZ_SIM_EXIT_TEST_END               "TEST_END"

struct MSZZScreeningCandidateV2
{
   int      strategy_id;
   int      family_id;
   string   hypothesis_version;
   string   canonical_variant_id;
   string   origin_id;
   string   sequence_id;
   string   event_id;
   string   clock_domain;
   string   time_authority_id;
   long     signal_time;
   long     expiry_time;
   int      direction;   // +1 long, -1 short
   double   entry;
   double   stop;
   double   target;
   double   target_r;
   double   stop_distance_points;
};

struct MSZZScreeningCandidateManifestV2
{
   string symbol;
   int    timeframe;
   string journal_sha256;
   string source_data_sha256;
};

struct MSZZScreeningOutcomeV2
{
   string outcome_version;
   string policy_id;
   int    strategy_id;
   int    family_id;
   string hypothesis_version;
   string canonical_variant_id;
   string origin_id;
   string sequence_id;
   string event_id;
   long   signal_time_raw;
   long   expiry_time_raw;
   long   entry_time_raw;
   long   exit_time_raw;
   string direction;
   long   candidate_entry_points;
   long   candidate_stop_points;
   long   candidate_target_points;
   long   candidate_target_r_1e9;
   long   executable_entry_points;
   long   normalized_stop_points;
   long   reconstructed_target_points;
   long   executable_exit_points;
   long   initial_risk_points;
   long   spread_points_at_entry;
   long   spread_points_at_exit;
   string status;
   string rejection_reason;
   string exit_reason;
   string stop_first_collision;
   long   gross_r_1e9;
   long   mfe_r_1e9;
   long   mae_r_1e9;
   long   holding_bars;
   string symbol;
   int    timeframe;
   string clock_domain;
   string time_authority_id;
   string source_data_sha256;
   string candidate_journal_sha256;
   string market_data_sha256;
   string instrument_params_sha256;
};

class CMSZZScreeningSimulatorV2
{
private:
   static long RoundRatio(const long num,const long den)
   {
      if(den<=0) return 0;
      if(num>=0) return (num + den/2)/den;
      return -((-num + den/2)/den);
   }
   static long RoundScale(const double x)
   {
      return (x>=0.0 ? (long)(x+0.5) : -(long)(-x+0.5));
   }
   static long PointsRound(const double price,const double point_size)
   {
      double ratio=price/point_size;
      return (ratio>=0.0 ? (long)(ratio+0.5) : -(long)(-ratio+0.5));
   }
   static long PointsExact(const double price,const double point_size,bool &ok)
   {
      double ratio=price/point_size;
      long nearest=PointsRound(price,point_size);
      if(MathAbs(ratio-nearest)>MSZZ_SCREENING_GRID_TOL_PTS) { ok=false; return 0; }
      ok=true; return nearest;
   }
   static string DirToken(const int direction) { return (direction>0 ? "LONG" : "SHORT"); }
   static bool IsSha256(const string v)
   {
      if(StringLen(v)!=64) return false;
      for(int i=0;i<64;i++)
      { ushort c=StringGetCharacter(v,i);
        if(!((c>='0'&&c<='9')||(c>='a'&&c<='f'))) return false; }
      return true;
   }
   static string Quote(const string value)
   {
      string e="";
      for(int i=0;i<StringLen(value);i++)
      { string ch=StringSubstr(value,i,1); e+=(ch=="\"" ? "\"\"" : ch); }
      return "\""+e+"\"";
   }
   static string CanonicalRecord(const string &fields[])
   {
      string r="";
      for(int i=0;i<ArraySize(fields);i++) { if(i>0) r+=","; r+=Quote(fields[i]); }
      return r;
   }
   // stable comparator: signal_time, family_id, event_id bytewise, sequence_id bytewise
   static bool Less(const MSZZScreeningCandidateV2 &a,const MSZZScreeningCandidateV2 &b)
   {
      if(a.signal_time!=b.signal_time) return a.signal_time<b.signal_time;
      if(a.family_id!=b.family_id) return a.family_id<b.family_id;
      int e=StringCompare(a.event_id,b.event_id,true);
      if(e!=0) return e<0;
      int s=StringCompare(a.sequence_id,b.sequence_id,true);
      return s<0;
   }
   static void StableSort(MSZZScreeningCandidateV2 &c[])
   {
      int n=ArraySize(c);
      for(int i=1;i<n;i++)
      {
         MSZZScreeningCandidateV2 key=c[i];
         int j=i-1;
         while(j>=0 && Less(key,c[j])) { c[j+1]=c[j]; j--; }
         c[j+1]=key;
      }
   }
   static void BlankOutcome(MSZZScreeningOutcomeV2 &o,const MSZZScreeningCandidateV2 &c,
                            const MSZZScreeningCandidateManifestV2 &cm,const string market_sha,
                            const string params_sha,const string status,
                            const long ce,const long cs,const long ct,const long tr)
   {
      o.outcome_version=MSZZ_SCREENING_OUTCOME_V2; o.policy_id="MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST";
      o.strategy_id=c.strategy_id; o.family_id=c.family_id;
      o.hypothesis_version=c.hypothesis_version; o.canonical_variant_id=c.canonical_variant_id;
      o.origin_id=c.origin_id; o.sequence_id=c.sequence_id; o.event_id=c.event_id;
      o.signal_time_raw=c.signal_time; o.expiry_time_raw=c.expiry_time;
      o.entry_time_raw=0; o.exit_time_raw=0; o.direction=DirToken(c.direction);
      o.candidate_entry_points=ce; o.candidate_stop_points=cs; o.candidate_target_points=ct;
      o.candidate_target_r_1e9=tr;
      o.executable_entry_points=0; o.normalized_stop_points=0; o.reconstructed_target_points=0;
      o.executable_exit_points=0; o.initial_risk_points=0;
      o.spread_points_at_entry=0; o.spread_points_at_exit=0;
      o.status=status; o.rejection_reason=status; o.exit_reason=""; o.stop_first_collision="false";
      o.gross_r_1e9=0; o.mfe_r_1e9=0; o.mae_r_1e9=0; o.holding_bars=0;
      o.symbol=cm.symbol; o.timeframe=cm.timeframe;
      o.clock_domain=MSZZ_SCREENING_CLOCK_DOMAIN; o.time_authority_id=MSZZ_SCREENING_TIME_AUTHORITY;
      o.source_data_sha256=cm.source_data_sha256; o.candidate_journal_sha256=cm.journal_sha256;
      o.market_data_sha256=market_sha; o.instrument_params_sha256=params_sha;
   }

   static string DatasetIdentity(MSZZScreeningCandidateV2 &candidates[],
                                 const MSZZScreeningCandidateManifestV2 &cm,
                                 const string market_symbol,const int market_tf,
                                 const string market_sha,const long market_rows,
                                 const MSZZScreeningMarketManifestV2 &mm,
                                 const MSZZScreeningInstrumentParamsV2 &params,
                                 const string policy_id)
   {
      if(policy_id!="MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST") return MSZZ_SIM_REJECT_UNSUPPORTED_POLICY;
      MSZZScreeningPolicyV2 p=CMSZZScreeningExecutionPolicyV2::Canonical();
      string preason="";
      if(!CMSZZScreeningExecutionPolicyV2::Validate(p,preason)) return MSZZ_SIM_REJECT_UNSUPPORTED_POLICY;
      if(mm.symbol!=market_symbol) return MSZZ_SIM_REJECT_SYMBOL_MISMATCH;
      if(mm.timeframe!=market_tf) return MSZZ_SIM_REJECT_TIMEFRAME_MISMATCH;
      if(mm.row_count!=market_rows) return MSZZ_SIM_REJECT_MARKET_HASH_MISMATCH;
      if(mm.market_data_sha256!=market_sha) return MSZZ_SIM_REJECT_MARKET_HASH_MISMATCH;
      if(mm.clock_domain!=MSZZ_SCREENING_CLOCK_DOMAIN) return MSZZ_SIM_REJECT_CLOCK_DOMAIN_MISMATCH;
      if(mm.time_authority_id!=MSZZ_SCREENING_TIME_AUTHORITY) return MSZZ_SIM_REJECT_TIME_AUTHORITY_MISMATCH;
      if(cm.symbol!=market_symbol) return MSZZ_SIM_REJECT_SYMBOL_MISMATCH;
      if(cm.timeframe!=market_tf) return MSZZ_SIM_REJECT_TIMEFRAME_MISMATCH;
      if(!IsSha256(cm.journal_sha256)) return MSZZ_SIM_REJECT_JOURNAL_MANIFEST_INVALID;
      if(!IsSha256(cm.source_data_sha256)) return MSZZ_SIM_REJECT_JOURNAL_MANIFEST_INVALID;
      if(cm.source_data_sha256!=market_sha) return MSZZ_SIM_REJECT_SOURCE_HASH_MISMATCH;
      if(params.symbol!=market_symbol || params.timeframe!=market_tf)
         return MSZZ_SIM_REJECT_INSTRUMENT_PARAMS_MISMATCH;
      if(!IsSha256(params.params_sha256)) return MSZZ_SIM_REJECT_INSTRUMENT_PARAMS_MISMATCH;
      for(int i=0;i<ArraySize(candidates);i++)
      {
         if(candidates[i].clock_domain!=MSZZ_SCREENING_CLOCK_DOMAIN)
            return MSZZ_SIM_REJECT_CLOCK_DOMAIN_MISMATCH;
         if(candidates[i].time_authority_id!=MSZZ_SCREENING_TIME_AUTHORITY)
            return MSZZ_SIM_REJECT_TIME_AUTHORITY_MISMATCH;
         double risk=MathAbs(candidates[i].entry-candidates[i].stop);
         if(risk>0.0 && candidates[i].stop_distance_points>0.0)
         {
            string r="";
            if(!CMSZZScreeningMarketV2::VerifyCandidatePointSize(params,risk,
                  candidates[i].stop_distance_points,r))
               return MSZZ_SIM_REJECT_INSTRUMENT_PARAMS_MISMATCH;
         }
      }
      return MSZZ_SIM_RUN_OK;
   }

   static void Simulate(const MSZZScreeningCandidateV2 &c,const MSZZScreeningCandidateManifestV2 &cm,
                        const string market_sha,const MSZZScreeningMarketBarV2 &bars[],
                        const MSZZScreeningInstrumentParamsV2 &params,const int entry_i,
                        const long test_end,const double point_size,const double tick_size,
                        const long ce,const long cs,const long ct,const long tr,
                        MSZZScreeningOutcomeV2 &o)
   {
      int direction=c.direction;
      double min_dist_price=params.minimum_distance_points*point_size;
      long entry_points=(direction>0 ? bars[entry_i].open_points+bars[entry_i].spread_points
                                      : bars[entry_i].open_points);
      double entry_price=entry_points*point_size;

      double raw_stop=c.stop;
      if(direction>0) raw_stop=MathMin(raw_stop,entry_price-min_dist_price);
      else            raw_stop=MathMax(raw_stop,entry_price+min_dist_price);
      double normalized_stop=CMSZZScreeningExecutionPolicyV2::NormalizeStop(direction,raw_stop,
                                                                           entry_price,tick_size);
      bool okg=true;
      long normalized_stop_points=PointsExact(normalized_stop,point_size,okg);
      long initial_risk_points=(long)MathAbs(entry_points-normalized_stop_points);
      if(initial_risk_points<=0)
      { BlankOutcome(o,c,cm,market_sha,params.params_sha256,MSZZ_SIM_REJECT_INVALID_GEOMETRY,ce,cs,ct,tr);
        return; }

      double risk_price=MathAbs(entry_price-normalized_stop);
      double raw_target=entry_price+direction*c.target_r*risk_price;
      double reconstructed_target=CMSZZScreeningExecutionPolicyV2::NormalizeTarget(direction,raw_target,
                                                                                  entry_price,tick_size);
      long reconstructed_target_points=PointsExact(reconstructed_target,point_size,okg);

      double stop_price=normalized_stop_points*point_size;
      double target_price=reconstructed_target_points*point_size;

      string exit_reason=MSZZ_SIM_EXIT_TEST_END;
      int exit_i=entry_i;
      bool collision=false;
      for(int i=entry_i;i<ArraySize(bars);i++)
      {
         if(bars[i].time_raw>test_end) break;
         exit_i=i;
         double hi,lo;
         if(direction>0) { hi=bars[i].high_points*point_size; lo=bars[i].low_points*point_size; }
         else { hi=(bars[i].high_points+bars[i].spread_points)*point_size;
                lo=(bars[i].low_points+bars[i].spread_points)*point_size; }
         ENUM_MSZZ_SCREEN_EXIT_V2 res=CMSZZScreeningExecutionPolicyV2::ResolveBar(direction,stop_price,
                                                                                 target_price,hi,lo);
         if(res==MSZZ_SCREEN_EXIT_TEST_END) continue;
         bool hit_stop=(direction>0 ? lo<=stop_price : hi>=stop_price);
         bool hit_target=(direction>0 ? hi>=target_price : lo<=target_price);
         if(res==MSZZ_SCREEN_EXIT_STOP) { exit_reason=MSZZ_SIM_EXIT_STOP; collision=(hit_stop&&hit_target); }
         else exit_reason=MSZZ_SIM_EXIT_TARGET;
         break;
      }

      long exit_points;
      if(exit_reason==MSZZ_SIM_EXIT_STOP)
      {
         if(direction>0) exit_points=(long)MathMin(bars[exit_i].open_points,normalized_stop_points);
         else exit_points=(long)MathMax(bars[exit_i].open_points+bars[exit_i].spread_points,
                                        normalized_stop_points);
      }
      else if(exit_reason==MSZZ_SIM_EXIT_TARGET) exit_points=reconstructed_target_points;
      else
      {
         if(direction>0) exit_points=bars[exit_i].close_points;
         else exit_points=bars[exit_i].close_points+bars[exit_i].spread_points;
      }

      double exit_price=exit_points*point_size;
      double gross_r_policy=CMSZZScreeningExecutionPolicyV2::GrossR(direction,entry_price,exit_price,
                                                                   stop_price);
      long gross_r_1e9=RoundRatio(direction*(exit_points-entry_points)*MSZZ_SCREENING_R_SCALE,
                                  initial_risk_points);
      // policy cross-check (semantic authority): integer R must agree with GrossR within tolerance
      double check=MathAbs((double)gross_r_1e9/MSZZ_SCREENING_R_SCALE-gross_r_policy);
      if(check>MSZZ_SCREENING_R_TOL) PrintFormat("WARN gross_r parity %.12f",check);

      // MFE/MAE entry->exit inclusive, exit bar capped at exit price
      long fav=entry_points, adv=entry_points;
      for(int i=entry_i;i<=exit_i;i++)
      {
         long hi_p,lo_p;
         if(i==exit_i) { hi_p=exit_points; lo_p=exit_points; }
         else if(direction>0) { hi_p=bars[i].high_points; lo_p=bars[i].low_points; }
         else { hi_p=bars[i].high_points+bars[i].spread_points;
                lo_p=bars[i].low_points+bars[i].spread_points; }
         if(direction>0) { fav=MathMax(fav,hi_p); adv=MathMin(adv,lo_p); }
         else { fav=MathMin(fav,lo_p); adv=MathMax(adv,hi_p); }
      }
      long mfe_num,mae_num;
      if(direction>0) { mfe_num=(fav-entry_points)*MSZZ_SCREENING_R_SCALE;
                        mae_num=(entry_points-adv)*MSZZ_SCREENING_R_SCALE; }
      else { mfe_num=(entry_points-fav)*MSZZ_SCREENING_R_SCALE;
             mae_num=(adv-entry_points)*MSZZ_SCREENING_R_SCALE; }
      long mfe_r_1e9=RoundRatio(mfe_num,initial_risk_points);
      long mae_r_1e9=RoundRatio(mae_num,initial_risk_points);
      long holding_bars=(exit_i-entry_i)+1;

      BlankOutcome(o,c,cm,market_sha,params.params_sha256,MSZZ_SIM_ACCEPTED,ce,cs,ct,tr);
      o.rejection_reason="";  // accepted trades carry no rejection reason (mirror Python)
      o.entry_time_raw=bars[entry_i].time_raw; o.exit_time_raw=bars[exit_i].time_raw;
      o.executable_entry_points=entry_points; o.normalized_stop_points=normalized_stop_points;
      o.reconstructed_target_points=reconstructed_target_points; o.executable_exit_points=exit_points;
      o.initial_risk_points=initial_risk_points;
      o.spread_points_at_entry=bars[entry_i].spread_points;
      o.spread_points_at_exit=bars[exit_i].spread_points;
      o.exit_reason=exit_reason; o.stop_first_collision=(collision ? "true" : "false");
      o.gross_r_1e9=gross_r_1e9; o.mfe_r_1e9=mfe_r_1e9; o.mae_r_1e9=mae_r_1e9;
      o.holding_bars=holding_bars;
   }

public:
   static string RunScreening(MSZZScreeningCandidateV2 &candidates[],
                              const MSZZScreeningCandidateManifestV2 &cm,
                              const MSZZScreeningMarketBarV2 &bars[],
                              const string market_symbol,const int market_tf,const string market_sha,
                              const MSZZScreeningMarketManifestV2 &mm,
                              const MSZZScreeningInstrumentParamsV2 &params,
                              const string policy_id,const long test_end_in,
                              MSZZScreeningOutcomeV2 &outcomes[])
   {
      ArrayResize(outcomes,0);
      long market_rows=ArraySize(bars);
      string status=DatasetIdentity(candidates,cm,market_symbol,market_tf,market_sha,market_rows,
                                    mm,params,policy_id);
      if(status!=MSZZ_SIM_RUN_OK) return status;

      double point_size=CMSZZScreeningMarketV2::PointSize(params);
      double tick_size=CMSZZScreeningMarketV2::TickSize(params);
      long test_end=(test_end_in<0 ? bars[ArraySize(bars)-1].time_raw : test_end_in);

      MSZZScreeningCandidateV2 ordered[];
      ArrayResize(ordered,ArraySize(candidates));
      for(int i=0;i<ArraySize(candidates);i++) ordered[i]=candidates[i];
      StableSort(ordered);

      long fam_id[]; long fam_until[];
      for(int oi=0;oi<ArraySize(ordered);oi++)
      {
         MSZZScreeningCandidateV2 c=ordered[oi];
         // diagnostic geometry exact grid alignment
         bool ok1=true,ok2=true,ok3=true;
         long ce=PointsExact(c.entry,point_size,ok1);
         long cs=PointsExact(c.stop,point_size,ok2);
         long ct=PointsExact(c.target,point_size,ok3);
         long tr=RoundScale(c.target_r*MSZZ_SCREENING_R_SCALE);
         int idx=ArraySize(outcomes); ArrayResize(outcomes,idx+1);
         if(!ok1 || !ok2 || !ok3)
         {
            long fe=PointsRound(c.entry,point_size),fs=PointsRound(c.stop,point_size),
                 ftt=PointsRound(c.target,point_size);
            BlankOutcome(outcomes[idx],c,cm,market_sha,params.params_sha256,
                         MSZZ_SIM_REJECT_CANDIDATE_OFF_GRID,fe,fs,ftt,tr);
            continue;
         }
         // occupancy
         bool rejected=false;
         for(int k=0;k<ArraySize(fam_id);k++)
            if(fam_id[k]==c.family_id && c.signal_time<=fam_until[k])
            { BlankOutcome(outcomes[idx],c,cm,market_sha,params.params_sha256,
                           MSZZ_SIM_REJECT_FAMILY_OPEN,ce,cs,ct,tr); rejected=true; break; }
         if(rejected) continue;

         int entry_i=-1;
         for(int i=0;i<ArraySize(bars);i++) if(bars[i].time_raw>c.signal_time) { entry_i=i; break; }
         if(entry_i<0)
         { BlankOutcome(outcomes[idx],c,cm,market_sha,params.params_sha256,
                        MSZZ_SIM_REJECT_NO_NEXT_EXECUTABLE_BAR,ce,cs,ct,tr); continue; }
         if(bars[entry_i].time_raw>test_end)
         { BlankOutcome(outcomes[idx],c,cm,market_sha,params.params_sha256,
                        MSZZ_SIM_REJECT_ENTRY_AFTER_TEST_END,ce,cs,ct,tr); continue; }
         if(bars[entry_i].time_raw>c.expiry_time)
         { BlankOutcome(outcomes[idx],c,cm,market_sha,params.params_sha256,
                        MSZZ_SIM_REJECT_EXPIRED,ce,cs,ct,tr); continue; }

         Simulate(c,cm,market_sha,bars,params,entry_i,test_end,point_size,tick_size,
                  ce,cs,ct,tr,outcomes[idx]);
         if(outcomes[idx].status==MSZZ_SIM_ACCEPTED)
         {
            bool found=false;
            for(int k=0;k<ArraySize(fam_id);k++)
               if(fam_id[k]==c.family_id) { fam_until[k]=outcomes[idx].exit_time_raw; found=true; break; }
            if(!found) { int m=ArraySize(fam_id); ArrayResize(fam_id,m+1); ArrayResize(fam_until,m+1);
                         fam_id[m]=c.family_id; fam_until[m]=outcomes[idx].exit_time_raw; }
         }
      }
      return MSZZ_SIM_RUN_OK;
   }

   static string OutcomeHeader()
   {
      return "run_status,outcome_version,policy_id,strategy_id,family_id,hypothesis_version,"
             "canonical_variant_id,origin_id,sequence_id,event_id,signal_time_raw,expiry_time_raw,"
             "entry_time_raw,exit_time_raw,direction,candidate_entry_points,candidate_stop_points,"
             "candidate_target_points,candidate_target_r_1e9,executable_entry_points,"
             "normalized_stop_points,reconstructed_target_points,executable_exit_points,"
             "initial_risk_points,spread_points_at_entry,spread_points_at_exit,status,"
             "rejection_reason,exit_reason,stop_first_collision,gross_r_1e9,mfe_r_1e9,mae_r_1e9,"
             "holding_bars,symbol,timeframe,clock_domain,time_authority_id,source_data_sha256,"
             "candidate_journal_sha256,market_data_sha256,instrument_params_sha256";
   }

   static string OutcomeRow(const string run_status,const MSZZScreeningOutcomeV2 &o)
   {
      string f[42];
      f[0]=run_status; f[1]=o.outcome_version; f[2]=o.policy_id;
      f[3]=IntegerToString(o.strategy_id); f[4]=IntegerToString(o.family_id);
      f[5]=o.hypothesis_version; f[6]=o.canonical_variant_id; f[7]=o.origin_id;
      f[8]=o.sequence_id; f[9]=o.event_id;
      f[10]=StringFormat("%I64d",o.signal_time_raw); f[11]=StringFormat("%I64d",o.expiry_time_raw);
      f[12]=StringFormat("%I64d",o.entry_time_raw); f[13]=StringFormat("%I64d",o.exit_time_raw);
      f[14]=o.direction;
      f[15]=StringFormat("%I64d",o.candidate_entry_points);
      f[16]=StringFormat("%I64d",o.candidate_stop_points);
      f[17]=StringFormat("%I64d",o.candidate_target_points);
      f[18]=StringFormat("%I64d",o.candidate_target_r_1e9);
      f[19]=StringFormat("%I64d",o.executable_entry_points);
      f[20]=StringFormat("%I64d",o.normalized_stop_points);
      f[21]=StringFormat("%I64d",o.reconstructed_target_points);
      f[22]=StringFormat("%I64d",o.executable_exit_points);
      f[23]=StringFormat("%I64d",o.initial_risk_points);
      f[24]=StringFormat("%I64d",o.spread_points_at_entry);
      f[25]=StringFormat("%I64d",o.spread_points_at_exit);
      f[26]=o.status; f[27]=o.rejection_reason; f[28]=o.exit_reason; f[29]=o.stop_first_collision;
      f[30]=StringFormat("%I64d",o.gross_r_1e9); f[31]=StringFormat("%I64d",o.mfe_r_1e9);
      f[32]=StringFormat("%I64d",o.mae_r_1e9); f[33]=StringFormat("%I64d",o.holding_bars);
      f[34]=o.symbol; f[35]=IntegerToString(o.timeframe); f[36]=o.clock_domain;
      f[37]=o.time_authority_id; f[38]=o.source_data_sha256; f[39]=o.candidate_journal_sha256;
      f[40]=o.market_data_sha256; f[41]=o.instrument_params_sha256;
      return CanonicalRecord(f);
   }

   static string OutcomesDocument(const string run_status,const MSZZScreeningOutcomeV2 &outcomes[])
   {
      string doc=OutcomeHeader();
      for(int i=0;i<ArraySize(outcomes);i++) doc+="\r\n"+OutcomeRow(run_status,outcomes[i]);
      doc+="\r\n";
      return doc;
   }

   static bool OutcomesSha256(const string run_status,const MSZZScreeningOutcomeV2 &outcomes[],
                              string &hex,string &reason)
   {
      string doc=OutcomesDocument(run_status,outcomes);
      uchar data[]; StringToCharArray(doc,data,0,-1,CP_UTF8);
      if(ArraySize(data)>0) ArrayResize(data,ArraySize(data)-1);
      return CMSZZScreeningMarketV2::Sha256Bytes(data,hex,reason);
   }
};

#endif
