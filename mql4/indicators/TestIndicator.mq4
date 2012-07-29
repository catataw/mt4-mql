/**
 * TestIndicator
 */
#include <types.mqh>
#define     __TYPE__    T_INDICATOR
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


#property indicator_chart_window


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

   int hWndTester = GetTesterWindow();
   if (hWndTester == 0)
      return(_int(catch("onTick(1)"), debug("onTick()   hWndTester=0x"+ IntToHexStr(hWndTester))));


   debug("onTick()   hWndTester=0x"+ IntToHexStr(hWndTester));


   return(catch("onTick(2)"));
}
