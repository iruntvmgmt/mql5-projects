#ifndef __MSZZ_SCREENING_JOURNAL_BINDING_V2_MQH__
#define __MSZZ_SCREENING_JOURNAL_BINDING_V2_MQH__

// Journal-to-screening binding adapter. Dependency direction is one-way:
//   ResearchJournalTransportV2 -> this adapter -> ScreeningSimulatorV2.
// It reconstructs the simulator candidate projection from the exact canonical
// journal bytes verified by JournalTransportV2, computes a versioned projection
// digest byte-identical to the Python adapter, and exposes the CERTIFIED public
// entry point RunScreening(bundle, ...). An unbound candidate run is
// structurally impossible on this path: candidates are re-derived from the
// bundle's own verified journal bytes and every claimed field must match.

#include <MultiSpeedZigZag/Research/ResearchJournalTransportV2.mqh>
// Grant this certified adapter (and only this compilation path) the bound bridge
// into the private execution core. Must be defined before the first include of
// the simulator header so the gated wrapper is compiled into the class. Consumers
// that include this adapter get the bundle-only public entry below.
#define MSZZ_SCREENING_BOUND_ADAPTER_ACCESS
#include <MultiSpeedZigZag/Research/ScreeningSimulatorV2.mqh>

#define MSZZ_VERIFIED_JOURNAL_TRANSPORT_V2 "MSZZ_RESEARCH_JOURNAL_TRANSPORT_V2"

struct MSZZVerifiedScreeningJournalV2
{
   string bundle_version;
   string transport_version;
   string schema_version;
   string projection_version;
   string symbol;
   int    timeframe;
   string source_data_sha256;
   string journal_sha256;
   long   row_count;
   string projection_sha256;
   uchar  journal_bytes[];
   MSZZScreeningCandidateV2 candidates[];
   MSZZResearchJournalManifestV2 manifest;   // verified at build; re-checked at run
};

