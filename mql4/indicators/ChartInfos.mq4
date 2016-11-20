/**
 * Zeigt im Chart verschiedene Informationen zum Instrument und zu den aktuellen Positionen einer der folgenden Typen an:
 *
 *  � interne Positionen: - Positionen, die im aktuellen Account des Terminals gehalten werden
 *                        - Order- und P/L-Daten stammen vom Terminal
 *                        - In diesem Mode kann zus�tzlich ein interner OrderTracker mit akustischen Benachrichtigungen aktiviert werden,
 *                          dessen Funktionalit�t dem des externen EventTrackers entspricht: onPositionOpen, onPositionClosed, onOrderFailed
 *
 *                          TODO: Der OrderTracker mu� alle Symbole �berwachen, darf ein Event jedoch nicht mehrfach signalisieren, wenn er
 *                                in mehreren Charts aktiv ist.
 *
 *  � externe Positionen: - Positionen, die in einem externen Account gehalten werden (z.B. in SimpleTrader-Accounts)
 *                        - Orderdaten stammen aus einer externen Quelle
 *                        - P/L-Daten werden anhand der aktuellen Kurse des Terminals selbst berechnet
 *
 *  � Remote-Positionen:  - Positionen, die in einem anderen Account gehalten werden (in der Regel synthetische Positionen)
 *                        - Orderdaten stammen aus einer externen Quelle
 *                        - P/L-Daten stammen ebenfalls aus einer externen Quelle
 *                        - Orderlimits k�nnen �berwacht und die externe Quelle bei Erreichen benachrichtigt werden
 */
#property indicator_chart_window

#include <stddefine.mqh>
int   __INIT_FLAGS__[] = { INIT_TIMEZONE };
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern string Track.Orders         = "on | off | account*";
extern bool   Offline.Ticker       = true;                                                // ob der Ticker in Offline-Charts aktiviert wird
extern string __________________________;

extern string Signal.Sound         = "on | off | account*";                               // Sound
extern string Signal.Mail.Receiver = "system | account | auto* | off | {address}";        // E-Mailadresse
extern string Signal.SMS.Receiver  = "system | account | auto* | off | {phone}";          // Telefonnummer


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinStrings.mqh>

#include <iFunctions/@ATR.mqh>
#include <iFunctions/iBarShiftNext.mqh>
#include <iFunctions/iBarShiftPrevious.mqh>

#include <MT4iQuickChannel.mqh>
#include <lfx.mqh>
#include <scriptrunner.mqh>
#include <structs/myfx/LFXOrder.mqh>

#include <signals/Configure.Signal.Mail.mqh>
#include <signals/Configure.Signal.SMS.mqh>
#include <signals/Configure.Signal.Sound.mqh>


// Typ der Kursanzeige
int appliedPrice = PRICE_MEDIAN;                                  // Preis: Bid | Ask | Median (default)


// Moneymanagement
#define STANDARD_VOLATILITY  10                                   // Standard-Volatilit�t einer Unit in Prozent Equity je Woche (willk�rlich gew�hlt)

double mm.realEquity;                                             // real verwendeter Equity-Betrag; nicht der vom Broker berechnete = AccountEquity()
                                                                  //  - enth�lt externe Assets                                                           !!! doppelte Spreads und      !!!
                                                                  //  - enth�lt offene Gewinne/Verluste gehedgter Positionen (gehedgt = realisiert)      !!! Commissions herausrechnen !!!
                                                                  //  - enth�lt offene Verluste ungehedgter Positionen
                                                                  //  - enth�lt NICHT offene Gewinne ungehedgter Positionen (ungehedgt = unrealisiert)

double mm.lotValue;                                               // Value eines Lots in Account-Currency
double mm.unleveragedLots;                                        // Lotsize bei Hebel von 1:1

double mm.ATRwAbs;                                                // w�chentliche ATR: absoluter Wert
double mm.ATRwPct;                                                // w�chentliche ATR: prozentualer Wert

double mm.stdVola = STANDARD_VOLATILITY;                          // Standard-Volatilit�t einer Unit in Prozent je Woche (kann per Konfiguration �berschrieben werden)
double mm.stdLeverage;                                            // Hebel f�r Standard-Volatilit�t
double mm.stdLots;                                                // resultierende Lotsize

double mm.customVola;                                             // benutzerdefinierte Volatilit�t einer Unit in Prozent je Woche
double mm.customLeverage;                                         // benutzerdefinierter Hebel
double mm.customLots;                                             // resultierende Lotsize
bool   mm.isCustomUnitSize;                                       // ob die Default-UnitSize (mm.defaultLots) nach Std.-Werten oder benutzerdefiniert berechnet wird

double mm.defaultVola;                                            // resultierende Moneymanagement-Werte (nach Standard- oder Custom- berechnet)
double mm.defaultLeverage;                                        //
double mm.defaultLots;                                            // UnitSize: exakter Wert
double mm.defaultLots.normalized;                                 // UnitSize: auf MODE_LOTSTEP normalisierter Wert

bool   mm.ready;                                                  // Flag

double aum.value;                                                 // zus�tzliche extern gehaltene bei Equity-Berechnungen zu ber�cksichtigende Assets


// Konfiguration individueller Positionen
#define POSITION_CONFIG_TERM.size      40
#define POSITION_CONFIG_TERM.doubleSize 5

double positions.config[][POSITION_CONFIG_TERM.doubleSize];       // geparste Konfiguration, Format siehe CustomPositions.ReadConfig()
string positions.config.comments[];                               // Kommentare konfigurierter Positionen (Gr��e entspricht der Anzahl der konfigurierten Positionen)

#define TERM_OPEN_LONG                  1                         // ConfigTerm-Types
#define TERM_OPEN_SHORT                 2
#define TERM_OPEN_SYMBOL                3
#define TERM_OPEN_ALL                   4
#define TERM_HISTORY_SYMBOL             5
#define TERM_HISTORY_ALL                6
#define TERM_ADJUSTMENT                 7
#define TERM_EQUITY                     8


// interne + externe Positionsdaten
bool   isPendings;                                                // ob Pending-Limite im Markt liegen (Orders oder Positions)
bool   isPosition;                                                // ob offene Positionen existieren = (longPosition || shortPosition);   // die Gesamtposition kann flat sein
double totalPosition;
double longPosition;
double shortPosition;
int    positions.iData[][3];                                      // Positionsdetails: [ConfigType, PositionType, CommentIndex]
double positions.dData[][9];                                      //                   [DirectionalLots, HedgedLots, BreakevenPrice|PipDistance, OpenProfit, ClosedProfit, AdjustedProfit, FullProfitAbsolute, FullProfitPercent]
bool   positions.analyzed;
bool   positions.absoluteProfits;                                 // default: FALSE


#define CONFIG_AUTO                     0                         // ConfigTypes:      normale unkonfigurierte offene Position (intern oder extern)
#define CONFIG_REAL                     1                         //                   individuell konfigurierte reale Position
#define CONFIG_VIRTUAL                  2                         //                   individuell konfigurierte virtuelle Position

#define POSITION_LONG                   1                         // PositionTypes
#define POSITION_SHORT                  2                         // (werden in typeDescriptions[] als Arrayindizes benutzt)
#define POSITION_HEDGE                  3
#define POSITION_HISTORY                4
string  typeDescriptions[] = {"", "Long:", "Short:", "Hedge:", "History:"};

#define I_CONFIG_TYPE                   0                         // Arrayindizes von positions.iData[]
#define I_POSITION_TYPE                 1
#define I_COMMENT_INDEX                 2

#define I_DIRECTIONAL_LOTS              0                         // Arrayindizes von positions.dData[]
#define I_HEDGED_LOTS                   1
#define I_BREAKEVEN_PRICE               2
#define I_PIP_DISTANCE  I_BREAKEVEN_PRICE
#define I_OPEN_EQUITY                   3
#define I_OPEN_PROFIT                   4
#define I_CLOSED_PROFIT                 5
#define I_ADJUSTED_PROFIT               6
#define I_FULL_PROFIT_ABS               7
#define I_FULL_PROFIT_PCT               8


// externe Positionen: open
int      external.open.ticket    [];
int      external.open.type      [];
double   external.open.lots      [];
datetime external.open.openTime  [];
double   external.open.openPrice [];
double   external.open.takeProfit[];
double   external.open.stopLoss  [];
double   external.open.commission[];
double   external.open.swap      [];
double   external.open.profit    [];
bool     external.open.lots.checked;
double   external.open.longPosition, external.open.shortPosition;

// externe Positionen: closed
int      external.closed.ticket    [];
int      external.closed.type      [];
double   external.closed.lots      [];
datetime external.closed.openTime  [];
double   external.closed.openPrice [];
datetime external.closed.closeTime [];
double   external.closed.closePrice[];
double   external.closed.takeProfit[];
double   external.closed.stopLoss  [];
double   external.closed.commission[];
double   external.closed.swap      [];
double   external.closed.profit    [];

// Cache-Variablen f�r LFX-Orders. Ihre Gr��e entspricht der Gr��e von lfxOrders[].
// Dienen der Beschleunigung, um nicht st�ndig die LFX_ORDER-Getter aufrufen zu m�ssen.
int      lfxOrders.iCache[][1];                                      // = {Ticket}
bool     lfxOrders.bCache[][3];                                      // = {IsPendingOrder, IsOpenPosition , IsPendingPosition}
double   lfxOrders.dCache[][7];                                      // = {OpenEquity    , Profit         , LastProfit       , TP-Amount , TP-Percent, SL-Amount, SL-Percent}
int      lfxOrders.pendingOrders;                                    // Anzahl der PendingOrders (mit Entry-Limit)  : lo.IsPendingOrder()    = 1
int      lfxOrders.openPositions;                                    // Anzahl der offenen Positionen               : lo.IsOpenPosition()    = 1
int      lfxOrders.pendingPositions;                                 // Anzahl der offenen Positionen mit Exit-Limit: lo.IsPendingPosition() = 1

#define I_IC.ticket                 0                                // Arrayindizes f�r Cache-Arrays

#define I_BC.isPendingOrder         0
#define I_BC.isOpenPosition         1
#define I_BC.isPendingPosition      2

#define I_DC.openEquity             0
#define I_DC.profit                 1
#define I_DC.lastProfit             2                                // der letzte vorherige Profit-Wert, um PL-Aktionen nur bei �nderungen durchf�hren zu k�nnen
#define I_DC.takeProfitAmount       3
#define I_DC.takeProfitPercent      4
#define I_DC.stopLossAmount         5
#define I_DC.stopLossPercent        6


// Textlabel f�r die einzelnen Anzeigen
string   label.instrument   = "${__NAME__}.Instrument";
string   label.ohlc         = "${__NAME__}.OHLC";
string   label.price        = "${__NAME__}.Price";
string   label.spread       = "${__NAME__}.Spread";
string   label.aum          = "${__NAME__}.AuM";
string   label.position     = "${__NAME__}.Position";
string   label.unitSize     = "${__NAME__}.UnitSize";
string   label.orderCounter = "${__NAME__}.OrderCounter";
string   label.tradeAccount = "${__NAME__}.TradeAccount";
string   label.stopoutLevel = "${__NAME__}.StopoutLevel";
string   label.time         = "${__NAME__}.Time";


// Font-Settings der CustomPositions-Anzeige
string   positions.fontName          = "MS Sans Serif";
int      positions.fontSize          = 8;

color    positions.fontColor.intern  = Blue;
color    positions.fontColor.extern  = Red;
color    positions.fontColor.remote  = Blue;
color    positions.fontColor.virtual = Green;
color    positions.fontColor.history = C'128,128,0';


// Farben f�r Orderanzeige
#define CLR_PENDING_OPEN         DeepSkyBlue
#define CLR_OPEN_LONG            C'0,0,254'                       // Blue - rgb(1,1,1)
#define CLR_OPEN_SHORT           C'254,0,0'                       // Red  - rgb(1,1,1)
#define CLR_OPEN_TAKEPROFIT      LimeGreen
#define CLR_OPEN_STOPLOSS        Red
#define CLR_CLOSED_LONG          Blue
#define CLR_CLOSED_SHORT         Red
#define CLR_CLOSE                Orange


// Offline-Chartticker
int    tickTimerId;                                               // ID eines ggf. installierten Offline-Tickers


// Ordertracking                                                  // entspricht dem Code im EventTracker
bool   track.orders;

// Konfiguration der Signalisierung
bool   signal.sound;
string signal.sound.orderFailed    = "speech/OrderExecutionFailed.wav";
string signal.sound.positionOpened = "speech/OrderFilled.wav";
string signal.sound.positionClosed = "speech/PositionClosed.wav";

bool   signal.mail;
string signal.mail.sender   = "";
string signal.mail.receiver = "";

bool   signal.sms;
string signal.sms.receiver = "";

// Order-Events
int    orders.knownOrders.ticket[];                                  // vom letzten Aufruf bekannte offene Orders
int    orders.knownOrders.type  [];

// Close-Typen f�r automatisch geschlossene Positionen
#define CLOSE_TYPE_TP               1                                // TakeProfit
#define CLOSE_TYPE_SL               2                                // StopLoss
#define CLOSE_TYPE_SO               3                                // StopOut (Margin-Call)


#include <ChartInfos/init.mqh>
#include <ChartInfos/deinit.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   mm.ready           = false;
   positions.analyzed = false;

   HandleEvent(EVENT_CHART_CMD);                                                                   // ChartCommands verarbeiten

   if (!UpdatePrice())                     if (CheckLastError("onTick(1)"))  return(last_error);   // aktualisiert die Kursanzeige oben rechts
   if (!UpdateOHLC())                      if (CheckLastError("onTick(2)"))  return(last_error);   // aktualisiert die OHLC-Anzeige oben links           // TODO: unvollst�ndig

   if (mode.remote.trading) {
      if (!QC.HandleLfxTerminalMessages()) if (CheckLastError("onTick(3)"))  return(last_error);   // Quick-Channel: bei einem LFX-Terminal eingehende Messages verarbeiten
      if (!UpdatePositions())              if (CheckLastError("onTick(4)"))  return(last_error);   // aktualisiert die Positionsanzeigen unten rechts (gesamt) und links (detailliert)
   }
   else {
      if (!QC.HandleTradeCommands())       if (CheckLastError("onTick(5)"))  return(last_error);   // Quick-Channel: bei einem Trade-Terminal eingehende Messages verarbeiten
      if (!UpdateSpread())                 if (CheckLastError("onTick(6)"))  return(last_error);
      if (!UpdateUnitSize())               if (CheckLastError("onTick(7)"))  return(last_error);   // akualisiert die UnitSize-Anzeige unten rechts
      if (!UpdatePositions())              if (CheckLastError("onTick(8)"))  return(last_error);   // aktualisiert die Positionsanzeigen unten rechts (gesamt) und unten links (detailliert)
      if (!UpdateStopoutLevel())           if (CheckLastError("onTick(9)"))  return(last_error);   // aktualisiert die Markierung des Stopout-Levels im Chart
      if (!UpdateOrderCounter())           if (CheckLastError("onTick(10)")) return(last_error);   // aktualisiert die Anzeige der Anzahl der offenen Orders

      // ggf. Orders �berwachen
      if (mode.intern.trading && track.orders) {
         int failedOrders      []; ArrayResize(failedOrders,    0);
         int openedPositions   []; ArrayResize(openedPositions, 0);
         int closedPositions[][2]; ArrayResize(closedPositions, 0);     // { Ticket, CloseType=[CLOSE_TYPE_TP | CLOSE_TYPE_SL | CLOSE_TYPE_SO] }

         if (!OrderTracker.CheckPositions(failedOrders, openedPositions, closedPositions))
            return(last_error);

         if (ArraySize(failedOrders   ) > 0) onOrderFail    (failedOrders   );
         if (ArraySize(openedPositions) > 0) onPositionOpen (openedPositions);
         if (ArraySize(closedPositions) > 0) onPositionClose(closedPositions);
      }
   }

   if (IsVisualModeFix()) {                                                                        // nur im Tester:
      if (!UpdateTime())                   if (CheckLastError("onTick(11)")) return(last_error);   // aktualisiert die Anzeige der Serverzeit unten rechts
   }
   return(last_error);
}


/**
 * Pr�ft, ob ein Fehler gesetzt ist und gibt eine Warnung aus, wenn das nicht der Fall ist. Zum Debugging in onTick()
 *
 * @param  string location - Ort der Pr�fung
 *
 * @return bool - ob ein Fehler gesetzt ist
 */
bool CheckLastError(string location) {
   if (IsLastError())
      return(true);
   //debug(location +"  returned FALSE but set no error");
   return(false);
}


/**
 * Handler f�r ChartCommands.
 *
 * @param  string commands[] - die eingetroffenen Commands
 *
 * @return bool - Erfolgsstatus
 *
 *
 * Messageformat: "cmd=account:[{companyId}:{account}]" - Schaltet den externen Account um.
 *                "cmd=ToggleOpenOrders"                - Schaltet die Anzeige der offenen Orders ein/aus.
 *                "cmd=ToggleTradeHistory"              - Schaltet die Anzeige der Trade-History ein/aus.
 *                "cmd=ToggleAuM"                       - Schaltet die Assets-under-Management-Anzeige ein/aus.
 *                "cmd=EditAccountConfig"               - L�dt die Konfigurationsdatei des aktuellen Accounts in den Editor. Im ChartInfos-Indikator,
 *                                                        da der aktuelle Account ein im Indikator definierter externer oder LFX-Account sein kann.
 */
bool onChartCommand(string commands[]) {
   int size = ArraySize(commands);
   if (!size) return(!warn("onChartCommand(1)  empty parameter commands = {}"));

   for (int i=0; i < size; i++) {
      if (commands[i] == "cmd=EditAccountConfig") {
         if (!EditAccountConfig())
            return(false);
         continue;
      }
      if (commands[i] == "cmd=LogPositionTickets") {
         if (!Positions.LogTickets())
            return(false);
         continue;
      }
      if (commands[i] == "cmd=ToggleProfits") {
         if (!Positions.ToggleProfits())
            return(false);
         continue;
      }
      if (commands[i] == "cmd=ToggleAuM") {
         if (!ToggleAuM())
            return(false);
         continue;
      }
      if (commands[i] == "cmd=ToggleOpenOrders") {
         if (!ToggleOpenOrders())
            return(false);
         continue;
      }
      if (commands[i] == "cmd=ToggleTradeHistory") {
         if (!ToggleTradeHistory())
            return(false);
         continue;
      }
      if (StringStartsWith(commands[i], "cmd=account:")) {
         string key = StringRightFrom(commands[i], ":");
         if (!InitTradeAccount(key))  return(false);
         if (!UpdateAccountDisplay()) return(false);
         if (mode.extern.notrading) {
            external.open.lots.checked = false;
            if (ReadExternalPositions(tradeAccount.company, tradeAccount.alias) == -1)
               return(false);
         }
         ArrayResize(positions.config,          0);
         ArrayResize(positions.config.comments, 0);
         continue;
      }
      warn("onChartCommand(2)  unknown chart command \""+ commands[i] +"\"");
   }
   return(!catch("onChartCommand(3)"));
}


/**
 * Schaltet die Anzeige der offenen Orders ein/aus.
 *
 * @return bool - Erfolgsstatus
 */
bool ToggleOpenOrders() {
   // aktuellen Anzeigestatus aus Chart auslesen und umschalten: ON/OFF
   bool status = !GetOpenOrderDisplayStatus();

   // Status ON: offene Orders anzeigen
   if (status) {
      int orders = ShowOpenOrders();
      if (orders == -1)
         return(false);
      if (!orders) {                                                 // ohne offene Orders bleibt die Anzeige unver�ndert
         status = false;
         PlaySoundEx("Plonk.wav");                                   // Plonk!!!
      }
   }

   // Status OFF: Chartobjekte offener Orders l�schen
   else {
      for (int i=ObjectsTotal()-1; i >= 0; i--) {
         string name = ObjectName(i);
         if (StringGetChar(name, 0) == '#') {
            if (ObjectType(name)==OBJ_ARROW) {
               int arrow = ObjectGet(name, OBJPROP_ARROWCODE);
               color clr = ObjectGet(name, OBJPROP_COLOR    );
               if (arrow == SYMBOL_ORDEROPEN)
                  if (clr!=CLR_PENDING_OPEN) /*&&*/ if (clr!=CLR_OPEN_LONG) /*&&*/ if (clr!=CLR_OPEN_SHORT)
                     continue;
               if (arrow == SYMBOL_ORDERCLOSE)
                  if (clr!=CLR_OPEN_TAKEPROFIT) /*&&*/ if (clr!=CLR_OPEN_STOPLOSS)
                     continue;
               ObjectDelete(name);
            }
         }
      }
   }

   // Anzeigestatus im Chart speichern
   SetOpenOrderDisplayStatus(status);

   if (This.IsTesting())
      WindowRedraw();
   return(!catch("ToggleOpenOrders(1)"));
}


/**
 * Zeigt alle aktuell offenen Orders an.
 *
 * @return int - Anzahl der angezeigten offenen Orders oder -1 (EMPTY), falls ein Fehler auftrat.
 */
