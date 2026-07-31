#ifndef __MSZZ_SCREENING_MARKET_V2_MQH__
#define __MSZZ_SCREENING_MARKET_V2_MQH__

// Strict canonical INTEGER market/instrument transports for the standalone
// screening simulator. Real-data-safe: OHLC are signed integer point counts and
// instrument sizes are integer 1e-8 units, so ordinary decimal prices are exact
// and nothing in the transport or the SHA-256 depends on float formatting.
// Prices are reconstructed only at simulation time as points * point_size, where
// point_size = point_size_1e8 / 1e8 (1e8 is binary-exact -> identical double in
// MQL5 and Python). Family-neutral; touches no family generator, production
// path, or the certified candidate JournalTransportV2. Byte conventions mirror
// the certified research transport and match screening_market_v2.py.

#define MSZZ_SCREENING_MARKET_DATA_V2       "MSZZ_SCREENING_MARKET_DATA_V2"
#define MSZZ_SCREENING_MARKET_MANIFEST_V2   "MSZZ_SCREENING_MARKET_MANIFEST_V2"
#define MSZZ_SCREENING_INSTRUMENT_PARAMS_V2 "MSZZ_SCREENING_INSTRUMENT_PARAMS_V2"
#define MSZZ_SCREENING_CLOCK_DOMAIN         "BROKER_SERVER_RAW"
#define MSZZ_SCREENING_TIME_AUTHORITY       "MSZZ_TIME_RAW_BROKER_V1"
#define MSZZ_SCREENING_PRICE_SCALE_1E8      100000000.0

struct MSZZScreeningMarketBarV2
{
   long time_raw;
   long open_points;
   long high_points;
   long low_points;
   long close_points;
   long spread_points;
};

struct MSZZScreeningMarketManifestV2
{
   string manifest_version;
   string market_data_version;
   string symbol;
   int    timeframe;
   string clock_domain;
   string time_authority_id;
   long   row_count;
   string market_data_sha256;
};

struct MSZZScreeningInstrumentParamsV2
{
   string params_version;
   string symbol;
   int    timeframe;
   long   point_size_1e8;
   long   tick_size_1e8;
   long   stops_level_points;
   long   freeze_level_points;
   long   minimum_distance_points;
   string params_sha256;
};

class CMSZZScreeningMarketV2
{
private:
   static bool HexDigit(const ushort value)
   {
      return (value>='0' && value<='9') || (value>='a' && value<='f');
   }

   static string Quote(const string value)
   {
      string escaped="";
      for(int i=0;i<StringLen(value);i++)
      {
         string character=StringSubstr(value,i,1);
         escaped+=(character=="\"" ? "\"\"" : character);
      }
      return "\""+escaped+"\"";
   }

   static string CanonicalRecord(const string &fields[])
   {
      string result="";
      for(int i=0;i<ArraySize(fields);i++)
      {
         if(i>0) result+=",";
         result+=Quote(fields[i]);
      }
      return result;
   }

   static bool ValidateUtf8(const uchar &data[],string &reason)
   {
      int size=ArraySize(data);
      if(size>=3 && data[0]==0xEF && data[1]==0xBB && data[2]==0xBF)
      { reason="UTF8_BOM_FORBIDDEN"; return false; }
      for(int i=0;i<size;)
      {
         int b=(int)data[i];
         if(b<=0x7F) { i++; continue; }
         int need=0; uint code=0;
         if(b>=0xC2 && b<=0xDF) { need=1; code=(uint)(b&0x1F); }
         else if(b>=0xE0 && b<=0xEF) { need=2; code=(uint)(b&0x0F); }
         else if(b>=0xF0 && b<=0xF4) { need=3; code=(uint)(b&0x07); }
         else { reason="INVALID_UTF8"; return false; }
         if(i+need>=size) { reason="TRUNCATED_UTF8"; return false; }
         for(int j=1;j<=need;j++)
         {
            int continuation=(int)data[i+j];
            if((continuation&0xC0)!=0x80) { reason="INVALID_UTF8_CONTINUATION"; return false; }
            code=(code<<6)|(uint)(continuation&0x3F);
         }
         if((need==2 && code<0x800) || (need==3 && code<0x10000) ||
            (code>=0xD800 && code<=0xDFFF) || code>0x10FFFF)
         { reason="NONCANONICAL_UTF8"; return false; }
         i+=need+1;
      }
      return true;
   }

