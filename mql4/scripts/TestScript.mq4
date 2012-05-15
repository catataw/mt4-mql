/**
 * TestScript
 */
#include <types.mqh>
#define     __TYPE__    T_SCRIPT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>
//#include <sampledll.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   return(catch("onInit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(catch("onStart()"));
}
