//+------------------------------------------------------------------+
//| MultiSpeedZigZagEA.mq5                                           |
//+------------------------------------------------------------------+
#property strict
#property version   "0.320"
#property description "Standalone Multi-Speed ZigZag strategy suite"

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>
#include <MultiSpeedZigZag/Execution/EventStore.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionGuard.mqh>
#include <MultiSpeedZigZag/Execution/PositionOwnership.mqh>
#include <MultiSpeedZigZag/Execution/PositionOwnershipPolicy.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionReconciler.mqh>

input group "═══ Operating Mode ═══"
input bool   InpShadowOnly=true;
input bool   InpAllowLiveExecution=false;
input bool   InpAcknowledgeRisk=false;
input long   InpMagic=26072501;
input int    InpHistoryBars=1500;

input group "═══ Fast Speed ═══"
input int    InpFastATRLen=14;
input double InpFastATRMult=1.0;
input group "═══ Medium Speed ═══"
input int    InpMedATRLen=14;
input double InpMedATRMult=2.0;
input group "═══ Slow Speed ═══"
input int    InpSlowATRLen=14;
input double InpSlowATRMult=3.5;

input group "═══ Strategy Enablement ═══"
input bool InpEnableFastBreakout=true;
input bool InpEnableMediumBreakout=true;
input bool InpEnableSlowBreakout=true;
input bool InpEnableFastMedConfluence=true;
input bool InpEnableFastMedContext=true;
input bool InpEnableMedSlowContext=true;
input bool InpEnableNestedPullback=true;
input bool InpEnableWeightedEnsemble=true;

input group "═══ Structure & Signal ═══"
input int    InpMinBarsBetween=3;
input double InpMinScore=5.0;
input double InpRiskReward=1.5;
input bool   InpOneOwnedPositionPerSymbol=true;

input group "═══ Standalone Execution ═══"
input double InpFixedLots=0.01;
input double InpMaxSpreadPoints=80.0;
input int    InpDeviationPoints=30;
input bool   InpExitOwnedOpposite=true;
input int    InpMaxPersistentEvents=2000;

input group "═══ Diagnostics ═══"
input bool InpWriteCSV=true;
input bool InpVerboseLog=true;

CMSZZTripleZigZagEngine       g_engine;
CMSZZStrategySuite            g_suite;
CMSZZOpportunityClusterEngine g_cluster_engine;
CMSZZEventStore                g_event_store;
CMSZZExecutionGuard            g_execution_guard;
CMSZZPositionOwnership         g_ownership;
CMSZZExecutionIntentStore      g_intent_store;
CMSZZExecutionReconciler       g_reconciler;
CTrade                         g_trade;
datetime                       g_last_bar=0;
string                         g_instance_id="";
bool                           g_recovery_required=false;

bool LiveExecutionAuthorized(){ return (!InpShadowOnly && InpAllowLiveExecution && InpAcknowledgeRisk); }
bool EventConsumed(const string id){ return g_event_store.Contains(id); }
bool ConsumeEvent(const string id){ return g_event_store.Add(id); }

void JournalCandidate(const MSZZCandidate &c,const string status,const string cluster_id="")
{
   if(InpVerboseLog)
      PrintFormat("MSZZ %s %s cluster=%s score=%.2f entry=%.*f stop=%.*f target=%.*f origin=%s event=%s reason=%s",
                  status,c.setup_name,cluster_id,c.score,_Digits,c.entry,_Digits,c.stop,_Digits,c.target,c.origin_id,c.event_id,c.reason);
   if(!InpWriteCSV) return;
   int h=FileOpen("MSZZ_SignalJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){ PrintFormat("MSZZ journal open failed error=%d",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","status","cluster_id","strategy_id","setup","direction","score","entry","stop","target","origin_id","event_id","reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(c.signal_time,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),status,cluster_id,
             (int)c.strategy_id,c.setup_name,MSZZDirectionText(c.direction),DoubleToString(c.score,2),
             DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),DoubleToString(c.target,_Digits),
             c.origin_id,c.event_id,c.reason);
   FileFlush(h); FileClose(h);
}

void JournalCluster(const MSZZOpportunityCluster &cluster,const string status)
{
   if(InpVerboseLog)
      PrintFormat("MSZZ CLUSTER %s id=%s owner=%d score=%.2f support=%d evidence=%d stop_disagreement=%.*f",
                  status,cluster.cluster_id,(int)cluster.owner_strategy_id,cluster.combined_score,
                  cluster.support_count,cluster.evidence_mask,_Digits,cluster.stop_disagreement);
}

