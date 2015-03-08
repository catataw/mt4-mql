/**
 * �berwacht ein Instrument auf verschiedene Ereignisse und benachrichtigt akustisch und/oder per SMS.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Default-Konfiguration //////////////////////////////////////////////////////////////////////////////////
//                                                 (Konfiguration nicht per Input-Parametern, sondern per Konfigurationsdatei)
bool   Sound.Alerts                = true;
bool   SMS.Alerts                  = false;
string SMS.Receiver                = "";

bool   Track.Orders                = false;
string Positions.SoundOnOpen       = "speech/OrderFilled.wav";
string Positions.SoundOnClose      = "speech/PositionClosed.wav";

bool   Track.MovingAverage         = false;
double MovingAverage.Periods       = 0;                              // die Angabe fraktionaler Werte ist m�glich, z.B. 3.5 x D1
int    MovingAverage.Timeframe     = 0;                              // M1 | M5 | M15 etc.
int    MovingAverage.Method        = MODE_SMA;                       // SMA | EMA | LWMA | ALMA

bool   Track.BollingerBands        = false;
int    BollingerBands.MA.Periods   = 0;
int    BollingerBands.MA.Timeframe = 0;                              // M1 | M5 | M15 etc.
int    BollingerBands.MA.Method    = MODE_SMA;                       // SMA | EMA | LWMA | ALMA
double BollingerBands.Deviation    = 2.0;                            // Std.-Abweichung

bool   Track.NewHighLow            = false;

bool   Track.BreakPreviousRange    = false;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <iCustom/icMovingAverage.mqh>
#include <iFunctions/iBarShiftNext.mqh>
#include <iFunctions/iBarShiftPrevious.mqh>


#define EVENT_POSITION_OPEN       0x0010
#define EVENT_POSITION_CLOSE      0x0020

#define OFLAG_CURRENTSYMBOL            1        // order of current symbol (active chart)
#define OFLAG_BUY                      2        // long order
#define OFLAG_SELL                     4        // short order
#define OFLAG_MARKETORDER              8        // market order
#define OFLAG_PENDINGORDER            16        // pending order (Limit- oder Stop-Order)

#property indicator_chart_window

int    movingAverage.TimeframeFlag;                                  // Timeframe-Flag f�r EventListener.BarOpen (max. F_PERIOD_H1)
string strMovingAverage;
string strBollingerBands;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) Parametervalidierung
   // (1.1) Sound.Alerts
   Sound.Alerts = GetConfigBool("EventTracker", "Alert.Sound", Sound.Alerts);

   // (1.2) SMS.Alerts
   SMS.Alerts   = GetConfigBool("EventTracker", "Alert.SMS", SMS.Alerts);
   if (SMS.Alerts) {
      // SMS.Receiver
      SMS.Receiver = GetConfigString("SMS", "Receiver", SMS.Receiver);
      if (!StringIsDigit(SMS.Receiver))                SMS.Alerts = _false(catch("onInit(1)  invalid config value SMS.Receiver = \""+ SMS.Receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   __SMS.alerts   = SMS.Alerts;
   __SMS.receiver = SMS.Receiver;

   // (1.3) Track.Orders
   Track.Orders = GetConfigBool("EventTracker", "Track.Orders", Track.Orders);

   // (1.4) Track.MovingAverage
   Track.MovingAverage = GetConfigBool("EventTracker."+ StdSymbol(), "MovingAverage", Track.MovingAverage);
   if (Track.MovingAverage) {
      // MovingAverage.Timeframe zuerst, da G�ltigkeit von Periods davon abh�ngt
      string strValue = GetConfigString("EventTracker."+ StdSymbol(), "MovingAverage.Timeframe", MovingAverage.Timeframe);
      MovingAverage.Timeframe = StrToPeriod(strValue);
      if (MovingAverage.Timeframe == -1)               Track.MovingAverage = _false(catch("onInit(2)  invalid or missing config value [EventTracker."+ StdSymbol() +"] MovingAverage.Timeframe = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.MovingAverage) {
      if (MovingAverage.Timeframe >= PERIOD_MN1)       Track.MovingAverage = _false(catch("onInit(3)  unsupported config value [EventTracker."+ StdSymbol() +"] MovingAverage.Timeframe = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.MovingAverage) {
      // MovingAverage.Method
      strValue = GetConfigString("EventTracker."+ StdSymbol(), "MovingAverage.Method", MovingAverageMethodDescription(MovingAverage.Method));
      MovingAverage.Method = StrToMaMethod(strValue, MUTE_ERR_INVALID_PARAMETER);
      if (MovingAverage.Method == -1)                  Track.MovingAverage = _false(catch("onInit(4)  invalid config value [EventTracker."+ StdSymbol() +"] MovingAverage.Method = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }

   if (Track.MovingAverage) {
      // MovingAverage.Periods
      MovingAverage.Periods = GetConfigDouble("EventTracker."+ StdSymbol(), "MovingAverage.Periods", MovingAverage.Periods);
      if (LE(MovingAverage.Periods, 0))                Track.MovingAverage = _false(catch("onInit(5)  invalid or missing config value [EventTracker."+ StdSymbol() +"] MovingAverage.Periods = \""+ GetConfigString("EventTracker."+ StdSymbol(), "MovingAverage.Periods", "") +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.MovingAverage) {
      if (MathModFix(MovingAverage.Periods, 0.5) != 0) Track.MovingAverage = _false(catch("onInit(6)  illegal config value [EventTracker."+ StdSymbol() +"] MovingAverage.Periods = \""+ GetConfigString("EventTracker."+ StdSymbol(), "MovingAverage.Periods", "") +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.MovingAverage) {
      // max. Timeframe f�r EventListener.BarOpen soll H1 sein
      strValue         = NumberToStr(MovingAverage.Periods, ".+");
      strMovingAverage = MovingAverageMethodDescription(MovingAverage.Method) +"("+ strValue +"x"+ PeriodDescription(MovingAverage.Timeframe) +")";
      if (MovingAverage.Timeframe > PERIOD_H1) {
         switch (MovingAverage.Timeframe) {
            case PERIOD_H4: MovingAverage.Periods *=   4; break;
            case PERIOD_D1: MovingAverage.Periods *=  24; break;
            case PERIOD_W1: MovingAverage.Periods *= 120; break;
         }
         MovingAverage.Periods   = MathRound(MovingAverage.Periods);
         MovingAverage.Timeframe = PERIOD_H1;
      }
      movingAverage.TimeframeFlag = PeriodFlag(MovingAverage.Timeframe);
   }

   /*
   // (1.5) Track.BollingerBands
   Track.BollingerBands = GetConfigBool("EventTracker."+ StdSymbol(), "BollingerBands", Track.BollingerBands);
   if (Track.BollingerBands) {
      // BollingerBands.MA.Periods
      BollingerBands.MA.Periods = GetConfigInt("EventTracker."+ StdSymbol(), "BollingerBands.MA.Periods", BollingerBands.MA.Periods);
      if (BollingerBands.MA.Periods < 2)               Track.BollingerBands = _false(catch("onInit(7)  invalid or missing config value [EventTracker."+ StdSymbol() +"] BollingerBands.MA.Periods = \""+ GetConfigString("EventTracker."+ StdSymbol(), "BollingerBands.MA.Periods", "") +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.BollingerBands) {
      // BollingerBands.MA.Timeframe
      strValue = GetConfigString("EventTracker."+ StdSymbol(), "BollingerBands.MA.Timeframe", BollingerBands.MA.Timeframe);
      BollingerBands.MA.Timeframe = StrToPeriod(strValue);
      if (BollingerBands.MA.Timeframe == -1)           Track.BollingerBands = _false(catch("onInit(8)  invalid or missing config value [EventTracker."+ StdSymbol() +"] BollingerBands.MA.Timeframe = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
      if (BollingerBands.MA.Timeframe >= PERIOD_MN1)   Track.BollingerBands = _false(catch("onInit(9)  unsupported config value [EventTracker."+ StdSymbol() +"] BollingerBands.MA.Timeframe = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.BollingerBands) {
      // BollingerBands.MA.Method
      strValue = GetConfigString("EventTracker."+ StdSymbol(), "BollingerBands.MA.Method", MovingAverageMethodDescription(BollingerBands.MA.Method));
      BollingerBands.MA.Method = StrToMaMethod(strValue, MUTE_ERR_INVALID_PARAMETER);
      if (BollingerBands.MA.Method == -1)              Track.BollingerBands = _false(catch("onInit(10)  invalid config value [EventTracker."+ StdSymbol() +"] BollingerBands.MA.Method = \""+ strValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.BollingerBands) {
      // BollingerBands.Deviation
      BollingerBands.Deviation = GetConfigDouble("EventTracker."+ StdSymbol(), "BollingerBands.Deviation", BollingerBands.Deviation);
      if (LE(BollingerBands.Deviation, 0))             Track.BollingerBands = _false(catch("onInit(11)  invalid config value [EventTracker."+ StdSymbol() +"] BollingerBands.Deviation = \""+ GetConfigString("EventTracker."+ StdSymbol(), "BollingerBands.Deviation", "") +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }
   if (Track.BollingerBands) {
      // max. Indikator-Timeframe soll H1 sein
      strBollingerBands = StringConcatenate("BollingerBands(", BollingerBands.MA.Periods, "x", PeriodDescription(BollingerBands.MA.Timeframe), ")");
      if (BollingerBands.MA.Timeframe > PERIOD_H1) {
         switch (BollingerBands.MA.Timeframe) {
            case PERIOD_H4: BollingerBands.MA.Periods *=   4; break;
            case PERIOD_D1: BollingerBands.MA.Periods *=  24; break;
            case PERIOD_W1: BollingerBands.MA.Periods *= 120; break;
         }
         BollingerBands.MA.Timeframe = PERIOD_H1;
      }
   }
   */


   // Datenanzeige ausschalten
   SetIndexLabel(0, NULL);
   return(catch("onInit(12)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   /*
   // unvollst�ndige Accountinitialisierung abfangen (bei Start und Accountwechseln mit schnellen Prozessoren)
   if (!AccountNumber())
      return(SetLastError(ERR_NO_CONNECTION));

   // aktuelle Accountdaten holen und alte Ticks abfangen: s�mtliche Events werden nur nach neuen Ticks �berpr�ft
   static int loginData[3];                                          // { Login.PreviousAccount, Login.CurrentAccount, Login.Servertime }
   EventListener.AccountChange(loginData, 0);                        // Der Eventlistener schreibt unabh�ngig vom Egebnis immer die aktuellen Accountdaten ins Array.
   if (TimeCurrent() < loginData[2]) {
      //debug("onTick()  old tick=\""+ TimeToStr(TimeCurrent(), TIME_FULL) +"\"   login=\""+ TimeToStr(loginData[2], TIME_FULL) +"\"");
      return(catch("onTick()"));
   }
   */


   // (1) Track.Orders
   if (Track.Orders) {                                               // nur Pending-Orders des aktuellen Instruments tracken (manuelle jedoch nicht)
      HandleEvent.alt(EVENT_POSITION_CLOSE, OFLAG_CURRENTSYMBOL|OFLAG_PENDINGORDER);
      HandleEvent.alt(EVENT_POSITION_OPEN,  OFLAG_CURRENTSYMBOL|OFLAG_PENDINGORDER);
   }


   // (2) Track.MovingAverage                                        // Pr�fung nur bei onBarOpen, nicht bei jedem Tick
   if (Track.MovingAverage) {
      int iNull[];
      if (EventListener.BarOpen(iNull, movingAverage.TimeframeFlag)) {
         debug("onTick()  BarOpen=true");

         int    timeframe   = MovingAverage.Timeframe;
         string maPeriods   = NumberToStr(MovingAverage.Periods, ".+");
         string maTimeframe = PeriodDescription(MovingAverage.Timeframe);
         string maMethod    = MovingAverage.Method;

         int trend = icMovingAverage(timeframe, maPeriods, maTimeframe, maMethod, "Close", MovingAverage.MODE_TREND, 1);
         if (!trend) {
            int error = stdlib.GetLastError();
            if (IsError(error))
               return(SetLastError(error));
         }
         if (trend==1 || trend==-1) {
            //onMovingAverageTrendChange();
            debug("onTick()->icMovingAverage() => trend change");
         }
      }

   }


   // (3) Track.BollingerBands
   if (Track.BollingerBands) {
      if (!CheckBollingerBands())
         return(last_error);
   }


   // (4) Track.NewHighLow
   if (Track.NewHighLow) {
      // aktuelle Range ermitteln
      while (true) {
         // Bruch der Range �berwachen
         bool Bruch = false;
         if (Bruch) {
            // wenn seit letzten Bruch mind. Zeitspanne X verstrichen ist, Bruch signalisieren
            // Range aktualisieren
         }
      }
   }


   // (5) Track.BreakPreviousRange
   if (Track.BreakPreviousRange) {
      // letzte Range ermitteln
      // Bruch �berwachen
   }

   return(last_error);
}


/**
 * Pr�ft, ob ein Event aufgetreten ist und ruft ggf. dessen Eventhandler auf. Erm�glicht die Angabe weiterer
 * eventspezifischer Pr�fungskriterien.
 *
 * @param  int event    - Event-Flag
 * @param  int criteria - weitere eventspezifische Pr�fungskriterien (default: keine)
 *
 * @return int - 1, wenn ein Event aufgetreten ist;
 *               0  andererseits
 */
int HandleEvent.alt(int event, int criteria=NULL) {
   bool   status;
   int    iResults[];                                                // die Listener m�ssen die Arrays selbst zur�cksetzen
   string sResults[];                                                // ...

   switch (event) {
      case EVENT_POSITION_OPEN  : if (EventListener.PositionOpen (iResults, criteria)) { status = true; onPositionOpen (iResults); } break;
      case EVENT_POSITION_CLOSE : if (EventListener.PositionClose(iResults, criteria)) { status = true; onPositionClose(iResults); } break;

      default:
         return(!catch("HandleEvent.alt(1)  unknown event = "+ event, ERR_INVALID_PARAMETER));
   }
   return(status);                                                   // (int) bool
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein PositionOpen-Event aufgetreten ist. Werden zus�tzliche Orderkriterien angegeben, wird das Event nur
 * dann signalisiert, wenn alle angegebenen Kriterien erf�llt sind.
 *
 * @param  int tickets[] - Zielarray f�r Ticketnummern neu ge�ffneter Positionen
 * @param  int flags     - ein oder mehrere zus�tzliche Orderkriterien: OFLAG_CURRENTSYMBOL, OFLAG_BUY, OFLAG_SELL, OFLAG_MARKETORDER, OFLAG_PENDINGORDER
 *                         (default: keine)
 * @return bool - Ergebnis
 */
bool EventListener.PositionOpen(int &tickets[], int flags=NULL) {
   // ohne vollst�ndige Account-Initialisierung Abbruch
   int account = AccountNumber();
   if (!account)
      return(false);

   if (ArraySize(tickets) > 0)
      ArrayResize(tickets, 0);

   static int      accountNumber  [1];
   static datetime accountInitTime[1];                               // GMT-Zeit
   static int      knownPendings  [][2];                             // bekannte Pending-Orders und ihr Typ
   static int      knownPositions [];                                // bekannte Positionen


   // (1) Account initialisieren bzw. Accountwechsel erkennen
   if (!accountNumber[0]) {                                          // erster Aufruf
      accountNumber  [0] = account;
      accountInitTime[0] = GetGmtTime();
      //debug("EventListener.PositionOpen()  Account "+ account +" nach erstem Aufruf initialisiert, GMT-Zeit: '"+ TimeToStr(accountInitTime[0], TIME_FULL) +"'");
   }
   else if (accountNumber[0] != account) {                           // Aufruf nach Accountwechsel zur Laufzeit
      accountNumber  [0] = account;
      accountInitTime[0] = GetGmtTime();
      ArrayResize(knownPendings,  0);                                // gespeicherte Orderdaten l�schen
      ArrayResize(knownPositions, 0);
      //debug("EventListener.PositionOpen()  Account "+ account +" nach Accountwechsel initialisiert, GMT-Zeit: '"+ TimeToStr(accountInitTime[0], TIME_FULL) +"'");
   }


   // (2) Pending-Orders und Positionen abgleichen
   OrderPush("EventListener.PositionOpen(1)");
   int orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;

      int n, pendings, positions, type=OrderType(), ticket=OrderTicket();

      // (2.1) Pending-Orders
      if (type==OP_BUYLIMIT || type==OP_SELLLIMIT || type==OP_BUYSTOP || type==OP_SELLSTOP) {
         pendings = ArrayRange(knownPendings, 0);
         for (n=0; n < pendings; n++)
            if (knownPendings[n][0] == ticket)                       // bekannte Pending-Order
               break;
         if (n < pendings)
            continue;

         ArrayResize(knownPendings, pendings+1);                     // neue, unbekannte Pending-Order
         knownPendings[pendings][0] = ticket;
         knownPendings[pendings][1] = type;
         //debug("EventListener.PositionOpen()  pending order #", ticket, " added: ", OperationTypeDescription(type));
      }

      // (2.2) Positionen
      else if (type==OP_BUY || type==OP_SELL) {
         positions = ArraySize(knownPositions);
         for (n=0; n < positions; n++)
            if (knownPositions[n] == ticket)                         // bekannte Position
               break;
         if (n < positions)
            continue;

         // Die offenen Positionen stehen u.U. (z.B. nach Accountwechsel) erst nach einigen Ticks zur Verf�gung. Daher m�ssen
         // neue Positionen zus�tzlich anhand ihres OrderOpen-Timestamps auf ihren jeweiligen Status �berpr�ft werden.

         // neue (unbekannte) Position: pr�fen, ob sie nach Accountinitialisierung ge�ffnet wurde (= wirklich neu ist)
         if (accountInitTime[0] <= ServerToGmtTime(OrderOpenTime())) {
            // ja, in flags angegebene Orderkriterien pr�fen
            int event = 1;
            pendings = ArrayRange(knownPendings, 0);

            if (flags & OFLAG_CURRENTSYMBOL && 1) event &= _int(OrderSymbol() == Symbol());
            if (flags & OFLAG_BUY           && 1) event &= _int(         type == OP_BUY  );
            if (flags & OFLAG_SELL          && 1) event &= _int(         type == OP_SELL );
            if (flags & OFLAG_MARKETORDER   && 1) {
               for (int z=0; z < pendings; z++)
                  if (knownPendings[z][0] == ticket)                 // Order war pending
                     break;                         event &= _int(z == pendings);
            }
            if (flags & OFLAG_PENDINGORDER && 1) {
               for (z=0; z < pendings; z++)
                  if (knownPendings[z][0] == ticket)                 // Order war pending
                     break;                         event &= _int(z < pendings);
            }

            // wenn alle Kriterien erf�llt sind, Ticket in Resultarray speichern
            if (event == 1) {
               ArrayResize(tickets, ArraySize(tickets)+1);
               tickets[ArraySize(tickets)-1] = ticket;
            }
         }

         ArrayResize(knownPositions, positions+1);
         knownPositions[positions] = ticket;
         //debug("EventListener.PositionOpen()  position #", ticket, " added: ", OperationTypeDescription(type));
      }
   }

   bool eventStatus = (ArraySize(tickets) > 0);
   //debug("EventListener.PositionOpen()  eventStatus: "+ eventStatus);

   int error = GetLastError();
   if (!error)
      return(eventStatus && OrderPop("EventListener.PositionOpen(2)"));
   return(!catch("EventListener.PositionOpen(3)", error, O_POP));
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein PositionClose-Event aufgetreten ist. Werden zus�tzliche Orderkriterien angegeben, wird das Event nur
 * dann signalisiert, wenn alle angegebenen Kriterien erf�llt sind.
 *
 * @param  int tickets[] - Zielarray f�r Ticket-Nummern geschlossener Positionen
 * @param  int flags     - ein oder mehrere zus�tzliche Orderkriterien: OFLAG_CURRENTSYMBOL, OFLAG_BUY, OFLAG_SELL, OFLAG_MARKETORDER, OFLAG_PENDINGORDER
 *                         (default: keine)
 * @return bool - Ergebnis
 */
bool EventListener.PositionClose(int tickets[], int flags=NULL) {
   // ohne Verbindung zum Tradeserver sofortige R�ckkehr
   int account = AccountNumber();
   if (!account)
      return(false);

   OrderPush("EventListener.PositionClose(1)");

   // Ergebnisarray sicherheitshalber zur�cksetzen
   if (ArraySize(tickets) > 0)
      ArrayResize(tickets, 0);

   static int accountNumber[1];
   static int knownPositions[];                                         // bekannte Positionen
          int noOfKnownPositions = ArraySize(knownPositions);

   if (!accountNumber[0]) {
      accountNumber[0] = account;
      //debug("EventListener.PositionClose()  Account "+ account +" nach 1. Lib-Aufruf initialisiert");
   }
   else if (accountNumber[0] != account) {
      accountNumber[0] = account;
      ArrayResize(knownPositions, 0);
      //debug("EventListener.PositionClose()  Account "+ account +" nach Accountwechsel initialisiert");
   }
   else {
      // alle beim letzten Aufruf offenen Positionen pr�fen             // TODO: bei offenen Orders und dem ersten Login in einen anderen Account crasht alles
      for (int i=0; i < noOfKnownPositions; i++) {
         if (!SelectTicket(knownPositions[i], "EventListener.PositionClose(2)", NULL, O_POP))
            return(false);

         if (OrderCloseTime() > 0) {                                    // Position geschlossen, in flags angegebene Orderkriterien pr�fen
            int    event=1, type=OrderType();
            bool   pending;
            string comment = StringToLower(StringTrim(OrderComment()));

            if      (StringStartsWith(comment, "so:" )) pending = true; // Margin Stopout, wie pending behandeln
            else if (StringEndsWith  (comment, "[tp]")) pending = true;
            else if (StringEndsWith  (comment, "[sl]")) pending = true;
            else if (OrderTakeProfit() > 0) {
               if      (type == OP_BUY )                pending = (OrderClosePrice() >= OrderTakeProfit());
               else if (type == OP_SELL)                pending = (OrderClosePrice() <= OrderTakeProfit());
            }

            if (flags & OFLAG_CURRENTSYMBOL && 1) event &= _int(OrderSymbol() == Symbol());
            if (flags & OFLAG_BUY           && 1) event &= _int(type == OP_BUY );
            if (flags & OFLAG_SELL          && 1) event &= _int(type == OP_SELL);
            if (flags & OFLAG_MARKETORDER   && 1) event &= _int(!pending);
            if (flags & OFLAG_PENDINGORDER  && 1) event &= _int( pending);

            // wenn alle Kriterien erf�llt sind, Ticket in Resultarray speichern
            if (event == 1)
               ArrayPushInt(tickets, knownPositions[i]);
         }
      }
   }


   // offene Positionen jedes mal neu einlesen (l�scht auch vorher gespeicherte und jetzt ggf. geschlossene Positionen)
   if (noOfKnownPositions > 0) {
      ArrayResize(knownPositions, 0);
      noOfKnownPositions = 0;
   }
   int orders = OrdersTotal();
   for (i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))         // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;
      if (OrderType()==OP_BUY || OrderType()==OP_SELL) {
         noOfKnownPositions++;
         ArrayResize(knownPositions, noOfKnownPositions);
         knownPositions[noOfKnownPositions-1] = OrderTicket();
         //debug("EventListener.PositionClose()  open position #", ticket, " added: ", OperationTypeDescription(OrderType()));
      }
   }

   bool eventStatus = (ArraySize(tickets) > 0);
   //debug("EventListener.PositionClose()  eventStatus: "+ eventStatus);

   int error = GetLastError();
   if (!error)
      return(eventStatus && OrderPop("EventListener.PositionClose(3)"));
   return(!catch("EventListener.PositionClose(4)", error, O_POP));
}


