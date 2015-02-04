/**
 * EventTracker f�r verschiedene Ereignisse. Benachrichtigt optisch, akustisch, per E-Mail, SMS, HTML-Request oder ICQ.
 *
 *
 * (1) Order-Events
 *     Die Order�berwachung wird im Indikator aktiviert/deaktiviert. Ein so aktivierter EventTracker �berwacht alle Symbole eines Accounts, nicht nur das
 *     des aktuellen Charts. Es liegt in der Verantwortung des Benutzers, nur einen aller laufenden EventTracker f�r die Order�berwachung zu aktivieren.
 *
 *     Events:
 *      - Orderausf�hrung fehlgeschlagen
 *      - Position ge�ffnet
 *      - Position geschlossen
 *
 *
 * (2) Preis-Events
 *     Die Preis�berwachung wird im Indikator aktiviert/deaktiviert und die einzelnen Events in der Account-Konfiguration je Instrument konfiguriert. Es liegt
 *     in der Verantwortung des Benutzers, nur einen EventTracker je Instrument f�r die Preis�berwachung zu aktivieren.
 *
 *     Events:
 *      - Erreichen der 10%-Schwelle der Tages-Range
 *      - Bruch der Tages-Range = neues Tages-High/Low (mit konfigurierbarer Wartezeit)
 *      - Erreichen der 10%-Schwelle der Vortages-Range
 *      - Bruch der Vortages-Range
 *      - Erreichen des Vorvortages-Close
 *
 *      - Erreichen der 10%-Schwelle der Wochen-Range
 *      - Bruch der Wochen-Range = neues Wochen-High/Low (mit konfigurierbarer Wartezeit)
 *      - Erreichen der 10%-Schwelle der Vorwochen-Range
 *      - Bruch der Vorwochen-Range
 *      - Erreichen des Vorvorwochen-Close
 *
 *     Pattern:
 *      - neues Inside-Range-Pattern auf Tagesbasis
 *      - neues Inside-Range-Pattern auf Wochenbasis
 *      - Aufl�sung eines Inside-Range-Pattern auf Tagesbasis
 *      - Aufl�sung eines Inside-Range-Pattern auf Wochenbasis
 *
 *
 * Die Art der Benachrichtigung (akustisch, E-Mail, SMS, HTML-Request, ICQ) kann je Event einzeln konfiguriert werden.
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


extern bool   Track.Order.Events   = false;
extern bool   Track.Price.Events   = false;

extern string __________________________;

extern bool   Alerts.Sound         = true;                           // alle Order-Alerts bis auf Sounds sind per Default inaktiv
extern string Alerts.Mail.Receiver = "email@address.tld";            // E-Mailadresse    ("system" => global konfigurierte Adresse)
extern string Alerts.SMS.Receiver  = "phone-number";                 // Telefonnummer    ("system" => global konfigurierte Nummer )
extern string Alerts.HTTP.Url      = "url";                          // vollst�ndige URL ("system" => global konfigurierte URL    )
extern string Alerts.ICQ.UserID    = "contact-id";                   // ICQ-Kontakt      ("system" => global konfigurierte User-ID)

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include <core/indicator.mqh>


bool     track.orders;
bool     track.price;

bool     alerts.sound;
string   sound.orderFailed    = "speech/OrderExecutionFailed.wav";
string   sound.positionOpened = "speech/OrderFilled.wav";
string   sound.positionClosed = "speech/PositionClosed.wav";

bool     alerts.mail;
string   alerts.mail.receiver = "";

bool     alerts.sms;
string   alerts.sms.receiver = "";

bool     alerts.http;
string   alerts.http.url = "";

bool     alerts.icq;
string   alerts.icq.userId = "";


// interne Variablen
int      orders.knownOrders.ticket[];                                // vom letzten Aufruf bekannte offene Orders
int      orders.knownOrders.type  [];


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   if (!Configure())                                                 // Konfiguration einlesen
      return(last_error);

   SetIndexLabel(0, NULL);                                           // Datenanzeige ausschalten
   return(catch("onInit(1)"));
}


/**
 * Konfiguriert den EventTracker.
 *
 * @return bool - Erfolgsstatus
 */
