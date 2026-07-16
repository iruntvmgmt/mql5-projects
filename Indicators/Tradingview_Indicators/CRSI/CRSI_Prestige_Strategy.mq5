//+------------------------------------------------------------------+
//|                                   CRSI Prestige Strategy Ind.mq5  |
//|                    Ported from Pine Script v5 → MQL5 (Indicator)  |
//|                    Original: CRSI_Prestige_Strategy.pine          |
//+------------------------------------------------------------------+
#property copyright   "Ported from TradingView Pine Script"
#property version     "1.00"
#property description ":: CRSI Prestige - Advanced ::"
#property description "Cyclic Smoothed RSI with Bollinger Bands, Fibonacci levels,"
#property description "Squeeze Momentum filter, and V5.8 Divergence Engine."
#property description "NOTE: Trading execution requires separate EA."

#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 21
#property indicator_plots   21

// ── Plot 0: CRSI ────────────────────────────────────────────────────────────
#property indicator_label1  "CRSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'0x26,0xA6,0x9A'  // teal (bull) but fixed
#property indicator_width1  2

// ── Plot 1: Smoothed CRSI ───────────────────────────────────────────────────
#property indicator_label2  "Smoothed cRSI"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_width2  2
#property indicator_style2  STYLE_DOT

// ── Plot 2-3: Dynamic CRSI Bands ────────────────────────────────────────────
#property indicator_label3  "Dynamic Low"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrAqua
#property indicator_width3  1

#property indicator_label4  "Dynamic High"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrAqua
#property indicator_width4  1

// ── Plot 4-5: CRSI Fib Levels ───────────────────────────────────────────────
#property indicator_label5  "Fib 50"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrange
#property indicator_width5  2

#property indicator_label6  "Fib 61.8 Up"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrRed
#property indicator_width6  1

#property indicator_label7  "Fib 61.8 Down"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrRed
#property indicator_width7  1

// ── Plot 8-10: Static Levels ────────────────────────────────────────────────
#property indicator_label8  "HI Level"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrGreen
#property indicator_width8  1

#property indicator_label9  "MID Level"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrWhite
#property indicator_width9  1

#property indicator_label10 "LO Level"
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrRed
#property indicator_width10 1

// ── Plot 11-12: Sub Levels ──────────────────────────────────────────────────
#property indicator_label11 "HI Sub"
#property indicator_type11  DRAW_LINE
#property indicator_color11 clrGreen
#property indicator_width11 1

#property indicator_label12 "LO Sub"
#property indicator_type12  DRAW_LINE
#property indicator_color12 clrRed
#property indicator_width12 1

// ── Plot 13-15: Bollinger Bands ─────────────────────────────────────────────
#property indicator_label13 "BB Upper"
#property indicator_type13  DRAW_LINE
#property indicator_color13 C'0x80,0x80,0x80'
#property indicator_width13 1

#property indicator_label14 "BB Middle"
#property indicator_type14  DRAW_LINE
#property indicator_color14 clrYellow
#property indicator_width14 1

#property indicator_label15 "BB Lower"
#property indicator_type15  DRAW_LINE
#property indicator_color15 C'0x80,0x80,0x80'
#property indicator_width15 1

// ── Plot 16-17: Buy/Sell Signal markers on oscillator ───────────────────────
#property indicator_label16 "Buy Signal"
#property indicator_type16  DRAW_ARROW
#property indicator_color16 clrLime
#property indicator_width16 2

#property indicator_label17 "Sell Signal"
#property indicator_type17  DRAW_ARROW
#property indicator_color17 clrRed
#property indicator_width17 2

// ── Plot 18: Squeeze Momentum ───────────────────────────────────────────────
#property indicator_label18 "SQZ Momentum"
#property indicator_type18  DRAW_HISTOGRAM
#property indicator_color18 clrDodgerBlue
#property indicator_width18 2

// ── Plot 19-21: Hidden extra plots ──────────────────────────────────────────
#property indicator_label19 "SQZ On"
#property indicator_type19  DRAW_NONE
#property indicator_label20 "BB Mid Std"
#property indicator_type20  DRAW_NONE
#property indicator_label21 "Normalized Price"
#property indicator_type21  DRAW_LINE
#property indicator_color21 clrGray
#property indicator_width21 1