/**
 * Handler f�r PositionOpen-Events.
 *
 * @param  int tickets[] - Tickets der ge�ffneten Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool onPositionOpen(int tickets[]) {
   if (!Track.Orders)
      return(true);

   int positions = ArraySize(tickets);

   for (int i=0; i < positions; i++) {
      if (!SelectTicket(tickets[i], "onPositionOpen(1)"))
         return(false);

      string type    = OperationTypeDescription(OrderType());
      string lots    = NumberToStr(OrderLots(), ".+");
      string price   = NumberToStr(OrderOpenPrice(), PriceFormat);
      string message = "Position opened: "+ type +" "+ lots +" "+ GetSymbolName(GetStandardSymbol(OrderSymbol())) +" at "+ price;

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, TimeToStr(TimeLocal(), TIME_MINUTES) +" "+ message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionOpen(3)  "+ message);
   }

   // ggf. Sound abspielen
   if (Sound.Alerts)
      PlaySoundEx(Positions.SoundOnOpen);
   return(!catch("onPositionOpen(4)"));
}


/**
 * Handler f�r PositionClose-Events.
 *
 * @param  int tickets[] - Tickets der geschlossenen Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool onPositionClose(int tickets[]) {
   if (!Track.Orders)
      return(true);

   int positions = ArraySize(tickets);

   for (int i=0; i < positions; i++) {
      if (!SelectTicket(tickets[i], "onPositionClose(1)"))
         continue;

      string type       = OperationTypeDescription(OrderType());
      string lots       = NumberToStr(OrderLots(), ".+");
      string openPrice  = NumberToStr(OrderOpenPrice(), PriceFormat);
      string closePrice = NumberToStr(OrderClosePrice(), PriceFormat);
      string message    = "Position closed: "+ type +" "+ lots +" "+ GetSymbolName(GetStandardSymbol(OrderSymbol())) +" at "+ openPrice +" -> "+ closePrice;

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, TimeToStr(TimeLocal(), TIME_MINUTES) +" "+ message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionClose(3)  "+ message);
   }

   // ggf. Sound abspielen
   if (Sound.Alerts)
      PlaySoundEx(Positions.SoundOnClose);
   return(!catch("onPositionClose(4)"));
}


#include <bollingerbandCrossing.mqh>


/**
 * Pr�ft, ob das aktuelle BollingerBand verletzt wurde und benachrichtigt entsprechend.
 *
 * @return bool - Erfolgsstatus (nicht, ob ein Signal aufgetreten ist)
 */
