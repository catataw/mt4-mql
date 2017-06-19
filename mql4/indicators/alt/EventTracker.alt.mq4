/**
 * EventTracker f�r getriggerte Pending-Orders. Benachrichtigt akustisch und/oder per SMS.
 *
 *
 * TODO:
 * -----
 *  - PositionOpen-/Close-Events w�hrend Timeframe- oder Symbolwechsel werden nicht erkannt
 *  - bei Accountwechsel auftretende Fehler werden nicht abgefangen
 *  - Konfiguration per Indikator-Parameter und NICHT per Accountkonfiguration
 *  - Konfiguration w�hrend eines init-Cycles im Chart speichern, damit Recompilation �berlebt werden kann
 *  - Anzeige der �berwachten Kriterien
 */
#property indicator_chart_window

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>


// Konfiguration
bool   eventTracker.initialized;                                     // Settings sind per Account, der kann bei Terminalstart kurzzeitig unbekannt sein
bool   sound.alerts;

bool   track.orders;
string sound.order.failed   = "speech/OrderExecutionFailed.wav";
string sound.position.open  = "speech/OrderFilled.wav";
string sound.position.close = "speech/PositionClosed.wav";

int    knownOrders.ticket[];                                         // vom letzten Aufruf bekannte offene Orders
int    knownOrders.type  [];

string accountAlias;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // EventTracker initialisieren (kann fehlschlagen, wenn die AccountNumber() beim Terminalstart noch nicht verf�gbar ist)
   eventTracker.initialized = EventTracker.init();
   if (!eventTracker.initialized)
      return(last_error);

   SetIndexLabel(0, NULL);                                           // Datenanzeige ausschalten
   return(catch("onInit(1)"));
}


/**
 * Initialisiert und konfiguriert den EventTracker mit Account-spezifischen Einstellungen.
 *
 * @return bool - Erfolgsstatus
 */
