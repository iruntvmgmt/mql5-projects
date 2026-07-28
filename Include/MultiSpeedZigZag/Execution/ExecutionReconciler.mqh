#ifndef __MSZZ_EXECUTION_RECONCILER_MQH__
#define __MSZZ_EXECUTION_RECONCILER_MQH__

// See DECISION_LOG.md D009. First increment of Phase 2 (broker order/deal/
// position reconciliation) -- not all ~20 scenarios from the original request,
// see D009 for exactly what is and is not covered.

#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>
#include <MultiSpeedZigZag/Execution/PositionOwnership.mqh>

enum ENUM_MSZZ_BROKER_RECORD_TYPE
{
   MSZZ_RECORD_OPEN_POSITION = 0,
   MSZZ_RECORD_HISTORY_ORDER,
   MSZZ_RECORD_HISTORY_DEAL
};

enum ENUM_MSZZ_RECONCILE_VERDICT
{
   MSZZ_RECONCILE_NO_ACTION = 0,
   MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION,
   MSZZ_RECONCILE_MATCHED_CLOSED_POSITION,
   MSZZ_RECONCILE_CONSISTENT_REJECTION,
   MSZZ_RECONCILE_RECOVERY_REQUIRED
};

string MSZZReconcileVerdictText(const ENUM_MSZZ_RECONCILE_VERDICT v)
{
   switch(v)
   {
      case MSZZ_RECONCILE_NO_ACTION:               return "NO_ACTION";
      case MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION:  return "MATCHED_ACTIVE_POSITION";
      case MSZZ_RECONCILE_MATCHED_CLOSED_POSITION:  return "MATCHED_CLOSED_POSITION";
      case MSZZ_RECONCILE_CONSISTENT_REJECTION:     return "CONSISTENT_REJECTION";
      case MSZZ_RECONCILE_RECOVERY_REQUIRED:        return "RECOVERY_REQUIRED";
      default:                                      return "UNKNOWN";
   }
}

struct MSZZBrokerRecord
{
   ulong    ticket;
   string   symbol;
   long     magic;
   int      direction;      // ENUM_MSZZ_DIRECTION as int; MSZZ_DIR_NONE if unknown
   double   volume;
   double   price;
   datetime time;
   string   comment_token;  // extracted "MI"+8hex correlation token, or "" if absent
   int      record_type;    // ENUM_MSZZ_BROKER_RECORD_TYPE
   ulong    position_id;    // for history orders/deals: the owning position ticket; else 0
};

struct MSZZReconcileResult
{
   string                       intent_id;
   ENUM_MSZZ_RECONCILE_VERDICT  verdict;
   ulong                        matched_ticket;
   string                       reason;
};

// Pure, deterministic reconciliation core -- no live MT5 API calls. Mirrors the
// PositionOwnership.mqh / PositionOwnershipPolicy.mqh split from D005.
class CMSZZReconciliationPolicy
{
private:
   bool IsTerminal(const int state) const
   {
      return state==(int)MSZZ_INTENT_POSITION_CLOSED || state==(int)MSZZ_INTENT_ABANDONED;
   }

