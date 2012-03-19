/**
 * SnowRoller - Pyramiding Anti-Martingale Grid
 *
 *
 * Trade-Modes:
 * ------------
 * - Bidirectional: ein bi-direktionales Grid mit fester Gridbasis in Long- und Short-Richtung (schlechteste Performance)
 * - Long         : ein uni-direktionales Grid mit Trailing-Gridbasis in Long-Richtung (gute Performance)
 * - Short        : ein uni-direktionales Grid mit Trailing-Gridbasis in Short-Richtung (gute Performance)
 * - Long + Short : zwei sich überlagernde uni-direktionale Grids mit Trailing-Gridbasis in Long- und Short-Richtung (beste Performance)
 *
 *
 * @see http://sites.google.com/site/prof7bit/snowball
 *
 *
 *  TODO:
 *  -----
 *  - ein- und beidseitig unidirektionales Grid implementieren             *
 *  - Pause/Resume implementieren                                          *
 *  - PendingOrders nicht per Tick trailen                                 *
 *  - Exit-Rule implementieren: onBreakeven, onProfit(value|pip), onLimit  *
 *
 *  - Umschaltung der OrderDisplay-Modes per Hotkey implementieren
 *  - onBarOpen(PERIOD_M1) für Breakeven-Indikator implementieren
 *  - EventListener.BarOpen() muß Event auch erkennen, wenn er nicht bei jedem Tick aufgerufen wird
 *  - Upload der Statusdatei implementieren
 *  - STATUS_FINISHING und STATUS_MONITORING implementieren
 *  - Laufzeit im Tester optimieren (I/O-Operations, Logging, etc.)
 *  - StartCondition "@time" implementieren
 *  - Client-Side-Limits implementieren
 *  - Heartbeat implementieren
 */
#include <stdlib.mqh>
#include <win32api.mqh>


int Strategy.Id = 103;                       // eindeutige ID der Strategie (Bereich 101-1023)


// Grid-Directions
#define D_BIDIR               0              // default
#define D_LONG                1
#define D_SHORT               2
#define D_LONG_SHORT          3


// Sequenzstatus-Werte
#define STATUS_WAITING        0              // default
#define STATUS_PROGRESSING    1
#define STATUS_FINISHED       2
#define STATUS_DISABLED       3


// OrderDisplay-Modes
#define DM_NONE               0              // - keine Anzeige -
#define DM_STOPS              1              // Pending,       ClosedByStop
#define DM_PYRAMID            2              // Pending, Open,               ClosedByFinish (default)
#define DM_ALL                3              // Pending, Open, ClosedByStop, ClosedByFinish


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern               string GridDirection                   = "Bidirectional";
extern               string GridDirection.Help              = "Bidirectional* | Long | Short | L+S (2 grids)";
extern               int    GridSize                        = 20;
extern               double LotSize                         = 0.1;
extern               string StartCondition                  = "";
extern /*transient*/ string OrderDisplayMode                = "Pyramid";
extern               string OrderDisplayMode.Help           = "None | Stops | Pyramid* | All";
extern /*transient*/ color  Color.Breakeven                 = DodgerBlue;
extern               string _______________________________ = "======== Sequence to Manage =========";
extern /*transient*/ string Sequence.ID                     = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


string   last.GridDirection;                             // Input-Parameter sind nicht statisch. Werden sie extern geladen, werden sie bei REASON_CHARTCHANGE
int      last.GridSize;                                  // mit den Default-Parametern überschrieben. Um dies rückgängig machen zu können und um bei Parameter-
double   last.LotSize;                                   // änderungen neue mit alten Werten vergleichen zu können, werden sie in deinit() in last.* zwischen-
string   last.StartCondition;                            // gespeichert.
string   last.OrderDisplayMode;
color    last.Color.Breakeven;
string   last.Sequence.ID;

int      sequenceId;
int      status       = STATUS_WAITING;
bool     testSequence = false;                           // ob diese Sequenz ein Backtest ist oder war (*nicht*, ob der Test gerade läuft)

datetime sequenceStartTime;
double   sequenceStartPrice;
datetime sequenceStopTime;
double   sequenceStopPrice;

double   entry.limit;
double   entry.lastBid;

int      grid.direction = D_BIDIR;
int      grid.level;                                     // aktueller Grid-Level
int      grid.maxLevelLong;                              // maximal erreichter Long-Level
int      grid.maxLevelShort;                             // maximal erreichter Short-Level

double   grid.base;                                      // aktuelle Gridbasis
datetime grid.base.time [];                              // Zeitpunkt einer Änderung der Gridbasis
double   grid.base.value[];                              // Gridbasis zum Zeitpunkt

int      grid.stops;                                     // Anzahl der bisher getriggerten Stops
double   grid.stopsPL;                                   // P/L der getriggerten Stops (0 oder negativ)
double   grid.finishedPL;                                // P/L sonstiger geschlossener Positionen (realizedPL = stopsPL + finishedPL)
double   grid.floatingPL;                                // P/L offener Positionen
double   grid.totalPL;                                   // Gesamt-P/L der Sequenz:  realizedPL + floatingPL
double   grid.openStopValue;                             // Stoploss-Betrag aller offenen Positionen (0 oder positiv)
double   grid.valueAtRisk;                               // aktuelles Maximalrisiko: -realizedPL + openStopValue (0 oder positiv)

double   grid.maxProfitLoss;                             // maximal erreichter Gesamtprofit (0 oder positiv)
datetime grid.maxProfitLossTime;                         // Zeitpunkt von grid.maxProfitLoss
double   grid.maxDrawdown;                               // maximal erreichter Drawdown (0 oder negativ)
datetime grid.maxDrawdownTime;                           // Zeitpunkt von grid.maxDrawdown
double   grid.breakevenLong;
double   grid.breakevenShort;

int      orders.ticket           [];
int      orders.level            [];                     // Grid-Level der Order

int      orders.pendingType      [];                     // Pending-Orderdaten (falls zutreffend)
datetime orders.pendingTime      [];
datetime orders.pendingModifyTime[];
double   orders.pendingPrice     [];
double   orders.pendingExecution [];

int      orders.type             [];
datetime orders.openTime         [];
double   orders.openPrice        [];
double   orders.openSlippage     [];
double   orders.openExecution    [];

datetime orders.closeTime        [];
double   orders.closePrice       [];
double   orders.closeSlippage    [];
double   orders.closeExecution   [];
double   orders.stopLoss         [];
double   orders.stopValue        [];
bool     orders.closedByStop     [];

double   orders.swap             [];
double   orders.commission       [];
double   orders.profit           [];

string   str.testSequence        = "";                   // Speichervariablen für schnellere Abarbeitung von ShowStatus()
string   str.LotSize             = "";
string   str.entry.limit         = "";
string   str.grid.base           = "";
string   str.grid.direction      = "";
string   str.grid.maxLevel       = "";
string   str.grid.stops          = "0 stops";
string   str.grid.stopsPL        = "0.00";
string   str.grid.totalPL        = "0.00";
string   str.grid.valueAtRisk    = "0.00";
string   str.grid.maxProfitLoss  = "0.00";
string   str.grid.maxDrawdown    = "0.00";
string   str.grid.breakeven      = "";

color    CLR_LONG  = Blue;
color    CLR_SHORT = Red;
color    CLR_CLOSE = Orange;