   static bool SplitDocument(const string document,string &records[],string &reason)
   {
      ArrayResize(records,0);
      bool quoted=false;
      int start=0;
      int length=StringLen(document);
      for(int i=0;i<length;i++)
      {
         string character=StringSubstr(document,i,1);
         if(character=="\"")
         {
            if(quoted && i+1<length && StringSubstr(document,i+1,1)=="\"") i++;
            else quoted=!quoted;
            continue;
         }
         if(character=="\n" && !quoted) { reason="BARE_LF"; return false; }
         if(character=="\r" && !quoted)
         {
            if(i+1>=length || StringSubstr(document,i+1,1)!="\n")
            { reason="BARE_CR"; return false; }
            int count=ArraySize(records);
            ArrayResize(records,count+1);
            records[count]=StringSubstr(document,start,i-start);
            i++;
            start=i+1;
         }
      }
      if(quoted) { reason="UNCLOSED_QUOTE"; return false; }
      if(start<length) { reason="MISSING_FINAL_CRLF"; return false; }
      if(start==0 && length==0) { reason="EMPTY_DOCUMENT"; return false; }
      if(ArraySize(records)>0 && records[ArraySize(records)-1]=="")
      { reason="EMPTY_RECORD"; return false; }
      return true;
   }

   static bool IntegerExact(const string value,long &parsed)
   {
      if(value=="") return false;
      parsed=(long)StringToInteger(value);
      return StringFormat("%I64d",parsed)==value;
   }

   static bool ReadBytes(const string file_name,uchar &data[],string &reason)
   {
      ArrayResize(data,0);
      int handle=FileOpen(file_name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE) { reason="FILE_OPEN_FAILED"; return false; }
      ulong size=FileSize(handle);
      if(size>2147483647) { FileClose(handle); reason="INVALID_FILE_SIZE"; return false; }
      ArrayResize(data,(int)size);
      uint read=(size>0 ? FileReadArray(handle,data,0,(uint)size) : 0);
      FileClose(handle);
      if((ulong)read!=size) { reason="FILE_READ_FAILED"; return false; }
      return true;
   }

public:
   static bool IsSha256(const string value)
   {
      if(StringLen(value)!=64) return false;
      for(int i=0;i<64;i++)
         if(!HexDigit(StringGetCharacter(value,i))) return false;
      return true;
   }

   static bool Sha256Bytes(const uchar &data[],string &hex,string &reason)
   {
      uchar key[]; uchar digest[];
      ArrayResize(key,0);
      ResetLastError();
      int count=CryptEncode(CRYPT_HASH_SHA256,data,key,digest);
      if(count!=32) { reason="SHA256_FAILED_"+IntegerToString(GetLastError()); return false; }
      hex="";
      for(int i=0;i<count;i++) hex+=StringFormat("%02x",(int)digest[i]);
      reason="OK";
      return true;
   }

   static bool ParseQuotedRecord(const string record,string &fields[],string &reason)
   {
      ArrayResize(fields,0);
      int length=StringLen(record);
      int i=0;
      while(i<length)
      {
         if(StringSubstr(record,i,1)!="\"") { reason="UNQUOTED_FIELD"; return false; }
         i++;
         string field=""; bool closed=false;
         while(i<length)
         {
            string character=StringSubstr(record,i,1);
            if(character=="\"")
            {
               if(i+1<length && StringSubstr(record,i+1,1)=="\"")
               { field+="\""; i+=2; continue; }
               closed=true; i++; break;
            }
            field+=character; i++;
         }
         if(!closed) { reason="UNCLOSED_QUOTE"; return false; }
         int count=ArraySize(fields);
         ArrayResize(fields,count+1);
         fields[count]=field;
         if(i==length) break;
         if(StringSubstr(record,i,1)!=",") { reason="TRAILING_AFTER_QUOTE"; return false; }
         i++;
         if(i==length) { reason="UNQUOTED_FIELD"; return false; }
      }
      if(length==0) { reason="EMPTY_RECORD"; return false; }
      reason="OK";
      return true;
   }

