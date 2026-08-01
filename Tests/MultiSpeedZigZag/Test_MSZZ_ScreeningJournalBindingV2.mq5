#property strict
#include <MultiSpeedZigZag/Research/ScreeningJournalBindingV2.mqh>

// JOURNAL_BINDING (JB) certification harness. Driven by the canonical index
// journal_binding_fixture_index.csv (explicit journal filename, tamper stage/
// field/value, expected journal/projection SHAs, expected status + outcome
// count). Every fixture goes through the certified public bundle-only entry
// CMSZZScreeningJournalBindingV2::RunScreening. Fail-closed: structural problems
// emit HARNESS_FAILURE and block a green summary; each fixture emits exactly one
// FIXTURE_RESULT marker.

#define JB_VERSION "MSZZ_SCREENING_JB_INDEX_V2"

int g_tests=0, g_failures=0, g_harness=0, g_fixfail=0, g_markers=0;
string g_run_id="";

void Check(const bool ok,const string what){ g_tests++; if(!ok){ g_failures++; Print("assert FAIL: ",what);} }
void Harness(const string code,const string detail){ g_harness++; g_failures++; PrintFormat("HARNESS_FAILURE [JOURNAL_BINDING] %s %s",code,detail); }
void Marker(const string id,const bool pass){ g_markers++; if(!pass) g_fixfail++; PrintFormat("FIXTURE_RESULT [%s] %s",id,(pass?"PASS":"FAIL")); }
void FixtureFail(const string id,const string exp,const string act){ PrintFormat("FIXTURE_FAILURE [%s] expected=%s actual=%s",id,exp,act); Marker(id,false); }

bool ReadBytes(const string name,uchar &data[])
{
   int h=FileOpen(name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   ulong size=FileSize(h); ArrayResize(data,(int)size);
   uint rd=(size>0 ? FileReadArray(h,data,0,(uint)size) : 0);
   FileClose(h);
   return ((ulong)rd==size);
}
bool ReadStr(const string name,string &out)
{ uchar d[]; if(!ReadBytes(name,d)) return false; out=CharArrayToString(d,0,ArraySize(d),CP_UTF8); return true; }
void SplitLines(const string doc,string &lines[])
{
   ArrayResize(lines,0); int start=0,len=StringLen(doc);
   for(int i=0;i<len-1;i++)
      if(StringSubstr(doc,i,1)=="\r" && StringSubstr(doc,i+1,1)=="\n")
      { int n=ArraySize(lines); ArrayResize(lines,n+1); lines[n]=StringSubstr(doc,start,i-start); i++; start=i+1; }
}

// shared market (0.01 grid; bars after signal_time=100)
MSZZScreeningMarketBarV2 g_bars[]; string g_market_sha=""; MSZZScreeningInstrumentParamsV2 g_params;
MSZZScreeningMarketManifestV2 g_mm;
bool BuildMarket()
{
   ArrayResize(g_bars,3);
   long t[]={50,150,250}; long op[]={10000,10000,10200}; long hp[]={10010,10250,10260};
   long lp[]={9990,9990,10180}; long cp[]={10000,10200,10210}; long sp[]={2,2,2};
   for(int i=0;i<3;i++){ g_bars[i].time_raw=t[i]; g_bars[i].open_points=op[i]; g_bars[i].high_points=hp[i];
      g_bars[i].low_points=lp[i]; g_bars[i].close_points=cp[i]; g_bars[i].spread_points=sp[i]; }
   string mdoc=CMSZZScreeningMarketV2::MarketDataDocument("XAUUSD",5,g_bars);
   uchar md[]; StringToCharArray(mdoc,md,0,-1,CP_UTF8); if(ArraySize(md)>0) ArrayResize(md,ArraySize(md)-1);
   MSZZScreeningMarketBarV2 pb[]; string ps; int pt; string mr;
   if(!CMSZZScreeningMarketV2::ParseMarketDataBytes(md,pb,ps,pt,g_market_sha,mr)) return false;
   ArrayResize(g_bars,ArraySize(pb)); for(int i=0;i<ArraySize(pb);i++) g_bars[i]=pb[i];
   string pdoc=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,1000000,1000000,0,0);
   uchar pd[]; StringToCharArray(pdoc,pd,0,-1,CP_UTF8); if(ArraySize(pd)>0) ArrayResize(pd,ArraySize(pd)-1);
   string pr; if(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pd,g_params,pr)) return false;
   CMSZZScreeningMarketV2::BuildMarketManifest("XAUUSD",5,ArraySize(g_bars),g_market_sha,g_mm);
   return true;
}

