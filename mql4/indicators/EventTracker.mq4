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
 *     in der Verantwortung des Benutzers, nur einen EventTracker je Instrument f�r die Preis�berwachung zu aktivieren. Mit den frei kombinierbaren Eventkeys
 *     k�nnen beliebige Preis-Events formuliert werden.
 *
 *      � Eventkey:     {Timeframe-ID}.{Signal-ID}[.Params]
 *
 *      � Timeframe-ID: {number}[-]{Timeframe}[-]Ago                 ; [Timeframe|Day|Week|Month] Singular und Plural der Timeframe-Bezeichner sind austauschbar
 *                      This[-]{Timeframe}                           ; Synonym f�r 0-{Timeframe}-Ago
 *                      Last[-]{Timeframe}                           ; Synonym f�r 1-{Timeframe}-Ago
 *                      Today                                        ; Synonym f�r 0-Days-Ago
 *                      Yesterday                                    ; Synonym f�r 1-Day-Ago
 *
 *      � Signal-ID:    BarClose            = On|Off                 ; Erreichen des Close-Preises der Bar
 *                      BarRange            = {90}%                  ; Erreichen der {x}%-Schwelle der Bar-Range (100% = bisheriges High/Low)
 *                      BarBreakout         = On|Off                 ; neues High/Low
 *                      BarBreakout.OnTouch = 1|0                    ; ob zus�tzlich zum Breakout ein Erreichen der Range signalisiert werden soll
 *                      BarBreakout.Reset   = {5} [minute|hour][s]   ; Zeit, nachdem die Pr�fung eines getriggerten Signals reaktiviert wird
 *
 *     Pattern und ihre Konfiguration:
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

//////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////

extern bool   Track.Order.Events   = false;
extern bool   Track.Price.Events   = true;

extern string __________________________;

extern bool   Alerts.Sound         = true;                           // alle Order-Alerts bis auf Sounds sind per Default inaktiv
extern string Alerts.Mail.Receiver = "email@address.tld";            // E-Mailadresse    ("system" => global konfigurierte Adresse)
extern string Alerts.SMS.Receiver  = "phone-number";                 // Telefonnummer    ("system" => global konfigurierte Nummer )
extern string Alerts.HTTP.Url      = "url";                          // vollst�ndige URL ("system" => global konfigurierte URL    )
extern string Alerts.ICQ.UserID    = "contact-id";                   // ICQ-Kontakt      ("system" => global konfigurierte User-ID)

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <iFunctions/iBarShiftNext.mqh>
#include <iFunctions/iBarShiftPrevious.mqh>
#include <iFunctions/iChangedBars.mqh>
#include <iFunctions/iPreviousPeriodTimes.mqh>


bool   track.orders;
bool   track.price;


// Alert-Konfiguration
bool   alerts.sound;
string alerts.sound.orderFailed    = "speech/OrderExecutionFailed.wav";
string alerts.sound.positionOpened = "speech/OrderFilled.wav";
string alerts.sound.positionClosed = "speech/PositionClosed.wav";

bool   alerts.mail;
string alerts.mail.receiver = "";

bool   alerts.sms;
string alerts.sms.receiver = "";

bool   alerts.http;
string alerts.http.url = "";

bool   alerts.icq;
string alerts.icq.userId = "";


// Order-Events
int orders.knownOrders.ticket[];                                     // vom letzten Aufruf bekannte offene Orders
int orders.knownOrders.type  [];


// Price-Events
#define ET_PRICE_BAR_CLOSE          1                                // PriceEvent-Typen
#define ET_PRICE_BAR_RANGE          2
#define ET_PRICE_BAR_BREAKOUT       3

#define I_PRICE_CONFIG_ID           0                                // Signal-ID:       int
#define I_PRICE_CONFIG_ENABLED      1                                // SignalEnabled:   int 0|1
#define I_PRICE_CONFIG_TIMEFRAME    2                                // SignalTimeframe: int PERIOD_D1|PERIOD_W1|PERIOD_MN1
#define I_PRICE_CONFIG_BAR          3                                // SignalBar:       int 0..x (look back)
#define I_PRICE_CONFIG_PARAM1       4                                // SignalParam1:    int ...
#define I_PRICE_CONFIG_PARAM2       5                                // SignalParam2:    int ...
#define I_PRICE_CONFIG_PARAM3       6                                // SignalParam3:    int ...

