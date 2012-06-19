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
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   done = false;
   //debug("onInit()   string="+ StaticString() +"  bool="+ StaticBool() +"  int="+ StaticInt() +"  double="+ NumberToStr(StaticDouble(), ".1+"));
   return(catch("onInit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {

   if (!done) {
      //debug("onTick()   string="+ StaticString() +"  bool="+ StaticBool() +"  int="+ StaticInt() +"  double="+ NumberToStr(StaticDouble(), ".1+"));
      done = true;
   }
   return(catch("onTick()"));
}


/**
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   done = false;
   return(catch("onDeinit()"));
}