bool CheckBollingerBands() {
   double event[3];

   // EventListener aufrufen und bei Erfolg Event signalisieren
   if (EventListener.BandsCrossing(BollingerBands.MA.Periods, BollingerBands.MA.Timeframe, BollingerBands.MA.Method, BollingerBands.Deviation, event, DeepSkyBlue)) {
      int    crossing = MathRound(event[CROSSING_TYPE]);
      double value    = ifDouble(crossing==CROSSING_LOW, event[CROSSING_LOW_VALUE], event[CROSSING_HIGH_VALUE]);
      debug("CheckBollingerBands(0.1)  new "+ ifString(crossing==CROSSING_LOW, "low", "high") +" bands crossing at "+ TimeToStr(TimeCurrent(), TIME_FULL) + ifString(crossing==CROSSING_LOW, "  <= ", "  => ") + NumberToStr(value, PriceFormat));

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         string message = GetSymbolName(StdSymbol()) + ifString(crossing==CROSSING_LOW, " lower", " upper") +" "+ strBollingerBands +" @ "+ NumberToStr(value, PriceFormat) +" crossed";
         if (!SendSMS(__SMS.receiver, StringConcatenate(TimeToStr(TimeLocal(), TIME_MINUTES), " ", message)))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("CheckBollingerBands(2)  "+ message);

      // ggf. Sound abspielen
      if (Sound.Alerts)
         PlaySoundEx("Windows Alert.wav");
   }

   return(!catch("CheckBollingerBands(3)"));
}


