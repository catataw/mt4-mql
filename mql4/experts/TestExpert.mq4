/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


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
