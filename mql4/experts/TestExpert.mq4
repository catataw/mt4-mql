/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__      T_EXPERT
int   __INIT_FLAGS__[] = {INIT_TIMEZONE, INIT_TICKVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   return(catch("onTick()"));
}
