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
   bool sized = false;
   bool init  = false;

   GlobalArrays(sized, init);


   return(last_error);

   GlobalPrimitives(NULL);
   LocalPrimitives(NULL);
   GlobalArrays(NULL, NULL);
   LocalArrays(NULL, NULL);
}
