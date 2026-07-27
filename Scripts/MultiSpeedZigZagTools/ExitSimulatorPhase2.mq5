//+------------------------------------------------------------------+
//| ExitSimulatorPhase2.mq5                                           |
//| D024: FastMedConfluence Phase 2 exit and holding-tail study.       |
//| Replays FastMedConfluence's fixed SIGNAL_LEVEL entry set against   |
//| 12 models: 11 causal structural/composite models (ExitModelsPhase2)|
//| plus TRAIL_0_5R_AFTER_1R (D021/D022's already-tested model, reused |
//| verbatim for direct comparability). SIGNAL_LEVEL (no occupancy)    |
//| and PORTFOLIO_LEVEL (one-owned-position, chronological occupancy   |
//| per model) both computed, exactly mirroring D021/D022's design.    |
//| See DECISION_LOG.md D024.                                          |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ExitModelsPhase2.mqh>
#include <MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh>

input string InpSignalSetFile="MSZZ_SignalSet.csv";
input string InpTradeOutputFile="MSZZ_Phase2_Trades.csv";
input string InpSummaryOutputFile="MSZZ_Phase2_Summary.csv";
input int    InpForwardWindowDays=7;       // longer than D021's 3d -- structural exits may hold longer in rare cases
input int    InpHistoryBars=1500;          // matches the live EA's InpHistoryBars, for ZigZag warmup at entry
input double InpMinMfeThresholdR=0.1;
input double InpEstimatedCostR=0.02;       // same D021 flat round-trip estimate
input int    InpFastATRLen=14;  input double InpFastATRMult=1.0;
input int    InpMedATRLen=14;   input double InpMedATRMult=2.0;
input int    InpMinBarsBetween=3;
input ENUM_MSZZ_AMBIGUITY_MODE InpAmbiguityMode=MSZZ_AMBIG_PESSIMISTIC;

#define MAX_SIGNALS 800
#define MODEL_COUNT 12

string   g_sig_time_str[MAX_SIGNALS];
datetime g_sig_time[MAX_SIGNALS];
int      g_sig_direction[MAX_SIGNALS];
double   g_sig_entry[MAX_SIGNALS];
double   g_sig_stop[MAX_SIGNALS];
double   g_sig_target[MAX_SIGNALS];
string   g_sig_strategy_id[MAX_SIGNALS];
string   g_sig_cluster_id[MAX_SIGNALS];
int      g_signal_count=0;
string   g_symbol="XAUUSD";
ENUM_TIMEFRAMES g_period=PERIOD_M5;

string   g_model_names[MODEL_COUNT]={
   "CHANDELIER_TRAIL","FAST_SWING_TRAIL","MEDIUM_SWING_TRAIL","HL_LH_TRAIL",
   "OPPOSITE_FAST_EXIT","TIME_8H","TIME_12H","TIME_24H",
   "FIXED_2R_PLUS_TIMEOUT","TRAIL_AFTER_1R","BE_1R_PLUS_TRAIL","SESSION_OVERNIGHT"};

bool     g_resolved[MODEL_COUNT][MAX_SIGNALS];
datetime g_entry_time[MAX_SIGNALS];
datetime g_exit_time[MODEL_COUNT][MAX_SIGNALS];
double   g_exit_price[MODEL_COUNT][MAX_SIGNALS];
string   g_exit_reason[MODEL_COUNT][MAX_SIGNALS];
double   g_gross_r[MODEL_COUNT][MAX_SIGNALS];
double   g_net_r[MODEL_COUNT][MAX_SIGNALS];
int      g_bars_held[MODEL_COUNT][MAX_SIGNALS];
double   g_final_stop[MODEL_COUNT][MAX_SIGNALS];
int      g_trail_updates[MODEL_COUNT][MAX_SIGNALS];
bool     g_sequencing_ambiguous[MODEL_COUNT][MAX_SIGNALS];
double   g_mfe_until_exit_r[MODEL_COUNT][MAX_SIGNALS];
double   g_mae_until_exit_r[MODEL_COUNT][MAX_SIGNALS];
double   g_mfe_r[MAX_SIGNALS];
double   g_mae_r[MAX_SIGNALS];
int      g_bars_to_mfe[MAX_SIGNALS];
datetime g_time_to_mfe[MAX_SIGNALS];
string   g_session_text[MAX_SIGNALS];
string   g_weekday_text[MAX_SIGNALS];

