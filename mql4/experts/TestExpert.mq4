/**
 * TestExpert
 */
#include <core/define.mqh>
#define __TYPE__        T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {
      done = true;
   }

   string symbol    = Symbol();
   int    timeframe = Period();
   string indicator = "Moving Average";
   //-----------------------------------------
   int    MA.Periods        = 200;
   string MA.Timeframe      = "";
   string AppliedPrice      = "Close";
   string AppliedPrice.Help = "";
   int    Max.Values        = 2000;
   color  Color.UpTrend     = DodgerBlue;
   color  Color.DownTrend   = Orange;
   color  Color.Reversal    = Yellow;
   //-----------------------------------------
   int buffer = 0;
   int bar    = 0;

   debug("onTick()");

   double value = iCustom(symbol, timeframe, indicator,
                          MA.Periods,
                          MA.Timeframe,
                          AppliedPrice,
                          AppliedPrice.Help,
                          Max.Values,
                          Color.UpTrend,
                          Color.DownTrend,
                          Color.Reversal,
                          buffer, bar);

   //debug("onTick()   value(iCustom)="+ NumberToStr(value, ".+"));
   return(catch("onTick()"));
}


