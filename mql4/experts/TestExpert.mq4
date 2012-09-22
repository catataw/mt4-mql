/**
 * TestExpert
 */
#include <stdtypes.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {

      if (TimeCurrent() > D'2012-07-20 09:30') {
         catch("onTick()", ERR_INVALID_STOP);

         done = true;
      }
   }

   return(last_error + catch("onTick()"));
}


