/**
 * SnowRoller Resume
 */
#include <types.mqh>
#define     __TYPE__    T_SCRIPT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


#property show_inputs


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(catch("onStart()"));
}