/**
 *
 */
int GetDailyStartEndBars(string symbol, int bar, int &lpStartBar, int &lpEndBar) {
   if (symbol == "0")                                                   // (string) NULL
      symbol = Symbol();
   int period = PERIOD_H1;

   // Ausgangspunkt ist die Startbar der aktuellen Session
   datetime startTime = iTime(symbol, period, 0);
   if (GetLastError() == ERS_HISTORY_UPDATE)
      return(SetLastError(ERS_HISTORY_UPDATE));

   startTime = GetSessionStartTime.srv(startTime);
   if (startTime == NaT)                                                // Wochenend-Candles
      startTime = GetPrevSessionEndTime.srv(iTime(symbol, period, 0));

   int endBar=0, startBar=iBarShiftNext(symbol, period, startTime);
   if (startBar == -1)
      return(catch("GetDailyStartEndBars(1:symbol="+ symbol +", bar="+ bar +")    iBarShiftNext() => -1    no history bars for "+ TimeToStr(startTime), ERR_RUNTIME_ERROR));

   // Bars durchlaufen und Bar-Range der gew�nschten Periode ermitteln
   for (int i=1; i<=bar; i++) {
      endBar = startBar + 1;                                            // Endbar der n�chsten Range ist die der letzten Startbar vorhergehende Bar
      if (endBar >= Bars) {                                             // Chart deckt die Session nicht ab => Abbruch
         catch("GetDailyStartEndBars(2)");
         return(ERR_NO_RESULT);
      }

      startTime = GetSessionStartTime.srv(iTime(symbol, period, endBar));
      while (startTime == NaT) {                                        // Endbar kann theoretisch wieder eine Wochenend-Candle sein
         startBar = iBarShiftNext(symbol, period, GetPrevSessionEndTime.srv(iTime(symbol, period, endBar)));
         if (startBar == -1)
            return(catch("GetDailyStartEndBars(3:symbol="+ symbol +", bar="+ bar +")    iBarShiftNext() => -1    no history bars for "+ TimeToStr(GetPrevSessionEndTime.srv(iTime(symbol, period, endBar))), ERR_RUNTIME_ERROR));

         endBar = startBar + 1;
         if (endBar >= Bars) {                                          // Chart deckt die Session nicht ab => Abbruch
            catch("GetDailyStartEndBars(4)");
            return(ERR_NO_RESULT);
         }
         startTime = GetSessionStartTime.srv(iTime(symbol, period, endBar));
      }

      startBar = iBarShiftNext(symbol, period, startTime);
      if (startBar == -1)
         return(catch("GetDailyStartEndBars(5)(symbol="+ symbol +", bar="+ bar +")    iBarShiftNext() => -1    no history bars for "+ TimeToStr(startTime), ERR_RUNTIME_ERROR));
   }

   lpStartBar = startBar;
   lpEndBar   = endBar;

   return(catch("GetDailyStartEndBars(6)"));
}


