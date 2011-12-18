/**
 * TestExpert
 */
#include <stdlib.mqh>
#include <win32api.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   onInit(T_EXPERT, WindowExpertName());

   debug("init()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());

   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   debug("deinit()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());
   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   static bool done = false;
   if (!done) {
      debug("onTick()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());
      done = true;
   }
   return(catch("onTick()"));
}
