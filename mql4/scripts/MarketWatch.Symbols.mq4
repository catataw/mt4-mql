/**
 * Ruft den Kontextmen�-Befehl MarketWatch->Symbols auf.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = { INIT_DOESNT_REQUIRE_BARS };
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(MarketWatch.Symbols());
}