int ShowOpenOrders() {
   int      orders, ticket, type, colors[]={CLR_OPEN_LONG, CLR_OPEN_SHORT};
   datetime openTime;
   double   lots, units, openPrice, takeProfit, stopLoss;
   string   comment, label1, label2, label3, sTP, sSL, types[]={"buy", "sell", "buy limit", "sell limit", "buy stop", "sell stop"};


   // (1) mode.intern.trading
   if (mode.intern.trading) {
      orders = OrdersTotal();

      for (int i=0, n; i < orders; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))                  // FALSE: w�hrend des Auslesens wurde von dritter Seite eine offene Order geschlossen oder gel�scht
            break;
         if (OrderSymbol() != Symbol()) continue;

         // Daten auslesen
         ticket     = OrderTicket();
         type       = OrderType();
         lots       = OrderLots();
         openTime   = OrderOpenTime();
         openPrice  = OrderOpenPrice();
         takeProfit = OrderTakeProfit();
         stopLoss   = OrderStopLoss();

         if (OrderType() > OP_SELL) {
            // Pending-Order
            label1 = StringConcatenate("#", ticket, " ", types[type], " ", DoubleToStr(lots, 2), " at ", NumberToStr(openPrice, PriceFormat));

            // Order anzeigen
            if (ObjectFind(label1) == 0)
               ObjectDelete(label1);
            if (ObjectCreate(label1, OBJ_ARROW, 0, TimeServer(), openPrice)) {
               ObjectSet(label1, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN);
               ObjectSet(label1, OBJPROP_COLOR,     CLR_PENDING_OPEN);
            }
         }
         else {
            // offene Position
            label1 = StringConcatenate("#", ticket, " ", types[type], " ", DoubleToStr(lots, 2), " at ", NumberToStr(openPrice, PriceFormat));

            // TakeProfit anzeigen
            if (takeProfit != NULL) {
               sTP    = StringConcatenate("TP: ", NumberToStr(takeProfit, PriceFormat));
               label2 = StringConcatenate(label1, ",  ", sTP);
               if (ObjectFind(label2) == 0)
                  ObjectDelete(label2);
               if (ObjectCreate(label2, OBJ_ARROW, 0, TimeServer(), takeProfit)) {
                  ObjectSet(label2, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE  );
                  ObjectSet(label2, OBJPROP_COLOR,     CLR_OPEN_TAKEPROFIT);
               }
            }
            else sTP = "";

            // StopLoss anzeigen
            if (stopLoss != NULL) {
               sSL    = StringConcatenate("SL: ", NumberToStr(stopLoss, PriceFormat));
               label3 = StringConcatenate(label1, ",  ", sSL);
               if (ObjectFind(label3) == 0)
                  ObjectDelete(label3);
               if (ObjectCreate(label3, OBJ_ARROW, 0, TimeServer(), stopLoss)) {
                  ObjectSet(label3, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
                  ObjectSet(label3, OBJPROP_COLOR,     CLR_OPEN_STOPLOSS);
               }
            }
            else sSL = "";

            // Order anzeigen
            if (ObjectFind(label1) == 0)
               ObjectDelete(label1);
            if (ObjectCreate(label1, OBJ_ARROW, 0, openTime, openPrice)) {
               ObjectSet(label1, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN);
               ObjectSet(label1, OBJPROP_COLOR,     colors[type]    );
               ObjectSetText(label1, StringConcatenate(sTP, "   ", sSL));
            }
         }
         n++;
      }
      return(n);
   }


   // (2) mode.extern.notrading
   if (mode.extern.notrading) {
      orders = ArraySize(external.open.ticket);

      for (i=0; i < orders; i++) {
         // Daten auslesen
         ticket     =                 external.open.ticket    [i];
         type       =                 external.open.type      [i];
         lots       =                 external.open.lots      [i];
         openTime   = FxtToServerTime(external.open.openTime  [i]);
         openPrice  =                 external.open.openPrice [i];
         takeProfit =                 external.open.takeProfit[i];
         stopLoss   =                 external.open.stopLoss  [i];

         // Hauptlabel erstellen
         label1 = StringConcatenate("#", ticket, " ", types[type], " ", DoubleToStr(lots, 2), " at ", NumberToStr(openPrice, SubPipPriceFormat));

         // TakeProfit anzeigen
         if (takeProfit != NULL) {
            sTP    = StringConcatenate("TP: ", NumberToStr(takeProfit, SubPipPriceFormat));
            label2 = StringConcatenate(label1, ",  ", sTP);
            if (ObjectFind(label2) == 0)
               ObjectDelete(label2);
            if (ObjectCreate(label2, OBJ_ARROW, 0, TimeServer(), takeProfit)) {
               ObjectSet(label2, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE  );
               ObjectSet(label2, OBJPROP_COLOR,     CLR_OPEN_TAKEPROFIT);
            }
         }
         else sTP = "";

         // StopLoss anzeigen
         if (stopLoss != NULL) {
            sSL    = StringConcatenate("SL: ", NumberToStr(stopLoss, SubPipPriceFormat));
            label3 = StringConcatenate(label1, ",  ", sSL);
            if (ObjectFind(label3) == 0)
               ObjectDelete(label3);
            if (ObjectCreate(label3, OBJ_ARROW, 0, TimeServer(), stopLoss)) {
               ObjectSet(label3, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
               ObjectSet(label3, OBJPROP_COLOR,     CLR_OPEN_STOPLOSS);
            }
         }
         else sSL = "";

         // Order anzeigen
         if (ObjectFind(label1) == 0)
            ObjectDelete(label1);
         if (ObjectCreate(label1, OBJ_ARROW, 0, openTime, openPrice)) {
            ObjectSet(label1, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN);
            ObjectSet(label1, OBJPROP_COLOR,     colors[type]    );
            ObjectSetText(label1, StringConcatenate(sTP, "   ", sSL));
         }
      }
      return(orders);
   }


   // (3) mode.remote.trading
   if (mode.remote.trading) {
      orders = ArrayRange(lfxOrders, 0);

      for (i=0, n=0; i < orders; i++) {
         if (!lfxOrders.bCache[i][I_BC.isPendingOrder]) /*&&*/ if (!lfxOrders.bCache[i][I_BC.isOpenPosition])
            continue;

         // Daten auslesen
         ticket     = lfxOrders.iCache[i][I_IC.ticket];
         type       =                     los.Type           (lfxOrders, i);
         units      =                     los.Units          (lfxOrders, i);
         openTime   = FxtToServerTime(Abs(los.OpenTime       (lfxOrders, i)));
         openPrice  =                     los.OpenPrice      (lfxOrders, i);
         takeProfit =                     los.TakeProfitPrice(lfxOrders, i);
         stopLoss   =                     los.StopLossPrice  (lfxOrders, i);
         comment    =                     los.Comment        (lfxOrders, i);

         if (type > OP_SELL) {
            // Pending-Order
            label1 = StringConcatenate("#", ticket, " ", types[type], " ", DoubleToStr(units, 1), " at ", NumberToStr(openPrice, PriceFormat));

            // Order anzeigen
            if (ObjectFind(label1) == 0)
               ObjectDelete(label1);
            if (ObjectCreate(label1, OBJ_ARROW, 0, TimeServer(), openPrice)) {
               ObjectSet(label1, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN);
               ObjectSet(label1, OBJPROP_COLOR,     CLR_PENDING_OPEN);
            }
         }
         else {
            // offene Position
            label1 = StringConcatenate("#", ticket, " ", types[type], " ", DoubleToStr(units, 1), " at ", NumberToStr(openPrice, PriceFormat));

            // TakeProfit anzeigen                                   // TODO: !!! TP fixen, wenn tpValue oder tpPercent angegeben sind
            if (takeProfit != NULL) {
               sTP    = StringConcatenate("TP: ", NumberToStr(takeProfit, PriceFormat));
               label2 = StringConcatenate(label1, ",  ", sTP);
               if (ObjectFind(label2) == 0)
                  ObjectDelete(label2);
               if (ObjectCreate(label2, OBJ_ARROW, 0, TimeServer(), takeProfit)) {
                  ObjectSet(label2, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE  );
                  ObjectSet(label2, OBJPROP_COLOR,     CLR_OPEN_TAKEPROFIT);
               }
            }
            else sTP = "";

            // StopLoss anzeigen                                     // TODO: !!! SL fixen, wenn slValue oder slPercent angegeben sind
            if (stopLoss != NULL) {
               sSL    = StringConcatenate("SL: ", NumberToStr(stopLoss, PriceFormat));
               label3 = StringConcatenate(label1, ",  ", sSL);
               if (ObjectFind(label3) == 0)
                  ObjectDelete(label3);
               if (ObjectCreate(label3, OBJ_ARROW, 0, TimeServer(), stopLoss)) {
                  ObjectSet(label3, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
                  ObjectSet(label3, OBJPROP_COLOR,     CLR_OPEN_STOPLOSS);
               }
            }
            else sSL = "";

            // Order anzeigen
            if (ObjectFind(label1) == 0)
               ObjectDelete(label1);
            if (ObjectCreate(label1, OBJ_ARROW, 0, openTime, openPrice)) {
               ObjectSet(label1, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN);
               ObjectSet(label1, OBJPROP_COLOR,     colors[type]    );
               if (StringStartsWith(comment, "#")) comment = StringConcatenate(lfxCurrency, ".", StrToInteger(StringRight(comment, -1)));
               else                                comment = "";
               ObjectSetText(label1, StringTrim(StringConcatenate(comment, "   ", sTP, "   ", sSL)));
            }
         }
         n++;
      }
      return(n);
   }

   return(_EMPTY(catch("ShowOpenOrders(1)  unreachable code reached", ERR_RUNTIME_ERROR)));
}


/**
 * Liest den im Chart gespeicherten aktuellen OpenOrder-Anzeigestatus aus.
 *
 * @return bool - Status: ON/OFF
 */
bool GetOpenOrderDisplayStatus() {
   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".OpenOrderDisplay.status";
   if (ObjectFind(label) != -1)
      return(StrToInteger(ObjectDescription(label)) != 0);
   return(false);
}


/**
 * Speichert den angegebenen OpenOrder-Anzeigestatus im Chart.
 *
 * @param  bool status - Status
 *
 * @return bool - Erfolgsstatus
 */
bool SetOpenOrderDisplayStatus(bool status) {
   status = status!=0;

   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".OpenOrderDisplay.status";
   if (ObjectFind(label) == -1)
      ObjectCreate(label, OBJ_LABEL, 0, 0, 0);

   ObjectSet    (label, OBJPROP_XDISTANCE, -1000);                   // Label in unsichtbaren Bereich setzen
   ObjectSetText(label, ""+ status, 0);

   return(!catch("SetOpenOrderDisplayStatus(1)"));
}


/**
 * Schaltet die Anzeige der Trade-History ein/aus.
 *
 * @return bool - Erfolgsstatus
 */
bool ToggleTradeHistory() {
   // aktuellen Anzeigestatus aus Chart auslesen und umschalten: ON/OFF
   bool status = !GetTradeHistoryDisplayStatus();

   // neuer Status ON: Trade-History anzeigen
   if (status) {
      int trades = ShowTradeHistory();
      if (trades == -1)
         return(false);
      if (!trades) {                                                 // ohne Trade-History bleiben Anzeige und Status unver�ndert
         status = false;
         PlaySoundEx("Plonk.wav");                                   // Plonk!!!
      }
   }

   // neuer Status OFF: Chartobjekte der Trade-History l�schen
   else {
      for (int i=ObjectsTotal()-1; i >= 0; i--) {
         string name = ObjectName(i);
         if (StringGetChar(name, 0) == '#') {
            if (ObjectType(name) == OBJ_ARROW) {
               int arrow = ObjectGet(name, OBJPROP_ARROWCODE);
               color clr = ObjectGet(name, OBJPROP_COLOR    );
               if (arrow == SYMBOL_ORDEROPEN)
                  if (clr!=CLR_CLOSED_LONG) /*&&*/ if (clr!=CLR_CLOSED_SHORT)
                     continue;
               if (arrow == SYMBOL_ORDERCLOSE)
                  if (clr!=CLR_CLOSE)
                     continue;
               ObjectDelete(name);
            }
            else if (ObjectType(name) == OBJ_TREND) {
               ObjectDelete(name);
            }
         }
      }
   }

   // neuen Anzeigestatus im Chart speichern
   SetTradeHistoryDisplayStatus(status);

   if (This.IsTesting())
      WindowRedraw();
   return(!catch("ToggleTradeHistory(1)"));
}


/**
 * Liest den im Chart gespeicherten aktuellen TradeHistory-Anzeigestatus aus.
 *
 * @return bool - Status: ON/OFF
 */
bool GetTradeHistoryDisplayStatus() {
   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".TradeHistoryDisplay.status";
   if (ObjectFind(label) != -1)
      return(StrToInteger(ObjectDescription(label)) != 0);
   return(false);
}


/**
 * Speichert den angegebenen TradeHistory-Anzeigestatus im Chart.
 *
 * @param  bool status - Status
 *
 * @return bool - Erfolgsstatus
 */
bool SetTradeHistoryDisplayStatus(bool status) {
   status = status!=0;

   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".TradeHistoryDisplay.status";
   if (ObjectFind(label) == -1)
      ObjectCreate(label, OBJ_LABEL, 0, 0, 0);

   ObjectSet    (label, OBJPROP_XDISTANCE, -1000);                   // Label in unsichtbaren Bereich setzen
   ObjectSetText(label, ""+ status, 0);

   return(!catch("SetTradeHistoryDisplayStatus(1)"));
}


/**
 * Zeigt die verf�gbare Trade-History an.
 *
 * @return int - Anzahl der angezeigten geschlossenen Positionen oder -1 (EMPTY), falls ein Fehler auftrat.
 */
int ShowTradeHistory() {
   int      orders, ticket, type, markerColors[]={CLR_CLOSED_LONG, CLR_CLOSED_SHORT}, lineColors[]={Blue, Red};
   datetime openTime, closeTime;
   double   lots, units, openPrice, closePrice, openEquity, profit;
   string   sOpenPrice, sClosePrice, comment, text, openLabel, lineLabel, closeLabel, sTypes[]={"buy", "sell"};


   // (1) Anzeigekonfiguration auslesen
   string mqlDir  = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = TerminalPath() + mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.alias +"_config.ini";
   string section = "Charts";
   string key     = "TradeHistory.ConnectOrders";

   bool drawConnectors = GetIniBool(file, section, key, GetLocalConfigBool(section, key, true));  // Account- �berschreibt Terminal-Konfiguration (default = true)


   // (2) mode.intern.trading
   if (mode.intern.trading) {
      // (2.1) Sortierschl�ssel aller geschlossenen Positionen auslesen und nach {CloseTime, OpenTime, Ticket} sortieren
      orders = OrdersHistoryTotal();
      int sortKeys[][3];                                                // {CloseTime, OpenTime, Ticket}
      ArrayResize(sortKeys, orders);

      for (int n, i=0; i < orders; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {            // FALSE: w�hrend des Auslesens wurde der Anzeigezeitraum der History verk�rzt
            orders = i;
            break;
         }
         if (OrderSymbol() != Symbol()) continue;
         if (OrderType()   >  OP_SELL ) continue;

         sortKeys[n][0] = OrderCloseTime();
         sortKeys[n][1] = OrderOpenTime();
         sortKeys[n][2] = OrderTicket();
         n++;
      }
      orders = n;
      ArrayResize(sortKeys, orders);
      SortClosedTickets(sortKeys);

      // (2.2) Tickets sortiert einlesen
      int      tickets    []; ArrayResize(tickets    , 0);
      int      types      []; ArrayResize(types      , 0);
      double   lotSizes   []; ArrayResize(lotSizes   , 0);
      datetime openTimes  []; ArrayResize(openTimes  , 0);
      datetime closeTimes []; ArrayResize(closeTimes , 0);
      double   openPrices []; ArrayResize(openPrices , 0);
      double   closePrices[]; ArrayResize(closePrices, 0);
      double   commissions[]; ArrayResize(commissions, 0);
      double   swaps      []; ArrayResize(swaps      , 0);
      double   profits    []; ArrayResize(profits    , 0);
      string   comments   []; ArrayResize(comments   , 0);

      for (i=0; i < orders; i++) {
         if (!SelectTicket(sortKeys[i][2], "ShowTradeHistory(1)"))
            return(-1);
         ArrayPushInt   (tickets    , OrderTicket()    );
         ArrayPushInt   (types      , OrderType()      );
         ArrayPushDouble(lotSizes   , OrderLots()      );
         ArrayPushInt   (openTimes  , OrderOpenTime()  );
         ArrayPushInt   (closeTimes , OrderCloseTime() );
         ArrayPushDouble(openPrices , OrderOpenPrice() );
         ArrayPushDouble(closePrices, OrderClosePrice());
         ArrayPushDouble(commissions, OrderCommission());
         ArrayPushDouble(swaps      , OrderSwap()      );
         ArrayPushDouble(profits    , OrderProfit()    );
         ArrayPushString(comments   , OrderComment()   );
      }

      // (2.3) Hedges korrigieren: alle Daten dem ersten Ticket zuordnen und hedgendes Ticket verwerfen
      for (i=0; i < orders; i++) {
         if (tickets[i] && EQ(lotSizes[i], 0)) {                     // lotSize = 0: Hedge-Position

            // TODO: Pr�fen, wie sich OrderComment() bei custom comments verh�lt.
            if (!StringStartsWithI(comments[i], "close hedge by #"))
               return(_EMPTY(catch("ShowTradeHistory(3)  #"+ tickets[i] +" - unknown comment for assumed hedging position: \""+ comments[i] +"\"", ERR_RUNTIME_ERROR)));

            // Gegenst�ck suchen
            ticket = StrToInteger(StringSubstr(comments[i], 16));
            for (n=0; n < orders; n++) {
               if (tickets[n] == ticket)
                  break;
            }
            if (n == orders) return(_EMPTY(catch("ShowTradeHistory(4)  cannot find counterpart for hedging position #"+ tickets[i] +": \""+ comments[i] +"\"", ERR_RUNTIME_ERROR)));
            if (i == n     ) return(_EMPTY(catch("ShowTradeHistory(5)  both hedged and hedging position have the same ticket #"+ tickets[i] +": \""+ comments[i] +"\"", ERR_RUNTIME_ERROR)));

            int first  = Min(i, n);
            int second = Max(i, n);

            // Orderdaten korrigieren
            if (i == first) {
               lotSizes   [first] = lotSizes   [second];             // alle Transaktionsdaten in der ersten Order speichern
               commissions[first] = commissions[second];
               swaps      [first] = swaps      [second];
               profits    [first] = profits    [second];
            }
            closeTimes [first] = openTimes [second];
            closePrices[first] = openPrices[second];
            tickets   [second] = NULL;                               // hedgendes Ticket als verworfen markieren
         }
      }

      // (2.4) Orders anzeigen
      for (i=0; i < orders; i++) {
         if (!tickets[i])                                            // verworfene Hedges �berspringen
            continue;
         sOpenPrice  = NumberToStr(openPrices [i], PriceFormat);
         sClosePrice = NumberToStr(closePrices[i], PriceFormat);

         // Open-Marker anzeigen
         openLabel = StringConcatenate("#", tickets[i], " ", sTypes[types[i]], " ", DoubleToStr(lotSizes[i], 2), " at ", sOpenPrice);
         if (ObjectFind(openLabel) == 0)
            ObjectDelete(openLabel);
         if (ObjectCreate(openLabel, OBJ_ARROW, 0, openTimes[i], openPrices[i])) {
            ObjectSet(openLabel, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN      );
            ObjectSet(openLabel, OBJPROP_COLOR    , markerColors[types[i]]);
         }

         // Trendlinie anzeigen
         if (drawConnectors) {
            lineLabel = StringConcatenate("#", tickets[i], " ", sOpenPrice, " -> ", sClosePrice);
            if (ObjectFind(lineLabel) == 0)
               ObjectDelete(lineLabel);
            if (ObjectCreate(lineLabel, OBJ_TREND, 0, openTimes[i], openPrices[i], closeTimes[i], closePrices[i])) {
               ObjectSet(lineLabel, OBJPROP_RAY  , false               );
               ObjectSet(lineLabel, OBJPROP_STYLE, STYLE_DOT           );
               ObjectSet(lineLabel, OBJPROP_COLOR, lineColors[types[i]]);
               ObjectSet(lineLabel, OBJPROP_BACK , true                );
            }
         }

         // Close-Marker anzeigen                                    // "#1 buy 0.10 GBPUSD at 1.53024 close[ by tester] at 1.52904"
         closeLabel = StringConcatenate(openLabel, " close at ", sClosePrice);
         if (ObjectFind(closeLabel) == 0)
            ObjectDelete(closeLabel);
         if (ObjectCreate(closeLabel, OBJ_ARROW, 0, closeTimes[i], closePrices[i])) {
            ObjectSet(closeLabel, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
            ObjectSet(closeLabel, OBJPROP_COLOR    , CLR_CLOSE        );
         }
         n++;
      }
      return(n);
   }


   // (3) mode.extern.notrading
   if (mode.extern.notrading) {
      orders = ArraySize(external.closed.ticket);

      for (i=0; i < orders; i++) {
         // Daten auslesen
         ticket     =                 external.closed.ticket    [i];
         type       =                 external.closed.type      [i];
         lots       =                 external.closed.lots      [i];
         openTime   = FxtToServerTime(external.closed.openTime  [i]);
         openPrice  =                 external.closed.openPrice [i];  sOpenPrice  = NumberToStr(openPrice, PriceFormat);
         closeTime  = FxtToServerTime(external.closed.closeTime [i]);
         closePrice =                 external.closed.closePrice[i];  sClosePrice = NumberToStr(closePrice, PriceFormat);

         // Open-Marker anzeigen
         openLabel = StringConcatenate("#", ticket, " ", sTypes[type], " ", DoubleToStr(lots, 2), " at ", sOpenPrice);
         if (ObjectFind(openLabel) == 0)
            ObjectDelete(openLabel);
         if (ObjectCreate(openLabel, OBJ_ARROW, 0, openTime, openPrice)) {
            ObjectSet(openLabel, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN  );
            ObjectSet(openLabel, OBJPROP_COLOR    , markerColors[type]);
         }

         // Trendlinie anzeigen
         if (drawConnectors) {
            lineLabel = StringConcatenate("#", ticket, " ", sOpenPrice, " -> ", sClosePrice);
            if (ObjectFind(lineLabel) == 0)
               ObjectDelete(lineLabel);
            if (ObjectCreate(lineLabel, OBJ_TREND, 0, openTime, openPrice, closeTime, closePrice)) {
               ObjectSet(lineLabel, OBJPROP_RAY  , false           );
               ObjectSet(lineLabel, OBJPROP_STYLE, STYLE_DOT       );
               ObjectSet(lineLabel, OBJPROP_COLOR, lineColors[type]);
               ObjectSet(lineLabel, OBJPROP_BACK , true            );
            }
         }

         // Close-Marker anzeigen                                    // "#1 buy 0.10 GBPUSD at 1.53024 close[ by tester] at 1.52904"
         closeLabel = StringConcatenate(openLabel, " close at ", sClosePrice);
         if (ObjectFind(closeLabel) == 0)
            ObjectDelete(closeLabel);
         if (ObjectCreate(closeLabel, OBJ_ARROW, 0, closeTime, closePrice)) {
            ObjectSet(closeLabel, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
            ObjectSet(closeLabel, OBJPROP_COLOR    , CLR_CLOSE        );
         }
      }
      return(orders);
   }


   // (4) mode.remote.trading
   if (mode.remote.trading) {
      orders = ArrayRange(lfxOrders, 0);

      for (i=0, n=0; i < orders; i++) {
         if (!los.IsClosedPosition(lfxOrders, i)) continue;

         ticket      =                     los.Ticket    (lfxOrders, i);
         type        =                     los.Type      (lfxOrders, i);
         units       =                     los.Units     (lfxOrders, i);
         openTime    =     FxtToServerTime(los.OpenTime  (lfxOrders, i));
         openPrice   =                     los.OpenPrice (lfxOrders, i);
         openEquity  =                     los.OpenEquity(lfxOrders, i);
         closeTime   = FxtToServerTime(Abs(los.CloseTime (lfxOrders, i)));
         closePrice  =                     los.ClosePrice(lfxOrders, i);
         profit      =                     los.Profit    (lfxOrders, i);
         comment     =                     los.Comment   (lfxOrders, i);

         sOpenPrice  = NumberToStr(openPrice,  PriceFormat);
         sClosePrice = NumberToStr(closePrice, PriceFormat);

         // Open-Marker anzeigen
         openLabel = StringConcatenate("#", ticket, " ", sTypes[type], " ", DoubleToStr(units, 1), " at ", sOpenPrice);
         if (ObjectFind(openLabel) == 0)
            ObjectDelete(openLabel);
         if (ObjectCreate(openLabel, OBJ_ARROW, 0, openTime, openPrice)) {
            ObjectSet    (openLabel, OBJPROP_ARROWCODE, SYMBOL_ORDEROPEN  );
            ObjectSet    (openLabel, OBJPROP_COLOR    , markerColors[type]);
               if (positions.absoluteProfits || !openEquity) text = ifString(profit > 0, "+", "") + DoubleToStr(profit, 2);
               else                                          text = ifString(profit > 0, "+", "") + DoubleToStr(profit/openEquity * 100, 2) +"%";
            ObjectSetText(openLabel, text);
         }

         // Trendlinie anzeigen
         if (drawConnectors) {
            lineLabel = StringConcatenate("#", ticket, " ", sOpenPrice, " -> ", sClosePrice);
            if (ObjectFind(lineLabel) == 0)
               ObjectDelete(lineLabel);
            if (ObjectCreate(lineLabel, OBJ_TREND, 0, openTime, openPrice, closeTime, closePrice)) {
               ObjectSet(lineLabel, OBJPROP_RAY  , false           );
               ObjectSet(lineLabel, OBJPROP_STYLE, STYLE_DOT       );
               ObjectSet(lineLabel, OBJPROP_COLOR, lineColors[type]);
               ObjectSet(lineLabel, OBJPROP_BACK , true            );
            }
         }

         // Close-Marker anzeigen                                    // "#1 buy 0.10 GBPUSD at 1.53024 close[ by tester] at 1.52904"
         closeLabel = StringConcatenate(openLabel, " close at ", sClosePrice);
         if (ObjectFind(closeLabel) == 0)
            ObjectDelete(closeLabel);
         if (ObjectCreate(closeLabel, OBJ_ARROW, 0, closeTime, closePrice)) {
            ObjectSet    (closeLabel, OBJPROP_ARROWCODE, SYMBOL_ORDERCLOSE);
            ObjectSet    (closeLabel, OBJPROP_COLOR    , CLR_CLOSE        );
            ObjectSetText(closeLabel, text);
         }
         n++;
      }
      return(n);
   }

   return(_EMPTY(catch("ShowTradeHistory(6)  unreachable code reached", ERR_RUNTIME_ERROR)));
}


/**
 * Schaltet die Anzeige der P/L-Betr�ge der Positionen zwischen "absolut" und "prozentual" um.
 *
 * @return bool - Erfolgsstatus
 */
bool Positions.ToggleProfits() {
   // aktuellen Anzeigestatus umschalten
   positions.absoluteProfits = !positions.absoluteProfits;

   // Positionsanzeige aktualisieren
   if (!UpdatePositions()) return(false);


   // ggf. TradeHistory aktualisieren
   if (GetTradeHistoryDisplayStatus())
      ShowTradeHistory();

   return(!catch("Positions.ToggleProfits(1)"));
}


/**
 * Schaltet die Assets-under-Management-Anzeige ein/aus.
 *
 * @return bool - Erfolgsstatus
 */
bool ToggleAuM() {
   // aktuellen Anzeigestatus aus Chart auslesen und umschalten: ON/OFF
   bool status = !GetAuMDisplayStatus();

   // Status ON
   if (status) {
      aum.value = RefreshExternalAssets(tradeAccount.company, ifString(mode.extern.notrading, tradeAccount.alias, tradeAccount.number));
      string strAum = " ";

      if (mode.intern.trading) {
         strAum = ifString(!aum.value, "Balance:  ", "Assets:  ") + DoubleToStr(AccountBalance() + aum.value, 2) +" "+ AccountCurrency();
      }
      else if (mode.extern.notrading) {
         strAum = "Assets:  " + ifString(!aum.value, "n/a", DoubleToStr(aum.value, 2) +" "+ AccountCurrency());
      }
      else /*mode.remote.trading*/{
         status = false;                                             // not yet implemented
         PlaySoundEx("Plonk.wav");                                   // Plonk!!!
      }
      ObjectSetText(label.aum, strAum, 9, "Tahoma", SlateGray);
   }

   // Status OFF
   else {
      ObjectSetText(label.aum, " ", 1);
   }

   int error = GetLastError();
   if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)  // bei offenem Properties-Dialog oder Object::onDrag()
      return(!catch("ToggleAuM(1)", error));

   // Anzeigestatus im Chart speichern
   SetAuMDisplayStatus(status);

   if (This.IsTesting())
      WindowRedraw();
   return(!catch("ToggleAuM(2)"));
}


/**
 * Liest den im Chart gespeicherten aktuellen AuM-Anzeigestatus aus.
 *
 * @return bool - Status: ON/OFF
 */
bool GetAuMDisplayStatus() {
   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".AuMDisplay.status";
   if (ObjectFind(label) != -1)
      return(StrToInteger(ObjectDescription(label)) != 0);
   return(false);
}


/**
 * Speichert den angegebenen AuM-Anzeigestatus im Chart.
 *
 * @param  bool status - Status
 *
 * @return bool - Erfolgsstatus
 */
bool SetAuMDisplayStatus(bool status) {
   status = status!=0;

   // TODO: Status statt im Chart im Fenster lesen/schreiben
   string label = __NAME__ +".AuMDisplay.status";
   if (ObjectFind(label) == -1)
      ObjectCreate(label, OBJ_LABEL, 0, 0, 0);

   ObjectSet    (label, OBJPROP_XDISTANCE, -1000);                   // Label in unsichtbaren Bereich setzen
   ObjectSetText(label, ""+ status, 0);

   return(!catch("SetAuMDisplayStatus(1)"));
}


/**
 * Erzeugt die einzelnen ChartInfo-Label.
 *
 * @return bool - Erfolgsstatus
 */
bool CreateLabels() {
   // Label definieren
   label.instrument   = StringReplace(label.instrument  , "${__NAME__}", __NAME__);
   label.ohlc         = StringReplace(label.ohlc        , "${__NAME__}", __NAME__);
   label.price        = StringReplace(label.price       , "${__NAME__}", __NAME__);
   label.spread       = StringReplace(label.spread      , "${__NAME__}", __NAME__);
   label.aum          = StringReplace(label.aum         , "${__NAME__}", __NAME__);
   label.position     = StringReplace(label.position    , "${__NAME__}", __NAME__);
   label.unitSize     = StringReplace(label.unitSize    , "${__NAME__}", __NAME__);
   label.orderCounter = StringReplace(label.orderCounter, "${__NAME__}", __NAME__);
   label.tradeAccount = StringReplace(label.tradeAccount, "${__NAME__}", __NAME__);
   label.time         = StringReplace(label.time        , "${__NAME__}", __NAME__);
   label.stopoutLevel = StringReplace(label.stopoutLevel, "${__NAME__}", __NAME__);


   // Instrument-Label: Anzeige wird sofort (und nur hier) gesetzt
   int build = GetTerminalBuild();
   if (build <= 509) {                                                                    // Builds gr��er 509 haben oben links eine {Symbol,Period}-Anzeige, die das
      if (ObjectFind(label.instrument) == 0)                                              // Label �berlagert und sich nicht ohne weiteres ausblenden l��t.
         ObjectDelete(label.instrument);
      if (ObjectCreate(label.instrument, OBJ_LABEL, 0, 0, 0)) {
         ObjectSet    (label.instrument, OBJPROP_CORNER, CORNER_TOP_LEFT);
         ObjectSet    (label.instrument, OBJPROP_XDISTANCE, ifInt(build < 479, 4, 13));   // Builds gr��er 478 haben oben links einen Pfeil f�rs One-Click-Trading,
         ObjectSet    (label.instrument, OBJPROP_YDISTANCE, ifInt(build < 479, 1,  3));   // das Instrument-Label wird dort entsprechend versetzt positioniert.
         ObjectRegister(label.instrument);
      }
      else GetLastError();
      string name = GetLongSymbolNameOrAlt(Symbol(), GetSymbolName(Symbol()));
      if      (StringEndsWithI(Symbol(), "_ask")) name = StringConcatenate(name, " (Ask)");
      else if (StringEndsWithI(Symbol(), "_avg")) name = StringConcatenate(name, " (Avg)");
      ObjectSetText(label.instrument, name, 9, "Tahoma Fett", Black);
   }


   // OHLC-Label
   if (ObjectFind(label.ohlc) == 0)
      ObjectDelete(label.ohlc);
   if (ObjectCreate(label.ohlc, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.ohlc, OBJPROP_CORNER, CORNER_TOP_LEFT);
      ObjectSet    (label.ohlc, OBJPROP_XDISTANCE, 110);
      ObjectSet    (label.ohlc, OBJPROP_YDISTANCE, 4  );
      ObjectSetText(label.ohlc, " ", 1);
      ObjectRegister(label.ohlc);
   }
   else GetLastError();


   // Price-Label
   if (ObjectFind(label.price) == 0)
      ObjectDelete(label.price);
   if (ObjectCreate(label.price, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.price, OBJPROP_CORNER, CORNER_TOP_RIGHT);
      ObjectSet    (label.price, OBJPROP_XDISTANCE, 14);
      ObjectSet    (label.price, OBJPROP_YDISTANCE, 15);
      ObjectSetText(label.price, " ", 1);
      ObjectRegister(label.price);
   }
   else GetLastError();


   // Spread-Label
   if (ObjectFind(label.spread) == 0)
      ObjectDelete(label.spread);
   if (ObjectCreate(label.spread, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.spread, OBJPROP_CORNER, CORNER_TOP_RIGHT);
      ObjectSet    (label.spread, OBJPROP_XDISTANCE, 33);
      ObjectSet    (label.spread, OBJPROP_YDISTANCE, 38);
      ObjectSetText(label.spread, " ", 1);
      ObjectRegister(label.spread);
   }
   else GetLastError();


   // OrderCounter-Label
   if (ObjectFind(label.orderCounter) == 0)
      ObjectDelete(label.orderCounter);
   if (ObjectCreate(label.orderCounter, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.orderCounter, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
      ObjectSet    (label.orderCounter, OBJPROP_XDISTANCE, 380);
      ObjectSet    (label.orderCounter, OBJPROP_YDISTANCE,   9);
      ObjectSetText(label.orderCounter, " ", 1);
      ObjectRegister(label.orderCounter);
   }
   else GetLastError();


   // Assets-under-Management-Label
   if (ObjectFind(label.aum) == 0)
      ObjectDelete(label.aum);
   if (ObjectCreate(label.aum, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.aum, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
      ObjectSet    (label.aum, OBJPROP_XDISTANCE, 240);
      ObjectSet    (label.aum, OBJPROP_YDISTANCE,   9);
      ObjectSetText(label.aum, " ", 1);
      ObjectRegister(label.aum);
   }
   else GetLastError();


   // Gesamt-Positions-Label
   if (ObjectFind(label.position) == 0)
      ObjectDelete(label.position);
   if (ObjectCreate(label.position, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.position, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
      ObjectSet    (label.position, OBJPROP_XDISTANCE,  9);
      ObjectSet    (label.position, OBJPROP_YDISTANCE, 29);
      ObjectSetText(label.position, " ", 1);
      ObjectRegister(label.position);
   }
   else GetLastError();


   // UnitSize-Label
   if (ObjectFind(label.unitSize) == 0)
      ObjectDelete(label.unitSize);
   if (ObjectCreate(label.unitSize, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.unitSize, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
      ObjectSet    (label.unitSize, OBJPROP_XDISTANCE, 9);
      ObjectSet    (label.unitSize, OBJPROP_YDISTANCE, 9);
      ObjectSetText(label.unitSize, " ", 1);
      ObjectRegister(label.unitSize);
   }
   else GetLastError();


   // TradeAccount-Label
   if (ObjectFind(label.tradeAccount) == 0)
      ObjectDelete(label.tradeAccount);
   if (ObjectCreate(label.tradeAccount, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet    (label.tradeAccount, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
      ObjectSet    (label.tradeAccount, OBJPROP_XDISTANCE, 6);
      ObjectSet    (label.tradeAccount, OBJPROP_YDISTANCE, 4);
      ObjectSetText(label.tradeAccount, " ", 1);
      ObjectRegister(label.tradeAccount);
   }
   else GetLastError();


   // Time-Label: nur im Tester bei VisualMode=On
   if (IsVisualModeFix()) {
      if (ObjectFind(label.time) == 0)
         ObjectDelete(label.time);
      if (ObjectCreate(label.time, OBJ_LABEL, 0, 0, 0)) {
         ObjectSet    (label.time, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
         ObjectSet    (label.time, OBJPROP_XDISTANCE,  9);
         ObjectSet    (label.time, OBJPROP_YDISTANCE, 49);
         ObjectSetText(label.time, " ", 1);
         ObjectRegister(label.time);
      }
      else GetLastError();
   }

   return(!catch("CreateLabels(1)"));
}


/**
 * Aktualisiert die Kursanzeige oben rechts.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePrice() {
   static string priceFormat;
   if (!StringLen(priceFormat))
      priceFormat = StringConcatenate(",,", PriceFormat);

   double price;

   if (!Bid) {                                                                // Symbol (noch) nicht subscribed (Start, Account- oder Templatewechsel) oder Offline-Chart
      price = RoundEx(Close[0], Digits);                                      // Bar-Daten in der History k�nnen u.U. unnormalisiert sein
   }                                                                          // (z.B. wenn sie nicht von MetaTrader erstellt wurden)
   else {
      switch (appliedPrice) {
         case PRICE_BID   : price =  Bid;                                   break;
         case PRICE_ASK   : price =  Ask;                                   break;
         case PRICE_MEDIAN: price = NormalizeDouble((Bid + Ask)/2, Digits); break;
      }
   }
   ObjectSetText(label.price, NumberToStr(price, priceFormat), 13, "Microsoft Sans Serif", Black);

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                            // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdatePrice(1)", error));
}


/**
 * Aktualisiert die Spreadanzeige.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateSpread() {
   if (!Bid)                                                                  // Symbol (noch) nicht subscribed (Start, Account- oder Templatewechsel) oder Offline-Chart
      return(true);

   string strSpread = DoubleToStr(MarketInfo(Symbol(), MODE_SPREAD)/PipPoints, Digits & 1);

   ObjectSetText(label.spread, strSpread, 9, "Tahoma", SlateGray);

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                            // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateSpread(1)", error));
}


/**
 * Aktualisiert die UnitSize-Anzeige unten rechts.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateUnitSize() {
   if (IsTesting())                                    return(true);          // Anzeige wird im Tester nicht ben�tigt
   if (!mm.ready) /*&&*/ if (!UpdateMoneyManagement()) return(_false(CheckLastError("UpdateUnitSize(1)->UpdateMoneyManagement()")));
   if (!mm.ready)                                      return(true);

   string strUnitSize;

   // Anzeige nur bei internem Account:                      V - Volatilit�t/Woche                      L - Leverage                                     Unitsize
   if (mode.intern.trading) strUnitSize = StringConcatenate("V", DoubleToStr(mm.defaultVola, 1), "%     L", DoubleToStr(mm.defaultLeverage, 1), "  =  ", NumberToStr(mm.defaultLots.normalized, ", .+"), " lot");
   else                     strUnitSize = " ";

   // Anzeige aktualisieren (!!! max. 63 Zeichen !!!)
   ObjectSetText(label.unitSize, strUnitSize, 9, "Tahoma", SlateGray);

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                            // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateUnitSize(1)", error));
}


/**
 * Aktualisiert die Positionsanzeigen unten rechts (Gesamtposition) und unten links (detaillierte Einzelpositionen).
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePositions() {
   if (!positions.analyzed ) /*&&*/ if (!AnalyzePositions()) return(false);
   if (!mode.remote.trading) /*&&*/ if (!mm.ready) {
      if (!UpdateMoneyManagement())                         return(false);
      if (!mm.ready )                                       return(true);
   }


   // (1) Gesamtpositionsanzeige unten rechts
   string strCurrentVola, strCurrentLeverage, strCurrentPosition;
   if      (!isPosition   ) strCurrentPosition = " ";
   else if (!totalPosition) strCurrentPosition = StringConcatenate("Position:   �", NumberToStr(longPosition, ", .+"), " lot (hedged)");
   else {
      // Leverage der aktuellen Position = MathAbs(totalPosition)/mm.unleveragedLots
      double currentLeverage;
      if (!mm.realEquity) currentLeverage = MathAbs(totalPosition)/((AccountEquity()-AccountCredit())/mm.lotValue);  // Workaround bei negativer AccountBalance:
      else                currentLeverage = MathAbs(totalPosition)/mm.unleveragedLots;                               // die unrealisierten Gewinne werden mit einbezogen !!!
      strCurrentLeverage = StringConcatenate("L", DoubleToStr(currentLeverage, 1), "      ");

      // Volatilit�t/Woche der aktuellen Position = aktueller Leverage * ATRwPct
      if (mm.ATRwPct != 0)
         strCurrentVola = StringConcatenate("V", DoubleToStr(mm.ATRwPct * 100 * currentLeverage, 1), "%     ");

      strCurrentPosition = StringConcatenate("Position:   " , strCurrentVola, strCurrentLeverage, NumberToStr(totalPosition, "+, .+"), " lot");
   }
   ObjectSetText(label.position, strCurrentPosition, 9, "Tahoma", SlateGray);

   int error = GetLastError();
   if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)  // bei offenem Properties-Dialog oder Object::onDrag()
      return(!catch("UpdatePositions(1)", error));


   // (2) PendingTickets-Marker unten rechts ein-/ausblenden
   string label = __NAME__+".PendingTickets";
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   if (isPendings) {
      if (ObjectCreate(label, OBJ_LABEL, 0, 0, 0)) {
         ObjectSet    (label, OBJPROP_CORNER, CORNER_BOTTOM_RIGHT);
         ObjectSet    (label, OBJPROP_XDISTANCE,                       12);
         ObjectSet    (label, OBJPROP_YDISTANCE, ifInt(isPosition, 48, 30));
         ObjectSetText(label, "n", 6, "Webdings", Orange);           // Webdings: runder Marker, orange="Notice"
         ObjectRegister(label);
      }
   }


   // (3) Einzelpositionsanzeige unten links
   static int  col.xShifts[], cols, percentCol, commentCol, yDist=3, lines;
   static bool lastAbsoluteProfits;
   if (!ArraySize(col.xShifts) || positions.absoluteProfits!=lastAbsoluteProfits) {
      if (positions.absoluteProfits) {
         // Spalten:         Type: Lots   BE:  BePrice   Profit: Amount Percent   Comment
         // col.xShifts[] = {20,   59,    135, 160,      226,    258,   345,      406};
         ArrayResize(col.xShifts, 8);
         col.xShifts[0] =  20;
         col.xShifts[1] =  59;
         col.xShifts[2] = 135;
         col.xShifts[3] = 160;
         col.xShifts[4] = 226;
         col.xShifts[5] = 258;
         col.xShifts[6] = 345;
         col.xShifts[7] = 406;
      }
      else {
         // Spalten:         Type: Lots   BE:  BePrice   Profit: Percent   Comment
         // col.xShifts[] = {20,   59,    135, 160,      226,    258,      319};
         ArrayResize(col.xShifts, 7);
         col.xShifts[0] =  20;
         col.xShifts[1] =  59;
         col.xShifts[2] = 135;
         col.xShifts[3] = 160;
         col.xShifts[4] = 226;
         col.xShifts[5] = 258;
         col.xShifts[6] = 319;
      }
      cols                = ArraySize(col.xShifts);
      percentCol          = cols - 2;
      commentCol          = cols - 1;
      lastAbsoluteProfits = positions.absoluteProfits;

      // nach (Re-)Initialisierung alle vorhandenen Zeilen l�schen
      while (lines > 0) {
         for (int col=0; col < 8; col++) {                           // alle Spalten testen: mit und ohne absoluten Betr�gen
            label = StringConcatenate(label.position, ".line", lines, "_col", col);
            if (ObjectFind(label) != -1)
               ObjectDelete(label);
         }
         lines--;
      }
   }
   int iePositions = ArrayRange(positions.iData, 0), positions;
   if (mode.remote.trading) positions = lfxOrders.openPositions;
   else                     positions = iePositions;

   // (3.1) zus�tzlich ben�tigte Zeilen hinzuf�gen
   while (lines < positions) {
      lines++;
      for (col=0; col < cols; col++) {
         label = StringConcatenate(label.position, ".line", lines, "_col", col);
         if (ObjectCreate(label, OBJ_LABEL, 0, 0, 0)) {
            ObjectSet    (label, OBJPROP_CORNER, CORNER_BOTTOM_LEFT);
            ObjectSet    (label, OBJPROP_XDISTANCE, col.xShifts[col]              );
            ObjectSet    (label, OBJPROP_YDISTANCE, yDist + (lines-1)*(positions.fontSize+8));
            ObjectSetText(label, " ", 1);
            ObjectRegister(label);
         }
         else GetLastError();
      }
   }

   // (3.2) nicht ben�tigte Zeilen l�schen
   while (lines > positions) {
      for (col=0; col < cols; col++) {
         label = StringConcatenate(label.position, ".line", lines, "_col", col);
         if (ObjectFind(label) != -1)
            ObjectDelete(label);
      }
      lines--;
   }

   // (3.3) Zeilen von unten nach oben schreiben: "{Type}: {Lots}   BE|Dist: {Price|Pips}   Profit: [{Amount} ]{Percent}   {Comment}"
   string sLotSize, sDistance, sBreakeven, sAdjustedProfit, sProfitPct, sComment;
   color  fontColor;
   int    line;


   // (4.1) Anzeige interne/externe Positionsdaten
   if (!mode.remote.trading) {
      for (int i=iePositions-1; i >= 0; i--) {
         line++;
         if      (positions.iData[i][I_CONFIG_TYPE  ] == CONFIG_VIRTUAL  ) fontColor = positions.fontColor.virtual;
         else if (positions.iData[i][I_POSITION_TYPE] == POSITION_HISTORY) fontColor = positions.fontColor.history;
         else if (mode.intern.trading)                                     fontColor = positions.fontColor.intern;
         else                                                              fontColor = positions.fontColor.extern;

         if (!positions.dData[i][I_ADJUSTED_PROFIT])     sAdjustedProfit = "";
         else                                            sAdjustedProfit = StringConcatenate(" (", DoubleToStr(positions.dData[i][I_ADJUSTED_PROFIT], 2), ")");

         if ( positions.iData[i][I_COMMENT_INDEX] == -1) sComment = " ";
         else                                            sComment = positions.config.comments[positions.iData[i][I_COMMENT_INDEX]];

         // Nur History
         if (positions.iData[i][I_POSITION_TYPE] == POSITION_HISTORY) {
            // "{Type}: {Lots}   BE|Dist: {Price|Pips}   Profit: [{Amount} ]{Percent}   {Comment}"
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col0"           ), typeDescriptions[positions.iData[i][I_POSITION_TYPE]],                   positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col1"           ), " ",                                                                     positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col2"           ), " ",                                                                     positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col3"           ), " ",                                                                     positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col4"           ), "Profit:",                                                               positions.fontSize, positions.fontName, fontColor);
            if (positions.absoluteProfits)
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col5"           ), DoubleToStr(positions.dData[i][I_FULL_PROFIT_ABS], 2) + sAdjustedProfit, positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", percentCol), DoubleToStr(positions.dData[i][I_FULL_PROFIT_PCT], 2) +"%",              positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", commentCol), sComment,                                                                positions.fontSize, positions.fontName, fontColor);
         }

         // Directional oder Hedged
         else {
            // "{Type}: {Lots}   BE|Dist: {Price|Pips}   Profit: [{Amount} ]{Percent}   {Comment}"
            // Hedged
            if (positions.iData[i][I_POSITION_TYPE] == POSITION_HEDGE) {
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col0"), typeDescriptions[positions.iData[i][I_POSITION_TYPE]],                           positions.fontSize, positions.fontName, fontColor);
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col1"),      NumberToStr(positions.dData[i][I_HEDGED_LOTS  ], ".+") +" lot",             positions.fontSize, positions.fontName, fontColor);
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col2"), "Dist:",                                                                         positions.fontSize, positions.fontName, fontColor);
                  if (!positions.dData[i][I_PIP_DISTANCE]) sDistance = "...";
                  else                                     sDistance = DoubleToStr(RoundFloor(positions.dData[i][I_PIP_DISTANCE], Digits-PipDigits), Digits-PipDigits) +" pip";
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col3"), sDistance,                                                                       positions.fontSize, positions.fontName, fontColor);
            }

            // Not Hedged
            else {
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col0"), typeDescriptions[positions.iData[i][I_POSITION_TYPE]],                           positions.fontSize, positions.fontName, fontColor);
                  if (!positions.dData[i][I_HEDGED_LOTS]) sLotSize = NumberToStr(positions.dData[i][I_DIRECTIONAL_LOTS], ".+");
                  else                                    sLotSize = NumberToStr(positions.dData[i][I_DIRECTIONAL_LOTS], ".+") +" �"+ NumberToStr(positions.dData[i][I_HEDGED_LOTS], ".+");
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col1"), sLotSize +" lot",                                                                positions.fontSize, positions.fontName, fontColor);
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col2"), "BE:",                                                                           positions.fontSize, positions.fontName, fontColor);
                  if (!positions.dData[i][I_BREAKEVEN_PRICE]) sBreakeven = "...";
                  else                                        sBreakeven = NumberToStr(positions.dData[i][I_BREAKEVEN_PRICE], PriceFormat);
               ObjectSetText(StringConcatenate(label.position, ".line", line, "_col3"), sBreakeven,                                                                      positions.fontSize, positions.fontName, fontColor);
            }

            // Hedged und Not-Hedged
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col4"           ), "Profit:",                                                               positions.fontSize, positions.fontName, fontColor);
            if (positions.absoluteProfits)
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col5"           ), DoubleToStr(positions.dData[i][I_FULL_PROFIT_ABS], 2) + sAdjustedProfit, positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", percentCol), DoubleToStr(positions.dData[i][I_FULL_PROFIT_PCT], 2) +"%",              positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", commentCol), sComment,                                                                positions.fontSize, positions.fontName, fontColor);
         }
      }
   }

   // (4.2) Anzeige Remote-Positionsdaten
   if (mode.remote.trading) {
      fontColor = positions.fontColor.remote;
      for (i=ArrayRange(lfxOrders, 0)-1; i >= 0; i--) {
         if (lfxOrders.bCache[i][I_BC.isOpenPosition]) {
            line++;
            // "{Type}: {Lots}   BE|Dist: {Price|Pips}   Profit: [{Amount} ]{Percent}   {Comment}"
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col0"           ), typeDescriptions[los.Type(lfxOrders, i)+1],                              positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col1"           ), NumberToStr(los.Units    (lfxOrders, i), ".+") +" units",                positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col2"           ), "BE:",                                                                   positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col3"           ), NumberToStr(los.OpenPrice(lfxOrders, i), SubPipPriceFormat),             positions.fontSize, positions.fontName, fontColor);
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col4"           ), "Profit:",                                                               positions.fontSize, positions.fontName, fontColor);
            if (positions.absoluteProfits)
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col5"           ), DoubleToStr(lfxOrders.dCache[i][I_DC.profit], 2),                        positions.fontSize, positions.fontName, fontColor);
               double profitPct = lfxOrders.dCache[i][I_DC.profit] / los.OpenEquity(lfxOrders, i) * 100;
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", percentCol), DoubleToStr(profitPct, 2) +"%",                                          positions.fontSize, positions.fontName, fontColor);
               sComment = StringConcatenate(los.Comment(lfxOrders, i), " ");
               if (StringGetChar(sComment, 0) == '#')
                  sComment = StringConcatenate(lfxCurrency, ".", StringRight(sComment, -1));
            ObjectSetText(StringConcatenate(label.position, ".line", line, "_col", commentCol), sComment,                                                                positions.fontSize, positions.fontName, fontColor);
         }
      }
   }

   return(!catch("UpdatePositions(3)"));
}


