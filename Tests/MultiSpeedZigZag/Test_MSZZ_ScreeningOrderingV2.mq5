#property strict
#define MSZZ_SCREENING_FIXTURE_ACCESS
#include <MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh>

// ORDERING (OR) certification harness. Reads the language-neutral
// ordering_fixtures.csv, sorts each fixture's candidates with the exact frozen
// UTF-8 bytewise comparator, and asserts the expected rank of every candidate.
// Fail-closed: structural problems emit HARNESS_FAILURE and block a green
// summary; each fixture emits exactly one FIXTURE_RESULT marker.

#define OR_VERSION "MSZZ_SCREENING_ORDERING_FIXTURES_V2"

int g_tests=0, g_failures=0, g_harness=0, g_fixfail=0, g_markers=0;
string g_run_id="";

void Check(const bool ok,const string what){ g_tests++; if(!ok){ g_failures++; Print("assert FAIL: ",what);} }
void Harness(const string group,const string code,const string detail)
{ g_harness++; g_failures++; PrintFormat("HARNESS_FAILURE [%s] %s %s",group,code,detail); }
void Marker(const string id,const bool pass)
{ g_markers++; if(!pass){ g_fixfail++; } PrintFormat("FIXTURE_RESULT [%s] %s",id,(pass?"PASS":"FAIL")); }

bool ReadFileString(const string name,string &out)
{
   int h=FileOpen(name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   ulong size=FileSize(h); uchar data[]; ArrayResize(data,(int)size);
   uint rd=(size>0 ? FileReadArray(h,data,0,(uint)size) : 0);
   FileClose(h);
   if((ulong)rd!=size) return false;
   out=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
   return true;
}
void SplitLines(const string doc,string &lines[])
{
   ArrayResize(lines,0); int start=0,len=StringLen(doc);
   for(int i=0;i<len-1;i++)
      if(StringSubstr(doc,i,1)=="\r" && StringSubstr(doc,i+1,1)=="\n")
      { int n=ArraySize(lines); ArrayResize(lines,n+1); lines[n]=StringSubstr(doc,start,i-start); i++; start=i+1; }
}

// current fixture accumulator
string cur_id="";
MSZZScreeningCandidateV2 cur[];       // candidates in input order (strategy_id = expected rank)
int cur_ranks[];                      // expected ranks (parallel)
bool cur_bad=false;

void ResetFixture(const string id){ cur_id=id; ArrayResize(cur,0); ArrayResize(cur_ranks,0); cur_bad=false; }

void FinishFixture()
{
   if(cur_id=="") return;
   if(cur_bad){ Marker(cur_id,false); return; }
   int n=ArraySize(cur);
   // ranks must be a permutation of 0..n-1
   bool seen[]; ArrayResize(seen,n); for(int i=0;i<n;i++) seen[i]=false;
   bool ok=true;
   for(int i=0;i<n;i++){ int r=cur_ranks[i]; if(r<0 || r>=n || seen[r]){ ok=false; break; } seen[r]=true; }
   if(!ok){ Harness("ORDERING","BAD_RANKS",cur_id); Marker(cur_id,false); return; }
   // sort a copy with the real comparator; strategy_id carries the expected rank
   MSZZScreeningCandidateV2 arr[]; ArrayResize(arr,n); for(int i=0;i<n;i++) arr[i]=cur[i];
   CMSZZScreeningSimulatorV2::SortCandidatesForFixtures(arr);
   bool pass=true;
   for(int p=0;p<n;p++) if(arr[p].strategy_id!=p) pass=false;
   Check(pass,"["+cur_id+"] sorted order matches expected ranks");
   Marker(cur_id,pass);
}

void OnStart()
{
   if(!ReadFileString("cert_run_id.txt",g_run_id)) { Harness("ORDERING","MISSING_RUN_ID",""); }
   else { StringReplace(g_run_id,"\r",""); StringReplace(g_run_id,"\n",""); }

   string doc;
   if(!ReadFileString("ordering_fixtures.csv",doc)){ Harness("ORDERING","MISSING_FILE","ordering_fixtures.csv"); Summary(); return; }
   string lines[]; SplitLines(doc,lines);
   if(ArraySize(lines)<2 || lines[0]!=OR_VERSION){ Harness("ORDERING","BAD_VERSION",(ArraySize(lines)>0?lines[0]:"")); Summary(); return; }

   string seen_ids[];
   for(int i=2;i<ArraySize(lines);i++)   // lines[1] is the column header
   {
      string f[]; string r;
      if(!CMSZZScreeningMarketV2::ParseQuotedRecord(lines[i],f,r)){ Harness("ORDERING","MALFORMED_ROW","line="+IntegerToString(i)); continue; }
      if(ArraySize(f)!=7){ Harness("ORDERING","FIELD_COUNT","line="+IntegerToString(i)); continue; }
      string id=f[0];
      if(id!=cur_id)
      {
         FinishFixture();
         // duplicate (non-contiguous) fixture id guard
         for(int k=0;k<ArraySize(seen_ids);k++) if(seen_ids[k]==id) Harness("ORDERING","DUPLICATE_FIXTURE",id);
         int sn=ArraySize(seen_ids); ArrayResize(seen_ids,sn+1); seen_ids[sn]=id;
         ResetFixture(id);
      }
      int idx=(int)StringToInteger(f[1]);
      int rank=(int)StringToInteger(f[6]);
      if(IntegerToString(idx)!=f[1] || IntegerToString(rank)!=f[6]){ cur_bad=true; Harness("ORDERING","BAD_NUMERIC","line="+IntegerToString(i)); }
      int n=ArraySize(cur);
      if(idx!=n){ cur_bad=true; Harness("ORDERING","IDX_ORDER",cur_id+" line="+IntegerToString(i)); }
      ArrayResize(cur,n+1); ArrayResize(cur_ranks,n+1);
      cur[n].strategy_id=rank; cur[n].family_id=(int)StringToInteger(f[3]);
      cur[n].signal_time=(long)StringToInteger(f[2]);
      cur[n].event_id=f[4]; cur[n].sequence_id=f[5];
      cur[n].hypothesis_version=""; cur[n].canonical_variant_id=""; cur[n].origin_id="";
      cur[n].clock_domain=""; cur[n].time_authority_id=""; cur[n].direction=1;
      cur[n].entry=0; cur[n].stop=0; cur[n].target=0; cur[n].target_r=0; cur[n].stop_distance_points=0;
      cur[n].expiry_time=0;
      cur_ranks[n]=rank;
   }
   FinishFixture();

   // inventory: exactly 13 unique OR fixtures
   if(ArraySize(seen_ids)!=13) Harness("ORDERING","INVENTORY","or="+IntegerToString(ArraySize(seen_ids)));
   Summary();
}

void Summary()
{
   PrintFormat("TEST_SUMMARY tests=%d failures=%d fixtures=13 f=0 jb=0 or=%d markers=%d fixture_failures=%d harness_failures=%d cert_run=%s",
               g_tests,g_failures,g_markers,g_markers,g_fixfail,g_harness,g_run_id);
}