void JournalOwnership(const MSZZOwnershipSnapshot &snapshot,const string status)
{
   if(!InpVerboseLog) return;
   PrintFormat("MSZZ OWNERSHIP %s mode=%s symbol_total=%d owned=%d long=%d short=%d manual=%d foreign=%d err=%s",
               status,CMSZZPositionOwnership::AccountModeText(snapshot.account_mode),snapshot.total_symbol_positions,
               snapshot.owned_positions,snapshot.owned_longs,snapshot.owned_shorts,
               snapshot.manual_positions,snapshot.foreign_positions,snapshot.error_reason);
}

bool RefreshOwnership(string &reason)
{
   reason="";
   if(!g_ownership.Refresh())
   {
      MSZZOwnershipSnapshot failed=g_ownership.Snapshot();
      JournalOwnership(failed,"REFRESH_FAILED");
      reason=(failed.error_reason!="" ? failed.error_reason : "ownership refresh failed");
      return false;
   }
   JournalOwnership(g_ownership.Snapshot(),"REFRESHED");
   return true;
}

bool ApplyOwnershipPreflight(const ENUM_MSZZ_DIRECTION desired,string &reason)
{
   reason="";
   if(!RefreshOwnership(reason)) return false;

   MSZZOwnershipSnapshot before=g_ownership.Snapshot();
   if(!g_ownership.ExecutionAllowedForAccountMode(reason)) return false;

   if(!g_ownership.CloseOwnedOpposite(g_trade,desired,InpExitOwnedOpposite,reason)) return false;

   if(InpExitOwnedOpposite && ((desired==MSZZ_DIR_LONG && before.owned_shorts>0) ||
                               (desired==MSZZ_DIR_SHORT && before.owned_longs>0)))
   {
      if(!RefreshOwnership(reason)) return false;
   }

   MSZZOwnershipSnapshot after=g_ownership.Snapshot();
   if(!CMSZZPositionOwnershipPolicy::CanOpen(after,InpOneOwnedPositionPerSymbol,reason)) return false;
   return true;
}

bool PrepareMarketCandidate(const MSZZCandidate &source,MSZZCandidate &prepared,string &reason)
{
   prepared=source;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)){ reason="no current tick"; return false; }
   prepared.entry=(source.direction==MSZZ_DIR_LONG ? tick.ask : tick.bid);
   double risk=MathAbs(prepared.entry-source.stop);
   if(risk<=0.0){ reason="market entry equals structural stop"; return false; }
   prepared.target=(source.direction==MSZZ_DIR_LONG ? prepared.entry+risk*InpRiskReward : prepared.entry-risk*InpRiskReward);
   return g_execution_guard.ValidateStops(prepared,prepared.stop,prepared.target,reason);
}

