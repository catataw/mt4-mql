
/**
 * Kein UninitializeReason gesetzt: im Tester nach regulärem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   if (IsTesting()) {
      if (__STATUS__CANCELLED)
         return(onDeinitChartClose());                               // entspricht gewaltsamen Ende

      if (status==STATUS_WAITING || status==STATUS_PROGRESSING)
         if (StopSequence())                                         // ruft intern UpdateStatus() und SaveStatus() auf
            ShowStatus();
      return(last_error);
   }
   return(catch("onDeinitUndefined()", ERR_RUNTIME_ERROR));          // mal schaun, wann hier jemand reinlatscht
}


/**
 * - Chart geschlossen                       -oder-
 * - Template wird neu geladen               -oder-
 * - Terminal-Shutdown                       -oder-
 * - im Tester nach gewaltsamen Beenden der start()-Funktion (Stop-Button oder Chart ->Close)
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartClose() {
   // (1) Tester
   if (IsTesting()) {
      __STATUS__CANCELLED = true;                                    // Vorsicht: der EA-Status ist undefined

      // Statusfile löschen
      FileDelete("presets\\"+ StringToLower(StdSymbol()) +".SR."+ sequenceId +".set");
      GetLastError();

      // Titelzeile des Testers kann nicht zurückgesetzt werden, SendMessage() führt in deinit() zu Deadlock
      return(last_error);
   }


   // (2) Nicht im Tester:  Der Status kann sich seit dem letzten Tick geändert haben.
   if (!IsTest()) /*&&*/ if (status==STATUS_WAITING || status==STATUS_STARTING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      UpdateStatus();
      SaveStatus();
   }
   StoreTransientStatus();                                           // für evt. Terminal-Restart
   return(last_error);
}


/**
 * EA von Hand entfernt (Chart ->Expert ->Remove)
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // Der Status kann sich seit dem letzten Tick geändert haben.
   if (!IsTest()) /*&&*/ if (status==STATUS_WAITING || status==STATUS_STARTING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      UpdateStatus();
      SaveStatus();
   }
   return(last_error);
}


/**
 * Recompilation
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   StoreTransientStatus();
   return(-1);
}


/**
 * Parameteränderung
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
   last.Sequence.Start   = StringConcatenate(Sequence.Start,   "");
   return(-1);

}


/**
 * Symbol- oder Timeframewechsel
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // nicht-statische Input-Parameter werden für's nächste init() zwischengespeichert
   return(onDeinitParameterChange());                                // entspricht onDeinitParameterChange()
}