   bool RecordMatchesIntent(const MSZZBrokerRecord &rec,const MSZZExecutionIntent &intent) const
   {
      if(rec.magic!=intent.magic || rec.symbol!=intent.symbol) return false;
      if(intent.order_ticket>0 && rec.ticket==intent.order_ticket) return true;
      if(intent.position_ticket>0 && (rec.ticket==intent.position_ticket || rec.position_id==intent.position_ticket)) return true;
      if(intent.first_deal_ticket>0 && rec.ticket==intent.first_deal_ticket) return true;
      if(rec.comment_token!="" && rec.comment_token==MSZZCorrelationToken(intent.intent_id)) return true;
      return false;
   }

public:
   int Reconcile(const MSZZExecutionIntent &intents[],const int intent_count,
                 const MSZZBrokerRecord &records[],const int record_count,
                 const bool is_netting,
                 MSZZReconcileResult &results[]) const
   {
      ArrayResize(results,intent_count);

      int non_terminal_count=0;
      for(int i=0;i<intent_count;i++)
         if(!IsTerminal(intents[i].execution_state)) non_terminal_count++;

      // First pass: count how many distinct intents match each record, so a
      // record claimed by more than one intent can be flagged as a conflict
      // for ALL of them, regardless of processing order.
      int matched_by_count[];
      ArrayResize(matched_by_count,record_count);
      for(int j=0;j<record_count;j++) matched_by_count[j]=0;
      for(int i=0;i<intent_count;i++)
      {
         if(IsTerminal(intents[i].execution_state)) continue;
         for(int j=0;j<record_count;j++)
            if(RecordMatchesIntent(records[j],intents[i])) matched_by_count[j]++;
      }

      for(int i=0;i<intent_count;i++)
      {
         results[i].intent_id=intents[i].intent_id;
         results[i].matched_ticket=0;
         // Safe default: fail closed unless positively overridden below by
         // concrete evidence. Never assume a "nothing found" result means
         // abandoned/rejected.
         results[i].verdict=MSZZ_RECONCILE_RECOVERY_REQUIRED;
         results[i].reason="no conclusive broker evidence found";

         if(IsTerminal(intents[i].execution_state))
         {
            results[i].verdict=MSZZ_RECONCILE_NO_ACTION;
            results[i].reason="already terminal";
            continue;
         }

         if(is_netting && non_terminal_count>1)
         {
            results[i].reason="netting account: multiple simultaneous non-terminal intents cannot be unambiguously attributed";
            continue;
         }

         ulong matched_tickets[];
         int match_count=0;
         bool saw_open=false;
         bool conflict=false;
         for(int j=0;j<record_count;j++)
         {
            if(!RecordMatchesIntent(records[j],intents[i])) continue;
            if(matched_by_count[j]>1) { conflict=true; continue; }
            ulong canon=(records[j].position_id>0 ? records[j].position_id : records[j].ticket);
            bool already=false;
            for(int k=0;k<match_count;k++) if(matched_tickets[k]==canon) { already=true; break; }
            if(!already) { ArrayResize(matched_tickets,match_count+1); matched_tickets[match_count++]=canon; }
            if(records[j].record_type==(int)MSZZ_RECORD_OPEN_POSITION) saw_open=true;
         }

         if(conflict)
         {
            results[i].reason="one or more matching broker records are also claimed by a different intent (conflict)";
            continue;
         }
         if(match_count==0)
         {
            if(intents[i].execution_state==(int)MSZZ_INTENT_BROKER_REJECTED)
            {
               results[i].verdict=MSZZ_RECONCILE_CONSISTENT_REJECTION;
               results[i].reason="locally rejected, no broker record exists (consistent)";
            }
            continue;
         }
         if(match_count>1)
         {
            results[i].reason=StringFormat("%d distinct broker tickets matched this single intent (ambiguous)",match_count);
            continue;
         }

         results[i].matched_ticket=matched_tickets[0];
         if(intents[i].execution_state==(int)MSZZ_INTENT_BROKER_REJECTED)
         {
            results[i].reason="locally marked rejected but a matching broker record exists (conflict)";
            continue;
         }
         if(saw_open)
         {
            results[i].verdict=MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION;
            results[i].reason="matched an open position";
         }
         else
         {
            results[i].verdict=MSZZ_RECONCILE_MATCHED_CLOSED_POSITION;
            results[i].reason="matched closed-position history (order/deal records, no open position)";
         }
      }
      return intent_count;
   }
};

// Live wrapper: builds the MSZZBrokerRecord[] from real MT5 API calls, then
// delegates to CMSZZReconciliationPolicy for the actual classification.
class CMSZZExecutionReconciler
{
private:
   string m_symbol;
   long   m_magic;
   int    m_lookback_days;
   CMSZZReconciliationPolicy m_policy;

   string ExtractCommentToken(const string comment) const
   {
      if(StringLen(comment)>=10 && StringSubstr(comment,0,2)=="MI") return StringSubstr(comment,2,8);
      return "";
   }

   void AppendRecord(MSZZBrokerRecord &records[],int &count,const MSZZBrokerRecord &rec)
   {
      for(int i=0;i<count;i++)
         if(records[i].ticket==rec.ticket && records[i].record_type==rec.record_type) return;
      ArrayResize(records,count+1);
      records[count++]=rec;
   }

public:
   CMSZZExecutionReconciler(void) { m_symbol=""; m_magic=0; m_lookback_days=90; }

   void Configure(const string symbol,const long magic,const int lookback_days=90)
   {
      m_symbol=symbol; m_magic=magic; m_lookback_days=MathMax(1,lookback_days);
   }