bool EventTracker.init() {
   int account = GetAccountNumber(); if (!account) return(false);

   string mqlDir = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file   = TerminalPath() + mqlDir +"\\files\\"+ ShortAccountCompany() +"\\"+ account +"_config.ini";

   // Sound.Alerts
   string section = "EventTracker";
   string key     = "Signal.Sound";
   sound.alerts   = GetIniBool(file, section, key);

   // SMS.Alerts
   section = "EventTracker";
   key     = "Signal.SMS";
   __SMS.alerts = GetIniBool(file, section, key);
   if (__SMS.alerts) {
      section = "SMS";
      key     = "Receiver";
      __SMS.receiver = GetGlobalConfigString(section, key);
      // TODO: Rufnummer validieren
      //if (!StringIsDigit(__SMS.receiver)) return(!catch("EventTracker.init(1)  invalid config value ["+ section +"]->"+ key +" = \""+ __SMS.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
      if (!StringLen(__SMS.receiver))
         __SMS.alerts = false;
   }

   // Track.Orders
   section = "EventTracker";
   key     = "Track.Orders";
   track.orders = GetIniBool(file, section, key);

   // TODO: Orders in Library zwischenspeichern und bei init() daraus restaurieren


   // AccountAlias
   section = "Accounts";
   key     = account +".alias";
   accountAlias = GetGlobalConfigString(section, key);
   if (!StringLen(accountAlias)) return(!catch("EventTracker.init(2)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));


   debug(InputsToStr());
   return(true);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // (1) endg�ltige Pr�fung, ob der EventTracker initialisiert ist
   if (!eventTracker.initialized) {
      eventTracker.initialized = EventTracker.init();
      if (!eventTracker.initialized) return(last_error);
   }

   // (2) Pending- und Limit-Orders �berwachen
   if (track.orders) {
      int failedOrders   []; ArrayResize(failedOrders,    0);
      int openedPositions[]; ArrayResize(openedPositions, 0);
      int closedPositions[]; ArrayResize(closedPositions, 0);

      if (!CheckPositions(failedOrders, openedPositions, closedPositions))
         return(last_error);

      if (ArraySize(failedOrders   ) > 0) onOrderFail    (failedOrders   );
      if (ArraySize(openedPositions) > 0) onPositionOpen (openedPositions);
      if (ArraySize(closedPositions) > 0) onPositionClose(closedPositions);
   }
   return(last_error);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf eine Pending-Order oder ein Close-Limit ausgef�hrt wurden.
 *
 * @param  int failedOrders   [] - Array zur Aufnahme der Tickets fehlgeschlagener Pening-Orders
 * @param  int openedPositions[] - Array zur Aufnahme der Tickets neuer offener Positionen
 * @param  int closedPositions[] - Array zur Aufnahme der Tickets neuer geschlossener Positionen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckPositions(int failedOrders[], int openedPositions[], int closedPositions[]) {
   /*
   PositionOpen
   ------------
   - ist Ausf�hrung einer Pending-Order
   - Pending-Order mu� vorher bekannt sein
     (1) alle bekannten Pending-Orders auf Status�nderung pr�fen:  �ber bekannte Orders iterieren
     (2) alle unbekannten Pending-Orders in �berwachung aufnehmen: �ber OpenOrders iterieren

   PositionClose
   -------------
   - ist Schlie�ung einer Position
   - Position mu� vorher bekannt sein
     (1) alle bekannten Pending-Orders und Positionen auf OrderClose pr�fen:            �ber bekannte Orders iterieren
     (2) alle unbekannten Positionen mit und ohne Close-Limit in �berwachung aufnehmen: �ber OpenOrders iterieren
         (limitlose Positionen k�nnen durch Stopout geschlossen worden sein)

   beides zusammen
   ---------------
     (1.1) alle bekannten Pending-Orders auf Status�nderung pr�fen:                 �ber bekannte Orders iterieren
     (1.2) alle bekannten Pending-Orders und Positionen auf OrderClose pr�fen:      �ber bekannte Orders iterieren

     (2)   alle unbekannten Pending-Orders und Positionen in �berwachung aufnehmen: �ber OpenOrders iterieren
           - nach (1.1) und (1.2), um sofortige Pr�fung neuer zu �berwachender Orders zu vermeiden
   */

   int type, knownSize=ArraySize(knownOrders.ticket);


   // (1) �ber alle bekannten Orders iterieren (r�ckw�rts, um beim Entfernen von Elementen die Schleife einfacher managen zu k�nnen)
   for (int i=knownSize-1; i >= 0; i--) {
      if (!SelectTicket(knownOrders.ticket[i], "CheckPositions(1)"))
         return(false);
      type = OrderType();

      if (knownOrders.type[i] > OP_SELL) {
         // (1.1) beim letzten Aufruf Pending-Order
         if (type == knownOrders.type[i]) {
            // immer noch Pending-Order
            if (OrderCloseTime() != 0) {
               if (OrderComment() != "cancelled")
                  ArrayPushInt(failedOrders, knownOrders.ticket[i]);             // keine regul�r gestrichene Pending-Order: "deleted [no money]" etc.

               // geschlossene Pending-Order aus der �berwachung entfernen
               ArraySpliceInts(knownOrders.ticket, i, 1);
               ArraySpliceInts(knownOrders.type,   i, 1);
               knownSize--;
            }
         }
         else {
            // jetzt offene oder bereits geschlossene Position
            ArrayPushInt(openedPositions, knownOrders.ticket[i]);                // Pending-Order wurde ausgef�hrt
            knownOrders.type[i] = type;
            i++; continue;                                                       // ausgef�hrte Order in Zweig (1.2) nochmal pr�fen (anstatt hier die Logik zu duplizieren)
         }
      }
      else {
         // (1.2) beim letzten Aufruf offene Position
         if (!OrderCloseTime()) {
            // immer noch offene Position
         }
         else {
            // jetzt geschlossene Position
            // pr�fen, ob die Position durch ein Close-Limit, durch Stopout oder manuell geschlossen wurde
            bool closedByBroker = false;
            string comment = StringToLower(StringTrim(OrderComment()));

            if      (StringStartsWith(comment, "so:" )) closedByBroker = true;   // Margin Stopout erkennen
            else if (StringEndsWith  (comment, "[tp]")) closedByBroker = true;
            else if (StringEndsWith  (comment, "[sl]")) closedByBroker = true;
            else {                                                               // manche Broker setzen den OrderComment bei Schlie�ung durch Limit nicht korrekt
               if (!EQ(OrderTakeProfit(), 0)) {
                  if (type == OP_BUY ) closedByBroker = closedByBroker || (OrderClosePrice() >= OrderTakeProfit());
                  else                 closedByBroker = closedByBroker || (OrderClosePrice() <= OrderTakeProfit());
               }
               if (!EQ(OrderStopLoss(), 0)) {
                  if (type == OP_BUY ) closedByBroker = closedByBroker || (OrderClosePrice() <= OrderStopLoss());
                  else                 closedByBroker = closedByBroker || (OrderClosePrice() >= OrderStopLoss());
               }
            }
            if (closedByBroker)
               ArrayPushInt(closedPositions, knownOrders.ticket[i]);             // Position wurde geschlossen
            ArraySpliceInts(knownOrders.ticket, i, 1);                           // geschlossene Position aus der �berwachung entfernen
            ArraySpliceInts(knownOrders.type,   i, 1);
            knownSize--;
         }
      }
   }


   // (2) �ber alle OpenOrders iterieren und neue Pending-Orders und Positionen in �berwachung aufnehmen
   while (true) {
      int ordersTotal = OrdersTotal();

      for (i=0; i < ordersTotal; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {          // FALSE: w�hrend des Auslesens wurde von dritter Seite eine offene Order geschlossen oder gel�scht
            ordersTotal = -1;                                        // Abbruch, via while-Schleife alle Orders nochmal verarbeiten, bis for fehlerfrei durchl�uft
            break;
         }
         for (int n=0; n < knownSize; n++) {
            if (knownOrders.ticket[n] == OrderTicket())              // Order bereits bekannt
               break;
         }
         if (n >= knownSize) {                                       // Order unbekannt: in �berwachung aufnehmen
            ArrayPushInt(knownOrders.ticket, OrderTicket());
            ArrayPushInt(knownOrders.type,   OrderType()  );
            knownSize++;
         }
      }

      if (ordersTotal == OrdersTotal())
         break;
   }

   return(!catch("CheckPositions(2)"));
}


/**
 * Handler f�r OrderFail-Events.
 *
 * @param  int tickets[] - Tickets der fehlgeschlagenen Pending-Orders
 *
 * @return bool - Erfolgsstatus
 */
bool onOrderFail(int tickets[]) {
   if (!track.orders)
      return(true);

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
      string message     = "Order failed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"with error: \""+ OrderComment() +"\""+ NL +"("+ TimeToStr(TimeLocalEx("onOrderFail(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ accountAlias +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message)) return(false);
      }
      else if (__LOG) log("onOrderFail(3)  "+ message);
   }

   // ggf. Sound abspielen
   if (sound.alerts)
      PlaySoundEx(sound.order.failed);
   return(!catch("onOrderFail(4)"));
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
      string message     = "Position opened: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"("+ TimeToStr(TimeLocalEx("onPositionOpen(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ accountAlias +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message)) return(false);
      }
      else if (__LOG) log("onPositionOpen(3)  "+ message);
   }

   // ggf. Sound abspielen
   if (sound.alerts)
      PlaySoundEx(sound.position.open);
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
   if (!track.orders)
      return(true);

   int positions = ArraySize(tickets);

   for (int i=0; i < positions; i++) {
      if (!SelectTicket(tickets[i], "onPositionClose(1)"))
         continue;

      string type        = OperationTypeDescription(OrderType());
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string openPrice   = NumberToStr(OrderOpenPrice(), priceFormat);
      string closePrice  = NumberToStr(OrderClosePrice(), priceFormat);
      string message     = "Position closed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" open="+ openPrice +" close="+ closePrice + NL +"("+ TimeToStr(TimeLocalEx("onPositionClose(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ accountAlias +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message)) return(false);
      }
      else if (__LOG) log("onPositionClose(3)  "+ message);
   }

   // ggf. Sound abspielen
   if (sound.alerts)
      PlaySoundEx(sound.position.close);
   return(!catch("onPositionClose(4)"));
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "Sound.Alerts=",       BoolToStr(sound.alerts)      , "; ",
                            "Track.Orders=",       BoolToStr(track.orders)      , "; ",

                            "__lpSuperContext=0x", IntToHexStr(__lpSuperContext), "; ")
   );
}