   // Reconstruct an actual price from an integer point count and point_size_1e8.
   static double PointsToPrice(const long points,const long point_size_1e8)
   {
      double point_size=(double)point_size_1e8/MSZZ_SCREENING_PRICE_SCALE_1E8;
      return (double)points*point_size;
   }

   // ------------------------------------------------------------------
   // Market data (MSZZ_SCREENING_MARKET_DATA_V2) — integer point counts
   // ------------------------------------------------------------------
   static string MarketDataHeader()
   {
      return "market_data_version,symbol,timeframe,clock_domain,time_authority_id,"
             "time_raw,open_points,high_points,low_points,close_points,spread_points";
   }

   static string MarketBarRow(const string symbol,const int timeframe,
                              const MSZZScreeningMarketBarV2 &bar)
   {
      string fields[11];
      fields[0]=MSZZ_SCREENING_MARKET_DATA_V2;
      fields[1]=symbol;
      fields[2]=IntegerToString(timeframe);
      fields[3]=MSZZ_SCREENING_CLOCK_DOMAIN;
      fields[4]=MSZZ_SCREENING_TIME_AUTHORITY;
      fields[5]=StringFormat("%I64d",bar.time_raw);
      fields[6]=StringFormat("%I64d",bar.open_points);
      fields[7]=StringFormat("%I64d",bar.high_points);
      fields[8]=StringFormat("%I64d",bar.low_points);
      fields[9]=StringFormat("%I64d",bar.close_points);
      fields[10]=StringFormat("%I64d",bar.spread_points);
      return CanonicalRecord(fields);
   }

   static string MarketDataDocument(const string symbol,const int timeframe,
                                    const MSZZScreeningMarketBarV2 &bars[])
   {
      string document=MarketDataHeader();
      for(int i=0;i<ArraySize(bars);i++)
         document+="\r\n"+MarketBarRow(symbol,timeframe,bars[i]);
      document+="\r\n";
      return document;
   }

