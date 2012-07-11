/**
 *  SnowRoller - Pyramiding Trade Manager
 *  -------------------------------------
 *
 *
 *  TODO:
 *  -----
 *  - execution[] als Struct implementieren                                                           *
 *  - Logging aller Trade-Operationen, Traderequest-Fehler, Slippage                                  *
 *                                                                                                    *
 *  - STOPLEVEL-Verletzung bei Resume abfangen                                                        *
 *  - Sounds in Tradefunktionen abschaltbar machen                                                    *
 *                                                                                                    *
 *  - Start/StopConditions vervollständigen                                                           *
 *  - ResumeCondition implementieren                                                                  *
 *  - automatisches Pause/Resume an Wochenenden                                                       *
 *  - StartCondition @level() implementieren                                                          *
 *  - StartSequence: bei @level(1) Gridbase verschieben und StartCondition neu setzen                 *
 *  - Orderabbruch bei IsStopped()=TRUE abfangen                                                      *
 *  - PendingOrders nicht per Tick trailen                                                            *
 *  - Equity-Charts generieren                                                                        *
 *  - beidseitig unidirektionales Grid implementieren                                                 *
 *  - Laufzeitumgebung auf Server auslagern                                                           *
 *  - BE-Anzeige laufender Sequenzen bis zum aktuellen Moment                                         *
 *  - onBarOpen(PERIOD_M1) für Breakeven-Indikator implementieren                                     *
 *  - EventListener.BarOpen() muß Event auch erkennen, wenn er nicht bei jedem Tick aufgerufen wird   *
 *
 *  - Änderungen der Gridbasis während Auszeit erkennen
 *  - maxProfit/Loss analog zu PendingOrders regelmäßig speichern
 *  - bidirektionales Grid entfernen
 *
 *  - Bug: ChartMarker bei Stopouts
 *  - Bug: Crash, wenn Statusdatei der geladenen Testsequenz gelöscht wird
 *  - Logging aller MessageBoxen
 *  - alle Tradeoperationen müssen einen geänderten Ticketstatus verarbeiten können
 *  - Upload der Statusdatei implementieren
 *  - Heartbeat implementieren
 *  - STATUS_MONITORING implementieren
 *  - Client-Side-Limits implementieren
 *  - Bestätigungsprompt des Traderequests beim ersten Tick auslagern
 *  - orders.stopLoss[] in open-Block verschieben
 *  - die letzten 100 Ticks rund um Traderequest/Ausführung tracken und grafisch aufbereiten
 *
 *  - Build 419 silently crashes (1 mal)
 *  - Alpari: wiederholte Trade-Timeouts von exakt 200 sec.
 *  - Alpari: StopOrder-Slippage EUR/USD bis 4.1 pip, GBP/AUD bis 6 pip, GBP/JPY bis 21.4 pip
 *  - FxPro: zu viele Traderequests in zu kurzer Zeit => ERR_TRADE_TIMEOUT
 *
 *
 *  Übersicht der Aktionen und Statuswechsel:
 *  +-------------------+----------------------+------------+---------------+--------------------+
 *  | Aktion            | Status               | Positionen |  BE-Berechn.  | Erkennung          |
 *  +-------------------+----------------------+------------+---------------+--------------------+
 *  | EA.init()         | STATUS_UNINITIALIZED |            |               |                    |
 *  |                   |                      |            |               |                    |
 *  | EA.start()        | STATUS_WAITING       |            |               |                    |
 *  +-------------------+----------------------+------------+---------------+--------------------+
 *  | StartSequence()   | STATUS_PROGRESSING   |     0      |       -       |                    | sequenceStartTime = Wechsel zu STATUS_PROGRESSING
 *  |                   |                      |            |               |                    |
 *  | Gridbase-Änderung | STATUS_PROGRESSING   |     0      |       -       |                    |
 *  |                   |                      |            |               |                    |
 *  | OrderFilled       | STATUS_PROGRESSING   |    1..n    |  ja (Beginn)  | maxLong-Short > 0  |
 *  |                   |                      |            |               |                    |
 *  | OrderStoppedOut   | STATUS_PROGRESSING   |    n..0    |      ja       |                    |
 *  |                   |                      |            |               |                    |
 *  | Gridbase-Änderung | STATUS_PROGRESSING   |     0      |      ja       |                    |
 *  |                   |                      |            |               |                    |
 *  | StopSequence()    | STATUS_STOPPING      |     n      | nein (Redraw) | STATUS_STOPPING    |
 *  | PositionClose     | STATUS_STOPPING      |    n..0    |       Redraw  | PositionClose      |
 *  |                   | STATUS_STOPPED       |     0      |  Ende Redraw  | STATUS_STOPPED     | sequenceStopTime = Wechsel zu STATUS_STOPPED
 *  +-------------------+----------------------+------------+---------------+--------------------+
 *  | ResumeSequence()  | STATUS_STARTING      |     0      |       -       |                    | ungültige Gridbasis
 *  | Gridbase-Änderung | STATUS_STARTING      |     0      |       -       |                    |
 *  | PositionReopen    | STATUS_STARTING      |    0..n    |               |                    |
 *  |                   | STATUS_PROGRESSING   |     n      |  ja (Beginn)  | STATUS_PROGRESSING | sequenceStartTime = Wechsel zu STATUS_PROGRESSING
 *  |                   |                      |            |               |                    |
 *  | OrderFilled       | STATUS_PROGRESSING   |    1..n    |      ja       |                    |
 *  |                   |                      |            |               |                    |
 *  | OrderStoppedOut   | STATUS_PROGRESSING   |    n..0    |      ja       |                    |
 *  |                   |                      |            |               |                    |
 *  | Gridbase-Änderung | STATUS_PROGRESSING   |     0      |      ja       |                    |
 *  | ...               |                      |            |               |                    |
 *  +-------------------+----------------------+------------+---------------+--------------------+
 */
#include <types.mqh>
#define     __TYPE__      T_EXPERT
int   __INIT_FLAGS__[] = {INIT_TICKVALUE, LOG_INSTANCE_ID, LOG_PER_INSTANCE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>
#include <SnowRoller/define.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern /*sticky*/ string Sequence.ID             = "";
extern            string GridDirection           = "Bidirectional* | Long | Short | Long+Short";
extern            int    GridSize                = 20;
extern            double LotSize                 = 0.1;
extern            string StartConditions         = "";                     // @limit(1.33) && @time(2012.03.12 12:00)
extern            string StopConditions          = "@profit(20%)";         // @limit(1.33) || @time(2012.03.12 12:00) || @profit(1234.00) || @profit(10%)
extern /*sticky*/ color  Breakeven.Color         = Blue;
extern /*sticky*/ string Sequence.StatusLocation = "";                     // Unterverzeichnis

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

       /*sticky*/ int    startStopDisplayMode    = SDM_PRICE;              // sticky-Variablen werden im Chart zwischengespeichert, sie überleben
       /*sticky*/ int    orderDisplayMode        = ODM_NONE;               // dort Terminal-Restart, Profile-Wechsel oder Recompilation.
       /*sticky*/ int    breakeven.Width         = 0;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   last.Sequence.ID             = "";           // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE
string   last.Sequence.StatusLocation = "";           // mit den Default-Werten überschrieben. Um dies zu verhindern und um geänderte Parameter mit
string   last.GridDirection           = "";           // alten Werten vergleichen zu können, werden sie in deinit() in last.* zwischengespeichert und
int      last.GridSize;                               // in init() daraus restauriert.
double   last.LotSize;
string   last.StartConditions         = "";
string   last.StopConditions          = "";
color    last.Breakeven.Color;

int      sequenceId;
bool     test;                                        // ob dies eine Testsequenz ist (im Tester oder im Online-Chart)

int      status = STATUS_UNINITIALIZED;
string   status.directory;                            // MQL-Verzeichnis der Statusdatei (unterhalb ".\files\")
string   status.fileName;                             // einfacher Dateiname der Statusdatei

datetime instanceStartTime;                           // Start des EA's
double   instanceStartPrice;
double   sequenceStartEquity;                         // Equity bei Start der ersten Subsequenz

datetime sequenceStartTimes [];                       // Start-Daten: bei Abschluß des Starts (Statuswechsel zu STATUS_PROGRESSING)
double   sequenceStartPrices[];

datetime sequenceStopTimes [];                        // Stop-Daten: bei Abschluß des Stops (Statuswechsel zu STATUS_STOPPED)
double   sequenceStopPrices[];

bool     start.conditions;                            // ob mindestens eine StartCondition aktiv ist
bool     start.limit.condition;
double   start.limit.value;
bool     start.time.condition;
datetime start.time.value;

bool     stop.conditions;                             // ob mindestens eine StopCondition aktiv ist
bool     stop.limit.condition;
double   stop.limit.value;
bool     stop.time.condition;
datetime stop.time.value;
bool     stop.profitAbs.condition;
double   stop.profitAbs.value;
bool     stop.profitPercent.condition;
double   stop.profitPercent.value;

int      grid.direction = D_BIDIR;

datetime grid.base.time [];                           // Gridbasis-Daten
double   grid.base.value[];
double   grid.base;                                   // aktuelle Gridbasis                                                         SS Grid:        Feld 2

int      grid.level;                                  // aktueller Grid-Level                                                       SS Header:      Feld 2
int      grid.maxLevelLong;                           // maximal erreichter Long-Level                                              SS Header:      Feld 3
int      grid.maxLevelShort;                          // maximal erreichter Short-Level                                             SS Header:      Feld 4
double   grid.commission;                             // Commission-Betrag je Level (falls zutreffend)

int      grid.stops;                                  // Anzahl der bisher getriggerten Stops                                       SS Stops:       Feld 1
double   grid.stopsPL;                                // P/L der ausgestoppten Positionen (0 oder negativ)                          SS Stops:       Feld 2
double   grid.closedPL;                               // P/L bei StopSequence() geschlossener Positionen (realizedPL = stopsPL + closedPL)
double   grid.floatingPL;                             // P/L offener Positionen
double   grid.totalPL;                                // Gesamt-P/L der Sequenz:  realizedPL + floatingPL                           SS Profit/Loss: Feld 1
double   grid.activeRisk;                             // aktuelles Risiko der aktiven Level (0 oder positiv)
double   grid.valueAtRisk;                            // aktuelles Gesamtrisiko:  -stopsPL + activeRisk (0 oder positiv)            SS Profit/Loss: Feld 4

double   grid.maxProfit;                              // maximal erreichter Gesamtprofit (0 oder positiv)                           SS Profit/Loss: Feld 2
datetime grid.maxProfitTime;
double   grid.maxDrawdown;                            // maximal erreichter Drawdown (0 oder negativ)                               SS Profit/Loss: Feld 3
datetime grid.maxDrawdownTime;

double   grid.breakevenLong;                          //                                                                            SS Breakeven:   Feld 1
double   grid.breakevenShort;                         //                                                                            SS Breakeven:   Feld 2

int      orders.ticket        [];
int      orders.level         [];                     // Gridlevel der Order
double   orders.gridBase      [];                     // Gridbasis der Order

int      orders.pendingType   [];                     // Pending-Orderdaten (falls zutreffend)
datetime orders.pendingTime   [];                     // Zeitpunkt von OrderOpen() bzw. des letzten OrderModify()
double   orders.pendingPrice  [];

int      orders.type          [];
datetime orders.openTime      [];
double   orders.openPrice     [];
double   orders.risk          [];                     // Risiko des Levels (0, solange Order pending, danach positiv)

datetime orders.closeTime     [];
double   orders.closePrice    [];
double   orders.stopLoss      [];
bool     orders.closedBySL    [];

double   orders.swap          [];
double   orders.commission    [];
double   orders.profit        [];

int      ignorePendingOrders  [];                     // orphaned tickets to ignore
int      ignoreOpenPositions  [];
int      ignoreClosedPositions[];

string   str.test              = "";                  // Zwischenspeicher für schnellere Abarbeitung von ShowStatus()
string   str.LotSize           = "";
string   str.startConditions   = "";
string   str.stopConditions    = "";
string   str.grid.direction    = "";
string   str.grid.base         = "";
string   str.grid.maxLevel     = "";
string   str.grid.stops        = "0 stops";
string   str.grid.stopsPL      = "";
string   str.grid.breakeven    = "";
string   str.grid.totalPL      = "-";
string   str.grid.maxProfit    = "0.00";
string   str.grid.maxDrawdown  = "0.00";
string   str.grid.valueAtRisk  = "0.00";
string   str.grid.plStatistics = "";

bool     firstTick                      = true;
bool     firstTickConfirmed             = false;


#include <SnowRoller/init.mqh>
#include <SnowRoller/deinit.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (status==STATUS_UNINITIALIZED || status==STATUS_DISABLED) {
      firstTick = false;
      return(NO_ERROR);
   }


   // (1) Commands verarbeiten
   HandleEvent(EVENT_CHART_CMD);

   if (status == STATUS_STOPPED) {
      firstTick = false;
      return(last_error);
   }


   static int    last.grid.level;
   static double last.grid.base;


   // (2) Sequenz wartet entweder auf Startsignal...
   if (status == STATUS_WAITING) {
      if (IsStartSignal())                    StartSequence();
   }

   // (3) ...oder läuft: Daten und Orders aktualisieren
   else if (UpdateStatus()) {
      if      (IsStopSignal())                StopSequence();
      else if (grid.level != last.grid.level) UpdatePendingOrders();
      else if (NE(grid.base, last.grid.base)) UpdatePendingOrders();
   }

   last.grid.level = grid.level;
   last.grid.base  = grid.base;
   firstTick       = false;


   // (4) Status anzeigen
   ShowStatus();

   return(last_error);
}


/**
 * Handler für ChartCommand-Events.
 *
 * @param  string commands[] - die übermittelten Kommandos
 *
 * @return int - Fehlerstatus
 */
int onChartCommand(string commands[]) {
   if (ArraySize(commands) == 0)
      return(catch("onChartCommand(1)   illegal parameter commands = "+ StringsToStr(commands, NULL), ERR_INVALID_FUNCTION_PARAMVALUE));

   string cmd = commands[0];

   if (cmd == "start") {
      switch (status) {
         case STATUS_WAITING:
            StartSequence();
            break;
         case STATUS_STOPPED:
            ResumeSequence();
            break;
      }
      return(last_error);
   }
   else if (cmd == "stop") {
      switch (status) {
         case STATUS_WAITING    :
         case STATUS_PROGRESSING:
            if (UpdateStatus())
               StopSequence();
            ShowStatus();
      }
      return(last_error);
   }
   else if (cmd == "startstopdisplay") return(ToggleStartStopDisplayMode());
   else if (cmd ==     "orderdisplay") return(    ToggleOrderDisplayMode());
   else if (cmd == "breakevendisplay") return(ToggleBreakevenDisplayMode());

   // unbekannte Commands anzeigen, aber keinen Fehler setzen (sie dürfen den EA nicht deaktivieren können)
   warn("onChartCommand(2)   unknown command \""+ cmd +"\"");
   return(NO_ERROR);
}


/**
 * Handler für BarOpen-Events.
 *
 * @param int timeframes[] - IDs der Timeframes, in denen das BarOpen-Event aufgetreten ist
 *
 * @return int - Fehlerstatus
 */
int onBarOpen(int timeframes[]) {
   if (Grid.DrawBreakeven())
      return(NO_ERROR);
   return(last_error);
}


/**
 * Startet eine neue Trade-Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("StartSequence(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_WAITING)             return(_false(catch("StartSequence(2)   cannot start "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - StartSequence()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to start a new sequence now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("StartSequence(3)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   status = STATUS_STARTING;


   // (1) Startvariablen setzen
   datetime startTime  = TimeCurrent();
   double   startPrice = NormalizeDouble((Bid + Ask)/2, Digits);

   ArrayPushInt   (sequenceStartTimes, startTime-1);                 // Wir setzen startTime 1 sec. in die Vergangenheit, um Mehrdeutigkeiten
   ArrayPushDouble(sequenceStartPrices, startPrice);                 // bei der Sortierung der Breakeven-Events zu vermeiden.
   ArrayPushInt   (sequenceStopTimes,            0);
   ArrayPushDouble(sequenceStopPrices,           0);

   sequenceStartEquity = NormalizeDouble(AccountEquity()-AccountCredit(), 2);

   status = STATUS_PROGRESSING;


   // (2) Gridbasis setzen
   Grid.BaseReset(startTime, startPrice);                            // zeitlich immer nach sequenceStartTime


   // (3) Stop-Orders in den Markt legen
   if (!UpdatePendingOrders())
      return(false);

   RedrawStartStop();
   return(IsNoError(catch("StartSequence(4)")));
}


/**
 * Schließt alle PendingOrders und offenen Positionen der Sequenz.
 *
 * @return bool - Erfolgsstatus: ob die Sequenz erfolgreich gestoppt wurde
 */
bool StopSequence() {
   if (__STATUS__CANCELLED || IsLastError())                                            return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())                                               return(_false(catch("StopSequence(1)", ERR_ILLEGAL_STATE)));
   if (status!=STATUS_WAITING && status!=STATUS_PROGRESSING && status!=STATUS_STOPPING) return(_false(catch("StopSequence(2)   cannot stop "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));


   if (firstTick && !firstTickConfirmed) {                                       // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - StopSequence()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to stop the sequence now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("StopSequence(3)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) eine wartende Sequenz ist noch nicht gestartet und wird gecanceled
   if (status == STATUS_WAITING) {
      __STATUS__CANCELLED = true;
      if (IsTesting())
         Tester.Pause();
      return(_false(catch("StopSequence(4)")));
   }


   status = STATUS_STOPPING;


   // (2) PendingOrders und OpenPositions einlesen
   int pendingOrders[], openPositions[], sizeOfTickets=ArraySize(orders.ticket);
   ArrayResize(pendingOrders, 0);
   ArrayResize(openPositions, 0);

   for (int i=0; i < sizeOfTickets; i++) {
      if (orders.closeTime[i] == 0) {                                            // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "StopSequence(5)"))
            return(false);
         if (OrderCloseTime() == 0) {                                            // offene Tickets je nach Typ zwischenspeichern
            if (IsPendingTradeOperation(OrderType())) ArrayPushInt(pendingOrders, orders.ticket[i]);
            else                                      ArrayPushInt(openPositions, orders.ticket[i]);
         }
      }
   }


   // (3) zuerst Pending-Orders streichen (ansonsten werden während OrderClose() u.U. die Stops/Limits getriggert)
   bool ordersChanged;
   int  sizeOfPendingOrders = ArraySize(pendingOrders);

   for (i=0; i < sizeOfPendingOrders; i++) {
      if (!Grid.DeleteOrder(pendingOrders[i]))
         return(false);
      ordersChanged = true;
   }


   // (4) offene Positionen schließen                                            // TODO: Wurde eine PendingOrder inzwischen getriggert, muß sie hier mit verarbeitet werden.
   int    sizeOfOpenPositions = ArraySize(openPositions);
   int    n = ArraySize(sequenceStopTimes) - 1;
   int    flags = NULL;
   double execution[];

   if (sizeOfOpenPositions > 0) {
      if (!OrderMultiClose(openPositions, NULL, CLR_CLOSE, flags, execution))
         return(_false(SetLastError(stdlib_PeekLastError())));

      sequenceStopTimes [n] =           Round(execution[EXEC_TIME ] + 1);        // Wir setzen sequenceStopTime 1 sec. in die Zukunft, um Mehrdeutigkeiten
      sequenceStopPrices[n] = NormalizeDouble(execution[EXEC_PRICE], Digits);    // bei der Sortierung der Breakeven-Events zu vermeiden.

      for (i=0; i < sizeOfOpenPositions; i++) {
         int pos = SearchIntArray(orders.ticket, openPositions[i]);

         orders.closeTime [pos] = Round(execution[9*i+EXEC_TIME ]);              // entspricht execution[EXEC_TIME ]
         orders.closePrice[pos] =       execution[9*i+EXEC_PRICE];               // entspricht execution[EXEC_PRICE]
         orders.closedBySL[pos] = false;

         orders.swap      [pos] = execution[9*i+EXEC_SWAP      ];
         orders.commission[pos] = execution[9*i+EXEC_COMMISSION];
         orders.profit    [pos] = execution[9*i+EXEC_PROFIT    ];

         grid.closedPL += orders.swap[pos] + orders.commission[pos] + orders.profit[pos];
       //grid.activeRisk  ändert sich nicht bei StopSequence()
       //grid.valueAtRisk ändert sich nicht bei StopSequence()
      }
      /*
      grid.floatingPL      = ...                                                 // Solange unten UpdateStatus() aufgerufen wird, werden diese Werte dort automatisch aktualisiert.
      grid.totalPL         = ...
      grid.maxProfit       = ...
      grid.maxProfitTime   = ...
      grid.maxDrawdown     = ...
      grid.maxDrawdownTime = ...
      */
      ordersChanged = true;
   }
   else {
      sequenceStopTimes [n] = TimeCurrent() + 1;                                 // Wir setzen sequenceStopTime 1 sec. in die Zukunft, um Mehrdeutigkeiten
      sequenceStopPrices[n] = (Bid + Ask)/2;                                     // bei der Sortierung der Breakeven-Events zu vermeiden.
      if      (grid.base < sequenceStopPrices[n]) sequenceStopPrices[n] = Bid;
      else if (grid.base > sequenceStopPrices[n]) sequenceStopPrices[n] = Ask;
      sequenceStopPrices[n] = NormalizeDouble(sequenceStopPrices[n], Digits);
   }


   status = STATUS_STOPPED;


   // (5) Daten aktualisieren und speichern
   if (ordersChanged) {
      if (!UpdateStatus()) return(false);
      if (  !SaveStatus()) return(false);
   }
   RedrawStartStop();


   // (6) ggf. Tester stoppen
   if (IsTesting())
      Tester.Pause();

   /*
   debug("StopSequence()      level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));
   */
   return(IsNoError(catch("StopSequence(6)")));
}


/**
 * Setzt eine gestoppte Sequenz fort.
 *
 * @return bool - Erfolgsstatus
 */
bool ResumeSequence() {
   if (__STATUS__CANCELLED || IsLastError())              return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())                 return(_false(catch("ResumeSequence(1)", ERR_ILLEGAL_STATE)));
   if (status!=STATUS_STOPPED && status!=STATUS_STARTING) return(_false(catch("ResumeSequence(2)   cannot resume "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                                    // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - ResumeSequence()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to resume the sequence now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("ResumeSequence(3)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   status = STATUS_STARTING;


   datetime startTime;
   double   startPrice, lastStopPrice, gridBase;


   // (1) Start-/StopConditions deaktivieren
   start.conditions = false; StartConditions = "";
   stop.conditions  = false; StopConditions  = "";
   SS.StartStopConditions();


   // (2) Wird ResumeSequence() nach einem Fehler erneut aufgerufen, kann es sein, daß einige Level bereits offen sind und andere noch fehlen.
   if (grid.level > 0) {
      for (int level=1; level <= grid.level; level++) {
         int i = Grid.FindOpenPosition(level);
         if (i != -1) {
            gridBase = orders.gridBase[i];
            break;
         }
      }
   }
   else if (grid.level < 0) {
      for (level=-1; level >= grid.level; level--) {
         i = Grid.FindOpenPosition(level);
         if (i != -1) {
            gridBase = orders.gridBase[i];
            break;
         }
      }
   }


   // (3) Neue Gridbasis nur dann setzen, wenn noch keine offenen Positionen existieren.
   if (EQ(gridBase, 0)) {
      startTime     = TimeCurrent();
      startPrice    = (Bid + Ask)/2;
      lastStopPrice = sequenceStopPrices[ArraySize(sequenceStopPrices)-1];
      if      (grid.base < lastStopPrice) startPrice = Ask;
      else if (grid.base > lastStopPrice) startPrice = Bid;
      startPrice = NormalizeDouble(startPrice, Digits);

      Grid.BaseChange(startTime-1, grid.base + startPrice - lastStopPrice);   // Wir setzen grid.base.time 1 sec. in die Vergangenheit, um Mehrdeutigkeiten
   }                                                                          // bei der Sortierung der Breakeven-Events zu vermeiden.
   else {
      grid.base = NormalizeDouble(gridBase, Digits);                          // Gridbasis der vorhandenen Positionen übernehmen (sollte schon so gesetzt sein, aber wer weiß...)
   }


   // (4) vorherige Positionen wieder in den Markt legen und letzte OrderOpenTime abfragen
   if (!UpdateOpenPositions(startTime, startPrice))
      return(false);


   // (5) neuen Sequenzstart speichern
   ArrayPushInt   (sequenceStartTimes, startTime+1);                          // zeitlich immer nach der letzten OrderOpenTime()
   ArrayPushDouble(sequenceStartPrices, startPrice);
   ArrayPushInt   (sequenceStopTimes,            0);
   ArrayPushDouble(sequenceStopPrices,           0);


   status = STATUS_PROGRESSING;


   // (5) Stop-Orders vervollständigen
   if (!UpdatePendingOrders())
      return(false);


   // (6) Breakeven neu berechnen und Anzeigen aktualisieren
   if (!Grid.CalculateBreakeven())
      return(false);
   RedrawStartStop();

   /*
   debug("ResumeSequence()    level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));
   */
   return(IsNoError(catch("ResumeSequence(4)")));
}


/**
 * Prüft und synchronisiert die im EA gespeicherten mit den aktuellen Laufzeitdaten.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatus() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("UpdateStatus(1)", ERR_ILLEGAL_STATE)));
   if (status == STATUS_WAITING)             return( true);

   grid.floatingPL = 0;

   bool wasPending, isClosed, openPositions, recalcBreakeven, updateStatusLocation;
   int  sizeOfTickets = ArraySize(orders.ticket);


   // (1) Tickets aktualisieren
   for (int i=0; i < sizeOfTickets; i++) {
      if (orders.closeTime[i] == 0) {                                                           // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "UpdateStatus(2)"))
            return(false);

         wasPending = orders.type[i] == OP_UNDEFINED;

         if (wasPending) {
            // beim letzten Aufruf Pending-Order
            if (OrderType() != orders.pendingType[i]) {                                         // Order wurde ausgeführt
               orders.type      [i] = OrderType();
               orders.openTime  [i] = OrderOpenTime();
               orders.openPrice [i] = OrderOpenPrice();
               orders.risk      [i] = CalculateActiveRisk(orders.level[i], orders.ticket[i], OrderOpenPrice(), OrderSwap(), OrderCommission());
               orders.swap      [i] = OrderSwap();
               orders.commission[i] = OrderCommission(); grid.commission = OrderCommission(); SS.LotSize();
               orders.profit    [i] = OrderProfit();
               ChartMarker.OrderFilled(i);

               grid.level          += Sign(orders.level[i]);
               updateStatusLocation = updateStatusLocation || (grid.maxLevelLong-grid.maxLevelShort==0);
               grid.maxLevelLong    = Max(grid.level, grid.maxLevelLong );
               grid.maxLevelShort   = Min(grid.level, grid.maxLevelShort); SS.Grid.MaxLevel();
               grid.activeRisk     += orders.risk[i];
               grid.valueAtRisk    += orders.risk[i]; SS.Grid.ValueAtRisk();                    // valueAtRisk = -stopsPL + activeRisk
               recalcBreakeven      = true;
            }
         }
         else {
            // beim letzten Aufruf offene Position
            if (NE(orders.swap[i], OrderSwap())) {                                              // bei Swap-Änderung activeRisk und valueAtRisk justieren
               grid.activeRisk  -= (OrderSwap() - orders.swap[i]);
               grid.valueAtRisk -= (OrderSwap() - orders.swap[i]); SS.Grid.ValueAtRisk();
               recalcBreakeven   = true;
            }
            orders.swap      [i] = OrderSwap();
            orders.commission[i] = OrderCommission();
            orders.profit    [i] = OrderProfit();
         }


         isClosed = OrderCloseTime() != 0;

         if (!isClosed) {                                                                       // weiterhin offenes Ticket
            grid.floatingPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
            if (orders.type[i] != OP_UNDEFINED)
               openPositions = true;
         }
         else {                                                                                 // jetzt geschlossenes Ticket: gestrichene Pending-Order oder geschlossene Position
            orders.closeTime [i] = OrderCloseTime();                                            // Bei Spikes kann eine Pending-Order ausgeführt *und* bereits geschlossen sein.
            orders.closePrice[i] = OrderClosePrice();

            if (orders.type[i] == OP_UNDEFINED) {                                               // gestrichene Pending-Order im STATUS_MONITORING
               //ChartMarker.OrderDeleted(i);                                                   // TODO: implementieren
               Grid.DropTicket(orders.ticket[i]);
               sizeOfTickets--; i--;
               continue;
            }
            else {                                                                              // geschlossene Position
               orders.closedBySL[i] = IsOrderClosedBySL();
               ChartMarker.PositionClosed(i);

               if (orders.closedBySL[i]) {                                                      // ausgestoppt
                  grid.level      -= Sign(orders.level[i]);
                  grid.stops++;
                  grid.stopsPL    += orders.swap[i] + orders.commission[i] + orders.profit[i]; SS.Grid.Stops();
                  grid.activeRisk -= orders.risk[i];
                  grid.valueAtRisk = grid.activeRisk - grid.stopsPL; SS.Grid.ValueAtRisk();     // valueAtRisk = -stopsPL + activeRisk
                  recalcBreakeven = true;
               }
               else {                                                                           // Sequenzstop im STATUS_MONITORING oder autom. Close bei Beenden des Testers
                  status = STATUS_STOPPING;
                  grid.closedPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
               }
            }
         }
      }
   }


   // (2) P/L-Kennziffern  aktualisieren
   grid.totalPL = grid.stopsPL + grid.closedPL + grid.floatingPL; SS.Grid.TotalPL();

   if (grid.totalPL > grid.maxProfit) {
      grid.maxProfit     = grid.totalPL;
      grid.maxProfitTime = TimeCurrent(); SS.Grid.MaxProfit();
   }
   else if (grid.totalPL < grid.maxDrawdown) {
      grid.maxDrawdown     = grid.totalPL;
      grid.maxDrawdownTime = TimeCurrent(); SS.Grid.MaxDrawdown();
   }


   // (3) Status aktualisieren
   if (status == STATUS_STOPPING) {
      if (!openPositions) {                                                                     // StopSequence() in STATUS_MONITORING: alle offenen Positionen geschlossen
         status = STATUS_STOPPED;

         int n = ArraySize(sequenceStopTimes) - 1;
         sequenceStopTimes [n] = CalculateSequenceStopTime() + 1;                               // Wir setzen sequenceStopTime 1 sec. in die Zukunft, um Mehrdeutigkeiten
         sequenceStopPrices[n] = CalculateSequenceStopPrice();                                  // bei der Sortierung der Breakeven-Events zu vermeiden.
         RedrawStartStop();
      }
   }


   if (status == STATUS_PROGRESSING) {
      // (4) ggf. Gridbasis trailen
      if (grid.level == 0) {
         double last.grid.base = grid.base;

         if      (grid.direction == D_LONG ) grid.base = MathMin(grid.base, NormalizeDouble((Bid + Ask)/2, Digits));
         else if (grid.direction == D_SHORT) grid.base = MathMax(grid.base, NormalizeDouble((Bid + Ask)/2, Digits));

         if (NE(grid.base, last.grid.base)) {
            Grid.BaseChange(TimeCurrent()+1, grid.base);                                        // Wir setzen den Zeitpunkt 1 sec. in die Zukunft, um eine eindeutige Sortierung
            recalcBreakeven = true;                                                             // der Breakeven-Events zu gewährleisten (EV_POSITION_STOPOUT != EV_GRIDBASE_CHANGE).
         }
      }


      // (5) ggf. Breakeven neu berechnen oder (ab dem ersten ausgeführten Trade) Anzeige aktualisieren
      if (recalcBreakeven) {
         Grid.CalculateBreakeven();
      }
      else if (grid.maxLevelLong-grid.maxLevelShort != 0) {
         if      (  !IsTesting()) HandleEvent(EVENT_BAR_OPEN/*, F_PERIOD_M1*/);                 // jede Minute       // TODO: EventListener muß Event auch ohne permanenten Aufruf erkennen
         else if (IsVisualMode()) HandleEvent(EVENT_BAR_OPEN);                                  // nur onBarOpen     //       (langlaufendes UpdateStatus() überspringt evt. Event)
      }
   }


   // (6) ggf. Ort der Statusdatei aktualisieren
   if (updateStatusLocation)
      UpdateStatusLocation();

   return(!IsLastError() && IsNoError(catch("UpdateStatus(3)")));
}


