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

   //debug("init()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());

   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {

   //debug("deinit()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   UI thread="+ GetUIThreadId());

   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int start() {
   init = false;
   stdlib_start(0);

   static bool done = false;
   if (!done) {
      debug("start()    vor ForceMessageBox(), thread = "+ GetCurrentThreadId());

      ForceMessageBox("hello", __SCRIPT__, MB_OK);

      debug("start()   nach ForceMessageBox(), thread = "+ GetCurrentThreadId());
      done = true;
   }

   return(catch("start()"));
}
