//+------------------------------------------------------------------+
//|                                       QuantBeast/RecoveryEngine.mqh|
//|                          XAUUSD Quant Beast EA - Recovery Engine  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_RECOVERYENGINE_MQH
#define QB_RECOVERYENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Diagnostics.mqh"
#include "Reconciliation.mqh"
#include "PositionManager.mqh"

//+------------------------------------------------------------------+
//| Recovery Engine - orchestrates startup position recovery.         |
//|                                                                   |
//| Owns the position-reconstruction step of the OnInit restart       |
//| sequence: it drives CPositionManager.ReconstructFromBroker(),     |
//| assembles the structured ReconciliationResult, and defers to      |
//| CReconciliation to turn that result + the configured unknown-     |
//| position policy into the recovery verdict (quarantine / emergency)|
//| the caller acts on.                                               |
//|                                                                   |
//| The verdict-application mechanism (killing entries, activating a   |
//| protection emergency) stays with the caller because it mutates    |
//| the EA's global kill-switch / protection state -- this module     |
//| owns the *decision*, not the side effects, keeping the extraction |
//| behavior-preserving and side-effect-free beyond the reconstruction|
//| itself (which is identical to the pre-extraction call).           |
//+------------------------------------------------------------------+
class CRecoveryEngine
{
public:
   CRecoveryEngine() {}

   //+------------------------------------------------------------------+
   //| Reconstruct owned positions from the broker and classify the      |
   //| outcome. `resOut` receives the raw counts; the return value is    |
   //| the verdict the caller applies. Behavior is identical to the      |
   //| former inline OnInit sequence.                                    |
   //+------------------------------------------------------------------+
   ReconciliationVerdict RecoverPositions(CPositionManager &pm,
                                          ulong magicBase,
                                          ENUM_UNKNOWN_POS_POLICY unknownPolicy,
                                          ReconciliationResult &resOut)
   {
      resOut.reconstructed = pm.ReconstructFromBroker(magicBase, unknownPolicy,
                                                      resOut.unknown,
                                                      resOut.unprotected);
      return CReconciliation::Classify(resOut, unknownPolicy);
   }
};

#endif // QB_RECOVERYENGINE_MQH