bool BuildHonestBundle(const uchar &jb[],MSZZVerifiedScreeningJournalV2 &bundle,string &reason)
{
   long rows=0; string jsha="";
   if(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(jb,rows,jsha,reason)) return false;
   MSZZResearchJournalManifestV2 man;
   man.manifest_version=MSZZ_RESEARCH_MANIFEST_V2; man.writer_version=MSZZ_RESEARCH_WRITER_V2;
   man.schema_version=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2; man.symbol="XAUUSD"; man.timeframe=5;
   man.row_count=rows; man.journal_sha256=jsha; man.source_data_sha256=g_market_sha;
   return CMSZZScreeningJournalBindingV2::BuildVerifiedBundle(jb,man,"XAUUSD",5,g_market_sha,bundle,reason);
}

void RunFixture(const string id,const string journal_file,const string invalid,const string stage,
                const string field,const string value,const string exp_jsha,const string exp_psha,
                const string exp_status,const int exp_outcomes)
{
   uchar jb[];
   if(!ReadBytes(journal_file,jb)){ Harness("MISSING_JOURNAL",id+" "+journal_file); Marker(id,false); return; }

   MSZZVerifiedScreeningJournalV2 bundle; string reason="";
   if(stage=="PRE_TRANSPORT_BYTES" || invalid=="1")
   {
      // invalid journal: build a valid baseline bundle, then inject the bad bytes
      uchar base[];
      if(!ReadBytes("cert_jb_JB01_journal.csv",base) || !BuildHonestBundle(base,bundle,reason))
      { Harness("BASELINE_BUILD",id+" "+reason); Marker(id,false); return; }
      ArrayResize(bundle.journal_bytes,ArraySize(jb)); ArrayCopy(bundle.journal_bytes,jb);
   }
   else
   {
      if(!BuildHonestBundle(jb,bundle,reason)){ Harness("HONEST_BUILD",id+" "+reason); Marker(id,false); return; }
      // parity assertions on the honest bundle before tampering
      Check(exp_jsha=="" || bundle.journal_sha256==exp_jsha,"["+id+"] journal SHA parity");
      Check(exp_psha=="" || bundle.projection_sha256==exp_psha,"["+id+"] projection SHA parity");
      if(exp_jsha!="" && bundle.journal_sha256!=exp_jsha){ Marker(id,false); return; }
      if(exp_psha!="" && bundle.projection_sha256!=exp_psha){ Marker(id,false); return; }

      if(stage=="POST_BUNDLE_MANIFEST")
      {
         if(field=="manifest_row_count") bundle.manifest.row_count=(long)StringToInteger(value);
         else if(field=="manifest_journal_sha") bundle.manifest.journal_sha256=value;
         else if(field=="manifest_source_sha") bundle.manifest.source_data_sha256=value;
         else if(field=="manifest_symbol") bundle.manifest.symbol=value;
         else if(field=="manifest_timeframe") bundle.manifest.timeframe=(int)StringToInteger(value);
         else { Harness("UNKNOWN_MANIFEST_FIELD",id+" "+field); Marker(id,false); return; }
      }
      else if(stage=="POST_BUNDLE_CANDIDATE")
      {
         int n=ArraySize(bundle.candidates);
         if(field=="MUTATE_ENTRY") bundle.candidates[0].entry+=1.0;
         else if(field=="MUTATE_STOP") bundle.candidates[0].stop-=0.5;
         else if(field=="MUTATE_TARGET") bundle.candidates[0].target+=1.0;
         else if(field=="MUTATE_TARGET_R") bundle.candidates[0].target_r+=1.0;
         else if(field=="MUTATE_SIGNAL") bundle.candidates[0].signal_time+=1;
         else if(field=="MUTATE_EXPIRY") bundle.candidates[0].expiry_time+=1;
         else if(field=="MUTATE_EVENT_ID") bundle.candidates[0].event_id+="X";
         else if(field=="MUTATE_SEQUENCE_ID") bundle.candidates[0].sequence_id+="X";
         else if(field=="ADD_CANDIDATE"){ ArrayResize(bundle.candidates,n+1); bundle.candidates[n]=bundle.candidates[0]; bundle.candidates[n].event_id="EXTRA|1"; bundle.candidates[n].sequence_id="EXTRA|1"; }
         else if(field=="REMOVE_CANDIDATE"){ if(n>0) ArrayResize(bundle.candidates,n-1); }
         else if(field=="DUP_CANDIDATE"){ ArrayResize(bundle.candidates,n+1); bundle.candidates[n]=bundle.candidates[0]; }
         else { Harness("UNKNOWN_CANDIDATE_FIELD",id+" "+field); Marker(id,false); return; }
      }
      else if(stage=="POST_BUNDLE_IDENTITY")
      {
         if(field=="BUNDLE_VERSION") bundle.bundle_version="X";
         else if(field=="TRANSPORT_VERSION") bundle.transport_version="X";
         else if(field=="PROJECTION_VERSION") bundle.projection_version="X";
         else if(field=="SCHEMA_VERSION") bundle.schema_version="X";
         else { Harness("UNKNOWN_IDENTITY_FIELD",id+" "+field); Marker(id,false); return; }
      }
      else if(stage!="NONE"){ Harness("UNKNOWN_STAGE",id+" "+stage); Marker(id,false); return; }
   }

   MSZZScreeningOutcomeV2 outcomes[];
   string st=CMSZZScreeningJournalBindingV2::RunScreening(bundle,g_bars,"XAUUSD",5,g_market_sha,g_mm,g_params,
                "MSZZ_SIX_FAMILY_EXEC_V2_FIXED_ST",-1,outcomes);
   bool ok=(st==exp_status && ArraySize(outcomes)==exp_outcomes);
   Check(st==exp_status,"["+id+"] status "+st+" vs "+exp_status);
   Check(ArraySize(outcomes)==exp_outcomes,"["+id+"] outcomes "+IntegerToString(ArraySize(outcomes))+" vs "+IntegerToString(exp_outcomes));
   if(!ok) FixtureFail(id,exp_status+"/"+IntegerToString(exp_outcomes),st+"/"+IntegerToString(ArraySize(outcomes)));
   else Marker(id,true);
}

