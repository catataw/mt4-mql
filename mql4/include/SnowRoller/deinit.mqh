
/**
 * Kein UninitializeReason gesetzt: im Tester nach regulärem Ende (Testperiode zu Ende)
 *
 * @return int - Fehlerstatus
 */
int onDeinitUndefined() {
   if (IsTesting()) {
      if (__STATUS__CANCELLED)
         return(onDeinitChartClose());                               // entspricht gewaltsamen Ende

      if (status==STATUS_WAITING || status==STATUS_PROGRESSING) {
         int iNull[];
         if (UpdateStatus(iNull, iNull))
            StopSequence();                                          // ruft intern SaveStatus() auf
         ShowStatus();
      }
      return(last_error);
   }
   return(catch("onDeinitUndefined()", ERR_RUNTIME_ERROR));          // mal schaun, wann hier jemand reinlatscht
}


/**
 * - Chart geschlossen                       -oder-
 * - Template wird neu geladen               -oder-
 * - Terminal-Shutdown                       -oder-
 * - im Tester nach Betätigen des "Stop"-Buttons oder nach Chart ->Close
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Der "Stop"-Button des Testers kann intern betätigt worden sein (nach einem Fehler oder nach Testabschluß).
 * -----
 */
int onDeinitChartClose() {
   // (1) Im Tester
   if (IsTesting()) {
      __STATUS__CANCELLED = true;
      /**
       * !!! Vorsicht: Die start()-Funktion wurde gewaltsam beendet, die primitiven Variablen können Datenmüll enthalten !!!
       *
       * Das Flag "Statusfile nicht löschen" kann nicht über primitive Variablen oder den Chart kommuniziert werden.
       *  => Strings/Arrays testen (ansonsten globale Variable mit Thread-ID)
       */
      if (IsLastError()) {
         // Statusfile löschen
         FileDelete(GetMqlStatusFileName());
         GetLastError();                                             // falls in FileDelete() ein Fehler auftrat

         // Der Fenstertitel des Testers kann nicht zurückgesetzt werden: SendMessage() führt in deinit() zu Deadlock.
      }
      return(last_error);
   }


   // (2) Nicht im Tester:  Der Status kann sich seit dem letzten Tick geändert haben.
   if (!IsTest()) /*&&*/ if (status==STATUS_WAITING || status==STATUS_STARTING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      int iNull[];
      UpdateStatus(iNull, iNull);
      SaveStatus();
   }
   StoreStickyStatus();                                              // für Terminal-Restart oder Profile-Wechsel
   return(last_error);
}


/**
 * EA von Hand entfernt (Chart ->Expert ->Remove) oder neuer EA drübergeladen
 *
 * @return int - Fehlerstatus
 */
int onDeinitRemove() {
   // Der Status kann sich seit dem letzten Tick geändert haben.
   if (!IsTest()) /*&&*/ if (status==STATUS_WAITING || status==STATUS_STARTING || status==STATUS_PROGRESSING || status==STATUS_STOPPING) {
      int iNull[];
      UpdateStatus(iNull, iNull);
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
   StoreStickyStatus();
   return(-1);
}


/**
 * Parameteränderung
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // alte Parameter für Vergleich mit neuen Parametern zwischenspeichern
   last.Sequence.ID             = StringConcatenate(Sequence.ID,             "");   // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
   last.Sequence.StatusLocation = StringConcatenate(Sequence.StatusLocation, "");
   last.GridDirection           = StringConcatenate(GridDirection,           "");
   last.GridSize                = GridSize;
   last.LotSize                 = LotSize;
   last.StartConditions         = StringConcatenate(StartConditions,         "");
   last.StopConditions          = StringConcatenate(StopConditions,          "");
   last.Breakeven.Color         = Breakeven.Color;
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