bool ExecuteCluster(const MSZZOpportunityCluster &cluster,const MSZZCandidate &owner)
{
   string persistence_id=cluster.cluster_id;
   if(!LiveExecutionAuthorized())
   {
      JournalCluster(cluster,"SHADOW");
      JournalCandidate(owner,"SHADOW",cluster.cluster_id);
      return true;
   }
   if(cluster.combined_score<InpMinScore){ JournalCandidate(owner,"REJECT_SCORE",cluster.cluster_id); return false; }
   if(EventConsumed(persistence_id)){ JournalCandidate(owner,"REJECT_DUPLICATE_CLUSTER",cluster.cluster_id); return false; }

   // D009: a RECOVERY_REQUIRED intent (unresolved broker state from a prior
   // run) blocks all new live execution for this symbol/magic until an
   // operator clears it out-of-band. See DECISION_LOG.md D009 failure policy.
   if(g_recovery_required)
   {
      MSZZCandidate rejected=owner;
      rejected.reason="one or more execution intents require manual recovery (see MSZZ RECONCILE log at startup)";
      JournalCandidate(rejected,"REJECT_RECOVERY_REQUIRED",cluster.cluster_id);
      return false;
   }

   string reason;
   if(!g_execution_guard.TradingAllowed(reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=reason;
      JournalCandidate(rejected,"REJECT_TRADING_DISABLED",cluster.cluster_id); return false;
   }
   double spread_points=0.0;
   if(!g_execution_guard.SpreadAllowed(InpMaxSpreadPoints,spread_points))
   {
      MSZZCandidate rejected=owner;
      rejected.reason=StringFormat("spread %.1f exceeds maximum %.1f points",spread_points,InpMaxSpreadPoints);
      JournalCandidate(rejected,"REJECT_SPREAD",cluster.cluster_id); return false;
   }

   MSZZCandidate prepared;
   if(!PrepareMarketCandidate(owner,prepared,reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=reason;
      JournalCandidate(rejected,"REJECT_STOPS",cluster.cluster_id); return false;
   }
   double volume=g_execution_guard.NormalizeVolume(InpFixedLots);
   if(volume<=0.0){ prepared.reason="volume normalization failed"; JournalCandidate(prepared,"REJECT_VOLUME",cluster.cluster_id); return false; }

   if(!ApplyOwnershipPreflight(prepared.direction,reason))
   {
      prepared.reason=reason;
      JournalCandidate(prepared,"REJECT_OWNERSHIP",cluster.cluster_id);
      return false;
   }

   // D006 idempotent execution-intent persistence: durably mark this cluster
   // consumed BEFORE attempting to submit the order, and fail closed if that
   // write does not succeed. This makes execution idempotent with respect to
   // persistence-layer failures -- a live order attempt and its durable
   // consumed-event record can never be split by an I/O failure, because the
   // record is written first and gates the attempt. The trade-off (accepted,
   // see DECISION_LOG.md D006): if the order itself is then rejected by the
   // broker, this cluster will not be retried even though no position opened.
   if(!ConsumeEvent(persistence_id))
   {
      prepared.reason="execution intent persistence failed, order not attempted";
      JournalCandidate(prepared,"REJECT_INTENT_PERSISTENCE",cluster.cluster_id);
      return false;
   }

   // D008: a second, independent, equally fail-closed gate using the richer
   // ExecutionIntentStore (D007), run after D006's proven EventStore gate.
   // Neither gate replaces the other in this pass. See DECISION_LOG.md D008.
   MSZZExecutionIntent intent;
   intent.schema_version=MSZZ_INTENT_SCHEMA_VERSION;
   intent.intent_id=persistence_id;
   intent.cluster_id=cluster.cluster_id;
   intent.origin_id=owner.origin_id;
   intent.strategy_id=(int)prepared.strategy_id;
   intent.symbol=_Symbol;
   intent.timeframe=(int)_Period;
   intent.magic=InpMagic;
   intent.direction=(int)prepared.direction;
   intent.signal_time=owner.signal_time;
   intent.intent_time=TimeCurrent();
   intent.expiry_time=owner.expiry_time;
   intent.requested_volume=volume;
   intent.requested_entry=prepared.entry;
   intent.requested_stop=prepared.stop;
   intent.requested_target=prepared.target;
   intent.execution_state=(int)MSZZ_INTENT_PERSISTED;
   intent.submission_attempts=0;
   intent.broker_retcode=0;
   intent.broker_result_text="";
   intent.order_ticket=0; intent.position_ticket=0;
   intent.first_deal_ticket=0; intent.last_deal_ticket=0;
   intent.filled_volume=0.0; intent.average_fill_price=0.0;
   intent.last_reconciliation_time=0;
   intent.protection_status=0;
   intent.instance_id=g_instance_id;

   if(!g_intent_store.CreateIntent(intent))
   {
      prepared.reason="execution intent store persistence failed: "+g_intent_store.LastError();
      JournalCandidate(prepared,"REJECT_INTENT_STORE",cluster.cluster_id);
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok=false;
   // D009: "MI"+8-hex correlation token, not the old bare strategy id -- lets
   // the reconciler match this order back to its intent even if the local
   // ticket fields were never recorded (e.g. a crash right after submission).
   string comment="MI"+MSZZCorrelationToken(persistence_id);
   if(prepared.direction==MSZZ_DIR_LONG) ok=g_trade.Buy(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);
   else if(prepared.direction==MSZZ_DIR_SHORT) ok=g_trade.Sell(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);

   intent.submission_attempts=1;
   intent.broker_retcode=g_trade.ResultRetcode();
   intent.broker_result_text=g_trade.ResultRetcodeDescription();
   if(ok)
   {
      intent.execution_state=(int)MSZZ_INTENT_BROKER_ACCEPTED;
      intent.order_ticket=g_trade.ResultOrder();
      intent.first_deal_ticket=g_trade.ResultDeal();
      // position_ticket is intentionally left unset here -- see DECISION_LOG.md
      // D008: deriving it correctly (especially under hedging) is Phase 2's job.
   }
   else
   {
      intent.execution_state=(int)MSZZ_INTENT_BROKER_REJECTED;
   }
   // Warn-only, not fail-closed: EventStore already durably marked this cluster
   // consumed above, so the anti-duplicate guarantee does not depend on this
   // update succeeding. A failure here leaves the intent record's fill/ticket
   // details incomplete -- exactly what Phase 2's reconciler exists to detect
   // and repair against broker truth, not a new gap this decision introduces.
   if(!g_intent_store.UpdateIntent(intent))
      Print("MSZZ WARNING: intent store post-submission update failed: ",g_intent_store.LastError());

   if(ok)
   {
      JournalCluster(cluster,"EXECUTED"); JournalCandidate(prepared,"EXECUTED",cluster.cluster_id);
   }
   else
   {
      prepared.reason=StringFormat("retcode=%u %s (cluster already marked consumed; not retried)",
                                   g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      JournalCandidate(prepared,"ORDER_FAILED",cluster.cluster_id);
   }
   return ok;
}

void ProcessClosedBar()
{
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,_Period,0,MathMax(300,InpHistoryBars),rates);
   if(copied<100){ PrintFormat("MSZZ insufficient bars copied=%d error=%d",copied,GetLastError()); return; }
   int closed_count=copied-1; if(closed_count<100) return;

   g_engine.Configure(InpFastATRLen,InpFastATRMult,InpMedATRLen,InpMedATRMult,InpSlowATRLen,InpSlowATRMult,InpMinBarsBetween);
   if(!g_engine.Rebuild(_Symbol,_Period,rates,closed_count)) return;
   MSZZSpeedSnapshot fast=g_engine.Snapshot(MSZZ_SPEED_FAST);
   MSZZSpeedSnapshot med=g_engine.Snapshot(MSZZ_SPEED_MEDIUM);
   MSZZSpeedSnapshot slow=g_engine.Snapshot(MSZZ_SPEED_SLOW);

   g_suite.SetRiskReward(InpRiskReward);
   g_suite.ConfigureStrategies(InpEnableFastBreakout,InpEnableMediumBreakout,InpEnableSlowBreakout,
                               InpEnableFastMedConfluence,InpEnableFastMedContext,InpEnableMedSlowContext,
                               InpEnableNestedPullback,InpEnableWeightedEnsemble);
   MSZZCandidate candidates[];
   int candidate_count=g_suite.Evaluate(fast,med,slow,rates[closed_count-1].time,rates[closed_count-1].close,candidates);
   if(candidate_count<=0) return;
   for(int i=0;i<candidate_count;i++) if(candidates[i].valid) JournalCandidate(candidates[i],"RAW_CANDIDATE");

   MSZZOpportunityCluster clusters[];
   int cluster_count=g_cluster_engine.Build(_Symbol,_Period,candidates,candidate_count,clusters);
   if(cluster_count<=0) return;
   int best_cluster=g_cluster_engine.SelectBest(clusters,cluster_count);
   if(best_cluster<0 || !clusters[best_cluster].valid) return;

   MSZZOpportunityCluster selected_cluster=clusters[best_cluster];
   int owner_index=selected_cluster.preferred_index;
   if(owner_index<0 || owner_index>=candidate_count || !candidates[owner_index].valid) return;
   MSZZCandidate owner=candidates[owner_index];

   JournalCluster(selected_cluster,"SELECTED");
   if(selected_cluster.combined_score<InpMinScore){ JournalCandidate(owner,"REJECT_SCORE",selected_cluster.cluster_id); return; }
   if(EventConsumed(selected_cluster.cluster_id)){ JournalCandidate(owner,"REJECT_DUPLICATE_CLUSTER",selected_cluster.cluster_id); return; }

   ExecuteCluster(selected_cluster,owner);
   if(!LiveExecutionAuthorized() && !ConsumeEvent(selected_cluster.cluster_id))
      Print("MSZZ WARNING: shadow cluster persistence failed.");
}

int OnInit()
{
   if(InpMagic<=0 || InpFastATRLen<1 || InpMedATRLen<1 || InpSlowATRLen<1 || InpFastATRMult<=0.0 ||
      InpMedATRMult<=0.0 || InpSlowATRMult<=0.0 || InpRiskReward<=0.0 || InpHistoryBars<300)
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   if(!g_execution_guard.Load(_Symbol)) return INIT_FAILED;

   g_ownership.Configure(_Symbol,InpMagic);
   string ownership_reason;
   if(!RefreshOwnership(ownership_reason))
   {
      PrintFormat("MSZZ ownership initialization failed: %s",ownership_reason);
      return INIT_FAILED;
   }

   g_event_store.Configure(_Symbol,_Period,InpMagic,InpMaxPersistentEvents);
   if(!g_event_store.Load()) return INIT_FAILED;

   g_instance_id=StringFormat("%d-%d-%d",(int)AccountInfoInteger(ACCOUNT_LOGIN),(int)TimeLocal(),MathRand());
   if(!g_intent_store.Configure(_Symbol,_Period,InpMagic,g_instance_id))
   {
      PrintFormat("MSZZ intent store initialization failed: %s",g_intent_store.LastError());
      return INIT_FAILED;
   }
   if(!g_intent_store.Load())
   {
      PrintFormat("MSZZ intent store load failed: %s",g_intent_store.LastError());
      return INIT_FAILED;
   }

   // D009: reconcile every loaded intent against broker truth once at startup,
   // before the EA does anything else. See DECISION_LOG.md D009 "Restart
   // behavior". This also fulfils D008's deferred TODO of deriving
   // position_ticket from broker records rather than leaving it unset.
   g_reconciler.Configure(_Symbol,InpMagic);
   int intent_count=g_intent_store.Count();
   MSZZExecutionIntent all_intents[];
   ArrayResize(all_intents,intent_count);
   for(int i=0;i<intent_count;i++) g_intent_store.IntentAt(i,all_intents[i]);

   bool is_netting=(g_ownership.AccountMode()==MSZZ_ACCOUNT_NETTING || g_ownership.AccountMode()==MSZZ_ACCOUNT_EXCHANGE);
   MSZZReconcileResult recon_results[];
   g_reconciler.Reconcile(all_intents,intent_count,is_netting,recon_results);

   g_recovery_required=false;
   for(int i=0;i<intent_count;i++)
   {
      bool terminal=(all_intents[i].execution_state==(int)MSZZ_INTENT_POSITION_CLOSED ||
                     all_intents[i].execution_state==(int)MSZZ_INTENT_ABANDONED);
      if(terminal) continue;

      PrintFormat("MSZZ RECONCILE intent=%s verdict=%s ticket=%I64u reason=%s",
                  recon_results[i].intent_id,MSZZReconcileVerdictText(recon_results[i].verdict),
                  recon_results[i].matched_ticket,recon_results[i].reason);

      MSZZExecutionIntent updated=all_intents[i];
      updated.last_reconciliation_time=TimeCurrent();
      if(recon_results[i].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED)
      {
         updated.execution_state=(int)MSZZ_INTENT_RECOVERY_REQUIRED;
         g_recovery_required=true;
      }
      else if((recon_results[i].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION ||
               recon_results[i].verdict==MSZZ_RECONCILE_MATCHED_CLOSED_POSITION) &&
              updated.position_ticket==0)
      {
         updated.position_ticket=recon_results[i].matched_ticket;
      }
      if(!g_intent_store.UpdateIntent(updated))
         PrintFormat("MSZZ WARNING: reconciliation update failed for intent=%s error=%s",
                     updated.intent_id,g_intent_store.LastError());
   }
   if(g_recovery_required)
      Print("MSZZ WARNING: one or more intents require manual recovery. New live execution is blocked for this symbol/magic until cleared.");

   Print(!LiveExecutionAuthorized() ?
         "MSZZ initialized in SHADOW posture. Three live gates are required." :
         "MSZZ WARNING: LIVE EXECUTION AUTHORIZED by all three gates.");
   PrintFormat("MSZZ account mode=%s event store loaded count=%d file=%s",
               CMSZZPositionOwnership::AccountModeText(g_ownership.AccountMode()),
               g_event_store.Count(),g_event_store.Filename());
   PrintFormat("MSZZ intent store loaded count=%d unknown=%d file=%s instance=%s",
               g_intent_store.Count(),g_intent_store.UnknownRecordCount(),
               g_intent_store.PrimaryFilename(),g_instance_id);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==0 || bar==g_last_bar) return;
   g_last_bar=bar; ProcessClosedBar();
}

void OnDeinit(const int reason){ PrintFormat("MSZZ deinitialized reason=%d",reason); }
