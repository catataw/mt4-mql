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
   init = true; init_error = NO_ERROR; __SCRIPT__ = WindowExpertName();
   stdlib_init(__SCRIPT__);

   int iNull[];
   //debug("init()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   main window thread="+ GetWindowThreadProcessId(GetTerminalWindow(), iNull));

   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   int iNull[];
   //debug("deinit()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   main window thread="+ GetWindowThreadProcessId(GetTerminalWindow(), iNull));

   return(catch("deinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int start() {
   Tick++;
   init = false;
   if (init_error != NO_ERROR) return(init_error);
   if (last_error != NO_ERROR) return(last_error);
   // --------------------------------------------

   static bool done = false;
   if (!done) {
      int iNull[];
      debug("start()   IsTesting()="+ IsTesting() +"   current thread="+ GetCurrentThreadId() +"   main window thread="+ GetWindowThreadProcessId(GetTerminalWindow(), iNull));
      done = true;
   }

   return(catch("start()"));
}