/**
 * Ermittelt die OHLC-Werte eines Instruments f�r eine Bar-Range. Existieren die angegebene Startbar (from) bzw. die angegebene Endbar (to) nicht,
 * werden stattdessen die n�chste bzw. die letzte existierende Bar verwendet.
 *
 * @param  double results[] - Ergebnisarray {Open, Low, High, Close}
 * @param  string symbol    - Symbol des Instruments (default: NULL = aktuelles Symbol)
 * @param  int    period    - Periode (default: 0 = aktuelle Periode)
 * @param  int    from      - Offset der Startbar
 * @param  int    to        - Offset der Endbar
 *
 * @return int - Fehlerstatus: ERR_NO_RESULT, wenn die angegebene Range nicht existiert, ggf. ERS_HISTORY_UPDATE
 *
 *
 * NOTE: Diese Funktion wertet die in der History gespeicherten Bars unabh�ngig davon aus, ob diese Bars realen Bars entsprechen.
 *       @see iOHLCTime(symbol, timeframe, time, results)
 */
int iOHLCBarRange(string symbol, int period, int from, int to, double &results[]) {
   // TODO: um ERS_HISTORY_UPDATE zu vermeiden, m�glichst die aktuelle Periode benutzen

   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();

   if (from < 0) return(catch("iOHLCBarRange(1)  invalid parameter from = "+ from, ERR_INVALID_PARAMETER));
   if (to   < 0) return(catch("iOHLCBarRange(2)  invalid parameter to = "+ to, ERR_INVALID_PARAMETER));

   if (from < to) {
      int tmp = from;
      from = to;
      to   = tmp;
   }

   int bars = iBars(symbol, period);

   int error = GetLastError();                                       // ERS_HISTORY_UPDATE ???
   if (error != NO_ERROR) {
      if (error != ERS_HISTORY_UPDATE)
         catch("iOHLCBarRange(3)", error);
      return(error);
   }

   if (bars-1 < to) {                                                // History enth�lt zu wenig Daten in dieser Periode
      results[MODE_OPEN ] = 0;
      results[MODE_HIGH ] = 0;
      results[MODE_LOW  ] = 0;
      results[MODE_CLOSE] = 0;
      return(SetLastError(ERR_NO_RESULT));
   }

   if (from > bars-1)
      from = bars-1;

   int high=from, low=from;

   if (from != to) {
      high = iHighest(symbol, period, MODE_HIGH, from-to+1, to);
      low  = iLowest (symbol, period, MODE_LOW , from-to+1, to);
   }

   results[MODE_OPEN ] = iOpen (symbol, period, from);
   results[MODE_HIGH ] = iHigh (symbol, period, high);
   results[MODE_LOW  ] = iLow  (symbol, period, low );
   results[MODE_CLOSE] = iClose(symbol, period, to  );

   return(catch("iOHLCBarRange(5)"));
}


