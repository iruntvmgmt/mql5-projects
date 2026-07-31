#property strict
#property script_show_inputs
#include <MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh>

// Cross-language parity test: consumes the shared committed fixtures
// (simulator_fixtures.csv) and the Python reference expected outcomes
// (expected_outcomes.csv) from MQL5/Files/. For every fixture the MQL5
// simulator must reproduce the reference run-status and byte-identical
// canonical outcome SHA-256.

int g_tests=0, g_failures=0;
void Check(const bool ok,const string what)
{
   g_tests++;
   if(!ok) { PrintFormat("FAIL: %s",what); g_failures++; }
}

bool ReadFileString(const string name,string &out,string &reason)
{
   int h=FileOpen(name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) { reason="OPEN_FAILED "+name; return false; }
   ulong size=FileSize(h);
   uchar data[]; ArrayResize(data,(int)size);
   uint rd=(size>0 ? FileReadArray(h,data,0,(uint)size) : 0);
   FileClose(h);
   if((ulong)rd!=size) { reason="READ_FAILED"; return false; }
   out=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
   reason="OK"; return true;
}

// split a canonical document into logical records on CRLF (fields carry no CRLF here)
void SplitLines(const string doc,string &lines[])
{
   ArrayResize(lines,0);
   int start=0, len=StringLen(doc);
   for(int i=0;i<len-1;i++)
   {
      if(StringSubstr(doc,i,1)=="\r" && StringSubstr(doc,i+1,1)=="\n")
      {
         int n=ArraySize(lines); ArrayResize(lines,n+1);
         lines[n]=StringSubstr(doc,start,i-start);
         i++; start=i+1;
      }
   }
}

string exp_id[]; string exp_status[]; string exp_rows[]; string exp_sha[];
void LoadExpected()
{
   string doc,reason;
   if(!ReadFileString("expected_outcomes.csv",doc,reason)) { PrintFormat("EXPECTED %s",reason); return; }
   string lines[]; SplitLines(doc,lines);
   for(int i=1;i<ArraySize(lines);i++)
   {
      string f[]; string r;
      if(!CMSZZScreeningMarketV2::ParseQuotedRecord(lines[i],f,r)) continue;
      if(ArraySize(f)<4) continue;
      int n=ArraySize(exp_id);
      ArrayResize(exp_id,n+1); ArrayResize(exp_status,n+1);
      ArrayResize(exp_rows,n+1); ArrayResize(exp_sha,n+1);
      exp_id[n]=f[0]; exp_status[n]=f[1]; exp_rows[n]=f[2]; exp_sha[n]=f[3];
   }
}
int ExpIndex(const string id)
{
   for(int i=0;i<ArraySize(exp_id);i++) if(exp_id[i]==id) return i;
   return -1;
}

// current-fixture accumulators
string m_meta[]; MSZZScreeningMarketBarV2 m_bars[]; MSZZScreeningCandidateV2 m_cands[];

void ResetFixture() { ArrayResize(m_meta,0); ArrayResize(m_bars,0); ArrayResize(m_cands,0); }

void ProcessFixture(const string id)
{
   if(ArraySize(m_meta)<16) return;
   long test_end=(m_meta[2]=="NONE" ? -1 : (long)StringToInteger(m_meta[2]));
   string policy_id=m_meta[3];
   string cm_symbol=m_meta[4];
   int cm_tf=(int)StringToInteger(m_meta[5]);
   string journal_sha=m_meta[6];
   string cm_source_mode=m_meta[7];
   long ps=(long)StringToInteger(m_meta[8]);
   long ts=(long)StringToInteger(m_meta[9]);
   long stops=(long)StringToInteger(m_meta[10]);
   long freeze=(long)StringToInteger(m_meta[11]);
   string mm_mode=m_meta[12];
   string expect_rs=m_meta[13];
   string market_symbol=m_meta[14];
   int market_tf=(int)StringToInteger(m_meta[15]);

   int ei=ExpIndex(id);
   string want_status=(ei>=0 ? exp_status[ei] : "");
   string want_sha=(ei>=0 ? exp_sha[ei] : "");

   // build + parse market data (validate + sha)
   string mdoc=CMSZZScreeningMarketV2::MarketDataDocument(market_symbol,market_tf,m_bars);
   uchar mdata[]; StringToCharArray(mdoc,mdata,0,-1,CP_UTF8);
   if(ArraySize(mdata)>0) ArrayResize(mdata,ArraySize(mdata)-1);
   MSZZScreeningMarketBarV2 pbars[]; string psym; int ptf; string market_sha; string mreason;
   bool parsed=CMSZZScreeningMarketV2::ParseMarketDataBytes(mdata,pbars,psym,ptf,market_sha,mreason);
   if(expect_rs=="TRANSPORT_REJECT")
   {
      Check(!parsed && want_status=="TRANSPORT_REJECT","["+id+"] transport reject ("+mreason+")");
      return;
   }
   if(!parsed) { Check(false,"["+id+"] unexpected transport reject "+mreason); return; }

   // instrument params (build canonical -> parse to get struct + sha)
   string pdoc=CMSZZScreeningMarketV2::InstrumentParamsDocument(market_symbol,market_tf,ps,ts,stops,freeze);
   uchar pdata[]; StringToCharArray(pdoc,pdata,0,-1,CP_UTF8);
   if(ArraySize(pdata)>0) ArrayResize(pdata,ArraySize(pdata)-1);
   MSZZScreeningInstrumentParamsV2 params; string preason;
   if(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pdata,params,preason))
   { Check(false,"["+id+"] params parse "+preason); return; }

   // market manifest (override sha if requested)
   MSZZScreeningMarketManifestV2 mm;
   CMSZZScreeningMarketV2::BuildMarketManifest(market_symbol,market_tf,ArraySize(pbars),market_sha,mm);
   if(mm_mode!="AUTO") mm.market_data_sha256=mm_mode;

   // candidate manifest
   MSZZScreeningCandidateManifestV2 cm;
   cm.symbol=cm_symbol; cm.timeframe=cm_tf; cm.journal_sha256=journal_sha;
   cm.source_data_sha256=(cm_source_mode=="AUTO" ? market_sha : cm_source_mode);

   MSZZScreeningOutcomeV2 outcomes[];
   string run_status=CMSZZScreeningSimulatorV2::RunScreening(m_cands,cm,pbars,market_symbol,market_tf,
                        market_sha,mm,params,policy_id,test_end,outcomes);
   string sha,sreason;
   CMSZZScreeningSimulatorV2::OutcomesSha256(run_status,outcomes,sha,sreason);

   Check(run_status==want_status,"["+id+"] run_status "+run_status+" vs "+want_status);
   Check(sha==want_sha,"["+id+"] outcome sha "+StringSubstr(sha,0,12)+" vs "+StringSubstr(want_sha,0,12));
}