   static bool ParseMarketDataBytes(const uchar &data[],MSZZScreeningMarketBarV2 &bars[],
                                    string &symbol,int &timeframe,string &sha256,
                                    string &reason)
   {
      ArrayResize(bars,0);
      symbol=""; timeframe=0; sha256="";
      if(!ValidateUtf8(data,reason)) return false;
      if(!Sha256Bytes(data,sha256,reason)) return false;
      string document=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
      string records[];
      if(!SplitDocument(document,records,reason)) return false;
      if(ArraySize(records)<1) { reason="MISSING_HEADER"; return false; }
      if(records[0]!=MarketDataHeader()) { reason="MARKET_HEADER_MISMATCH"; return false; }

      bool have_market=false;
      long previous_time=0;
      for(int r=1;r<ArraySize(records);r++)
      {
         string f[];
         if(!ParseQuotedRecord(records[r],f,reason)) return false;
         if(ArraySize(f)!=11) { reason="MARKET_COLUMN_COUNT_MISMATCH"; return false; }
         if(CanonicalRecord(f)!=records[r]) { reason="NONCANONICAL_RECORD"; return false; }
         if(f[0]!=MSZZ_SCREENING_MARKET_DATA_V2)
         { reason="UNSUPPORTED_MARKET_DATA_VERSION"; return false; }
         if(f[1]=="") { reason="MISSING_MARKET_SYMBOL"; return false; }
         long tf=0;
         if(!IntegerExact(f[2],tf)) { reason="INVALID_INTEGER"; return false; }
         if(f[3]!=MSZZ_SCREENING_CLOCK_DOMAIN || f[4]!=MSZZ_SCREENING_TIME_AUTHORITY)
         { reason="UNSUPPORTED_MARKET_TIME_AUTHORITY"; return false; }
         if(!have_market) { symbol=f[1]; timeframe=(int)tf; have_market=true; }
         else if(f[1]!=symbol || (int)tf!=timeframe)
         { reason="INCONSISTENT_MARKET_MARKET"; return false; }

         long time_raw=0,open_points=0,high_points=0,low_points=0,close_points=0,spread=0;
         if(!IntegerExact(f[5],time_raw) || !IntegerExact(f[6],open_points) ||
            !IntegerExact(f[7],high_points) || !IntegerExact(f[8],low_points) ||
            !IntegerExact(f[9],close_points) || !IntegerExact(f[10],spread))
         { reason="INVALID_INTEGER"; return false; }

         if(time_raw<=0) { reason="INVALID_MARKET_BAR"; return false; }
         if(r>1)
         {
            if(time_raw==previous_time) { reason="DUPLICATE_MARKET_TIME"; return false; }
            if(time_raw<previous_time) { reason="NON_MONOTONIC_MARKET_TIME"; return false; }
         }
         if(open_points<=0 || high_points<=0 || low_points<=0 || close_points<=0)
         { reason="INVALID_MARKET_BAR"; return false; }
         long hi_ref=(open_points>close_points ? open_points : close_points);
         long lo_ref=(open_points<close_points ? open_points : close_points);
         if(high_points<hi_ref || low_points>lo_ref)
         { reason="INVALID_MARKET_BAR"; return false; }
         if(high_points<low_points) { reason="INVALID_MARKET_BAR"; return false; }
         if(spread<0) { reason="INVALID_SPREAD"; return false; }

         int count=ArraySize(bars);
         ArrayResize(bars,count+1);
         bars[count].time_raw=time_raw;
         bars[count].open_points=open_points;
         bars[count].high_points=high_points;
         bars[count].low_points=low_points;
         bars[count].close_points=close_points;
         bars[count].spread_points=spread;
         previous_time=time_raw;
      }
      if(!have_market || ArraySize(bars)==0) { reason="EMPTY_MARKET_DATA"; return false; }
      reason="OK";
      return true;
   }

   // ------------------------------------------------------------------
   // Market manifest (MSZZ_SCREENING_MARKET_MANIFEST_V2)
   // ------------------------------------------------------------------
   static string MarketManifestHeader()
   {
      return "manifest_version,market_data_version,symbol,timeframe,clock_domain,"
             "time_authority_id,row_count,market_data_sha256";
   }

   static void BuildMarketManifest(const string symbol,const int timeframe,
                                   const long row_count,const string market_data_sha256,
                                   MSZZScreeningMarketManifestV2 &manifest)
   {
      manifest.manifest_version=MSZZ_SCREENING_MARKET_MANIFEST_V2;
      manifest.market_data_version=MSZZ_SCREENING_MARKET_DATA_V2;
      manifest.symbol=symbol;
      manifest.timeframe=timeframe;
      manifest.clock_domain=MSZZ_SCREENING_CLOCK_DOMAIN;
      manifest.time_authority_id=MSZZ_SCREENING_TIME_AUTHORITY;
      manifest.row_count=row_count;
      manifest.market_data_sha256=market_data_sha256;
   }

   static string MarketManifestRow(const MSZZScreeningMarketManifestV2 &manifest)
   {
      string fields[8];
      fields[0]=manifest.manifest_version;
      fields[1]=manifest.market_data_version;
      fields[2]=manifest.symbol;
      fields[3]=IntegerToString(manifest.timeframe);
      fields[4]=manifest.clock_domain;
      fields[5]=manifest.time_authority_id;
      fields[6]=StringFormat("%I64d",manifest.row_count);
      fields[7]=manifest.market_data_sha256;
      return CanonicalRecord(fields);
   }

   static string MarketManifestDocument(const MSZZScreeningMarketManifestV2 &manifest)
   {
      return MarketManifestHeader()+"\r\n"+MarketManifestRow(manifest)+"\r\n";
   }