/**
 * Ermittelt die OHLC-Werte eines Instruments f�r einen Zeitpunkt einer Periode und schreibt sie in das angegebene Ergebnisarray.
 * Ergebnisse sind die Werte derjenigen Bar, die den angegebenen Zeitpunkt abdeckt.
 *
 * @param  string   symbol    - Symbol des Instruments (default: aktuelles Symbol)
 * @param  int      timeframe - Chartperiode           (default: aktuelle Periode)
 * @param  datetime time      - Zeitpunkt
 * @param  double   results[] - Array zur Aufnahme der Ergebnisse = {Open, Low, High, Close}
 *
 * @return int - Fehlerstatus: ERR_NO_RESULT, wenn f�r den Zeitpunkt keine Kurse existieren,
 *                             ggf. ERS_HISTORY_UPDATE
 */
int iOHLCTime(string symbol, int timeframe, datetime time, double &results[]) {

   // TODO: Parameter bool exact=TRUE implementieren
   // TODO: m�glichst aktuellen Chart benutzen, um ERS_HISTORY_UPDATE zu vermeiden

   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();

   int bar = iBarShift(symbol, timeframe, time, true);

   int error = GetLastError();                                       // ERS_HISTORY_UPDATE ???
   if (error != NO_ERROR) {
      if (error != ERS_HISTORY_UPDATE) catch("iOHLCTime(1)", error);
      return(error);
   }

   if (bar == -1) {                                                  // keine Kurse f�r diesen Zeitpunkt
      results[MODE_OPEN ] = 0;
      results[MODE_HIGH ] = 0;
      results[MODE_LOW  ] = 0;
      results[MODE_CLOSE] = 0;
      return(SetLastError(ERR_NO_RESULT));
   }

   error = iOHLCBar(symbol, timeframe, bar, results);
   if (error == ERR_NO_RESULT)
      catch("iOHLCTime(2)", error);
   return(error);
}


