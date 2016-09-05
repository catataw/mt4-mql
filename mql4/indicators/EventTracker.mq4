/**
 * EventTracker f�r verschiedene Ereignisse. Benachrichtigt optisch, akustisch, per E-Mail und/oder per SMS.
 * Die Art der Benachrichtigung kann je Event konfiguriert werden.
 *
 *
 * (1) Order-Events
 *     Ein aktivierter EventTracker �berwacht alle Symbole eines Accounts, nicht nur das des aktuellen Charts. Es liegt in der Verantwortung des Benutzers,
 *     nur einen aller laufenden EventTracker f�r die Order�berwachung zu aktivieren.
 *
 *     Events:
 *      - eine Position wurde ge�ffnet
 *      - eine Position wurde geschlossen
 *      - die Ausf�hrung einer Order schlug fehl
 *
 *
 * (2) Preis-Events (Signale)
 *     Ein aktivierter EventTracker �berwacht die in der Account-Konfiguration konfigurierten Signale des Instruments des aktuellen Charts. Es liegt in der
 *     Verantwortung des Benutzers, nur einen EventTracker je Instrument f�r Signale zu aktivieren. Folgende Signale k�nnen konfiguriert werden:
 *
 *      � Eventkey:     {Timeframe-ID}.{Signal-ID}[.Params]
 *
 *      � Timeframe-ID: {This|Last|number}[-]{Timeframe}[-]Ago       ; [{Timeframe}|Day|Week|Month]: Singular und Plural der Timeframe-Bezeichner sind austauschbar
 *                      This                                         ; Synonym f�r 0-{Timeframe}-Ago
 *                      Last                                         ; Synonym f�r 1-{Timeframe}-Ago
 *                      Today                                        ; Synonym f�r 0-Days-Ago
 *                      Yesterday                                    ; Synonym f�r 1-Day-Ago
 *
 *      � Signal-ID:    BarClose            = On|Off                 ; Erreichen des Close-Preises der Bar
 *                      BarRange            = {90}%                  ; Erreichen der {x}%-Schwelle der Bar-Range (100% = High/Low der Bar)
 *                      BarBreakout         = On|Off                 ; neues High/Low
 *                      BarBreakout.OnTouch = 1|0                    ; ob zus�tzlich zum Breakout ein Erreichen der Level signalisiert werden soll
 *                      BarBreakout.Reset   = {5} [minute|hour][s]   ; Zeit, nachdem die Pr�fung eines getriggerten Signals reaktiviert wird
 *
 *     Pattern und ihre Konfiguration:
 *      - neues Inside-Range-Pattern auf Tagesbasis
 *      - neues Inside-Range-Pattern auf Wochenbasis
 *      - Aufl�sung eines Inside-Range-Pattern auf Tagesbasis
 *      - Aufl�sung eines Inside-Range-Pattern auf Wochenbasis
 *
 *
 * TODO:
 * -----
 *  - Benachrichtigung per E-Mail, HTML-Request, ICQ
 *  - PositionOpen-/Close-Events w�hrend Timeframe- oder Symbolwechsel werden nicht erkannt
 *  - bei Accountwechsel auftretende Fehler werden nicht abgefangen
 *  - Konfiguration w�hrend eines init-Cycles im Chart speichern, damit Recompilation �berlebt werden kann
 *  - Anzeige der �berwachten Kriterien
 */
#property indicator_chart_window

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern string Track.Orders         = "on | off | account*";
extern string Track.Signals        = "on | off | account*";

extern string __________________________;

extern string Signal.Sound         = "on | off | account*";                            // Sound
extern string Signal.Mail.Receiver = "system | account | auto* | off | address";       // E-Mailadresse
extern string Signal.SMS.Receiver  = "system | account | auto* | off | phone-number";  // Telefonnummer
extern string Signal.ICQ.UserID    = "system | account | auto* | off | user-id";       // ICQ-Kontakt
extern string Signal.HTTP.Url      = "system | account | auto* | off | url";           // URL

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <functions/JoinStrings.mqh>
#include <iFunctions/iBarShiftNext.mqh>
#include <iFunctions/iBarShiftPrevious.mqh>
#include <iFunctions/iChangedBars.mqh>
#include <iFunctions/iPreviousPeriodTimes.mqh>
#include <signals/Configure.Signal.Mail.mqh>
#include <signals/Configure.Signal.SMS.mqh>
#include <signals/Configure.Signal.Sound.mqh>
#include <stdlib.mqh>


bool   track.orders;
bool   track.signals;


// Art der Signalisierung
bool   signal.sound;
string signal.sound.orderFailed      = "speech/OrderExecutionFailed.wav";
string signal.sound.positionOpened   = "speech/OrderFilled.wav";
string signal.sound.positionClosed   = "speech/PositionClosed.wav";
string signal.sound.priceSignal_up   = "Signal-Up.wav";
string signal.sound.priceSignal_down = "Signal-Down.wav";

bool   signal.mail;
string signal.mail.sender   = "";
string signal.mail.receiver = "";

bool   signal.sms;
string signal.sms.receiver = "";

bool   signal.icq;
string signal.icq.userId = "";

bool   signal.http;
string signal.http.url = "";


// Order-Events
int    orders.knownOrders.ticket[];                                  // vom letzten Aufruf bekannte offene Orders
int    orders.knownOrders.type  [];
string orders.accountAlias;                                          // Verwendung in ausgehenden Messages

// Close-Typen f�r automatisch geschlossene Positionen
#define CLOSE_TYPE_TP               1                                // TakeProfit
#define CLOSE_TYPE_SL               2                                // StopLoss
#define CLOSE_TYPE_SO               3                                // StopOut (Margin-Call)

// Price-Events (Signale)
#define ET_SIGNAL_BAR_CLOSE         1                                // Signaltypen
#define ET_SIGNAL_BAR_RANGE         2
#define ET_SIGNAL_BAR_BREAKOUT      3

