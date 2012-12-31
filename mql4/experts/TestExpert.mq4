/**
 * TestExpert
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern string Parameter = "dummy";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


#include <test/library.mqh>
//#include <test/static.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   bool sized = true;
   bool init  = true;

   //GlobalPrimitives(init);
   //LocalPrimitives(init);

   //GlobalArrays(sized, init);
   LocalArrays(sized, init);

   return(last_error);
}







/**
 *
 * @return int - Fehlerstatus
 */
void DummyCalls() {
   GlobalPrimitives(NULL);
   LocalPrimitives(NULL);
   GlobalArrays(NULL, NULL);
   LocalArrays(NULL, NULL);
}
