//+------------------------------------------------------------------+
//| Test_MSZZ_StructuralReplay.mq5                                    |
//| D024: verifies CMSZZStructuralReplay::BuildBarHistory's final-bar |
//| state is byte-identical to the real CMSZZTripleZigZagEngine's     |
//| Rebuild()+Snapshot() on the same input -- the safeguard against   |
//| algorithmic drift between the live engine and this research       |
//| duplicate (see DECISION_LOG.md D024).                             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Research/StructuralReplay.mqh>

input string InpSymbol="XAUUSD";
input ENUM_TIMEFRAMES InpPeriod=PERIOD_M5;

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

void AssertPivotEqual(const MSZZPivot &a,const MSZZPivot &b,const string label)
{
   AssertTrue(a.valid==b.valid && MathAbs(a.price-b.price)<0.0000001 &&
              a.pivot_time==b.pivot_time && a.confirmed_time==b.confirmed_time &&
              a.structure_label==b.structure_label,
              StringFormat("%s matches (valid=%d/%d price=%.5f/%.5f struct=%d/%d)",
                            label,a.valid,b.valid,a.price,b.price,(int)a.structure_label,(int)b.structure_label));
}

void RunEquivalenceCase(const string label,const MqlRates &rates[],const int count,
                         const int atr_len,const double atr_mult,const int min_bars_between,
                         const ENUM_MSZZ_SPEED speed)
{
   CMSZZTripleZigZagEngine engine;
   int fl=(speed==MSZZ_SPEED_FAST)?atr_len:14; double fm=(speed==MSZZ_SPEED_FAST)?atr_mult:1.0;
   int ml=(speed==MSZZ_SPEED_MEDIUM)?atr_len:14; double mm=(speed==MSZZ_SPEED_MEDIUM)?atr_mult:2.0;
   int sl=14; double sm=3.5;
   engine.Configure(fl,fm,ml,mm,sl,sm,min_bars_between);
   bool ok=engine.Rebuild(InpSymbol,InpPeriod,rates,count);
   AssertTrue(ok,label+": real engine Rebuild succeeds");
   MSZZSpeedSnapshot snap=engine.Snapshot(speed);

   MSZZSpeedBarState hist[];
   bool ok2=CMSZZStructuralReplay::BuildBarHistory(InpSymbol,InpPeriod,rates,count,atr_len,atr_mult,min_bars_between,speed,hist);
   AssertTrue(ok2,label+": duplicate BuildBarHistory succeeds");

   MSZZSpeedBarState last=hist[count-1];
   AssertTrue(last.leg_direction==snap.leg_direction,label+": leg_direction matches");
   AssertPivotEqual(last.last_high,snap.last_high,label+": last_high");
   AssertPivotEqual(last.last_low,snap.last_low,label+": last_low");
   AssertPivotEqual(last.prior_high,snap.prior_high,label+": prior_high");
   AssertPivotEqual(last.prior_low,snap.prior_low,label+": prior_low");
   AssertTrue(last.bullish_break==snap.bullish_break,label+": bullish_break matches");
   AssertTrue(last.bearish_break==snap.bearish_break,label+": bearish_break matches");
}

void BuildTrendingBars(MqlRates &bars[],const int count,const double start_price,
                        const double step,const double noise,const datetime start_time,const int period_seconds)
{
   ArrayResize(bars,count);
   double price=start_price;
   for(int i=0;i<count;i++)
   {
      bars[i].time=start_time+i*period_seconds;
      double wiggle=(i%7==0)?-noise:(i%5==0?noise*0.6:0.0);
      bars[i].open=price;
      bars[i].high=price+MathAbs(step)+noise+wiggle;
      bars[i].low=price-noise*0.5+wiggle;
      price+=step;
      bars[i].close=price;
   }
}

void TestSyntheticUptrend()
{
   MqlRates bars[];
   BuildTrendingBars(bars,120,100.0,0.6,0.3,D'2026.01.01 00:00:00',300);
   RunEquivalenceCase("synthetic uptrend (fast)",bars,120,14,1.0,3,MSZZ_SPEED_FAST);
   RunEquivalenceCase("synthetic uptrend (medium)",bars,120,14,2.0,3,MSZZ_SPEED_MEDIUM);
}

void TestSyntheticChoppy()
{
   MqlRates bars[];
   ArrayResize(bars,150);
   double price=200.0;
   datetime t=D'2026.02.01 00:00:00';
   for(int i=0;i<150;i++)
   {
      bars[i].time=t+i*300;
      double dir=(MathMod(i,11)<5)?1.0:-1.0;
      bars[i].open=price;
      price+=dir*0.8;
      bars[i].close=price;
      bars[i].high=MathMax(bars[i].open,bars[i].close)+0.5;
      bars[i].low=MathMin(bars[i].open,bars[i].close)-0.5;
   }
   RunEquivalenceCase("synthetic choppy (fast)",bars,150,14,1.0,3,MSZZ_SPEED_FAST);
   RunEquivalenceCase("synthetic choppy (medium)",bars,150,14,2.0,3,MSZZ_SPEED_MEDIUM);
}

void TestRealData()
{
   MqlRates bars[];
   datetime from=D'2025.06.01 00:00:00';
   datetime to=D'2025.07.01 00:00:00';
   int copied=CopyRates(InpSymbol,InpPeriod,from,to,bars);
   if(copied<200)
   {
      Print("SKIP: real-data equivalence case -- insufficient bars copied (",copied,")");
      return;
   }
   RunEquivalenceCase("real XAUUSD M5 (fast)",bars,copied,14,1.0,3,MSZZ_SPEED_FAST);
   RunEquivalenceCase("real XAUUSD M5 (medium)",bars,copied,14,2.0,3,MSZZ_SPEED_MEDIUM);
}

void OnStart()
{
   TestSyntheticUptrend();
   TestSyntheticChoppy();
   TestRealData();
   PrintFormat("MSZZ structural replay equivalence test complete failures=%d",g_failures);
}