void AddCandidate(const string &f[],const double point_size)
{
   int n=ArraySize(m_cands); ArrayResize(m_cands,n+1);
   m_cands[n].direction=(int)StringToInteger(f[2]);
   m_cands[n].signal_time=(long)StringToInteger(f[3]);
   m_cands[n].expiry_time=(long)StringToInteger(f[4]);
   m_cands[n].entry=StringToDouble(f[5]);
   m_cands[n].stop=StringToDouble(f[6]);
   m_cands[n].target_r=StringToDouble(f[7]);
   double risk=MathAbs(m_cands[n].entry-m_cands[n].stop);
   m_cands[n].target=m_cands[n].entry+m_cands[n].direction*risk*m_cands[n].target_r;
   m_cands[n].family_id=(int)StringToInteger(f[8]);
   m_cands[n].event_id=f[9];
   m_cands[n].sequence_id=f[10];
   m_cands[n].strategy_id=(int)StringToInteger(f[11]);
   m_cands[n].clock_domain=f[12];
   m_cands[n].time_authority_id=f[13];
   m_cands[n].hypothesis_version="H"; m_cands[n].canonical_variant_id="V"; m_cands[n].origin_id="O";
   string sdm=f[14];
   m_cands[n].stop_distance_points=(sdm=="AUTO" ? risk/point_size : StringToDouble(sdm));
}

void OnStart()
{
   LoadExpected();
   string doc,reason;
   if(!ReadFileString("simulator_fixtures.csv",doc,reason))
   { PrintFormat("FIXTURES %s",reason); PrintFormat("TEST_SUMMARY tests=0 failures=1"); return; }
   string lines[]; SplitLines(doc,lines);

   string current="";
   double point_size=0.0;
   for(int i=1;i<ArraySize(lines);i++)
   {
      string f[]; string r;
      if(!CMSZZScreeningMarketV2::ParseQuotedRecord(lines[i],f,r)) continue;
      if(ArraySize(f)<16) continue;
      string id=f[0], kind=f[1];
      if(id!=current)
      {
         if(current!="") ProcessFixture(current);
         ResetFixture(); current=id;
      }
      if(kind=="META")
      {
         ArrayResize(m_meta,16);
         for(int k=0;k<16;k++) m_meta[k]=f[k];
         point_size=(double)StringToInteger(f[8])/MSZZ_SCREENING_PRICE_SCALE_1E8;
      }
      else if(kind=="BAR")
      {
         int n=ArraySize(m_bars); ArrayResize(m_bars,n+1);
         m_bars[n].time_raw=(long)StringToInteger(f[2]);
         m_bars[n].open_points=(long)StringToInteger(f[3]);
         m_bars[n].high_points=(long)StringToInteger(f[4]);
         m_bars[n].low_points=(long)StringToInteger(f[5]);
         m_bars[n].close_points=(long)StringToInteger(f[6]);
         m_bars[n].spread_points=(long)StringToInteger(f[7]);
      }
      else if(kind=="CAND")
      {
         AddCandidate(f,point_size);
      }
   }
   if(current!="") ProcessFixture(current);

   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
}
