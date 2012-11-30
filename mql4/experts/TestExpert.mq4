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

   //---------------------------------
   int    MA.Periods        = 200;
   string MA.Timeframe      = "M5";
   string MA.Method         = "SMA";
   string MA.Method.Help    = "";
   string AppliedPrice      = "Close";
   string AppliedPrice.Help = "";
   int    Max.Values        = 2000;
   //---------------------------------
   int bar = 0;

   double value1 = iCustom(NULL, PERIOD_M5, "Moving Average",
                           MA.Periods,
                           MA.Timeframe,
                           MA.Method,
                           MA.Method.Help,
                           AppliedPrice,
                           AppliedPrice.Help,
                           Max.Values,
                           BUFFER_0, bar);

   double value2 = iCustom(NULL, PERIOD_M5, "Moving Average",
                           MA.Periods,
                           MA.Timeframe,
                           MA.Method,
                           MA.Method.Help,
                           AppliedPrice,
                           AppliedPrice.Help,
                           Max.Values,
                           BUFFER_1, bar);
   debug("onTick()   value1="+ NumberToStr(value1, ".+") +"   value2="+ NumberToStr(value2, ".+"));

   return(catch("onTick()"));
}