int    price.config[][7];
double price.data  [][9];                                            // je nach Signal unterschiedliche Laufzeitdaten zur Signalverwaltung
string price.descr [];                                               // Signalbeschreibung f�r Statusanzeige


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
      // (2.1) Konfiguration lesen
      int account = GetAccountNumber();
      if (!account) return(!SetLastError(stdlib.GetLastError()));

      string keys[], keyValues[], key, sValue, sValue1, sValue2, sValue3, sDigits, sParam, iniValue;
      bool   signal.enabled;
      int    iValue, iValue1, iValue2, iValue3, valuesSize, sLen, signal.id, signal.bar, signal.timeframe, signal.param1, signal.param2, signal.param3;
      double dValue, dValue1, dValue2, dValue3;

      string mqlDir   = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
      string file     = TerminalPath() + mqlDir +"\\files\\"+ ShortAccountCompany() +"\\"+ account +"_config.ini";
      string section  = "EventTracker."+ StdSymbol();
      int    keysSize = GetIniKeys(file, section, keys);

      for (int i=0; i < keysSize; i++) {
         // (2.2) Schl�ssel zerlegen und parsen
         valuesSize = Explode(StringToUpper(keys[i]), ".", keyValues, NULL);

         // Timeframe-ID und Baroffset
         if (valuesSize >= 1) {
            sValue = StringTrim(keyValues[0]);
            sLen   = StringLen(sValue); if (!sLen) return(!catch("Configure(1)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));

            if (sValue == "TODAY") {
               signal.bar       = 0;
               signal.timeframe = PERIOD_D1;
            }
            else if (sValue == "YESTERDAY") {
               signal.bar       = 1;
               signal.timeframe = PERIOD_D1;
            }
            else if (StringStartsWith(sValue, "THIS")) {
               signal.bar = 0;
               sValue     = StringTrim(StringRight(sValue, -4));
               if (StringStartsWith(sValue, "-"))
                  sValue = StringTrim(StringRight(sValue, -1));                                    // ggf. "-" vorn abschneiden
               if      (sValue == "MINUTE") signal.timeframe = PERIOD_M1;
               else if (sValue == "HOUR"  ) signal.timeframe = PERIOD_H1;
               else if (sValue == "DAY"   ) signal.timeframe = PERIOD_D1;
               else if (sValue == "WEEK"  ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MONTH" ) signal.timeframe = PERIOD_MN1;
               else if (sValue == "M1"    ) signal.timeframe = PERIOD_M1;
               else if (sValue == "M5"    ) signal.timeframe = PERIOD_M5;
               else if (sValue == "M15"   ) signal.timeframe = PERIOD_M15;
               else if (sValue == "M30"   ) signal.timeframe = PERIOD_M30;
               else if (sValue == "H1"    ) signal.timeframe = PERIOD_H1;
               else if (sValue == "H4"    ) signal.timeframe = PERIOD_H4;
               else if (sValue == "D1"    ) signal.timeframe = PERIOD_D1;
               else if (sValue == "W1"    ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MN1"   ) signal.timeframe = PERIOD_MN1;
               else return(!catch("Configure(2)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            }
            else if (StringStartsWith(sValue, "LAST")) {
               signal.bar = 1;
               sValue     = StringTrim(StringRight(sValue, -4));
               if (StringStartsWith(sValue, "-"))
                  sValue = StringTrim(StringRight(sValue, -1));                                    // ggf. "-" vorn abschneiden
               if      (sValue == "MINUTE") signal.timeframe = PERIOD_M1;
               else if (sValue == "HOUR"  ) signal.timeframe = PERIOD_H1;
               else if (sValue == "DAY"   ) signal.timeframe = PERIOD_D1;
               else if (sValue == "WEEK"  ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MONTH" ) signal.timeframe = PERIOD_MN1;
               else if (sValue == "M1"    ) signal.timeframe = PERIOD_M1;
               else if (sValue == "M5"    ) signal.timeframe = PERIOD_M5;
               else if (sValue == "M15"   ) signal.timeframe = PERIOD_M15;
               else if (sValue == "M30"   ) signal.timeframe = PERIOD_M30;
               else if (sValue == "H1"    ) signal.timeframe = PERIOD_H1;
               else if (sValue == "H4"    ) signal.timeframe = PERIOD_H4;
               else if (sValue == "D1"    ) signal.timeframe = PERIOD_D1;
               else if (sValue == "W1"    ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MN1"   ) signal.timeframe = PERIOD_MN1;
               else return(!catch("Configure(3)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            }
            else if (StringIsDigit(StringLeft(sValue, 1))) {
               sDigits = StringLeft(sValue, 1);                                                    // Zahl vorn parsen
               for (int char, j=1; j < sLen; j++) {
                  char = StringGetChar(sValue, j);
                  if ('0'<=char && char<='9') sDigits = StringLeft(sValue, j+1);
                  else                        break;
               }
               sValue     = StringTrim(StringRight(sValue, -j));                                   // Zahl vorn abschneiden
               signal.bar = StrToInteger(sDigits);

               if (!StringEndsWith(sValue, "AGO")) return(!catch("Configure(4)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
                                                  sValue = StringTrim(StringLeft (sValue, -3));    // "Ago" hinten abschneiden
               if (StringStartsWith(sValue, "-")) sValue = StringTrim(StringRight(sValue, -1));    // ggf. "-" vorn abschneiden
               if (StringEndsWith  (sValue, "-")) sValue = StringTrim(StringLeft (sValue, -1));    // ggf. "-" hinten abschneiden
               if (StringEndsWith  (sValue, "S")) sValue = StringTrim(StringLeft (sValue, -1));    // ggf. "s" hinten abschneiden

               // Timeframe-ID des Strings parsen
               if      (sValue == "MINUTE") signal.timeframe = PERIOD_M1;
               else if (sValue == "HOUR"  ) signal.timeframe = PERIOD_H1;
               else if (sValue == "DAY"   ) signal.timeframe = PERIOD_D1;
               else if (sValue == "WEEK"  ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MONTH" ) signal.timeframe = PERIOD_MN1;
               else if (sValue == "M1"    ) signal.timeframe = PERIOD_M1;
               else if (sValue == "M5"    ) signal.timeframe = PERIOD_M5;
               else if (sValue == "M15"   ) signal.timeframe = PERIOD_M15;
               else if (sValue == "M30"   ) signal.timeframe = PERIOD_M30;
               else if (sValue == "H1"    ) signal.timeframe = PERIOD_H1;
               else if (sValue == "H4"    ) signal.timeframe = PERIOD_H4;
               else if (sValue == "D1"    ) signal.timeframe = PERIOD_D1;
               else if (sValue == "W1"    ) signal.timeframe = PERIOD_W1;
               else if (sValue == "MN1"   ) signal.timeframe = PERIOD_MN1;
               else return(!catch("Configure(5)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            }
            else return(!catch("Configure(6)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
         }

         // Signal-ID
         if (valuesSize >= 2) {
            sValue = StringTrim(keyValues[1]);
            if      (sValue == "BARCLOSE"   ) signal.id = ET_PRICE_BAR_CLOSE;
            else if (sValue == "BARRANGE"   ) signal.id = ET_PRICE_BAR_RANGE;
            else if (sValue == "BARBREAKOUT") signal.id = ET_PRICE_BAR_BREAKOUT;
            else return(!catch("Configure(7)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
         }
         //debug("Configure(0.1)  "+ StringsToStr(keyValues, NULL));

         // zus�tzliche Parameter
         if (valuesSize == 3) {
            sParam = StringTrim(keyValues[2]);
            sValue = GetIniString(file, section, keys[i], "");
            if (!Configure.Set(signal.id, signal.timeframe, signal.bar, sParam, sValue))
               return(!catch("Configure(8)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            //debug("Configure(0.2)  "+ PeriodDescription(signal.timeframe) +","+ signal.bar +"."+ sParam +" = "+ sValue);
            continue;
         }

         // nicht unterst�tzte Parameter
         if (valuesSize > 3) return(!catch("Configure(9)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));


         // (2.3) ini-Value parsen
         iniValue = GetIniString(file, section, keys[i], "");
         //debug("Configure(0.3)  "+ PeriodDescription(signal.timeframe) +","+ signal.bar +" = "+ iniValue);

         if (signal.id == ET_PRICE_BAR_CLOSE) {
            signal.enabled = GetIniBool(file, section, keys[i], false);
            signal.param1  = NULL;
         }
         else if (signal.id == ET_PRICE_BAR_RANGE) {
            sValue1 = iniValue;
            if (StringEndsWith(sValue1, "%"))
               sValue1 = StringTrim(StringLeft(sValue1, -1));
            if (!StringIsDigit(sValue1))       return(!catch("Configure(10)  invalid bar range signal ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (not between 0 and 99) in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            iValue1 = StrToInteger(sValue1);
            if (iValue1 < 0 || iValue1 >= 100) return(!catch("Configure(11)  invalid bar range signal ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (not between 0 and 99) in \""+ file +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            signal.enabled = (iValue1 != 0);
            signal.param1  = iValue1;
         }
         else if (signal.id == ET_PRICE_BAR_BREAKOUT) {
            signal.enabled = GetIniBool(file, section, keys[i], false);
            signal.param1  = NULL;
         }

         // (2.4) Signal zur Konfiguration hinzuf�gen
         int size = ArrayRange(price.config, 0);
         ArrayResize(price.config, size+1);
         ArrayResize(price.data,   size+1);
         ArrayResize(price.descr,  size+1);
         price.config[size][I_PRICE_CONFIG_ID       ] = signal.id;
         price.config[size][I_PRICE_CONFIG_ENABLED  ] = signal.enabled;       // (int) bool
         price.config[size][I_PRICE_CONFIG_TIMEFRAME] = signal.timeframe;
         price.config[size][I_PRICE_CONFIG_BAR      ] = signal.bar;
         price.config[size][I_PRICE_CONFIG_PARAM1   ] = signal.param1;
      }

      // (2.5) Signale initialisieren
      bool success;
      size = ArrayRange(price.config, 0);

      for (i=0; i < size; i++) {
         if (price.config[i][I_PRICE_CONFIG_ENABLED] != 0) {
            switch (price.config[i][I_PRICE_CONFIG_ID]) {
               case ET_PRICE_BAR_CLOSE   : success = CheckBarCloseSignal.Init(i); break;
               case ET_PRICE_BAR_RANGE   : success = CheckBarRangeSignal.Init(i); break;
               case ET_PRICE_BAR_BREAKOUT: success = CheckBreakoutSignal.Init(i); break;
               default:
                  catch("Configure(12)  unknown price signal["+ i +"] = "+ price.config[i][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR);
            }
         }
         if (!success) return(false);
      }
   }


   // (3) Alert-Methoden einlesen und auswerten
   if (track.orders || track.price) {
      // (3.1) Order.Alerts.Sound
      alerts.sound = Alerts.Sound;

      // (3.2) Alerts.Mail.Receiver
      // (3.3) Alerts.SMS.Receiver
      sValue = StringToLower(StringTrim(Alerts.SMS.Receiver));
      if (sValue!="" && sValue!="phone-number") {
         alerts.sms.receiver = ifString(sValue=="system", GetConfigString("SMS", "Receiver", ""), sValue);
         alerts.sms          = StringIsPhoneNumber(alerts.sms.receiver);
         if (!alerts.sms) {
            if (sValue == "system") return(!catch("Configure(13)  "+ ifString(alerts.sms.receiver=="", "Missing", "Invalid") +" global/local config value [SMS]->Receiver = \""+ alerts.sms.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            else                    return(!catch("Configure(14)  Invalid input parameter Alerts.SMS.Receiver = \""+ Alerts.SMS.Receiver +"\"", ERR_INVALID_INPUT_PARAMETER));
         }
      }
      else alerts.sms = false;

      // (3.4) Alerts.HTTP.Url
      // (3.5) Alerts.ICQ.UserID

      // SMS.Alerts
      __SMS.alerts = GetIniBool(file, "EventTracker", "SMS.Alerts", false);
      if (__SMS.alerts) {
         __SMS.receiver = GetGlobalConfigString("SMS", "Receiver", "");
         __SMS.alerts   = StringIsPhoneNumber(__SMS.receiver);
         if (!__SMS.alerts)         return(!catch("Configure(15)  invalid config value [SMS]->Receiver = \""+ __SMS.receiver +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
      }
   }


   int error = catch("Configure(16)");
   if (!error) {
      ShowStatus();
      if (false) {
         debug("Configure()  "+ StringConcatenate("track.orders=", BoolToStr(track.orders),                                          "; ",
                                                  "track.price=",  BoolToStr(track.price),                                           "; ",
                                                  "alerts.sound=", BoolToStr(alerts.sound),                                          "; ",
                                                  "alerts.mail=" , ifString(alerts.mail, "\""+ alerts.mail.receiver +"\"", "false"), "; ",
                                                  "alerts.sms="  , ifString(alerts.sms,  "\""+ alerts.sms.receiver  +"\"", "false"), "; ",
                                                  "alerts.http=" , ifString(alerts.http, "\""+ alerts.http.url      +"\"", "false"), "; ",
                                                  "alerts.icq="  , ifString(alerts.icq,  "\""+ alerts.icq.userId    +"\"", "false"), "; "
         ));
      }
   }
   return(!error);
}


/**
 * Setzt einen Signal-Parameter.
 *
 * @param  int    signalId        - ID des Signals
 * @param  int    signalTimeframe - Timeframe des Signals
 * @param  int    signalBar       - Offset-Bar des Signals
 * @param  string name            - Name des zu setzenden Parameters
 * @param  string value           - Wert des zu setzenden Parameters
 *
 * @return bool - Erfogsstatus
 */
bool Configure.Set(int signalId, int signalTimeframe, int signalBar, string name, string value) {
   int len  = StringLen(value); if (!len) return(false);
   int size = ArrayRange(price.config, 0);

   for (int i=0; i < size; i++) {
      if (price.config[i][I_PRICE_CONFIG_ID] == signalId)
         if (price.config[i][I_PRICE_CONFIG_TIMEFRAME] == signalTimeframe)
            if (price.config[i][I_PRICE_CONFIG_BAR] == signalBar)
               break;
   }
   if (i == size) return(false);
   // i enth�lt hier immer den Index des zu modifizierenden Signals


   if (signalId == ET_PRICE_BAR_BREAKOUT) {
      if (name == "ONTOUCH") {
         price.config[i][I_PRICE_CONFIG_PARAM1] = StrToBool(value);
         return(true);
      }

      if (name == "RESET") {
         if (signalBar == 0) {                                                            // 15 [minute|hour|day][s]: bis jetzt nur in Bar[0] implementiert
            if (!StringIsDigit(StringLeft(value, 1)))
               return(false);

            string sDigits = StringLeft(value, 1);                                        // Zahl vorn parsen
            for (int char, j=1; j < len; j++) {
               char = StringGetChar(value, j);
               if ('0'<=char && char<='9') sDigits = StringLeft(value, j+1);
               else                        break;
            }
            int iValue = StrToInteger(sDigits);
            value      = StringToUpper(StringTrim(StringRight(value, -j)));               // Zahl vorn abschneiden
            if (StringEndsWith(value, "S")) value = StringTrim(StringLeft (value, -1));   // ggf. "s" hinten abschneiden

            if      (value == "MINUTE") iValue *= MINUTES;
            else if (value == "HOUR"  ) iValue *= HOURS;
            else if (value == "DAY"   ) iValue *= DAYS;
            else if (value == "WEEK"  ) iValue *= WEEKS;
            else return(false);

            price.config[i][I_PRICE_CONFIG_PARAM2] = iValue;
         }
         return(true);
      }
   }

   return(false);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // (1) Order-Events �berwachen
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


   // (2) Price-Events �berwachen
   if (track.price) {
      int iNull[];
      onNewTick(iNull);
   }

   return(ShowStatus(last_error));
}


/**
 * Pr�ft, ob der aktuelle Tick ein neuer Tick ist.
 *
 * @param  int results[] - event-spezifische Detailinfos (zur Zeit keine)
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: keine)
 *
 * @return bool - Ergebnis
 */
bool EventListener.NewTick(int results[], int flags=NULL) {
   static double   lastBid, lastAsk;
   static int      lastVol;
   static datetime lastTime;

   int      vol   = Volume[0];
   datetime time  = MarketInfo(Symbol(), MODE_TIME);
   bool newTick, exactMatch;

   if (Bid && Ask && vol && time) {                                  // wenn aktueller Tick g�ltig ist
      if (lastTime != 0) {                                           // wenn letzter Tick g�ltig war
         if      (vol  != lastVol ) newTick = true;                  // wenn der aktuelle Tick ungleich dem letztem Tick ist
         else if (NE(Bid, lastBid)) newTick = true;
         else if (NE(Ask, lastAsk)) newTick = true;
         else if (time != lastTime) newTick = true;

         if (!newTick) {
            //debug("EventListener.NewTick(zTick="+ zTick +")  current tick == last tick");
            exactMatch = true;
         }
      }
      lastBid  = Bid;                                                // aktuellen Tick speichern, wenn er g�ltig ist
      lastAsk  = Ask;
      lastVol  = vol;
      lastTime = time;
   }

   //if      (newTick    ) debug("EventListener.NewTick(zTick="+ zTick +")     new tick: Bid="+ NumberToStr(Bid, PriceFormat) +"  Ask="+ NumberToStr(Ask, PriceFormat) +"  vol="+ vol +"  time="+ DateToStr(time, "w, D.M.Y H:I:S"));
   //else if (!exactMatch) debug("EventListener.NewTick(zTick="+ zTick +")  no new tick: Bid="+ NumberToStr(Bid, PriceFormat) +"  Ask="+ NumberToStr(Ask, PriceFormat) +"  vol="+ vol +"  time="+ DateToStr(time, "w, D.M.Y H:I:S"));

   return(newTick);
}


/**
 * Wird bei Eintreffen eines neuen Ticks ausgef�hrt, nicht bei sonstigen Aufrufen der start()-Funktion.
 *
 * @param  int data[] - event-spezifische Daten (zur Zeit keine)
 *
 * @return bool - Erfolgsstatus
 */
bool onNewTick(int data[]) {
   int  size = ArrayRange(price.config, 0);
   bool success;

   for (int i=0; i < size; i++) {
      if (price.config[i][I_PRICE_CONFIG_ENABLED] != 0) {
         switch (price.config[i][I_PRICE_CONFIG_ID]) {
            case ET_PRICE_BAR_CLOSE:    success = CheckBarCloseSignal(i); break;
            case ET_PRICE_BAR_RANGE:    success = CheckBarRangeSignal(i); break;
            case ET_PRICE_BAR_BREAKOUT: success = CheckBreakoutSignal(i); break;
            default:
               catch("onNewTick(1)  unknow price signal["+ i +"] = "+ price.config[i][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR);
         }
      }
      if (!success)
         return(false);
   }
   return(true);
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
      PlaySoundEx(alerts.sound.orderFailed);
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
      PlaySoundEx(alerts.sound.positionOpened);
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
      PlaySoundEx(alerts.sound.positionClosed);
   return(!catch("onPositionClose(3)"));
}


/**
 * Initialisiert die Laufzeitdaten zur Verwaltung eines BarClose-Signals.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarCloseSignal.Init(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_CLOSE) return(!catch("CheckBarCloseSignal.Init(1)  signal "+ index +" is not a bar close signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                       return(true);

   price.descr[index] = BarCloseSignalToStr(index);
   return(!catch("CheckBarCloseSignal.Init(2)"));
}


/**
 * Pr�ft auf ein BarClose-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarCloseSignal(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_CLOSE) return(!catch("CheckBarCloseSignal(1)  signal "+ index +" is not a bar close signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                       return(true);

   return(!catch("CheckBarCloseSignal(2)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarClose-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarCloseSignalToStr(int index) {
   if (price.config[index][I_PRICE_CONFIG_ID] != ET_PRICE_BAR_CLOSE) return(_emptyStr(catch("BarCloseSignalToStr(1)  signal "+ index +" is not a bar close signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool signal.enabled   = price.config[index][I_PRICE_CONFIG_ENABLED  ] != 0;
   int  signal.timeframe = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int  signal.bar       = price.config[index][I_PRICE_CONFIG_BAR      ];
   int  signal.reset     = price.config[index][I_PRICE_CONFIG_PARAM1   ];

   string description = "Signal  "+ (index+1) +"  at close of "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"] "+ ifString(signal.enabled, "enabled", "disabled");
   return(description);
}


// I_Signal-Bar-Range
#define I_SBR_LEVEL_H         0           // oberer Breakout-Level
#define I_SBR_LEVEL_L         1           // unterer Breakout-Level
#define I_SBR_TIMEFRAME       2           // Timeframe der zur Pr�fung verwendeten Datenreihe
#define I_SBR_ENDBAR          3           // Bar-Offset der Referenzsession innerhalb der zur Pr�fung verwendeten Datenreihe
#define I_SBR_SESSION_END     4           // Ende der j�ngsten Session-Periode innerhalb der zur Pr�fung verwendeten Datenreihe


/**
 * Initialisiert die Laufzeitdaten zur Verwaltung eines BarRange-Signals.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarRangeSignal.Init(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_RANGE) return(!catch("CheckBarRangeSignal.Init(1)  signal "+ index +" is not a bar range signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                       return(true);

   int      signal.timeframe = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int      signal.bar       = price.config[index][I_PRICE_CONFIG_BAR      ];
   int      signal.barRange  = price.config[index][I_PRICE_CONFIG_PARAM1   ];
   int      signal.reset     = price.config[index][I_PRICE_CONFIG_PARAM2   ]; if (signal.bar != 0) signal.reset = NULL;

   int      dataTimeframe    = Min(signal.timeframe, PERIOD_H1);                       // der zur Pr�fung verwendete Timeframe (maximal PERIOD_H1)
   datetime lastSessionEndTime;                                                        // Ende der j�ngsten Session mit vorhandenen Daten (Bar[0]; danach Re-Initialisierung)


   // (1) Anfangs- und Endzeitpunkt der gesuchten Session und entsprechende Bar-Offsets im zu benutzenden Timeframe bestimmen
   datetime openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv;
   int openBar, closeBar;

   for (int i=0; i<=signal.bar; i++) {
      if (!iPreviousPeriodTimes(signal.timeframe, openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv))  return(false);
      //debug("CheckBarRangeSignal.Init(0.1)  bar="+ i +"  open="+ DateToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateToStr(closeTime.fxt, "w, D.M.Y H:I"));
      openBar  = iBarShiftNext    (NULL, dataTimeframe, openTime.srv          ); if (openBar  == EMPTY_VALUE) return(false);
      closeBar = iBarShiftPrevious(NULL, dataTimeframe, closeTime.srv-1*SECOND); if (closeBar == EMPTY_VALUE) return(false);
      if (closeBar == -1) {                                                            // nicht ausreichende Daten zum Tracking: Signal deaktivieren und andere Signale weiterlaufen lassen
         price.config[index][I_PRICE_CONFIG_ENABLED] = false;
         return(!warn("CheckBarRangeSignal.Init(2)  signal "+ index, ERR_HISTORY_INSUFFICIENT));
      }
      if (openBar < closeBar) {                                                        // Datenl�cke, weiter zu den n�chsten verf�gbaren Daten
         i--;
      }
      else if (i == 0) {                                                               // openTime/closeTime enthalten die Daten der ersten Session mit vorhandenen Daten
         lastSessionEndTime = closeTime.srv - 1*SECOND;
      }
   }
   //debug("CheckBarRangeSignal.Init(0.2)  bar="+ signal.bar +"  open="+ DateToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateToStr(closeTime.fxt, "w, D.M.Y H:I"));


   // (2) High/Low bestimmen (openBar ist hier immer >= closeBar und Timeseries-Fehler k�nnen nicht mehr auftreten)
   int highBar = iHighest(NULL, dataTimeframe, MODE_HIGH, openBar-closeBar+1, closeBar);
   int lowBar  = iLowest (NULL, dataTimeframe, MODE_LOW , openBar-closeBar+1, closeBar);
   double H    = iHigh   (NULL, dataTimeframe, highBar);
   double L    = iLow    (NULL, dataTimeframe, lowBar );


   // (3) Signalrange berechnen
   double dist   = (H-L) * Min(signal.barRange, 100-signal.barRange)/100;
   double levelH = H - dist;
   double levelL = L + dist;


   // (4) pr�fen, ob die Level bereits gebrochen wurden
   //if (highBar != iHighest(NULL, dataTimeframe, MODE_HIGH, highBar+1, 0)) H = NULL;    // High ist bereits gebrochen
   //if (lowBar  != iLowest (NULL, dataTimeframe, MODE_LOW,  lowBar +1, 0)) L = NULL;    // Low ist bereits gebrochen


   debug("CheckBarRangeSignal.Init(0.3)  sig="+ index +"  "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"]  H="+ NumberToStr(levelH, PriceFormat) +"  L="+ NumberToStr(levelL, PriceFormat));


   // (5) Daten speichern
   price.data[index][I_SBR_LEVEL_H    ] = NormalizeDouble(levelH, Digits);
   price.data[index][I_SBR_LEVEL_L    ] = NormalizeDouble(levelL, Digits);
   price.data[index][I_SBR_TIMEFRAME  ] = dataTimeframe;
   price.data[index][I_SBR_ENDBAR     ] = closeBar;
   price.data[index][I_SBR_SESSION_END] = lastSessionEndTime;

   price.descr[index] = BarRangeSignalToStr(index);
   return(!catch("CheckBarRangeSignal.Init(3)"));
}


/**
 * Pr�ft auf ein BarRange-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarRangeSignal(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_RANGE) return(!catch("CheckBarRangeSignal(1)  signal "+ index +" is not a bar range signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                       return(true);

   return(!catch("CheckBarRangeSignal(2)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarRange-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarRangeSignalToStr(int index) {
   if (price.config[index][I_PRICE_CONFIG_ID] != ET_PRICE_BAR_RANGE) return(_emptyStr(catch("BarRangeSignalToStr(1)  signal "+ index +" is not a bar range signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool signal.enabled   = price.config[index][I_PRICE_CONFIG_ENABLED  ] != 0;
   int  signal.timeframe = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int  signal.bar       = price.config[index][I_PRICE_CONFIG_BAR      ];
   int  signal.barRange  = price.config[index][I_PRICE_CONFIG_PARAM1   ];
   int  signal.reset     = price.config[index][I_PRICE_CONFIG_PARAM2   ];

   string description = "Signal  "+ (index+1) +"  at "+ signal.barRange +"% of "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"] "+ ifString(signal.enabled, "enabled", "disabled");
   return(description);
}


// I_Signal-Bar-Breakout
#define I_SBB_LEVEL_H         0           // oberer Breakout-Level
#define I_SBB_LEVEL_L         1           // unterer Breakout-Level
#define I_SBB_TIMEFRAME       2           // Timeframe der zur Pr�fung verwendeten Datenreihe
#define I_SBB_ENDBAR          3           // Bar-Offset der Referenzsession innerhalb der zur Pr�fung verwendeten Datenreihe
#define I_SBB_SESSION_END     4           // Ende der j�ngsten Session-Periode innerhalb der zur Pr�fung verwendeten Datenreihe


/**
 * Initialisiert die Laufzeitdaten zur Verwaltung eines Breakout-Signals.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBreakoutSignal.Init(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_BREAKOUT) return(!catch("CheckBreakoutSignal.Init(1)  signal "+ index +" is not a breakout signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                          return(true);

   int      signal.timeframe = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int      signal.bar       = price.config[index][I_PRICE_CONFIG_BAR      ];
   bool     signal.onTouch   = price.config[index][I_PRICE_CONFIG_PARAM1   ] != 0;
   int      signal.reset     = price.config[index][I_PRICE_CONFIG_PARAM2   ]; if (signal.bar > 0) signal.reset = NULL;

   int      dataTimeframe    = Min(signal.timeframe, PERIOD_H1);                       // der zur Pr�fung verwendete Timeframe (maximal PERIOD_H1)
   datetime lastSessionEndTime;                                                        // Ende der j�ngsten Session mit vorhandenen Daten (Bar[0]; danach Re-Initialisierung)


   // (1) Anfangs- und Endzeitpunkt der gesuchten Session und entsprechende Bar-Offsets im zu benutzenden Timeframe bestimmen
   datetime openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv;
   int openBar, closeBar;

   for (int i=0; i<=signal.bar; i++) {
      if (!iPreviousPeriodTimes(signal.timeframe, openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv))  return(false);
      //debug("CheckBreakoutSignal.Init(0.1)  sig="+ index +"  bar="+ i +"  open="+ DateToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateToStr(closeTime.fxt, "w, D.M.Y H:I"));
      openBar  = iBarShiftNext    (NULL, dataTimeframe, openTime.srv          ); if (openBar  == EMPTY_VALUE) return(false);
      closeBar = iBarShiftPrevious(NULL, dataTimeframe, closeTime.srv-1*SECOND); if (closeBar == EMPTY_VALUE) return(false);
      if (closeBar == -1) {                                                            // nicht ausreichende Daten zum Tracking: Signal deaktivieren und andere Signale weiterlaufen lassen
         price.config[index][I_PRICE_CONFIG_ENABLED] = false;
         return(!warn("CheckBreakoutSignal.Init(2)  signal "+ index, ERR_HISTORY_INSUFFICIENT));
      }
      if (openBar < closeBar) {                                                        // Datenl�cke, weiter zu den n�chsten verf�gbaren Daten
         i--;
      }
      else if (i == 0) {                                                               // openTime/closeTime enthalten die Daten der ersten Session mit vorhandenen Daten
         lastSessionEndTime = closeTime.srv - 1*SECOND;
      }
   }
   //debug("CheckBreakoutSignal.Init(0.2)  sig="+ index +"  bar="+ signal.bar +"  open="+ DateToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateToStr(closeTime.fxt, "w, D.M.Y H:I"));


   // (2) High/Low bestimmen (openBar ist hier immer >= closeBar und Timeseries-Fehler k�nnen nicht mehr auftreten)
   int highBar = iHighest(NULL, dataTimeframe, MODE_HIGH, openBar-closeBar+1, closeBar);
   int lowBar  = iLowest (NULL, dataTimeframe, MODE_LOW , openBar-closeBar+1, closeBar);
   double H    = iHigh   (NULL, dataTimeframe, highBar);
   double L    = iLow    (NULL, dataTimeframe, lowBar );


   // (3) pr�fen, ob die Level bereits gebrochen wurden
   if (highBar != iHighest(NULL, dataTimeframe, MODE_HIGH, highBar+1, 0)) H = NULL;    // High ist bereits gebrochen
   if (lowBar  != iLowest (NULL, dataTimeframe, MODE_LOW,  lowBar +1, 0)) L = NULL;    // Low ist bereits gebrochen


   debug("CheckBreakoutSignal.Init(0.3)  sig="+ index +"  "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"]  H="+ NumberToStr(H, PriceFormat) +"  L="+ NumberToStr(L, PriceFormat));


   // (4) Daten speichern
   price.data[index][I_SBB_LEVEL_H    ] = NormalizeDouble(H, Digits);
   price.data[index][I_SBB_LEVEL_L    ] = NormalizeDouble(L, Digits);
   price.data[index][I_SBB_TIMEFRAME  ] = dataTimeframe;
   price.data[index][I_SBB_ENDBAR     ] = closeBar;
   price.data[index][I_SBB_SESSION_END] = lastSessionEndTime;

   price.descr[index] = BarBreakoutSignalToStr(index);
   return(!catch("CheckBreakoutSignal.Init(3)"));
}


/**
 * Pr�ft auf ein Breakout-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus (nicht, ob ein neues Signal getriggert wurde)
 */
bool CheckBreakoutSignal(int index) {
   if ( price.config[index][I_PRICE_CONFIG_ID     ] != ET_PRICE_BAR_BREAKOUT) return(!catch("CheckBreakoutSignal(1)  signal "+ index +" is not a breakout signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!price.config[index][I_PRICE_CONFIG_ENABLED])                          return(true);

   int      signal.timeframe   = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int      signal.bar         = price.config[index][I_PRICE_CONFIG_BAR      ];
   bool     signal.onTouch     = price.config[index][I_PRICE_CONFIG_PARAM1   ] != 0;
   int      signal.reset       = price.config[index][I_PRICE_CONFIG_PARAM2   ];
   //debug("CheckBreakoutSignal(0.1)       sig="+ index +"  "+ PeriodDescription(signal.timeframe) +","+ signal.bar +"  onTouch="+ signal.onTouch +"  reset="+ signal.reset);

   double   signalLevelH       = price.data  [index][I_SBB_LEVEL_H           ];
   double   signalLevelL       = price.data  [index][I_SBB_LEVEL_L           ];
   int      dataTimeframe      = price.data  [index][I_SBB_TIMEFRAME         ];
   int      dataSessionEndBar  = price.data  [index][I_SBB_ENDBAR            ];
   datetime lastSessionEndTime = price.data  [index][I_SBB_SESSION_END       ];


   // (1) aktuellen Tick klassifizieren
   int iNull[];
   bool newTick = EventListener.NewTick(iNull);


   // (2) changedBars(dataTimeframe) f�r den Daten-Timeframe ermitteln
   int oldError    = last_error;
   int changedBars = iChangedBars(NULL, dataTimeframe, MUTE_ERR_SERIES_NOT_AVAILABLE);
   if (changedBars == -1) {                                                // Fehler
      if (last_error == ERR_SERIES_NOT_AVAILABLE)
         return(_true(SetLastError(oldError)));                            // ERR_SERIES_NOT_AVAILABLE unterdr�cken: Pr�fung setzt fort, wenn Daten eingetroffen sind
      return(false);
   }
   //debug("CheckBreakoutSignal(0.2)       sig="+ index +"  changedBars("+ PeriodDescription(dataTimeframe) +")="+ changedBars);
   if (!changedBars)                                                       // z.B. bei Aufruf in init() oder deinit()
      return(true);


   // (3) Pr�flevel re-initialisieren, wenn:
   //     - der Bereich der changedBars(dataTimeframe) den Barbereich der Referenzsession �berlappt (ggf. Ausnahme bei Bar[0], siehe dort) oder wenn
   //     - die n�chste Periode der Referenzsession begonnen hat (automatischer Signal-Reset nach onBarOpen)
   bool reinitialized;
   if (changedBars > dataSessionEndBar) {
      // Ausnahme: Ist Bar[0] Bestandteil der Referenzsession und nur diese Bar ist ver�ndert, wird re-initialisiert, wenn der aktuelle Tick KEIN neuer Tick ist.
      if (changedBars > 1 || !newTick) {
         if (!CheckBreakoutSignal.Init(index)) return(false);              // Bei synthetischen Ticks wird also re-initialisiert, weil changedBars=0 in anderen als dem aktuellem
         reinitialized = true;                                             // Timeframe nicht zuverl�ssig detektiert werden kann.
      }
   }
   else if (changedBars > 1) /*&&*/ if (iTime(NULL, dataTimeframe, 0) > lastSessionEndTime) {
      if (!CheckBreakoutSignal.Init(index)) return(false);                 // automatischer Signal-Reset: neue Periode im Timeframe der Referenzsession
      reinitialized = true;                                                // Der Test auf (changedBars > 1) ist nicht zwingend n�tig, sorgt aber daf�r, da� iTime() nicht bei jedem Tick
   }                                                                       // aufgerufen wird.

   if (reinitialized) {
      signalLevelH       = price.data[index][I_SBB_LEVEL_H    ];           // Werte ggf. neueinlesen
      signalLevelL       = price.data[index][I_SBB_LEVEL_L    ];
      dataTimeframe      = price.data[index][I_SBB_TIMEFRAME  ];
      dataSessionEndBar  = price.data[index][I_SBB_ENDBAR     ];
      lastSessionEndTime = price.data[index][I_SBB_SESSION_END];
   }


   // (4) Signallevel pr�fen
   double price = NormalizeDouble(Bid, Digits);

   if (signalLevelH != NULL) {
      if (GE(price, signalLevelH)) {
         if (GT(price, signalLevelH)) {
            debug("CheckBreakoutSignal(0.3)       sig="+ index +"  new High["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"] = "+ NumberToStr(price, PriceFormat));
            PlaySoundEx("_Up_Windows Alert.wav");
            signalLevelH                      = NULL;
            price.data [index][I_SBB_LEVEL_H] = NULL;
            price.descr[index] = BarBreakoutSignalToStr(index);
         }
         //else if (signal.onTouch) debug("CheckBreakoutSignal(0.4)       sig="+ index +"  touch signal: current price "+ NumberToStr(price, PriceFormat) +" = High["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"]="+ NumberToStr(signalLevelH, PriceFormat));
      }
   }
   if (signalLevelL != NULL) {
      if (LE(price, signalLevelL)) {
         if (LT(price, signalLevelL)) {
            debug("CheckBreakoutSignal(0.5)       sig="+ index +"  new Low["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"] = "+ NumberToStr(price, PriceFormat));
            PlaySoundEx("_Down_Dingdong.wav");
            signalLevelL                      = NULL;
            price.data [index][I_SBB_LEVEL_L] = NULL;
            price.descr[index] = BarBreakoutSignalToStr(index);
         }
         //else if (signal.onTouch) debug("CheckBreakoutSignal(0.6)       sig="+ index +"  touch signal: current price "+ NumberToStr(price, PriceFormat) +" = Low["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"]="+ NumberToStr(signalLevelL, PriceFormat));
      }
   }

   return(!catch("CheckBreakoutSignal(2)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarBreakout-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarBreakoutSignalToStr(int index) {
   if (price.config[index][I_PRICE_CONFIG_ID] != ET_PRICE_BAR_BREAKOUT) return(_emptyStr(catch("BarBreakoutSignalToStr(1)  signal "+ index +" is not a breakout signal = "+ price.config[index][I_PRICE_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool     signal.enabled     = price.config[index][I_PRICE_CONFIG_ENABLED  ] != 0;         //ifString(signal.enabled, "enabled", "disabled")
   int      signal.timeframe   = price.config[index][I_PRICE_CONFIG_TIMEFRAME];
   int      signal.bar         = price.config[index][I_PRICE_CONFIG_BAR      ];
   bool     signal.onTouch     = price.config[index][I_PRICE_CONFIG_PARAM1   ] != 0;
   int      signal.reset       = price.config[index][I_PRICE_CONFIG_PARAM2   ];

   double   signalLevelH       = price.data  [index][I_SBB_LEVEL_H           ];
   double   signalLevelL       = price.data  [index][I_SBB_LEVEL_L           ];
   int      dataTimeframe      = price.data  [index][I_SBB_TIMEFRAME         ];
   int      dataSessionEndBar  = price.data  [index][I_SBB_ENDBAR            ];
   datetime lastSessionEndTime = price.data  [index][I_SBB_SESSION_END       ];

   string description = "Signal  "+ (index+1) +"  at breakout of "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"]    High: "+ ifString(signalLevelH, NumberToStr(signalLevelH, PriceFormat), "triggered") +"    Low: "+ ifString(signalLevelL, NumberToStr(signalLevelL, PriceFormat), "triggered");
   return(description);
}


/**
 * Zeigt den aktuellen Laufzeitstatus optisch an. Ist immer aktiv.
 *
 * @param  int error - anzuzeigender Fehler (default: keiner)
 *
 * @return int - der �bergebene Fehler oder der Fehlerstatus der Funktion, falls kein Fehler �bergeben wurde
 */
int ShowStatus(int error=NULL) {
   if (__STATUS_OFF)
      error = __STATUS_OFF.reason;

   string msg = __NAME__;
   if (!error) msg = StringConcatenate(msg,                                      NL, NL);
   else        msg = StringConcatenate(msg, "  [", ErrorDescription(error), "]", NL, NL);
               msg = StringConcatenate(msg, JoinStrings(price.descr, NL));

   // etwas Abstand nach oben f�r Instrumentanzeige
   Comment(StringConcatenate(NL, msg));
   if (__WHEREAMI__ == FUNC_INIT)
      WindowRedraw();

   if (!catch("ShowStatus(1)"))
      return(error);
   return(last_error);
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