int      orderDisplayMode;
bool     firstTick        = true;
bool     breakevenUpdated = false;                       // ob Breakeven während des aktuellen Ticks bereits neuberechnet wurde (verhindert Mehrfachberechnungen)


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int init() {
   if (IsError(onInit(T_EXPERT)))
      return(ShowStatus(true));
   /*
   Zuerst wird die aktuelle Sequenz-ID bestimmt und deren Konfiguration geladen und validiert. Dann wird der Laufzeitstatus der Sequenz restauriert.
   Es gibt 4 unterschiedliche init()-Szenarien:

   (1.1) Recompilation:                    keine internen Daten vorhanden, evt. transienter Status im Chart
   (1.2) Neustart des EA, evt. im Tester:  keine internen Daten vorhanden, evt. transienter Status im Chart
   (1.3) Parameteränderung:                alle internen Daten vorhanden, externer Status unnötig
   (1.4) Timeframe-Wechsel:                alle internen Daten vorhanden, externer Status unnötig
   */

   // (1) Sind keine internen Daten vorhanden, befinden wir uns in Szenario 1.1 oder 1.2.
   if (sequenceId == 0) {

      // (1.1) Recompilation ----------------------------------------------------------------------------------------------------------------------------------
      if (UninitializeReason() == REASON_RECOMPILE) {
         if (RestoreTransientStatus())                               // falls transienter Status vorhanden (im Chart), restaurieren
            if (RestoreStatus())                                     // ohne transienten Status weiter in (1.2)
               if (ValidateConfiguration())
                  SynchronizeStatus();
      }

      // (1.2) Neustart ---------------------------------------------------------------------------------------------------------------------------------------
      if (sequenceId == 0) {
         if (IsInputSequenceId()) {                                  // Zuerst eine ausdrücklich angegebene Sequenz restaurieren...
            if (RestoreInputSequenceId())
               if (RestoreStatus())
                  if (ValidateConfiguration())
                     SynchronizeStatus();
         }
         else if (RestoreTransientStatus()) {                        // ...dann ggf. transiente (im Chart gespeicherte) Sequenz restaurieren...
            if (RestoreStatus())
               if (ValidateConfiguration())
                  SynchronizeStatus();
         }
         else if (RestoreRunningSequenceId()) {                      // ...dann ID aus laufender Sequenz restaurieren.
            if (RestoreStatus())
               if (ValidateConfiguration())
                  SynchronizeStatus();
         }
         else if (ValidateConfiguration()) {                         // Zum Schluß neue Sequenz anlegen.
            sequenceId   = CreateSequenceId(); SS.SequenceId();
            testSequence = IsTesting();        SS.TestSequence();
            if (StartCondition != "")                                // Ohne StartCondition erfolgt sofortiger Einstieg, in diesem Fall wird der
               SaveStatus();                                         // Status erst nach Sicherheitsabfrage in StartSequence() gespeichert.
         }
      }
      ClearTransientStatus();
   }

   // (1.3) Parameteränderung ---------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_PARAMETERS) {             // alle internen Daten sind vorhanden
      if (ValidateConfiguration(REASON_PARAMETERS)) {
         /*
         if (ConfigurationChanged()) {
            // GridDirection  = last.GridDirection;
            // GridSize       = last.GridSize;
            // LotSize        = last.LotSize;
            // StartCondition = last.StartCondition;
            // Sequence.ID    = last.Sequence.ID;                    // TODO: Sequence.ID kann geändert worden sein
            SaveStatus();
         }
         */
         if (OrderDisplayMode != last.OrderDisplayMode) { RedrawOrders();                        }
         if (Color.Breakeven  != last.Color.Breakeven)  { RedrawStartStop(); RecolorBreakeven(); }
      }
   }

   // (1.4) Timeframewechsel ----------------------------------------------------------------------------------------------------------------------------------
   else if (UninitializeReason() == REASON_CHARTCHANGE) {
      GridDirection    = last.GridDirection;                         // Alle internen Daten sind vorhanden, es werden nur die nicht-statischen
      GridSize         = last.GridSize;                              // Input-Parameter restauriert.
      LotSize          = last.LotSize;
      StartCondition   = last.StartCondition;
      OrderDisplayMode = last.OrderDisplayMode;
      Color.Breakeven  = last.Color.Breakeven;
      Sequence.ID      = last.Sequence.ID;
   }

   // ---------------------------------------------------------------------------------------------------------------------------------------------------------
   else catch("init(1)   unknown init() scenario", ERR_RUNTIME_ERROR);


   // (2) Status anzeigen
   ShowStatus(true);
   if (IsLastError())
      return(last_error);


   // (3) ggf. EA's aktivieren
   int reasons1[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT };
   if (IntInArray(reasons1, UninitializeReason())) /*&&*/ if (!IsExpertEnabled())
      SwitchExperts(true);                                        // TODO: Bug, wenn mehrere EA's den EA-Modus gleichzeitig einschalten


   // (4) nicht auf den nächsten Tick warten (außer bei REASON_CHARTCHANGE oder REASON_ACCOUNT)
   int reasons2[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_APPEXIT, REASON_PARAMETERS, REASON_RECOMPILE };
   if (IntInArray(reasons2, UninitializeReason())) /*&&*/ if (!IsTesting())
      SendTick(false);

   return(catch("init(2)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int deinit() {
   if (UninitializeReason()==REASON_CHARTCHANGE || UninitializeReason()==REASON_PARAMETERS) {
      // REASON_CHARTCHANGE: Input-Parameter sind nicht statisch und werden für's nächste init() zwischengespeichert
      // REASON_PARAMETERS:  Input-Parameter werden für Vergleich mit neuen Parametern zwischengespeichert
      last.GridDirection    = GridDirection;
      last.GridSize         = GridSize;
      last.LotSize          = LotSize;
      last.StartCondition   = StartCondition;
      last.OrderDisplayMode = OrderDisplayMode;
      last.Color.Breakeven  = Color.Breakeven;
      last.Sequence.ID      = Sequence.ID;
      return(catch("deinit(1)"));
   }

   if (IsTesting()) {
      if (StopSequence())                                               // ruft intern ggf. UpdateStatus() und SaveStatus() auf
         ShowStatus();
   }
   else if (UpdateStatus()) {
      SaveStatus();
   }

   if (UninitializeReason()==REASON_CHARTCLOSE || UninitializeReason()==REASON_RECOMPILE)
      StoreTransientStatus();

   return(catch("deinit(2)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (status==STATUS_FINISHED || status==STATUS_DISABLED)
      return(last_error);

   static int    last.grid.level;
   static double last.grid.base;

   breakevenUpdated = false;


   // ****** TEMPORÄR ******
   //if (sequenceId==11857 && StringICompare(GetComputerName(), "sirius")) {
   // ****** TEMPORÄR ******


   // (1) Sequenz wartet entweder auf Startsignal...
   if (status == STATUS_WAITING) {
      if (IsStartSignal())                    StartSequence();
   }

   // (2) ...oder läuft: Daten und Orders aktualisieren
   else if (UpdateStatus()) {
      if      (IsProfitTargetReached())       StopSequence();
      else if (grid.level != last.grid.level) UpdatePendingOrders();
      else if (NE(grid.base, last.grid.base)) UpdatePendingOrders();
   }

   last.grid.level = grid.level;
   last.grid.base  = grid.base;
   firstTick       = false;


   // (3) Status anzeigen
   ShowStatus();


   if (IsLastError())
      return(last_error);
   return(catch("onTick()"));
}


/**
 * Prüft und synchronisiert die im EA gespeicherten mit den aktuellen Laufzeitdaten.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (!IsTesting()) /*&&*/ if (IsTestSequence())
      return(false);

   grid.floatingPL = 0;

   bool wasPending, isClosed;
   int  orders = ArraySize(orders.ticket);


   // (1) Tickets prüfen
   for (int i=0; i < orders; i++) {
      if (orders.closeTime[i] == 0) {                                // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "UpdateStatus(1)"))
            return(false);

         wasPending = orders.type[i] == OP_UNDEFINED;                // ob die Order beim letzten Aufruf "pending" war

         if (wasPending) {
            // beim letzten Aufruf Pending-Order
            if (OrderType() != orders.pendingType[i]) {              // Order wurde ausgeführt
               orders.type        [i] = OrderType();
               orders.openTime    [i] = OrderOpenTime();
               orders.openPrice   [i] = OrderOpenPrice();
               orders.openSlippage[i] = GetOpenPriceSlippage(i);
               orders.stopValue   [i] = (GridSize + orders.openSlippage[i]) * PipValue(LotSize);         // um Slippage justiert
               orders.swap        [i] = OrderSwap();
               orders.commission  [i] = OrderCommission();
               orders.profit      [i] = OrderProfit();
               ChartMarker.OrderFilled(i);

               grid.level         += MathSign(orders.level[i]);
               grid.maxLevelLong   = MathMax(grid.level, grid.maxLevelLong ) +0.1;                       // (int) double
               grid.maxLevelShort  = MathMin(grid.level, grid.maxLevelShort) -0.1; SS.Grid.MaxLevel();   // (int) double
               grid.openStopValue += orders.stopValue[i];                                                // realizedPL = stopsPL + finishedPL
               grid.valueAtRisk    = grid.openStopValue - grid.stopsPL; SS.Grid.ValueAtRisk();           // ohne finishedPL => ist während Laufzeit 0
               breakevenUpdated    = Grid.UpdateBreakeven();
            }
         }
         else {
            // beim letzten Aufruf offene Position
            orders.swap      [i] = OrderSwap();
            orders.commission[i] = OrderCommission();
            orders.profit    [i] = OrderProfit();
         }

         isClosed = OrderCloseTime() != 0;                           // ob das Ticket jetzt geschlossen ist

         if (!isClosed) {                                            // weiterhin offenes Ticket
            grid.floatingPL += OrderSwap() + OrderCommission() + OrderProfit();
         }
         else {                                                      // jetzt geschlossenes Ticket: gestrichene Pending-Order oder geschlossene Position
            orders.closeTime [i] = OrderCloseTime();                 // Bei Spikes kann eine Pending-Order ausgeführt *und* bereits geschlossen sein.
            orders.closePrice[i] = OrderClosePrice();

            if (orders.type[i] == OP_UNDEFINED) {                    // gestrichene Pending-Order
            }
            else {                                                   // geschlossene Position
               orders.closedByStop [i] = IsOrderClosedByStop();
               orders.closeSlippage[i] = GetClosePriceSlippage(i);
               ChartMarker.PositionClosed(i);

               grid.openStopValue -= orders.stopValue[i];

               if (orders.closedByStop[i]) {
                  grid.level      -= MathSign(orders.level[i]);
                  grid.stops++;
                  grid.stopsPL    += orders.swap[i] + orders.commission[i] + orders.profit[i]; SS.Grid.Stops();
                  grid.valueAtRisk = grid.openStopValue - grid.stopsPL; SS.Grid.ValueAtRisk();  // ohne finishedPL => ist während Laufzeit 0 und wird ab Sequenzstop nicht mehr berücksichtigt
               }
               else {
                  grid.finishedPL += orders.swap[i] + orders.commission[i] + orders.profit[i];  // bei Sequenzstop geschlossen, valueAtRisk wird nicht mehr verändert
               }
               breakevenUpdated = Grid.UpdateBreakeven();
            }
         }
      }
   }


   // (2) P/L-Kennziffern  aktualisieren
   grid.totalPL = grid.stopsPL + grid.finishedPL + grid.floatingPL; SS.Grid.TotalPL();

   if (grid.totalPL > grid.maxProfitLoss) {
      grid.maxProfitLoss     = grid.totalPL;
      grid.maxProfitLossTime = TimeCurrent(); SS.Grid.MaxProfitLoss();
   }
   else if (grid.totalPL < grid.maxDrawdown) {
      grid.maxDrawdown     = grid.totalPL;
      grid.maxDrawdownTime = TimeCurrent(); SS.Grid.MaxDrawdown();
   }


   // (3) Gridbasis prüfen und ggf. trailen
   if (grid.level == 0) {
      double price = NormalizeDouble((Bid + Ask)/2, Digits);
      if (grid.direction == D_LONG) {
         if (LT(price, grid.base)) {
            grid.base = price; SS.Grid.Base();
            if (grid.maxLevelLong != 0) {
               Grid.BaseChange(TimeCurrent(), grid.base);            // ab dem ersten ausgeführten Trade Änderung tracken...
               breakevenUpdated = Grid.UpdateBreakeven();            // ...und Breakeven neuberechnen
            }
         }
      }
      else if (grid.direction == D_SHORT) {
         if (GT(price, grid.base)) {
            grid.base = price; SS.Grid.Base();
            if (grid.maxLevelShort != 0) {
               Grid.BaseChange(TimeCurrent(), grid.base);            // ab dem ersten ausgeführten Trade Änderung tracken...
               breakevenUpdated = Grid.UpdateBreakeven();            // ...und Breakeven neuberechnen
            }
         }
      }
   }


   // (4) 1 mal je Minute Breakeven neuzeichnen, damit Indikator bei Timeframewechsel immer aktuell ist
   if      (!IsTesting())   HandleEvent(EVENT_BAR_OPEN/*, F_PERIOD_M1*/);
   else if (IsVisualMode()) HandleEvent(EVENT_BAR_OPEN);             // TODO: EventListener muß Event auch ohne permanenten Aufruf erkennen

   return(IsNoError(catch("UpdateStatus(2)")));
}


/**
 * Handler für BarOpen-Events.
 *
 * @param int timeframes[] - IDs der Timeframes, in denen das BarOpen-Event aufgetreten ist
 *
 * @return int - Fehlerstatus
 */
int onBarOpen(int timeframes[]) {
   // Breakeven neuzeichnen, damit Indikator bei Timeframewechsel immer aktuell ist
   if (!breakevenUpdated) {
      if (grid.maxLevelLong-grid.maxLevelShort > 0)                  // jedoch nicht vor dem ersten ausgeführten Trade
         Grid.DrawBreakeven();
   }
   return(catch("onBarOpen()"));
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

   if (closed) /*&&*/ if (position) /*&&*/ if (NE(OrderStopLoss(), 0)) {
      if (StringIEndsWith(OrderComment(), "[sl]")) closedByStop = true;
      else if (OrderType() == OP_BUY )             closedByStop = LE(OrderClosePrice(), OrderStopLoss());
      else if (OrderType() == OP_SELL)             closedByStop = GE(OrderClosePrice(), OrderStopLoss());
   }
   return(closedByStop);
}


/**
 * Signalgeber für StartSequence(). Wurde kein Limit angegeben (StartCondition = 0 oder ""), gibt die Funktion immer TRUE zurück.
 *
 * @return bool - ob die konfigurierte StartCondition erfüllt ist
 */
bool IsStartSignal() {
   // Das Limit ist erreicht, wenn der Bid-Preis es seit dem letzten Tick berührt oder gekreuzt hat.
   if (EQ(entry.limit, 0))                                           // kein Limit definiert => immer TRUE
      return(true);

   if (EQ(Bid, entry.limit) || EQ(entry.lastBid, entry.limit)) {     // Bid liegt oder lag beim letzten Tick exakt auf dem Limit
      entry.lastBid = entry.limit;                                   // Tritt während der weiteren Verarbeitung des Ticks ein behandelbarer Fehler auf, wird durch
      return(true);                                                  // entry.lastBid = entry.limit das Limit, einmal getriggert, nachfolgend immer wieder getriggert.
   }

   static bool lastBid.init = false;

   if (EQ(entry.lastBid, 0)) {                                       // entry.lastBid muß initialisiert sein => ersten Aufruf überspringen und Status merken,
      lastBid.init = true;                                           // um firstTick bei erstem tatsächlichen Test gegen entry.lastBid auf TRUE zurückzusetzen
   }
   else {
      if (LT(entry.lastBid, entry.limit)) {
         if (GT(Bid, entry.limit)) {                                 // Bid hat Limit von unten nach oben gekreuzt
            entry.lastBid = entry.limit;
            return(true);
         }
      }
      else if (LT(Bid, entry.limit)) {                               // Bid hat Limit von oben nach unten gekreuzt
         entry.lastBid = entry.limit;
         return(true);
      }
      if (lastBid.init) {
         lastBid.init = false;
         firstTick    = true;                                        // firstTick nach erstem tatsächlichen Test gegen entry.lastBid auf TRUE zurückzusetzen
      }
   }

   entry.lastBid = Bid;
   return(false);
}


/**
 * Beginnt eine neue Trade-Sequenz.
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (firstTick) {                                                  // Sicherheitsabfrage, wenn der erste Tick sofort eine Tradeoperation triggert
      if (!IsTesting()) {                                            // jedoch nicht im Tester
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to start a new trade sequence now?", __SCRIPT__ +" - StartSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK)
            return(_false(SetLastError(ERR_CANCELLED_BY_USER), catch("StartSequence(1)")));
      }
   }

   // Status setzen und Gridbasis definieren
   if (sequenceStartTime == 0)
      sequenceStartTime = TimeCurrent();
   sequenceStartPrice   = ifDouble(EQ(entry.limit, 0), NormalizeDouble((Bid + Ask)/2, Digits), entry.limit);
   grid.base            = sequenceStartPrice; SS.Grid.Base();
   status               = STATUS_PROGRESSING;

   // Stop-Orders in den Markt legen
   if (!UpdatePendingOrders())
      return(false);

   RedrawStartStop();
   return(IsNoError(catch("StartSequence(2)")));
}


/**
 * Setzt dem Grid-Level entsprechend fehlende und löscht unnötige PendingOrders.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePendingOrders() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

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

   else /*(grid.level == 0)*/ {                                                  // Nur *hier* kann sich grid.base geändert haben.
      bool buyOrderExists, sellOrderExists;

      // unnötige Pending-Orders löschen
      for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
         if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]==0) {  // if (isPending && !isClosed)
            if (grid.direction!=D_SHORT) /*&&*/ if (orders.level[i]==1) {
               if (NE(orders.pendingPrice[i], grid.base + GridSize*Pips))
                  if (!Grid.ModifyPendingOrder(i))
                     return(false);
               buyOrderExists = true;
               continue;
            }
            if (grid.direction!=D_LONG) /*&&*/ if (orders.level[i]==-1) {
               if (NE(orders.pendingPrice[i], grid.base - GridSize*Pips))
                  if (!Grid.ModifyPendingOrder(i))
                     return(false);
               sellOrderExists = true;
               continue;
            }
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
 * Speichert eine Änderung der Gridbasis.
 *
 * @param  datetime time  - Zeitpunkt der Änderung
 * @param  double   value - neue Gridbasis
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.BaseChange(datetime time, double value) {
   int size = ArraySize(grid.base.time);

   if (size == 0) {
      ArrayPushInt   (grid.base.time,  time );
      ArrayPushDouble(grid.base.value, value);
   }
   else {
      int minutes=time/MINUTE, lastMinutes=grid.base.time[size-1]/MINUTE;
      if (minutes == lastMinutes) {
         grid.base.time [size-1] = time;                             // Änderungen der aktuellen Minute mit neuen Werten überschreiben
         grid.base.value[size-1] = value;
      }
      else {
         ArrayPushInt   (grid.base.time,  time );
         ArrayPushDouble(grid.base.value, value);
      }
   }

   return(IsNoError(catch("Grid.BaseChange()")));
}


/**
 * Legt die angegebene Stop-Order in den Markt und fügt den Grid-Arrays deren Daten hinzu.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.AddOrder(int type, int level) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   // Order in den Markt legen
   int ticket = PendingStopOrder(type, level);
   if (ticket == -1)
      return(false);

   // Daten speichern
   if (!Grid.PushTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.AddOrder()")));
}


/**
 * Justiert den Stop-Preis der angegebenen Order beim Broker und aktualisiert die Datenarrays des Grids.
 *
 * @param  int i - Index der Order in den Datenarrays
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.ModifyPendingOrder(int i) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (i < 0 || ArraySize(orders.ticket) < i+1) return(_false(catch("Grid.ModifyPendingOrder(1)   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (orders.type[i] != OP_UNDEFINED)          return(_false(catch("Grid.ModifyPendingOrder(2)   cannot modify open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
   if (orders.closeTime[i] != 0)                return(_false(catch("Grid.ModifyPendingOrder(3)   cannot modify cancelled order #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   double stopPrice   = grid.base +          orders.level[i]  * GridSize * Pips;
   double stopLoss    = stopPrice - MathSign(orders.level[i]) * GridSize * Pips;
   color  markerColor = ifInt(orders.level[i] > 0, CLR_LONG, CLR_SHORT);

   if (EQ(orders.pendingPrice[i], stopPrice)) /*&&*/ if (EQ(orders.stopLoss[i], stopLoss))
      return(_false(catch("Grid.ModifyPendingOrder(4)   found nothing to modify for order #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));

   if (!OrderModifyEx(orders.ticket[i], stopPrice, stopLoss, NULL, NULL, markerColor))
      return(_false(SetLastError(stdlib_PeekLastError())));

   orders.pendingModifyTime[i] = TimeCurrent();
   orders.pendingPrice     [i] = stopPrice;
   orders.stopLoss         [i] = stopLoss;

   return(IsNoError(catch("Grid.ModifyPendingOrder(5)")));
}


/**
 * Streicht die angegebene Order beim Broker und entfernt sie aus den Datenarrays des Grids.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.DeleteOrder(int ticket) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   if (!OrderDeleteEx(ticket, CLR_NONE))
      return(_false(SetLastError(stdlib_PeekLastError())));

   if (!Grid.DropTicket(ticket))
      return(false);

   return(IsNoError(catch("Grid.DeleteOrder()")));
}


/**
 * Fügt die Daten des angegebenen Tickets den Datenarrays des Grids hinzu.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.PushTicket(int ticket) {
   if (!OrderSelectByTicket(ticket, "Grid.PushTicket(1)"))
      return(false);

   // Arrays vergrößern und Daten speichern
   int size = ArraySize(orders.ticket);
   ResizeArrays(size+1);

   orders.ticket           [size] = OrderTicket();
   orders.level            [size] = ifInt(IsLongTradeOperation(OrderType()), 1, -1) * OrderMagicNumber()>>14 & 0xFF;   // 8 Bits (Bits 15-22) => grid.level

   orders.pendingType      [size] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.pendingTime      [size] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
 //orders.pendingModifyTime[size] = 0;
   orders.pendingPrice     [size] = ifDouble( IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);
 //orders.pendingExecution [size] = 0;

   orders.type             [size] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.openTime         [size] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
   orders.openPrice        [size] = ifDouble(!IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);
   orders.openSlippage     [size] = GetOpenPriceSlippage(size);
 //orders.openExecution    [size] = 0;

   orders.closeTime        [size] = OrderCloseTime();
   orders.closePrice       [size] = OrderClosePrice();
 //orders.closeExecution   [size] = 0;
   orders.stopLoss         [size] = OrderStopLoss();
   orders.stopValue        [size] = ifDouble(!IsPendingTradeOperation(OrderType()), (GridSize + orders.openSlippage[size]) * PipValue(LotSize), 0); // um Slippage justiert
   orders.closedByStop     [size] = IsOrderClosedByStop();
   orders.closeSlippage    [size] = GetClosePriceSlippage(size);         // erst nach stopLoss[i] und closedByStop[i]

   orders.swap             [size] = OrderSwap();
   orders.commission       [size] = OrderCommission();
   orders.profit           [size] = OrderProfit();

   return(IsNoError(catch("Grid.PushTicket(2)")));
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
   int size = ArraySize(orders.ticket);

   if (i < size-1) {                                                 // wenn das zu entfernende Element nicht das Letzte ist
      ArrayCopy(orders.ticket,            orders.ticket,            i, i+1);
      ArrayCopy(orders.level,             orders.level,             i, i+1);
      ArrayCopy(orders.pendingType,       orders.pendingType,       i, i+1);
      ArrayCopy(orders.pendingTime,       orders.pendingTime,       i, i+1);
      ArrayCopy(orders.pendingModifyTime, orders.pendingModifyTime, i, i+1);
      ArrayCopy(orders.pendingPrice,      orders.pendingPrice,      i, i+1);
      ArrayCopy(orders.pendingExecution,  orders.pendingExecution,  i, i+1);
      ArrayCopy(orders.type,              orders.type,              i, i+1);
      ArrayCopy(orders.openTime,          orders.openTime,          i, i+1);
      ArrayCopy(orders.openPrice,         orders.openPrice,         i, i+1);
      ArrayCopy(orders.openSlippage,      orders.openSlippage,      i, i+1);
      ArrayCopy(orders.openExecution,     orders.openExecution,     i, i+1);
      ArrayCopy(orders.closeTime,         orders.closeTime,         i, i+1);
      ArrayCopy(orders.closePrice,        orders.closePrice,        i, i+1);
      ArrayCopy(orders.closeSlippage,     orders.closeSlippage,     i, i+1);
      ArrayCopy(orders.closeExecution,    orders.closeExecution,    i, i+1);
      ArrayCopy(orders.stopLoss,          orders.stopLoss,          i, i+1);
      ArrayCopy(orders.stopValue,         orders.stopValue,         i, i+1);
      ArrayCopy(orders.closedByStop,      orders.closedByStop,      i, i+1);
      ArrayCopy(orders.swap,              orders.swap,              i, i+1);
      ArrayCopy(orders.commission,        orders.commission,        i, i+1);
      ArrayCopy(orders.profit,            orders.profit,            i, i+1);
   }
   ResizeArrays(size-1);

   return(IsNoError(catch("Grid.DropTicket(2)")));
}


/**
 * Ersetzt die Arraydaten des angegebenen Tickets mit den aktuellen Online-Daten.
 *
 * @param  int ticket - Orderticket
 *
 * @return bool - Erfolgsstatus
 */
bool Grid.ReplaceTicket(int ticket) {
   // Position in Datenarrays bestimmen
   int i = SearchIntArray(orders.ticket, ticket);
   if (i == -1)
      return(_false(catch("Grid.ReplaceTicket(1)   #"+ ticket +" not found in grid arrays", ERR_RUNTIME_ERROR)));

   if (!OrderSelectByTicket(ticket, "Grid.ReplaceTicket(2)"))
      return(false);

   orders.ticket       [i] = OrderTicket();
   orders.level        [i] = ifInt(IsLongTradeOperation(OrderType()), 1, -1) * OrderMagicNumber()>>14 & 0xFF;              // 8 Bits (Bits 15-22) => grid.level

   orders.pendingType  [i] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderType(),      orders.pendingType [i]);    // Pending-Orderdaten ggf. bewahren
   orders.pendingTime  [i] = ifInt   ( IsPendingTradeOperation(OrderType()), OrderOpenTime(),  orders.pendingTime [i]);
   orders.pendingPrice [i] = ifDouble( IsPendingTradeOperation(OrderType()), OrderOpenPrice(), orders.pendingPrice[i]);

   orders.type         [i] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderType(), OP_UNDEFINED);
   orders.openTime     [i] = ifInt   (!IsPendingTradeOperation(OrderType()), OrderOpenTime(),        0);
   orders.openPrice    [i] = ifDouble(!IsPendingTradeOperation(OrderType()), OrderOpenPrice(),       0);
   orders.openSlippage [i] = GetOpenPriceSlippage(i);

   orders.closeTime    [i] = OrderCloseTime();
   orders.closePrice   [i] = OrderClosePrice();
   orders.stopLoss     [i] = OrderStopLoss();

   if (IsPendingTradeOperation(OrderType())) orders.stopValue[i] = 0;
   else if (EQ(orders.stopValue[i], 0))      orders.stopValue[i] = (GridSize + orders.openSlippage[i]) * PipValue(LotSize);

   orders.closedByStop [i] = IsOrderClosedByStop();
   orders.closeSlippage[i] = GetClosePriceSlippage(i);               // erst nach stopLoss und closedByStop

   orders.swap         [i] = OrderSwap();
   orders.commission   [i] = OrderCommission();
   orders.profit       [i] = OrderProfit();

   return(IsNoError(catch("Grid.ReplaceTicket(3)")));
}


/**
 * Legt eine Stop-Order in den Markt.
 *
 * @param  int type  - Ordertyp: OP_BUYSTOP | OP_SELLSTOP
 * @param  int level - Gridlevel der Order
 *
 * @return int - Ticket der Order oder -1, falls ein Fehler auftrat
 */
int PendingStopOrder(int type, int level) {
   if (IsLastError() || status==STATUS_DISABLED)
      return(-1);

   if (type == OP_BUYSTOP) {
      if (level <= 0) return(_int(-1, catch("PendingStopOrder(1)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else if (type == OP_SELLSTOP) {
      if (level >= 0) return(_int(-1, catch("PendingStopOrder(2)   illegal parameter level = "+ level +" for "+ OperationTypeDescription(type), ERR_INVALID_FUNCTION_PARAMVALUE)));
   }
   else               return(_int(-1, catch("PendingStopOrder(3)   illegal parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));

   double stopPrice   = grid.base +          level  * GridSize * Pips;
   double stopLoss    = stopPrice - MathSign(level) * GridSize * Pips;
   int    magicNumber = CreateMagicNumber(level);
   string comment     = StringConcatenate("SR.", sequenceId, ".", NumberToStr(level, "+."));
   color  markerColor = ifInt(level > 0, CLR_LONG, CLR_SHORT);
   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               ClosedByFinish
   #define DM_ALL       3     // Pending, Open, ClosedByStop, ClosedByFinish
   */
   if (orderDisplayMode == DM_NONE)
      markerColor = CLR_NONE;

   int ticket = OrderSendEx(Symbol(), type, LotSize, stopPrice, NULL, stopLoss, NULL, comment, magicNumber, NULL, markerColor);
   if (ticket == -1)
      SetLastError(stdlib_PeekLastError());

   if (IsError(catch("PendingStopOrder(4)")))
      return(-1);
   return(ticket);
}


/**
 * Ob der konfigurierte TakeProfit-Level erreicht oder überschritten wurde.
 *
 * @return bool
 */
bool IsProfitTargetReached() {
   return(false);
}


/**
 * Schließt alle PendingOrders und offenen Positionen der Sequenz.
 *
 * @return bool - Erfolgsstatus: ob die Sequenz erfolgreich gestoppt wurde (FALSE, wenn sie bereits gestoppt war)
 */
bool StopSequence() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (status==STATUS_FINISHED)
      return(false);

   if (firstTick) {                                                  // Sicherheitsabfrage, wenn der erste Tick sofort eine Tradeoperation triggert
      if (!IsTesting()) {                                            // jedoch nicht im Tester
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to stop the sequence now?", __SCRIPT__ +" - StopSequence()", MB_ICONQUESTION|MB_OKCANCEL);
         if (button != IDOK)
            return(_false(SetLastError(ERR_CANCELLED_BY_USER), catch("StopSequence(1)")));
      }
   }

   int pendings[], positions[], orders=ArraySize(orders.ticket);
   ArrayResize(pendings,  0);
   ArrayResize(positions, 0);

   for (int i=0; i < orders; i++) {
      if (orders.closeTime[i] == 0) {                                // Ticket prüfen, wenn es beim letzten Aufruf noch offen war
         if (!OrderSelectByTicket(orders.ticket[i], "StopSequence(2)"))
            return(false);
         if (OrderCloseTime() == 0) {                                // Ticket zwischenspeichern, wenn es immer noch offen ist
            if (IsPendingTradeOperation(OrderType())) ArrayPushInt(pendings,  orders.ticket[i]);
            else                                      ArrayPushInt(positions, orders.ticket[i]);
         }
      }
   }


   // Status vorm Schließen evt. offener Positionen setzen
   status           = STATUS_FINISHED;
   sequenceStopTime = TimeCurrent();

   double price = (Bid + Ask)/2;
   if      (LT(grid.base, price)) sequenceStopPrice = Bid;
   else if (GT(grid.base, price)) sequenceStopPrice = Ask;
   else                           sequenceStopPrice = grid.base;
   sequenceStopPrice = NormalizeDouble(sequenceStopPrice, Digits);


   bool ordersChanged;

   // offene Positionen schließen
   if (ArraySize(positions) != 0) {
      if (!OrderMultiClose(positions, NULL, CLR_CLOSE))
         return(_false(SetLastError(stdlib_PeekLastError())));
      ordersChanged = true;
   }

   // Pending-Orders streichen
   for (i=ArraySize(pendings)-1; i >= 0; i--) {
      if (!OrderDeleteEx(pendings[i], CLR_NONE))
         return(_false(SetLastError(stdlib_PeekLastError())));
      if (!Grid.DropTicket(pendings[i]))
         return(false);
      ordersChanged = true;
   }

   // Daten aktualisieren und speichern
   if (ordersChanged) {
      if (!UpdateStatus()) return(false);
      if (!SaveStatus()  ) return(false);
   }

   RedrawStartStop();
   return(IsNoError(catch("StopSequence(3)")));
}


/**
 * Generiert einen Wert für OrderMagicNumber() für den angegebenen Gridlevel.
 *
 * @param  int level - Gridlevel
 *
 * @return int - MagicNumber oder -1, falls ein Fehler auftrat
 */
int CreateMagicNumber(int level) {
   if (sequenceId < 1000) return(_int(-1, catch("CreateMagicNumber(1)   illegal sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));
   if (level == 0)        return(_int(-1, catch("CreateMagicNumber(2)   illegal parameter level = "+ level, ERR_INVALID_FUNCTION_PARAMVALUE)));

   // Für bessere Obfuscation ist die Reihenfolge der Werte [ea,level,sequence] und nicht [ea,sequence,level]. Dies wären aufeinander folgende Werte.
   int ea       = Strategy.Id & 0x3FF << 22;                         // 10 bit (Bits größer 10 löschen und auf 32 Bit erweitern) | in MagicNumber: Bits 23-32
   level        = MathAbs(level) +0.1;                               // (int) double: Wert in MagicNumber ist immer positiv
   level        = level & 0xFF << 14;                                //  8 bit (Bits größer 8 löschen und auf 22 Bit erweitern)  | in MagicNumber: Bits 15-22
   int sequence = sequenceId  & 0x3FFF;                              // 14 bit (Bits größer 14 löschen                           | in MagicNumber: Bits  1-14

   return(ea + level + sequence);
}


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @param  bool init - ob der Aufruf innerhalb der init()-Funktion erfolgt (default: FALSE)
 *
 * @return int - Fehlerstatus
 */
int ShowStatus(bool init=false) {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(last_error);

   int error = last_error;                                           // bei Funktionseintritt bereits existierenden Fehler zwischenspeichern

   static string msg, str.stopValue, str.error;

   if (IsLastError()) {
      status    = STATUS_DISABLED;
      str.error = StringConcatenate("  [", ErrorDescription(last_error), "]");
   }

   switch (status) {
      case STATUS_WAITING:     msg = StringConcatenate(":  ", str.testSequence, "sequence ", sequenceId, " waiting");
                               if (StringLen(StartCondition) > 0)
                                  msg = StringConcatenate(msg, " for crossing of ", str.entry.limit);                                                                    break;
      case STATUS_PROGRESSING: msg = StringConcatenate(":  ", str.testSequence, "sequence ", sequenceId, " progressing at level ", grid.level, "  ", str.grid.maxLevel); break;
      case STATUS_FINISHED:    msg = StringConcatenate(":  ", str.testSequence, "sequence ", sequenceId, " stopped at level ", grid.level, "  ", str.grid.maxLevel);     break;
      case STATUS_DISABLED:    msg = StringConcatenate(":  ", str.testSequence, "sequence ", sequenceId, " disabled", str.error);                                        break;
      default:
         return(catch("ShowStatus(1)   illegal sequence status = "+ status, ERR_RUNTIME_ERROR));
   }

   if (!IsLastError()) {
      str.stopValue = DoubleToStr(GridSize * PipValue(LotSize), 2);
   }

   msg = StringConcatenate(__SCRIPT__, msg,                                                                                                                NL,
                                                                                                                                                           NL,
                           "Grid:            ", GridSize, " pip", str.grid.base, str.grid.direction,                                                       NL,
                           "LotSize:         ", str.LotSize, " lot = ", str.stopValue, "/stop",                                                            NL,
                           "Realized:       ", str.grid.stops, " = ", str.grid.stopsPL,                                                                    NL,
                           "Breakeven:   ", str.grid.breakeven,                                                                                            NL,
                           "Profit/Loss:    ", str.grid.totalPL, "  (", str.grid.maxProfitLoss, "/", str.grid.maxDrawdown, "/", str.grid.valueAtRisk, ")", NL);

   // einige Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, msg));
   if (init)
      WindowRedraw();

   if (!IsError(catch("ShowStatus(2)")))
      last_error = error;                                            // bei Funktionseintritt bereits existierenden Fehler restaurieren
   return(last_error);
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
 * ShowStatus(): Aktualisiert die String-Repräsentation von testSequence.
 */
void SS.TestSequence() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   if (testSequence) str.testSequence = "test ";
   else              str.testSequence = "";
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
 * ShowStatus(): Aktualisiert die String-Repräsentation von entry.limit.
 */
void SS.Entry.Limit() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.entry.limit = NumberToStr(entry.limit, PriceFormat);
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.base.
 */
void SS.Grid.Base() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
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

   str.grid.stops   = StringConcatenate(grid.stops, " stop", ifString(grid.stops==1, "", "s"));
   str.grid.stopsPL = DoubleToStr(grid.stopsPL, 2);
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.totalPL.
 */
void SS.Grid.TotalPL() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.totalPL = NumberToStr(grid.totalPL, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.valueAtRisk.
 */
void SS.Grid.ValueAtRisk() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.valueAtRisk = NumberToStr(-grid.valueAtRisk, "+.2");     // Wert ist positv, Anzeige ist negativ
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.maxProfitLoss.
 */
void SS.Grid.MaxProfitLoss() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxProfitLoss = NumberToStr(grid.maxProfitLoss, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.maxDrawdown.
 */
void SS.Grid.MaxDrawdown() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   str.grid.maxDrawdown = NumberToStr(grid.maxDrawdown, "+.2");
}


/**
 * ShowStatus(): Aktualisiert die String-Repräsentation von grid.breakevenLong und grid.breakevenShort.
 */
void SS.Grid.Breakeven() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   string strLong, strShort;

   if (grid.direction != D_SHORT)
      strLong = ifString(EQ(grid.breakevenLong, 0), "-", DoubleToStr(grid.breakevenLong, PipDigits));

   if (grid.direction != D_LONG)
      strShort = ifString(EQ(grid.breakevenShort, 0), "-", DoubleToStr(grid.breakevenShort, PipDigits));

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

   // wenn floatingPL = -realizedPL, dann totalPL = 0.00     => Breakeven-Punkt auf aktueller Seite
   distance1 = ProfitToDistance(-grid.stopsPL, grid.level);          // ohne finishedPL => ist während Laufzeit 0 und wird ab Stop nicht mehr berücksichtigt

   if (grid.level == 0) {                                            // realizedPL und valueAtRisk sind identisch, Abstand der Breakeven-Punkte ist gleich
      grid.breakevenLong  = grid.base + distance1*Pips;
      grid.breakevenShort = grid.base - distance1*Pips;
   }
   else {
      // wenn floatingPL = valueAtRisk, dann totalPL = 0.00  => Breakeven-Punkt auf gegenüberliegender Seite
      if (grid.direction == D_BIDIR)
         distance2 = ProfitToDistance(grid.valueAtRisk, 0);

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
         string labelL = StringConcatenate("SR.", sequenceId, ".beL ", DoubleToStr(last.grid.breakevenLong, Digits), " -> ", DoubleToStr(grid.breakevenLong, Digits), " (", TimeToStr(last.startTimeLong, TIME_DATE|TIME_MINUTES|TIME_SECONDS), ")");
         if (ObjectCreate(labelL, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenLong, now, grid.breakevenLong)) {
            ObjectSet(labelL, OBJPROP_RAY  , false          );
            ObjectSet(labelL, OBJPROP_COLOR, Color.Breakeven);
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
         string labelS = StringConcatenate("SR.", sequenceId, ".beS ", DoubleToStr(last.grid.breakevenShort, Digits), " -> ", DoubleToStr(grid.breakevenShort, Digits), " (", TimeToStr(last.startTimeShort, TIME_DATE|TIME_MINUTES|TIME_SECONDS), ")");
         if (ObjectCreate(labelS, OBJ_TREND, 0, last.drawingTime, last.grid.breakevenShort, now, grid.breakevenShort)) {
            ObjectSet(labelS, OBJPROP_RAY  , false          );
            ObjectSet(labelS, OBJPROP_COLOR, Color.Breakeven);
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
            ObjectSet(label, OBJPROP_COLOR, Color.Breakeven);
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
 * Ob in den Input-Parametern ausdrücklich eine zu benutzende Sequenz-ID angegeben wurde. Hier wird nur geprüft,
 * ob ein Wert angegeben wurde. Die Gültigkeit einer ID wird erst in RestoreInputSequenceId() überprüft.
 *
 * @return bool
 */
bool IsInputSequenceId() {
   return(StringLen(StringTrim(Sequence.ID)) > 0);
}


/**
 * Validiert und setzt die in der Konfiguration angegebene Sequenz-ID.
 *
 * @return bool - ob eine gültige Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreInputSequenceId() {
   if (IsInputSequenceId()) {
      string strValue = StringToUpper(StringTrim(Sequence.ID));

      if (StringLeft(strValue, 1) == "T") {
         testSequence = true; SS.TestSequence();
         strValue     = StringRight(strValue, -1);
      }
      if (StringIsDigit(strValue)) {
         int iValue = StrToInteger(strValue);
         if (1000 <= iValue) /*&&*/ if (iValue <= 16383) {
            sequenceId  = iValue; SS.SequenceId();
            Sequence.ID = ifString(IsTestSequence(), "T", "") + sequenceId;
            return(true);
         }
      }
      catch("RestoreInputSequenceId()  Invalid input parameter Sequence.ID = \""+ Sequence.ID +"\"", ERR_INVALID_INPUT_PARAMVALUE);
   }
   return(false);
}


/**
 * Speichert den transienten Sequenzstatus im Chart, sodaß er daraus wiederhergestellt werden kann (hauptsächlich für REASON_RECOMPILE).
 * Der transiente Status umfaßt alle die User-Eingaben, die nicht im Statusfile gespeichert werden: die aktuelle Sequenz-ID, Farben,
 * Display-Modes, ERR_CANCELLED_BY_USER etc.
 *
 * @return int - Fehlerstatus
 */
int StoreTransientStatus() {
   string label = StringConcatenate(__SCRIPT__, ".transient.Sequence.ID");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                  // hidden on all timeframes
   ObjectSetText(label, ifString(IsTestSequence(), "T", "") + sequenceId, 1);

   label = StringConcatenate(__SCRIPT__, ".transient.Color.Breakeven");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                  // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", Color.Breakeven), 1);

   label = StringConcatenate(__SCRIPT__, ".transient.OrderDisplayMode");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                  // hidden on all timeframes
   ObjectSetText(label, OrderDisplayMode, 1);

   if (last_error == ERR_CANCELLED_BY_USER) {
      label = StringConcatenate(__SCRIPT__, ".transient.last_error");
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
      ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);               // hidden on all timeframes
      ObjectSetText(label, StringConcatenate("", last_error), 1);
   }

   return(catch("StoreTransientStatus()"));
}


/**
 * Restauriert alle im Chart gespeicherten transienten Sequenzdaten.
 *
 * @return bool - ob eine Sequenz-ID gefunden und restauriert wurde
 */
bool RestoreTransientStatus() {
   string strValue;
   int    iValue;

   string label = StringConcatenate(__SCRIPT__, ".transient.Sequence.ID");
   if (ObjectFind(label) == 0) {
      Sequence.ID = StringTrim(ObjectDescription(label));
      if (!RestoreInputSequenceId())                                 // RestoreInputSequenceId() wiederverwenden
         return(_false(catch("RestoreTransientStatus(1)")));
   }
   else return(_false(catch("RestoreTransientStatus(2)")));

   label = StringConcatenate(__SCRIPT__, ".transient.Color.Breakeven");
   if (ObjectFind(label) == 0) {
      strValue = StringTrim(ObjectDescription(label));
      if (StringIsInteger(strValue)) {
         iValue = StrToInteger(strValue);
         if (CLR_NONE <= iValue && iValue <= C'255,255,255')
            Color.Breakeven = iValue;
      }
   }

   label = StringConcatenate(__SCRIPT__, ".transient.OrderDisplayMode");
   if (ObjectFind(label) == 0) {
      string modes[] = {"None", "Stops", "Pyramid", "All"};
      strValue = StringTrim(ObjectDescription(label));
      if (StringInArray(modes, strValue))
         OrderDisplayMode = strValue;
   }

   label = StringConcatenate(__SCRIPT__, ".transient.last_error");
   if (ObjectFind(label) == 0) {
      strValue = StringTrim(ObjectDescription(label));
      if (StringIsDigit(strValue)) {
         iValue = StrToInteger(strValue);
         if (IsErrorCode(iValue)) /*&&*/ if (IsError(iValue))
            last_error = iValue;
      }
   }
   return(IsNoError(catch("RestoreTransientStatus(3)")));
}


/**
 * Löscht alle im Chart gespeicherten transienten Sequenzdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearTransientStatus() {
   string label, prefix=StringConcatenate(__SCRIPT__, ".transient.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearTransientStatus()"));
}


/**
 * Restauriert die Sequenz-ID einer laufenden Sequenz.
 *
 * @return bool - ob eine laufende Sequenz gefunden und die ID restauriert wurde
 */
bool RestoreRunningSequenceId() {
   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: während des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;

      if (IsMyOrder()) {
         sequenceId = OrderMagicNumber() & 0x3FFF; SS.SequenceId();  // 14 Bits (Bits 1-14) => sequenceId
         return(_true(catch("RestoreRunningSequenceId(1)")));
      }
   }
   return(_false(catch("RestoreRunningSequenceId(2)")));
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
      if (OrderMagicNumber() >> 22 == Strategy.Id) {
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
 * Validiert die aktuelle Konfiguration.
 *
 * @param int reason - bei REASON_PARAMETERS darf eine laufende Sequenz nicht mit den angegebenen Parametern kollidieren
 *                     (die vorherigen Parameter liegen zu Vergleichszwecken in last.*)
 *
 * @return bool - ob die Konfiguration gültig ist
 */
bool ValidateConfiguration(int reason=NULL) {
   // GridDirection
   string directions[] = {"Bidirectional", "Long", "Short", "L+S"};
   string strValue     = StringToLower(StringTrim(StringReplace(StringReplace(StringReplace(GridDirection, "+", ""), "&", ""), " ", "")) +"b");
   switch (StringGetChar(strValue, 0)) {
      case 'l': if (StringStartsWith(strValue, "longshort") || StringStartsWith(strValue, "ls")) {
                   //grid.direction = D_LONG_SHORT; break;
                }
                grid.direction    = D_LONG;       break;
      case 's': grid.direction    = D_SHORT;      break;
      case 'b': grid.direction    = D_BIDIR;      break;                // default für leeren Input-Parameter

      default:                              return(_false(catch("ValidateConfiguration(1)  Invalid input parameter GridDirection = \""+ GridDirection +"\"", ERR_INVALID_INPUT_PARAMVALUE)));
   }
   if (reason==REASON_PARAMETERS) /*&&*/ if (directions[grid.direction]!=last.GridDirection)
      if (status != STATUS_WAITING)         return(_false(catch("ValidateConfiguration(2)  Cannot change parameter GridDirection of running sequence", ERR_ILLEGAL_INPUT_PARAMVALUE)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   GridDirection = directions[grid.direction]; SS.Grid.Direction();

   // GridSize
   if (reason==REASON_PARAMETERS) /*&&*/ if (GridSize!=last.GridSize)
      if (status != STATUS_WAITING)         return(_false(catch("ValidateConfiguration(3)  Cannot change parameter GridSize of running sequence", ERR_ILLEGAL_INPUT_PARAMVALUE)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   if (GridSize < 1)                        return(_false(catch("ValidateConfiguration(4)  Invalid input parameter GridSize = "+ GridSize, ERR_INVALID_INPUT_PARAMVALUE)));

   // LotSize
   if (reason==REASON_PARAMETERS) /*&&*/ if (NE(LotSize, last.LotSize))
      if (status != STATUS_WAITING)         return(_false(catch("ValidateConfiguration(5)  Cannot change parameter LotSize of running sequence", ERR_ILLEGAL_INPUT_PARAMVALUE)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   if (LE(LotSize, 0))                      return(_false(catch("ValidateConfiguration(6)  Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+"), ERR_INVALID_INPUT_PARAMVALUE)));
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT );
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT );
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                      return(_false(catch("ValidateConfiguration(7)   symbol=\""+ Symbol() +"\"", error)));
   if (LT(LotSize, minLot))                 return(_false(catch("ValidateConfiguration(8)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MinLot="+  NumberToStr(minLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE)));
   if (GT(LotSize, maxLot))                 return(_false(catch("ValidateConfiguration(9)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (MaxLot="+  NumberToStr(maxLot, ".+" ) +")", ERR_INVALID_INPUT_PARAMVALUE)));
   if (NE(MathModFix(LotSize, lotStep), 0)) return(_false(catch("ValidateConfiguration(10)   Invalid input parameter LotSize = "+ NumberToStr(LotSize, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", ERR_INVALID_INPUT_PARAMVALUE)));
   SS.LotSize();

   // StartCondition
   StartCondition = StringReplace(StartCondition, " ", "");
   if (reason==REASON_PARAMETERS) /*&&*/ if (StartCondition!=last.StartCondition)
      if (status != STATUS_WAITING)         return(_false(catch("ValidateConfiguration(11)  Cannot change parameter StartCondition of running sequence", ERR_ILLEGAL_INPUT_PARAMVALUE)));
      // TODO: Modify ist erlaubt, solange nicht die erste Position eröffnet wurde
   if (StringLen(StartCondition) == 0) {
      entry.limit = 0;
   }
   else if (StringIsNumeric(StartCondition)) {
      entry.limit = StrToDouble(StartCondition); SS.Entry.Limit();
      if (LT(entry.limit, 0))               return(_false(catch("ValidateConfiguration(12)  Invalid input parameter StartCondition = \""+ StartCondition +"\"", ERR_INVALID_INPUT_PARAMVALUE)));
      if (EQ(entry.limit, 0))
         StartCondition = "";
   }
   else                                     return(_false(catch("ValidateConfiguration(13)  Invalid input parameter StartCondition = \""+ StartCondition +"\"", ERR_INVALID_INPUT_PARAMVALUE)));

   // OrderDisplayMode
   string modes[] = {"None", "Stops", "Pyramid", "All"};
   switch (StringGetChar(StringToUpper(StringTrim(OrderDisplayMode) +"P"), 0)) {
      case 'N': orderDisplayMode = DM_NONE;    break;
      case 'S': orderDisplayMode = DM_STOPS;   break;
      case 'P': orderDisplayMode = DM_PYRAMID; break;                   // default für leeren Input-Parameter
      case 'A': orderDisplayMode = DM_ALL;     break;
      default:                              return(_false(catch("ValidateConfiguration(14)  Invalid input parameter OrderDisplayMode = \""+ OrderDisplayMode +"\"", ERR_INVALID_INPUT_PARAMVALUE)));
   }
   OrderDisplayMode = modes[orderDisplayMode];

   // Color.Breakeven
   if (Color.Breakeven == 0xFF000000)                                   // kann vom Terminal falsch gesetzt worden sein
      Color.Breakeven = CLR_NONE;
   if (Color.Breakeven < CLR_NONE || Color.Breakeven > C'255,255,255')  // kann über transienten Chartstatus falsch reinkommen
                                            return(_false(catch("ValidateConfiguration(15)  Invalid input parameter Color.Breakeven = 0x"+ IntToHexStr(Color.Breakeven), ERR_INVALID_INPUT_PARAMVALUE)));

   // Sequence.ID: falls gesetzt, wurde sie schon in RestoreInputSequenceId() validiert
   if (reason == REASON_PARAMETERS)
      if (Sequence.ID != last.Sequence.ID)  return(_false(catch("ValidateConfiguration(16)  Cannot change parameter Sequence.ID", ERR_ILLEGAL_INPUT_PARAMVALUE)));


   // TODO: Parameter mit externer Konfiguration werden geändert, ohne vorher die Konfigurationsdatei zu laden.

   return(IsNoError(catch("ValidateConfiguration(17)")));
}


/**
 * Speichert den aktuellen Status der Instanz, um später die nahtlose Re-Initialisierung im selben oder einem anderen Terminal
 * zu ermöglichen.
 *
 * @return bool - Erfolgsstatus
 */
bool SaveStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (IsTestSequence()) /*&&*/ if (!IsTesting())
      return(false);
   if (sequenceId == 0)
      return(_false(catch("SaveStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));


   // Spätestens beim ersten SaveStatus() wird sequenceStartTime gesetzt.
   if (sequenceStartTime == 0)
      sequenceStartTime = TimeCurrent();


   /*
   Der komplette Laufzeitstatus wird abgespeichert, nicht nur die Input-Parameter.
   -------------------------------------------------------------------------------
   Speichernotwendigkeit der einzelnen Variablen:

   int      status;                          // nein: kann aus Orderdaten und offenen Positionen restauriert werden
   bool     testSequence;                    // nein: wird aus Statusdatei ermittelt

   datetime sequenceStartTime;               // ja
   double   sequenceStartPrice;              // ja
   datetime sequenceStopTime;                // ja
   double   sequenceStopPrice;               // ja

   double   entry.limit;                     // nein: wird aus StartCondition abgeleitet
   double   entry.lastBid;                   // nein: unnötig

   double   grid.base;                       // ja
   int      grid.level;                      // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelLong;               // nein: kann aus Orderdaten restauriert werden
   int      grid.maxLevelShort;              // nein: kann aus Orderdaten restauriert werden

   int      grid.stops;                      // nein: kann aus Orderdaten restauriert werden
   double   grid.stopsPL;                    // nein: kann aus Orderdaten restauriert werden
   double   grid.finishedPL;                 // nein: kann aus Orderdaten restauriert werden
   double   grid.floatingPL;                 // nein: kann aus offenen Positionen restauriert werden
   double   grid.totalPL;                    // nein: kann aus stopsPL, finishedPL und floatingPL restauriert werden
   double   grid.openStopValue;              // nein: kann aus Orderdaten restauriert werden
   double   grid.valueAtRisk;                // nein: kann aus Orderdaten restauriert werden

   double   grid.maxProfitLoss;              // ja
   datetime grid.maxProfitLossTime;          // ja
   double   grid.maxDrawdown;                // ja
   datetime grid.maxDrawdownTime;            // ja
   double   grid.breakevenLong;              // nein: wird mit dem aktuellen TickValue als Näherung neuberechnet
   double   grid.breakevenShort;             // nein: wird mit dem aktuellen TickValue als Näherung neuberechnet

   int      orders.ticket           [];      // ja
   int      orders.level            [];      // ja
   int      orders.pendingType      [];      // ja
   datetime orders.pendingTime      [];      // ja
   datetime orders.pendingModifyTime[];      // ja
   double   orders.pendingPrice     [];      // ja
   double   orders.pendingExecution [];      // ja
   int      orders.type             [];      // ja
   datetime orders.openTime         [];      // ja
   double   orders.openPrice        [];      // ja
   double   orders.openSlippage     [];      // ja
   double   orders.openExecution    [];      // ja
   datetime orders.closeTime        [];      // ja
   double   orders.closePrice       [];      // ja
   double   orders.closeSlippage    [];      // ja
   double   orders.closeExecution   [];      // ja
   double   orders.stopLoss         [];      // ja
   double   orders.stopValue        [];      // ja
   bool     orders.closedByStop     [];      // ja
   double   orders.swap             [];      // ja
   double   orders.commission       [];      // ja
   double   orders.profit           [];      // ja
   */

   // (1.1) Input-Parameter zusammenstellen
   string lines[];  ArrayResize(lines, 0);
   ArrayPushString(lines, /*string*/ "Account="       + ShortAccountCompany() +":"+ GetAccountNumber()      );
   ArrayPushString(lines, /*string*/ "Symbol="        +                                       Symbol()      );
   ArrayPushString(lines, /*string*/ "Sequence.ID="   + ifString(IsTestSequence(), "T", "") + sequenceId    );
   ArrayPushString(lines, /*string*/ "GridDirection=" +                                       GridDirection );
   ArrayPushString(lines, /*int   */ "GridSize="      +                                       GridSize      );
   ArrayPushString(lines, /*double*/ "LotSize="       +                           NumberToStr(LotSize, ".+"));
   ArrayPushString(lines, /*string*/ "StartCondition="+                                       StartCondition);

   // (1.2) Laufzeit-Variablen zusammenstellen
   int size = ArraySize(orders.ticket);
   if (size > 0) {
      ArrayPushString(lines, /*datetime*/ "rt.sequenceStartTime="     +             sequenceStartTime        );
      ArrayPushString(lines, /*double*/   "rt.sequenceStartPrice="    + NumberToStr(sequenceStartPrice, ".+"));
      ArrayPushString(lines, /*datetime*/ "rt.sequenceStopTime="      +             sequenceStopTime         );
      ArrayPushString(lines, /*double*/   "rt.sequenceStopPrice="     + NumberToStr(sequenceStopPrice, ".+") );
      ArrayPushString(lines, /*double*/   "rt.grid.base="             + NumberToStr(grid.base, ".+")         );
      ArrayPushString(lines, /*double*/   "rt.grid.maxProfitLoss="    + NumberToStr(grid.maxProfitLoss, ".+"));
      ArrayPushString(lines, /*datetime*/ "rt.grid.maxProfitLossTime="+             grid.maxProfitLossTime   );
      ArrayPushString(lines, /*double*/   "rt.grid.maxDrawdown="      + NumberToStr(grid.maxDrawdown, ".+")  );
      ArrayPushString(lines, /*datetime*/ "rt.grid.maxDrawdownTime="  +             grid.maxDrawdownTime     );
   }
   for (int i=0; i < size; i++) {
      int      ticket            = orders.ticket           [i];
      int      level             = orders.level            [i];
      int      pendingType       = orders.pendingType      [i];
      datetime pendingTime       = orders.pendingTime      [i];
      datetime pendingModifyTime = orders.pendingModifyTime[i];
      double   pendingPrice      = orders.pendingPrice     [i];
      double   pendingExecution  = orders.pendingExecution [i];
      int      type              = orders.type             [i];
      datetime openTime          = orders.openTime         [i];
      double   openPrice         = orders.openPrice        [i];
      double   openSlippage      = orders.openSlippage     [i];
      double   openExecution     = orders.openExecution    [i];
      datetime closeTime         = orders.closeTime        [i];
      double   closePrice        = orders.closePrice       [i];
      double   closeSlippage     = orders.closeSlippage    [i];
      double   closeExecution    = orders.closeExecution   [i];
      double   stopLoss          = orders.stopLoss         [i];
      double   stopValue         = orders.stopValue        [i];
      bool     closedByStop      = orders.closedByStop     [i];
      double   swap              = orders.swap             [i];
      double   commission        = orders.commission       [i];
      double   profit            = orders.profit           [i];
      ArrayPushString(lines, StringConcatenate("rt.order.", i, "=", ticket, ",", level, ",", pendingType, ",", pendingTime, ",", pendingModifyTime, ",", NumberToStr(NormalizeDouble(pendingPrice, Digits), ".+"), ",", NumberToStr(NormalizeDouble(pendingExecution, 1), ".+"), ",", type, ",", openTime, ",", NumberToStr(NormalizeDouble(openPrice, Digits), ".+"), ",", NumberToStr(openSlippage, ".+"), ",", NumberToStr(NormalizeDouble(openExecution, 1), ".+"), ",", closeTime, ",", NumberToStr(NormalizeDouble(closePrice, Digits), ".+"), ",", NumberToStr(closeSlippage, ".+"), ",", NumberToStr(NormalizeDouble(closeExecution, 1), ".+"), ",", NumberToStr(NormalizeDouble(stopLoss, Digits), ".+"), ",", NumberToStr(NormalizeDouble(stopValue, 2), ".+"), ",", closedByStop, ",", NumberToStr(swap, ".+"), ",", NumberToStr(commission, ".+"), ",", NumberToStr(profit, ".+")));
   }


   // (2) Daten in lokaler Datei speichern/überschreiben
   string filename;
   if (!IsTestSequence() || IsTesting()) filename = "presets\\SR."+         sequenceId +".set"; // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch
   else                                  filename = "presets\\tester\\SR."+ sequenceId +".set"; //  ist das Presets-Verzeichnis für die MQL-Dateifunktionen erreichbar.

   int hFile = FileOpen(filename, FILE_CSV|FILE_WRITE);
   if (hFile < 0)
      return(_false(catch("SaveStatus(2)->FileOpen(\""+ filename +"\")")));

   for (i=0; i < ArraySize(lines); i++) {
      if (FileWrite(hFile, lines[i]) < 0) {
         catch("SaveStatus(3)->FileWrite(line #"+ (i+1) +")");
         FileClose(hFile);
         return(false);
      }
   }
   FileClose(hFile);


   // (3) Datei auf Server laden
   int error = UploadStatus(ShortAccountCompany(), AccountNumber(), StdSymbol(), filename);
   if (IsError(error))
      return(false);

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
   if (IsLastError() || status==STATUS_DISABLED)
      return(last_error);
   if (IsTestSequence())                                             // skipping for Tests
      return(NO_ERROR);

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

   return(catch("UploadStatus(3)"));
}


/**
 * Liest den Status einer Sequenz ein und restauriert die internen Variablen. Bei fehlender lokaler Statusdatei wird versucht,
 * die Datei vom Server zu laden.
 *
 * @return bool - ob der Status erfolgreich restauriert wurde
 */
bool RestoreStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   if (sequenceId == 0)
      return(_false(catch("RestoreStatus(1)   illegal value of sequenceId = "+ sequenceId, ERR_RUNTIME_ERROR)));

   // (1) bei nicht existierender lokaler Konfiguration die Datei vom Server laden
   string filesDir = TerminalPath() + "\\experts\\files\\";                                              // "experts\files\presets" ist ein Softlink auf "experts\presets", dadurch
   string fileName = "presets\\"+ ifString(IsTestSequence(), "tester\\", "") +"SR."+ sequenceId +".set"; // ist das Presets-Verzeichnis für die MQL-Dateifunktionen erreichbar.

   if (!IsFile(filesDir + fileName)) {
      if (IsTestSequence())
         return(_false(catch("RestoreStatus(2)   status file \""+ filesDir + fileName +"\" for test sequence T"+ sequenceId +" not found", ERR_FILE_NOT_FOUND)));

      // TODO: Existenz von wget.exe prüfen

      // Befehlszeile für Shellaufruf zusammensetzen
      string url        = "http://sub.domain.tld/downloadSRStatus.php?company="+ UrlEncode(ShortAccountCompany()) +"&account="+ AccountNumber() +"&symbol="+ UrlEncode(StdSymbol()) +"&sequence="+ sequenceId;
      string targetFile = filesDir +"\\"+ fileName;
      string logFile    = filesDir +"\\"+ fileName +".log";
      string cmd        = "wget.exe \""+ url +"\" -O \""+ targetFile +"\" -o \""+ logFile +"\"";

      debug("RestoreStatus()   downloading status file for sequence "+ ifString(IsTestSequence(), "T", "") + sequenceId);

      int error = WinExecAndWait(cmd, SW_HIDE);                      // SW_SHOWNORMAL|SW_HIDE
      if (IsError(error))
         return(_false(SetLastError(error)));

      debug("RestoreStatus()   status file for sequence "+ ifString(IsTestSequence(), "T", "") + sequenceId +" successfully downloaded");
      FileDelete(fileName +".log");
   }

   // (2) Datei einlesen
   string lines[];
   int size = FileReadLines(fileName, lines, true);
   if (size < 0)
      return(_false(SetLastError(stdlib_PeekLastError())));
   if (size == 0) {
      FileDelete(fileName);
      return(_false(catch("RestoreStatus(3)   status for sequence "+ ifString(IsTestSequence(), "T", "") + sequenceId +" not found", ERR_RUNTIME_ERROR)));
   }

   // (3) Zeilen in Schlüssel-Wert-Paare aufbrechen, Datentypen validieren und Daten übernehmen
   string keys[] = { "Account", "Symbol", "Sequence.ID", "GridDirection", "GridSize", "LotSize", "StartCondition", "rt.sequenceStartTime", "rt.sequenceStartPrice", "rt.sequenceStopTime", "rt.sequenceStopPrice", "rt.grid.base", "rt.grid.maxProfitLoss", "rt.grid.maxProfitLossTime", "rt.grid.maxDrawdown", "rt.grid.maxDrawdownTime" };
   /*                "Account"                  ,
                     "Symbol"                   ,                    // Der Compiler kommt mit den Zeilennummern durcheinander,
                     "Sequence.ID"              ,                    // wenn der Initializer nicht komplett in einer Zeile steht.
                     "GridDirection"            ,
                     "GridSize"                 ,
                     "LotSize"                  ,
                     "StartCondition"           ,
                     "rt.sequenceStartTime"     ,
                     "rt.sequenceStartPrice"    ,
                     "rt.sequenceStopTime"      ,
                     "rt.sequenceStopPrice"     ,
                     "rt.grid.base"             ,
                     "rt.grid.maxProfitLoss"    ,
                     "rt.grid.maxProfitLossTime",
                     "rt.grid.maxDrawdown"      ,
                     "rt.grid.maxDrawdownTime"  ,
   */
   string parts[];
   for (int i=0; i < size; i++) {
      if (Explode(lines[i], "=", parts, 2) < 2)          return(_false(catch("RestoreStatus(4)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
      string key=StringTrim(parts[0]), value=StringTrim(parts[1]);

      if (key == "Account") {
         string account = ShortAccountCompany() +":"+ GetAccountNumber();
         if (value != account)                           return(_false(catch("RestoreStatus(5)   account mis-match \""+ value +"\"/\""+ account +"\" in status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         ArrayDropString(keys, key);
      }
      else if (key == "Symbol") {
         if (value != Symbol())                          return(_false(catch("RestoreStatus(6)   symbol mis-match \""+ value +"\"/\""+ Symbol() +"\" in status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         ArrayDropString(keys, key);
      }
      else if (key == "Sequence.ID") {
         value = StringToUpper(value);
         if (StringLeft(value, 1) == "T") {
            testSequence = true; SS.TestSequence();
            value = StringRight(value, -1);
         }
         if (value != StringConcatenate("", sequenceId)) return(_false(catch("RestoreStatus(7)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         Sequence.ID = ifString(IsTestSequence(), "T", "") + sequenceId;
         ArrayDropString(keys, key);
      }
      else if (key == "GridDirection") {
         if (value == "")                                return(_false(catch("RestoreStatus(8)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         GridDirection = value;
         ArrayDropString(keys, key);
      }
      else if (key == "GridSize") {
         if (!StringIsDigit(value))                      return(_false(catch("RestoreStatus(9)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         GridSize = StrToInteger(value);
         ArrayDropString(keys, key);
      }
      else if (key == "LotSize") {
         if (!StringIsNumeric(value))                    return(_false(catch("RestoreStatus(10)   invalid status file \""+ fileName +"\" (line \""+ lines[i] +"\")", ERR_RUNTIME_ERROR)));
         LotSize = StrToDouble(value);
         ArrayDropString(keys, key);
      }
      else if (key == "StartCondition") {
         StartCondition = value;
         ArrayDropString(keys, key);
      }
      else if (StringStartsWith(key, "rt.")) {                       // Laufzeitvariable
         if (!RestoreStatus.Runtime(fileName, lines[i], key, value, keys))
            return(false);
      }
   }
   if (ArraySize(keys) > 0)                              return(_false(catch("RestoreStatus(11)   entries \""+ JoinStrings(keys, "\", \"") +"\" missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));
   if (IntInArray(orders.ticket, 0))                     return(_false(catch("RestoreStatus(12)   one or more order entries missing in file \""+ fileName +"\"", ERR_RUNTIME_ERROR)));

   return(IsNoError(catch("RestoreStatus(13)")));
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
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);
   /*
   datetime rt.sequenceStartTime=1328701713
   double   rt.sequenceStartPrice=1.32677
   datetime rt.sequenceStopTime=1328701999
   double   rt.sequenceStopPrice=1.32734
   double   rt.grid.base=1.32677
   double   rt.grid.maxProfitLoss=200.13
   datetime rt.grid.maxProfitLossTime=1328701713
   double   rt.grid.maxDrawdown=-127.80
   datetime rt.grid.maxDrawdownTime=1328691713
   string   rt.order.0=62544847,1,4,1330932525,1330932525,1.32067,0,0,1330936196,1.32067,0,0,1330938698,1.31897,0,0,1.31897,17,1,0,0,-17
      int      ticket            = values[ 0];
      int      level             = values[ 1];
      int      pendingType       = values[ 2];
      datetime pendingTime       = values[ 3];
      datetime pendingModifyTime = values[ 4];
      double   pendingPrice      = values[ 5];
      double   pendingExecution  = values[ 6];
      int      type              = values[ 7];
      datetime openTime          = values[ 8];
      double   openPrice         = values[ 9];
      double   openSlippage      = values[10];
      double   openExecution     = values[11];
      datetime closeTime         = values[12];
      double   closePrice        = values[13];
      double   closeSlippage     = values[14];
      double   closeExecution    = values[15];
      double   stopLoss          = values[16];
      double   stopValue         = values[17];
      bool     closedByStop      = values[18];
      double   swap              = values[19];
      double   commission        = values[20];
      double   profit            = values[21];
   */
   if (key == "rt.sequenceStartTime") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(1)   illegal sequenceStartTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStartTime = StrToInteger(value);
      if (sequenceStartTime == 0)                                           return(_false(catch("RestoreStatus.Runtime(2)   illegal sequence start time "+ sequenceStartTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStartPrice") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(3)   illegal sequenceStartPrice \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStartPrice = StrToDouble(value);
      if (LE(sequenceStartPrice, 0))                                        return(_false(catch("RestoreStatus.Runtime(4)   illegal sequenceStartPrice "+ NumberToStr(sequenceStartPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStopTime") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(5)   illegal sequenceStopTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStopTime = StrToInteger(value);
      if (sequenceStopTime!=0 && sequenceStartTime >= sequenceStopTime)     return(_false(catch("RestoreStatus.Runtime(6)   sequenceStartTime/sequenceStopTime mis-match '"+ TimeToStr(sequenceStartTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'/'"+ TimeToStr(sequenceStopTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.sequenceStopPrice") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(7)   illegal sequenceStopPrice \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      sequenceStopPrice = StrToDouble(value);
      if (LT(sequenceStopPrice, 0))                                         return(_false(catch("RestoreStatus.Runtime(8)   illegal sequenceStopPrice "+ NumberToStr(sequenceStopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (sequenceStopTime==0 && NE(sequenceStopPrice, 0))                  return(_false(catch("RestoreStatus.Runtime(9)   sequenceStopTime/sequenceStopPrice mis-match "+ sequenceStopTime +"/"+ NumberToStr(sequenceStopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (sequenceStopTime!=0 && EQ(sequenceStopPrice, 0))                  return(_false(catch("RestoreStatus.Runtime(10)   sequenceStopTime/sequenceStopPrice mis-match '"+ TimeToStr(sequenceStopTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'/"+ NumberToStr(sequenceStopPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.base") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(11)   illegal grid.base \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.base = StrToDouble(value); SS.Grid.Base();
      if (LE(grid.base, 0))                                                 return(_false(catch("RestoreStatus.Runtime(12)   illegal grid.base "+ NumberToStr(grid.base, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxProfitLoss") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(13)   illegal grid.maxProfitLoss \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitLoss = StrToDouble(value); SS.Grid.MaxProfitLoss();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxProfitLossTime") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(14)   illegal grid.maxProfitLossTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxProfitLossTime = StrToInteger(value);
      if (grid.maxProfitLossTime==0 && NE(grid.maxProfitLoss, 0))           return(_false(catch("RestoreStatus.Runtime(15)   grid.maxProfitLoss/grid.maxProfitLossTime mis-match "+ NumberToStr(grid.maxProfitLoss, ".2") +"/'"+ TimeToStr(grid.maxProfitLossTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdown") {
      if (!StringIsNumeric(value))                                          return(_false(catch("RestoreStatus.Runtime(16)   illegal grid.maxDrawdown \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdown = StrToDouble(value); SS.Grid.MaxDrawdown();
      ArrayDropString(keys, key);
   }
   else if (key == "rt.grid.maxDrawdownTime") {
      if (!StringIsDigit(value))                                            return(_false(catch("RestoreStatus.Runtime(17)   illegal grid.maxDrawdownTime \""+ value +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      grid.maxDrawdownTime = StrToInteger(value);
      if (grid.maxDrawdownTime==0 && NE(grid.maxDrawdown, 0))               return(_false(catch("RestoreStatus.Runtime(18)   grid.maxDrawdown/grid.maxDrawdownTime mis-match "+ NumberToStr(grid.maxDrawdown, ".2") +"/'"+ TimeToStr(grid.maxDrawdownTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      ArrayDropString(keys, key);
   }
   else if (StringStartsWith(key, "rt.order.")) {
      // Orderindex
      string strIndex = StringRight(key, -9);
      if (!StringIsDigit(strIndex))                                         return(_false(catch("RestoreStatus.Runtime(19)   illegal order index \""+ key +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int i = StrToInteger(strIndex);
      if (ArraySize(orders.ticket) > i) /*&&*/ if (orders.ticket[i]!=0)     return(_false(catch("RestoreStatus.Runtime(20)   duplicate order index "+ key +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // Orderdaten
      string values[];
      if (Explode(value, ",", values, NULL) != 22)                          return(_false(catch("RestoreStatus.Runtime(21)   illegal number of order details ("+ ArraySize(values) +") in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // ticket
      string strTicket = StringTrim(values[0]);
      if (!StringIsDigit(strTicket))                                        return(_false(catch("RestoreStatus.Runtime(22)   illegal order ticket \""+ strTicket +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int ticket = StrToInteger(strTicket);
      if (ticket == 0)                                                      return(_false(catch("RestoreStatus.Runtime(23)   illegal order ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (IntInArray(orders.ticket, ticket))                                return(_false(catch("RestoreStatus.Runtime(24)   duplicate order ticket #"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // level
      string strLevel = StringTrim(values[1]);
      if (!StringIsInteger(strLevel))                                       return(_false(catch("RestoreStatus.Runtime(25)   illegal order level \""+ strLevel +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int level = StrToInteger(strLevel);
      if (level == 0)                                                       return(_false(catch("RestoreStatus.Runtime(26)   illegal order level "+ level +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingType
      string strPendingType = StringTrim(values[2]);
      if (!StringIsInteger(strPendingType))                                 return(_false(catch("RestoreStatus.Runtime(27)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int pendingType = StrToInteger(strPendingType);
      if (pendingType!=OP_UNDEFINED && !IsTradeOperation(pendingType))      return(_false(catch("RestoreStatus.Runtime(28)   illegal pending order type \""+ strPendingType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingTime
      string strPendingTime = StringTrim(values[3]);
      if (!StringIsDigit(strPendingTime))                                   return(_false(catch("RestoreStatus.Runtime(29)   illegal pending order time \""+ strPendingTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingTime = StrToInteger(strPendingTime);
      if (pendingType==OP_UNDEFINED && pendingTime!=0)                      return(_false(catch("RestoreStatus.Runtime(30)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/'"+ TimeToStr(pendingTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && pendingTime==0)                      return(_false(catch("RestoreStatus.Runtime(31)   pending order type/time mis-match "+ OperationTypeToStr(pendingType) +"/"+ pendingTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingModifyTime
      string strPendingModifyTime = StringTrim(values[4]);
      if (!StringIsDigit(strPendingModifyTime))                             return(_false(catch("RestoreStatus.Runtime(29)   illegal pending order modification time \""+ strPendingModifyTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime pendingModifyTime = StrToInteger(strPendingModifyTime);
      if (pendingType==OP_UNDEFINED && pendingModifyTime!=0)                return(_false(catch("RestoreStatus.Runtime(30)   pending order type/modification time mis-match "+ OperationTypeToStr(pendingType) +"/'"+ TimeToStr(pendingModifyTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingPrice
      string strPendingPrice = StringTrim(values[5]);
      if (!StringIsNumeric(strPendingPrice))                                return(_false(catch("RestoreStatus.Runtime(32)   illegal pending order price \""+ strPendingPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double pendingPrice = StrToDouble(strPendingPrice);
      if (LT(pendingPrice, 0))                                              return(_false(catch("RestoreStatus.Runtime(33)   illegal pending order price "+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType==OP_UNDEFINED && NE(pendingPrice, 0))                 return(_false(catch("RestoreStatus.Runtime(34)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType!=OP_UNDEFINED && EQ(pendingPrice, 0))                 return(_false(catch("RestoreStatus.Runtime(35)   pending order type/price mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(pendingPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // pendingExecution
      string strPendingExecution = StringTrim(values[6]);
      if (!StringIsNumeric(strPendingExecution))                            return(_false(catch("RestoreStatus.Runtime(36)   illegal pending order execution \""+ strPendingExecution +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double pendingExecution = StrToDouble(strPendingExecution);
      if (LT(pendingExecution, 0))                                          return(_false(catch("RestoreStatus.Runtime(37)   illegal pending order execution "+ NumberToStr(pendingExecution, ".+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // type
      string strType = StringTrim(values[7]);
      if (!StringIsInteger(strType))                                        return(_false(catch("RestoreStatus.Runtime(38)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      int type = StrToInteger(strType);
      if (type!=OP_UNDEFINED && !IsTradeOperation(type))                    return(_false(catch("RestoreStatus.Runtime(39)   illegal order type \""+ strType +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (pendingType == OP_UNDEFINED) {
         if (type==OP_UNDEFINED)                                            return(_false(catch("RestoreStatus.Runtime(40)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }
      else if (type != OP_UNDEFINED) {
         if (IsLongTradeOperation(pendingType)!=IsLongTradeOperation(type)) return(_false(catch("RestoreStatus.Runtime(41)   pending order type/open order type mis-match "+ OperationTypeToStr(pendingType) +"/"+ OperationTypeToStr(type) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // openTime
      string strOpenTime = StringTrim(values[8]);
      if (!StringIsDigit(strOpenTime))                                      return(_false(catch("RestoreStatus.Runtime(42)   illegal order open time \""+ strOpenTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime openTime = StrToInteger(strOpenTime);
      if (type==OP_UNDEFINED && openTime!=0)                                return(_false(catch("RestoreStatus.Runtime(43)   order type/time mis-match "+ OperationTypeToStr(type) +"/'"+ TimeToStr(openTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && openTime==0)                                return(_false(catch("RestoreStatus.Runtime(44)   order type/time mis-match "+ OperationTypeToStr(type) +"/"+ openTime +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openPrice
      string strOpenPrice = StringTrim(values[9]);
      if (!StringIsNumeric(strOpenPrice))                                   return(_false(catch("RestoreStatus.Runtime(45)   illegal order open price \""+ strOpenPrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openPrice = StrToDouble(strOpenPrice);
      if (LT(openPrice, 0))                                                 return(_false(catch("RestoreStatus.Runtime(46)   illegal order open price "+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(47)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(openPrice, 0))                           return(_false(catch("RestoreStatus.Runtime(48)   order type/price mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(openPrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openSlippage
      string strOpenSlippage = StringTrim(values[10]);
      if (!StringIsNumeric(strOpenSlippage))                                return(_false(catch("RestoreStatus.Runtime(49)   illegal order open slippage \""+ strOpenSlippage +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openSlippage = StrToDouble(openSlippage);
      if (type==OP_UNDEFINED && NE(openSlippage, 0))                        return(_false(catch("RestoreStatus.Runtime(50)   pending order/open slippage mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(openSlippage, Digits-PipDigits) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // openExecution
      string strOpenExecution = StringTrim(values[11]);
      if (!StringIsNumeric(strOpenExecution))                               return(_false(catch("RestoreStatus.Runtime(51)   illegal position open execution \""+ strOpenExecution +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double openExecution = StrToDouble(strOpenExecution);
      if (LT(openExecution, 0))                                             return(_false(catch("RestoreStatus.Runtime(52)   illegal position open execution "+ NumberToStr(openExecution, ".+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closeTime
      string strCloseTime = StringTrim(values[12]);
      if (!StringIsDigit(strCloseTime))                                     return(_false(catch("RestoreStatus.Runtime(53)   illegal order close time \""+ strCloseTime +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      datetime closeTime = StrToInteger(strCloseTime);
      if (closeTime!=0 && closeTime < pendingTime)                          return(_false(catch("RestoreStatus.Runtime(54)   pending order time/delete time mis-match '"+ TimeToStr(pendingTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'/'"+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (closeTime!=0 && closeTime < openTime)                             return(_false(catch("RestoreStatus.Runtime(55)   order open/close time mis-match '"+ TimeToStr(openTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'/'"+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closePrice
      string strClosePrice = StringTrim(values[13]);
      if (!StringIsNumeric(strClosePrice))                                  return(_false(catch("RestoreStatus.Runtime(56)   illegal order close price \""+ strClosePrice +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closePrice = StrToDouble(strClosePrice);
      if (LT(closePrice, 0))                                                return(_false(catch("RestoreStatus.Runtime(57)   illegal order close price "+ NumberToStr(closePrice, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closeSlippage
      string strCloseSlippage = StringTrim(values[14]);
      if (!StringIsNumeric(strCloseSlippage))                               return(_false(catch("RestoreStatus.Runtime(58)   illegal order close slippage \""+ strCloseSlippage +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closeSlippage = StrToDouble(strCloseSlippage);
      if (NE(closeSlippage, 0)) {
         if (type == OP_UNDEFINED)                                          return(_false(catch("RestoreStatus.Runtime(59)   pending order/close slippage mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(closeSlippage, Digits-PipDigits) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (closeTime == 0)                                                return(_false(catch("RestoreStatus.Runtime(60)   order close time/slippage mis-match "+ closeTime +"/"+ DoubleToStr(closeSlippage, Digits-PipDigits) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // closeExecution
      string strCloseExecution = StringTrim(values[15]);
      if (!StringIsNumeric(strCloseExecution))                              return(_false(catch("RestoreStatus.Runtime(61)   illegal position close execution \""+ strCloseExecution +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double closeExecution = StrToDouble(strCloseExecution);
      if (LT(closeExecution, 0))                                            return(_false(catch("RestoreStatus.Runtime(62)   illegal position close execution "+ NumberToStr(closeExecution, ".+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // stopLoss
      string strStopLoss = StringTrim(values[16]);
      if (!StringIsNumeric(strStopLoss))                                    return(_false(catch("RestoreStatus.Runtime(63)   illegal order stoploss \""+ strStopLoss +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double stopLoss = StrToDouble(strStopLoss);
      if (LT(stopLoss, 0))                                                  return(_false(catch("RestoreStatus.Runtime(64)   illegal order stoploss "+ NumberToStr(stopLoss, PriceFormat) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // stopValue
      string strStopValue = StringTrim(values[17]);
      if (!StringIsNumeric(strStopValue))                                   return(_false(catch("RestoreStatus.Runtime(65)   illegal order stop value \""+ strStopValue +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double stopValue = StrToDouble(strStopValue);
      if (LT(stopValue, 0))                                                 return(_false(catch("RestoreStatus.Runtime(66)   illegal order stop value "+ NumberToStr(stopValue, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type==OP_UNDEFINED && NE(stopValue, 0))                           return(_false(catch("RestoreStatus.Runtime(67)   pending order/stop value mis-match "+ OperationTypeToStr(pendingType) +"/"+ NumberToStr(stopValue, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      if (type!=OP_UNDEFINED && EQ(stopValue, 0))                           return(_false(catch("RestoreStatus.Runtime(68)   order type/stop value mis-match "+ OperationTypeToStr(type) +"/"+ NumberToStr(stopValue, ".2+") +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // closedByStop
      string strClosedByStop = StringTrim(values[18]);
      if (!StringIsDigit(strClosedByStop))                                  return(_false(catch("RestoreStatus.Runtime(69)   illegal closedByStop value \""+ strClosedByStop +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      bool closedByStop = _bool(StrToInteger(strClosedByStop));
      if (type!=OP_UNDEFINED && closeTime!=0 && !closedByStop) {
         if (sequenceStopTime == 0)                                         return(_false(catch("RestoreStatus.Runtime(70)   sequenceStopTime/finished position mis-match "+ sequenceStopTime +"/#"+ ticket +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
         if (closeTime < sequenceStopTime)                                  return(_false(catch("RestoreStatus.Runtime(71)   sequenceStopTime/finished position close time mis-match '"+ TimeToStr(sequenceStopTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'/#"+ ticket +" '"+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"' in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      }

      // swap
      string strSwap = StringTrim(values[19]);
      if (!StringIsNumeric(strSwap))                                        return(_false(catch("RestoreStatus.Runtime(72)   illegal order swap \""+ strSwap +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double swap = StrToDouble(strSwap);
      if (type==OP_UNDEFINED && NE(swap, 0))                                return(_false(catch("RestoreStatus.Runtime(73)   pending order/swap mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(swap, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // commission
      string strCommission = StringTrim(values[20]);
      if (!StringIsNumeric(strCommission))                                  return(_false(catch("RestoreStatus.Runtime(74)   illegal order commission \""+ strCommission +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double commission = StrToDouble(strCommission);
      if (type==OP_UNDEFINED && NE(commission, 0))                          return(_false(catch("RestoreStatus.Runtime(75)   pending order/commission mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(commission, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // profit
      string strProfit = StringTrim(values[21]);
      if (!StringIsNumeric(strProfit))                                      return(_false(catch("RestoreStatus.Runtime(76)   illegal order profit \""+ strProfit +"\" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));
      double profit = StrToDouble(strProfit);
      if (type==OP_UNDEFINED && NE(profit, 0))                              return(_false(catch("RestoreStatus.Runtime(77)   pending order/profit mis-match "+ OperationTypeToStr(pendingType) +"/"+ DoubleToStr(profit, 2) +" in status file \""+ file +"\" (line \""+ line +"\")", ERR_RUNTIME_ERROR)));

      // ggf. Datenarrays vergrößern
      if (ArraySize(orders.ticket) < i+1)
         ResizeArrays(i+1);

      // Daten speichern
      orders.ticket           [i] = ticket;
      orders.level            [i] = level;
      orders.pendingType      [i] = pendingType;
      orders.pendingTime      [i] = pendingTime;
      orders.pendingModifyTime[i] = pendingModifyTime;
      orders.pendingPrice     [i] = pendingPrice;
      orders.pendingExecution [i] = pendingExecution;
      orders.type             [i] = type;
      orders.openTime         [i] = openTime;
      orders.openPrice        [i] = openPrice;
      orders.openSlippage     [i] = openSlippage;
      orders.openExecution    [i] = openExecution;
      orders.closeTime        [i] = closeTime;
      orders.closePrice       [i] = closePrice;
      orders.closeSlippage    [i] = closeSlippage;
      orders.closeExecution   [i] = closeExecution;
      orders.stopLoss         [i] = stopLoss;
      orders.stopValue        [i] = stopValue;
      orders.closedByStop     [i] = closedByStop;
      orders.swap             [i] = swap;
      orders.commission       [i] = commission;
      orders.profit           [i] = profit;

      //debug("RestoreStatus.Runtime()   #"+ ticket +"  level="+ level +"  pendingType="+ OperationTypeToStr(pendingType) +"  pendingTime='"+ TimeToStr(pendingTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'  pendingModifyTime='"+ TimeToStr(pendingModifyTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'  pendingPrice="+ NumberToStr(pendingPrice, PriceFormat) +"  pendingExecution="+ DoubleToStr(pendingExecution, 1) +"  type="+ OperationTypeToStr(type) +"  openTime='"+ TimeToStr(openTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'  openPrice="+ NumberToStr(openPrice, PriceFormat) +"  openSlippage="+ DoubleToStr(openSlippage, Digits-PipDigits) +"  openExecution="+ DoubleToStr(openExecution, 1) +"  closeTime='"+ TimeToStr(closeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"'  closePrice="+ NumberToStr(closePrice, PriceFormat) +"  closeSlippage="+ DoubleToStr(closeSlippage, Digits-PipDigits) +"  closeExecution="+ DoubleToStr(closeExecution, 1) +"  stopLoss="+ NumberToStr(stopLoss, PriceFormat) +"  stopValue="+ DoubleToStr(stopValue, 2) +"  closedByStop="+ BoolToStr(closedByStop) +"  swap="+ DoubleToStr(swap, 2) +"  commission="+ DoubleToStr(commission, 2) +"  profit="+ DoubleToStr(profit, 2));
   }
   return(IsNoError(catch("RestoreStatus.Runtime(78)")));
}


/**
 * Gleicht den in der Instanz gespeicherten Laufzeitstatus mit den Online-Daten der laufenden Sequenz ab.
 *
 * @return bool - Erfolgsstatus
 */
bool SynchronizeStatus() {
   if (IsLastError() || status==STATUS_DISABLED)
      return(false);

   // (1.1) alle offenen Tickets in Datenarrays mit Online-Status synchronisieren
   for (int i=ArraySize(orders.ticket)-1; i >= 0; i--) {
      // Daten synchronisieren, wenn das Ticket beim letzten Mal noch offen war
      if (orders.closeTime[i] == 0) {
         if (!OrderSelectByTicket(orders.ticket[i], "SynchronizeStatus(1)   cannot synchronize "+ OperationTypeDescription(ifInt(orders.type[i]==OP_UNDEFINED, orders.pendingType[i], orders.type[i])) +" order, #"+ orders.ticket[i] +" not found"))
            return(false);
         if (!Grid.ReplaceTicket(orders.ticket[i]))
            return(false);
      }
   }

   // (1.2) alle erreichbaren Online-Tickets mit Datenarrays synchronisieren
   for (i=OrdersTotal()-1; i >= 0; i--) {                            // offene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: während des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;
      if (IsMyOrder(sequenceId)) {
         if (IntInArray(orders.ticket, OrderTicket())) {             // bekannte Order
            if (!Grid.ReplaceTicket(OrderTicket()))
               return(false);
         }
         else if (!Grid.PushTicket(OrderTicket())) {                 // neue Order
            return(false);
         }
      }
   }
   for (i=OrdersHistoryTotal()-1; i >= 0; i--) {                     // geschlossene Tickets
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))              // FALSE: während des Auslesens wurde der Anzeigezeitraum der History verändert
         continue;
      if (IsMyOrder(sequenceId)) {
         if (IntInArray(orders.ticket, OrderTicket())) {             // bekannte Order
            if (!Grid.ReplaceTicket(OrderTicket()))
               return(false);
         }
         else if (!Grid.PushTicket(OrderTicket())) {                 // neue Order
            return(false);
         }
      }
   }

   // (1.3) gestrichene Orders aus Datenarrays entfernen
   for (i=ArraySize(orders.ticket)-1; i >= 0; i--) {
      if (orders.type[i]==OP_UNDEFINED) /*&&*/ if (orders.closeTime[i]!=0)
         if (!Grid.DropTicket(orders.ticket[i]))
            return(false);
   }


   // (2) Laufzeitvariablen restaurieren
   /*int   */ status              = STATUS_WAITING;
   /*int   */ grid.level          = 0;
   /*int   */ grid.maxLevelLong   = 0;
   /*int   */ grid.maxLevelShort  = 0;
   /*int   */ grid.stops          = 0;
   /*double*/ grid.stopsPL        = 0;
   /*double*/ grid.finishedPL     = 0;
   /*double*/ grid.floatingPL     = 0;
   /*double*/ grid.totalPL        = 0;
   /*double*/ grid.openStopValue  = 0;
   /*double*/ grid.valueAtRisk    = 0;
   /*double*/ grid.breakevenLong  = 0;
   /*double*/ grid.breakevenShort = 0;

   #define EVENT_OPEN         1                                         // Event-Types: {PositionOpen | PositionCloseByStop | PositionCloseByFinish}
   #define EVENT_CLOSESTOP    2
   #define EVENT_CLOSEFINISH  3

   bool   pendingOrder, openPosition, closedPosition;
   double profitLoss, pipValue=PipValue(LotSize);
   int    openLevels[]; ArrayResize(openLevels, 0);
   double events[][6]; ArrayResize(events, 0);

   int size = ArraySize(orders.ticket);

   for (i=0; i < size; i++) {
      pendingOrder   = orders.type[i] == OP_UNDEFINED;
      openPosition   = !pendingOrder && orders.closeTime[i]==0;
      closedPosition = !pendingOrder && !openPosition;

      if (closedPosition) {                                             // geschlossenes Ticket
         if (ArraySize(openLevels)!=0 && !orders.closedByStop[i]) return(_false(catch("SynchronizeStatus(2)   illegal sequence status, both open (#?) and finished (#"+ orders.ticket[i] +") positions found", ERR_RUNTIME_ERROR)));
      }

      /*
      // grid.base aus StopLoss ableiten (OpenPrice kann um Slippage verzerrt sein)
      grid.base = OrderStopLoss() - (orders.level[size] - MathSign(orders.level[size])) * GridSize * Pips;
      */

      if (!pendingOrder) {
         profitLoss = orders.swap[i] + orders.commission[i] + orders.profit[i];
         Sync.PushBreakevenEvent(events, orders.openTime[i], EVENT_OPEN, orders.level[i], NULL, NULL, orders.stopValue[i]);

         if (openPosition) {
            grid.floatingPL += profitLoss;
            if (IntInArray(openLevels, orders.level[i]))          return(_false(catch("SynchronizeStatus(3)   duplicate order level "+ orders.level[i] +" of open position #"+ orders.ticket[i], ERR_RUNTIME_ERROR)));
            ArrayPushInt(openLevels, orders.level[i]);
         }
         else if (orders.closedByStop[i]) {
            Sync.PushBreakevenEvent(events, orders.closeTime[i], EVENT_CLOSESTOP, orders.level[i], profitLoss, NULL, -orders.stopValue[i]);
         }
         else /*(closedByFinish)*/ {
            Sync.PushBreakevenEvent(events, orders.closeTime[i], EVENT_CLOSEFINISH, orders.level[i], NULL, profitLoss, -orders.stopValue[i]);
         }
      }
      if (IsLastError())
         return(false);
   }

   // status
   if (sequenceStartTime != 0)
      status = STATUS_PROGRESSING;

   if (ArraySize(openLevels) != 0) {
      int min = openLevels[ArrayMinimum(openLevels)];
      int max = openLevels[ArrayMaximum(openLevels)];
      if (min < 0 && max > 0)                return(_false(catch("SynchronizeStatus(4)   illegal sequence status, both long and short open positions found", ERR_RUNTIME_ERROR)));
      int maxLevel = MathMax(MathAbs(min), MathAbs(max)) +0.1;          // (int) double
      if (ArraySize(openLevels) != maxLevel) return(_false(catch("SynchronizeStatus(5)   illegal sequence status, one or more open positions missed", ERR_RUNTIME_ERROR)));
   }

   if (sequenceStopTime != 0) {
      status = STATUS_FINISHED;
      if (ArraySize(openLevels) != 0)        return(_false(catch("SynchronizeStatus(6)   illegal sequence status "+ SequenceStatusToStr(status) +", open positions found", ERR_RUNTIME_ERROR)));
   }


   // (3) Start-/Stop-Marker zeichnen
   RedrawStartStop();


   // (4) Orders visualisieren
   RedrawOrders();


   // (5) Breakeven-Verlauf restaurieren und Indikator neu zeichnen
   int time, lastTime, minute, lastMinute, type, level;
   size = ArrayRange(events, 0);
   if (size > 0)
      ArraySort(events);                                                // Breakeven-Änderungen zeitlich sortieren

   for (i=0; i < size; i++) {
      time = events[i][0] +0.1;                                         // (int) double

      // zwischen den BE-Events liegende BarOpen(M1)-Events simulieren
      if (lastTime > 0) {
         minute = time/60; lastMinute = lastTime/60;
         while (lastMinute < minute-1) {                                // TODO: fehlende Sessions überspringen (Wochenende)
            lastMinute++;
            Grid.DrawBreakeven(lastMinute * MINUTES);
         }
      }
      type                = events[i][1] +0.1;                          // (int) double
      level               = events[i][2] + MathSign(events[i][2])*0.1;  // (int) double
      grid.stopsPL       += events[i][3];
      grid.finishedPL    += events[i][4];
      grid.openStopValue += events[i][5];

      if (type != EVENT_CLOSEFINISH)                                    // realizedPL = stopsPL + finishedPL
         grid.valueAtRisk = grid.openStopValue - grid.stopsPL;          // ohne finishedPL => ist während Laufzeit 0 und wird ab Stop nicht mehr berücksichtigt

      if      (type == EVENT_OPEN)      { grid.level = level; }
      else if (type == EVENT_CLOSESTOP) { grid.level = level-MathSign(level); grid.stops++; }

      Grid.UpdateBreakeven(time);
      lastTime = time;
   }


   grid.totalPL = grid.stopsPL + grid.finishedPL + grid.floatingPL;
   SS.Grid.MaxLevel();
   SS.Grid.Stops();
   SS.Grid.TotalPL();
   SS.Grid.ValueAtRisk();

   return(IsNoError(catch("SynchronizeStatus(7)")));
}


/**
 * Fügt den Breakeven-relevanten Events ein weiteres hinzu.
 *
 * @param  double   events[]      - Array mit bereits gespeicherten Events
 * @param  datetime time          - Zeitpunkt des neuen Events
 * @param  int      type          - Event-Typ: EVENT_OPEN | EVENT_CLOSESTOP | EVENT_CLOSEFINISH
 * @param  int      level         - Gridlevel des neuen Events
 * @param  double   stopsPL       - Änderung des Profit/Loss durch ausgestoppte Positionen
 * @param  double   finishedPL    - Änderung des Profit/Loss durch sonstige geschlossene Positionen
 * @param  double   openStopValue - Änderung des OpenStop-Values durch das neue Event
 *
 * @return bool - Erfolgsstatus
 */
bool Sync.PushBreakevenEvent(double& events[][], datetime time, int type, int level, double stopsPL, double finishedPL, double openStopValue) {
   int size = ArrayRange(events, 0);
   ArrayResize(events, size+1);

   events[size][0] = time;
   events[size][1] = type;
   events[size][2] = level;
   events[size][3] = stopsPL;
   events[size][4] = finishedPL;
   events[size][5] = openStopValue;

   grid.maxLevelLong  = MathMax(grid.maxLevelLong,  level) +0.1;     // (int) double
   grid.maxLevelShort = MathMin(grid.maxLevelShort, level) -0.1;     // (int) double

   return(IsNoError(catch("Sync.PushBreakevenEvent()")));
}


/**
 * Ermittelt die OpenPrice-Slippage einer Position.
 *
 * @param  int i - Index der Position in den Datenarrays
 *
 * @return double - positive (zu ungunsten) oder negative (zugunsten) Slippage in Pip
 */
double GetOpenPriceSlippage(int i) {
   if (orders.type[i] == OP_UNDEFINED)                                                 // Pending-Order
      return(0);

   double slippage, expectedPrice=grid.base + orders.level[i] * GridSize * Pips;

   if (orders.type[i] == OP_BUY) slippage = orders.openPrice[i] - expectedPrice;       // Slippage zu ungunsten ist positiv, zugunsten negativ
   else                          slippage = expectedPrice - orders.openPrice[i];
   slippage = NormalizeDouble(slippage/Pips, Digits-PipDigits);                        // in Pip

   if (NE(slippage, 0))
      debug("GetOpenPriceSlippage()   open price slippage of #"+ orders.ticket[i] +" = "+ DoubleToStr(slippage, Digits-PipDigits) +" pip");
   return(slippage);
}


/**
 * Ermittelt die ClosePrice-Slippage einer Position.
 *
 * @param  int i - Index der Position in den Datenarrays
 *
 * @return double - positive (zu ungunsten) oder negative (zugunsten) Slippage in Pip
 */
double GetClosePriceSlippage(int i) {
   if (orders.type[i] == OP_UNDEFINED)                                                 // Pending-Order
      return(0);
   if (orders.closeTime[i] == 0)                                                       // offene Position
      return(0);
   if (!orders.closedByStop[i])                                                        // nicht vom StopLoss geschlossene Position
      return(0);

   double slippage;

   if (orders.type[i] == OP_BUY) slippage = orders.stopLoss[i] - orders.closePrice[i]; // Slippage zu ungunsten ist positiv, zugunsten negativ
   else                          slippage = orders.closePrice[i] - orders.stopLoss[i];
   slippage = NormalizeDouble(slippage/Pips, Digits-PipDigits);                        // in Pip

   if (NE(slippage, 0))
      debug("GetClosePriceSlippage()   close price slippage of #"+ orders.ticket[i] +" = "+ DoubleToStr(slippage, Digits-PipDigits) +" pip");
   return(slippage);
}


/**
 * Zeichnet die Start-/Stop-Marker der Sequenz.
 */
void RedrawStartStop() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return;

   static color last.MarkerColor = DodgerBlue;
   if (Color.Breakeven != CLR_NONE)
      last.MarkerColor = Color.Breakeven;

   string label;

   // Start-Marker
   if (sequenceStartTime > 0) {
      label = StringConcatenate("SR.", sequenceId, ".start");
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      ObjectCreate(label, OBJ_ARROW, 0, sequenceStartTime, NormalizeDouble(sequenceStartPrice, PipDigits));
      ObjectSet   (label, OBJPROP_ARROWCODE, SYMBOL_LEFTPRICE);
      ObjectSet   (label, OBJPROP_BACK,      false           );
      ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor);
   }

   // Stop-Marker
   if (sequenceStopTime > 0) {
      label = StringConcatenate("SR.", sequenceId, ".stop");
      if (ObjectFind(label) == 0)
         ObjectDelete(label);
      ObjectCreate(label, OBJ_ARROW, 0, sequenceStopTime, NormalizeDouble(sequenceStopPrice, PipDigits));
      ObjectSet   (label, OBJPROP_ARROWCODE, SYMBOL_LEFTPRICE);
      ObjectSet   (label, OBJPROP_BACK,      false            );
      ObjectSet   (label, OBJPROP_COLOR,     last.MarkerColor);
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
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1)
      return(_false(catch("ChartMarker.OrderSent()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               ClosedByFinish
   #define DM_ALL       3     // Pending, Open, ClosedByStop, ClosedByFinish
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
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1)
      return(_false(catch("ChartMarker.OrderFilled()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               ClosedByFinish
   #define DM_ALL       3     // Pending, Open, ClosedByStop, ClosedByFinish
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
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(true);
   if (i < 0 || ArraySize(orders.ticket) < i+1)
      return(_false(catch("ChartMarker.PositionClosed()   illegal parameter i = "+ i, ERR_INVALID_FUNCTION_PARAMVALUE)));
   /*
   #define DM_NONE      0     // - keine Anzeige -
   #define DM_STOPS     1     // Pending,       ClosedByStop
   #define DM_PYRAMID   2     // Pending, Open,               ClosedByFinish
   #define DM_ALL       3     // Pending, Open, ClosedByStop, ClosedByFinish
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
 * Ob die Sequenz im Tester erzeugt wurde (für Visualisierung von Tests in Live-Charts). Der Aufruf dieser Funktion in Live-Charts mit einer im Tester
 * erzeugten Sequenz (z.B. mit VisualMode=Off) gibt ebenfalls TRUE zurück.
 *
 * @return bool
 */
bool IsTestSequence() {
   return(IsTesting() || testSequence);
}


/**
 * Setzt die Größe der Datenarrays auf den angegebenen Wert.
 *
 * @param  int  size  - neue Größe
 * @param  bool reset - ob die Arrays komplett zurückgesetzt werden sollen
 *                      (default: nur neu hinzugefügte Felder werden initialisiert)
 *
 * @return int - Fehlerstatus
 */
int ResizeArrays(int size, bool reset=false) {
   int oldSize = ArraySize(orders.ticket);

   if (size != oldSize) {
      ArrayResize(orders.ticket,            size);
      ArrayResize(orders.level,             size);
      ArrayResize(orders.pendingType,       size);
      ArrayResize(orders.pendingTime,       size);
      ArrayResize(orders.pendingModifyTime, size);
      ArrayResize(orders.pendingPrice,      size);
      ArrayResize(orders.pendingExecution,  size);
      ArrayResize(orders.type,              size);
      ArrayResize(orders.openTime,          size);
      ArrayResize(orders.openPrice,         size);
      ArrayResize(orders.openSlippage,      size);
      ArrayResize(orders.openExecution,     size);
      ArrayResize(orders.closeTime,         size);
      ArrayResize(orders.closePrice,        size);
      ArrayResize(orders.closeSlippage,     size);
      ArrayResize(orders.closeExecution,    size);
      ArrayResize(orders.stopLoss,          size);
      ArrayResize(orders.stopValue,         size);
      ArrayResize(orders.closedByStop,      size);
      ArrayResize(orders.swap,              size);
      ArrayResize(orders.commission,        size);
      ArrayResize(orders.profit,            size);
   }

   if (reset) {                                                      // alle Felder zurücksetzen
      if (size != 0) {
         ArrayInitialize(orders.ticket,                     0);
         ArrayInitialize(orders.level,                      0);
         ArrayInitialize(orders.pendingType,      OP_UNDEFINED);
         ArrayInitialize(orders.pendingTime,                0);
         ArrayInitialize(orders.pendingModifyTime,          0);
         ArrayInitialize(orders.pendingPrice,               0);
         ArrayInitialize(orders.pendingExecution,           0);
         ArrayInitialize(orders.type,             OP_UNDEFINED);
         ArrayInitialize(orders.openTime,                   0);
         ArrayInitialize(orders.openPrice,                  0);
         ArrayInitialize(orders.openSlippage,               0);
         ArrayInitialize(orders.openExecution,              0);
         ArrayInitialize(orders.closeTime,                  0);
         ArrayInitialize(orders.closePrice,                 0);
         ArrayInitialize(orders.closeSlippage,              0);
         ArrayInitialize(orders.closeExecution,             0);
         ArrayInitialize(orders.stopLoss,                   0);
         ArrayInitialize(orders.stopValue,                  0);
         ArrayInitialize(orders.closedByStop,           false);
         ArrayInitialize(orders.swap,                       0);
         ArrayInitialize(orders.commission,                 0);
         ArrayInitialize(orders.profit,                     0);
      }
   }
   else {
      for (int i=oldSize; i < size; i++) {
         orders.pendingType[i] = OP_UNDEFINED;                       // hinzugefügte pendingType- und type-Felder initialisieren (0 kann nicht verwendet werden)
         orders.type       [i] = OP_UNDEFINED;
      }
   }

   return(catch("ResizeArrays()"));

   // Dummy-Calls
   BreakevenEventToStr(NULL);
   DistanceToProfit(NULL);
   GridDirectionToStr(NULL);
   OrderDisplayModeToStr(NULL);
}


/**
 * Gibt die lesbare Konstante eines Sequenzstatus-Codes zurück.
 *
 * @param  int status - Status-Code
 *
 * @return string
 */
string SequenceStatusToStr(int status) {
   switch (status) {
      case STATUS_WAITING    : return("STATUS_WAITING"    );
      case STATUS_PROGRESSING: return("STATUS_PROGRESSING");
      case STATUS_FINISHED   : return("STATUS_FINISHED"   );
      case STATUS_DISABLED   : return("STATUS_DISABLED"   );
   }
   return(_empty(catch("SequenceStatusToStr()  invalid parameter status = "+ status, ERR_INVALID_FUNCTION_PARAMVALUE)));
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
      case EVENT_OPEN       : return("EVENT_OPEN"       );
      case EVENT_CLOSESTOP  : return("EVENT_CLOSESTOP"  );
      case EVENT_CLOSEFINISH: return("EVENT_CLOSEFINISH");
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
