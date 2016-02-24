
#define __TYPE__ MT_INDICATOR

extern string ___________________________;
extern int    __lpSuperContext;
extern string LogLevel = "inherit";


/**
 * Globale init()-Funktion f�r Indikatoren.
 *
 * Bei Aufruf durch das Terminal wird der letzte Errorcode 'last_error' in 'prev_error' gespeichert und vor Abarbeitung
 * zur�ckgesetzt.
 *
 * @return int - Fehlerstatus
 *
 * @throws ERS_TERMINAL_NOT_YET_READY
 */
int init() {
   if (__STATUS_OFF)
      return(last_error);

   if (__WHEREAMI__ == NULL) {                                                            // Aufruf durch Terminal, alle Variablen sind zur�ckgesetzt
      __WHEREAMI__ = RF_INIT;
      prev_error   = NO_ERROR;
      last_error   = NO_ERROR;
   }                                                                                      // noch vor Laden der ersten Library; der resultierende Kontext kann unvollst�ndig sein
   SyncMainExecutionContext(__ExecutionContext, __TYPE__, WindowExpertName(), __WHEREAMI__, UninitializeReason(), Symbol(), Period());


   // (1) Initialisierung abschlie�en
   if (!InitExecContext.Finalize()) {
      UpdateProgramStatus(); if (__STATUS_OFF) return(last_error);
   }                                                                                      // wiederholter Aufruf, um eine existierende Kontext-Chain zu aktualisieren
   SyncMainExecutionContext(__ExecutionContext, __TYPE__, WindowExpertName(), __WHEREAMI__, UninitializeReason(), Symbol(), Period());


   // (2) stdlib initialisieren
   int tickData[3];
   int error = stdlib.init(__ExecutionContext, tickData);
   if (IsError(error)) {
      UpdateProgramStatus(SetLastError(error));
      if (__STATUS_OFF) return(last_error);
   }


   Tick          = tickData[0];
   Tick.Time     = tickData[1];
   Tick.prevTime = tickData[2];


   // (3) bei Aufruf durch iCustom() Indikatorkonfiguration loggen
   if (__LOG) /*&&*/ if (IsSuperContext())
      log(InputsToStr());


   // (4) user-spezifische Init-Tasks ausf�hren
   int initFlags = ec_InitFlags(__ExecutionContext);

   if (initFlags & INIT_PIPVALUE && 1) {
      TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);                      // schl�gt fehl, wenn kein Tick vorhanden ist
      error = GetLastError();
      if (IsError(error)) {                                                // - Symbol nicht subscribed (Start, Account-/Templatewechsel), Symbol kann noch "auftauchen"
         if (error == ERR_SYMBOL_NOT_AVAILABLE)                            // - synthetisches Symbol im Offline-Chart
                           return(UpdateProgramStatus(debug("init(1)  MarketInfo() => ERR_SYMBOL_NOT_AVAILABLE", SetLastError(ERS_TERMINAL_NOT_YET_READY))));
         UpdateProgramStatus(catch("init(2)", error));
         if (__STATUS_OFF) return(last_error);
      }
      if (!TickSize)       return(UpdateProgramStatus(debug("init(3)  MarketInfo(MODE_TICKSIZE) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY))));

      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      error = GetLastError();
      if (IsError(error)) {
         UpdateProgramStatus(catch("init(5)", error));
         if (__STATUS_OFF) return(last_error);
      }
      if (!tickValue)      return(UpdateProgramStatus(debug("init(6)  MarketInfo(MODE_TICKVALUE) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY))));
   }
   if (initFlags & INIT_BARS_ON_HIST_UPDATE && 1) {}                       // noch nicht implementiert


   /*
   (5) User-spezifische init()-Routinen aufrufen. Diese *k�nnen*, m�ssen aber nicht implementiert sein.

   Die vom Terminal bereitgestellten UninitializeReasons und ihre Bedeutung �ndern sich in den einzelnen Terminalversionen
   und k�nnen nicht zur eindeutigen Unterscheidung der verschiedenen Init-Szenarien verwendet werden.
   Abhilfe: Expander-Funktion InitReason() und die neueingef�hrten Variablen INIT_REASON_*.

   Init-Szenario                   User-Routine                Beschreibung
   -------------                   ------------                ------------
   INIT_REASON_USER              - onInit_User()             - bei Laden durch den User                               -      Input-Dialog
   INIT_REASON_TEMPLATE          - onInit_Template()         - bei Laden durch ein Template (auch bei Terminal-Start) - kein Input-Dialog
   INIT_REASON_PROGRAM           - onInit_Program()          - bei Laden durch iCustom()                              - kein Input-Dialog
   INIT_REASON_PROGRAM_CLEARTEST - onInit_ProgramClearTest() - bei Laden durch iCustom() nach Testende                - kein Input-Dialog
   INIT_REASON_PARAMETERS        - onInit_Parameters()       - nach �nderung der Indikatorparameter                   -      Input-Dialog
   INIT_REASON_TIMEFRAMECHANGE   - onInit_TimeframeChange()  - nach Timeframewechsel des Charts                       - kein Input-Dialog
   INIT_REASON_SYMBOLCHANGE      - onInit_SymbolChange()     - nach Symbolwechsel des Charts                          - kein Input-Dialog
   INIT_REASON_RECOMPILE         - onInit_Recompile()        - bei Reload nach Recompilation                          - kein Input-Dialog

   Die User-Routinen werden ausgef�hrt, wenn der Preprocessing-Hook (falls implementiert) ohne Fehler zur�ckkehrt.
   Der Postprocessing-Hook wird ausgef�hrt, wenn weder der Preprocessing-Hook (falls implementiert) noch die User-Routinen
   (falls implementiert) -1 zur�ckgeben.
   */
   error = onInit();                                                                                              // Preprocessing-Hook
                                                                                                                  //
   if (!error) {                                                                                                  //
      int initReason = InitReason();                                                                              //
      if (!initReason) { UpdateProgramStatus(); if (__STATUS_OFF) return(last_error); }                           //
                                                                                                                  //
      switch (initReason) {                                                                                       //
         case INIT_REASON_USER             : error = onInit_User();             break;                            //
         case INIT_REASON_TEMPLATE         : error = onInit_Template();         break;                            // TODO: in neuem Chartfenster falsche Werte f�r Point und Digits
         case INIT_REASON_PROGRAM          : error = onInit_Program();          break;                            //
         case INIT_REASON_PROGRAM_CLEARTEST: error = onInit_ProgramClearTest(); break;                            //
         case INIT_REASON_PARAMETERS       : error = onInit_Parameters();       break;                            //
         case INIT_REASON_TIMEFRAMECHANGE  : error = onInit_TimeframeChange();  break;                            //
         case INIT_REASON_SYMBOLCHANGE     : error = onInit_SymbolChange();     break;                            //
         case INIT_REASON_RECOMPILE        : error = onInit_Recompile();        break;                            //
         default:                                                                                                 //
            return(UpdateProgramStatus(catch("init(7)  unknown initReason = "+ initReason, ERR_RUNTIME_ERROR)));  //
      }                                                                                                           //
   }                                                                                                              //
   if (error == ERS_TERMINAL_NOT_YET_READY) return(error);                                                        //
   UpdateProgramStatus();                                                                                         //
                                                                                                                  //
   if (error != -1) {                                                                                             //
      afterInit();                                                                                                // Postprocessing-Hook
      UpdateProgramStatus();                                                                                      //
   }                                                                                                              //
   if (__STATUS_OFF) return(last_error);                                                                          //


   // (6) nach Parameter�nderung im "Indicators List"-Window nicht auf den n�chsten Tick warten
   if (initReason == INIT_REASON_PARAMETERS) {
      error = Chart.SendTick();                                      // TODO: !!! Nur bei Existenz des "Indicators List"-Windows (nicht bei einzelnem Indikator)
      if (IsError(error)) {
         UpdateProgramStatus(SetLastError(error));
         if (__STATUS_OFF) return(last_error);
      }
   }
   UpdateProgramStatus(catch("init(8)"));
   return(last_error);
}


/**
 * Globale start()-Funktion f�r Indikatoren.
 *
 * - Erfolgt der Aufruf nach einem vorherigem init()-Aufruf und init() kehrte mit ERS_TERMINAL_NOT_YET_READY zur�ck,
 *   wird versucht, init() erneut auszuf�hren. Bei erneutem init()-Fehler bricht start() ab.
 *   Wurde init() fehlerfrei ausgef�hrt, wird der letzte Errorcode 'last_error' vor Abarbeitung zur�ckgesetzt.
 *
 * - Der letzte Errorcode 'last_error' wird in 'prev_error' gespeichert und vor Abarbeitung zur�ckgesetzt.
 *
 * @return int - Fehlerstatus
 *
 * @throws ERS_TERMINAL_NOT_YET_READY
 */
int start() {
   if (__STATUS_OFF) {
      string msg = WindowExpertName() +": switched off ("+ ifString(!__STATUS_OFF.reason, "unknown reason", ErrorToStr(__STATUS_OFF.reason)) +")";
      Comment(NL + NL + NL + msg);                                                  // 3 Zeilen Abstand f�r Instrumentanzeige und ggf. vorhandene Legende
      return(last_error);
   }

   Tick++; zTick++;                                                                 // einfache Z�hler, die konkreten Werte haben keine Bedeutung
   Tick.prevTime = Tick.Time;
   Tick.Time     = MarketInfo(Symbol(), MODE_TIME);                                 // TODO: !!! MODE_TIME ist im synthetischen Chart NULL               !!!
                                                                                    // TODO: !!! MODE_TIME und TimeCurrent() sind im Tester-Chart falsch !!!
   if (!Tick.Time) {
      int error = GetLastError();
      if (error!=NO_ERROR) /*&&*/ if (error!=ERR_SYMBOL_NOT_AVAILABLE) {            // ERR_SYMBOL_NOT_AVAILABLE vorerst ignorieren, da ein Offline-Chart beim ersten Tick
         UpdateProgramStatus(catch("start(1)", error));                             // nicht sicher detektiert werden kann
         if (__STATUS_OFF) return(last_error);
      }
   }


   // (1) Valid- und ChangedBars berechnen (diese Originalwerte werden sp�ter bei Bedarf �berschrieben)
   ValidBars   = IndicatorCounted();
   ChangedBars = Bars - ValidBars;


   // (2) Abschlu� der Chart-Initialisierung �berpr�fen (!Bars kann bei Terminal-Start auftreten)
   if (!Bars) return(UpdateProgramStatus(SetLastError(debug("start(2)  Bars = 0", ERS_TERMINAL_NOT_YET_READY))));


   // (3) Tickstatus bestimmen
   int vol = Volume[0];
   static int last.vol;
   if      (!vol || !last.vol) Tick.isVirtual = true;
   else if ( vol ==  last.vol) Tick.isVirtual = true;
   else                        Tick.isVirtual = (ChangedBars > 2);
   last.vol = vol;


   // (4) ValidBars und ChangedBars in synthetischen Charts anhand der Zeitreihe selbst bestimmen. IndicatorCounted() signalisiert dort immer alle Bars als modifiziert.
   //     Die Logik des folgenden Abschnitts entspricht der Logik der Funktion iChangedBars(), ist jedoch laufzeitoptimiert.
   static int      last.bars = -1;
   static datetime last.oldestBarTime, last.newestBarTime;
   if (!ValidBars) /*&&*/ if (!IsConnected()) {
      if      (last.bars==-1)                                       ChangedBars = Bars;                  // erster Zugriff auf die Zeitreihe
      else if (Bars==last.bars && Time[Bars-1]==last.oldestBarTime) ChangedBars = 1;                     // Baranzahl gleich und �lteste Bar noch dieselbe
      else {                                                                                             // normaler Tick (mit/ohne L�cke) oder synthetischer/sonstiger Tick
       //if (Bars == last.bars)
       //   debug("start(3)  Bars==last.bars: "+ Bars +" (we hit MAX_CHART_BARS)");                      // (*) Hat sich die letzte Bar ge�ndert, wurden Bars hinten "hinausgeschoben".
         if (Time[0] != last.newestBarTime)                         ChangedBars = Bars - last.bars + 1;  // neue Bars zu Beginn hinzugekommen
         else                                                       ChangedBars = Bars;                  // neue Bars in L�cke eingef�gt: uneindeutig => alle als modifiziert melden

         if (Bars == last.bars) ChangedBars = Bars;   // solange die Suche in (*) noch nicht implementiert ist
      }
   }
   last.bars          = Bars;                                                                            // (*) TODO: In diesem Fall mu� die Bar mit last.newestBarTime gesucht und
   last.oldestBarTime = Time[Bars-1];                                                                    //           der Wert von ChangedBars daraus abgeleitet werden.
   last.newestBarTime = Time[0];
   ValidBars          = Bars - ChangedBars;                                                              // ValidBars aus ChangedBars ableiten


   // (5) Falls wir aus init() kommen, dessen Ergebnis pr�fen
   if (__WHEREAMI__ == RF_INIT) {
      __WHEREAMI__ = ec_setRootFunction(__ExecutionContext, RF_START);              // __STATUS_OFF ist false: evt. ist jedoch ein Status gesetzt, siehe UpdateProgramStatus()

      if (last_error == ERS_TERMINAL_NOT_YET_READY) {                               // alle anderen Stati brauchen zur Zeit keine eigene Behandlung
         debug("start(4)  init() returned ERS_TERMINAL_NOT_YET_READY, retrying...");
         last_error = NO_ERROR;

         error = init();                                                            // init() erneut aufrufen
         if (__STATUS_OFF) return(last_error);

         if (error == ERS_TERMINAL_NOT_YET_READY) {                                 // wenn �berhaupt, kann wieder nur ein Status gesetzt sein
            __WHEREAMI__ = ec_setRootFunction(__ExecutionContext, RF_INIT);         // __WHEREAMI__ zur�cksetzen und auf den n�chsten Tick warten
            return(error);
         }
      }
      last_error = NO_ERROR;                                                        // init() war erfolgreich
      ValidBars  = 0;
   }
   else {
      // normaler Tick
      prev_error = last_error;
      SetLastError(NO_ERROR);

      if      (prev_error == ERS_TERMINAL_NOT_YET_READY) ValidBars = 0;
      else if (prev_error == ERS_HISTORY_UPDATE        ) ValidBars = 0;
      else if (prev_error == ERR_HISTORY_INSUFFICIENT  ) ValidBars = 0;
      if      (__STATUS_HISTORY_UPDATE                 ) ValidBars = 0;             // *_HISTORY_UPDATE und *_HISTORY_INSUFFICIENT k�nnen je nach Kontext Fehler und/oder Status sein.
      if      (__STATUS_HISTORY_INSUFFICIENT           ) ValidBars = 0;
   }
   ChangedBars = Bars - ValidBars;                                                  // ChangedBars aktualisieren (ValidBars wurde evt. neu gesetzt)


   /*
   // (6) Werden Zeichenpuffer verwendet, mu� in onTick() deren Initialisierung �berpr�ft werden.
   if (ArraySize(buffer) == 0)
      return(SetLastError(ERS_TERMINAL_NOT_YET_READY));                             // kann bei Terminal-Start auftreten
   */

   __STATUS_HISTORY_UPDATE       = false;
   __STATUS_HISTORY_INSUFFICIENT = false;


   SyncMainExecutionContext(__ExecutionContext, __TYPE__, WindowExpertName(), __WHEREAMI__, UninitializeReason(), Symbol(), Period());


   // (7) stdLib benachrichtigen
   if (stdlib.start(__ExecutionContext, Tick, Tick.Time, ValidBars, ChangedBars) != NO_ERROR) {
      UpdateProgramStatus(SetLastError(stdlib.GetLastError()));
      if (__STATUS_OFF) return(last_error);
   }


   // (8) bei Bedarf Input-Dialog aufrufen
   if (__STATUS_RELAUNCH_INPUT) {
      __STATUS_RELAUNCH_INPUT = false;
      return(UpdateProgramStatus(start.RelaunchInputDialog()));
   }


   // (9) Main-Funktion aufrufen und auswerten
   onTick();

   error = GetLastError();
   if (error != NO_ERROR)
      catch("start(5)", error);

   if      (last_error == ERS_HISTORY_UPDATE      ) __STATUS_HISTORY_UPDATE       = true;
   else if (last_error == ERR_HISTORY_INSUFFICIENT) __STATUS_HISTORY_INSUFFICIENT = true;

   return(UpdateProgramStatus(last_error));
}


/**
 * Globale deinit()-Funktion f�r Indikatoren.
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   __WHEREAMI__ = RF_DEINIT;
   SyncMainExecutionContext (__ExecutionContext, __TYPE__, WindowExpertName(), __WHEREAMI__, UninitializeReason(), Symbol(), Period());
   Init.StoreSymbol(Symbol());                                                   // TODO: aktuelles Symbol im ExecutionContext speichern


   // User-Routinen *k�nnen*, m�ssen aber nicht implementiert werden.
   //
   // Die User-Routinen werden ausgef�hrt, wenn der Preprocessing-Hook (falls implementiert) ohne Fehler zur�ckkehrt.
   // Der Postprocessing-Hook wird ausgef�hrt, wenn weder der Preprocessing-Hook (falls implementiert) noch die User-Routinen
   // (falls implementiert) -1 zur�ckgeben.


   // (1) User-spezifische deinit()-Routinen aufrufen                            //
   int error = onDeinit();                                                       // Preprocessing-Hook
                                                                                 //
   if (!error) {                                                                 //
      switch (UninitializeReason()) {                                            //
         case REASON_PARAMETERS : error = onDeinitParameterChange(); break;      //
         case REASON_CHARTCHANGE: error = onDeinitChartChange();     break;      //
         case REASON_ACCOUNT    : error = onDeinitAccountChange();   break;      //
         case REASON_CHARTCLOSE : error = onDeinitChartClose();      break;      //
         case REASON_UNDEFINED  : error = onDeinitUndefined();       break;      //
         case REASON_REMOVE     : error = onDeinitRemove();          break;      //
         case REASON_RECOMPILE  : error = onDeinitRecompile();       break;      //
         // build > 509                                                          //
         case REASON_TEMPLATE   : error = onDeinitTemplate();        break;      //
         case REASON_INITFAILED : error = onDeinitFailed();          break;      //
         case REASON_CLOSE      : error = onDeinitClose();           break;      //
                                                                                 //
         default: return(UpdateProgramStatus(catch("deinit(1)  unknown UninitializeReason = "+ UninitializeReason(), ERR_RUNTIME_ERROR)));
      }                                                                          //
   }                                                                             //
   UpdateProgramStatus();                                                        //
                                                                                 //
   if (error != -1) {                                                            //
      error = afterDeinit();                                                     // Postprocessing-Hook
      UpdateProgramStatus();
   }


   // (2) User-spezifische Deinit-Tasks ausf�hren
   if (!error) {
      // ...
   }


   // (3) stdlib deinitialisieren und Context speichern
   error = stdlib.deinit(__ExecutionContext);
   if (IsError(error))
      SetLastError(error);

   UpdateProgramStatus(catch("deinit(2)"));
   return(last_error); __DummyCalls();
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Expert Adviser ist.
 *
 * @return bool
 */
bool IsExpert() {
   return(false);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Script ist.
 *
 * @return bool
 */
bool IsScript() {
   return(false);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Indikator ist.
 *
 * @return bool
 */
bool IsIndicator() {
   return(true);
}


/**
 * Ob das aktuell ausgef�hrte Modul eine Library ist.
 *
 * @return bool
 */
bool IsLibrary() {
   return(false);
}


/**
 * Gibt die ID des aktuellen oder letzten Init()-Szenarios zur�ck. Kann nicht in deinit() aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int InitReason() {
   /*
   Init-Szenarien:
   ---------------
   - onInit_User()             - bei Laden durch den User                               -      Input-Dialog
   - onInit_Template()         - bei Laden durch ein Template (auch bei Terminal-Start) - kein Input-Dialog
   - onInit_Program()          - bei Laden durch iCustom()                              - kein Input-Dialog
   - onInit_ProgramClearTest() - bei Laden durch iCustom() nach Testende                - kein Input-Dialog
   - onInit_Parameters()       - nach �nderung der Indikatorparameter                   -      Input-Dialog
   - onInit_TimeframeChange()  - nach Timeframewechsel des Charts                       - kein Input-Dialog
   - onInit_SymbolChange()     - nach Symbolwechsel des Charts                          - kein Input-Dialog
   - onInit_Recompile()        - bei Reload nach Recompilation                          - kein Input-Dialog

   History:
   --------------------------------------------------------------------------------------------------------------------------------------------------
   - Build 547-551: onInit_User()             - Broken: Wird zwei mal aufgerufen, beim zweiten mal ist der EXECUTION_CONTEXT ung�ltig.
   - Build  >= 654: onInit_User()             - UninitializeReason() ist REASON_UNDEFINED.
   --------------------------------------------------------------------------------------------------------------------------------------------------
   - Build 577-583: onInit_Template()         - Broken: Kein Aufruf bei Terminal-Start, der Indikator wird aber geladen.
   --------------------------------------------------------------------------------------------------------------------------------------------------
   - Build 556-569: onInit_Program()          - Broken: Wird in- und au�erhalb des Testers bei jedem Tick aufgerufen.
   --------------------------------------------------------------------------------------------------------------------------------------------------
   - Build  <= 229: onInit_ProgramClearTest() - UninitializeReason() ist REASON_UNDEFINED.
   - Build     387: onInit_ProgramClearTest() - Broken: Wird nie aufgerufen.
   - Build 388-628: onInit_ProgramClearTest() - UninitializeReason() ist REASON_REMOVE.
   - Build  <= 577: onInit_ProgramClearTest() - Wird nur nach einem automatisiertem Test aufgerufen (VisualMode=Off), der Aufruf erfolgt vorm Start
                                                des n�chsten Tests.
   - Build  >= 578: onInit_ProgramClearTest() - Wird auch nach einem manuellen Test aufgerufen (VisualMode=On), nur in diesem Fall erfolgt der Aufruf
                                                sofort nach Testende.
   - Build  >= 633: onInit_ProgramClearTest() - UninitializeReason() ist REASON_CHARTCLOSE.
   --------------------------------------------------------------------------------------------------------------------------------------------------
   - Build 577:     onInit_TimeframeChange()  - Broken: Bricht mit der Logmessage "WARN: expert stopped" ab.
   --------------------------------------------------------------------------------------------------------------------------------------------------
   */

   int  uninitializeReason = UninitializeReason();
   int  build              = GetTerminalBuild(); if (!build) return(_NULL(SetLastError(stdlib.GetLastError())));
   bool isUIThread         = IsUIThread();


   // (1) REASON_PARAMETERS
   if (uninitializeReason == REASON_PARAMETERS) {
      // innerhalb iCustom(): nie
      if (IsSuperContext())            return(!catch("InitReason(1)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      // au�erhalb iCustom(): erste Parameter-Eingabe bei neuem Indikator oder Parameter-Wechsel bei vorhandenem Indikator (auch im Tester bei VisualMode=On), Input-Dialog
      if (Init.IsNoTick())             return(INIT_REASON_USER      );     // erste Parameter-Eingabe eines manuell zum Chart hinzugef�gten Indikators
      else                             return(INIT_REASON_PARAMETERS);     // Parameter-Wechsel eines vorhandenen Indikators
   }


   // (2) REASON_CHARTCHANGE
   if (uninitializeReason == REASON_CHARTCHANGE) {
      // innerhalb iCustom(): nie
      if (IsSuperContext())            return(!catch("InitReason(2)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      // au�erhalb iCustom(): nach Symbol- oder Timeframe-Wechsel bei vorhandenem Indikator, kein Input-Dialog
      if (Init.IsNewSymbol(Symbol()))  return(INIT_REASON_SYMBOLCHANGE   );
      else                             return(INIT_REASON_TIMEFRAMECHANGE);
   }


   // (3) REASON_UNDEFINED
   if (uninitializeReason == REASON_UNDEFINED) {
      // au�erhalb iCustom(): je nach Umgebung
      if (!IsSuperContext()) {
         if (build < 654)              return(INIT_REASON_TEMPLATE);       // wenn Template mit Indikator geladen wird (auch bei Start und im Tester bei VisualMode=On|Off), kein Input-Dialog
         if (WindowOnDropped() >= 0)   return(INIT_REASON_TEMPLATE);
         else                          return(INIT_REASON_USER    );       // erste Parameter-Eingabe eines manuell zum Chart hinzugef�gten Indikators, Input-Dialog
      }
      // innerhalb iCustom(): je nach Umgebung, kein Input-Dialog
      if (IsTesting() && !IsVisualModeFix() && isUIThread) {               // versionsunabh�ngig
         if (build <= 229)             return(INIT_REASON_PROGRAM_CLEARTEST);
                                       return(!catch("InitReason(3)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      }
      return(INIT_REASON_PROGRAM);
   }


   // (4) REASON_REMOVE
   if (uninitializeReason == REASON_REMOVE) {
      // au�erhalb iCustom(): nie
      if (!IsSuperContext())                                  return(!catch("InitReason(4)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      // innerhalb iCustom(): je nach Umgebung, kein Input-Dialog
      if (!IsTesting() || !isUIThread)                        return(!catch("InitReason(5)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      if (!IsVisualModeFix()) { if (388<=build && build<=628) return(INIT_REASON_PROGRAM_CLEARTEST); }
      else                    { if (578<=build && build<=628) return(INIT_REASON_PROGRAM_CLEARTEST); }
      return(!catch("InitReason(6)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
   }


   // (5) REASON_RECOMPILE
   if (uninitializeReason == REASON_RECOMPILE) {
      // innerhalb iCustom(): nie
      if (IsSuperContext())            return(!catch("InitReason(7)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      // au�erhalb iCustom(): bei Reload nach Recompilation, vorhandener Indikator, kein Input-Dialog
      return(INIT_REASON_RECOMPILE);
   }


   // (6) REASON_CHARTCLOSE
   if (uninitializeReason == REASON_CHARTCLOSE) {
      // au�erhalb iCustom(): nie
      if (!IsSuperContext())           return(!catch("InitReason(8)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      // innerhalb iCustom(): je nach Umgebung, kein Input-Dialog
      if (!IsTesting() || !isUIThread) return(!catch("InitReason(9)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
      if (build >= 633)                return(INIT_REASON_PROGRAM_CLEARTEST);
      return(!catch("InitReason(10)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
   }


   switch (uninitializeReason) {
      case REASON_ACCOUNT:       // nie
      case REASON_TEMPLATE:      // build > 509
      case REASON_INITFAILED:    // ...
      case REASON_CLOSE:         // ...
         return(!catch("InitReason(11)  unexpected UninitializeReason = "+ UninitializeReasonToStr(uninitializeReason) +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
   }
   return(!catch("InitReason(12)  unknown UninitializeReason = "+ uninitializeReason +" (SuperContext="+ IsSuperContext() +", Testing="+ IsTesting() +", VisualMode="+ IsVisualModeFix() +", IsUiThread="+ isUIThread +", build="+ build +")", ERR_RUNTIME_ERROR));
}


/**
 * Gibt die ID des aktuellen Deinit()-Szenarios zur�ck. Kann nur in deinit() aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int DeinitReason() {
   return(NULL);
}


/**
 * Initialisiert den EXECUTION_CONTEXT des Indikators.
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: In Indikatoren wird der EXECUTION_CONTEXT des Hauptmoduls nach jedem init-Cycle an einer anderen Adresse liegen.
 */
bool InitExecContext.Finalize() {
   // (1) Context initialisieren, wenn er neu ist (also nicht aus dem letzten init-Cycle stammt)
   if (!ec_hChartWindow(__ExecutionContext)) {

      // (1.1) Variablen definieren (werden sp�ter ggf. mit Werten aus SuperContext �berschrieben)
      int hChart       = WindowHandleEx(NULL); if (!hChart) return(false);
      int hChartWindow = 0;
         if (hChart == -1) hChart       = 0;
         else              hChartWindow = GetParent(hChart);
      int testFlags;
         if (This.IsTesting()) {
            if (__CHART) testFlags = TF_VISUAL_TEST;
            else         testFlags = TF_TEST;
         }
      bool   isChart     = hChart && 1;
      bool   isLog       = true;
      bool   isCustomLog = false;                                    // Custom-Logging gibt es vorerst nur f�r Experts
      string logFile;

      // (1.2) Gibt es einen SuperContext, die in (2.1) definierten Variablen mit denen aus dem SuperContext �berschreiben
      if (__lpSuperContext != NULL) {
         if (__lpSuperContext > 0 && __lpSuperContext < MIN_VALID_POINTER) return(!catch("InitExecContext.Finalize(1)  invalid input parameter __lpSuperContext = 0x"+ IntToHexStr(__lpSuperContext) +" (not a valid pointer)", ERR_INVALID_POINTER));
         int sec.copy[EXECUTION_CONTEXT.intSize];
         CopyMemory(GetIntsAddress(sec.copy), __lpSuperContext, EXECUTION_CONTEXT.size);

         hChart       = ec_hChart      (sec.copy);
         hChartWindow = ec_hChartWindow(sec.copy);
         testFlags    = ec_TestFlags   (sec.copy);
         logFile      = ec_LogFile     (sec.copy);
         isChart      = hChart && 1;
         isLog        = ec_Logging     (sec.copy);
         isCustomLog  = isLog && StringLen(logFile);

         ArrayResize(sec.copy, 0);                                   // Speicher freigeben
      }

      // (1.3) Context aktualisieren
      ec_setLpSuperContext(__ExecutionContext, __lpSuperContext         );
      ec_setInitFlags     (__ExecutionContext, SumInts(__INIT_FLAGS__  ));
      ec_setDeinitFlags   (__ExecutionContext, SumInts(__DEINIT_FLAGS__));

      ec_setHChartWindow  (__ExecutionContext, hChartWindow             );
      ec_setHChart        (__ExecutionContext, hChart                   );
      ec_setTestFlags     (__ExecutionContext, testFlags                );

    //ec_setLastError     ...wird nicht �berschrieben
      ec_setLogging       (__ExecutionContext, isLog                    );
      ec_setLogFile       (__ExecutionContext, logFile                  );
   }


   // (2) Globale Variablen aktualisieren.
   __NAME__     = WindowExpertName();
   logFile      = ec_LogFile(__ExecutionContext);
   __CHART      = ec_hChart (__ExecutionContext) && 1;
   __LOG        = ec_Logging(__ExecutionContext);
   __LOG_CUSTOM = __LOG && StringLen(logFile);


   // (3) restliche globale Variablen initialisieren
   //
   // Bug 1: Die Variablen Digits und Point sind in init() beim �ffnen eines neuen Charts und beim Accountwechsel u.U. falsch gesetzt.
   //        Nur ein Reload des Templates korrigiert die falschen Werte.
   //
   // Bug 2: Die Variablen Digits und Point sind in Offline-Charts ab Terminalversion ??? permanent auf 5 und 0.00001 gesetzt.
   //
   // Bug 3: Die Variablen Digits und Point k�nnen vom Broker u.U. falsch gesetzt worden sein (z.B. S&P500 bei Forex Ltd).
   //
   PipDigits      = Digits & (~1);                                        SubPipDigits      = PipDigits+1;
   PipPoints      = MathRound(MathPow(10, Digits & 1));                   PipPoint          = PipPoints;
   Pip            = NormalizeDouble(1/MathPow(10, PipDigits), PipDigits); Pips              = Pip;
   PipPriceFormat = StringConcatenate(".", PipDigits);                    SubPipPriceFormat = StringConcatenate(PipPriceFormat, "'");
   PriceFormat    = ifString(Digits==PipDigits, PipPriceFormat, SubPipPriceFormat);

   N_INF = MathLog(0);
   P_INF = -N_INF;
   NaN   =  N_INF - N_INF;

   __account.companyId = AccountCompanyId(ShortAccountCompany());

   return(!catch("InitExecContext.Finalize(2)"));
}


/**
 * Ob das aktuelle Programm durch ein anderes Programm ausgef�hrt wird.
 *
 * @return bool
 */
bool IsSuperContext() {
   return(__lpSuperContext != 0);
}


/**
 * Setzt den internen Fehlercode des Indikators. Bei Indikatoraufruf aus iCustom() wird der Fehler zus�tzlich an den Aufrufer weitergereicht.
 *
 * @param  int error - Fehlercode
 *
 * @return int - derselbe Fehlercode (for chaining)
 *
 *
 * NOTE: Akzeptiert einen weiteren beliebigen Parameter, der bei der Verarbeitung jedoch ignoriert wird.
 */
int SetLastError(int error, int param=NULL) {
   last_error = ec_setLastError(__ExecutionContext, error);
   return(error);
}


/**
 * �berpr�ft und aktualisiert den aktuellen Programmstatus des Indikators. Setzt je nach Kontext das Flag __STATUS_OFF.
 *
 * @param  int value - der zur�ckzugebende Wert (default: NULL)
 *
 * @return int - der �bergebene Wert
 */
int UpdateProgramStatus(int value=NULL) {
   switch (last_error) {
      case NO_ERROR                  :
      case ERS_HISTORY_UPDATE        :
      case ERS_TERMINAL_NOT_YET_READY:
      case ERS_EXECUTION_STOPPING    : break;

      default:
         __STATUS_OFF        = true;
         __STATUS_OFF.reason = last_error;
   }
   return(value);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein ChartCommand f�r diesen Indikator eingetroffen ist.
 *
 * @param  string commands[] - Array zur Aufnahme der eingetroffenen Commands
 * @param  int    flags      - zus�tzliche eventspezifische Flags (default: keine)
 *
 * @return bool - Ergebnis
 */
bool EventListener.ChartCommand(string &commands[], int flags=NULL) {
   if (!__CHART) return(false);

   static string label, mutex; if (!StringLen(label)) {
      label = __NAME__ +".command";
      mutex = "mutex."+ label;
   }

   // (1) zuerst nur Lesezugriff (unsynchronisiert m�glich), um nicht bei jedem Tick das Lock erwerben zu m�ssen
   if (ObjectFind(label) == 0) {

      // (2) erst, wenn ein Command eingetroffen ist, Lock f�r Schreibzugriff holen
      if (!AquireLock(mutex, true)) return(!SetLastError(stdlib.GetLastError()));

      // (3) Command auslesen und Command-Object l�schen
      ArrayResize(commands, 1);
      commands[0] = ObjectDescription(label);
      ObjectDelete(label);

      // (4) Lock wieder freigeben
      if (!ReleaseLock(mutex)) return(!SetLastError(stdlib.GetLastError()));

      return(!catch("EventListener.ChartCommand(1)"));
   }
   return(false);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   int    stdlib.init  (/*EXECUTION_CONTEXT*/int ec[], int tickData[]);
   int    stdlib.start (/*EXECUTION_CONTEXT*/int ec[], int tick, datetime tickTime, int validBars, int changedBars);
   int    stdlib.deinit(/*EXECUTION_CONTEXT*/int ec[]);

   int    onDeinitAccountChange();
   int    onDeinitChartChange();
   int    onDeinitChartClose();
   int    onDeinitParameterChange();
   int    onDeinitRecompile();
   int    onDeinitRemove();
   int    onDeinitUndefined();
   // build > 509
   int    onDeinitTemplate();
   int    onDeinitFailed();
   int    onDeinitClose();

   bool   Init.IsNoTick();
   bool   Init.IsNewSymbol(string symbol);
   void   Init.StoreSymbol(string symbol);
   string InputsToStr();

   bool   AquireLock(string mutexName, bool wait);
   bool   ReleaseLock(string mutexName);

#import "Expander.dll"
   int    ec_hChart               (/*EXECUTION_CONTEXT*/int ec[]);
   int    ec_hChartWindow         (/*EXECUTION_CONTEXT*/int ec[]);
   int    ec_InitFlags            (/*EXECUTION_CONTEXT*/int ec[]);
   string ec_LogFile              (/*EXECUTION_CONTEXT*/int ec[]);
   bool   ec_Logging              (/*EXECUTION_CONTEXT*/int ec[]);

   int    ec_setDeinitFlags       (/*EXECUTION_CONTEXT*/int ec[], int    deinitFlags       );
   int    ec_setHChart            (/*EXECUTION_CONTEXT*/int ec[], int    hChart            );
   int    ec_setHChartWindow      (/*EXECUTION_CONTEXT*/int ec[], int    hChartWindow      );
   int    ec_setInitFlags         (/*EXECUTION_CONTEXT*/int ec[], int    initFlags         );
   int    ec_setLastError         (/*EXECUTION_CONTEXT*/int ec[], int    lastError         );
   bool   ec_setLogging           (/*EXECUTION_CONTEXT*/int ec[], int    logging           );
   string ec_setLogFile           (/*EXECUTION_CONTEXT*/int ec[], string logFile           );
   int    ec_setLpSuperContext    (/*EXECUTION_CONTEXT*/int ec[], int    lpSuperContext    );
   int    ec_setRootFunction      (/*EXECUTION_CONTEXT*/int ec[], int    rootFunction      );
   int    ec_setTestFlags         (/*EXECUTION_CONTEXT*/int ec[], int    testFlags         );

   bool   SyncMainExecutionContext(int ec[], int programType, string programName, int rootFunction, int reason, string symbol, int period);

#import "kernel32.dll"
   int    GetCurrentThreadId();
#import


// -- init()-Templates ------------------------------------------------------------------------------------------------------------------------------


/**
 * Initialisierung Preprocessing-Hook
 *
 * @return int - Fehlerstatus
 *
int onInit() {
   return(NO_ERROR);
}


/**
 * Nach manuellem Laden des Indikators durch den User. Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_User() {
   return(NO_ERROR);
}


/**
 * Nach Laden des Indikators innerhalb eines Templates, auch bei Terminal-Start und im Tester bei VisualMode=On|Off. Bei VisualMode=Off
 * werden bei jedem Teststart init() und deinit() der Indikatoren in Tester.tpl aufgerufen, nicht jedoch deren start()-Funktion.
 * Kein Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_Template() {
   return(NO_ERROR);
}


/**
 * Nach Laden des Indikators mittels iCustom(). Kein Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_Program() {
   return(NO_ERROR);
}


/**
 * Nach Testende bei Laden des Indikators mittels iCustom(). Der SuperContext des Indikators ist bei diesem Aufruf bereits nicht mehr g�ltig.
 * Kein Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_ProgramClearTest() {
   return(NO_ERROR);
}


/**
 * Nach manueller �nderung der Indikatorparameter. Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_Parameters() {
   return(NO_ERROR);
}


/**
 * Nach �nderung der aktuellen Chartperiode. Kein Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_TimeframeChange() {
   return(NO_ERROR);
}


/**
 * Nach �nderung des aktuellen Chartsymbols. Kein Input-Dialog.
 *
 * @return int - Fehlerstatus
 *
int onInit_SymbolChange() {
   return(NO_ERROR);
}


/**
 * Bei Reload des Indikators nach Neukompilierung. Kein Input-Dialog
 *
 * @return int - Fehlerstatus
 *
int onInit_Recompile() {
   return(NO_ERROR);
}


/**
 * Initialisierung Postprocessing-Hook
 *
 * @return int - Fehlerstatus
 *
int afterInit() {
   return(NO_ERROR);
}


// -- deinit()-Templates ----------------------------------------------------------------------------------------------------------------------------


/**
 * Deinitialisierung Preprocessing
 *
 * @return int - Fehlerstatus
 *
int onDeinit() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): vor Parameter�nderung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 *
int onDeinitParameterChange() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): vor Symbol- oder Timeframewechsel
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 *
int onDeinitChartChange() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): ???
 * innerhalb iCustom(): ???
 *
 * @return int - Fehlerstatus
 *
int onDeinitAccountChange() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): ???
 * innerhalb iCustom(): ???
 *
 * @return int - Fehlerstatus
 *
int onDeinitChartClose() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): ???
 * innerhalb iCustom(): ???
 *
 * @return int - Fehlerstatus
 *
int onDeinitUndefined() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen, auch vorm Laden eines Profils oder Templates
 * innerhalb iCustom(): in allen deinit()-F�llen
 *
 * @return int - Fehlerstatus
 *
int onDeinitRemove() {
   return(NO_ERROR);
}


/**
 * au�erhalb iCustom(): bei Reload nach Recompilation
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 *
int onDeinitRecompile() {
   return(NO_ERROR);
}


/**
 * Deinitialisierung Postprocessing
 *
 * @return int - Fehlerstatus
 *
int afterDeinit() {
   return(NO_ERROR);
}
*/
