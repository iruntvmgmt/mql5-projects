#property strict
#property script_show_inputs
#include <MultiSpeedZigZag/Research/ScreeningMarketV2.mqh>

// Cross-language byte-parity constants produced by
// Tools/SixFamilyRecovery/ScreeningSimulatorV2/make_market_fixtures.py.
#define EXPECTED_MARKET_SHA   "52f1e419b6c1c5ed723c6fb1f4b068a3a6ce30699ac6a55751b46c2f37f8601a"
#define EXPECTED_MANIFEST_SHA "daa87892a2bffe3e001dd314ebedf536934109f9195a14eae7b65a224e3ef17e"
#define EXPECTED_PARAMS_SHA   "1fb4118a7eeb2b054ae2f4cb5499acf184148919bc5ebf28aeb4009e18e8f752"

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
   // Exactly-representable (multiples of 0.25) so MQL5/Python 16-digit strings agree.
   ArrayResize(bars,3);
   bars[0].time_raw=1000; bars[0].open_bid=100.0;  bars[0].high_bid=100.5;
   bars[0].low_bid=99.5;   bars[0].close_bid=100.25; bars[0].spread_points=20;
   bars[1].time_raw=1300; bars[1].open_bid=100.25; bars[1].high_bid=101.0;
   bars[1].low_bid=100.0;  bars[1].close_bid=100.75; bars[1].spread_points=20;
   bars[2].time_raw=1600; bars[2].open_bid=100.75; bars[2].high_bid=101.25;
   bars[2].low_bid=100.25; bars[2].close_bid=100.5; bars[2].spread_points=30;
}

string MarketRowFields(const string time_raw,const string open_bid,const string high_bid,
                       const string low_bid,const string close_bid,const string spread)
{
   string f[11];
   f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="XAUUSD"; f[2]="5";
   f[3]=MSZZ_SCREENING_CLOCK_DOMAIN; f[4]=MSZZ_SCREENING_TIME_AUTHORITY;
   f[5]=time_raw; f[6]=open_bid; f[7]=high_bid; f[8]=low_bid; f[9]=close_bid; f[10]=spread;
   return RawRecord(f);
}

// A canonical two-bar body used to build fail-closed variants.
string GoodBar0() { return MarketRowFields("1000","100.0000000000000000","100.5000000000000000",
                                           "99.5000000000000000","100.2500000000000000","20"); }
