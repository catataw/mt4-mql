/**
 * Schickt einen k�nstlichen Tick an den aktuellen Chart.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = { INIT_NO_BARS_REQUIRED };
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(Chart.SendTick(true));
}