double   g_sig_r_acc[MODEL_COUNT][MAX_SIGNALS];
int      g_sig_r_count[MODEL_COUNT];
double   g_port_r_acc[MODEL_COUNT][MAX_SIGNALS];
int      g_port_r_count[MODEL_COUNT];
int      g_port_skipped[MODEL_COUNT];
int      g_port_qualifying[MODEL_COUNT];
int      g_ambiguous_count[MODEL_COUNT];

int ParseDirection(const string s) { return (s=="L" || s=="LONG") ? 1 : -1; }

string WeekdayName(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   string names[7]={"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"};
   return names[dt.day_of_week];
}

bool LoadSignalSet()
{
   int h=FileOpen(InpSignalSetFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("MSZZ Phase2: failed to open %s error=%d",InpSignalSetFile,GetLastError());
      return false;
   }
   for(int c=0;c<10 && !FileIsEnding(h);c++) FileReadString(h);

   g_signal_count=0;
   while(!FileIsEnding(h) && g_signal_count<MAX_SIGNALS)
   {
      string f[10]; bool complete=true;
      for(int c=0;c<10;c++)
      {
         if(FileIsEnding(h)) { complete=false; break; }
         f[c]=FileReadString(h);
      }
      if(!complete) break;
      int i=g_signal_count;
      g_sig_time_str[i]=f[0]; g_sig_time[i]=StringToTime(f[0]);
      g_sig_direction[i]=ParseDirection(f[1]);
      g_sig_entry[i]=StringToDouble(f[2]); g_sig_stop[i]=StringToDouble(f[3]); g_sig_target[i]=StringToDouble(f[4]);
      g_sig_strategy_id[i]=f[5]; g_sig_cluster_id[i]=f[6];
      if(i==0) g_symbol=f[8];
      g_signal_count++;
   }
   FileClose(h);
   PrintFormat("MSZZ Phase2: loaded %d signals from %s",g_signal_count,InpSignalSetFile);
   return g_signal_count>0;
}