#define I_SIGNAL_CONFIG_ID          0                                // Signal-ID:       int
#define I_SIGNAL_CONFIG_ENABLED     1                                // SignalEnabled:   int 0|1
#define I_SIGNAL_CONFIG_TIMEFRAME   2                                // SignalTimeframe: int PERIOD_D1|PERIOD_W1|PERIOD_MN1
#define I_SIGNAL_CONFIG_BAR         3                                // SignalBar:       int 0..x (look back)
#define I_SIGNAL_CONFIG_PARAM1      4                                // SignalParam1:    int ...
#define I_SIGNAL_CONFIG_PARAM2      5                                // SignalParam2:    int ...
#define I_SIGNAL_CONFIG_PARAM3      6                                // SignalParam3:    int ...

#define SD_UP                       0                                // Signalrichtungen
#define SD_DOWN                     1

int    signal.config[][7];
double signal.data  [][9];                                           // je nach Signal unterschiedliche Laufzeitdaten zur Signalverwaltung
string signal.descr [];                                              // Signalbeschreibung f�r Statusanzeige


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   if (!Configure())                                                 // Konfiguration einlesen
      return(last_error);

   SetIndexLabel(0, NULL);                                           // Datenanzeige ausschalten
   return(ShowStatus(catch("onInit(1)")));
}


/**
 * Konfiguriert den EventTracker.
 *
 * @return bool - Erfolgsstatus
 */
