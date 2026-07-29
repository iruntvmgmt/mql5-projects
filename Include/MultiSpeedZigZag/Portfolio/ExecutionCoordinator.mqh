#ifndef __MSZZ_EXECUTION_COORDINATOR_MQH__
#define __MSZZ_EXECUTION_COORDINATOR_MQH__

#include <MultiSpeedZigZag/Execution/PositionOwnership.mqh>
#include <MultiSpeedZigZag/Portfolio/CrossFamilyPolicy.mqh>
#include <MultiSpeedZigZag/Portfolio/VirtualNettingLedger.mqh>

enum ENUM_MSZZ_COORDINATOR_ACTION
{
   MSZZ_COORDINATOR_NONE = 0,
   MSZZ_COORDINATOR_OPEN_PHYSICAL,
   MSZZ_COORDINATOR_CLOSE_PHYSICAL,
   MSZZ_COORDINATOR_ADJUST_NET,
   MSZZ_COORDINATOR_SYNTHETIC_ONLY,
   MSZZ_COORDINATOR_REJECT
};

struct MSZZExecutionPlan
{
   bool                         valid;
   ENUM_MSZZ_COORDINATOR_ACTION action;
   ENUM_MSZZ_ACCOUNT_MODE       account_mode;
   long                         book_id;
   long                         magic;
   ulong                        owned_ticket;
   ENUM_MSZZ_DIRECTION          direction;
   double                       logical_volume;
   double                       broker_net_volume_before;
   double                       broker_net_volume_after;
   double                       broker_delta_volume;
   double                       stop_price;
   double                       target_price;
   bool                         synthetic_protection_required;
   string                       logical_position_id;
   string                       reason;
};

class CMSZZExecutionCoordinator
{
private:
   string                        m_symbol;
   long                          m_base_magic;
   ENUM_MSZZ_ACCOUNT_MODE        m_account_mode;
   ENUM_MSZZ_CROSS_FAMILY_POLICY m_policy;
   bool                          m_configured;

public:
   CMSZZExecutionCoordinator(void)
   {
      m_symbol="";
      m_base_magic=0;
      m_account_mode=MSZZ_ACCOUNT_UNSUPPORTED;
      m_policy=MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE;
      m_configured=false;
   }

   bool Configure(const string symbol,const long base_magic,
                  const ENUM_MSZZ_CROSS_FAMILY_POLICY policy,string &reason)
   {
      reason="";
      if(symbol=="") { reason="execution coordinator symbol required"; return false; }
      if(base_magic<=0) { reason="execution coordinator base magic must be positive"; return false; }
      if(!CMSZZCrossFamilyPolicy::IsKnown(policy))
      { reason="unknown cross-family policy"; return false; }
      m_symbol=symbol;
      m_base_magic=base_magic;
      m_policy=policy;
      m_account_mode=CMSZZPositionOwnership::DetectAccountMode();
      if(m_account_mode==MSZZ_ACCOUNT_UNSUPPORTED)
      { reason="unsupported account margin mode"; return false; }
      m_configured=true;
      return true;
   }

   ENUM_MSZZ_ACCOUNT_MODE AccountMode() const { return m_account_mode; }
   bool PhysicalTicketIsolationSupported() const { return m_account_mode==MSZZ_ACCOUNT_HEDGING; }
   bool VirtualLedgerRequired() const
   {
      return m_account_mode==MSZZ_ACCOUNT_NETTING || m_account_mode==MSZZ_ACCOUNT_EXCHANGE;
   }

   long BookMagic(const ENUM_MSZZ_STRATEGY_ID strategy_id,const long book_id) const
   {
      if(!m_configured || strategy_id==MSZZ_STRAT_NONE || book_id<=0) return 0;
      return m_base_magic+(long)strategy_id*1000+book_id;
   }

   bool BuildOpenPlan(const MSZZStrategyBookState &book,
                      const double broker_net_volume_before,
                      MSZZExecutionPlan &plan,string &reason) const
   {
      ZeroMemory(plan);
      reason="";
      if(!m_configured) { reason="execution coordinator not configured"; return false; }
      if(!book.valid || !book.enabled || book.status!=MSZZ_BOOK_ENTRY_PENDING)
      { reason="book is not valid entry-pending state"; return false; }
      if(book.magic<=0 || book.logical_volume<=0.0 ||
         (book.direction!=MSZZ_DIR_LONG && book.direction!=MSZZ_DIR_SHORT))
      { reason="book execution identity invalid"; return false; }

      plan.valid=true;
      plan.account_mode=m_account_mode;
      plan.book_id=book.book_id;
      plan.magic=book.magic;
      plan.direction=book.direction;
      plan.logical_volume=book.logical_volume;
      plan.broker_net_volume_before=broker_net_volume_before;
      plan.stop_price=book.stop_price;
      plan.target_price=book.target_price;
      plan.logical_position_id=book.logical_position_id;
      double signed_volume=(book.direction==MSZZ_DIR_LONG ?
                            book.logical_volume : -book.logical_volume);
      if(m_account_mode==MSZZ_ACCOUNT_HEDGING)
      {
         plan.action=MSZZ_COORDINATOR_OPEN_PHYSICAL;
         plan.broker_net_volume_after=broker_net_volume_before+signed_volume;
         plan.broker_delta_volume=signed_volume;
         plan.synthetic_protection_required=false;
         plan.reason="hedging ticket-isolated physical open";
      }
      else
      {
         plan.action=MSZZ_COORDINATOR_ADJUST_NET;
         plan.broker_net_volume_after=broker_net_volume_before+signed_volume;
         plan.broker_delta_volume=CMSZZVirtualNettingLedger::RequiredBrokerDelta(
            broker_net_volume_before,plan.broker_net_volume_after);
         plan.synthetic_protection_required=true;
         plan.reason="netting/exchange virtual book with EA-managed protection";
      }
      return true;
   }
};

#endif