void WriteTradeRow(const int h,const string replay_mode,const int s,const int m,const bool skipped)
{
   if(skipped)
   {
      // Header has 31 columns total. Fields 1-6 (replay_mode..entry_time)
      // and field 8 (exit_reason) carry real values; field 7 (exit_time)
      // is empty; fields 9-30 (22 fields) are empty; field 31
      // (skipped_while_occupied) is "true". 8 real/placeholder-text
      // fields + 22 empties + 1 "true" = 31, matching the header exactly.
      string empty22[22]; for(int e=0;e<22;e++) empty22[e]="";
      FileWrite(h,replay_mode,g_sig_strategy_id[s],g_model_names[m],g_sig_cluster_id[s],
                (g_sig_direction[s]>0?"L":"S"),TimeToString(g_entry_time[s],TIME_DATE|TIME_SECONDS),
                "","SKIPPED_WHILE_OCCUPIED",
                empty22[0],empty22[1],empty22[2],empty22[3],empty22[4],empty22[5],empty22[6],empty22[7],
                empty22[8],empty22[9],empty22[10],empty22[11],empty22[12],empty22[13],empty22[14],empty22[15],
                empty22[16],empty22[17],empty22[18],empty22[19],empty22[20],empty22[21],
                "true");
      return;
   }
   if(!g_resolved[m][s]) return;

   double risk=MathAbs(g_sig_entry[s]-g_sig_stop[s]);
   int minutes_held=(int)((g_exit_time[m][s]-g_entry_time[s])/60);
   double mfe_until_exit=g_mfe_until_exit_r[m][s];
   double surrender_r=mfe_until_exit-g_net_r[m][s];
   double pct_open_captured=0.0, pct_ref_captured=0.0;
   bool pct_open_valid=CMSZZExitSimulatorPolicy::PercentMfeCaptured(g_net_r[m][s],mfe_until_exit,InpMinMfeThresholdR,pct_open_captured);
   bool pct_ref_valid=CMSZZExitSimulatorPolicy::PercentMfeCaptured(g_net_r[m][s],g_mfe_r[s],InpMinMfeThresholdR,pct_ref_captured);

   FileWrite(h,replay_mode,g_sig_strategy_id[s],g_model_names[m],g_sig_cluster_id[s],
             (g_sig_direction[s]>0?"L":"S"),TimeToString(g_entry_time[s],TIME_DATE|TIME_SECONDS),
             TimeToString(g_exit_time[m][s],TIME_DATE|TIME_SECONDS),g_exit_reason[m][s],
             DoubleToString(g_sig_entry[s],5),DoubleToString(g_sig_stop[s],5),DoubleToString(risk,5),
             DoubleToString(g_gross_r[m][s],4),DoubleToString(g_net_r[m][s],4),
             DoubleToString(mfe_until_exit,4),DoubleToString(g_mae_until_exit_r[m][s],4),
             DoubleToString(g_mfe_r[s],4),DoubleToString(g_mae_r[s],4),
             g_bars_to_mfe[s],(int)((g_time_to_mfe[s]-g_entry_time[s])/60),
             g_bars_held[m][s],minutes_held,DoubleToString(surrender_r,4),
             (pct_open_valid?DoubleToString(pct_open_captured,4):"null"),
             (pct_ref_valid?DoubleToString(pct_ref_captured,4):"null"),
             g_trail_updates[m][s],DoubleToString(g_final_stop[m][s],5),
             EnumToString(InpAmbiguityMode),g_session_text[s],g_weekday_text[s],
             (g_sequencing_ambiguous[m][s]?"true":"false"),"false");
}