// ── INPUTS ───────────────────────────────────────────────────────────────────
input group                        "═══ CRSI Settings ═══"
input int                          InpDomCycle     = 20;                 // Dominant Cycle (>=10)
input int                          InpLeveling     = 10;                 // Leveling (>=0)
input int                          InpSmoothLen    = 3;                  // Smoothing (>=1)
input ENUM_APPLIED_PRICE           InpSrc          = PRICE_CLOSE;        // Source

input group                        "═══ Static Levels ═══"
input double                       InpCRSI_HI      = 80.0;               // Static High
input double                       InpCRSI_MID     = 50.0;               // Static Mid
input double                       InpCRSI_LO      = 20.0;               // Static Low
input double                       InpCRSI_HI_sub  = 65.0;               // High-Sub
input double                       InpCRSI_LO_sub  = 35.0;               // Low-Sub

input group                        "═══ Bollinger Bands ═══"
input bool                         InpShowBB       = true;               // Show Bollinger Bands
input int                          InpBBLen        = 20;                 // BB Length
input double                       InpBBMult       = 2.0;                // BB Multiplier

input group                        "═══ Squeeze Momentum ═══"
input bool                         InpUseSQZ       = false;              // Use SQZ Momentum
input int                          InpSQZBBLen     = 20;                 // BB Length
input double                       InpSQZBBMult    = 2.0;                // BB Mult
input int                          InpSQZKCLen     = 20;                 // KC Length
input double                       InpSQZKCMult    = 1.5;                // KC Mult
input bool                         InpSQZTrueRange = true;               // Use True Range
input int                          InpSQZMomLen    = 20;                 // Momentum Length
input int                          InpSQZSmoothLen = 1;                  // Smoothing

input group                        "═══ Divergence Engine ═══"
input int                          InpDivLeft      = 5;                  // Pivot Lookback Left
input int                          InpDivRight     = 3;                  // Pivot Lookback Right
input int                          InpMaxPivotBars = 100;                // Max Bars Between Pivots
input bool                         InpShowDivLines = true;               // Show Divergence Lines
input int                          InpMaxDivLines  = 15;                 // Max Lines

input group                        "═══ Signal Display ═══"
input bool                         InpShowSignals  = true;               // Show Buy/Sell Markers
input bool                         InpShowAlerts   = true;               // Enable Alerts

// ── Buffers ─────────────────────────────────────────────────────────────────
double g_crsi[];            // 0
double g_smoothCRSI[];      // 1
double g_dbCRSI[];          // 2  dynamic low band
double g_ubCRSI[];          // 3  dynamic high band
double g_fib50[];           // 4
double g_fib618Up[];        // 5
double g_fib618Dn[];        // 6
double g_levelHI[];         // 7
double g_levelMID[];        // 8
double g_levelLO[];         // 9
double g_levelHISub[];      // 10
double g_levelLOSub[];      // 11
double g_bbUpper[];         // 12
double g_bbMiddle[];        // 13
double g_bbLower[];         // 14
double g_buySig[];          // 15
double g_sellSig[];         // 16
double g_sqzMom[];          // 17
double g_sqzOn[];           // 18
double g_bbMidStd[];        // 19 (hidden calc buffer)
double g_priceNorm[];       // 20

// ── Runtime ─────────────────────────────────────────────────────────────────
string g_prefix = "CRSI_";
bool   g_prevBuy, g_prevSell;

//+------------------------------------------------------------------+
//| SMA helper                                                        |
//+------------------------------------------------------------------+
double SMA(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double sum = 0;
   for(int i = 0; i < period; i++) sum += arr[shift + i];
   return sum / period;
}

//+------------------------------------------------------------------+
//| EMA helper                                                        |
//+------------------------------------------------------------------+
double EMA(const double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   double alpha = 2.0 / (period + 1.0);
   double ema = arr[shift + period - 1];
   for(int i = shift + period - 2; i >= shift; i--)
      ema = arr[i] * alpha + ema * (1.0 - alpha);
   return ema;
}

//+------------------------------------------------------------------+
//| RMA (Wilder's moving average)                                     |
//+------------------------------------------------------------------+
double RMA(const double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   double alpha = 1.0 / period;
   double rma = arr[shift + period - 1];
   for(int i = shift + period - 2; i >= shift; i--)
      rma = arr[i] * alpha + rma * (1.0 - alpha);
   return rma;
}

