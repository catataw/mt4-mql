
/**
 * Nach Parameteränderung
 *
 *  - altes Chartfenster, alter EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitParameterChange() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);

   StoreConfiguration();

   if (!ValidateConfiguration(true)) {
      RestoreConfiguration();
      return(last_error);
   }

   if (status == STATUS_UNINITIALIZED) {
      // neue Sequenz anlegen
      instanceStartTime  = TimeCurrent();
      instanceStartPrice = NormalizeDouble((Bid + Ask)/2, Digits);
      isTest             = IsTesting();
      sequenceId         = InstanceId(CreateSequenceId());
      Sequence.ID        = ifString(IsTest(), "T", "") + sequenceId; SS.SequenceId();
      status             = STATUS_WAITING;
      InitStatusLocation();

      if (start.conditions)                                          // Ohne aktivierte StartConditions erfolgt sofortiger Sequenzstart, der Status wird dabei
         SaveStatus();                                               // automatisch gespeichert.
      RedrawStartStop();
   }
   else {
      // Parameteränderung einer existierenden Sequenz
      if (SaveStatus()) {
         if (Breakeven.Color != last.Breakeven.Color) {
            RedrawStartStop();
            RecolorBreakeven();
         }
      }
   }
   return(last_error);
}


/**
 * Vorheriger EA von Hand entfernt (Chart->Expert->Remove) oder neuer EA drübergeladen
 *
 * - altes Chartfenster, neuer EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitRemove() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);
   return(onInitChartClose());                                       // Funktionalität entspricht onInitChartClose()
}


/**
 * Nach Symbol- oder Timeframe-Wechsel
 *
 * - altes Chartfenster, alter EA, kein Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitChartChange() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);

   // nur die nicht-statischen Input-Parameter restaurieren
   Sequence.ID             = last.Sequence.ID;
   Sequence.StatusLocation = last.Sequence.StatusLocation;
   GridDirection           = last.GridDirection;
   GridSize                = last.GridSize;
   LotSize                 = last.LotSize;
   StartConditions         = last.StartConditions;
   StopConditions          = last.StopConditions;
   Breakeven.Color         = last.Breakeven.Color;

   // TODO: Symbolwechsel behandeln
   return(NO_ERROR);
}


/**
 * Altes Chartfenster mit neu geladenem Template
 *
 * - neuer EA, Input-Dialog, keine Statusdaten im Chart
 *
 * @return int - Fehlerstatus
 */
int onInitChartClose() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);

   // (1) Zuerst eine angegebene Sequenz restaurieren...
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


   // (2) ...dann laufende Sequenzen suchen und ggf. eine davon restaurieren...
   int ids[], button;

   if (GetRunningSequences(ids)) {
      int sizeOfIds = ArraySize(ids);
      for (int i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         button = ForceMessageBox(__NAME__, ifString(!IsDemo(), "- Live Account -\n\n", "") +"Running sequence"+ ifString(sizeOfIds==1, " ", "s ") + JoinInts(ids, ", ") +" found.\n\nDo you want to load "+ ifString(sizeOfIds==1, "it", ids[i]) +"?", MB_ICONQUESTION|MB_YESNOCANCEL);
         if (button == IDYES) {
            isTest      = false;
            sequenceId  = InstanceId(ids[i]);
            Sequence.ID = sequenceId; SS.SequenceId();
            status      = STATUS_WAITING;
            if (RestoreStatus())                                     // TODO: Erkennen, ob einer der anderen Parameter von Hand geändert wurde und
               if (ValidateConfiguration(false))                     //       sofort nach neuer Sequenz fragen.
                  SynchronizeStatus();
            return(last_error);
         }
         if (button == IDCANCEL) {
            __STATUS__CANCELLED = true;
            return(last_error);
         }
      }

      if (!ConfirmTradeOnTick1("", "Do you want to start a new sequence?")) {
         __STATUS__CANCELLED = true;
         return(last_error);
      }
   }


   // (3) ...zum Schluß neue Sequenz anlegen.
   if (ValidateConfiguration(true)) {
      instanceStartTime  = TimeCurrent();
      instanceStartPrice = NormalizeDouble((Bid + Ask)/2, Digits);
      isTest             = IsTesting();
      sequenceId         = InstanceId(CreateSequenceId());
      Sequence.ID        = ifString(IsTest(), "T", "") + sequenceId; SS.SequenceId();
      status             = STATUS_WAITING;
      InitStatusLocation();

      if (start.conditions)                                          // Ohne aktive StartConditions kann vorm Sequenzstart abgebrochen werden, der Status
         SaveStatus();                                               // wird erst danach gespeichert.
      RedrawStartStop();
   }
   return(last_error);
}


/**
 * Kein UninitializeReason gesetzt
 *
 * - nach Terminal-Neustart:    neues Chartfenster, vorheriger EA, kein Input-Dialog
 * - nach File -> New -> Chart: neues Chartfenster, neuer EA, Input-Dialog
 *
 * @return int - Fehlerstatus
 */
int onInitUndefined() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);
   last_error = NO_ERROR;

   // Prüfen, ob im Chart Statusdaten existieren (einziger Unterschied zwischen vorherigem/neuem EA)
   if (!RestoreStickyStatus())
      if (IsLastError())
         return(last_error);

   bool idFound = ObjectFind(StringConcatenate(__NAME__, ".sticky.Sequence.ID")) == 0;

   if (idFound) return(onInitRecompile());      // ja:   vorheriger EA -> kein Input-Dialog: Funktionalität entspricht onInitRecompile()
   else         return(onInitChartClose());     // nein: neuer      EA -> Input-Dialog:      Funktionalität entspricht onInitChartClose()
}


/**
 * Nach Recompilation
 *
 * - altes Chartfenster, vorheriger EA, kein Input-Dialog, Statusdaten im Chart
 *
 * @return int - Fehlerstatus
 */
int onInitRecompile() {
   if (__STATUS__CANCELLED)
      return(NO_ERROR);

   // im Chart gespeicherte Sequenz restaurieren
   if (RestoreStickyStatus()) {
      if (RestoreStatus())
         if (ValidateConfiguration(false))
            SynchronizeStatus();
   }
   ClearStickyStatus();
   return(last_error);
}


/**
 * Postprocessing-Hook nach Initialisierung
 *
 * @return int - Fehlerstatus
 */
int afterInit() {
   CreateStatusBox();
   SS.All();
   ShowStatus();
   return(last_error);
}


/**
 * Die Statusbox besteht aus 3 nebeneinander angeordneten "Quadraten" (Font "Webdings", Zeichen 'g').
 *
 * @return int - Fehlerstatus
 */
int CreateStatusBox() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

 //int x[]={0,  89, 145}, y=22, fontSize=67;                         // eine Zeile für Start/StopCondition
   int x[]={0, 101, 133}, y=22, fontSize=76;                         // zwei Zeilen für Start/StopCondition
   color color.Background = C'248,248,248';                          // entspricht Chart-Background


   // 1. Quadrat
   string label = StringConcatenate(__NAME__, ".statusbox.1");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(1)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x[0]);
   ObjectSet(label, OBJPROP_YDISTANCE, y   );
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);


   // 2. Quadrat
   label = StringConcatenate(__NAME__, ".statusbox.2");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(2)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x[1]);
   ObjectSet(label, OBJPROP_YDISTANCE, y   );
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);


   // 3. Quadrat (überlappt 2.)
   label = StringConcatenate(__NAME__, ".statusbox.3");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(3)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x[2]);
   ObjectSet(label, OBJPROP_YDISTANCE, y   );
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);

   return(catch("CreateStatusBox(4)"));
}
