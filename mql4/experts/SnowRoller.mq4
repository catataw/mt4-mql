/**
 * SnowRoller - Pyramiding Trade Manager
 *
 *
 *  TODO:
 *  -----
 *  - Resume implementieren                                                                           *
 *  - automatisches Pause/Resume am Wochenende implementieren                                         *
 *  - StartConditions vervollständigen                                                                *
 *  - StopConditions vervollständigen                                                                 *
 *  - StartCondition "@level" implementieren (GBP/AUD 02.04.)                                         *
 *  - StartSequence: bei @level(1) zurück auf @price(@level(0.5)) gehen (Stop 1 liegt sehr ungünstig) *
 *  - Änderungen der Gridbasis während Auszeit erkennen                                               *
 *  - PendingOrders nicht per Tick trailen                                                            *
 *  - bidirektionales Grid entfernen                                                                  *
 *  - beidseitig unidirektionales Grid implementieren                                                 *
 *  - Build 419 silently crashes                                                                      *
 *
 *  - execution[] um tatsächlichen OrderStopLoss() und OrderTakeprofit() erweitern
 *  - Bug: BE-Anzeige ab erstem Trade, laufende Sequenzen bis zum aktuellen Moment
 *  - Bug: ChartMarker bei PendingOrders + Stops
 *  - Bug: Crash, wenn Statusdatei der geladenen Testsequenz gelöscht wird
 *  - onBarOpen(PERIOD_M1) für Breakeven-Indikator implementieren
 *  - EventListener.BarOpen() muß Event auch erkennen, wenn er nicht bei jedem Tick aufgerufen wird
 *  - Logging: alle Trade-Operationen und Trade-Request-Fehler, Slippage, Aufruf von MessageBoxen
 *  - Logging im Tester reduzieren
 *  - Upload der Statusdatei implementieren
 *  - Heartbeat implementieren
 *  - STATUS_MONITORING implementieren
 *  - Client-Side-Limits implementieren
 *  - Alpari: wiederholte Trade-Timeouts von exakt 200 sec.
 *  - Alpari: StopOrder-Slippage EUR/USD bis zu 3.9 pip, GBP/AUD bis zu 6 pip
 */
#include <types.mqh>
#define     __TYPE__      T_EXPERT
int   __INIT_FLAGS__[] = {INIT_TICKVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>
#include <SnowRoller/define.mqh>


//////////////////////////////////////////////////////////////// externe Parameter ////////////////////////////////////////////////////////////////

extern /*transient*/ string Sequence.ID           = "";
extern               string GridDirection         = "Bidirectional* | Long | Short | Long+Short";
extern               int    GridSize              = 20;
extern               double LotSize               = 0.1;
extern               string StartConditions       = "";                       // @limit(1.33) && @time(2012.03.12 12:00)
extern               string StopConditions        = "@profit(20%)";           // @limit(1.33) || @time(2012.03.12 12:00) || @profit(1234.00) || @profit(10%) || @profit(10%E)
extern /*transient*/ string OrderDisplayMode      = "None";
extern               string OrderDisplayMode.Help = "None* | Stops | Pyramid | All";
extern /*transient*/ color  Breakeven.Color       = DodgerBlue;
extern /*transient*/ int    Breakeven.Width       = 1;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   last.Sequence.ID      = "";                  // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE
string   last.GridDirection    = "";                  // mit den Default-Werten überschrieben. Um dies zu verhindern und um geänderte Parameter mit
int      last.GridSize;                               // alten Werten vergleichen zu können, werden sie in deinit() in last.* zwischengespeichert und
double   last.LotSize;                                // in init() daraus restauriert.
string   last.StartConditions  = "";
string   last.StopConditions   = "";
string   last.OrderDisplayMode = "";
color    last.Breakeven.Color;
int      last.Breakeven.Width;

int      status = STATUS_UNINITIALIZED;

int      sequenceId;
bool     test = false;                                // ob diese Sequenz ein Test ist oder war (*nicht*, ob der Test gerade läuft)

datetime instanceStartTime;                           // Start des EA's
double   instanceStartPrice;
double   sequenceStartEquity;                         // Equity bei Start der ersten Subsequenz

datetime sequenceStartTimes [];                       // Start/Resume-Daten
double   sequenceStartPrices[];

datetime sequenceStopTimes  [];                       // Pause/Stop-Daten
double   sequenceStopPrices [];

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

int      grid.stops;                                  // Anzahl der bisher getriggerten Stops                                       SS Realized:    Feld 1
double   grid.stopsPL;                                // P/L der ausgestoppten Positionen (0 oder negativ)                          SS Realized:    Feld 2
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

int      orders.ticket           [];
int      orders.level            [];                  // Gridlevel der Order
double   orders.gridBase         [];                  // Gridbasis der Order

int      orders.pendingType      [];                  // Pending-Orderdaten (falls zutreffend)
datetime orders.pendingTime      [];                  // Zeitpunkt von OrderOpen()
datetime orders.pendingModifyTime[];                  // Zeitpunkt des letzten OrderModify()
double   orders.pendingPrice     [];

int      orders.type             [];
datetime orders.openTime         [];
double   orders.openPrice        [];
double   orders.risk             [];                  // Risiko des Levels (0, solange Order pending, danach positiv)

datetime orders.closeTime        [];
double   orders.closePrice       [];
double   orders.stopLoss         [];
bool     orders.closedByStop     [];

double   orders.swap             [];
double   orders.commission       [];
double   orders.profit           [];

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

int      orderDisplayMode;
bool     firstTick          = true;
bool     firstTickConfirmed = false;


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

      // temporär
      if (IsTesting()) {
         static bool done;
         if (!done) {
            if (TimeCurrent() > sequenceStopTimes[ArraySize(sequenceStopTimes)-1] + 6.5*HOURS) {
               Tester.Pause();
               done = true;
            }
         }
      }
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
         case STATUS_WAITING:
         case STATUS_PROGRESSING:
            if (UpdateStatus())
               StopSequence();
            ShowStatus();
      }
      return(last_error);
   }

   return(catch("onChartCommand(2)   unknow command = \""+ cmd +"\"", ERR_INVALID_FUNCTION_PARAMVALUE));
}


/**
 * Handler für BarOpen-Events.
 *
 * @param int timeframes[] - IDs der Timeframes, in denen das BarOpen-Event aufgetreten ist
 *
 * @return int - Fehlerstatus
 */
int onBarOpen(int timeframes[]) {
   Grid.DrawBreakeven();
   return(catch("onBarOpen()"));
}


/**
 * Startet eine neue Trade-Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (status != STATUS_WAITING)             return(_false(catch("StartSequence(1)   cannot start "+ StatusDescription(status) +" trade sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to start a new trade sequence now?", __NAME__ +" - StartSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("StartSequence(2)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // Startvariablen und Status setzen
   sequenceStartEquity = AccountEquity()-AccountCredit();

   datetime startTime  = TimeCurrent() - 1;                          // Wir setzen startTime um 1 sec. in die Vergangenheit. Ansonsten wäre es möglich, daß
   double   startPrice = NormalizeDouble((Bid + Ask)/2, Digits);     // startTime und OpenTime() des nächsten Tickets denselben Timestamp haben, wodurch eine
   Grid.BaseReset(startTime, startPrice);                            // eindeutige Sortierung der Breakeven-Events für den Breakeven-Indikator unmöglich wäre.

   ArrayPushInt   (sequenceStartTimes,  startTime );
   ArrayPushDouble(sequenceStartPrices, startPrice);
   ArrayPushInt   (sequenceStopTimes,   0);                          // Größe von sequenceStarts und -Stops synchron halten
   ArrayPushDouble(sequenceStopPrices,  0);

   status = STATUS_PROGRESSING;


   // Stop-Orders in den Markt legen
   if (!UpdatePendingOrders())
      return(false);

   RedrawStartStop();
   return(IsNoError(catch("StartSequence(3)")));
}


/**
 * Schließt alle PendingOrders und offenen Positionen der Sequenz.
 *
 * @return bool - Erfolgsstatus: ob die Sequenz erfolgreich gestoppt wurde
 */
