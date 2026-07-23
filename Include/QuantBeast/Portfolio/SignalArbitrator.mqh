//+------------------------------------------------------------------+
//|                                     QuantBeast/SignalArbitrator.mqh|
//|                          XAUUSD Quant Beast EA - Signal Arbitration|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_SIGNALARBITRATOR_MQH
#define QB_SIGNALARBITRATOR_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Signal Arbitrator - evaluates and scores all strategy signals     |
//+------------------------------------------------------------------+
class CSignalArbitrator
{
private:
   ENUM_ARBITRATION_METHOD m_method;
   int                     m_cooldownSeconds;
   int                     m_duplicateWindowSeconds;
   bool                    m_allowOpposite;
   bool                    m_allowSameDirectionStack;

   // Tracking state
   StrategySignal          m_lastAcceptedLong;
   StrategySignal          m_lastAcceptedShort;
   datetime                m_lastAcceptTime;
   int                     m_existingLongCount;
   int                     m_existingShortCount;
   string                  m_recentSignalIDs[];
   double                  m_recentSignalHashes[];
   datetime                m_recentSignalTimes[];
   int                     m_recentCount;
   int                     m_recentMax;

public:
   //+------------------------------------------------------------------+
   CSignalArbitrator()
   {
      m_method                  = ARBITRATION_HIGHEST_SCORE;
      m_cooldownSeconds         = 300;
      m_duplicateWindowSeconds  = 600;
      m_allowOpposite           = false;
      m_allowSameDirectionStack = false;
      m_lastAcceptTime          = 0;
      m_existingLongCount       = 0;
      m_existingShortCount      = 0;
      m_recentCount             = 0;
      m_recentMax               = 50;

      ZeroMemory(m_lastAcceptedLong);
      ZeroMemory(m_lastAcceptedShort);

      ArrayResize(m_recentSignalIDs, m_recentMax);
      ArrayResize(m_recentSignalHashes, m_recentMax);
      ArrayResize(m_recentSignalTimes, m_recentMax);
   }

   //+------------------------------------------------------------------+
   void Init(ENUM_ARBITRATION_METHOD method, int cooldownSec,
             int duplicateWindowSec, bool allowOpposite, bool allowSameDirStack)
   {
      m_method                 = method;
      m_cooldownSeconds        = cooldownSec;
      m_duplicateWindowSeconds = duplicateWindowSec;
      m_allowOpposite          = allowOpposite;
      m_allowSameDirectionStack = allowSameDirStack;
   }

   //+------------------------------------------------------------------+
   //| Generate a unique signal ID                                       |
   //+------------------------------------------------------------------+
   string GenerateSignalID(string strategyID, ENUM_ORDER_TYPE dir,
                           datetime time, double entry, double level)
   {
      // Stable economic ID: do not include clock time, otherwise the same
      // setup becomes "new" every minute inside the duplicate window.
      double anchor = (level != 0) ? level : entry;
      return strategyID + "_" + IntegerToString(dir) + "_" +
             DoubleToString(anchor, 5);
   }

   //+------------------------------------------------------------------+
   //| Stable 32-bit FNV-1a hash for bounded duplicate persistence       |
   //+------------------------------------------------------------------+
   double SignalIDHash(const string signalID)
   {
      uint hash = 2166136261;
      for(int i = 0; i < StringLen(signalID); i++)
      {
         hash ^= (uint)StringGetCharacter(signalID, i);
         hash *= 16777619;
      }
      return (double)hash;
   }