class CMSZZScreeningJournalBindingV2
{
private:
   static string ProjQuote(const string v)
   {
      string out="\"";
      int n=StringLen(v);
      for(int i=0;i<n;i++)
      {
         string ch=StringSubstr(v,i,1);
         if(ch=="\"") out+="\"\""; else out+=ch;
      }
      out+="\"";
      return out;
   }
   // Canonical projection record: 17 fields in the frozen order, direction
   // normalized to +-1, every other field the journal string verbatim.
   static string ProjectionRecord(const string &f[])
   {
      string dir=(f[12]=="LONG" ? "1" : (f[12]=="SHORT" ? "-1" : "?"));
      int cols[]={1,2,3,4,5,6,7,8,9,10,11,-1,13,14,15,28,27};
      string r="";
      for(int i=0;i<17;i++)
      {
         if(i>0) r+=",";
         r+=(cols[i]==-1 ? ProjQuote(dir) : ProjQuote(f[cols[i]]));
      }
      return r;
   }
   static bool ProjectCandidate(const string &f[],MSZZScreeningCandidateV2 &c,string &reason)
   {
      if(f[12]!="LONG" && f[12]!="SHORT") { reason="INVALID_DIRECTION"; return false; }
      c.strategy_id=(int)StringToInteger(f[1]);
      c.family_id=(int)StringToInteger(f[2]);
      c.hypothesis_version=f[3];
      c.canonical_variant_id=f[4];
      c.origin_id=f[5];
      c.sequence_id=f[6];
      c.event_id=f[7];
      c.clock_domain=f[8];
      c.time_authority_id=f[9];
      c.signal_time=(long)StringToInteger(f[10]);
      c.expiry_time=(long)StringToInteger(f[11]);
      c.direction=(f[12]=="LONG" ? 1 : -1);
      c.entry=StringToDouble(f[13]);
      c.stop=StringToDouble(f[14]);
      c.target=StringToDouble(f[15]);
      c.target_r=StringToDouble(f[28]);
      c.stop_distance_points=StringToDouble(f[27]);
      return true;
   }
   // Validate bytes through the certified transport, project candidates, and
   // compute the projection SHA. Single source of the re-derivation used by both
   // the builder and the public entry (mutation/forgery guard).
   static bool DeriveFromBytes(const uchar &data[],MSZZScreeningCandidateV2 &cands[],
                               string &projection_sha,long &row_count,
                               string &journal_sha,string &reason)
   {
      string records[];
      if(!CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(data,records,row_count,journal_sha,reason))
         return false;
      string projdoc=MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2+"\r\n";
      ArrayResize(cands,0);
      for(int r=1;r<ArraySize(records);r++)
      {
         string f[];
         if(!CMSZZResearchJournalTransportV2::ParseRecord(records[r],f,reason,true)) return false;
         projdoc+=ProjectionRecord(f)+"\r\n";
         MSZZScreeningCandidateV2 sc;
         if(!ProjectCandidate(f,sc,reason)) return false;
         int n=ArraySize(cands); ArrayResize(cands,n+1); cands[n]=sc;
      }
      uchar pb[];
      StringToCharArray(projdoc,pb,0,-1,CP_UTF8);
      if(ArraySize(pb)>0) ArrayResize(pb,ArraySize(pb)-1);  // drop terminating null
      return CMSZZResearchJournalTransportV2::Sha256Bytes(pb,projection_sha,reason);
   }
   static bool SameCandidates(const MSZZScreeningCandidateV2 &a[],const MSZZScreeningCandidateV2 &b[])
   {
      if(ArraySize(a)!=ArraySize(b)) return false;
      for(int i=0;i<ArraySize(a);i++)
      {
         if(a[i].strategy_id!=b[i].strategy_id || a[i].family_id!=b[i].family_id) return false;
         if(a[i].hypothesis_version!=b[i].hypothesis_version) return false;
         if(a[i].canonical_variant_id!=b[i].canonical_variant_id) return false;
         if(a[i].origin_id!=b[i].origin_id || a[i].sequence_id!=b[i].sequence_id) return false;
         if(a[i].event_id!=b[i].event_id) return false;
         if(a[i].clock_domain!=b[i].clock_domain || a[i].time_authority_id!=b[i].time_authority_id) return false;
         if(a[i].signal_time!=b[i].signal_time || a[i].expiry_time!=b[i].expiry_time) return false;
         if(a[i].direction!=b[i].direction) return false;
         if(a[i].entry!=b[i].entry || a[i].stop!=b[i].stop || a[i].target!=b[i].target) return false;
         if(a[i].target_r!=b[i].target_r || a[i].stop_distance_points!=b[i].stop_distance_points) return false;
      }
      return true;
   }

public:
   static bool BuildVerifiedBundle(const uchar &data[],
                                   const MSZZResearchJournalManifestV2 &manifest,
                                   const string symbol,const int timeframe,
                                   const string source_data_sha256,
                                   MSZZVerifiedScreeningJournalV2 &bundle,string &reason)
   {
      MSZZScreeningCandidateV2 cands[];
      string projection_sha=""; long row_count=0; string journal_sha="";
      if(!DeriveFromBytes(data,cands,projection_sha,row_count,journal_sha,reason)) return false;
      if(manifest.manifest_version!=MSZZ_RESEARCH_MANIFEST_V2 ||
         manifest.writer_version!=MSZZ_RESEARCH_WRITER_V2 ||
         manifest.schema_version!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2)
      { reason="MANIFEST_VERSION_MISMATCH"; return false; }
      if(manifest.symbol!=symbol || manifest.timeframe!=timeframe)
      { reason="MANIFEST_MARKET_MISMATCH"; return false; }
      if(manifest.source_data_sha256!=source_data_sha256)
      { reason="SOURCE_DATA_HASH_MISMATCH"; return false; }
      if(manifest.row_count!=row_count) { reason="ROW_COUNT_MISMATCH"; return false; }
      if(manifest.journal_sha256!=journal_sha) { reason="JOURNAL_HASH_MISMATCH"; return false; }

      bundle.bundle_version=MSZZ_VERIFIED_CANDIDATE_JOURNAL_V2;
      bundle.transport_version=MSZZ_VERIFIED_JOURNAL_TRANSPORT_V2;
      bundle.schema_version=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2;
      bundle.projection_version=MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2;
      bundle.symbol=symbol; bundle.timeframe=timeframe;
      bundle.source_data_sha256=source_data_sha256;
      bundle.journal_sha256=journal_sha; bundle.row_count=row_count;
      bundle.projection_sha256=projection_sha;
      ArrayResize(bundle.journal_bytes,ArraySize(data));
      ArrayCopy(bundle.journal_bytes,data);
      ArrayResize(bundle.candidates,ArraySize(cands));
      for(int i=0;i<ArraySize(cands);i++) bundle.candidates[i]=cands[i];
      bundle.manifest=manifest;
      reason="OK";
      return true;
   }

