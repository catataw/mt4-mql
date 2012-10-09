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
int onTick() {

   if (!done) {
      done = true;
   }

   return(catch("onTick()"));
}
