#property strict
#property script_show_inputs
#include <MultiSpeedZigZag/Research/ScreeningMarketV2.mqh>

// Cross-language byte-parity constants produced by
// Tools/SixFamilyRecovery/ScreeningSimulatorV2/make_market_fixtures.py.
#define EXPECTED_MARKET_SHA   "78067caf702df82808a0c705d4043065d13f559b535c978ac30d4cfc6ddf9a83"
#define EXPECTED_MANIFEST_SHA "3232295529ffb813778f882c355575e4433cc4c9bd8a1df0cd89d8fa5128cb32"
#define EXPECTED_PARAMS_SHA   "fe608f32bc4070d801f21e464b7fd96c1ef4058637ab0bcc0cf4fee939fdea2c"

int g_failures=0;
int g_tests=0;
void Check(const bool ok,const string what)
{
   g_tests++;
   if(!ok) { PrintFormat("FAIL: %s",what); g_failures++; }
   else PrintFormat("PASS: %s",what);
}

void Bytes(const string document,uchar &data[])
{
   StringToCharArray(document,data,0,-1,CP_UTF8);
   if(ArraySize(data)>0) ArrayResize(data,ArraySize(data)-1); // drop trailing NUL
}

string RawQuote(const string value)
{
   string escaped="";
   for(int i=0;i<StringLen(value);i++)
   {
      string ch=StringSubstr(value,i,1);
      escaped+=(ch=="\"" ? "\"\"" : ch);
   }
   return "\""+escaped+"\"";
}

string RawRecord(const string &fields[])
{
   string out="";
   for(int i=0;i<ArraySize(fields);i++)
   {
      if(i>0) out+=",";
      out+=RawQuote(fields[i]);
   }
   return out;
}

void FixtureBars(MSZZScreeningMarketBarV2 &bars[])
{
   // Ordinary decimal prices (point_size 0.01) as exact integer point counts.
   ArrayResize(bars,3);
   bars[0].time_raw=1000; bars[0].open_points=10000; bars[0].high_points=10050;
   bars[0].low_points=9950;  bars[0].close_points=10020; bars[0].spread_points=20;
   bars[1].time_raw=1300; bars[1].open_points=10020; bars[1].high_points=10100;
   bars[1].low_points=10000; bars[1].close_points=10080; bars[1].spread_points=20;
   bars[2].time_raw=1600; bars[2].open_points=10080; bars[2].high_points=10120;
   bars[2].low_points=10030; bars[2].close_points=10040; bars[2].spread_points=30;
}

string MarketRowFields(const string time_raw,const string open_p,const string high_p,
                       const string low_p,const string close_p,const string spread)
{
   string f[11];
   f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="XAUUSD"; f[2]="5";
   f[3]=MSZZ_SCREENING_CLOCK_DOMAIN; f[4]=MSZZ_SCREENING_TIME_AUTHORITY;
   f[5]=time_raw; f[6]=open_p; f[7]=high_p; f[8]=low_p; f[9]=close_p; f[10]=spread;
   return RawRecord(f);
}

string GoodBar0() { return MarketRowFields("1000","10000","10050","9950","10020","20"); }
string GoodBar1() { return MarketRowFields("1300","10020","10100","10000","10080","20"); }

bool ParseDoc(const string document,string &reason)
{
   uchar data[]; Bytes(document,data);
   MSZZScreeningMarketBarV2 bars[]; string symbol; int tf; string sha;
   return CMSZZScreeningMarketV2::ParseMarketDataBytes(data,bars,symbol,tf,sha,reason);
}

void ExpectMarketReject(const string document,const string expected_reason)
{
   string reason="";
   bool ok=ParseDoc(document,reason);
   Check(!ok && reason==expected_reason,"market reject "+expected_reason+" (got "+reason+")");
}