void OnStart()
{
   if(!LoadSignalSet()) return;

   MSZZPhase2Params p2[MODEL_COUNT];
   ZeroMemory(p2[0]); p2[0].model=MSZZ_P2_CHANDELIER_TRAIL;        p2[0].chandelier_atr_mult=InpMedATRMult;
   ZeroMemory(p2[1]); p2[1].model=MSZZ_P2_FAST_SWING_TRAIL;
   ZeroMemory(p2[2]); p2[2].model=MSZZ_P2_MEDIUM_SWING_TRAIL;
   ZeroMemory(p2[3]); p2[3].model=MSZZ_P2_HL_LH_TRAIL;
   ZeroMemory(p2[4]); p2[4].model=MSZZ_P2_OPPOSITE_FAST_EXIT;
   ZeroMemory(p2[5]); p2[5].model=MSZZ_P2_TIME_8H;                 p2[5].timeout_seconds=8*3600;
   ZeroMemory(p2[6]); p2[6].model=MSZZ_P2_TIME_12H;                p2[6].timeout_seconds=12*3600;
   ZeroMemory(p2[7]); p2[7].model=MSZZ_P2_TIME_24H;                p2[7].timeout_seconds=24*3600;
   ZeroMemory(p2[8]); p2[8].model=MSZZ_P2_FIXED_2R_PLUS_TIMEOUT;   p2[8].timeout_seconds=24*3600;
   // index 9 = TRAIL_AFTER_1R, delegated to CMSZZExitSimulatorPolicy directly (not a Phase2Params model)
   ZeroMemory(p2[10]); p2[10].model=MSZZ_P2_BE_1R_PLUS_TRAIL;
   ZeroMemory(p2[11]); p2[11].model=MSZZ_P2_SESSION_OVERNIGHT;

   MSZZExitParams trail_after_1r; ZeroMemory(trail_after_1r);
   trail_after_1r.model=MSZZ_EXIT_TRAIL_0_5R_AFTER_1R; trail_after_1r.trail_trigger_r=1.0; trail_after_1r.trail_distance_r=0.5;

   long history_seconds=(long)InpHistoryBars*PeriodSeconds(g_period);
   long forward_seconds=(long)InpForwardWindowDays*86400;
   int unresolved_no_data=0;

   for(int s=0;s<g_signal_count;s++)
   {
      datetime entry_time=g_sig_time[s]+PeriodSeconds(g_period);
      g_entry_time[s]=entry_time;
      double entry=g_sig_entry[s], stop=g_sig_stop[s], target=g_sig_target[s];
      int dir=g_sig_direction[s];
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) { unresolved_no_data++; for(int m=0;m<MODEL_COUNT;m++) g_resolved[m][s]=false; continue; }

      datetime window_start=entry_time-(datetime)history_seconds;
      datetime window_end=entry_time+(datetime)forward_seconds;
      MqlRates full_rates[];
      int copied=CopyRates(g_symbol,g_period,window_start,window_end,full_rates);
      if(copied<=0) { unresolved_no_data++; for(int m=0;m<MODEL_COUNT;m++) g_resolved[m][s]=false; continue; }

      int entry_idx=-1;
      for(int b=0;b<copied;b++) if(full_rates[b].time>=entry_time) { entry_idx=b; break; }
      if(entry_idx<0 || copied-entry_idx<2) { unresolved_no_data++; for(int m=0;m<MODEL_COUNT;m++) g_resolved[m][s]=false; continue; }

      MSZZSpeedBarState fast_full[], med_full[];
      CMSZZStructuralReplay::BuildBarHistory(g_symbol,g_period,full_rates,copied,InpFastATRLen,InpFastATRMult,InpMinBarsBetween,MSZZ_SPEED_FAST,fast_full);
      CMSZZStructuralReplay::BuildBarHistory(g_symbol,g_period,full_rates,copied,InpMedATRLen,InpMedATRMult,InpMinBarsBetween,MSZZ_SPEED_MEDIUM,med_full);

      int fwd_count=copied-entry_idx;
      MSZZExitBar bars[]; ArrayResize(bars,fwd_count);
      MSZZSpeedBarState fast_hist[], med_hist[]; ArrayResize(fast_hist,fwd_count); ArrayResize(med_hist,fwd_count);
      double atr_med[]; ArrayResize(atr_med,fwd_count);
      for(int b=0;b<fwd_count;b++)
      {
         int src=entry_idx+b;
         bars[b].time=full_rates[src].time; bars[b].high=full_rates[src].high;
         bars[b].low=full_rates[src].low; bars[b].close=full_rates[src].close;
         fast_hist[b]=fast_full[src]; med_hist[b]=med_full[src];
         // ATR(MedATRLen) at this bar, recomputed directly (same formula
         // as StructuralReplay's private ATRAt, duplicated here since it
         // is a tiny, self-contained calc and not worth a public-API
         // change to the research engine for one caller).
         if(src>=InpMedATRLen)
         {
            double sum=0.0;
            for(int j=src-InpMedATRLen+1;j<=src;j++)
            {
               double tr = (j<=0) ? full_rates[j].high-full_rates[j].low :
                  MathMax(full_rates[j].high-full_rates[j].low,
                  MathMax(MathAbs(full_rates[j].high-full_rates[j-1].close),MathAbs(full_rates[j].low-full_rates[j-1].close)));
               sum+=tr;
            }
            atr_med[b]=sum/(double)InpMedATRLen;
         }
         else atr_med[b]=0.0;
      }

      double mfe_r,mae_r; int bars_to_mfe; datetime time_to_mfe;
      CMSZZExitSimulatorPolicy::ComputeMfeMae(entry,risk,dir,bars,fwd_count,mfe_r,mae_r,bars_to_mfe,time_to_mfe);
      g_mfe_r[s]=mfe_r; g_mae_r[s]=mae_r; g_bars_to_mfe[s]=bars_to_mfe; g_time_to_mfe[s]=time_to_mfe;

      int session_hour; { MqlDateTime dtm; TimeToStruct(entry_time,dtm); session_hour=dtm.hour; }
      g_session_text[s]=MSZZSessionText(CMSZZTradeAnalyticsPolicy::SessionBucket(session_hour));
      g_weekday_text[s]=WeekdayName(entry_time);

      double fixed_target_2r = (dir>0) ? entry+2.0*risk : entry-2.0*risk;

      for(int m=0;m<MODEL_COUNT;m++)
      {
         MSZZExitResult r;
         if(m==9) // TRAIL_AFTER_1R -- delegate to D021/D022's tested implementation
         {
            CMSZZExitSimulatorPolicy::SimulateExit(dir,entry,stop,risk,target,entry_time,bars,fwd_count,trail_after_1r,InpAmbiguityMode,r);
         }
         else
         {
            // p2[] is indexed identically to g_model_names[]/m (0-8, 10, 11);
            // only slot 9 (TRAIL_AFTER_1R) is intentionally left unset,
            // and m==9 always takes the delegate branch above, so it is
            // never read. No index shift is needed or correct here --
            // an earlier (m<9)?m:m-1 shift silently ran BE_1R_PLUS_TRAIL
            // (m=10) against p2[9] (uninitialized/garbage params) and
            // SESSION_OVERNIGHT (m=11) against p2[10] (BE_1R_PLUS_TRAIL's
            // real params), found via implausible BE_1R_PLUS_TRAIL output
            // (75% win rate, PF 6.8) during D024 verification.
            int pidx = m;
            CMSZZPhase2ExitPolicy::SimulatePhase2Exit(dir,entry,stop,risk,fixed_target_2r,entry_time,
               bars,fast_hist,med_hist,atr_med,fwd_count,p2[pidx],InpAmbiguityMode,r);
         }

         g_resolved[m][s]=r.resolved;
         g_sequencing_ambiguous[m][s]=r.sequencing_ambiguous;
         if(r.sequencing_ambiguous) g_ambiguous_count[m]++;
         if(!r.resolved) continue;

         g_exit_time[m][s]=r.exit_time; g_exit_price[m][s]=r.exit_price; g_exit_reason[m][s]=r.exit_reason;
         g_final_stop[m][s]=r.final_stop; g_trail_updates[m][s]=r.number_of_trail_updates;
         g_mfe_until_exit_r[m][s]=r.mfe_until_exit_r; g_mae_until_exit_r[m][s]=r.mae_until_exit_r;
         g_gross_r[m][s]=CMSZZExitSimulatorPolicy::RMultiple(r.exit_price,entry,risk,dir);
         g_net_r[m][s]=g_gross_r[m][s]-InpEstimatedCostR;
         int bh=0; for(int b=0;b<fwd_count;b++) if(bars[b].time==r.exit_time) { bh=b+1; break; }
         g_bars_held[m][s]=bh;
      }
   }

   int trade_h=FileOpen(InpTradeOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(trade_h==INVALID_HANDLE) { PrintFormat("MSZZ Phase2: trade output open failed error=%d",GetLastError()); return; }
   FileWrite(trade_h,"replay_mode","strategy_id","exit_model","cluster_id","direction","entry_time","exit_time",
             "exit_reason","entry_price","initial_stop","initial_risk","gross_r","net_r_after_costs",
             "mfe_until_exit_r","mae_until_exit_r","mfe_reference_horizon_r","mae_reference_horizon_r",
             "bars_to_mfe","minutes_to_mfe","bars_held","minutes_held","surrender_r",
             "pct_open_trade_mfe_captured","pct_reference_horizon_mfe_captured",
             "number_of_trail_updates","final_stop","replay_price_mode","session","weekday",
             "sequencing_ambiguous","skipped_while_occupied");

   for(int m=0;m<MODEL_COUNT;m++)
   {
      g_sig_r_count[m]=0; g_port_r_count[m]=0; g_port_skipped[m]=0; g_port_qualifying[m]=0;
      for(int s=0;s<g_signal_count;s++)
      {
         if(!g_resolved[m][s]) continue;
         WriteTradeRow(trade_h,"SIGNAL_LEVEL",s,m,false);
         g_sig_r_acc[m][g_sig_r_count[m]]=g_net_r[m][s]; g_sig_r_count[m]++;
      }
      datetime occupied_until=0;
      for(int s=0;s<g_signal_count;s++)
      {
         if(!g_resolved[m][s]) continue;
         g_port_qualifying[m]++;
         if(g_entry_time[s]<occupied_until)
         {
            g_port_skipped[m]++;
            WriteTradeRow(trade_h,"PORTFOLIO_LEVEL",s,m,true);
            continue;
         }
         occupied_until=g_exit_time[m][s];
         WriteTradeRow(trade_h,"PORTFOLIO_LEVEL",s,m,false);
         g_port_r_acc[m][g_port_r_count[m]]=g_net_r[m][s]; g_port_r_count[m]++;
      }
   }
   FileClose(trade_h);

   int summary_h=FileOpen(InpSummaryOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(summary_h==INVALID_HANDLE) { PrintFormat("MSZZ Phase2: summary output open failed error=%d",GetLastError()); return; }
   FileWrite(summary_h,"replay_mode","exit_model","trades","win_rate","expectancy_r","profit_factor_r",
             "max_drawdown_r","qualifying_signals","skipped_while_occupied","occupancy_pct","ambiguous_count");
   for(int m=0;m<MODEL_COUNT;m++)
   {
      if(g_sig_r_count[m]>0)
      {
         double vals[]; ArrayResize(vals,g_sig_r_count[m]);
         for(int i=0;i<g_sig_r_count[m];i++) vals[i]=g_sig_r_acc[m][i];
         FileWrite(summary_h,"SIGNAL_LEVEL",g_model_names[m],g_sig_r_count[m],
                   DoubleToString(CMSZZRunSummaryPolicy::WinRate(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::Average(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::ProfitFactorR(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::MaxDrawdownR(vals,g_sig_r_count[m]),4),
                   g_sig_r_count[m],"","",g_ambiguous_count[m]);
      }
      if(g_port_qualifying[m]>0 && g_port_r_count[m]>0)
      {
         double vals[]; ArrayResize(vals,g_port_r_count[m]);
         for(int i=0;i<g_port_r_count[m];i++) vals[i]=g_port_r_acc[m][i];
         double occ_pct=100.0*g_port_skipped[m]/g_port_qualifying[m];
         FileWrite(summary_h,"PORTFOLIO_LEVEL",g_model_names[m],g_port_r_count[m],
                   DoubleToString(CMSZZRunSummaryPolicy::WinRate(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::Average(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::ProfitFactorR(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::MaxDrawdownR(vals,g_port_r_count[m]),4),
                   g_port_qualifying[m],g_port_skipped[m],DoubleToString(occ_pct,2),g_ambiguous_count[m]);
      }
   }
   FileClose(summary_h);

   PrintFormat("MSZZ Phase2 ExitSimulator complete: signals=%d unresolved_no_data=%d models=%d -> %s / %s",
               g_signal_count,unresolved_no_data,MODEL_COUNT,InpTradeOutputFile,InpSummaryOutputFile);
}