/**
 * Aktualisiert die Anzeige der aktuellen Anzahl und des Limits der offenen Orders.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateOrderCounter() {
   static int   showLimit   =INT_MAX,   warnLimit=INT_MAX,    alertLimit=INT_MAX, maxOpenOrders;
   static color defaultColor=SlateGray, warnColor=DarkOrange, alertColor=Red;

   if (!maxOpenOrders) {
      maxOpenOrders = GetGlobalConfigInt("Accounts", GetAccountNumber() +".maxOpenTickets.total", -1);
      if (!maxOpenOrders)
         maxOpenOrders = -1;
      if (maxOpenOrders > 0) {
         alertLimit = Min(Round(0.9  * maxOpenOrders), maxOpenOrders-5);
         warnLimit  = Min(Round(0.75 * maxOpenOrders), alertLimit   -5);
         showLimit  = Min(Round(0.5  * maxOpenOrders), warnLimit    -5);
      }
   }

   string sText = " ";
   color  objectColor = defaultColor;

   int orders = OrdersTotal();
   if (orders >= showLimit) {
      if      (orders >= alertLimit) objectColor = alertColor;
      else if (orders >= warnLimit ) objectColor = warnColor;
      sText = StringConcatenate(orders, " open orders (max. ", maxOpenOrders, ")");
   }
   ObjectSetText(label.orderCounter, sText, 8, "Tahoma Fett", objectColor);

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                            // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateOrderCounter(1)", error));
}


/**
 * Aktualisiert die Anzeige eines externen oder Remote-Accounts.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateAccountDisplay() {
   string text;

   if (mode.intern.trading) {
      ObjectSetText(label.tradeAccount, " ", 1);
   }
   if (mode.extern.notrading) {
      ObjectSetText(label.unitSize, " ", 1);
      text = tradeAccount.name +"  ("+ tradeAccount.company +")";
      ObjectSetText(label.tradeAccount, text, 8, "Arial Fett", Red);
   }
   if (mode.remote.trading) {
      ObjectSetText(label.unitSize, " ", 1);
      text = tradeAccount.name +": "+ tradeAccount.company +", "+ tradeAccount.number +", "+ tradeAccount.currency;
      ObjectSetText(label.tradeAccount, text, 8, "Arial Fett", ifInt(tradeAccount.type==ACCOUNT_TYPE_DEMO, LimeGreen, DarkOrange));
   }

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                            // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateAccountDisplay(1)", error));
}


/**
 * Aktualisiert die Anzeige des aktuellen Stopout-Levels.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStopoutLevel() {
   if (!positions.analyzed) /*&&*/ if (!AnalyzePositions())
      return(false);

   if (!mode.intern.trading || !totalPosition) {                                       // keine effektive Position im Markt: vorhandene Marker l�schen
      ObjectDelete(label.stopoutLevel);
      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)                 // bei offenem Properties-Dialog oder Object::onDrag()
         return(!catch("UpdateStopoutLevel(1)", error));
      return(true);
   }


   // (1) Stopout-Preis berechnen
   double equity     = AccountEquity();
   double usedMargin = AccountMargin();
   int    soMode     = AccountStopoutMode();
   double soEquity   = AccountStopoutLevel(); if (soMode != MSM_ABSOLUTE) soEquity /= (100/usedMargin);
   double tickSize   = MarketInfo(Symbol(), MODE_TICKSIZE );
   double tickValue  = MarketInfo(Symbol(), MODE_TICKVALUE) * MathAbs(totalPosition);  // TickValue der aktuellen Position
   if (!tickSize || !tickValue)
      return(!SetLastError(ERR_SYMBOL_NOT_AVAILABLE));                                 // Symbol (noch) nicht subscribed (Start, Account- oder Templatewechsel) oder Offline-Chart
   double soDistance = (equity - soEquity)/tickValue * tickSize;
   double soPrice;
   if (totalPosition > 0) soPrice = NormalizeDouble(Bid - soDistance, Digits);
   else                   soPrice = NormalizeDouble(Ask + soDistance, Digits);


   // (2) Stopout-Preis anzeigen
   if (ObjectFind(label.stopoutLevel) == -1) {
      ObjectCreate (label.stopoutLevel, OBJ_HLINE, 0, 0, 0);
      ObjectSet    (label.stopoutLevel, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSet    (label.stopoutLevel, OBJPROP_COLOR, OrangeRed  );
      ObjectSet    (label.stopoutLevel, OBJPROP_BACK , true       );
         if (soMode == MSM_PERCENT) string text = StringConcatenate("Stopout  ", Round(AccountStopoutLevel()), "%  =  ", NumberToStr(soPrice, PriceFormat));
         else                              text = StringConcatenate("Stopout  ", DoubleToStr(soEquity, 2), AccountCurrency(), "  =  ", NumberToStr(soPrice, PriceFormat));
      ObjectSetText(label.stopoutLevel, text);
      ObjectRegister(label.stopoutLevel);
   }
   ObjectSet(label.stopoutLevel, OBJPROP_PRICE1, soPrice);


   error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                                     // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateStopoutLevel(2)", error));
}


/**
 * Aktualisiert die OHLC-Anzeige.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateOHLC() {
   // TODO: noch nicht zufriedenstellend implementiert
   return(true);


   // (1) Zeit des letzten Ticks holen
   datetime lastTickTime = MarketInfo(Symbol(), MODE_TIME);
   if (!lastTickTime) {                                                          // Symbol (noch) nicht subscribed (Start, Account- oder Templatewechsel) oder Offline-Chart
      if (!SetLastError(GetLastError()))
         SetLastError(ERR_SYMBOL_NOT_AVAILABLE);
      return(false);
   }


   // (2) Beginn und Ende der aktuellen Session ermitteln
   datetime sessionStart = GetSessionStartTime.srv(lastTickTime);                // throws ERR_MARKET_CLOSED
   if (sessionStart == NaT) {
      if (SetLastError(stdlib.GetLastError()) != ERR_MARKET_CLOSED)              // am Wochenende die letzte Session verwenden
         return(false);
      sessionStart = GetPrevSessionStartTime.srv(lastTickTime);
   }
   datetime sessionEnd = sessionStart + 1*DAY;


   // (3) Baroffsets von Sessionbeginn und -ende ermitteln
   int openBar = iBarShiftNext(NULL, NULL, sessionStart);
      if (openBar == EMPTY_VALUE) return(false);                                 // Fehler
      if (openBar ==          -1) return(true);                                  // sessionStart ist zu jung f�r den Chart
   int closeBar = iBarShiftPrevious(NULL, NULL, sessionEnd);
      if (closeBar == EMPTY_VALUE) return(false);
      if (closeBar ==          -1) return(true);                                 // sessionEnd ist zu alt f�r den Chart
   if (openBar < closeBar)
      return(!catch("UpdateOHLC(1)  illegal open/close bar offsets for session from="+ DateTimeToStr(sessionStart, "w D.M.Y H:I") +" (bar="+ openBar +")  to="+ DateTimeToStr(sessionEnd, "w D.M.Y H:I") +" (bar="+ closeBar +")", ERR_RUNTIME_ERROR));


   // (4) Baroffsets von Session-High und -Low ermitteln
   int highBar = iHighest(NULL, NULL, MODE_HIGH, openBar-closeBar+1, closeBar);
   int lowBar  = iLowest (NULL, NULL, MODE_LOW , openBar-closeBar+1, closeBar);


   // (5) Anzeige aktualisieren
   string strOHLC = "O="+ NumberToStr(Open[openBar], PriceFormat) +"   H="+ NumberToStr(High[highBar], PriceFormat) +"   L="+ NumberToStr(Low[lowBar], PriceFormat);
   ObjectSetText(label.ohlc, strOHLC, 8, "", Black);

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                               // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateOHLC(2)", error));
}


/**
 * Aktualisiert die Zeitanzeige (nur im Tester bei VisualMode=On).
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateTime() {
   if (!IsVisualModeFix())
      return(true);

   static datetime lastTime;

   datetime now = TimeCurrentEx("UpdateTime(1)");
   if (now == lastTime)
      return(true);

   string date = TimeToStr(now, TIME_DATE),
          yyyy = StringSubstr(date, 0, 4),
          mm   = StringSubstr(date, 5, 2),
          dd   = StringSubstr(date, 8, 2),
          time = TimeToStr(now, TIME_MINUTES|TIME_SECONDS);

   ObjectSetText(label.time, StringConcatenate(dd, ".", mm, ".", yyyy, " ", time), 9, "Tahoma", SlateGray);

   lastTime = now;

   int error = GetLastError();
   if (!error || error==ERR_OBJECT_DOES_NOT_EXIST)                      // bei offenem Properties-Dialog oder Object::onDrag()
      return(true);
   return(!catch("UpdateTime(2)", error));
}


/**
 * Wrapper f�r AnalyzePositions(bool logTickets=TRUE) f�r onChartCommand()-Handler.
 *
 * @return bool - Erfolgsstatus
 */
bool Positions.LogTickets() {
   return(AnalyzePositions(true));
}


/**
 * Ermittelt die aktuelle Positionierung, gruppiert sie je nach individueller Konfiguration und berechnet deren Kennziffern.
 *
 * @param  bool logTickets - ob die Tickets der einzelnen Positionen geloggt werden sollen (default: FALSE)
 *
 * @return bool - Erfolgsstatus
 */
bool AnalyzePositions(bool logTickets=false) {
   logTickets = logTickets!=0;
   if (logTickets)          positions.analyzed = false;                          // vorm Loggen werden die Positionen immer re-evaluiert
   if (mode.remote.trading) positions.analyzed = true;
   if (positions.analyzed)  return(true);

   int      tickets    [], openPositions;                                        // Positionsdetails
   int      types      [];
   double   lots       [];
   datetime openTimes  [];
   double   openPrices [];
   double   commissions[];
   double   swaps      [];
   double   profits    [];


   // (1) Gesamtposition ermitteln
   longPosition  = 0;                                                            // globale Variablen
   shortPosition = 0;
   isPendings    = false;

   // (1.1) mode.intern.trading
   if (mode.intern.trading) {
      bool lfxProfits = false;
      int pos, orders = OrdersTotal();
      int sortKeys[][2];                                                         // Sortierschl�ssel der offenen Positionen: {OpenTime, Ticket}
      ArrayResize(sortKeys, orders);

      // Sortierschl�ssel auslesen und dabei P/L's von LFX-Positionen erfassen (alle Symbole).
      for (int n, i=0; i < orders; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) break;                 // FALSE: w�hrend des Auslesens wurde woanders ein offenes Ticket entfernt
         if (OrderType() > OP_SELL) {
            if (!isPendings) /*&&*/ if (OrderSymbol()==Symbol())
               isPendings = true;
            continue;
         }

         // P/L gefundener LFX-Positionen aufaddieren
         while (true) {                                                          // Pseudo-Schleife, dient dem einfacherem Verlassen des Blocks
            if (!lfxOrders.openPositions) break;

            if (LFX.IsMyOrder()) {                                               // Index des Tickets in lfxOrders.iCache[] bestimmen:
               if (OrderMagicNumber() != lfxOrders.iCache[pos][I_IC.ticket]) {   // Quickcheck mit letztem verwendeten Index, erst danach Vollsuche (schnellere Variante)
                  pos = SearchLfxTicket(OrderMagicNumber());                     // (ist lfxOrders.openPositions!=0, mu� nicht auf size(*.iCache)==0 gepr�ft werden)
                  if (pos == -1) {
                     pos = 0;
                     break;
                  }
               }
               if (!lfxProfits) {                                                // Profits in lfxOrders.dCache[] beim ersten Zugriff in lastProfit speichern und zur�cksetzen
                  for (int j=0; j < lfxOrders.openPositions; j++) {
                     lfxOrders.dCache[j][I_DC.lastProfit] = lfxOrders.dCache[j][I_DC.profit];
                     lfxOrders.dCache[j][I_DC.profit    ] = 0;
                  }
               }
               lfxOrders.dCache[pos][I_DC.profit] += OrderCommission() + OrderSwap() + OrderProfit();
               lfxProfits = true;
            }
            break;
         }

         if (OrderSymbol() != Symbol()) continue;
         if (OrderType() == OP_BUY) longPosition  += OrderLots();                // Gesamtposition je Richtung aufaddieren
         else                       shortPosition += OrderLots();
         if (!isPendings) /*&&*/ if (OrderStopLoss() || OrderTakeProfit())       // Pendings-Status tracken
            isPendings = true;

         sortKeys[n][0] = OrderOpenTime();                                       // Sortierschl�ssel der Tickets auslesen
         sortKeys[n][1] = OrderTicket();
         n++;
      }
      if (lfxProfits) /*&&*/if (!AnalyzePos.ProcessLfxProfits()) return(false);  // P/L's gefundener LFX-Positionen verarbeiten

      if (n < orders)
         ArrayResize(sortKeys, n);
      openPositions = n;

      // offene Positionen sortieren und einlesen
      if (openPositions > 1) /*&&*/ if (!SortOpenTickets(sortKeys))
         return(false);

      ArrayResize(tickets    , openPositions);                                   // interne Positionsdetails werden bei jedem Tick zur�ckgesetzt
      ArrayResize(types      , openPositions);
      ArrayResize(lots       , openPositions);
      ArrayResize(openTimes  , openPositions);
      ArrayResize(openPrices , openPositions);
      ArrayResize(commissions, openPositions);
      ArrayResize(swaps      , openPositions);
      ArrayResize(profits    , openPositions);

      for (i=0; i < openPositions; i++) {
         if (!SelectTicket(sortKeys[i][1], "AnalyzePositions(1)"))
            return(false);
         tickets    [i] = OrderTicket();
         types      [i] = OrderType();
         lots       [i] = NormalizeDouble(OrderLots(), 2);
         openTimes  [i] = OrderOpenTime();
         openPrices [i] = OrderOpenPrice();
         commissions[i] = OrderCommission();
         swaps      [i] = OrderSwap();
         profits    [i] = OrderProfit();
      }
   }

   // (1.2) mode.extern.notrading
   if (mode.extern.notrading) {
      openPositions = ArraySize(external.open.ticket);

      // offene Positionen werden nicht bei jedem Tick, sondern nur in init() oder nach entsprechendem Event neu eingelesen
      if (!external.open.lots.checked) {
         external.open.longPosition  = 0;
         external.open.shortPosition = 0;
         for (i=0; i < openPositions; i++) {                                     // Gesamtposition je Richtung aufaddieren
            if (external.open.type[i] == OP_BUY) external.open.longPosition  += external.open.lots[i];
            else                                 external.open.shortPosition += external.open.lots[i];
         }
         external.open.lots.checked = true;
      }
      longPosition  = external.open.longPosition;
      shortPosition = external.open.shortPosition;

      if (openPositions > 0) {
         ArrayCopy(tickets    , external.open.ticket    );                       // ExtractPosition() modifiziert die �bergebenen Arrays, also Kopie der Originaldaten erstellen
         ArrayCopy(types      , external.open.type      );
         ArrayCopy(lots       , external.open.lots      );
         ArrayCopy(openTimes  , external.open.openTime  );
         ArrayCopy(openPrices , external.open.openPrice );
         ArrayCopy(commissions, external.open.commission);
         ArrayCopy(swaps      , external.open.swap      );
         ArrayCopy(profits    , external.open.profit    );

         for (i=0; i < openPositions; i++) {
            profits[i] = ifDouble(types[i]==OP_LONG, Bid-openPrices[i], openPrices[i]-Ask)/Pips * PipValue(lots[i], true); // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
         }
      }
   }

   // (1.3) Ergebnisse intern + extern
   longPosition  = NormalizeDouble(longPosition,  2);                            // globale Variablen
   shortPosition = NormalizeDouble(shortPosition, 2);
   totalPosition = NormalizeDouble(longPosition - shortPosition, 2);
   isPosition    = longPosition || shortPosition;


   // (2) Positionen analysieren und in positions.~data[] speichern
   if (ArrayRange(positions.iData, 0) > 0) {
      ArrayResize(positions.iData, 0);
      ArrayResize(positions.dData, 0);
   }

   // (2.1) individuelle Konfiguration parsen
   int oldError = last_error;
   SetLastError(NO_ERROR);
   if (ArrayRange(positions.config, 0)==0) /*&&*/ if (!CustomPositions.ReadConfig()) {
      positions.analyzed = !last_error;                                          // MarketInfo()-Daten stehen ggf. noch nicht zur Verf�gung,
      if (!last_error) SetLastError(oldError);                                   // in diesem Fall n�chster Versuch beim n�chsten Tick.
      return(positions.analyzed);
   }
   SetLastError(oldError);

   int    termType, confLineIndex;
   double termValue1, termValue2, termCache1, termCache2, customLongPosition, customShortPosition, customTotalPosition, closedProfit=EMPTY_VALUE, adjustedProfit, customEquity, _longPosition=longPosition, _shortPosition=shortPosition, _totalPosition=totalPosition;
   bool   isCustomVirtual;
   int    customTickets    [];
   int    customTypes      [];
   double customLots       [];
   double customOpenPrices [];
   double customCommissions[];
   double customSwaps      [];
   double customProfits    [];

   // (2.2) individuell konfigurierte Positionen aus den offenen Positionen extrahieren
   int confSize = ArrayRange(positions.config, 0);

   for (i=0, confLineIndex=0; i < confSize; i++) {
      termType   = positions.config[i][0];
      termValue1 = positions.config[i][1];
      termValue2 = positions.config[i][2];
      termCache1 = positions.config[i][3];
      termCache2 = positions.config[i][4];

      if (!termType) {                                                           // termType=NULL => "Zeilenende"
         if (logTickets) AnalyzePositions.LogTickets(isCustomVirtual, customTickets, confLineIndex);

         // (2.3) individuell konfigurierte Position speichern
         if (!StorePosition(isCustomVirtual, customLongPosition, customShortPosition, customTotalPosition, customTickets, customTypes, customLots, customOpenPrices, customCommissions, customSwaps, customProfits, closedProfit, adjustedProfit, customEquity, confLineIndex))
            return(false);
         isCustomVirtual     = false;
         customLongPosition  = 0;
         customShortPosition = 0;
         customTotalPosition = 0;
         closedProfit        = EMPTY_VALUE;
         adjustedProfit      = 0;
         customEquity        = 0;
         ArrayResize(customTickets    , 0);
         ArrayResize(customTypes      , 0);
         ArrayResize(customLots       , 0);
         ArrayResize(customOpenPrices , 0);
         ArrayResize(customCommissions, 0);
         ArrayResize(customSwaps      , 0);
         ArrayResize(customProfits    , 0);
         confLineIndex++;
         continue;
      }
      if (!ExtractPosition(termType, termValue1, termValue2, termCache1, termCache2,
                           _longPosition,      _shortPosition,      _totalPosition,      tickets,       types,       lots,       openTimes, openPrices,       commissions,       swaps,       profits,
                           customLongPosition, customShortPosition, customTotalPosition, customTickets, customTypes, customLots,            customOpenPrices, customCommissions, customSwaps, customProfits, closedProfit, adjustedProfit, customEquity,
                           isCustomVirtual))
         return(false);
      positions.config[i][3] = termCache1;
      positions.config[i][4] = termCache2;
   }

   if (logTickets) AnalyzePositions.LogTickets(false, tickets, -1);

   // (2.4) verbleibende Position(en) speichern
   if (!StorePosition(false, _longPosition, _shortPosition, _totalPosition, tickets, types, lots, openPrices, commissions, swaps, profits, EMPTY_VALUE, 0, 0, -1))
      return(false);

   positions.analyzed = true;
   return(!catch("AnalyzePositions(2)"));
}


/**
 * Loggt die Tickets jeder Zeile der Positionsanzeige.
 *
 * @return bool - Erfolgsstatus
 */