/**
 * Ermittelt die OHLC-Werte eines Instruments f�r einen Zeitraum und schreibt sie in das angegebene Ergebnisarray.
 * Existieren in diesem Zeitraum keine Kurse, werden die Werte 0 und der Fehlerstatus ERR_NO_RESULT zur�ckgegeben.
 *
 * @param  string   symbol    - Symbol des Instruments (default: NULL = aktuelles Symbol)
 * @param  datetime from      - Beginn des Zeitraumes
 * @param  datetime to        - Ende des Zeitraumes
 * @param  double   results[] - Array zur Aufnahme der Ergebnisse = {Open, Low, High, Close}
 *
 * @return int - Fehlerstatus: ERR_NO_RESULT, wenn im Zeitraum keine Kurse existieren,
 *                             ggf. ERS_HISTORY_UPDATE
 */
int iOHLCTimeRange(string symbol, datetime from, datetime to, double &results[]) {

   // TODO: Parameter bool exact=TRUE implementieren
   // TODO: m�glichst aktuellen Chart benutzen, um ERS_HISTORY_UPDATE zu vermeiden

   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();

   if (from < 0) return(catch("iOHLCTimeRange(1)  invalid parameter from: "+ from, ERR_INVALID_PARAMETER));
   if (to   < 0) return(catch("iOHLCTimeRange(2)  invalid parameter to: "  + to  , ERR_INVALID_PARAMETER));

   if (from > to) {
      datetime tmp = from;
      from = to;
      to   = tmp;
   }

   // gr��tm�gliche f�r from und to geeignete Periode bestimmen
   int pMinutes[60] = { PERIOD_H1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M15, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M30, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M15, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M5, PERIOD_M1, PERIOD_M1, PERIOD_M1, PERIOD_M1 };
   int pHours  [24] = { PERIOD_D1, PERIOD_H1, PERIOD_H1, PERIOD_H1, PERIOD_H4, PERIOD_H1, PERIOD_H1, PERIOD_H1, PERIOD_H4, PERIOD_H1, PERIOD_H1, PERIOD_H1, PERIOD_H4, PERIOD_H1, PERIOD_H1, PERIOD_H1, PERIOD_H4, PERIOD_H1, PERIOD_H1, PERIOD_H1, PERIOD_H4, PERIOD_H1, PERIOD_H1, PERIOD_H1 };

   int tSec = TimeSeconds(to);                                       // 'to' wird zur n�chsten Minute aufgerundet
   if (tSec > 0)
      to += 60 - tSec;

   int period = Min(pMinutes[TimeMinute(from)], pMinutes[TimeMinute(to)]);

   if (period == PERIOD_H1) {
      period = Min(pHours[TimeHour(from)], pHours[TimeHour(to)]);

      if (period==PERIOD_D1) /*&&*/ if (TimeDayOfWeekFix(from)==MONDAY) /*&&*/ if (TimeDayOfWeekFix(to)==SATURDAY)
         period = PERIOD_W1;
      // die weitere Pr�fung auf >= PERIOD_MN1 ist nicht sinnvoll
   }

   // from- und toBar ermitteln (to zeigt auf Beginn der n�chsten Bar)
   int fromBar = iBarShiftNext(symbol, period, from);
      if (fromBar == EMPTY_VALUE) return(last_error);

   int toBar = iBarShiftPrevious(symbol, period, to-1); if (toBar == EMPTY_VALUE) return(last_error);

   if (fromBar==-1 || toBar==-1) {                                   // Zeitraum ist zu alt oder zu jung f�r den Chart
      results[MODE_OPEN ] = 0;
      results[MODE_HIGH ] = 0;
      results[MODE_LOW  ] = 0;
      results[MODE_CLOSE] = 0;
      return(SetLastError(ERR_NO_RESULT));
   }

   // high- und lowBar ermitteln (identisch zu iOHLCBarRange(), wir sparen hier aber alle zus�tzlichen Checks)
   int highBar=fromBar, lowBar=fromBar;

   if (fromBar != toBar) {
      highBar = iHighest(symbol, period, MODE_HIGH, fromBar-toBar+1, toBar);
      lowBar  = iLowest (symbol, period, MODE_LOW , fromBar-toBar+1, toBar);
   }
   results[MODE_OPEN ] = iOpen (symbol, period, fromBar);
   results[MODE_HIGH ] = iHigh (symbol, period, highBar);
   results[MODE_LOW  ] = iLow  (symbol, period, lowBar );
   results[MODE_CLOSE] = iClose(symbol, period, toBar  );
   //debug("iOHLCTimeRange()    from="+ TimeToStr(from, TIME_DATE|TIME_MINUTES) +" (bar="+ fromBar +")   to="+ TimeToStr(to, TIME_DATE|TIME_MINUTES) +" (bar="+ toBar +")  period="+ PeriodDescription(period));

   return(catch("iOHLCTimeRange(3)"));
}