bool StopSequence() {
   if (__STATUS__CANCELLED || IsLastError())                 return( false);
   if (status!=STATUS_WAITING && status!=STATUS_PROGRESSING) return(_false(catch("StopSequence(1)   cannot stop "+ StatusDescription(status) +" trade sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                              // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to stop the sequence now?", __NAME__ +" - StopSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("StopSequence(2)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) eine wartende Sequenz ist noch nicht gestartet und wird gecanceled
   if (status == STATUS_WAITING) {
      __STATUS__CANCELLED = true;
      return(_false(catch("StopSequence(3)")));
   }


   // (2) PendingOrders und OpenPositions einlesen
   int pendingOrders[], openPositions[], sizeOfTickets=ArraySize(orders.ticket);
   ArrayResize(pendingOrders, 0);
   ArrayResize(openPositions, 0);

   for (int i=0; i < sizeOfTickets; i++) {
      if (orders.closeTime[i] == 0) {                                   // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "StopSequence(4)"))
            return(false);
         if (OrderCloseTime() == 0) {                                   // offene Tickets je nach Typ zwischenspeichern
            if (IsPendingTradeOperation(OrderType())) ArrayPushInt(pendingOrders, orders.ticket[i]);
            else                                      ArrayPushInt(openPositions, orders.ticket[i]);
         }
      }
   }


   // (3) offene Positionen schließen
   bool   ordersChanged;
   int    sizeOfOpenPositions = ArraySize(openPositions);
   int    n = ArraySize(sequenceStopTimes) - 1;
   double execution[] = {NULL};

   status = STATUS_STOPPING;

   if (sizeOfOpenPositions > 0) {
      if (!OrderMultiClose(openPositions, NULL, CLR_CLOSE, execution))
         return(_false(SetLastError(stdlib_PeekLastError())));

      sequenceStopTimes [n] =                 execution[EXEC_TIME ] +0.1;     // (datetime)(double) datetime
      sequenceStopPrices[n] = NormalizeDouble(execution[EXEC_PRICE], Digits);

      for (i=0; i < sizeOfOpenPositions; i++) {
         int pos = SearchIntArray(orders.ticket, openPositions[i]);

         orders.closeTime   [pos] = execution[9*i+EXEC_TIME      ] +0.1;      // (datetime)(double) datetime
         orders.closePrice  [pos] = execution[9*i+EXEC_PRICE     ];
         orders.closedByStop[pos] = false;

         orders.swap        [pos] = execution[9*i+EXEC_SWAP      ];
         orders.commission  [pos] = execution[9*i+EXEC_COMMISSION];
         orders.profit      [pos] = execution[9*i+EXEC_PROFIT    ];

         grid.closedPL += orders.swap[pos] + orders.commission[pos] + orders.profit[pos];
      // grid.activeRisk/grid.valueAtRisk ändern sich nur bei Level-Änderung, nicht bei StopSequence()
      }

      /*
      grid.floatingPL      = ...          // Solange unten UpdateStatus() aufgerufen wird, werden diese Werte dort automatisch aktualisiert.
      grid.totalPL         = ...
      grid.maxProfit       = ...
      grid.maxProfitTime   = ...
      grid.maxDrawdown     = ...
      grid.maxDrawdownTime = ...
      */
      ordersChanged = true;
   }
   else {
      sequenceStopTimes [n] = TimeCurrent();
      sequenceStopPrices[n] = (Bid + Ask)/2;
      if      (grid.base < sequenceStopPrices[n]) sequenceStopPrices[n] = Bid;
      else if (grid.base > sequenceStopPrices[n]) sequenceStopPrices[n] = Ask;
      sequenceStopPrices[n] = NormalizeDouble(sequenceStopPrices[n], Digits);
   }


   // (4) Pending-Orders streichen
   int sizeOfPendingOrders = ArraySize(pendingOrders);

   for (i=0; i < sizeOfPendingOrders; i++) {
      if (!Grid.DeleteOrder(pendingOrders[i]))
         return(false);
      ordersChanged = true;
   }


   // (5) Daten aktualisieren und speichern
   status = STATUS_STOPPED;
   if (ordersChanged) {
      if (!UpdateStatus()) return(false);
      if (  !SaveStatus()) return(false);
   }
   RedrawStartStop();


   debug("StopSequence()      level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));

   ArrayResize(pendingOrders, 0);
   ArrayResize(openPositions, 0);
   ArrayResize(execution,     0);
   return(IsNoError(catch("StopSequence(5)")));
}


/**
 * Setzt ein vorher gestoppte Sequenz fort.
 *
 * @return bool - Erfolgsstatus
 */
bool ResumeSequence() {
   if (__STATUS__CANCELLED || IsLastError()) return( false);
   if (status != STATUS_STOPPED)             return(_false(catch("ResumeSequence(1)   cannot resume "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to resume the sequence now?", __NAME__ +" - ResumeSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("ResumeSequence(2)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;



   if (!IsTesting() && !IsDemo()) return(_true(debug("ResumeSequence()   online not yet implemented")));



   // (1) neue Gridbasis und Sequenzstart setzen
   datetime startTime  = TimeCurrent() - 1;                                      // Wir setzen startTime um 1 sec. in die Vergangenheit. Ansonsten wäre es möglich, daß
   double   startPrice = (Bid + Ask)/2;                                          // startTime und OpenTime() des nächsten Tickets denselben Timestamp haben, wodurch eine
   double   stopPrice  = sequenceStopPrices[ArraySize(sequenceStopPrices)-1];    // eindeutige Sortierung der Breakeven-Events für den Breakeven-Indikator unmöglich wäre.
   if      (grid.base < stopPrice) startPrice = Ask;
   else if (grid.base > stopPrice) startPrice = Bid;
   startPrice = NormalizeDouble(startPrice, Digits);

   Grid.BaseChange(startTime, grid.base + startPrice - stopPrice);

   ArrayPushInt   (sequenceStartTimes,  startTime );
   ArrayPushDouble(sequenceStartPrices, startPrice);
   ArrayPushInt   (sequenceStopTimes,   0);                                      // Größe von sequenceStarts und -Stops synchron halten
   ArrayPushDouble(sequenceStopPrices,  0);


   // (2) vorherige Positionen wieder in den Markt legen
   if (!ReopenPositions())
      return(false);
   status = STATUS_PROGRESSING;


   // (3) Stop-Orders vervollständigen
   if (!UpdatePendingOrders())
      return(false);


   // (4) Start-/Stop-Bedingungen zunächst deaktivieren (können später wieder angepaßt werden)
   start.conditions = false; StartConditions = "";                               // nur um Anzeige in ShowStatus() zu unterdrücken
   stop.conditions  = false; StopConditions  = "";
   SS.StartStopConditions();

   debug("ResumeSequence()    level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));


   // (5) Breakeven neu berechnen und aktualisieren
   string beOld = str.grid.breakeven;
   if (grid.maxLevelLong-grid.maxLevelShort > 0)                                 // jedoch nicht vorm ersten ausgeführten Trade
      Grid.UpdateBreakeven();


   RedrawStartStop();
   return(IsNoError(catch("ResumeSequence(3)")));

/*                                      ausgestoppt        closed           floating           total         activeRisk         gesamtRisk
-----------------------------------------------------------------------------------------------------------------------------------------------
StopSequence()      level=-4  stops=2  stopsPL=-36.00  closedPL=145.20  floatingPL=  0.00  totalPL=109.20  activeRisk=72.00  valueAtRisk=108.00
ResumeSequence()    level=-4  stops=2  stopsPL=-36.00  closedPL=145.20  floatingPL=  0.00  totalPL=109.20  activeRisk=72.00  valueAtRisk=108.00
SynchronizeStatus() level=-4  stops=2  stopsPL=-36.00  closedPL=145.20  floatingPL=  0.00  totalPL=109.20  activeRisk=72.00  valueAtRisk=108.00
*/
}


/**
 * Prüft und synchronisiert die im EA gespeicherten mit den aktuellen Laufzeitdaten.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatus() {
   if (__STATUS__CANCELLED || IsLastError()) return(false);
   if (status == STATUS_WAITING)             return(true);
   if (IsTest()) /*&&*/ if (!IsTesting())    return(true);


   grid.floatingPL = 0;

   bool     wasPending, isClosed, recalcBreakeven, openTickets;
   datetime stopTime;
   double   stopPrice;
   int      sizeOfTickets = ArraySize(orders.ticket);


   // (1) Tickets aktualisieren
   for (int i=0; i < sizeOfTickets; i++) {
      if (orders.closeTime[i] == 0) {                                                                 // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "UpdateStatus(1)"))
            return(false);

         wasPending = orders.type[i] == OP_UNDEFINED;                                                 // ob das Ticket beim letzten Aufruf "pending" war

         if (wasPending) {
            // beim letzten Aufruf Pending-Order
            if (OrderType() != orders.pendingType[i]) {                                               // Order wurde ausgeführt
               orders.type      [i] = OrderType();
               orders.openTime  [i] = OrderOpenTime();
               orders.openPrice [i] = OrderOpenPrice();
               orders.risk      [i] = CalculateActiveRisk(orders.level[i], orders.ticket[i], OrderOpenPrice(), OrderSwap(), OrderCommission());
               orders.swap      [i] = OrderSwap();
               orders.commission[i] = OrderCommission();
               orders.profit    [i] = OrderProfit();
               ChartMarker.OrderFilled(i);

               grid.level        += MathSign(orders.level[i]);
               grid.maxLevelLong  = MathMax(grid.level, grid.maxLevelLong ) +0.1;                     // (int) double
               grid.maxLevelShort = MathMin(grid.level, grid.maxLevelShort) -0.1; SS.Grid.MaxLevel(); // (int) double
               grid.activeRisk   += orders.risk[i];
               grid.valueAtRisk  += orders.risk[i]; SS.Grid.ValueAtRisk();                            // valueAtRisk = -stopsPL + activeRisk
               recalcBreakeven    = true;
            }
         }
         else {
            // beim letzten Aufruf offene Position
            if (NE(orders.swap[i], OrderSwap())) {                                                    // bei Swap-Änderung activeRisk und valueAtRisk justieren
               grid.activeRisk  -= (OrderSwap()-orders.swap[i]);
               grid.valueAtRisk -= (OrderSwap()-orders.swap[i]); SS.Grid.ValueAtRisk();
               recalcBreakeven   = true;
            }
            orders.swap      [i] = OrderSwap();
            orders.commission[i] = OrderCommission();
            orders.profit    [i] = OrderProfit();
         }

         isClosed = OrderCloseTime() != 0;                                                            // ob das Ticket jetzt geschlossen ist

         if (!isClosed) {                                                                             // weiterhin offenes Ticket
            grid.floatingPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
            openTickets = true;
         }
         else {                                                                                       // jetzt geschlossenes Ticket: gestrichene Pending-Order oder geschlossene Position
            orders.closeTime [i] = OrderCloseTime();                                                  // Bei Spikes kann eine Pending-Order ausgeführt *und* bereits geschlossen sein.
            orders.closePrice[i] = OrderClosePrice();

            if (orders.type[i] == OP_UNDEFINED) {                                                     // gestrichene Pending-Order
            }
            else {                                                                                    // geschlossene Position
               orders.closedByStop[i] = IsOrderClosedByStop();
               ChartMarker.PositionClosed(i);

               if (orders.closedByStop[i]) {                                                          // ausgestoppt
                  grid.level      -= MathSign(orders.level[i]);
                  grid.stops++;
                  grid.stopsPL    += orders.swap[i] + orders.commission[i] + orders.profit[i]; SS.Grid.Stops();
                  grid.activeRisk -= orders.risk[i];
                  grid.valueAtRisk = grid.activeRisk - grid.stopsPL; SS.Grid.ValueAtRisk();           // valueAtRisk = -stopsPL + activeRisk
                  recalcBreakeven  = true;
               }
               else {                                                                                 // Sequenzstop
                  grid.closedPL += orders.swap[i] + orders.commission[i] + orders.profit[i];
                  if (stopTime==0 || orders.closeTime[i] < stopTime) {                                // TODO: wird die Sequenz außerhalb Stück für Stück geschlossen, muß nach
                     stopTime  = orders.closeTime [i];                                                //       Abschluß des Stops avg(stopPrice) berechnet werden.
                     stopPrice = orders.closePrice[i];
                  }
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
   if (stopTime > 0) {                                                                                // mindestens eine Position wurde nicht durch StopLoss geschlossen
      if (openTickets) status = STATUS_STOPPING;                                                      // mindestens ein Ticket ist noch offen
      else             status = STATUS_STOPPED;                                                       // alle Tickets sind geschlossen
      int n = ArraySize(sequenceStopTimes) - 1;

      if (sequenceStopTimes[n]==0 || stopTime < sequenceStopTimes[n]) {
         sequenceStopTimes [n] = stopTime;
         sequenceStopPrices[n] = NormalizeDouble(stopPrice, Digits);
      }
      RedrawStartStop();
   }


   // (4) ggf. Gridbasis trailen
   if (status == STATUS_PROGRESSING) {
      if (grid.level == 0) {
         double last.grid.base = grid.base;

         if      (grid.direction == D_LONG ) grid.base = MathMin(grid.base, NormalizeDouble((Bid + Ask)/2, Digits));
         else if (grid.direction == D_SHORT) grid.base = MathMax(grid.base, NormalizeDouble((Bid + Ask)/2, Digits));

         if (NE(grid.base, last.grid.base)) {
            Grid.BaseChange(TimeCurrent(), grid.base);
            recalcBreakeven = true;
         }
      }


      // (5) ggf. Breakeven neu berechnen und anzeigen
      if (grid.maxLevelLong-grid.maxLevelShort > 0) {                                                 // nicht vorm ersten ausgeführten Trade
         if (recalcBreakeven) {
            Grid.UpdateBreakeven();
         }
         else {                                                                                       // mind. 1 x je Minute Anzeige aktualisieren
            if      (!IsTesting())   HandleEvent(EVENT_BAR_OPEN/*, F_PERIOD_M1*/);
            else if (IsVisualMode()) HandleEvent(EVENT_BAR_OPEN);                                     // TODO: EventListener muß Event auch ohne permanenten Aufruf erkennen
         }                                                                                            // TODO: langlaufendes UpdateStatus() überspringt evt. BarOpen-Event
      }
   }

   return(!IsLastError() && IsNoError(catch("UpdateStatus(2)")));
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

   static string label;
   static int    sid;

   if (sequenceId != sid) {                                          // Label wird nur modifiziert, wenn es sich tatsächlich ändert
      label = StringConcatenate(__NAME__, ".", Sequence.ID, ".command");
      sid   = sequenceId;
   }

   if (ObjectFind(label) == 0) {
      ArrayPushString(commands, ObjectDescription(label));
      ObjectDelete(label);
      return(true);
   }
   return(false);
}


/**
 * Ob der StopLoss der aktuell selektierten Order getriggert wurde.
 *
 * @return bool
 */
bool IsOrderClosedByStop() {
   bool position     = OrderType()==OP_BUY || OrderType()==OP_SELL;
   bool closed       = OrderCloseTime() != 0;                        // geschlossene Position
   bool closedByStop = false;

   if (closed) /*&&*/ if (position) {
      if (StringIEndsWith(OrderComment(), "[sl]")) {
         closedByStop = true;
      }
      else {
         // Bei client-side-Limits StopLoss aus Griddaten verwenden.
         double stopLoss = OrderStopLoss();
         if (EQ(stopLoss, 0)) {
            int i = SearchIntArray(orders.ticket, OrderTicket());
            if (i == -1)
               return(_false(catch("IsOrderClosedByStop(1)   #"+ OrderTicket() +" not found in grid arrays", ERR_RUNTIME_ERROR)));
            stopLoss = NormalizeDouble(orders.stopLoss[i], Digits);
            if (EQ(stopLoss, 0))
               return(_false(catch("IsOrderClosedByStop(2)   #"+ OrderTicket() +" no stopLoss found in grid arrays", ERR_RUNTIME_ERROR)));
         }
         if      (OrderType() == OP_BUY ) closedByStop = LE(OrderClosePrice(), stopLoss);
         else if (OrderType() == OP_SELL) closedByStop = GE(OrderClosePrice(), stopLoss);
      }
   }
   return(closedByStop);
}


/**
 * Signalgeber für StartSequence(). Die einzelnen Bedingungen sind AND-verknüpft.
 *
 * @return bool - ob alle konfigurierten Startbedingungen erfüllt sind
 */
bool IsStartSignal() {
   if (__STATUS__CANCELLED || IsLastError())
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
   if (__STATUS__CANCELLED || IsLastError())              return(false);
   if (status==STATUS_STOPPING || status==STATUS_STOPPED) return(false);

   bool nextOrderExists, ordersChanged;
   int  nextLevel = grid.level + MathSign(grid.level);

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

   return(IsNoError(catch("UpdatePendingOrders()")));
}


/**
 * Öffnet die zuletzt offenen Positionen der Sequenz neu.
 *
 * @return bool - Erfolgsstatus
 */
bool ReopenPositions() {
   if (__STATUS__CANCELLED || IsLastError()) return(false);
   if (status != STATUS_STOPPED)             return(_false(catch("ReopenPositions(1)   cannot re-open positions of "+ StatusDescription(status) +" sequence", ERR_RUNTIME_ERROR)));

   // activeRisk zurücksetzen und neu berechnen
   grid.activeRisk = 0;

   if (grid.level > 0) {
      for (int level=1; level <= grid.level; level++) {                          // TODO: STOP_LEVEL-Fehler im letzten Level abfangen und behandeln
         if (!Grid.AddPosition(OP_BUY, level))
            return(false);
         grid.activeRisk += orders.risk[ArraySize(orders.risk)-1];
      }
   }
   else if (grid.level < 0) {
      for (level=-1; level >= grid.level; level--) {                             // TODO: STOP_LEVEL-Fehler im letzten Level abfangen und behandeln
         if (!Grid.AddPosition(OP_SELL, level))
            return(false);
         grid.activeRisk += orders.risk[ArraySize(orders.risk)-1];
      }
   }
   else {
      // grid.level==0: beim letzten Stop waren keine Positionen offen
   }

   // valueAtRisk neu berechnen
   grid.valueAtRisk = grid.activeRisk - grid.stopsPL; SS.Grid.ValueAtRisk();     // valueAtRisk = -stopsPL + activeRisk

   return(IsNoError(catch("ReopenPositions(2)")));
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

   if (grid.maxLevelLong-grid.maxLevelShort == 0) {                  // vor dem ersten ausgeführten Trade werden vorhandene Werte überschrieben
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
   if (__STATUS__CANCELLED || IsLastError())
      return(false);

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to submit a new "+ OperationTypeDescription(type) +" order now?", __NAME__ +" - Grid.AddOrder()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.AddOrder(1)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) Order in den Markt legen
   double execution[] = {NULL};
   int ticket = PendingStopOrder(type, level, execution);
   if (ticket == -1)
      return(false);


   // (2) Daten speichern
   if (!OrderSelectByTicket(ticket, "Grid.AddOrder(2)"))
      return(false);

   //int    ticket            = OrderTicket();
   //int    level             = level;
   //double grid.base         = grid.base;

   int      pendingType       = type;
   datetime pendingTime       = execution[EXEC_TIME    ];
   datetime pendingModifyTime = NULL;
   double   pendingPrice      = execution[EXEC_PRICE   ];

   /*int*/  type              = OP_UNDEFINED;
   datetime openTime          = NULL;
   double   openPrice         = NULL;
   double   risk              = NULL;

   datetime closeTime         = NULL;
   double   closePrice        = NULL;
   double   stopLoss          = OrderStopLoss();
   bool     closedByStop      = false;

   double   swap              = NULL;
   double   commission        = NULL;
   double   profit            = NULL;

   if (!Grid.PushData(ticket, level, grid.base, pendingType, pendingTime, pendingModifyTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedByStop, swap, commission, profit))
      return(false);
   return(IsNoError(catch("Grid.AddOrder(3)")));
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
   if (__STATUS__CANCELLED || IsLastError())
      return(false);

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to submit a new "+ OperationTypeDescription(type) +" order now?", __NAME__ +" - Grid.AddPosition()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.AddPosition(1)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;


   // (1) Position öffnen
   double execution[] = {NULL};
   int ticket = MarketOrder(type, level, execution);
   if (ticket == -1)
      return(false);


   // (2) Daten speichern
   if (!OrderSelectByTicket(ticket, "Grid.AddPosition(2)"))
      return(false);

   //int    ticket            = ...                                  // unverändert
   //int    level             = ...                                  // unverändert
   //double grid.base         = ...                                  // unverändert

   int      pendingType       = OP_UNDEFINED;
   datetime pendingTime       = NULL;
   datetime pendingModifyTime = NULL;
   double   pendingPrice      = NULL;

   //int    type              = ...                                  // unverändert
   datetime openTime          = execution[EXEC_TIME ];
   double   openPrice         = execution[EXEC_PRICE];
   double   risk              = CalculateActiveRisk(level, ticket, openPrice, execution[EXEC_SWAP], execution[EXEC_COMMISSION]);

   datetime closeTime         = NULL;
   double   closePrice        = NULL;
   double   stopLoss          = OrderStopLoss();
   bool     closedByStop      = false;

   double   swap              = execution[EXEC_SWAP      ];          // falls Swap bereits bei OrderOpen gesetzt ist
   double   commission        = execution[EXEC_COMMISSION];
   double   profit            = NULL;

   if (!Grid.PushData(ticket, level, grid.base, pendingType, pendingTime, pendingModifyTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedByStop, swap, commission, profit))
      return(false);

   ArrayResize(execution, 0);
   return(IsNoError(catch("Grid.AddPosition(3)")));
}


/**
 * Justiert PendingOpenPrice() und StopLoss() der angegebenen Order beim Broker und aktualisiert die Gridarrays.
 *
 * @param  int i - Index der Order in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.TrailPendingOrder(int i) {
   if (__STATUS__CANCELLED || IsLastError())    return( false);
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("Grid.TrailPendingOrder(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (orders.type[i] != OP_UNDEFINED)          return(_false(catch("Grid.TrailPendingOrder(2)   cannot trail open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
   if (orders.closeTime[i] != 0)                return(_false(catch("Grid.TrailPendingOrder(3)   cannot trail cancelled order #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to modify the "+ OperationTypeDescription(orders.pendingType[i]) +" order #"+ orders.ticket[i] +" now?", __NAME__ +" - Grid.TrailPendingOrder()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.TrailPendingOrder(4)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;

   double stopPrice   = grid.base +          orders.level[i]  * GridSize * Pips;
   double stopLoss    = stopPrice - MathSign(orders.level[i]) * GridSize * Pips;
   color  markerColor = ifInt(orders.level[i] > 0, CLR_LONG, CLR_SHORT);
   double execution[] = {NULL};

   if (EQ(orders.pendingPrice[i], stopPrice)) /*&&*/ if (EQ(orders.stopLoss[i], stopLoss))
      return(_false(catch("Grid.TrailPendingOrder(5)   nothing to modify for #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   if (!OrderModifyEx(orders.ticket[i], stopPrice, stopLoss, NULL, NULL, markerColor, execution))
      return(_false(SetLastError(stdlib_PeekLastError())));

   orders.gridBase         [i] = NormalizeDouble(grid.base, Digits);
   orders.pendingModifyTime[i] = execution[EXEC_TIME];
   orders.pendingPrice     [i] = NormalizeDouble(stopPrice, Digits);
   orders.stopLoss         [i] = NormalizeDouble(stopLoss,  Digits);

   return(IsNoError(catch("Grid.TrailPendingOrder(6)")));
}


/**
 * Streicht die angegebene Order beim Broker und entfernt sie aus den Datenarrays des Grids.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DeleteOrder(int ticket) {
   if (__STATUS__CANCELLED || IsLastError())
      return(false);

   // Position in Datenarrays bestimmen
   int i = SearchIntArray(orders.ticket, ticket);
   if (i == -1)
      return(_false(catch("Grid.DeleteOrder(1)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   if (firstTick && !firstTickConfirmed) {                           // Sicherheitsabfrage bei Aufruf beim ersten Tick
      if (!IsTesting()) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to cancel the "+ OperationTypeDescription(orders.pendingType[i]) +" order #"+ ticket +" now?", __NAME__ +" - Grid.DeleteOrder()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK) {
            __STATUS__CANCELLED = true;
            return(_false(catch("Grid.DeleteOrder(2)")));
         }
         RefreshRates();
      }
   }
   firstTickConfirmed = true;

   double execution[] = {NULL};
   if (!OrderDeleteEx(ticket, CLR_NONE, execution))
      return(_false(SetLastError(stdlib_PeekLastError())));

   if (!Grid.DropTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.DeleteOrder(3)")));
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
 * @param  datetime pendingModifyTime
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
 * @param  bool     closedByStop
 *
 * @param  double   swap
 * @param  double   commission
 * @param  double   profit
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.PushData(int ticket, int level, double gridBase, int pendingType, datetime pendingTime, datetime pendingModifyTime, double pendingPrice, int type, datetime openTime, double openPrice, double risk, datetime closeTime, double closePrice, double stopLoss, bool closedByStop, double swap, double commission, double profit) {
   return(Grid.SetData(-1, ticket, level, gridBase, pendingType, pendingTime, pendingModifyTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedByStop, swap, commission, profit));
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
 * @param  datetime pendingModifyTime
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
 * @param  bool     closedByStop
 *
 * @param  double   swap
 * @param  double   commission
 * @param  double   profit
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.SetData(int position, int ticket, int level, double gridBase, int pendingType, datetime pendingTime, datetime pendingModifyTime, double pendingPrice, int type, datetime openTime, double openPrice, double risk, datetime closeTime, double closePrice, double stopLoss, bool closedByStop, double swap, double commission, double profit) {
   if (position < -1)
      return(_false(catch("Grid.SetData(1)   illegal parameter position = "+ position, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int i=position, size=ArraySize(orders.ticket);

   if      (position ==     -1) i = ResizeArrays(    size+1) - 1;
   else if (position  > size-1) i = ResizeArrays(position+1) - 1;

   orders.ticket           [i] = ticket;
   orders.level            [i] = level;
   orders.gridBase         [i] = NormalizeDouble(gridBase, Digits);

   orders.pendingType      [i] = pendingType;
   orders.pendingTime      [i] = pendingTime;
   orders.pendingModifyTime[i] = pendingModifyTime;
   orders.pendingPrice     [i] = NormalizeDouble(pendingPrice, Digits);

   orders.type             [i] = type;
   orders.openTime         [i] = openTime;
   orders.openPrice        [i] = NormalizeDouble(openPrice, Digits);
   orders.risk             [i] = NormalizeDouble(risk, 2);

   orders.closeTime        [i] = closeTime;
   orders.closePrice       [i] = NormalizeDouble(closePrice, Digits);
   orders.stopLoss         [i] = NormalizeDouble(stopLoss, Digits);
   orders.closedByStop     [i] = closedByStop;

   orders.swap             [i] = NormalizeDouble(swap,       2);
   orders.commission       [i] = NormalizeDouble(commission, 2);
   orders.profit           [i] = NormalizeDouble(profit,     2);

   return(!IsError(catch("Grid.SetData(2)")));
}


/**
 * Aktualisiert die Daten der lokal als *offen* markierten Order mit den Online-Daten.
 *
 * @param  int i - Orderindex
 *
 * @return bool - Erfolgsstatus
 *
 *
 *  NOTE: Wird nur in SynchronizeStatus() verwendet.
 *  -----
 */
bool Grid.UpdateOrder(int i) {
   if (i < 0 || i > ArraySize(orders.ticket)-1) return(_false(catch("Grid.UpdateOrder(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (orders.closeTime[i] != 0)                return(_false(catch("Grid.UpdateOrder(2)   cannot update #"+ orders.ticket[i] +" (marked as closed in grid arrays)", ERR_RUNTIME_ERROR)));

   // das Ticket ist bereits selektiert
   bool wasPending = orders.type[i] == OP_UNDEFINED;
   bool wasOpen    = !wasPending;
   bool isPending  = IsPendingTradeOperation(OrderType());
   bool isClosed   = OrderCloseTime() != 0;
   bool isOpen     = !isPending && !isClosed;


   // (1) Ticketdaten aktualisieren
    //orders.ticket           [i]                                    // unverändert
    //orders.level            [i]                                    // unverändert
    //orders.gridBase         [i]                                    // unverändert

   if (isPending) {
    //orders.pendingType      [i]                                    // unverändert
    //orders.pendingTime      [i]                                    // unverändert
    //orders.pendingModifyTime[i]                                    // n.a.
      orders.pendingPrice     [i] = OrderOpenPrice();                // kann sich bei EA-Ausfall im Moment von OrderModify() geändert haben
   }
   else if (wasPending) {
      orders.type             [i] = OrderType();
      orders.openTime         [i] = OrderOpenTime();
      orders.openPrice        [i] = OrderOpenPrice();
      orders.risk             [i] = CalculateActiveRisk(orders.level[i], orders.ticket[i], OrderOpenPrice(), OrderSwap(), OrderCommission());
   }

   if (isClosed) {
      orders.closeTime        [i] = OrderCloseTime();
      orders.closePrice       [i] = OrderClosePrice();
      orders.stopLoss         [i] = OrderStopLoss();                 // kann sich bei EA-Ausfall im Moment von OrderModify() geändert haben
      orders.closedByStop     [i] = IsOrderClosedByStop();
   }

   if (!isPending) {
      orders.swap             [i] = OrderSwap();
      orders.commission       [i] = OrderCommission();
      orders.profit           [i] = OrderProfit();
   }


   // (2) Sequenzdaten aktualisieren (für den theoretischen Fall, das Sequenz außerhalb geschlossen wird)
   if (isClosed && !orders.closedByStop[i]) {
      int n = ArraySize(sequenceStartTimes) - 1;
      if (sequenceStopTimes[n]==0 || orders.closeTime[i] < sequenceStopTimes[n]) {
         sequenceStopTimes [n] = orders.closeTime [i];
         sequenceStopPrices[n] = orders.closePrice[i];               // TODO: bei Schließen Stück-für-Stück muß avg(stopPrice) berechnet werden
      }
   }

   return(!IsLastError() && IsNoError(catch("Grid.UpdateOrder(3)")));
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
   ArraySpliceInts   (orders.ticket,            i, 1);
   ArraySpliceInts   (orders.level,             i, 1);
   ArraySpliceDoubles(orders.gridBase,          i, 1);

   ArraySpliceInts   (orders.pendingType,       i, 1);
   ArraySpliceInts   (orders.pendingTime,       i, 1);
   ArraySpliceInts   (orders.pendingModifyTime, i, 1);
   ArraySpliceDoubles(orders.pendingPrice,      i, 1);

   ArraySpliceInts   (orders.type,              i, 1);
   ArraySpliceInts   (orders.openTime,          i, 1);
   ArraySpliceDoubles(orders.openPrice,         i, 1);
   ArraySpliceDoubles(orders.risk,              i, 1);

   ArraySpliceInts   (orders.closeTime,         i, 1);
   ArraySpliceDoubles(orders.closePrice,        i, 1);
   ArraySpliceDoubles(orders.stopLoss,          i, 1);
   ArraySpliceBools  (orders.closedByStop,      i, 1);

   ArraySpliceDoubles(orders.swap,              i, 1);
   ArraySpliceDoubles(orders.commission,        i, 1);
   ArraySpliceDoubles(orders.profit,            i, 1);

   return(IsNoError(catch("Grid.DropTicket(2)")));
}


/**
 * Legt eine Stop-Order in den Markt.
 *
 * @param  int    type        - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int    level       - Gridlevel der Order
 * @param  double execution[] - ausführungsspezifische Daten
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int PendingStopOrder(int type, int level, double& execution[]) {
   if (__STATUS__CANCELLED || IsLastError())
      return(-1);

   if (type == OP_BUYSTOP) {
      if (level <= 0) return(_int(-1, catch("PendingStopOrder(1)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELLSTOP) {
      if (level >= 0) return(_int(-1, catch("PendingStopOrder(2)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("PendingStopOrder(3)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (ArraySize(execution) < 1)
      ArrayResize(execution, 1);
   execution[EXEC_FLAGS] = NULL;

   double   stopPrice   = grid.base +          level  * GridSize * Pips;
   double   slippage    = NULL;
   double   stopLoss    = stopPrice - MathSign(level) * GridSize * Pips;
   double   takeProfit  = NULL;
   int      magicNumber = CreateMagicNumber(level);
   datetime expires     = NULL;
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));
   color    markerColor = ifInt(level > 0, CLR_LONG, CLR_SHORT);

   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               Closed
   #define DM_ALL       3     // Pending, Open, ClosedByStop, Closed
   */
   if (orderDisplayMode == DM_NONE)
      markerColor = CLR_NONE;

   if (IsLastError())
      return(-1);

   int ticket = OrderSendEx(Symbol(), type, LotSize, stopPrice, slippage, stopLoss, takeProfit, comment, magicNumber, expires, markerColor, execution);
   if (ticket == -1)
      return(_int(-1, SetLastError(stdlib_PeekLastError())));

   if (IsError(catch("PendingStopOrder(4)")))
      return(-1);
   return(ticket);
}


/**
 * Öffnet eine Position zum aktuellen Preis.
 *
 * @param  int    type        - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int    level       - Gridlevel der Order
 * @param  double execution[] - ausführungsspezifische Daten
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int MarketOrder(int type, int level, double& execution[]) {
   if (__STATUS__CANCELLED || IsLastError())
      return(-1);

   if (type == OP_BUY) {
      if (level <= 0) return(_int(-1, catch("MarketOrder(1)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELL) {
      if (level >= 0) return(_int(-1, catch("MarketOrder(2)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("MarketOrder(3)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (ArraySize(execution) < 1)
      ArrayResize(execution, 1);
   execution[EXEC_FLAGS] = NULL;

   double   price       = NULL;
   double   slippage    = 0.1;
   double   stopLoss    = grid.base + (level-MathSign(level)) * GridSize * Pips;
   double   takeProfit  = NULL;
   int      magicNumber = CreateMagicNumber(level);
   datetime expires     = NULL;
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));
   color    markerColor = ifInt(level > 0, CLR_LONG, CLR_SHORT);

   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               Closed
   #define DM_ALL       3     // Pending, Open, ClosedByStop, Closed
   */
   if (orderDisplayMode == DM_NONE)
      markerColor = CLR_NONE;

   if (IsLastError())
      return(-1);

   int ticket = OrderSendEx(Symbol(), type, LotSize, price, slippage, stopLoss, takeProfit, comment, magicNumber, expires, markerColor, execution);
   if (ticket == -1)
      return(_int(-1, SetLastError(stdlib_PeekLastError())));

   if (IsError(catch("MarketOrder(4)")))
      return(-1);
   return(ticket);
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
       level    = MathAbs(level) +0.1;                               // (int) double: Wert in MagicNumber ist immer positiv
       level    = level & 0xFF << 14;                                //  8 bit (Bits größer 8 löschen und auf 22 Bit erweitern)  | in MagicNumber: Bits 15-22
   int sequence = sequenceId  & 0x3FFF;                              // 14 bit (Bits größer 14 löschen                           | in MagicNumber: Bits  1-14

   return(ea + level + sequence);
}


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @param  bool initByTerminal - ob der Aufruf innerhalb der vom Terminal aufgerufenen init()-Funktion erfolgt (default: nein)
 *
 * @return int - Fehlerstatus
 */
int ShowStatus(bool initByTerminal=false) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   string msg, str.error, str.stopValue;

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
      case STATUS_PROGRESSING:   msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " progressing at level ", grid.level, "  ", str.grid.maxLevel); break;
      case STATUS_STOPPING:      msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " stopping at level ", grid.level, "  ", str.grid.maxLevel   ); break;
      case STATUS_STOPPED:       msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " stopped at level ", grid.level, "  ", str.grid.maxLevel    ); break;
      case STATUS_DISABLED:      msg = StringConcatenate(":  ", str.test, "sequence ", sequenceId, " disabled"                                                  ); break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ status, ERR_RUNTIME_ERROR));
   }

   if (!IsLastError())
      str.stopValue = DoubleToStr(GridSize * PipValue(LotSize), 2);

   msg = StringConcatenate(__NAME__, msg, str.error,                                                 NL,
                                                                                                     NL,
                           "Grid:            ", GridSize, " pip", str.grid.base, str.grid.direction, NL,
                           "LotSize:         ", str.LotSize, " lot = ", str.stopValue, "/stop",      NL,
                           str.startConditions,                                                             // enthält NL, wenn gesetzt
                           str.stopConditions,                                                              // enthält NL, wenn gesetzt
                           "Stops:           ", str.grid.stops, " ", str.grid.stopsPL,               NL,
                           "Breakeven:   ", str.grid.breakeven,                                      NL,
                           "Profit/Loss:    ", str.grid.totalPL, "  ", str.grid.plStatistics,        NL);

   // einige Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));
   if (initByTerminal)
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
      int hWnd = GetTesterWindow();
      if (hWnd == 0)
         return(_ZERO(SetLastError(stdlib_PeekLastError())));

      string text = StringConcatenate("Tester - SR.", sequenceId);

      if (!SetWindowTextA(hWnd, text))
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

   str.LotSize = NumberToStr(LotSize, ".+");
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
   if (grid.maxLevelLong-grid.maxLevelShort > 0)
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
   if (grid.maxLevelLong-grid.maxLevelShort > 0)
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
 * Berechnet die aktuellen Breakeven-Werte.
 *
 * @param  datetime time - Zeitpunkt, für Breakeven-Indikator (default: aktueller Zeitpunkt)
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.UpdateBreakeven(datetime time=0) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);

   double distance1, distance2;

   /*
   (1) Breakeven-Punkt auf aktueller Seite:
   ------------------------------------
         totalPL = realizedPL + floatingPL

   =>          0 = realizedPL + floatingPL                     // Soll: totalPL = 0.00

   => floatingPL = -realizedPL                                 // wenn floatingPL = -realizedPL, dann totalPL = 0.00

   => floatingPL = -(stopsPL + closedPL)                       // realizedPL = stopsPL + closedPL (nach herkömmlicher Denke)

   => floatingPL = -stopsPL - closedPL                         // alle "realisierten" Beträge werden weiter als floating betrachtet, nach ResumeSequence() sind sie nicht mehr realisiert

   => floatingPL = -stopsPL                                    // closedPL ist immer 0  =>  daraus folgt, daß zur Breakeven-Berechnung die Kenntnis von stopsPL ausreicht
   */
   distance1 = ProfitToDistance(-grid.stopsPL, grid.level);    // aktueller Level

   if (grid.level == 0) {
      grid.breakevenLong  = grid.base + distance1*Pips;        // activeRisk=0, valueAtRisk=-stopsPL (siehe 2)
      grid.breakevenShort = grid.base - distance1*Pips;        // Abstand der Breakeven-Punkte ist gleich, eine Berechnung reicht
   }
   else {
      /*
      (2) Breakeven-Punkt auf gegenüberliegender Seite:
      ---------------------------------------------
             stopsPL = -valueAtRisk                            // wenn Sequenz Level 0 triggert

      => valueAtRisk = -stopsPL                                // analog zu (1)
      */
      if (grid.direction == D_BIDIR)
         distance2 = ProfitToDistance(grid.valueAtRisk, 0);    // Level 0

      if (grid.level > 0) {
         grid.breakevenLong  = grid.base + distance1*Pips;
         grid.breakevenShort = grid.base - distance2*Pips;
      }
      else /*(grid.level < 0)*/ {
         grid.breakevenLong  = grid.base + distance2*Pips;
         grid.breakevenShort = grid.base - distance1*Pips;
      }
   }
   Grid.DrawBreakeven(time);
   SS.Grid.Breakeven();

   return(IsNoError(catch("Grid.UpdateBreakeven()")));
}


/**
 * Aktualisiert den Breakeven-Indikator.
 *
 * @param  datetime time - Zeitpunkt der zu zeichnenden Werte (default: aktueller Zeitpunkt)
 */
void Grid.DrawBreakeven(datetime time=NULL) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;
   if (EQ(grid.breakevenLong, 0))                                                // ohne initialisiertes Breakeven sofortige Rückkehr
      return;

   static double   last.grid.breakevenLong, last.grid.breakevenShort;            // Daten der zuletzt gezeichneten Indikatorwerte
   static datetime last.startTimeLong, last.startTimeShort, last.drawingTime;

   if (time == NULL)
      time = TimeCurrent();
   datetime now = time;

   // Trendlinien zeichnen
   if (last.drawingTime != 0) {
      // Long
      if (grid.direction != D_SHORT) {                                           // "SR.5609.L 1.53024 -> 1.52904 (2012.01.23 10:19:35)"
         string labelL = StringConcatenate("SR.", sequenceId, ".beL ", DoubleToStr(last.grid.breakevenLong, Digits), " -> ", DoubleToStr(grid.breakevenLong, Digits), " (", TimeToStr(last.startTimeLong, TIME_FULL), ")");
         if (ObjectCreate(labelL, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenLong, now, grid.breakevenLong)) {
            ObjectSet(labelL, OBJPROP_RAY  , false          );
            ObjectSet(labelL, OBJPROP_COLOR, Breakeven.Color);
            ObjectSet(labelL, OBJPROP_WIDTH, Breakeven.Width);
            if (EQ(last.grid.breakevenLong, grid.breakevenLong)) last.startTimeLong = last.drawingTime;
            else                                                 last.startTimeLong = now;
         }
         else {
            GetLastError();                                                      // ERR_OBJECT_ALREADY_EXISTS
            ObjectSet(labelL, OBJPROP_TIME2, now);                               // vorhandene Trendlinien werden möglichst verlängert (verhindert Erzeugung unzähliger gleicher Objekte)
         }
      }

      // Short
      if (grid.direction != D_LONG) {
         string labelS = StringConcatenate("SR.", sequenceId, ".beS ", DoubleToStr(last.grid.breakevenShort, Digits), " -> ", DoubleToStr(grid.breakevenShort, Digits), " (", TimeToStr(last.startTimeShort, TIME_FULL), ")");
         if (ObjectCreate(labelS, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenShort, now, grid.breakevenShort)) {
            ObjectSet(labelS, OBJPROP_RAY  , false          );
            ObjectSet(labelS, OBJPROP_COLOR, Breakeven.Color);
            ObjectSet(labelS, OBJPROP_WIDTH, Breakeven.Width);
            if (EQ(last.grid.breakevenShort, grid.breakevenShort)) last.startTimeShort = last.drawingTime;
            else                                                   last.startTimeShort = now;
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
            ObjectSet(label, OBJPROP_COLOR, Breakeven.Color);
            ObjectSet(label, OBJPROP_WIDTH, Breakeven.Width);
         }
      }
   }
   catch("RecolorBreakeven()");
}


/**
 * Berechnet den notwendigen Abstand von der aktuellen Gridbasis, um den angegebenen Gewinn zu erzielen.
 *
 * @param  double profit - zu erzielender Gewinn
 * @param  int    level  - aktueller Gridlevel (Stops zwischen diesem Level und dem resultierenden Abstand werden berücksichtigt)
 *
 * @return double - Abstand in Pips oder 0, wenn ein Fehler auftrat
 *
 *
 *  NOTE: Benötigt *nicht* die Gridbasis, die GridSize ist ausreichend.
 *  -----
 */
double ProfitToDistance(double profit, int level) {
   if (EQ(profit, 0))
      return(GridSize);

   profit = MathAbs(profit);

   if (level < 0)
      level = -level;
   level--;                                                                      // Formeln beziehen sich auf Zählung von der Gridbasis
   /*
   Formeln gelten für Sequenzstart an der Gridbasis:
   -------------------------------------------------
   gs        = GridSize
   n         = Level
   pipV(n)   = PipValue von Level n
   profit(d) = profit(exp) + profit(lin)                                         // Summe aus exponentiellem (ganzer Level) und linearem Anteil (partieller nächster Level)


   Level des exponentiellen Anteils ermitteln:
   -------------------------------------------
   expProfit(n)   = n * (n+1)/2 * gs * pipV(1)

   =>          0 = n² + n - 2*profit/(gs*pipV(1))                                // Normalform

   => (n + 0.5)² = n² + n + 0.25                                                 // Binom

   => (n + 0.5)² - 0.25 - 2*profit/(gs*pipV(1)) = n² + n - 2*profit/(gs*pipV(1))

   => (n + 0.5)² - 0.25 - 2*profit/(gs*pipV(1)) = 0

   => (n + 0.5)² = 2*profit/(gs*pipV(1)) + 0.25

   => (n + 0.5)  = (2*profit/(gs*pipV(1)) + 0.25)½                               // Quadratwurzel

   =>          n = (2*profit/(gs*pipV(1)) + 0.25)½ - 0.5                         // n = rationale Zahl
   */
   int    gs   = GridSize;
   double pipV = PipValue(LotSize);
   int    n    = MathSqrt(2*profit/(gs*pipV) + 0.25) - 0.5 +0.000000001;         // (int) double

   while (n < level-1) {                                                         // Sind wir im Plus und oberhalb von Breakeven liegen Stops, muß
      profit += gs * pipV;                                                       // auf dem "Weg zu Breakeven" deren Triggern einkalkuliert werden.
      level--;
      n = MathSqrt(2*profit/(gs*pipV) + 0.25) - 0.5 +0.000000001;                // (int) double
      //debug("ProfitToDistance()    new n="+ n);
   }

   /*
   Pips des linearen Anteils ermitteln:
   ------------------------------------
   linProfit(n.x) = 0.x * gs * pipV(n+1)

   =>   linProfit = linPips * pipV(n+1)

   =>   linProfit = linPips * (n+1)*pipV(1)

   =>     linPips = linProfit / ((n+1)*pipV(1))
   */
   double linProfit = profit - n * (n+1)/2 * gs * pipV;                          // verbleibender linearer Anteil am Profit
   double linPips   = linProfit / ((n+1) * pipV);

   // Gesamtdistanz berechnen
   double distance  = n * gs + linPips + gs;                                     // 1 x GridSize hinzu addieren, da der Sequenzstart erst bei Grid.Base + GridSize erfolgt

   //debug("ProfitToDistance()    profit="+ DoubleToStr(profit, 2) +"  n="+ n +"  exp="+ DoubleToStr(n * (n+1)/2 * gs * pipV, 2) +"  lin="+ DoubleToStr(linProfit, 2) +"  linPips="+ NumberToStr(linPips, ".+") +"  distance="+ NumberToStr(distance, ".+"));
   return(distance);
}


/**
 * Berechnet den theoretischen Profit im angegebenen Abstand von der Gridbasis.
 *
 * @param  double distance - Abstand in Pips von Grid.Base
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
   double d    = distance - gs;                                      // GridSize von distance abziehen, da Sequenzstart erst bei Grid.Base + GridSize erfolgt
   int    n    = (d+0.000000001) / gs;
   double pipV = PipValue(LotSize);

   double expProfit = n * (n+1)/2 * gs * pipV;
   double linProfit = MathModFix(d, gs) * (n+1) * pipV;
   double profit    = expProfit + linProfit;

   //debug("DistanceToProfit()   gs="+ gs +"  d="+ d +"  n="+ n +"  exp="+ DoubleToStr(expProfit, 2) +"  lin="+ DoubleToStr(linProfit, 2) +"  profit="+ NumberToStr(profit, ".+"));
   return(profit);
}


/**
 * Speichert den transienten Sequenzstatus im Chart, sodaß er nach einem Recompile oder Terminal-Restart wiederhergestellt werden kann.
 * Der transiente Status umfaßt die User-Eingaben, die nicht im Statusfile gespeichert sind (Sequenz-ID, Display-Modes, Farben, Strichstärken)
 * und die Flags __STATUS__CANCELLED und __STATUS__INVALID_INPUT.
 *
 * @return int - Fehlerstatus
 */
int StoreTransientStatus() {
   string label = StringConcatenate(__NAME__, ".transient.Sequence.ID");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, ifString(sequenceId==0, "0", Sequence.ID), 1);        // 0 = STATUS_UNINITIALIZED

   label = StringConcatenate(__NAME__, ".transient.OrderDisplayMode");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, OrderDisplayMode, 1);

   label = StringConcatenate(__NAME__, ".transient.Breakeven.Color");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", Breakeven.Color), 1);

   label = StringConcatenate(__NAME__, ".transient.Breakeven.Width");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", Breakeven.Width), 1);

   label = StringConcatenate(__NAME__, ".transient.__STATUS__CANCELLED");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS__CANCELLED), 1);

   label = StringConcatenate(__NAME__, ".transient.__STATUS__INVALID_INPUT");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS__INVALID_INPUT), 1);

   return(catch("StoreTransientStatus()"));
}