bool AnalyzePositions.LogTickets(bool isVirtual, int tickets[], int commentIndex) {
   isVirtual = isVirtual!=0;

   if (ArraySize(tickets) > 0) {
      if (commentIndex > -1) log("LogTickets(2)  conf("+ commentIndex +") = \""+ positions.config.comments[commentIndex] +"\" = "+ TicketsToStr.Position(tickets) +" = "+ TicketsToStr(tickets, NULL));
      else                   log("LogTickets(3)  conf(none) = "                                                                  + TicketsToStr.Position(tickets) +" = "+ TicketsToStr(tickets, NULL));
   }
   return(true);
}


/**
 * Aktualisiert die dynamischen Werte des Money-Managements.
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateMoneyManagement() {
   if (mm.ready           ) return(true);
   if (mode.remote.trading) return(true);
 //if (mode.remote.trading) return(_true(debug("UpdateMoneyManagement(1)  feature not implemented for mode.remote.trading=true")));

   mm.realEquity             = 0;
   mm.lotValue               = 0;
   mm.unleveragedLots        = 0;                                             // Lotsize bei Hebel 1:1
   mm.ATRwAbs                = 0;                                             // w�chentliche ATR, absolut
   mm.ATRwPct                = 0;                                             // w�chentliche ATR, prozentual
   mm.stdLeverage            = 0;                                             // Hebel bei w�chentlicher Volatilit�t einer Unit von {mm.stdVola} Prozent
   mm.stdLots                = 0;                                             // Lotsize f�r w�chentliche Volatilit�t einer Unit von {mm.stdVola} Prozent
   mm.customVola             = 0;                                             // Volatilit�t/Woche bei benutzerdefiniertem Hebel
   mm.customLots             = 0;                                             // Lotsize bei benutzerdefiniertem Hebel
   mm.defaultVola            = 0;
   mm.defaultLeverage        = 0;
   mm.defaultLots            = 0;
   mm.defaultLots.normalized = 0;

   // (1) unleveraged Lots
   double tickSize       = MarketInfo(Symbol(), MODE_TICKSIZE      );
   double tickValue      = MarketInfo(Symbol(), MODE_TICKVALUE     );
   double marginRequired = MarketInfo(Symbol(), MODE_MARGINREQUIRED); if (marginRequired == -92233720368547760.) marginRequired = 0;
      int error = GetLastError();
      if (IsError(error)) {
         if (error == ERR_SYMBOL_NOT_AVAILABLE) {
            SetLastError(ERS_TERMINAL_NOT_YET_READY);
            //debug("UpdateMoneyManagement(2)  MarketInfo(\""+ Symbol() +"\") => ERR_SYMBOL_NOT_AVAILABLE", last_error);
            return(false);
         }
         return(!catch("UpdateMoneyManagement(3)", error));
      }
   double externalAssets = GetExternalAssets(tradeAccount.company, ifString(mode.extern.notrading, tradeAccount.alias, tradeAccount.number));
   if (mode.intern.trading) {
      double visibleEquity = AccountEquity()-AccountCredit();                 // bei negativer AccountBalance wird nur visibleEquity benutzt
         if (AccountBalance() > 0) visibleEquity = MathMin(AccountBalance(), visibleEquity);
      mm.realEquity = visibleEquity + externalAssets;
   }
   else {
      mm.realEquity = externalAssets;                                         // falsch, solange ExternalAssets bei mode.extern nicht st�ndig aktualisiert wird
   }

   if (!Bid || !tickSize || !tickValue || !marginRequired) {                  // bei Start oder Accountwechsel k�nnen einige Werte noch ungesetzt sein
      SetLastError(ERS_TERMINAL_NOT_YET_READY);
      //debug("UpdateMoneyManagement(5)  Tick="+ Tick + ifString(!Bid, "  Bid=0", "") + ifString(!tickSize, "  tickSize=0", "") + ifString(!tickValue, "  tickValue=0", "") + ifString(!marginRequired, "  marginRequired=0", ""), last_error);
      return(false);
   }

   mm.lotValue        = Bid/tickSize * tickValue;                             // Value eines Lots in Account-Currency
   mm.unleveragedLots = mm.realEquity/mm.lotValue;                            // ungehebelte Lotsize (Leverage 1:1)


   // (2) Expected TrueRange als Maximalwert von ATR und den letzten beiden Einzelwerten: ATR, TR[1] und TR[0]
   double a = @ATR(NULL, PERIOD_W1, 14, 1); if (a == EMPTY) return(false);    // ATR(14xW):  throws ERS_HISTORY_UPDATE (wenn, dann nur einmal)
      if (last_error == ERS_HISTORY_UPDATE) /*&&*/ if (Period()!=PERIOD_W1) SetLastError(NO_ERROR);
      if (!a)                                               return(false);
   double b = @ATR(NULL, PERIOD_W1,  1, 1); if (b == EMPTY) return(false);    // TrueRange letzte Woche
      if (!b)                                               return(false);
   double c = @ATR(NULL, PERIOD_W1,  1, 0); if (c == EMPTY) return(false);    // TrueRange aktuelle Woche
      if (!c)                                               return(false);
   mm.ATRwAbs = MathMax(a, MathMax(b, c));
      double C = iClose(NULL, PERIOD_W1, 1); if (!C)        return(false);
      double H = iHigh (NULL, PERIOD_W1, 0); if (!H)        return(false);
      double L = iLow  (NULL, PERIOD_W1, 0); if (!L)        return(false);
   mm.ATRwPct = mm.ATRwAbs/((MathMax(C, H) + MathMax(C, L))/2);               // median price

   if (mm.isCustomUnitSize) {
      // (3) customLots
      mm.customLots      = mm.unleveragedLots * mm.customLeverage;            // mit benutzerdefiniertem Hebel gehebelte Lotsize
      mm.customVola      = mm.customLeverage * (mm.ATRwPct*100);              // resultierende w�chentliche Volatilit�t

      mm.defaultVola     = mm.customVola;
      mm.defaultLeverage = mm.customLeverage;
      mm.defaultLots     = mm.customLots;
   }
   else {
      // (4) stdLots
      if (!mm.ATRwPct)
         return(false);
      mm.stdLeverage     = mm.stdVola/(mm.ATRwPct*100);
      mm.stdLots         = mm.unleveragedLots * mm.stdLeverage;               // auf w�chentliche Volatilit�t gehebelte Lotsize

      mm.defaultVola     = mm.stdVola;
      mm.defaultLeverage = mm.stdLeverage;
      mm.defaultLots     = mm.stdLots;
   }


   // (5) Lotsize runden
   if (mm.defaultLots > 0) {                                                                                                              // Abstufung max. 6.7% je Schritt
      if      (mm.defaultLots <=    0.03) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.001) *   0.001, 3);    //     0-0.03: Vielfaches von   0.001
      else if (mm.defaultLots <=   0.075) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.002) *   0.002, 3);    // 0.03-0.075: Vielfaches von   0.002
      else if (mm.defaultLots <=    0.1 ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.005) *   0.005, 3);    //  0.075-0.1: Vielfaches von   0.005
      else if (mm.defaultLots <=    0.3 ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.01 ) *   0.01 , 2);    //    0.1-0.3: Vielfaches von   0.01
      else if (mm.defaultLots <=    0.75) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.02 ) *   0.02 , 2);    //   0.3-0.75: Vielfaches von   0.02
      else if (mm.defaultLots <=    1.2 ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.05 ) *   0.05 , 2);    //   0.75-1.2: Vielfaches von   0.05
      else if (mm.defaultLots <=    3.  ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.1  ) *   0.1  , 1);    //      1.2-3: Vielfaches von   0.1
      else if (mm.defaultLots <=    7.5 ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.2  ) *   0.2  , 1);    //      3-7.5: Vielfaches von   0.2
      else if (mm.defaultLots <=   12.  ) mm.defaultLots.normalized = NormalizeDouble(MathRound(mm.defaultLots/  0.5  ) *   0.5  , 1);    //     7.5-12: Vielfaches von   0.5
      else if (mm.defaultLots <=   30.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/  1    ) *   1       );    //      12-30: Vielfaches von   1
      else if (mm.defaultLots <=   75.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/  2    ) *   2       );    //      30-75: Vielfaches von   2
      else if (mm.defaultLots <=  120.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/  5    ) *   5       );    //     75-120: Vielfaches von   5
      else if (mm.defaultLots <=  300.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/ 10    ) *  10       );    //    120-300: Vielfaches von  10
      else if (mm.defaultLots <=  750.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/ 20    ) *  20       );    //    300-750: Vielfaches von  20
      else if (mm.defaultLots <= 1200.  ) mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/ 50    ) *  50       );    //   750-1200: Vielfaches von  50
      else                                mm.defaultLots.normalized =       MathRound(MathRound(mm.defaultLots/100    ) * 100       );    //   1200-...: Vielfaches von 100
   }

   mm.ready = true;
   return(!catch("UpdateMoneyManagement(16)"));
}


/**
 * Durchsucht das globale Cache-Array lfxOrders.iCache[] nach dem �bergebenen Ticket.
 *
 * @param  int ticket - zu findendes LFX-Ticket
 *
 * @return int - Index des gesuchten Tickets oder -1, wenn das Ticket unbekannt ist
 */
int SearchLfxTicket(int ticket) {
   int size = ArrayRange(lfxOrders.iCache, 0);
   for (int i=0; i < size; i++) {
      if (lfxOrders.iCache[i][I_IC.ticket] == ticket)
         return(i);
   }
   return(-1);
}


/**
 * Liest die individuelle Positionskonfiguration ein und speichert sie in einem bin�ren Format.
 *
 * @return bool - Erfolgsstatus
 *
 *
 * F�llt das Array positions.config[][] mit den Konfigurationsdaten des aktuellen Instruments in der Accountkonfiguration. Das Array enth�lt danach Elemente
 * im Format {type, value1, value2, ...}.  Ein NULL-Term-Element {NULL, ...} markiert ein Zeilenende bzw. eine leere Konfiguration. Nach einer eingelesenen
 * Konfiguration ist die Gr��e der ersten Dimension des Arrays niemals 0. Positionskommentare werden in positions.config.comments[] gespeichert.
 *
 *
 *  Notation:                                        Beschreibung:                                                            Arraydarstellung:
 *  ---------                                        -------------                                                            -----------------
 *   0.1#123456                                      - O.1 Lot eines Tickets (1)                                              [123456             , 0.1             , ...             , ...     , ...     ]
 *      #123456                                      - komplettes Ticket oder verbleibender Rest eines Tickets                [123456             , EMPTY           , ...             , ...     , ...     ]
 *   0.2L                                            - mit Lotsize: virtuelle Long-Position zum aktuellen Preis (2)           [TERM_OPEN_LONG     , 0.2             , NULL            , ...     , ...     ]
 *   0.3S[@]1.2345                                   - mit Lotsize: virtuelle Short-Position zum angegebenen Preis (2)        [TERM_OPEN_SHORT    , 0.3             , 1.2345          , ...     , ...     ]
 *      L                                            - ohne Lotsize: alle verbleibenden Long-Positionen                       [TERM_OPEN_LONG     , EMPTY           , ...             , ...     , ...     ]
 *      S                                            - ohne Lotsize: alle verbleibenden Short-Positionen                      [TERM_OPEN_SHORT    , EMPTY           , ...             , ...     , ...     ]
 *   O{DateTime}                                     - offene Positionen des aktuellen Symbols eines Standard-Zeitraums (3)   [TERM_OPEN_SYMBOL   , 2014.01.01 00:00, 2014.12.31 23:59, ...     , ...     ]
 *   OT{DateTime}-{DateTime}                         - offene Positionen aller Symbole von und bis zu einem Zeitpunkt (3)(4)  [TERM_OPEN_ALL      , 2014.02.01 08:00, 2014.02.10 18:00, ...     , ...     ]
 *   H{DateTime}             [Monthly|Weekly|Daily]  - Trade-History des aktuellen Symbols eines Standard-Zeitraums (3)(5)    [TERM_HISTORY_SYMBOL, 2014.01.01 00:00, 2014.12.31 23:59, {cache1}, {cache2}]
 *   HT{DateTime}-{DateTime} [Monthly|Weekly|Daily]  - Trade-History aller Symbole von und bis zu einem Zeitpunkt (3)(4)(5)   [TERM_HISTORY_ALL   , 2014.02.01 08:00, 2014.02.10 18:00, {cache1}, {cache2}]
 *   12.34                                           - dem P/L einer Position zuzuschlagender Betrag                          [TERM_ADJUSTMENT    , 12.34           , ...             , ...     , ...     ]
 *   EQ123.00                                        - f�r Equityberechnungen zu verwendender Wert                            [TERM_EQUITY        , 123.00          , ...             , ...     , ...     ]
 *
 *   Kommentar (Text nach dem ersten Semikolon ";")  - wird als Beschreibung angezeigt
 *   Kommentare in Kommentaren (nach weiterem ";")   - werden ignoriert
 *
 *
 *  Beispiel:
 *  ---------
 *   [CustomPositions]
 *   GBPAUD.0 = #111111, 0.1#222222      ;  komplettes Ticket #111111 und 0.1 Lot von Ticket #222222 (Text wird als Kommentar angezeigt)
 *   GBPAUD.1 = 0.2L, #222222            ;; virtuelle 0.2 Lot Long-Position und Rest von #222222 (2)
 *   GBPAUD.3 = L,S,-34.56               ;; alle verbleibenden Positionen, inkl. eines Restes von #222222, zzgl. eines Verlustes von -34.56
 *   GBPAUD.3 = 0.5L                     ;; Zeile wird ignoriert, da der Schl�ssel "GBPAUD.3" doppelt vorhanden ist und bereits verarbeitet wurde
 *   GBPAUD.2 = 0.3S                     ;; virtuelle 0.3 Lot Short-Position, wird als letzte angezeigt (6)
 *
 *
 *  Resultierendes Array:
 *  ---------------------
 *  positions.config = [
 *     [111111         , EMPTY, ... , ..., ...], [222222         , 0.1  , ..., ..., ...],                                           [NULL, ..., ..., ..., ...],
 *     [TERM_OPEN_LONG , 0.2  , NULL, ..., ...], [222222         , EMPTY, ..., ..., ...],                                           [NULL, ..., ..., ..., ...],
 *     [TERM_OPEN_LONG , EMPTY, ... , ..., ...], [TERM_OPEN_SHORT, EMPTY, ..., ..., ...], [TERM_ADJUSTMENT, -34.45, ..., ..., ...], [NULL, ..., ..., ..., ...],
 *     [TERM_OPEN_SHORT, 0.3  , NULL, ..., ...],                                                                                    [NULL, ..., ..., ..., ...],
 *  ];
 *
 *  (1) Bei einer Lotsize von 0 wird die entsprechende Teilposition der individuellen Position ignoriert.
 *  (2) Reale Positionen, die mit virtuellen Positionen kombiniert werden, werden nicht von der verbleibenden Gesamtposition abgezogen.
 *      Dies kann in Verbindung mit (1) benutzt werden, um auf die Schnelle eine virtuelle Position zu konfigurieren, die keinen Einflu�
 *      auf die Anzeige sp�ter folgender Positionen hat (z.B. durch "0L" innerhalb einer Konfigurationszeile).
 *  (3) Zeitangaben im Format: 2014[.01[.15 [W|12:30[:45]]]]
 *  (4) Einer der beiden Zeitpunkte kann leer sein und steht f�r "von Beginn" oder "bis Ende".
 *  (5) Ein Historyzeitraum kann tages-, wochen- oder monatsweise gruppiert werden, wenn er nicht mit anderen Positionsdaten kombiniert wird.
 *  (6) Die konfigurierten Positionen werden in der Reihenfolge ihrer Notierung verarbeitet und angezeigt, sie werden nicht sortiert.
 */