   static bool ParseMarketManifestDocument(const string document,
                                           MSZZScreeningMarketManifestV2 &manifest,
                                           string &reason)
   {
      string records[];
      if(!SplitDocument(document,records,reason)) return false;
      if(ArraySize(records)!=2 || records[0]!=MarketManifestHeader())
      { reason="MARKET_MANIFEST_SHAPE_MISMATCH"; return false; }
      string f[];
      if(!ParseQuotedRecord(records[1],f,reason)) return false;
      if(ArraySize(f)!=8 || CanonicalRecord(f)!=records[1])
      { reason="MARKET_MANIFEST_SHAPE_MISMATCH"; return false; }
      long timeframe=0,row_count=0;
      if(!IntegerExact(f[3],timeframe) || !IntegerExact(f[6],row_count))
      { reason="INVALID_MARKET_MANIFEST_FIELD"; return false; }
      if(f[0]!=MSZZ_SCREENING_MARKET_MANIFEST_V2 ||
         f[1]!=MSZZ_SCREENING_MARKET_DATA_V2 || f[2]=="" ||
         f[4]!=MSZZ_SCREENING_CLOCK_DOMAIN || f[5]!=MSZZ_SCREENING_TIME_AUTHORITY ||
         row_count<0 || !IsSha256(f[7]))
      { reason="INVALID_MARKET_MANIFEST_FIELD"; return false; }
      manifest.manifest_version=f[0];
      manifest.market_data_version=f[1];
      manifest.symbol=f[2];
      manifest.timeframe=(int)timeframe;
      manifest.clock_domain=f[4];
      manifest.time_authority_id=f[5];
      manifest.row_count=row_count;
      manifest.market_data_sha256=f[7];
      reason="OK";
      return true;
   }

   static bool VerifyMarketManifest(const MSZZScreeningMarketManifestV2 &manifest,
                                    const string symbol,const int timeframe,
                                    const long row_count,const string market_data_sha256,
                                    string &reason)
   {
      if(manifest.manifest_version!=MSZZ_SCREENING_MARKET_MANIFEST_V2 ||
         manifest.market_data_version!=MSZZ_SCREENING_MARKET_DATA_V2)
      { reason="MARKET_MANIFEST_VERSION_MISMATCH"; return false; }
      if(manifest.symbol!=symbol || manifest.timeframe!=timeframe)
      { reason="MARKET_MANIFEST_MARKET_MISMATCH"; return false; }
      if(manifest.row_count!=row_count)
      { reason="MARKET_MANIFEST_ROW_COUNT_MISMATCH"; return false; }
      if(manifest.market_data_sha256!=market_data_sha256)
      { reason="MARKET_HASH_MISMATCH"; return false; }
      reason="OK";
      return true;
   }

   // ------------------------------------------------------------------
   // Instrument params (MSZZ_SCREENING_INSTRUMENT_PARAMS_V2) — integer 1e-8 units
   // ------------------------------------------------------------------
   static string InstrumentParamsHeader()
   {
      return "params_version,symbol,timeframe,point_size_1e8,tick_size_1e8,"
             "stops_level_points,freeze_level_points,minimum_distance_points";
   }

   static double PointSize(const MSZZScreeningInstrumentParamsV2 &params)
   {
      return (double)params.point_size_1e8/MSZZ_SCREENING_PRICE_SCALE_1E8;
   }

   static double TickSize(const MSZZScreeningInstrumentParamsV2 &params)
   {
      return (double)params.tick_size_1e8/MSZZ_SCREENING_PRICE_SCALE_1E8;
   }

   static string InstrumentParamsRow(const string symbol,const int timeframe,
                                     const long point_size_1e8,const long tick_size_1e8,
                                     const long stops_level_points,
                                     const long freeze_level_points)
   {
      long minimum=(stops_level_points>freeze_level_points ?
                    stops_level_points : freeze_level_points);
      string fields[8];
      fields[0]=MSZZ_SCREENING_INSTRUMENT_PARAMS_V2;
      fields[1]=symbol;
      fields[2]=IntegerToString(timeframe);
      fields[3]=StringFormat("%I64d",point_size_1e8);
      fields[4]=StringFormat("%I64d",tick_size_1e8);
      fields[5]=StringFormat("%I64d",stops_level_points);
      fields[6]=StringFormat("%I64d",freeze_level_points);
      fields[7]=StringFormat("%I64d",minimum);
      return CanonicalRecord(fields);
   }

