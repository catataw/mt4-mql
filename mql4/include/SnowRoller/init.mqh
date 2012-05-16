
/**
 * Kein UninitializeReason gesetzt
 *
 * - nach Terminal-Neustart, neues Chartfenster, wenn alter EA, dann kein Input-Dialog
 * - File ->New ->Chart, neues Chartfenster, neuer EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitUndefined() {
   last_error = NO_ERROR;

   // Prüfen, ob im Chart Statusdaten existieren
   if (!RestoreTransientStatus())
      if (IsLastError())
         return(last_error);

   bool data = (ObjectFind(StringConcatenate(__NAME__, ".transient.Sequence.ID")) == 0);

   if (data) return(onInitRecompile());   // ja   -> alter EA -> kein Input-Dialog: Funktionalität entspricht onInitRecompile()
   else      return(onInitChartClose());  // nein -> neuer EA -> Input-Dialog:      Funktionalität entspricht onInitChartClose()
}


/**
 * altes Chartfenster mit neu geladenem Template, neuer EA, Input-Dialog, keine Statusdaten im Chart
 *
 * @return int - Fehlerstatus
 */
int onInitChartClose() {
   // (1) Zuerst eine angegebene Sequenz restaurieren
   if (ValidateConfiguration.ID(true)) {
      status = STATUS_WAITING;
      if (RestoreStatus())
         if (ValidateConfiguration(true))
            SynchronizeStatus();
      return(last_error);
   }
   else if (StringLen(StringTrim(Sequence.ID)) > 0) {
      return(last_error);                                            // Falscheingabe
   }


   // (2) keine Eingabe, eine der laufenden Sequenzen nach Bestätigung restaurieren
   int ids[], button;

   if (GetRunningSequences(ids)) {
      int sizeOfIds = ArraySize(ids);
      for (int i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Running sequence"+ ifString(sizeOfIds==1, " ", "s ") + JoinInts(ids, ", ") +" found.\n\nDo you want to load "+ ifString(sizeOfIds==1, "it", ids[i]) +"?", __NAME__, MB_ICONQUESTION|MB_YESNOCANCEL);
         if (button == IDYES) {
            test        = false; SS.Test();
            sequenceId  = ids[i];
            Sequence.ID = sequenceId; SS.SequenceId();
            status      = STATUS_WAITING;
            if (RestoreStatus())                                     // TODO: erkennen, ob einer der anderen Parameter von Hand geändert wurde und
               if (ValidateConfiguration(false))                     //       sofort nach neuer Sequenz mit Hinweis auf die laufenden fragen
                  SynchronizeStatus();
            return(last_error);
         }
         if (button == IDCANCEL) {
            __STATUS__CANCELLED = true;
            return(last_error);
         }
      }

      ForceSound("notify.wav");
      button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you want to start a new sequence?", __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
      if (button == IDCANCEL) {
         __STATUS__CANCELLED = true;
         return(last_error);
      }
      firstTickConfirmed = true;
   }


   // (3) zum Schluß neue Sequenz anlegen.
   if (ValidateConfiguration(true)) {
      instanceStartTime   = TimeCurrent();
      instanceStartPrice  = NormalizeDouble((Bid + Ask)/2, Digits);
      instanceStartEquity = AccountEquity()-AccountCredit();
      test                = IsTesting(); SS.Test();
      sequenceId          = CreateSequenceId();
      Sequence.ID         = ifString(IsTest(), "T", "") + sequenceId; SS.SequenceId();
      status              = STATUS_WAITING;

      if (start.conditions)                                          // Ohne StartConditions erfolgt sofortiger Sequenzstart, der Status automatisch speichert.
         SaveStatus();
      RedrawStartStop();
   }
   return(last_error);
}


/**
 * altes Chartfenster, neuer EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitRemove() {
   return(onInitChartClose());                                       // Funktionalität entspricht onInitChartClose()
}


/**
 * altes Chartfenster, alter EA, kein Input-Dialog, Statusdaten im Chart
 *
 * @return int - Fehlerstatus
 */