//+------------------------------------------------------------------+
//| Standard Deviation                                                |
//+------------------------------------------------------------------+
double StdDev(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double mean = SMA(arr, period, shift);
   double sumSq = 0;
   for(int i = 0; i < period; i++)
   {
      double diff = arr[shift + i] - mean;
      sumSq += diff * diff;
   }
   return MathSqrt(sumSq / period);
}

//+------------------------------------------------------------------+
//| Linear Regression slope at point                                  |
//+------------------------------------------------------------------+
double LinReg(const double &arr[], int period, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size) return 0;
   
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   for(int i = 0; i < period; i++)
   {
      double x = i;
      double y = arr[shift + i];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }
   
   double denom = period * sumX2 - sumX * sumX;
   if(MathAbs(denom) < 1e-10) return 0;
   
   double slope = (period * sumXY - sumX * sumY) / denom;
   return slope * (period - 1) + (sumY / period);  // value at end
}

//+------------------------------------------------------------------+
//| Percentile nearest rank                                           |
//+------------------------------------------------------------------+
double PercentileNR(const double &arr[], int period, double pct, int shift)
{
   int size = ArraySize(arr);
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > size || period < 2) return 0;
   
   double sorted[];
   ArrayResize(sorted, period);
   for(int i = 0; i < period; i++)
      sorted[i] = arr[shift + i];
   ArraySort(sorted);
   
   int idx = (int)MathRound(pct / 100.0 * (period - 1));
   if(idx < 0) idx = 0;
   if(idx >= period) idx = period - 1;
   return sorted[idx];
}

