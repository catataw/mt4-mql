/**
 * EventTracker f�r verschiedene Ereignisse. Benachrichtigt optisch, akustisch, per E-Mail, SMS, HTML-Request und/oder ICQ.
 *
 *
 * Zu �berwachende Order-Events werden mit Indikator-Inputparametern konfiguriert. Ein so konfigurierter EventTracker �berwacht alle Symbole des Accounts,
 * nicht nur das des aktuellen Charts. Es liegt in der Verantwortung des Benutzers, nur einen von allen laufenden EventTrackern f�r die Order�berwachung
 * zu konfigurieren. Order-Events:
 *  - Orderausf�hrung fehlgeschlagen
 *  - Position ge�ffnet
 *  - Position geschlossen
 *
 * Zu �berwachende Preis-Events werden in der Account-Konfiguration je Instrument konfiguriert. Es liegt in der Verantwortung des Benutzers, nur einen
 * EventTracker je Instrument zu laden. Preis-Events:
 *  - neues Tages-High/Low (mit konfigurierbarem Mindestabstand zwischen zwei aufeinanderfolgenden gleichen Events)
 *  - neues Wochen-High/Low (einmal je Richtung)
 *  - Bruch Vortages-Range
 *  - Bruch Vorwochen-Range
 *
 * Die Art der Benachrichtigung (akustisch, E-Mail, SMS, HTML-Request und/oder ICQ) kann je Event einzeln konfiguriert werden.
 *
 *
 *
 *
 * TODO:
 * -----
 *  - PositionOpen-/Close-Events w�hrend Timeframe- oder Symbolwechsel werden nicht erkannt
 *  - bei Accountwechsel auftretende Fehler werden nicht abgefangen
 *  - Konfiguration w�hrend eines init-Cycles im Chart speichern, damit Recompilation �berlebt werden kann
 *  - Anzeige der �berwachten Kriterien
 */
#property indicator_chart_window

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

//////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////

extern bool   Track.Orders               = false;

extern bool   Order.Alerts.Sound         = true;                     // alle Alerts bis auf Sounds sind per Default inaktiv
extern string Order.Alerts.Mail.Receiver = "email@address.tld";      // E-Mailadresse    ("system" => global konfigurierte Adresse)
extern string Order.Alerts.SMS.Receiver  = "phone-number";           // Telefonnummer    ("system" => global konfigurierte Nummer )
extern string Order.Alerts.HTTP.Url      = "";                       // vollst�ndige URL ("system" => global konfigurierte URL    )
//     string Order.Alerts.ICQ.Contact   = "user-id";                // ICQ-Kontakt      ("system" => global konfigurierte User-ID)

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include <core/indicator.mqh>


bool     isConfigured;


// OrderTracker
bool     track.orders;

bool     orderAlerts.sound;
string   sound.orderFailed    = "speech/OrderExecutionFailed.wav";
string   sound.positionOpened = "speech/OrderFilled.wav";
string   sound.positionClosed = "speech/PositionClosed.wav";

bool     orderAlerts.mail;
string   orderAlerts.mail.receiver = "";

bool     orderAlerts.sms;
string   orderAlerts.sms.receiver = "";

bool     orderAlerts.http;
string   orderAlerts.http.url = "";

int      orders.knownOrders.ticket[];                                // vom letzten Aufruf bekannte offene Orders
int      orders.knownOrders.type  [];


// PriceTracker
bool     track.price;
bool     priceAlerts.sound;
bool     priceAlerts.mail;
bool     priceAlerts.sms;
bool     priceAlerts.http;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   if (This.IsTesting() == -1)
      return(last_error);

   // Konfiguration einlesen. Ist die AccountNumber() beim Terminalstart noch nicht verf�gbar, wird der Aufruf in onTick() wiederholt.
   if (!Configure())
      return(last_error);

   SetIndexLabel(0, NULL);                                           // Datenanzeige ausschalten
   return(catch("onInit(1)"));
}


/**
 * Konfiguriert diesen EventTracker.
 *
 * @return bool - Erfolgsstatus
 */