int onInitRecompile() {
   // im Chart gespeicherte Sequenz restaurieren
   if (RestoreTransientStatus()) {
      if (RestoreStatus())
         if (ValidateConfiguration(false))
            SynchronizeStatus();
   }
   ClearTransientStatus();
   return(last_error);
}


/**
 * altes Chartfenster, alter EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitParameterChange() {
   SaveConfiguration();

   if (!ValidateConfiguration(true)) {
      RestoreConfiguration();
      return(last_error);
   }

   if (status == STATUS_UNINITIALIZED) {
      // neue Sequenz anlegen
      instanceStartTime   = TimeCurrent();
      instanceStartPrice  = NormalizeDouble((Bid + Ask)/2, Digits);
      instanceStartEquity = AccountEquity()-AccountCredit();
      test                = IsTesting(); SS.Test();
      sequenceId          = CreateSequenceId();
      Sequence.ID         = ifString(IsTest(), "T", "") + sequenceId; SS.SequenceId();
      status              = STATUS_WAITING;

      if (start.conditions)                                          // Ohne StartConditions erfolgt sofortiger Sequenzstart, der Status automatisch speichert.
         SaveStatus();
      RedrawStartStop();
   }
   else {
      // Parameteränderung einer laufenden Sequenz
      if (SaveStatus()) {
         if      (OrderDisplayMode != last.OrderDisplayMode) { RedrawOrders();                                        }
         if      ( Breakeven.Color != last.Breakeven.Color ) {                 RedrawStartStop(); RecolorBreakeven(); }
         else if ( Breakeven.Width != last.Breakeven.Width ) {                                    RecolorBreakeven(); }
      }
   }
   return(last_error);
}


/**
 * altes Chartfenster, alter EA, kein Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitChartChange() {
   // nur die nicht-statischen Input-Parameter restaurieren
   Sequence.ID      = last.Sequence.ID;
   GridDirection    = last.GridDirection;
   GridSize         = last.GridSize;
   LotSize          = last.LotSize;
   StartConditions  = last.StartConditions;
   StopConditions   = last.StopConditions;
   OrderDisplayMode = last.OrderDisplayMode;
   Breakeven.Color  = last.Breakeven.Color;
   Breakeven.Width  = last.Breakeven.Width;
   return(NO_ERROR);
}


/**
 * Initialisierung
 *
 * @param  bool userCall - ob der Aufruf der zugrunde liegenden init()-Funktion durch das Terminal oder durch User-Code erfolgte
 *
 * @return int - Fehlerstatus
 */
int afterInit(bool userCall) {
   CreateStatusBox();
   SS.All();
   ShowStatus(!userCall);

   if (IsLastError())
      status = STATUS_DISABLED;
   return(last_error);
}


/**
 * @return int - Fehlerstatus
 */
int CreateStatusBox() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);
                                                                     // Chart-Background: C'248,248,248'
   color color.Background = C'248,248,248';                          // hellblau:         C'136,225,223'
                                                                     // Standard-Dialog:  C'212,208,200'
   // (1)
   string label = StringConcatenate(__NAME__, ".statusbox.1");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(1)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE,  0);
   ObjectSet(label, OBJPROP_YDISTANCE, 23);
   ObjectSetText(label, "g", 73, "Webdings", color.Background);


   // (2)
   label = StringConcatenate(__NAME__, ".statusbox.2");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(2)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, 97);
   ObjectSet(label, OBJPROP_YDISTANCE, 23);
   ObjectSetText(label, "g", 73, "Webdings", color.Background);


   // (3)
   label = StringConcatenate(__NAME__, ".statusbox.3");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(3)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, 152);
   ObjectSet(label, OBJPROP_YDISTANCE,  23);
   ObjectSetText(label, "g", 73, "Webdings", color.Background);

   return(catch("CreateStatusBox(4)"));
}