   bool CollectBrokerRecords(MSZZBrokerRecord &records[])
   {
      ArrayResize(records,0);
      int count=0;

      int pos_total=PositionsTotal();
      for(int i=0;i<pos_total;i++)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;

         MSZZBrokerRecord rec;
         rec.ticket=ticket; rec.symbol=m_symbol; rec.magic=m_magic;
         long type=PositionGetInteger(POSITION_TYPE);
         rec.direction=(type==POSITION_TYPE_BUY ? (int)MSZZ_DIR_LONG : (type==POSITION_TYPE_SELL ? (int)MSZZ_DIR_SHORT : (int)MSZZ_DIR_NONE));
         rec.volume=PositionGetDouble(POSITION_VOLUME);
         rec.price=PositionGetDouble(POSITION_PRICE_OPEN);
         rec.time=(datetime)PositionGetInteger(POSITION_TIME);
         rec.comment_token=ExtractCommentToken(PositionGetString(POSITION_COMMENT));
         rec.record_type=(int)MSZZ_RECORD_OPEN_POSITION;
         rec.position_id=ticket;
         AppendRecord(records,count,rec);
      }

      datetime from=TimeCurrent()-(datetime)(m_lookback_days*86400);
      datetime to=TimeCurrent();
      if(!HistorySelect(from,to)) return false;

      int order_total=HistoryOrdersTotal();
      for(int i=0;i<order_total;i++)
      {
         ulong ticket=HistoryOrderGetTicket(i);
         if(ticket==0) continue;
         if(HistoryOrderGetString(ticket,ORDER_SYMBOL)!=m_symbol || HistoryOrderGetInteger(ticket,ORDER_MAGIC)!=m_magic) continue;

         MSZZBrokerRecord rec;
         rec.ticket=ticket; rec.symbol=m_symbol; rec.magic=m_magic;
         long type=HistoryOrderGetInteger(ticket,ORDER_TYPE);
         rec.direction=(type==ORDER_TYPE_BUY ? (int)MSZZ_DIR_LONG : (type==ORDER_TYPE_SELL ? (int)MSZZ_DIR_SHORT : (int)MSZZ_DIR_NONE));
         rec.volume=HistoryOrderGetDouble(ticket,ORDER_VOLUME_INITIAL);
         rec.price=HistoryOrderGetDouble(ticket,ORDER_PRICE_OPEN);
         rec.time=(datetime)HistoryOrderGetInteger(ticket,ORDER_TIME_SETUP);
         rec.comment_token=ExtractCommentToken(HistoryOrderGetString(ticket,ORDER_COMMENT));
         rec.record_type=(int)MSZZ_RECORD_HISTORY_ORDER;
         rec.position_id=(ulong)HistoryOrderGetInteger(ticket,ORDER_POSITION_ID);
         AppendRecord(records,count,rec);
      }

      int deal_total=HistoryDealsTotal();
      for(int i=0;i<deal_total;i++)
      {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol || HistoryDealGetInteger(ticket,DEAL_MAGIC)!=m_magic) continue;

         MSZZBrokerRecord rec;
         rec.ticket=ticket; rec.symbol=m_symbol; rec.magic=m_magic;
         long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
         rec.direction=(type==DEAL_TYPE_BUY ? (int)MSZZ_DIR_LONG : (type==DEAL_TYPE_SELL ? (int)MSZZ_DIR_SHORT : (int)MSZZ_DIR_NONE));
         rec.volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
         rec.price=HistoryDealGetDouble(ticket,DEAL_PRICE);
         rec.time=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         rec.comment_token=ExtractCommentToken(HistoryDealGetString(ticket,DEAL_COMMENT));
         rec.record_type=(int)MSZZ_RECORD_HISTORY_DEAL;
         rec.position_id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         AppendRecord(records,count,rec);
      }
      return true;
   }

   // is_netting is passed in (not detected here) so this component stays free
   // of any direct dependency on CMSZZPositionOwnership's account-mode enum.
   int Reconcile(const MSZZExecutionIntent &intents[],const int intent_count,const bool is_netting,
                 MSZZReconcileResult &results[])
   {
      MSZZBrokerRecord records[];
      if(!CollectBrokerRecords(records))
      {
         // Cannot query broker history at all: fail closed for every
         // non-terminal intent rather than silently reconciling against an
         // empty/partial view.
         ArrayResize(results,intent_count);
         for(int i=0;i<intent_count;i++)
         {
            bool terminal=(intents[i].execution_state==(int)MSZZ_INTENT_POSITION_CLOSED ||
                           intents[i].execution_state==(int)MSZZ_INTENT_ABANDONED);
            results[i].intent_id=intents[i].intent_id;
            results[i].matched_ticket=0;
            results[i].verdict=(terminal ? MSZZ_RECONCILE_NO_ACTION : MSZZ_RECONCILE_RECOVERY_REQUIRED);
            results[i].reason=(terminal ? "already terminal" : "broker history query failed");
         }
         return intent_count;
      }
      return m_policy.Reconcile(intents,intent_count,records,ArraySize(records),is_netting,results);
   }
};

#endif