   static string InstrumentParamsDocument(const string symbol,const int timeframe,
                                          const long point_size_1e8,const long tick_size_1e8,
                                          const long stops_level_points,
                                          const long freeze_level_points)
   {
      return InstrumentParamsHeader()+"\r\n"+
             InstrumentParamsRow(symbol,timeframe,point_size_1e8,tick_size_1e8,
                                 stops_level_points,freeze_level_points)+"\r\n";
   }

   static bool ParseInstrumentParamsBytes(const uchar &data[],
                                          MSZZScreeningInstrumentParamsV2 &params,
                                          string &reason)
   {
      if(!ValidateUtf8(data,reason)) return false;
      string sha="";
      if(!Sha256Bytes(data,sha,reason)) return false;
      string document=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
      string records[];
      if(!SplitDocument(document,records,reason)) return false;
      if(ArraySize(records)!=2 || records[0]!=InstrumentParamsHeader())
      { reason="INSTRUMENT_PARAMS_SHAPE_MISMATCH"; return false; }
      string f[];
      if(!ParseQuotedRecord(records[1],f,reason)) return false;
      if(ArraySize(f)!=8 || CanonicalRecord(f)!=records[1])
      { reason="INSTRUMENT_PARAMS_SHAPE_MISMATCH"; return false; }
      long timeframe=0,point_size_1e8=0,tick_size_1e8=0,stops=0,freeze=0,minimum=0;
      if(!IntegerExact(f[2],timeframe) || !IntegerExact(f[3],point_size_1e8) ||
         !IntegerExact(f[4],tick_size_1e8) || !IntegerExact(f[5],stops) ||
         !IntegerExact(f[6],freeze) || !IntegerExact(f[7],minimum))
      { reason="INVALID_INSTRUMENT_PARAMS_FIELD"; return false; }
      if(f[0]!=MSZZ_SCREENING_INSTRUMENT_PARAMS_V2 || f[1]=="")
      { reason="INVALID_INSTRUMENT_PARAMS_FIELD"; return false; }
      if(point_size_1e8<=0 || tick_size_1e8<=0 || stops<0 || freeze<0 || minimum<0)
      { reason="INVALID_INSTRUMENT_PARAMS_FIELD"; return false; }
      if(minimum!=(stops>freeze ? stops : freeze))
      { reason="INSTRUMENT_MINIMUM_DISTANCE_MISMATCH"; return false; }
      if((tick_size_1e8%point_size_1e8)!=0)
      { reason="INSTRUMENT_GRID_INCOMPATIBLE"; return false; }
      params.params_version=f[0];
      params.symbol=f[1];
      params.timeframe=(int)timeframe;
      params.point_size_1e8=point_size_1e8;
      params.tick_size_1e8=tick_size_1e8;
      params.stops_level_points=stops;
      params.freeze_level_points=freeze;
      params.minimum_distance_points=minimum;
      params.params_sha256=sha;
      reason="OK";
      return true;
   }

   static bool VerifyInstrumentParams(const MSZZScreeningInstrumentParamsV2 &params,
                                      const string symbol,const int timeframe,
                                      string &reason)
   {
      if(params.symbol!=symbol || params.timeframe!=timeframe)
      { reason="INSTRUMENT_PARAMS_MARKET_MISMATCH"; return false; }
      reason="OK";
      return true;
   }

   static bool VerifyCandidatePointSize(const MSZZScreeningInstrumentParamsV2 &params,
                                        const double risk_price,
                                        const double stop_distance_points,
                                        string &reason)
   {
      if(stop_distance_points<=0.0 || risk_price<=0.0)
      { reason="INSTRUMENT_POINT_SIZE_UNVERIFIABLE"; return false; }
      double point_size=PointSize(params);
      double derived=risk_price/stop_distance_points;
      double tolerance=MathMax(1.0e-12,point_size*1.0e-6);
      if(MathAbs(derived-point_size)>tolerance)
      { reason="INSTRUMENT_POINT_SIZE_MISMATCH"; return false; }
      reason="OK";
      return true;
   }
};

#endif