//+------------------------------------------------------------------+
//| Is pivot high?                                                    |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   double val = arr[idx];
   for(int i = idx - left; i < idx; i++)
      if(arr[i] > val) return false;
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] >= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Is pivot low?                                                     |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &arr[], int left, int right, int idx)
{
   if(idx - left < 0 || idx + right >= ArraySize(arr)) return false;
   double val = arr[idx];
   for(int i = idx - left; i < idx; i++)
      if(arr[i] < val) return false;
   for(int i = idx + 1; i <= idx + right; i++)
      if(arr[i] <= val) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Highest in range                                                  |
//+------------------------------------------------------------------+
double Highest(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double hi = arr[shift];
   for(int i = 1; i < period; i++)
      if(arr[shift + i] > hi) hi = arr[shift + i];
   return hi;
}

//+------------------------------------------------------------------+
//| Lowest in range                                                   |
//+------------------------------------------------------------------+
double Lowest(const double &arr[], int period, int shift)
{
   if(period <= 0 || shift < 0) return 0;
   if(shift + period > ArraySize(arr)) return 0;
   double lo = arr[shift];
   for(int i = 1; i < period; i++)
      if(arr[shift + i] < lo) lo = arr[shift + i];
   return lo;
}

//+------------------------------------------------------------------+
//| True Range                                                        |
//+------------------------------------------------------------------+
double TrueRange(double h, double l, double prevC)
{
   return MathMax(h - l, MathMax(MathAbs(h - prevC), MathAbs(l - prevC)));
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,  g_crsi,         INDICATOR_DATA);
   SetIndexBuffer(1,  g_smoothCRSI,   INDICATOR_DATA);
   SetIndexBuffer(2,  g_dbCRSI,       INDICATOR_DATA);
   SetIndexBuffer(3,  g_ubCRSI,       INDICATOR_DATA);
   SetIndexBuffer(4,  g_fib50,        INDICATOR_DATA);
   SetIndexBuffer(5,  g_fib618Up,     INDICATOR_DATA);
   SetIndexBuffer(6,  g_fib618Dn,     INDICATOR_DATA);
   SetIndexBuffer(7,  g_levelHI,      INDICATOR_DATA);
   SetIndexBuffer(8,  g_levelMID,     INDICATOR_DATA);
   SetIndexBuffer(9,  g_levelLO,      INDICATOR_DATA);
   SetIndexBuffer(10, g_levelHISub,   INDICATOR_DATA);
   SetIndexBuffer(11, g_levelLOSub,   INDICATOR_DATA);
   SetIndexBuffer(12, g_bbUpper,      INDICATOR_DATA);
   SetIndexBuffer(13, g_bbMiddle,     INDICATOR_DATA);
   SetIndexBuffer(14, g_bbLower,      INDICATOR_DATA);
   SetIndexBuffer(15, g_buySig,       INDICATOR_DATA);
   SetIndexBuffer(16, g_sellSig,      INDICATOR_DATA);
   SetIndexBuffer(17, g_sqzMom,       INDICATOR_DATA);
   SetIndexBuffer(18, g_sqzOn,        INDICATOR_DATA);
   SetIndexBuffer(19, g_bbMidStd,     INDICATOR_DATA);
   SetIndexBuffer(20, g_priceNorm,    INDICATOR_DATA);
   
   PlotIndexSetInteger(15, PLOT_ARROW, 233); // Buy arrow
   PlotIndexSetInteger(16, PLOT_ARROW, 234); // Sell arrow
   
   for(int p = 0; p < 21; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("CRSI(%d,%d,%d)", InpDomCycle, InpLeveling, InpSmoothLen));
   
   g_prevBuy = false; g_prevSell = false;
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minBars = InpDomCycle * 2 + InpBBLen + InpDivLeft + InpDivRight + 50;
   if(rates_total < minBars) return 0;
   
   if(prev_calculated == 0)
   {
      ArrayInitialize(g_crsi, EMPTY_VALUE);
      ArrayInitialize(g_smoothCRSI, EMPTY_VALUE);
      ArrayInitialize(g_dbCRSI, EMPTY_VALUE);
      ArrayInitialize(g_ubCRSI, EMPTY_VALUE);
      ArrayInitialize(g_fib50, EMPTY_VALUE);
      ArrayInitialize(g_fib618Up, EMPTY_VALUE);
      ArrayInitialize(g_fib618Dn, EMPTY_VALUE);
      ArrayInitialize(g_levelHI, EMPTY_VALUE);
      ArrayInitialize(g_levelMID, EMPTY_VALUE);
      ArrayInitialize(g_levelLO, EMPTY_VALUE);
      ArrayInitialize(g_levelHISub, EMPTY_VALUE);
      ArrayInitialize(g_levelLOSub, EMPTY_VALUE);
      ArrayInitialize(g_bbUpper, EMPTY_VALUE);
      ArrayInitialize(g_bbMiddle, EMPTY_VALUE);
      ArrayInitialize(g_bbLower, EMPTY_VALUE);
      ArrayInitialize(g_buySig, EMPTY_VALUE);
      ArrayInitialize(g_sellSig, EMPTY_VALUE);
      ArrayInitialize(g_sqzMom, EMPTY_VALUE);
      ArrayInitialize(g_sqzOn, EMPTY_VALUE);
      ArrayInitialize(g_bbMidStd, EMPTY_VALUE);
      ArrayInitialize(g_priceNorm, EMPTY_VALUE);
   }
   
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start < minBars) start = minBars;
   
   // ── Source price array ──
   double src[];
   ArrayResize(src, rates_total);
   for(int i = 0; i < rates_total; i++)
      src[i] = GetPrice(open[i], high[i], low[i], close[i], InpSrc);
   
   // ── TR array for SQZ ──
   double trArr[];
   ArrayResize(trArr, rates_total);
   trArr[0] = high[0] - low[0];
   for(int i = 1; i < rates_total; i++)
      trArr[i] = InpSQZTrueRange ? TrueRange(high[i], low[i], close[i-1]) : (high[i] - low[i]);
   
   // ── MAIN LOOP ────────────────────────────────────────────────────────────
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      g_buySig[i] = EMPTY_VALUE;
      g_sellSig[i] = EMPTY_VALUE;
      g_bbUpper[i] = EMPTY_VALUE;
      g_bbLower[i] = EMPTY_VALUE;
      g_sqzMom[i] = EMPTY_VALUE;
      g_sqzOn[i] = EMPTY_VALUE;
      
      // --- CRSI Calculation ---
      int cycleLen   = InpDomCycle / 2;
      int cyclicMem  = InpDomCycle * 2;
      double torque  = 2.0 / (10.0 + 1.0);
      int phasingLag = (10 - 1) / 2;
      
      // Calculate RSI
      double upSum = 0, downSum = 0;
      for(int j = 0; j < cycleLen && i - j > 0; j++)
      {
         double change = src[i - j] - src[i - j - 1];
         if(change > 0) upSum += change; else downSum -= change;
      }
      double rsiVal = (downSum == 0) ? 100 : (upSum == 0) ? 0 : 100 - 100 / (1 + upSum / downSum);
      
      // CRSI = torque * (2*rsi - rsi[phasingLag]) + (1-torque) * crsi[1]
      double prevCRSI = (i > 0) ? g_crsi[i-1] : rsiVal;
      double phasedRSI = (i >= phasingLag) ? rsiVal : rsiVal;
      
      // Compute RSI at phasing lag
      double phasedRSI2 = rsiVal;
      if(i >= phasingLag && i - phasingLag >= 0)
      {
         // Recalc RSI for phased bar
         int pIdx = i - phasingLag;
         double pUp = 0, pDn = 0;
         for(int j = 0; j < cycleLen && pIdx - j > 0; j++)
         {
            double chg = src[pIdx - j] - src[pIdx - j - 1];
            if(chg > 0) pUp += chg; else pDn -= chg;
         }
         phasedRSI2 = (pDn == 0) ? 100 : (pUp == 0) ? 0 : 100 - 100/(1 + pUp/pDn);
      }
      
      g_crsi[i] = torque * (2.0 * rsiVal - phasedRSI2) + (1.0 - torque) * prevCRSI;
      g_crsi[i] = MathMax(0, MathMin(100, g_crsi[i]));
      
      // Smooth CRSI
      g_smoothCRSI[i] = SMA(g_crsi, InpSmoothLen, i - InpSmoothLen + 1);
      
      // --- Bollinger Bands on CRSI ---
      g_bbMiddle[i] = SMA(g_crsi, InpBBLen, i - InpBBLen + 1);
      double bbStd = StdDev(g_crsi, InpBBLen, i - InpBBLen + 1);
      g_bbMidStd[i] = bbStd;
      
      if(InpShowBB)
      {
         g_bbUpper[i] = g_bbMiddle[i] + bbStd * InpBBMult;
         g_bbLower[i] = g_bbMiddle[i] - bbStd * InpBBMult;
      }
      
      // --- CRSI Dynamic Bands ---
      g_dbCRSI[i] = PercentileNR(g_crsi, cyclicMem, InpLeveling, i - cyclicMem + 1);
      g_ubCRSI[i] = PercentileNR(g_crsi, cyclicMem, 100 - InpLeveling, i - cyclicMem + 1);
      
      double range = g_ubCRSI[i] - g_dbCRSI[i];
      g_fib50[i]     = (g_ubCRSI[i] + g_dbCRSI[i]) / 2.0;
      g_fib618Up[i]  = g_fib50[i] + range * 0.618 / 2.0;
      g_fib618Dn[i]  = g_fib50[i] - range * 0.618 / 2.0;
      
      // --- Static Levels ---
      g_levelHI[i]    = InpCRSI_HI;
      g_levelMID[i]   = InpCRSI_MID;
      g_levelLO[i]    = InpCRSI_LO;
      g_levelHISub[i] = InpCRSI_HI_sub;
      g_levelLOSub[i] = InpCRSI_LO_sub;
      
      // --- Squeeze Momentum ---
      if(InpUseSQZ && i >= InpSQZMomLen + InpSQZBBLen)
      {
         // BB and KC on price
         double bbBasis = SMA(src, InpSQZBBLen, i - InpSQZBBLen + 1);
         double bbDev   = StdDev(src, InpSQZBBLen, i - InpSQZBBLen + 1) * InpSQZBBMult;
         double upperBB = bbBasis + bbDev;
         double lowerBB = bbBasis - bbDev;
         
         double kcBasis = SMA(src, InpSQZKCLen, i - InpSQZKCLen + 1);
         double kcRange = SMA(trArr, InpSQZKCLen, i - InpSQZKCLen + 1);
         double upperKC = kcBasis + kcRange * InpSQZKCMult;
         double lowerKC = kcBasis - kcRange * InpSQZKCMult;
         
         // Squeeze on: BB inside KC
         g_sqzOn[i] = (lowerBB > lowerKC && upperBB < upperKC) ? 1.0 : 0.0;
         
         // Momentum = linreg(price - mean, len)
         double rangeMid = (Highest(high, InpSQZMomLen, i - InpSQZMomLen + 1) +
                           Lowest(low, InpSQZMomLen, i - InpSQZMomLen + 1)) / 2.0;
         double classicMean = (rangeMid + SMA(src, InpSQZMomLen, i - InpSQZMomLen + 1)) / 2.0;
         
         double diffArr[];
         ArrayResize(diffArr, rates_total);
         for(int j = 0; j < rates_total; j++)
            diffArr[j] = src[j] - classicMean;
         
         g_sqzMom[i] = LinReg(diffArr, InpSQZMomLen, i - InpSQZMomLen + 1);
         
         if(InpSQZSmoothLen > 1 && i - InpSQZSmoothLen + 1 >= 0)
            g_sqzMom[i] = EMA(g_sqzMom, InpSQZSmoothLen, i - InpSQZSmoothLen + 1);
      }
      
      // --- Normalized Price Trend ---
      double priceMA = EMA(src, 5, i - 4);
      double hiMA100 = Highest(src, 100, MathMax(0, i - 99));
      double loMA100 = Lowest(src, 100, MathMax(0, i - 99));
      if(hiMA100 - loMA100 > 0)
         g_priceNorm[i] = ((priceMA - loMA100) / (hiMA100 - loMA100)) * 100.0;
      else
         g_priceNorm[i] = 50.0;
      
      // --- Divergence Detection ---
      if(i >= InpDivLeft + InpDivRight)
      {
         int pivotIdx = i - InpDivRight;
         
         bool isPivotHi = IsPivotHigh(high, InpDivLeft, InpDivRight, pivotIdx);
         bool isPivotLo = IsPivotLow(low, InpDivLeft, InpDivRight, pivotIdx);
         
         if(isPivotHi || isPivotLo)
         {
            DetectDivergence(isPivotHi, isPivotLo, high, low, pivotIdx, time);
         }
      }
      
      // --- Signal Generation (simplified without trading) ---
      bool crossoverLong  = (i > 0 && g_crsi[i] > g_smoothCRSI[i] && g_crsi[i-1] <= g_smoothCRSI[i-1]);
      bool crossoverShort = (i > 0 && g_crsi[i] < g_smoothCRSI[i] && g_crsi[i-1] >= g_smoothCRSI[i-1]);
      
      bool longSig  = crossoverLong && g_crsi[i] > g_bbMiddle[i];
      bool shortSig = crossoverShort && g_crsi[i] < g_bbMiddle[i];
      
      if(InpShowSignals)
      {
         g_buySig[i]  = longSig  ? g_crsi[i] - 2.0 : EMPTY_VALUE;
         g_sellSig[i] = shortSig ? g_crsi[i] + 2.0 : EMPTY_VALUE;
      }
      
      // Alerts
      if(InpShowAlerts && i == rates_total - 1)
      {
         if(longSig && !g_prevBuy)
            Alert("CRSI LONG | ", _Symbol, " | CRSI=", DoubleToString(g_crsi[i], 2));
         if(shortSig && !g_prevSell)
            Alert("CRSI SHORT | ", _Symbol, " | CRSI=", DoubleToString(g_crsi[i], 2));
         g_prevBuy = longSig; g_prevSell = shortSig;
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Divergence Detection Engine                                       |
//+------------------------------------------------------------------+
void DetectDivergence(bool isPhi, bool isPlo, const double &h[], const double &l[],
                      int pivotIdx, const datetime &time[])
{
   static double lastPhiPrice = 0, lastPhiOsc = 0;
   static int    lastPhiIdx   = -1;
   static double lastPloPrice = 0, lastPloOsc = 0;
   static int    lastPloIdx   = -1;
   
   if(isPhi)
   {
      double curPrice = h[pivotIdx];
      double curOsc   = g_crsi[pivotIdx];
      
      if(lastPhiIdx >= 0 && (pivotIdx - lastPhiIdx) < InpMaxPivotBars)
      {
         // Regular Bearish: price higher, osc lower
         if(curPrice > lastPhiPrice && curOsc < lastPhiOsc)
            DrawDivLine("RB_", lastPhiIdx, lastPhiOsc, pivotIdx, curOsc, clrRed, STYLE_SOLID, 2);
         // Hidden Bearish: price lower, osc higher
         if(curPrice < lastPhiPrice && curOsc > lastPhiOsc)
            DrawDivLine("HB_", lastPhiIdx, lastPhiOsc, pivotIdx, curOsc, clrMaroon, STYLE_DASH, 2);
         // Bullish Convergence: price higher, osc higher
         if(curPrice > lastPhiPrice && curOsc > lastPhiOsc)
            DrawDivLine("BC_", lastPhiIdx, lastPhiOsc, pivotIdx, curOsc, clrBlue, STYLE_DOT, 1);
      }
      lastPhiPrice = curPrice;
      lastPhiOsc   = curOsc;
      lastPhiIdx   = pivotIdx;
   }
   
   if(isPlo)
   {
      double curPrice = l[pivotIdx];
      double curOsc   = g_crsi[pivotIdx];
      
      if(lastPloIdx >= 0 && (pivotIdx - lastPloIdx) < InpMaxPivotBars)
      {
         // Regular Bullish: price lower, osc higher
         if(curPrice < lastPloPrice && curOsc > lastPloOsc)
            DrawDivLine("RB_", lastPloIdx, lastPloOsc, pivotIdx, curOsc, clrLime, STYLE_SOLID, 2);
         // Hidden Bullish: price higher, osc lower
         if(curPrice > lastPloPrice && curOsc < lastPloOsc)
            DrawDivLine("HB_", lastPloIdx, lastPloOsc, pivotIdx, curOsc, C'0x32,0xCD,0x32', STYLE_DASH, 2);
         // Bearish Convergence: price lower, osc lower
         if(curPrice < lastPloPrice && curOsc < lastPloOsc)
            DrawDivLine("BC_", lastPloIdx, lastPloOsc, pivotIdx, curOsc, clrPurple, STYLE_DOT, 1);
      }
      lastPloPrice = curPrice;
      lastPloOsc   = curOsc;
      lastPloIdx   = pivotIdx;
   }
}

//+------------------------------------------------------------------+
//| Draw divergence line on chart                                     |
//+------------------------------------------------------------------+
void DrawDivLine(string type, int idx1, double val1, int idx2, double val2,
                 color clr, ENUM_LINE_STYLE style, int width)
{
   if(!InpShowDivLines) return;
   
   // Limit total lines
   static int lineCount = 0;
   if(lineCount >= InpMaxDivLines * 6) return;
   
   string name = g_prefix + type + IntegerToString(idx2);
   if(ObjectFind(0, name) >= 0) return;
   
   // Get time at bar indices
   datetime t1, t2;
   int barShift1 = iBars(_Symbol, PERIOD_CURRENT) - idx1 - 1;
   int barShift2 = iBars(_Symbol, PERIOD_CURRENT) - idx2 - 1;
   
   datetime barTimes[];
   ArraySetAsSeries(barTimes, true);
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, iBars(_Symbol, PERIOD_CURRENT), barTimes) <= 0)
      return;
   
   if(barShift1 >= ArraySize(barTimes) || barShift2 >= ArraySize(barTimes)) return;
   t1 = barTimes[barShift1];
   t2 = barTimes[barShift2];
   
   ObjectCreate(0, name, OBJ_TREND, 1, t1, val1, t2, val2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   
   lineCount++;
}

//+------------------------------------------------------------------+
//| Get price from source enum                                        |
//+------------------------------------------------------------------+
double GetPrice(double o, double h, double l, double c, ENUM_APPLIED_PRICE ap)
{
   switch(ap)
   {
      case PRICE_OPEN:    return o;
      case PRICE_HIGH:    return h;
      case PRICE_LOW:     return l;
      case PRICE_CLOSE:   return c;
      case PRICE_MEDIAN:  return (h+l)/2;
      case PRICE_TYPICAL: return (h+l+c)/3;
      case PRICE_WEIGHTED:return (h+l+c*2)/4;
      default:            return c;
   }
}

//+------------------------------------------------------------------+
//| Cleanup objects                                                   |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   int total = ObjectsTotal(1); // Sub-window 1
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(1, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(1, name);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