void OnStart()
{
   string reason="";
   MSZZScreeningMarketBarV2 bars[];
   FixtureBars(bars);

   // --- Good market data: byte parity with Python ---
   string doc=CMSZZScreeningMarketV2::MarketDataDocument("XAUUSD",5,bars);
   uchar data[]; Bytes(doc,data);
   string sha="";
   Check(CMSZZScreeningMarketV2::Sha256Bytes(data,sha,reason),"market sha computes");
   Check(sha==EXPECTED_MARKET_SHA,"market data byte-parity with Python ("+sha+")");

   MSZZScreeningMarketBarV2 out[]; string psym; int ptf; string psha;
   Check(CMSZZScreeningMarketV2::ParseMarketDataBytes(data,out,psym,ptf,psha,reason),
         "market data parses");
   Check(psym=="XAUUSD" && ptf==5 && ArraySize(out)==3 && psha==EXPECTED_MARKET_SHA,
         "market data fields reconstructed");
   Check(out[1].time_raw==1300 && out[2].close_points==10040 && out[2].spread_points==30,
         "market bar integer values reconstructed");

   // --- price reconstruction from integer points ---
   Check(MathAbs(CMSZZScreeningMarketV2::PointsToPrice(10020,1000000)-100.20)<1e-9,
         "points->price reconstructs 100.20 exactly");

   // --- Market manifest byte parity + verify ---
   MSZZScreeningMarketManifestV2 manifest;
   CMSZZScreeningMarketV2::BuildMarketManifest("XAUUSD",5,3,EXPECTED_MARKET_SHA,manifest);
   string mdoc=CMSZZScreeningMarketV2::MarketManifestDocument(manifest);
   uchar mdata[]; Bytes(mdoc,mdata); string msha="";
   CMSZZScreeningMarketV2::Sha256Bytes(mdata,msha,reason);
   Check(msha==EXPECTED_MANIFEST_SHA,"market manifest byte-parity with Python ("+msha+")");
   MSZZScreeningMarketManifestV2 parsed_manifest;
   Check(CMSZZScreeningMarketV2::ParseMarketManifestDocument(mdoc,parsed_manifest,reason),
         "market manifest parses");
   Check(CMSZZScreeningMarketV2::VerifyMarketManifest(parsed_manifest,"XAUUSD",5,3,
         EXPECTED_MARKET_SHA,reason),"market manifest verifies");
   Check(!CMSZZScreeningMarketV2::VerifyMarketManifest(parsed_manifest,"XAUUSD",5,3,
         EXPECTED_MANIFEST_SHA,reason) && reason=="MARKET_HASH_MISMATCH",
         "market manifest rejects wrong data hash");

   // --- Instrument params byte parity + verify ---
   string pdoc=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,1000000,1000000,0,0);
   uchar pdata[]; Bytes(pdoc,pdata); string psha2="";
   CMSZZScreeningMarketV2::Sha256Bytes(pdata,psha2,reason);
   Check(psha2==EXPECTED_PARAMS_SHA,"instrument params byte-parity with Python ("+psha2+")");
   MSZZScreeningInstrumentParamsV2 params;
   Check(CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pdata,params,reason),
         "instrument params parse");
   Check(params.point_size_1e8==1000000 &&
         MathAbs(CMSZZScreeningMarketV2::PointSize(params)-0.01)<1e-12 &&
         params.minimum_distance_points==0 && params.params_sha256==EXPECTED_PARAMS_SHA,
         "instrument params fields");
   Check(CMSZZScreeningMarketV2::VerifyInstrumentParams(params,"XAUUSD",5,reason),
         "instrument params market matches");
   Check(CMSZZScreeningMarketV2::VerifyCandidatePointSize(params,2.0,200.0,reason),
         "instrument point-size cross-check ok");
   Check(!CMSZZScreeningMarketV2::VerifyCandidatePointSize(params,2.0,100.0,reason) &&
         reason=="INSTRUMENT_POINT_SIZE_MISMATCH","instrument point-size mismatch rejected");

   // --- minimum-distance derivation ---
   string pdoc2=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,1000000,1000000,30,50);
   uchar pdata2[]; Bytes(pdoc2,pdata2);
   MSZZScreeningInstrumentParamsV2 params2;
   Check(CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pdata2,params2,reason) &&
         params2.minimum_distance_points==50,"minimum distance = max(stops,freeze)");

   // --- fail-closed market data matrix ---
   string header=CMSZZScreeningMarketV2::MarketDataHeader();
   ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+
      MarketRowFields("1000","10020","10100","10000","10080","20")+"\r\n",
      "DUPLICATE_MARKET_TIME");
   ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+
      MarketRowFields("500","10020","10100","10000","10080","20")+"\r\n",
      "NON_MONOTONIC_MARKET_TIME");
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","10000","9900","9950","10020","20")+"\r\n","INVALID_MARKET_BAR");
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","10000","10050","9950","10020","-1")+"\r\n","INVALID_SPREAD");
   // noncanonical integer (leading zero)
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","010000","10050","9950","10020","20")+"\r\n","INVALID_INTEGER");
   // wrong version
   {
      string f[11];
      f[0]="OTHER"; f[1]="XAUUSD"; f[2]="5"; f[3]=MSZZ_SCREENING_CLOCK_DOMAIN;
      f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1000"; f[6]="10000"; f[7]="10050";
      f[8]="9950"; f[9]="10020"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+RawRecord(f)+"\r\n","UNSUPPORTED_MARKET_DATA_VERSION");
   }
   // inconsistent symbol row 2
   {
      string f[11];
      f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="EURUSD"; f[2]="5";
      f[3]=MSZZ_SCREENING_CLOCK_DOMAIN; f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1300";
      f[6]="10020"; f[7]="10100"; f[8]="10000"; f[9]="10080"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+RawRecord(f)+"\r\n","INCONSISTENT_MARKET_MARKET");
   }
   // bad clock domain
   {
      string f[11];
      f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="XAUUSD"; f[2]="5"; f[3]="UTC_CONVERTED";
      f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1000"; f[6]="10000"; f[7]="10050";
      f[8]="9950"; f[9]="10020"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+RawRecord(f)+"\r\n","UNSUPPORTED_MARKET_TIME_AUTHORITY");
   }
   // header mismatch
   ExpectMarketReject("bad_header\r\n"+GoodBar0()+"\r\n","MARKET_HEADER_MISMATCH");
   // missing final CRLF
   ExpectMarketReject(header+"\r\n"+GoodBar0(),"MISSING_FINAL_CRLF");
   // unquoted first field (quotes otherwise balanced)
   {
      string uq="MSZZ_SCREENING_MARKET_DATA_V2,"+RawQuote("XAUUSD")+","+RawQuote("5")+","+
                RawQuote(MSZZ_SCREENING_CLOCK_DOMAIN)+","+RawQuote(MSZZ_SCREENING_TIME_AUTHORITY)+","+
                RawQuote("1000")+","+RawQuote("10000")+","+RawQuote("10050")+","+
                RawQuote("9950")+","+RawQuote("10020")+","+RawQuote("20");
      ExpectMarketReject(header+"\r\n"+uq+"\r\n","UNQUOTED_FIELD");
   }

   // --- fail-closed instrument params ---
   {
      string f[8];
      f[0]=MSZZ_SCREENING_INSTRUMENT_PARAMS_V2; f[1]="XAUUSD"; f[2]="5";
      f[3]="1000000"; f[4]="1000000"; f[5]="50"; f[6]="30"; f[7]="30";
      string bad=CMSZZScreeningMarketV2::InstrumentParamsHeader()+"\r\n"+RawRecord(f)+"\r\n";
      uchar bd[]; Bytes(bad,bd);
      MSZZScreeningInstrumentParamsV2 bp;
      Check(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(bd,bp,reason) &&
            reason=="INSTRUMENT_MINIMUM_DISTANCE_MISMATCH","params minimum mismatch rejected");
   }
   {
      string bad=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,1000000,1500000,0,0);
      uchar bd[]; Bytes(bad,bd);
      MSZZScreeningInstrumentParamsV2 bp;
      Check(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(bd,bp,reason) &&
            reason=="INSTRUMENT_GRID_INCOMPATIBLE","params grid incompatible rejected");
   }

   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
}
