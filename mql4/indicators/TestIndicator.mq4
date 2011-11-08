/**
 * TestIndicator
 */
#include <stdlib.mqh>
#include <win32api.mqh>


#property indicator_chart_window


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   init = true; init_error = NO_ERROR; __SCRIPT__ = WindowExpertName();
   stdlib_init(__SCRIPT__);

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
int start() {
   init = false;
   stdlib_onTick(0);

   static bool done = false;
   if (!done) {
      debug("start()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());
      done = true;
   }

   return(catch("start()"));
}
