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
   if (IsError(onInit(T_EXPERT)))
      return(last_error);


   int array[3][3];

   array[0][0] = 3; array[0][1] = -3; array[0][2] = 3;
   array[1][0] = 2; array[1][1] = -2; array[1][2] = 2;
   array[2][0] = 1; array[2][1] = -1; array[2][2] = 1;

   debug("init()   array = "+ IntsToStr(array, NULL));

   ArraySort(array);

   debug("init()   array = "+ IntsToStr(array, NULL));

   return(catch("init()"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   if (IsError(onDeinit()))
      return(last_error);

   if (IsTesting()) /*&&*/ if (!DeletePendingOrders(CLR_NONE))       // Der Tester schließt beim Beenden nur offene Positionen,
      return(SetLastError(stdlib_PeekLastError()));                  // offene Pending-Orders werden jedoch nicht gelöscht.

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
      done = true;
   }
   return(catch("onTick()"));
}
