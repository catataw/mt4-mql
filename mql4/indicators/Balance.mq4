/**
 * Balance-Verlauf des aktuellen Accounts als Linienchart im Indikator-Subfenster
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

#include <core/indicator.mqh>

#property indicator_separate_window

#property indicator_buffers 1
#property indicator_color1  Blue


double iBalance[];


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // ERS_TERMINAL_NOT_READY abfangen
   if (!GetAccountNumber())
      return(SetLastError(stdlib_GetLastError()));

   SetIndexBuffer(0, iBalance);
   SetIndexLabel (0, "Balance");
   IndicatorShortName("Balance");
   IndicatorDigits(2);

   return(catch("onInit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // Abschlu� der Buffer-Initialisierung �berpr�fen
   if (ArraySize(iBalance) == 0)                                     // kann bei Terminal-Start auftreten
      return(SetLastError(ERS_TERMINAL_NOT_READY));

   // Alle Werte komplett ...
   if (!ValidBars) {
      ArrayInitialize(iBalance, EMPTY_VALUE);                        // vor Neuberechnung alte Werte zur�cksetzen
      if (IsError(iAccountBalanceSeries(AccountNumber(), iBalance)))
         return(SetLastError(stdlib_GetLastError()));
   }
   else {                                                            // ... oder nur die fehlenden Werte berechnen
      for (int bar=ChangedBars-1; bar >= 0; bar--) {
         if (IsError(iAccountBalance(AccountNumber(), iBalance, bar)))
            return(SetLastError(stdlib_GetLastError()));
      }
   }

   return(last_error);
}