   // Re-verify the retained manifest against authoritative re-derived values.
   static bool ManifestBindingOk(const MSZZResearchJournalManifestV2 &m,
                                 const string journal_sha,const long row_count,
                                 const string symbol,const int timeframe,const string source_sha)
   {
      if(m.manifest_version!=MSZZ_RESEARCH_MANIFEST_V2 || m.writer_version!=MSZZ_RESEARCH_WRITER_V2 ||
         m.schema_version!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2) return false;
      if(m.symbol!=symbol || m.timeframe!=timeframe) return false;
      if(m.source_data_sha256!=source_sha) return false;
      if(m.row_count!=row_count) return false;
      if(m.journal_sha256!=journal_sha) return false;
      return true;
   }

   // Certified public entry point (bundle-only). Re-derives from the bundle's own
   // journal bytes and proves journal SHA, projection SHA, row count, market
   // binding and candidate identity before invoking the execution core.
   static string RunScreening(const MSZZVerifiedScreeningJournalV2 &bundle,
                              const MSZZScreeningMarketBarV2 &bars[],
                              const string market_symbol,const int market_tf,const string market_sha,
                              const MSZZScreeningMarketManifestV2 &mm,
                              const MSZZScreeningInstrumentParamsV2 &params,
                              const string policy_id,const long test_end_in,
                              MSZZScreeningOutcomeV2 &outcomes[])
   {
      ArrayResize(outcomes,0);
      if(bundle.bundle_version!=MSZZ_VERIFIED_CANDIDATE_JOURNAL_V2 ||
         bundle.transport_version!=MSZZ_VERIFIED_JOURNAL_TRANSPORT_V2 ||
         bundle.schema_version!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2 ||
         bundle.projection_version!=MSZZ_VERIFIED_SCREENING_CANDIDATE_PROJECTION_V2)
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;

      MSZZScreeningCandidateV2 rederived[];
      string proj_sha=""; long row_count=0; string journal_sha=""; string reason="";
      if(!DeriveFromBytes(bundle.journal_bytes,rederived,proj_sha,row_count,journal_sha,reason))
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;
      if(bundle.journal_sha256!=journal_sha || bundle.projection_sha256!=proj_sha ||
         bundle.row_count!=row_count)
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;
      if(bundle.source_data_sha256!=market_sha || bundle.symbol!=market_symbol ||
         bundle.timeframe!=market_tf)
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;
      // Re-verify the retained manifest against authoritative re-derived values
      // (do not trust stored fields on a mutable struct).
      if(!ManifestBindingOk(bundle.manifest,journal_sha,row_count,bundle.symbol,bundle.timeframe,bundle.source_data_sha256))
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;
      // Mutation guard: bundle-owned candidates must equal the re-derivation that
      // produced the frozen projection SHA (stronger than reserializing doubles).
      if(!SameCandidates(bundle.candidates,rederived))
         return MSZZ_SIM_REJECT_CANDIDATE_JOURNAL_BINDING_MISMATCH;

      MSZZScreeningCandidateManifestV2 cm;
      cm.symbol=bundle.symbol; cm.timeframe=bundle.timeframe;
      cm.journal_sha256=bundle.journal_sha256; cm.source_data_sha256=bundle.source_data_sha256;

      MSZZScreeningCandidateV2 local[];
      ArrayResize(local,ArraySize(rederived));
      for(int i=0;i<ArraySize(rederived);i++) local[i]=rederived[i];
      return CMSZZScreeningSimulatorV2::RunScreeningBoundCore(
                local,cm,bars,market_symbol,market_tf,market_sha,mm,params,policy_id,test_end_in,outcomes);
   }
};
#endif
