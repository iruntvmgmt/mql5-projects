//+------------------------------------------------------------------+
//|                                                          WPR.mq5 |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2000-2026, MetaQuotes Ltd."
#property link        "https://www.mql5.com"
#property description "Larry Williams' Percent Range"
//--- indicator settings
#property indicator_separate_window
#property indicator_level1     -20.0
#property indicator_level2     -80.0
#property indicator_levelstyle STYLE_DOT
#property indicator_levelcolor clrSilver
#property indicator_levelwidth 1
#property indicator_maximum    0.0
#property indicator_minimum    -100.0
#property indicator_buffers    1
#property indicator_plots      1
#property indicator_type1      DRAW_LINE
#property indicator_color1     clrDodgerBlue
//--- input parameters
input int InpWPRPeriod=14; // Period
//--- indicator buffers
double    ExtWPRBuffer[];
//--- global variables
int       ExtPeriodWPR;
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
  {
//--- check for input value
   if(InpWPRPeriod<3)
     {
      ExtPeriodWPR=14;
      Print("Incorrect InpWPRPeriod value. Indicator will use value=",ExtPeriodWPR);
     }
   else
      ExtPeriodWPR=InpWPRPeriod;
//--- indicator's buffer
   SetIndexBuffer(0,ExtWPRBuffer);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,ExtPeriodWPR-1);
//--- name for DataWindow and indicator subwindow label
   IndicatorSetString(INDICATOR_SHORTNAME,"%R"+"("+string(ExtPeriodWPR)+")");
//--- digits
   IndicatorSetInteger(INDICATOR_DIGITS,2);
  }
//+------------------------------------------------------------------+
//| Williams’ Percent Range                                          |
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
   if(rates_total<ExtPeriodWPR)
      return(0);
//--- start working
   int i,pos=prev_calculated-1;
   if(pos<ExtPeriodWPR-1)
     {
      pos=ExtPeriodWPR-1;
      for(i=0; i<pos; i++)
         ExtWPRBuffer[i]=0.0;
     }
//---  main cycle
   for(i=pos; i<rates_total && !IsStopped(); i++)
     {
      double max_high=Highest(high,ExtPeriodWPR,i);
      double min_low =Lowest(low,ExtPeriodWPR,i);
      //--- calculate WPR
      if(max_high!=min_low)
         ExtWPRBuffer[i]=-(max_high-close[i])*100/(max_high-min_low);
      else
         ExtWPRBuffer[i]=ExtWPRBuffer[i-1];
     }
//--- return new prev_calculated value
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Maximum High                                                     |
//+------------------------------------------------------------------+
double Highest(const double &array[],int period,int cur_position)
  {
   double res=array[cur_position];
   for(int i=cur_position-1; i>cur_position-period && i>=0; i--)
      if(res<array[i])
         res=array[i];
   return(res);
  }
//+------------------------------------------------------------------+
//| Minimum Low                                                      |
//+------------------------------------------------------------------+
double Lowest(const double &array[],int period,int cur_position)
  {
   double res=array[cur_position];
   for(int i=cur_position-1; i>cur_position-period && i>=0; i--)
      if(res>array[i])
         res=array[i];
   return(res);
  }
//+------------------------------------------------------------------+