bool Configure() {
   // (1) Konfiguration des OrderTrackers einlesen und auswerten
   track.orders = Track.Order.Events;
   if (track.orders) {
   }


   // (2) Konfiguration des PriceTrackers einlesen und auswerten
   track.price = Track.Price.Events;
   if (track.price) {
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
   }


   // (3) Alert-Methoden auswerten
   if (track.orders || track.price) {

      // (3.1) Order.Alerts.Sound
      alerts.sound = Alerts.Sound;

      // (3.2) Alerts.Mail.Receiver

      // (3.3) Alerts.SMS.Receiver
      string sValue = StringToLower(StringTrim(Alerts.SMS.Receiver));
      if (sValue != "") {
         alerts.sms.receiver = ifString(sValue=="system", GetConfigString("SMS", "Receiver", ""), sValue);
         alerts.sms          = StringIsPhoneNumber(alerts.sms.receiver);
         if (!alerts.sms) {
            if (sValue == "system") return(!catch("Configure(1)  "+ ifString(alerts.sms.receiver=="", "Missing", "Invalid") +" global/local config value [SMS]->Receiver = \""+ alerts.sms.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            else                    return(!catch("Configure(2)  Invalid input parameter Alerts.SMS.Receiver = \""+ Alerts.SMS.Receiver +"\"", ERR_INVALID_INPUT_PARAMVALUE));
         }
      }
      else alerts.sms = false;

      // (3.4) Alerts.HTTP.Url
      // (3.5) Alerts.ICQ.UserID



      // SMS.Alerts
      __SMS.alerts = GetIniBool(file, "EventTracker", "SMS.Alerts", false);
      if (__SMS.alerts) {
         __SMS.receiver = GetGlobalConfigString("SMS", "Receiver", "");
         // TODO: Rufnummer validieren
         //if (!StringIsDigit(__SMS.receiver)) return(!catch("Configure(1)  invalid config value [SMS]->Receiver = \""+ __SMS.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
         if (!StringLen(__SMS.receiver))
            __SMS.alerts = false;
      }
   }


   int error = catch("Configure(2)");
   if (!error) {
      debug("Configure()  "+ StringConcatenate("track.orders=", BoolToStr(track.orders),                                          "; ",
                                               "track.price=",  BoolToStr(track.price),                                           "; ",
                                               "alerts.sound=", BoolToStr(alerts.sound),                                          "; ",
                                               "alerts.mail=" , ifString(alerts.mail, "\""+ alerts.mail.receiver +"\"", "false"), "; ",
                                               "alerts.sms="  , ifString(alerts.sms,  "\""+ alerts.sms.receiver  +"\"", "false"), "; ",
                                               "alerts.http=" , ifString(alerts.http, "\""+ alerts.http.url      +"\"", "false"), "; ",
                                               "alerts.icq="  , ifString(alerts.icq,  "\""+ alerts.icq.userId    +"\"", "false"), "; "
      ));
   }
   return(!error);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // (1) Pending- und Limit-Orders �berwachen
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
      string message     = "Order failed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"with error: \""+ OrderComment() +"\""+ NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onOrderFail(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (alerts.sound)
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
      string message     = "Position opened: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionOpen(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (alerts.sound)
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
      string message     = "Position closed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" open="+ openPrice +" close="+ closePrice + NL +"("+ TimeToStr(TimeLocal(), TIME_MINUTES|TIME_SECONDS) +")";

      // ggf. SMS verschicken
      if (__SMS.alerts) {
         if (!SendSMS(__SMS.receiver, message))
            return(!SetLastError(stdlib.GetLastError()));
      }
      else if (__LOG) log("onPositionClose(2)  "+ message);
   }

   // ggf. Sound abspielen
   if (alerts.sound)
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

                            "Track.Order.Events="    , BoolToStr(Track.Order.Events),  "; ",
                            "Track.Price.Events="    , BoolToStr(Track.Price.Events),  "; ",
                            "Alerts.Sound="          , BoolToStr(Alerts.Sound),        "; ",
                            "Alerts.Mail.Receiver=\"", Alerts.Mail.Receiver,         "\"; ",
                            "Alerts.SMS.Receiver=\"" , Alerts.SMS.Receiver,          "\"; ",
                            "Alerts.HTTP.Url=\""     , Alerts.HTTP.Url,              "\"; ",
                            "Alerts.ICQ.UserID=\""   , Alerts.ICQ.UserID,            "\"; "
                            )
   );
}