/**
 * Prüft, ob seit dem letzten Aufruf ein ChartCommand-Event aufgetreten ist.
 *
 * @param  string commands[] - Array zur Aufnahme der aufgetretenen Kommandos
 * @param  int    flags      - zusätzliche eventspezifische Flags (default: keine)
 *
 * @return bool - Ergebnis
 */
bool EventListener.ChartCommand(string commands[], int flags=NULL) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(false);

   if (ArraySize(commands) > 0)
      ArrayResize(commands, 0);

   static string label, mutex="mutex.ChartCommand";
   static int    sid;

   if (sequenceId != sid) {
      label = StringConcatenate(__NAME__, ".", Sequence.ID, ".command");      // Label wird nur modifiziert, wenn es sich tatsächlich ändert
      sid   = sequenceId;
   }

   if (ObjectFind(label) == 0) {
      if (!AquireLock(mutex))
         return(_false(SetLastError(stdlib_PeekLastError())));

      ArrayPushString(commands, ObjectDescription(label));
      ObjectDelete(label);

      if (!ReleaseLock(mutex))
         return(_false(SetLastError(stdlib_PeekLastError())));

      return(true);
   }
   return(false);
}


/**
 * Ob der StopLoss der aktuell selektierten Order getriggert wurde.
 *
 * @return bool
 */
bool IsOrderClosedBySL() {
   bool position   = OrderType()==OP_BUY || OrderType()==OP_SELL;
   bool closed     = OrderCloseTime() != 0;                          // geschlossene Position
   bool closedBySL = false;

   if (closed) /*&&*/ if (position) {
      if (StringIEndsWith(OrderComment(), "[sl]")) {
         closedBySL = true;
      }
      else {
         // Bei client-side-Limits StopLoss aus Griddaten verwenden.
         double stopLoss = OrderStopLoss();
         if (EQ(stopLoss, 0)) {
            int i = SearchIntArray(orders.ticket, OrderTicket());
            if (i == -1)
               return(_false(catch("IsOrderClosedBySL(1)   #"+ OrderTicket() +" not found in grid arrays", ERR_RUNTIME_ERROR)));
            stopLoss = NormalizeDouble(orders.stopLoss[i], Digits);
            if (EQ(stopLoss, 0))
               return(_false(catch("IsOrderClosedBySL(2)   #"+ OrderTicket() +" no stop-loss found in grid arrays", ERR_RUNTIME_ERROR)));
         }
         if      (OrderType() == OP_BUY ) closedBySL = LE(OrderClosePrice(), stopLoss);
         else if (OrderType() == OP_SELL) closedBySL = GE(OrderClosePrice(), stopLoss);
      }
   }
   return(closedBySL);
}


/**
 * Signalgeber für StartSequence(). Die einzelnen Bedingungen sind AND-verknüpft.
 *
 * @return bool - ob alle konfigurierten Startbedingungen erfüllt sind
 */
bool IsStartSignal() {
   if (__STATUS__CANCELLED || status!=STATUS_WAITING || IsLastError())
      return(false);

   static bool isTriggered = false;


   if (start.conditions) {
      if (isTriggered)                                               // einmal getriggert, immer getriggert (solange start.conditions aktiviert sind)
         return(true);

      // -- start.limit: erfüllt, wenn der Bid-Preis den Wert berührt oder kreuzt ---------------------------------------
      if (start.limit.condition) {
         static double lastBid;                                      // Kreuzen des Limits seit dem letzten Tick erkennen
         static bool   lastBid_init = true;

         bool result;

         if (EQ(Bid, start.limit.value)) {                           // Bid liegt exakt auf dem Limit
            result = true;
         }
         else if (lastBid_init) {
            lastBid_init = false;
         }
         else if (LT(lastBid, start.limit.value)) {
            result = GT(Bid, start.limit.value);                     // Bid hat Limit von unten nach oben gekreuzt
         }
         else if (GT(lastBid, start.limit.value)) {
            result = LT(Bid, start.limit.value);                     // Bid hat Limit von oben nach unten gekreuzt
         }

         lastBid = Bid;
         if (!result)
            return(false);
      }

      // -- start.time: zum angegebenen Zeitpunkt oder danach erfüllt ---------------------------------------------------
      if (start.time.condition) {
         if (TimeCurrent() < start.time.value)
            return(false);
      }

      // -- alle Bedingungen sind erfüllt (AND-Verknüpfung) -------------------------------------------------------------
      isTriggered = true;
   }
   else {
      isTriggered = false;                                           // Keine Startbedingungen sind ebenfalls gültiges Startsignal,
   }                                                                 // isTriggered wird jedoch zurückgesetzt (Startbedingungen könnten sich ändern).
   return(true);
}


/**
 * Signalgeber für StopSequence(). Die einzelnen Bedingungen sind OR-verknüpft.
 *
 * @return bool - ob mindestens eine der konfigurierten Stopbedingungen erfüllt ist
 */
bool IsStopSignal() {
   if (__STATUS__CANCELLED || status!=STATUS_PROGRESSING)
      return(false);

   static bool isTriggered = false;


   if (stop.conditions) {
      if (isTriggered)                                               // einmal getriggert, immer getriggert (solange stop.conditions aktiviert ist)
         return(true);

      // -- stop.limit: erfüllt, wenn der Bid-Preis den Wert berührt oder kreuzt ----------------------------------------
      if (stop.limit.condition) {
         static double lastBid;                                      // Kreuzen des Limits seit dem letzten Tick erkennen
         static bool   lastBid_init = true;

         bool result;

         if (EQ(Bid, stop.limit.value)) {                            // Bid liegt exakt auf dem Limit
            result = true;
         }
         else if (lastBid_init) {
            lastBid_init = false;
         }
         else if (LT(lastBid, stop.limit.value)) {
            result = GT(Bid, stop.limit.value);                      // Bid hat Limit von unten nach oben gekreuzt
         }
         else if (GT(lastBid, stop.limit.value)) {
            result = LT(Bid, stop.limit.value);                      // Bid hat Limit von oben nach unten gekreuzt
         }

         lastBid = Bid;
         if (result) {
            isTriggered = true;
            return(true);
         }
      }

      // -- stop.time: zum angegebenen Zeitpunkt oder danach erfüllt ----------------------------------------------------
      if (stop.time.condition) {
         if (stop.time.value <= TimeCurrent()) {
            isTriggered = true;
            return(true);
         }
      }

      // -- stop.profitAbs: ---------------------------------------------------------------------------------------------
      if (stop.profitAbs.condition) {
         if (GE(grid.totalPL, stop.profitAbs.value)) {
            isTriggered = true;
            return(true);
         }
      }

      // -- stop.profitPercent: -----------------------------------------------------------------------------------------
      if (stop.profitPercent.condition) {
         if (GE(grid.totalPL, stop.profitPercent.value/100 * sequenceStartEquity)) {
            isTriggered = true;
            return(true);
         }
      }

      // -- keine der Bedingungen ist erfüllt (OR-Verknüpfung) ----------------------------------------------------------
   }

   isTriggered = false;
   return(false);
}


/**
 * Aktualisiert vorhandene, setzt fehlende und löscht unnötige PendingOrders.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePendingOrders() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("UpdatePendingOrders(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_PROGRESSING)         return(_false(catch("UpdatePendingOrders(2)   cannot update orders of "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   bool nextOrderExists, ordersChanged;
   int  nextLevel = grid.level + Sign(grid.level);

   if (grid.level > 0) {                                                         // hier niemals Änderung von grid.base
      // unnötige Pending-Orders löschen
      for (int i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (orders.level[i] == nextLevel) {
               nextOrderExists = true;
               continue;
            }
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }
      // wenn nötig, neue Stop-Order in den Markt legen
      if (!nextOrderExists) {
         if (!Grid.AddOrder(OP_BUYSTOP, nextLevel))
            return(false);
         ordersChanged = true;
      }
   }

   else if (grid.level < 0) {                                                    // hier niemals Änderung von grid.base
      // unnötige Pending-Orders löschen
      for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (orders.level[i] == nextLevel) {
               nextOrderExists = true;
               continue;
            }
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }
      // wenn nötig, neue Stop-Order in den Markt legen
      if (!nextOrderExists) {
         if (!Grid.AddOrder(OP_SELLSTOP, nextLevel))
            return(false);
         ordersChanged = true;
      }
   }

   else /*(grid.level == 0)*/ {                                                  // Nur hier kann sich grid.base geändert haben: Pending-Orders trailen
      bool buyOrderExists, sellOrderExists;

      for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (grid.direction!=D_SHORT) /*&&*/ if (orders.level[i]==1) {
               if (NE(orders.pendingPrice[i], grid.base + GridSize*Pips)) {
                  if (!Grid.TrailPendingOrder(i))
                     return(false);
                  ordersChanged = true;
               }
               buyOrderExists = true;
               continue;
            }
            if (grid.direction!=D_LONG) /*&&*/ if (orders.level[i]==-1) {
               if (NE(orders.pendingPrice[i], grid.base - GridSize*Pips)) {
                  if (!Grid.TrailPendingOrder(i))
                     return(false);
                  ordersChanged = true;
               }
               sellOrderExists = true;
               continue;
            }
            // unnötige Pending-Orders löschen
            if (!Grid.DeleteOrder(orders.ticket[i]))
               return(false);
            ordersChanged = true;
         }
      }

      // wenn nötig, neue Stop-Orders in den Markt legen
      if (grid.direction!=D_SHORT) /*&&*/ if (!buyOrderExists) {
         if (!Grid.AddOrder(OP_BUYSTOP, 1))
            return(false);
         ordersChanged = true;
      }
      if (grid.direction!=D_LONG) /*&&*/ if (!sellOrderExists) {
         if (!Grid.AddOrder(OP_SELLSTOP, -1))
            return(false);
         ordersChanged = true;
      }
   }

   if (ordersChanged)                                                            // nach jeder Änderung Status speichern
      if (!SaveStatus())
         return(false);

   return(IsNoError(catch("UpdatePendingOrders(3)")));
}


/**
 * Öffnet neue bzw. vervollständigt fehlende der zuletzt offenen Positionen der Sequenz.
 *
 * @param  datetime lpOpenTime  - Zeiger auf Variable, die die OpenTime der zuletzt geöffneten Position aufnimmt
 * @param  double   lpOpenPrice - Zeiger auf Variable, die den durchschnittlichen OpenPrice aufnimmt
 *
 * @return bool - Erfolgsstatus
 *
 *
 *  NOTE:  Im Level 0 (keine Positionen zu öffnen) werden die Variablen, auf die die Parameter zeigen, nicht modifiziert.
 *  -----
 */
bool UpdateOpenPositions(datetime &lpOpenTime, double &lpOpenPrice) {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("UpdateOpenPositions(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_STARTING)            return(_false(catch("UpdateOpenPositions(2)   cannot update positions of "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   int i, level;
   datetime openTime;
   double   openPrice;


   // (1) activeRisk jedes mal neuberechnen
   grid.activeRisk = 0;


   if (grid.level > 0) {
      for (level=1; level <= grid.level; level++) {                              // TODO: STOPLEVEL-Fehler im letzten Level abfangen und behandeln
         i = Grid.FindOpenPosition(level);
         if (i == -1) {
            if (!Grid.AddPosition(OP_BUY, level))
               return(false);
            if (!SaveStatus())                                                   // Status nach jeder Trade-Operation speichern, um das Ticket nicht zu verlieren,
               return(false);                                                    // wenn in einer der folgenden Operationen ein Fehler auftritt.
            i = ArraySize(orders.ticket) - 1;
         }
         openTime         = Max(openTime, orders.openTime[i]);
         openPrice       += orders.openPrice[i];
         grid.activeRisk += orders.risk     [i];
      }
      openPrice /= Abs(grid.level);                                              // avg(OpenPrice)
   }
   else if (grid.level < 0) {
      for (level=-1; level >= grid.level; level--) {                             // TODO: STOPLEVEL-Fehler im letzten Level abfangen und behandeln
         i = Grid.FindOpenPosition(level);
         if (i == -1) {
            if (!Grid.AddPosition(OP_SELL, level))
               return(false);
            if (!SaveStatus())                                                   // Status nach jeder Trade-Operation speichern, um das Ticket nicht zu verlieren,
               return(false);                                                    // wenn in einer der folgenden Operationen ein Fehler auftritt.
            i = ArraySize(orders.ticket) - 1;
         }
         openTime         = Max(openTime, orders.openTime[i]);
         openPrice       += orders.openPrice[i];
         grid.activeRisk += orders.risk     [i];
      }
      openPrice /= Abs(grid.level);                                              // avg(OpenPrice)
   }
   else {
      // grid.level == 0: es waren keine Positionen offen
   }


   // (2) valueAtRisk neuberechnen
   grid.valueAtRisk = -grid.stopsPL + grid.activeRisk; SS.Grid.ValueAtRisk();


   // (3) Ergebnis setzen
   if (grid.level != 0) {
      lpOpenTime  = openTime;
      lpOpenPrice = NormalizeDouble(openPrice, Digits);
   }

   return(IsNoError(catch("UpdateOpenPositions(3)")));
}


/**
 * Löscht alle gespeicherten Änderungen der Gridbasis und initialisiert sie mit dem angegebenen Wert.
 *
 * @param  datetime time  - Zeitpunkt
 * @param  double   value - neue Gridbasis
 *
 * @return double - die neue Gridbasis
 */
double Grid.BaseReset(datetime time, double value) {
   ArrayResize(grid.base.time,  0);
   ArrayResize(grid.base.value, 0);

   return(Grid.BaseChange(time, value));
}


/**
 * Speichert eine Änderung der Gridbasis.
 *
 * @param  datetime time  - Zeitpunkt der Änderung
 * @param  double   value - neue Gridbasis
 *
 * @return double - die neue Gridbasis
 */
double Grid.BaseChange(datetime time, double value) {
   value = NormalizeDouble(value, Digits);

   if (grid.maxLevelLong==0) /*&&*/ if (grid.maxLevelShort==0) {     // vor dem ersten ausgeführten Trade werden vorhandene Werte überschrieben
      ArrayResize(grid.base.time,  0);
      ArrayResize(grid.base.value, 0);
   }

   int size = ArraySize(grid.base.time);                             // ab dem ersten ausgeführten Trade werden neue Werte angefügt
   if (size == 0) {
      ArrayPushInt   (grid.base.time,  time );
      ArrayPushDouble(grid.base.value, value);
   }
   else {
      int minutes=time/MINUTE, lastMinutes=grid.base.time[size-1]/MINUTE;
      if (minutes == lastMinutes) {
         grid.base.time [size-1] = time;                             // Änderungen der aktuellen Minute werden mit neuem Wert überschrieben
         grid.base.value[size-1] = value;
      }
      else {
         ArrayPushInt   (grid.base.time,  time );
         ArrayPushDouble(grid.base.value, value);
      }
   }

   grid.base = value; SS.Grid.Base();
   return(value);
}


/**
 * Legt die angegebene Stop-Order in den Markt und fügt den Gridarrays deren Daten hinzu.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.AddOrder(int type, int level) {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("Grid.AddOrder(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_PROGRESSING)         return(_false(catch("Grid.AddOrder(2)   cannot add order for "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));


   if (firstTick && !firstTickConfirmed) {                           // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - Grid.AddOrder()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to submit a new "+ OperationTypeDescription(type) +" order now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.AddOrder(3)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) Order in den Markt legen
   /*ORDER_EXECUTION*/int oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket = SubmitStopOrder(type, level, oe);
   if (ticket == -1)
      return(false);


   // (2) Daten speichern
   //int    ticket       = oe.Ticket(oe);
   //int    level        = level;
   //double grid.base    = grid.base;

   int      pendingType  = type;
   datetime pendingTime  = oe.Time (oe);
   double   pendingPrice = oe.Price(oe);

   /*int*/  type         = OP_UNDEFINED;
   datetime openTime     = NULL;
   double   openPrice    = NULL;
   double   risk         = NULL;

   datetime closeTime    = NULL;
   double   closePrice   = NULL;
   double   stopLoss     = oe.StopLoss(oe);
   bool     closedBySL   = false;

   double   swap         = NULL;
   double   commission   = NULL;
   double   profit       = NULL;

   if (!Grid.PushData(ticket, level, grid.base, pendingType, pendingTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedBySL, swap, commission, profit))
      return(false);
   return(IsNoError(catch("Grid.AddOrder(5)")));
}


/**
 * Legt die angegebene Position in den Markt und fügt den Gridarrays deren Daten hinzu.
 *
 * @param  int type  - Ordertyp: OP_BUY | OP_SELL
 * @param  int level - Gridlevel der Position
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.AddPosition(int type, int level) {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_false(catch("Grid.AddPosition(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_STARTING)            return(_false(catch("Grid.AddPosition(2)   cannot add market position to "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - Grid.AddPosition()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to submit a Market "+ OperationTypeDescription(type) +" order now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.AddPosition(3)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) Position öffnen
   /*ORDER_EXECUTION*/int oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket = SubmitMarketOrder(type, level, oe);
   if (ticket == -1)
      return(false);


   // (2) Daten speichern
   //int    ticket       = ...                                       // unverändert
   //int    level        = ...                                       // unverändert
   //double grid.base    = ...                                       // unverändert

   int      pendingType  = OP_UNDEFINED;
   datetime pendingTime  = NULL;
   double   pendingPrice = NULL;

   //int    type         = ...                                       // unverändert
   datetime openTime     = oe.Time (oe);
   double   openPrice    = oe.Price(oe);

   datetime closeTime    = NULL;
   double   closePrice   = NULL;
   double   stopLoss     = oe.StopLoss(oe);
   bool     closedBySL   = false;

   double   swap         = oe.Swap      (oe);                        // falls Swap bereits bei OrderOpen gesetzt sein sollte
   double   commission   = oe.Commission(oe);
   double   profit       = NULL;
   double   risk         = CalculateActiveRisk(level, ticket, openPrice, swap, commission);

   if (!Grid.PushData(ticket, level, grid.base, pendingType, pendingTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedBySL, swap, commission, profit))
      return(false);

   return(IsNoError(catch("Grid.AddPosition(5)")));
}