bool Configure() {
   int    account=GetAccountNumber(), iValue, iValue1, iValue2, iValue3, valuesSize, sLen, signal.id, signal.bar, signal.timeframe, signal.param1, signal.param2, signal.param3;
   if (!account) return(!SetLastError(stdlib.GetLastError()));
   bool   signal.enabled;
   double dValue, dValue1, dValue2, dValue3;
   string keys[], keyValues[], section, key, sValue, sValue1, sValue2, sValue3, sDigits, sParam, iniValue, accountConfig=GetAccountConfigPath(ShortAccountCompany(), account);


   // (1) Track.Orders: "on | off | account*"
   track.orders = false;
   sValue = StringToLower(StringTrim(Track.Orders));
   if (sValue=="on" || sValue=="1" || sValue=="yes" || sValue=="true") {
      track.orders = true;
   }
   else if (sValue=="off" || sValue=="0" || sValue=="no" || sValue=="false" || sValue=="") {
      track.orders = false;
   }
   else if (sValue=="account" || sValue=="on | off | account*") {
      section = "EventTracker";
      key     = "Track.Orders";
      track.orders = GetIniBool(accountConfig, section, key);
   }
   else return(!catch("Configure(1)  Invalid input parameter Track.Orders = \""+ Track.Orders +"\"", ERR_INVALID_INPUT_PARAMETER));

   if (track.orders) {
      section             = "Accounts";
      key                 = account +".alias";                       // AccountAlias
      orders.accountAlias = GetGlobalConfigString(section, key);
      if (!StringLen(orders.accountAlias)) return(!catch("Configure(2)  Missing global account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   }


   // (2) Track.Signals: "on | off | account*"
   track.signals = false;
   sValue = StringToLower(StringTrim(Track.Signals));
   if (sValue=="on" || sValue=="1" || sValue=="yes" || sValue=="true") {
      track.signals = true;
   }
   else if (sValue=="off" || sValue=="0" || sValue=="no" || sValue=="false" || sValue=="") {
      track.orders = false;
   }
   else if (sValue=="account" || sValue=="on | off | account*") {
      section       = "EventTracker";
      key           = "Track.Signals";
      track.signals = GetIniBool(accountConfig, section, key);
   }
   else return(!catch("Configure(3)  Invalid input parameter Track.Signals = \""+ Track.Signals +"\"", ERR_INVALID_INPUT_PARAMETER));

   if (track.signals) {
      // (2.1) die einzelnen Signalkonfigurationen einlesen
      section = "EventTracker."+ StdSymbol();
      int keysSize = GetIniKeys(accountConfig, section, keys);

      for (int i=0; i < keysSize; i++) {
         // (2.2) Schl�ssel zerlegen und parsen
         valuesSize = Explode(StringToUpper(keys[i]), ".", keyValues, NULL);

         // Timeframe-ID und Baroffset
         if (valuesSize >= 1) {
            sValue = StringTrim(keyValues[0]);
            sLen   = StringLen(sValue); if (!sLen) return(!catch("Configure(4)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));

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
               else return(!catch("Configure(5)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
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
               else return(!catch("Configure(6)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
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

               if (!StringEndsWith(sValue, "AGO")) return(!catch("Configure(7)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
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
               else return(!catch("Configure(8)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            }
            else return(!catch("Configure(9)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
         }

         // Signal-ID
         if (valuesSize >= 2) {
            sValue = StringTrim(keyValues[1]);
            if      (sValue == "BARCLOSE"   ) signal.id = ET_SIGNAL_BAR_CLOSE;
            else if (sValue == "BARRANGE"   ) signal.id = ET_SIGNAL_BAR_RANGE;
            else if (sValue == "BARBREAKOUT") signal.id = ET_SIGNAL_BAR_BREAKOUT;
            else return(!catch("Configure(10)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
         }

         // zus�tzliche Parameter
         if (valuesSize == 3) {
            sParam = StringTrim(keyValues[2]);
            sValue = GetIniString(accountConfig, section, keys[i]);
            if (!Configure.Set(signal.id, signal.timeframe, signal.bar, sParam, sValue))
               return(!catch("Configure(11)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            continue;
         }

         // nicht unterst�tzte Parameter
         if (valuesSize > 3) return(!catch("Configure(12)  invalid or unknown price signal ["+ section +"]->"+ keys[i] +" in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));


         // (2.3) ini-Value parsen
         iniValue = GetIniString(accountConfig, section, keys[i]);
         if (signal.id == ET_SIGNAL_BAR_CLOSE) {
            signal.enabled = GetIniBool(accountConfig, section, keys[i]);
            signal.param1  = NULL;
         }
         else if (signal.id == ET_SIGNAL_BAR_RANGE) {
            sValue1 = iniValue;
            if (StringEndsWith(sValue1, "%"))
               sValue1 = StringTrim(StringLeft(sValue1, -1));
            if (!StringIsDigit(sValue1))       return(!catch("Configure(13)  invalid bar range signal ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (not between 0 and 99) in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            iValue1 = StrToInteger(sValue1);
            if (iValue1 < 0 || iValue1 >= 100) return(!catch("Configure(14)  invalid bar range signal ["+ section +"]->"+ keys[i] +"=\""+ iniValue +"\" (not between 0 and 99) in \""+ accountConfig +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
            signal.enabled = (iValue1 != 0);
            signal.param1  = iValue1;
         }
         else if (signal.id == ET_SIGNAL_BAR_BREAKOUT) {
            signal.enabled = GetIniBool(accountConfig, section, keys[i]);
            signal.param1  = NULL;
         }

         // (2.4) Signal zur Konfiguration hinzuf�gen
         int size = ArrayRange(signal.config, 0);
         ArrayResize(signal.config, size+1);
         ArrayResize(signal.data,   size+1);
         ArrayResize(signal.descr,  size+1);
         signal.config[size][I_SIGNAL_CONFIG_ID       ] = signal.id;
         signal.config[size][I_SIGNAL_CONFIG_ENABLED  ] = signal.enabled;      // (int) bool
         signal.config[size][I_SIGNAL_CONFIG_TIMEFRAME] = signal.timeframe;
         signal.config[size][I_SIGNAL_CONFIG_BAR      ] = signal.bar;
         signal.config[size][I_SIGNAL_CONFIG_PARAM1   ] = signal.param1;
      }

      // (2.5) Signale initialisieren
      bool success;
      size = ArrayRange(signal.config, 0);

      for (i=0; i < size; i++) {
         if (signal.config[i][I_SIGNAL_CONFIG_ENABLED] != 0) {
            switch (signal.config[i][I_SIGNAL_CONFIG_ID]) {
               case ET_SIGNAL_BAR_CLOSE   : success = CheckBarCloseSignal.Init   (i); break;
               case ET_SIGNAL_BAR_RANGE   : success = CheckBarRangeSignal.Init   (i); break;
               case ET_SIGNAL_BAR_BREAKOUT: success = CheckBarBreakoutSignal.Init(i); break;
               default:
                  catch("Configure(15)  unknown price signal["+ i +"] = "+ signal.config[i][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR);
            }
         }
         if (!success) return(false);
      }
   }


   // (3) Signal-Methoden einlesen
   if (track.orders || track.signals) {
      if (!Configure.Signal.Sound(Signal.Sound,         signal.sound                                         )) return(last_error);
      if (!Configure.Signal.Mail (Signal.Mail.Receiver, signal.mail, signal.mail.sender, signal.mail.receiver)) return(last_error);
      if (!Configure.Signal.SMS  (Signal.SMS.Receiver,  signal.sms,                      signal.sms.receiver )) return(last_error);
      // Signal.ICQ.UserID
      // Signal.HTTP.Url
   }

   return(!ShowStatus(catch("Configure(16)")));
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
   int size = ArrayRange(signal.config, 0);


   // (1) zu modifizierendes Signal suchen
   for (int i=0; i < size; i++) {
      if (signal.config[i][I_SIGNAL_CONFIG_ID] == signalId)
         if (signal.config[i][I_SIGNAL_CONFIG_TIMEFRAME] == signalTimeframe)
            if (signal.config[i][I_SIGNAL_CONFIG_BAR] == signalBar)
               break;
   }
   if (i == size) return(false);
   // i entspricht hier immer dem Index des zu modifizierenden Signals


   // (2) BarClose-Signal
   if (signalId == ET_SIGNAL_BAR_CLOSE) {
      if (name == "ONTOUCH") {
         signal.config[i][I_SIGNAL_CONFIG_PARAM1] = StrToBool(value);
         return(true);
      }
      return(false);
   }


   // (3) BarRange-Signal
   if (signalId == ET_SIGNAL_BAR_RANGE) {
      if (name == "ONTOUCH") {
         signal.config[i][I_SIGNAL_CONFIG_PARAM2] = StrToBool(value);
         return(true);
      }
      return(false);
   }


   // (4) BarBreakout-Signal
   if (signalId == ET_SIGNAL_BAR_BREAKOUT) {
      if (name == "ONTOUCH") {
         signal.config[i][I_SIGNAL_CONFIG_PARAM1] = StrToBool(value);
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

            signal.config[i][I_SIGNAL_CONFIG_PARAM2] = iValue;
         }
         return(true);
      }
      return(false);
   }

   return(false);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // (1) Orders �berwachen
   if (track.orders) {
      int failedOrders      []; ArrayResize(failedOrders,    0);
      int openedPositions   []; ArrayResize(openedPositions, 0);
      int closedPositions[][2]; ArrayResize(closedPositions, 0);     // { Ticket, CloseType=[CLOSE_TYPE_TP | CLOSE_TYPE_SL | CLOSE_TYPE_SO] }

      if (!CheckPositions(failedOrders, openedPositions, closedPositions))
         return(last_error);

      if (ArraySize(failedOrders   ) > 0) onOrderFail    (failedOrders   );
      if (ArraySize(openedPositions) > 0) onPositionOpen (openedPositions);
      if (ArraySize(closedPositions) > 0) onPositionClose(closedPositions);
   }


   // (2) Signale �berwachen
   if (track.signals) {
      int  size = ArrayRange(signal.config, 0);
      bool success;

      for (int i=0; i < size; i++) {
         if (signal.config[i][I_SIGNAL_CONFIG_ENABLED] != 0) {
            switch (signal.config[i][I_SIGNAL_CONFIG_ID]) {
               case ET_SIGNAL_BAR_CLOSE:    success = CheckBarCloseSignal   (i); break;
               case ET_SIGNAL_BAR_RANGE:    success = CheckBarRangeSignal   (i); break;
               case ET_SIGNAL_BAR_BREAKOUT: success = CheckBarBreakoutSignal(i); break;
               default:
                  catch("onTick(1)  unknown signal["+ i +"] = "+ signal.config[i][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR);
            }
         }
         if (!success) break;
      }
   }

   if (IsError(last_error))
      ShowStatus(last_error);
   return(last_error);
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
bool CheckPositions(int failedOrders[], int openedPositions[], int closedPositions[][]) {
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

   return(!catch("CheckPositions(2)"));
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
      string message     = "Order failed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"with error: \""+ OrderComment() +"\""+ NL +"("+ TimeToStr(TimeLocalEx("onOrderFail(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ orders.accountAlias +")";

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
      string message     = "Position opened: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" at "+ price + NL +"("+ TimeToStr(TimeLocalEx("onPositionOpen(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ orders.accountAlias +")";

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
      string message     = "Position closed: "+ type +" "+ lots +" "+ GetStandardSymbol(OrderSymbol()) +" open="+ openPrice +" close="+ closePrice + closeTypeDescr[closeType] + NL +"("+ TimeToStr(TimeLocalEx("onPositionClose(2)"), TIME_MINUTES|TIME_SECONDS) +", "+ orders.accountAlias +")";

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
 * Initialisiert die Laufzeitdaten zur Verwaltung eines BarClose-Signals.
 *
 * @param  int index    - Index in den zur �berwachung konfigurierten Signalen
 * @param  bool barOpen - ob dieser Aufruf zur Initialisierung von einem BarOpen-Event ausgel�st wurde (default: nein)
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarCloseSignal.Init(int index, bool barOpen=false) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_CLOSE) return(!catch("CheckBarCloseSignal.Init(1)  signal "+ index +" is not a bar close signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                        return(true);

   if (barOpen) debug("CheckBarCloseSignal.Init(0.1)  sidx="+ index +"  barOpen="+ barOpen);

   signal.descr[index] = BarCloseSignalToStr(index);
   return(!ShowStatus(catch("CheckBarCloseSignal.Init(2)")));
}


/**
 * Pr�ft auf ein BarClose-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarCloseSignal(int index) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_CLOSE) return(!catch("CheckBarCloseSignal(1)  signal "+ index +" is not a bar close signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                        return(true);

   if (false)
      onBarCloseSignal(index, NULL);

   return(!catch("CheckBarCloseSignal(2)"));
}


/**
 * Handler f�r BarClose-Signale.
 *
 * @param  int index     - Index in den zur �berwachung konfigurierten Signalen
 * @param  int direction - Richtung des Signals: SD_UP|SD_DOWN
 *
 * @return bool - Erfolgsstatus
 */
bool onBarCloseSignal(int index, int direction) {
   if (!track.signals)                         return(true);
   if (direction!=SD_UP && direction!=SD_DOWN) return(!catch("onBarCloseSignal(1)  invalid parameter direction = "+ direction, ERR_INVALID_PARAMETER));

   string message = "";
   if (__LOG) log("onBarCloseSignal(2)  "+ message);


   // (1) Sound abspielen
   if (signal.sound) {
      if (direction == SD_UP) PlaySoundEx(signal.sound.priceSignal_up  );
      else                    PlaySoundEx(signal.sound.priceSignal_down);
   }

   // (2) Mailversand
   if (signal.mail) {
   }

   // (3) SMS-Verand
   if (signal.sms) {
      if (!SendSMS(signal.sms.receiver, message)) return(false);
   }

   // (4) HTTP-Request
   if (signal.http) {
   }

   // (5) ICQ-Message
   if (signal.icq) {
   }

   return(!catch("onBarCloseSignal(3)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarClose-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarCloseSignalToStr(int index) {
   if (signal.config[index][I_SIGNAL_CONFIG_ID] != ET_SIGNAL_BAR_CLOSE) return(_EMPTY_STR(catch("BarCloseSignalToStr(1)  signal "+ index +" is not a bar close signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool signal.enabled   = signal.config[index][I_SIGNAL_CONFIG_ENABLED  ] != 0;
   int  signal.timeframe = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int  signal.bar       = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   bool signal.onTouch   = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ] != 0;
   int  signal.reset     = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ];

   string description = "Signal  "+ (index+1) +"  at close of "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"] "+ ifString(signal.enabled, "enabled", "disabled") +"    onTouch: "+ ifString(signal.onTouch, "On", "Off");
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
 * @param  int index    - Index in den zur �berwachung konfigurierten Signalen
 * @param  bool barOpen - ob dieser Aufruf zur Initialisierung von einem BarOpen-Event ausgel�st wurde (default: nein)
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarRangeSignal.Init(int index, bool barOpen=false) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_RANGE) return(!catch("CheckBarRangeSignal.Init(1)  signal "+ index +" is not a bar range signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                        return(true);

   if (barOpen) debug("CheckBarRangeSignal.Init(0.1)  sidx="+ index +"  barOpen="+ barOpen);

   int      signal.timeframe = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int      signal.bar       = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   int      signal.barRange  = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ];
   bool     signal.onTouch   = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ] != 0;
   int      signal.reset     = signal.config[index][I_SIGNAL_CONFIG_PARAM3   ]; if (signal.bar != 0) signal.reset = NULL;

   int      dataTimeframe    = Min(signal.timeframe, PERIOD_H1);                       // der zur Pr�fung verwendete Timeframe (maximal PERIOD_H1)
   datetime lastSessionEndTime;                                                        // Ende der j�ngsten Session mit vorhandenen Daten (Bar[0]; danach Re-Initialisierung)


   // (1) Anfangs- und Endzeitpunkt der gesuchten Session und entsprechende Bar-Offsets im zu benutzenden Timeframe bestimmen
   datetime openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv;
   int openBar, closeBar;

   for (int i=0; i<=signal.bar; i++) {
      if (!iPreviousPeriodTimes(signal.timeframe, openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv))  return(false);
      //debug("CheckBarRangeSignal.Init(0.2)  bar="+ i +"  open="+ DateTimeToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateTimeToStr(closeTime.fxt, "w, D.M.Y H:I"));
      openBar  = iBarShiftNext    (NULL, dataTimeframe, openTime.srv          ); if (openBar  == EMPTY_VALUE) return(false);
      closeBar = iBarShiftPrevious(NULL, dataTimeframe, closeTime.srv-1*SECOND); if (closeBar == EMPTY_VALUE) return(false);
      if (closeBar == -1) {                                                            // nicht ausreichende Daten zum Tracking: Signal deaktivieren und andere Signale weiterlaufen lassen
         signal.config[index][I_SIGNAL_CONFIG_ENABLED] = false;
         return(!warn("CheckBarRangeSignal.Init(2)  signal "+ index, ERR_HISTORY_INSUFFICIENT));
      }
      if (openBar < closeBar) {                                                        // Datenl�cke, weiter zu den n�chsten verf�gbaren Daten
         i--;
      }
      else if (i == 0) {                                                               // openTime/closeTime enthalten die Daten der ersten Session mit vorhandenen Daten
         lastSessionEndTime = closeTime.srv - 1*SECOND;
      }
   }
   //debug("CheckBarRangeSignal.Init(0.3)  bar="+ signal.bar +"  open="+ DateTimeToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateTimeToStr(closeTime.fxt, "w, D.M.Y H:I"));


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
   debug("CheckBarRangeSignal.Init(0.4)  sidx="+ index +"  "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"]  H="+ NumberToStr(levelH, PriceFormat) +"  L="+ NumberToStr(levelL, PriceFormat));


   // (5) Daten speichern
   signal.data[index][I_SBR_LEVEL_H    ] = NormalizeDouble(levelH, Digits);
   signal.data[index][I_SBR_LEVEL_L    ] = NormalizeDouble(levelL, Digits);
   signal.data[index][I_SBR_TIMEFRAME  ] = dataTimeframe;
   signal.data[index][I_SBR_ENDBAR     ] = closeBar;
   signal.data[index][I_SBR_SESSION_END] = lastSessionEndTime;

   signal.descr[index] = BarRangeSignalToStr(index);
   return(!ShowStatus(catch("CheckBarRangeSignal.Init(3)")));
}


/**
 * Pr�ft auf ein BarRange-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarRangeSignal(int index) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_RANGE) return(!catch("CheckBarRangeSignal(1)  signal "+ index +" is not a bar range signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                        return(true);

   if (false)
      onBarRangeSignal(index, NULL);

   return(!catch("CheckBarRangeSignal(2)"));
}


/**
 * Handler f�r BarRange-Signale.
 *
 * @param  int index     - Index in den zur �berwachung konfigurierten Signalen
 * @param  int direction - Richtung des Signals: SD_UP|SD_DOWN
 *
 * @return bool - Erfolgsstatus
 */
bool onBarRangeSignal(int index, int direction) {
   if (!track.signals)                         return(true);
   if (direction!=SD_UP && direction!=SD_DOWN) return(!catch("onBarRangeSignal(1)  invalid parameter direction = "+ direction, ERR_INVALID_PARAMETER));

   string message = "";
   if (__LOG) log("onBarRangeSignal(2)  "+ message);


   // (1) Sound abspielen
   if (signal.sound) {
      if (direction == SD_UP) PlaySoundEx(signal.sound.priceSignal_up  );
      else                    PlaySoundEx(signal.sound.priceSignal_down);
   }

   // (2) Mailversand
   if (signal.mail) {
   }

   // (3) SMS-Verand
   if (signal.sms) {
      if (!SendSMS(signal.sms.receiver, message)) return(false);
   }

   // (4) HTTP-Request
   if (signal.http) {
   }

   // (5) ICQ-Message
   if (signal.icq) {
   }

   return(!catch("onBarRangeSignal(3)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarRange-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarRangeSignalToStr(int index) {
   if (signal.config[index][I_SIGNAL_CONFIG_ID] != ET_SIGNAL_BAR_RANGE) return(_EMPTY_STR(catch("BarRangeSignalToStr(1)  signal "+ index +" is not a bar range signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool signal.enabled   = signal.config[index][I_SIGNAL_CONFIG_ENABLED  ] != 0;
   int  signal.timeframe = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int  signal.bar       = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   int  signal.barRange  = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ];
   bool signal.onTouch   = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ] != 0;
   int  signal.reset     = signal.config[index][I_SIGNAL_CONFIG_PARAM3   ];

   string description = "Signal  "+ (index+1) +"  at "+ signal.barRange +"% of "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"] "+ ifString(signal.enabled, "enabled", "disabled") +"    onTouch: "+ ifString(signal.onTouch, "On", "Off");
   return(description);
}


// I_Signal-Bar-Breakout
#define I_SBB_LEVEL_H            0        // oberer Breakout-Level
#define I_SBB_LEVEL_L            1        // unterer Breakout-Level
#define I_SBB_TIMEFRAME          2        // Timeframe der zur Pr�fung verwendeten Datenreihe
#define I_SBB_ENDBAR             3        // Bar-Offset der Referenzsession innerhalb der zur Pr�fung verwendeten Datenreihe
#define I_SBB_SESSION_END        4        // Ende der j�ngsten Session-Periode innerhalb der zur Pr�fung verwendeten Datenreihe
#define I_SBB_LAST_CHANGED_BARS  5        // changedBars der zur Pr�fung verwendeten Datenreihe bei der letzten Pr�fung


/**
 * Initialisiert die Laufzeitdaten zur Verwaltung eines Breakout-Signals.
 *
 * @param  int index    - Index in den zur �berwachung konfigurierten Signalen
 * @param  bool barOpen - ob dieser Aufruf zur Initialisierung von einem BarOpen-Event ausgel�st wurde (default: nein)
 *
 * @return bool - Erfolgsstatus
 */
bool CheckBarBreakoutSignal.Init(int index, bool barOpen=false) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_BREAKOUT) return(!catch("CheckBarBreakoutSignal.Init(1)  signal "+ index +" is not a breakout signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                           return(true);

   int      signal.timeframe = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int      signal.bar       = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   bool     signal.onTouch   = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ] != 0;
   int      signal.reset     = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ]; if (signal.bar > 0) signal.reset = NULL;

   int      dataTimeframe    = Min(signal.timeframe, PERIOD_H1);                       // der zur Pr�fung verwendete Timeframe (maximal PERIOD_H1)
   datetime lastSessionEndTime;                                                        // Ende der j�ngsten Session mit vorhandenen Daten (Bar[0]; danach Re-Initialisierung)


   // (1) Anfangs- und Endzeitpunkt der gesuchten Session und entsprechende Bar-Offsets im zu benutzenden Timeframe bestimmen
   datetime openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv;
   int openBar, closeBar;

   for (int i=0; i<=signal.bar; i++) {
      if (!iPreviousPeriodTimes(signal.timeframe, openTime.fxt, closeTime.fxt, openTime.srv, closeTime.srv))  return(false);
      //debug("CheckBarBreakoutSignal.Init(0.1)  sidx="+ index +"  bar="+ i +"  open="+ DateTimeToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateTimeToStr(closeTime.fxt, "w, D.M.Y H:I"));
      openBar  = iBarShiftNext    (NULL, dataTimeframe, openTime.srv          ); if (openBar  == EMPTY_VALUE) return(false);
      closeBar = iBarShiftPrevious(NULL, dataTimeframe, closeTime.srv-1*SECOND); if (closeBar == EMPTY_VALUE) return(false);
      if (closeBar == -1) {                                                            // nicht ausreichende Daten zum Tracking: Signal deaktivieren und andere Signale weiterlaufen lassen
         signal.config[index][I_SIGNAL_CONFIG_ENABLED] = false;
         return(!warn("CheckBarBreakoutSignal.Init(2)  signal "+ index, ERR_HISTORY_INSUFFICIENT));
      }
      if (openBar < closeBar) {                                                        // Datenl�cke, weiter zu den n�chsten verf�gbaren Daten
         i--;
      }
      else if (i == 0) {                                                               // openTime/closeTime enthalten die Daten der ersten Session mit vorhandenen Daten
         lastSessionEndTime = closeTime.srv - 1*SECOND;
      }
   }
   //debug("CheckBarBreakoutSignal.Init(0.2)  sidx="+ index +"  bar="+ signal.bar +"  open="+ DateTimeToStr(openTime.fxt, "w, D.M.Y H:I") +"  close="+ DateTimeToStr(closeTime.fxt, "w, D.M.Y H:I"));


   // (2) High/Low bestimmen (openBar ist hier immer >= closeBar und Timeseries-Fehler k�nnen nicht mehr auftreten)
   int highBar = iHighest(NULL, dataTimeframe, MODE_HIGH, openBar-closeBar+1, closeBar);
   int lowBar  = iLowest (NULL, dataTimeframe, MODE_LOW , openBar-closeBar+1, closeBar);
   double H    = iHigh   (NULL, dataTimeframe, highBar);
   double L    = iLow    (NULL, dataTimeframe, lowBar );


   // (3) pr�fen, ob die Level bereits gebrochen wurden
   if (highBar != iHighest(NULL, dataTimeframe, MODE_HIGH, highBar+1, 0)) H = NULL;    // High ist bereits gebrochen
   if (lowBar  != iLowest (NULL, dataTimeframe, MODE_LOW,  lowBar +1, 0)) L = NULL;    // Low ist bereits gebrochen
   //debug("CheckBarBreakoutSignal.Init(0.3)  sidx="+ index +"  "+ PeriodDescription(signal.timeframe) +"["+ signal.bar +"]  H="+ NumberToStr(H, PriceFormat) +"  L="+ NumberToStr(L, PriceFormat) +"  T="+ TimeToStr(openTime.srv));


   // (4) Daten speichern
   signal.data [index][I_SBB_LEVEL_H          ] = NormalizeDouble(H, Digits);
   signal.data [index][I_SBB_LEVEL_L          ] = NormalizeDouble(L, Digits);
   signal.data [index][I_SBB_TIMEFRAME        ] = dataTimeframe;
   signal.data [index][I_SBB_ENDBAR           ] = closeBar;
   signal.data [index][I_SBB_SESSION_END      ] = lastSessionEndTime;
   signal.data [index][I_SBB_LAST_CHANGED_BARS] = 0;
   signal.descr[index]                          = BarBreakoutSignalToStr(index);

   return(!ShowStatus(catch("CheckBarBreakoutSignal.Init(3)")));
}


/**
 * Pr�ft auf ein Breakout-Event.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return bool - Erfolgsstatus (nicht, ob ein neues Signal getriggert wurde)
 */
bool CheckBarBreakoutSignal(int index) {
   if ( signal.config[index][I_SIGNAL_CONFIG_ID     ] != ET_SIGNAL_BAR_BREAKOUT) return(!catch("CheckBarBreakoutSignal(1)  signal "+ index +" is not a breakout signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR));
   if (!signal.config[index][I_SIGNAL_CONFIG_ENABLED])                           return(true);

   int      signal.timeframe   = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int      signal.bar         = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   bool     signal.onTouch     = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ] != 0;
   int      signal.reset       = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ];

   double   signalLevelH       = signal.data  [index][I_SBB_LEVEL_H            ];
   double   signalLevelL       = signal.data  [index][I_SBB_LEVEL_L            ];
   int      dataTimeframe      = signal.data  [index][I_SBB_TIMEFRAME          ];
   int      dataSessionEndBar  = signal.data  [index][I_SBB_ENDBAR             ];
   datetime lastSessionEndTime = signal.data  [index][I_SBB_SESSION_END        ];
   int      lastChangedBars    = signal.data  [index][I_SBB_LAST_CHANGED_BARS  ];


   // (1) aktuellen Tick klassifizieren
   static int  lastTick;
   static bool wasNewTickBefore, tick.isNew;

   if (Tick != lastTick) {
      lastTick = Tick;
      if (tick.isNew) wasNewTickBefore = true;
      tick.isNew = EventListener.NewTick();
   }


   // (2) changedBars(dataTimeframe) f�r den Daten-Timeframe ermitteln
   int oldError    = last_error;
   int changedBars = iChangedBars(NULL, dataTimeframe, MUTE_ERR_SERIES_NOT_AVAILABLE);
   if (changedBars == -1) {                                                // Fehler
      if (last_error == ERR_SERIES_NOT_AVAILABLE)
         return(_true(SetLastError(oldError)));                            // ERR_SERIES_NOT_AVAILABLE unterdr�cken: Pr�fung setzt fort, wenn Daten eingetroffen sind
      return(false);
   }
   if (!changedBars)                                                       // z.B. bei Aufruf in init() oder deinit()
      return(true);
   //debug("CheckBarBreakoutSignal(0.1)       sidx="+ index +"  changedBars="+ changedBars +"  newTick="+ newTick);


   // (3) Pr�flevel re-initialisieren, wenn:
   //     - der Bereich der changedBars(dataTimeframe) den Barbereich der Referenzsession �berlappt (ggf. Ausnahme bei Bar[0], siehe dort) oder wenn
   //     - die n�chste Periode der Referenzsession begonnen hat (automatischer Signal-Reset bei onBarOpen)
   bool reinitialized;
   if (changedBars > dataSessionEndBar) {
      // Ausnahme: Ist Bar[0] Bestandteil der Referenzsession und nur diese Bar ist ver�ndert, wird re-initialisiert, wenn der aktuelle Tick KEIN neuer Tick ist.
      if (changedBars > 1 || !tick.isNew) {
         //debug("CheckBarBreakoutSignal(0.2)       sidx="+ index +"  changedBars="+ changedBars +"  newTick="+ newTick);
         if (!CheckBarBreakoutSignal.Init(index)) return(false);           // Bei synthetischen Ticks wird also re-initialisiert, weil changedBars=0 in anderen als dem aktuellem
         reinitialized = true;                                             // Timeframe nicht zuverl�ssig detektiert werden kann.
      }
   }
   else if (changedBars > 1) /*&&*/ if (iTime(NULL, dataTimeframe, 0) > lastSessionEndTime) {
      //debug("CheckBarBreakoutSignal(0.3)       sidx="+ index +"  changedBars="+ changedBars +"  newTick="+ newTick);
      if (!CheckBarBreakoutSignal.Init(index, true)) return(false);        // automatischer Signal-Reset bei signal.bar > 1: neue Periode im Timeframe der Referenzsession
      reinitialized = true;                                                // Der Test auf (changedBars > 1) ist nicht wirklich n�tig, sorgt aber daf�r, da� iTime() nicht bei jedem Tick
   }                                                                       // aufgerufen wird.

   if (reinitialized) {
      signalLevelH       = signal.data[index][I_SBB_LEVEL_H          ];    // Werte ggf. neueinlesen
      signalLevelL       = signal.data[index][I_SBB_LEVEL_L          ];
      dataTimeframe      = signal.data[index][I_SBB_TIMEFRAME        ];
      dataSessionEndBar  = signal.data[index][I_SBB_ENDBAR           ];
      lastSessionEndTime = signal.data[index][I_SBB_SESSION_END      ];
      lastChangedBars    = signal.data[index][I_SBB_LAST_CHANGED_BARS];
   }


   // (4) Signallevel pr�fen, wenn die Bars des Datentimeframes komplett scheinen und der zweite echte Tick eintrifft
   if (lastChangedBars<=2 && changedBars<=2 && wasNewTickBefore && tick.isNew) {    // Optimierung unn�tig, da im Normalfall immer alle Bedingungen zutreffen
      //debug("CheckBarBreakoutSignal(0.4)       sidx="+ index +"  checking tick "+ Tick);

      double price = NormalizeDouble(Bid, Digits);

      if (signalLevelH != NULL) {
         if (GE(price, signalLevelH)) {
            if (GT(price, signalLevelH)) {
               //debug("CheckBarBreakoutSignal(0.5)       sidx="+ index +"  breakout signal: price="+ NumberToStr(price, PriceFormat) +"  changedBars="+ changedBars);
               onBarBreakoutSignal(index, SD_UP, signalLevelH, price, TimeCurrentEx("CheckBarBreakoutSignal(2)"));
               signalLevelH                       = NULL;
               signal.data [index][I_SBB_LEVEL_H] = NULL;
               signal.descr[index]                = BarBreakoutSignalToStr(index);
               ShowStatus();
            }
            //else if (signal.onTouch) debug("CheckBarBreakoutSignal(0.6)       sidx="+ index +"  touch signal: current price "+ NumberToStr(price, PriceFormat) +" = High["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"]="+ NumberToStr(signalLevelH, PriceFormat));
         }
      }
      if (signalLevelL != NULL) {
         if (LE(price, signalLevelL)) {
            if (LT(price, signalLevelL)) {
               //debug("CheckBarBreakoutSignal(0.7)       sidx="+ index +"  breakout signal: price="+ NumberToStr(price, PriceFormat) +"  changedBars="+ changedBars);
               onBarBreakoutSignal(index, SD_DOWN, signalLevelL, price, TimeCurrentEx("CheckBarBreakoutSignal(3)"));
               signalLevelL                       = NULL;
               signal.data [index][I_SBB_LEVEL_L] = NULL;
               signal.descr[index]                = BarBreakoutSignalToStr(index);
               ShowStatus();
            }
            //else if (signal.onTouch) debug("CheckBarBreakoutSignal(0.8)       sidx="+ index +"  touch signal: current price "+ NumberToStr(price, PriceFormat) +" = Low["+ PeriodDescription(signal.timeframe) +","+ signal.bar +"]="+ NumberToStr(signalLevelL, PriceFormat));
         }
      }
   }
   else {
      //debug("CheckBarBreakoutSignal(0.9)       sidx="+ index +"  not checking tick "+ Tick +", lastChangedBars="+ lastChangedBars +"  changedBars="+ changedBars +"  wasNewTickBefore="+ wasNewTickBefore +"  tick.isNew="+ tick.isNew);
   }

   signal.data[index][I_SBB_LAST_CHANGED_BARS] = changedBars;
   return(!catch("CheckBarBreakoutSignal(4)"));
}


/**
 * Handler f�r BarBreakout-Signale.
 *
 * @param  int      index     - Index in den zur �berwachung konfigurierten Signalen
 * @param  int      direction - Richtung des Signals: SD_UP|SD_DOWN
 * @param  double   level     - Signallevel, der ber�hrt oder gebrochen wurde
 * @param  double   price     - Preis, der den Signallevel ber�hrt oder gebrochen hat
 * @param  datetime time.srv  - Zeitpunkt des Signals (Serverzeit)
 *
 * @return bool - Erfolgsstatus
 */
bool onBarBreakoutSignal(int index, int direction, double level, double price, datetime time.srv) {
   if (direction!=SD_UP && direction!=SD_DOWN) return(!catch("onBarBreakoutSignal(1)  invalid parameter direction = "+ direction, ERR_INVALID_PARAMETER));
   if (!track.signals)                         return(true);

   int signal.timeframe = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int signal.bar       = signal.config[index][I_SIGNAL_CONFIG_BAR      ];

   string message = StdSymbol() +" broke "+ BarDescription(signal.timeframe, signal.bar) +"'s "+ ifString(direction==SD_UP, "high", "low") + NL +" ("+ TimeToStr(TimeLocalEx("onBarBreakoutSignal(2)"), TIME_MINUTES|TIME_SECONDS) +")";
   if (__LOG) log("onBarBreakoutSignal(3)  "+ message);


   // (1) Sound abspielen
   if (signal.sound) {
      if (direction == SD_UP) PlaySoundEx(signal.sound.priceSignal_up  );
      else                    PlaySoundEx(signal.sound.priceSignal_down);
   }

   // (2) Mailversand
   if (signal.mail) {
   }

   // (3) SMS-Verand
   if (signal.sms) {
      if (!SendSMS(signal.sms.receiver, message)) return(false);
   }

   // (4) HTTP-Request
   if (signal.http) {
   }

   // (5) ICQ-Message
   if (signal.icq) {
   }

   return(!catch("onBarBreakoutSignal(4)"));
}


/**
 * Gibt die lesbare Beschreibung eines BarBreakout-Signals zur�ck.
 *
 * @param  int index - Index in den zur �berwachung konfigurierten Signalen
 *
 * @return string
 */
string BarBreakoutSignalToStr(int index) {
   if (signal.config[index][I_SIGNAL_CONFIG_ID] != ET_SIGNAL_BAR_BREAKOUT) return(_EMPTY_STR(catch("BarBreakoutSignalToStr(1)  signal "+ index +" is not a breakout signal = "+ signal.config[index][I_SIGNAL_CONFIG_ID], ERR_RUNTIME_ERROR)));

   bool     signal.enabled     = signal.config[index][I_SIGNAL_CONFIG_ENABLED  ] != 0;
   int      signal.timeframe   = signal.config[index][I_SIGNAL_CONFIG_TIMEFRAME];
   int      signal.bar         = signal.config[index][I_SIGNAL_CONFIG_BAR      ];
   bool     signal.onTouch     = signal.config[index][I_SIGNAL_CONFIG_PARAM1   ] != 0;
   int      signal.reset       = signal.config[index][I_SIGNAL_CONFIG_PARAM2   ];

   double   signalLevelH       = signal.data  [index][I_SBB_LEVEL_H           ];
   double   signalLevelL       = signal.data  [index][I_SBB_LEVEL_L           ];
   int      dataTimeframe      = signal.data  [index][I_SBB_TIMEFRAME         ];
   int      dataSessionEndBar  = signal.data  [index][I_SBB_ENDBAR            ];
   datetime lastSessionEndTime = signal.data  [index][I_SBB_SESSION_END       ];

   string description = "Signal  "+ (index+1) +"  at break of "+ BarDescription(signal.timeframe, signal.bar) +"'s    High: "+ ifString(signalLevelH, NumberToStr(signalLevelH, PriceFormat), "triggered") +"    Low: "+ ifString(signalLevelL, NumberToStr(signalLevelL, PriceFormat), "triggered") +"    onTouch: "+ ifString(signal.onTouch, "On", "Off");
   return(description);
}


/**
 * Gibt die lesbare Beschreibung einer Bar eines Timeframes zur�ck.
 *
 * @param  int timeframe - Timeframe
 * @param  int bar       - Bar-Offset
 *
 * @return string
 */
string BarDescription(int timeframe, int bar) {
   string description = PeriodDescription(timeframe) +"["+ bar +"]";

   if      (description == "M1[0]" ) description = "This Minute";
   else if (description == "M1[1]" ) description = "Last Minute";
   else if (description == "H1[0]" ) description = "This Hour";
   else if (description == "H1[1]" ) description = "Last Hour";
   else if (description == "D1[0]" ) description = "Today";
   else if (description == "D1[1]" ) description = "Yesterday";
   else if (description == "W1[0]" ) description = "This Week";
   else if (description == "W1[1]" ) description = "Last Week";
   else if (description == "MN1[0]") description = "This Month";
   else if (description == "MN1[1]") description = "Last Month";

   return(description);
}


/**
 * Zeigt den aktuellen Laufzeitstatus optisch an. Ist immer aktiv.
 *
 * @param  int error - anzuzeigender Fehler (default: keiner)
 *
 * @return int - der �bergebene Fehler
 */
int ShowStatus(int error=NULL) {
   if (__STATUS_OFF)
      error = __STATUS_OFF.reason;

   string sSettings, sError;

   if (track.orders || track.signals) sSettings = "    Sound="+ ifString(signal.sound, "On", "Off") + ifString(signal.mail, "    Mail="+ signal.mail.receiver, "") + ifString(signal.sms, "    SMS="+ signal.sms.receiver, "") + ifString(signal.http, "    HTTP="+ signal.http.url, "") + ifString(signal.icq, "    ICQ="+ signal.icq.userId, "");
   else                               sSettings = ":  Off";

   if (!error)                        sError    = "";
   else                               sError    = "  ["+ ErrorDescription(error) +"]";

   string msg = StringConcatenate(__NAME__, sSettings, sError,           NL);

   if (track.orders || track.signals) {
      msg    = StringConcatenate(msg, "-------------------",             NL);

      if (track.orders) {
         msg = StringConcatenate(msg,
                                "Track.Orders = 1",                      NL);
      }
      if (track.signals) {
         msg = StringConcatenate(msg,
                                 JoinStrings(signal.descr, NL),          NL);
      }
      msg    = StringConcatenate(msg,                                    NL,
                                                                         NL,
                                "Last signals:", NL, "----------------", NL);
   }

   Comment(NL, NL, NL, msg);
   if (__WHEREAMI__ == RF_INIT)
      WindowRedraw();
   return(error);
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "Track.Orders="        , track.orders,                         "; ",
                            "Track.Signals="       , track.signals,                        "; ",

                            "Signal.Sound="        , signal.sound,                         "; ",
                            "Signal.Mail.Receiver=", DoubleQuoteStr(signal.mail.receiver), "; ",
                            "Signal.SMS.Receiver=" , DoubleQuoteStr(signal.sms.receiver),  "; ",
                            "Signal.HTTP.Url="     , DoubleQuoteStr(signal.http.url),      "; ",
                            "Signal.ICQ.UserID="   , DoubleQuoteStr(signal.icq.userId),    "; ")
   );
}
