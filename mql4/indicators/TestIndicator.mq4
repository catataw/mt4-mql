/**
 * TestIndicator
 */
#include <stdtypes.mqh>
#define     __TYPE__   T_INDICATOR
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>


#property indicator_chart_window


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   debug("onInit()");
   DebugMarketInfo();
   return(catch("onInit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   bool done;
   if (!done) {
      debug("onTick()");
      DebugMarketInfo();
      done = true;
   }
   return(catch("onTick()"));
}
