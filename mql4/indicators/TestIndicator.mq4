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
   onInit(T_INDICATOR, WindowExpertName());

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
int onTick() {
   static bool done = false;
   if (!done) {
      debug("onTick()    vor ForceMessageBox(), thread = "+ GetCurrentThreadId());

      ForceMessageBox("hello", __SCRIPT__, MB_OK);

      debug("onTick()   nach ForceMessageBox(), thread = "+ GetCurrentThreadId());
      done = true;
   }

   return(catch("onTick()"));
}