/**
 * Ermittelt die OHLC-Werte eines Symbols f�r eine einzelne Bar einer Periode. Im Unterschied zu den eingebauten Funktionen iHigh(), iLow() etc.
 * ermittelt diese Funktion alle vier Werte mit einem einzigen Funktionsaufruf.
 *
 * @param  string symbol    - Symbol  (default: aktuelles Symbol)
 * @param  int    period    - Periode (default: aktuelle Periode)
 * @param  int    bar       - Bar-Offset
 * @param  double results[] - Array zur Aufnahme der Ergebnisse = {Open, Low, High, Close}
 *
 * @return int - Fehlerstatus; ERR_NO_RESULT, wenn die angegebene Bar nicht existiert (ggf. ERS_HISTORY_UPDATE)
 */
int iOHLCBar(string symbol, int period, int bar, double &results[]) {
   if (symbol == "0")                                                // (string) NULL
      symbol = Symbol();
   if (bar < 0)
      return(catch("iOHLCBar(1)  invalid parameter bar = "+ bar, ERR_INVALID_PARAMETER));
   if (ArraySize(results) != 4)
      ArrayResize(results, 4);

   // TODO: um ERS_HISTORY_UPDATE zu vermeiden, m�glichst die aktuelle Periode benutzen

   // Scheint f�r Bars gr��er als ChartBars Nonsens zur�ckzugeben

   results[MODE_OPEN ] = iOpen (symbol, period, bar);
   results[MODE_HIGH ] = iHigh (symbol, period, bar);
   results[MODE_LOW  ] = iLow  (symbol, period, bar);
   results[MODE_CLOSE] = iClose(symbol, period, bar);

   int error = GetLastError();

   if (!error) {
      if (!results[MODE_CLOSE])
         error = ERR_NO_RESULT;
   }
   else if (error != ERS_HISTORY_UPDATE) {
      catch("iOHLCBar(2)", error);
   }
   return(error);
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "Sound.Alerts=",                BoolToStr(Sound.Alerts)                     , "; ",

                            "SMS.Alerts=",                  BoolToStr(SMS.Alerts)                       , "; ",
                    ifString(SMS.Alerts,
          StringConcatenate("SMS.Receiver=\"",              SMS.Receiver                                , "\"; "), ""),

                            "Track.Orders=",                BoolToStr(Track.Orders)                     , "; ",
                    ifString(Track.Orders,
          StringConcatenate("Positions.SoundOnOpen=\"",     Positions.SoundOnOpen                       , "\"; ",
                            "Positions.SoundOnClose=\"",    Positions.SoundOnClose                      , "\"; "), ""),

                            "Track.MovingAverage=",         BoolToStr(Track.MovingAverage)              , "; ",
                    ifString(Track.MovingAverage,
          StringConcatenate("MovingAverage.Periods=",       NumberToStr(MovingAverage.Periods, ".1+")  , "; ",
                            "MovingAverage.Timeframe=",     MovingAverage.Timeframe                     , "; ",
                            "MovingAverage.Method=",        MovingAverage.Method                        , "; "), ""),

                            "Track.BollingerBands=",        BoolToStr(Track.BollingerBands)             , "; ",
                    ifString(Track.BollingerBands,
          StringConcatenate("BollingerBands.MA.Periods=",   BollingerBands.MA.Periods                   , "; ",
                            "BollingerBands.MA.Timeframe=", BollingerBands.MA.Timeframe                 , "; ",
                            "BollingerBands.MA.Method=",    BollingerBands.MA.Method                    , "; ",
                            "BollingerBands.Deviation=",    NumberToStr(BollingerBands.Deviation, ".1+"), "; "), ""),

                            "Track.NewHighLow=",            BoolToStr(Track.NewHighLow)                 , "; ",

                            "Track.BreakPreviousRange=",    BoolToStr(Track.BreakPreviousRange)         , "; ")
   );
}


/**
 * Unterdr�ckt unn�tze Compilerwarnungen.
 */
void DummyCalls() {
   int    iNull;
   double dNulls[];
   GetDailyStartEndBars(NULL, NULL, iNull, iNull);
   iOHLCBarRange(NULL, NULL, NULL, NULL, dNulls);
   iOHLCTime(NULL, NULL, NULL, dNulls);
   iOHLCTimeRange(NULL, NULL, NULL, dNulls);
}