string GoodBar1() { return MarketRowFields("1300","100.2500000000000000","101.0000000000000000",
                                           "100.0000000000000000","100.7500000000000000","20"); }

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
   Check(out[1].time_raw==1300 && MathAbs(out[2].close_bid-100.5)<1e-9 && out[2].spread_points==30,
         "market bar values reconstructed");

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
         StringSubstr(EXPECTED_MANIFEST_SHA,0,64),reason) && reason=="MARKET_HASH_MISMATCH",
         "market manifest rejects wrong data hash");

   // --- Instrument params byte parity + verify ---
   string pdoc=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,0.01,0.01,0,0);
   uchar pdata[]; Bytes(pdoc,pdata); string psha2="";
   CMSZZScreeningMarketV2::Sha256Bytes(pdata,psha2,reason);
   Check(psha2==EXPECTED_PARAMS_SHA,"instrument params byte-parity with Python ("+psha2+")");
   MSZZScreeningInstrumentParamsV2 params;
   Check(CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pdata,params,reason),
         "instrument params parse");
   Check(MathAbs(params.point_size-0.01)<1e-12 && params.minimum_distance_points==0 &&
         params.params_sha256==EXPECTED_PARAMS_SHA,"instrument params fields");
   Check(CMSZZScreeningMarketV2::VerifyInstrumentParams(params,"XAUUSD",5,reason),
         "instrument params market matches");
   Check(CMSZZScreeningMarketV2::VerifyCandidatePointSize(params,2.0,200.0,reason),
         "instrument point-size cross-check ok");
   Check(!CMSZZScreeningMarketV2::VerifyCandidatePointSize(params,2.0,100.0,reason) &&
         reason=="INSTRUMENT_POINT_SIZE_MISMATCH","instrument point-size mismatch rejected");

   // --- minimum-distance derivation ---
   string pdoc2=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,0.01,0.01,30,50);
   uchar pdata2[]; Bytes(pdoc2,pdata2);
   MSZZScreeningInstrumentParamsV2 params2;
   Check(CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(pdata2,params2,reason) &&
         params2.minimum_distance_points==50,"minimum distance = max(stops,freeze)");

   // --- fail-closed market data matrix ---
   string header=CMSZZScreeningMarketV2::MarketDataHeader();
   ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+
      MarketRowFields("1000","100.2500000000000000","101.0000000000000000",
                      "100.0000000000000000","100.7500000000000000","20")+"\r\n",
      "DUPLICATE_MARKET_TIME");
   ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+
      MarketRowFields("500","100.2500000000000000","101.0000000000000000",
                      "100.0000000000000000","100.7500000000000000","20")+"\r\n",
      "NON_MONOTONIC_MARKET_TIME");
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","100.0000000000000000","99.0000000000000000",
                      "99.5000000000000000","100.2500000000000000","20")+"\r\n",
      "INVALID_MARKET_BAR");
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","100.0000000000000000","100.5000000000000000",
                      "99.5000000000000000","100.2500000000000000","-1")+"\r\n",
      "INVALID_SPREAD");
   // noncanonical decimal (open_bid not 16 fractional digits)
   ExpectMarketReject(header+"\r\n"+
      MarketRowFields("1000","100.0","100.5000000000000000",
                      "99.5000000000000000","100.2500000000000000","20")+"\r\n",
      "INVALID_NUMBER");
   // wrong version
   {
      string f[11];
      f[0]="OTHER"; f[1]="XAUUSD"; f[2]="5"; f[3]=MSZZ_SCREENING_CLOCK_DOMAIN;
      f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1000"; f[6]="100.0000000000000000";
      f[7]="100.5000000000000000"; f[8]="99.5000000000000000"; f[9]="100.2500000000000000"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+RawRecord(f)+"\r\n","UNSUPPORTED_MARKET_DATA_VERSION");
   }
   // inconsistent symbol row 2
   {
      string f[11];
      f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="EURUSD"; f[2]="5";
      f[3]=MSZZ_SCREENING_CLOCK_DOMAIN; f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1300";
      f[6]="100.2500000000000000"; f[7]="101.0000000000000000"; f[8]="100.0000000000000000";
      f[9]="100.7500000000000000"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+GoodBar0()+"\r\n"+RawRecord(f)+"\r\n","INCONSISTENT_MARKET_MARKET");
   }
   // bad clock domain
   {
      string f[11];
      f[0]=MSZZ_SCREENING_MARKET_DATA_V2; f[1]="XAUUSD"; f[2]="5"; f[3]="UTC_CONVERTED";
      f[4]=MSZZ_SCREENING_TIME_AUTHORITY; f[5]="1000"; f[6]="100.0000000000000000";
      f[7]="100.5000000000000000"; f[8]="99.5000000000000000"; f[9]="100.2500000000000000"; f[10]="20";
      ExpectMarketReject(header+"\r\n"+RawRecord(f)+"\r\n","UNSUPPORTED_MARKET_TIME_AUTHORITY");
   }
   // header mismatch
   ExpectMarketReject("bad_header\r\n"+GoodBar0()+"\r\n","MARKET_HEADER_MISMATCH");
   // missing final CRLF
   ExpectMarketReject(header+"\r\n"+GoodBar0(),"MISSING_FINAL_CRLF");
   // unquoted field (first field unquoted, quotes otherwise balanced)
   {
      string uq="MSZZ_SCREENING_MARKET_DATA_V2,"+RawQuote("XAUUSD")+","+RawQuote("5")+","+
                RawQuote(MSZZ_SCREENING_CLOCK_DOMAIN)+","+RawQuote(MSZZ_SCREENING_TIME_AUTHORITY)+","+
                RawQuote("1000")+","+RawQuote("100.0000000000000000")+","+
                RawQuote("100.5000000000000000")+","+RawQuote("99.5000000000000000")+","+
                RawQuote("100.2500000000000000")+","+RawQuote("20");
      ExpectMarketReject(header+"\r\n"+uq+"\r\n","UNQUOTED_FIELD");
   }

   // --- fail-closed instrument params ---
   {
      string f[8];
      f[0]=MSZZ_SCREENING_INSTRUMENT_PARAMS_V2; f[1]="XAUUSD"; f[2]="5";
      f[3]="0.0100000000000000"; f[4]="0.0100000000000000"; f[5]="50"; f[6]="30"; f[7]="30";
      string bad=CMSZZScreeningMarketV2::InstrumentParamsHeader()+"\r\n"+RawRecord(f)+"\r\n";
      uchar bd[]; Bytes(bad,bd);
      MSZZScreeningInstrumentParamsV2 bp;
      Check(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(bd,bp,reason) &&
            reason=="INSTRUMENT_MINIMUM_DISTANCE_MISMATCH","params minimum mismatch rejected");
   }
   {
      string bad=CMSZZScreeningMarketV2::InstrumentParamsDocument("XAUUSD",5,0.01,0.015,0,0);
      uchar bd[]; Bytes(bad,bd);
      MSZZScreeningInstrumentParamsV2 bp;
      Check(!CMSZZScreeningMarketV2::ParseInstrumentParamsBytes(bd,bp,reason) &&
            reason=="INSTRUMENT_GRID_INCOMPATIBLE","params grid incompatible rejected");
   }

   PrintFormat("TEST_SUMMARY tests=%d failures=%d",g_tests,g_failures);
}