bool Configure() {
   // (1) Konfiguration des OrderTrackers auswerten
   track.orders = Track.Orders;
   if (track.orders) {
      // (1.1) Order.Alerts.Sound
      orderAlerts.sound = Order.Alerts.Sound;

      // (1.2) Order.Alerts.Mail.Receiver = "email@address.tld";

      // (1.3) Order.Alerts.SMS.Receiver  = "phone-number";
      string sValue = StringToLower(StringTrim(Order.Alerts.SMS.Receiver));
      if (StringLen(sValue) && sValue!="phone-number") {
         orderAlerts.sms.receiver = ifString(sValue=="system", GetConfigString("SMS", "Receiver", ""), sValue);
         orderAlerts.sms          = StringIsPhoneNumber(orderAlerts.sms.receiver);

         if (!orderAlerts.sms) {
            if (sValue == "system") return(!catch("Configure(1)  "+ ifString(orderAlerts.sms.receiver=="", "Missing", "Invalid") +" global/local config value [SMS]->Receiver = \""+ orderAlerts.sms.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            else                    return(!catch("Configure(2)  Invalid input parameter Order.Alerts.SMS.Receiver = \""+ Order.Alerts.SMS.Receiver +"\"", ERR_INVALID_INPUT_PARAMVALUE));
         }
      }
      else orderAlerts.sms = false;

      // (1.4) Order.Alerts.HTTP.Url      = "";
      // (1.5) Order.Alerts.ICQ.Contact   = "user-id";
   }


   // (2) Konfiguration des PriceTrackers auswerten
   int account = GetAccountNumber();
   if (!account) return(!SetLastError(stdlib.GetLastError()));

   string mqlDir = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file   = TerminalPath() + mqlDir +"\\files\\"+ ShortAccountCompany() +"\\"+ account +"_config.ini";


   /*
   - neues Tages-High/Low
   - neues Wochen-High/Low
   - Bruch Vortages-Range
   - Bruch Vorwochen-Range
   */


   // SMS.Alerts
   __SMS.alerts = GetIniBool(file, "EventTracker", "SMS.Alerts", false);
   if (__SMS.alerts) {
      __SMS.receiver = GetGlobalConfigString("SMS", "Receiver", "");
      // TODO: Rufnummer validieren
      //if (!StringIsDigit(__SMS.receiver)) return(!catch("Configure(1)  invalid config value [SMS]->Receiver = \""+ __SMS.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
      if (!StringLen(__SMS.receiver))
         __SMS.alerts = false;
   }



   if (true) {
      debug("Configure()  "+ StringConcatenate("track.orders=", BoolToStr(track.orders),                                                    "; ",
                                                "orders.sound=", BoolToStr(orderAlerts.sound),                                               "; ",
                                                "orders.mail=" , ifString(orderAlerts.mail, "\""+ orderAlerts.mail.receiver +"\"", "false"), "; ",
                                                "orders.sms="  , ifString(orderAlerts.sms,  "\""+ orderAlerts.sms.receiver  +"\"", "false"), "; ",
                                                "orders.http=" , ifString(orderAlerts.http, "\""+ orderAlerts.http.url      +"\"", "false"), "; "
                                              //"orders.icq="  , ifString(orderAlerts.icq,  "\""+ orderAlerts.icq.contact   +"\"", "false"), "; "
                              )
      );
   }

   isConfigured = !catch("Configure(2)");
   return(isConfigured);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // (1) endg�ltige Pr�fung, ob der EventTracker konfiguriert ist
   if (!isConfigured) /*&&*/ if (!Configure())
      return(last_error);


   // (2) Pending- und Limit-Orders �berwachen
   if (Track.Orders) {
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

   int type, knownSize=ArraySize(orders.knownOrders.ticket);


   // (1) �ber alle bekannten Orders iterieren (r�ckw�rts, um beim Entfernen von Elementen die Schleife einfacher managen zu k�nnen)
   for (int i=knownSize-1; i >= 0; i--) {
      if (!SelectTicket(orders.knownOrders.ticket[i], "CheckPositions(1)"))
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
            else {                                                               // manche Broker setzen den OrderComment bei Schlie�ung durch Limit nicht gem�� MT4-Standard
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
               ArrayPushInt(closedPositions, orders.knownOrders.ticket[i]);      // Position wurde geschlossen
            ArraySpliceInts(orders.knownOrders.ticket, i, 1);                    // geschlossene Position aus der �berwachung entfernen
            ArraySpliceInts(orders.knownOrders.type,   i, 1);
            knownSize--;
         }
      }
   }


   // (2) �ber alle OpenOrders iterieren und neue Pending-Orders und Positionen in �berwachung aufnehmen
   while (true) {
      int ordersTotal = OrdersTotal();

      for (i=0; i < ordersTotal; i++) {
         if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {                      // FALSE: w�hrend des Auslesens wurde von dritter Seite eine offene Order geschlossen oder gel�scht
            ordersTotal = -1;                                                    // Abbruch, via while-Schleife alle Orders nochmal verarbeiten, bis for fehlerfrei durchl�uft
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
   if (!Track.Orders)
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
      string message     = "Order failed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"with error: \""+ OrderComment() +"\""+ NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onOrderFail(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (orderAlerts.sound)
      PlaySoundEx(sound.orderFailed);
   return(!catch("onOrderFail(3)"));
}


/**
 * Handler f�r PositionOpen-Events.
 *
 * @param  int tickets[] - Tickets der neu ge�ffneten Positionen
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

      string type        = OperationTypeDescription(OrderType());
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string price       = NumberToStr(OrderOpenPrice(), priceFormat);
      string message     = "Position opened: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionOpen(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (orderAlerts.sound)
      PlaySoundEx(sound.positionOpened);
   return(!catch("onPositionOpen(3)"));
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

      string type        = OperationTypeDescription(OrderType());
      string lots        = DoubleToStr(OrderLots(), 2);
      int    digits      = MarketInfo(OrderSymbol(), MODE_DIGITS);
      int    pipDigits   = digits & (~1);
      string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      string openPrice   = NumberToStr(OrderOpenPrice(), priceFormat);
      string closePrice  = NumberToStr(OrderClosePrice(), priceFormat);
      string message     = "Position closed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" open="+ openPrice +" close="+ closePrice + NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionClose(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (orderAlerts.sound)
      PlaySoundEx(sound.positionClosed);
   return(!catch("onPositionClose(3)"));
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "Track.Orders="                , BoolToStr(Track.Orders),       "; ",
                            "Order.Alerts.Sound="          , BoolToStr(Order.Alerts.Sound), "; ",
                            "Order.Alerts.Mail.Receiver=\"", Order.Alerts.Mail.Receiver,  "\"; ",
                            "Order.Alerts.SMS.Receiver=\"" , Order.Alerts.SMS.Receiver,   "\"; ",
                            "Order.Alerts.HTTP.Url=\""     , Order.Alerts.HTTP.Url,       "\"; "
                          //"Order.Alerts.ICQ.Contact=\""  , Order.Alerts.ICQ.Contact,    "\"; "
                            )
   );
}
