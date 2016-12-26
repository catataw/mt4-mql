/**
 * SuperBars Down
 *
 * Schickt dem SuperBars-Indikator des aktuellen Charts die Nachricht, den n�chstniedrigeren SuperTimeframe anzuzeigen.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = { INIT_NO_BARS_REQUIRED };
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
   // Schreibzugriff auf Command-Object synchronisieren
   string mutex = "mutex.SuperBars.command";
   if (!AquireLock(mutex, true))
      return(SetLastError(stdlib.GetLastError()));

   // Command setzen
   string label = "SuperBars.command";                             // TODO: Command zu bereits existierenden Commands hinzuf�gen
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))                return(_int(catch("onStart(1)"), ReleaseLock(mutex)));
      if (!ObjectSet(label, OBJPROP_TIMEFRAMES, OBJ_PERIODS_NONE)) return(_int(catch("onStart(2)"), ReleaseLock(mutex)));
   }
   if (!ObjectSetText(label, "Timeframe=Down"))                    return(_int(catch("onStart(3)"), ReleaseLock(mutex)));

   // Schreibzugriff auf Command-Object freigeben
   if (!ReleaseLock(mutex))
      return(SetLastError(stdlib.GetLastError()));

   // Tick senden
   Chart.SendTick();
   return(catch("onStart(4)"));
}
