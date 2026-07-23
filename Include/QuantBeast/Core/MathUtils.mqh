//+------------------------------------------------------------------+
//|                                          QuantBeast/MathUtils.mqh |
//|                          XAUUSD Quant Beast EA - Math Utilities   |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_MATHUTILS_MQH
#define QB_MATHUTILS_MQH

#include "Constants.mqh"

//+------------------------------------------------------------------+
//| Clamp a value between min and max                                 |
//+------------------------------------------------------------------+
double Clamp(double value, double minVal, double maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

int ClampInt(int value, int minVal, int maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

//+------------------------------------------------------------------+
//| Linear interpolation                                             |
//+------------------------------------------------------------------+
double Lerp(double a, double b, double t)
{
   return a + (b - a) * t;
}

//+------------------------------------------------------------------+
//| Normalize a value to [0,1] range                                  |
//+------------------------------------------------------------------+
double Normalize01(double value, double minVal, double maxVal)
{
   if(MathAbs(maxVal - minVal) < QB_EPSILON) return 0.5;
   return Clamp((value - minVal) / (maxVal - minVal), 0.0, 1.0);
}

//+------------------------------------------------------------------+
//| Calculate mean of an array                                        |
//+------------------------------------------------------------------+
double ArrayMean(const double &arr[], int count)
{
   if(count <= 0) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < count; i++)
      sum += arr[i];
   return sum / count;
}

//+------------------------------------------------------------------+
//| Calculate standard deviation of an array                          |
//+------------------------------------------------------------------+
double ArrayStdDev(const double &arr[], int count, double mean)
{
   if(count <= 1) return 0.0;
   double sumSq = 0.0;
   for(int i = 0; i < count; i++)
   {
      double diff = arr[i] - mean;
      sumSq += diff * diff;
   }
   return MathSqrt(sumSq / (count - 1));
}

//+------------------------------------------------------------------+
//| Calculate both mean and std dev                                   |
//+------------------------------------------------------------------+
void ArrayMeanStdDev(const double &arr[], int count, double &mean, double &stddev)
{
   mean = ArrayMean(arr, count);
   stddev = ArrayStdDev(arr, count, mean);
}

//+------------------------------------------------------------------+
//| Calculate percentile of a sorted array                            |
//+------------------------------------------------------------------+
double ArrayPercentile(const double &sorted[], int count, double percentile)
{
   if(count <= 0) return 0.0;
   double idx = percentile / 100.0 * (count - 1);
   int lo = (int)MathFloor(idx);
   int hi = (int)MathCeil(idx);
   if(lo < 0) lo = 0;
   if(hi >= count) hi = count - 1;
   if(lo == hi) return sorted[lo];
   double frac = idx - lo;
   return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
}

//+------------------------------------------------------------------+
//| Calculate percentile of an unsorted array (copies and sorts)      |
//+------------------------------------------------------------------+
double ArrayPercentileUnsorted(const double &arr[], int count, double percentile)
{
   if(count <= 0) return 0.0;
   double sorted[];
   ArrayResize(sorted, count);
   for(int i = 0; i < count; i++) sorted[i] = arr[i];
   ArraySort(sorted);
   return ArrayPercentile(sorted, count, percentile);
}

//+------------------------------------------------------------------+
//| Linear regression slope over a window                             |
//+------------------------------------------------------------------+
double RegressionSlope(const double &y[], int start, int count)
{
   if(count < 2) return 0.0;

   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   for(int i = 0; i < count; i++)
   {
      double x = (double)i;
      double yVal = y[start + i];
      sumX  += x;
      sumY  += yVal;
      sumXY += x * yVal;
      sumX2 += x * x;
   }

   double denom = count * sumX2 - sumX * sumX;
   if(MathAbs(denom) < QB_EPSILON) return 0.0;

   return (count * sumXY - sumX * sumY) / denom;
}

// Series arrays are newest-first. Reverse the sign so positive always
// means price rose as chronological time advanced.
double RegressionSlopeSeries(const double &y[], int start, int count)
{
   return -RegressionSlope(y, start, count);
}

//+------------------------------------------------------------------+
//| Directional Efficiency Ratio (net displacement / total path)      |
//+------------------------------------------------------------------+
double DirectionalEfficiency(const double &arr[], int start, int count)
{
   if(count < 2 || start + count > ArraySize(arr)) return 0.0;

   double netChange = MathAbs(arr[start + count - 1] - arr[start]);
   double totalPath = 0.0;

   for(int i = start + 1; i < start + count; i++)
      totalPath += MathAbs(arr[i] - arr[i - 1]);

   if(totalPath < QB_EPSILON) return 1.0;
   return netChange / totalPath;
}

//+------------------------------------------------------------------+
//| Maximum value in an array slice                                   |
//+------------------------------------------------------------------+
double ArrayMaxSlice(const double &arr[], int start, int count)
{
   if(count <= 0) return 0.0;
   double maxVal = arr[start];
   for(int i = start + 1; i < start + count && i < ArraySize(arr); i++)
      if(arr[i] > maxVal) maxVal = arr[i];
   return maxVal;
}

//+------------------------------------------------------------------+
//| Minimum value in an array slice                                   |
//+------------------------------------------------------------------+
double ArrayMinSlice(const double &arr[], int start, int count)
{
   if(count <= 0) return 0.0;
   double minVal = arr[start];
   for(int i = start + 1; i < start + count && i < ArraySize(arr); i++)
      if(arr[i] < minVal) minVal = arr[i];
   return minVal;
}

//+------------------------------------------------------------------+
//| Round to nearest tick size                                        |
//+------------------------------------------------------------------+
double RoundToTick(double price, double tickSize)
{
   if(tickSize <= 0) return price;
   return MathRound(price / tickSize) * tickSize;
}

//+------------------------------------------------------------------+
//| Round down to tick size                                           |
//+------------------------------------------------------------------+
double RoundDownToTick(double price, double tickSize)
{
   if(tickSize <= 0) return price;
   return MathFloor(price / tickSize) * tickSize;
}

//+------------------------------------------------------------------+
//| Round up to tick size                                             |
//+------------------------------------------------------------------+
double RoundUpToTick(double price, double tickSize)
{
   if(tickSize <= 0) return price;
   return MathCeil(price / tickSize) * tickSize;
}

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                  |
//+------------------------------------------------------------------+
double NormalizePrice(double price, int digits)
{
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Calculate true range                                              |
//+------------------------------------------------------------------+
double TrueRange(double high, double low, double prevClose)
{
   double tr1 = high - low;
   double tr2 = MathAbs(high - prevClose);
   double tr3 = MathAbs(low - prevClose);
   return MathMax(tr1, MathMax(tr2, tr3));
}

//+------------------------------------------------------------------+
//| Exponential Moving Average (incremental)                          |
//+------------------------------------------------------------------+
double EMA_Incremental(double prevEMA, double newPrice, int period)
{
   double alpha = 2.0 / (period + 1.0);
   return prevEMA + alpha * (newPrice - prevEMA);
}

//+------------------------------------------------------------------+
//| Simple Moving Average over array slice                            |
//+------------------------------------------------------------------+
double SMA_Slice(const double &arr[], int start, int count)
{
   if(count <= 0) return 0.0;
   double sum = 0.0;
   for(int i = start; i < start + count; i++)
      sum += arr[i];
   return sum / count;
}

//+------------------------------------------------------------------+
//| Finite and within (minExclusive, maxInclusive]. Used by            |
//| QBProductionConfigurationValid() (QuantBeastEA.mq5, Part F         |
//| configuration audit) to reject nonfinite/negative/zero/dangerously |
//| permissive safety-critical inputs.                                 |
//+------------------------------------------------------------------+
bool QBValidNumberInRange(double value, double minExclusive, double maxInclusive)
{
   if(!MathIsValidNumber(value)) return false;
   if(value <= minExclusive) return false;
   if(value > maxInclusive) return false;
   return true;
}

#endif // QB_MATHUTILS_MQH
