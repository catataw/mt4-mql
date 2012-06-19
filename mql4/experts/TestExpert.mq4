/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


bool done;


/**
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   done = false;
   return(catch("onInit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {
      debug("onTick()   stdSymbol="+ StdSymbol());
      done = true;
   }
   return(catch("onTick()"));
   //debug("onTick()   string="+ StaticString() +"  bool="+ StaticBool() +"  int="+ StaticInt() +"  double="+ NumberToStr(StaticDouble(), ".1+"));
}
