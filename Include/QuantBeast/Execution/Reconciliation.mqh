//+------------------------------------------------------------------+
//|                                       QuantBeast/Reconciliation.mqh|
//|                          XAUUSD Quant Beast EA - State Reconciliation|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_RECONCILIATION_MQH
#define QB_RECONCILIATION_MQH

#include "../Core/Types.mqh"
#include "../Core/Diagnostics.mqh"
#include "BrokerAdapter.mqh"

//+------------------------------------------------------------------+
//| Structured outcome of comparing persisted state with broker       |
//| reality at startup. Populated by PositionManager.ReconstructFrom- |
//| Broker() (owned/unknown/unprotected classification) and consumed  |
//| by the recovery flow.                                             |
//+------------------------------------------------------------------+
struct ReconciliationResult
{
   int  reconstructed;   // owned QuantBeast positions successfully adopted
   int  unknown;         // positions whose strategy ownership is unrecoverable
   int  unprotected;     // reconstructed positions with no verified stop
};

//+------------------------------------------------------------------+
//| Verdict the recovery flow must act on. The two conditions are     |
//| independent -- an unprotected position forces a protection        |
//| emergency regardless of the unknown-ownership outcome -- so the   |
//| verdict carries both flags rather than a single enum.             |
//+------------------------------------------------------------------+
struct ReconciliationVerdict
{
   bool   need_quarantine;   // kill new entries (unknown ownership under QUARANTINE policy)
   bool   need_emergency;    // activate protection emergency (unprotected position found)
   string reason;            // human-readable summary for the acting caller
};

//+------------------------------------------------------------------+
//| Reconciliation - compares persisted state with broker reality.    |
//| Owns the *classification-to-verdict* policy that the startup      |
//| recovery previously hard-coded inline: it turns the raw           |
//| reconstruction counts + the configured unknown-position policy    |
//| into the actions the caller performs. Stateless; pure decision.   |
//+------------------------------------------------------------------+
class CReconciliation
{
public:
   CReconciliation() {}

   //+------------------------------------------------------------------+
   //| Classify a reconstruction result into the recovery verdict.       |
   //|                                                                   |
   //| Mirrors the original OnInit logic exactly:                        |
   //|   unknown > 0 && policy == UNKNOWN_QUARANTINE -> kill entries      |
   //|   unprotected > 0                             -> protection emerg. |
   //+------------------------------------------------------------------+
   static ReconciliationVerdict Classify(const ReconciliationResult &res,
                                         ENUM_UNKNOWN_POS_POLICY unknownPolicy)
   {
      ReconciliationVerdict v;
      v.need_quarantine = (res.unknown > 0 && unknownPolicy == UNKNOWN_QUARANTINE);
      v.need_emergency  = (res.unprotected > 0);

      string parts = "";
      if(v.need_quarantine)
         parts += "quarantine(unknown=" + IntegerToString(res.unknown) + ")";
      if(v.need_emergency)
      {
         if(StringLen(parts) > 0) parts += " ";
         parts += "emergency(unprotected=" + IntegerToString(res.unprotected) + ")";
      }
      if(StringLen(parts) == 0)
         parts = "clean(reconstructed=" + IntegerToString(res.reconstructed) + ")";
      v.reason = parts;
      return v;
   }
};

#endif // QB_RECONCILIATION_MQH