bool CustomPositions.ReadConfig() {
   if (ArrayRange(positions.config, 0) > 0) {
      ArrayResize(positions.config,          0);
      ArrayResize(positions.config.comments, 0);
   }

   string   keys[], values[], iniValue, comment, confComment, openComment, hstComment, strSize, strTicket, strPrice, sNull, symbol=Symbol(), stdSymbol=StdSymbol();
   double   termType, termValue1, termValue2, termCache1, termCache2, lotSize, minLotSize=MarketInfo(symbol, MODE_MINLOT), lotStep=MarketInfo(symbol, MODE_LOTSTEP);
   int      valuesSize, confSize, pos, ticket, positionStartOffset;
   datetime from, to;
   bool     isPositionEmpty, isPositionVirtual, isPositionGrouped, isTotal;
   if (!minLotSize || !lotStep) return(false);                       // falls MarketInfo()-Daten noch nicht verf�gbar sind

   if (mode.remote.trading) return(!catch("CustomPositions.ReadConfig(1)  feature for mode.remote.trading=true not yet implemented", ERR_NOT_IMPLEMENTED));

   string mqlDir   = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file     = TerminalPath() + mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ ifString(mode.extern.notrading, tradeAccount.alias, tradeAccount.number) +"_config.ini";
   string section  = "CustomPositions";
   int    keysSize = GetIniKeys(file, section, keys);

   for (int i=0; i < keysSize; i++) {
      if (StringStartsWithI(keys[i], symbol) || StringStartsWithI(keys[i], stdSymbol)) {
         if (SearchStringArrayI(keys, keys[i]) == i) {               // bei gleichnamigen Schl�sseln wird nur der erste verarbeitet
            iniValue = GetRawIniString(file, section, keys[i], "");
            iniValue = StringReplace(iniValue, TAB, " ");

            // Kommentar auswerten
            comment     = "";
            confComment = "";
            openComment = "";
            hstComment  = "";
            pos = StringFind(iniValue, ";");
            if (pos >= 0) {
               confComment = StringRight(iniValue, -pos-1);
               iniValue    = StringTrim(StringLeft(iniValue, pos));
               pos = StringFind(confComment, ";");
               if (pos == -1) confComment = StringTrim(confComment);
               else           confComment = StringTrim(StringLeft(confComment, pos));
               if (StringStartsWith(confComment, "\"") && StringEndsWith(confComment, "\"")) // f�hrende und schlie�ende Anf�hrungszeichen entfernen
                  confComment = StringSubstrFix(confComment, 1, StringLen(confComment)-2);
            }

            // Konfiguration auswerten
            isPositionEmpty   = true;                                // ob die resultierende Position bereits Daten enth�lt oder nicht
            isPositionVirtual = false;                               // ob die resultierende Position virtuell ist
            isPositionGrouped = false;                               // ob die resultierende Position gruppiert ist
            valuesSize        = Explode(StringToUpper(iniValue), ",", values, NULL);

            for (int n=0; n < valuesSize; n++) {
               values[n] = StringTrim(values[n]);
               if (!StringLen(values[n]))                            // Leervalue
                  continue;

               if (StringStartsWith(values[n], "H")) {               // H[T] = History[Total]
                  if (!CustomPositions.ParseHstTerm(values[n], confComment, hstComment, isPositionEmpty, isPositionGrouped, isTotal, from, to)) return(false);
                  if (isPositionGrouped) {
                     isPositionEmpty = false;
                     continue;                                       // gruppiert: die Konfiguration wurde bereits in CustomPositions.ParseHstTerm() gespeichert
                  }
                  termType   = ifInt(!isTotal, TERM_HISTORY_SYMBOL, TERM_HISTORY_ALL);
                  termValue1 = from;                                 // nicht gruppiert
                  termValue2 = to;
                  termCache1 = EMPTY_VALUE;                          // EMPTY_VALUE, da NULL bei TERM_HISTORY_* ein g�ltiger Wert ist
                  termCache2 = EMPTY_VALUE;
               }

               else if (StringStartsWith(values[n], "#")) {          // Ticket
                  strTicket = StringTrim(StringRight(values[n], -1));
                  if (!StringIsDigit(strTicket))                     return(!catch("CustomPositions.ReadConfig(2)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-digits in ticket \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termType   = StrToInteger(strTicket);
                  termValue1 = EMPTY;                                // alle verbleibenden Lots
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringStartsWith(values[n], "L")) {          // alle verbleibenden Long-Positionen
                  if (values[n] != "L")                              return(!catch("CustomPositions.ReadConfig(3)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (\""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termType   = TERM_OPEN_LONG;
                  termValue1 = EMPTY;
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringStartsWith(values[n], "S")) {          // alle verbleibenden Short-Positionen
                  if (values[n] != "S")                              return(!catch("CustomPositions.ReadConfig(4)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (\""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termType   = TERM_OPEN_SHORT;
                  termValue1 = EMPTY;
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringStartsWith(values[n], "O")) {          // O[T] = die verbleibenden Positionen [aller Symbole] eines Zeitraums
                  if (!CustomPositions.ParseOpenTerm(values[n], openComment, isTotal, from, to)) return(false);
                  termType   = ifInt(!isTotal, TERM_OPEN_SYMBOL, TERM_OPEN_ALL);
                  termValue1 = from;
                  termValue2 = to;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringStartsWith(values[n], "E")) {          // E[Q] = Equity
                  strSize = StringTrim(StringRight(values[n], ifInt(!StringStartsWith(values[n], "EQ"), -1, -2)));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(5)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric equity \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termType   = TERM_EQUITY;
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 <= 0)                               return(!catch("CustomPositions.ReadConfig(6)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (illegal equity \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringIsNumeric(values[n])) {                // P/L-Adjustment
                  termType   = TERM_ADJUSTMENT;
                  termValue1 = StrToDouble(values[n]);
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringEndsWith(values[n], "L")) {            // virtuelle Longposition zum aktuellen Preis
                  termType = TERM_OPEN_LONG;
                  strSize  = StringTrim(StringLeft(values[n], -1));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(7)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 < 0)                                return(!catch("CustomPositions.ReadConfig(8)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (negative lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  if (MathModFix(termValue1, 0.001) != 0)            return(!catch("CustomPositions.ReadConfig(9)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (virtual lot size not a multiple of 0.001 \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringEndsWith(values[n], "S")) {            // virtuelle Shortposition zum aktuellen Preis
                  termType = TERM_OPEN_SHORT;
                  strSize  = StringTrim(StringLeft(values[n], -1));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(10)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 < 0)                                return(!catch("CustomPositions.ReadConfig(11)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (negative lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  if (MathModFix(termValue1, 0.001) != 0)            return(!catch("CustomPositions.ReadConfig(12)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (virtual lot size not a multiple of 0.001 \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringContains(values[n], "L")) {            // virtuelle Longposition zum angegebenen Preis
                  termType = TERM_OPEN_LONG;
                  pos = StringFind(values[n], "L");
                  strSize = StringTrim(StringLeft(values[n], pos));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(13)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 < 0)                                return(!catch("CustomPositions.ReadConfig(14)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (negative lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  if (MathModFix(termValue1, 0.001) != 0)            return(!catch("CustomPositions.ReadConfig(15)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (virtual lot size not a multiple of 0.001 \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  strPrice = StringTrim(StringRight(values[n], -pos-1));
                  if (StringStartsWith(strPrice, "@"))
                     strPrice = StringTrim(StringRight(strPrice, -1));
                  if (!StringIsNumeric(strPrice))                    return(!catch("CustomPositions.ReadConfig(16)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric price \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue2 = StrToDouble(strPrice);
                  if (termValue2 <= 0)                               return(!catch("CustomPositions.ReadConfig(17)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (illegal price \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringContains(values[n], "S")) {            // virtuelle Shortposition zum angegebenen Preis
                  termType = TERM_OPEN_SHORT;
                  pos = StringFind(values[n], "S");
                  strSize = StringTrim(StringLeft(values[n], pos));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(18)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 < 0)                                return(!catch("CustomPositions.ReadConfig(19)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (negative lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  if (MathModFix(termValue1, 0.001) != 0)            return(!catch("CustomPositions.ReadConfig(20)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (virtual lot size not a multiple of 0.001 \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  strPrice = StringTrim(StringRight(values[n], -pos-1));
                  if (StringStartsWith(strPrice, "@"))
                     strPrice = StringTrim(StringRight(strPrice, -1));
                  if (!StringIsNumeric(strPrice))                    return(!catch("CustomPositions.ReadConfig(21)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric price \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue2 = StrToDouble(strPrice);
                  if (termValue2 <= 0)                               return(!catch("CustomPositions.ReadConfig(22)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (illegal price \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termCache1 = NULL;
                  termCache2 = NULL;
               }

               else if (StringContains(values[n], "#")) {            // Lotsizeangabe + # + Ticket
                  pos = StringFind(values[n], "#");
                  strSize = StringTrim(StringLeft(values[n], pos));
                  if (!StringIsNumeric(strSize))                     return(!catch("CustomPositions.ReadConfig(23)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-numeric lot size \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termValue1 = StrToDouble(strSize);
                  if (termValue1 && LT(termValue1, minLotSize))      return(!catch("CustomPositions.ReadConfig(24)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (lot size smaller than MIN_LOTSIZE \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  if (MathModFix(termValue1, lotStep) != 0)          return(!catch("CustomPositions.ReadConfig(25)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (lot size not a multiple of LOTSTEP \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  strTicket = StringTrim(StringRight(values[n], -pos-1));
                  if (!StringIsDigit(strTicket))                     return(!catch("CustomPositions.ReadConfig(26)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (non-digits in ticket \""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                  termType   = StrToInteger(strTicket);
                  termValue2 = NULL;
                  termCache1 = NULL;
                  termCache2 = NULL;
               }
               else                                                  return(!catch("CustomPositions.ReadConfig(27)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (\""+ values[n] +"\") in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));

               // Eine gruppierte Trade-History kann nicht mit anderen Termen kombiniert werden
               if (isPositionGrouped && termType!=TERM_EQUITY)       return(!catch("CustomPositions.ReadConfig(28)  invalid configuration value ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (cannot combine grouped trade history with other entries) in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));

               // Die Konfiguration virtueller Positionen mu� mit einem virtuellen Term beginnen, damit die realen Lots nicht um die virtuellen Lots reduziert werden, siehe (2).
               if ((termType==TERM_OPEN_LONG || termType==TERM_OPEN_SHORT) && termValue1!=EMPTY) {
                  if (!isPositionEmpty && !isPositionVirtual) {
                     double tmp[POSITION_CONFIG_TERM.doubleSize] = {TERM_OPEN_LONG, 0, NULL, NULL, NULL};   // am Anfang der Zeile virtuellen 0-Term einf�gen: 0L
                     ArrayInsertDoubleArray(positions.config, positionStartOffset, tmp);
                  }
                  isPositionVirtual = true;
               }

               // Konfigurations-Term speichern
               confSize = ArrayRange(positions.config, 0);
               ArrayResize(positions.config, confSize+1);
               positions.config[confSize][0] = termType;
               positions.config[confSize][1] = termValue1;
               positions.config[confSize][2] = termValue2;
               positions.config[confSize][3] = termCache1;
               positions.config[confSize][4] = termCache2;
               isPositionEmpty = false;
            }

            if (!isPositionEmpty) {                                  // Zeile mit Leer-Term abschlie�en (markiert Zeilenende)
               confSize = ArrayRange(positions.config, 0);
               ArrayResize(positions.config, confSize+1);            // initialisiert Term mit NULL
                  comment = openComment + ifString(StringLen(openComment) && StringLen(hstComment ), ", ", "") + hstComment;
                  comment = comment     + ifString(StringLen(comment    ) && StringLen(confComment), ", ", "") + confComment;
               ArrayPushString(positions.config.comments, comment);
               positionStartOffset = confSize + 1;                   // Start-Offset der n�chsten Custom-Position speichern (falls noch eine weitere Position folgt)
            }
         }
      }
   }

   confSize = ArrayRange(positions.config, 0);
   if (!confSize) {                                                  // leere Konfiguration mit Leer-Term markieren
      ArrayResize(positions.config, 1);                              // initialisiert Term mit NULL
      ArrayPushString(positions.config.comments, "");
   }

   //debug("CustomPositions.ReadConfig(0.3)  conf="+ DoublesToStr(positions.config, NULL));
   return(!catch("CustomPositions.ReadConfig(29)"));
}


/**
 * Parst einen Open-Konfigurations-Term (Open Position).
 *
 * @param  _In_     string   term         - Konfigurations-Term
 * @param  _In_Out_ string   openComments - vorhandene OpenPositions-Kommentare (werden ggf. erweitert)
 * @param  _Out_    bool     isTotal      - ob die offenen Positionen alle verf�gbaren Symbole (TRUE) oder nur das aktuelle Symbol (FALSE) umfassen
 * @param  _Out_    datetime from         - Beginnzeitpunkt der zu ber�cksichtigenden Positionen
 * @param  _Out_    datetime to           - Endzeitpunkt der zu ber�cksichtigenden Positionen
 *
 * @return bool - Erfolgsstatus
 *
 *
 * Format:
 * -------
 *  O{DateTime}                                       � Trade-History eines Symbols eines Standard-Zeitraums
 *  OT{DateTime}-{DateTime}                           � Trade-History aller Symbole von und bis zu einem Zeitpunkt
 *
 *  {DateTime} = 2014[.01[.15 [W|12:34[:56]]]]        oder
 *  {DateTime} = (This|Last)(Day|Week|Month|Year)     oder
 *  {DateTime} = Today                                � Synonym f�r ThisDay
 *  {DateTime} = Yesterday                            � Synonym f�r LastDay
 */
bool CustomPositions.ParseOpenTerm(string term, string &openComments, bool &isTotal, datetime &from, datetime &to) {
   isTotal = isTotal!=0;

   string term.orig = StringTrim(term);
          term      = StringToUpper(term.orig);
   if (!StringStartsWith(term, "O")) return(!catch("CustomPositions.ParseOpenTerm(1)  invalid parameter term = "+ DoubleQuoteStr(term.orig) +" (not TERM_OPEN_*)", ERR_INVALID_PARAMETER));
   term = StringTrim(StringRight(term, -1));

   if     (!StringStartsWith(term, "T"    )) isTotal = false;
   else if (StringStartsWith(term, "THIS" )) isTotal = false;
   else if (StringStartsWith(term, "TODAY")) isTotal = false;
   else                                      isTotal = true;
   if (isTotal) term = StringTrim(StringRight(term, -1));

   bool     isSingleTimespan, isFullYear1, isFullYear2, isFullMonth1, isFullMonth2, isFullWeek1, isFullWeek2, isFullDay1, isFullDay2, isFullHour1, isFullHour2, isFullMinute1, isFullMinute2;
   datetime dtFrom, dtTo;
   string   comment = "";


   // (1) Beginn- und Endzeitpunkt parsen
   int pos = StringFind(term, "-");
   if (pos >= 0) {                                                   // von-bis parsen
      // {DateTime}-{DateTime}
      // {DateTime}-NULL
      //       NULL-{DateTime}
      dtFrom = ParseDateTime(StringTrim(StringLeft (term,  pos  )), isFullYear1, isFullMonth1, isFullWeek1, isFullDay1, isFullHour1, isFullMinute1); if (IsNaT(dtFrom)) return(false);
      dtTo   = ParseDateTime(StringTrim(StringRight(term, -pos-1)), isFullYear2, isFullMonth2, isFullWeek2, isFullDay2, isFullHour2, isFullMinute2); if (IsNaT(dtTo  )) return(false);
      if (dtTo != NULL) {
         if      (isFullYear2  ) dtTo  = DateTime(TimeYearFix(dtTo)+1)                  - 1*SECOND;   // Jahresende
         else if (isFullMonth2 ) dtTo  = DateTime(TimeYearFix(dtTo), TimeMonth(dtTo)+1) - 1*SECOND;   // Monatsende
         else if (isFullWeek2  ) dtTo += 1*WEEK                                         - 1*SECOND;   // Wochenende
         else if (isFullDay2   ) dtTo += 1*DAY                                          - 1*SECOND;   // Tagesende
         else if (isFullHour2  ) dtTo -=                                                  1*SECOND;   // Ende der vorhergehenden Stunde
       //else if (isFullMinute2) dtTo -=                                                  1*SECOND;   // nicht bei Minuten (deaktivert)
      }
   }
   else {
      // {DateTime}                                                  // einzelnen Zeitraum parsen
      isSingleTimespan = true;
      dtFrom = ParseDateTime(term, isFullYear1, isFullMonth1, isFullWeek1, isFullDay1, isFullHour1, isFullMinute1); if (IsNaT(dtFrom)) return(false);
                                                                                                                         if (!dtFrom)  return(!catch("CustomPositions.ParseOpenTerm(2)  invalid open positions configuration in "+ DoubleQuoteStr(term.orig), ERR_INVALID_CONFIG_PARAMVALUE));
      if      (isFullYear1  ) dtTo = DateTime(TimeYearFix(dtFrom)+1)                    - 1*SECOND;   // Jahresende
      else if (isFullMonth1 ) dtTo = DateTime(TimeYearFix(dtFrom), TimeMonth(dtFrom)+1) - 1*SECOND;   // Monatsende
      else if (isFullWeek1  ) dtTo = dtFrom + 1*WEEK                                    - 1*SECOND;   // Wochenende
      else if (isFullDay1   ) dtTo = dtFrom + 1*DAY                                     - 1*SECOND;   // Tagesende
      else if (isFullHour1  ) dtTo = dtFrom + 1*HOUR                                    - 1*SECOND;   // Ende der Stunde
      else if (isFullMinute1) dtTo = dtFrom + 1*MINUTE                                  - 1*SECOND;   // Ende der Minute
      else                    dtTo = dtFrom;
   }
   //debug("CustomPositions.ParseOpenTerm(0.1)  dtFrom="+ TimeToStr(dtFrom, TIME_FULL) +"  dtTo="+ TimeToStr(dtTo, TIME_FULL));
   if (!dtFrom && !dtTo)      return(!catch("CustomPositions.ParseOpenTerm(3)  invalid open positions configuration in "+ DoubleQuoteStr(term.orig), ERR_INVALID_CONFIG_PARAMVALUE));
   if (dtTo && dtFrom > dtTo) return(!catch("CustomPositions.ParseOpenTerm(4)  invalid open positions configuration in "+ DoubleQuoteStr(term.orig) +" (start time after end time)", ERR_INVALID_CONFIG_PARAMVALUE));


   // (2) Datumswerte definieren und zur�ckgeben
   if (isSingleTimespan) {
      if      (isFullYear1  ) comment =               DateTimeToStr(dtFrom, "Y");
      else if (isFullMonth1 ) comment =               DateTimeToStr(dtFrom, "Y O");
      else if (isFullWeek1  ) comment = "Woche vom "+ DateTimeToStr(dtFrom, "D.M.Y");
      else if (isFullDay1   ) comment =               DateTimeToStr(dtFrom, "D.M.Y");
      else if (isFullHour1  ) comment =               DateTimeToStr(dtFrom, "D.M.Y H:I") + DateTimeToStr(dtTo+1*SECOND, "-H:I");
      else if (isFullMinute1) comment =               DateTimeToStr(dtFrom, "D.M.Y H:I");
      else                    comment =               DateTimeToStr(dtFrom, "D.M.Y H:I:S");
   }
   else if (!dtTo) {
      if      (isFullYear1  ) comment = "seit "+      DateTimeToStr(dtFrom, "Y");
      else if (isFullMonth1 ) comment = "seit "+      DateTimeToStr(dtFrom, "O Y");
      else if (isFullWeek1  ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y");
      else if (isFullDay1   ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y");
      else if (isFullHour1  ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I");
      else if (isFullMinute1) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I");
      else                    comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I:S");
   }
   else if (!dtFrom) {
      if      (isFullYear2  ) comment =  "bis "+      DateTimeToStr(dtTo,          "Y");
      else if (isFullMonth2 ) comment =  "bis "+      DateTimeToStr(dtTo,          "O Y");
      else if (isFullWeek2  ) comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y");
      else if (isFullDay2   ) comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y");
      else if (isFullHour2  ) comment =  "bis "+      DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");
      else if (isFullMinute2) comment =  "bis "+      DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");
      else                    comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y H:I:S");
   }
   else {
      // von und bis angegeben
      if      (isFullYear1  ) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "Y")           +" bis "+ DateTimeToStr(dtTo,          "Y");                // 2014 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014 - 2015.01.15 12:34:56
      }
      else if (isFullMonth1 ) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014.01 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014.01 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01 - 2015.01.15 12:34:56
      }
      else if (isFullWeek1  ) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15W - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15W - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15W - 2015.01.15 12:34:56
      }
      else if (isFullDay1   ) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 - 2015.01.15 12:34:56
      }
      else if (isFullHour1  ) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:00 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:00 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:00 - 2015.01.15 12:34:56
      }
      else if (isFullMinute1) {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:34 - 2015.01.15 12:34:56
      }
      else {
         if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015
         else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01
         else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01.15W
         else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01.15
         else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34:56 - 2015.01.15 12:00
         else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34:56 - 2015.01.15 12:34
         else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:34:56 - 2015.01.15 12:34:56
      }
   }
   if (isTotal) comment = comment +" (gesamt)";
   from = dtFrom;
   to   = dtTo;

   if (!StringLen(openComments)) openComments = comment;
   else                          openComments = openComments +", "+ comment;
   return(!catch("CustomPositions.ParseOpenTerm(5)"));
}


/**
 * Parst einen History-Konfigurations-Term (Closed Position).
 *
 * @param  _In_     string   term              - Konfigurations-Term
 * @param  _In_Out_ string   positionComment   - Kommentar der Position (wird bei Gruppierungen nur bei der ersten Gruppe angezeigt)
 * @param  _In_Out_ string   hstComments       - dynamisch generierte History-Kommentare (werden ggf. erweitert)
 * @param  _In_Out_ bool     isEmptyPosition   - ob die aktuelle Position noch leer ist
 * @param  _In_Out_ bool     isGroupedPosition - ob die aktuelle Position eine Gruppierung enth�lt
 * @param  _Out_    bool     isTotalHistory    - ob die History alle verf�gbaren Trades (TRUE) oder nur die des aktuellen Symbols (FALSE) einschlie�t
 * @param  _Out_    datetime from              - Beginnzeitpunkt der zu ber�cksichtigenden History
 * @param  _Out_    datetime to                - Endzeitpunkt der zu ber�cksichtigenden History
 *
 * @return bool - Erfolgsstatus
 *
 *
 * Format:
 * -------
 *  H{DateTime}             [Monthly|Weekly|Daily]    � Trade-History eines Symbols eines Standard-Zeitraums
 *  HT{DateTime}-{DateTime} [Monthly|Weekly|Daily]    � Trade-History aller Symbole von und bis zu einem Zeitpunkt
 *
 *  {DateTime} = 2014[.01[.15 [W|12:34[:56]]]]        oder
 *  {DateTime} = (This|Last)(Day|Week|Month|Year)     oder
 *  {DateTime} = Today                                � Synonym f�r ThisDay
 *  {DateTime} = Yesterday                            � Synonym f�r LastDay
 */
bool CustomPositions.ParseHstTerm(string term, string &positionComment, string &hstComments, bool &isEmptyPosition, bool &isGroupedPosition, bool &isTotalHistory, datetime &from, datetime &to) {
   isEmptyPosition   = isEmptyPosition  !=0;
   isGroupedPosition = isGroupedPosition!=0;
   isTotalHistory    = isTotalHistory   !=0;

   string term.orig = StringTrim(term);
          term      = StringToUpper(term.orig);
   if (!StringStartsWith(term, "H")) return(!catch("CustomPositions.ParseHstTerm(1)  invalid parameter term = "+ DoubleQuoteStr(term.orig) +" (not TERM_HISTORY_*)", ERR_INVALID_PARAMETER));
   term = StringTrim(StringRight(term, -1));

   if     (!StringStartsWith(term, "T"    )) isTotalHistory = false;
   else if (StringStartsWith(term, "THIS" )) isTotalHistory = false;
   else if (StringStartsWith(term, "TODAY")) isTotalHistory = false;
   else                                      isTotalHistory = true;
   if (isTotalHistory) term = StringTrim(StringRight(term, -1));

   bool     isSingleTimespan, groupByDay, groupByWeek, groupByMonth, isFullYear1, isFullYear2, isFullMonth1, isFullMonth2, isFullWeek1, isFullWeek2, isFullDay1, isFullDay2, isFullHour1, isFullHour2, isFullMinute1, isFullMinute2;
   datetime dtFrom, dtTo;
   string   comment = "";


   // (1) auf Group-Modifier pr�fen
   if (StringEndsWith(term, " DAILY")) {
      groupByDay = true;
      term       = StringTrim(StringLeft(term, -6));
   }
   else if (StringEndsWith(term, " WEEKLY")) {
      groupByWeek = true;
      term        = StringTrim(StringLeft(term, -7));
   }
   else if (StringEndsWith(term, " MONTHLY")) {
      groupByMonth = true;
      term         = StringTrim(StringLeft(term, -8));
   }

   bool isGroupingTerm = groupByDay || groupByWeek || groupByMonth;
   if (isGroupingTerm && !isEmptyPosition) return(!catch("CustomPositions.ParseHstTerm(2)  cannot combine grouping configuration "+ DoubleQuoteStr(term.orig) +" with another configuration", ERR_INVALID_CONFIG_PARAMVALUE));
   isGroupedPosition = isGroupedPosition || isGroupingTerm;


   // (2) Beginn- und Endzeitpunkt parsen
   int pos = StringFind(term, "-");
   if (pos >= 0) {                                                   // von-bis parsen
      // {DateTime}-{DateTime}
      // {DateTime}-NULL
      //       NULL-{DateTime}
      dtFrom = ParseDateTime(StringTrim(StringLeft (term,  pos  )), isFullYear1, isFullMonth1, isFullWeek1, isFullDay1, isFullHour1, isFullMinute1); if (IsNaT(dtFrom)) return(false);
      dtTo   = ParseDateTime(StringTrim(StringRight(term, -pos-1)), isFullYear2, isFullMonth2, isFullWeek2, isFullDay2, isFullHour2, isFullMinute2); if (IsNaT(dtTo  )) return(false);
      if (dtTo != NULL) {
         if      (isFullYear2  ) dtTo  = DateTime(TimeYearFix(dtTo)+1)                  - 1*SECOND;   // Jahresende
         else if (isFullMonth2 ) dtTo  = DateTime(TimeYearFix(dtTo), TimeMonth(dtTo)+1) - 1*SECOND;   // Monatsende
         else if (isFullWeek2  ) dtTo += 1*WEEK                                         - 1*SECOND;   // Wochenende
         else if (isFullDay2   ) dtTo += 1*DAY                                          - 1*SECOND;   // Tagesende
         else if (isFullHour2  ) dtTo -=                                                  1*SECOND;   // Ende der vorhergehenden Stunde
       //else if (isFullMinute2) dtTo -=                                                  1*SECOND;   // nicht bei Minuten (deaktiviert)
      }
   }
   else {
      // {DateTime}                                                  // einzelnen Zeitraum parsen
      isSingleTimespan = true;
      dtFrom = ParseDateTime(term, isFullYear1, isFullMonth1, isFullWeek1, isFullDay1, isFullHour1, isFullMinute1); if (IsNaT(dtFrom)) return(false);
                                                                                                                         if (!dtFrom)  return(!catch("CustomPositions.ParseHstTerm(3)  invalid history configuration in "+ DoubleQuoteStr(term.orig), ERR_INVALID_CONFIG_PARAMVALUE));
      if      (isFullYear1  ) dtTo = DateTime(TimeYearFix(dtFrom)+1)                    - 1*SECOND;   // Jahresende
      else if (isFullMonth1 ) dtTo = DateTime(TimeYearFix(dtFrom), TimeMonth(dtFrom)+1) - 1*SECOND;   // Monatsende
      else if (isFullWeek1  ) dtTo = dtFrom + 1*WEEK                                    - 1*SECOND;   // Wochenende
      else if (isFullDay1   ) dtTo = dtFrom + 1*DAY                                     - 1*SECOND;   // Tagesende
      else if (isFullHour1  ) dtTo = dtFrom + 1*HOUR                                    - 1*SECOND;   // Ende der Stunde
      else if (isFullMinute1) dtTo = dtFrom + 1*MINUTE                                  - 1*SECOND;   // Ende der Minute
      else                    dtTo = dtFrom;
   }
   //debug("CustomPositions.ParseHstTerm(0.1)  dtFrom="+ TimeToStr(dtFrom, TIME_FULL) +"  dtTo="+ TimeToStr(dtTo, TIME_FULL) +"  grouped="+ isGroupingTerm);
   if (!dtFrom && !dtTo)      return(!catch("CustomPositions.ParseHstTerm(4)  invalid history configuration in "+ DoubleQuoteStr(term.orig), ERR_INVALID_CONFIG_PARAMVALUE));
   if (dtTo && dtFrom > dtTo) return(!catch("CustomPositions.ParseHstTerm(5)  invalid history configuration in "+ DoubleQuoteStr(term.orig) +" (history start after history end)", ERR_INVALID_CONFIG_PARAMVALUE));


   if (isGroupingTerm) {
      //
      // TODO:  Performance verbessern
      //

      // (3) Gruppen anlegen und komplette Zeilen direkt hier einf�gen (bei der letzten Gruppe jedoch ohne Zeilenende)
      datetime groupFrom, groupTo, nextGroupFrom, now=TimeCurrentEx("CustomPositions.ParseHstTerm(6)");
      if      (groupByMonth) groupFrom = DateTime(TimeYearFix(dtFrom), TimeMonth(dtFrom));
      else if (groupByWeek ) groupFrom = dtFrom - dtFrom%DAYS - (TimeDayOfWeekFix(dtFrom)+6)%7 * DAYS;
      else if (groupByDay  ) groupFrom = dtFrom - dtFrom%DAYS;

      if (!dtTo) {                                                                                       // {DateTime} - NULL
         if      (groupByMonth) dtTo = DateTime(TimeYearFix(now), TimeMonth(now)+1)        - 1*SECOND;   // aktuelles Monatsende
         else if (groupByWeek ) dtTo = now - now%DAYS + (7-TimeDayOfWeekFix(now))%7 * DAYS - 1*SECOND;   // aktuelles Wochenende
         else if (groupByDay  ) dtTo = now - now%DAYS + 1*DAY                              - 1*SECOND;   // aktuelles Tagesende
      }

      for (bool firstGroup=true; groupFrom < dtTo; groupFrom=nextGroupFrom) {
         if      (groupByMonth) nextGroupFrom = DateTime(TimeYearFix(groupFrom), TimeMonth(groupFrom)+1);
         else if (groupByWeek ) nextGroupFrom = groupFrom + 7*DAYS;
         else if (groupByDay  ) nextGroupFrom = groupFrom + 1*DAY;
         groupTo   = nextGroupFrom - 1*SECOND;
         groupFrom = Max(groupFrom, dtFrom);
         groupTo   = Min(groupTo,   dtTo  );
         //debug("ParseHstTerm(0.2)  group from="+ TimeToStr(groupFrom) +"  to="+ TimeToStr(groupTo));

         // Kommentar erstellen
         if      (groupByMonth) comment =               DateTimeToStr(groupFrom, "Y O");
         else if (groupByWeek ) comment = "Woche vom "+ DateTimeToStr(groupFrom, "D.M.Y");
         else if (groupByDay  ) comment =               DateTimeToStr(groupFrom, "D.M.Y");
         if (isTotalHistory)    comment = comment +" (gesamt)";

         // Gruppe der globalen Konfiguration hinzuf�gen
         int confSize = ArrayRange(positions.config, 0);
         ArrayResize(positions.config, confSize+1);
         positions.config[confSize][0] = ifInt(!isTotalHistory, TERM_HISTORY_SYMBOL, TERM_HISTORY_ALL);
         positions.config[confSize][1] = groupFrom;
         positions.config[confSize][2] = groupTo;
         positions.config[confSize][3] = EMPTY_VALUE;
         positions.config[confSize][4] = EMPTY_VALUE;
         isEmptyPosition = false;

         // Zeile mit Zeilenende abschlie�en (au�er bei der letzten Gruppe)
         if (nextGroupFrom <= dtTo) {
            ArrayResize    (positions.config, confSize+2);           // initialisiert Element mit NULL
            ArrayPushString(positions.config.comments, comment + ifString(StringLen(positionComment), ", ", "") + positionComment);
            if (firstGroup) positionComment = "";                    // f�r folgende Gruppen wird der konfigurierte Kommentar nicht st�ndig wiederholt
         }
      }
   }
   else {
      // (4) normale R�ckgabewerte ohne Gruppierung
      if (isSingleTimespan) {
         if      (isFullYear1  ) comment =               DateTimeToStr(dtFrom, "Y");
         else if (isFullMonth1 ) comment =               DateTimeToStr(dtFrom, "Y O");
         else if (isFullWeek1  ) comment = "Woche vom "+ DateTimeToStr(dtFrom, "D.M.Y");
         else if (isFullDay1   ) comment =               DateTimeToStr(dtFrom, "D.M.Y");
         else if (isFullHour1  ) comment =               DateTimeToStr(dtFrom, "D.M.Y H:I") + DateTimeToStr(dtTo+1*SECOND, "-H:I");
         else if (isFullMinute1) comment =               DateTimeToStr(dtFrom, "D.M.Y H:I");
         else                    comment =               DateTimeToStr(dtFrom, "D.M.Y H:I:S");
      }
      else if (!dtTo) {
         if      (isFullYear1  ) comment = "seit "+      DateTimeToStr(dtFrom, "Y");
         else if (isFullMonth1 ) comment = "seit "+      DateTimeToStr(dtFrom, "O Y");
         else if (isFullWeek1  ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y");
         else if (isFullDay1   ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y");
         else if (isFullHour1  ) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I");
         else if (isFullMinute1) comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I");
         else                    comment = "seit "+      DateTimeToStr(dtFrom, "D.M.Y H:I:S");
      }
      else if (!dtFrom) {
         if      (isFullYear2  ) comment =  "bis "+      DateTimeToStr(dtTo,          "Y");
         else if (isFullMonth2 ) comment =  "bis "+      DateTimeToStr(dtTo,          "O Y");
         else if (isFullWeek2  ) comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y");
         else if (isFullDay2   ) comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y");
         else if (isFullHour2  ) comment =  "bis "+      DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");
         else if (isFullMinute2) comment =  "bis "+      DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");
         else                    comment =  "bis "+      DateTimeToStr(dtTo,          "D.M.Y H:I:S");
      }
      else {
         // von und bis angegeben
         if      (isFullYear1  ) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "Y")           +" bis "+ DateTimeToStr(dtTo,          "Y");                // 2014 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014 - 2015.01.15 12:34:56
         }
         else if (isFullMonth1 ) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014.01 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "O Y")         +" bis "+ DateTimeToStr(dtTo,          "O Y");              // 2014.01 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01 - 2015.01.15 12:34:56
         }
         else if (isFullWeek1  ) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15W - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15W - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15W - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15W - 2015.01.15 12:34:56
         }
         else if (isFullDay1   ) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y")       +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 - 2015.01.15 12:34:56
         }
         else if (isFullHour1  ) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:00 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:00 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:00 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:00 - 2015.01.15 12:34:56
         }
         else if (isFullMinute1) {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I")   +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:34 - 2015.01.15 12:34:56
         }
         else {
            if      (isFullYear2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015
            else if (isFullMonth2 ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01
            else if (isFullWeek2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01.15W
            else if (isFullDay2   ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y");            // 2014.01.15 12:34:56 - 2015.01.15
            else if (isFullHour2  ) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34:56 - 2015.01.15 12:00
            else if (isFullMinute2) comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo+1*SECOND, "D.M.Y H:I");        // 2014.01.15 12:34:56 - 2015.01.15 12:34
            else                    comment = DateTimeToStr(dtFrom, "D.M.Y H:I:S") +" bis "+ DateTimeToStr(dtTo,          "D.M.Y H:I:S");      // 2014.01.15 12:34:56 - 2015.01.15 12:34:56
         }
      }
      if (isTotalHistory) comment = comment +" (gesamt)";
      from = dtFrom;
      to   = dtTo;
   }

   if (!StringLen(hstComments)) hstComments = comment;
   else                         hstComments = hstComments +", "+ comment;
   return(!catch("CustomPositions.ParseHstTerm(7)"));
}


/**
 * Parst eine Zeitpunktbeschreibung. Kann ein allgemeiner Zeitraum (2014.03) oder ein genauer Zeitpunkt (2014.03.12 12:34:56) sein.
 *
 * @param  _In_  string value    - zu parsender String
 * @param  _Out_ bool   isYear   - ob ein allgemein formulierter Zeitraum ein Jahr beschreibt,    z.B. "2014"        oder "ThisYear"
 * @param  _Out_ bool   isMonth  - ob ein allgemein formulierter Zeitraum einen Monat beschreibt, z.B. "2014.02"     oder "LastMonth"
 * @param  _Out_ bool   isWeek   - ob ein allgemein formulierter Zeitraum eine Woche beschreibt,  z.B. "2014.02.15W" oder "ThisWeek"
 * @param  _Out_ bool   isDay    - ob ein allgemein formulierter Zeitraum einen Tag beschreibt,   z.B. "2014.02.18"  oder "Yesterday" (Synonym f�r LastDay)
 * @param  _Out_ bool   isHour   - ob ein allgemein formulierter Zeitraum eine Stunde beschreibt, z.B. "2014.02.18 12:00"
 * @param  _Out_ bool   isMinute - ob ein allgemein formulierter Zeitraum eine Minute beschreibt, z.B. "2014.02.18 12:34"
 *
 * @return datetime - Zeitpunkt oder NaT (Not-A-Time), falls ein Fehler auftrat
 *
 *
 * Format:
 * -------
 *  {value} = 2014[.01[.15 [W|12:34[:56]]]]        oder
 *  {value} = (This|Last)(Day|Week|Month|Year)     oder
 *  {value} = Today                                � Synonym f�r ThisDay
 *  {value} = Yesterday                            � Synonym f�r LastDay
 */
datetime ParseDateTime(string value, bool &isYear, bool &isMonth, bool &isWeek, bool &isDay, bool &isHour, bool &isMinute) {
   string   value.orig=value, values[], sYY, sMM, sDD, sTime, sHH, sII, sSS;
   int      valuesSize, iYY, iMM, iDD, iHH, iII, iSS, dow;

   static datetime now;
          datetime date;

   value = StringTrim(value);
   if (!StringLen(value)) return(NULL);

   isYear   = false;
   isMonth  = false;
   isWeek   = false;
   isDay    = false;
   isHour   = false;
   isMinute = false;


   // (1) Ausdruck parsen
   if (!StringIsDigit(StringLeft(value, 1))) {
      if (!now) now = TimeFXT(); if (!now) return(NaT);

      // (1.1) alphabetischer Ausdruck
      if (StringEndsWith(value, "DAY")) {
         if      (value == "TODAY"    ) value = "THISDAY";
         else if (value == "YESTERDAY") value = "LASTDAY";

         date = now;
         dow  = TimeDayOfWeekFix(date);
         if      (dow == SATURDAY) date -= 1*DAY;                    // an Wochenenden Datum auf den vorherigen Freitag setzen
         else if (dow == SUNDAY  ) date -= 2*DAYS;

         if (value != "THISDAY") {
            if (value != "LASTDAY")                                  return(_NaT(catch("ParseDateTime(1)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            if (dow != MONDAY) date -= 1*DAY;                        // Datum auf den vorherigen Tag setzen
            else               date -= 3*DAYS;                       // an Wochenenden Datum auf den vorherigen Freitag setzen
         }
         iYY   = TimeYearFix(date);
         iMM   = TimeMonth  (date);
         iDD   = TimeDayFix (date);
         isDay = true;
      }

      else if (StringEndsWith(value, "WEEK")) {
         date = now - (TimeDayOfWeekFix(now)+6)%7 * DAYS;            // Datum auf Wochenbeginn setzen
         if (value != "THISWEEK") {
            if (value != "LASTWEEK")                                 return(_NaT(catch("ParseDateTime(1)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            date -= 1*WEEK;                                          // Datum auf die vorherige Woche setzen
         }
         iYY    = TimeYearFix(date);
         iMM    = TimeMonth  (date);
         iDD    = TimeDayFix (date);
         isWeek = true;
      }

      else if (StringEndsWith(value, "MONTH")) {
         date = now;
         if (value != "THISMONTH") {
            if (value != "LASTMONTH")                                return(_NaT(catch("ParseDateTime(1)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            date = DateTime(TimeYearFix(date), TimeMonth(date)-1);   // Datum auf den vorherigen Monat setzen
         }
         iYY     = TimeYearFix(date);
         iMM     = TimeMonth  (date);
         iDD     = 1;
         isMonth = true;
      }

      else if (StringEndsWith(value, "YEAR")) {
         date = now;
         if (value != "THISYEAR") {
            if (value != "LASTYEAR")                                 return(_NaT(catch("ParseDateTime(1)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            date = DateTime(TimeYearFix(date)-1);                    // Datum auf das vorherige Jahr setzen
         }
         iYY    = TimeYearFix(date);
         iMM    = 1;
         iDD    = 1;
         isYear = true;
      }
      else                                                           return(_NaT(catch("ParseDateTime(1)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
   }

   else {
      // (1.2) numerischer Ausdruck
      // 2014
      // 2014.01
      // 2014.01.15
      // 2014.01.15W
      // 2014.01.15 12:34
      // 2014.01.15 12:34:56
      valuesSize = Explode(value, ".", values, NULL);
      if (valuesSize > 3)                                            return(_NaT(catch("ParseDateTime(2)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));

      if (valuesSize >= 1) {
         sYY = StringTrim(values[0]);                                // Jahr pr�fen
         if (StringLen(sYY) != 4)                                    return(_NaT(catch("ParseDateTime(3)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (!StringIsDigit(sYY))                                    return(_NaT(catch("ParseDateTime(4)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         iYY = StrToInteger(sYY);
         if (iYY < 1970 || 2037 < iYY)                               return(_NaT(catch("ParseDateTime(5)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (valuesSize == 1) {
            iMM    = 1;
            iDD    = 1;
            isYear = true;
         }
      }

      if (valuesSize >= 2) {
         sMM = StringTrim(values[1]);                                // Monat pr�fen
         if (StringLen(sMM) > 2)                                     return(_NaT(catch("ParseDateTime(6)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (!StringIsDigit(sMM))                                    return(_NaT(catch("ParseDateTime(7)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         iMM = StrToInteger(sMM);
         if (iMM < 1 || 12 < iMM)                                    return(_NaT(catch("ParseDateTime(8)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (valuesSize == 2) {
            iDD     = 1;
            isMonth = true;
         }
      }

      if (valuesSize == 3) {
         sDD = StringTrim(values[2]);
         if (StringEndsWith(sDD, "W")) {                             // Tag + Woche: "2014.01.15 W"
            isWeek = true;
            sDD    = StringTrim(StringLeft(sDD, -1));
         }
         else if (StringLen(sDD) > 2) {                              // Tag + Zeit:  "2014.01.15 12:34:56"
            int pos = StringFind(sDD, " ");
            if (pos == -1)                                           return(_NaT(catch("ParseDateTime(9)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            sTime = StringTrim(StringRight(sDD, -pos-1));
            sDD   = StringTrim(StringLeft (sDD,  pos  ));
         }
         else {                                                      // nur Tag
            isDay = true;
         }
                                                                     // Tag pr�fen
         if (StringLen(sDD) > 2)                                     return(_NaT(catch("ParseDateTime(10)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (!StringIsDigit(sDD))                                    return(_NaT(catch("ParseDateTime(11)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         iDD = StrToInteger(sDD);
         if (iDD < 1 || 31 < iDD)                                    return(_NaT(catch("ParseDateTime(12)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         if (iDD > 28) {
            if (iMM == FEB) {
               if (iDD > 29)                                         return(_NaT(catch("ParseDateTime(13)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
               if (!IsLeapYear(iYY))                                 return(_NaT(catch("ParseDateTime(14)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            }
            else if (iDD==31)
               if (iMM==APR || iMM==JUN || iMM==SEP || iMM==NOV)     return(_NaT(catch("ParseDateTime(15)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
         }

         if (StringLen(sTime) > 0) {                                 // Zeit pr�fen
            // hh:ii:ss
            valuesSize = Explode(sTime, ":", values, NULL);
            if (valuesSize < 2 || 3 < valuesSize)                    return(_NaT(catch("ParseDateTime(16)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));

            sHH = StringTrim(values[0]);                             // Stunden
            if (StringLen(sHH) > 2)                                  return(_NaT(catch("ParseDateTime(17)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            if (!StringIsDigit(sHH))                                 return(_NaT(catch("ParseDateTime(18)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            iHH = StrToInteger(sHH);
            if (iHH < 0 || 23 < iHH)                                 return(_NaT(catch("ParseDateTime(19)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));

            sII = StringTrim(values[1]);                             // Minuten
            if (StringLen(sII) > 2)                                  return(_NaT(catch("ParseDateTime(20)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            if (!StringIsDigit(sII))                                 return(_NaT(catch("ParseDateTime(21)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            iII = StrToInteger(sII);
            if (iII < 0 || 59 < iII)                                 return(_NaT(catch("ParseDateTime(22)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            if (valuesSize == 2) {
               if (!iII) isHour   = true;
               else      isMinute = true;
            }

            if (valuesSize == 3) {
               sSS = StringTrim(values[2]);                          // Sekunden
               if (StringLen(sSS) > 2)                               return(_NaT(catch("ParseDateTime(23)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
               if (!StringIsDigit(sSS))                              return(_NaT(catch("ParseDateTime(24)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
               iSS = StrToInteger(sSS);
               if (iSS < 0 || 59 < iSS)                              return(_NaT(catch("ParseDateTime(25)  invalid history configuration in "+ DoubleQuoteStr(value.orig), ERR_INVALID_CONFIG_PARAMVALUE)));
            }
         }
      }
   }


   // (2) DateTime aus geparsten Werten erzeugen
   datetime result = DateTime(iYY, iMM, iDD, iHH, iII, iSS);
   if (isWeek)                                                       // wenn volle Woche, dann Zeit auf Wochenbeginn setzen
      result -= (TimeDayOfWeekFix(result)+6)%7 * DAYS;
   return(result);
}


/**
 * Extrahiert aus dem Bestand der �bergebenen Positionen {fromVars} eine Teilposition und f�gt sie dem Bestand einer CustomPosition {customVars} hinzu.
 *
 *                                                                     -+    struct POSITION_CONFIG_TERM {
 * @param  _In_     int     type           - zu extrahierender Typ      |       double type;
 * @param  _In_     double  value1         - zu extrahierende Lotsize   |       double confValue1;
 * @param  _In_     double  value2         - Preis/Betrag/Equity        +->     double confValue2;
 * @param  _In_Out_ double &cache1         - Zwischenspeicher 1         |       double cacheValue1;
 * @param  _In_Out_ double &cache2         - Zwischenspeicher 2         |       double cacheValue2;
 *                                                                     -+    };
 *
 * @param  _In_Out_ mixed &fromVars        - Variablen, aus denen die Teilposition extrahiert wird (Bestand verringert sich)
 * @param  _In_Out_ mixed &customVars      - Variablen, denen die extrahierte Position hinzugef�gt wird (Bestand erh�ht sich)
 * @param  _In_Out_ bool  &isCustomVirtual - ob die resultierende CustomPosition virtuell ist
 *
 * @return bool - Erfolgsstatus
 */
bool ExtractPosition(int type, double value1, double value2, double &cache1, double &cache2,
                     double &longPosition,       double &shortPosition,       double &totalPosition,       int &tickets[],       int &types[],       double &lots[],       datetime &openTimes[], double &openPrices[],       double &commissions[],       double &swaps[],       double &profits[],
                     double &customLongPosition, double &customShortPosition, double &customTotalPosition, int &customTickets[], int &customTypes[], double &customLots[],                        double &customOpenPrices[], double &customCommissions[], double &customSwaps[], double &customProfits[], double &closedProfit, double &adjustedProfit, double &customEquity,
                     bool   &isCustomVirtual) {
   isCustomVirtual = isCustomVirtual!=0;

   double   lotsize;
   datetime from, to;
   int sizeTickets = ArraySize(tickets);

   if (type == TERM_OPEN_LONG) {
      lotsize = value1;

      if (lotsize == EMPTY) {
         // alle �brigen Long-Positionen
         if (longPosition > 0) {
            for (int i=0; i < sizeTickets; i++) {
               if (!tickets[i])
                  continue;
               if (types[i] == OP_BUY) {
                  // Daten nach custom.* �bernehmen und Ticket ggf. auf NULL setzen
                  ArrayPushInt   (customTickets,     tickets    [i]);
                  ArrayPushInt   (customTypes,       types      [i]);
                  ArrayPushDouble(customLots,        lots       [i]);
                  ArrayPushDouble(customOpenPrices,  openPrices [i]);
                  ArrayPushDouble(customCommissions, commissions[i]);
                  ArrayPushDouble(customSwaps,       swaps      [i]);
                  ArrayPushDouble(customProfits,     profits    [i]);
                  if (!isCustomVirtual) {
                     longPosition  = NormalizeDouble(longPosition - lots[i],       2);
                     totalPosition = NormalizeDouble(longPosition - shortPosition, 2);
                     tickets[i]    = NULL;
                  }
                  customLongPosition  = NormalizeDouble(customLongPosition + lots[i],             3);
                  customTotalPosition = NormalizeDouble(customLongPosition - customShortPosition, 3);
               }
            }
         }
      }
      else {
         // virtuelle Long-Position zu custom.* hinzuf�gen (Ausgangsdaten bleiben unver�ndert)
         if (lotsize != 0) {                                         // 0-Lots-Positionen werden �bersprungen (es gibt nichts abzuziehen oder hinzuzuf�gen)
            double openPrice = ifDouble(value2, value2, Ask);
            ArrayPushInt   (customTickets,     TERM_OPEN_LONG                                );
            ArrayPushInt   (customTypes,       OP_BUY                                        );
            ArrayPushDouble(customLots,        lotsize                                       );
            ArrayPushDouble(customOpenPrices,  openPrice                                     );
            ArrayPushDouble(customCommissions, NormalizeDouble(-GetCommission() * lotsize, 2));
            ArrayPushDouble(customSwaps,       0                                             );
            ArrayPushDouble(customProfits,     (Bid-openPrice)/Pips * PipValue(lotsize, true)); // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
            customLongPosition  = NormalizeDouble(customLongPosition + lotsize,             3);
            customTotalPosition = NormalizeDouble(customLongPosition - customShortPosition, 3);
         }
         isCustomVirtual = true;
      }
   }

   else if (type == TERM_OPEN_SHORT) {
      lotsize = value1;

      if (lotsize == EMPTY) {
         // alle �brigen Short-Positionen
         if (shortPosition > 0) {
            for (i=0; i < sizeTickets; i++) {
               if (!tickets[i])
                  continue;
               if (types[i] == OP_SELL) {
                  // Daten nach custom.* �bernehmen und Ticket ggf. auf NULL setzen
                  ArrayPushInt   (customTickets,     tickets    [i]);
                  ArrayPushInt   (customTypes,       types      [i]);
                  ArrayPushDouble(customLots,        lots       [i]);
                  ArrayPushDouble(customOpenPrices,  openPrices [i]);
                  ArrayPushDouble(customCommissions, commissions[i]);
                  ArrayPushDouble(customSwaps,       swaps      [i]);
                  ArrayPushDouble(customProfits,     profits    [i]);
                  if (!isCustomVirtual) {
                     shortPosition = NormalizeDouble(shortPosition - lots[i],       2);
                     totalPosition = NormalizeDouble(longPosition  - shortPosition, 2);
                     tickets[i]    = NULL;
                  }
                  customShortPosition = NormalizeDouble(customShortPosition + lots[i],             3);
                  customTotalPosition = NormalizeDouble(customLongPosition  - customShortPosition, 3);
               }
            }
         }
      }
      else {
         // virtuelle Short-Position zu custom.* hinzuf�gen (Ausgangsdaten bleiben unver�ndert)
         if (lotsize != 0) {                                         // 0-Lots-Positionen werden �bersprungen (es gibt nichts abzuziehen oder hinzuzuf�gen)
            openPrice = ifDouble(value2, value2, Bid);
            ArrayPushInt   (customTickets,     TERM_OPEN_SHORT                               );
            ArrayPushInt   (customTypes,       OP_SELL                                       );
            ArrayPushDouble(customLots,        lotsize                                       );
            ArrayPushDouble(customOpenPrices,  openPrice                                     );
            ArrayPushDouble(customCommissions, NormalizeDouble(-GetCommission() * lotsize, 2));
            ArrayPushDouble(customSwaps,       0                                             );
            ArrayPushDouble(customProfits,     (openPrice-Ask)/Pips * PipValue(lotsize, true)); // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
            customShortPosition = NormalizeDouble(customShortPosition + lotsize,            3);
            customTotalPosition = NormalizeDouble(customLongPosition - customShortPosition, 3);
         }
         isCustomVirtual = true;
      }
   }

   else if (type == TERM_OPEN_SYMBOL) {
      from = value1;
      to   = value2;

      // offene Positionen des aktuellen Symbols eines Zeitraumes
      if (longPosition || shortPosition) {
         for (i=0; i < sizeTickets; i++) {
            if (!tickets[i])                 continue;
            if (from && openTimes[i] < from) continue;
            if (to   && openTimes[i] > to  ) continue;

            // Daten nach custom.* �bernehmen und Ticket ggf. auf NULL setzen
            ArrayPushInt   (customTickets,     tickets    [i]);
            ArrayPushInt   (customTypes,       types      [i]);
            ArrayPushDouble(customLots,        lots       [i]);
            ArrayPushDouble(customOpenPrices,  openPrices [i]);
            ArrayPushDouble(customCommissions, commissions[i]);
            ArrayPushDouble(customSwaps,       swaps      [i]);
            ArrayPushDouble(customProfits,     profits    [i]);
            if (!isCustomVirtual) {
               if (types[i] == OP_BUY) longPosition     = NormalizeDouble(longPosition  - lots[i]      , 2);
               else                    shortPosition    = NormalizeDouble(shortPosition - lots[i]      , 2);
                                       totalPosition    = NormalizeDouble(longPosition  - shortPosition, 2);
                                       tickets[i]       = NULL;
            }
            if (types[i] == OP_BUY) customLongPosition  = NormalizeDouble(customLongPosition  + lots[i]            , 3);
            else                    customShortPosition = NormalizeDouble(customShortPosition + lots[i]            , 3);
                                    customTotalPosition = NormalizeDouble(customLongPosition  - customShortPosition, 3);
         }
      }
   }

   else if (type == TERM_OPEN_ALL) {
      // offene Positionen aller Symbole eines Zeitraumes
      warn("ExtractPosition(1)  type=TERM_OPEN_ALL not yet implemented");
   }

   else if (type==TERM_HISTORY_SYMBOL || type==TERM_HISTORY_ALL) {
      // geschlossene Positionen des aktuellen oder aller Symbole eines Zeitraumes
      from              = value1;
      to                = value2;
      double lastProfit = cache1;      // default: EMPTY_VALUE
      int    lastOrders = cache2;      // default: EMPTY_VALUE                // Anzahl der Tickets in der History: �ndert sie sich, wird der Profit neu berechnet

      int orders=OrdersHistoryTotal(), _orders=orders;

      if (orders != lastOrders) {
         // (1) Sortierschl�ssel aller geschlossenen Positionen auslesen und nach {CloseTime, OpenTime, Ticket} sortieren
         int sortKeys[][3], n, hst.ticket;                                    // {CloseTime, OpenTime, Ticket}
         ArrayResize(sortKeys, orders);

         for (i=0; i < orders; i++) {
            if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))                 // FALSE: w�hrend des Auslesens wurde der Anzeigezeitraum der History verk�rzt
               break;

            // wenn OrderType()==OP_BALANCE, dann OrderSymbol()==Leerstring
            if (OrderType() == OP_BALANCE) {
               // Dividenden                                                  // "Ex Dividend US2000" oder
               if (StringStartsWithI(OrderComment(), "ex dividend ")) {       // "Ex Dividend 17/03/15 US2000"
                  if (type == TERM_HISTORY_SYMBOL)                            // single history
                     if (!StringEndsWithI(OrderComment(), " "+ Symbol()))     // ok, wenn zum aktuellen Symbol geh�rend
                        continue;
               }
               // Rollover adjustments
               else if (StringStartsWithI(OrderComment(), "adjustment ")) {   // "Adjustment BRENT"
                  if (type == TERM_HISTORY_SYMBOL)                            // single history
                     if (!StringEndsWithI(OrderComment(), " "+ Symbol()))     // ok, wenn zum aktuellen Symbol geh�rend
                        continue;
               }
               else {
                  continue;                                                   // sonstige Balance-Eintr�ge
               }
            }

            else {
               if (OrderType() > OP_SELL)                                         continue;
               if (type==TERM_HISTORY_SYMBOL) /*&&*/ if (OrderSymbol()!=Symbol()) continue;  // ggf. Positionen aller Symbole
            }

            sortKeys[n][0] = OrderCloseTime();
            sortKeys[n][1] = OrderOpenTime();
            sortKeys[n][2] = OrderTicket();
            n++;
         }
         orders = n;
         ArrayResize(sortKeys, orders);
         SortClosedTickets(sortKeys);

         // (2) Tickets sortiert einlesen
         int      hst.tickets    []; ArrayResize(hst.tickets    , 0);
         int      hst.types      []; ArrayResize(hst.types      , 0);
         double   hst.lotSizes   []; ArrayResize(hst.lotSizes   , 0);
         datetime hst.openTimes  []; ArrayResize(hst.openTimes  , 0);
         datetime hst.closeTimes []; ArrayResize(hst.closeTimes , 0);
         double   hst.openPrices []; ArrayResize(hst.openPrices , 0);
         double   hst.closePrices[]; ArrayResize(hst.closePrices, 0);
         double   hst.commissions[]; ArrayResize(hst.commissions, 0);
         double   hst.swaps      []; ArrayResize(hst.swaps      , 0);
         double   hst.profits    []; ArrayResize(hst.profits    , 0);
         string   hst.comments   []; ArrayResize(hst.comments   , 0);

         for (i=0; i < orders; i++) {
            if (!SelectTicket(sortKeys[i][2], "ExtractPosition(2)"))
               return(false);
            ArrayPushInt   (hst.tickets    , OrderTicket()    );
            ArrayPushInt   (hst.types      , OrderType()      );
            ArrayPushDouble(hst.lotSizes   , OrderLots()      );
            ArrayPushInt   (hst.openTimes  , OrderOpenTime()  );
            ArrayPushInt   (hst.closeTimes , OrderCloseTime() );
            ArrayPushDouble(hst.openPrices , OrderOpenPrice() );
            ArrayPushDouble(hst.closePrices, OrderClosePrice());
            ArrayPushDouble(hst.commissions, OrderCommission());
            ArrayPushDouble(hst.swaps      , OrderSwap()      );
            ArrayPushDouble(hst.profits    , OrderProfit()    );
            ArrayPushString(hst.comments   , OrderComment()   );
         }

         // (3) Hedges korrigieren: alle Daten dem ersten Ticket zuordnen und hedgendes Ticket verwerfen (auch Positionen mehrerer Symbole werden korrekt zugeordnet)
         for (i=0; i < orders; i++) {
            if (hst.tickets[i] && EQ(hst.lotSizes[i], 0)) {          // lotSize = 0: Hedge-Position
               // TODO: Pr�fen, wie sich OrderComment() bei custom comments verh�lt.
               if (!StringStartsWithI(hst.comments[i], "close hedge by #"))
                  return(!catch("ExtractPosition(3)  #"+ hst.tickets[i] +" - unknown comment for assumed hedging position "+ DoubleQuoteStr(hst.comments[i]), ERR_RUNTIME_ERROR));

               // Gegenst�ck suchen
               hst.ticket = StrToInteger(StringSubstr(hst.comments[i], 16));
               for (n=0; n < orders; n++) {
                  if (hst.tickets[n] == hst.ticket)
                     break;
               }
               if (n == orders) return(!catch("ExtractPosition(4)  cannot find counterpart for hedging position #"+ hst.tickets[i] +" "+ DoubleQuoteStr(hst.comments[i]), ERR_RUNTIME_ERROR));
               if (i == n     ) return(!catch("ExtractPosition(5)  both hedged and hedging position have the same ticket #"+ hst.tickets[i] +" "+ DoubleQuoteStr(hst.comments[i]), ERR_RUNTIME_ERROR));

               int first  = Min(i, n);
               int second = Max(i, n);

               // Orderdaten korrigieren
               if (i == first) {
                  hst.lotSizes   [first] = hst.lotSizes   [second];              // alle Transaktionsdaten in der ersten Order speichern
                  hst.commissions[first] = hst.commissions[second];
                  hst.swaps      [first] = hst.swaps      [second];
                  hst.profits    [first] = hst.profits    [second];
               }
               hst.closeTimes [first] = hst.openTimes [second];
               hst.closePrices[first] = hst.openPrices[second];
               hst.tickets   [second] = NULL;                                    // hedgendes Ticket als verworfen markieren
            }
         }

         // (4) Trades auswerten
         lastProfit=0; n=0;
         for (i=0; i < orders; i++) {
            if (!hst.tickets[i])                  continue;                      // verworfene Hedges �berspringen
            if (from && hst.closeTimes[i] < from) continue;
            if (to   && hst.closeTimes[i] > to  ) continue;
            lastProfit += hst.commissions[i] + hst.swaps[i] + hst.profits[i];
            n++;
         }
         if (!n) lastProfit = EMPTY_VALUE;                                       // keine passenden geschlossenen Trades gefunden
         else    lastProfit = NormalizeDouble(lastProfit, 2);
         cache1             = lastProfit;
         cache2             = _orders;
         //debug("ExtractPosition(6)  from="+ ifString(from, TimeToStr(from), "start") +"  to="+ ifString(to, TimeToStr(to), "end") +"  profit="+ ifString(IsEmptyValue(lastProfit), "empty", DoubleToStr(lastProfit, 2)) +"  closed trades="+ n);
      }
      // lastProfit zu closedProfit hinzuf�gen, wenn geschlossene Trades existierten (Ausgangsdaten bleiben unver�ndert)
      if (lastProfit != EMPTY_VALUE) {
         if (closedProfit == EMPTY_VALUE) closedProfit  = lastProfit;
         else                             closedProfit += lastProfit;
      }
   }

   else if (type == TERM_ADJUSTMENT) {
      // Betrag zu adjustedProfit hinzuf�gen (Ausgangsdaten bleiben unver�ndert)
      adjustedProfit += value1;
   }

   else if (type == TERM_EQUITY) {
      // vorhandenen Betrag �berschreiben (Ausgangsdaten bleiben unver�ndert)
      customEquity = value1;
   }

   else { // type = Ticket
      lotsize = value1;

      if (lotsize == EMPTY) {
         // komplettes Ticket
         for (i=0; i < sizeTickets; i++) {
            if (tickets[i] == type) {
               // Daten nach custom.* �bernehmen und Ticket ggf. auf NULL setzen
               ArrayPushInt   (customTickets,     tickets    [i]);
               ArrayPushInt   (customTypes,       types      [i]);
               ArrayPushDouble(customLots,        lots       [i]);
               ArrayPushDouble(customOpenPrices,  openPrices [i]);
               ArrayPushDouble(customCommissions, commissions[i]);
               ArrayPushDouble(customSwaps,       swaps      [i]);
               ArrayPushDouble(customProfits,     profits    [i]);
               if (!isCustomVirtual) {
                  if (types[i] == OP_BUY) longPosition        = NormalizeDouble(longPosition  - lots[i],       2);
                  else                    shortPosition       = NormalizeDouble(shortPosition - lots[i],       2);
                                          totalPosition       = NormalizeDouble(longPosition  - shortPosition, 2);
                                          tickets[i]          = NULL;
               }
               if (types[i] == OP_BUY)    customLongPosition  = NormalizeDouble(customLongPosition  + lots[i],             3);
               else                       customShortPosition = NormalizeDouble(customShortPosition + lots[i],             3);
                                          customTotalPosition = NormalizeDouble(customLongPosition  - customShortPosition, 3);
               break;
            }
         }
      }
      else if (lotsize != 0) {                                       // 0-Lots-Positionen werden �bersprungen (es gibt nichts abzuziehen oder hinzuzuf�gen)
         // partielles Ticket
         for (i=0; i < sizeTickets; i++) {
            if (tickets[i] == type) {
               if (GT(lotsize, lots[i])) return(!catch("ExtractPosition(7)  illegal partial lotsize "+ NumberToStr(lotsize, ".+") +" for ticket #"+ tickets[i] +" (only "+ NumberToStr(lots[i], ".+") +" lot remaining)", ERR_RUNTIME_ERROR));
               if (EQ(lotsize, lots[i])) {
                  // komplettes Ticket �bernehmen
                  if (!ExtractPosition(type, EMPTY, value2, cache1, cache2,
                                       longPosition,       shortPosition,       totalPosition,       tickets,       types,       lots,       openTimes, openPrices,       commissions,       swaps,       profits,
                                       customLongPosition, customShortPosition, customTotalPosition, customTickets, customTypes, customLots,            customOpenPrices, customCommissions, customSwaps, customProfits, closedProfit, adjustedProfit, customEquity,
                                       isCustomVirtual))
                     return(false);
               }
               else {
                  // Daten anteilig nach custom.* �bernehmen und Ticket ggf. reduzieren
                  double factor = lotsize/lots[i];
                  ArrayPushInt   (customTickets,     tickets    [i]         );
                  ArrayPushInt   (customTypes,       types      [i]         );
                  ArrayPushDouble(customLots,        lotsize                ); if (!isCustomVirtual) lots       [i]  = NormalizeDouble(lots[i]-lotsize, 2); // reduzieren
                  ArrayPushDouble(customOpenPrices,  openPrices [i]         );
                  ArrayPushDouble(customSwaps,       swaps      [i]         ); if (!isCustomVirtual) swaps      [i]  = NULL;                                // komplett
                  ArrayPushDouble(customCommissions, commissions[i] * factor); if (!isCustomVirtual) commissions[i] *= (1-factor);                          // anteilig
                  ArrayPushDouble(customProfits,     profits    [i] * factor); if (!isCustomVirtual) profits    [i] *= (1-factor);                          // anteilig
                  if (!isCustomVirtual) {
                     if (types[i] == OP_BUY) longPosition        = NormalizeDouble(longPosition  - lotsize, 2);
                     else                    shortPosition       = NormalizeDouble(shortPosition - lotsize, 2);
                                             totalPosition       = NormalizeDouble(longPosition  - shortPosition, 2);
                  }
                  if (types[i] == OP_BUY)    customLongPosition  = NormalizeDouble(customLongPosition  + lotsize, 3);
                  else                       customShortPosition = NormalizeDouble(customShortPosition + lotsize, 3);
                                             customTotalPosition = NormalizeDouble(customLongPosition  - customShortPosition, 3);
               }
               break;
            }
         }
      }
   }
   return(!catch("ExtractPosition(8)"));
}


/**
 * Speichert die �bergebenen Daten zusammengefa�t (direktionaler und gehedgeter Anteil gemeinsam) als eine Position in den globalen Variablen positions.~data[].
 *
 * @param  _In_ bool   isVirtual
 *
 * @param  _In_ double longPosition
 * @param  _In_ double shortPosition
 * @param  _In_ double totalPosition
 *
 * @param  _In_ int    tickets    []
 * @param  _In_ int    types      []
 * @param  _In_ double lots       []
 * @param  _In_ double openPrices []
 * @param  _In_ double commissions[]
 * @param  _In_ double swaps      []
 * @param  _In_ double profits    []
 *
 * @param  _In_ double closedProfit
 * @param  _In_ double adjustedProfit
 * @param  _In_ double customEquity
 * @param  _In_ int    commentIndex
 *
 * @return bool - Erfolgsstatus
 */
bool StorePosition(bool isVirtual, double longPosition, double shortPosition, double totalPosition, int &tickets[], int types[], double &lots[], double openPrices[], double &commissions[], double &swaps[], double &profits[], double closedProfit, double adjustedProfit, double customEquity, int commentIndex) {
   isVirtual = isVirtual!=0;

   double hedgedLots, remainingLong, remainingShort, factor, openPrice, closePrice, commission, swap, floatingProfit, hedgedProfit, openProfit, fullProfit, equity, pipValue, pipDistance;
   int size, ticketsSize=ArraySize(tickets);

   // Enth�lt die Position weder OpenProfit (offene Positionen), ClosedProfit noch AdjustedProfit, wird sie �bersprungen.
   // Ein Test auf (ticketsSize != 0) reicht nicht aus, da alle Tickets in tickets[] bereits auf NULL gesetzt worden sein k�nnen.
   if (!longPosition) /*&&*/ if (!shortPosition) /*&&*/ if (!totalPosition) /*&&*/ if (closedProfit==EMPTY_VALUE) /*&&*/ if (!adjustedProfit)
      return(true);

   if (closedProfit == EMPTY_VALUE)
      closedProfit = 0;                                                       // 0.00 ist g�ltiger P/L

   static double externalAssets = EMPTY_VALUE;
   if (IsEmptyValue(externalAssets)) externalAssets = GetExternalAssets(tradeAccount.company, ifString(mode.extern.notrading, tradeAccount.alias, tradeAccount.number));

   if (customEquity != NULL)   equity  = customEquity;
   else {                      equity  = externalAssets;
      if (mode.intern.trading) equity += (AccountEquity()-AccountCredit());   // TODO: tats�chlichen Wert von openEquity ermitteln
   }

   // Die Position besteht aus einem gehedgtem Anteil (konstanter Profit) und einem direktionalen Anteil (variabler Profit).
   // - kein direktionaler Anteil:  BE-Distance in Pips berechnen
   // - direktionaler Anteil:       Breakeven unter Ber�cksichtigung des Profits eines gehedgten Anteils berechnen


   // (1) Profit und BE-Distance einer eventuellen Hedgeposition ermitteln
   if (longPosition && shortPosition) {
      hedgedLots     = MathMin(longPosition, shortPosition);
      remainingLong  = hedgedLots;
      remainingShort = hedgedLots;

      for (int i=0; i < ticketsSize; i++) {
         if (!tickets[i]) continue;

         if (types[i] == OP_BUY) {
            if (!remainingLong) continue;
            if (remainingLong >= lots[i]) {
               // Daten komplett �bernehmen, Ticket auf NULL setzen
               openPrice     = NormalizeDouble(openPrice + lots[i] * openPrices[i], 8);
               swap         += swaps      [i];
               commission   += commissions[i];
               remainingLong = NormalizeDouble(remainingLong - lots[i], 3);
               tickets[i]    = NULL;
            }
            else {
               // Daten anteilig �bernehmen: Swap komplett, Commission, Profit und Lotsize des Tickets reduzieren
               factor        = remainingLong/lots[i];
               openPrice     = NormalizeDouble(openPrice + remainingLong * openPrices[i], 8);
               swap         += swaps[i];                swaps      [i]  = 0;
               commission   += factor * commissions[i]; commissions[i] -= factor * commissions[i];
                                                        profits    [i] -= factor * profits    [i];
                                                        lots       [i]  = NormalizeDouble(lots[i]-remainingLong, 3);
               remainingLong = 0;
            }
         }
         else /*types[i] == OP_SELL*/ {
            if (!remainingShort) continue;
            if (remainingShort >= lots[i]) {
               // Daten komplett �bernehmen, Ticket auf NULL setzen
               closePrice     = NormalizeDouble(closePrice + lots[i] * openPrices[i], 8);
               swap          += swaps      [i];
               //commission  += commissions[i];                                        // Commission wird nur f�r Long-Leg �bernommen
               remainingShort = NormalizeDouble(remainingShort - lots[i], 3);
               tickets[i]     = NULL;
            }
            else {
               // Daten anteilig �bernehmen: Swap komplett, Commission, Profit und Lotsize des Tickets reduzieren
               factor         = remainingShort/lots[i];
               closePrice     = NormalizeDouble(closePrice + remainingShort * openPrices[i], 8);
               swap          += swaps[i]; swaps      [i]  = 0;
                                          commissions[i] -= factor * commissions[i];   // Commission wird nur f�r Long-Leg �bernommen
                                          profits    [i] -= factor * profits    [i];
                                          lots       [i]  = NormalizeDouble(lots[i]-remainingShort, 3);
               remainingShort = 0;
            }
         }
      }
      if (remainingLong  != 0) return(!catch("StorePosition(1)  illegal remaining long position = "+ NumberToStr(remainingLong, ".+") +" of hedged position = "+ NumberToStr(hedgedLots, ".+"), ERR_RUNTIME_ERROR));
      if (remainingShort != 0) return(!catch("StorePosition(2)  illegal remaining short position = "+ NumberToStr(remainingShort, ".+") +" of hedged position = "+ NumberToStr(hedgedLots, ".+"), ERR_RUNTIME_ERROR));

      // BE-Distance und Profit berechnen
      pipValue = PipValue(hedgedLots, true);                                           // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
      if (pipValue != 0) {
         pipDistance  = NormalizeDouble((closePrice-openPrice)/hedgedLots/Pips + (commission+swap)/pipValue, 8);
         hedgedProfit = pipDistance * pipValue;
      }

      // (1.1) Kein direktionaler Anteil: Hedge-Position speichern und R�ckkehr
      if (!totalPosition) {
         size = ArrayRange(positions.iData, 0);
         ArrayResize(positions.iData, size+1);
         ArrayResize(positions.dData, size+1);

         positions.iData[size][I_CONFIG_TYPE     ] = ifInt(isVirtual, CONFIG_VIRTUAL, CONFIG_REAL);
         positions.iData[size][I_POSITION_TYPE   ] = POSITION_HEDGE;
         positions.iData[size][I_COMMENT_INDEX   ] = commentIndex;

         positions.dData[size][I_DIRECTIONAL_LOTS] = 0;
         positions.dData[size][I_HEDGED_LOTS     ] = hedgedLots;
         positions.dData[size][I_PIP_DISTANCE    ] = pipDistance;

         positions.dData[size][I_OPEN_EQUITY     ] = equity;         openProfit = hedgedProfit;
         positions.dData[size][I_OPEN_PROFIT     ] = openProfit;
         positions.dData[size][I_CLOSED_PROFIT   ] = closedProfit;
         positions.dData[size][I_ADJUSTED_PROFIT ] = adjustedProfit; fullProfit = openProfit + closedProfit + adjustedProfit;
         positions.dData[size][I_FULL_PROFIT_ABS ] = fullProfit;        // Bei customEquity wird der gemachte Profit nicht vom Equitywert abgezogen.
         positions.dData[size][I_FULL_PROFIT_PCT ] = MathDiv(fullProfit, equity-ifDouble(customEquity, 0, fullProfit)) * 100;

         return(!catch("StorePosition(3)"));
      }
   }


   // (2) Direktionaler Anteil: Bei Breakeven-Berechnung den Profit eines gehedgten Anteils und AdjustedProfit ber�cksichtigen.
   // (2.1) eventuelle Longposition ermitteln
   if (totalPosition > 0) {
      remainingLong  = totalPosition;
      openPrice      = 0;
      swap           = 0;
      commission     = 0;
      floatingProfit = 0;

      for (i=0; i < ticketsSize; i++) {
         if (!tickets[i]   ) continue;
         if (!remainingLong) continue;

         if (types[i] == OP_BUY) {
            if (remainingLong >= lots[i]) {
               // Daten komplett �bernehmen, Ticket auf NULL setzen
               openPrice       = NormalizeDouble(openPrice + lots[i] * openPrices[i], 8);
               swap           += swaps      [i];
               commission     += commissions[i];
               floatingProfit += profits    [i];
               tickets[i]      = NULL;
               remainingLong   = NormalizeDouble(remainingLong - lots[i], 3);
            }
            else {
               // Daten anteilig �bernehmen: Swap komplett, Commission, Profit und Lotsize des Tickets reduzieren
               factor          = remainingLong/lots[i];
               openPrice       = NormalizeDouble(openPrice + remainingLong * openPrices[i], 8);
               swap           +=          swaps      [i]; swaps      [i]  = 0;
               commission     += factor * commissions[i]; commissions[i] -= factor * commissions[i];
               floatingProfit += factor * profits    [i]; profits    [i] -= factor * profits    [i];
                                                          lots       [i]  = NormalizeDouble(lots[i]-remainingLong, 3);
               remainingLong = 0;
            }
         }
      }
      if (remainingLong != 0) return(!catch("StorePosition(4)  illegal remaining long position = "+ NumberToStr(remainingLong, ".+") +" of long position = "+ NumberToStr(totalPosition, ".+"), ERR_RUNTIME_ERROR));

      // Position speichern
      size = ArrayRange(positions.iData, 0);
      ArrayResize(positions.iData, size+1);
      ArrayResize(positions.dData, size+1);

      positions.iData[size][I_CONFIG_TYPE     ] = ifInt(isVirtual, CONFIG_VIRTUAL, CONFIG_REAL);
      positions.iData[size][I_POSITION_TYPE   ] = POSITION_LONG;
      positions.iData[size][I_COMMENT_INDEX   ] = commentIndex;

      positions.dData[size][I_DIRECTIONAL_LOTS] = totalPosition;
      positions.dData[size][I_HEDGED_LOTS     ] = hedgedLots;
      positions.dData[size][I_BREAKEVEN_PRICE ] = NULL;

      positions.dData[size][I_OPEN_EQUITY     ] = equity;         openProfit = hedgedProfit + commission + swap + floatingProfit;
      positions.dData[size][I_OPEN_PROFIT     ] = openProfit;
      positions.dData[size][I_CLOSED_PROFIT   ] = closedProfit;
      positions.dData[size][I_ADJUSTED_PROFIT ] = adjustedProfit; fullProfit = openProfit + closedProfit + adjustedProfit;
      positions.dData[size][I_FULL_PROFIT_ABS ] = fullProfit;           // Bei customEquity wird der gemachte Profit nicht vom Equitywert abgezogen.
      positions.dData[size][I_FULL_PROFIT_PCT ] = MathDiv(fullProfit, equity-ifDouble(customEquity, 0, fullProfit)) * 100;

      pipValue = PipValue(totalPosition, true);                         // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
      if (pipValue != 0)
         positions.dData[size][I_BREAKEVEN_PRICE] = RoundCeil(openPrice/totalPosition - (fullProfit-floatingProfit)/pipValue*Pips, Digits);
      return(!catch("StorePosition(5)"));
   }


   // (2.2) eventuelle Shortposition ermitteln
   if (totalPosition < 0) {
      remainingShort = -totalPosition;
      openPrice      = 0;
      swap           = 0;
      commission     = 0;
      floatingProfit = 0;

      for (i=0; i < ticketsSize; i++) {
         if (!tickets[i]    ) continue;
         if (!remainingShort) continue;

         if (types[i] == OP_SELL) {
            if (remainingShort >= lots[i]) {
               // Daten komplett �bernehmen, Ticket auf NULL setzen
               openPrice       = NormalizeDouble(openPrice + lots[i] * openPrices[i], 8);
               swap           += swaps      [i];
               commission     += commissions[i];
               floatingProfit += profits    [i];
               tickets[i]      = NULL;
               remainingShort  = NormalizeDouble(remainingShort - lots[i], 3);
            }
            else {
               // Daten anteilig �bernehmen: Swap komplett, Commission, Profit und Lotsize des Tickets reduzieren
               factor          = remainingShort/lots[i];
               openPrice       = NormalizeDouble(openPrice + remainingShort * openPrices[i], 8);
               swap           +=          swaps      [i]; swaps      [i]  = 0;
               commission     += factor * commissions[i]; commissions[i] -= factor * commissions[i];
               floatingProfit += factor * profits    [i]; profits    [i] -= factor * profits    [i];
                                                          lots       [i]  = NormalizeDouble(lots[i]-remainingShort, 3);
               remainingShort = 0;
            }
         }
      }
      if (remainingShort != 0) return(!catch("StorePosition(6)  illegal remaining short position = "+ NumberToStr(remainingShort, ".+") +" of short position = "+ NumberToStr(-totalPosition, ".+"), ERR_RUNTIME_ERROR));

      // Position speichern
      size = ArrayRange(positions.iData, 0);
      ArrayResize(positions.iData, size+1);
      ArrayResize(positions.dData, size+1);

      positions.iData[size][I_CONFIG_TYPE     ] = ifInt(isVirtual, CONFIG_VIRTUAL, CONFIG_REAL);
      positions.iData[size][I_POSITION_TYPE   ] = POSITION_SHORT;
      positions.iData[size][I_COMMENT_INDEX   ] = commentIndex;

      positions.dData[size][I_DIRECTIONAL_LOTS] = -totalPosition;
      positions.dData[size][I_HEDGED_LOTS     ] = hedgedLots;
      positions.dData[size][I_BREAKEVEN_PRICE ] = NULL;

      positions.dData[size][I_OPEN_EQUITY     ] = equity;         openProfit = hedgedProfit + commission + swap + floatingProfit;
      positions.dData[size][I_OPEN_PROFIT     ] = openProfit;
      positions.dData[size][I_CLOSED_PROFIT   ] = closedProfit;
      positions.dData[size][I_ADJUSTED_PROFIT ] = adjustedProfit; fullProfit = openProfit + closedProfit + adjustedProfit;
      positions.dData[size][I_FULL_PROFIT_ABS ] = fullProfit;           // Bei customEquity wird der gemachte Profit nicht vom Equitywert abgezogen.
      positions.dData[size][I_FULL_PROFIT_PCT ] = MathDiv(fullProfit, equity-ifDouble(customEquity, 0, fullProfit)) * 100;

      pipValue = PipValue(-totalPosition, true);                        // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
      if (pipValue != 0)
         positions.dData[size][I_BREAKEVEN_PRICE] = RoundFloor((fullProfit-floatingProfit)/pipValue*Pips - openPrice/totalPosition, Digits);
      return(!catch("StorePosition(7)"));
   }


   // (2.3) ohne offene Positionen mu� ClosedProfit (kann 0.00 sein) oder AdjustedProfit gesetzt sein
   // History mit leerer Position speichern
   size = ArrayRange(positions.iData, 0);
   ArrayResize(positions.iData, size+1);
   ArrayResize(positions.dData, size+1);

   positions.iData[size][I_CONFIG_TYPE     ] = ifInt(isVirtual, CONFIG_VIRTUAL, CONFIG_REAL);
   positions.iData[size][I_POSITION_TYPE   ] = POSITION_HISTORY;
   positions.iData[size][I_COMMENT_INDEX   ] = commentIndex;

   positions.dData[size][I_DIRECTIONAL_LOTS] = NULL;
   positions.dData[size][I_HEDGED_LOTS     ] = NULL;
   positions.dData[size][I_BREAKEVEN_PRICE ] = NULL;

   positions.dData[size][I_OPEN_EQUITY     ] = equity;         openProfit = 0;
   positions.dData[size][I_OPEN_PROFIT     ] = openProfit;
   positions.dData[size][I_CLOSED_PROFIT   ] = closedProfit;
   positions.dData[size][I_ADJUSTED_PROFIT ] = adjustedProfit; fullProfit = openProfit + closedProfit + adjustedProfit;
   positions.dData[size][I_FULL_PROFIT_ABS ] = fullProfit;              // Bei customEquity wird der gemachte Profit nicht vom Equitywert abgezogen.
   positions.dData[size][I_FULL_PROFIT_PCT ] = MathDiv(fullProfit, equity-ifDouble(customEquity, 0, fullProfit)) * 100;

   return(!catch("StorePosition(8)"));
}


/**
 * Handler f�r beim LFX-Terminal eingehende Messages.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.HandleLfxTerminalMessages() {
   if (!__CHART)
      return(true);

   // (1) ggf. Receiver starten
   if (!hQC.TradeToLfxReceiver) /*&&*/ if (!QC.StartLfxReceiver())
      return(false);

   // (2) Channel auf neue Messages pr�fen
   int checkResult = QC_CheckChannel(qc.TradeToLfxChannel);
   if (checkResult == QC_CHECK_CHANNEL_EMPTY)
      return(true);
   if (checkResult < QC_CHECK_CHANNEL_EMPTY) {
      if (checkResult == QC_CHECK_CHANNEL_ERROR)  return(!catch("QC.HandleLfxTerminalMessages(1)->MT4iQuickChannel::QC_CheckChannel(name="+ DoubleQuoteStr(qc.TradeToLfxChannel) +") => QC_CHECK_CHANNEL_ERROR",                ERR_WIN32_ERROR));
      if (checkResult == QC_CHECK_CHANNEL_NONE )  return(!catch("QC.HandleLfxTerminalMessages(2)->MT4iQuickChannel::QC_CheckChannel(name="+ DoubleQuoteStr(qc.TradeToLfxChannel) +")  channel doesn't exist",                   ERR_WIN32_ERROR));
                                                  return(!catch("QC.HandleLfxTerminalMessages(3)->MT4iQuickChannel::QC_CheckChannel(name="+ DoubleQuoteStr(qc.TradeToLfxChannel) +")  unexpected return value = "+ checkResult, ERR_WIN32_ERROR));
   }

   // (3) neue Messages abholen
   string messageBuffer[]; if (!ArraySize(messageBuffer)) InitializeStringBuffer(messageBuffer, QC_MAX_BUFFER_SIZE);
   int getResult = QC_GetMessages3(hQC.TradeToLfxReceiver, messageBuffer, QC_MAX_BUFFER_SIZE);
   if (getResult != QC_GET_MSG3_SUCCESS) {
      if (getResult == QC_GET_MSG3_CHANNEL_EMPTY) return(!catch("QC.HandleLfxTerminalMessages(4)->MT4iQuickChannel::QC_GetMessages3()  QuickChannel mis-match: QC_CheckChannel="+ checkResult +"chars/QC_GetMessages3=CHANNEL_EMPTY", ERR_WIN32_ERROR));
      if (getResult == QC_GET_MSG3_INSUF_BUFFER ) return(!catch("QC.HandleLfxTerminalMessages(5)->MT4iQuickChannel::QC_GetMessages3()  QuickChannel mis-match: QC_CheckChannel="+ checkResult +"chars/QC_MAX_BUFFER_SIZE="+ QC_MAX_BUFFER_SIZE +"/size(buffer)="+ (StringLen(messageBuffer[0])+1) +"/QC_GetMessages3=INSUF_BUFFER", ERR_WIN32_ERROR));
                                                  return(!catch("QC.HandleLfxTerminalMessages(6)->MT4iQuickChannel::QC_GetMessages3()  unexpected return value = "+ getResult, ERR_WIN32_ERROR));
   }

   // (4) Messages verarbeiten: Da hier sehr viele Messages in kurzer Zeit eingehen k�nnen, werden sie zur Beschleunigung statt mit Explode() manuell zerlegt.
   string msgs = messageBuffer[0];
   int from=0, to=StringFind(msgs, TAB, from);
   while (to != -1) {                                                            // mind. ein TAB gefunden
      if (to != from)
         if (!ProcessLfxTerminalMessage(StringSubstr(msgs, from, to-from)))
            return(false);
      from = to+1;
      to = StringFind(msgs, TAB, from);
   }
   if (from < StringLen(msgs))
      if (!ProcessLfxTerminalMessage(StringSubstr(msgs, from)))
         return(false);

   return(true);
}


/**
 * Verarbeitet beim LFX-Terminal eingehende Messages.
 *
 * @param  string message - QuickChannel-Message, siehe Formatbeschreibung
 *
 * @return bool - Erfolgsstatus: Ob die Message erfolgreich verarbeitet wurde. Ein falsches Messageformat oder keine zur Message passende Order sind kein Fehler,
 *                               das Ausl�sen eines Fehlers durch Schicken einer falschen Message ist so nicht m�glich. F�r nicht unterst�tzte Messages wird
 *                               stattdessen eine Warnung ausgegeben.
 *
 * Messageformat: "LFX:{iTicket]:pending={1|0}"   - die angegebene Pending-Order wurde platziert (immer erfolgreich, da im Fehlerfall keine Message generiert wird)
 *                "LFX:{iTicket]:open={1|0}"      - die angegebene Pending-Order wurde ausgef�hrt/konnte nicht ausgef�hrt werden
 *                "LFX:{iTicket]:close={1|0}"     - die angegebene Position wurde geschlossen/konnte nicht geschlossen werden
 *                "LFX:{iTicket]:profit={dValue}" - der P/L der angegebenen Position hat sich ge�ndert
 */
bool ProcessLfxTerminalMessage(string message) {
   //debug("ProcessLfxTerminalMessage(1)  tick="+ Tick +"  msg=\""+ message +"\"");

   // Da hier in kurzer Zeit sehr viele Messages eingehen k�nnen, werden sie zur Beschleunigung statt mit Explode() manuell zerlegt.
   // LFX-Prefix
   if (StringSubstr(message, 0, 4) != "LFX:")                                        return(_true(warn("ProcessLfxTerminalMessage(2)  unknown message format \""+ message +"\"")));
   // LFX-Ticket
   int from=4, to=StringFind(message, ":", from);                   if (to <= from)  return(_true(warn("ProcessLfxTerminalMessage(3)  unknown message \""+ message +"\" (illegal order ticket)")));
   int ticket = StrToInteger(StringSubstr(message, from, to-from)); if (ticket <= 0) return(_true(warn("ProcessLfxTerminalMessage(4)  unknown message \""+ message +"\" (illegal order ticket)")));
   // LFX-Parameter
   double profit;
   bool   success;
   from = to+1;

   // :profit={dValue}
   if (StringSubstr(message, from, 7) == "profit=") {                         // die h�ufigste Message wird zuerst gepr�ft
      int size = ArrayRange(lfxOrders, 0);
      for (int i=0; i < size; i++) {
         if (lfxOrders.iCache[i][I_IC.ticket] == ticket) {                    // geladene LFX-Orders durchsuchen und P/L aktualisieren
            if (lfxOrders.bCache[i][I_BC.isOpenPosition]) {
               lfxOrders.dCache[i][I_DC.lastProfit] = lfxOrders.dCache[i][I_DC.profit];
               lfxOrders.dCache[i][I_DC.profit    ] = NormalizeDouble(StrToDouble(StringSubstr(message, from+7)), 2);
            }
            break;
         }
      }
      return(true);
   }

   // :pending={1|0}
   if (StringSubstr(message, from, 8) == "pending=") {
      success = (StrToInteger(StringSubstr(message, from+8)) != 0);
      if (success) { if (__LOG) log("ProcessLfxTerminalMessage(5)  #"+ ticket +" pending order "+ ifString(success, "notification", "error"                           )); }
      else         {           warn("ProcessLfxTerminalMessage(6)  #"+ ticket +" pending order "+ ifString(success, "notification", "error (what use case is this???)")); }
      return(RestoreLfxOrders(false));                                        // LFX-Orders neu einlesen (auch bei Fehler)
   }

   // :open={1|0}
   if (StringSubstr(message, from, 5) == "open=") {
      success = (StrToInteger(StringSubstr(message, from+5)) != 0);
      if (__LOG) log("ProcessLfxTerminalMessage(7)  #"+ ticket +" open position "+ ifString(success, "notification", "error"));
      return(RestoreLfxOrders(false));                                        // LFX-Orders neu einlesen (auch bei Fehler)
   }

   // :close={1|0}
   if (StringSubstr(message, from, 6) == "close=") {
      success = (StrToInteger(StringSubstr(message, from+6)) != 0);
      if (__LOG) log("ProcessLfxTerminalMessage(8)  #"+ ticket +" close position "+ ifString(success, "notification", "error"));
      return(RestoreLfxOrders(false));                                        // LFX-Orders neu einlesen (auch bei Fehler)
   }

   // ???
   return(_true(warn("ProcessLfxTerminalMessage(9)  unknown message \""+ message +"\"")));
}


/**
 * Liest die LFX-Orderdaten neu ein bzw. restauriert sie aus dem Cache.
 *
 * @param  bool fromCache - Ob die Orderdaten aus zwischengespeicherten Daten restauriert oder komplett neu eingelesen werden.
 *
 *                          TRUE:  Restauriert die Orderdaten aus in der Library zwischengespeicherten Daten.
 *
 *                          FALSE: Liest die LFX-Orderdaten im aktuellen Kontext neu ein. F�r offene Positionen wird im Dateisystem kein P/L gespeichert
 *                                 (�ndert sich st�ndig). Stattdessen wird dieser P/L in globalen Terminal-Variablen zwischengespeichert (schneller) und
 *                                 von dort restauriert.
 * @return bool - Erfolgsstatus
 */
bool RestoreLfxOrders(bool fromCache) {
   fromCache = fromCache!=0;

   if (fromCache) {
      // (1) LFX-Orders aus in der Library zwischengespeicherten Daten restaurieren
      int size = ChartInfos.CopyLfxOrders(false, lfxOrders, lfxOrders.iCache, lfxOrders.bCache, lfxOrders.dCache);
      if (size == -1) return(!SetLastError(ERR_RUNTIME_ERROR));

      // Order-Z�hler aktualisieren
      lfxOrders.pendingOrders    = 0;                                               // Diese Z�hler dienen der Beschleunigung, um nicht st�ndig �ber alle Orders
      lfxOrders.openPositions    = 0;                                               // iterieren zu m�ssen.
      lfxOrders.pendingPositions = 0;

      for (int i=0; i < size; i++) {
         lfxOrders.pendingOrders    += lfxOrders.bCache[i][I_BC.isPendingOrder   ];
         lfxOrders.openPositions    += lfxOrders.bCache[i][I_BC.isOpenPosition   ];
         lfxOrders.pendingPositions += lfxOrders.bCache[i][I_BC.isPendingPosition];
      }
      return(true);
   }


   // (2) Orderdaten neu einlesen: Sind wir nicht in einem init()-Cycle, werden im Cache noch vorhandene Daten vorm �berschreiben gespeichert.
   if (ArrayRange(lfxOrders.iCache, 0) > 0) {
      if (!SaveLfxOrderCache()) return(false);
   }
   ArrayResize(lfxOrders.iCache, 0);
   ArrayResize(lfxOrders.bCache, 0);
   ArrayResize(lfxOrders.dCache, 0);
   lfxOrders.pendingOrders    = 0;
   lfxOrders.openPositions    = 0;
   lfxOrders.pendingPositions = 0;

   // solange in mode.remote.trading noch lfxCurrency und lfxCurrencyId benutzt werden, bei Nicht-LFX-Instrumenten hier abbrechen
   if (mode.remote.trading) /*&&*/ if (!StringEndsWith(Symbol(), "LFX"))
      return(true);

   // LFX-Orders einlesen
   string currency = "";
   int    flags    = NULL;
   if      (mode.intern.trading) {                         flags = OF_OPENPOSITION;     }    // offene Positionen aller LFX-W�hrungen (zum Managen von Profitbetrags-Exit-Limiten)
   else if (mode.remote.trading) { currency = lfxCurrency; flags = OF_OPEN | OF_CLOSED; }    // alle Orders der aktuellen LFX-W�hrung (zur Anzeige)

   size = LFX.GetOrders(currency, flags, lfxOrders); if (size==-1) return(false);

   ArrayResize(lfxOrders.iCache, size);
   ArrayResize(lfxOrders.bCache, size);
   ArrayResize(lfxOrders.dCache, size);

   // Z�hler-Variablen und P/L-Daten aktualisieren
   for (i=0; i < size; i++) {
      lfxOrders.iCache[i][I_IC.ticket           ] = los.Ticket           (lfxOrders, i);
      lfxOrders.bCache[i][I_BC.isPendingOrder   ] = los.IsPendingOrder   (lfxOrders, i);
      lfxOrders.bCache[i][I_BC.isOpenPosition   ] = los.IsOpenPosition   (lfxOrders, i);
      lfxOrders.bCache[i][I_BC.isPendingPosition] = los.IsPendingPosition(lfxOrders, i);

      lfxOrders.pendingOrders    += lfxOrders.bCache[i][I_BC.isPendingOrder   ];
      lfxOrders.openPositions    += lfxOrders.bCache[i][I_BC.isOpenPosition   ];
      lfxOrders.pendingPositions += lfxOrders.bCache[i][I_BC.isPendingPosition];

      if (los.IsOpenPosition(lfxOrders, i)) {                        // TODO: !!! Der Account mu� Teil des Schl�ssels sein.
         string varName = StringConcatenate("LFX.#", lfxOrders.iCache[i][I_IC.ticket], ".profit");
         double value   = GlobalVariableGet(varName);
         if (!value) {                                               // 0 oder Fehler
            int error = GetLastError();
            if (error!=NO_ERROR) /*&&*/ if (error!=ERR_GLOBAL_VARIABLE_NOT_FOUND)
               return(!catch("RestoreLfxOrders(1)->GlobalVariableGet(name=\""+ varName +"\")", error));
         }
         lfxOrders.dCache[i][I_DC.profit    ] = value;
      }
      else {
         lfxOrders.dCache[i][I_DC.profit] = los.Profit(lfxOrders, i);
      }

      lfxOrders.dCache[i][I_DC.openEquity       ] = los.OpenEquity       (lfxOrders, i);
      lfxOrders.dCache[i][I_DC.lastProfit       ] = lfxOrders.dCache[i][I_DC.profit];     // Wert ist auf jeden Fall bereits verarbeitet worden.
      lfxOrders.dCache[i][I_DC.takeProfitAmount ] = los.TakeProfitValue  (lfxOrders, i);
      lfxOrders.dCache[i][I_DC.takeProfitPercent] = los.TakeProfitPercent(lfxOrders, i);
      lfxOrders.dCache[i][I_DC.stopLossAmount   ] = los.StopLossValue    (lfxOrders, i);
      lfxOrders.dCache[i][I_DC.stopLossPercent  ] = los.StopLossPercent  (lfxOrders, i);
   }
   return(true);
}


/**
 * Speichert die aktuellen LFX-Order-P/L's in globalen Terminal-Variablen. So steht der letzte bekannte P/L auch dann zur Verf�gung,
 * wenn das Trade-Terminal nicht l�uft.
 *
 * @return bool - Erfolgsstatus
 */
bool SaveLfxOrderCache() {
   string varName;
   int size = ArrayRange(lfxOrders.iCache, 0);

   for (int i=0; i < size; i++) {
      if (lfxOrders.bCache[i][I_BC.isOpenPosition]) {                // TODO: !!! Der Account mu� Teil des Schl�ssels sein.
         varName = StringConcatenate("LFX.#", lfxOrders.iCache[i][I_IC.ticket], ".profit");

         if (!GlobalVariableSet(varName, lfxOrders.dCache[i][I_DC.profit])) {
            int error = GetLastError();
            return(!catch("SaveLfxOrderCache(1)->GlobalVariableSet(name=\""+ varName +"\", value="+ DoubleToStr(lfxOrders.dCache[i][I_DC.profit], 2) +")", ifInt(!error, ERR_RUNTIME_ERROR, error)));
         }
      }
   }
   return(true);
}


/**
 * Handler f�r beim Terminal eingehende Trade-Commands.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.HandleTradeCommands() {
   if (!__CHART)
      return(true);

   // (1) ggf. Receiver starten
   if (!hQC.TradeCmdReceiver) /*&&*/ if (!QC.StartTradeCmdReceiver())
      return(false);

   // (2) Channel auf neue Messages pr�fen
   int checkResult = QC_CheckChannel(qc.TradeCmdChannel);
   if (checkResult == QC_CHECK_CHANNEL_EMPTY)
      return(true);
   if (checkResult < QC_CHECK_CHANNEL_EMPTY) {
      if (checkResult == QC_CHECK_CHANNEL_ERROR)  return(!catch("QC.HandleTradeCommands(1)->MT4iQuickChannel::QC_CheckChannel(name=\""+ qc.TradeCmdChannel +"\") => QC_CHECK_CHANNEL_ERROR",                ERR_WIN32_ERROR));
      if (checkResult == QC_CHECK_CHANNEL_NONE )  return(!catch("QC.HandleTradeCommands(2)->MT4iQuickChannel::QC_CheckChannel(name=\""+ qc.TradeCmdChannel +"\")  channel doesn't exist",                   ERR_WIN32_ERROR));
                                                  return(!catch("QC.HandleTradeCommands(3)->MT4iQuickChannel::QC_CheckChannel(name=\""+ qc.TradeCmdChannel +"\")  unexpected return value = "+ checkResult, ERR_WIN32_ERROR));
   }

   // (3) neue Messages abholen
   string messageBuffer[]; if (!ArraySize(messageBuffer)) InitializeStringBuffer(messageBuffer, QC_MAX_BUFFER_SIZE);
   int getResult = QC_GetMessages3(hQC.TradeCmdReceiver, messageBuffer, QC_MAX_BUFFER_SIZE);
   if (getResult != QC_GET_MSG3_SUCCESS) {
      if (getResult == QC_GET_MSG3_CHANNEL_EMPTY) return(!catch("QC.HandleTradeCommands(4)->MT4iQuickChannel::QC_GetMessages3()  QuickChannel mis-match: QC_CheckChannel="+ checkResult +"chars/QC_GetMessages3=CHANNEL_EMPTY", ERR_WIN32_ERROR));
      if (getResult == QC_GET_MSG3_INSUF_BUFFER ) return(!catch("QC.HandleTradeCommands(5)->MT4iQuickChannel::QC_GetMessages3()  QuickChannel mis-match: QC_CheckChannel="+ checkResult +"chars/QC_MAX_BUFFER_SIZE="+ QC_MAX_BUFFER_SIZE +"/size(buffer)="+ (StringLen(messageBuffer[0])+1) +"/QC_GetMessages3=INSUF_BUFFER", ERR_WIN32_ERROR));
                                                  return(!catch("QC.HandleTradeCommands(6)->MT4iQuickChannel::QC_GetMessages3()  unexpected return value = "+ getResult, ERR_WIN32_ERROR));
   }

   // (4) Messages verarbeiten
   string msgs[];
   int msgsSize = Explode(messageBuffer[0], TAB, msgs, NULL);

   for (int i=0; i < msgsSize; i++) {
      if (!StringLen(msgs[i])) continue;
      msgs[i] = StringReplace(msgs[i], HTML_TAB, TAB);
      log("QC.HandleTradeCommands(7)  received \""+ msgs[i] +"\"");

      string cmdType = StringTrim(StringLeftTo(msgs[i], "{"));

      if      (cmdType == "LfxOrderCreateCommand" ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderOpenCommand"   ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderCloseCommand"  ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderCloseByCommand") { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderHedgeCommand"  ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderModifyCommand" ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else if (cmdType == "LfxOrderDeleteCommand" ) { if (!RunScript("LFX.ExecuteTradeCmd", msgs[i])) return(false); }
      else {
         return(!catch("QC.HandleTradeCommands(8)  unsupported trade command = "+ DoubleQuoteStr(cmdType), ERR_RUNTIME_ERROR));
      }
  }
   return(true);
}


/**
 * Schickt den Profit der LFX-Positionen ans LFX-Terminal und pr�ft die absoluten und prozentualen Limite. Beides nur, wenn sich der Wert
 * seit dem letzten Aufruf ge�ndert hat.
 *
 * @return bool - Erfolgsstatus
 */
bool AnalyzePos.ProcessLfxProfits() {
   string messages[]; ArrayResize(messages, 0); ArrayResize(messages, ArraySize(hQC.TradeToLfxSenders));    // 2 x ArrayResize() = ArrayInitialize()

   int size = ArrayRange(lfxOrders, 0);

   // Urspr�nglich enth�lt lfxOrders[] nur OpenPositions, bei Ausbleiben einer Ausf�hrungsbenachrichtigung k�nnen daraus geschlossene Positionen werden.
   for (int i=0; i < size; i++) {
      if (!EQ(lfxOrders.dCache[i][I_DC.profit], lfxOrders.dCache[i][I_DC.lastProfit], 2)) {
         // Profit hat sich ge�ndert: Betrag zu Messages des entsprechenden Channels hinzuf�gen
         double profit = lfxOrders.dCache[i][I_DC.profit];
         int    cid    = LFX.CurrencyId(lfxOrders.iCache[i][I_IC.ticket]);
         if (!StringLen(messages[cid])) messages[cid] = StringConcatenate(                    "LFX:", lfxOrders.iCache[i][I_IC.ticket], ":profit=", DoubleToStr(profit, 2));
         else                           messages[cid] = StringConcatenate(messages[cid], TAB, "LFX:", lfxOrders.iCache[i][I_IC.ticket], ":profit=", DoubleToStr(profit, 2));

         if (!lfxOrders.bCache[i][I_BC.isPendingPosition])
            continue;

         // Profit-Limite pr�fen (Preis-Limite nicht)
         int limitResult = LFX.CheckLimits(lfxOrders, i, NULL, NULL, profit); if (!limitResult) return(false);
         if (limitResult == NO_LIMIT_TRIGGERED)
            continue;

         // Position schlie�en
         if (!LFX.SendTradeCommand(lfxOrders, i, limitResult)) return(false);

         // Ohne Ausf�hrungsbenachrichtigung wurde die Order nach TimeOut neu eingelesen und die PendingPosition ggf. zu einer ClosedPosition.
         if (los.IsClosed(lfxOrders, i)) {
            lfxOrders.bCache[i][I_BC.isOpenPosition   ] = false;
            lfxOrders.bCache[i][I_BC.isPendingPosition] = false;
            lfxOrders.openPositions--;
            lfxOrders.pendingPositions--;
         }
      }
   }

   // angesammelte Messages verschicken: Messages je Channel werden gemeinsam und nicht einzeln verschickt, um beim Empf�nger unn�tige Ticks zu vermeiden.
   size = ArraySize(messages);
   for (i=1; i < size; i++) {                                        // Index 0 ist unbenutzt, denn 0 ist keine g�ltige CurrencyId
      if (StringLen(messages[i]) > 0) {
         if (!hQC.TradeToLfxSenders[i]) /*&&*/ if (!QC.StartLfxSender(i))
            return(false);
         if (!QC_SendMessage(hQC.TradeToLfxSenders[i], messages[i], QC_FLAG_SEND_MSG_IF_RECEIVER))
            return(!catch("AnalyzePos.ProcessLfxProfits(1)->MT4iQuickChannel::QC_SendMessage() = QC_SEND_MSG_ERROR", ERR_WIN32_ERROR));
      }
   }
   return(!catch("AnalyzePos.ProcessLfxProfits(2)"));
}


/**
 * Speichert die Laufzeitkonfiguration im Fenster (f�r Init-Cycle und neue Templates) und im Chart (f�r Terminal-Restart).
 *
 *  (1) string tradeAccount.company, int tradeAccount.number (wenn mode.extern.notrading=TRUE)
 *  (2) bool   positions.absoluteProfits
 *
 * @return bool - Erfolgsstatus
 */
bool StoreRuntimeStatus() {
   // (1) string tradeAccount.company, int tradeAccount.number (wenn mode.extern.notrading=TRUE)
   // Company-ID im Fenster speichern bzw. l�schen
   int    hWnd    = WindowHandleEx(NULL); if (!hWnd) return(false);
   string key     = __NAME__ +".runtime.tradeAccount.company";       // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   if (mode.extern.notrading) SetWindowProperty(hWnd, key, AccountCompanyId(tradeAccount.company));
   else                       RemoveWindowProperty(hWnd, key);
   // Company-ID im Chart speichern bzw. l�schen
   if (ObjectFind(key) == 0)
      ObjectDelete(key);
   if (mode.extern.notrading) {
      ObjectCreate (key, OBJ_LABEL, 0, 0, 0);
      ObjectSet    (key, OBJPROP_TIMEFRAMES, OBJ_PERIODS_NONE);
      ObjectSetText(key, ""+ AccountCompanyId(tradeAccount.company));
   }

   // AccountNumber im Fenster speichern bzw. l�schen
   key = __NAME__ +".runtime.tradeAccount.number";                   // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   if (mode.extern.notrading) SetWindowProperty(hWnd, key, tradeAccount.number);
   else                       RemoveWindowProperty(hWnd, key);
   // AccountNumber im Chart speichern bzw. l�schen
   if (ObjectFind(key) == 0)
      ObjectDelete(key);
   if (mode.extern.notrading) {
      ObjectCreate (key, OBJ_LABEL, 0, 0, 0);
      ObjectSet    (key, OBJPROP_TIMEFRAMES, OBJ_PERIODS_NONE);
      ObjectSetText(key, ""+ tradeAccount.number);
   }


   // (2) bool positions.absoluteProfits
   // Konfiguration im Fenster speichern
   key       = __NAME__ +".runtime.positions.absoluteProfits";       // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   int value = ifInt(positions.absoluteProfits, 1, -1);
   SetWindowProperty(hWnd, key, value);
   // Konfiguration im Chart speichern
   if (ObjectFind(key) == 0)
      ObjectDelete(key);
   ObjectCreate (key, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (key, OBJPROP_TIMEFRAMES, OBJ_PERIODS_NONE);
   ObjectSetText(key, ""+ value);

   return(!catch("StoreRuntimeStatus(1)"));
}


/**
 * Restauriert eine im Fenster oder im Chart gespeicherte Laufzeitkonfiguration.
 *
 *  (1) string tradeAccount.company, int tradeAccount.number (wenn mode.extern.notrading=TRUE)
 *  (2) bool   positions.absoluteProfits
 *
 * @return bool - Erfolgsstatus
 */
bool RestoreRuntimeStatus() {
   // (1) string tradeAccount.company, int tradeAccount.number
   int companyId, accountNumber;
   // Company-ID im Fenster suchen
   int    hWnd    = WindowHandleEx(NULL); if (!hWnd) return(false);
   string key     = __NAME__ +".runtime.tradeAccount.company";          // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   int    value   = GetWindowProperty(hWnd, key);
   bool   success = (value != 0);
   // bei Mi�erfolg Company-ID im Chart suchen
   if (!success) {
      if (ObjectFind(key) == 0) {
         value   = StrToInteger(ObjectDescription(key));
         success = (value != 0);
      }
   }
   if (success) companyId = value;

   // AccountNumber im Fenster suchen
   key     = __NAME__ +".runtime.tradeAccount.number";                  // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   value   = GetWindowProperty(hWnd, key);
   success = (value != 0);
   // bei Mi�erfolg AccountNumber im Chart suchen
   if (!success) {
      if (ObjectFind(key) == 0) {
         value   = StrToInteger(ObjectDescription(key));
         success = (value != 0);
      }
   }
   if (success) accountNumber = value;

   // Account restaurieren
   if (companyId && accountNumber) {
      if (!InitTradeAccount(companyId +":"+ accountNumber)) return(false);
      if (!UpdateAccountDisplay())                          return(false);
      if (mode.extern.notrading) {
         external.open.lots.checked = false;
         if (ReadExternalPositions(tradeAccount.company, tradeAccount.alias) == -1)
            return(false);
      }
      ArrayResize(positions.config,          0);
      ArrayResize(positions.config.comments, 0);
   }


   // (2) bool positions.absoluteProfits
   // Konfiguration im Fenster suchen
   key     = __NAME__ +".runtime.positions.absoluteProfits";         // TODO: Schl�ssel global verwalten und Instanz-ID des Indikators integrieren
   value   = GetWindowProperty(hWnd, key);
   success = (value != 0);
   // bei Mi�erfolg Konfiguration im Chart suchen
   if (!success) {
      if (ObjectFind(key) == 0) {
         value   = StrToInteger(ObjectDescription(key));
         success = (value != 0);
      }
   }
   if (success) positions.absoluteProfits = (value > 0);

   return(!catch("RestoreRuntimeStatus(1)"));
}


/**
 * Liest die externen offenen und geschlossenen Positionen des aktiven Signals ein. Die Positionen sind bereits sortiert gespeichert und m�ssen nicht
 * nochmal sortiert werden.
 *
 * @param  string provider - Signalprovider
 * @param  string signal   - Signal
 *
 * @return int - Anzahl der gelesenen Positionen oder -1 (EMPTY), falls ein Fehler auftrat
 */
int ReadExternalPositions(string provider, string signal) {
   // (1.1) offene Positionen: alle Schl�ssel einlesen
   string mqlDir  = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = TerminalPath() + mqlDir +"\\files\\"+ provider +"\\"+ signal +"_open.ini";
      if (!IsFile(file)) return(_EMPTY(catch("ReadExternalPositions(1)  file not found \""+ file +"\"", ERR_RUNTIME_ERROR)));
   string section = provider +"."+ signal;
   string keys[], symbol = StdSymbol();
   int keysSize = GetIniKeys(file, section, keys);

   ArrayResize(external.open.ticket    , 0);
   ArrayResize(external.open.type      , 0);
   ArrayResize(external.open.lots      , 0);
   ArrayResize(external.open.openTime  , 0);
   ArrayResize(external.open.openPrice , 0);
   ArrayResize(external.open.takeProfit, 0);
   ArrayResize(external.open.stopLoss  , 0);
   ArrayResize(external.open.commission, 0);
   ArrayResize(external.open.swap      , 0);
   ArrayResize(external.open.profit    , 0);

   // (1.2) Schl�ssel gegen aktuelles Symbol pr�fen und Positionen einlesen
   for (int i=0; i < keysSize; i++) {
      string key = keys[i];
      if (StringStartsWith(key, symbol +".")) {

         // (1.2.1) Zeile lesen
         string value = GetIniString(file, section, key);
         if (!StringLen(value))                       return(_EMPTY(catch("ReadExternalPositions(2)  invalid ini entry ["+ section +"]->"+ key +" in \""+ file +"\" (empty)", ERR_RUNTIME_ERROR)));

         // (1.2.2) Positionsdaten validieren
         //Symbol.Ticket = Type, Lots, OpenTime, OpenPrice, TakeProfit, StopLoss, Commission, Swap, MagicNumber, Comment
         string sValue, values[];
         if (Explode(value, ",", values, NULL) != 10) return(_EMPTY(catch("ReadExternalPositions(3)  invalid position entry ("+ ArraySize(values) +" substrings) ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Ticket
         sValue = StringRight(key, -StringLen(symbol));
         if (StringGetChar(sValue, 0) != '.')         return(_EMPTY(catch("ReadExternalPositions(4)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         sValue = StringSubstr(sValue, 1);
         if (!StringIsDigit(sValue))                  return(_EMPTY(catch("ReadExternalPositions(5)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         int _ticket = StrToInteger(sValue);
         if (_ticket <= 0)                            return(_EMPTY(catch("ReadExternalPositions(6)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Type
         sValue = StringTrim(values[0]);
         int _type = StrToOperationType(sValue);
         if (!IsTradeOperation(_type))                return(_EMPTY(catch("ReadExternalPositions(7)  invalid order type \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Lots
         sValue = StringTrim(values[1]);
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(8)  invalid lot size \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         double _lots = StrToDouble(sValue);
         if (_lots <= 0)                              return(_EMPTY(catch("ReadExternalPositions(9)  invalid lot size \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _lots = NormalizeDouble(_lots, 2);

         // OpenTime
         sValue = StringTrim(values[2]);
         datetime _openTime = StrToTime(sValue);
         if (!_openTime)                              return(_EMPTY(catch("ReadExternalPositions(10)  invalid open time \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // OpenPrice
         sValue = StringTrim(values[3]);
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(11)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         double _openPrice = StrToDouble(sValue);
         if (_openPrice <= 0)                         return(_EMPTY(catch("ReadExternalPositions(12)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _openPrice = NormalizeDouble(_openPrice, Digits);

         // TakeProfit
         sValue = StringTrim(values[4]);
         double _takeProfit = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(13)  invalid takeprofit \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _takeProfit = StrToDouble(sValue);
            if (_takeProfit < 0)                      return(_EMPTY(catch("ReadExternalPositions(14)  invalid takeprofit \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _takeProfit = NormalizeDouble(_takeProfit, Digits);
         }

         // StopLoss
         sValue = StringTrim(values[5]);
         double _stopLoss = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(15)  invalid stoploss \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _stopLoss = StrToDouble(sValue);
            if (_stopLoss < 0)                        return(_EMPTY(catch("ReadExternalPositions(16)  invalid stoploss \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _stopLoss = NormalizeDouble(_stopLoss, Digits);
         }

         // Commission
         sValue = StringTrim(values[6]);
         double _commission = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(17)  invalid commission value \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _commission = NormalizeDouble(StrToDouble(sValue), 2);
         }

         // Swap
         sValue = StringTrim(values[7]);
         double _swap = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(18)  invalid swap value \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _swap = NormalizeDouble(StrToDouble(sValue), 2);
         }

         // MagicNumber: vorerst nicht ben�tigt
         // Comment:     vorerst nicht ben�tigt

         // (1.2.3) Position in die globalen Arrays schreiben (erst nach vollst�ndiger erfolgreicher Validierung)
         int size=ArraySize(external.open.ticket), newSize=size+1;
         ArrayResize(external.open.ticket    , newSize);
         ArrayResize(external.open.type      , newSize);
         ArrayResize(external.open.lots      , newSize);
         ArrayResize(external.open.openTime  , newSize);
         ArrayResize(external.open.openPrice , newSize);
         ArrayResize(external.open.takeProfit, newSize);
         ArrayResize(external.open.stopLoss  , newSize);
         ArrayResize(external.open.commission, newSize);
         ArrayResize(external.open.swap      , newSize);
         ArrayResize(external.open.profit    , newSize);

         external.open.ticket    [size] = _ticket;
         external.open.type      [size] = _type;
         external.open.lots      [size] = _lots;
         external.open.openTime  [size] = _openTime;
         external.open.openPrice [size] = _openPrice;
         external.open.takeProfit[size] = _takeProfit;
         external.open.stopLoss  [size] = _stopLoss;
         external.open.commission[size] = _commission;
         external.open.swap      [size] = _swap;
         external.open.profit    [size] = ifDouble(_type==OP_LONG, Bid-_openPrice, _openPrice-Ask)/Pips * PipValue(_lots, true);   // Fehler unterdr�cken, INIT_PIPVALUE ist u.U. nicht gesetzt
      }
   }


   // (2.1) geschlossene Positionen: alle Schl�ssel einlesen
   file = TerminalPath() + mqlDir +"\\files\\"+ provider +"\\"+ signal +"_closed.ini";
      if (!IsFile(file)) return(_EMPTY(catch("ReadExternalPositions(19)  file not found \""+ file +"\"", ERR_RUNTIME_ERROR)));
   section  = provider +"."+ signal;
   keysSize = GetIniKeys(file, section, keys);

   ArrayResize(external.closed.ticket    , 0);
   ArrayResize(external.closed.type      , 0);
   ArrayResize(external.closed.lots      , 0);
   ArrayResize(external.closed.openTime  , 0);
   ArrayResize(external.closed.openPrice , 0);
   ArrayResize(external.closed.closeTime , 0);
   ArrayResize(external.closed.closePrice, 0);
   ArrayResize(external.closed.takeProfit, 0);
   ArrayResize(external.closed.stopLoss  , 0);
   ArrayResize(external.closed.commission, 0);
   ArrayResize(external.closed.swap      , 0);
   ArrayResize(external.closed.profit    , 0);

   // (2.2) Schl�ssel gegen aktuelles Symbol pr�fen und Positionen einlesen
   for (i=0; i < keysSize; i++) {
      key = keys[i];
      if (StringStartsWith(key, symbol +".")) {
         // (2.2.1) Zeile lesen
         value = GetIniString(file, section, key);
         if (!StringLen(value))                       return(_EMPTY(catch("ReadExternalPositions(20)  invalid ini entry ["+ section +"]->"+ key +" in \""+ file +"\" (empty)", ERR_RUNTIME_ERROR)));

         // (2.2.2) Positionsdaten validieren
         //Symbol.Ticket = Type, Lots, OpenTime, OpenPrice, CloseTime, ClosePrice, TakeProfit, StopLoss, Commission, Swap, Profit, MagicNumber, Comment
         if (Explode(value, ",", values, NULL) != 13) return(_EMPTY(catch("ReadExternalPositions(21)  invalid position entry ("+ ArraySize(values) +" substrings) ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Ticket
         sValue = StringRight(key, -StringLen(symbol));
         if (StringGetChar(sValue, 0) != '.')         return(_EMPTY(catch("ReadExternalPositions(22)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         sValue = StringSubstr(sValue, 1);
         if (!StringIsDigit(sValue))                  return(_EMPTY(catch("ReadExternalPositions(23)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _ticket = StrToInteger(sValue);
         if (_ticket <= 0)                            return(_EMPTY(catch("ReadExternalPositions(24)  invalid ticket \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Type
         sValue = StringTrim(values[0]);
         _type  = StrToOperationType(sValue);
         if (!IsTradeOperation(_type))                return(_EMPTY(catch("ReadExternalPositions(25)  invalid order type \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // Lots
         sValue = StringTrim(values[1]);
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(26)  invalid lot size \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _lots = StrToDouble(sValue);
         if (_lots <= 0)                              return(_EMPTY(catch("ReadExternalPositions(27)  invalid lot size \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _lots = NormalizeDouble(_lots, 2);

         // OpenTime
         sValue    = StringTrim(values[2]);
         _openTime = StrToTime(sValue);
         if (!_openTime)                              return(_EMPTY(catch("ReadExternalPositions(28)  invalid open time \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // OpenPrice
         sValue = StringTrim(values[3]);
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(29)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _openPrice = StrToDouble(sValue);
         if (_openPrice <= 0)                         return(_EMPTY(catch("ReadExternalPositions(30)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _openPrice = NormalizeDouble(_openPrice, Digits);

         // CloseTime
         sValue = StringTrim(values[4]);
         datetime _closeTime = StrToTime(sValue);
         if (!_closeTime)                             return(_EMPTY(catch("ReadExternalPositions(31)  invalid open time \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));

         // ClosePrice
         sValue = StringTrim(values[5]);
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(32)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         double _closePrice = StrToDouble(sValue);
         if (_closePrice <= 0)                        return(_EMPTY(catch("ReadExternalPositions(33)  invalid open price \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         _closePrice = NormalizeDouble(_closePrice, Digits);

         // TakeProfit
         sValue      = StringTrim(values[6]);
         _takeProfit = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(34)  invalid takeprofit \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _takeProfit = StrToDouble(sValue);
            if (_takeProfit < 0)                      return(_EMPTY(catch("ReadExternalPositions(35)  invalid takeprofit \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _takeProfit = NormalizeDouble(_takeProfit, Digits);
         }

         // StopLoss
         sValue    = StringTrim(values[7]);
         _stopLoss = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(36)  invalid stoploss \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _stopLoss = StrToDouble(sValue);
            if (_stopLoss < 0)                        return(_EMPTY(catch("ReadExternalPositions(37)  invalid stoploss \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _stopLoss = NormalizeDouble(_stopLoss, Digits);
         }

         // Commission
         sValue      = StringTrim(values[8]);
         _commission = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(38)  invalid commission value \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _commission = NormalizeDouble(StrToDouble(sValue), 2);
         }

         // Swap
         sValue = StringTrim(values[9]);
         _swap  = 0;
         if (sValue != "") {
            if (!StringIsNumeric(sValue))             return(_EMPTY(catch("ReadExternalPositions(39)  invalid swap value \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
            _swap = NormalizeDouble(StrToDouble(sValue), 2);
         }

         // Profit
         sValue = StringTrim(values[10]);
         if (sValue == "")                            return(_EMPTY(catch("ReadExternalPositions(40)  invalid profit value \"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         if (!StringIsNumeric(sValue))                return(_EMPTY(catch("ReadExternalPositions(41)  invalid profit value \""+ sValue +"\" in position entry ["+ section +"]->"+ key +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR)));
         double _profit = NormalizeDouble(StrToDouble(sValue), 2);

         // MagicNumber: vorerst nicht ben�tigt
         // Comment:     vorerst nicht ben�tigt

         // (2.2.3) Position in die globalen Arrays schreiben (erst nach vollst�ndiger erfolgreicher Validierung)
         size=ArraySize(external.closed.ticket); newSize=size+1;
         ArrayResize(external.closed.ticket    , newSize);
         ArrayResize(external.closed.type      , newSize);
         ArrayResize(external.closed.lots      , newSize);
         ArrayResize(external.closed.openTime  , newSize);
         ArrayResize(external.closed.openPrice , newSize);
         ArrayResize(external.closed.closeTime , newSize);
         ArrayResize(external.closed.closePrice, newSize);
         ArrayResize(external.closed.takeProfit, newSize);
         ArrayResize(external.closed.stopLoss  , newSize);
         ArrayResize(external.closed.commission, newSize);
         ArrayResize(external.closed.swap      , newSize);
         ArrayResize(external.closed.profit    , newSize);

         external.closed.ticket    [size] = _ticket;
         external.closed.type      [size] = _type;
         external.closed.lots      [size] = _lots;
         external.closed.openTime  [size] = _openTime;
         external.closed.openPrice [size] = _openPrice;
         external.closed.closeTime [size] = _closeTime;
         external.closed.closePrice[size] = _closePrice;
         external.closed.takeProfit[size] = _takeProfit;
         external.closed.stopLoss  [size] = _stopLoss;
         external.closed.commission[size] = _commission;
         external.closed.swap      [size] = _swap;
         external.closed.profit    [size] = _profit;
      }
   }


   ArrayResize(keys,   0);
   ArrayResize(values, 0);
   if (!catch("ReadExternalPositions(42)"))
      return(ArraySize(external.open.ticket) + ArraySize(external.closed.ticket));
   return(-1);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf eine Pending-Order oder ein Close-Limit ausgef�hrt wurden.
 *
 * @param  int failedOrders   []    - Array zur Aufnahme der Tickets fehlgeschlagener Pening-Orders
 * @param  int openedPositions[]    - Array zur Aufnahme der Tickets neuer offener Positionen
 * @param  int closedPositions[][2] - Array zur Aufnahme der Tickets neuer geschlossener Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool OrderTracker.CheckPositions(int failedOrders[], int openedPositions[], int closedPositions[][]) {
   /*
   PositionOpen
   ------------
   - ist Ausf�hrung einer Pending-Order
   - Pending-Order mu� vorher bekannt sein
     (1) alle bekannten Pending-Orders auf Status�nderung pr�fen:              �ber bekannte Orders iterieren
     (2) alle unbekannten Pending-Orders registrieren:                         �ber alle Tickets(MODE_TRADES) iterieren

   PositionClose
   -------------
   - ist Schlie�ung einer Position
   - Position mu� vorher bekannt sein
     (1) alle bekannten Pending-Orders und Positionen auf OrderClose pr�fen:   �ber bekannte Orders iterieren
     (2) alle unbekannten Positionen mit und ohne Exit-Limit registrieren:     �ber alle Tickets(MODE_TRADES) iterieren
         (limitlose Positionen k�nnen durch Stopout geschlossen werden/worden sein)

   beides zusammen
   ---------------
     (1.1) alle bekannten Pending-Orders auf Status�nderung pr�fen:            �ber bekannte Orders iterieren
     (1.2) alle bekannten Pending-Orders und Positionen auf OrderClose pr�fen: �ber bekannte Orders iterieren
     (2)   alle unbekannten Pending-Orders und Positionen registrieren:        �ber alle Tickets(MODE_TRADES) iterieren
           - nach (1), um neue Orders nicht sofort zu pr�fen (unsinnig)
   */

   int type, knownSize=ArraySize(orders.knownOrders.ticket);


   // (1) �ber alle bekannten Orders iterieren (r�ckw�rts, um beim Entfernen von Elementen die Schleife einfacher managen zu k�nnen)
   for (int i=knownSize-1; i >= 0; i--) {
      if (!SelectTicket(orders.knownOrders.ticket[i], "OrderTracker.CheckPositions(1)"))
         return(false);
      type = OrderType();

      if (orders.knownOrders.type[i] > OP_SELL) {
         // (1.1) beim letzten Aufruf Pending-Order
         if (type == orders.knownOrders.type[i]) {
            // immer noch Pending-Order
            if (OrderCloseTime() != 0) {
               if (OrderComment() != "cancelled")
                  ArrayPushInt(failedOrders, orders.knownOrders.ticket[i]);      // keine regul�r gestrichene Pending-Order: "deleted [no money]" etc.

               // geschlossene Pending-Order aus der �berwachung entfernen
               ArraySpliceInts(orders.knownOrders.ticket, i, 1);
               ArraySpliceInts(orders.knownOrders.type,   i, 1);
               knownSize--;
            }
         }
         else {
            // jetzt offene oder bereits geschlossene Position
            ArrayPushInt(openedPositions, orders.knownOrders.ticket[i]);         // Pending-Order wurde ausgef�hrt
            orders.knownOrders.type[i] = type;
            i++;
            continue;                                                            // ausgef�hrte Order in Zweig (1.2) nochmal pr�fen (anstatt hier die Logik zu duplizieren)
         }
      }
      else {
         // (1.2) beim letzten Aufruf offene Position
         if (!OrderCloseTime()) {
            // immer noch offene Position
         }
         else {
            // jetzt geschlossene Position
            // pr�fen, ob die Position manuell oder automatisch geschlossen wurde (durch ein Close-Limit oder durch Stopout)
            bool   closedByLimit=false, autoClosed=false;
            int    closeType, closeData[2];
            string comment = StringToLower(StringTrim(OrderComment()));

            if      (StringStartsWith(comment, "so:" )) { autoClosed=true; closeType=CLOSE_TYPE_SO; } // Margin Stopout erkennen
            else if (StringEndsWith  (comment, "[tp]")) { autoClosed=true; closeType=CLOSE_TYPE_TP; }
            else if (StringEndsWith  (comment, "[sl]")) { autoClosed=true; closeType=CLOSE_TYPE_SL; }
            else {
               if (!EQ(OrderTakeProfit(), 0)) {                                                       // manche Broker setzen den OrderComment bei getriggertem Limit nicht
                  closedByLimit = false;                                                              // gem�� MT4-Standard
                  if (type == OP_BUY ) { closedByLimit = (OrderClosePrice() >= OrderTakeProfit()); }
                  else                 { closedByLimit = (OrderClosePrice() <= OrderTakeProfit()); }
                  if (closedByLimit) {
                     autoClosed = true;
                     closeType  = CLOSE_TYPE_TP;
                  }
               }
               if (!EQ(OrderStopLoss(), 0)) {
                  closedByLimit = false;
                  if (type == OP_BUY ) { closedByLimit = (OrderClosePrice() <= OrderStopLoss()); }
                  else                 { closedByLimit = (OrderClosePrice() >= OrderStopLoss()); }
                  if (closedByLimit) {
                     autoClosed = true;
                     closeType  = CLOSE_TYPE_SL;
                  }
               }
            }
            if (autoClosed) {
               closeData[0] = orders.knownOrders.ticket[i];
               closeData[1] = closeType;
               ArrayPushInts(closedPositions, closeData);            // Position wurde automatisch geschlossen
            }
            ArraySpliceInts(orders.knownOrders.ticket, i, 1);        // geschlossene Position aus der �berwachung entfernen
            ArraySpliceInts(orders.knownOrders.type,   i, 1);
            knownSize--;
         }
      }
   }


   // (2) �ber Tickets(MODE_TRADES) iterieren und alle unbekannten Tickets registrieren (immer Pending-Order oder offene Position)
   while (true) {
      int ordersTotal = OrdersTotal();

      for (i=0; i < ordersTotal; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {                      // FALSE: w�hrend des Auslesens wurde von dritter Seite eine Order geschlossen oder gel�scht
            ordersTotal = -1;                                                    // Abbruch und via while-Schleife alles nochmal verarbeiten, bis for() fehlerfrei durchl�uft
            break;
         }
         for (int n=0; n < knownSize; n++) {
            if (orders.knownOrders.ticket[n] == OrderTicket())                   // Order bereits bekannt
               break;
         }
         if (n >= knownSize) {                                                   // Order unbekannt: in �berwachung aufnehmen
            ArrayPushInt(orders.knownOrders.ticket, OrderTicket());
            ArrayPushInt(orders.knownOrders.type,   OrderType()  );
            knownSize++;
         }
      }

      if (ordersTotal == OrdersTotal())
         break;
   }

   return(!catch("OrderTracker.CheckPositions(2)"));
}


/**
 * Handler f�r OrderFail-Events.
 *
 * @param  int tickets[] - Tickets der fehlgeschlagenen Orders (immer Pending-Orders)
 *
 * @return bool - Erfolgsstatus
 */
bool onOrderFail(int tickets[]) {
   if (!track.orders)
      return(true);

   int success   = 0;
   int positions = ArraySize(tickets);

   for (int i=0; i < positions; i++) {
      if (!SelectTicket(tickets[i], "onOrderFail(1)"))
         return(false);

      string type        = OperationTypeDescription(OrderType() & 1);      // Buy-Limit -> Buy, Sell-Stop -> Sell, etc.
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string price       = NumberToStr(OrderOpenPrice(), priceFormat);
      string message     = "Order failed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"with error: \""+ OrderComment() +"\""+ NL +"("+ TimeToStr(TimeLocalEx("onOrderFail(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ tradeAccount.alias +")";

      if (__LOG) log("onOrderFail(3)  "+ message);

      // Signale f�r jede Order einzeln verschicken
      if (signal.mail) success &= !SendEmail(signal.mail.sender, signal.mail.receiver, message, message);
      if (signal.sms)  success &= !SendSMS(signal.sms.receiver, message);
   }

   // Sound f�r alle Orders gemeinsam abspielen
   if (signal.sound) success &= _int(PlaySoundEx(signal.sound.orderFailed));

   return(success != 0);
}


/**
 * Handler f�r PositionOpen-Events.
 *
 * @param  int tickets[] - Tickets der neu ge�ffneten Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool onPositionOpen(int tickets[]) {
   if (!track.orders)
      return(true);

   int success   = 0;
   int positions = ArraySize(tickets);

   for (int i=0; i < positions; i++) {
      if (!SelectTicket(tickets[i], "onPositionOpen(1)"))
         return(false);

      string type        = OperationTypeDescription(OrderType());
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string price       = NumberToStr(OrderOpenPrice(), priceFormat);
      string message     = "Position opened: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"("+ TimeToStr(TimeLocalEx("onPositionOpen(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ tradeAccount.alias +")";

      if (__LOG) log("onPositionOpen(3)  "+ message);

      // Signale f�r jede Position einzeln verschicken
      if (signal.mail) success &= !SendEmail(signal.mail.sender, signal.mail.receiver, message, message);
      if (signal.sms)  success &= !SendSMS(signal.sms.receiver, message);
   }

   // Sound f�r alle Positionen gemeinsam abspielen
   if (signal.sound) success &= _int(PlaySoundEx(signal.sound.positionOpened));

   return(success != 0);
}


/**
 * Handler f�r PositionClose-Events.
 *
 * @param  int tickets[] - Tickets der geschlossenen Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool onPositionClose(int tickets[][]) {
   if (!track.orders)
      return(true);

   string closeTypeDescr[] = {"", " (TakeProfit)", " (StopLoss)", " (StopOut)"};

   int success   = 0;
   int positions = ArrayRange(tickets, 0);

   for (int i=0; i < positions; i++) {
      int ticket    = tickets[i][0];
      int closeType = tickets[i][1];
      if (!SelectTicket(ticket, "onPositionClose(1)"))
         continue;

      string type        = OperationTypeDescription(OrderType());
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string openPrice   = NumberToStr(OrderOpenPrice(), priceFormat);
      string closePrice  = NumberToStr(OrderClosePrice(), priceFormat);
      string message     = "Position closed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" open="+ openPrice +" close="+ closePrice + closeTypeDescr[closeType] + NL +"("+ TimeToStr(TimeLocalEx("onPositionClose(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ tradeAccount.alias +")";

      if (__LOG) log("onPositionClose(3)  "+ message);

      // Signale f�r jede Position einzeln verschicken
      if (signal.mail) success &= !SendEmail(signal.mail.sender, signal.mail.receiver, message, message);
      if (signal.sms)  success &= !SendSMS(signal.sms.receiver, message);
   }

   // Sound f�r alle Positionen gemeinsam abspielen
   if (signal.sound) success &= _int(PlaySoundEx(signal.sound.positionClosed));

   return(success != 0);
}


/**
 * L�dt die Konfigurationsdatei des aktuellen Accounts in den Editor.
 *
 * @return bool - Erfolgsstatus
 */
bool EditAccountConfig() {
   string mqlDir = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string files[];

   if (mode.intern.trading) {
      ArrayPushString(files, mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.number +"_config.ini");
   }
   else if (mode.extern.notrading) {
      ArrayPushString(files, mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.alias +"_open.ini"  );
      ArrayPushString(files, mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.alias +"_closed.ini");
      ArrayPushString(files, mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.alias +"_config.ini");
   }
   else if (mode.remote.trading) {
      ArrayPushString(files, mqlDir +"\\files\\"+ ShortAccountCompany() +"\\"+ GetAccountNumber()  +"_config.ini");
      ArrayPushString(files, mqlDir +"\\files\\"+ tradeAccount.company  +"\\"+ tradeAccount.number +"_config.ini");
   }
   else {
      return(!catch("EditAccountConfig(1)", ERR_WRONG_JUMP));
   }

   if (!EditFiles(files)) return(!SetLastError(stdlib.GetLastError()));
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  config: ",                     // 'config' statt 'inputs', da die Laufzeitparameter extern konfiguriert werden

                            "appliedPrice=",                PriceTypeToStr(appliedPrice), "; ")
   );
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   bool     AquireLock(string mutexName, bool wait);
   int      ArrayDropInt      (int    array[], int value);
   int      ArrayInsertDoubles(double array[], int offset, double values[]);
   int      ArrayPushDouble   (double array[], double value);
   int      ArraySpliceInts   (int    array[], int offset, int length);
   string   DateTimeToStr(datetime time, string mask);
   int      DeleteRegisteredObjects(string prefix);
   bool     EditFiles(string filenames[]);
   datetime FxtToServerTime(datetime fxtTime);
   double   GetCommission();
   string   GetHostName();
   string   GetLocalConfigPath();
   string   GetLongSymbolNameOrAlt(string symbol, string altValue);
   datetime GetPrevSessionStartTime.srv(datetime serverTime);
   string   GetRawIniString(string file, string section, string key, string defaultValue);
   datetime GetSessionStartTime.srv(datetime serverTime);
   string   GetStandardSymbol(string symbol);
   string   GetSymbolName(string symbol);
   bool     IsFile(string filename);
   bool     ChartMarker.OrderSent_A(int ticket, int digits, color markerColor);
   int      ObjectRegister(string label);
   bool     ReleaseLock(string mutexName);
   int      SearchStringArrayI(string haystack[], string needle);

#import "stdlib2.ex4"
   int      ArrayInsertDoubleArray(double array[][], int offset, double values[]);
   int      ChartInfos.CopyLfxOrders(bool direction, /*LFX_ORDER*/int orders[][], int iData[][], bool bData[][], double dData[][]);
   bool     SortClosedTickets(int keys[][]);
   bool     SortOpenTickets  (int keys[][]);

   string   IntsToStr            (int    array[], string separator);
   string   DoublesToStr         (double array[], string separator);
   string   StringsToStr         (string array[], string separator);
   string   TicketsToStr         (int    array[], string separator);
   string   TicketsToStr.Lots    (int    array[], string separator);
   string   TicketsToStr.Position(int    array[]);

#import