   //+------------------------------------------------------------------+
   //| Check if signal is a duplicate of a recent one                    |
   //+------------------------------------------------------------------+
   bool IsDuplicate(string signalID, datetime signalTime)
   {
      datetime cutoff = signalTime - m_duplicateWindowSeconds;
      double signalHash = SignalIDHash(signalID);
      for(int i = 0; i < m_recentCount; i++)
      {
         if(m_recentSignalIDs[i] == signalID &&
            m_recentSignalTimes[i] >= cutoff)
         {
            return true;
         }
         if(m_recentSignalHashes[i] == signalHash &&
            m_recentSignalTimes[i] >= cutoff)
         {
            return true;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Record a signal ID for duplicate prevention                       |
   //+------------------------------------------------------------------+
   void RecordSignal(string signalID, datetime signalTime)
   {
      if(m_recentCount >= m_recentMax)
      {
         // Shift array down
         for(int i = 0; i < m_recentMax - 1; i++)
         {
            m_recentSignalIDs[i]   = m_recentSignalIDs[i + 1];
            m_recentSignalHashes[i] = m_recentSignalHashes[i + 1];
            m_recentSignalTimes[i] = m_recentSignalTimes[i + 1];
         }
         m_recentCount = m_recentMax - 1;
      }

      m_recentSignalIDs[m_recentCount]   = signalID;
      m_recentSignalHashes[m_recentCount] = SignalIDHash(signalID);
      m_recentSignalTimes[m_recentCount] = signalTime;
      m_recentCount++;
   }

   //+------------------------------------------------------------------+
   //| Export restart-critical arbitration state                         |
   //+------------------------------------------------------------------+
   void ExportPersistence(datetime &lastAcceptTime, double &hashes[],
                          datetime &times[], int &count, int maxItems)
   {
      lastAcceptTime = m_lastAcceptTime;
      count = 0;
      int capped = MathMin(maxItems, m_recentCount);
      ArrayResize(hashes, capped);
      ArrayResize(times, capped);
      datetime cutoff = TimeCurrent() - m_duplicateWindowSeconds;

      for(int i = m_recentCount - 1; i >= 0 && count < capped; i--)
      {
         if(m_recentSignalTimes[i] <= 0 || m_recentSignalTimes[i] < cutoff)
            continue;
         hashes[count] = m_recentSignalHashes[i];
         times[count] = m_recentSignalTimes[i];
         count++;
      }
      ArrayResize(hashes, count);
      ArrayResize(times, count);
   }

   //+------------------------------------------------------------------+
   //| Restore restart-critical arbitration state                        |
   //+------------------------------------------------------------------+
   void RestorePersistence(datetime lastAcceptTime, const double &hashes[],
                           const datetime &times[], int count, datetime now)
   {
      m_lastAcceptTime = 0;
      if(lastAcceptTime > 0 && lastAcceptTime <= now &&
         now - lastAcceptTime < m_cooldownSeconds)
         m_lastAcceptTime = lastAcceptTime;

      m_recentCount = 0;
      int capped = MathMin(MathMin(count, ArraySize(hashes)), ArraySize(times));
      datetime cutoff = now - m_duplicateWindowSeconds;
      for(int i = 0; i < capped && m_recentCount < m_recentMax; i++)
      {
         if(hashes[i] <= 0 || times[i] <= 0 || times[i] > now || times[i] < cutoff)
            continue;
         m_recentSignalIDs[m_recentCount] = "";
         m_recentSignalHashes[m_recentCount] = hashes[i];
         m_recentSignalTimes[m_recentCount] = times[i];
         m_recentCount++;
      }
   }

   //+------------------------------------------------------------------+
   //| Score a signal (0.0 - 1.0)                                        |
   //+------------------------------------------------------------------+
   double ScoreSignal(const StrategySignal &sig, const RegimeState &regime,
                      const FeatureSnapshot &feat)
   {
      double score = 0.0;
      int components = 0;

      // Strategy confidence
      score += sig.confidence;
      components++;

      // Regime compatibility
      score += regime.confidence;
      components++;

      // Expected R:R contribution (normalize: 2.0 -> 1.0)
      double rrScore = Clamp(sig.expected_reward_r / 2.0, 0.0, 1.0);
      score += rrScore;
      components++;

      // Spread quality (lower spread = better)
      double spreadScore = 1.0 - Clamp(feat.spread_percentile / 100.0, 0.0, 1.0);
      score += spreadScore;
      components++;

      // Directional HTF component on the same 0..1 scale.
      bool htfDirectionOK = (sig.direction == ORDER_TYPE_BUY && feat.htf_slope > 0) ||
                            (sig.direction == ORDER_TYPE_SELL && feat.htf_slope < 0);
      score += htfDirectionOK ? 1.0 : 0.0;
      components++;

      return (components > 0) ? score / components : 0.0;
   }

   //+------------------------------------------------------------------+
   //| Arbitrate: pick the best signal from all candidates               |
   //+------------------------------------------------------------------+
   StrategySignal Arbitrate(StrategySignal &candidates[], int count,
                              const RegimeState &regime,
                              const FeatureSnapshot &feat)
   {
      StrategySignal best;
      ZeroMemory(best);
      best.valid = false;

      if(count <= 0) return best;

      // Filter valid signals
      StrategySignal validCands[];
      int validCount = 0;
      ArrayResize(validCands, count);

      for(int i = 0; i < count; i++)
      {
         if(!candidates[i].valid) continue;

         // Check cooldown
         if(TimeCurrent() - m_lastAcceptTime < m_cooldownSeconds)
         {
            candidates[i].valid = false;
            candidates[i].rejection_code = REJECT_COOLDOWN_ACTIVE;
            candidates[i].reason = "Arbitration: cooldown active";
            continue;
         }

         // Check duplicate
         string sigID = GenerateSignalID(candidates[i].strategy_id,
                                          candidates[i].direction,
                                          candidates[i].signal_time,
                                          candidates[i].proposed_entry, 0);
         if(IsDuplicate(sigID, candidates[i].signal_time))
         {
            candidates[i].valid = false;
            candidates[i].rejection_code = REJECT_DUPLICATE_SIGNAL;
            candidates[i].reason = "Arbitration: duplicate signal";
            continue;
         }

         // Check direction conflicts
         if(!m_allowOpposite)
         {
            if(candidates[i].direction == ORDER_TYPE_BUY && m_existingShortCount > 0)
            {
               candidates[i].valid = false;
               candidates[i].rejection_code = REJECT_CONFLICTING_SIGNAL;
               candidates[i].reason = "Arbitration: existing short positions";
               continue;
            }
            if(candidates[i].direction == ORDER_TYPE_SELL && m_existingLongCount > 0)
            {
               candidates[i].valid = false;
               candidates[i].rejection_code = REJECT_CONFLICTING_SIGNAL;
               candidates[i].reason = "Arbitration: existing long positions";
               continue;
            }
         }

         // Check stacking
         if(!m_allowSameDirectionStack)
         {
            if(candidates[i].direction == ORDER_TYPE_BUY && m_existingLongCount > 0)
            {
               candidates[i].valid = false;
               candidates[i].rejection_code = REJECT_EXPOSURE_LIMIT;
               candidates[i].reason = "Arbitration: same-direction stacking disabled";
               continue;
            }
            if(candidates[i].direction == ORDER_TYPE_SELL && m_existingShortCount > 0)
            {
               candidates[i].valid = false;
               candidates[i].rejection_code = REJECT_EXPOSURE_LIMIT;
               candidates[i].reason = "Arbitration: same-direction stacking disabled";
               continue;
            }
         }

         validCands[validCount] = candidates[i];
         validCount++;
      }

      if(validCount == 0)
         return best;

      int bestIdx = -1;
      double bestScore = -DBL_MAX;

      // Score and select best based on method
      switch(m_method)
      {
         case ARBITRATION_HIGHEST_SCORE:
         {
            for(int i = 0; i < validCount; i++)
            {
               double sc = ScoreSignal(validCands[i], regime, feat);
               if(sc > bestScore)
               {
                  bestScore = sc;
                  bestIdx = i;
               }
            }
            break;
         }

         case ARBITRATION_REGIME_PRIORITY:
         {
            for(int i = 0; i < validCount; i++)
            {
               double compatibility = 0;
               if(validCands[i].strategy_id == STRATEGY_ID_BREAKOUT &&
                  (regime.structure == STRUCTURE_BREAKOUT_ATTEMPT ||
                   regime.structure == STRUCTURE_ACCEPTED_BREAKOUT)) compatibility = 0.25;
               else if(validCands[i].strategy_id == STRATEGY_ID_FAILED_BREAKOUT &&
                       regime.structure == STRUCTURE_FAILED_BREAKOUT) compatibility = 0.25;
               else if((validCands[i].strategy_id == STRATEGY_ID_TREND_PULLBACK ||
                        validCands[i].strategy_id == STRATEGY_ID_TREND_PULLBACK_V2) &&
                       (regime.trend != TREND_NEUTRAL)) compatibility = 0.20;
               else if(validCands[i].strategy_id == STRATEGY_ID_MEAN_REVERSION &&
                       regime.structure == STRUCTURE_BALANCED) compatibility = 0.20;
               double sc = ScoreSignal(validCands[i], regime, feat) + compatibility;
               if(sc > bestScore) { bestScore = sc; bestIdx = i; }
            }
            break;
         }

         case ARBITRATION_REQUIRE_CONFLUENCE:
         {
            int longVotes = 0, shortVotes = 0;
            for(int i = 0; i < validCount; i++)
            {
               if(validCands[i].direction == ORDER_TYPE_BUY) longVotes++;
               else if(validCands[i].direction == ORDER_TYPE_SELL) shortVotes++;
            }
            int agreedDirection = -1;
            if(longVotes >= 2 && shortVotes == 0) agreedDirection = ORDER_TYPE_BUY;
            if(shortVotes >= 2 && longVotes == 0) agreedDirection = ORDER_TYPE_SELL;
            if(agreedDirection >= 0)
            {
               for(int i = 0; i < validCount; i++)
               {
                  if(validCands[i].direction != agreedDirection) continue;
                  double sc = ScoreSignal(validCands[i], regime, feat);
                  if(sc > bestScore) { bestScore = sc; bestIdx = i; }
               }
            }
            break;
         }

         case ARBITRATION_REJECT_CONFLICTS:
         {
            // If both long and short present, reject all
            bool hasLong  = false;
            bool hasShort = false;
            for(int i = 0; i < validCount; i++)
            {
               if(validCands[i].direction == ORDER_TYPE_BUY)  hasLong  = true;
               if(validCands[i].direction == ORDER_TYPE_SELL) hasShort = true;
            }
            if(hasLong && hasShort)
            {
               // Reject all
               for(int i = 0; i < count; i++)
               {
                  if(candidates[i].valid)
                  {
                     candidates[i].valid = false;
                     candidates[i].rejection_code = REJECT_CONFLICTING_SIGNAL;
                     candidates[i].reason = "Arbitration: conflicting directions rejected";
                  }
               }
               return best;
            }
            for(int i = 0; i < validCount; i++)
            {
               double sc = ScoreSignal(validCands[i], regime, feat);
               if(sc > bestScore) { bestScore = sc; bestIdx = i; }
            }
            break;
         }

         default:
         {
            QBLogError("Unknown arbitration method; rejecting all candidates");
            break;
         }
      }

      if(bestIdx >= 0)
         best = validCands[bestIdx];

      // Every candidate must leave arbitration in a final signal-decision
      // state. The selected candidate remains valid; all other candidates
      // are explicit rejections so journals cannot report false acceptance.
      for(int i = 0; i < count; i++)
      {
         if(!candidates[i].valid) continue;

         bool selected = best.valid &&
                         candidates[i].strategy_id == best.strategy_id &&
                         candidates[i].direction == best.direction &&
                         candidates[i].signal_time == best.signal_time;
         if(selected) continue;

         candidates[i].valid = false;
         candidates[i].rejection_code = REJECT_ARBITRATION_LOST;
         candidates[i].reason = (m_method == ARBITRATION_REQUIRE_CONFLUENCE) ?
                                "Arbitration: confluence not met" :
                                "Arbitration: lower-ranked candidate";
      }

      return best;
   }

   // Call only after risk, sizing, margin, and submission/simulation succeed.
   void CommitAccepted(const StrategySignal &signal)
   {
      if(!signal.valid) return;
      string sigID = GenerateSignalID(signal.strategy_id, signal.direction,
                                      signal.signal_time, signal.proposed_entry, 0);
      RecordSignal(sigID, signal.signal_time);
      m_lastAcceptTime = TimeCurrent();
      if(signal.direction == ORDER_TYPE_BUY) m_lastAcceptedLong = signal;
      else m_lastAcceptedShort = signal;
   }

   //+------------------------------------------------------------------+
   //| Update position counts (called by position manager)               |
   //+------------------------------------------------------------------+
   void SetPositionCounts(int longCount, int shortCount)
   {
      m_existingLongCount  = longCount;
      m_existingShortCount = shortCount;
   }

   //+------------------------------------------------------------------+
   int GetLongCount()  const { return m_existingLongCount; }
   int GetShortCount() const { return m_existingShortCount; }
   datetime GetLastAcceptTime() const { return m_lastAcceptTime; }
   int GetRecentCount() const { return m_recentCount; }
};

#endif // QB_SIGNALARBITRATOR_MQH