void OnStart()
{
   if(!ReadStr("cert_run_id.txt",g_run_id)) Harness("MISSING_RUN_ID","");
   else { StringReplace(g_run_id,"\r",""); StringReplace(g_run_id,"\n",""); }
   if(!BuildMarket()){ Harness("MARKET_BUILD",""); Summary(); return; }

   string doc;
   if(!ReadStr("journal_binding_fixture_index.csv",doc)){ Harness("MISSING_FILE","journal_binding_fixture_index.csv"); Summary(); return; }
   string lines[]; SplitLines(doc,lines);
   if(ArraySize(lines)<2 || lines[0]!=JB_VERSION){ Harness("BAD_VERSION",(ArraySize(lines)>0?lines[0]:"")); Summary(); return; }

   string seen[];
   for(int i=2;i<ArraySize(lines);i++)
   {
      string f[]; string r;
      if(!CMSZZScreeningMarketV2::ParseQuotedRecord(lines[i],f,r)){ Harness("MALFORMED_ROW","line="+IntegerToString(i)); continue; }
      if(ArraySize(f)!=12){ Harness("FIELD_COUNT","line="+IntegerToString(i)); continue; }
      string id=f[0];
      for(int k=0;k<ArraySize(seen);k++) if(seen[k]==id){ Harness("DUPLICATE_FIXTURE",id); }
      int sn=ArraySize(seen); ArrayResize(seen,sn+1); seen[sn]=id;
      string exp_status=f[10];
      if(exp_status!="RUN_OK" && exp_status!="REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH"){ Harness("UNKNOWN_STATUS",id+" "+exp_status); Marker(id,false); continue; }
      RunFixture(id,f[2],f[3],f[4],f[5],f[6],f[8],f[9],exp_status,(int)StringToInteger(f[11]));
   }
   if(ArraySize(seen)!=24) Harness("INVENTORY","jb="+IntegerToString(ArraySize(seen)));
   Summary();
}

void Summary()
{
   PrintFormat("TEST_SUMMARY tests=%d failures=%d fixtures=24 f=0 jb=%d or=0 markers=%d fixture_failures=%d harness_failures=%d cert_run=%s",
               g_tests,g_failures,g_markers,g_markers,g_fixfail,g_harness,g_run_id);
}
