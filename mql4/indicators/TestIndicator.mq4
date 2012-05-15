/**
 * TestIndicator
 */
#include <types.mqh>
#define     __TYPE__    T_INDICATOR
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


#property indicator_chart_window


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {

   static bool done;
   if (!done) {
      done = true;

      //debug("onTick(0)");
      //SwitchExperts(!IsExpertEnabled());
      //debug("onTick(1)");
   }

   return(catch("onTick()"));
}
