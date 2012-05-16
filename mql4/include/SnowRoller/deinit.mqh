
/**
 * Kein UninitializeReason gesetzt: im Tester nach regulärem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   // Tester
   if (IsTesting()) {
      if (StopSequence())                                            // ruft intern UpdateStatus() und SaveStatus() auf
         ShowStatus();
      return(-1);
   }
   return(catch("onDeinitUndefined()", ERR_RUNTIME_ERROR));          // mal schaun, wann hier jemand reinlatscht
}


// !!! TODO: Tester-Funktionalität implementieren !!!
/**
 * - Chart geschlossen
 * - Template wird neu geladen
 * - im Tester nach vorzeitigem, manuellem Abbruch
 * - Terminal-Shutdown
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartClose() {
   // Tester
   if (IsTesting()) {
      // TODO: Statusfile löschen und Titelzeile des Testers zurücksetzen
      return(-1);
   }

   // der Status kann sich seit dem letzten Tick geändert haben
   if (status==STATUS_WAITING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      UpdateStatus();
      SaveStatus();
   }
   StoreTransientStatus();                                           // für evt. Terminal-Restart
   return(-1);
}


/**
 * EA von Hand entfernt (Chart ->Expert ->Remove)
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // der Status kann sich seit dem letzten Tick geändert haben
   if (status==STATUS_WAITING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      UpdateStatus();
      SaveStatus();
   }
   return(NO_ERROR);
}


/**
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   StoreTransientStatus();
   return(-1);
}


/**
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // alte Parameter für Vergleich mit neuen Parametern zwischenspeichern
   last.Sequence.ID      = StringConcatenate(Sequence.ID,      "");
   last.GridDirection    = StringConcatenate(GridDirection,    "");  // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
   last.GridSize         = GridSize;
   last.LotSize          = LotSize;
   last.StartConditions  = StringConcatenate(StartConditions,  "");
   last.StopConditions   = StringConcatenate(StopConditions,   "");
   last.OrderDisplayMode = StringConcatenate(OrderDisplayMode, "");
   last.Breakeven.Color  = Breakeven.Color;
   last.Breakeven.Width  = Breakeven.Width;
   return(-1);

}


/**
 * Symbol- oder Timeframewechsel
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // nicht-statische Input-Parameter werden für's nächste init() zwischengespeichert
   return(onDeinitParameterChange());                                // Funktionalität entspricht onDeinitParameterChange()
}