/**
 * Restauriert die im Chart gespeicherten transienten Sequenzdaten.
 *
 * @return bool - ob die ID einer initialisierten Sequenz gefunden wurde (gespeicherte Sequenz kann im STATUS_UNINITIALIZED sein)
 */
bool RestoreTransientStatus() {
   string label, strValue;
   bool   idFound;

   label = StringConcatenate(__NAME__, ".transient.Sequence.ID");
   if (ObjectFind(label) == 0) {
      strValue = StringToUpper(StringTrim(ObjectDescription(label)));
      if (StringLeft(strValue, 1) == "T") {
         test     = true; SS.Test();
         strValue = StringRight(strValue, -1);
      }
      if (!StringIsDigit(strValue))
         return(_false(catch("RestoreTransientStatus(1)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
      int iValue = StrToInteger(strValue);
      if (iValue == 0) {
         status  = STATUS_UNINITIALIZED;
         idFound = false;
      }
      else if (iValue < 1000 || iValue > 16383) {
         return(_false(catch("RestoreTransientStatus(2)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
      }
      else {
         sequenceId  = iValue; SS.SequenceId();
         Sequence.ID = ifString(IsTest(), "T", "") + sequenceId;
         status      = STATUS_WAITING;
         idFound     = true;
      }

      label = StringConcatenate(__NAME__, ".transient.OrderDisplayMode");
      if (ObjectFind(label) == 0) {
         string modes[] = {"None", "Stops", "Pyramid", "All"};
         strValue = StringTrim(ObjectDescription(label));
         if (!StringInArray(modes, strValue))
            return(_false(catch("RestoreTransientStatus(3)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         OrderDisplayMode = strValue;
      }

      label = StringConcatenate(__NAME__, ".transient.Breakeven.Color");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreTransientStatus(4)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (iValue < CLR_NONE || iValue > C'255,255,255')
            return(_false(catch("RestoreTransientStatus(5)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\" (0x"+ IntToHexStr(iValue) +")", ERR_INVALID_CONFIG_PARAMVALUE)));
         Breakeven.Color = iValue;
      }

      label = StringConcatenate(__NAME__, ".transient.Breakeven.Width");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsInteger(strValue))
            return(_false(catch("RestoreTransientStatus(6)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         iValue = StrToInteger(strValue);
         if (iValue < 1 || iValue > 5)
            return(_false(catch("RestoreTransientStatus(7)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         Breakeven.Width = iValue;
      }

      label = StringConcatenate(__NAME__, ".transient.__STATUS__CANCELLED");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreTransientStatus(8)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS__CANCELLED = StrToInteger(strValue) != 0;
      }

      label = StringConcatenate(__NAME__, ".transient.__STATUS__INVALID_INPUT");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreTransientStatus(9)  illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS__INVALID_INPUT = StrToInteger(strValue) != 0;
      }
   }

   return(idFound && IsNoError(catch("RestoreTransientStatus(10)")));
}


/**
 * Löscht alle im Chart gespeicherten transienten Sequenzdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearTransientStatus() {
   string label, prefix=StringConcatenate(__NAME__, ".transient.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearTransientStatus()"));
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

   sequenceId  = iValue; SS.SequenceId();
   Sequence.ID = ifString(IsTest(), "T", "") + sequenceId;

   return(true);
}


/**
 * Validiert die gesamte aktuelle Konfiguration.
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


   // (6) StopConditions:  "@limit(1.33) || @time(12:00) || @profit(1234.00) || @profit(20%) || @profit(10%e)" OR-verknüpft
   // ---------------------------------------------------------------------------------------------------------------------
   //  @limit(1.33)     oder  1.33                                            // shortkey nicht implementiert
   //  @time(12:00)     oder  12:00          // Validierung unzureichend      // shortkey nicht implementiert
   //  @profit(1234.00)
   //  @profit(20%)     oder  20%                                             // shortkey nicht implementiert
   //  @profit(10%e)    oder  20%e           // noch nicht implementiert      // shortkey nicht implementiert
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


   // (7) OrderDisplayMode
   string modes[] = {"None", "Stops", "Pyramid", "All"};
   switch (StringGetChar(StringToUpper(StringTrim(OrderDisplayMode) +"N"), 0)) {
      case 'N': orderDisplayMode = DM_NONE;    break;                   // default
      case 'S': orderDisplayMode = DM_STOPS;   break;
      case 'P': orderDisplayMode = DM_PYRAMID; break;
      case 'A': orderDisplayMode = DM_ALL;     break;
      default:                                     return(_false(HandleConfigError("ValidateConfiguration(41)", "Invalid parameter OrderDisplayMode = \""+ OrderDisplayMode +"\"", interactive)));
   }
   OrderDisplayMode = modes[orderDisplayMode];


   // (8) Breakeven.Color
   if (Breakeven.Color == 0xFF000000)                                   // kann vom Terminal falsch gesetzt worden sein
      Breakeven.Color = CLR_NONE;
   if (Breakeven.Color < CLR_NONE || Breakeven.Color > C'255,255,255')  // kann nur nicht-interaktiv falsch reinkommen
                                                   return(_false(HandleConfigError("ValidateConfiguration(42)", "Invalid parameter Breakeven.Color = 0x"+ IntToHexStr(Breakeven.Color), interactive)));

   // (9) Breakeven.Width
   if (Breakeven.Width < 1 || Breakeven.Width > 5) return(_false(HandleConfigError("ValidateConfiguration(43)", "Invalid parameter Breakeven.Width = "+ Breakeven.Width, interactive)));


   // (10) __STATUS__INVALID_INPUT zurücksetzen
   if (interactive)
      __STATUS__INVALID_INPUT = false;

   ArrayResize(directions, 0);
   ArrayResize(exprs,      0);
   ArrayResize(elems,      0);
   ArrayResize(modes,      0);
   return(IsNoError(catch("ValidateConfiguration(44)")));
}


/**
 * "Exception-Handler" für ungültige Input-Parameter. Je nach Laufzeitumgebung wird der Fehler weitergereicht oder eine interaktive Korrektur angeboten.
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


   log(location +"   "+ msg, ERR_INVALID_INPUT);

   ForceSound("chord.wav");
   int button = ForceMessageBox(msg, __NAME__ +" - ValidateConfiguration()", MB_ICONERROR|MB_RETRYCANCEL);

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
void SaveConfiguration(bool save=true) {
   static string   _Sequence.ID;
   static string   _GridDirection;
   static int      _GridSize;
   static double   _LotSize;
   static string   _StartConditions;
   static string   _StopConditions;
   static string   _OrderDisplayMode;
   static color    _Breakeven.Color;
   static int      _Breakeven.Width;

   static int      _grid.direction;
   static int      _orderDisplayMode;

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
      _Sequence.ID                  = StringConcatenate(Sequence.ID,      "");   // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
      _GridDirection                = StringConcatenate(GridDirection,    "");
      _GridSize                     = GridSize;
      _LotSize                      = LotSize;
      _StartConditions              = StringConcatenate(StartConditions,  "");
      _StopConditions               = StringConcatenate(StopConditions,   "");
      _OrderDisplayMode             = StringConcatenate(OrderDisplayMode, "");
      _Breakeven.Color              = Breakeven.Color;
      _Breakeven.Width              = Breakeven.Width;

      _grid.direction               = grid.direction;
      _orderDisplayMode             = orderDisplayMode;

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
      GridDirection                 = _GridDirection;
      GridSize                      = _GridSize;
      LotSize                       = _LotSize;
      StartConditions               = _StartConditions;
      StopConditions                = _StopConditions;
      OrderDisplayMode              = _OrderDisplayMode;
      Breakeven.Color               = _Breakeven.Color;
      Breakeven.Width               = _Breakeven.Width;

      grid.direction                = _grid.direction;
      orderDisplayMode              = _orderDisplayMode;

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
   SaveConfiguration(false);
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
   if (IsTesting()) /*&&*/ if (counter!=0) /*&&*/ if (status!=STATUS_STOPPED)    // im Tester Ausführung nur beim ersten Aufruf und nach Stop
      return(true);
   counter++;

   /*
   Speichernotwendigkeit der einzelnen Variablen
   ---------------------------------------------
   int      status;                          // nein: kann aus Orderdaten und offenen Positionen restauriert werden
   bool     test;                            // nein: wird aus Statusdatei ermittelt

   datetime instanceStartTime;               // ja
   double   instanceStartPrice;              // ja
   double   sequenceStartEquity;             // ja

   datetime sequenceStartTimes [];           // ja
   double   sequenceStartPrices[];           // ja

   datetime sequenceStopTimes [];            // ja
   double   sequenceStopPrices[];            // ja

   bool     start.*.condition;               // nein: wird aus StartConditions abgeleitet
   bool     stop.*.condition;                // nein: wird aus StopConditions abgeleitet

   datetime grid.base.time [];               // ja
   double   grid.base.value[];               // ja
   double   grid.base;                       // nein: wird aus Gridbase-History restauriert

   int      grid.level;                      // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelLong;               // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelShort;              // nein: kann aus Orderdaten restauriert werden

   int      grid.stops;                      // nein: kann aus Orderdaten restauriert werden
   double   grid.stopsPL;                    // nein: kann aus Orderdaten restauriert werden
   double   grid.closedPL;                   // nein: kann aus Orderdaten restauriert werden
   double   grid.floatingPL;                 // nein: kann aus offenen Positionen restauriert werden
   double   grid.totalPL;                    // nein: kann aus stopsPL, closedPL und floatingPL restauriert werden
   double   grid.activeRisk;                 // nein: kann aus Orderdaten restauriert werden
   double   grid.valueAtRisk;                // nein: kann aus Orderdaten restauriert werden

   double   grid.maxProfit;                  // ja
   datetime grid.maxProfitTime;              // ja
   double   grid.maxDrawdown;                // ja
   datetime grid.maxDrawdownTime;            // ja
   double   grid.breakevenLong;              // nein: wird mit dem aktuellen TickValue als Näherung neu berechnet
   double   grid.breakevenShort;             // nein: wird mit dem aktuellen TickValue als Näherung neu berechnet

   int      orders.ticket           [];      // ja
   int      orders.level            [];      // ja
   double   orders.gridBase         [];      // ja
   int      orders.pendingType      [];      // ja
   datetime orders.pendingTime      [];      // ja
   datetime orders.pendingModifyTime[];      // ja
   double   orders.pendingPrice     [];      // ja
   int      orders.type             [];      // ja
   datetime orders.openTime         [];      // ja
   double   orders.openPrice        [];      // ja
   double   orders.risk             [];      // ja
   datetime orders.closeTime        [];      // ja
   double   orders.closePrice       [];      // ja
   double   orders.stopLoss         [];      // ja
   bool     orders.closedByStop     [];      // ja
   double   orders.swap             [];      // ja
   double   orders.commission       [];      // ja
   double   orders.profit           [];      // ja
   */
   string lines[]; ArrayResize(lines, 0);

   // (1.1) Input-Parameter
   ArrayPushString(lines, /*string*/   "Account="        + ShortAccountCompany() +":"+ GetAccountNumber());
   ArrayPushString(lines, /*string*/   "Symbol="         +                                Symbol()       );
   ArrayPushString(lines, /*string*/   "Sequence.ID="    +  ifString(IsTest(), "T", "") + sequenceId     );
   ArrayPushString(lines, /*string*/   "GridDirection="  +                                GridDirection  );
   ArrayPushString(lines, /*int   */   "GridSize="       +                                GridSize       );
   ArrayPushString(lines, /*double*/   "LotSize="        +                    NumberToStr(LotSize, ".+") );
   ArrayPushString(lines, /*string*/   "StartConditions="+                                StartConditions);
   ArrayPushString(lines, /*string*/   "StopConditions=" +                                StopConditions );

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
   ArrayPushString(lines, /*string*/   "rt.sequenceStarts="      + JoinStrings(values, ","));

      ArrayResize(values, 0);
      size = ArraySize(sequenceStopTimes);
      for (i=0; i < size; i++)
         ArrayPushString(values, StringConcatenate(sequenceStopTimes[i], "|", NumberToStr(sequenceStopPrices[i], ".+")));
      if (size == 0)
         ArrayPushString(values, "0|0");
   ArrayPushString(lines, /*string*/   "rt.sequenceStops="       + JoinStrings(values, ","));

   ArrayPushString(lines, /*double*/   "rt.grid.maxProfit="      + NumberToStr(grid.maxProfit, ".+"));
   ArrayPushString(lines, /*datetime*/ "rt.grid.maxProfitTime="  +             grid.maxProfitTime + ifString(grid.maxProfitTime==0, "", " ("+ TimeToStr(grid.maxProfitTime, TIME_FULL) +")"));
   ArrayPushString(lines, /*double*/   "rt.grid.maxDrawdown="    + NumberToStr(grid.maxDrawdown, ".+")  );
   ArrayPushString(lines, /*datetime*/ "rt.grid.maxDrawdownTime="+             grid.maxDrawdownTime   + ifString(grid.maxDrawdownTime  ==0, "", " ("+ TimeToStr(grid.maxDrawdownTime  , TIME_FULL) +")"));

      ArrayResize(values, 0);
      size = ArraySize(grid.base.time);
      for (i=0; i < size; i++)
         ArrayPushString(values, StringConcatenate(grid.base.time[i], "|", NumberToStr(grid.base.value[i], ".+")));
      if (size == 0)
         ArrayPushString(values, "0|0");
   ArrayPushString(lines, /*string*/   "rt.grid.base="           + JoinStrings(values, ","));

   size = ArraySize(orders.ticket);
   for (i=0; i < size; i++) {
      int      ticket            = orders.ticket           [i];
      int      level             = orders.level            [i];
      double   gridBase          = orders.gridBase         [i];
      int      pendingType       = orders.pendingType      [i];
      datetime pendingTime       = orders.pendingTime      [i];
      datetime pendingModifyTime = orders.pendingModifyTime[i];
      double   pendingPrice      = orders.pendingPrice     [i];
      int      type              = orders.type             [i];
      datetime openTime          = orders.openTime         [i];
      double   openPrice         = orders.openPrice        [i];
      double   risk              = orders.risk             [i];
      datetime closeTime         = orders.closeTime        [i];
      double   closePrice        = orders.closePrice       [i];
      double   stopLoss          = orders.stopLoss         [i];
      bool     closedByStop      = orders.closedByStop     [i];
      double   swap              = orders.swap             [i];
      double   commission        = orders.commission       [i];
      double   profit            = orders.profit           [i];
      ArrayPushString(lines, StringConcatenate("rt.order.", i, "=", ticket, ",", level, ",", NumberToStr(NormalizeDouble(gridBase, Digits), ".+"), ",", pendingType, ",", pendingTime, ",", pendingModifyTime, ",", NumberToStr(NormalizeDouble(pendingPrice, Digits), ".+"), ",", type, ",", openTime, ",", NumberToStr(NormalizeDouble(openPrice, Digits), ".+"), ",", NumberToStr(NormalizeDouble(risk, 2), ".+"), ",", closeTime, ",", NumberToStr(NormalizeDouble(closePrice, Digits), ".+"), ",", NumberToStr(NormalizeDouble(stopLoss, Digits), ".+"), ",", closedByStop, ",", NumberToStr(swap, ".+"), ",", NumberToStr(commission, ".+"), ",", NumberToStr(profit, ".+")));
   }


   // (2) Daten in lokaler Datei speichern/überschreiben
   string fileName = StringToLower(StdSymbol()) +".SR."+ sequenceId +".set";
   if      (IsTesting()) fileName = "presets\\"+ fileName;                                // "experts\files\presets" ist SymLink auf "experts\presets", dadurch
   else if (IsTest())    fileName = "presets\\tester\\"+ fileName;                        //  ist "experts\presets" für die MQL-Dateifunktionen erreichbar.
   else                  fileName = "presets\\"+ ShortAccountCompany() +"\\"+ fileName;

   int hFile = FileOpen(fileName, FILE_CSV|FILE_WRITE);
   if (hFile < 0)
      return(_false(catch("SaveStatus(2) ->FileOpen(\""+ fileName +"\")")));

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


   // (1) bei nicht existierender lokaler Konfiguration die Datei vom Server laden
   string filesDir = TerminalPath() +"\\experts\\files\\";
   string fileName = StringToLower(StdSymbol()) +".SR."+ sequenceId +".set";

   if      (IsTesting()) fileName = "presets\\"+ fileName;                                // "experts\files\presets" ist SymLink auf "experts\presets", dadurch
   else if (IsTest())    fileName = "presets\\tester\\"+ fileName;                        //  ist "experts\presets" für die MQL-Dateifunktionen erreichbar.
   else                  fileName = "presets\\"+ ShortAccountCompany() +"\\"+ fileName;

   if (!IsFile(filesDir + fileName)) {
      if (IsTest())
         return(_false(catch("RestoreStatus(2)   status file \""+ filesDir + fileName +"\" for test sequence T"+ sequenceId +" not found", ERR_FILE_NOT_FOUND)));
      /*
      // TODO: Existenz von wget.exe prüfen

      // Befehlszeile für Shellaufruf zusammensetzen
      string url        = "http://sub.domain.tld/downloadSRStatus.php?company="+ UrlEncode(ShortAccountCompany()) +"&account="+ AccountNumber() +"&symbol="+ UrlEncode(StdSymbol()) +"&sequence="+ sequenceId;
      string targetFile = filesDir +"\\"+ fileName;
      string logFile    = filesDir +"\\"+ fileName +".log";
      string cmd        = "wget.exe \""+ url +"\" -O \""+ targetFile +"\" -o \""+ logFile +"\"";

      debug("RestoreStatus()   downloading status file for sequence "+ ifString(IsTest(), "T", "") + sequenceId);

      int error = WinExecAndWait(cmd, SW_HIDE);                      // SW_SHOWNORMAL|SW_HIDE
      if (IsError(error))
         return(_false(SetLastError(error)));

      debug("RestoreStatus()   status file for sequence "+ ifString(IsTest(), "T", "") + sequenceId +" successfully downloaded");
      FileDelete(fileName +".log");
      */
   }
   if (!IsFile(filesDir + fileName))
      return(_false(catch("RestoreStatus(3)   status file \""+ filesDir + fileName +"\" for "+ ifString(IsTest(), "test ", "") +"sequence "+ ifString(IsTest(), "T", "") + sequenceId +" not found", ERR_FILE_NOT_FOUND)));


   // (2) Datei einlesen
   string lines[];
   int size = FileReadLines(fileName, lines, true);
   if (size < 0)
      return(_false(SetLastError(stdlib_PeekLastError())));
   if (size == 0) {
      FileDelete(fileName);
      return(_false(catch("RestoreStatus(4)   status for sequence "+ ifString(IsTest(), "T", "") + sequenceId +" not found", ERR_RUNTIME_ERROR)));
   }


   // (3) notwendige Schlüssel definieren
   string keys[] = { "Account", "Symbol", "Sequence.ID", "GridDirection", "GridSize", "LotSize", "StartConditions", "StopConditions", "rt.instanceStartTime", "rt.instanceStartPrice", "rt.sequenceStartEquity", "rt.sequenceStarts", "rt.sequenceStops", "rt.grid.maxProfit", "rt.grid.maxProfitTime", "rt.grid.maxDrawdown", "rt.grid.maxDrawdownTime", "rt.grid.base" };
   /*                "Account"                ,
                     "Symbol"                 ,                      // Der Compiler kommt mit den Zeilennummern durcheinander,
                     "Sequence.ID"            ,                      // wenn der Initializer nicht komplett in einer Zeile steht.
                     "GridDirection"          ,
                     "GridSize"               ,
                     "LotSize"                ,
                     "StartConditions"        ,
                     "StopConditions"         ,
                     "rt.instanceStartTime"   ,
                     "rt.instanceStartPrice"  ,
                     "rt.sequenceStartEquity" ,
                     "rt.sequenceStarts"      ,
                     "rt.sequenceStops"       ,
                     "rt.grid.maxProfit"      ,
                     "rt.grid.maxProfitTime"  ,
                     "rt.grid.maxDrawdown"    ,
                     "rt.grid.maxDrawdownTime",
                     "rt.grid.base"           ,
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
         ArrayDropString(keys, key);
      }
      else if (key == "StopConditions") {
         StopConditions = value;
         ArrayDropString(keys, key);
      }
   }

   // (4.2) gegenseitige Abhängigkeiten validieren

   // Account: Wenn die AccountCompany (= Zeitzone) übereinstimmt, kann ein Test in einem anderen Account visualisiert werden.
   if (accountValue != ShortAccountCompany()+":"+GetAccountNumber()) {
      if (IsTesting() || !IsTest() || !StringIStartsWith(accountValue, ShortAccountCompany()+":"))
                                                                      return(_false(catch("RestoreStatus(11)   account mis-match \""+ ShortAccountCompany() +":"+ GetAccountNumber() +"\"/\""+ accountValue +"\" in status file \""+ fileName +"\" (line \""+ lines[accountLine] +"\")", ERR_RUNTIME_ERROR)));
   }


   // (5.1) Runtime-Settings auslesen, validieren und übernehmen
   ArrayResize(sequenceStartTimes,  0);
   ArrayResize(sequenceStartPrices, 0);
   ArrayResize(sequenceStopTimes,   0);
   ArrayResize(sequenceStopPrices,  0);
   ArrayResize(grid.base.time,      0);
   ArrayResize(grid.base.value,     0);

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
   datetime rt.sequenceStarts=1328701713|1.32677,1329999999|1.33215
   datetime rt.sequenceStops=1328701999|1.32734,0|0
   double   rt.grid.maxProfit=200.13
   datetime rt.grid.maxProfitTime=1328701713
   double   rt.grid.maxDrawdown=-127.80
   datetime rt.grid.maxDrawdownTime=1328691713
   string   rt.grid.base=1331710960|1.56743,1331711010|1.56714
   string   rt.order.0=62544847,1,1.32067,4,1330932525,1330932525,1.32067,0,0,1330936196,1.32067,0,0,0,1330938698,1.31897,1.31897,17,1,0,0,0,0,0,-17
      int      ticket            = values[ 0];
      int      level             = values[ 1];
      double   gridBase          = values[ 2];
      int      pendingType       = values[ 3];
      datetime pendingTime       = values[ 4];
      datetime pendingModifyTime = values[ 5];
      double   pendingPrice      = values[ 6];
      int      type              = values[ 7];
      datetime openTime          = values[ 8];
      double   openPrice         = values[ 9];
      double   risk              = values[10];
      datetime closeTime         = values[11];
      double   closePrice        = values[12];
      double   stopLoss          = values[13];
      bool     closedByStop      = values[14];
      double   swap              = values[15];
      double   commission        = values[16];
      double   profit            = values[17];
   */
   string values[], data[];

   if (key == "rt.instanceStartTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                                return(_false(catch("RestoreStatus.Runtime(1)   illegal instanceStartTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      instanceStartTime = StrToInteger(value);
      if (instanceStartTime == 0)                                               return(_false(catch("RestoreStatus.Runtime(2)   illegal instanceStartTime "+ instanceStartTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.instanceStartPrice") {
      if (!StringIsNumeric(value))                                              return(_false(catch("RestoreStatus.Runtime(3)   illegal instanceStartPrice \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      instanceStartPrice = StrToDouble(value);
      if (LE(instanceStartPrice, 0))                                            return(_false(catch("RestoreStatus.Runtime(4)   illegal instanceStartPrice "+ NumberToStr(instanceStartPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStartEquity") {
      if (!StringIsNumeric(value))                                              return(_false(catch("RestoreStatus.Runtime(5)   illegal sequenceStartEquity \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStartEquity = StrToDouble(value);
      if (LT(sequenceStartEquity, 0))                                           return(_false(catch("RestoreStatus.Runtime(6)   illegal sequenceStartEquity "+ DoubleToStr(sequenceStartEquity, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStarts") {
      // rt.sequenceStarts=1331710960|1.56743,1331711010|1.56714
      int sizeOfValues = Explode(value, ",", values, NULL);
      for (int i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                          return(_false(catch("RestoreStatus.Runtime(7)   illegal number of sequenceStarts["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // sequenceStartTime
         if (!StringIsDigit(value))                                             return(_false(catch("RestoreStatus.Runtime(8)   illegal sequenceStartTimes["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime startTime = StrToInteger(value);
         if (startTime == 0) {
            if (NE(sequenceStartEquity, 0))                                     return(_false(catch("RestoreStatus.Runtime(9)   sequenceStartEquity/sequenceStartTimes["+ i +"] mis-match "+ NumberToStr(sequenceStartEquity, ".2") +"/"+ startTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (sizeOfValues==1 && data[1]=="0")
               break;                                                           return(_false(catch("RestoreStatus.Runtime(10)   illegal sequenceStartTimes["+ i +"] "+ startTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         }
         else if (EQ(sequenceStartEquity, 0))                                   return(_false(catch("RestoreStatus.Runtime(11)   sequenceStartEquity/sequenceStartTimes["+ i +"] mis-match "+ NumberToStr(sequenceStartEquity, ".2") +"/'"+ TimeToStr(startTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         else if (startTime < instanceStartTime)                                return(_false(catch("RestoreStatus.Runtime(12)   instanceStartTime/sequenceStartTimes["+ i +"] mis-match '"+ TimeToStr(instanceStartTime, TIME_FULL) +"'/'"+ TimeToStr(startTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // sequenceStartPrice
         if (!StringIsNumeric(value))                                           return(_false(catch("RestoreStatus.Runtime(13)   illegal sequenceStartPrices["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double startPrice = StrToDouble(value);
         if (LE(startPrice, 0))                                                 return(_false(catch("RestoreStatus.Runtime(14)   illegal sequenceStartPrices["+ i +"] "+ NumberToStr(startPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (sequenceStartTimes,  startTime );
         ArrayPushDouble(sequenceStartPrices, startPrice);
      }
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStops") {
      // rt.sequenceStops=1331710960|1.56743,0|0
      sizeOfValues = Explode(value, ",", values, NULL);
      for (i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                          return(_false(catch("RestoreStatus.Runtime(15)   illegal number of sequenceStops["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // sequenceStopTime
         if (!StringIsDigit(value))                                             return(_false(catch("RestoreStatus.Runtime(16)   illegal sequenceStopTimes["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime stopTime = StrToInteger(value);
         if (stopTime == 0) {
            if (i < sizeOfValues-1 || data[1]!="0")                             return(_false(catch("RestoreStatus.Runtime(17)   illegal sequenceStopTimes["+ i +"] "+ stopTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (i==0 && ArraySize(sequenceStartTimes)==0)
               break;
         }
         else if (i >= ArraySize(sequenceStartTimes))                           return(_false(catch("RestoreStatus.Runtime(18)   sequenceStarts("+ ArraySize(sequenceStartTimes) +") / sequenceStops("+ sizeOfValues +") mis-match in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         else if (stopTime < sequenceStartTimes[i])                             return(_false(catch("RestoreStatus.Runtime(19)   sequenceStartTimes["+ i +"]/sequenceStopTimes["+ i +"] mis-match '"+ TimeToStr(sequenceStartTimes[i], TIME_FULL) +"'/'"+ TimeToStr(stopTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // sequenceStopPrice
         if (!StringIsNumeric(value))                                           return(_false(catch("RestoreStatus.Runtime(20)   illegal sequenceStopPrices["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double stopPrice = StrToDouble(value);
         if (LT(stopPrice, 0))                                                  return(_false(catch("RestoreStatus.Runtime(21)   illegal sequenceStopPrices["+ i +"] "+ NumberToStr(stopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (EQ(stopPrice, 0) && stopTime!=0)                                   return(_false(catch("RestoreStatus.Runtime(22)   sequenceStopTimes["+ i +"]/sequenceStopPrices["+ i +"] mis-match '"+ TimeToStr(stopTime, TIME_FULL) +"'/"+ NumberToStr(stopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (sequenceStopTimes,  stopTime );
         ArrayPushDouble(sequenceStopPrices, stopPrice);
      }
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxProfit") {
      if (!StringIsNumeric(value))                                              return(_false(catch("RestoreStatus.Runtime(23)   illegal grid.maxProfit \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfit = StrToDouble(value); SS.Grid.MaxProfit();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxProfitTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                                return(_false(catch("RestoreStatus.Runtime(24)   illegal grid.maxProfitTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitTime = StrToInteger(value);
      if (grid.maxProfitTime==0 && NE(grid.maxProfit, 0))                       return(_false(catch("RestoreStatus.Runtime(25)   grid.maxProfit/grid.maxProfitTime mis-match "+ NumberToStr(grid.maxProfit, ".2") +"/'"+ TimeToStr(grid.maxProfitTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdown") {
      if (!StringIsNumeric(value))                                              return(_false(catch("RestoreStatus.Runtime(26)   illegal grid.maxDrawdown \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdown = StrToDouble(value); SS.Grid.MaxDrawdown();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdownTime") {
      Explode(value, "(", values, 2);
      value = StringTrim(values[0]);
      if (!StringIsDigit(value))                                                return(_false(catch("RestoreStatus.Runtime(27)   illegal grid.maxDrawdownTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdownTime = StrToInteger(value);
      if (grid.maxDrawdownTime==0 && NE(grid.maxDrawdown, 0))                   return(_false(catch("RestoreStatus.Runtime(28)   grid.maxDrawdown/grid.maxDrawdownTime mis-match "+ NumberToStr(grid.maxDrawdown, ".2") +"/'"+ TimeToStr(grid.maxDrawdownTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.base") {
      // rt.grid.base=1331710960|1.56743,1331711010|1.56714
      sizeOfValues = Explode(value, ",", values, NULL);
      for (i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2)                          return(_false(catch("RestoreStatus.Runtime(29)   illegal number of grid.base["+ i +"] details (\""+ values[i] +"\" = "+ ArraySize(data) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[0];           // GridBase-Zeitpunkt
         if (!StringIsDigit(value))                                             return(_false(catch("RestoreStatus.Runtime(30)   illegal grid.base.time["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         datetime gridBaseTime = StrToInteger(value);
         int startTimes = ArraySize(sequenceStartTimes);
         if (gridBaseTime == 0) {
            if (startTimes > 0)                                                 return(_false(catch("RestoreStatus.Runtime(31)   sequenceStartTimes/grid.base.time["+ i +"] mis-match '"+ TimeToStr(sequenceStartTimes[0], TIME_FULL) +"'/"+ gridBaseTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
            if (sizeOfValues==1 && data[1]=="0")
               break;                                                           return(_false(catch("RestoreStatus.Runtime(32)   illegal grid.base.time["+ i +"] "+ gridBaseTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         }
         else if (startTimes == 0)                                              return(_false(catch("RestoreStatus.Runtime(33)   sequenceStartTimes/grid.base.time["+ i +"] mis-match "+ startTimes +"/'"+ TimeToStr(gridBaseTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (gridBaseTime < sequenceStartTimes[0])                              return(_false(catch("RestoreStatus.Runtime(34)   sequenceStartTimes/grid.base.time["+ i +"] mis-match '"+ TimeToStr(sequenceStartTimes[0], TIME_FULL) +"'/'"+ TimeToStr(gridBaseTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         value = data[1];           // GridBase-Wert
         if (!StringIsNumeric(value))                                           return(_false(catch("RestoreStatus.Runtime(35)   illegal grid.base.value["+ i +"] \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         double gridBaseValue = StrToDouble(value);
         if (LE(gridBaseValue, 0))                                              return(_false(catch("RestoreStatus.Runtime(36)   illegal grid.base.value["+ i +"] "+ NumberToStr(gridBaseValue, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

         ArrayPushInt   (grid.base.time,  gridBaseTime );
         ArrayPushDouble(grid.base.value, gridBaseValue);
      }
      ArrayDropString(keys, key);
   }
   else if (StringStartsWith(key, "rt.order.")) {
      // Orderindex
      string strIndex = StringRight(key, -9);
      if (!StringIsDigit(strIndex))                                             return(_false(catch("RestoreStatus.Runtime(37)   illegal order index \""+ key +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      i = StrToInteger(strIndex);
      if (ArraySize(orders.ticket) > i) /*&&*/ if (orders.ticket[i]!=0)         return(_false(catch("RestoreStatus.Runtime(38)   duplicate order index "+ key +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // Orderdaten
      if (Explode(value, ",", values, NULL) != 18)                              return(_false(catch("RestoreStatus.Runtime(39)   illegal number of order details ("+ ArraySize(values) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // ticket
      string strTicket = StringTrim(values[0]);
      if (!StringIsDigit(strTicket))                                            return(_false(catch("RestoreStatus.Runtime(40)   illegal ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int ticket = StrToInteger(strTicket);
      if (ticket == 0)                                                          return(_false(catch("RestoreStatus.Runtime(41)   illegal ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (IntInArray(orders.ticket, ticket))                                    return(_false(catch("RestoreStatus.Runtime(42)   duplicate ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // level
      string strLevel = StringTrim(values[1]);
      if (!StringIsInteger(strLevel))                                           return(_false(catch("RestoreStatus.Runtime(43)   illegal order level \""+ strLevel +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int level = StrToInteger(strLevel);
      if (level == 0)                                                           return(_false(catch("RestoreStatus.Runtime(44)   illegal order level "+ level +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // gridBase
      string strGridBase = StringTrim(values[2]);
      if (!StringIsNumeric(strGridBase))                                        return(_false(catch("RestoreStatus.Runtime(45)   illegal order grid base \""+ strGridBase +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double gridBase = StrToDouble(strGridBase);
      if (LE(gridBase, 0))                                                      return(_false(catch("RestoreStatus.Runtime(46)   illegal order grid base "+ NumberToStr(gridBase, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingType
      string strPendingType = StringTrim(values[3]);
      if (!StringIsInteger(strPendingType))                                     return(_false(catch("RestoreStatus.Runtime(47)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int pendingType = StrToInteger(strPendingType);
      if (pendingType!=OP_UNDEFINED && !IsTradeOperation(pendingType))          return(_false(catch("RestoreStatus.Runtime(48)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingTime
      string strPendingTime = StringTrim(values[4]);
      if (!StringIsDigit(strPendingTime))                                       return(_false(catch("RestoreStatus.Runtime(49)   illegal pending order time \""+ strPendingTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingTime = StrToInteger(strPendingTime);
      if (pendingType==OP_UNDEFINED && pendingTime!=0)                          return(_false(catch("RestoreStatus.Runtime(50)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/'"+ TimeToStr(pendingTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && pendingTime==0)                          return(_false(catch("RestoreStatus.Runtime(51)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/"+ pendingTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingModifyTime
      string strPendingModifyTime = StringTrim(values[5]);
      if (!StringIsDigit(strPendingModifyTime))                                 return(_false(catch("RestoreStatus.Runtime(52)   illegal pending order modification time \""+ strPendingModifyTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingModifyTime = StrToInteger(strPendingModifyTime);
      if (pendingType==OP_UNDEFINED && pendingModifyTime!=0)                    return(_false(catch("RestoreStatus.Runtime(53)   pending order type/modification time mis-match "+ OperationTypeToStr(pendingType) +"/'"+ TimeToStr(pendingModifyTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingPrice
      string strPendingPrice = StringTrim(values[6]);
      if (!StringIsNumeric(strPendingPrice))                                    return(_false(catch("RestoreStatus.Runtime(54)   illegal pending order price \""+ strPendingPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double pendingPrice = StrToDouble(strPendingPrice);
      if (LT(pendingPrice, 0))                                                  return(_false(catch("RestoreStatus.Runtime(55)   illegal pending order price "+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType==OP_UNDEFINED && NE(pendingPrice, 0))                     return(_false(catch("RestoreStatus.Runtime(56)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED) {
         if (EQ(pendingPrice, 0))                                               return(_false(catch("RestoreStatus.Runtime(57)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (NE(pendingPrice, gridBase+level*GridSize*Pips, Digits))            return(_false(catch("RestoreStatus.Runtime(58)   grid base/pending order price mis-match "+ NumberToStr(gridBase, PriceFormat) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" (level "+ level +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // type
      string strType = StringTrim(values[7]);
      if (!StringIsInteger(strType))                                            return(_false(catch("RestoreStatus.Runtime(61)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int type = StrToInteger(strType);
      if (type!=OP_UNDEFINED && !IsTradeOperation(type))                        return(_false(catch("RestoreStatus.Runtime(62)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType == OP_UNDEFINED) {
         if (type == OP_UNDEFINED)                                              return(_false(catch("RestoreStatus.Runtime(63)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }
      else if (type != OP_UNDEFINED) {
         if (IsLongTradeOperation(pendingType)!=IsLongTradeOperation(type))     return(_false(catch("RestoreStatus.Runtime(64)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // openTime
      string strOpenTime = StringTrim(values[8]);
      if (!StringIsDigit(strOpenTime))                                          return(_false(catch("RestoreStatus.Runtime(65)   illegal order open time \""+ strOpenTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime openTime = StrToInteger(strOpenTime);
      if (type==OP_UNDEFINED && openTime!=0)                                    return(_false(catch("RestoreStatus.Runtime(66)   order type/time mis-match "+ OperationTypeToStr(type) +"/'"+ TimeToStr(openTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && openTime==0)                                    return(_false(catch("RestoreStatus.Runtime(67)   order type/time mis-match "+ OperationTypeToStr(type) +"/"+ openTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openPrice
      string strOpenPrice = StringTrim(values[9]);
      if (!StringIsNumeric(strOpenPrice))                                       return(_false(catch("RestoreStatus.Runtime(68)   illegal order open price \""+ strOpenPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openPrice = StrToDouble(strOpenPrice);
      if (LT(openPrice, 0))                                                     return(_false(catch("RestoreStatus.Runtime(69)   illegal order open price "+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(openPrice, 0))                               return(_false(catch("RestoreStatus.Runtime(70)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(openPrice, 0))                               return(_false(catch("RestoreStatus.Runtime(71)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // risk
      string strRisk = StringTrim(values[10]);
      if (!StringIsNumeric(strRisk))                                            return(_false(catch("RestoreStatus.Runtime(87)   illegal order risk \""+ strRisk +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double risk = StrToDouble(strRisk);
      if (LT(risk, 0))                                                          return(_false(catch("RestoreStatus.Runtime(88)   illegal order risk "+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(risk, 0))                                    return(_false(catch("RestoreStatus.Runtime(89)   pending order/risk mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(risk, 0))                                    return(_false(catch("RestoreStatus.Runtime(90)   order type/risk mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(risk, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closeTime
      string strCloseTime = StringTrim(values[11]);
      if (!StringIsDigit(strCloseTime))                                         return(_false(catch("RestoreStatus.Runtime(79)   illegal order close time \""+ strCloseTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime closeTime = StrToInteger(strCloseTime);
      if (closeTime != 0) {
         if (closeTime < pendingTime)                                           return(_false(catch("RestoreStatus.Runtime(80)   pending order time/delete time mis-match '"+ TimeToStr(pendingTime, TIME_FULL) +"'/'"+ TimeToStr(closeTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (closeTime < openTime)                                              return(_false(catch("RestoreStatus.Runtime(81)   order open/close time mis-match '"+ TimeToStr(openTime, TIME_FULL) +"'/'"+ TimeToStr(closeTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // closePrice
      string strClosePrice = StringTrim(values[12]);
      if (!StringIsNumeric(strClosePrice))                                      return(_false(catch("RestoreStatus.Runtime(82)   illegal order close price \""+ strClosePrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closePrice = StrToDouble(strClosePrice);
      if (LT(closePrice, 0))                                                    return(_false(catch("RestoreStatus.Runtime(83)   illegal order close price "+ NumberToStr(closePrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // stopLoss
      string strStopLoss = StringTrim(values[13]);
      if (!StringIsNumeric(strStopLoss))                                        return(_false(catch("RestoreStatus.Runtime(84)   illegal order stoploss \""+ strStopLoss +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double stopLoss = StrToDouble(strStopLoss);
      if (LE(stopLoss, 0))                                                      return(_false(catch("RestoreStatus.Runtime(85)   illegal order stoploss "+ NumberToStr(stopLoss, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (NE(stopLoss, gridBase+(level-MathSign(level))*GridSize*Pips, Digits)) return(_false(catch("RestoreStatus.Runtime(86)   grid base/stoploss mis-match "+ NumberToStr(gridBase, PriceFormat) +"/"+ NumberToStr(stopLoss, PriceFormat) +" (level "+ level +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closedByStop
      string strClosedByStop = StringTrim(values[14]);
      if (!StringIsDigit(strClosedByStop))                                      return(_false(catch("RestoreStatus.Runtime(91)   illegal closedByStop value \""+ strClosedByStop +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      bool closedByStop = _bool(StrToInteger(strClosedByStop));
      if (type!=OP_UNDEFINED && closeTime!=0 && !closedByStop) {
         datetime firstStopTime;
         if (ArraySize(sequenceStopTimes) > 0) firstStopTime = sequenceStopTimes[0];
         if (firstStopTime == 0)                                                return(_false(catch("RestoreStatus.Runtime(92)   sequenceStopTimes[0]/closed position mis-match "+ firstStopTime +"/#"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (closeTime < firstStopTime)                                         return(_false(catch("RestoreStatus.Runtime(93)   sequenceStopTimes[0]/position close time mis-match '"+ TimeToStr(firstStopTime, TIME_FULL) +"'/#"+ ticket +" '"+ TimeToStr(closeTime, TIME_FULL) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // swap
      string strSwap = StringTrim(values[15]);
      if (!StringIsNumeric(strSwap))                                            return(_false(catch("RestoreStatus.Runtime(104)   illegal order swap \""+ strSwap +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double swap = StrToDouble(strSwap);
      if (type==OP_UNDEFINED && NE(swap, 0))                                    return(_false(catch("RestoreStatus.Runtime(105)   pending order/swap mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(swap, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // commission
      string strCommission = StringTrim(values[16]);
      if (!StringIsNumeric(strCommission))                                      return(_false(catch("RestoreStatus.Runtime(106)   illegal order commission \""+ strCommission +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double commission = StrToDouble(strCommission);
      if (type==OP_UNDEFINED && NE(commission, 0))                              return(_false(catch("RestoreStatus.Runtime(107)   pending order/commission mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(commission, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // profit
      string strProfit = StringTrim(values[17]);
      if (!StringIsNumeric(strProfit))                                          return(_false(catch("RestoreStatus.Runtime(108)   illegal order profit \""+ strProfit +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double profit = StrToDouble(strProfit);
      if (type==OP_UNDEFINED && NE(profit, 0))                                  return(_false(catch("RestoreStatus.Runtime(109)   pending order/profit mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(profit, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));


      // Daten speichern
      Grid.SetData(i, ticket, level, gridBase, pendingType, pendingTime, pendingModifyTime, pendingPrice, type, openTime, openPrice, risk, closeTime, closePrice, stopLoss, closedByStop, swap, commission, profit);
      //debug("RestoreStatus.Runtime()   #"+ ticket +"  level="+ level +"  gridBase="+ NumberToStr(gridBase, PriceFormat) +"  pendingType="+ OperationTypeToStr(pendingType) +"  pendingTime='"+ TimeToStr(pendingTime, TIME_FULL) +"'  pendingModifyTime='"+ TimeToStr(pendingModifyTime, TIME_FULL) +"'  pendingPrice="+ NumberToStr(pendingPrice, PriceFormat) +"  type="+ OperationTypeToStr(type) +"  openTime='"+ TimeToStr(openTime, TIME_FULL) +"'  openPrice="+ NumberToStr(openPrice, PriceFormat) +"  risk="+ DoubleToStr(risk, 2) +"  closeTime='"+ TimeToStr(closeTime, TIME_FULL) +"'  closePrice="+ NumberToStr(closePrice, PriceFormat) +"  stopLoss="+ NumberToStr(stopLoss, PriceFormat) +"  closedByStop="+ BoolToStr(closedByStop) +"  swap="+ DoubleToStr(swap, 2) +"  commission="+ DoubleToStr(commission, 2) +"  profit="+ DoubleToStr(profit, 2));
   }

   ArrayResize(values, 0);
   ArrayResize(data,   0);
   return(!IsLastError() && IsNoError(catch("RestoreStatus.Runtime(110)")));
}


/**
 * Gleicht den in der Instanz gespeicherten Laufzeitstatus mit den Online-Daten der laufenden Sequenz ab.
 *
 * @return bool - Erfolgsstatus
 */
bool SynchronizeStatus() {
   if (__STATUS__CANCELLED || IsLastError())
      return(false);

   int sizeOfTickets = ArraySize(orders.ticket);


   // (1.1) alle offenen Tickets in Datenarrays mit Online-Status synchronisieren, gecancelte Orders lokal entfernen
   for (int i=sizeOfTickets-1; i >= 0; i--) {
      if (orders.closeTime[i] == 0) {
         if (!OrderSelectByTicket(orders.ticket[i], "SynchronizeStatus(1)   cannot synchronize "+ OperationTypeDescription(ifInt(orders.type[i]==OP_UNDEFINED, orders.pendingType[i], orders.type[i])) +" order (#"+ orders.ticket[i] +" not found)"))
            return(false);
         if (!Grid.UpdateOrder(i))
            return(false);
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]!=0) {
            if (!Grid.DropTicket(orders.ticket[i]))
               return(false);
            sizeOfTickets--;
         }
      }
   }

   // (1.2) alle erreichbaren Online-Tickets der Sequenz auf lokale Referenz überprüfen
   for (i=OrdersTotal()-1; i >= 0; i--) {                                     // offene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))                        // FALSE: während des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;
      if (IsMyOrder(sequenceId)) /*&&*/ if (!IntInArray(orders.ticket, OrderTicket()))
         return(_false(catch("SynchronizeStatus(2)   unknown open ticket #"+ OrderTicket() +" found (no local reference)", ERR_RUNTIME_ERROR)));
   }
   for (i=OrdersHistoryTotal()-1; i >= 0; i--) {                              // geschlossene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))                       // FALSE: während des Auslesens wurde der Anzeigezeitraum der History verändert
         continue;
      if (IsPendingTradeOperation(OrderType()))                               // gecancelte Orders ignorieren
         continue;
      if (IsMyOrder(sequenceId)) /*&&*/ if (!IntInArray(orders.ticket, OrderTicket()))
         return(_false(catch("SynchronizeStatus(3)   unknown closed ticket #"+ OrderTicket() +" found (no local reference)", ERR_RUNTIME_ERROR)));
   }


   // (2) Laufzeitvariablen restaurieren
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

   #define EV_GRIDBASE_CHANGE    1                                            // Event-Types: {GridBaseChange | PositionOpen | PositionStopout | PositionClose}
   #define EV_POSITION_OPEN      2
   #define EV_POSITION_STOPOUT   3
   #define EV_POSITION_CLOSE     4


   bool   pendingOrder, openPosition, closedPosition, closedByStop;
   double gridBase, profitLoss, pipValue=PipValue(LotSize);
   int    openLevels[]; ArrayResize(openLevels, 0);
   double events[][7];  ArrayResize(events, 0);

   for (i=0; i < sizeOfTickets; i++) {
      pendingOrder   = orders.type[i] == OP_UNDEFINED;
      openPosition   = !pendingOrder && orders.closeTime[i]==0;
      closedPosition = !pendingOrder && !openPosition;
      closedByStop   = closedPosition && orders.closedByStop[i];

      if (closedPosition && !closedByStop)
         if (ArraySize(openLevels) != 0)                 return(_false(catch("SynchronizeStatus(4)   illegal sequence status, both open (#?) and closed (#"+ orders.ticket[i] +") positions found", ERR_RUNTIME_ERROR)));

      if (!pendingOrder) {
         profitLoss = orders.swap[i] + orders.commission[i] + orders.profit[i];
         Sync.PushBreakevenEvent(events, orders.openTime[i], EV_POSITION_OPEN, orders.gridBase[i], orders.level[i], NULL, NULL, orders.risk[i]);

         if (openPosition) {
            grid.floatingPL += profitLoss;
            if (IntInArray(openLevels, orders.level[i])) return(_false(catch("SynchronizeStatus(5)   duplicate order level "+ orders.level[i] +" of open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
            ArrayPushInt(openLevels, orders.level[i]);
         }
         else if (closedByStop) {
            Sync.PushBreakevenEvent(events, orders.closeTime[i], EV_POSITION_STOPOUT, orders.gridBase[i], orders.level[i], profitLoss, NULL, -orders.risk[i]);
         }
         else /*(closed)*/ {
            Sync.PushBreakevenEvent(events, orders.closeTime[i], EV_POSITION_CLOSE, orders.gridBase[i], orders.level[i], NULL, profitLoss, NULL);
         }
      }
      if (IsLastError())
         return(false);
   }

   // GridBase-Änderungen zu den Breakeven-Events hinzufügen
   int sizeOfGridBase = ArraySize(grid.base.time);
   for (i=0; i < sizeOfGridBase; i++) {
      Sync.PushBreakevenEvent(events, grid.base.time[i], EV_GRIDBASE_CHANGE, grid.base.value[i], 0, NULL, NULL, NULL);
   }

   if (ArraySize(openLevels) != 0) {
      int min = openLevels[ArrayMinimum(openLevels)];
      int max = openLevels[ArrayMaximum(openLevels)];
      if (min < 0 && max > 0)                return(_false(catch("SynchronizeStatus(6)   illegal sequence status, both open long and short positions found", ERR_RUNTIME_ERROR)));
      int maxLevel = MathMax(MathAbs(min), MathAbs(max)) +0.1;                // (int) double
      if (ArraySize(openLevels) != maxLevel) return(_false(catch("SynchronizeStatus(7)   illegal sequence status, one or more open positions missed", ERR_RUNTIME_ERROR)));
   }

   // status
   int starts = ArraySize(sequenceStartTimes);
   if (starts > 0) {
      if (sequenceStopTimes[starts-1] == 0) {
         status = STATUS_PROGRESSING;
      }
      else {
         status = STATUS_STOPPED;
         if (ArraySize(openLevels) != 0) return(_false(catch("SynchronizeStatus(8)   illegal sequence status "+ StatusToStr(status) +", open positions found", ERR_RUNTIME_ERROR)));
      }
   }


   // (3) Start-/Stop-Marker und Orders zeichnen
   RedrawStartStop();
   RedrawOrders();


   // (4) Breakeven-Verlauf restaurieren und Indikator neu zeichnen
   datetime time, lastTime;
   int minute, lastMinute, type, level;
   int sizeOfEvents = ArrayRange(events, 0);

   if (sizeOfEvents > 0)
      ArraySort(events);                                                      // Breakeven-Änderungen zeitlich sortieren

   for (i=0; i < sizeOfEvents; i++) {
      time = events[i][0] +0.1;                                               // (datetime) double

      // zwischen den Breakeven-Events liegende BarOpen(M1)-Events simulieren
      if (lastTime > 0) {
         minute = time/60; lastMinute = lastTime/60;
         while (lastMinute < minute-1) {                                      // TODO: fehlende Sessions überspringen (Wochenende)
            lastMinute++;
            Grid.DrawBreakeven(lastMinute * MINUTES);
         }
      }
      type             = events[i][1] +0.1;                                   // (int) double
      grid.base        = events[i][2];
      level            = events[i][3] + MathSign(events[i][3])*0.1;           // (int) double
      grid.stopsPL    += events[i][4];
      grid.closedPL   += events[i][5];
      grid.activeRisk += events[i][6];
      grid.valueAtRisk = grid.activeRisk - grid.stopsPL;                      // valueAtRisk = -stopsPL + activeRisk
      //debug("SynchronizeStatus()   event: "+ BreakevenEventToStr(type) +"   level="+ level);

      if      (type == EV_POSITION_OPEN   ) { grid.level = level;                               }
      else if (type == EV_POSITION_STOPOUT) { grid.level = level-MathSign(level); grid.stops++; }

      Grid.UpdateBreakeven(time);
      lastTime = time;
   }


   grid.totalPL = grid.stopsPL + grid.closedPL + grid.floatingPL;
   SS.All();


   debug("SynchronizeStatus() level="      + grid.level
                          +"  stops="      + grid.stops
                          +"  stopsPL="    + DoubleToStr(grid.stopsPL,     2)
                          +"  closedPL="   + DoubleToStr(grid.closedPL,    2)
                          +"  floatingPL=" + DoubleToStr(grid.floatingPL,  2)
                          +"  totalPL="    + DoubleToStr(grid.totalPL,     2)
                          +"  activeRisk=" + DoubleToStr(grid.activeRisk,  2)
                          +"  valueAtRisk="+ DoubleToStr(grid.valueAtRisk, 2));


   ArrayResize(openLevels, 0);
   ArrayResize(events,     0);
   return(IsNoError(catch("SynchronizeStatus(9)")));
}


/**
 * Fügt den Breakeven-relevanten Events ein weiteres hinzu.
 *
 * @param  double   events[]   - Array mit bereits gespeicherten Events
 * @param  datetime time       - Zeitpunkt des Events
 * @param  int      type       - Event-Typ: EV_GRIDBASE_CHANGE | EV_POSITION_OPEN | EV_POSITION_STOPOUT | EV_POSITION_CLOSE
 * @param  double   gridBase   - Gridbasis des Events
 * @param  int      level      - Gridlevel des Events
 * @param  double   stopsPL    - Änderung des Stopout-Profit/Loss durch das Event
 * @param  double   closedPL   - Änderung des Closed-Profit/Loss durch das Event
 * @param  double   activeRisk - Änderung des aktiven Risikos durch das Event (ändert sich nur bei Wechsel des Levels)
 *
 * @return bool - Erfolgsstatus
 */
bool Sync.PushBreakevenEvent(double& events[][], datetime time, int type, double gridBase, int level, double stopsPL, double closedPL, double activeRisk) {
   int size = ArrayRange(events, 0);
   ArrayResize(events, size+1);

   events[size][0] = time;
   events[size][1] = type;
   events[size][2] = gridBase;
   events[size][3] = level;
   events[size][4] = stopsPL;
   events[size][5] = closedPL;
   events[size][6] = activeRisk;

   grid.maxLevelLong  = MathMax(grid.maxLevelLong,  level) +0.1;        // (int) double
   grid.maxLevelShort = MathMin(grid.maxLevelShort, level) -0.1;        // (int) double

   //debug("Sync.PushBreakevenEvent()   time='"+ TimeToStr(time, TIME_FULL) +"'  type="+ StringRightPad(BreakevenEventToStr(type), 19, " ") +"  gridBase="+ NumberToStr(gridBase, PriceFormat) +"  level="+ level +"  stopsPL="+ DoubleToStr(stopsPL, 2) +"  closedPL="+ DoubleToStr(closedPL, 2) +"  activeRisk="+ DoubleToStr(activeRisk, 2));

   return(IsNoError(catch("Sync.PushBreakevenEvent()")));
}


/**
 * Ermittelt das aktuelle Risiko des angegebenen Levels, inkl. Slippage. Dazu muß eine Position in diesem Level offen sein.
 * Ohne offene Position gibt es nur ein theoretisches (Gridsize-abhängiges) Risiko, das hier nicht interessiert.
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
      if (orders.closedByStop[i])                                    // Abbruch vor erster durch StopLoss geschlossenen Position des Levels (wir iterieren rückwärts)
         break;

      realized += orders.swap[i] + orders.commission[i] + orders.profit[i];
   }

   double stopLoss      = gridBase + (level-MathSign(level)) * GridSize * Pips;
   double stopLossValue = -MathAbs(openPrice-stopLoss)/Pips * PipValue(LotSize);
   double risk          = realized + stopLossValue + swap + commission;
   //debug("CalculateActiveRisk()   level="+ level +"  realized="+ DoubleToStr(realized, 2) +"  stopLoss="+ NumberToStr(stopLoss, PriceFormat) +"  slValue="+ DoubleToStr(stopLossValue, 2) +"  risk="+ DoubleToStr(risk, 2));

   return(NormalizeDouble(-risk, 2));                                // Rückgabewert für Verlustrisiko soll positiv sein
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
         if (i == 0) time  = instanceStartTime;
         else        time  = sequenceStartTimes [i];
                     price = sequenceStartPrices[i];
      }
      label = StringConcatenate("SR.", sequenceId, ".start.", i);
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      ObjectCreate(label, OBJ_ARROW, 0, time, price);
      ObjectSet   (label, OBJPROP_ARROWCODE, SYMBOL_LEFTPRICE);
      ObjectSet   (label, OBJPROP_BACK,      false           );
      ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor);
   }


   // (2) Stop-Marker
   for (i=0; i < starts; i++) {
      if (sequenceStopTimes[i] > 0) {
         time  = sequenceStopTimes [i];
         price = sequenceStopPrices[i];
         label = StringConcatenate("SR.", sequenceId, ".stop.", i);
         if (ObjectFind(label) == 0)
            ObjectDelete(label);
         ObjectCreate(label, OBJ_ARROW, 0, time, price);
         ObjectSet   (label, OBJPROP_ARROWCODE, SYMBOL_LEFTPRICE);
         ObjectSet   (label, OBJPROP_BACK,      false            );
         ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor);
      }
   }

   catch("RedrawStartStop()");
}


/**
 * Visualisiert die Orders entsprechend dem aktuellen OrderDisplay-Mode.
 */
void RedrawOrders() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   bool pendingOrder, closedPosition;
   int  size = ArraySize(orders.ticket);

   for (int i=0; i < size; i++) {
      pendingOrder   = orders.type[i] == OP_UNDEFINED;
      closedPosition = !pendingOrder && orders.closeTime[i]!=0;

      if     (pendingOrder)                         ChartMarker.OrderSent(i);
      else /*(openPosition || closedPosition)*/ {                                   // openPosition ist Folge einer
         if (orders.pendingType[i] != OP_UNDEFINED) ChartMarker.OrderFilled(i);     // ...ausgeführten Pending-
         else                                       ChartMarker.OrderSent(i);       // ...oder Market-Order
         if (closedPosition)                        ChartMarker.PositionClosed(i);
      }
   }
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
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               Closed
   #define DM_ALL       3     // Pending, Open, ClosedByStop, Closed
   */
   bool pending = orders.pendingType[i] != OP_UNDEFINED;

   int      type        =    ifInt(pending, orders.pendingType [i], orders.type     [i]);
   datetime openTime    =    ifInt(pending, orders.pendingTime [i], orders.openTime [i]);
   double   openPrice   = ifDouble(pending, orders.pendingPrice[i], orders.openPrice[i]);
   string   comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(orders.level[i], "+."));
   color    markerColor = CLR_NONE;

   if (orderDisplayMode != DM_NONE) {
      if (pending || orderDisplayMode >= DM_PYRAMID)
         markerColor = ifInt(IsLongTradeOperation(type), CLR_LONG, CLR_SHORT);
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
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               Closed
   #define DM_ALL       3     // Pending, Open, ClosedByStop, Closed
   */
   string comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(orders.level[i], "+."));
   color  markerColor = CLR_NONE;

   if (orderDisplayMode >= DM_PYRAMID)
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
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               Closed
   #define DM_ALL       3     // Pending, Open, ClosedByStop, Closed
   */
   color markerColor = CLR_NONE;

   if (orderDisplayMode != DM_NONE) {
      if ( orders.closedByStop[i] && orderDisplayMode!=DM_PYRAMID) markerColor = CLR_CLOSE;
      if (!orders.closedByStop[i] && orderDisplayMode>=DM_PYRAMID) markerColor = CLR_CLOSE;
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
      ArrayResize(orders.ticket,            size);
      ArrayResize(orders.level,             size);
      ArrayResize(orders.gridBase,          size);
      ArrayResize(orders.pendingType,       size);
      ArrayResize(orders.pendingTime,       size);
      ArrayResize(orders.pendingModifyTime, size);
      ArrayResize(orders.pendingPrice,      size);
      ArrayResize(orders.type,              size);
      ArrayResize(orders.openTime,          size);
      ArrayResize(orders.openPrice,         size);
      ArrayResize(orders.risk,              size);
      ArrayResize(orders.closeTime,         size);
      ArrayResize(orders.closePrice,        size);
      ArrayResize(orders.stopLoss,          size);
      ArrayResize(orders.closedByStop,      size);
      ArrayResize(orders.swap,              size);
      ArrayResize(orders.commission,        size);
      ArrayResize(orders.profit,            size);
   }

   if (reset) {                                                      // alle Felder zurücksetzen
      if (size != 0) {
         ArrayInitialize(orders.ticket,                     0);
         ArrayInitialize(orders.level,                      0);
         ArrayInitialize(orders.gridBase,                   0);
         ArrayInitialize(orders.pendingType,     OP_UNDEFINED);
         ArrayInitialize(orders.pendingTime,                0);
         ArrayInitialize(orders.pendingModifyTime,          0);
         ArrayInitialize(orders.pendingPrice,               0);
         ArrayInitialize(orders.type,            OP_UNDEFINED);
         ArrayInitialize(orders.openTime,                   0);
         ArrayInitialize(orders.openPrice,                  0);
         ArrayInitialize(orders.risk,                       0);
         ArrayInitialize(orders.closeTime,                  0);
         ArrayInitialize(orders.closePrice,                 0);
         ArrayInitialize(orders.stopLoss,                   0);
         ArrayInitialize(orders.closedByStop,           false);
         ArrayInitialize(orders.swap,                       0);
         ArrayInitialize(orders.commission,                 0);
         ArrayInitialize(orders.profit,                     0);
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
   GridDirectionToStr(NULL);
   OrderDisplayModeToStr(NULL);
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
      case DM_NONE   : return("DM_NONE"   );
      case DM_STOPS  : return("DM_STOPS"  );
      case DM_PYRAMID: return("DM_PYRAMID");
      case DM_ALL    : return("DM_ALL"    );
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
