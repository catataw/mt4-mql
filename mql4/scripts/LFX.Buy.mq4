/**
 * Schickt dem TradeTerminal die Nachricht, eine "Buy Market"-Order f�r das aktuelle Symbol auszuf�hren. Mu� auf dem jeweiligen LFX-Chart ausgef�hrt werden.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

#include <core/script.mqh>
#include <stdfunctions.mqh>


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   return(last_error);
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   return(last_error);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(last_error);
}