/**
 * Justiert PendingOpenPrice() und StopLoss() der angegebenen Order und aktualisiert die Gridarrays.
 *
 * @param  int i - Index der Order in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.TrailPendingOrder(int i) {
   if (__STATUS__CANCELLED || IsLastError())    return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())       return(_false(catch("Grid.TrailPendingOrder(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_PROGRESSING)            return(_false(catch("Grid.TrailPendingOrder(2)   cannot trail order of "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("Grid.TrailPendingOrder(3)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (orders.type[i] != OP_UNDEFINED)          return(_false(catch("Grid.TrailPendingOrder(4)   cannot trail position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
   if (orders.closeTime[i] != 0)                return(_false(catch("Grid.TrailPendingOrder(5)   cannot trail cancelled order #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - Grid.TrailPendingOrder()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to modify the "+ OperationTypeDescription(orders.pendingType[i]) +" order #"+ orders.ticket[i] +" now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.TrailPendingOrder(6)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;

   double stopPrice   = grid.base +      orders.level[i]  * GridSize * Pips;
   double stopLoss    = stopPrice - Sign(orders.level[i]) * GridSize * Pips;
   color  markerColor = CLR_PENDING;
   int    flags       = NULL;
   double execution[];

   if (EQ(orders.pendingPrice[i], stopPrice)) /*&&*/ if (EQ(orders.stopLoss[i], stopLoss))
      return(_false(catch("Grid.TrailPendingOrder(7)   nothing to modify for #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   if (!OrderModifyEx(orders.ticket[i], stopPrice, stopLoss, NULL, NULL, markerColor, flags, execution))
      return(_false(SetLastError(stdlib_PeekLastError())));

   orders.gridBase    [i] = NormalizeDouble(grid.base, Digits);
   orders.pendingTime [i] = Round(execution[EXEC_TIME]);
   orders.pendingPrice[i] = NormalizeDouble(stopPrice, Digits);
   orders.stopLoss    [i] = NormalizeDouble(stopLoss,  Digits);

   return(IsNoError(catch("Grid.TrailPendingOrder(8)")));
}


/**
 * Streicht die angegebene Order beim Broker und entfernt sie aus den Datenarrays des Grids.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DeleteOrder(int ticket) {
   if (__STATUS__CANCELLED || IsLastError())                  return( false);
   if (IsTest()) /*&&*/ if (!IsTesting())                     return(_false(catch("Grid.DeleteOrder(1)", ERR_ILLEGAL_STATE)));
   if (status!=STATUS_PROGRESSING && status!=STATUS_STOPPING) return(_false(catch("Grid.DeleteOrder(2)   cannot delete order of "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   // Position in Datenarrays bestimmen
   int i = SearchIntArray(orders.ticket, ticket);
   if (i == -1)
      return(_false(catch("Grid.DeleteOrder(3)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Bestätigungsprompt bei Traderequest beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__ +" - Grid.DeleteOrder()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to cancel the "+ OperationTypeDescription(orders.pendingType[i]) +" order #"+ ticket +" now?", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.DeleteOrder(4)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;

   int    flags       = NULL;
   double execution[] = {NULL};

   if (!OrderDeleteEx(ticket, CLR_NONE, flags, execution))
      return(_false(SetLastError(stdlib_PeekLastError())));

   if (!Grid.DropTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.DeleteOrder(5)")));
}


/**
 * Fügt die angegebenen Daten den Datenarrays des Grids hinzu.
 *
 * @param  int      ticket
 * @param  int      level
 * @param  double   gridBase
 *
 * @param  int      pendingType
 * @param  datetime pendingTime
 * @param  double   pendingPrice
 *
 * @param  int      type
 * @param  datetime openTime
 * @param  double   openPrice
 * @param  double   risk
 *
 * @param  datetime closeTime
 * @param  double   closePrice
 * @param  double   stopLoss
 * @param  bool     closedBySL
 *
 * @param  double   swap
 * @param  double   commission
 * @param  double   profit
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.PushData(int ticket, int level, double gridBase, int pendingType, datetime pendingTime, double pendingPrice, int type, datetime openTime, double openPrice, double risk, datetime closeTime, double closePrice, double stopLoss, bool closedBySL, double swap, double commission, double profit) {
   return(Grid.SetData(-1, ticket, level, gridBase, pendingType, pendingTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedBySL, swap, commission, profit));
}


/**
 * Schreibt die angegebenen Daten an die angegebene Position der Gridarrays.
 *
 * @param  int      position - Gridposition: Ist dieser Wert -1 oder sind die Gridarrays zu klein, werden sie vergrößert.
 *
 * @param  int      ticket
 * @param  int      level
 * @param  double   gridBase
 *
 * @param  int      pendingType
 * @param  datetime pendingTime
 * @param  double   pendingPrice
 *
 * @param  int      type
 * @param  datetime openTime
 * @param  double   openPrice
 * @param  double   risk
 *
 * @param  datetime closeTime
 * @param  double   closePrice
 * @param  double   stopLoss
 * @param  bool     closedBySL
 *
 * @param  double   swap
 * @param  double   commission
 * @param  double   profit
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.SetData(int position, int ticket, int level, double gridBase, int pendingType, datetime pendingTime, double pendingPrice, int type, datetime openTime, double openPrice, double risk, datetime closeTime, double closePrice, double stopLoss, bool closedBySL, double swap, double commission, double profit) {
   if (position < -1)
      return(_false(catch("Grid.SetData(1)   illegal parameter position = "+ position, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int i=position, size=ArraySize(orders.ticket);

   if      (position ==     -1) i = ResizeArrays(    size+1) - 1;
   else if (position  > size-1) i = ResizeArrays(position+1) - 1;

   orders.ticket      [i] = ticket;
   orders.level       [i] = level;
   orders.gridBase    [i] = NormalizeDouble(gridBase, Digits);

   orders.pendingType [i] = pendingType;
   orders.pendingTime [i] = pendingTime;
   orders.pendingPrice[i] = NormalizeDouble(pendingPrice, Digits);

   orders.type        [i] = type;
   orders.openTime    [i] = openTime;
   orders.openPrice   [i] = NormalizeDouble(openPrice, Digits);
   orders.risk        [i] = NormalizeDouble(risk, 2);

   orders.closeTime   [i] = closeTime;
   orders.closePrice  [i] = NormalizeDouble(closePrice, Digits);
   orders.stopLoss    [i] = NormalizeDouble(stopLoss, Digits);
   orders.closedBySL  [i] = closedBySL;

   orders.swap        [i] = NormalizeDouble(swap,       2);
   orders.commission  [i] = NormalizeDouble(commission, 2); if (type != OP_UNDEFINED) { grid.commission = orders.commission[i]; SS.LotSize(); }
   orders.profit      [i] = NormalizeDouble(profit,     2);

   return(!IsError(catch("Grid.SetData(2)")));
}


/**
 * Entfernt die Daten des angegebenen Tickets aus den Datenarrays des Grids.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DropTicket(int ticket) {
   // Position in Datenarrays bestimmen
   int i = SearchIntArray(orders.ticket, ticket);
   if (i == -1)
      return(_false(catch("Grid.DropTicket(1)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   // Einträge entfernen
   ArraySpliceInts   (orders.ticket,       i, 1);
   ArraySpliceInts   (orders.level,        i, 1);
   ArraySpliceDoubles(orders.gridBase,     i, 1);

   ArraySpliceInts   (orders.pendingType,  i, 1);
   ArraySpliceInts   (orders.pendingTime,  i, 1);
   ArraySpliceDoubles(orders.pendingPrice, i, 1);

   ArraySpliceInts   (orders.type,         i, 1);
   ArraySpliceInts   (orders.openTime,     i, 1);
   ArraySpliceDoubles(orders.openPrice,    i, 1);
   ArraySpliceDoubles(orders.risk,         i, 1);

   ArraySpliceInts   (orders.closeTime,    i, 1);
   ArraySpliceDoubles(orders.closePrice,   i, 1);
   ArraySpliceDoubles(orders.stopLoss,     i, 1);
   ArraySpliceBools  (orders.closedBySL,   i, 1);

   ArraySpliceDoubles(orders.swap,         i, 1);
   ArraySpliceDoubles(orders.commission,   i, 1);
   ArraySpliceDoubles(orders.profit,       i, 1);

   return(IsNoError(catch("Grid.DropTicket(2)")));
}


/**
 * Sucht eine offene Position des angegebenen Levels und gibt deren Index in den Datenarrays des Grids zurück.
 * Je Level kann es maximal eine offene Position geben.
 *
 * @param  int level - Level der zu suchenden Position
 *
 * @return int - Index der gefundenen Position oder -1, wenn keine offene Position des angegebenen Levels gefunden wurde
 */
int Grid.FindOpenPosition(int level) {
   if (level == 0) return(_int(-1, catch("Grid.FindOpenPosition()   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int size = ArraySize(orders.ticket);

   for (int i=size-1; i >= 0; i--) {                                 // rückwärts iterieren, um Zeit zu sparen
      if (orders.level[i] != level)
         continue;                                                   // Order muß zum Level gehören
      if (orders.type[i] == OP_UNDEFINED)
         continue;                                                   // Order darf nicht pending sein
      if (orders.closeTime[i] != 0)
         continue;                                                   // Position darf nicht geschlossen sein
      return(i);
   }
   return(-1);
}


/**
 * Legt eine Stop-Order in den Markt.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 * @param  int oe[]  - Ausführungsdetails
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int SubmitStopOrder(int type, int level, int oe[]) {
   if (__STATUS__CANCELLED || IsLastError())                  return(-1);
   if (IsTest()) /*&&*/ if (!IsTesting())                     return(_int(-1, catch("SubmitStopOrder(1)", ERR_ILLEGAL_STATE)));
   if (status!=STATUS_PROGRESSING && status!=STATUS_STARTING) return(_int(-1, catch("SubmitStopOrder(2)   cannot submit stop order for "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (type == OP_BUYSTOP) {
      if (level <= 0) return(_int(-1, catch("SubmitStopOrder(3)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELLSTOP) {
      if (level >= 0) return(_int(-1, catch("SubmitStopOrder(4)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("SubmitStopOrder(5)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   double   stopPrice   = grid.base +      level  * GridSize * Pips;
   double   slippage    = NULL;
   double   stopLoss    = stopPrice - Sign(level) * GridSize * Pips;
   double   takeProfit  = NULL;
   int      magicNumber = CreateMagicNumber(level);
   datetime expires     = NULL;
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));
   color    markerColor = CLR_PENDING;
   int      oeFlags     = NULL;

   /*
   #define ODM_NONE     0     // - keine Anzeige -
   #define ODM_STOPS    1     // Pending,       ClosedBySL
   #define ODM_PYRAMID  2     // Pending, Open,             Closed
   #define ODM_ALL      3     // Pending, Open, ClosedBySL, Closed
   */
   if (orderDisplayMode == ODM_NONE)
      markerColor = CLR_NONE;

   if (IsLastError())
      return(-1);

   int ticket = OrderSendEx(Symbol(), type, LotSize, stopPrice, slippage, stopLoss, takeProfit, comment, magicNumber, expires, markerColor, oeFlags, oe);
   if (ticket == -1)
      return(_int(-1, SetLastError(stdlib_PeekLastError())));

   if (IsError(catch("SubmitStopOrder(6)")))
      return(-1);
   return(ticket);
}


/**
 * Öffnet eine Position zum aktuellen Preis.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 * @param  int oe[]  - Ausführungsdetails
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int SubmitMarketOrder(int type, int level, int oe[]) {
   if (__STATUS__CANCELLED || IsLastError()) return(-1);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(_int(-1, catch("SubmitMarketOrder(1)", ERR_ILLEGAL_STATE)));
   if (status != STATUS_STARTING)            return(_int(-1, catch("SubmitMarketOrder(2)   cannot submit market order for "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (type == OP_BUY) {
      if (level <= 0) return(_int(-1, catch("SubmitMarketOrder(3)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELL) {
      if (level >= 0) return(_int(-1, catch("SubmitMarketOrder(4)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("SubmitMarketOrder(5)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   double   price       = NULL;
   double   slippage    = 0.1;
   double   stopLoss    = grid.base + (level-Sign(level)) * GridSize * Pips;
   double   takeProfit  = NULL;
   int      magicNumber = CreateMagicNumber(level);
   datetime expires     = NULL;
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));
   color    markerColor = ifInt(level > 0, CLR_LONG, CLR_SHORT);
   int      oeFlags     = NULL;

   /*
   #define ODM_NONE     0     // - keine Anzeige -
   #define ODM_STOPS    1     // Pending,       ClosedBySL
   #define ODM_PYRAMID  2     // Pending, Open,             Closed
   #define ODM_ALL      3     // Pending, Open, ClosedBySL, Closed
   */
   if (orderDisplayMode == ODM_NONE)
      markerColor = CLR_NONE;

   if (IsLastError())
      return(-1);

   // TODO: in ResumeSequence() kann STOPLEVEL-Verletzung auftreten

   int ticket = OrderSendEx(Symbol(), type, LotSize, price, slippage, stopLoss, takeProfit, comment, magicNumber, expires, markerColor, oeFlags, oe);
   if (ticket == -1)
      return(_int(-1, SetLastError(stdlib_PeekLastError())));

   if (IsError(catch("SubmitMarketOrder(6)")))
      return(-1);
   return(ticket);
}


/**
 * Generiert eine neue Sequenz-ID.
 *
 * @return int - Sequenz-ID im Bereich 1000-16383 (14 bit)
 */
int CreateSequenceId() {
   MathSrand(GetTickCount());
   int id;
   while (id < 2000) {
      id = MathRand();
   }
   return(id >> 1);                                                  // Das abschließende Shiften halbiert den Wert und wir wollen mindestens eine 4-stellige ID haben.
}


/**
 * Generiert für den angegebenen Gridlevel eine MagicNumber.
 *
 * @param  int level - Gridlevel
 *
 * @return int - MagicNumber oder -1, falls ein Fehler auftrat
 */
int CreateMagicNumber(int level) {
   if (sequenceId < 1000) return(_int(-1, catch("CreateMagicNumber(1)   illegal sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));
   if (level == 0)        return(_int(-1, catch("CreateMagicNumber(2)   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));

   // Für bessere Obfuscation ist die Reihenfolge der Werte [ea,level,sequence] und nicht [ea,sequence,level]. Dies wären aufeinander folgende Werte.
   int ea       = STRATEGY_ID & 0x3FF << 22;                         // 10 bit (Bits größer 10 löschen und auf 32 Bit erweitern) | in MagicNumber: Bits 23-32
       level    = Abs(level);                                        // Wert in MagicNumber ist immer positiv
       level    = level & 0xFF << 14;                                //  8 bit (Bits größer 8 löschen und auf 22 Bit erweitern)  | in MagicNumber: Bits 15-22
   int sequence = sequenceId  & 0x3FFF;                              // 14 bit (Bits größer 14 löschen                           | in MagicNumber: Bits  1-14

   return(ea + level + sequence);
}


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @return int - Fehlerstatus
 */
int ShowStatus() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   string msg, str.error;

   if (__STATUS__CANCELLED) {
      str.error = StringConcatenate("  [", ErrorDescription(ERR_CANCELLED_BY_USER), "]");
   }
   else if (IsLastError()) {
      status    = STATUS_DISABLED;
      str.error = StringConcatenate("  [", ErrorDescription(last_error), "]");
   }
   else if (__STATUS__INVALID_INPUT) {
      str.error = StringConcatenate("  [", ErrorDescription(ERR_INVALID_INPUT), "]");
   }

   switch (status) {
      case STATUS_UNINITIALIZED: msg = StringConcatenate(":  ", str.test, "sequence not initialized"                                                            ); break;
      case STATUS_WAITING:       msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " waiting"                                                   ); break;
      case STATUS_STARTING:      msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " starting at level ", grid.level, "  ", str.grid.maxLevel   ); break;
      case STATUS_PROGRESSING:   msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " progressing at level ", grid.level, "  ", str.grid.maxLevel); break;
      case STATUS_STOPPING:      msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " stopping at level ", grid.level, "  ", str.grid.maxLevel   ); break;
      case STATUS_STOPPED:       msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " stopped at level ", grid.level, "  ", str.grid.maxLevel    ); break;
      case STATUS_DISABLED:      msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " disabled"                                                  ); break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ status, ERR_RUNTIME_ERROR));
   }

   msg = StringConcatenate(__NAME__, msg, str.error,                                                 NL,
                                                                                                     NL,
                           "Grid:            ", GridSize, " pip", str.grid.base, str.grid.direction, NL,
                           "LotSize:         ", str.LotSize,                                         NL,
                           str.startConditions,                                                             // enthält NL, wenn gesetzt
                           str.stopConditions,                                                              // enthält NL, wenn gesetzt
                           "Stops:           ", str.grid.stops, " ", str.grid.stopsPL,               NL,
                           "Breakeven:   ", str.grid.breakeven,                                      NL,
                           "Profit/Loss:    ", str.grid.totalPL, "  ", str.grid.plStatistics,        NL);

   // einige Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));
   if (__WHEREAMI__ == FUNC_INIT)
      WindowRedraw();


   // für Fernbedienung unsichtbaren Status im Chart speichern
   string label = StringConcatenate(__NAME__, ".status");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("ShowStatus(2)"));
      ObjectSet(label, OBJPROP_TIMEFRAMES, EMPTY);                   // hidden on all timeframes
   }
   ObjectSetText(label, StringConcatenate(Sequence.ID, "|", status), 1);


   if (IsError(catch("ShowStatus(3)"))) {
      status = STATUS_DISABLED;
      return(last_error);
   }
   return(NO_ERROR);
}


/**
 * ShowStatus(): Aktualisiert alle in ShowStatus() verwendeten String-Repräsentationen.
 */
void SS.All() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   SS.Test();
   SS.SequenceId();
   SS.Grid.Base();
   SS.Grid.Direction();
   SS.LotSize();
   SS.StartStopConditions();
   SS.Grid.MaxLevel();
   SS.Grid.Stops();
   SS.Grid.TotalPL();
   SS.Grid.MaxProfit();
   SS.Grid.MaxDrawdown();
   SS.Grid.ValueAtRisk();
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von test.
 */
void SS.Test() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   if (test) str.test = "test ";
   else      str.test = "";
}


/**
 * ShowStatus(): Aktualisiert die Anzeige der Sequenz-ID in der Titelzeile des Strategy Testers.
 */
void SS.SequenceId() {
   if (IsTesting()) {
      int hWndTester = GetTesterWindow();
      if (hWndTester == 0)
         return(_ZERO(SetLastError(stdlib_PeekLastError())));

      string text = StringConcatenate("Tester - SR.", sequenceId);

      if (!SetWindowTextA(hWndTester, text))
         catch("SS.SequenceId() ->user32::SetWindowTextA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
   }
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.base.
 */
void SS.Grid.Base() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   if (ArraySize(grid.base.time) == 0)
      return;

   str.grid.base = StringConcatenate(" @ ", NumberToStr(grid.base, PriceFormat));
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.direction.
 */
void SS.Grid.Direction() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.direction = StringConcatenate("  (", GridDirectionDescription(grid.direction), ")");

   SS.Grid.Breakeven();                                              // je nach GridDirection ändert sich das Anzeigeformat von str.grid.breakeven;
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von LotSize.
 */
void SS.LotSize() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.LotSize = StringConcatenate(NumberToStr(LotSize, ".+"), " lot = ", DoubleToStr(GridSize * PipValue(LotSize) - grid.commission, 2), "/stop");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von start/stopConditions.
 */
void SS.StartStopConditions() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.startConditions = "";
   str.stopConditions  = "";

   if (start.conditions) /*&&*/ if (ArraySize(orders.ticket)==0)
      str.startConditions = StringConcatenate("Start:           ", StartConditions, NL);

   if (stop.conditions)
      str.stopConditions  = StringConcatenate("Stop:            ", StopConditions,  NL);
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.maxLevelLong und grid.maxLevelShort.
 */
void SS.Grid.MaxLevel() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   string strLong, strShort;

   if (grid.direction != D_SHORT) {
      strLong = grid.maxLevelLong;
      if (grid.maxLevelLong > 0)
         strLong = StringConcatenate("+", strLong);
   }
   if (grid.direction != D_LONG)
      strShort = grid.maxLevelShort;

   str.grid.maxLevel = StringConcatenate("(", strLong, ifString(grid.direction==D_BIDIR, "/", ""), strShort, ")");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentationen von grid.stops und grid.stopsPL.
 */
void SS.Grid.Stops() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.stops = StringConcatenate(grid.stops, " stop", ifString(grid.stops==1, "", "s"));

   // Anzeige wird nicht vor der ersten ausgestoppten Position gesetzt
   if (grid.stops > 0)
      str.grid.stopsPL = StringConcatenate("= ", DoubleToStr(grid.stopsPL, 2));
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.totalPL.
 */
void SS.Grid.TotalPL() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   // Anzeige wird nicht vor der ersten offenen Position gesetzt
   if (grid.maxLevelLong-grid.maxLevelShort != 0)
      str.grid.totalPL = NumberToStr(grid.totalPL, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.maxProfit.
 */
void SS.Grid.MaxProfit() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxProfit = NumberToStr(grid.maxProfit, "+.2");
   SS.Grid.ProfitLossStatistics();
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.maxDrawdown.
 */
void SS.Grid.MaxDrawdown() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxDrawdown = NumberToStr(grid.maxDrawdown, "+.2");
   SS.Grid.ProfitLossStatistics();
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.valueAtRisk.
 */
void SS.Grid.ValueAtRisk() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.valueAtRisk = NumberToStr(-grid.valueAtRisk, "+.2");     // Wert ist positiv, Anzeige ist negativ
   SS.Grid.ProfitLossStatistics();
}


/**
 * ShowStatus(): Aktualisiert die kombinierte String-Repräsentation der P/L-Statistik.
 */
void SS.Grid.ProfitLossStatistics() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   // Anzeige wird nicht vor der ersten offenen Position gesetzt
   if (grid.maxLevelLong-grid.maxLevelShort != 0)
      str.grid.plStatistics = StringConcatenate("(", str.grid.maxProfit, "/", str.grid.maxDrawdown, "/", str.grid.valueAtRisk, ")");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.breakevenLong und grid.breakevenShort.
 */
void SS.Grid.Breakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   string strLong, strShort;

   if (grid.direction != D_SHORT) {
      if (grid.maxLevelLong-grid.maxLevelShort == 0) strLong  = "-";    // Anzeige wird nicht vor der ersten offenen Position gesetzt
      else                                           strLong  = DoubleToStr(grid.breakevenLong,  PipDigits);
   }
   if (grid.direction != D_LONG) {
      if (grid.maxLevelLong-grid.maxLevelShort == 0) strShort = "-";    // Anzeige wird nicht vor der ersten offenen Position gesetzt
      else                                           strShort = DoubleToStr(grid.breakevenShort, PipDigits);
   }

   str.grid.breakeven = StringConcatenate(strLong, ifString(grid.direction==D_BIDIR, " / ", ""), strShort);
}


/**
 * Berechnet die aktuellen Breakeven-Werte und aktualisiert den Indikator.
 *
 * @param  datetime time - Zeitpunkt innerhalb der Sequenz                    (default: aktueller Zeitpunkt)
 * @param  int      i    - Index innerhalb der Gridarrays zu diesem Zeitpunkt (default: letztes Element    )
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.CalculateBreakeven(datetime time=0, int i=-1) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);
   if (grid.maxLevelLong==0) /*&&*/ if (grid.maxLevelShort==0)                // nicht vorm ersten ausgeführten Trade
      return(true);

   if (time == 0)
      time = TimeCurrent();

   int sizeOfTickets = ArraySize(orders.ticket);
   if (i >= sizeOfTickets)
      return(_false(catch("Grid.CalculateBreakeven(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (i < 0)
      i = sizeOfTickets - 1;


   double distance1, distance2;

   /*
   (1) Breakeven-Punkt auf aktueller Seite:
   ----------------------------------------
        totalPL = realizedPL + floatingPL

   =>         0 = realizedPL + floatingPL                                     // Soll: totalPL = 0.00, also floatingPL = -realizedPL

   =>         0 = stopsPL + closedPL + floatingPL                             // realizedPL = stopsPL + closedPL

   =>  -stopsPL = closedPL + floatingPL                                       // closedPL muß nach PositionReopen wieder als 0 angenommen werden
   */
   distance1 = ProfitToDistance(-grid.stopsPL, grid.level, true, time, i);    // stopsPL reicht zur Berechnung aus
   if (EQ(distance1, 0))
      return(false);


   if (grid.level == 0) {
      grid.breakevenLong  = grid.base + distance1*Pips;                       // activeRisk=0, valueAtRisk=-stopsPL (siehe 2)
      grid.breakevenShort = grid.base - distance1*Pips;                       // Abstand der Breakeven-Punkte ist gleich, eine Berechnung reicht
   }
   else {
      /*
      (2) Breakeven-Punkt auf gegenüberliegender Seite:
      -------------------------------------------------
              stopsPL = -valueAtRisk                                          // wenn die Sequenz Level 0 triggert, entspricht stopsPL = -valueAtRisk

      =>  valueAtRisk = -stopsPL                                              // analog zu (1)
      */
      if (grid.direction == D_BIDIR) {
         distance2 = ProfitToDistance(grid.valueAtRisk, 0, false, time, i);   // Level 0
         if (EQ(distance2, 0))
            return(false);
      }

      if (grid.level > 0) {
         grid.breakevenLong  = grid.base + distance1*Pips;
         grid.breakevenShort = grid.base - distance2*Pips;
      }
      else /*grid.level < 0*/ {
         grid.breakevenLong  = grid.base + distance2*Pips;
         grid.breakevenShort = grid.base - distance1*Pips;
      }
   }

   if (!Grid.DrawBreakeven(time))
      return(false);
   SS.Grid.Breakeven();

   return(IsNoError(catch("Grid.CalculateBreakeven()")));
}


/**
 * Aktualisiert den Breakeven-Indikator.
 *
 * @param  datetime time   - Zeitpunkt der zu zeichnenden Werte (default: aktueller Zeitpunkt)
 * @param  int      status - Status zu diesem Zeitpunkt (default: aktueller Status)
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DrawBreakeven(datetime time=NULL, int timeStatus=NULL) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);
   if (EQ(grid.breakevenLong, 0))                                                // ohne initialisiertes Breakeven sofortige Rückkehr
      return(true);

   static double   last.grid.breakevenLong, last.grid.breakevenShort;            // Daten der zuletzt gezeichneten Indikatorwerte
   static datetime last.startTimeLong, last.startTimeShort, last.drawingTime;
   static int      last.status;


   if (time == NULL)
      time = TimeCurrent();
   datetime now = time;

   if (timeStatus == NULL)
      timeStatus = status;
   int nowStatus = timeStatus;

   int breakeven.Color      = Breakeven.Color;
   int breakeven.Background = false;

   if (last.status == STATUS_STOPPED) {
      breakeven.Color      = Aqua;
      breakeven.Background = true;
   }


   if (last.drawingTime != 0) {
      // (1) Long
      if (grid.direction != D_SHORT) {                                           // "SR.5609.L 1.53024 -> 1.52904 (2012.01.23 10:19:35)"
         string labelL = StringConcatenate("SR.", sequenceId, ".beL ", DoubleToStr(last.grid.breakevenLong, Digits), " -> ", DoubleToStr(grid.breakevenLong, Digits), " (", TimeToStr(last.startTimeLong, TIME_FULL), ")");
         if (ObjectCreate(labelL, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenLong, now, grid.breakevenLong)) {
            ObjectSet(labelL, OBJPROP_RAY,   false               );
            ObjectSet(labelL, OBJPROP_WIDTH, breakeven.Width     );
            ObjectSet(labelL, OBJPROP_COLOR, breakeven.Color     );
            ObjectSet(labelL, OBJPROP_BACK,  breakeven.Background);

            if (EQ(last.grid.breakevenLong, grid.breakevenLong)) last.startTimeLong = last.drawingTime;
            else                                                 last.startTimeLong = now;
         }
         else {
            GetLastError();                                                      // ERR_OBJECT_ALREADY_EXISTS
            ObjectSet(labelL, OBJPROP_TIME2, now);                               // vorhandene Trendlinien werden möglichst verlängert (verhindert Erzeugung unzähliger gleicher Objekte)
         }
      }

      // (2) Short
      if (grid.direction != D_LONG) {
         string labelS = StringConcatenate("SR.", sequenceId, ".beS ", DoubleToStr(last.grid.breakevenShort, Digits), " -> ", DoubleToStr(grid.breakevenShort, Digits), " (", TimeToStr(last.startTimeShort, TIME_FULL), ")");
         if (ObjectCreate(labelS, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenShort, now, grid.breakevenShort)) {
            ObjectSet(labelS, OBJPROP_RAY,   false               );
            ObjectSet(labelS, OBJPROP_WIDTH, breakeven.Width     );
            ObjectSet(labelS, OBJPROP_COLOR, breakeven.Color     );
            ObjectSet(labelS, OBJPROP_BACK,  breakeven.Background);

            if (EQ(last.grid.breakevenLong, grid.breakevenLong)) last.startTimeLong = last.drawingTime;
            else                                                 last.startTimeLong = now;
         }
         else {
            GetLastError();                                                      // ERR_OBJECT_ALREADY_EXISTS
            ObjectSet(labelS, OBJPROP_TIME2, now);                               // vorhandene Trendlinien werden möglichst verlängert (verhindert Erzeugung unzähliger gleicher Objekte)
         }
      }
   }
   else {
      last.startTimeLong  = now;
      last.startTimeShort = now;
   }

   last.grid.breakevenLong  = grid.breakevenLong;
   last.grid.breakevenShort = grid.breakevenShort;
   last.drawingTime         = now;
   last.status              = nowStatus;

   return(IsNoError(catch("Grid.DrawBreakeven()")));
}


/**
 * Färbt den Breakeven-Indikator neu ein.
 */
void RecolorBreakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   if (ObjectsTotal(OBJ_TREND) > 0) {
      string label, labelBe=StringConcatenate("SR.", sequenceId, ".be");

      for (int i=ObjectsTotal()-1; i>=0; i--) {
         label = ObjectName(i);
         if (ObjectType(label)==OBJ_TREND) /*&&*/ if (StringStartsWith(label, labelBe)) {
            if (breakeven.Width == 0) ObjectSet(label, OBJPROP_TIMEFRAMES, EMPTY          );    // hidden on all timeframes
            else                      ObjectSet(label, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);    // visible on all timeframes
         }
      }
   }
   catch("RecolorBreakeven()");
}


/**
 * Berechnet den notwendigen Abstand von der Gridbasis, um im angegebenen Level den angegebenen Gewinn zu erzielen (bzw. Verlust auszugleichen).
 *
 * @param  double   profit             - zu erzielender Gewinn
 * @param  int      level              - Gridlevel
 * @param  bool     checkOpenPositions - ob die Entry-Preise offener Positionen berücksichtigen werden sollen (bezieht Slippage ins Ergebnis ein)
 * @param  datetime time               - wenn checkOpenPositions=TRUE: Zeitpunkt innerhalb der Sequenz
 * @param  int      i                  - wenn checkOpenPositions=TRUE: Index innerhalb der Gridarrays
 *
 * @return double - Abstand in Pips oder 0, wenn ein Fehler auftrat
 *
 *
 *  NOTE:
 *  -----
 *  Eine direkte Berechnung anhand der zugrunde liegenden quadratischen Gleichung ist praktisch nicht ausreichend,
 *  denn sie unterschlägt auftretende Slippage. Für ein korrektes Ergebnis wird statt dessen der notwendige Abstand
 *  vom tatsächlichen Durchschnittspreis der Positionen ermittelt und in einen Abstand von der Gridbasis umgerechnet.
 */
double ProfitToDistance(double profit, int level, bool checkOpenPositions, datetime time, int i) {
   profit = NormalizeDouble(MathAbs(profit), 2);

   double gridBaseDistance, avgPrice, risk, bePrice, beDistance, nextStop, nextEntry;
   bool   entryStop, exitStop;


   // (1) Level == 0: Um einen Verlust auszugleichen, muß immer der nächste Entry-Stop (Level +1/-1) getriggert werden.
   if (level == 0) {
      if (EQ(profit, 0))
         return(0);
      //debug("ProfitToDistance.0(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  entryStop=1 ->");
      gridBaseDistance = ProfitToDistance(profit, 1, false, time, i);                                    // Sollte die Grid-Direction hier falsch sein, ändert das nichts
                                                                                                         // am Abstand des Ergebnisses von der Gridbasis.
      //debug("ProfitToDistance.0(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  -> distance="+ NumberToStr(gridBaseDistance, ".1") +" pip");
   }


   // (2) Level != 0: Je nach Durchschnitts- und Breakeven-Preis das Triggern weiterer Stops berücksichtigen
   else {
      avgPrice   = CalculateAverageOpenPrice(level, checkOpenPositions, time, i, risk);
         if (EQ(avgPrice, 0)) return(0);
      beDistance = profit/PipValue(Abs(level) * LotSize);                                                // für profit benötigter Abstand von avgPrice in Pip
      bePrice    = NormalizeDouble(avgPrice + Sign(level)*beDistance*Pip, Digits);                       // Breakeven-Preis

      // Testen, ob der Breakeven-Preis innerhalb des Levels liegt.
      nextEntry  = NormalizeDouble(grid.base + (level+Sign(level))*GridSize*Pips, Digits);
      nextStop   = NormalizeDouble(nextEntry       -2*Sign(level) *GridSize*Pips, Digits);

      if    (level > 0)  { entryStop = GT(bePrice, nextEntry); exitStop = LT(bePrice, nextStop); }
      else /*level < 0*/ { entryStop = LT(bePrice, nextEntry); exitStop = GT(bePrice, nextStop); }

      if (entryStop) {                                                                                   // Level vergrößert sich, Verlust bleibt konstant
         //debug("ProfitToDistance.1(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  avgPrice="+ NumberToStr(avgPrice, PriceFormat) +"  beDistance="+ NumberToStr(beDistance, ".1") +" pip" +"  entryStop="+ entryStop +" ->");
         level           += Sign(level);
         gridBaseDistance = ProfitToDistance(profit, level, checkOpenPositions, time, i);
         //debug("ProfitToDistance.1(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  -> distance="+ NumberToStr(gridBaseDistance, ".1") +" pip");
      }
      else if (exitStop) {                                                                               // Level verringert und Verlust vergrößert sich
         if (Abs(level) == 1)
            return(_NULL(catch("ProfitToDistance()   illegal calculation of exit stop in level 1", ERR_RUNTIME_ERROR)));

         //debug("ProfitToDistance.2(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  avgPrice="+ NumberToStr(avgPrice, PriceFormat) +"  beDistance="+ NumberToStr(beDistance, ".1") +" pip" +"  exitStop="+ exitStop +" ->");
         level           -= Sign(level);
         profit          += risk;
         gridBaseDistance = ProfitToDistance(profit, level, checkOpenPositions, time, i);
         //debug("ProfitToDistance.2(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  -> distance="+ NumberToStr(gridBaseDistance, ".1") +" pip");
      }
      else {
         gridBaseDistance = MathAbs(bePrice - grid.base)/Pip;
         //debug("ProfitToDistance.3(profit="+ DoubleToStr(profit, 2) +", level="+ level +")  avgPrice="+ NumberToStr(avgPrice, PriceFormat) +"  distance="+ NumberToStr(gridBaseDistance, ".1") +" pip");
      }
   }

   return(NormalizeDouble(gridBaseDistance, 1));
}


/**
 * Berechnet den theoretischen Profit im angegebenen Abstand von der Gridbasis.
 *
 * @param  double distance - Abstand in Pips von der Gridbasis
 *
 * @return double - Profit oder 0, wenn ein Fehler auftrat
 *
 *
 *  NOTE: Benötigt *nicht* die Gridbasis, die GridSize ist ausreichend.
 *  -----
 */
double DistanceToProfit(double distance) {
   if (LE(distance, GridSize)) {
      if (LT(distance, 0))
         return(_ZERO(catch("DistanceToProfit()  invalid parameter distance = "+ NumberToStr(distance, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));
      return(0);
   }
   /*
   d         = Distanz in Pip
   gs        = GridSize
   n         = Level
   pipV(n)   = PipValue von Level n
   profit(d) = profit(exp) + profit(lin)                             // Summe aus exponentiellem (ganzer Level) und linearem Anteil (partieller nächster Level)

   Für Sequenzstart an der Gridbasis gilt:
   ---------------------------------------
   Ganzer Level:      expProfit(n.0) = n * (n+1)/2 * gs * pipV(1)    // am Ende des Levels
   Partieller Level:  linProfit(n.x) =         0.x * gs * pipV(n+1)
   PipValue:          pipV(n)        = n * pipV(LotSize)

   profit(d) = expProfit((int) d) + linProfit(d % gs)
   */
   int    gs   = GridSize;
   double d    = distance - gs;                                      // GridSize abziehen, da Sequenzstart erst bei Gridbase + GridSize erfolgt
   int    n    = (d+0.000000001) / gs;
   double pipV = PipValue(LotSize);

   double expProfit = n * (n+1)/2 * gs * pipV;
   double linProfit = MathModFix(d, gs) * (n+1) * pipV;
   double profit    = expProfit + linProfit;

   //debug("DistanceToProfit()   gs="+ gs +"  d="+ d +"  n="+ n +"  exp="+ DoubleToStr(expProfit, 2) +"  lin="+ DoubleToStr(linProfit, 2) +"  profit="+ NumberToStr(profit, ".+"));
   return(profit);
}


/**
 * Speichert temporäre Werte des Sequenzstatus im Chart, sodaß der volle Status nach einem Recompile oder Terminal-Restart daraus wiederhergestellt werden kann.
 * Die temporären Werte umfassen die Parameter, die zur Ermittlung des vollen Dateinamens der Statusdatei erforderlich sind und jene User-Eingaben, die nicht
 * in der Statusdatei gespeichert sind (aktuelle Display-Modes, Farben und Strichstärken) sowie die Flags __STATUS__CANCELLED und __STATUS__INVALID_INPUT.
 *
 * @return int - Fehlerstatus
 */
int StoreStickyStatus() {
   string label = StringConcatenate(__NAME__, ".sticky.Sequence.ID");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, ifString(sequenceId==0, "0", Sequence.ID), 1);        // String: "0" (STATUS_UNINITIALIZED) oder Sequence.ID (enthält ggf. "T")

   if (StringLen(StringTrim(Sequence.StatusLocation)) > 0) {
      label = StringConcatenate(__NAME__, ".sticky.Sequence.StatusLocation");
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
      ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                        // hidden on all timeframes
      ObjectSetText(label, Sequence.StatusLocation, 1);
   }

   label = StringConcatenate(__NAME__, ".sticky.startStopDisplayMode");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", startStopDisplayMode), 1);

   label = StringConcatenate(__NAME__, ".sticky.orderDisplayMode");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", orderDisplayMode), 1);

   label = StringConcatenate(__NAME__, ".sticky.Breakeven.Color");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", Breakeven.Color), 1);

   label = StringConcatenate(__NAME__, ".sticky.breakeven.Width");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", breakeven.Width), 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS__CANCELLED");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS__CANCELLED), 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS__INVALID_INPUT");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS__INVALID_INPUT), 1);

   return(catch("StoreStickyStatus()"));
}


/**
 * Restauriert die im Chart gespeicherten Sequenzdaten.
 *
 * @return bool - ob die ID einer initialisierten Sequenz gefunden wurde (gespeicherte Sequenz kann im STATUS_UNINITIALIZED sein)
 */
bool RestoreStickyStatus() {
   string label, strValue;
   bool   idFound;

   label = StringConcatenate(__NAME__, ".sticky.Sequence.ID");
   if (ObjectFind(label) == 0) {
      strValue = StringToUpper(StringTrim(ObjectDescription(label)));
      if (StringLeft(strValue, 1) == "T") {
         test     = true; SS.Test();
         strValue = StringRight(strValue, -1);
      }
      if (!StringIsDigit(strValue))
         return(_false(catch("RestoreStickyStatus(1)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
      int iValue = StrToInteger(strValue);
      if (iValue == 0) {
         status  = STATUS_UNINITIALIZED;
         idFound = false;
      }
      else if (iValue < 1000 || iValue > 16383) {
         return(_false(catch("RestoreStickyStatus(2)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
      }
      else {
         sequenceId  = InstanceId(iValue); SS.SequenceId();
         Sequence.ID = ifString(IsTest(), "T", "") + sequenceId;
         status      = STATUS_WAITING;
         idFound     = true;
      }

      label = StringConcatenate(__NAME__, ".sticky.Sequence.StatusLocation");
      if (ObjectFind(label) == 0) {
         Sequence.StatusLocation = StringTrim(ObjectDescription(label));
      }

      label = StringConcatenate(__NAME__, ".sticky.startStopDisplayMode");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreStickyStatus(3)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (!IntInArray(startStopDisplayModes, iValue))
            return(_false(catch("RestoreStickyStatus(4)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         startStopDisplayMode = iValue;
      }

      label = StringConcatenate(__NAME__, ".sticky.orderDisplayMode");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreStickyStatus(5)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (!IntInArray(orderDisplayModes, iValue))
            return(_false(catch("RestoreStickyStatus(6)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         orderDisplayMode = iValue;
      }

      label = StringConcatenate(__NAME__, ".sticky.Breakeven.Color");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreStickyStatus(7)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (iValue < CLR_NONE || iValue > C'255,255,255')
            return(_false(catch("RestoreStickyStatus(8)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\" (0x"+ IntToHexStr(iValue) +")", ERR_INVALID_CONFIG_PARAMVALUE)));
         Breakeven.Color = iValue;
      }

      label = StringConcatenate(__NAME__, ".sticky.breakeven.Width");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreStickyStatus(9)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (iValue < 0 || iValue > 5)
            return(_false(catch("RestoreStickyStatus(10)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         breakeven.Width = iValue;
      }

      label = StringConcatenate(__NAME__, ".sticky.__STATUS__CANCELLED");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(11)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS__CANCELLED = StrToInteger(strValue) != 0;
      }

      label = StringConcatenate(__NAME__, ".sticky.__STATUS__INVALID_INPUT");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(12)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS__INVALID_INPUT = StrToInteger(strValue) != 0;
      }
   }

   return(idFound && IsNoError(catch("RestoreStickyStatus(13)")));
}


/**
 * Löscht alle im Chart gespeicherten Sequenzdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearStickyStatus() {
   string label, prefix=StringConcatenate(__NAME__, ".sticky.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearStickyStatus()"));
}


/**
 * Ermittelt die aktuell laufenden Sequenzen.
 *
 * @param  int ids[] - Array zur Aufnahme der gefundenen Sequenz-IDs
 *
 * @return bool - ob mindestens eine laufende Sequenz gefunden wurde
 */
bool GetRunningSequences(int ids[]) {
   ArrayResize(ids, 0);
   int id;

   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: während des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;

      if (IsMyOrder()) {
         id = OrderMagicNumber() & 0x3FFF;                           // 14 Bits (Bits 1-14) => sequenceId
         if (!IntInArray(ids, id))
            ArrayPushInt(ids, id);
      }
   }

   if (ArraySize(ids) != 0)
      return(ArraySort(ids));
   return(false);
}


/**
 * Ob die aktuell selektierte Order zu dieser Strategie gehört. Wird eine Sequenz-ID angegeben, wird zusätzlich überprüft,
 * ob die Order zur angegebenen Sequenz gehört.
 *
 * @param  int sequenceId - ID einer Sequenz (default: NULL)
 *
 * @return bool
 */
bool IsMyOrder(int sequenceId = NULL) {
   if (OrderSymbol() == Symbol()) {
      if (OrderMagicNumber() >> 22 == STRATEGY_ID) {
         if (sequenceId == NULL)
            return(true);
         return(sequenceId == OrderMagicNumber() & 0x3FFF);          // 14 Bits (Bits 1-14) => sequenceId
      }
   }
   return(false);
}


/**
 * Validiert und setzt nur die in der Konfiguration angegebene Sequenz-ID.
 *
 * @param bool interactive - ob fehlerhafte Parameter interaktiv korrigiert werden können
 *
 * @return bool - ob eine gültige Sequenz-ID gefunden und restauriert wurde
 */
bool ValidateConfiguration.ID(bool interactive) {
   bool parameterChange = (UninitializeReason() == REASON_PARAMETERS);
   if (parameterChange)
      interactive = true;

   string strValue = StringToUpper(StringTrim(Sequence.ID));

   if (StringLen(strValue) == 0)
      return(false);

   if (StringLeft(strValue, 1) == "T") {
      test     = true; SS.Test();
      strValue = StringRight(strValue, -1);
   }
   if (!StringIsDigit(strValue))
      return(_false(HandleConfigError("ValidateConfiguration.ID(1)", "Illegal input parameter Sequence.ID = \""+ Sequence.ID +"\"", interactive)));

   int iValue = StrToInteger(strValue);
   if (iValue < 1000 || iValue > 16383)
      return(_false(HandleConfigError("ValidateConfiguration.ID(2)", "Illegal input parameter Sequence.ID = \""+ Sequence.ID +"\"", interactive)));

   sequenceId  = InstanceId(iValue); SS.SequenceId();
   Sequence.ID = ifString(IsTest(), "T", "") + sequenceId;

   return(true);
}


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @param bool interactive - ob fehlerhafte Parameter interaktiv korrigiert werden können
 *
 * @return bool - ob die Konfiguration gültig ist
 */
bool ValidateConfiguration(bool interactive) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   bool parameterChange = (UninitializeReason() == REASON_PARAMETERS);
   if (parameterChange)
      interactive = true;


   // (1) Sequence.ID
   if (parameterChange) {
      if (status == STATUS_UNINITIALIZED) {
         if (Sequence.ID != last.Sequence.ID) {    return(_false(HandleConfigError("ValidateConfiguration(1)", "Loading of another sequence not yet implemented!", interactive)));
            if (ValidateConfiguration.ID(interactive)) {
               // TODO: neue Sequenz laden
            }
         }
      }
      else {
         if (Sequence.ID == "")                    return(_false(HandleConfigError("ValidateConfiguration(2)", "Sequence.ID missing!", interactive)));
         if (Sequence.ID != last.Sequence.ID) {    return(_false(HandleConfigError("ValidateConfiguration(3)", "Loading of another sequence not yet implemented!", interactive)));
            if (ValidateConfiguration.ID(interactive)) {
               // TODO: neue Sequenz laden
            }
         }
      }
   }
   else if (StringLen(Sequence.ID) == 0) {         // wir müssen im STATUS_UNINITIALIZED sein (sequenceId = 0)
      if (sequenceId != 0)                         return(_false(catch("ValidateConfiguration(4)   illegal parameter Sequence.ID = \""+ Sequence.ID +"\" (sequenceId="+ sequenceId +")", ERR_RUNTIME_ERROR)));
   }
   else {} // wenn gesetzt, ist sie schon validiert und die Sequenz geladen (sonst landen wir nicht hier)


   // (2) GridDirection
   if (parameterChange) {
      if (GridDirection != last.GridDirection)
         if (status != STATUS_UNINITIALIZED)       return(_false(HandleConfigError("ValidateConfiguration(5)", "Cannot change GridDirection of "+ StatusDescription(status) +" sequence", interactive)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   }
   string directions[] = {"Bidirectional", "Long", "Short", "L+S"};
   string strValue     = StringToLower(StringTrim(StringReplace(StringReplace(StringReplace(GridDirection, "+", ""), "&", ""), " ", "")) +"b");    // b = default
   switch (StringGetChar(strValue, 0)) {
      case 'l': if (StringStartsWith(strValue, "longshort") || StringStartsWith(strValue, "ls"))
                                                   return(_false(HandleConfigError("ValidateConfiguration(6)", "Grid mode Long+Short not yet implemented.", interactive)));
                grid.direction = D_LONG;  break;
      case 's': grid.direction = D_SHORT; break;
      case 'b': grid.direction = D_BIDIR; break;
      default:                                     return(_false(HandleConfigError("ValidateConfiguration(7)", "Invalid parameter GridDirection = \""+ GridDirection +"\"", interactive)));
   }
   GridDirection = directions[grid.direction]; SS.Grid.Direction();


   // (3) GridSize
   if (parameterChange) {
      if (GridSize != last.GridSize)
         if (status != STATUS_UNINITIALIZED)       return(_false(HandleConfigError("ValidateConfiguration(8)", "Cannot change GridSize of "+ StatusDescription(status) +" sequence", interactive)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   }
   if (GridSize < 1)                               return(_false(HandleConfigError("ValidateConfiguration(9)", "Invalid parameter GridSize = "+ GridSize, interactive)));


   // (4) LotSize
   if (parameterChange) {
      if (NE(LotSize, last.LotSize))
         if (status != STATUS_UNINITIALIZED)       return(_false(HandleConfigError("ValidateConfiguration(10)", "Cannot change LotSize of "+ StatusDescription(status) +" sequence", interactive)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   }
   if (LE(LotSize, 0))                             return(_false(HandleConfigError("ValidateConfiguration(11)", "Invalid parameter LotSize = "+ NumberToStr(LotSize, ".+"), interactive)));
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT );
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT );
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                             return(_false(catch("ValidateConfiguration(12)   symbol=\""+ Symbol() +"\"", error)));
   if (LT(LotSize, minLot))                        return(_false(HandleConfigError("ValidateConfiguration(13)", "Invalid parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MinLot="+  NumberToStr(minLot, ".+" ) +")", interactive)));
   if (GT(LotSize, maxLot))                        return(_false(HandleConfigError("ValidateConfiguration(14)", "Invalid parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MaxLot="+  NumberToStr(maxLot, ".+" ) +")", interactive)));
   if (NE(MathModFix(LotSize, lotStep), 0))        return(_false(HandleConfigError("ValidateConfiguration(15)", "Invalid parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", interactive)));
   SS.LotSize();


   // (5) StartConditions:  "@limit(1.33) && @time(12:00)" AND-verknüpft
   // ------------------------------------------------------------------
   //  @limit(1.33)     oder  1.33                                            // shortkey nicht implementiert
   //  @time(12:00)     oder  12:00          // Validierung unzureichend      // shortkey nicht implementiert
   if (parameterChange)
      if (StartConditions != last.StartConditions)
         if (status!=STATUS_UNINITIALIZED && status!=STATUS_WAITING)
                                                   return(_false(HandleConfigError("ValidateConfiguration(16)", "Cannot change StartConditions of "+ StatusDescription(status) +" sequence", interactive)));
   start.conditions      = false;
   start.limit.condition = false;
   start.time.condition  = false;

   // (5.1) StartConditions in einzelne Ausdrücke zerlegen
   string exprs[], expr, elems[], key, value;
   double dValue;
   int    time, sizeOfElems, sizeOfExprs=Explode(StartConditions, "&&", exprs, NULL);

   // (5.2) jeden Ausdruck parsen und validieren
   for (int i=0; i < sizeOfExprs; i++) {
      expr = StringToLower(StringTrim(exprs[i]));
      if (StringLen(expr) == 0) {
         if (sizeOfExprs > 1)                      return(_false(HandleConfigError("ValidateConfiguration(17)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
         break;
      }
      if (StringGetChar(expr, 0) != '@')           return(_false(HandleConfigError("ValidateConfiguration(18)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
      if (Explode(expr, "(", elems, NULL) != 2)    return(_false(HandleConfigError("ValidateConfiguration(19)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
      if (!StringEndsWith(elems[1], ")"))          return(_false(HandleConfigError("ValidateConfiguration(20)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
      key   = StringTrim(elems[0]);
      value = StringTrim(StringLeft(elems[1], -1));
      if (StringLen(value) == 0)                   return(_false(HandleConfigError("ValidateConfiguration(21)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
      //debug("()   key="+ StringRightPad("\""+ key +"\"", 9, " ") +"   value=\""+ value +"\"");

      if (key == "@limit") {
         if (!StringIsNumeric(value))              return(_false(HandleConfigError("ValidateConfiguration(22)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
         dValue = StrToDouble(value);
         if (LE(dValue, 0))                        return(_false(HandleConfigError("ValidateConfiguration(23)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
         start.limit.condition = true;
         start.limit.value     = dValue;
         exprs[i] = key +"("+ DoubleToStr(dValue, PipDigits) +")";
      }
      else if (key == "@time") {
         time = StrToTime(value);
         if (IsError(GetLastError()))              return(_false(HandleConfigError("ValidateConfiguration(24)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
         // TODO: Validierung von @time unzureichend
         start.time.condition = true;
         start.time.value     = time;
         exprs[i] = key +"("+ TimeToStr(time) +")";
      }
      else                                         return(_false(HandleConfigError("ValidateConfiguration(25)", "Invalid parameter StartConditions = \""+ StartConditions +"\"", interactive)));
      start.conditions = true;
   }
   if (start.conditions) StartConditions = JoinStrings(exprs, " && ");
   else                  StartConditions = "";
   //debug("()   StartConditions = \""+ StartConditions +"\"");


   // (6) StopConditions:  "@limit(1.33) || @time(12:00) || @profit(1234.00) || @profit(20%)" OR-verknüpft
   // ----------------------------------------------------------------------------------------------------
   //  @limit(1.33)     oder  1.33                                            // shortkey nicht implementiert
   //  @time(12:00)     oder  12:00          // Validierung unzureichend      // shortkey nicht implementiert
   //  @profit(1234.00)
   //  @profit(20%)     oder  20%                                             // shortkey nicht implementiert
   if (parameterChange)
      if (StopConditions != last.StopConditions)
         if (status == STATUS_STOPPED)             return(_false(HandleConfigError("ValidateConfiguration(26)", "Cannot change StopConditions of "+ StatusDescription(status) +" sequence", interactive)));

   stop.conditions              = false;
   stop.limit.condition         = false;
   stop.time.condition          = false;
   stop.profitAbs.condition     = false;
   stop.profitPercent.condition = false;

   // (6.1) StopConditions in einzelne Ausdrücke zerlegen
   sizeOfExprs = Explode(StopConditions, "||", exprs, NULL);

   // (6.2) jeden Ausdruck parsen und validieren
   for (i=0; i < sizeOfExprs; i++) {
      expr = StringToLower(StringTrim(exprs[i]));
      if (StringLen(expr) == 0) {
         if (sizeOfExprs > 1)                      return(_false(HandleConfigError("ValidateConfiguration(27)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         break;
      }
      if (StringGetChar(expr, 0) != '@')           return(_false(HandleConfigError("ValidateConfiguration(28)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
      if (Explode(expr, "(", elems, NULL) != 2)    return(_false(HandleConfigError("ValidateConfiguration(29)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
      if (!StringEndsWith(elems[1], ")"))          return(_false(HandleConfigError("ValidateConfiguration(30)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
      key   = StringTrim(elems[0]);
      value = StringTrim(StringLeft(elems[1], -1));
      if (StringLen(value) == 0)                   return(_false(HandleConfigError("ValidateConfiguration(31)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
      //debug("()   key="+ StringRightPad("\""+ key +"\"", 9, " ") +"   value=\""+ value +"\"");

      if (key == "@limit") {
         if (!StringIsNumeric(value))              return(_false(HandleConfigError("ValidateConfiguration(32)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         dValue = StrToDouble(value);
         if (LE(dValue, 0))                        return(_false(HandleConfigError("ValidateConfiguration(33)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         stop.limit.condition = true;
         stop.limit.value     = dValue;
         exprs[i] = key +"("+ DoubleToStr(dValue, PipDigits) +")";
      }
      else if (key == "@time") {
         time = StrToTime(value);
         if (IsError(GetLastError()))              return(_false(HandleConfigError("ValidateConfiguration(34)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         // TODO: Validierung von @time unzureichend
         stop.time.condition = true;
         stop.time.value     = time;
         exprs[i] = key +"("+ TimeToStr(time) +")";
      }
      else if (key == "@profit") {
         sizeOfElems = Explode(value, "%", elems, NULL);
         if (sizeOfElems > 2)                      return(_false(HandleConfigError("ValidateConfiguration(35)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         value = StringTrim(elems[0]);
         if (StringLen(value) == 0)                return(_false(HandleConfigError("ValidateConfiguration(36)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         if (!StringIsNumeric(value))              return(_false(HandleConfigError("ValidateConfiguration(37)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
         dValue = StrToDouble(value);
         if (sizeOfElems == 1) {
            if (LT(dValue, 0))                     return(_false(HandleConfigError("ValidateConfiguration(38)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
            stop.profitAbs.condition = true;
            stop.profitAbs.value     = dValue;
            exprs[i] = key +"("+ NumberToStr(dValue, ".2") +")";
         }
         else {
            if (LE(dValue, 0))                     return(_false(HandleConfigError("ValidateConfiguration(39)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
            stop.profitPercent.condition = true;
            stop.profitPercent.value     = dValue;
            exprs[i] = key +"("+ NumberToStr(dValue, ".+") +"%)";
         }
      }
      else                                         return(_false(HandleConfigError("ValidateConfiguration(40)", "Invalid parameter StopConditions = \""+ StopConditions +"\"", interactive)));
      stop.conditions = true;
   }
   if (stop.conditions) StopConditions = JoinStrings(exprs, " || ");
   else                 StopConditions = "";
   //debug("()   StopConditions = \""+ StopConditions +"\"");


   // (7) Breakeven.Color
   if (Breakeven.Color == 0xFF000000)                                   // kann vom Terminal falsch gesetzt worden sein
      Breakeven.Color = CLR_NONE;
   if (Breakeven.Color < CLR_NONE || Breakeven.Color > C'255,255,255')  // kann nur nicht-interaktiv falsch reinkommen
                                                   return(_false(HandleConfigError("ValidateConfiguration(41)", "Invalid parameter Breakeven.Color = 0x"+ IntToHexStr(Breakeven.Color), interactive)));

   // (8) __STATUS__INVALID_INPUT zurücksetzen
   if (interactive)
      __STATUS__INVALID_INPUT = false;

   return(IsNoError(catch("ValidateConfiguration(42)")));
}


/**
 * "Exception-Handler" für ungültige Input-Parameter. Je nach Laufzeitumgebung wird der Fehler weitergereicht oder zur Korrektur aufgefordert.
 *
 * @param  string location  - Ort, an dem der Fehler auftrat
 * @param  string msg       - Fehlermeldung
 * @param  bool interactive - ob der Fehler interaktiv behandelt werden kann
 *
 * @return int - der resultierende Fehlerstatus
 */
int HandleConfigError(string location, string msg, bool interactive) {
   if (IsTesting())
      interactive = false;
   if (!interactive)
      return(catch(location +"   "+ msg, ERR_INVALID_CONFIG_PARAMVALUE));

   if (__LOG) log(location +"   "+ msg, ERR_INVALID_INPUT);
   ForceSound("chord.wav");
   int button = ForceMessageBox(__NAME__ +" - ValidateConfiguration()", msg, MB_ICONERROR|MB_RETRYCANCEL);

   __STATUS__INVALID_INPUT = true;

   if (button == IDRETRY)
      __STATUS__RELAUNCH_INPUT = true;

   return(NO_ERROR);
}


/**
 * Speichert die aktuelle Konfiguration zwischen, um sie bei Fehleingaben nach Parameteränderungen restaurieren zu können.
 *
 * @return void
 */
void StoreConfiguration(bool save=true) {
   static string   _Sequence.ID;
   static string   _Sequence.StatusLocation;
   static string   _GridDirection;
   static int      _GridSize;
   static double   _LotSize;
   static string   _StartConditions;
   static string   _StopConditions;
   static color    _Breakeven.Color;

   static int      _grid.direction;

   static bool     _start.conditions;
   static bool     _start.limit.condition;
   static double   _start.limit.value;
   static bool     _start.time.condition;
   static datetime _start.time.value;

   static bool     _stop.conditions;
   static bool     _stop.limit.condition;
   static double   _stop.limit.value;
   static bool     _stop.time.condition;
   static datetime _stop.time.value;
   static bool     _stop.profitAbs.condition;
   static double   _stop.profitAbs.value;
   static bool     _stop.profitPercent.condition;
   static double   _stop.profitPercent.value;

   if (save) {
      _Sequence.ID                  = StringConcatenate(Sequence.ID,             "");  // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
      _Sequence.StatusLocation      = StringConcatenate(Sequence.StatusLocation, "");
      _GridDirection                = StringConcatenate(GridDirection,           "");
      _GridSize                     = GridSize;
      _LotSize                      = LotSize;
      _StartConditions              = StringConcatenate(StartConditions,         "");
      _StopConditions               = StringConcatenate(StopConditions,          "");
      _Breakeven.Color              = Breakeven.Color;

      _grid.direction               = grid.direction;

      _start.conditions             = start.conditions;
      _start.limit.condition        = start.limit.condition;
      _start.limit.value            = start.limit.value;
      _start.time.condition         = start.time.condition;
      _start.time.value             = start.time.value;

      _stop.conditions              = stop.conditions;
      _stop.limit.condition         = stop.limit.condition;
      _stop.limit.value             = stop.limit.value;
      _stop.time.condition          = stop.time.condition;
      _stop.time.value              = stop.time.value;
      _stop.profitAbs.condition     = stop.profitAbs.condition;
      _stop.profitAbs.value         = stop.profitAbs.value;
      _stop.profitPercent.condition = stop.profitPercent.condition;
      _stop.profitPercent.value     = stop.profitPercent.value;
   }
   else {
      Sequence.ID                   = _Sequence.ID;
      Sequence.StatusLocation       = _Sequence.StatusLocation;
      GridDirection                 = _GridDirection;
      GridSize                      = _GridSize;
      LotSize                       = _LotSize;
      StartConditions               = _StartConditions;
      StopConditions                = _StopConditions;
      Breakeven.Color               = _Breakeven.Color;

      grid.direction                = _grid.direction;

      start.conditions              = _start.conditions;
      start.limit.condition         = _start.limit.condition;
      start.limit.value             = _start.limit.value;
      start.time.condition          = _start.time.condition;
      start.time.value              = _start.time.value;

      stop.conditions               = _stop.conditions;
      stop.limit.condition          = _stop.limit.condition;
      stop.limit.value              = _stop.limit.value;
      stop.time.condition           = _stop.time.condition;
      stop.time.value               = _stop.time.value;
      stop.profitAbs.condition      = _stop.profitAbs.condition;
      stop.profitAbs.value          = _stop.profitAbs.value;
      stop.profitPercent.condition  = _stop.profitPercent.condition;
      stop.profitPercent.value      = _stop.profitPercent.value;
   }
}


/**
 * Restauriert eine zuvor gespeicherte Konfiguration.
 *
 * @return void
 */
void RestoreConfiguration() {
   StoreConfiguration(false);
}


/**
 * Initialisiert die Dateinamensvariablen der Statusdatei mit den Ausgangswerten einer neuen Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool InitStatusLocation() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (sequenceId == 0)                      return(_false(catch("InitStatusLocation(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   if      (IsTesting()) status.directory = "presets\\";
   else if (IsTest())    status.directory = "presets\\tester\\";
   else                  status.directory = "presets\\"+ ShortAccountCompany() +"\\";

   status.fileName = StringConcatenate(StringToLower(StdSymbol()), ".SR.", sequenceId, ".set");

   Sequence.StatusLocation = "";
   return(true);
}


/**
 * Aktualisiert die Dateinamensvariablen der Statusdatei.  Nur die Variablen werden modifiziert, nicht die Datei.
 * SaveStatus() erkennt die Änderung selbst und verschiebt die Datei automatisch.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatusLocation() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (sequenceId == 0)                      return(_false(catch("UpdateStatusLocation(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   // TODO: Prüfen, ob status.fileName existiert und ggf. aktualisieren

   string startDate = "";

   if      (IsTesting()) status.directory = "presets\\";
   else if (IsTest())    status.directory = "presets\\tester\\";
   else {
      status.directory = "presets\\"+ ShortAccountCompany() +"\\";

      if (grid.maxLevelLong-grid.maxLevelShort > 0) {
         startDate        = TimeToStr(orders.openTime[0], TIME_DATE);
         status.directory = status.directory + startDate +"\\";
      }
   }

   Sequence.StatusLocation = startDate;
   return(true);
}


/**
 * Restauriert anhand der verfügbaren Informationen Ort und Namen der Statusdatei, wird nur aus RestoreStatus() heraus aufgerufen.
 *
 * @return bool - Erfolgsstatus
 */
bool ResolveStatusLocation() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);


   // (1) Location-Variablen zurücksetzen
   string location = StringTrim(Sequence.StatusLocation);
   InitStatusLocation();

   string filesDirectory  = StringConcatenate(TerminalPath(), ifString(IsTesting(), "\\tester", "\\experts"), "\\files\\");
   string statusDirectory = GetMqlStatusDirectory();
   string directory, subdirs[], subdir, file="";


   while (true) {
      // (2.1) mit StatusLocation: das angegebene Unterverzeichnis durchsuchen
      if (location != "") {
         directory = StringConcatenate(filesDirectory, statusDirectory, StdSymbol(), "\\", location, "\\");
         if (ResolveStatusLocation.FindFile(directory, file))
            break;
         if (IsLastError()) return( false);
                            return(_false(catch("ResolveStatusLocation(1)   invalid Sequence.StatusLocation = \""+ location +"\" (status file not found)", ERR_FILE_NOT_FOUND)));
      }

      // (2.2) ohne StatusLocation: zuerst Basisverzeichnis durchsuchen...
      directory = StringConcatenate(filesDirectory, statusDirectory);
      if (ResolveStatusLocation.FindFile(directory, file))
         break;
      if (IsLastError()) return(false);


      // (2.3) ohne StatusLocation: ...dann Unterverzeichnisse des jeweiligen Symbols durchsuchen
      directory = StringConcatenate(directory, StdSymbol(), "\\");
      int size = FindFileNames(directory +"*", subdirs, FF_DIRSONLY);
      if (size == -1)
         return(_false(SetLastError(stdlib_PeekLastError())));
      //debug("ResolveStatusLocation()   subdirs="+ StringsToStr(subdirs, NULL));

      for (int i=0; i < size; i++) {
         subdir = StringConcatenate(directory, subdirs[i], "\\");
         if (ResolveStatusLocation.FindFile(subdir, file)) {
            directory = subdir;
            location  = subdirs[i];
            break;
         }
         if (IsLastError()) return(false);
      }
      if (StringLen(file) > 0)
         break;
      return(_false(catch("ResolveStatusLocation(2)   status file not found", ERR_FILE_NOT_FOUND)));
   }
   //debug("ResolveStatusLocation()  directory=\""+ directory +"\"  location=\""+ location +"\"  file=\""+ file +"\"");

   status.directory        = StringRight(directory, -StringLen(filesDirectory));
   status.fileName         = file;
   Sequence.StatusLocation = location;
   //debug("ResolveStatusLocation()  status.directory=\""+ status.directory +"\"  Sequence.StatusLocation=\""+ Sequence.StatusLocation +"\"  status.fileName=\""+ status.fileName +"\"");
   return(true);
}


/**
 * Durchsucht das angegebene Verzeichnis nach einer passenden Statusdatei und schreibt das Ergebnis in die angegebene Variable.
 *
 * @param  string directory - vollständiger Name des zu durchsuchenden Verzeichnisses
 * @param  string lpFile    - Zeiger auf Variable zur Aufnahme des gefundenen Dateinamens
 *
 * @return bool - Erfolgsstatus
 */
bool ResolveStatusLocation.FindFile(string directory, string &lpFile) {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (sequenceId == 0)                      return(_false(catch("ResolveStatusLocation.FindFile(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   if (!StringEndsWith(directory, "\\"))
      directory = StringConcatenate(directory, "\\");

   string sequenceName = StringConcatenate("SR.", sequenceId, ".");
   string pattern      = StringConcatenate(directory, "*", sequenceName, "*set");
   string files[];

   int size = FindFileNames(pattern, files, FF_FILESONLY);                       // Dateien suchen, die den Sequenznamen enthalten und mit "set" enden
   if (size == -1)
      return(_false(SetLastError(stdlib_PeekLastError())));

   for (int i=0; i < size; i++) {
      if (!StringIStartsWith(files[i], sequenceName))
         if (!StringIContains(files[i], StringConcatenate(".", sequenceName)))
            continue;
      if (StringIEndsWith(files[i], ".set")) {
         lpFile = files[i];                                                      // Abbruch nach Fund der ersten .set-Datei
         return(true);
      }
   }

   lpFile = "";
   return(false);
}


/**
 * Gibt den MQL-Namen der Statusdatei der Sequenz zurück (unterhalb ".\files\").
 *
 * @return string
 */
string GetMqlStatusFileName() {
   return(StringConcatenate(status.directory, status.fileName));
}


/**
 * Gibt den vollständigen Namen der Statusdatei der Sequenz zurück (für Windows-Dateifunktionen).
 *
 * @return string
 */
string GetFullStatusFileName() {
   if (IsTesting()) return(StringConcatenate(TerminalPath(), "\\tester\\files\\",  GetMqlStatusFileName()));
   else             return(StringConcatenate(TerminalPath(), "\\experts\\files\\", GetMqlStatusFileName()));
}


/**
 * Gibt den MQL-Namen des Statusverzeichnisses der Sequenz zurück (unterhalb ".\files\").
 *
 * @return string - Verzeichnisname (mit einem Back-Slash endend)
 */
string GetMqlStatusDirectory() {
   return(status.directory);
}


/**
 * Gibt den vollständigen Namen des Statusverzeichnisses der Sequenz zurück (für Windows-Dateifunktionen).
 *
 * @return string - Verzeichnisname (mit einem Back-Slash endend)
 */
string GetFullStatusDirectory() {
   if (IsTesting()) return(StringConcatenate(TerminalPath(), "\\tester\\files\\",  GetMqlStatusDirectory()));
   else             return(StringConcatenate(TerminalPath(), "\\experts\\files\\", GetMqlStatusDirectory()));
}


/**
 * Speichert den aktuellen Status der Instanz, um später die nahtlose Re-Initialisierung im selben oder einem anderen Terminal
 * zu ermöglichen.
 *
 * @return bool - Erfolgsstatus
 */
bool SaveStatus() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (sequenceId == 0)                      return(_false(catch("SaveStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));
   if (IsTest()) /*&&*/ if (!IsTesting())    return(true);

   static int counter;
   if (IsTesting()) /*&&*/ if (counter > 0) /*&&*/ if (status!=STATUS_STOPPED)   // im Tester Ausführung nur beim ersten Aufruf und nach Stop
      return(true);                                                              // TODO: STATUS_STOPPED mit Check for deinit ersetzen
   counter++;

   /*
   Speichernotwendigkeit der einzelnen Variablen
   ---------------------------------------------
   int      status;                    // nein: kann aus Orderdaten und offenen Positionen restauriert werden
   bool     test;                      // nein: wird aus Statusdatei ermittelt

   datetime instanceStartTime;         // ja
   double   instanceStartPrice;        // ja
   double   sequenceStartEquity;       // ja

   datetime sequenceStartTimes [];     // ja
   double   sequenceStartPrices[];     // ja

   datetime sequenceStopTimes [];      // ja
   double   sequenceStopPrices[];      // ja

   bool     start.*.condition;         // nein: wird aus StartConditions abgeleitet
   bool     stop.*.condition;          // nein: wird aus StopConditions abgeleitet

   int      ignorePendingOrders  [];   // optional (wenn belegt)
   int      ignoreOpenPositions  [];   // optional (wenn belegt)
   int      ignoreClosedPositions[];   // optional (wenn belegt)

   datetime grid.base.time [];         // ja
   double   grid.base.value[];         // ja
   double   grid.base;                 // nein: wird aus Gridbase-History restauriert

   int      grid.level;                // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelLong;         // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelShort;        // nein: kann aus Orderdaten restauriert werden

   int      grid.stops;                // nein: kann aus Orderdaten restauriert werden
   double   grid.stopsPL;              // nein: kann aus Orderdaten restauriert werden
   double   grid.closedPL;             // nein: kann aus Orderdaten restauriert werden
   double   grid.floatingPL;           // nein: kann aus offenen Positionen restauriert werden
   double   grid.totalPL;              // nein: kann aus stopsPL, closedPL und floatingPL restauriert werden
   double   grid.activeRisk;           // nein: kann aus Orderdaten restauriert werden
   double   grid.valueAtRisk;          // nein: kann aus Orderdaten restauriert werden

   double   grid.maxProfit;            // ja
   datetime grid.maxProfitTime;        // ja
   double   grid.maxDrawdown;          // ja
   datetime grid.maxDrawdownTime;      // ja

   double   grid.breakevenLong;        // nein: wird mit dem aktuellen TickValue als Näherung neu berechnet
   double   grid.breakevenShort;       // nein: wird mit dem aktuellen TickValue als Näherung neu berechnet

   int      orders.ticket      [];     // ja
   int      orders.level       [];     // ja
   double   orders.gridBase    [];     // ja
   int      orders.pendingType [];     // ja
   datetime orders.pendingTime [];     // ja
   double   orders.pendingPrice[];     // ja
   int      orders.type        [];     // ja
   datetime orders.openTime    [];     // ja
   double   orders.openPrice   [];     // ja
   double   orders.risk        [];     // ja
   datetime orders.closeTime   [];     // ja
   double   orders.closePrice  [];     // ja
   double   orders.stopLoss    [];     // ja
   bool     orders.closedBySL  [];     // ja
   double   orders.swap        [];     // ja
   double   orders.commission  [];     // ja
   double   orders.profit      [];     // ja
   */

   // (1) Dateiinhalt zusammenstellen
   string lines[]; ArrayResize(lines, 0);

   // (1.1) Input-Parameter
   ArrayPushString(lines, /*string*/   "Account="+      ShortAccountCompany() +":"+ GetAccountNumber()   );
   ArrayPushString(lines, /*string*/   "Symbol="                 +             Symbol()                  );
   ArrayPushString(lines, /*string*/   "Sequence.ID="            +             Sequence.ID               );
   if (StringLen(Sequence.StatusLocation) > 0)
   ArrayPushString(lines, /*string*/   "Sequence.StatusLocation="+             Sequence.StatusLocation   );
   ArrayPushString(lines, /*string*/   "GridDirection="          +             GridDirection             );
   ArrayPushString(lines, /*int   */   "GridSize="               +             GridSize                  );
   ArrayPushString(lines, /*double*/   "LotSize="                + NumberToStr(LotSize, ".+")            );
   if (StringLen(StartConditions) > 0)
   ArrayPushString(lines, /*string*/   "StartConditions="        +             StartConditions           );
   if (StringLen(StartConditions) > 0)
   ArrayPushString(lines, /*string*/   "StopConditions="         +             StopConditions            );

   // (1.2) Laufzeit-Variablen
   ArrayPushString(lines, /*datetime*/ "rt.instanceStartTime="   +             instanceStartTime         );
   ArrayPushString(lines, /*double*/   "rt.instanceStartPrice="  + NumberToStr(instanceStartPrice, ".+") );
   ArrayPushString(lines, /*double*/   "rt.sequenceStartEquity=" + NumberToStr(sequenceStartEquity, ".+"));

      string values[]; ArrayResize(values, 0);
      int size = ArraySize(sequenceStartTimes);
      for (int i=0; i < size; i++)
         ArrayPushString(values, StringConcatenate(sequenceStartTimes[i], "|", NumberToStr(sequenceStartPrices[i], ".+")));
      if (size == 0)
         ArrayPushString(values, "0|0");
   ArrayPushString(lines, /*string*/   "rt.sequenceStarts="       + JoinStrings(values, ","));

      ArrayResize(values, 0);
      size = ArraySize(sequenceStopTimes);
      for (i=0; i < size; i++)
         ArrayPushString(values, StringConcatenate(sequenceStopTimes[i], "|", NumberToStr(sequenceStopPrices[i], ".+")));
      if (size == 0)
         ArrayPushString(values, "0|0");
   ArrayPushString(lines, /*string*/   "rt.sequenceStops="        + JoinStrings(values, ","));

   if (ArraySize(ignorePendingOrders) > 0)
   ArrayPushString(lines, /*string*/   "rt.ignorePendingOrders="  + JoinInts(ignorePendingOrders, ","));
   if (ArraySize(ignoreOpenPositions) > 0)
   ArrayPushString(lines, /*string*/   "rt.ignoreOpenPositions="  + JoinInts(ignoreOpenPositions, ","));
   if (ArraySize(ignoreClosedPositions) > 0)
   ArrayPushString(lines, /*string*/   "rt.ignoreClosedPositions="+ JoinInts(ignoreClosedPositions, ","));

   ArrayPushString(lines, /*double*/   "rt.grid.maxProfit="       + NumberToStr(grid.maxProfit, ".+"));
   ArrayPushString(lines, /*datetime*/ "rt.grid.maxProfitTime="   +             grid.maxProfitTime   + ifString(grid.maxProfitTime  ==0, "", " ("+ TimeToStr(grid.maxProfitTime,   TIME_FULL) +")"));
   ArrayPushString(lines, /*double*/   "rt.grid.maxDrawdown="     + NumberToStr(grid.maxDrawdown, ".+")  );
   ArrayPushString(lines, /*datetime*/ "rt.grid.maxDrawdownTime=" +             grid.maxDrawdownTime + ifString(grid.maxDrawdownTime==0, "", " ("+ TimeToStr(grid.maxDrawdownTime, TIME_FULL) +")"));

      ArrayResize(values, 0);
      size = ArraySize(grid.base.time);
      for (i=0; i < size; i++)
         ArrayPushString(values, StringConcatenate(grid.base.time[i], "|", NumberToStr(grid.base.value[i], ".+")));
      if (size == 0)
         ArrayPushString(values, "0|0");
   ArrayPushString(lines, /*string*/   "rt.grid.base="           + JoinStrings(values, ","));

   size = ArraySize(orders.ticket);
   for (i=0; i < size; i++) {
      int      ticket       = orders.ticket      [i];
      int      level        = orders.level       [i];
      double   gridBase     = orders.gridBase    [i];
      int      pendingType  = orders.pendingType [i];
      datetime pendingTime  = orders.pendingTime [i];
      double   pendingPrice = orders.pendingPrice[i];
      int      type         = orders.type        [i];
      datetime openTime     = orders.openTime    [i];
      double   openPrice    = orders.openPrice   [i];
      double   risk         = orders.risk        [i];
      datetime closeTime    = orders.closeTime   [i];
      double   closePrice   = orders.closePrice  [i];
      double   stopLoss     = orders.stopLoss    [i];
      bool     closedBySL   = orders.closedBySL  [i];
      double   swap         = orders.swap        [i];
      double   commission   = orders.commission  [i];
      double   profit       = orders.profit      [i];
      ArrayPushString(lines, StringConcatenate("rt.order.", i, "=", ticket, ",", level, ",", NumberToStr(NormalizeDouble(gridBase, Digits), ".+"), ",", pendingType, ",", pendingTime, ",", NumberToStr(NormalizeDouble(pendingPrice, Digits), ".+"), ",", type, ",", openTime, ",", NumberToStr(NormalizeDouble(openPrice, Digits), ".+"), ",", NumberToStr(NormalizeDouble(risk, 2), ".+"), ",", closeTime, ",", NumberToStr(NormalizeDouble(closePrice, Digits), ".+"), ",", NumberToStr(NormalizeDouble(stopLoss, Digits), ".+"), ",", closedBySL, ",", NumberToStr(swap, ".+"), ",", NumberToStr(commission, ".+"), ",", NumberToStr(profit, ".+")));
   }


   // (2) Daten speichern
   int hFile = FileOpen(GetMqlStatusFileName(), FILE_CSV|FILE_WRITE);
   if (hFile < 0)
      return(_false(catch("SaveStatus(2) ->FileOpen(\""+ GetMqlStatusFileName() +"\")")));

   for (i=0; i < ArraySize(lines); i++) {
      if (FileWrite(hFile, lines[i]) < 0) {
         catch("SaveStatus(3) ->FileWrite(line #"+ (i+1) +")");
         FileClose(hFile);
         return(false);
      }
   }
   FileClose(hFile);

   /*
   // (3) Datei auf Server laden
   int error = UploadStatus(ShortAccountCompany(), AccountNumber(), StdSymbol(), fileName);
   if (IsError(error))
      return(false);
   */

   ArrayResize(lines,  0);
   ArrayResize(values, 0);
   return(IsNoError(catch("SaveStatus(4)")));
}


/**
 * Lädt die angegebene Statusdatei auf den Server.
 *
 * @param  string company  - Account-Company
 * @param  int    account  - Account-Number
 * @param  string symbol   - Symbol der Sequenz
 * @param  string filename - Dateiname, relativ zu "{terminal-directory}\experts"
 *
 * @return int - Fehlerstatus
 */
int UploadStatus(string company, int account, string symbol, string filename) {
   if (__STATUS__CANCELLED || IsLastError()) return(last_error);
   if (IsTest())                             return(NO_ERROR);

   // TODO: Existenz von wget.exe prüfen

   string parts[]; Explode(filename, "\\", parts, NULL);
   string baseName = ArrayPopString(parts);                          // einfacher Dateiname ohne Verzeichnisse

   // Befehlszeile für Shellaufruf zusammensetzen
          filename     = TerminalPath() +"\\experts\\"+ filename;    // Dateinamen mit vollständigen Pfaden
   string responseFile = filename +".response";
   string logFile      = filename +".log";
   string url          = "http://sub.domain.tld/uploadSRStatus.php?company="+ UrlEncode(company) +"&account="+ account +"&symbol="+ UrlEncode(symbol) +"&name="+ UrlEncode(baseName);
   string cmdLine      = "wget.exe -b \""+ url +"\" --post-file=\""+ filename +"\" --header=\"Content-Type: text/plain\" -O \""+ responseFile +"\" -a \""+ logFile +"\"";

   // Existenz der Datei prüfen
   if (!IsFile(filename))
      return(catch("UploadStatus(1)   file not found \""+ filename +"\"", ERR_FILE_NOT_FOUND));

   // Datei hochladen, WinExec() kehrt ohne zu warten zurück, wget -b beschleunigt zusätzlich
   int error = WinExec(cmdLine, SW_HIDE);                            // SW_SHOWNORMAL|SW_HIDE
   if (error < 32)
      return(catch("UploadStatus(2) ->kernel32::WinExec(cmdLine=\""+ cmdLine +"\"), error="+ error +" ("+ ShellExecuteErrorToStr(error) +")", ERR_WIN32_ERROR));

   ArrayResize(parts, 0);
   return(catch("UploadStatus(3)"));
}


/**
 * Liest den Status einer Sequenz ein und restauriert die internen Variablen. Bei fehlender lokaler Statusdatei wird versucht,
 * die Datei vom Server zu laden.
 *
 * @return bool - ob der Status erfolgreich restauriert wurde
 */
bool RestoreStatus() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (sequenceId == 0)                      return(_false(catch("RestoreStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));


   // (1) Pfade und Dateinamen bestimmen
   string fileName = GetMqlStatusFileName();
   if (!IsMqlFile(fileName))
      if (!ResolveStatusLocation())
         return(false);
   fileName = GetMqlStatusFileName();

   /*
   // (2) bei nicht existierender Datei die Datei vom Server laden
   if (!IsMqlFile(fileName)) {
      if (IsTest())
         return(_false(catch("RestoreStatus(2)   status file \""+ subDir + fileName +"\" for test sequence T"+ sequenceId +" not found", ERR_FILE_NOT_FOUND)));

      // TODO: Existenz von wget.exe prüfen

      // Befehlszeile für Shellaufruf zusammensetzen
      string url        = "http://sub.domain.tld/downloadSRStatus.php?company="+ UrlEncode(ShortAccountCompany()) +"&account="+ AccountNumber() +"&symbol="+ UrlEncode(StdSymbol()) +"&sequence="+ sequenceId;
      string targetFile = fullFileName;
      string logFile    = fullFileName +".log";
      string cmd        = "wget.exe \""+ url +"\" -O \""+ targetFile +"\" -o \""+ logFile +"\"";

      debug("RestoreStatus()   downloading status file for sequence "+ ifString(IsTest(), "T", "") + sequenceId);

      int error = WinExecAndWait(cmd, SW_HIDE);                      // SW_SHOWNORMAL|SW_HIDE
      if (IsError(error))
         return(_false(SetLastError(error)));

      debug("RestoreStatus()   status file for sequence "+ ifString(IsTest(), "T", "") + sequenceId +" successfully downloaded");
      FileDelete(subDir + fileName +".log");
   }
   */
   if (!IsMqlFile(fileName))
      return(_false(catch("RestoreStatus(3)   status file \""+ fileName +"\" not found", ERR_FILE_NOT_FOUND)));


   // (3) Datei einlesen
   string lines[];
   int size = FileReadLines(fileName, lines, true);
   if (size < 0)
      return(_false(SetLastError(stdlib_PeekLastError())));
   if (size == 0) {
      FileDelete(fileName);
      return(_false(catch("RestoreStatus(4)   no status for sequence "+ ifString(IsTest(), "T", "") + sequenceId +" not found", ERR_RUNTIME_ERROR)));
   }

   // notwendige Schlüssel definieren
   string keys[] = { "Account", "Symbol", "Sequence.ID", "GridDirection", "GridSize", "LotSize", "rt.instanceStartTime", "rt.instanceStartPrice", "rt.sequenceStartEquity", "rt.sequenceStarts", "rt.sequenceStops", "rt.grid.maxProfit", "rt.grid.maxProfitTime", "rt.grid.maxDrawdown", "rt.grid.maxDrawdownTime", "rt.grid.base" };
   /*                "Account"                 ,                     // Der Compiler kommt mit den Zeilennummern durcheinander,
                     "Symbol"                  ,                     // wenn der Initializer nicht komplett in einer Zeile steht.
                     "Sequence.ID"             ,
                   //"Sequence.Status.Location",                     // optional
                     "GridDirection"           ,
                     "GridSize"                ,
                     "LotSize"                 ,
                   //"StartConditions"         ,                     // optional
                   //"StopConditions"          ,                     // optional
                     "rt.instanceStartTime"    ,
                     "rt.instanceStartPrice"   ,
                     "rt.sequenceStartEquity"  ,
                     "rt.sequenceStarts"       ,
                     "rt.sequenceStops"        ,
                   //"rt.ignorePendingOrders"  ,                     // optional
                   //"rt.ignoreOpenPositions"  ,                     // optional
                   //"rt.ignoreClosedPositions",                     // optional
                     "rt.grid.maxProfit"       ,
                     "rt.grid.maxProfitTime"   ,
                     "rt.grid.maxDrawdown"     ,
                     "rt.grid.maxDrawdownTime" ,
                     "rt.grid.base"            ,
   */


   // (4.1) Nicht-Runtime-Settings auslesen, validieren und übernehmen
   string parts[], key, value, accountValue;
   int    accountLine;

   for (int i=0; i < size; i++) {
      if (Explode(lines[i], "=", parts, 2) < 2)                       return(_false(catch("RestoreStatus(5)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
      key   = StringTrim(parts[0]);
      value = StringTrim(parts[1]);

      if (key == "Account") {
         accountValue = value;
         accountLine  = i;
         ArrayDropString(keys, key);                                  // Abhängigkeit Account <=> Sequence.ID (siehe 4.2)
      }
      else if (key == "Symbol") {
         if (value != Symbol())                                       return(_false(catch("RestoreStatus(6)   symbol mis-match \""+ value +"\"/\""+ Symbol() +"\" in status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         ArrayDropString(keys, key);
      }
      else if (key == "Sequence.ID") {
         value = StringToUpper(value);
         if (StringLeft(value, 1) == "T") {
            test  = true; SS.Test();
            value = StringRight(value, -1);
         }
         if (value != StringConcatenate("", sequenceId))              return(_false(catch("RestoreStatus(7)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         Sequence.ID = ifString(IsTest(), "T", "") + sequenceId;
         ArrayDropString(keys, key);
      }
      else if (key == "Sequence.StatusLocation") {
         Sequence.StatusLocation = value;
      }
      else if (key == "GridDirection") {
         if (value == "")                                             return(_false(catch("RestoreStatus(8)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         GridDirection = value;
         ArrayDropString(keys, key);
      }
      else if (key == "GridSize") {
         if (!StringIsDigit(value))                                   return(_false(catch("RestoreStatus(9)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         GridSize = StrToInteger(value);
         ArrayDropString(keys, key);
      }
      else if (key == "LotSize") {
         if (!StringIsNumeric(value))                                 return(_false(catch("RestoreStatus(10)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         LotSize = StrToDouble(value);
         ArrayDropString(keys, key);
      }
      else if (key == "StartConditions") {
         StartConditions = value;
      }
      else if (key == "StopConditions") {
         StopConditions = value;
      }
   }

   // (4.2) gegenseitige Abhängigkeiten validieren

   // Account: Eine Testsequenz kann in einem anderen Account visualisiert werden, solange die Zeitzonen beider Accounts übereinstimmen.
   if (accountValue != ShortAccountCompany()+":"+GetAccountNumber()) {
      if (IsTesting() || !IsTest() || !StringIStartsWith(accountValue, ShortAccountCompany()+":"))
                                                                      return(_false(catch("RestoreStatus(11)   account mis-match \""+ ShortAccountCompany() +":"+ GetAccountNumber() +"\"/\""+ accountValue +"\" in status file \""+ fileName +"\" (line \""+ lines[accountLine] +"\")", ERR_RUNTIME_ERROR)));
   }


   // (5.1) Runtime-Settings auslesen, validieren und übernehmen
   ArrayResize(sequenceStartTimes,    0);
   ArrayResize(sequenceStartPrices,   0);
   ArrayResize(sequenceStopTimes,     0);
   ArrayResize(sequenceStopPrices,    0);
   ArrayResize(ignorePendingOrders,   0);
   ArrayResize(ignoreOpenPositions,   0);
   ArrayResize(ignoreClosedPositions, 0);
   ArrayResize(grid.base.time,        0);
   ArrayResize(grid.base.value,       0);

   for (i=0; i < size; i++) {
      if (Explode(lines[i], "=", parts, 2) < 2)                       return(_false(catch("RestoreStatus(12)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
      key   = StringTrim(parts[0]);
      value = StringTrim(parts[1]);

      if (StringStartsWith(key, "rt."))
         if (!RestoreStatus.Runtime(fileName, lines[i], key, value, keys))
            return(false);
   }
   if (ArraySize(keys) > 0)                                           return(_false(catch("RestoreStatus(13)   "+ ifString(ArraySize(keys)==1, "entry", "entries") +" \""+ JoinStrings(keys, "\", \"") +"\" missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));

   // (5.2) gegenseitige Abhängigkeiten validieren
   if (ArraySize(sequenceStartTimes) != ArraySize(sequenceStopTimes)) return(_false(catch("RestoreStatus(14)   sequenceStarts("+ ArraySize(sequenceStartTimes) +") / sequenceStops("+ ArraySize(sequenceStopTimes) +") mis-match in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));
   if (IntInArray(orders.ticket, 0))                                  return(_false(catch("RestoreStatus(15)   one or more order entries missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));


   ArrayResize(lines, 0);
   ArrayResize(keys,  0);
   ArrayResize(parts, 0);
   return(IsNoError(catch("RestoreStatus(16)")));
}


/**
 * Restauriert eine oder mehrere Laufzeitvariablen.
 *
 * @param  string file   - Name der Statusdatei, aus der die Einstellung stammt (für evt. Fehlermeldung)
 * @param  string line   - Statuszeile der Einstellung                          (für evt. Fehlermeldung)
 * @param  string key    - Schlüssel der Einstellung
 * @param  string value  - Wert der Einstellung
 * @param  string keys[] - Array für Rückmeldung des restaurierten Schlüssels
 *
 * @return bool - Erfolgsstatus
 */
bool RestoreStatus.Runtime(string file, string line, string key, string value, string keys[]) {
   if (__STATUS__CANCELLED || IsLastError())
      return(false);
   /*
   datetime rt.instanceStartTime=1328701713
   double   rt.instanceStartPrice=1.32677
   double   rt.sequenceStartEquity=7801.13
   string   rt.sequenceStarts=1328701713|1.32677,1329999999|1.33215
   string   rt.sequenceStops=1328701999|1.32734,0|0
   string   rt.ignorePendingOrders=66064890,66064891,66064892
   string   rt.ignoreOpenPositions=66064890,66064891,66064892
   string   rt.ignoreClosedPositions=66064890,66064891,66064892
   double   rt.grid.maxProfit=200.13
   datetime rt.grid.maxProfitTime=1328701713
   double   rt.grid.maxDrawdown=-127.80
   datetime rt.grid.maxDrawdownTime=1328691713
   string   rt.grid.base=1331710960|1.56743,1331711010|1.56714
   string   rt.order.0=62544847,1,1.32067,4,1330932525,1330932525,1.32067,0,0,1330936196,1.32067,0,0,0,1330938698,1.31897,1.31897,17,1,0,0,0,0,0,-17
      int      ticket       = values[ 0];
      int      level        = values[ 1];
      double   gridBase     = values[ 2];
      int      pendingType  = values[ 3];
      datetime pendingTime  = values[ 4];
      double   pendingPrice = values[ 5];
      int      type         = values[ 6];
      datetime openTime     = values[ 7];
      double   openPrice    = values[ 8];
      double   risk         = values[ 9];
      datetime closeTime    = values[10];
      double   closePrice   = values[11];
      double   stopLoss     = values[12];
      bool     closedBySL   = values[13];
      double   swap         = values[14];
      double   commission   = values[15];
      double   profit       = values[16];
   */
   string values[], data[];

   if (key == "rt.instanceStartTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(1)   illegal instanceStartTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      instanceStartTime = StrToInteger(value);
      if (instanceStartTime == 0)                                           return(_false(catch("RestoreStatus.Runtime(2)   illegal instanceStartTime "+ instanceStartTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.instanceStartPrice") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(3)   illegal instanceStartPrice \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      instanceStartPrice = StrToDouble(value);
      if (LE(instanceStartPrice, 0))                                        return(_false(catch("RestoreStatus.Runtime(4)   illegal instanceStartPrice "+ NumberToStr(instanceStartPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStartEquity") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(5)   illegal sequenceStartEquity \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStartEquity = StrToDouble(value);
      if (LT(sequenceStartEquity, 0))                                       return(_false(catch("RestoreStatus.Runtime(6)   illegal sequenceStartEquity "+ DoubleToStr(sequenceStartEquity, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStarts") {
      // rt.sequenceStarts=1331710960|1.56743,1331711010|1.56714
      int sizeOfValues = Explode(value, ",", values, NULL);
      for (int i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                      return(_false(catch("RestoreStatus.Runtime(7)   illegal number of sequenceStarts["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // sequenceStartTime
         if (!StringIsDigit(value))                                         return(_false(catch("RestoreStatus.Runtime(8)   illegal sequenceStartTimes["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime startTime = StrToInteger(value);
         if (startTime == 0) {
            if (NE(sequenceStartEquity, 0))                                 return(_false(catch("RestoreStatus.Runtime(9)   sequenceStartEquity/sequenceStartTimes["+ i +"] mis-match "+ NumberToStr(sequenceStartEquity, ".2") +"/"+ startTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (sizeOfValues==1 && data[1]=="0")
               break;                                                       return(_false(catch("RestoreStatus.Runtime(10)   illegal sequenceStartTimes["+ i +"] "+ startTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         }
         else if (EQ(sequenceStartEquity, 0))                               return(_false(catch("RestoreStatus.Runtime(11)   sequenceStartEquity/sequenceStartTimes["+ i +"] mis-match "+ NumberToStr(sequenceStartEquity, ".2") +"/'"+ TimeToStr(startTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         else if (startTime < instanceStartTime)                            return(_false(catch("RestoreStatus.Runtime(12)   instanceStartTime/sequenceStartTimes["+ i +"] mis-match '"+ TimeToStr(instanceStartTime, TIME_FULL) +"'/'"+ TimeToStr(startTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // sequenceStartPrice
         if (!StringIsNumeric(value))                                       return(_false(catch("RestoreStatus.Runtime(13)   illegal sequenceStartPrices["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double startPrice = StrToDouble(value);
         if (LE(startPrice, 0))                                             return(_false(catch("RestoreStatus.Runtime(14)   illegal sequenceStartPrices["+ i +"] "+ NumberToStr(startPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (sequenceStartTimes,  startTime );
         ArrayPushDouble(sequenceStartPrices, startPrice);
      }
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStops") {
      // rt.sequenceStops=1331710960|1.56743,0|0
      sizeOfValues = Explode(value, ",", values, NULL);
      for (i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                      return(_false(catch("RestoreStatus.Runtime(15)   illegal number of sequenceStops["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // sequenceStopTime
         if (!StringIsDigit(value))                                         return(_false(catch("RestoreStatus.Runtime(16)   illegal sequenceStopTimes["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime stopTime = StrToInteger(value);
         if (stopTime == 0) {
            if (i < sizeOfValues-1 || data[1]!="0")                         return(_false(catch("RestoreStatus.Runtime(17)   illegal sequenceStopTimes["+ i +"] "+ stopTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (i==0 && ArraySize(sequenceStartTimes)==0)
               break;
         }
         else if (i >= ArraySize(sequenceStartTimes))                       return(_false(catch("RestoreStatus.Runtime(18)   sequenceStarts("+ ArraySize(sequenceStartTimes) +") / sequenceStops("+ sizeOfValues +") mis-match in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         else if (stopTime < sequenceStartTimes[i])                         return(_false(catch("RestoreStatus.Runtime(19)   sequenceStartTimes["+ i +"]/sequenceStopTimes["+ i +"] mis-match '"+ TimeToStr(sequenceStartTimes[i], TIME_FULL) +"'/'"+ TimeToStr(stopTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // sequenceStopPrice
         if (!StringIsNumeric(value))                                       return(_false(catch("RestoreStatus.Runtime(20)   illegal sequenceStopPrices["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double stopPrice = StrToDouble(value);
         if (LT(stopPrice, 0))                                              return(_false(catch("RestoreStatus.Runtime(21)   illegal sequenceStopPrices["+ i +"] "+ NumberToStr(stopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (EQ(stopPrice, 0) && stopTime!=0)                               return(_false(catch("RestoreStatus.Runtime(22)   sequenceStopTimes["+ i +"]/sequenceStopPrices["+ i +"] mis-match '"+ TimeToStr(stopTime, TIME_FULL) +"'/"+ NumberToStr(stopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (sequenceStopTimes,  stopTime );
         ArrayPushDouble(sequenceStopPrices, stopPrice);
      }
      ArrayDropString(keys, key);
   }
   else if (key == "rt.ignorePendingOrders") {
      // rt.ignorePendingOrders=66064890,66064891,66064892
      if (StringLen(value) > 0) {
         sizeOfValues = Explode(value, ",", values, NULL);
         for (i=0; i < sizeOfValues; i++) {
            string strTicket = StringTrim(values[i]);
            if (!StringIsDigit(strTicket))                                  return(_false(catch("RestoreStatus.Runtime(23)   illegal ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            int ticket = StrToInteger(strTicket);
            if (ticket == 0)                                                return(_false(catch("RestoreStatus.Runtime(24)   illegal ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            ArrayPushInt(ignorePendingOrders, ticket);
         }
      }
   }
   else if (key == "rt.ignoreOpenPositions") {
      // rt.ignoreOpenPositions=66064890,66064891,66064892
      if (StringLen(value) > 0) {
         sizeOfValues = Explode(value, ",", values, NULL);
         for (i=0; i < sizeOfValues; i++) {
            strTicket = StringTrim(values[i]);
            if (!StringIsDigit(strTicket))                                  return(_false(catch("RestoreStatus.Runtime(25)   illegal ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            ticket = StrToInteger(strTicket);
            if (ticket == 0)                                                return(_false(catch("RestoreStatus.Runtime(26)   illegal ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            ArrayPushInt(ignoreOpenPositions, ticket);
         }
      }
   }
   else if (key == "rt.ignoreClosedPositions") {
      // rt.ignoreClosedPositions=66064890,66064891,66064892
      if (StringLen(value) > 0) {
         sizeOfValues = Explode(value, ",", values, NULL);
         for (i=0; i < sizeOfValues; i++) {
            strTicket = StringTrim(values[i]);
            if (!StringIsDigit(strTicket))                                  return(_false(catch("RestoreStatus.Runtime(27)   illegal ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            ticket = StrToInteger(strTicket);
            if (ticket == 0)                                                return(_false(catch("RestoreStatus.Runtime(28)   illegal ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            ArrayPushInt(ignoreClosedPositions, ticket);
         }
      }
   }
   else if (key == "rt.grid.maxProfit") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(29)   illegal grid.maxProfit \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfit = StrToDouble(value); SS.Grid.MaxProfit();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxProfitTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(30)   illegal grid.maxProfitTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitTime = StrToInteger(value);
      if (grid.maxProfitTime==0 && NE(grid.maxProfit, 0))                   return(_false(catch("RestoreStatus.Runtime(31)   grid.maxProfit/grid.maxProfitTime mis-match "+ NumberToStr(grid.maxProfit, ".2") +"/'"+ TimeToStr(grid.maxProfitTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdown") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(32)   illegal grid.maxDrawdown \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdown = StrToDouble(value); SS.Grid.MaxDrawdown();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdownTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(33)   illegal grid.maxDrawdownTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdownTime = StrToInteger(value);
      if (grid.maxDrawdownTime==0 && NE(grid.maxDrawdown, 0))               return(_false(catch("RestoreStatus.Runtime(34)   grid.maxDrawdown/grid.maxDrawdownTime mis-match "+ NumberToStr(grid.maxDrawdown, ".2") +"/'"+ TimeToStr(grid.maxDrawdownTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.base") {
      // rt.grid.base=1331710960|1.56743,1331711010|1.56714
      sizeOfValues = Explode(value, ",", values, NULL);
      for (i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                      return(_false(catch("RestoreStatus.Runtime(35)   illegal number of grid.base["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // GridBase-Zeitpunkt
         if (!StringIsDigit(value))                                         return(_false(catch("RestoreStatus.Runtime(36)   illegal grid.base.time["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime gridBaseTime = StrToInteger(value);
         int startTimes = ArraySize(sequenceStartTimes);
         if (gridBaseTime == 0) {
            if (startTimes > 0)                                             return(_false(catch("RestoreStatus.Runtime(37)   sequenceStartTimes/grid.base.time["+ i +"] mis-match '"+ TimeToStr(sequenceStartTimes[0], TIME_FULL) +"'/"+ gridBaseTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (sizeOfValues==1 && data[1]=="0")
               break;                                                       return(_false(catch("RestoreStatus.Runtime(38)   illegal grid.base.time["+ i +"] "+ gridBaseTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         }
         else if (startTimes == 0)                                          return(_false(catch("RestoreStatus.Runtime(39)   sequenceStartTimes/grid.base.time["+ i +"] mis-match "+ startTimes +"/'"+ TimeToStr(gridBaseTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // GridBase-Wert
         if (!StringIsNumeric(value))                                       return(_false(catch("RestoreStatus.Runtime(40)   illegal grid.base.value["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double gridBaseValue = StrToDouble(value);
         if (LE(gridBaseValue, 0))                                          return(_false(catch("RestoreStatus.Runtime(41)   illegal grid.base.value["+ i +"] "+ NumberToStr(gridBaseValue, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (grid.base.time,  gridBaseTime );
         ArrayPushDouble(grid.base.value, gridBaseValue);
      }
      ArrayDropString(keys, key);
   }
   else if (StringStartsWith(key, "rt.order.")) {
      // Orderindex
      string strIndex = StringRight(key, -9);
      if (!StringIsDigit(strIndex))                                         return(_false(catch("RestoreStatus.Runtime(42)   illegal order index \""+ key +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      i = StrToInteger(strIndex);
      if (ArraySize(orders.ticket) > i) /*&&*/ if (orders.ticket[i]!=0)     return(_false(catch("RestoreStatus.Runtime(43)   duplicate order index "+ key +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // Orderdaten
      if (Explode(value, ",", values, NULL) != 17)                          return(_false(catch("RestoreStatus.Runtime(44)   illegal number of order details ("+ ArraySize(values) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // ticket
      strTicket = StringTrim(values[0]);
      if (!StringIsDigit(strTicket))                                        return(_false(catch("RestoreStatus.Runtime(45)   illegal ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ticket = StrToInteger(strTicket);
      if (ticket == 0)                                                      return(_false(catch("RestoreStatus.Runtime(46)   illegal ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (IntInArray(orders.ticket, ticket))                                return(_false(catch("RestoreStatus.Runtime(47)   duplicate ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // level
      string strLevel = StringTrim(values[1]);
      if (!StringIsInteger(strLevel))                                       return(_false(catch("RestoreStatus.Runtime(48)   illegal order level \""+ strLevel +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int level = StrToInteger(strLevel);
      if (level == 0)                                                       return(_false(catch("RestoreStatus.Runtime(49)   illegal order level "+ level +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // gridBase
      string strGridBase = StringTrim(values[2]);
      if (!StringIsNumeric(strGridBase))                                    return(_false(catch("RestoreStatus.Runtime(50)   illegal order grid base \""+ strGridBase +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double gridBase = StrToDouble(strGridBase);
      if (LE(gridBase, 0))                                                  return(_false(catch("RestoreStatus.Runtime(51)   illegal order grid base "+ NumberToStr(gridBase, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingType
      string strPendingType = StringTrim(values[3]);
      if (!StringIsInteger(strPendingType))                                 return(_false(catch("RestoreStatus.Runtime(52)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int pendingType = StrToInteger(strPendingType);
      if (pendingType!=OP_UNDEFINED && !IsTradeOperation(pendingType))      return(_false(catch("RestoreStatus.Runtime(53)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingTime
      string strPendingTime = StringTrim(values[4]);
      if (!StringIsDigit(strPendingTime))                                   return(_false(catch("RestoreStatus.Runtime(54)   illegal pending order time \""+ strPendingTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingTime = StrToInteger(strPendingTime);
      if (pendingType==OP_UNDEFINED && pendingTime!=0)                      return(_false(catch("RestoreStatus.Runtime(55)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/'"+ TimeToStr(pendingTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && pendingTime==0)                      return(_false(catch("RestoreStatus.Runtime(56)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/"+ pendingTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingPrice
      string strPendingPrice = StringTrim(values[5]);
      if (!StringIsNumeric(strPendingPrice))                                return(_false(catch("RestoreStatus.Runtime(57)   illegal pending order price \""+ strPendingPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double pendingPrice = StrToDouble(strPendingPrice);
      if (LT(pendingPrice, 0))                                              return(_false(catch("RestoreStatus.Runtime(58)   illegal pending order price "+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType==OP_UNDEFINED && NE(pendingPrice, 0))                 return(_false(catch("RestoreStatus.Runtime(59)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED) {
         if (EQ(pendingPrice, 0))                                           return(_false(catch("RestoreStatus.Runtime(60)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (NE(pendingPrice, gridBase+level*GridSize*Pips, Digits))        return(_false(catch("RestoreStatus.Runtime(61)   grid base/pending order price mis-match "+ NumberToStr(gridBase, PriceFormat) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" (level "+ level +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // type
      string strType = StringTrim(values[6]);
      if (!StringIsInteger(strType))                                        return(_false(catch("RestoreStatus.Runtime(62)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int type = StrToInteger(strType);
      if (type!=OP_UNDEFINED && !IsTradeOperation(type))                    return(_false(catch("RestoreStatus.Runtime(63)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType == OP_UNDEFINED) {
         if (type == OP_UNDEFINED)                                          return(_false(catch("RestoreStatus.Runtime(64)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }
      else if (type != OP_UNDEFINED) {
         if (IsLongTradeOperation(pendingType)!=IsLongTradeOperation(type)) return(_false(catch("RestoreStatus.Runtime(65)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // openTime
      string strOpenTime = StringTrim(values[7]);
      if (!StringIsDigit(strOpenTime))                                      return(_false(catch("RestoreStatus.Runtime(66)   illegal order open time \""+ strOpenTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime openTime = StrToInteger(strOpenTime);
      if (type==OP_UNDEFINED && openTime!=0)                                return(_false(catch("RestoreStatus.Runtime(67)   order type/time mis-match "+ OperationTypeToStr(type) +"/'"+ TimeToStr(openTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && openTime==0)                                return(_false(catch("RestoreStatus.Runtime(68)   order type/time mis-match "+ OperationTypeToStr(type) +"/"+ openTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openPrice
      string strOpenPrice = StringTrim(values[8]);
      if (!StringIsNumeric(strOpenPrice))                                   return(_false(catch("RestoreStatus.Runtime(69)   illegal order open price \""+ strOpenPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openPrice = StrToDouble(strOpenPrice);
      if (LT(openPrice, 0))                                                 return(_false(catch("RestoreStatus.Runtime(70)   illegal order open price "+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(71)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(72)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // risk
      string strRisk = StringTrim(values[9]);
      if (!StringIsNumeric(strRisk))                                        return(_false(catch("RestoreStatus.Runtime(73)   illegal order risk \""+ strRisk +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double risk = StrToDouble(strRisk);
      if (LT(risk, 0))                                                      return(_false(catch("RestoreStatus.Runtime(74)   illegal order risk "+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(risk, 0))                                return(_false(catch("RestoreStatus.Runtime(75)   pending order/risk mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(risk, 0))                                return(_false(catch("RestoreStatus.Runtime(76)   order type/risk mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closeTime
      string strCloseTime = StringTrim(values[10]);
      if (!StringIsDigit(strCloseTime))                                     return(_false(catch("RestoreStatus.Runtime(77)   illegal order close time \""+ strCloseTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime closeTime = StrToInteger(strCloseTime);
      if (closeTime != 0) {
         if (closeTime < pendingTime)                                       return(_false(catch("RestoreStatus.Runtime(78)   pending order time/delete time mis-match '"+ TimeToStr(pendingTime, TIME_FULL) +"'/'"+ TimeToStr(closeTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (closeTime < openTime)                                          return(_false(catch("RestoreStatus.Runtime(79)   order open/close time mis-match '"+ TimeToStr(openTime, TIME_FULL) +"'/'"+ TimeToStr(closeTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // closePrice
      string strClosePrice = StringTrim(values[11]);
      if (!StringIsNumeric(strClosePrice))                                  return(_false(catch("RestoreStatus.Runtime(80)   illegal order close price \""+ strClosePrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closePrice = StrToDouble(strClosePrice);
      if (LT(closePrice, 0))                                                return(_false(catch("RestoreStatus.Runtime(81)   illegal order close price "+ NumberToStr(closePrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // stopLoss
      string strStopLoss = StringTrim(values[12]);
      if (!StringIsNumeric(strStopLoss))                                    return(_false(catch("RestoreStatus.Runtime(82)   illegal order stoploss \""+ strStopLoss +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double stopLoss = StrToDouble(strStopLoss);
      if (LE(stopLoss, 0))                                                  return(_false(catch("RestoreStatus.Runtime(83)   illegal order stoploss "+ NumberToStr(stopLoss, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (NE(stopLoss, gridBase+(level-Sign(level))*GridSize*Pips, Digits)) return(_false(catch("RestoreStatus.Runtime(84)   grid base/stoploss mis-match "+ NumberToStr(gridBase, PriceFormat) +"/"+ NumberToStr(stopLoss, PriceFormat) +" (level "+ level +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closedBySL
      string strClosedBySL = StringTrim(values[13]);
      if (!StringIsDigit(strClosedBySL))                                    return(_false(catch("RestoreStatus.Runtime(85)   illegal closedBySL value \""+ strClosedBySL +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      bool closedBySL = _bool(StrToInteger(strClosedBySL));

      // swap
      string strSwap = StringTrim(values[14]);
      if (!StringIsNumeric(strSwap))                                        return(_false(catch("RestoreStatus.Runtime(86)   illegal order swap \""+ strSwap +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double swap = StrToDouble(strSwap);
      if (type==OP_UNDEFINED && NE(swap, 0))                                return(_false(catch("RestoreStatus.Runtime(87)   pending order/swap mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(swap, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // commission
      string strCommission = StringTrim(values[15]);
      if (!StringIsNumeric(strCommission))                                  return(_false(catch("RestoreStatus.Runtime(88)   illegal order commission \""+ strCommission +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double commission = StrToDouble(strCommission);
      if (type==OP_UNDEFINED && NE(commission, 0))                          return(_false(catch("RestoreStatus.Runtime(89)   pending order/commission mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(commission, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // profit
      string strProfit = StringTrim(values[16]);
      if (!StringIsNumeric(strProfit))                                      return(_false(catch("RestoreStatus.Runtime(90)   illegal order profit \""+ strProfit +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double profit = StrToDouble(strProfit);
      if (type==OP_UNDEFINED && NE(profit, 0))                              return(_false(catch("RestoreStatus.Runtime(91)   pending order/profit mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(profit, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));


      // Daten speichern
      Grid.SetData(i, ticket, level, gridBase, pendingType, pendingTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedBySL, swap, commission, profit);
      //debug("RestoreStatus.Runtime()   #"+ ticket +"  level="+ level +"  gridBase="+ NumberToStr(gridBase, PriceFormat) +"  pendingType="+ OperationTypeToStr(pendingType) +"  pendingTime='"+ TimeToStr(pendingTime, TIME_FULL) +"'  pendingPrice="+ NumberToStr(pendingPrice, PriceFormat) +"  type="+ OperationTypeToStr(type) +"  openTime='"+ TimeToStr(openTime, TIME_FULL) +"'  openPrice="+ NumberToStr(openPrice, PriceFormat) +"  risk="+ DoubleToStr(risk, 2) +"  closeTime='"+ TimeToStr(closeTime, TIME_FULL) +"'  closePrice="+ NumberToStr(closePrice, PriceFormat) +"  stopLoss="+ NumberToStr(stopLoss, PriceFormat) +"  closedBySL="+ BoolToStr(closedBySL) +"  swap="+ DoubleToStr(swap, 2) +"  commission="+ DoubleToStr(commission, 2) +"  profit="+ DoubleToStr(profit, 2));
   }

   ArrayResize(values, 0);
   ArrayResize(data,   0);
   return(!IsLastError() && IsNoError(catch("RestoreStatus.Runtime(92)")));
}


/**
 * Gleicht den in der Instanz gespeicherten Laufzeitstatus mit den Online-Daten der laufenden Sequenz ab.
 *
 * @return bool - Erfolgsstatus
 */
bool SynchronizeStatus() {
   if (__STATUS__CANCELLED || IsLastError())
      return(false);

   bool permStatusChange, permTicketChange, pendingOrder, openPosition, closedPosition, closedBySL;

   int  orphanedPendingOrders  []; ArrayResize(orphanedPendingOrders,   0);
   int  orphanedOpenPositions  []; ArrayResize(orphanedOpenPositions,   0);
   int  orphanedClosedPositions[]; ArrayResize(orphanedClosedPositions, 0);

   int  sizeOfTickets = ArraySize(orders.ticket);


   // (1.1) alle offenen Tickets in Datenarrays mit Online-Status synchronisieren, gestrichene PendingOrders löschen
   for (int i=sizeOfTickets-1; i >= 0; i--) {
      if (orders.closeTime[i] == 0) {
         if (!OrderSelectByTicket(orders.ticket[i], "SynchronizeStatus(1)   cannot synchronize "+ OperationTypeDescription(ifInt(orders.type[i]==OP_UNDEFINED, orders.pendingType[i], orders.type[i])) +" order (#"+ orders.ticket[i] +" not found)"))
            return(false);

         if (!Sync.UpdateOrder(i, permTicketChange))
            return(false);
         if (permTicketChange)
            permStatusChange = true;

         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]!=0) {
            if (!Grid.DropTicket(orders.ticket[i]))
               return(false);
            sizeOfTickets--;
            permStatusChange = true;
         }
      }
   }

   // (1.2) alle erreichbaren Online-Tickets der Sequenz auf lokale Referenz überprüfen
   for (i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))                  // offene Tickets (FALSE: während des Auslesens wurde in einem anderen Thread eine offene Order entfernt)
         continue;
      if (IsMyOrder(sequenceId)) /*&&*/ if (!IntInArray(orders.ticket, OrderTicket())) {
         pendingOrder = IsPendingTradeOperation(OrderType());           // kann PendingOrder oder offene Position sein
         openPosition = !pendingOrder;
         if (pendingOrder) /*&&*/ if (!IntInArray(ignorePendingOrders, OrderTicket())) ArrayPushInt(orphanedPendingOrders, OrderTicket());
         if (openPosition) /*&&*/ if (!IntInArray(ignoreOpenPositions, OrderTicket())) ArrayPushInt(orphanedOpenPositions, OrderTicket());
      }
   }
   for (i=OrdersHistoryTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))                 // geschlossene Tickets (FALSE: während des Auslesens wurde der Anzeigezeitraum der History verändert)
         continue;
      if (IsPendingTradeOperation(OrderType()))                         // gestrichene PendingOrders ignorieren
         continue;
      if (IsMyOrder(sequenceId)) /*&&*/ if (!IntInArray(orders.ticket, OrderTicket())) {
         if (!IntInArray(ignoreClosedPositions, OrderTicket()))         // kann nur geschlossene Position sein
            ArrayPushInt(orphanedClosedPositions, OrderTicket());
      }
   }

   // (1.3) Vorgehensweise für verwaiste Tickets erfragen
   int size = ArraySize(orphanedPendingOrders);                         // TODO: Ignorieren nicht möglich; wenn die Tickets übernommen werden sollen,
   if (size > 0) {                                                      //       müssen sie richtig einsortiert werden.
      return(_false(catch("SynchronizeStatus(2)   unknown pending orders found: #"+ JoinInts(orphanedPendingOrders, ", #"), ERR_RUNTIME_ERROR)));
      //ArraySort(orphanedPendingOrders);
      //ForceSound("notify.wav");
      //int button = ForceMessageBox(__NAME__ +" - SynchronizeStatus()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Orphaned pending order"+ ifString(size==1, "", "s") +" found: #"+ JoinInts(orphanedPendingOrders, ", #") +"\nDo you want to ignore "+ ifString(size==1, "it", "them") +"?", MB_ICONWARNING|MB_OKCANCEL);
      //if (button != IDOK) {
      //   __STATUS__CANCELLED = true;
      //   return(_false(catch("SynchronizeStatus(3)")));
      //}
   }
   size = ArraySize(orphanedOpenPositions);                             // TODO: Ignorieren nicht möglich; wenn die Tickets übernommen werden sollen,
   if (size > 0) {                                                      //       müssen sie richtig einsortiert werden.
      return(_false(catch("SynchronizeStatus(4)   unknown open positions found: #"+ JoinInts(orphanedOpenPositions, ", #"), ERR_RUNTIME_ERROR)));
      //ArraySort(orphanedOpenPositions);
      //ForceSound("notify.wav");
      //button = ForceMessageBox(__NAME__ +" - SynchronizeStatus()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Orphaned open position"+ ifString(size==1, "", "s") +" found: #"+ JoinInts(orphanedPendingOrders, ", #") +"\nDo you want to ignore "+ ifString(size==1, "it", "them") +"?", MB_ICONWARNING|MB_OKCANCEL);
      //if (button != IDOK) {
      //   __STATUS__CANCELLED = true;
      //   return(_false(catch("SynchronizeStatus(5)")));
      //}
   }
   size = ArraySize(orphanedClosedPositions);
   if (size > 0) {
      ArraySort(orphanedClosedPositions);
      ForceSound("notify.wav");
      int button = ForceMessageBox(__NAME__ +" - SynchronizeStatus()", ifString(!IsDemo(), "- Live Account -\n\n", "") +"Orphaned closed position"+ ifString(size==1, "", "s") +" found: #"+ JoinInts(orphanedClosedPositions, ", #") +"\nDo you want to ignore "+ ifString(size==1, "it", "them") +"?", MB_ICONWARNING|MB_OKCANCEL);
      if (button != IDOK) {
         __STATUS__CANCELLED = true;
         return(_false(catch("SynchronizeStatus(6)")));
      }
      MergeIntArrays(ignoreClosedPositions, orphanedClosedPositions, ignoreClosedPositions);
      ArraySort(ignoreClosedPositions);
      permStatusChange = true;
   }


   /*int   */ status              = STATUS_WAITING;
   /*int   */ grid.level          = 0;
   /*int   */ grid.maxLevelLong   = 0;
   /*int   */ grid.maxLevelShort  = 0;
   /*int   */ grid.stops          = 0;
   /*double*/ grid.stopsPL        = 0;
   /*double*/ grid.closedPL       = 0;
   /*double*/ grid.floatingPL     = 0;
   /*double*/ grid.totalPL        = 0;
   /*double*/ grid.activeRisk     = 0;
   /*double*/ grid.valueAtRisk    = 0;
   /*double*/ grid.breakevenLong  = 0;
   /*double*/ grid.breakevenShort = 0;


   // (2) Breakeven-relevante Events zusammenstellen
   #define EV_SEQUENCE_START     1                                      // Event-Types
   #define EV_SEQUENCE_STOP      2
   #define EV_GRIDBASE_CHANGE    3
   #define EV_POSITION_OPEN      4
   #define EV_POSITION_STOPOUT   5
   #define EV_POSITION_CLOSE     6

   double gridBase, profitLoss, pipValue=PipValue(LotSize);
   int    openLevels[]; ArrayResize(openLevels, 0);
   double events[][4];  ArrayResize(events, 0);

   // (2.1) Sequenzstarts und -stops
   int sizeOfStarts = ArraySize(sequenceStartTimes);
   for (i=0; i < sizeOfStarts; i++) {
    //Sync.PushEvent(events, time, type, gridBase, order);
      Sync.PushEvent(events, sequenceStartTimes[i], EV_SEQUENCE_START, NULL, -1);
      Sync.PushEvent(events, sequenceStopTimes [i], EV_SEQUENCE_STOP,  NULL, -1);
   }

   // (2.2) GridBase-Änderungen
   int sizeOfGridBase = ArraySize(grid.base.time);
   for (i=0; i < sizeOfGridBase; i++) {
      Sync.PushEvent(events, grid.base.time[i], EV_GRIDBASE_CHANGE, grid.base.value[i], -1);
   }

   // (2.3) Tickets
   for (i=0; i < sizeOfTickets; i++) {
      pendingOrder   = orders.type[i] == OP_UNDEFINED;
      openPosition   = !pendingOrder && orders.closeTime[i]==0;
      closedPosition = !pendingOrder && !openPosition;
      closedBySL     = closedPosition && orders.closedBySL[i];


      // TODO: Was ist das für ein Nonsense hier???
      if (closedPosition && !closedBySL)
         if (ArraySize(openLevels) != 0)                 return(_false(catch("SynchronizeStatus(5)   illegal sequence status, both open (#?) and closed (#"+ orders.ticket[i] +") positions found", ERR_RUNTIME_ERROR)));


      if (!pendingOrder) {
         Sync.PushEvent(events, orders.openTime[i], EV_POSITION_OPEN, NULL, i);

         if (openPosition) {
            if (IntInArray(openLevels, orders.level[i])) return(_false(catch("SynchronizeStatus(6)   duplicate order level "+ orders.level[i] +" of open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
            ArrayPushInt(openLevels, orders.level[i]);
            grid.floatingPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
         }
         else if (closedBySL) {
            Sync.PushEvent(events, orders.closeTime[i], EV_POSITION_STOPOUT, NULL, i);
         }
         else /*(closed)*/ {
            Sync.PushEvent(events, orders.closeTime[i], EV_POSITION_CLOSE, NULL, i);
         }
      }
      if (IsLastError())
         return(false);
   }
   if (ArraySize(openLevels) != 0) {
      int min = openLevels[ArrayMinimum(openLevels)];
      int max = openLevels[ArrayMaximum(openLevels)];
      if (min < 0 && max > 0)                return(_false(catch("SynchronizeStatus(7)   illegal sequence status, both open long and short positions found", ERR_RUNTIME_ERROR)));
      int maxLevel = Max(Abs(min), Abs(max));
      if (ArraySize(openLevels) != maxLevel) return(_false(catch("SynchronizeStatus(8)   illegal sequence status, missing one or more open positions", ERR_RUNTIME_ERROR)));
   }


   // (3) Breakeven-Verlauf und Laufzeitvariablen restaurieren
   datetime time, lastTime, nextTime;
   int      minute, lastMinute, type, lastType, nextType, iOrder, nextiOrder, iOrderMax, ticket, lastTicket, nextTicket, closedPositions, reopenedPositions;
   bool     recalcBreakeven, breakevenVisible;
   int sizeOfEvents = ArrayRange(events, 0);

   if (sizeOfEvents > 0) {
      ArraySort(events);                                                // Breakeven-Events zeitlich sortieren
      int  firstType = Round(events[0][1]);
      if (firstType != EV_SEQUENCE_START)    return(_false(catch("SynchronizeStatus(9)   illegal first break-even event = "+ BreakevenEventToStr(firstType) +" (time="+ Round(events[0][0]) +")", ERR_RUNTIME_ERROR)));
   }

   for (i=0; i < sizeOfEvents; i++) {
      time       = Round(events[i][0]);
      type       = Round(events[i][1]);
      gridBase   =       events[i][2];
      iOrder     = Round(events[i][3]);
      iOrderMax  = Max(iOrderMax, iOrder);

      ticket     = 0; if (iOrder != -1) ticket = orders.ticket[iOrder];
      nextTicket = 0;
      if (i < sizeOfEvents-1) { nextTime = Round(events[i+1][0]); nextType = Round(events[i+1][1]); nextiOrder = Round(events[i+1][3]); if (nextiOrder != -1) nextTicket = orders.ticket[nextiOrder]; }
      else                    { nextTime = 0;                     nextType = 0;                                                                               nextTicket = 0;                         }

      // (3.1) zwischen den Breakeven-Events liegende BarOpen(M1)-Events simulieren
      if (breakevenVisible) {
         lastMinute = lastTime/60; minute = time/60;
         while (lastMinute < minute-1) {                                // TODO: Wochenenden überspringen
            lastMinute++;
            if (!Grid.DrawBreakeven(lastMinute * MINUTES))
               return(false);
         }
      }

      // (3.2) Breakeven-Events auswerten
      // -- EV_SEQUENCE_START --------------
      if (type == EV_SEQUENCE_START) {
         if (i!=0 && status!=STATUS_STOPPED && status!=STATUS_STARTING)     return(_false(catch("SynchronizeStatus(10)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (time==lastTime || time==nextTime)                              return(_false(catch("SynchronizeStatus(11)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") and before "+ BreakevenEventToStr(nextType) +" ("+ ifString(nextTicket, "#"+ nextTicket +", ", "") +"time="+ nextTime +", "+ TimeToStr(nextTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (status==STATUS_STARTING && reopenedPositions!=Abs(grid.level)) return(_false(catch("SynchronizeStatus(12)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") and before "+ BreakevenEventToStr(nextType) +" ("+ ifString(nextTicket, "#"+ nextTicket +", ", "") +"time="+ nextTime +", "+ TimeToStr(nextTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         reopenedPositions = 0;
         status            = STATUS_PROGRESSING;
         recalcBreakeven   = (i != 0);
      }
      // -- EV_GRIDBASE_CHANGE -------------
      else if (type == EV_GRIDBASE_CHANGE) {
         if (status!=STATUS_PROGRESSING && status!=STATUS_STOPPED)          return(_false(catch("SynchronizeStatus(13)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (time==lastTime || time==nextTime)                              return(_false(catch("SynchronizeStatus(14)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") and before "+ BreakevenEventToStr(nextType) +" ("+ ifString(nextTicket, "#"+ nextTicket +", ", "") +"time="+ nextTime +", "+ TimeToStr(nextTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         grid.base = gridBase;
         if (status == STATUS_PROGRESSING) {
            if (grid.level != 0)                                            return(_false(catch("SynchronizeStatus(15)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
            recalcBreakeven = (grid.maxLevelLong-grid.maxLevelShort > 0);
         }
         else { // STATUS_STOPPED
            grid.activeRisk   = 0;
            reopenedPositions = 0;
            status            = STATUS_STARTING;
            recalcBreakeven   = false;
         }
      }
      // -- EV_POSITION_OPEN ---------------
      else if (type == EV_POSITION_OPEN) {
         if (status!=STATUS_PROGRESSING && status!=STATUS_STARTING)         return(_false(catch("SynchronizeStatus(16)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (status == STATUS_PROGRESSING) {                                // nicht bei PositionReopen
            grid.level        += Sign(orders.level[iOrder]);
            grid.maxLevelLong  = Max(grid.level, grid.maxLevelLong );
            grid.maxLevelShort = Min(grid.level, grid.maxLevelShort);
         }
         else {
            reopenedPositions++;
         }
         grid.activeRisk += orders.risk[iOrder];
         recalcBreakeven  = (status==STATUS_PROGRESSING);                   // nicht bei PositionReopen
      }
      // -- EV_POSITION_STOPOUT ------------
      else if (type == EV_POSITION_STOPOUT) {
         if (status != STATUS_PROGRESSING)                                  return(_false(catch("SynchronizeStatus(17)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         grid.level      -= Sign(orders.level[iOrder]);
         grid.stops++;
         grid.stopsPL    += orders.swap[iOrder] + orders.commission[iOrder] + orders.profit[iOrder];
         grid.activeRisk -= orders.risk[iOrder];
         recalcBreakeven  = true;
      }
      // -- EV_POSITION_CLOSE --------------
      else if (type == EV_POSITION_CLOSE) {
         if (status!=STATUS_PROGRESSING && status!=STATUS_STOPPING)         return(_false(catch("SynchronizeStatus(18)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         grid.closedPL  += orders.swap[iOrder] + orders.commission[iOrder] + orders.profit[iOrder];
         if (status == STATUS_PROGRESSING)
            closedPositions = 0;
         closedPositions++;
         status          = STATUS_STOPPING;
         recalcBreakeven = false;
      }
      // -- EV_SEQUENCE_STOP ---------------
      else if (type == EV_SEQUENCE_STOP) {
         if (status!=STATUS_PROGRESSING && status!=STATUS_STOPPING)         return(_false(catch("SynchronizeStatus(19)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (time==lastTime || time==nextTime)                              return(_false(catch("SynchronizeStatus(20)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") and before "+ BreakevenEventToStr(nextType) +" ("+ ifString(nextTicket, "#"+ nextTicket +", ", "") +"time="+ nextTime +", "+ TimeToStr(nextTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         if (closedPositions!=Abs(grid.level))                              return(_false(catch("SynchronizeStatus(21)   illegal break-even event "+ BreakevenEventToStr(type) +" ("+ ifString(ticket, "#"+ ticket +", ", "") +"time="+ time +", "+ TimeToStr(time, TIME_FULL) +") after "+ BreakevenEventToStr(lastType) +" ("+ ifString(lastTicket, "#"+ lastTicket +", ", "") +"time="+ lastTime +", "+ TimeToStr(lastTime, TIME_FULL) +") and before "+ BreakevenEventToStr(nextType) +" ("+ ifString(nextTicket, "#"+ nextTicket +", ", "") +"time="+ nextTime +", "+ TimeToStr(nextTime, TIME_FULL) +") in "+ StatusToStr(status) +" at level "+ grid.level, ERR_RUNTIME_ERROR)));
         closedPositions = 0;
         status          = STATUS_STOPPED;
         recalcBreakeven = false;
      }
      // -----------------------------------
      grid.valueAtRisk = -grid.stopsPL + grid.activeRisk;

      //debug("SynchronizeStatus()   "+ ifString(ticket, "#"+ ticket, "") +"  "+ TimeToStr(time, TIME_FULL) +" ("+ time +")  "+ StringRightPad(StatusToStr(status), 20, " ") + StringRightPad(BreakevenEventToStr(type), 19, " ") +"  grid.level="+ grid.level +"  iOrder="+ iOrder +"  closed="+ closedPositions +"  reopened="+ reopenedPositions +"  recalcBE="+recalcBreakeven +"  visibleBE="+ breakevenVisible);


      // (3.3) Breakeven ggf. neuberechnen und zeichnen
      if (recalcBreakeven) {
         if (!Grid.CalculateBreakeven(time, iOrderMax))
            return(false);
         breakevenVisible = true;
      }
      else if (breakevenVisible) {
         if (!Grid.DrawBreakeven(time))
            return(false);
         breakevenVisible = (status != STATUS_STOPPED);
      }

      lastTime   = time;
      lastType   = type;
      lastTicket = ticket;
   }


   // (4) Wurde die Sequenz außerhalb gestoppt, fehlen die Stop-Daten (EV_SEQUENCE_STOP)
   if (status == STATUS_STOPPING) {
      if (closedPositions == Abs(grid.level)) {

         // Stopdaten ermitteln und hinzufügen
         double price;
         for (i=sizeOfEvents-Abs(grid.level); i < sizeOfEvents; i++) {
            time   = Round(events[i][0]);
            type   = Round(events[i][1]);
            iOrder = Round(events[i][3]);
            if (type != EV_POSITION_CLOSE)
               return(_false(catch("SynchronizeStatus(22)  unexpected "+ BreakevenEventToStr(type) +" at index "+ i, ERR_SOME_ARRAY_ERROR)));
            price += orders.closePrice[iOrder];
         }
         time  += 1;                                                       // Wir setzen sequenceStopTime 1 sec. in die Zukunft, um Mehrdeutigkeiten
         price /= Abs(grid.level);                                         // bei der nächsten Sortierung der Breakeven-Events zu vermeiden.

         int n = ArraySize(sequenceStopTimes) - 1;
         if (sequenceStopTimes[n] != 0)
            return(_false(catch("SynchronizeStatus(23)  unexpected sequenceStopTimes="+ IntsToStr(sequenceStopTimes, NULL), ERR_RUNTIME_ERROR)));
         sequenceStopTimes [n] = time;
         sequenceStopPrices[n] = NormalizeDouble(price, Digits);

         permStatusChange = true;
         closedPositions  = 0;
         status           = STATUS_STOPPED;
         recalcBreakeven  = false;

         if (!Grid.DrawBreakeven(time))
            return(false);
         breakevenVisible = false;
      }
   }


   grid.stopsPL     = NormalizeDouble(grid.stopsPL,                                   2);
   grid.closedPL    = NormalizeDouble(grid.closedPL,                                  2);
   grid.totalPL     = NormalizeDouble(grid.stopsPL + grid.closedPL + grid.floatingPL, 2);
   grid.activeRisk  = NormalizeDouble(grid.activeRisk,                                2);
   grid.valueAtRisk = NormalizeDouble(grid.valueAtRisk,                               2);
   SS.All();

   RedrawStartStop();
   RedrawOrders();


   // (5) Status ggf. speichern
   if (permStatusChange)
      if (!SaveStatus())
         return(false);

   /*
   debug("SynchronizeStatus() level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));
   */
   ArrayResize(openLevels, 0);
   ArrayResize(events,     0);
   return(IsNoError(catch("SynchronizeStatus(24)")));
}


/**
 * Aktualisiert die Daten des lokal als offen markierten Tickets mit den Online-Daten.
 *
 * @param  int  i            - Ticketindex
 * @param  bool lpPermChange - Zeiger auf Variable, die anzeigt, ob dauerhafte Ticketänderungen vorliegen
 *
 * @return bool - Erfolgsstatus
 *
 *
 *  NOTE: Wird nur in SynchronizeStatus() verwendet.
 *  -----
 */
bool Sync.UpdateOrder(int i, bool &lpPermChange) {
   if (i < 0 || i > ArraySize(orders.ticket)-1) return(_false(catch("Sync.UpdateOrder(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (orders.closeTime[i] != 0)                return(_false(catch("Sync.UpdateOrder(2)   cannot update ticket #"+ orders.ticket[i] +" (marked as closed in grid arrays)", ERR_RUNTIME_ERROR)));

   // das Ticket ist selektiert
   bool   wasPending = orders.type[i] == OP_UNDEFINED;                              // vormals PendingOrder
   bool   wasOpen    = !wasPending;                                                 // vormals offene Position
   bool   isPending  = IsPendingTradeOperation(OrderType());                        // jetzt PendingOrder
   bool   isClosed   = OrderCloseTime() != 0;                                       // jetzt geschlossen oder gestrichen
   bool   isOpen     = !isPending && !isClosed;                                     // jetzt offene Position
   double lastSwap   = orders.swap[i];


   // (1) Ticketdaten aktualisieren
    //orders.ticket      [i]                                                        // unverändert
    //orders.level       [i]                                                        // unverändert
    //orders.gridBase    [i]                                                        // unverändert

   if (isPending) {
    //orders.pendingType [i]                                                        // unverändert
    //orders.pendingTime [i]                                                        // unverändert
      orders.pendingPrice[i] = OrderOpenPrice();
   }
   else if (wasPending) {
      orders.type      [i] = OrderType();
      orders.openTime  [i] = OrderOpenTime();
      orders.openPrice [i] = OrderOpenPrice();
      orders.risk      [i] = CalculateActiveRisk(orders.level[i], orders.ticket[i], OrderOpenPrice(), OrderSwap(), OrderCommission());
   }
      orders.stopLoss  [i] = OrderStopLoss();

   if (isClosed) {
      orders.closeTime [i] = OrderCloseTime();
      orders.closePrice[i] = OrderClosePrice();
      orders.closedBySL[i] = IsOrderClosedBySL();
   }

   if (!isPending) {
      orders.swap      [i] = OrderSwap();
      orders.commission[i] = OrderCommission(); grid.commission = OrderCommission(); SS.LotSize();
      orders.profit    [i] = OrderProfit();
   }

   // (2) Variable lpPermChange aktualisieren
   if      (wasPending) lpPermChange = isOpen || isClosed;
   else if (  isClosed) lpPermChange = true;
   else                 lpPermChange = NE(lastSwap, OrderSwap());

   return(!IsLastError() && IsNoError(catch("Sync.UpdateOrder(3)")));
}


/**
 * Fügt den Breakeven-relevanten Events ein weiteres hinzu.
 *
 * @param  double   events[] - Array mit bereits gespeicherten Events
 * @param  datetime time     - Zeitpunkt des Events
 * @param  int      type     - Event-Typ
 * @param  double   gridBase - Gridbasis des Events
 * @param  int      order    - Index der Order, falls das Event zu einer Order in den Gridarrays gehört
 */
void Sync.PushEvent(double &events[][], datetime time, int type, double gridBase, int order) {
   if (type==EV_SEQUENCE_STOP) /*&&*/ if (time==0)
      return;                                                        // undefinierte Sequenz-Stops ignorieren (wenn, dann immer der letzte Stop)

   int size = ArrayRange(events, 0);
   ArrayResize(events, size+1);

   events[size][0] = time;
   events[size][1] = type;
   events[size][2] = gridBase;
   events[size][3] = order;
}


/**
 * Ermittelt das aktuelle Risiko des angegebenen Levels, inkl. Slippage. Dazu muß eine Position in diesem Level offen sein.
 * Ohne offene Position gibt es nur ein theoretisches, Gridsize-abhängiges Risiko, das hier nicht interessiert.
 *
 * @param  int    level      - Level
 * @param  int    ticket     - Ticket der offenen Position
 * @param  double openPrice  - OpenPrice der offenen Position
 * @param  double swap       - aktueller Swap der offenen Position
 * @param  double commission - Commission der offenen Position (falls zutreffend)
 *
 * @return double - Risiko (positiver Wert für Verlustrisiko)
 */
double CalculateActiveRisk(int level, int ticket, double openPrice, double swap, double commission) {
   if (level == 0) return(_NULL(catch("CalculateActiveRisk(1)   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (ticket < 1) return(_NULL(catch("CalculateActiveRisk(2)   illegal parameter ticket = "+ ticket, ERR_INVALID_FUNCTION_PARAMVALUE)));

   double realized, gridBase=grid.base;

   int size = ArraySize(orders.ticket);

   for (int i=size-1; i >= 0; i--) {
      if (orders.ticket[i] == ticket) {
         gridBase = orders.gridBase[i];                              // die übrigen Daten der offenen Position sind uninteressant
         continue;
      }
      if (orders.level[i] != level)                                  // Order muß zum Level gehören
         continue;
      if (orders.type[i] == OP_UNDEFINED)                            // Order darf nicht pending sein
         continue;
      if (orders.closedBySL[i])                                      // Abbruch vor erster durch StopLoss geschlossenen Position des Levels (wir iterieren rückwärts)
         break;

      realized += orders.swap[i] + orders.commission[i] + orders.profit[i];
   }

   double stopLoss      = gridBase + (level-Sign(level)) * GridSize * Pips;
   double stopLossValue = -MathAbs(openPrice-stopLoss)/Pips * PipValue(LotSize);
   double risk          = realized + stopLossValue + swap + commission;
   //debug("CalculateActiveRisk()   level="+ level +"  realized="+ DoubleToStr(realized, 2) +"  stopLoss="+ NumberToStr(stopLoss, PriceFormat) +"  slValue="+ DoubleToStr(stopLossValue, 2) +"  risk="+ DoubleToStr(risk, 2));

   return(NormalizeDouble(-risk, 2));                                // Rückgabewert für Verlustrisiko soll positiv sein
}


/**
 * Berechnet den durchschnittlichen OpenPrice einer Gesamtposition im angegebenen Level.
 *
 * @param  int      level              - Level
 * @param  bool     checkOpenPositions - ob die Open-Preise schon offener Positionen berücksichtigen werden sollen (um aufgetretene Slippage mit einzukalkulieren)
 * @param  datetime time               - wenn checkOpenPositions=TRUE: Zeitpunkt innerhalb der Sequenz (nur zu diesem Zeitpunkt offene Positionen werden berücksichtigt)
 * @param  int      i                  - wenn checkOpenPositions=TRUE: Orderindex innerhalb der Gridarrays (offene Positionen bis zu diesem Index werden berücksichtigt)
 * @param  double   lpRisk             - wenn checkOpenPositions=TRUE: Zeiger auf Variable, die das Risiko derjeniger aller offenen Position aufnimmt, deren Stoploss als erster getriggert werden würde
 *
 * @return double - Durchschnittspreis oder NULL, falls ein Fehler auftrat
 */
double CalculateAverageOpenPrice(int level, bool checkOpenPositions, datetime time, int i, double &lpRisk) {
   if (level == 0)
      return(_NULL(catch("CalculateAverageOpenPrice(1)   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int    foundLevels, absLevel=Abs(level), absOrdersLevel, lastOpenPosition=-1;
   double sumOpenPrices;


   // (1) ggf. offene Positionen berücksichtigen
   if (checkOpenPositions) {
      if (i < 0 || i >= ArraySize(orders.ticket))
         return(_NULL(catch("CalculateAverageOpenPrice(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));

      for (; i >= 0; i--) {
         if (orders.type[i] == OP_UNDEFINED)                               // Order darf nicht pending sein
            continue;
         if (orders.closeTime[i]!=0 && orders.closeTime[i] <= time)        // Position darf zum Zeitpunkt 'time' nicht geschlossen sein
            continue;
         if (Sign(level) != Sign(orders.level[i]))                         // offene Position: Grid-Directions müssen übereinstimmen
            return(_NULL(catch("CalculateAverageOpenPrice(2|level="+level+", cop="+ checkOpenPositions +", time="+time+", i="+i+", lpRisk)   parameter level/orders.level["+ i +"] mis-match: "+ level +"/"+ orders.level[i], ERR_INVALID_FUNCTION_PARAMVALUE)));
         absOrdersLevel = Abs(orders.level[i]);

         if (lastOpenPosition != -1)
            if (absOrdersLevel != Abs(orders.level[lastOpenPosition])-1)
               return(_NULL(catch("CalculateAverageOpenPrice(3|level="+level+", cop="+ checkOpenPositions +", time="+time+", i="+i+", lpRisk)   open positions mis-match (found position at orders.level["+ i +"]="+ orders.level[i] +", next position at orders.level["+ lastOpenPosition +"] = "+ orders.level[lastOpenPosition] +")", ERR_INVALID_FUNCTION_PARAMVALUE)));
         lastOpenPosition = i;

         if (absOrdersLevel <= absLevel) {                                 // Positionen oberhalb des angegebenen Levels werden ignoriert
            sumOpenPrices += orders.openPrice[i];
            if (foundLevels == 0)
               lpRisk = orders.risk[i];
            foundLevels++;
         }
         if (absOrdersLevel == 1)
            break;
      }
      if (lastOpenPosition != -1)
         if (Abs(orders.level[lastOpenPosition]) != 1)
            return(_NULL(catch("CalculateAverageOpenPrice(4)   open position at level "+ Sign(level) +" missing", ERR_INVALID_FUNCTION_PARAMVALUE)));
   }


   // (2) für fehlende Positionen den Soll-OpenPrice verwenden
   if (foundLevels < absLevel) {
      for (i=absLevel; i > foundLevels; i--) {
         sumOpenPrices += grid.base + i*Sign(level) * GridSize * Pips;
      }
      if (foundLevels == 0)
         lpRisk = 0;
   }

   //debug("CalculateAverageOpenPrice(0.2)   level="+ level +"   sum="+ NumberToStr(sumOpenPrices, ".+"));
   return(sumOpenPrices / absLevel);
}


/**
 * Ermittelt die StopTime der aktuell gestoppten Sequenz.
 *
 * @return datetime
 */
datetime CalculateSequenceStopTime() {
   if (status != STATUS_STOPPED) return(_NULL(catch("CalculateSequenceStopTime(1)   cannot calculate stop time for "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));
   if (grid.level == 0)          return(_NULL(catch("CalculateSequenceStopTime(2)   cannot calculate stop time for sequence at level "+ grid.level, ERR_RUNTIME_ERROR)));

   datetime stopTime;
   int n=grid.level, size=ArraySize(orders.ticket);

   for (int i=size-1; n != 0; i--) {
      if (orders.closeTime[i] == 0) return(_NULL(catch("CalculateSequenceStopTime(3)   #"+ orders.ticket[i] +" is not closed", ERR_RUNTIME_ERROR)));
      if (orders.type[i] == OP_UNDEFINED)                            // gestrichene Orders ignorieren
         continue;
      if (orders.closedBySL[i])                                      // ausgestoppte Positionen ignorieren
         continue;
      if (orders.level[i] != n)     return(_NULL(catch("CalculateSequenceStopTime(4)   #"+ orders.ticket[i] +" (level="+ orders.level[i] +") doesn't match the expected level "+ n, ERR_RUNTIME_ERROR)));

      stopTime = Max(stopTime, orders.closeTime[i]);

      if (n < 0) n++;
      else       n--;
   }
   return(stopTime);
}


/**
 * Ermittelt den durchschnittlichen StopPrice der aktuell gestoppten Sequenz.
 *
 * @return double
 */
double CalculateSequenceStopPrice() {
   if (status != STATUS_STOPPED) return(_NULL(catch("CalculateSequenceStopPrice(1)   cannot calculate stop price for "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));
   if (grid.level == 0)          return(_NULL(catch("CalculateSequenceStopPrice(2)   cannot calculate stop price for sequence at level "+ grid.level, ERR_RUNTIME_ERROR)));

   double stopPrice;
   int n=grid.level, size=ArraySize(orders.ticket);

   for (int i=size-1; n != 0; i--) {
      if (orders.closeTime[i] == 0) return(_NULL(catch("CalculateSequenceStopPrice(3)   #"+ orders.ticket[i] +" is not closed", ERR_RUNTIME_ERROR)));
      if (orders.type[i] == OP_UNDEFINED)                            // gestrichene Orders ignorieren
         continue;
      if (orders.closedBySL[i])                                      // ausgestoppte Positionen ignorieren
         continue;
      if (orders.level[i] != n)     return(_NULL(catch("CalculateSequenceStopPrice(4)   #"+ orders.ticket[i] +" (level="+ orders.level[i] +") doesn't match the expected level "+ n, ERR_RUNTIME_ERROR)));

      stopPrice += orders.closePrice[i];

      if (n < 0) n++;
      else       n--;
   }
   return(NormalizeDouble(stopPrice/Abs(grid.level), Digits));
}


/**
 * Zeichnet die Start-/Stop-Marker der Sequenz neu.
 */
void RedrawStartStop() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   static color last.MarkerColor = DodgerBlue;
   if (Breakeven.Color != CLR_NONE)
      last.MarkerColor = Breakeven.Color;

   datetime time;
   double   price;
   string   label;

   int starts = ArraySize(sequenceStartTimes);


   // (1) Start-Marker
   for (int i=0; i <= starts; i++) {
      if (starts == 0) {
         time  = instanceStartTime;
         price = instanceStartPrice;
      }
      else if (i == starts) {
         break;
      }
      else {
         time  = sequenceStartTimes [i];
         price = sequenceStartPrices[i];
      }

      label = StringConcatenate("SR.", sequenceId, ".start.", i);
      if (ObjectFind(label) == 0)
         ObjectDelete(label);

      if (startStopDisplayMode != SDM_NONE) {
         ObjectCreate(label, OBJ_ARROW, 0, time, price);
         ObjectSet   (label, OBJPROP_ARROWCODE, startStopDisplayMode);
         ObjectSet   (label, OBJPROP_BACK,      false               );
         ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor    );
      }
   }


   // (2) Stop-Marker
   for (i=0; i < starts; i++) {
      if (sequenceStopTimes[i] > 0) {
         time  = sequenceStopTimes [i];
         price = sequenceStopPrices[i];

         label = StringConcatenate("SR.", sequenceId, ".stop.", i);
         if (ObjectFind(label) == 0)
            ObjectDelete(label);

         if (startStopDisplayMode != SDM_NONE) {
            ObjectCreate(label, OBJ_ARROW, 0, time, price);
            ObjectSet   (label, OBJPROP_ARROWCODE, startStopDisplayMode);
            ObjectSet   (label, OBJPROP_BACK,      false               );
            ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor    );
         }
      }
   }

   catch("RedrawStartStop()");
}


/**
 * Zeichnet die ChartMarker aller Orders neu.
 */
void RedrawOrders() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   bool wasPending, isPending, closedPosition;
   int  size = ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      wasPending     = orders.pendingType[i] != OP_UNDEFINED;
      isPending      = orders.type[i] == OP_UNDEFINED;
      closedPosition = !isPending && orders.closeTime[i]!=0;

      if    (isPending)                         ChartMarker.OrderSent(i);
      else /*openPosition || closedPosition*/ {                                     // openPosition ist Folge einer
         if (wasPending)                        ChartMarker.OrderFilled(i);         // ...ausgeführten Pending-Order
         else                                   ChartMarker.OrderSent(i);           // ...oder Market-Order
         if (closedPosition)                    ChartMarker.PositionClosed(i);
      }
   }
}


/**
 * Wechselt den Modus der Start/Stopanzeige.
 *
 * @return int - Fehlerstatus
 */
int ToggleStartStopDisplayMode() {
   // Mode wechseln
   int i = SearchIntArray(startStopDisplayModes, startStopDisplayMode);    // #define SDM_NONE        - keine Anzeige -
   if (i == -1) {                                                          // #define SDM_MARKER      einfache Markierung
      startStopDisplayMode = SDM_PRICE;           // default               // #define SDM_PRICE       Markierung mit Preisangabe
   }
   else {
      int size = ArraySize(startStopDisplayModes);
      startStopDisplayMode = startStopDisplayModes[(i+1) % size];
   }

   // Anzeige aktualisieren
   RedrawStartStop();

   return(catch("ToggleStartStopDisplayMode()"));
}


/**
 * Wechselt den Modus der Orderanzeige.
 *
 * @return int - Fehlerstatus
 */
int ToggleOrderDisplayMode() {
   int pendings   = CountPendingOrders();
   int open       = CountOpenPositions();
   int stoppedOut = CountStoppedOutPositions();
   int closed     = CountClosedPositions();


   // Modus wechseln, dabei Modes ohne entsprechende Orders überspringen
   int oldMode      = orderDisplayMode;
   int size         = ArraySize(orderDisplayModes);
   orderDisplayMode = (orderDisplayMode+1) % size;

   while (orderDisplayMode != oldMode) {                                   // #define ODM_NONE        - keine Anzeige -
      if (orderDisplayMode == ODM_NONE) {                                  // #define ODM_STOPS       Pending,       StoppedOut
         break;                                                            // #define ODM_PYRAMID     Pending, Open,             Closed
      }                                                                    // #define ODM_ALL         Pending, Open, StoppedOut, Closed
      else if (orderDisplayMode == ODM_STOPS) {
         if (pendings+stoppedOut > 0)
            break;
      }
      else if (orderDisplayMode == ODM_PYRAMID) {
         if (pendings+open+closed > 0)
            if (open+stoppedOut+closed > 0)                                // ansonsten ist Anzeige identisch zu vorherigem Mode
               break;
      }
      else if (orderDisplayMode == ODM_ALL) {
         if (pendings+open+stoppedOut+closed > 0)
            if (stoppedOut > 0)                                            // ansonsten ist Anzeige identisch zu vorherigem Mode
               break;
      }
      orderDisplayMode = (orderDisplayMode+1) % size;
   }


   // Anzeige aktualisieren
   if (orderDisplayMode != oldMode) {
      RedrawOrders();
   }
   else {
      // nothing to change, Anzeige bleibt unverändert
      ForceSound("Windows XP-Batterie niedrig.wav");
   }
   return(catch("ToggleOrderDisplayMode()"));
}


/**
 * Wechselt den Modus der Breakeven-Anzeige.
 *
 * @return int - Fehlerstatus
 */
int ToggleBreakevenDisplayMode() {
   if (breakeven.Width == 0) breakeven.Width = 1;
   else                      breakeven.Width = 0;

   RecolorBreakeven();
   return(catch("ToggleBreakevenDisplayMode()"));
}


/**
 * Gibt die Anzahl der Pending-Orders der Sequenz zurück.
 *
 * @return int
 */
int CountPendingOrders() {
   int count, size=ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0)
         count++;
   }
   return(count);
}


/**
 * Gibt die Anzahl der offenen Positionen der Sequenz zurück.
 *
 * @return int
 */
int CountOpenPositions() {
   int count, size=ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      if (orders.type[i]!=OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0)
         count++;
   }
   return(count);
}


/**
 * Gibt die Anzahl der ausgestoppten Positionen der Sequenz zurück.
 *
 * @return int
 */
int CountStoppedOutPositions() {
   int count, size=ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      if (orders.closedBySL[i])
         count++;
   }
   return(count);
}


/**
 * Gibt die Anzahl der durch StopSequence() geschlossenen Positionen der Sequenz zurück.
 *
 * @return int
 */
int CountClosedPositions() {
   int count, size=ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      if (orders.type[i]!=OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]!=0) /*&&*/ if (!orders.closedBySL[i])
         count++;
   }
   return(count);
}


/**
 * Korrigiert die vom Terminal beim Abschicken einer Pending- oder Market-Order gesetzten oder nicht gesetzten Chart-Marker.
 *
 * @param  int i - Index des Ordertickets in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool ChartMarker.OrderSent(int i) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode()) return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("ChartMarker.OrderSent()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define ODM_NONE     0     // - keine Anzeige -
   #define ODM_STOPS    1     // Pending,       ClosedBySL
   #define ODM_PYRAMID  2     // Pending, Open,             Closed
   #define ODM_ALL      3     // Pending, Open, ClosedBySL, Closed
   */
   bool pending = orders.pendingType[i] != OP_UNDEFINED;

   int      type        =    ifInt(pending, orders.pendingType [i], orders.type     [i]);
   datetime openTime    =    ifInt(pending, orders.pendingTime [i], orders.openTime [i]);
   double   openPrice   = ifDouble(pending, orders.pendingPrice[i], orders.openPrice[i]);
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(orders.level[i], "+."));
   color    markerColor = CLR_NONE;

   if (orderDisplayMode != ODM_NONE) {
      if      (pending)                         markerColor = CLR_PENDING;
      else if (orderDisplayMode >= ODM_PYRAMID) markerColor = ifInt(IsLongTradeOperation(type), CLR_LONG, CLR_SHORT);
   }

   if (!ChartMarker.OrderSent_B(orders.ticket[i], Digits, markerColor, type, LotSize, Symbol(), openTime, openPrice, orders.stopLoss[i], 0, comment))
      return(_false(SetLastError(stdlib_PeekLastError())));
   return(true);
}


/**
 * Korrigiert die vom Terminal beim Ausführen einer Pending-Order gesetzten oder nicht gesetzten Chart-Marker.
 *
 * @param  int i - Index des Ordertickets in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool ChartMarker.OrderFilled(int i) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode()) return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("ChartMarker.OrderFilled()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define ODM_NONE     0     // - keine Anzeige -
   #define ODM_STOPS    1     // Pending,       ClosedBySL
   #define ODM_PYRAMID  2     // Pending, Open,             Closed
   #define ODM_ALL      3     // Pending, Open, ClosedBySL, Closed
   */
   string comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(orders.level[i], "+."));
   color  markerColor = CLR_NONE;

   if (orderDisplayMode >= ODM_PYRAMID)
      markerColor = ifInt(orders.type[i]==OP_BUY, CLR_LONG, CLR_SHORT);

   if (!ChartMarker.OrderFilled_B(orders.ticket[i], orders.pendingType[i], orders.pendingPrice[i], Digits, markerColor, LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], comment))
      return(_false(SetLastError(stdlib_PeekLastError())));
   return(true);
}


/**
 * Korrigiert die vom Terminal beim Schließen einer Position gesetzten oder nicht gesetzten Chart-Marker.
 *
 * @param  int i - Index des Ordertickets in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool ChartMarker.PositionClosed(int i) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode()) return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("ChartMarker.PositionClosed()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define ODM_NONE     0     // - keine Anzeige -
   #define ODM_STOPS    1     // Pending,       ClosedBySL
   #define ODM_PYRAMID  2     // Pending, Open,             Closed
   #define ODM_ALL      3     // Pending, Open, ClosedBySL, Closed
   */
   color markerColor = CLR_NONE;

   if (orderDisplayMode != ODM_NONE) {
      if ( orders.closedBySL[i] && orderDisplayMode!=ODM_PYRAMID) markerColor = CLR_CLOSE;
      if (!orders.closedBySL[i] && orderDisplayMode>=ODM_PYRAMID) markerColor = CLR_CLOSE;
   }

   if (!ChartMarker.PositionClosed_B(orders.ticket[i], Digits, markerColor, orders.type[i], LotSize, Symbol(), orders.openTime[i], orders.openPrice[i], orders.closeTime[i], orders.closePrice[i]))
      return(_false(SetLastError(stdlib_PeekLastError())));
   return(true);
}


/**
 * Ob die Sequenz im Tester erzeugt wurde, also ein Test ist. Der Aufruf dieser Funktion in Online-Charts mit einer im Tester
 * erzeugten Sequenz gibt daher ebenfalls TRUE zurück.
 *
 * @return bool
 */
bool IsTest() {
   return(test || IsTesting());
}


/**
 * Setzt die Größe der Datenarrays auf den angegebenen Wert.
 *
 * @param  int  size  - neue Größe
 * @param  bool reset - ob die Arrays komplett zurückgesetzt werden sollen
 *                      (default: nur neu hinzugefügte Felder werden initialisiert)
 *
 * @return int - neue Größe der Arrays
 */
int ResizeArrays(int size, bool reset=false) {
   int oldSize = ArraySize(orders.ticket);

   if (size != oldSize) {
      ArrayResize(orders.ticket,       size);
      ArrayResize(orders.level,        size);
      ArrayResize(orders.gridBase,     size);
      ArrayResize(orders.pendingType,  size);
      ArrayResize(orders.pendingTime,  size);
      ArrayResize(orders.pendingPrice, size);
      ArrayResize(orders.type,         size);
      ArrayResize(orders.openTime,     size);
      ArrayResize(orders.openPrice,    size);
      ArrayResize(orders.risk,         size);
      ArrayResize(orders.closeTime,    size);
      ArrayResize(orders.closePrice,   size);
      ArrayResize(orders.stopLoss,     size);
      ArrayResize(orders.closedBySL,   size);
      ArrayResize(orders.swap,         size);
      ArrayResize(orders.commission,   size);
      ArrayResize(orders.profit,       size);
   }

   if (reset) {                                                      // alle Felder zurücksetzen
      if (size != 0) {
         ArrayInitialize(orders.ticket,                  0);
         ArrayInitialize(orders.level,                   0);
         ArrayInitialize(orders.gridBase,                0);
         ArrayInitialize(orders.pendingType,  OP_UNDEFINED);
         ArrayInitialize(orders.pendingTime,             0);
         ArrayInitialize(orders.pendingPrice,            0);
         ArrayInitialize(orders.type,         OP_UNDEFINED);
         ArrayInitialize(orders.openTime,                0);
         ArrayInitialize(orders.openPrice,               0);
         ArrayInitialize(orders.risk,                    0);
         ArrayInitialize(orders.closeTime,               0);
         ArrayInitialize(orders.closePrice,              0);
         ArrayInitialize(orders.stopLoss,                0);
         ArrayInitialize(orders.closedBySL,          false);
         ArrayInitialize(orders.swap,                    0);
         ArrayInitialize(orders.commission,              0);
         ArrayInitialize(orders.profit,                  0);
      }
   }
   else {
      for (int i=oldSize; i < size; i++) {
         orders.pendingType[i] = OP_UNDEFINED;                       // Hinzugefügte pendingType- und type-Felder immer re-initialisieren,
         orders.type       [i] = OP_UNDEFINED;                       // 0 ist ein gültiger Wert und daher als Default unzulässig.
      }
   }

   catch("ResizeArrays()");
   return(size);

   // Dummy-Calls, unterdrücken unnütze Compilerwarnungen
   BreakevenEventToStr(NULL);
   DistanceToProfit(NULL);
   GetFullStatusDirectory();
   GetFullStatusFileName();
   GetMqlStatusDirectory();
   GetMqlStatusFileName();
   GridDirectionToStr(NULL);
   OrderDisplayModeToStr(NULL);
   StatusToStr(NULL);
   UploadStatus(NULL, NULL, NULL, NULL);
}


/**
 * Gibt die lesbare Konstante eines Status-Codes zurück.
 *
 * @param  int status - Status-Code
 *
 * @return string
 */
string StatusToStr(int status) {
   switch (status) {
      case STATUS_UNINITIALIZED: return("STATUS_UNINITIALIZED");
      case STATUS_WAITING      : return("STATUS_WAITING"      );
      case STATUS_STARTING     : return("STATUS_STARTING"     );
      case STATUS_PROGRESSING  : return("STATUS_PROGRESSING"  );
      case STATUS_STOPPING     : return("STATUS_STOPPING"     );
      case STATUS_STOPPED      : return("STATUS_STOPPED"      );
      case STATUS_DISABLED     : return("STATUS_DISABLED"     );
   }
   return(_empty(catch("StatusToStr()  invalid parameter status = "+ status, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die Beschreibung eines Status-Codes zurück.
 *
 * @param  int status - Status-Code
 *
 * @return string
 */
string StatusDescription(int status) {
   switch (status) {
      case STATUS_UNINITIALIZED: return("not initialized");
      case STATUS_WAITING      : return("waiting"        );
      case STATUS_STARTING     : return("starting"       );
      case STATUS_PROGRESSING  : return("progressing"    );
      case STATUS_STOPPING     : return("stopping"       );
      case STATUS_STOPPED      : return("stopped"        );
      case STATUS_DISABLED     : return("disabled"       );
   }
   return(_empty(catch("StatusDescription()  invalid parameter status = "+ status, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante eines OrderDisplay-Modes zurück.
 *
 * @param  int mode - OrderDisplay-Mode
 *
 * @return string
 */
string OrderDisplayModeToStr(int mode) {
   switch (mode) {
      case ODM_NONE   : return("ODM_NONE"   );
      case ODM_STOPS  : return("ODM_STOPS"  );
      case ODM_PYRAMID: return("ODM_PYRAMID");
      case ODM_ALL    : return("ODM_ALL"    );
   }
   return(_empty(catch("OrderDisplayModeToStr()  invalid parameter mode = "+ mode, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante eines Breakeven-Events zurück.
 *
 * @param  int type - Event-Type
 *
 * @return string
 */
string BreakevenEventToStr(int type) {
   switch (type) {
      case EV_SEQUENCE_START  : return("EV_SEQUENCE_START"  );
      case EV_SEQUENCE_STOP   : return("EV_SEQUENCE_STOP"   );
      case EV_GRIDBASE_CHANGE : return("EV_GRIDBASE_CHANGE" );
      case EV_POSITION_OPEN   : return("EV_POSITION_OPEN"   );
      case EV_POSITION_STOPOUT: return("EV_POSITION_STOPOUT");
      case EV_POSITION_CLOSE  : return("EV_POSITION_CLOSE"  );
   }
   return(_empty(catch("BreakevenEventToStr()  illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante eines GridDirection-Codes zurück.
 *
 * @param  int direction - GridDirection
 *
 * @return string
 */
string GridDirectionToStr(int direction) {
   switch (direction) {
      case D_BIDIR     : return("D_BIDIR"     );
      case D_LONG      : return("D_LONG"      );
      case D_SHORT     : return("D_SHORT"     );
      case D_LONG_SHORT: return("D_LONG_SHORT");
   }
   return(_empty(catch("GridDirectionToStr()  illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die Beschreibung eines GridDirection-Codes zurück.
 *
 * @param  int direction - GridDirection
 *
 * @return string
 */
string GridDirectionDescription(int direction) {
   switch (direction) {
      case D_BIDIR     : return("bidirectional");
      case D_LONG      : return("long"         );
      case D_SHORT     : return("short"        );
      case D_LONG_SHORT: return("long + short" );
   }
   return(_empty(catch("GridDirectionDescription()  illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE)));
}
