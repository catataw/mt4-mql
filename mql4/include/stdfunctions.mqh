/**
 * Globale Funktionen.
 */
#include <metaquotes.mqh>                                            // MetaQuotes-Aliase
#include <MT4Expander.mqh>


/**
 * L�dt den Input-Dialog des aktuellen Programms neu.
 *
 * @return int - Fehlerstatus
 */
int start.RelaunchInputDialog() {
   int error;

   if (IsExpert()) {
      if (!IsTesting())
         error = Chart.Expert.Properties();
   }
   else if (IsIndicator()) {
      //if (!IsTesting())
      //   error = Chart.Indicator.Properties();                     // TODO: implementieren
   }

   if (IsError(error))
      SetLastError(error, NULL);
   return(error);
}


/**
 * Schickt eine Debug-Message an den angeschlossenen Debugger.
 *
 * @param  string message - Message
 * @param  int    error   - Fehlercode
 *
 * @return int - derselbe Fehlercode
 *
 * NOTE:  OutputDebugString() ben�tigt Admin-Rechte.
 */
int debug(string message, int error=NO_ERROR) {
   string name;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [", ErrorToStr(error)          , "]");

   OutputDebugStringA(StringConcatenate("MetaTrader::", Symbol(), ",", PeriodDescription(Period()), "::", name, "::", StringReplace(message, NL, " ")));
   return(error);
}


/**
 * Pr�ft, ob ein Fehler aufgetreten ist und zeigt diesen optisch und akustisch an. Der Fehler wird an die Debug-Ausgabe geschickt und in der
 * globalen Variable last_error gespeichert. Der mit der MQL-Funktion GetLastError() auslesbare letzte Fehler ist nach Aufruf dieser Funktion
 * immer zur�ckgesetzt.
 *
 * @param  string location - Ortsbezeichner des Fehlers, kann zus�tzlich eine anzuzeigende Nachricht enthalten
 * @param  int    error    - manuelles Forcieren eines bestimmten Fehlers
 * @param  bool   orderPop - ob ein zuvor gespeicherter Orderkontext wiederhergestellt werden soll (default: nein)
 *
 * @return int - der aufgetretene Fehler
 */
int catch(string location, int error=NO_ERROR, bool orderPop=false) {
   orderPop = orderPop!=0;

   if      (!error                  ) { error  =                      GetLastError(); }
   else if (error == ERR_WIN32_ERROR) { error += GetLastWin32Error(); GetLastError(); }
   else                               {                               GetLastError(); }

   static bool recursive = false;                                             // mit Initializer: h�lt in EA's immer
                                                                              //                  h�lt in Indikatoren bis zum n�chsten init-Cycle (ok)

   if (error != NO_ERROR) {
      if (recursive)                                                          // rekursive Fehler abfangen
         return(debug("catch(1)  recursive error: "+ location, error));
      recursive = true;

      // (1) Fehler immer auch an Debug-Ausgabe schicken
      debug("ERROR: "+ location, error);


      // (2) Programmnamen um Instanz-ID erweitern
      string name, nameInstanceId;
      if (StringLen(__NAME__) > 0) name = __NAME__;
      else                         name = WindowExpertName();                 // falls __NAME__ noch nicht definiert ist

      int logId = GetCustomLogID();
      if (!logId)       nameInstanceId = name;
      else {
         int pos = StringFind(name, "::");
         if (pos == -1) nameInstanceId = StringConcatenate(           name,       "(", logId, ")");
         else           nameInstanceId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
      }


      // (3) Fehler loggen
      string message = StringConcatenate(location, "  [", ifString(error>=ERR_WIN32_ERROR, "win32:"+ (error-ERR_WIN32_ERROR), ErrorToStr(error)), "]");

      bool logged, alerted;
      if (__LOG_CUSTOM)
         logged = logged || __log.custom(StringConcatenate("ERROR: ", name, "::", message));                   // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
      if (!logged) {
         Alert("ERROR:   ", Symbol(), ",", PeriodDescription(Period()), "  ", nameInstanceId, "::", message);  // global Log: ggf. mit Instanz-ID
         logged  = true;
         alerted = alerted || !IsExpert() || !IsTesting();
      }
      message = StringConcatenate(nameInstanceId, "::", message);


      // (4) Fehler anzeigen
      if (IsTesting()) {
         // weder Alert() noch MessageBox() k�nnen verwendet werden
         string caption = StringConcatenate("Strategy Tester ", Symbol(), ",", PeriodDescription(Period()));

         pos = StringFind(message, ") ");
         if (pos == -1) message = StringConcatenate("ERROR in ", message);    // Message am ersten Leerzeichen nach der ersten schlie�enden Klammer umbrechen
         else           message = StringConcatenate("ERROR in ", StringLeft(message, pos+1), NL, StringTrimLeft(StringRight(message, -pos-2)));
                        message = StringConcatenate(TimeToStr(TimeCurrentEx("catch(2)"), TIME_FULL), NL, message);

         PlaySoundEx("alert.wav");
         ForceMessageBox(caption, message, MB_ICONERROR|MB_OK);
         alerted = true;
      }
      else if (!alerted) {
         // EA au�erhalb des Testers, Script/Indikator im oder au�erhalb des Testers
         Alert("ERROR:   ", Symbol(), ",", PeriodDescription(Period()), "  ", message);
         alerted = true;
      }


      // (5) last_error setzen
      SetLastError(error, NULL);                                              // je nach Moduletyp unterschiedlich implementiert
      recursive = false;
   }

   if (orderPop)
      OrderPop(location);

   return(error);
}


/**
 * Gibt optisch und akustisch eine Warnung aus.
 *
 * @param  string message - anzuzeigende Nachricht
 * @param  int    error   - anzuzeigender Fehlercode
 *
 * @return int - derselbe Fehlercode
 */
int warn(string message, int error=NO_ERROR) {
   // (1) Warnung zus�tzlich an Debug-Ausgabe schicken
   debug("WARN: "+ message, error);


   // (2) Programmnamen um Instanz-ID erweitern
   string name, name_wId;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

   int logId = GetCustomLogID();
   if (logId != 0) {
      int pos = StringFind(name, "::");
      if (pos == -1) name_wId = StringConcatenate(           name,       "(", logId, ")");
      else           name_wId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
   }
   else              name_wId = name;

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");


   // (3) Warnung loggen
   bool logged, alerted;
   if (__LOG_CUSTOM)
      logged = logged || __log.custom(StringConcatenate("WARN: ", name, "::", message));              // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
   if (!logged) {
      Alert("WARN:   ", Symbol(), ",", PeriodDescription(Period()), "  ", name_wId, "::", message);   // global Log: ggf. mit Instanz-ID
      logged  = true;
      alerted = alerted || !IsExpert() || !IsTesting();
   }
   message = StringConcatenate(name_wId, "::", message);


   // (4) Warnung anzeigen
   if (IsTesting()) {
      // weder Alert() noch MessageBox() k�nnen verwendet werden
      string caption = StringConcatenate("Strategy Tester ", Symbol(), ",", PeriodDescription(Period()));
      pos = StringFind(message, ") ");
      if (pos == -1) message = StringConcatenate("WARN in ", message);                       // Message am ersten Leerzeichen nach der ersten schlie�enden Klammer umbrechen
      else           message = StringConcatenate("WARN in ", StringLeft(message, pos+1), NL, StringTrimLeft(StringRight(message, -pos-2)));
                     message = StringConcatenate(TimeToStr(TimeCurrentEx("warn(1)"), TIME_FULL), NL, message);

      PlaySoundEx("alert.wav");
      ForceMessageBox(caption, message, MB_ICONERROR|MB_OK);
   }
   else if (!alerted) {
      // au�erhalb des Testers
      Alert("WARN:   ", Symbol(), ",", PeriodDescription(Period()), "  ", message);
      alerted = true;
   }

   return(error);
}


/**
 * Gibt optisch und akustisch eine Warnung aus und verschickt diese Warnung per SMS, wenn SMS-Benachrichtigungen aktiv sind.
 *
 * @param  string message - anzuzeigende Nachricht
 * @param  int    error   - anzuzeigender Fehlercode
 *
 * @return int - derselbe Fehlercode
 */
int warnSMS(string message, int error=NO_ERROR) {
   int _error = warn(message, error);

   if (__SMS.alerts) {
      if (!This.IsTesting()) {
         // Programmnamen um Instanz-ID erweitern
         string name, name_wId;
         if (StringLen(__NAME__) > 0) name = __NAME__;
         else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

         int logId = GetCustomLogID();
         if (logId != 0) {
            int pos = StringFind(name, "::");
            if (pos == -1) name_wId = StringConcatenate(           name,       "(", logId, ")");
            else           name_wId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
         }
         else              name_wId = name;

         if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
         else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");

         message = StringConcatenate("WARN:   ", Symbol(), ",", PeriodDescription(Period()), "  ", name_wId, "::", message);

         // SMS verschicken
         SendSMS(__SMS.receiver, TimeToStr(TimeLocalEx("warnSMS(1)"), TIME_MINUTES) +" "+ message);
      }
   }
   return(_error);
}


/**
 * Loggt eine Message in das Logfile des Terminals.
 *
 * @param  string message - Message
 * @param  int    error   - Fehlercode
 *
 * @return int - derselbe Fehlercode
 */
int log(string message, int error=NO_ERROR) {
   if (!__LOG)
      return(error);


   // (1) ggf. ausschlie�liche/zus�tzliche Ausgabe via Debug oder ...
   static int static.logToDebug  = -1; if (static.logToDebug  == -1) static.logToDebug  = GetLocalConfigBool("Logging", "LogToDebug" );
   static int static.logTeeDebug = -1; if (static.logTeeDebug == -1) static.logTeeDebug = GetLocalConfigBool("Logging", "LogTeeDebug");

   if (static.logToDebug  == 1) return(debug(message, error));
   if (static.logTeeDebug == 1)        debug(message, error);


   string name;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();                 // falls __NAME__ noch nicht definiert ist

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");


   // (2) Custom-Log benutzen oder ...
   if (__LOG_CUSTOM)
      if (__log.custom(StringConcatenate(name, "::", message)))            // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
         return(error);


   // (3) Global-Log benutzen
   int logId = GetCustomLogID();
   if (logId != 0) {
      int pos = StringFind(name, "::");
      if (pos == -1) name = StringConcatenate(           name,       "(", logId, ")");
      else           name = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
   }
   Print(StringConcatenate(name, "::", StringReplace(message, NL, " ")));  // global Log: ggf. mit Instanz-ID

   return(error);
}


/**
 * Loggt eine Message in das Logfile des Programms.
 *
 * @param  string message - vollst�ndige zu loggende Message (ohne Zeitstempel, Symbol, Timeframe)
 *
 * @return bool - Erfolgsstatus: u.a. FALSE, wenn das Instanz-eigene Logfile nicht definiert ist
 *
 * @access private - Aufruf nur aus log()
 */
bool __log.custom(string message) {
   bool old.LOG_CUSTOM = __LOG_CUSTOM;
   int logId = GetCustomLogID();
   if (logId == NULL)
      return(false);

   message = StringConcatenate(TimeToStr(TimeLocalEx("__log.custom(1)"), TIME_FULL), "  ", StdSymbol(), ",", StringPadRight(PeriodDescription(Period()), 3, " "), "  ", StringReplace(message, NL, " "));

   string fileName = StringConcatenate(logId, ".log");

   int hFile = FileOpen(fileName, FILE_READ|FILE_WRITE);
   if (hFile < 0) {
      __LOG_CUSTOM = false; catch("__log.custom(2)->FileOpen(\""+ fileName +"\")"); __LOG_CUSTOM = old.LOG_CUSTOM;
      return(false);
   }

   if (!FileSeek(hFile, 0, SEEK_END)) {
      __LOG_CUSTOM = false; catch("__log.custom(3)->FileSeek()"); __LOG_CUSTOM = old.LOG_CUSTOM;
      FileClose(hFile);
      return(_false(GetLastError()));
   }

   if (FileWrite(hFile, message) < 0) {
      __LOG_CUSTOM = false; catch("__log.custom(4)->FileWrite()"); __LOG_CUSTOM = old.LOG_CUSTOM;
      FileClose(hFile);
      return(_false(GetLastError()));
   }

   FileClose(hFile);
   return(true);
}


/**
 * Setzt den internen Fehlercode des Modules.
 *
 * @param  int error - Fehlercode
 *
 * @return int - derselbe Fehlercode (for chaining)
 *
 *
 * NOTE: Akzeptiert einen weiteren beliebigen Parameter, der bei der Verarbeitung jedoch ignoriert wird.
 */
int SetLastError(int error, int param=NULL) {
   last_error = ec_SetMqlError(__ExecutionContext, error);
   return(error);
}


/**
 * Gibt die Beschreibung eines Fehlercodes zur�ck.
 *
 * @param  int error - MQL- oder gemappter Win32-Fehlercode
 *
 * @return string
 */
string ErrorDescription(int error) {
   if (error >= ERR_WIN32_ERROR)                                                                                 // >=100000
      return(StringConcatenate("win32 error (", error-ERR_WIN32_ERROR, ")"));

   switch (error) {
      case NO_ERROR                       : return("no error"                                                 ); //      0

      // trade server errors
      case ERR_NO_RESULT                  : return("no result"                                                ); //      1
      case ERR_COMMON_ERROR               : return("trade denied"                                             ); //      2
      case ERR_INVALID_TRADE_PARAMETERS   : return("invalid trade parameters"                                 ); //      3
      case ERR_SERVER_BUSY                : return("trade server busy"                                        ); //      4
      case ERR_OLD_VERSION                : return("old terminal version"                                     ); //      5
      case ERR_NO_CONNECTION              : return("no connection to trade server"                            ); //      6
      case ERR_NOT_ENOUGH_RIGHTS          : return("not enough rights"                                        ); //      7
      case ERR_TOO_FREQUENT_REQUESTS      : return("too frequent requests"                                    ); //      8
      case ERR_MALFUNCTIONAL_TRADE        : return("malfunctional trade operation"                            ); //      9
      case ERR_ACCOUNT_DISABLED           : return("account disabled"                                         ); //     64
      case ERR_INVALID_ACCOUNT            : return("invalid account"                                          ); //     65
      case ERR_TRADE_TIMEOUT              : return("trade timeout"                                            ); //    128
      case ERR_INVALID_PRICE              : return("invalid price"                                            ); //    129 Kurs bewegt sich zu schnell (aus dem Fenster)
      case ERR_INVALID_STOP               : return("invalid stop"                                             ); //    130
      case ERR_INVALID_TRADE_VOLUME       : return("invalid trade volume"                                     ); //    131
      case ERR_MARKET_CLOSED              : return("market closed"                                            ); //    132
      case ERR_TRADE_DISABLED             : return("trading disabled"                                         ); //    133
      case ERR_NOT_ENOUGH_MONEY           : return("not enough money"                                         ); //    134
      case ERR_PRICE_CHANGED              : return("price changed"                                            ); //    135
      case ERR_OFF_QUOTES                 : return("off quotes"                                               ); //    136
      case ERR_BROKER_BUSY                : return("broker busy, automated trading disabled?"                 ); //    137
      case ERR_REQUOTE                    : return("requote"                                                  ); //    138
      case ERR_ORDER_LOCKED               : return("order locked"                                             ); //    139
      case ERR_LONG_POSITIONS_ONLY_ALLOWED: return("long positions only allowed"                              ); //    140
      case ERR_TOO_MANY_REQUESTS          : return("too many requests"                                        ); //    141
    //case 142: ???                                                                                              //    @see  stderror.mqh
    //case 143: ???                                                                                              //    @see  stderror.mqh
    //case 144: ???                                                                                              //    @see  stderror.mqh
      case ERR_TRADE_MODIFY_DENIED        : return("modification denied because too close to market"          ); //    145
      case ERR_TRADE_CONTEXT_BUSY         : return("trade context busy"                                       ); //    146
      case ERR_TRADE_EXPIRATION_DENIED    : return("expiration setting denied by broker"                      ); //    147
      case ERR_TRADE_TOO_MANY_ORDERS      : return("number of open orders reached the broker limit"           ); //    148
      case ERR_TRADE_HEDGE_PROHIBITED     : return("hedging prohibited"                                       ); //    149
      case ERR_TRADE_PROHIBITED_BY_FIFO   : return("prohibited by FIFO rules"                                 ); //    150

      // runtime errors
      case ERR_NO_MQLERROR                : return("no MQL error"                                             ); //   4000 never generated error
      case ERR_WRONG_FUNCTION_POINTER     : return("wrong function pointer"                                   ); //   4001
      case ERR_ARRAY_INDEX_OUT_OF_RANGE   : return("array index out of range"                                 ); //   4002
      case ERR_NO_MEMORY_FOR_CALL_STACK   : return("no memory for function call stack"                        ); //   4003
      case ERR_RECURSIVE_STACK_OVERFLOW   : return("recursive stack overflow"                                 ); //   4004
      case ERR_NOT_ENOUGH_STACK_FOR_PARAM : return("not enough stack for parameter"                           ); //   4005
      case ERR_NO_MEMORY_FOR_PARAM_STRING : return("no memory for parameter string"                           ); //   4006
      case ERR_NO_MEMORY_FOR_TEMP_STRING  : return("no memory for temp string"                                ); //   4007
      case ERR_NOT_INITIALIZED_STRING     : return("uninitialized string"                                     ); //   4008
      case ERR_NOT_INITIALIZED_ARRAYSTRING: return("uninitialized string in array"                            ); //   4009
      case ERR_NO_MEMORY_FOR_ARRAYSTRING  : return("no memory for string in array"                            ); //   4010
      case ERR_TOO_LONG_STRING            : return("string too long"                                          ); //   4011
      case ERR_REMAINDER_FROM_ZERO_DIVIDE : return("remainder from division by zero"                          ); //   4012
      case ERR_ZERO_DIVIDE                : return("division by zero"                                         ); //   4013
      case ERR_UNKNOWN_COMMAND            : return("unknown command"                                          ); //   4014
      case ERR_WRONG_JUMP                 : return("wrong jump"                                               ); //   4015
      case ERR_NOT_INITIALIZED_ARRAY      : return("array not initialized"                                    ); //   4016
      case ERR_DLL_CALLS_NOT_ALLOWED      : return("DLL calls not allowed"                                    ); //   4017
      case ERR_CANNOT_LOAD_LIBRARY        : return("cannot load library"                                      ); //   4018
      case ERR_CANNOT_CALL_FUNCTION       : return("cannot call function"                                     ); //   4019
      case ERR_EX4_CALLS_NOT_ALLOWED      : return("EX4 library calls not allowed"                            ); //   4020
      case ERR_NO_MEMORY_FOR_RETURNED_STR : return("no memory for temp string returned from function"         ); //   4021
      case ERR_SYSTEM_BUSY                : return("system busy"                                              ); //   4022
      case ERR_DLL_EXCEPTION              : return("DLL exception"                                            ); //   4023
      case ERR_INTERNAL_ERROR             : return("internal error"                                           ); //   4024
      case ERR_OUT_OF_MEMORY              : return("out of memory"                                            ); //   4025
      case ERR_INVALID_POINTER            : return("invalid pointer"                                          ); //   4026
      case ERR_FORMAT_TOO_MANY_FORMATTERS : return("too many formatters in the format function"               ); //   4027
      case ERR_FORMAT_TOO_MANY_PARAMETERS : return("parameters count exceeds formatters count"                ); //   4028
      case ERR_ARRAY_INVALID              : return("invalid array"                                            ); //   4029
      case ERR_CHART_NOREPLY              : return("no reply from chart"                                      ); //   4030
      case ERR_INVALID_FUNCTION_PARAMSCNT : return("invalid function parameter count"                         ); //   4050 invalid parameters count
      case ERR_INVALID_PARAMETER          : return("invalid parameter"                                        ); //   4051 invalid parameter
      case ERR_STRING_FUNCTION_INTERNAL   : return("internal string function error"                           ); //   4052
      case ERR_ARRAY_ERROR                : return("array error"                                              ); //   4053 array error
      case ERR_SERIES_NOT_AVAILABLE       : return("requested time series not available"                      ); //   4054 time series not available
      case ERR_CUSTOM_INDICATOR_ERROR     : return("custom indicator error"                                   ); //   4055 custom indicator error
      case ERR_INCOMPATIBLE_ARRAYS        : return("incompatible arrays"                                      ); //   4056 incompatible arrays
      case ERR_GLOBAL_VARIABLES_PROCESSING: return("global variables processing error"                        ); //   4057
      case ERR_GLOBAL_VARIABLE_NOT_FOUND  : return("global variable not found"                                ); //   4058
      case ERR_FUNC_NOT_ALLOWED_IN_TESTER : return("function not allowed in tester"                           ); //   4059
      case ERR_FUNCTION_NOT_CONFIRMED     : return("function not confirmed"                                   ); //   4060
      case ERR_SEND_MAIL_ERROR            : return("send mail error"                                          ); //   4061
      case ERR_STRING_PARAMETER_EXPECTED  : return("string parameter expected"                                ); //   4062
      case ERR_INTEGER_PARAMETER_EXPECTED : return("integer parameter expected"                               ); //   4063
      case ERR_DOUBLE_PARAMETER_EXPECTED  : return("double parameter expected"                                ); //   4064
      case ERR_ARRAY_AS_PARAMETER_EXPECTED: return("array parameter expected"                                 ); //   4065
      case ERS_HISTORY_UPDATE             : return("requested history is updating"                            ); //   4066 requested history is updating      Status
      case ERR_TRADE_ERROR                : return("trade function error"                                     ); //   4067 trade function error
      case ERR_RESOURCE_NOT_FOUND         : return("resource not found"                                       ); //   4068
      case ERR_RESOURCE_NOT_SUPPORTED     : return("resource not supported"                                   ); //   4069
      case ERR_RESOURCE_DUPLICATED        : return("duplicate resource"                                       ); //   4070
      case ERR_INDICATOR_CANNOT_INIT      : return("custom indicator initialization error"                    ); //   4071
      case ERR_INDICATOR_CANNOT_LOAD      : return("custom indicator load error"                              ); //   4072
      case ERR_NO_HISTORY_DATA            : return("no history data"                                          ); //   4073
      case ERR_NO_MEMORY_FOR_HISTORY      : return("no memory for history data"                               ); //   4074
      case ERR_NO_MEMORY_FOR_INDICATOR    : return("not enough memory for indicator calculation"              ); //   4075
      case ERR_END_OF_FILE                : return("end of file"                                              ); //   4099 end of file
      case ERR_FILE_ERROR                 : return("file error"                                               ); //   4100 file error
      case ERR_WRONG_FILE_NAME            : return("wrong file name"                                          ); //   4101
      case ERR_TOO_MANY_OPENED_FILES      : return("too many opened files"                                    ); //   4102
      case ERR_CANNOT_OPEN_FILE           : return("cannot open file"                                         ); //   4103
      case ERR_INCOMPATIBLE_FILEACCESS    : return("incompatible file access"                                 ); //   4104
      case ERR_NO_TICKET_SELECTED         : return("no ticket selected"                                       ); //   4105
      case ERR_SYMBOL_NOT_AVAILABLE       : return("symbol not available"                                     ); //   4106
      case ERR_INVALID_PRICE_PARAM        : return("invalid price parameter for trade function"               ); //   4107
      case ERR_INVALID_TICKET             : return("invalid ticket"                                           ); //   4108
      case ERR_TRADE_NOT_ALLOWED          : return("online trading not enabled"                               ); //   4109
      case ERR_LONGS_NOT_ALLOWED          : return("long trades not enabled"                                  ); //   4110
      case ERR_SHORTS_NOT_ALLOWED         : return("short trades not enabled"                                 ); //   4111
      case ERR_AUTOMATED_TRADING_DISABLED : return("automated trading disabled"                               ); //   4112
      case ERR_OBJECT_ALREADY_EXISTS      : return("object already exists"                                    ); //   4200
      case ERR_UNKNOWN_OBJECT_PROPERTY    : return("unknown object property"                                  ); //   4201
      case ERR_OBJECT_DOES_NOT_EXIST      : return("object doesn't exist"                                     ); //   4202
      case ERR_UNKNOWN_OBJECT_TYPE        : return("unknown object type"                                      ); //   4203
      case ERR_NO_OBJECT_NAME             : return("no object name"                                           ); //   4204
      case ERR_OBJECT_COORDINATES_ERROR   : return("object coordinates error"                                 ); //   4205
      case ERR_NO_SPECIFIED_SUBWINDOW     : return("no specified subwindow"                                   ); //   4206
      case ERR_OBJECT_ERROR               : return("object error"                                             ); //   4207 object error
      case ERR_CHART_PROP_INVALID         : return("unknown chart property"                                   ); //   4210
      case ERR_CHART_NOT_FOUND            : return("chart not found"                                          ); //   4211
      case ERR_CHARTWINDOW_NOT_FOUND      : return("chart subwindow not found"                                ); //   4212
      case ERR_CHARTINDICATOR_NOT_FOUND   : return("chart indicator not found"                                ); //   4213
      case ERR_SYMBOL_SELECT              : return("symbol select error"                                      ); //   4220
      case ERR_NOTIFICATION_SEND_ERROR    : return("error placing notification into sending queue"            ); //   4250
      case ERR_NOTIFICATION_PARAMETER     : return("notification parameter error"                             ); //   4251 empty string passed
      case ERR_NOTIFICATION_SETTINGS      : return("invalid notification settings"                            ); //   4252
      case ERR_NOTIFICATION_TOO_FREQUENT  : return("too frequent notifications"                               ); //   4253
      case ERR_FTP_NOSERVER               : return("FTP server is not specified"                              ); //   4260
      case ERR_FTP_NOLOGIN                : return("FTP login is not specified"                               ); //   4261
      case ERR_FTP_CONNECT_FAILED         : return("FTP connection failed"                                    ); //   4262
      case ERR_FTP_CLOSED                 : return("FTP connection closed"                                    ); //   4263
      case ERR_FTP_CHANGEDIR              : return("FTP path not found on server"                             ); //   4264
      case ERR_FTP_FILE_ERROR             : return("file not found to send to FTP server"                     ); //   4265
      case ERR_FTP_ERROR                  : return("common error during FTP data transmission"                ); //   4266
      case ERR_FILE_TOO_MANY_OPENED       : return("too many opened files"                                    ); //   5001
      case ERR_FILE_WRONG_FILENAME        : return("wrong file name"                                          ); //   5002
      case ERR_FILE_TOO_LONG_FILENAME     : return("too long file name"                                       ); //   5003
      case ERR_FILE_CANNOT_OPEN           : return("cannot open file"                                         ); //   5004
      case ERR_FILE_BUFFER_ALLOC_ERROR    : return("text file buffer allocation error"                        ); //   5005
      case ERR_FILE_CANNOT_DELETE         : return("cannot delete file"                                       ); //   5006
      case ERR_FILE_INVALID_HANDLE        : return("invalid file handle, file already closed or wasn't opened"); //   5007
      case ERR_FILE_UNKNOWN_HANDLE        : return("unknown file handle, handle index is out of handle table" ); //   5008
      case ERR_FILE_NOT_TOWRITE           : return("file must be opened with FILE_WRITE flag"                 ); //   5009
      case ERR_FILE_NOT_TOREAD            : return("file must be opened with FILE_READ flag"                  ); //   5010
      case ERR_FILE_NOT_BIN               : return("file must be opened with FILE_BIN flag"                   ); //   5011
      case ERR_FILE_NOT_TXT               : return("file must be opened with FILE_TXT flag"                   ); //   5012
      case ERR_FILE_NOT_TXTORCSV          : return("file must be opened with FILE_TXT or FILE_CSV flag"       ); //   5013
      case ERR_FILE_NOT_CSV               : return("file must be opened with FILE_CSV flag"                   ); //   5014
      case ERR_FILE_READ_ERROR            : return("file read error"                                          ); //   5015
      case ERR_FILE_WRITE_ERROR           : return("file write error"                                         ); //   5016
      case ERR_FILE_BIN_STRINGSIZE        : return("string size must be specified for binary file"            ); //   5017
      case ERR_FILE_INCOMPATIBLE          : return("incompatible file, for string arrays-TXT, for others-BIN" ); //   5018
      case ERR_FILE_IS_DIRECTORY          : return("file is a directory"                                      ); //   5019
      case ERR_FILE_NOT_FOUND             : return("file not found"                                           ); //   5020
      case ERR_FILE_CANNOT_REWRITE        : return("file cannot be rewritten"                                 ); //   5021
      case ERR_FILE_WRONG_DIRECTORYNAME   : return("wrong directory name"                                     ); //   5022
      case ERR_FILE_DIRECTORY_NOT_EXIST   : return("directory does not exist"                                 ); //   5023
      case ERR_FILE_NOT_DIRECTORY         : return("file is not a directory"                                  ); //   5024
      case ERR_FILE_CANT_DELETE_DIRECTORY : return("cannot delete directory"                                  ); //   5025
      case ERR_FILE_CANT_CLEAN_DIRECTORY  : return("cannot clean directory"                                   ); //   5026
      case ERR_FILE_ARRAYRESIZE_ERROR     : return("array resize error"                                       ); //   5027
      case ERR_FILE_STRINGRESIZE_ERROR    : return("string resize error"                                      ); //   5028
      case ERR_FILE_STRUCT_WITH_OBJECTS   : return("struct contains strings or dynamic arrays"                ); //   5029
      case ERR_WEBREQUEST_INVALID_ADDRESS : return("invalid URL"                                              ); //   5200
      case ERR_WEBREQUEST_CONNECT_FAILED  : return("failed to connect"                                        ); //   5201
      case ERR_WEBREQUEST_TIMEOUT         : return("timeout exceeded"                                         ); //   5202
      case ERR_WEBREQUEST_REQUEST_FAILED  : return("HTTP request failed"                                      ); //   5203

      // user defined errors: 65536-99999 (0x10000-0x1869F)
      case ERR_RUNTIME_ERROR              : return("runtime error"                                            ); //  65536
      case ERR_NOT_IMPLEMENTED            : return("feature not implemented"                                  ); //  65537
      case ERR_INVALID_INPUT_PARAMETER    : return("invalid input parameter value"                            ); //  65538
      case ERR_INVALID_CONFIG_PARAMVALUE  : return("invalid configuration value"                              ); //  65539
      case ERS_TERMINAL_NOT_YET_READY     : return("terminal not yet ready"                                   ); //  65540   Status
      case ERR_INVALID_TIMEZONE_CONFIG    : return("invalid or missing timezone configuration"                ); //  65541
      case ERR_INVALID_MARKET_DATA        : return("invalid market data"                                      ); //  65542
      case ERR_CANCELLED_BY_USER          : return("cancelled by user"                                        ); //  65543
      case ERR_FUNC_NOT_ALLOWED           : return("function not allowed"                                     ); //  65544
      case ERR_INVALID_COMMAND            : return("invalid or unknow command"                                ); //  65545
      case ERR_ILLEGAL_STATE              : return("illegal runtime state"                                    ); //  65546
      case ERS_EXECUTION_STOPPING         : return("program execution stopping"                               ); //  65547   Status
      case ERR_ORDER_CHANGED              : return("order status changed"                                     ); //  65548
      case ERR_HISTORY_INSUFFICIENT       : return("insufficient history for calculation"                     ); //  65549
      case ERR_CONCURRENT_MODIFICATION    : return("concurrent modification"                                  ); //  65550
   }
   return(StringConcatenate("unknown error (", error, ")"));
}


/**
 * Ersetzt in einem String alle Vorkommen eines Substrings durch einen anderen String (kein rekursives Ersetzen).
 *
 * @param  string object  - Ausgangsstring
 * @param  string search  - Suchstring
 * @param  string replace - Ersatzstring
 *
 * @return string - modifizierter String
 */
string StringReplace(string object, string search, string replace) {
   if (!StringLen(object)) return(object);
   if (!StringLen(search)) return(object);
   if (search == replace)  return(object);

   int from=0, found=StringFind(object, search);
   if (found == -1)
      return(object);

   string result = "";

   while (found > -1) {
      result = StringConcatenate(result, StringSubstrFix(object, from, found-from), replace);
      from   = found + StringLen(search);
      found  = StringFind(object, search, from);
   }
   result = StringConcatenate(result, StringSubstr(object, from));

   return(result);
}


/**
 * Ersetzt in einem String alle Vorkommen eines Substrings rekursiv durch einen anderen String. Die Funktion pr�ft nicht,
 * ob durch Such- und Ersatzstring eine Endlosschleife ausgel�st wird.
 *
 * @param  string object  - Ausgangsstring
 * @param  string search  - Suchstring
 * @param  string replace - Ersatzstring
 *
 * @return string - rekursiv modifizierter String
 */
string StringReplace.Recursive(string object, string search, string replace) {
   if (!StringLen(object)) return(object);

   string lastResult="", result=object;

   while (result != lastResult) {
      lastResult = result;
      result     = StringReplace(result, search, replace);
   }
   return(lastResult);
}


/**
 * Bugfix f�r den Fall StringSubstr(string, start, length=0), in dem die MQL-Funktion Unfug zur�ckgibt.
 * Erm�glicht zus�tzlich die Angabe negativer Werte f�r start und length.
 *
 * @param  string object
 * @param  int    start  - wenn negativ, Startindex vom Ende des Strings
 * @param  int    length - wenn negativ, Anzahl der zur�ckzugebenden Zeichen links vom Startindex
 *
 * @return string
 */
string StringSubstrFix(string object, int start, int length=INT_MAX) {
   if (length == 0)
      return("");

   if (start < 0)
      start = Max(0, start + StringLen(object));

   if (length < 0) {
      start += 1 + length;
      length = Abs(length);
   }
   return(StringSubstr(object, start, length));
}


#define SND_ASYNC           0x01       // play asynchronously
#define SND_FILENAME  0x00020000       // parameter is a file name


/**
 * Dropin-Ersatz f�r PlaySound()
 *
 * Spielt ein Soundfile ab, auch wenn dies im aktuellen Kontext des Terminals (z.B. im Tester) nicht unterst�tzt wird.
 * Pr�ft zus�tzlich, ob das angegebene Soundfile existiert.
 *
 * @param  string soundfile
 *
 * @return bool - Erfolgsstatus
 */
bool PlaySoundEx(string soundfile) {
   string filename = StringReplace(soundfile, "/", "\\");
   string fullName = StringConcatenate(TerminalPath(), "\\sounds\\", filename);
   if (!IsFile(fullName)) return(!catch("PlaySoundEx(1)  file not found: \""+ fullName +"\"", ERR_FILE_NOT_FOUND));

   if (IsTesting()) PlaySoundA(fullName, NULL, SND_FILENAME|SND_ASYNC);
   else             PlaySound(filename);

   return(!catch("PlaySoundEx(2)"));
}


/**
 * Dropin-Ersatz f�r Alert()
 *
 * Zeigt eine Nachricht an, auch wenn dies im aktuellen Kontext (z.B. im Tester) nicht unterst�tzt wird.
 *
 * @param  string message
 */
void ForceAlert(string message) {
   Alert(message);                                                   // sorgt daf�r, da� immer die entsprechende Log-Message erzeugt wird

   if (IsTesting()) {
      // Alert() wird still ignoriert (und l�st auch keinen Fehler aus)
      string caption = StringConcatenate("Strategy Tester ", Symbol(), ",", PeriodDescription(Period()));
      message = StringConcatenate(TimeToStr(TimeCurrentEx("ForceAlert(1)"), TIME_FULL), NL, message);
      PlaySoundEx("alert.wav");
      ForceMessageBox(caption, message, MB_ICONERROR|MB_OK);
   }
}


/**
 * Dropin-Ersatz f�r MessageBox()
 *
 * Zeigt eine MessageBox an, auch wenn dies im aktuellen Kontext (z.B. im Tester oder in Indikatoren) nicht unterst�tzt wird.
 *
 * @param  string caption
 * @param  string message
 * @param  int    flags
 *
 * @return int - Tastencode
 */
int ForceMessageBox(string caption, string message, int flags=MB_OK) {
   string prefix = StringConcatenate(Symbol(), ",", PeriodDescription(Period()));

   if (!StringContains(caption, prefix))
      caption = StringConcatenate(prefix, " - ", caption);

   int button;

   if (!IsTesting() && !IsIndicator()) button = MessageBox(message, caption, flags);
   else                                button = MessageBoxA(NULL, message, caption, flags);  // TODO: hWndOwner fixen

   return(button);
}


#define GA_ROOT         2

#define GW_HWNDLAST     1
#define GW_HWNDNEXT     2
#define GW_HWNDPREV     3
#define GW_CHILD        5


/**
 * Dropin-Ersatz f�r und Workaround um die Bugs von WindowHandle(). Kann zus�tzlich bei der Suche ausdr�cklich nur das eigene oder ausdr�cklich nur ein fremdes
 * Fenster ber�cksichtigen.
 *
 * @param string symbol    - Symbol des Charts, dessen Handle ermittelt werden soll.
 *                           Ist dieser Parameter NULL und es wurde kein Timeframe angegeben (kein zweiter Parameter oder NULL), wird das Handle des eigenen
 *                           Chartfensters zur�ckgegeben oder -1, falls das Programm keinen Chart hat (im Tester bei VisualMode=Off).
 *                           Ist dieser oder der zweite Parameter nicht NULL, wird das Handle des ersten passenden fremden Chartfensters zur�ckgegeben (in Z order)
 *                           oder NULL, falls kein solches Chartfenster existiert. Das eigene Chartfenster wird bei dieser Suche nicht ber�cksichtigt.
 * @param int    timeframe - Timeframe des Charts, dessen Handle ermittelt werden soll (default: der aktuelle Timeframe)
 *
 * @return int - Fensterhandle oder NULL, falls kein entsprechendes Chartfenster existiert oder ein Fehler auftrat;
 *               -1, falls das Handle des eigenen Chartfensters gesucht ist und das Programm keinen Chart hat (im Tester bei VisualMode=Off)
 */
int WindowHandleEx(string symbol, int timeframe=NULL) {
   static int static.hWndSelf = 0;                                   // mit Initializer gegen Testerbug: wird in Library bei jedem lib::init() zur�ckgesetzt
   bool self = (symbol=="0" && !timeframe);                          // (string) NULL

   if (self) {
      // (1) Suche nach eigenem Chart
      if (static.hWndSelf != 0)
         return(static.hWndSelf);

      int hChart = ec_hChart(__ExecutionContext);                    // Zuerst wird ein schon im ExcecutionContext gespeichertes eigenes ChartHandle abgefragt.
      if (hChart > 0) {                                              // (vor allem f�r Libraries)
         static.hWndSelf = hChart;
         return(static.hWndSelf);
      }

      if (IsTesting()) {                                             // Im Tester bei VisualMode=Off gibt es keinen Chart: R�ckgabewert -1
         if (IsLibrary()) bool visualMode = IsVisualModeFix();
         else                  visualMode = IsVisualMode();
         if (!visualMode) {
            static.hWndSelf = -1;
            return(static.hWndSelf);
         }
      }
      // Hier sind wir entweder: au�erhalb des Testers
      // oder                    im Tester bei VisualMode=On


      hChart    = WindowHandle(Symbol(), NULL);
      int error = GetLastError();
      if (IsError(error)) return(!catch("WindowHandleEx(1)", error));

      if (!hChart) {
         // (1.1) Suche nach eigenem Chart in Indikatoren: WindowHandle() ist NULL
         if (IsIndicator()) {
            // Ein Indikator im SuperContext �bernimmt das ChartHandle von dort.
            if (IsSuperContext()) {
               if (__lpSuperContext>=0 && __lpSuperContext<MIN_VALID_POINTER) return(!catch("WindowHandleEx(2)  invalid input parameter __lpSuperContext = 0x"+ IntToHexStr(__lpSuperContext) +" (not a valid pointer)", ERR_INVALID_POINTER));
               int superContext[EXECUTION_CONTEXT.intSize];
               CopyMemory(GetIntsAddress(superContext), __lpSuperContext, EXECUTION_CONTEXT.size);    // SuperContext selbst kopieren, da der Context des laufenden Programms
               static.hWndSelf = ec_hChart(superContext);                                             // u.U. noch nicht endg�ltig initialisiert ist.
               ArrayResize(superContext, 0);
               return(static.hWndSelf);
            }

            // Bis Build 509+ ??? gibt WindowHandle() bei Terminal-Start in init() und in start() 0 zur�ck, solange das Terminal nicht endg�ltig initialisiert ist.
            // Existiert ein Chartfenster ohne gesetzten Titel und ist dies das letzte in Z-Order, ist dieses Fenster das gesuchte Fenster.
            // Existiert kein solches Fenster und l�uft der Indikator im UI-Thread und in init(), wurde er �ber das Template "Tester.tpl" in einem Test mit
            // VisualMode=Off geladen und es gibt kein Chartfenster.

            int hWndMain = GetApplicationWindow();               if (!hWndMain) return(NULL);
            int hWndMdi  = GetDlgItem(hWndMain, IDC_MDI_CLIENT); if (!hWndMdi)  return(!catch("WindowHandleEx(3)  MDIClient window not found (hWndMain = 0x"+ IntToHexStr(hWndMain) +")", ERR_RUNTIME_ERROR));

            bool noEmptyChild = false;
            string title, sError;

            int hWndChild = GetWindow(hWndMdi, GW_CHILD);               // das erste Child in Z order
            if (!hWndChild) {
               noEmptyChild = true; sError = "WindowHandleEx(4)  MDIClient window has no child windows";
            }
            else {
               int hWndLast = GetWindow(hWndChild, GW_HWNDLAST);        // das letzte Child in Z order
               title = GetWindowText(hWndLast);
               if (StringLen(title) > 0) {
                  noEmptyChild = true; sError = "WindowHandleEx(5)  last child window of MDIClient window doesn't have an empty title \""+ title +"\"";
               }
            }

            if (noEmptyChild) {
               if (__WHEREAMI__==RF_INIT) /*&&*/ if (IsUIThread()) {
                  static.hWndSelf = -1;                                 // R�ckgabewert -1
                  return(static.hWndSelf);
               }                                                        // vorhandene ChildWindows im Debugger ausgeben
               return(!catch(sError +" in context Indicator::"+ RootFunctionName(__WHEREAMI__) +"()", _int(ERR_RUNTIME_ERROR, EnumChildWindows(hWndMdi))));
            }
            int hChartWindow = hWndLast;
         }

         // (1.2) Suche nach eigenem Chart in Scripten: WindowHandle() ist NULL
         else if (IsScript()) {
            // Bis Build 509+ ??? gibt WindowHandle() bei Terminal-Start in init() und in start() 0 zur�ck, solange das Terminal nicht endg�ltig initialisiert ist.
            // Scripte werden in diesem Fall �ber die Startkonfiguration ausgef�hrt und laufen im ersten passenden Chart in absoluter Reihenfolge (CtrlID), nicht in Z-Order.
            // Das erste passende Chartfenster in absoluter Reihenfolge ist das gesuchte Fenster.

            hWndMain  = GetApplicationWindow();               if (!hWndMain) return(NULL);
            hWndMdi   = GetDlgItem(hWndMain, IDC_MDI_CLIENT); if (!hWndMdi)  return(!catch("WindowHandleEx(6)  MDIClient window not found (hWndMain = 0x"+ IntToHexStr(hWndMain) +")", ERR_RUNTIME_ERROR));
            hWndChild = GetWindow(hWndMdi, GW_CHILD);                   // das erste Child in Z order
            if (!hWndChild) return(!catch("WindowHandleEx(7)  MDIClient window has no child windows in context Script::"+ RootFunctionName(__WHEREAMI__) +"()", ERR_RUNTIME_ERROR));

            if (symbol == "0") symbol = Symbol();                       // (string) NULL
            if (!timeframe) timeframe = Period();
            string chartDescription = ChartDescription(symbol, timeframe);
            int id = INT_MAX;

            while (hWndChild != NULL) {
               title = GetWindowText(hWndChild); if (StringEndsWith(title, " (offline)")) title = StringLeft(title, -10);
               if (title == chartDescription) {                         // alle Childwindows durchlaufen und das erste passende in absoluter Reihenfolge finden
                  id = Min(id, GetDlgCtrlID(hWndChild));
                  if (!id) return(!catch("WindowHandleEx(8)  MDIClient child window 0x"+ IntToHexStr(hWndChild) +" has no control id", _int(ERR_RUNTIME_ERROR, EnumChildWindows(hWndMdi))));
               }
               hWndChild = GetWindow(hWndChild, GW_HWNDNEXT);           // das n�chste Child in Z order
            }
            if (id == INT_MAX) return(!catch("WindowHandleEx(9)  no matching MDIClient child window found for \""+ chartDescription +"\"", _int(ERR_RUNTIME_ERROR, EnumChildWindows(hWndMdi))));
            hChartWindow = GetDlgItem(hWndMdi, id);
         }

         // (1.3) Suche nach eigenem Chart in Experts: WindowHandle() ist NULL
         else {
            return(!catch("WindowHandleEx(10)->WindowHandle() => 0 in context Expert::"+ RootFunctionName(__WHEREAMI__) +"()", ERR_RUNTIME_ERROR));
         }

         // (1.4) Das so gefundene Chartfenster hat selbst wieder genau ein Child (AfxFrameOrView), welches das gesuchte MetaTrader-Handle() ist.
         hChart = GetWindow(hChartWindow, GW_CHILD);
         if (!hChart)
            return(!catch("WindowHandleEx(11)  no MetaTrader chart window inside of last MDIClient child window 0x"+ IntToHexStr(hChartWindow) +" found", _int(ERR_RUNTIME_ERROR, EnumChildWindows(hWndMdi))));
      }
      static.hWndSelf = hChart;
      return(static.hWndSelf);
   }


   if (symbol == "0") symbol = Symbol();                             // (string) NULL
   if (!timeframe) timeframe = Period();
   chartDescription = ChartDescription(symbol, timeframe);


   // (2) eingebaute Suche nach fremdem Chart                        // TODO: WindowHandle() wird das Handle des eigenen Charts nicht �berspringen, wenn dieser auf die Parameter pa�t
   hChart = WindowHandle(symbol, timeframe);
   error  = GetLastError();
   if (!error)                                  return(hChart);
   if (error != ERR_FUNC_NOT_ALLOWED_IN_TESTER) return(!catch("WindowHandleEx(12)", error));

                                                                     // TODO: das Handle des eigenen Charts �berspringen, wenn dieser auf die Parameter pa�t
   // (3) selbstdefinierte Suche nach fremdem Chart (dem ersten passenden in Z order)
   hWndMain  = GetApplicationWindow();               if (!hWndMain) return(NULL);
   hWndMdi   = GetDlgItem(hWndMain, IDC_MDI_CLIENT); if (!hWndMdi)  return(!catch("WindowHandleEx(13)  MDIClient window not found (hWndMain="+ IntToHexStr(hWndMain) +")", ERR_RUNTIME_ERROR));
   hWndChild = GetWindow(hWndMdi, GW_CHILD);                         // das erste Child in Z order

   while (hWndChild != NULL) {
      title = GetWindowText(hWndChild); if (StringEndsWith(title, " (offline)")) title = StringLeft(title, -10);
      if (title == chartDescription) {                               // Das Child hat selbst wieder genau ein Child (AfxFrameOrView), welches das gesuchte ChartWindow
         hChart = GetWindow(hWndChild, GW_CHILD);                    // mit dem MetaTrader-WindowHandle() ist.
         if (!hChart) return(!catch("WindowHandleEx(14)  no MetaTrader chart window inside of MDIClient window 0x"+ IntToHexStr(hWndChild) +" found", ERR_RUNTIME_ERROR));
         break;
      }
      hWndChild = GetWindow(hWndChild, GW_HWNDNEXT);                 // das n�chste Child in Z order
   }
   return(hChart);
}


/**
 * Gibt die Symbolbeschreibung eines Chartfensters zur�ck.
 *
 * @param  string symbol
 * @param  int    timeframe
 *
 * @return string - Beschreibung oder Leerstring, falls ein Fehler auftrat
 */
string ChartDescription(string symbol, int timeframe) {
   if (!StringLen(symbol)) return(_EMPTY_STR(catch("ChartDescription(1)  invalid parameter symbol = "+ DoubleQuoteStr(symbol), ERR_INVALID_PARAMETER)));

   switch (timeframe) {
      case PERIOD_M1 : return(StringConcatenate(symbol, ",M1"     ));   // 1 minute
      case PERIOD_M5 : return(StringConcatenate(symbol, ",M5"     ));   // 5 minutes
      case PERIOD_M15: return(StringConcatenate(symbol, ",M15"    ));   // 15 minutes
      case PERIOD_M30: return(StringConcatenate(symbol, ",M30"    ));   // 30 minutes
      case PERIOD_H1 : return(StringConcatenate(symbol, ",H1"     ));   // 1 hour
      case PERIOD_H4 : return(StringConcatenate(symbol, ",H4"     ));   // 4 hour
      case PERIOD_D1 : return(StringConcatenate(symbol, ",Daily"  ));   // 1 day
      case PERIOD_W1 : return(StringConcatenate(symbol, ",Weekly" ));   // 1 week
      case PERIOD_MN1: return(StringConcatenate(symbol, ",Monthly"));   // 1 month
   }
   return(_EMPTY_STR(catch("ChartDescription(2)  invalid parameter timeframe = "+ timeframe, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt den Klassennamen des angegebenen Fensters zur�ck.
 *
 * @param  int hWnd - Handle des Fensters
 *
 * @return string - Klassenname oder Leerstring, falls ein Fehler auftrat
 */
string GetClassName(int hWnd) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   int chars = GetClassNameA(hWnd, buffer[0], bufferSize);

   while (chars >= bufferSize-1) {                                   // GetClassNameA() gibt beim Abschneiden zu langer Klassennamen {bufferSize-1} zur�ck.
      bufferSize <<= 1;
      InitializeStringBuffer(buffer, bufferSize);
      chars = GetClassNameA(hWnd, buffer[0], bufferSize);
   }

   if (!chars)
      return(_EMPTY_STR(catch("GetClassName()->user32::GetClassNameA()", ERR_WIN32_ERROR)));

   return(buffer[0]);
}


/**
 * Ob das aktuelle Programm im Tester l�uft und der VisualMode-Status aktiv ist.
 *
 * Bugfix f�r IsVisualMode(). IsVisualMode() wird in Libraries zwischen aufeinanderfolgenden Tests nicht zur�ckgesetzt und gibt bis zur
 * Neuinitialisierung der Library den Status des ersten Tests zur�ck.
 *
 * @return bool
 */
bool IsVisualModeFix() {
   return(ec_TestFlags(__ExecutionContext) & TF_VISUAL_TEST == TF_VISUAL_TEST);
}


/**
 * Ob der angegebene Wert einen Fehler darstellt.
 *
 * @param  int value
 *
 * @return bool
 */
bool IsError(int value) {
   return(value != NO_ERROR);
}


/**
 * Ob der interne Fehler-Code des aktuellen Moduls gesetzt ist.
 *
 * @return bool
 */
bool IsLastError() {
   return(last_error != NO_ERROR);
}


/**
 * Setzt den internen Fehlercode des aktuellen Moduls zur�ck.
 *
 * @return int - der vorm Zur�cksetzen gesetzte Fehlercode
 */
int ResetLastError() {
   int error = last_error;
   SetLastError(NO_ERROR);
   return(error);
}


/**
 * Pr�ft, ob ein Event aufgetreten ist und ruft ggf. dessen Eventhandler auf. Erm�glicht die Angabe weiterer
 * eventspezifischer Pr�fungskriterien.
 *
 * @param  int event    - einzelnes Event-Flag
 * @param  int criteria - weitere eventspezifische Pr�fungskriterien (default: keine)
 *
 * @return int - 1, wenn ein Event aufgetreten ist und erfolgreich verarbeitet wurde;
 *               0  andererseits
 */
int HandleEvent(int event, int criteria=NULL) {
   bool   status;
   int    iResults[]; ArrayResize(iResults, 0);
   string sResults[]; ArrayResize(sResults, 0);

   switch (event) {
      case EVENT_BAR_OPEN      : if (EventListener.BarOpen.MTF  (iResults, criteria)) status = onBarOpen.MTF  (iResults); break;
      case EVENT_ACCOUNT_CHANGE: if (EventListener.AccountChange(iResults, criteria)) status = onAccountChange(iResults); break;
      case EVENT_CHART_CMD     : if (EventListener.ChartCommand (sResults, criteria)) status = onChartCommand (sResults); break;

      default:
         return(!catch("HandleEvent(1)  unknown event = "+ event, ERR_INVALID_PARAMETER));
   }
   return(status);                                                   // (int) bool
}


/**
 * Ob das angegebene Ticket existiert und erreichbar ist.
 *
 * @param  int ticket - Ticket-Nr.
 *
 * @return bool
 */
bool IsTicket(int ticket) {
   OrderPush("IsTicket(1)");

   bool result = OrderSelect(ticket, SELECT_BY_TICKET);

   GetLastError();
   OrderPop("IsTicket(2)");

   return(result);
}


/**
 * Selektiert ein Ticket.
 *
 * @param  int    ticket                  - Ticket-Nr.
 * @param  string location                - Bezeichner f�r evt. Fehlermeldung
 * @param  bool   storeSelection          - ob die aktuelle Selektion gespeichert werden soll (default: nein)
 * @param  bool   onErrorRestoreSelection - ob im Fehlerfall die letzte Selektion wiederhergestellt werden soll
 *                                          (default: bei storeSelection=TRUE ja; bei storeSelection=FALSE nein)
 * @return bool - Erfolgsstatus
 */
bool SelectTicket(int ticket, string location, bool storeSelection=false, bool onErrorRestoreSelection=false) {
   storeSelection          = storeSelection!=0;
   onErrorRestoreSelection = onErrorRestoreSelection!=0;

   if (storeSelection) {
      OrderPush(location);
      onErrorRestoreSelection = true;
   }

   if (OrderSelect(ticket, SELECT_BY_TICKET))
      return(true);                             // Success

   if (onErrorRestoreSelection)                 // Fehler
      OrderPop(location);

   int error = GetLastError();
   return(!catch(location +"->SelectTicket()   ticket="+ ticket, ifInt(!error, ERR_INVALID_TICKET, error)));
}


int stack.orderSelections[];


/**
 * Schiebt den aktuellen Orderkontext auf den Kontextstack (f�gt ihn ans Ende an).
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return int - Ticket des aktuellen Kontexts oder 0, wenn keine Order selektiert ist oder ein Fehler auftrat
 */
int OrderPush(string location) {
   int error = GetLastError();
   if (IsError(error))
      return(_NULL(catch(location +"->OrderPush(1)", error)));

   int ticket = OrderTicket();

   error = GetLastError();
   if (IsError(error)) /*&&*/ if (error != ERR_NO_TICKET_SELECTED)
      return(_NULL(catch(location +"->OrderPush(2)", error)));

   ArrayPushInt(stack.orderSelections, ticket);
   return(ticket);
}


/**
 * Entfernt den letzten Orderkontext vom Ende des Kontextstacks und restauriert ihn.
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return bool - Erfolgsstatus
 */
bool OrderPop(string location) {
   int ticket = ArrayPopInt(stack.orderSelections);

   if (ticket > 0)
      return(SelectTicket(ticket, StringConcatenate(location, "->OrderPop()")));

   OrderSelect(0, SELECT_BY_TICKET);
   return(true);
}


/**
 * Wartet darauf, da� das angegebene Ticket im OpenOrders- bzw. History-Pool des Accounts erscheint.
 *
 * @param  int  ticket    - Orderticket
 * @param  bool orderKeep - ob der aktuelle Orderkontext bewahrt werden soll (default: ja)
 *                          wenn FALSE, ist das angegebene Ticket nach R�ckkehr selektiert
 *
 * @return bool - Erfolgsstatus
 */
bool WaitForTicket(int ticket, bool orderKeep=true) {
   orderKeep = orderKeep!=0;

   if (ticket <= 0)
      return(!catch("WaitForTicket(1)  illegal parameter ticket = "+ ticket, ERR_INVALID_PARAMETER));

   if (orderKeep) {
      if (!OrderPush("WaitForTicket(2)"))
         return(!last_error);
   }

   int i, delay=100;                                                 // je 0.1 Sekunden warten

   while (!OrderSelect(ticket, SELECT_BY_TICKET)) {
      if (IsTesting())       warn(StringConcatenate("WaitForTicket(3)  #", ticket, " not yet accessible"));
      else if (i && !(i%10)) warn(StringConcatenate("WaitForTicket(4)  #", ticket, " not yet accessible after ", DoubleToStr(i*delay/1000., 1), " s"));
      Sleep(delay);
      i++;
   }

   if (orderKeep) {
      if (!OrderPop("WaitForTicket(5)"))
         return(false);
   }

   return(true);
}


/**
 * Gibt den PipValue des aktuellen Symbols f�r die angegebene Lotsize zur�ck.
 *
 * @param  double lots           - Lotsize (default: 1 lot)
 * @param  bool   suppressErrors - ob Laufzeitfehler unterdr�ckt werden sollen (default: nein)
 *
 * @return double - PipValue oder 0, falls ein Fehler auftrat
 */
double PipValue(double lots=1.0, bool suppressErrors=false) {
   suppressErrors = suppressErrors!=0;

   if (!TickSize) {
      TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);                   // schl�gt fehl, wenn kein Tick vorhanden ist
      int error = GetLastError();                                       // - Symbol (noch) nicht subscribed (Start, Account-/Templatewechsel), kann noch "auftauchen"
      if (error != NO_ERROR) {                                          // - ERR_SYMBOL_NOT_AVAILABLE: synthetisches Symbol im Offline-Chart
         if (!suppressErrors) catch("PipValue(1)", error);
         return(0);
      }
      if (!TickSize) {
         if (!suppressErrors) catch("PipValue(2)  illegal TickSize = 0", ERR_INVALID_MARKET_DATA);
         return(0);
      }
   }

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);             // TODO: wenn QuoteCurrency == AccountCurrency, ist dies nur ein einziges Mal notwendig
   error = GetLastError();
   if (!error) {
      if (!tickValue) {
         if (!suppressErrors) catch("PipValue(3)  illegal TickValue = 0", ERR_INVALID_MARKET_DATA);
         return(0);
      }
      return(Pip/TickSize * tickValue * lots);
   }

   if (!suppressErrors) catch("PipValue(4)", error);
   return(0);
}


/**
 * Gibt den PipValue eines Symbol f�r die angegebene Lotsize zur�ck. Das Symbol mu� nicht das aktuelle Symbol sein.
 *
 * @param  string symbol         - Symbol
 * @param  double lots           - Lotsize (default: 1 lot)
 * @param  bool   suppressErrors - ob Laufzeitfehler unterdr�ckt werden sollen (default: nein)
 *
 * @return double - PipValue oder 0, falls ein Fehler auftrat
 */
double PipValueEx(string symbol, double lots=1.0, bool suppressErrors=false) {
   suppressErrors = suppressErrors!=0;
   if (symbol == Symbol())
      return(PipValue(lots, suppressErrors));

   double tickSize = MarketInfo(symbol, MODE_TICKSIZE);              // schl�gt fehl, wenn kein Tick vorhanden ist
   int error = GetLastError();                                       // - Symbol (noch) nicht subscribed (Start, Account-/Templatewechsel), kann noch "auftauchen"
   if (error != NO_ERROR) {                                          // - ERR_SYMBOL_NOT_AVAILABLE: synthetisches Symbol im Offline-Chart
      if (!suppressErrors) catch("PipValueEx(1)", error);
      return(0);
   }
   if (!tickSize) {
      if (!suppressErrors) catch("PipValueEx(2)  illegal TickSize = 0", ERR_INVALID_MARKET_DATA);
      return(0);
   }

   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);            // TODO: wenn QuoteCurrency == AccountCurrency, ist dies nur ein einziges Mal notwendig
   error = GetLastError();
   if (error != NO_ERROR) {
      if (!suppressErrors) catch("PipValueEx(3)", error);
      return(0);
   }
   if (!tickValue) {
      if (!suppressErrors) catch("PipValueEx(4)  illegal TickValue = 0", ERR_INVALID_MARKET_DATA);
      return(0);
   }

   int digits = MarketInfo(symbol, MODE_DIGITS);                     // TODO: !!! digits ist u.U. falsch gesetzt !!!
   error = GetLastError();
   if (error != NO_ERROR) {
      if (!suppressErrors) catch("PipValueEx(5)", error);
      return(0);
   }

   int    pipDigits = digits & (~1);
   double pipSize   = NormalizeDouble(1/MathPow(10, pipDigits), pipDigits);

   return(pipSize/tickSize * tickValue * lots);
}


/**
 * Ob das Logging f�r das aktuelle Programm aktiviert ist. Standardm��ig ist das Logging au�erhalb des Testers ON und innerhalb des Testers OFF.
 *
 * @return bool
 */
bool IsLogging() {
   string name = __NAME__;
   if (IsLibrary()) {
      if (!StringLen(__NAME__))
         return(!catch("IsLogging(1)  library not initialized", ERR_RUNTIME_ERROR));
      name = StringSubstr(__NAME__, 0, StringFind(__NAME__, ":")) ;
   }

   if (!This.IsTesting()) return(GetConfigBool("Logging", name,     true ));      // Online:    default=ON
   else                   return(GetConfigBool("Logging", "Tester", false));      // im Tester: default=OFF
}


/**
 * Inlined conditional Boolean-Statement.
 *
 * @param  bool condition
 * @param  bool thenValue
 * @param  bool elseValue
 *
 * @return bool
 */
bool ifBool(bool condition, bool thenValue, bool elseValue) {
   if (condition != 0)
      return(thenValue != 0);
   return(elseValue != 0);
}


/**
 * Inlined conditional Integer-Statement.
 *
 * @param  bool condition
 * @param  int  thenValue
 * @param  int  elseValue
 *
 * @return int
 */
int ifInt(bool condition, int thenValue, int elseValue) {
   if (condition != 0)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional Double-Statement.
 *
 * @param  bool   condition
 * @param  double thenValue
 * @param  double elseValue
 *
 * @return double
 */
double ifDouble(bool condition, double thenValue, double elseValue) {
   if (condition != 0)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional String-Statement.
 *
 * @param  bool   condition
 * @param  string thenValue
 * @param  string elseValue
 *
 * @return string
 */
string ifString(bool condition, string thenValue, string elseValue) {
   if (condition != 0)
      return(thenValue);
   return(elseValue);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Then".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool LT(double double1, double double2, int digits=8) {
   if (EQ(double1, double2, digits))
      return(false);
   return(double1 < double2);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Or-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool LE(double double1, double double2, int digits=8) {
   if (double1 < double2)
      return(true);
   return(EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf Gleichheit "Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool EQ(double double1, double double2, int digits=8) {
   if (digits < 0 || digits > 8)
      return(!catch("EQ()  illegal parameter digits = "+ digits, ERR_INVALID_PARAMETER));

   double diff = NormalizeDouble(double1, digits) - NormalizeDouble(double2, digits);
   if (diff < 0)
      diff = -diff;
   return(diff < 0.000000000000001);

   /*
   switch (digits) {
      case  0: return(diff <= 0                 );
      case  1: return(diff <= 0.1               );
      case  2: return(diff <= 0.01              );
      case  3: return(diff <= 0.001             );
      case  4: return(diff <= 0.0001            );
      case  5: return(diff <= 0.00001           );
      case  6: return(diff <= 0.000001          );
      case  7: return(diff <= 0.0000001         );
      case  8: return(diff <= 0.00000001        );
      case  9: return(diff <= 0.000000001       );
      case 10: return(diff <= 0.0000000001      );
      case 11: return(diff <= 0.00000000001     );
      case 12: return(diff <= 0.000000000001    );
      case 13: return(diff <= 0.0000000000001   );
      case 14: return(diff <= 0.00000000000001  );
      case 15: return(diff <= 0.000000000000001 );
      case 16: return(diff <= 0.0000000000000001);
   }
   return(!catch("EQ()  illegal parameter digits = "+ digits, ERR_INVALID_PARAMETER));
   */
}


/**
 * Korrekter Vergleich zweier Doubles auf Ungleichheit "Not-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool NE(double double1, double double2, int digits=8) {
   return(!EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Or-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool GE(double double1, double double2, int digits=8) {
   if (double1 > double2)
      return(true);
   return(EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Then".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool GT(double double1, double double2, int digits=8) {
   if (EQ(double1, double2, digits))
      return(false);
   return(double1 > double2);
}


/**
 * Ob der Wert eines Doubles NaN (Not-a-Number) ist.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsNaN(double value) {
   // Bug Builds < 509: der Ausdruck (NaN==NaN) ist dort f�lschlicherweise TRUE
   string s = value;
   return(s == "-1.#IND0000");
}


/**
 * Ob der Wert eines Doubles positiv oder negativ unendlich (Infinity) ist.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsInfinity(double value) {
   if (!value)                               // 0
      return(false);
   return(value+value == value);             // 1.#INF oder -1.#INF
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als boolean TRUE zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return bool - TRUE
 */
bool _true(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(true);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als boolean FALSE zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return bool - FALSE
 */
bool _false(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(false);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als NULL = 0 (int) zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - NULL
 */
int _NULL(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NULL);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den Fehlerstatus NO_ERROR zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden. Ist funktional identisch zu _NULL().
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - NO_ERROR
 */
int _NO_ERROR(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NO_ERROR);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den letzten Fehlercode zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - last_error
 */
int _last_error(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(last_error);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante EMPTY (0xFFFFFFFF = -1) zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - EMPTY
 */
int _EMPTY(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(EMPTY);
}


/**
 * Ob der angegebene Wert die Konstante EMPTY darstellt.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsEmpty(double value) {
   return(value == EMPTY);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante EMPTY_VALUE (0x7FFFFFFF = 2147483647 = INT_MAX) zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - EMPTY_VALUE
 */
int _EMPTY_VALUE(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(EMPTY_VALUE);
}


/**
 * Ob der angegebene Wert die Konstante EMPTY_VALUE darstellt.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsEmptyValue(double value) {
   return(value == EMPTY_VALUE);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als einen Leerstring ("") zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return string - Leerstring
 */
string _EMPTY_STR(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return("");
}


/**
 * Ob der angegebene Wert einen Leerstring darstellt (keinen NULL-Pointer).
 *
 * @param  string value
 *
 * @return bool
 */
bool IsEmptyString(string value) {
   if (StringIsNull(value))
      return(false);
   return(value == "");
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante NaT (Not-A-Time: 0x80000000 = -2147483648 = INT_MIN = D'1901-12-13 20:45:52') zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return datetime - NaT (Not-A-Time)
 */
datetime _NaT(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NaT);
}


/**
 * Ob der angegebene Wert die Konstante NaT (Not-A-Time) darstellt.
 *
 * @param  datetime value
 *
 * @return bool
 */
bool IsNaT(datetime value) {
   return(value == NaT);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  bool param1 - Boolean
 * @param  ...         - beliebige weitere Parameter (werden ignoriert)
 *
 * @return bool - der erste Parameter
 */
bool _bool(bool param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1 != 0);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  int param1 - Integer
 * @param  ...        - beliebige weitere Parameter (werden ignoriert)
 *
 * @return int - der erste Parameter
 */
int _int(int param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  double param1 - Double
 * @param  ...           - beliebige weitere Parameter (werden ignoriert)
 *
 * @return double - der erste Parameter
 */
double _double(double param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  string param1 - String
 * @param  ...           - beliebige weitere Parameter (werden ignoriert)
 *
 * @return string - der erste Parameter
 */
string _string(string param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Integer-Version von MathMin()
 *
 * Ermittelt die kleinere mehrerer Ganzzahlen.
 *
 * @param  int value1
 * @param  int value2
 * @param      ...    - Insgesamt bis zu 8 Werte mit INT_MAX als Argumentbegrenzer. Kann einer der Werte selbst INT_MAX sein,
 *                      mu� er innerhalb der ersten drei Argumente aufgef�hrt sein.
 * @return int
 */
int Min(int value1, int value2, int value3=INT_MAX, int value4=INT_MAX, int value5=INT_MAX, int value6=INT_MAX, int value7=INT_MAX, int value8=INT_MAX) {
   int result = value1;
   while (true) {
      if (value2 < result) result = value2;
      if (value3 < result) result = value3; if (value3 == INT_MAX) break;
      if (value4 < result) result = value4; if (value4 == INT_MAX) break;
      if (value5 < result) result = value5; if (value5 == INT_MAX) break;
      if (value6 < result) result = value6; if (value6 == INT_MAX) break;
      if (value7 < result) result = value7; if (value7 == INT_MAX) break;
      if (value8 < result) result = value8; if (value8 == INT_MAX) break;
   }
   return(result);
}


/**
 * Integer-Version von MathMax()
 *
 * Ermittelt die gr��ere mehrerer Ganzzahlen.
 *
 * @param  int value1
 * @param  int value2
 * @param      ...    - Insgesamt bis zu 8 Werte mit INT_MIN als Argumentbegrenzer. Kann einer der Werte selbst INT_MIN sein,
 *                      mu� er innerhalb der ersten drei Argumente aufgef�hrt sein.
 * @return int
 */
int Max(int value1, int value2, int value3=INT_MIN, int value4=INT_MIN, int value5=INT_MIN, int value6=INT_MIN, int value7=INT_MIN, int value8=INT_MIN) {
   int result = value1;
   while (true) {
      if (value2 > result) result = value2;
      if (value3 > result) result = value3; if (value3 == INT_MIN) break;
      if (value4 > result) result = value4; if (value4 == INT_MIN) break;
      if (value5 > result) result = value5; if (value5 == INT_MIN) break;
      if (value6 > result) result = value6; if (value6 == INT_MIN) break;
      if (value7 > result) result = value7; if (value7 == INT_MIN) break;
      if (value8 > result) result = value8; if (value8 == INT_MIN) break;
   }
   return(result);
}


/**
 * Integer-Version von MathAbs()
 *
 * Ermittelt den Absolutwert einer Ganzzahl.
 *
 * @param  int  value
 *
 * @return int
 */
int Abs(int value) {
   if (value < 0)
      return(-value);
   return(value);
}


/**
 * Gibt das Vorzeichen einer Zahl zur�ck.
 *
 * @param  double number - Zahl
 *
 * @return int - Vorzeichen (+1, 0, -1)
 */
int Sign(double number) {
   if (GT(number, 0)) return( 1);
   if (LT(number, 0)) return(-1);
   return(0);
}


/**
 * Integer-Version von MathRound()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Round(double value) {
   return(MathRound(value));
}


/**
 * Erweiterte Version von MathRound(), rundet auf die angegebene Anzahl von positiven oder negativen Dezimalstellen.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundEx(double number, int decimals=0) {
   if (decimals > 0) return(NormalizeDouble(number, decimals));
   if (!decimals)    return(      MathRound(number));

   // decimals < 0
   double factor = MathPow(10, decimals);                            // -1:  1234.5678 => 1230
          number = MathRound(number * factor) / factor;              // -2:  1234.5678 => 1200
          number = MathRound(number);                                // -3:  1234.5678 => 1000
   return(number);
}


/**
 * Erweiterte Version von MathFloor(), rundet mit der angegebenen Anzahl von positiven oder negativen Dezimalstellen ab.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundFloor(double number, int decimals=0) {
   if (decimals > 0) {
      double factor = MathPow(10, decimals);                         // +1:  1234.5678 => 1234.5
             number = MathFloor(number * factor) / factor;           // +2:  1234.5678 => 1234.56
             number = NormalizeDouble(number, decimals);             // +3:  1234.5678 => 1234.567
      return(number);
   }

   if (decimals == 0)
      return(MathFloor(number));

   // decimals < 0
   factor = MathPow(10, decimals);                                   // -1:  1234.5678 => 1230
   number = MathFloor(number * factor) / factor;                     // -2:  1234.5678 => 1200
   number = MathRound(number);                                       // -3:  1234.5678 => 1000
   return(number);
}


/**
 * Erweiterte Version von MathCeil(), rundet mit der angegebenen Anzahl von positiven oder negativen Dezimalstellen auf.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundCeil(double number, int decimals=0) {
   if (decimals > 0) {
      double factor = MathPow(10, decimals);                         // +1:  1234.5678 => 1234.6
             number = MathCeil(number * factor) / factor;            // +2:  1234.5678 => 1234.57
             number = NormalizeDouble(number, decimals);             // +3:  1234.5678 => 1234.568
      return(number);
   }

   if (decimals == 0)
      return(MathCeil(number));

   // decimals < 0
   factor = MathPow(10, decimals);                                   // -1:  1234.5678 => 1240
   number = MathCeil(number * factor) / factor;                      // -2:  1234.5678 => 1300
   number = MathRound(number);                                       // -3:  1234.5678 => 2000
   return(number);
}


/**
 * Integer-Version von MathFloor()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Floor(double value) {
   return(MathFloor(value));
}


/**
 * Integer-Version von MathCeil()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Ceil(double value) {
   return(MathCeil(value));
}


/**
 * Dividiert zwei Doubles und f�ngt dabei eine Division durch 0 ab.
 *
 * @param  double a      - Divident
 * @param  double b      - Divisor
 * @param  double onZero - Ergebnis f�r den Fall, da� der Divisor 0 ist (default: 0)
 *
 * @return double
 */
double MathDiv(double a, double b, double onZero=0) {
   if (!b)
      return(onZero);
   return(a/b);
}


/**
 * Gibt den Divisionsrest zweier Doubles zur�ck (fehlerbereinigter Ersatz f�r MathMod()).
 *
 * @param  double a
 * @param  double b
 *
 * @return double - Divisionsrest
 */
double MathModFix(double a, double b) {
   double remainder = MathMod(a, b);
   if      (EQ(remainder, 0)) remainder = 0;                         // 0 normalisieren
   else if (EQ(remainder, b)) remainder = 0;
   return(remainder);
}


/**
 * Integer-Version von MathDiv(). Dividiert zwei Integers und f�ngt dabei eine Division durch 0 ab.
 *
 * @param  int a      - Divident
 * @param  int b      - Divisor
 * @param  int onZero - Ergebnis f�r den Fall, da� der Divisor 0 ist (default: 0)
 *
 * @return int
 */
int Div(int a, int b, int onZero=0) {
   if (!b)
      return(onZero);
   return(a/b);
}


/**
 * Gibt die Anzahl der Dezimal- bzw. Nachkommastellen eines Zahlenwertes zur�ck.
 *
 * @param  double number
 *
 * @return int - Anzahl der Nachkommastellen, h�chstens jedoch 8
 */
int CountDecimals(double number) {
   string str = number;
   int dot    = StringFind(str, ".");

   for (int i=StringLen(str)-1; i > dot; i--) {
      if (StringGetChar(str, i) != '0')
         break;
   }
   return(i - dot);
}


/**
 * Gibt einen linken Teilstring eines Strings zur�ck.
 *
 * Ist N positiv, gibt StringLeft() die N am meisten links stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringLeft("ABCDEFG",  2)  =>  "AB"
 *
 * Ist N negativ, gibt StringLeft() alle au�er den N am meisten rechts stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringLeft("ABCDEFG", -2)  =>  "ABCDE"
 *
 * @param  string value
 * @param  int    n
 *
 * @return string
 */
string StringLeft(string value, int n) {
   if (n > 0) return(StringSubstr   (value, 0, n                 ));
   if (n < 0) return(StringSubstrFix(value, 0, StringLen(value)+n));
   return("");
}


/**
 * Gibt den linken Teil eines Strings bis zum Auftreten eines Teilstrings zur�ck. Das Ergebnis enth�lt den begrenzenden Teilstring nicht.
 *
 * @param  string value     - Ausgangsstring
 * @param  string substring - der das Ergebnis begrenzende Teilstring
 * @param  int    count     - Anzahl der Teilstrings, deren Auftreten das Ergebnis begrenzt (default: das erste Auftreten)
 *                            Wenn gr��er als die Anzahl der im String existierenden Teilstrings, wird der gesamte String zur�ckgegeben.
 *                            Wenn 0, wird ein Leerstring zur�ckgegeben.
 *                            Wenn negativ, wird mit dem Z�hlen statt von links von rechts begonnen.
 * @return string
 */
string StringLeftTo(string value, string substring, int count=1) {
   int start=0, pos=-1;

   // positive Anzahl: von vorn z�hlen
   if (count > 0) {
      while (count > 0) {
         pos = StringFind(value, substring, pos+1);
         if (pos == -1)
            return(value);
         count--;
      }
      return(StringLeft(value, pos));
   }

   // negative Anzahl: von hinten z�hlen
   if (count < 0) {
      /*
      while(count < 0) {
         pos = StringFind(value, substring, 0);
         if (pos == -1)
            return("");
         count++;
      }
      */
      pos = StringFind(value, substring, 0);
      if (pos == -1)
         return(value);

      if (count == -1) {
         while (pos != -1) {
            start = pos+1;
            pos   = StringFind(value, substring, start);
         }
         return(StringLeft(value, start-1));
      }
      return(_EMPTY_STR(catch("StringLeftTo(1)->StringFindEx()", ERR_NOT_IMPLEMENTED)));

      //pos = StringFindEx(value, substring, count);
      //return(StringLeft(value, pos));
   }

   // Anzahl == 0
   return("");
}


/**
 * Gibt einen rechten Teilstring eines Strings zur�ck.
 *
 * Ist N positiv, gibt StringRight() die N am meisten rechts stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringRight("ABCDEFG",  2)  =>  "FG"
 *
 * Ist N negativ, gibt StringRight() alle au�er den N am meisten links stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringRight("ABCDEFG", -2)  =>  "CDEFG"
 *
 * @param  string value
 * @param  int    n
 *
 * @return string
 */
string StringRight(string value, int n) {
   if (n > 0) return(StringSubstr(value, StringLen(value)-n));
   if (n < 0) return(StringSubstr(value, -n                ));
   return("");
}


/**
 * Gibt den rechten Teil eines Strings ab dem Auftreten eines Teilstrings zur�ck. Das Ergebnis enth�lt den begrenzenden Teilstring nicht.
 *
 * @param  string value     - Ausgangsstring
 * @param  string substring - der das Ergebnis begrenzende Teilstring
 * @param  int    count     - Anzahl der Teilstrings, deren Auftreten das Ergebnis begrenzt (default: das erste Auftreten)
 *                            Wenn 0 oder gr��er als die Anzahl der im String existierenden Teilstrings, wird ein Leerstring zur�ckgegeben.
 *                            Wenn negativ, wird mit dem Z�hlen statt von links von rechts begonnen.
 *                            Wenn negativ und absolut gr��er als die Anzahl der im String existierenden Teilstrings, wird der gesamte String zur�ckgegeben.
 * @return string
 */
string StringRightFrom(string value, string substring, int count=1) {
   int start=0, pos=-1;


   // (1) positive Anzahl: von vorn z�hlen
   if (count > 0) {
      while (count > 0) {
         pos = StringFind(value, substring, pos+1);
         if (pos == -1)
            return("");
         count--;
      }
      return(StringRight(value, -(pos + StringLen(substring))));
   }


   // (2) negative Anzahl: von hinten z�hlen
   if (count < 0) {
      /*
      while(count < 0) {
         pos = StringFind(value, substring, 0);
         if (pos == -1)
            return("");
         count++;
      }
      */
      pos = StringFind(value, substring, 0);
      if (pos == -1)
         return(value);

      if (count == -1) {
         while (pos != -1) {
            start = pos+1;
            pos   = StringFind(value, substring, start);
         }
         return(StringRight(value, -(start-1 + StringLen(substring))));
      }

      return(_EMPTY_STR(catch("StringRightTo(1)->StringFindEx()", ERR_NOT_IMPLEMENTED)));
      //pos = StringFindEx(value, substring, count);
      //return(StringRight(value, -(pos + StringLen(substring))));
   }

   // Anzahl == 0
   return("");
}


/**
 * Ob ein String mit dem angegebenen Teilstring beginnt. Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string prefix - Substring
 *
 * @return bool
 */
bool StringStartsWith(string object, string prefix) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(object)) return(false);
         if (StringIsNull(prefix)) return(!catch("StringStartsWith(1)  invalid parameter prefix = NULL", error));
      }
      catch("StringStartsWith(2)", error);
   }
   if (!StringLen(prefix))         return(!catch("StringStartsWith(3)  illegal parameter prefix = \"\"", ERR_INVALID_PARAMETER));

   return(StringFind(object, prefix) == 0);
}


/**
 * Ob ein String mit dem angegebenen Teilstring beginnt. Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string prefix - Substring
 *
 * @return bool
 */
bool StringStartsWithI(string object, string prefix) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(object)) return(false);
         if (StringIsNull(prefix)) return(!catch("StringStartsWithI(1)  invalid parameter prefix = NULL", error));
      }
      catch("StringStartsWithI(2)", error);
   }
   if (!StringLen(prefix))         return(!catch("StringStartsWithI(3)  illegal parameter prefix = \"\"", ERR_INVALID_PARAMETER));

   return(StringFind(StringToUpper(object), StringToUpper(prefix)) == 0);
}


/**
 * Ob ein String mit dem angegebenen Teilstring endet. Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string suffix - Substring
 *
 * @return bool
 */
bool StringEndsWith(string object, string suffix) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(object)) return(false);
         if (StringIsNull(suffix)) return(!catch("StringEndsWith(1)  invalid parameter suffix = NULL", error));
      }
      catch("StringEndsWith(2)", error);
   }

   int lenObject = StringLen(object);
   int lenSuffix = StringLen(suffix);

   if (lenSuffix == 0)             return(!catch("StringEndsWith(3)  illegal parameter suffix = \"\"", ERR_INVALID_PARAMETER));

   if (lenObject < lenSuffix)
      return(false);

   if (lenObject == lenSuffix)
      return(object == suffix);

   int start = lenObject-lenSuffix;
   return(StringFind(object, suffix, start) == start);
}


/**
 * Ob ein String mit dem angegebenen Teilstring endet. Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string suffix - Substring
 *
 * @return bool
 */
bool StringEndsWithI(string object, string suffix) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(object)) return(false);
         if (StringIsNull(suffix)) return(!catch("StringEndsWithI(1)  invalid parameter suffix = NULL", error));
      }
      catch("StringEndsWithI(2)", error);
   }

   int lenObject = StringLen(object);
   int lenSuffix = StringLen(suffix);

   if (lenSuffix == 0)             return(!catch("StringEndsWithI(3)  illegal parameter suffix = \"\"", ERR_INVALID_PARAMETER));

   if (lenObject < lenSuffix)
      return(false);

   object = StringToUpper(object);
   suffix = StringToUpper(suffix);

   if (lenObject == lenSuffix)
      return(object == suffix);

   int start = lenObject-lenSuffix;
   return(StringFind(object, suffix, start) == start);
}


/**
 * Pr�ft, ob ein String nur Ziffern enth�lt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsDigit(string value) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(value)) return(false);
      }
      catch("StringIsDigit(1)", error);
   }

   int chr, len=StringLen(value);

   if (len == 0)
      return(false);

   for (int i=0; i < len; i++) {
      chr = StringGetChar(value, i);
      if (chr < '0') return(false);
      if (chr > '9') return(false);       // Conditions f�r MQL optimiert
   }
   return(true);
}


/**
 * Pr�ft, ob ein String einen g�ltigen Integer darstellt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsInteger(string value) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(value)) return(false);
      }
      catch("StringIsInteger(1)", error);
   }
   return(value == StringConcatenate("", StrToInteger(value)));
}


/**
 * Pr�ft, ob ein String einen g�ltigen numerischen Wert darstellt (Zeichen 0123456789.+-)
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsNumeric(string value) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(value)) return(false);
      }
      catch("StringIsNumeric(1)", error);
   }

   int len = StringLen(value);
   if (!len)
      return(false);

   bool period = false;

   for (int i=0; i < len; i++) {
      int chr = StringGetChar(value, i);

      if (i == 0) {
         if (chr == '+') continue;
         if (chr == '-') continue;
      }
      if (chr == '.') {
         if (period) return(false);
         period = true;
         continue;
      }
      if (chr < '0') return(false);
      if (chr > '9') return(false);       // Conditions f�r MQL optimiert
   }
   return(true);
}


/**
 * Ob ein String eine g�ltige E-Mailadresse darstellt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsEmailAddress(string value) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(value)) return(false);
      }
      catch("StringIsEmailAddress(1)", error);
   }

   string s = StringTrim(value);

   // Validierung noch nicht implementiert
   return(StringLen(s) > 0);
}


/**
 * Ob ein String eine g�ltige Telefonnummer darstellt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsPhoneNumber(string value) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(value)) return(false);
      }
      catch("StringIsPhoneNumber(1)", error);
   }

   string s = StringReplace(StringTrim(value), " ", "");
   int char, length=StringLen(s);

   // Enth�lt die Nummer Bindestriche "-", m�ssen davor und danach Ziffern stehen.
   int pos = StringFind(s, "-");
   while (pos != -1) {
      if (pos   == 0     ) return(false);
      if (pos+1 == length) return(false);

      char = StringGetChar(s, pos-1);           // left char
      if (char < '0') return(false);
      if (char > '9') return(false);

      char = StringGetChar(s, pos+1);           // right char
      if (char < '0') return(false);
      if (char > '9') return(false);

      pos = StringFind(s, "-", pos+1);
   }
   if (char != 0) s = StringReplace(s, "-", "");

   // Beginnt eine internationale Nummer mit "+", darf danach keine 0 folgen.
   if (StringStartsWith(s, "+" )) {
      s = StringRight(s, -1);
      if (StringStartsWith(s, "0")) return(false);
   }

   return(StringIsDigit(s));
}


/**
 * F�gt ein Element am Beginn eines String-Arrays an.
 *
 * @param  string array[] - String-Array
 * @param  string value   - hinzuzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays oder -1 (EMPTY), falls ein Fehler auftrat
 *
 *
 * NOTE: Mu� global definiert sein. Die intern benutzte Funktion ReverseStringArray() ruft ihrerseits ArraySetAsSeries() auf, dessen Verhalten mit einem
 *       String-Parameter fehlerhaft (offiziell: nicht unterst�tzt) ist. Unter ungekl�rten Umst�nden wird das �bergebene Array zerschossen, es enth�lt dann
 *       Zeiger auf andere im Programm existierende Strings. Dieser Fehler trat in Indikatoren auf, wenn ArrayUnshiftString() in einer MQL-Library definiert
 *       war und �ber Modulgrenzen aufgerufen wurde, nicht jedoch bei globaler Definition. Au�erdem trat der Fehler nicht sofort, sondern erst nach Aufruf
 *       anderer Array-Funktionen auf, die mit v�llig unbeteiligten Arrays/String arbeiteten.
 */
int ArrayUnshiftString(string array[], string value) {
   if (ArrayDimension(array) > 1) return(_EMPTY(catch("ArrayUnshiftString()  too many dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS)));

   ReverseStringArray(array);
   int size = ArrayPushString(array, value);
   ReverseStringArray(array);
   return(size);
}


/**
 * Gibt die numerische Konstante einer MovingAverage-Methode zur�ck.
 *
 * @param  string value     - MA-Methode: [MODE_][SMA|EMA|LWMA|ALMA]
 * @param  int    execFlags - Ausf�hrungssteuerung: Flags der Fehler, die still gesetzt werden sollen (default: keine)
 *
 * @return int - MA-Konstante oder -1 (EMPTY), falls ein Fehler auftrat
 */
int StrToMaMethod(string value, int execFlags=NULL) {
   string str = StringToUpper(StringTrim(value));

   if (StringStartsWith(str, "MODE_"))
      str = StringRight(str, -5);

   if (str ==         "SMA" ) return(MODE_SMA );
   if (str == ""+ MODE_SMA  ) return(MODE_SMA );
   if (str ==         "EMA" ) return(MODE_EMA );
   if (str == ""+ MODE_EMA  ) return(MODE_EMA );
   if (str ==         "LWMA") return(MODE_LWMA);
   if (str == ""+ MODE_LWMA ) return(MODE_LWMA);
   if (str ==         "ALMA") return(MODE_ALMA);
   if (str == ""+ MODE_ALMA ) return(MODE_ALMA);

   if (!execFlags & MUTE_ERR_INVALID_PARAMETER) return(_EMPTY(catch("StrToMaMethod(1)  invalid parameter value = "+ DoubleQuoteStr(value), ERR_INVALID_PARAMETER)));
   else                                         return(_EMPTY(SetLastError(ERR_INVALID_PARAMETER)));
}


/**
 * Alias
 */
int StrToMovingAverageMethod(string value, int execFlags=NULL) {
   return(StrToMaMethod(value, execFlags));
}


/**
 * Fa�t einen String in einfache Anf�hrungszeichen ein. F�r einen nicht initialisierten String (NULL-Pointer)
 * wird der String "NULL" (ohne Anf�hrungszeichen) zur�ckgegeben.
 *
 * @param  string value
 *
 * @return string - resultierender String
 */
string QuoteStr(string value) {
   if (StringIsNull(value)) {
      int error = GetLastError();
      if (error && error!=ERR_NOT_INITIALIZED_STRING)
         catch("QuoteStr(1)", error);
      return("NULL");
   }
   return(StringConcatenate("'", value, "'"));
}


/**
 * Tests whether or not a given year is a leap year.
 *
 * @param  int year
 *
 * @return bool
 */
bool IsLeapYear(int year) {
   if (year%  4 != 0) return(false);                                 // if      (year is not divisible by   4) then not leap year
   if (year%100 != 0) return(true);                                  // else if (year is not divisible by 100) then     leap year
   if (year%400 == 0) return(true);                                  // else if (year is     divisible by 400) then     leap year
   return(false);                                                    // else                                        not leap year
}


/**
 * Erzeugt einen datetime-Wert. Parameter, die au�erhalb der gebr�uchlichen Zeitgrenzen liegen, werden automatisch in die entsprechende Periode
 * �bertragen. Der resultierende Zeitpunkt kann im Bereich von D'1901.12.13 20:45:52' (INT_MIN) bis D'2038.01.19 03:14:07' (INT_MAX) liegen.
 *
 * Beispiel: DateTime(2012, 2, 32, 25, -2) => D'2012.03.04 00:58:00' (2012 war ein Schaltjahr)
 *
 * @param  int year    -
 * @param  int month   - default: Januar
 * @param  int day     - default: der 1. des Monats
 * @param  int hours   - default: 0 Stunden
 * @param  int minutes - default: 0 Minuten
 * @param  int seconds - default: 0 Sekunden
 *
 * @return datetime - datetime-Wert oder NaT (Not-a-Time), falls ein Fehler auftrat
 *
 *
 * Note: Die internen MQL-Funktionen unterst�tzen nur datetime-Werte im Bereich von D'1970.01.01 00:00:00' bis D'2037.12.31 23:59:59'.
 */
datetime DateTime(int year, int month=1, int day=1, int hours=0, int minutes=0, int seconds=0) {
   year += (Ceil(month/12.) - 1);
   month = (12 + month%12) % 12;
   if (!month)
      month = 12;

   string  sDate = StringConcatenate(StringRight("000"+year, 4), ".", StringRight("0"+month, 2), ".01");
   datetime date = StrToTime(sDate);
   if (date < 0) return(_NaT(catch("DateTime()  year="+ year +", month="+ month +", day="+ day +", hours="+ hours +", minutes="+ minutes +", seconds="+ seconds, ERR_INVALID_PARAMETER)));

   int time = (day-1)*DAYS + hours*HOURS + minutes*MINUTES + seconds*SECONDS;
   return(date + time);
}


/**
 * Fix f�r fehlerhafte interne Funktion TimeDay()
 *
 *
 * Gibt den Tag des Monats eines Zeitpunkts zur�ck (1-31).
 *
 * @param  datetime time
 *
 * @return int
 */
int TimeDayFix(datetime time) {
   if (!time)
      return(1);
   return(TimeDay(time));           // Fehler: 0 statt 1 f�r D'1970.01.01 00:00:00'
}


/**
 * Fix f�r fehlerhafte interne Funktion TimeDayOfWeek()
 *
 *
 * Gibt den Wochentag eines Zeitpunkts zur�ck (0=Sunday ... 6=Saturday).
 *
 * @param  datetime time
 *
 * @return int
 */
int TimeDayOfWeekFix(datetime time) {
   if (!time)
      return(3);
   return(TimeDayOfWeek(time));     // Fehler: 0 (Sunday) statt 3 (Thursday) f�r D'1970.01.01 00:00:00'
}


/**
 * Fix f�r fehlerhafte interne Funktion TimeYear()
 *
 *
 * Gibt das Jahr eines Zeitpunkts zur�ck (1970-2037).
 *
 * @param  datetime time
 *
 * @return int
 */
int TimeYearFix(datetime time) {
   if (!time)
      return(1970);
   return(TimeYear(time));          // Fehler: 1900 statt 1970 f�r D'1970.01.01 00:00:00'
}


/**
 * Kopiert einen Speicherbereich. Als MoveMemory() implementiert, die betroffenen Speicherbl�cke k�nnen sich also �berlappen.
 *
 * @param  int destination - Zieladresse
 * @param  int source      - Quelladdrese
 * @param  int bytes       - Anzahl zu kopierender Bytes
 *
 * @return int - Fehlerstatus
 */
void CopyMemory(int destination, int source, int bytes) {
   if (destination>=0 && destination<MIN_VALID_POINTER) return(catch("CopyMemory(1)  invalid parameter destination = 0x"+ IntToHexStr(destination) +" (not a valid pointer)", ERR_INVALID_POINTER));
   if (source     >=0 && source    < MIN_VALID_POINTER) return(catch("CopyMemory(2)  invalid parameter source = 0x"+ IntToHexStr(source) +" (not a valid pointer)", ERR_INVALID_POINTER));

   RtlMoveMemory(destination, source, bytes);
   return(NO_ERROR);
}


/**
 * Addiert die Werte eines Integer-Arrays.
 *
 * @param  int values[] - Array mit Ausgangswerten
 *
 * @return int - Summe der Werte oder 0, falls ein Fehler auftrat
 */
int SumInts(int values[]) {
   if (ArrayDimension(values) > 1) return(_NULL(catch("SumInts(1)  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int sum, size=ArraySize(values);

   for (int i=0; i < size; i++) {
      sum += values[i];
   }
   return(sum);
}

/**
 * Gibt alle verf�gbaren MarketInfo()-Daten des aktuellen Instruments aus.
 *
 * @param  string location - Aufruf-Bezeichner
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Erl�uterungen zu den MODEs in stddefine.mqh
 */
int DebugMarketInfo(string location) {
   string symbol = Symbol();
   double value;
   int    error;

   debug(location +"   "+ StringRepeat("-", 23 + StringLen(symbol)));      //  -------------------------
   debug(location +"   Global variables for \""+ symbol +"\"");            //  Global variables "EURUSD"
   debug(location +"   "+ StringRepeat("-", 23 + StringLen(symbol)));      //  -------------------------

   debug(location +"   Pip         = "+ NumberToStr(Pip, PriceFormat));
   debug(location +"   PipDigits   = "+ PipDigits);
   debug(location +"   Digits  (b) = "+ Digits);
   debug(location +"   Point   (b) = "+ NumberToStr(Point, PriceFormat));
   debug(location +"   PipPoints   = "+ PipPoints);
   debug(location +"   Bid/Ask (b) = "+ NumberToStr(Bid, PriceFormat) +"/"+ NumberToStr(Ask, PriceFormat));
   debug(location +"   Bars    (b) = "+ Bars);
   debug(location +"   PriceFormat = \""+ PriceFormat +"\"");

   debug(location +"   "+ StringRepeat("-", 19 + StringLen(symbol)));      //  -------------------------
   debug(location +"   MarketInfo() for \""+ symbol +"\"");                //  MarketInfo() for "EURUSD"
   debug(location +"   "+ StringRepeat("-", 19 + StringLen(symbol)));      //  -------------------------

   // Erl�uterungen zu den Werten in stddefine.mqh
   value = MarketInfo(symbol, MODE_LOW              ); error = GetLastError(); debug(location +"   MODE_LOW               = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_HIGH             ); error = GetLastError(); debug(location +"   MODE_HIGH              = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
 //value = MarketInfo(symbol, 3                     ); error = GetLastError(); debug(location +"   3                      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
 //value = MarketInfo(symbol, 4                     ); error = GetLastError(); debug(location +"   4                      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_TIME             ); error = GetLastError(); debug(location +"   MODE_TIME              = "+ ifString(value<=0, NumberToStr(value, ".+"), "'"+ TimeToStr(value, TIME_FULL) +"'") + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
 //value = MarketInfo(symbol, 6                     ); error = GetLastError(); debug(location +"   6                      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
 //value = MarketInfo(symbol, 7                     ); error = GetLastError(); debug(location +"   7                      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
 //value = MarketInfo(symbol, 8                     ); error = GetLastError(); debug(location +"   8                      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_BID              ); error = GetLastError(); debug(location +"   MODE_BID               = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_ASK              ); error = GetLastError(); debug(location +"   MODE_ASK               = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_POINT            ); error = GetLastError(); debug(location +"   MODE_POINT             = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_DIGITS           ); error = GetLastError(); debug(location +"   MODE_DIGITS            = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_SPREAD           ); error = GetLastError(); debug(location +"   MODE_SPREAD            = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_STOPLEVEL        ); error = GetLastError(); debug(location +"   MODE_STOPLEVEL         = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_LOTSIZE          ); error = GetLastError(); debug(location +"   MODE_LOTSIZE           = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_TICKVALUE        ); error = GetLastError(); debug(location +"   MODE_TICKVALUE         = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_TICKSIZE         ); error = GetLastError(); debug(location +"   MODE_TICKSIZE          = "+                    NumberToStr(value, ifString(error, ".+", PriceFormat))           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_SWAPLONG         ); error = GetLastError(); debug(location +"   MODE_SWAPLONG          = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_SWAPSHORT        ); error = GetLastError(); debug(location +"   MODE_SWAPSHORT         = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_STARTING         ); error = GetLastError(); debug(location +"   MODE_STARTING          = "+ ifString(value<=0, NumberToStr(value, ".+"), "'"+ TimeToStr(value, TIME_FULL) +"'") + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_EXPIRATION       ); error = GetLastError(); debug(location +"   MODE_EXPIRATION        = "+ ifString(value<=0, NumberToStr(value, ".+"), "'"+ TimeToStr(value, TIME_FULL) +"'") + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_TRADEALLOWED     ); error = GetLastError(); debug(location +"   MODE_TRADEALLOWED      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MINLOT           ); error = GetLastError(); debug(location +"   MODE_MINLOT            = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_LOTSTEP          ); error = GetLastError(); debug(location +"   MODE_LOTSTEP           = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MAXLOT           ); error = GetLastError(); debug(location +"   MODE_MAXLOT            = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_SWAPTYPE         ); error = GetLastError(); debug(location +"   MODE_SWAPTYPE          = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_PROFITCALCMODE   ); error = GetLastError(); debug(location +"   MODE_PROFITCALCMODE    = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MARGINCALCMODE   ); error = GetLastError(); debug(location +"   MODE_MARGINCALCMODE    = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MARGININIT       ); error = GetLastError(); debug(location +"   MODE_MARGININIT        = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MARGINMAINTENANCE); error = GetLastError(); debug(location +"   MODE_MARGINMAINTENANCE = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MARGINHEDGED     ); error = GetLastError(); debug(location +"   MODE_MARGINHEDGED      = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_MARGINREQUIRED   ); error = GetLastError(); debug(location +"   MODE_MARGINREQUIRED    = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));
   value = MarketInfo(symbol, MODE_FREEZELEVEL      ); error = GetLastError(); debug(location +"   MODE_FREEZELEVEL       = "+                    NumberToStr(value, ".+"                              )           + ifString(error, " ["+ ErrorToStr(error) +"]", ""));

   return(catch("DebugMarketInfo(1)"));
}


/*
MarketInfo()-Fehler im Tester
=============================

// EA im Tester
M15::TestExpert::onTick()      ---------------------------------
M15::TestExpert::onTick()      Predefined variables for "EURUSD"
M15::TestExpert::onTick()      ---------------------------------
M15::TestExpert::onTick()      Pip         = 0.0001'0
M15::TestExpert::onTick()      PipDigits   = 4
M15::TestExpert::onTick()      Digits  (b) = 5
M15::TestExpert::onTick()      Point   (b) = 0.0000'1
M15::TestExpert::onTick()      PipPoints   = 10
M15::TestExpert::onTick()      Bid/Ask (b) = 1.2711'2/1.2713'1
M15::TestExpert::onTick()      Bars    (b) = 1001
M15::TestExpert::onTick()      PriceFormat = ".4'"
M15::TestExpert::onTick()      ---------------------------------
M15::TestExpert::onTick()      MarketInfo() for "EURUSD"
M15::TestExpert::onTick()      ---------------------------------
M15::TestExpert::onTick()      MODE_LOW               = 0.0000'0                 // falsch: nicht modelliert
M15::TestExpert::onTick()      MODE_HIGH              = 0.0000'0                 // falsch: nicht modelliert
M15::TestExpert::onTick()      MODE_TIME              = '2012.11.12 00:00:00'
M15::TestExpert::onTick()      MODE_BID               = 1.2711'2
M15::TestExpert::onTick()      MODE_ASK               = 1.2713'1
M15::TestExpert::onTick()      MODE_POINT             = 0.0000'1
M15::TestExpert::onTick()      MODE_DIGITS            = 5
M15::TestExpert::onTick()      MODE_SPREAD            = 19
M15::TestExpert::onTick()      MODE_STOPLEVEL         = 20
M15::TestExpert::onTick()      MODE_LOTSIZE           = 100000
M15::TestExpert::onTick()      MODE_TICKVALUE         = 1
M15::TestExpert::onTick()      MODE_TICKSIZE          = 0.0000'1
M15::TestExpert::onTick()      MODE_SWAPLONG          = -1.3
M15::TestExpert::onTick()      MODE_SWAPSHORT         = 0.5
M15::TestExpert::onTick()      MODE_STARTING          = 0
M15::TestExpert::onTick()      MODE_EXPIRATION        = 0
M15::TestExpert::onTick()      MODE_TRADEALLOWED      = 0                        // falsch modelliert
M15::TestExpert::onTick()      MODE_MINLOT            = 0.01
M15::TestExpert::onTick()      MODE_LOTSTEP           = 0.01
M15::TestExpert::onTick()      MODE_MAXLOT            = 2
M15::TestExpert::onTick()      MODE_SWAPTYPE          = 0
M15::TestExpert::onTick()      MODE_PROFITCALCMODE    = 0
M15::TestExpert::onTick()      MODE_MARGINCALCMODE    = 0
M15::TestExpert::onTick()      MODE_MARGININIT        = 0
M15::TestExpert::onTick()      MODE_MARGINMAINTENANCE = 0
M15::TestExpert::onTick()      MODE_MARGINHEDGED      = 50000
M15::TestExpert::onTick()      MODE_MARGINREQUIRED    = 254.25
M15::TestExpert::onTick()      MODE_FREEZELEVEL       = 0

// Indikator im Tester, via iCustom()
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   Predefined variables for "EURUSD"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   Pip         = 0.0001'0
M15::TestIndicator::onTick()   PipDigits   = 4
M15::TestIndicator::onTick()   Digits  (b) = 5
M15::TestIndicator::onTick()   Point   (b) = 0.0000'1
M15::TestIndicator::onTick()   PipPoints   = 10
M15::TestIndicator::onTick()   Bid/Ask (b) = 1.2711'2/1.2713'1
M15::TestIndicator::onTick()   Bars    (b) = 1001
M15::TestIndicator::onTick()   PriceFormat = ".4'"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   MarketInfo() for "EURUSD"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   MODE_LOW               = 0.0000'0                 // falsch �bernommen
M15::TestIndicator::onTick()   MODE_HIGH              = 0.0000'0                 // falsch �bernommen
M15::TestIndicator::onTick()   MODE_TIME              = '2012.11.12 00:00:00'
M15::TestIndicator::onTick()   MODE_BID               = 1.2711'2
M15::TestIndicator::onTick()   MODE_ASK               = 1.2713'1
M15::TestIndicator::onTick()   MODE_POINT             = 0.0000'1
M15::TestIndicator::onTick()   MODE_DIGITS            = 5
M15::TestIndicator::onTick()   MODE_SPREAD            = 0                        // v�llig falsch
M15::TestIndicator::onTick()   MODE_STOPLEVEL         = 20
M15::TestIndicator::onTick()   MODE_LOTSIZE           = 100000
M15::TestIndicator::onTick()   MODE_TICKVALUE         = 1
M15::TestIndicator::onTick()   MODE_TICKSIZE          = 0.0000'1
M15::TestIndicator::onTick()   MODE_SWAPLONG          = -1.3
M15::TestIndicator::onTick()   MODE_SWAPSHORT         = 0.5
M15::TestIndicator::onTick()   MODE_STARTING          = 0
M15::TestIndicator::onTick()   MODE_EXPIRATION        = 0
M15::TestIndicator::onTick()   MODE_TRADEALLOWED      = 1
M15::TestIndicator::onTick()   MODE_MINLOT            = 0.01
M15::TestIndicator::onTick()   MODE_LOTSTEP           = 0.01
M15::TestIndicator::onTick()   MODE_MAXLOT            = 2
M15::TestIndicator::onTick()   MODE_SWAPTYPE          = 0
M15::TestIndicator::onTick()   MODE_PROFITCALCMODE    = 0
M15::TestIndicator::onTick()   MODE_MARGINCALCMODE    = 0
M15::TestIndicator::onTick()   MODE_MARGININIT        = 0
M15::TestIndicator::onTick()   MODE_MARGINMAINTENANCE = 0
M15::TestIndicator::onTick()   MODE_MARGINHEDGED      = 50000
M15::TestIndicator::onTick()   MODE_MARGINREQUIRED    = 259.73                   // falsch: online
M15::TestIndicator::onTick()   MODE_FREEZELEVEL       = 0

// Indikator im Tester, standalone
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   Predefined variables for "EURUSD"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   Pip         = 0.0001'0
M15::TestIndicator::onTick()   PipDigits   = 4
M15::TestIndicator::onTick()   Digits  (b) = 5
M15::TestIndicator::onTick()   Point   (b) = 0.0000'1
M15::TestIndicator::onTick()   PipPoints   = 10
M15::TestIndicator::onTick()   Bid/Ask (b) = 1.2983'9/1.2986'7                   // falsch: online
M15::TestIndicator::onTick()   Bars    (b) = 1001
M15::TestIndicator::onTick()   PriceFormat = ".4'"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   MarketInfo() for "EURUSD"
M15::TestIndicator::onTick()   ---------------------------------
M15::TestIndicator::onTick()   MODE_LOW               = 1.2967'6                 // falsch: online
M15::TestIndicator::onTick()   MODE_HIGH              = 1.3027'3                 // falsch: online
M15::TestIndicator::onTick()   MODE_TIME              = '2012.11.30 23:59:52'    // falsch: online
M15::TestIndicator::onTick()   MODE_BID               = 1.2983'9                 // falsch: online
M15::TestIndicator::onTick()   MODE_ASK               = 1.2986'7                 // falsch: online
M15::TestIndicator::onTick()   MODE_POINT             = 0.0000'1
M15::TestIndicator::onTick()   MODE_DIGITS            = 5
M15::TestIndicator::onTick()   MODE_SPREAD            = 28                       // falsch: online
M15::TestIndicator::onTick()   MODE_STOPLEVEL         = 20
M15::TestIndicator::onTick()   MODE_LOTSIZE           = 100000
M15::TestIndicator::onTick()   MODE_TICKVALUE         = 1
M15::TestIndicator::onTick()   MODE_TICKSIZE          = 0.0000'1
M15::TestIndicator::onTick()   MODE_SWAPLONG          = -1.3
M15::TestIndicator::onTick()   MODE_SWAPSHORT         = 0.5
M15::TestIndicator::onTick()   MODE_STARTING          = 0
M15::TestIndicator::onTick()   MODE_EXPIRATION        = 0
M15::TestIndicator::onTick()   MODE_TRADEALLOWED      = 1
M15::TestIndicator::onTick()   MODE_MINLOT            = 0.01
M15::TestIndicator::onTick()   MODE_LOTSTEP           = 0.01
M15::TestIndicator::onTick()   MODE_MAXLOT            = 2
M15::TestIndicator::onTick()   MODE_SWAPTYPE          = 0
M15::TestIndicator::onTick()   MODE_PROFITCALCMODE    = 0
M15::TestIndicator::onTick()   MODE_MARGINCALCMODE    = 0
M15::TestIndicator::onTick()   MODE_MARGININIT        = 0
M15::TestIndicator::onTick()   MODE_MARGINMAINTENANCE = 0
M15::TestIndicator::onTick()   MODE_MARGINHEDGED      = 50000
M15::TestIndicator::onTick()   MODE_MARGINREQUIRED    = 259.73                   // falsch: online
M15::TestIndicator::onTick()   MODE_FREEZELEVEL       = 0
*/


/**
 * Erweitert einen String mit einem anderen String linksseitig auf eine gew�nschte Mindestl�nge.
 *
 * @param  string input     - Ausgangsstring
 * @param  int    padLength - gew�nschte Mindestl�nge
 * @param  string padString - zum Erweitern zu verwendender String (default: Leerzeichen)
 *
 * @return string
 */
string StringPadLeft(string input, int padLength, string padString=" ") {
   while (StringLen(input) < padLength) {
      input = StringConcatenate(padString, input);
   }
   return(input);
}


/**
 * Alias
 */
string StringLeftPad(string input, int padLength, string padString=" ") {
   return(StringPadLeft(input, padLength, padString));
}


/**
 * Erweitert einen String mit einem anderen String rechtsseitig auf eine gew�nschte Mindestl�nge.
 *
 * @param  string input     - Ausgangsstring
 * @param  int    padLength - gew�nschte Mindestl�nge
 * @param  string padString - zum Erweitern zu verwendender String (default: Leerzeichen)
 *
 * @return string
 */
string StringPadRight(string input, int padLength, string padString=" ") {
   while (StringLen(input) < padLength) {
      input = StringConcatenate(input, padString);
   }
   return(input);
}


/**
 * Alias
 */
string StringRightPad(string input, int padLength, string padString=" ") {
   return(StringPadRight(input, padLength, padString));
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Expert ist.
 *
 * @return bool
 */
bool Expert.IsTesting() {
   if (__TYPE__ == MT_LIBRARY) return(!catch("Expert.IsTesting(1)  library not initialized", ERR_RUNTIME_ERROR));

   if (!IsExpert())
      return(false);

   return(IsTesting());                                              // IsTesting() allein reicht nicht, da IsTesting() auch in Indikatoren TRUE zur�ckgeben werden kann.
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufendes Script ist.
 *
 * @return bool
 */
bool Script.IsTesting() {
   if (__TYPE__ == MT_LIBRARY) return(!catch("Script.IsTesting(1)  library not initialized", ERR_RUNTIME_ERROR));

   if (!IsScript())
      return(false);

   static int static.result = -1;                                    // static: Script ok, alles andere nicht zutreffend
   if (static.result != -1)
      return(static.result != 0);

   int hWnd = WindowHandleEx(NULL);
   if (!hWnd) return(false);

   string title = GetWindowText(GetParent(hWnd));
   if (!StringLen(title))
      return(!catch("Script.IsTesting(2)  title(hWndChart)=\""+ title +"\"  in context Script::"+ RootFunctionName(__WHEREAMI__) +"()", ERR_RUNTIME_ERROR));

   static.result = StringEndsWith(title, "(visual)");                // (int) bool

   return(static.result != 0);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Indikator ist.
 *
 * @return bool
 */
bool Indicator.IsTesting() {
   if (__TYPE__ == MT_LIBRARY) return(!catch("Indicator.IsTesting(1)  library not initialized", ERR_RUNTIME_ERROR));
   if (!IsIndicator()) return(false);

   if (IsTesting())    return(true);                                                      // Indikator l�uft in iCustom() im Tester

   int static.result  = -1;                                                               // static: in Indikatoren bis zum n�chsten init-Cycle ok
   if (static.result != -1)
      return(static.result != 0);


   // (1) Indikator wurde durch iCustom() geladen => Status des SuperContext �bernehmen
   if (IsSuperContext()) {
      if (__lpSuperContext>=0 && __lpSuperContext<MIN_VALID_POINTER) return(!catch("Indicator.IsTesting(2)  invalid input parameter __lpSuperContext = 0x"+ IntToHexStr(__lpSuperContext) +" (not a valid pointer)", ERR_INVALID_POINTER));
      int superCopy[EXECUTION_CONTEXT.intSize];
      CopyMemory(GetIntsAddress(superCopy), __lpSuperContext, EXECUTION_CONTEXT.size);    // SuperContext selbst kopieren, da der Context des laufenden Programms u.U. noch nicht
                                                                                          // initialisiert ist, z.B. wenn IsTesting() in UpdateExecutionContext() aufgerufen wird.
      static.result = (ec_TestFlags(superCopy) & TF_TEST && 1);                           // (int) bool
      ArrayResize(superCopy, 0);

      return(static.result != 0);
   }


   // (2) Indikator wurde manuell geladen:          INIT_REASON_USER
   //     - au�erhalb des Testers:                                                           Fenster existiert, Titel ist gesetzt und endet nicht mit "(visual)"
   //     - innerhalb des Testers:                                                           Fenster existiert, Titel ist gesetzt und endet       mit "(visual)"


   // (3) Indikator wurde per Template geladen:     INIT_REASON_TEMPLATE
   //     - au�erhalb des Testers:                                                           Fenster existiert, Titel ist noch nicht gesetzt oder endet nicht mit "(visual)"
   //     - innerhalb des Testers:                                                           Fenster existiert, Titel ist            gesetzt und  endet       mit "(visual)"
   //                                                                                   oder Fenster existiert nicht (VisualMode=Off)


   int hWnd = WindowHandleEx(NULL); if (!hWnd) return(false);
   if (hWnd == -1) {                                                                      // Fenster existiert nicht             => kommt nur im Tester bei VisualMode=Off vor
      static.result = 1;
      return(static.result != 0);
   }

   string title = GetWindowText(GetParent(hWnd));
   if (!StringLen(title)) {                                                               // Fenstertitel ist noch nicht gesetzt => kommt nicht im Tester vor
      static.result = 0;
      return(static.result != 0);
   }

   static.result = StringEndsWith(title, "(visual)");                                     // Unterscheidung durch "...(visual)" im Titel
   return(static.result != 0);
}


/**
 * Ob das aktuelle Programm im Tester ausgef�hrt wird.
 *
 * @return bool
 */
bool This.IsTesting() {
   if (__TYPE__ == MT_LIBRARY) return(!catch("This.IsTesting(1)  library not initialized", ERR_RUNTIME_ERROR));

   if (   IsExpert()) return(   Expert.IsTesting());
   if (   IsScript()) return(   Script.IsTesting());
   if (IsIndicator()) return(Indicator.IsTesting());

   return(!catch("This.IsTesting(2)  unreachable code reached", ERR_RUNTIME_ERROR));
}


/**
 * Listet alle ChildWindows eines Parent-Windows auf und schickt die Ausgabe an die Debug-Ausgabe.
 *
 * @param  int  hWnd      - Handle des Parent-Windows
 * @param  bool recursive - ob die ChildWindows rekursiv aufgelistet werden sollen (default: nein)
 *
 * @return bool - Erfolgsstatus
 */
bool EnumChildWindows(int hWnd, bool recursive=false) {
   recursive = recursive!=0;
   if (hWnd <= 0)       return(!catch("EnumChildWindows(1)  invalid parameter hWnd="+ hWnd , ERR_INVALID_PARAMETER));
   if (!IsWindow(hWnd)) return(!catch("EnumChildWindows(2)  not an existing window hWnd="+ IntToHexStr(hWnd), ERR_RUNTIME_ERROR));

   string padding, class, title, sId;
   int    id;

   static int sublevel;
   if (!sublevel) {
      class = GetClassName(hWnd);
      title = GetWindowText(hWnd);
      id    = GetDlgCtrlID(hWnd);
      sId   = ifString(id, " ("+ id +")", "");
      debug("EnumChildWindows(.)  "+ IntToHexStr(hWnd) +": "+ class +" \""+ title +"\""+ sId);
   }
   sublevel++;
   padding = StringRepeat(" ", (sublevel-1)<<1);

   int i, hWndNext=GetWindow(hWnd, GW_CHILD);
   while (hWndNext != 0) {
      i++;
      class = GetClassName(hWndNext);
      title = GetWindowText(hWndNext);
      id    = GetDlgCtrlID(hWndNext);
      sId   = ifString(id, " ("+ id +")", "");
      debug("EnumChildWindows(.)  "+ padding +"-> "+ IntToHexStr(hWndNext) +": "+ class +" \""+ title +"\""+ sId);

      if (recursive) {
         if (!EnumChildWindows(hWndNext, true)) {
            sublevel--;
            return(false);
         }
      }
      hWndNext = GetWindow(hWndNext, GW_HWNDNEXT);
   }
   if (!sublevel) /*&&*/ if (!i) debug("EnumChildWindows(.)  "+ padding +"-> (no child windows)");

   sublevel--;
   return(!catch("EnumChildWindows(3)"));
}


/**
 * Konvertiert einen String in einen Boolean. Die Strings "1", "on", "true" und "yes" sowie numerische String ungleich 0 (zero) werden als TRUE, alle anderen
 * als FALSE interpretiert. Gro�-/Kleinschreibung wird nicht unterschieden, leading/trailing White-Space wird ignoriert. Unscharfe Rechtschreibfehler werden
 * erkannt und entsprechend interpretiert (Ziffer 0 statt gro�em Buchstaben O und umgekehrt).
 *
 * @param  string value - der zu konvertierende String
 *
 * @return bool
 */
bool StrToBool(string value) {
   value = StringTrim(value);

   if (value == "" )      return( false);
   if (value == "0")      return( false);                // zero
   if (value == "1")      return( true );                // one
   if (value == "O")      return(_false(log("StrToBool(1)  value "+ DoubleQuoteStr(value) +" is capital letter O, assumed to be zero")));

   string lValue = StringToLower(value);
   if (lValue == "on"   ) return( true );
   if (lValue == "off"  ) return( false);
   if (lValue == "0n"   ) return(_true (log("StrToBool(2)  value "+ DoubleQuoteStr(value) +" starts with zero, assumed to be capital letter O")));
   if (lValue == "0ff"  ) return(_false(log("StrToBool(3)  value "+ DoubleQuoteStr(value) +" starts with zero, assumed to be capital letter O")));

   if (lValue == "true" ) return( true );
   if (lValue == "false") return( false);

   if (lValue == "yes"  ) return( true );
   if (lValue == "no"   ) return( false);
   if (lValue == "n0"   ) return(_false(log("StrToBool(4)  value "+ DoubleQuoteStr(value) +" ends with zero, assumed to be capital letter O")));

   if (StringIsNumeric(value))
      return(StrToDouble(value) != 0);

   return(false);
}


/**
 * Konvertiert die Gro�buchstaben eines String zu Kleinbuchstaben (code-page: ANSI westlich).
 *
 * @param  string value
 *
 * @return string
 */
string StringToLower(string value) {
   string result = value;
   int char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      char = StringGetChar(value, i);
      //logische Version
      //if      ( 65 <= char && char <=  90) result = StringSetChar(result, i, char+32);  // A-Z->a-z
      //else if (192 <= char && char <= 214) result = StringSetChar(result, i, char+32);  // �-�->�-�
      //else if (216 <= char && char <= 222) result = StringSetChar(result, i, char+32);  // �-�->�-�
      //else if (char == 138)                result = StringSetChar(result, i, 154);      // �->�
      //else if (char == 140)                result = StringSetChar(result, i, 156);      // �->�
      //else if (char == 142)                result = StringSetChar(result, i, 158);      // �->�
      //else if (char == 159)                result = StringSetChar(result, i, 255);      // �->�

      // f�r MQL optimierte Version
      if (char > 64) {
         if (char < 91) {
            result = StringSetChar(result, i, char+32);                 // A-Z->a-z
         }
         else if (char > 191) {
            if (char < 223) {
               if (char != 215)
                  result = StringSetChar(result, i, char+32);           // �-�->�-�, �-�->�-�
            }
         }
         else if (char == 138) result = StringSetChar(result, i, 154);  // �->�
         else if (char == 140) result = StringSetChar(result, i, 156);  // �->�
         else if (char == 142) result = StringSetChar(result, i, 158);  // �->�
         else if (char == 159) result = StringSetChar(result, i, 255);  // �->�
      }
   }
   return(result);
}


/**
 * Konvertiert einen String in Gro�schreibweise.
 *
 * @param  string value
 *
 * @return string
 */
string StringToUpper(string value) {
   string result = value;
   int char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      char = StringGetChar(value, i);
      //logische Version
      //if      (96 < char && char < 123)             result = StringSetChar(result, i, char-32);
      //else if (char==154 || char==156 || char==158) result = StringSetChar(result, i, char-16);
      //else if (char==255)                           result = StringSetChar(result, i,     159);  // � -> �
      //else if (char > 223)                          result = StringSetChar(result, i, char-32);

      // f�r MQL optimierte Version
      if      (char == 255)                 result = StringSetChar(result, i,     159);   // � -> �
      else if (char  > 223)                 result = StringSetChar(result, i, char-32);
      else if (char == 158)                 result = StringSetChar(result, i, char-16);
      else if (char == 156)                 result = StringSetChar(result, i, char-16);
      else if (char == 154)                 result = StringSetChar(result, i, char-16);
      else if (char  >  96) if (char < 123) result = StringSetChar(result, i, char-32);
   }
   return(result);
}


/**
 * Trimmt einen String beidseitig.
 *
 * @param  string value
 *
 * @return string
 */
string StringTrim(string value) {
   return(StringTrimLeft(StringTrimRight(value)));
}


/**
 * URL-kodiert einen String.  Leerzeichen werden als "+"-Zeichen kodiert.
 *
 * @param  string value
 *
 * @return string - URL-kodierter String
 */
string UrlEncode(string value) {
   string strChar, result="";
   int    char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      strChar = StringSubstr(value, i, 1);
      char    = StringGetChar(strChar, 0);

      if      (47 < char && char <  58) result = StringConcatenate(result, strChar);                  // 0-9
      else if (64 < char && char <  91) result = StringConcatenate(result, strChar);                  // A-Z
      else if (96 < char && char < 123) result = StringConcatenate(result, strChar);                  // a-z
      else if (char == ' ')             result = StringConcatenate(result, "+");
      else                              result = StringConcatenate(result, "%", CharToHexStr(char));
   }

   if (!catch("UrlEncode()"))
      return(result);
   return("");
}


/**
 * Pr�ft, ob die angegebene Datei im MQL-Files-Verzeichnis existiert und eine normale Datei ist (kein Verzeichnis).
 *
 * @return string filename - zu "{mql_directory}\files\" relativer Dateiname
 *
 * @return bool
 */
bool IsMqlFile(string filename) {

   // TODO: Pr�fen, ob Scripte und Indikatoren im Tester tats�chlich auf "{terminal_directory}\tester\" zugreifen.

   if (IsScript() || !This.IsTesting()) string mqlDir = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   else                                        mqlDir = "\\tester";
   return(IsFile(StringConcatenate(TerminalPath(), mqlDir, "\\files\\",  filename)));
}


/**
 * Pr�ft, ob das angegebene Verzeichnis im MQL-Files-Verzeichnis existiert.
 *
 * @return string dirname - zu "{mql_directory}\files\" relativer Verzeichnisname
 *
 * @return bool
 */
bool IsMqlDirectory(string dirname) {

   // TODO: Pr�fen, ob Scripte und Indikatoren im Tester tats�chlich auf "{terminal_directory}\tester\" zugreifen.

   if (IsScript() || !This.IsTesting()) string mqlDir = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   else                                        mqlDir = "\\tester";
   return(IsDirectory(StringConcatenate(TerminalPath(), mqlDir, "\\files\\",  dirname)));
}


/**
 * Alias
 */
string CharToHexStr(int char) {
   return(ByteToHexStr(char));
}


/**
 * Gibt die hexadezimale Repr�sentation eines Strings zur�ck.
 *
 * @param  string value - Ausgangswert
 *
 * @return string - Hex-String
 */
string StringToHexStr(string value) {
   if (StringIsNull(value))
      return("NULL");

   string result = "";
   int len = StringLen(value);

   for (int i=0; i < len; i++) {
      result = StringConcatenate(result, CharToHexStr(StringGetChar(value, i)));
   }

   return(result);
}


/**
 * Konvertiert das erste Zeichen eines Strings in Gro�schreibweise.
 *
 * @param  string value
 *
 * @return string
 */
string StringCapitalize(string value) {
   if (!StringLen(value))
      return(value);
   return(StringConcatenate(StringToUpper(StringLeft(value, 1)), StringRight(value, -1)));
}


#define WM_COMMAND   0x0111


/**
 * Schickt dem aktuellen Chart eine Nachricht zum �ffnen des EA-Input-Dialogs.
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: Es wird nicht �berpr�ft, ob zur Zeit des Aufrufs ein EA l�uft.
 */
int Chart.Expert.Properties() {
   if (This.IsTesting()) return(catch("Chart.Expert.Properties(1)", ERR_FUNC_NOT_ALLOWED_IN_TESTER));

   int hWnd = WindowHandleEx(NULL);
   if (!hWnd) return(last_error);

   if (!PostMessageA(hWnd, WM_COMMAND, ID_CHART_EXPERT_PROPERTIES, 0))
      return(catch("Chart.Expert.Properties(3)->user32::PostMessageA() failed", ERR_WIN32_ERROR));

   return(NO_ERROR);
}


/**
 * Schickt dem aktuellen Chart einen k�nstlichen Tick.
 *
 * @param  bool sound - ob der Tick akustisch best�tigt werden soll oder nicht (default: nein)
 *
 * @return int - Fehlerstatus
 */
int Chart.SendTick(bool sound=false) {
   sound = sound!=0;

   int hWnd = WindowHandleEx(NULL);
   if (!hWnd) return(last_error);

   if (!This.IsTesting()) {
      PostMessageA(hWnd, MT4InternalMsg(), MT4_TICK, TICK_OFFLINE_EA);  // LPARAM lParam: 0 - EA::start() wird in Offline-Charts nicht getriggert
   }                                                                    //                1 - EA::start() wird in Offline-Charts getriggert (bei bestehender Server-Connection)
   else if (Tester.IsPaused()) {
      SendMessageA(hWnd, WM_COMMAND, ID_TESTER_TICK, 0);
   }

   if (sound)
      PlaySoundEx("Tick.wav");

   return(NO_ERROR);
}


/**
 * Ruft den Hauptmen�-Befehl Charts->Objects-Unselect All auf.
 *
 * @return int - Fehlerstatus
 */
int Chart.Objects.UnselectAll() {
   int hWnd = WindowHandleEx(NULL);
   if (!hWnd) return(last_error);

   PostMessageA(hWnd, WM_COMMAND, ID_CHART_OBJECTS_UNSELECTALL, 0);
   return(NO_ERROR);
}


/**
 * Ruft den Kontextmen�-Befehl Chart->Refresh auf.
 *
 * @return int - Fehlerstatus
 */
int Chart.Refresh() {
   int hWnd = WindowHandleEx(NULL);
   if (!hWnd) return(last_error);

   PostMessageA(hWnd, WM_COMMAND, ID_CHART_REFRESH, 0);
   return(NO_ERROR);
}


/**
 * Schaltet den Tester in den Pause-Mode. Der Aufruf ist nur im Tester m�glich.
 *
 * @return int - Fehlerstatus
 */
int Tester.Pause() {
   if (!This.IsTesting()) return(catch("Tester.Pause(1)  Tester only function", ERR_FUNC_NOT_ALLOWED));

   if (Tester.IsPaused())            return(NO_ERROR);               // skipping

   if (!IsScript())
      if (__WHEREAMI__ == RF_DEINIT) return(NO_ERROR);               // SendMessage() darf in deinit() nicht mehr benutzt werden

   int hWnd = GetApplicationWindow();
   if (!hWnd)
      return(last_error);

   int result = SendMessageA(hWnd, WM_COMMAND, IDC_TESTER_SETTINGS_PAUSERESUME, 0);

   return(NO_ERROR);
}


/**
 * Ob der Tester momentan pausiert. Der Aufruf ist nur im Tester selbst m�glich.
 *
 * @return bool
 */
bool Tester.IsPaused() {
   if (!This.IsTesting()) return(!catch("Tester.IsPaused(1)  Tester only function", ERR_FUNC_NOT_ALLOWED));

   bool testerStopped;
   int  hWndSettings = GetDlgItem(GetTesterWindow(), IDC_TESTER_SETTINGS);

   if (IsScript()) {
      // VisualMode=On
      testerStopped = GetWindowText(GetDlgItem(hWndSettings, IDC_TESTER_SETTINGS_STARTSTOP)) == "Start";    // mu� im Script reichen
   }
   else {
      if (!IsVisualModeFix())                                        // EA/Indikator aus iCustom()
         return(false);                                              // Indicator::deinit() wird zeitgleich zu EA::deinit() ausgef�hrt,
      testerStopped = (IsStopped() || __WHEREAMI__ ==RF_DEINIT);     // der EA stoppt(e) also auch
   }

   if (testerStopped)
      return(false);

   return(GetWindowText(GetDlgItem(hWndSettings, IDC_TESTER_SETTINGS_PAUSERESUME)) == ">>");
}


/**
 * Ob der Tester momentan gestoppt ist. Der Aufruf ist nur im Tester m�glich.
 *
 * @return bool
 */
bool Tester.IsStopped() {
   if (!This.IsTesting()) return(!catch("Tester.IsStopped(1)  Tester only function", ERR_FUNC_NOT_ALLOWED));

   if (IsScript()) {
      int hWndSettings = GetDlgItem(GetTesterWindow(), IDC_TESTER_SETTINGS);
      return(GetWindowText(GetDlgItem(hWndSettings, IDC_TESTER_SETTINGS_STARTSTOP)) == "Start");   // mu� im Script reichen
   }
   return(IsStopped() || __WHEREAMI__==RF_DEINIT);                   // IsStopped() war im Tester noch nie gesetzt; Indicator::deinit() wird
}                                                                    // zeitgleich zu EA::deinit() ausgef�hrt, der EA stoppt(e) also auch.


/**
 * Erzeugt einen neuen String der gew�nschten L�nge.
 *
 * @param  int length - L�nge
 *
 * @return string
 */
string CreateString(int length) {
   if (length < 0) return(_EMPTY_STR(catch("CreateString(1)  invalid parameter length = "+ length, ERR_INVALID_PARAMETER)));

   if (!length) return(StringConcatenate("", ""));                   // Um immer einen neuen String zu erhalten (MT4-Zeigerproblematik), darf Ausgangsbasis kein Literal sein.
                                                                     // Daher wird auch beim Initialisieren der string-Variable StringConcatenate() verwendet (siehe MQL.doc).
   string newStr = StringConcatenate(MAX_STRING_LITERAL, "");
   int    strLen = StringLen(newStr);

   while (strLen < length) {
      newStr = StringConcatenate(newStr, MAX_STRING_LITERAL);
      strLen = StringLen(newStr);
   }

   if (strLen != length)
      newStr = StringSubstr(newStr, 0, length);
   return(newStr);
}


/**
 * Aktiviert bzw. deaktiviert den Aufruf der start()-Funktion von Expert Advisern bei Eintreffen von Ticks.
 * Wird �blicherweise aus der init()-Funktion aufgerufen.
 *
 * @param  bool enable - gew�nschter Status: On/Off
 *
 * @return int - Fehlerstatus
 */
int Toolbar.Experts(bool enable) {
   enable = enable!=0;

   if (This.IsTesting()) return(debug("Toolbar.Experts(1)  skipping in Tester", NO_ERROR));

   // TODO: Lock implementieren, damit mehrere gleichzeitige Aufrufe sich nicht gegenseitig �berschreiben
   // TODO: Vermutlich Deadlock bei IsStopped()=TRUE, dann PostMessage() verwenden

   int hWnd = GetApplicationWindow();
   if (!hWnd)
      return(last_error);

   if (enable) {
      if (!IsExpertEnabled())
         SendMessageA(hWnd, WM_COMMAND, ID_EXPERTS_ONOFF, 0);
   }
   else /*disable*/ {
      if (IsExpertEnabled())
         SendMessageA(hWnd, WM_COMMAND, ID_EXPERTS_ONOFF, 0);
   }
   return(NO_ERROR);
}


/**
 * Ruft den Kontextmen�-Befehl MarketWatch->Symbols auf.
 *
 * @return int - Fehlerstatus
 */
int MarketWatch.Symbols() {
   int hWnd = GetApplicationWindow();
   if (!hWnd)
      return(last_error);

   PostMessageA(hWnd, WM_COMMAND, ID_MARKETWATCH_SYMBOLS, 0);
   return(NO_ERROR);
}


/**
 * Alias
 */
int WM_MT4() {
   return(MT4InternalMsg());
}


/**
 * Pr�ft, ob der aktuelle Tick ein neuer Tick ist.
 *
 * @return bool - Ergebnis
 */
bool EventListener.NewTick() {
   int vol = Volume[0];
   if (!vol)                                                         // Tick ung�ltig (z.B. Symbol noch nicht subscribed)
      return(false);

   static bool lastResult;
   static int  lastTick, lastVol;

   // Mehrfachaufrufe w�hrend desselben Ticks erkennen
   if (Tick == lastTick)
      return(lastResult);

   // Es reicht immer, den Tick nur anhand des Volumens des aktuellen Timeframes zu bestimmen.
   bool result = (lastVol && vol!=lastVol);                          // wenn der letzte Tick g�ltig war und sich das aktuelle Volumen ge�ndert hat
                                                                     // (Optimierung unn�tig, da im Normalfall immer beide Bedingungen zutreffen)
   lastVol    = vol;
   lastResult = result;
   return(result);
}


/**
 * Gibt die aktuelle Server-Zeit des Terminals zur�ck (im Tester entsprechend der im Tester modellierten Zeit). Diese Zeit mu� nicht mit der Zeit des
 * letzten Ticks �bereinstimmen (z.B. am Wochenende oder wenn keine Ticks existieren).
 *
 * @return datetime - Server-Zeit oder NULL, falls ein Fehler auftrat
 */
datetime TimeServer() {
   datetime serverTime;

   if (This.IsTesting()) {
      // im Tester entspricht die Serverzeit immer der Zeit des letzten Ticks
      serverTime = TimeCurrentEx("TimeServer(1)"); if (!serverTime) return(NULL);
   }
   else {
      // Au�erhalb des Testers darf TimeCurrent[Ex]() nicht verwendet werden. Der R�ckgabewert ist in Kurspausen bzw. am Wochenende oder wenn keine
      // Ticks existieren (in Offline-Charts) falsch.
      serverTime = GmtToServerTime(GetGmtTime()); if (serverTime == NaT) return(NULL);
   }
   return(serverTime);
}


/**
 * Gibt die aktuelle GMT-Zeit des Terminals zur�ck (im Tester entsprechend der im Tester modellierten Zeit).
 *
 * @return datetime - GMT-Zeit oder NULL, falls ein Fehler auftrat
 */
datetime TimeGMT() {
   datetime gmt;

   if (This.IsTesting()) {
      // TODO: Scripte und Indikatoren sehen bei Aufruf von TimeLocal() im Tester u.U. nicht die modellierte, sondern die reale Zeit oder sogar NULL.
      datetime localTime = TimeLocalEx("TimeGMT(1)"); if (!localTime) return(NULL);
      gmt = ServerToGmtTime(localTime);                              // TimeLocal() entspricht im Tester der Serverzeit
   }
   else {
      gmt = GetGmtTime();
   }
   return(gmt);
}


/**
 * Gibt die aktuelle FXT-Zeit des Terminals zur�ck (im Tester entsprechend der im Tester modellierten Zeit).
 *
 * @return datetime - FXT-Zeit oder NULL, falls ein Fehler auftrat
 */
datetime TimeFXT() {
   datetime gmt = TimeGMT();         if (!gmt)       return(NULL);
   datetime fxt = GmtToFxtTime(gmt); if (fxt == NaT) return(NULL);
   return(fxt);
}


/**
 * Gibt die aktuelle FXT-Zeit des Systems zur�ck (auch im Tester).
 *
 * @return datetime - FXT-Zeit oder NULL, falls ein Fehler auftrat
 */
datetime GetFxtTime() {
   datetime gmt = GetGmtTime();      if (!gmt)       return(NULL);
   datetime fxt = GmtToFxtTime(gmt); if (fxt == NaT) return(NULL);
   return(fxt);
}


/**
 * Gibt die aktuelle Serverzeit zur�ck (auch im Tester). Dies ist nicht der Zeitpunkt des letzten eingetroffenen Ticks wie von
 * TimeCurrent() zur�ckgegeben, sondern die auf dem Server tats�chlich g�ltige Zeit (in seiner Zeitzone).
 *
 * @return datetime - Serverzeit oder NULL, falls ein Fehler auftrat
 */
datetime GetServerTime() {
   datetime gmt  = GetGmtTime();         if (!gmt)        return(NULL);
   datetime time = GmtToServerTime(gmt); if (time == NaT) return(NULL);
   return(time);
}


/**
 * Gibt die aktuelle lokale Zeit des Terminals zur�ck. Im Tester entspricht diese Zeit dem Zeitpunkt des letzten Ticks.
 * Dies bedeutet, da� das Terminal w�hrend des Testens die lokale Zeitzone auf die Serverzeitzone setzt.
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return datetime - Zeitpunkt oder NULL, falls ein Fehler auftrat
 *
 *
 * NOTE: Diese Funktion meldet im Unterschied zur Originalfunktion einen Fehler, wenn TimeLocal() einen falschen Wert (NULL) zur�ckgibt.
 */
datetime TimeLocalEx(string location="") {
   datetime time = TimeLocal();
   if (!time) return(!catch(location + ifString(!StringLen(location), "", "->") +"TimeLocalEx(1)->TimeLocal() = 0", ERR_RUNTIME_ERROR));
   return(time);
}


/**
 * Gibt *NICHT* die Serverzeit, sondern den Zeitpunkt des letzten Ticks der selektierten Symbole zur�ck. Im Tester wird diese Zeit modelliert.
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return datetime - Zeitpunkt oder NULL, falls ein Fehler auftrat
 *
 *
 * NOTE: Diese Funktion meldet im Unterschied zur Originalfunktion einen Fehler, wenn der Zeitpunkt des letzten Ticks nicht bekannt ist.
 */
datetime TimeCurrentEx(string location="") {
   datetime time = TimeCurrent();
   if (!time) return(!catch(location + ifString(!StringLen(location), "", "->") +"TimeCurrentEx(1)->TimeCurrent() = 0", ERR_RUNTIME_ERROR));
   return(time);
}


/**
 * Gibt die lesbare Konstante eines ModuleType-Flags zur�ck.
 *
 * @param  int fType - ModuleType-Flag
 *
 * @return string
 */
string ModuleTypesToStr(int fType) {
   string result = "";

   if (fType & MT_EXPERT    && 1) result = StringConcatenate(result, "|MT_EXPERT"   );
   if (fType & MT_SCRIPT    && 1) result = StringConcatenate(result, "|MT_SCRIPT"   );
   if (fType & MT_INDICATOR && 1) result = StringConcatenate(result, "|MT_INDICATOR");
   if (fType & MT_LIBRARY   && 1) result = StringConcatenate(result, "|MT_LIBRARY"  );

   if (!StringLen(result)) result = "(unknown module type "+ fType +")";
   else                    result = StringSubstr(result, 1);
   return(result);
}


/**
 * Gibt die Beschreibung eines UninitializeReason-Codes zur�ck (siehe UninitializeReason()).
 *
 * @param  int reason - Code
 *
 * @return string
 */
string UninitializeReasonDescription(int reason) {
   switch (reason) {
      case REASON_UNDEFINED  : return("undefined"                          );
      case REASON_REMOVE     : return("program removed from chart"         );
      case REASON_RECOMPILE  : return("program recompiled"                 );
      case REASON_CHARTCHANGE: return("chart symbol or timeframe changed"  );
      case REASON_CHARTCLOSE : return("chart closed"                       );
      case REASON_PARAMETERS : return("input parameters changed"           );
      case REASON_ACCOUNT    : return("account or account settings changed");
      // ab Build > 509
      case REASON_TEMPLATE   : return("template changed"                   );
      case REASON_INITFAILED : return("OnInit() failed"                    );
      case REASON_CLOSE      : return("terminal closed"                    );
   }
   return(_EMPTY_STR(catch("UninitializeReasonDescription()  invalid parameter reason = "+ reason, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt die Beschreibung eines InitReason-Codes zur�ck (siehe InitReason()).
 *
 * @param  int reason - Code
 *
 * @return string
 */
string InitReasonDescription(int reason) {
   switch (reason) {
      case INIT_REASON_USER             : return("program loaded by user"    );
      case INIT_REASON_TEMPLATE         : return("program loaded by template");
      case INIT_REASON_PROGRAM          : return("program loaded by program" );
      case INIT_REASON_PROGRAM_AFTERTEST: return("program loaded after test"  );
      case INIT_REASON_PARAMETERS       : return("input parameters changed"  );
      case INIT_REASON_TIMEFRAMECHANGE  : return("chart timeframe changed"   );
      case INIT_REASON_SYMBOLCHANGE     : return("chart symbol changed"      );
      case INIT_REASON_RECOMPILE        : return("program recompiled"        );
   }
   return(_EMPTY_STR(catch("InitReasonDescription(1)  invalid parameter reason = "+ reason, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt den Wert der extern verwalteten Assets eines Accounts zur�ck.
 *
 * @param  string companyId - AccountCompany-Identifier
 * @param  string accountId - Account-Identifier
 *
 * @return double - Wert oder EMPTY_VALUE, falls ein Fehler auftrat
 */
double GetExternalAssets(string companyId, string accountId) {
   if (!StringLen(companyId)) return(_EMPTY_VALUE(catch("GetExternalAssets(1)  invalid parameter companyId = "+ DoubleQuoteStr(companyId), ERR_INVALID_PARAMETER)));
   if (!StringLen(accountId)) return(_EMPTY_VALUE(catch("GetExternalAssets(2)  invalid parameter accountId = "+ DoubleQuoteStr(accountId), ERR_INVALID_PARAMETER)));

   static string lastCompanyId;
   static string lastAccountId;
   static double lastAuM;

   if (companyId!=lastCompanyId || accountId!=lastAccountId) {
      double aum = RefreshExternalAssets(companyId, accountId);
      if (IsEmptyValue(aum))
         return(EMPTY_VALUE);

      lastCompanyId = companyId;
      lastAccountId = accountId;
      lastAuM       = aum;
   }
   return(lastAuM);
}


/**
 * Liest den Konfigurationswert der extern verwalteten Assets eines Acounts neu ein.  Der konfigurierte Wert kann negativ sein,
 * um die Accountgr��e herunterzuskalieren (z.B. zum Testen einer Strategie im Real-Account).
 *
 * @param  string companyId - AccountCompany-Identifier
 * @param  string accountId - Account-Identifier
 *
 * @return double - Wert oder EMPTY_VALUE, falls ein Fehler auftrat
 */
double RefreshExternalAssets(string companyId, string accountId) {
   if (!StringLen(companyId)) return(_EMPTY_VALUE(catch("RefreshExternalAssets(1)  invalid parameter companyId = "+ DoubleQuoteStr(companyId), ERR_INVALID_PARAMETER)));
   if (!StringLen(accountId)) return(_EMPTY_VALUE(catch("RefreshExternalAssets(2)  invalid parameter accountId = "+ DoubleQuoteStr(accountId), ERR_INVALID_PARAMETER)));

   string mqlDir  = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = TerminalPath() + mqlDir +"\\files\\"+ companyId +"\\"+ accountId +"_config.ini";
   string section = "General";
   string key     = "AuM.Value";
   double value   = GetIniDouble(file, section, key);

   return(value);
}


/**
 * Gibt den vollst�ndigen Dateinamen der Konfigurationsdatei eines Accounts zur�ck.
 *
 * @param  string companyId - AccountCompany-Identifier
 * @param  string accountId - Account-Identifier: je nach Company Account-Nummer oder Account-Alias
 *
 * @return string - Dateiname oder Leerstring, falls ein Fehler auftrat
 */
string GetAccountConfigPath(string companyId, string accountId) {
   if (!StringLen(companyId)) return(_EMPTY_STR(catch("GetAccountConfigPath(1)  invalid parameter companyId = "+ DoubleQuoteStr(companyId), ERR_INVALID_PARAMETER)));
   if (!StringLen(accountId)) return(_EMPTY_STR(catch("GetAccountConfigPath(2)  invalid parameter accountId = "+ DoubleQuoteStr(accountId), ERR_INVALID_PARAMETER)));

   string mqlDir   = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string filename = StringConcatenate(TerminalPath(), mqlDir, "\\files\\", companyId, "\\", accountId, "_config.ini");
   return(filename);
}


/**
 * Ob der angegebene Schl�ssel entweder in der globalen oder in der lokalen Konfiguration existiert.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsConfigKey(string section, string key) {
   if (IsGlobalConfigKey(section, key))
      return(true);
   return(IsLocalConfigKey(section, key));
}


/**
 * Ob der angegebene Schl�ssel in der lokalen Konfigurationsdatei existiert.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsLocalConfigKey(string section, string key) {
   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return(false);
   return(IsIniKey(localConfig, section, key));
}


/**
 * Ob der angegebene Schl�ssel in der globalen Konfigurationsdatei existiert.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsGlobalConfigKey(string section, string key) {
   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return(false);
   return(IsIniKey(globalConfig, section, key));
}


/**
 * Gibt einen Konfigurationswert als Boolean zur�ck.  Dabei werden die globale und die lokale Konfiguration der MetaTrader-Installation durchsucht,
 * wobei die lokale eine h�here Priorit�t als die globale Konfiguration hat.
 *
 * Der Wert kann als "0" oder "1", "On" oder "Off", "Yes" oder "No" und "true" oder "false" angegeben werden (ohne Beachtung von Gro�-/Kleinschreibung).
 * Ein leerer Wert eines existierenden Schl�ssels wird als FALSE und ein numerischer Wert als TRUE interpretiert, wenn sein Zahlenwert ungleich 0 (zero) ist.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return bool - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
bool GetConfigBool(string section, string key, bool defaultValue=false) {
   defaultValue = defaultValue!=0;

   // Es ist schneller, immer globale und lokale Konfiguration auszuwerten (intern jeweils nur ein Aufruf von GetPrivateProfileString()).
   bool result = GetGlobalConfigBool(section, key, defaultValue);
        result = GetLocalConfigBool (section, key, result);
   return(result);
}


/**
 * Gibt einen lokalen Konfigurationswert als Boolean zur�ck.
 *
 * Der Wert kann als "0" oder "1", "On" oder "Off", "Yes" oder "No" und "true" oder "false" angegeben werden (ohne Beachtung von Gro�-/Kleinschreibung).
 * Ein leerer Wert eines existierenden Schl�ssels wird als FALSE und ein numerischer Wert als TRUE interpretiert, wenn sein Zahlenwert ungleich 0 (zero) ist.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return bool - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
bool GetLocalConfigBool(string section, string key, bool defaultValue=false) {
   defaultValue = defaultValue!=0;

   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return(false);
   return(GetIniBool(localConfig, section, key, defaultValue));
}


/**
 * Gibt einen globalen Konfigurationswert als Boolean zur�ck.
 *
 * Der Wert kann als "0" oder "1", "On" oder "Off", "Yes" oder "No" und "true" oder "false" angegeben werden (ohne Beachtung von Gro�-/Kleinschreibung).
 * Ein leerer Wert eines existierenden Schl�ssels wird als FALSE und ein numerischer Wert als TRUE interpretiert, wenn sein Zahlenwert ungleich 0 (zero) ist.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return bool - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
bool GetGlobalConfigBool(string section, string key, bool defaultValue=false) {
   defaultValue = defaultValue!=0;

   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return(false);
   return(GetIniBool(globalConfig, section, key, defaultValue));
}


/**
 * Gibt den Konfigurationswert einer .ini-Datei als Boolean zur�ck.
 *
 * Die Strings "1", "true", "yes" und "on" sowie numerische String ungleich 0 (zero) werden als TRUE, alle anderen als FALSE interpretiert. Gro�-/Kleinschreibung
 * wird nicht unterschieden. Leading/trailing White-Space und dem Konfigurationswert folgende Kommentare werden ignoriert. Unscharfe Rechtschreibfehler werden
 * erkannt und entsprechend interpretiert (Ziffer 0 statt gro�em Buchstaben O und umgekehrt).
 *
 * @param  string fileName     - Name der .ini-Datei
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return bool - interpretierter Konfigurationswert
 */
bool GetIniBool(string fileName, string section, string key, bool defaultValue=false) {
   defaultValue = defaultValue!=0;

   string value = GetIniString(fileName, section, key, defaultValue);   // Der DefaultValue wird automatisch in einen String gecastet.

   if (value == "" )      return( false);
   if (value == "0")      return( false);
   if (value == "1")      return( true );
   if (value == "O")      return(_false(debug("GetIniBool(1)  ["+ section +"]->"+ key +" = \""+ value +"\" (value is capital letter O, assumed to be zero)")));

   string lValue = StringToLower(value);
   if (lValue == "on"   ) return( true );
   if (lValue == "off"  ) return( false);
   if (lValue == "0n"   ) return(_true (debug("GetIniBool(2)  ["+ section +"]->"+ key +" = \""+ value +"\" (value starts with zero, assumed to be capital letter O)")));
   if (lValue == "0ff"  ) return(_false(debug("GetIniBool(3)  ["+ section +"]->"+ key +" = \""+ value +"\" (value starts with zero, assumed to be capital letter O)")));

   if (lValue == "true" ) return( true );
   if (lValue == "false") return( false);

   if (lValue == "yes"  ) return( true );
   if (lValue == "no"   ) return( false);
   if (lValue == "n0"   ) return(_false(debug("GetIniBool(4)  ["+ section +"]->"+ key +" = \""+ value +"\" (value ends with zero, assumed to be capital letter O)")));

   if (StringIsNumeric(value))
      return(StrToDouble(value) != 0);
   return(false);
}


/**
 * Gibt einen Konfigurationswert einer .ini-Datei als Integer zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string fileName     - Name der .ini-Datei
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return int - Konfigurationswert (der Konfiguration folgende Nicht-Digits werden ignoriert)
 */
int GetIniInt(string fileName, string section, string key, int defaultValue=0) {
   int marker = -1234567890;                                         // rarely found value
   int value  = GetPrivateProfileIntA(section, key, marker, fileName);

   if (value != marker)
      return(value);
                                                                     // GetPrivateProfileInt() �bernimmt auch dann den angegebenen Default-Value, wenn der Schl�ssel existiert,
   if (IsIniKey(fileName, section, key))                             // der Konfigurationswert jedoch leer (ein Leerstring) ist. Dies wird hier korrigiert.
      return(0);
   return(defaultValue);
}


/**
 * Gibt einen Konfigurationswert einer .ini-Datei als Double zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string fileName     - Name der .ini-Datei
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return double - Konfigurationswert (der Konfiguration folgende nicht-numerische Zeichen werden ignoriert)
 */
double GetIniDouble(string fileName, string section, string key, double defaultValue=0) {
   string value = GetRawIniString(fileName, section, key, DoubleToStr(defaultValue, 8));
   return(StrToDouble(value));
}


/**
 * Gibt einen Konfigurationswert als Double zur�ck. Dabei werden die globale und die lokale Konfiguration der MetaTrader-Installation durchsucht,
 * wobei die lokale eine h�here Priorit�t als die globale Konfiguration hat. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return double - Konfigurationswert (der Konfiguration folgende nicht-numerische Zeichen werden ignoriert)
 */
double GetConfigDouble(string section, string key, double defaultValue=0) {
   // Es ist schneller, immer globale und lokale Konfiguration auszuwerten (intern jeweils nur ein Aufruf von GetPrivateProfileString()).
   double value = GetGlobalConfigDouble(section, key, defaultValue);
          value = GetLocalConfigDouble (section, key, value       );
   return(value);
}


/**
 * Gibt einen lokalen Konfigurationswert als Double zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return double - Konfigurationswert (der Konfiguration folgende nicht-numerische Zeichen werden ignoriert)
 */
double GetLocalConfigDouble(string section, string key, double defaultValue=0) {
   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return(NULL);
   return(GetIniDouble(localConfig, section, key, defaultValue));
}


/**
 * Gibt einen globalen Konfigurationswert als Double zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return double - Konfigurationswert (der Konfiguration folgende nicht-numerische Zeichen werden ignoriert)
 */
double GetGlobalConfigDouble(string section, string key, double defaultValue=0) {
   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return(NULL);
   return(GetIniDouble(globalConfig, section, key, defaultValue));
}


/**
 * Gibt einen Konfigurationswert als Integer zur�ck.  Dabei werden die globale und die lokale Konfiguration der MetaTrader-Installation durchsucht,
 * wobei die lokale eine h�here Priorit�t als die globale Konfiguration hat. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return int - Konfigurationswert (der Konfiguration folgende Nicht-Digits werden ignoriert)
 */
int GetConfigInt(string section, string key, int defaultValue=0) {
   // Es ist schneller, immer globale und lokale Konfiguration auszuwerten (intern jeweils nur ein Aufruf von GetPrivateProfileInt()).
   int value = GetGlobalConfigInt(section, key, defaultValue);
       value = GetLocalConfigInt (section, key, value       );
   return(value);
}


/**
 * Gibt einen lokalen Konfigurationswert als Integer zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return int - Konfigurationswert (der Konfiguration folgende Nicht-Digits werden ignoriert)
 */
int GetLocalConfigInt(string section, string key, int defaultValue=0) {
   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return(NULL);
   return(GetIniInt(localConfig, section, key, defaultValue));
}


/**
 * Gibt einen globalen Konfigurationswert als Integer zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als 0 (zero) zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return int - Konfigurationswert (der Konfiguration folgende Nicht-Digits werden ignoriert)
 */
int GetGlobalConfigInt(string section, string key, int defaultValue=0) {
   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return(NULL);
   return(GetIniInt(globalConfig, section, key, defaultValue));
}


/**
 * Gibt einen Konfigurationswert einer .ini-Datei als String zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string fileName     - Name der .ini-Datei
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - Konfigurationswert oder Leerstring, falls ein Fehler auftrat (der Konfiguration folgende Kommentare werden ignoriert)
 */
string GetIniString(string fileName, string section, string key, string defaultValue="") {
   string marker = "~^#";                                            // rarely found string
   string value  = GetRawIniString(fileName, section, key, marker);

   // Kommentar aus dem Config-Value, nicht jedoch aus dem �bergebenen Default-Value entfernen (falls zutreffend)
   if (value != marker) {
      int pos = StringFind(value, ";");                              // Kommentare entfernen
      if (pos >= 0) value = StringTrimRight(StringLeft(value, pos));
   }
   else if (!IsIniKey(fileName, section, key)) {                     // der seltene Marker reduziert dieses zus�tzliche Lookup auf ein absolutes Minimum
      value = defaultValue;                                          // Schl�ssel existiert nicht, Default-Value zur�ckgeben
   }
   return(value);
}


/**
 * Gibt einen Konfigurationswert als String zur�ck.  Dabei werden die globale und die lokale Konfiguration der MetaTrader-Installation durchsucht,
 * wobei die lokale eine h�here Priorit�t als die globale Konfiguration hat. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
string GetConfigString(string section, string key, string defaultValue="") {
   // Es ist schneller, immer globale und lokale Konfiguration auszuwerten (intern jeweils nur ein Aufruf von GetPrivateProfileString()).
   string value = GetGlobalConfigString(section, key, defaultValue);
          value = GetLocalConfigString (section, key, value       );
   return(value);
}


/**
 * Gibt einen lokalen Konfigurationswert als String zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
string GetLocalConfigString(string section, string key, string defaultValue="") {
   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return("");
   return(GetIniString(localConfig, section, key, defaultValue));
}


/**
 * Gibt einen globalen Konfigurationswert als String zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - Konfigurationswert (der Konfiguration folgende Kommentare werden ignoriert)
 */
string GetGlobalConfigString(string section, string key, string defaultValue="") {
   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return("");
   return(GetIniString(globalConfig, section, key, defaultValue));
}


/**
 * Gibt einen Konfigurationswert als String zur�ck. Dabei werden die globale als auch die lokale Konfiguration der MetaTrader-Installation
 * durchsucht. Lokale Konfigurationswerte haben eine h�here Priorit�t als globale Werte. Ein leerer Wert eines existierenden Schl�ssels wird
 * als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - unver�nderter Konfigurationswert oder Leerstring, falls ein Fehler auftrat (ggf. mit Konfigurationskommentar)
 */
string GetRawConfigString(string section, string key, string defaultValue="") {
   // Es ist schneller, immer globale und lokale Konfiguration auszuwerten (intern jeweils nur ein Aufruf von GetPrivateProfileString()).
   string value = GetRawGlobalConfigString(section, key, defaultValue);
          value = GetRawLocalConfigString (section, key, value       );
   return(value);
}


/**
 * Gibt einen lokalen Konfigurationswert als String zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - unver�nderter Konfigurationswert oder Leerstring, falls ein Fehler auftrat (ggf. mit Konfigurationskommentar)
 */
string GetRawLocalConfigString(string section, string key, string defaultValue="") {
   string localConfig = GetLocalConfigPath();
      if (localConfig == "") return("");
   return(GetRawIniString(localConfig, section, key, defaultValue));
}


/**
 * Gibt einen globalen Konfigurationswert als String zur�ck. Ein leerer Wert eines existierenden Schl�ssels wird als Leerstring zur�ckgegeben.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - R�ckgabewert, falls der angegebene Schl�ssel nicht existiert
 *
 * @return string - unver�nderter Konfigurationswert oder Leerstring, falls ein Fehler auftrat (ggf. mit Konfigurationskommentar)
 */
string GetRawGlobalConfigString(string section, string key, string defaultValue="") {
   string globalConfig = GetGlobalConfigPath();
      if (globalConfig == "") return("");
   return(GetRawIniString(globalConfig, section, key, defaultValue));
}


/**
 * L�scht einen Schl�ssel eines Abschnitts einer .ini-Datei.
 *
 * @param  string fileName - Name der .ini-Datei
 * @param  string section  - Abschnitt des Schl�ssels
 * @param  string key      - zu l�schender Schl�ssel
 *
 * @return bool - Erfolgsstatus
 */
bool DeleteIniKey(string fileName, string section, string key) {
   string sNull;
   if (!WritePrivateProfileStringA(section, key, sNull, fileName))
      return(!catch("DeleteIniKey(1)->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=NULL, fileName=\""+ fileName +"\")", ERR_WIN32_ERROR));
   return(true);
}


/**
 * Gibt den Kurznamen der Firma des aktuellen Accounts zur�ck. Der Name wird aus dem Namen des Account-Servers und
 * nicht aus dem R�ckgabewert von AccountCompany() ermittelt.
 *
 * @return string - Kurzname oder Leerstring, falls ein Fehler auftrat
 */
string ShortAccountCompany() {
   string server = GetServerName(); if (!StringLen(server)) return(_EMPTY_STR(SetLastError(stdlib.GetLastError())));
          server = StringToLower(server);

   if (StringStartsWith(server, "alpari-"            )) return(AC.Alpari          );
   if (StringStartsWith(server, "alparibroker-"      )) return(AC.Alpari          );
   if (StringStartsWith(server, "alpariuk-"          )) return(AC.Alpari          );
   if (StringStartsWith(server, "alparius-"          )) return(AC.Alpari          );
   if (StringStartsWith(server, "apbgtrading-"       )) return(AC.APBG            );
   if (StringStartsWith(server, "atcbrokers-"        )) return(AC.ATC             );
   if (StringStartsWith(server, "atcbrokersest-"     )) return(AC.ATC             );
   if (StringStartsWith(server, "atcbrokersliq1-"    )) return(AC.ATC             );
   if (StringStartsWith(server, "axitrader-"         )) return(AC.AxiTrader       );
   if (StringStartsWith(server, "axitraderusa-"      )) return(AC.AxiTrader       );
   if (StringStartsWith(server, "broco-"             )) return(AC.BroCo           );
   if (StringStartsWith(server, "brocoinvestments-"  )) return(AC.BroCo           );
   if (StringStartsWith(server, "cmap-"              )) return(AC.IC_Markets      );     // demo
   if (StringStartsWith(server, "collectivefx-"      )) return(AC.CollectiveFX    );
   if (StringStartsWith(server, "dukascopy-"         )) return(AC.Dukascopy       );
   if (StringStartsWith(server, "easyforex-"         )) return(AC.EasyForex       );
   if (StringStartsWith(server, "finfx-"             )) return(AC.FinFX           );
   if (StringStartsWith(server, "forex-"             )) return(AC.Forex_Ltd       );
   if (StringStartsWith(server, "forexbaltic-"       )) return(AC.FB_Capital      );
   if (StringStartsWith(server, "fxopen-"            )) return(AC.FXOpen          );
   if (StringStartsWith(server, "fxprimus-"          )) return(AC.FX_Primus       );
   if (StringStartsWith(server, "fxpro.com-"         )) return(AC.FxPro           );
   if (StringStartsWith(server, "fxdd-"              )) return(AC.FXDD            );
   if (StringStartsWith(server, "gci-"               )) return(AC.GCI             );
   if (StringStartsWith(server, "gcmfx-"             )) return(AC.Gallant         );
   if (StringStartsWith(server, "gftforex-"          )) return(AC.GFT             );
   if (StringStartsWith(server, "globalprime-"       )) return(AC.Global_Prime    );
   if (StringStartsWith(server, "icmarkets-"         )) return(AC.IC_Markets      );
   if (StringStartsWith(server, "inovatrade-"        )) return(AC.InovaTrade      );
   if (StringStartsWith(server, "integral-"          )) return(AC.Global_Prime    );     // demo
   if (StringStartsWith(server, "investorseurope-"   )) return(AC.Investors_Europe);
   if (StringStartsWith(server, "jfd-demo"           )) return(AC.JFD_Brokers     );
   if (StringStartsWith(server, "jfd-live"           )) return(AC.JFD_Brokers     );
   if (StringStartsWith(server, "liteforex-"         )) return(AC.LiteForex       );
   if (StringStartsWith(server, "londoncapitalgr-"   )) return(AC.London_Capital  );
   if (StringStartsWith(server, "londoncapitalgroup-")) return(AC.London_Capital  );
   if (StringStartsWith(server, "mbtrading-"         )) return(AC.MB_Trading      );
   if (StringStartsWith(server, "metaquotes-"        )) return(AC.MetaQuotes      );
   if (StringStartsWith(server, "migbank-"           )) return(AC.MIG             );
   if (StringStartsWith(server, "myfx-"              )) return(AC.MyFX            );
   if (StringStartsWith(server, "oanda-"             )) return(AC.Oanda           );
   if (StringStartsWith(server, "pepperstone-"       )) return(AC.Pepperstone     );
   if (StringStartsWith(server, "primexm-"           )) return(AC.PrimeXM         );
   if (StringStartsWith(server, "sig-"               )) return(AC.LiteForex       );
   if (StringStartsWith(server, "sts-"               )) return(AC.STS             );
   if (StringStartsWith(server, "teletrade-"         )) return(AC.TeleTrade       );
   if (StringStartsWith(server, "teletradecy-"       )) return(AC.TeleTrade       );

   warn("ShortAccountCompany(1)  unknown server name = \""+ server +"\"");
   return(AccountCompany());
}


/**
 * Gibt die Company-ID einer AccountCompany zur�ck.
 *
 * @param string shortName - Kurzname einer AccountCompany
 *
 * @return int - Company-ID oder NULL, falls der �bergebene Wert keine bekannte AccountCompany darstellt
 */
int AccountCompanyId(string shortName) {
   if (!StringLen(shortName))
      return(NULL);

   shortName = StringToUpper(shortName);

   switch (StringGetChar(shortName, 0)) {
      case 'A': if (shortName == StringToUpper(AC.Alpari          )) return(AC_ID.Alpari          );
                if (shortName == StringToUpper(AC.APBG            )) return(AC_ID.APBG            );
                if (shortName == StringToUpper(AC.ATC             )) return(AC_ID.ATC             );
                if (shortName == StringToUpper(AC.AxiTrader       )) return(AC_ID.AxiTrader       );
                break;

      case 'B': if (shortName == StringToUpper(AC.BroCo           )) return(AC_ID.BroCo           );
                break;

      case 'C': if (shortName == StringToUpper(AC.CollectiveFX    )) return(AC_ID.CollectiveFX    );
                break;

      case 'D': if (shortName == StringToUpper(AC.Dukascopy       )) return(AC_ID.Dukascopy       );
                break;

      case 'E': if (shortName == StringToUpper(AC.EasyForex       )) return(AC_ID.EasyForex       );
                break;

      case 'F': if (shortName == StringToUpper(AC.FB_Capital      )) return(AC_ID.FB_Capital      );
                if (shortName == StringToUpper(AC.FinFX           )) return(AC_ID.FinFX           );
                if (shortName == StringToUpper(AC.Forex_Ltd       )) return(AC_ID.Forex_Ltd       );
                if (shortName == StringToUpper(AC.FX_Primus       )) return(AC_ID.FX_Primus       );
                if (shortName == StringToUpper(AC.FXDD            )) return(AC_ID.FXDD            );
                if (shortName == StringToUpper(AC.FXOpen          )) return(AC_ID.FXOpen          );
                if (shortName == StringToUpper(AC.FxPro           )) return(AC_ID.FxPro           );
                break;

      case 'G': if (shortName == StringToUpper(AC.Gallant         )) return(AC_ID.Gallant         );
                if (shortName == StringToUpper(AC.GCI             )) return(AC_ID.GCI             );
                if (shortName == StringToUpper(AC.GFT             )) return(AC_ID.GFT             );
                if (shortName == StringToUpper(AC.Global_Prime    )) return(AC_ID.Global_Prime    );
                break;

      case 'H': break;

      case 'I': if (shortName == StringToUpper(AC.IC_Markets      )) return(AC_ID.IC_Markets      );
                if (shortName == StringToUpper(AC.InovaTrade      )) return(AC_ID.InovaTrade      );
                if (shortName == StringToUpper(AC.Investors_Europe)) return(AC_ID.Investors_Europe);
                break;

      case 'J': if (shortName == StringToUpper(AC.JFD_Brokers     )) return(AC_ID.JFD_Brokers     );
                break;

      case 'K': break;

      case 'L': if (shortName == StringToUpper(AC.LiteForex       )) return(AC_ID.LiteForex       );
                if (shortName == StringToUpper(AC.London_Capital  )) return(AC_ID.London_Capital  );
                break;

      case 'M': if (shortName == StringToUpper(AC.MB_Trading      )) return(AC_ID.MB_Trading      );
                if (shortName == StringToUpper(AC.MetaQuotes      )) return(AC_ID.MetaQuotes      );
                if (shortName == StringToUpper(AC.MIG             )) return(AC_ID.MIG             );
                if (shortName == StringToUpper(AC.MyFX            )) return(AC_ID.MyFX            );
                break;

      case 'N': break;

      case 'O': if (shortName == StringToUpper(AC.Oanda           )) return(AC_ID.Oanda           );
                break;

      case 'P': if (shortName == StringToUpper(AC.Pepperstone     )) return(AC_ID.Pepperstone     );
                if (shortName == StringToUpper(AC.PrimeXM         )) return(AC_ID.PrimeXM         );
                break;

      case 'Q': break;
      case 'R': break;

      case 'S': if (shortName == StringToUpper(AC.SimpleTrader    )) return(AC_ID.SimpleTrader    );
                if (shortName == StringToUpper(AC.STS             )) return(AC_ID.STS             );
                break;

      case 'T': if (shortName == StringToUpper(AC.TeleTrade       )) return(AC_ID.TeleTrade       );
                break;

      case 'U': break;
      case 'V': break;
      case 'W': break;
      case 'X': break;
      case 'Y': break;
      case 'Z': break;
   }

   return(NULL);
}


/**
 * Gibt den Kurznamen der Firma mit der �bergebenen Company-ID zur�ck.
 *
 * @param int id - Company-ID
 *
 * @return string - Kurzname oder Leerstring, falls die �bergebene ID unbekannt ist
 */
string ShortAccountCompanyFromId(int id) {
   switch (id) {
      case AC_ID.Alpari          : return(AC.Alpari          );
      case AC_ID.APBG            : return(AC.APBG            );
      case AC_ID.ATC             : return(AC.ATC             );
      case AC_ID.AxiTrader       : return(AC.AxiTrader       );
      case AC_ID.BroCo           : return(AC.BroCo           );
      case AC_ID.CollectiveFX    : return(AC.CollectiveFX    );
      case AC_ID.Dukascopy       : return(AC.Dukascopy       );
      case AC_ID.EasyForex       : return(AC.EasyForex       );
      case AC_ID.FB_Capital      : return(AC.FB_Capital      );
      case AC_ID.FinFX           : return(AC.FinFX           );
      case AC_ID.Forex_Ltd       : return(AC.Forex_Ltd       );
      case AC_ID.FX_Primus       : return(AC.FX_Primus       );
      case AC_ID.FXDD            : return(AC.FXDD            );
      case AC_ID.FXOpen          : return(AC.FXOpen          );
      case AC_ID.FxPro           : return(AC.FxPro           );
      case AC_ID.Gallant         : return(AC.Gallant         );
      case AC_ID.GCI             : return(AC.GCI             );
      case AC_ID.GFT             : return(AC.GFT             );
      case AC_ID.Global_Prime    : return(AC.Global_Prime    );
      case AC_ID.IC_Markets      : return(AC.IC_Markets      );
      case AC_ID.InovaTrade      : return(AC.InovaTrade      );
      case AC_ID.Investors_Europe: return(AC.Investors_Europe);
      case AC_ID.JFD_Brokers     : return(AC.JFD_Brokers     );
      case AC_ID.LiteForex       : return(AC.LiteForex       );
      case AC_ID.London_Capital  : return(AC.London_Capital  );
      case AC_ID.MB_Trading      : return(AC.MB_Trading      );
      case AC_ID.MetaQuotes      : return(AC.MetaQuotes      );
      case AC_ID.MIG             : return(AC.MIG             );
      case AC_ID.MyFX            : return(AC.MyFX            );
      case AC_ID.Oanda           : return(AC.Oanda           );
      case AC_ID.Pepperstone     : return(AC.Pepperstone     );
      case AC_ID.PrimeXM         : return(AC.PrimeXM         );
      case AC_ID.SimpleTrader    : return(AC.SimpleTrader    );
      case AC_ID.STS             : return(AC.STS             );
      case AC_ID.TeleTrade       : return(AC.TeleTrade       );
   }
   return("");
}


/**
 * Ob der �bergebene Wert einen bekannten Kurznamen einer AccountCompany darstellt.
 *
 * @param string value
 *
 * @return bool
 */
bool IsShortAccountCompany(string value) {
   return(AccountCompanyId(value) != 0);
}


/**
 * Gibt den Alias eines Accounts zur�ck.
 *
 * @param  string accountCompany
 * @param  int    accountNumber
 *
 * @return string - Alias oder Leerstring, falls der Account unbekannt ist
 */
string AccountAlias(string accountCompany, int accountNumber) {
   if (!StringLen(accountCompany)) return(_EMPTY_STR(catch("AccountAlias(1)  invalid parameter accountCompany = \"\"", ERR_INVALID_PARAMETER)));
   if (accountNumber <= 0)         return(_EMPTY_STR(catch("AccountAlias(2)  invalid parameter accountNumber = "+ accountNumber, ERR_INVALID_PARAMETER)));

   if (StringCompareI(accountCompany, AC.SimpleTrader)) {
      // SimpleTrader-Account
      switch (accountNumber) {
         case STA_ID.AlexProfit      : return(STA_ALIAS.AlexProfit      );
         case STA_ID.ASTA            : return(STA_ALIAS.ASTA            );
         case STA_ID.Caesar2         : return(STA_ALIAS.Caesar2         );
         case STA_ID.Caesar21        : return(STA_ALIAS.Caesar21        );
         case STA_ID.ConsistentProfit: return(STA_ALIAS.ConsistentProfit);
         case STA_ID.DayFox          : return(STA_ALIAS.DayFox          );
         case STA_ID.FXViper         : return(STA_ALIAS.FXViper         );
         case STA_ID.GCEdge          : return(STA_ALIAS.GCEdge          );
         case STA_ID.GoldStar        : return(STA_ALIAS.GoldStar        );
         case STA_ID.Kilimanjaro     : return(STA_ALIAS.Kilimanjaro     );
         case STA_ID.NovoLRfund      : return(STA_ALIAS.NovoLRfund      );
         case STA_ID.OverTrader      : return(STA_ALIAS.OverTrader      );
         case STA_ID.Ryan            : return(STA_ALIAS.Ryan            );
         case STA_ID.SmartScalper    : return(STA_ALIAS.SmartScalper    );
         case STA_ID.SmartTrader     : return(STA_ALIAS.SmartTrader     );
         case STA_ID.SteadyCapture   : return(STA_ALIAS.SteadyCapture   );
         case STA_ID.Twilight        : return(STA_ALIAS.Twilight        );
         case STA_ID.YenFortress     : return(STA_ALIAS.YenFortress     );
      }
   }
   else {
      // regul�rer Account
      string section = "Accounts";
      string key     = accountNumber +".alias";
      string value   = GetGlobalConfigString(section, key);
      if (StringLen(value) > 0)
         return(value);
   }

   return("");
}


/**
 * Gibt die Account-Nummer eines Accounts anhand seines Aliasses zur�ck.
 *
 * @param  string accountCompany
 * @param  string accountAlias
 *
 * @return int - Account-Nummer oder NULL, falls der Account unbekannt ist
 */
int AccountNumberFromAlias(string accountCompany, string accountAlias) {
   if (!StringLen(accountCompany)) return(_NULL(catch("AccountNumberFromAlias(1)  invalid parameter accountCompany = \"\"", ERR_INVALID_PARAMETER)));
   if (!StringLen(accountAlias))   return(_NULL(catch("AccountNumberFromAlias(2)  invalid parameter accountAlias = \"\"", ERR_INVALID_PARAMETER)));

   if (StringCompareI(accountCompany, AC.SimpleTrader)) {
      // SimpleTrader-Account
      accountAlias = StringToLower(accountAlias);

      if (accountAlias == StringToLower(STA_ALIAS.AlexProfit      )) return(STA_ID.AlexProfit      );
      if (accountAlias == StringToLower(STA_ALIAS.ASTA            )) return(STA_ID.ASTA            );
      if (accountAlias == StringToLower(STA_ALIAS.Caesar2         )) return(STA_ID.Caesar2         );
      if (accountAlias == StringToLower(STA_ALIAS.Caesar21        )) return(STA_ID.Caesar21        );
      if (accountAlias == StringToLower(STA_ALIAS.ConsistentProfit)) return(STA_ID.ConsistentProfit);
      if (accountAlias == StringToLower(STA_ALIAS.DayFox          )) return(STA_ID.DayFox          );
      if (accountAlias == StringToLower(STA_ALIAS.FXViper         )) return(STA_ID.FXViper         );
      if (accountAlias == StringToLower(STA_ALIAS.GCEdge          )) return(STA_ID.GCEdge          );
      if (accountAlias == StringToLower(STA_ALIAS.GoldStar        )) return(STA_ID.GoldStar        );
      if (accountAlias == StringToLower(STA_ALIAS.Kilimanjaro     )) return(STA_ID.Kilimanjaro     );
      if (accountAlias == StringToLower(STA_ALIAS.NovoLRfund      )) return(STA_ID.NovoLRfund      );
      if (accountAlias == StringToLower(STA_ALIAS.OverTrader      )) return(STA_ID.OverTrader      );
      if (accountAlias == StringToLower(STA_ALIAS.Ryan            )) return(STA_ID.Ryan            );
      if (accountAlias == StringToLower(STA_ALIAS.SmartScalper    )) return(STA_ID.SmartScalper    );
      if (accountAlias == StringToLower(STA_ALIAS.SmartTrader     )) return(STA_ID.SmartTrader     );
      if (accountAlias == StringToLower(STA_ALIAS.SteadyCapture   )) return(STA_ID.SteadyCapture   );
      if (accountAlias == StringToLower(STA_ALIAS.Twilight        )) return(STA_ID.Twilight        );
      if (accountAlias == StringToLower(STA_ALIAS.YenFortress     )) return(STA_ID.YenFortress     );
   }
   else {
      // regul�rer Account
      string file    = GetGlobalConfigPath();
      string section = "Accounts";
      string keys[], value, sAccount;
      int keysSize = GetIniKeys(file, section, keys);

      for (int i=0; i < keysSize; i++) {
         if (StringEndsWithI(keys[i], ".alias")) {
            value = GetGlobalConfigString(section, keys[i]);
            if (StringCompareI(value, accountAlias)) {
               sAccount = StringTrimRight(StringLeft(keys[i], -6));
               value    = GetGlobalConfigString(section, sAccount +".company");
               if (StringCompareI(value, accountCompany)) {
                  if (StringIsDigit(sAccount))
                     return(StrToInteger(sAccount));
               }
            }
         }
      }
   }
   return(NULL);
}


/**
 * Vergleicht zwei Strings ohne Ber�cksichtigung von Gro�-/Kleinschreibung.
 *
 * @param  string string1
 * @param  string string2
 *
 * @return bool
 */
bool StringCompareI(string string1, string string2) {
   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error == ERR_NOT_INITIALIZED_STRING) {
         if (StringIsNull(string1)) return(StringIsNull(string2));
         if (StringIsNull(string2)) return(false);
      }
      catch("StringCompareI(1)", error);
   }
   return(StringToUpper(string1) == StringToUpper(string2));
}


/**
 * Pr�ft, ob ein String einen Substring enth�lt. Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object    - zu durchsuchender String
 * @param  string substring - zu suchender Substring
 *
 * @return bool
 */
bool StringContains(string object, string substring) {
   if (!StringLen(substring))
      return(!catch("StringContains()  illegal parameter substring = "+ DoubleQuoteStr(substring), ERR_INVALID_PARAMETER));
   return(StringFind(object, substring) != -1);
}


/**
 * Pr�ft, ob ein String einen Substring enth�lt. Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object    - zu durchsuchender String
 * @param  string substring - zu suchender Substring
 *
 * @return bool
 */
bool StringContainsI(string object, string substring) {
   if (!StringLen(substring))
      return(!catch("StringContainsI()  illegal parameter substring = "+ DoubleQuoteStr(substring), ERR_INVALID_PARAMETER));
   return(StringFind(StringToUpper(object), StringToUpper(substring)) != -1);
}


/**
 * Durchsucht einen String vom Ende aus nach einem Substring und gibt dessen Position zur�ck.
 *
 * @param  string object - zu durchsuchender String
 * @param  string search - zu suchender Substring
 *
 * @return int - letzte Position des Substrings oder -1, wenn der Substring nicht gefunden wurde
 */
int StringFindR(string object, string search) {
   int lenObject = StringLen(object),
       lastFound = -1,
       result    =  0;

   for (int i=0; i < lenObject; i++) {
      result = StringFind(object, search, i);
      if (result == -1)
         break;
      lastFound = result;
   }
   return(lastFound);
}


/**
 * Konvertiert eine Farbe in ihre HTML-Repr�sentation.
 *
 * @param  color rgb
 *
 * @return string - HTML-Farbwert
 *
 * Beispiel: ColorToHtmlStr(C'255,255,255') => "#FFFFFF"
 */
string ColorToHtmlStr(color rgb) {
   int red   = rgb & 0x0000FF;
   int green = rgb & 0x00FF00;
   int blue  = rgb & 0xFF0000;

   int value = red<<16 + green + blue>>16;   // rot und blau vertauschen, um IntToHexStr() benutzen zu k�nnen

   return(StringConcatenate("#", StringRight(IntToHexStr(value), 6)));
}


/**
 * Konvertiert einen MQL-Farbcode in seine String-Repr�sentation, z.B. "DimGray", "Red" oder "0,255,255".
 *
 * @param  color value
 *
 * @return string - String-Token oder Leerstring, falls der �bergebene Wert kein g�ltiger Farbcode ist.
 */
string ColorToStr(color value)   {
   if (value == 0xFF000000)                                          // aus CLR_NONE = 0xFFFFFFFF macht das Terminal nach Recompilation oder Deserialisierung
      value = CLR_NONE;                                              // u.U. 0xFF000000 (entspricht Schwarz)
   if (value < CLR_NONE || value > C'255,255,255')
      return(_EMPTY_STR(catch("ColorToStr(1)  invalid parameter value = "+ value +" (not a color)", ERR_INVALID_PARAMETER)));

   if (value == CLR_NONE) return("CLR_NONE"         );
   if (value == 0xFFF8F0) return("AliceBlue"        );
   if (value == 0xD7EBFA) return("AntiqueWhite"     );
   if (value == 0xFFFF00) return("Aqua"             );
   if (value == 0xD4FF7F) return("Aquamarine"       );
   if (value == 0xDCF5F5) return("Beige"            );
   if (value == 0xC4E4FF) return("Bisque"           );
   if (value == 0x000000) return("Black"            );
   if (value == 0xCDEBFF) return("BlanchedAlmond"   );
   if (value == 0xFF0000) return("Blue"             );
   if (value == 0xE22B8A) return("BlueViolet"       );
   if (value == 0x2A2AA5) return("Brown"            );
   if (value == 0x87B8DE) return("BurlyWood"        );
   if (value == 0xA09E5F) return("CadetBlue"        );
   if (value == 0x00FF7F) return("Chartreuse"       );
   if (value == 0x1E69D2) return("Chocolate"        );
   if (value == 0x507FFF) return("Coral"            );
   if (value == 0xED9564) return("CornflowerBlue"   );
   if (value == 0xDCF8FF) return("Cornsilk"         );
   if (value == 0x3C14DC) return("Crimson"          );
   if (value == 0x8B0000) return("DarkBlue"         );
   if (value == 0x0B86B8) return("DarkGoldenrod"    );
   if (value == 0xA9A9A9) return("DarkGray"         );
   if (value == 0x006400) return("DarkGreen"        );
   if (value == 0x6BB7BD) return("DarkKhaki"        );
   if (value == 0x2F6B55) return("DarkOliveGreen"   );
   if (value == 0x008CFF) return("DarkOrange"       );
   if (value == 0xCC3299) return("DarkOrchid"       );
   if (value == 0x7A96E9) return("DarkSalmon"       );
   if (value == 0x8BBC8F) return("DarkSeaGreen"     );
   if (value == 0x8B3D48) return("DarkSlateBlue"    );
   if (value == 0x4F4F2F) return("DarkSlateGray"    );
   if (value == 0xD1CE00) return("DarkTurquoise"    );
   if (value == 0xD30094) return("DarkViolet"       );
   if (value == 0x9314FF) return("DeepPink"         );
   if (value == 0xFFBF00) return("DeepSkyBlue"      );
   if (value == 0x696969) return("DimGray"          );
   if (value == 0xFF901E) return("DodgerBlue"       );
   if (value == 0x2222B2) return("FireBrick"        );
   if (value == 0x228B22) return("ForestGreen"      );
   if (value == 0xDCDCDC) return("Gainsboro"        );
   if (value == 0x00D7FF) return("Gold"             );
   if (value == 0x20A5DA) return("Goldenrod"        );
   if (value == 0x808080) return("Gray"             );
   if (value == 0x008000) return("Green"            );
   if (value == 0x2FFFAD) return("GreenYellow"      );
   if (value == 0xF0FFF0) return("Honeydew"         );
   if (value == 0xB469FF) return("HotPink"          );
   if (value == 0x5C5CCD) return("IndianRed"        );
   if (value == 0x82004B) return("Indigo"           );
   if (value == 0xF0FFFF) return("Ivory"            );
   if (value == 0x8CE6F0) return("Khaki"            );
   if (value == 0xFAE6E6) return("Lavender"         );
   if (value == 0xF5F0FF) return("LavenderBlush"    );
   if (value == 0x00FC7C) return("LawnGreen"        );
   if (value == 0xCDFAFF) return("LemonChiffon"     );
   if (value == 0xE6D8AD) return("LightBlue"        );
   if (value == 0x8080F0) return("LightCoral"       );
   if (value == 0xFFFFE0) return("LightCyan"        );
   if (value == 0xD2FAFA) return("LightGoldenrod"   );
   if (value == 0xD3D3D3) return("LightGray"        );
   if (value == 0x90EE90) return("LightGreen"       );
   if (value == 0xC1B6FF) return("LightPink"        );
   if (value == 0x7AA0FF) return("LightSalmon"      );
   if (value == 0xAAB220) return("LightSeaGreen"    );
   if (value == 0xFACE87) return("LightSkyBlue"     );
   if (value == 0x998877) return("LightSlateGray"   );
   if (value == 0xDEC4B0) return("LightSteelBlue"   );
   if (value == 0xE0FFFF) return("LightYellow"      );
   if (value == 0x00FF00) return("Lime"             );
   if (value == 0x32CD32) return("LimeGreen"        );
   if (value == 0xE6F0FA) return("Linen"            );
   if (value == 0xFF00FF) return("Magenta"          );
   if (value == 0x000080) return("Maroon"           );
   if (value == 0xAACD66) return("MediumAquamarine" );
   if (value == 0xCD0000) return("MediumBlue"       );
   if (value == 0xD355BA) return("MediumOrchid"     );
   if (value == 0xDB7093) return("MediumPurple"     );
   if (value == 0x71B33C) return("MediumSeaGreen"   );
   if (value == 0xEE687B) return("MediumSlateBlue"  );
   if (value == 0x9AFA00) return("MediumSpringGreen");
   if (value == 0xCCD148) return("MediumTurquoise"  );
   if (value == 0x8515C7) return("MediumVioletRed"  );
   if (value == 0x701919) return("MidnightBlue"     );
   if (value == 0xFAFFF5) return("MintCream"        );
   if (value == 0xE1E4FF) return("MistyRose"        );
   if (value == 0xB5E4FF) return("Moccasin"         );
   if (value == 0xADDEFF) return("NavajoWhite"      );
   if (value == 0x800000) return("Navy"             );
   if (value == 0xE6F5FD) return("OldLace"          );
   if (value == 0x008080) return("Olive"            );
   if (value == 0x238E6B) return("OliveDrab"        );
   if (value == 0x00A5FF) return("Orange"           );
   if (value == 0x0045FF) return("OrangeRed"        );
   if (value == 0xD670DA) return("Orchid"           );
   if (value == 0xAAE8EE) return("PaleGoldenrod"    );
   if (value == 0x98FB98) return("PaleGreen"        );
   if (value == 0xEEEEAF) return("PaleTurquoise"    );
   if (value == 0x9370DB) return("PaleVioletRed"    );
   if (value == 0xD5EFFF) return("PapayaWhip"       );
   if (value == 0xB9DAFF) return("PeachPuff"        );
   if (value == 0x3F85CD) return("Peru"             );
   if (value == 0xCBC0FF) return("Pink"             );
   if (value == 0xDDA0DD) return("Plum"             );
   if (value == 0xE6E0B0) return("PowderBlue"       );
   if (value == 0x800080) return("Purple"           );
   if (value == 0x0000FF) return("Red"              );
   if (value == 0x8F8FBC) return("RosyBrown"        );
   if (value == 0xE16941) return("RoyalBlue"        );
   if (value == 0x13458B) return("SaddleBrown"      );
   if (value == 0x7280FA) return("Salmon"           );
   if (value == 0x60A4F4) return("SandyBrown"       );
   if (value == 0x578B2E) return("SeaGreen"         );
   if (value == 0xEEF5FF) return("Seashell"         );
   if (value == 0x2D52A0) return("Sienna"           );
   if (value == 0xC0C0C0) return("Silver"           );
   if (value == 0xEBCE87) return("SkyBlue"          );
   if (value == 0xCD5A6A) return("SlateBlue"        );
   if (value == 0x908070) return("SlateGray"        );
   if (value == 0xFAFAFF) return("Snow"             );
   if (value == 0x7FFF00) return("SpringGreen"      );
   if (value == 0xB48246) return("SteelBlue"        );
   if (value == 0x8CB4D2) return("Tan"              );
   if (value == 0x808000) return("Teal"             );
   if (value == 0xD8BFD8) return("Thistle"          );
   if (value == 0x4763FF) return("Tomato"           );
   if (value == 0xD0E040) return("Turquoise"        );
   if (value == 0xEE82EE) return("Violet"           );
   if (value == 0xB3DEF5) return("Wheat"            );
   if (value == 0xFFFFFF) return("White"            );
   if (value == 0xF5F5F5) return("WhiteSmoke"       );
   if (value == 0x00FFFF) return("Yellow"           );
   if (value == 0x32CD9A) return("YellowGreen"      );

   return(ColorToRGBStr(value));
}


/**
 * Repeats a string.
 *
 * @param  string input - The string to be repeated.
 * @param  int    times - Number of times the input string should be repeated.
 *
 * @return string - the repeated string
 */
string StringRepeat(string input, int times) {
   if (times < 0)
      return(_EMPTY_STR(catch("StringRepeat()  invalid parameter times = "+ times, ERR_INVALID_PARAMETER)));

   if (times ==  0)       return("");
   if (!StringLen(input)) return("");

   string output = input;
   for (int i=1; i < times; i++) {
      output = StringConcatenate(output, input);
   }
   return(output);
}


/**
 * Gibt die eindeutige ID einer W�hrung zur�ck.
 *
 * @param  string currency - 3-stelliger W�hrungsbezeichner
 *
 * @return int - Currency-ID oder 0, falls ein Fehler auftrat
 */
int GetCurrencyId(string currency) {
   string value = StringToUpper(currency);

   if (value == C_AUD) return(CID_AUD);
   if (value == C_CAD) return(CID_CAD);
   if (value == C_CHF) return(CID_CHF);
   if (value == C_CNY) return(CID_CNY);
   if (value == C_CZK) return(CID_CZK);
   if (value == C_DKK) return(CID_DKK);
   if (value == C_EUR) return(CID_EUR);
   if (value == C_GBP) return(CID_GBP);
   if (value == C_HKD) return(CID_HKD);
   if (value == C_HRK) return(CID_HRK);
   if (value == C_HUF) return(CID_HUF);
   if (value == C_INR) return(CID_INR);
   if (value == C_JPY) return(CID_JPY);
   if (value == C_LTL) return(CID_LTL);
   if (value == C_LVL) return(CID_LVL);
   if (value == C_MXN) return(CID_MXN);
   if (value == C_NOK) return(CID_NOK);
   if (value == C_NZD) return(CID_NZD);
   if (value == C_PLN) return(CID_PLN);
   if (value == C_RUB) return(CID_RUB);
   if (value == C_SAR) return(CID_SAR);
   if (value == C_SEK) return(CID_SEK);
   if (value == C_SGD) return(CID_SGD);
   if (value == C_THB) return(CID_THB);
   if (value == C_TRY) return(CID_TRY);
   if (value == C_TWD) return(CID_TWD);
   if (value == C_USD) return(CID_USD);
   if (value == C_ZAR) return(CID_ZAR);

   return(_NULL(catch("GetCurrencyId(1)  unknown currency = \""+ currency +"\"", ERR_RUNTIME_ERROR)));
}


/**
 * Gibt den 3-stelligen Bezeichner einer W�hrungs-ID zur�ck.
 *
 * @param  int id - W�hrungs-ID
 *
 * @return string - W�hrungsbezeichner
 */
string GetCurrency(int id) {
   switch (id) {
      case CID_AUD: return(C_AUD);
      case CID_CAD: return(C_CAD);
      case CID_CHF: return(C_CHF);
      case CID_CNY: return(C_CNY);
      case CID_CZK: return(C_CZK);
      case CID_DKK: return(C_DKK);
      case CID_EUR: return(C_EUR);
      case CID_GBP: return(C_GBP);
      case CID_HKD: return(C_HKD);
      case CID_HRK: return(C_HRK);
      case CID_HUF: return(C_HUF);
      case CID_INR: return(C_INR);
      case CID_JPY: return(C_JPY);
      case CID_LTL: return(C_LTL);
      case CID_LVL: return(C_LVL);
      case CID_MXN: return(C_MXN);
      case CID_NOK: return(C_NOK);
      case CID_NZD: return(C_NZD);
      case CID_PLN: return(C_PLN);
      case CID_RUB: return(C_RUB);
      case CID_SAR: return(C_SAR);
      case CID_SEK: return(C_SEK);
      case CID_SGD: return(C_SGD);
      case CID_THB: return(C_THB);
      case CID_TRY: return(C_TRY);
      case CID_TWD: return(C_TWD);
      case CID_USD: return(C_USD);
      case CID_ZAR: return(C_ZAR);
   }
   return(_EMPTY_STR(catch("GetCurrency(1)  unknown currency id = "+ id, ERR_RUNTIME_ERROR)));
}


/**
 * Ob ein String einen g�ltigen W�hrungsbezeichner darstellt.
 *
 * @param  string value - Wert
 *
 * @return bool
 */
bool IsCurrency(string value) {
   value = StringToUpper(value);

   if (value == C_AUD) return(true);
   if (value == C_CAD) return(true);
   if (value == C_CHF) return(true);
   if (value == C_CNY) return(true);
   if (value == C_CZK) return(true);
   if (value == C_DKK) return(true);
   if (value == C_EUR) return(true);
   if (value == C_GBP) return(true);
   if (value == C_HKD) return(true);
   if (value == C_HRK) return(true);
   if (value == C_HUF) return(true);
   if (value == C_INR) return(true);
   if (value == C_JPY) return(true);
   if (value == C_LTL) return(true);
   if (value == C_LVL) return(true);
   if (value == C_MXN) return(true);
   if (value == C_NOK) return(true);
   if (value == C_NZD) return(true);
   if (value == C_PLN) return(true);
   if (value == C_RUB) return(true);
   if (value == C_SAR) return(true);
   if (value == C_SEK) return(true);
   if (value == C_SGD) return(true);
   if (value == C_THB) return(true);
   if (value == C_TRY) return(true);
   if (value == C_TWD) return(true);
   if (value == C_USD) return(true);
   if (value == C_ZAR) return(true);

   return(false);
}


/**
 * Ob der �bergebene Parameter eine "pending" Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsPendingTradeOperation(int value) {
   switch (value) {
      case OP_BUYLIMIT :
      case OP_SELLLIMIT:
      case OP_BUYSTOP  :
      case OP_SELLSTOP :
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsTradeOperation(int value) {
   switch (value) {
      case OP_BUY      :
      case OP_SELL     :
      case OP_BUYLIMIT :
      case OP_SELLLIMIT:
      case OP_BUYSTOP  :
      case OP_SELLSTOP :
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine Long-Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsLongTradeOperation(int value) {
   switch (value) {
      case OP_BUY     :
      case OP_BUYLIMIT:
      case OP_BUYSTOP :
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine Short-Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsShortTradeOperation(int value) {
   switch (value) {
      case OP_SELL     :
      case OP_SELLLIMIT:
      case OP_SELLSTOP :
         return(true);
   }
   return(false);
}


/**
 * Gibt die lesbare Konstante einer MessageBox-Command-ID zur�ck.
 *
 * @param  int cmd - Command-ID (entspricht dem gedr�ckten Messagebox-Button)
 *
 * @return string
 */
string MessageBoxCmdToStr(int cmd) {
   switch (cmd) {
      case IDOK      : return("IDOK"      );
      case IDCANCEL  : return("IDCANCEL"  );
      case IDABORT   : return("IDABORT"   );
      case IDRETRY   : return("IDRETRY"   );
      case IDIGNORE  : return("IDIGNORE"  );
      case IDYES     : return("IDYES"     );
      case IDNO      : return("IDNO"      );
      case IDCLOSE   : return("IDCLOSE"   );
      case IDHELP    : return("IDHELP"    );
      case IDTRYAGAIN: return("IDTRYAGAIN");
      case IDCONTINUE: return("IDCONTINUE");
   }
   return(_EMPTY_STR(catch("MessageBoxCmdToStr(1)  unknown message box command = "+ cmd, ERR_RUNTIME_ERROR)));
}


/**
 * Gibt den Integer-Wert eines OperationType-Bezeichners zur�ck.
 *
 * @param  string value
 *
 * @return int - OperationType-Code oder -1, wenn der Bezeichner ung�ltig ist (OP_UNDEFINED)
 */
int StrToOperationType(string value) {
   string str = StringToUpper(StringTrim(value));

   if (StringLen(str) == 1) {
      switch (StrToInteger(str)) {
         case OP_BUY      :
            if (str == "0")    return(OP_BUY      ); break;          // OP_BUY = 0: Sonderfall
         case OP_SELL     :    return(OP_SELL     );
         case OP_BUYLIMIT :    return(OP_BUYLIMIT );
         case OP_SELLLIMIT:    return(OP_SELLLIMIT);
         case OP_BUYSTOP  :    return(OP_BUYSTOP  );
         case OP_SELLSTOP :    return(OP_SELLSTOP );
         case OP_BALANCE  :    return(OP_BALANCE  );
         case OP_CREDIT   :    return(OP_CREDIT   );
      }
   }
   else {
      if (StringStartsWith(str, "OP_"))
         str = StringRight(str, -3);
      if (str == "BUY"       ) return(OP_BUY      );
      if (str == "SELL"      ) return(OP_SELL     );
      if (str == "BUYLIMIT"  ) return(OP_BUYLIMIT );
      if (str == "BUY LIMIT" ) return(OP_BUYLIMIT );
      if (str == "SELLLIMIT" ) return(OP_SELLLIMIT);
      if (str == "SELL LIMIT") return(OP_SELLLIMIT);
      if (str == "BUYSTOP"   ) return(OP_BUYSTOP  );
      if (str == "STOP BUY"  ) return(OP_BUYSTOP  );
      if (str == "SELLSTOP"  ) return(OP_SELLSTOP );
      if (str == "STOP SELL" ) return(OP_SELLSTOP );
      if (str == "BALANCE"   ) return(OP_BALANCE  );
      if (str == "CREDIT"    ) return(OP_CREDIT   );
   }

   if (__LOG) log("StrToOperationType(1)  invalid parameter value = \""+ value +"\" (not an operation type)", ERR_INVALID_PARAMETER);
   return(OP_UNDEFINED);
}


/**
 * Gibt die lesbare Konstante eines Operation-Types zur�ck.
 *
 * @param  int type - Operation-Type
 *
 * @return string
 */
string OperationTypeToStr(int type) {
   switch (type) {
      case OP_BUY      : return("OP_BUY"      );
      case OP_SELL     : return("OP_SELL"     );
      case OP_BUYLIMIT : return("OP_BUYLIMIT" );
      case OP_SELLLIMIT: return("OP_SELLLIMIT");
      case OP_BUYSTOP  : return("OP_BUYSTOP"  );
      case OP_SELLSTOP : return("OP_SELLSTOP" );
      case OP_BALANCE  : return("OP_BALANCE"  );
      case OP_CREDIT   : return("OP_CREDIT"   );
      case OP_UNDEFINED: return("OP_UNDEFINED");
   }
   return(_EMPTY_STR(catch("OperationTypeToStr(1)  invalid parameter type = "+ type +" (not an operation type)", ERR_INVALID_PARAMETER)));
}


/**
 * Alias
 */
string OrderTypeToStr(int type) {
   return(OperationTypeToStr(type));
}


/**
 * Gibt die Beschreibung eines Operation-Types zur�ck.
 *
 * @param  int type - Operation-Type
 *
 * @return string - Beschreibung oder Leerstring, falls ein Fehler auftrat
 */
string OperationTypeDescription(int type) {
   switch (type) {
      case OP_BUY      : return("Buy"       );
      case OP_SELL     : return("Sell"      );
      case OP_BUYLIMIT : return("Buy Limit" );
      case OP_SELLLIMIT: return("Sell Limit");
      case OP_BUYSTOP  : return("Stop Buy"  );
      case OP_SELLSTOP : return("Stop Sell" );
      case OP_BALANCE  : return("Balance"   );
      case OP_CREDIT   : return("Credit"    );
      case OP_UNDEFINED: return("undefined" );
   }
   return(_EMPTY_STR(catch("OperationTypeDescription(1)  invalid parameter type = "+ type +" (not an operation type)", ERR_INVALID_PARAMETER)));
}


/**
 * Alias
 */
string OrderTypeDescription(int type) {
   return(OperationTypeDescription(type));
}


/**
 * Gibt die lesbare Konstante eines TradeCommands zur�ck.
 *
 * @param  int cmd - TradeCommand
 *
 * @return string
 */
string TradeCommandToStr(int cmd) {
   switch (cmd) {
      case TC_LFX_ORDER_CREATE : return("TC_LFX_ORDER_CREATE" );
      case TC_LFX_ORDER_OPEN   : return("TC_LFX_ORDER_OPEN"   );
      case TC_LFX_ORDER_CLOSE  : return("TC_LFX_ORDER_CLOSE"  );
      case TC_LFX_ORDER_CLOSEBY: return("TC_LFX_ORDER_CLOSEBY");
      case TC_LFX_ORDER_HEDGE  : return("TC_LFX_ORDER_HEDGE"  );
      case TC_LFX_ORDER_MODIFY : return("TC_LFX_ORDER_MODIFY" );
      case TC_LFX_ORDER_DELETE : return("TC_LFX_ORDER_DELETE" );
   }
   return(_EMPTY_STR(catch("TradeCommandToStr(1)  invalid parameter cmd = "+ cmd +" (not a trade command )", ERR_INVALID_PARAMETER)));
}


/**
 * Formatiert einen numerischen Wert im angegebenen Format und gibt den resultierenden String zur�ck.
 * The basic mask is "n" or "n.d" where n is the number of digits to the left and d is the number of digits to the right of the decimal point.
 *
 * Mask parameters:
 *
 *   n        = number of digits to the left of the decimal point, e.g. NumberToStr(123.456, "5") => "123"
 *   n.d      = number of left and right digits, e.g. NumberToStr(123.456, "5.2") => "123.45"
 *   n.       = number of left and all right digits, e.g. NumberToStr(123.456, "2.") => "23.456"
 *    .d      = all left and number of right digits, e.g. NumberToStr(123.456, ".2") => "123.45"
 *    .d'     = all left and number of right digits plus 1 additional subpip digit, e.g. NumberToStr(123.45678, ".4'") => "123.4567'8"
 *    .d+     = + anywhere right of .d in mask: all left and minimum number of right digits, e.g. NumberToStr(123.456, ".2+") => "123.456"
 *  +n.d      = + anywhere left of n. in mask: plus sign for positive values
 *    R       = round result in the last displayed digit, e.g. NumberToStr(123.456, "R3.2") => "123.46" or NumberToStr(123.7, "R3") => "124"
 *    ;       = Separatoren tauschen (Europ�isches Format), e.g. NumberToStr(123456.789, "6.2;") => "123456,78"
 *    ,       = Tausender-Separatoren einf�gen, e.g. NumberToStr(123456.789, "6.2,") => "123,456.78"
 *    ,<char> = Tausender-Separatoren einf�gen und auf <char> setzen, e.g. NumberToStr(123456.789, ", 6.2") => "123 456.78"
 *
 * @param  double value
 * @param  string mask
 *
 * @return string - formatierter Wert oder Leerstring, falls ein Fehler auftrat
 */
string NumberToStr(double value, string mask) {
   string sNumber = value;
   if (StringGetChar(sNumber, 3) == '#')                             // "-1.#IND0000" => NaN
      return(sNumber);                                               // "-1.#INF0000" => Infinite


   // --- Beginn Maske parsen -------------------------
   int maskLen = StringLen(mask);

   // zu allererst Separatorenformat erkennen
   bool swapSeparators = (StringFind(mask, ";") > -1);
      string sepThousand=",", sepDecimal=".";
      if (swapSeparators) {
         sepThousand = ".";
         sepDecimal  = ",";
      }
      int sepPos = StringFind(mask, ",");
   bool separators = (sepPos > -1);
      if (separators) /*&&*/ if (sepPos+1 < maskLen) {
         sepThousand = StringSubstr(mask, sepPos+1, 1);  // user-spezifischen 1000-Separator auslesen und aus Maske l�schen
         mask        = StringConcatenate(StringSubstr(mask, 0, sepPos+1), StringSubstr(mask, sepPos+2));
      }

   // white space entfernen
   mask    = StringReplace(mask, " ", "");
   maskLen = StringLen(mask);

   // Position des Dezimalpunktes
   int  dotPos   = StringFind(mask, ".");
   bool dotGiven = (dotPos > -1);
   if (!dotGiven)
      dotPos = maskLen;

   // Anzahl der linken Stellen
   int char, nLeft;
   bool nDigit;
   for (int i=0; i < dotPos; i++) {
      char = StringGetChar(mask, i);
      if ('0' <= char) /*&&*/ if (char <= '9') {
         nLeft = 10*nLeft + char-'0';
         nDigit = true;
      }
   }
   if (!nDigit) nLeft = -1;

   // Anzahl der rechten Stellen
   int nRight, nSubpip;
   if (dotGiven) {
      nDigit = false;
      for (i=dotPos+1; i < maskLen; i++) {
         char = StringGetChar(mask, i);
         if ('0' <= char && char <= '9') {
            nRight = 10*nRight + char-'0';
            nDigit = true;
         }
         else if (nDigit && char==39) {      // 39 => '
            nSubpip = nRight;
            continue;
         }
         else {
            if  (char == '+') nRight = Max(nRight + (nSubpip>0), CountDecimals(value));   // (int) bool
            else if (!nDigit) nRight = CountDecimals(value);
            break;
         }
      }
      if (nDigit) {
         if (nSubpip >  0) nRight++;
         if (nSubpip == 8) nSubpip = 0;
         nRight = Min(nRight, 8);
      }
   }

   // Vorzeichen
   string leadSign = "";
   if (value < 0) {
      leadSign = "-";
   }
   else if (value > 0) {
      int pos = StringFind(mask, "+");
      if (-1 < pos) /*&&*/ if (pos < dotPos)
         leadSign = "+";
   }

   // �brige Modifier
   bool round = (StringFind(mask, "R") > -1);
   // --- Ende Maske parsen ---------------------------


   // --- Beginn Wertverarbeitung ---------------------
   // runden
   if (round)
      value = RoundEx(value, nRight);
   string outStr = value;

   // negatives Vorzeichen entfernen (ist in leadSign gespeichert)
   if (value < 0)
      outStr = StringSubstr(outStr, 1);

   // auf angegebene L�nge k�rzen
   int dLeft = StringFind(outStr, ".");
   if (nLeft == -1) nLeft = dLeft;
   else             nLeft = Min(nLeft, dLeft);
   outStr = StringSubstrFix(outStr, StringLen(outStr)-9-nLeft, nLeft+(nRight>0)+nRight);

   // Dezimal-Separator anpassen
   if (swapSeparators)
      outStr = StringSetChar(outStr, nLeft, StringGetChar(sepDecimal, 0));

   // 1000er-Separatoren einf�gen
   if (separators) {
      string out1;
      i = nLeft;
      while (i > 3) {
         out1 = StringSubstrFix(outStr, 0, i-3);
         if (StringGetChar(out1, i-4) == ' ')
            break;
         outStr = StringConcatenate(out1, sepThousand, StringSubstr(outStr, i-3));
         i -= 3;
      }
   }

   // Subpip-Separator einf�gen
   if (nSubpip > 0)
      outStr = StringConcatenate(StringLeft(outStr, nSubpip-nRight), "'", StringRight(outStr, nRight-nSubpip));

   // Vorzeichen etc. anf�gen
   outStr = StringConcatenate(leadSign, outStr);

   //debug("NumberToStr(double="+ DoubleToStr(value, 8) +", mask="+ mask +")    nLeft="+ nLeft +"    dLeft="+ dLeft +"    nRight="+ nRight +"    nSubpip="+ nSubpip +"    outStr=\""+ outStr +"\"");

   if (!catch("NumberToStr(1)"))
      return(outStr);
   return("");
}


/**
 * Gibt das Timeframe-Flag der angegebenen Chartperiode zur�ck.
 *
 * @param  int period - Timeframe-Identifier (default: Periode des aktuellen Charts)
 *
 * @return int - Timeframe-Flag
 */
int PeriodFlag(int period=NULL) {
   if (period == NULL)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return(F_PERIOD_M1 );
      case PERIOD_M5 : return(F_PERIOD_M5 );
      case PERIOD_M15: return(F_PERIOD_M15);
      case PERIOD_M30: return(F_PERIOD_M30);
      case PERIOD_H1 : return(F_PERIOD_H1 );
      case PERIOD_H4 : return(F_PERIOD_H4 );
      case PERIOD_D1 : return(F_PERIOD_D1 );
      case PERIOD_W1 : return(F_PERIOD_W1 );
      case PERIOD_MN1: return(F_PERIOD_MN1);
      case PERIOD_Q1 : return(F_PERIOD_Q1 );
   }
   return(_NULL(catch("PeriodFlag(1)  invalid parameter period = "+ period, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt die lesbare Version ein oder mehrerer Timeframe-Flags zur�ck.
 *
 * @param  int flags - Kombination verschiedener Timeframe-Flags
 *
 * @return string
 */
string PeriodFlagsToStr(int flags) {
   string result = "";

   if (!flags)                    result = StringConcatenate(result, "|NULL");
   if (flags & F_PERIOD_M1  && 1) result = StringConcatenate(result, "|M1"  );
   if (flags & F_PERIOD_M5  && 1) result = StringConcatenate(result, "|M5"  );
   if (flags & F_PERIOD_M15 && 1) result = StringConcatenate(result, "|M15" );
   if (flags & F_PERIOD_M30 && 1) result = StringConcatenate(result, "|M30" );
   if (flags & F_PERIOD_H1  && 1) result = StringConcatenate(result, "|H1"  );
   if (flags & F_PERIOD_H4  && 1) result = StringConcatenate(result, "|H4"  );
   if (flags & F_PERIOD_D1  && 1) result = StringConcatenate(result, "|D1"  );
   if (flags & F_PERIOD_W1  && 1) result = StringConcatenate(result, "|W1"  );
   if (flags & F_PERIOD_MN1 && 1) result = StringConcatenate(result, "|MN1" );
   if (flags & F_PERIOD_Q1  && 1) result = StringConcatenate(result, "|Q1"  );

   if (StringLen(result) > 0)
      result = StringRight(result, -1);
   return(result);
}


/**
 * Gibt die lesbare Version ein oder mehrerer History-Flags zur�ck.
 *
 * @param  int flags - Kombination verschiedener History-Flags
 *
 * @return string
 */
string HistoryFlagsToStr(int flags) {
   string result = "";

   if (!flags)                                result = StringConcatenate(result, "|NULL"                    );
   if (flags & HST_BUFFER_TICKS         && 1) result = StringConcatenate(result, "|HST_BUFFER_TICKS"        );
   if (flags & HST_SKIP_DUPLICATE_TICKS && 1) result = StringConcatenate(result, "|HST_SKIP_DUPLICATE_TICKS");
   if (flags & HST_FILL_GAPS            && 1) result = StringConcatenate(result, "|HST_FILL_GAPS"           );
   if (flags & HST_TIME_IS_OPENTIME     && 1) result = StringConcatenate(result, "|HST_TIME_IS_OPENTIME"    );

   if (StringLen(result) > 0)
      result = StringRight(result, -1);
   return(result);
}


/**
 * Gibt den Integer-Wert eines PriceType-Bezeichners zur�ck.
 *
 * @param  string value
 *
 * @return int - PriceType-Code oder -1 (EMPTY), wenn der Bezeichner ung�ltig ist
 */
int StrToPriceType(string value) {
   string str = StringToUpper(StringTrim(value));

   if (StringLen(str) == 1) {
      if (str == "O"               ) return(PRICE_OPEN    );
      if (str == ""+ PRICE_OPEN    ) return(PRICE_OPEN    );
      if (str == "H"               ) return(PRICE_HIGH    );
      if (str == ""+ PRICE_HIGH    ) return(PRICE_HIGH    );
      if (str == "L"               ) return(PRICE_LOW     );
      if (str == ""+ PRICE_LOW     ) return(PRICE_LOW     );
      if (str == "C"               ) return(PRICE_CLOSE   );
      if (str == ""+ PRICE_CLOSE   ) return(PRICE_CLOSE   );
      if (str == "M"               ) return(PRICE_MEDIAN  );
      if (str == ""+ PRICE_MEDIAN  ) return(PRICE_MEDIAN  );
      if (str == "T"               ) return(PRICE_TYPICAL );
      if (str == ""+ PRICE_TYPICAL ) return(PRICE_TYPICAL );
      if (str == "W"               ) return(PRICE_WEIGHTED);
      if (str == ""+ PRICE_WEIGHTED) return(PRICE_WEIGHTED);
      if (str == "B"               ) return(PRICE_BID     );
      if (str == ""+ PRICE_BID     ) return(PRICE_BID     );
      if (str == "A"               ) return(PRICE_ASK     );
      if (str == ""+ PRICE_ASK     ) return(PRICE_ASK     );
   }
   else {
      if (StringStartsWith(str, "PRICE_"))
         str = StringRight(str, -6);

      if (str == "OPEN"            ) return(PRICE_OPEN    );
      if (str == "HIGH"            ) return(PRICE_HIGH    );
      if (str == "LOW"             ) return(PRICE_LOW     );
      if (str == "CLOSE"           ) return(PRICE_CLOSE   );
      if (str == "MEDIAN"          ) return(PRICE_MEDIAN  );
      if (str == "TYPICAL"         ) return(PRICE_TYPICAL );
      if (str == "WEIGHTED"        ) return(PRICE_WEIGHTED);
      if (str == "BID"             ) return(PRICE_BID     );
      if (str == "ASK"             ) return(PRICE_ASK     );
   }

   if (__LOG) log("StrToPriceType(1)  invalid parameter value = \""+ value +"\" (not a price type)", ERR_INVALID_PARAMETER);
   return(EMPTY);
}


/**
 * Gibt die lesbare Beschreibung einer MovingAverage-Methode zur�ck.
 *
 * @param  int type - MA-Methode
 *
 * @return string
 */
string MaMethodDescription(int method) {
   switch (method) {
      case MODE_SMA : return("SMA" );
      case MODE_EMA : return("EMA" );
      case MODE_LWMA: return("LWMA");
      case MODE_ALMA: return("ALMA");
   }
   return(_EMPTY_STR(catch("MaMethodDescription()  invalid paramter method = "+ method, ERR_INVALID_PARAMETER)));
}


/**
 * Alias
 */
string MovingAverageMethodDescription(int method) {
   return(MaMethodDescription(method));
}


/**
 * Gibt die lesbare Konstante einer MovingAverage-Methode zur�ck.
 *
 * @param  int type - MA-Methode
 *
 * @return string
 */
string MaMethodToStr(int method) {
   switch (method) {
      case MODE_SMA : return("MODE_SMA" );
      case MODE_EMA : return("MODE_EMA" );
      case MODE_LWMA: return("MODE_LWMA");
      case MODE_ALMA: return("MODE_ALMA");
   }
   return(_EMPTY_STR(catch("MaMethodToStr()  invalid paramter method = "+ method, ERR_INVALID_PARAMETER)));
}


/**
 * Alias
 */
string MovingAverageMethodToStr(int method) {
   return(MaMethodToStr(method));
}


/**
 * Gibt die lesbare Konstante eines Price-Identifiers zur�ck.
 *
 * @param  int type - Price-Type
 *
 * @return string
 */
string PriceTypeToStr(int type) {
   switch (type) {
      case PRICE_CLOSE   : return("PRICE_CLOSE"   );
      case PRICE_OPEN    : return("PRICE_OPEN"    );
      case PRICE_HIGH    : return("PRICE_HIGH"    );
      case PRICE_LOW     : return("PRICE_LOW"     );
      case PRICE_MEDIAN  : return("PRICE_MEDIAN"  );     // (High+Low)/2
      case PRICE_TYPICAL : return("PRICE_TYPICAL" );     // (High+Low+Close)/3
      case PRICE_WEIGHTED: return("PRICE_WEIGHTED");     // (High+Low+Close+Close)/4
      case PRICE_BID     : return("PRICE_BID"     );
      case PRICE_ASK     : return("PRICE_ASK"     );
   }
   return(_EMPTY_STR(catch("PriceTypeToStr(1)  invalid parameter type = "+ type, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt die lesbare Version eines Price-Identifiers zur�ck.
 *
 * @param  int type - Price-Type
 *
 * @return string
 */
string PriceTypeDescription(int type) {
   switch (type) {
      case PRICE_CLOSE   : return("Close"   );
      case PRICE_OPEN    : return("Open"    );
      case PRICE_HIGH    : return("High"    );
      case PRICE_LOW     : return("Low"     );
      case PRICE_MEDIAN  : return("Median"  );     // (High+Low)/2
      case PRICE_TYPICAL : return("Typical" );     // (High+Low+Close)/3
      case PRICE_WEIGHTED: return("Weighted");     // (High+Low+Close+Close)/4
      case PRICE_BID     : return("Bid"     );
      case PRICE_ASK     : return("Ask"     );
   }
   return(_EMPTY_STR(catch("PriceTypeDescription(1)  invalid parameter type = "+ type, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt den Integer-Wert eines Timeframe-Bezeichners zur�ck.
 *
 * @param  string value - M1, M5, M15, M30 etc.
 *
 * @return int - Timeframe-Code oder -1 (EMPTY), wenn der Bezeichner ung�ltig ist
 */
int StrToPeriod(string value) {
   string str = StringToUpper(StringTrim(value));

   if (StringStartsWith(str, "PERIOD_"))
      str = StringRight(str, -7);

   if (str ==           "M1" ) return(PERIOD_M1 );    // 1 minute
   if (str == ""+ PERIOD_M1  ) return(PERIOD_M1 );    //
   if (str ==           "M5" ) return(PERIOD_M5 );    // 5 minutes
   if (str == ""+ PERIOD_M5  ) return(PERIOD_M5 );    //
   if (str ==           "M15") return(PERIOD_M15);    // 15 minutes
   if (str == ""+ PERIOD_M15 ) return(PERIOD_M15);    //
   if (str ==           "M30") return(PERIOD_M30);    // 30 minutes
   if (str == ""+ PERIOD_M30 ) return(PERIOD_M30);    //
   if (str ==           "H1" ) return(PERIOD_H1 );    // 1 hour
   if (str == ""+ PERIOD_H1  ) return(PERIOD_H1 );    //
   if (str ==           "H4" ) return(PERIOD_H4 );    // 4 hour
   if (str == ""+ PERIOD_H4  ) return(PERIOD_H4 );    //
   if (str ==           "D1" ) return(PERIOD_D1 );    // 1 day
   if (str == ""+ PERIOD_D1  ) return(PERIOD_D1 );    //
   if (str ==           "W1" ) return(PERIOD_W1 );    // 1 week
   if (str == ""+ PERIOD_W1  ) return(PERIOD_W1 );    //
   if (str ==           "MN1") return(PERIOD_MN1);    // 1 month
   if (str == ""+ PERIOD_MN1 ) return(PERIOD_MN1);    //
   if (str ==           "Q1" ) return(PERIOD_Q1 );    // 1 quarter
   if (str == ""+ PERIOD_Q1  ) return(PERIOD_Q1 );    //

   if (__LOG) log("StrToPeriod(1)  invalid parameter value = \""+ value +"\"", ERR_INVALID_PARAMETER);
   return(EMPTY);
}


/**
 * Alias
 */
int StrToTimeframe(string timeframe) {
   return(StrToPeriod(timeframe));
}


/**
 * Gibt die lesbare Version eines FileAccess-Modes zur�ck.
 *
 * @param  int mode - Kombination verschiedener FileAccess-Modes
 *
 * @return string
 */
string FileAccessModeToStr(int mode) {
   string result = "";

   if (!mode)                  result = StringConcatenate(result, "|0"         );
   if (mode & FILE_CSV   && 1) result = StringConcatenate(result, "|FILE_CSV"  );
   if (mode & FILE_BIN   && 1) result = StringConcatenate(result, "|FILE_BIN"  );
   if (mode & FILE_READ  && 1) result = StringConcatenate(result, "|FILE_READ" );
   if (mode & FILE_WRITE && 1) result = StringConcatenate(result, "|FILE_WRITE");

   if (StringLen(result) > 0)
      result = StringSubstr(result, 1);
   return(result);
}


/**
 * Gibt die lesbare Konstante eines SwapCalculation-Modes zur�ck.
 *
 * @param  int mode - SwapCalculation-Mode
 *
 * @return string
 */
string SwapCalculationModeToStr(int mode) {
   switch (mode) {
      case SCM_POINTS         : return("SCM_POINTS"         );
      case SCM_BASE_CURRENCY  : return("SCM_BASE_CURRENCY"  );
      case SCM_INTEREST       : return("SCM_INTEREST"       );
      case SCM_MARGIN_CURRENCY: return("SCM_MARGIN_CURRENCY");       // Stringo: non-standard calculation (vom Broker abh�ngig)
   }
   return(_EMPTY_STR(catch("SwapCalculationModeToStr()  invalid paramter mode = "+ mode, ERR_INVALID_PARAMETER)));
}


/**
 * Gibt die lesbare Beschreibung eines ShellExecute()/ShellExecuteEx()-Fehlercodes zur�ck.
 *
 * @param  int error - ShellExecute-Fehlercode
 *
 * @return string
 */
string ShellExecuteErrorDescription(int error) {
   switch (error) {
      case 0                     : return("out of memory or resources"                        );   //  0
      case ERROR_BAD_FORMAT      : return("incorrect file format"                             );   // 11

      case SE_ERR_FNF            : return("file not found"                                    );   //  2
      case SE_ERR_PNF            : return("path not found"                                    );   //  3
      case SE_ERR_ACCESSDENIED   : return("access denied"                                     );   //  5
      case SE_ERR_OOM            : return("out of memory"                                     );   //  8
      case SE_ERR_SHARE          : return("a sharing violation occurred"                      );   // 26
      case SE_ERR_ASSOCINCOMPLETE: return("file association information incomplete or invalid");   // 27
      case SE_ERR_DDETIMEOUT     : return("DDE operation timed out"                           );   // 28
      case SE_ERR_DDEFAIL        : return("DDE operation failed"                              );   // 29
      case SE_ERR_DDEBUSY        : return("DDE operation is busy"                             );   // 30
      case SE_ERR_NOASSOC        : return("file association information not available"        );   // 31
      case SE_ERR_DLLNOTFOUND    : return("DLL not found"                                     );   // 32
   }
   return(StringConcatenate("unknown ShellExecute() error (", error, ")"));
}


/**
 * Loggt die vollst�ndigen Orderinformationen eines Tickets. Ersatz f�r das unbrauchbare OrderPrint().
 *
 * @param  int ticket

 * @return bool - Erfolgsstatus
 */
bool OrderLog(int ticket) {
   if (!SelectTicket(ticket, "OrderLog(1)", O_PUSH))
      return(false);

   int      type        = OrderType();
   double   lots        = OrderLots();
   string   symbol      = OrderSymbol();
   double   openPrice   = OrderOpenPrice();
   datetime openTime    = OrderOpenTime();
   double   stopLoss    = OrderStopLoss();
   double   takeProfit  = OrderTakeProfit();
   double   closePrice  = OrderClosePrice();
   datetime closeTime   = OrderCloseTime();
   double   commission  = OrderCommission();
   double   swap        = OrderSwap();
   double   profit      = OrderProfit();
   int      magic       = OrderMagicNumber();
   string   comment     = OrderComment();

   int      digits      = MarketInfo(symbol, MODE_DIGITS);
   int      pipDigits   = digits & (~1);
   string   priceFormat = "."+ pipDigits + ifString(digits==pipDigits, "", "'");
   string   message     = StringConcatenate("#", ticket, " ", OrderTypeDescription(type), " ", NumberToStr(lots, ".1+"), " ", symbol, " at ", NumberToStr(openPrice, priceFormat), " (", TimeToStr(openTime, TIME_FULL), "), sl=", ifString(stopLoss, NumberToStr(stopLoss, priceFormat), "0"), ", tp=", ifString(takeProfit, NumberToStr(takeProfit, priceFormat), "0"), ",", ifString(closeTime, " closed at "+ NumberToStr(closePrice, priceFormat) +" ("+ TimeToStr(closeTime, TIME_FULL) +"),", ""), " commission=", DoubleToStr(commission, 2), ", swap=", DoubleToStr(swap, 2), ", profit=", DoubleToStr(profit, 2) + AccountCurrency(), ", magic=", magic, ", comment=", DoubleQuoteStr(comment));

   log("OrderLog()  "+ message);

   return(OrderPop("OrderLog(2)"));
}


#define SW_SHOW      5     // Activates the window and displays it in its current size and position.
#define SW_HIDE      0     // Hides the window and activates another window.


/**
 * Verschickt eine E-Mail.
 *
 * @param  string sender   - E-Mailadresse des Senders    (default: der in der Terminal-Konfiguration angegebene Standard-Sender)
 * @param  string receiver - E-Mailadresse des Empf�ngers (default: der in der Terminal-Konfiguration angegebene Standard-Empf�nger)
 * @param  string subject  - Subject der E-Mail
 * @param  string message  - Body der E-Mail
 *
 * @return bool - Erfolgsstatus: TRUE, wenn die E-Mail zum Versand akzeptiert wurde (nicht, ob sie versendet wurde);
 *                               FALSE andererseits
 */
bool SendEmail(string sender, string receiver, string subject, string message) {
   string mqlDir   = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string filesDir = TerminalPath() + mqlDir +"\\files\\";


   // (1) Validierung
   // Sender
   string _sender = StringTrim(sender);
   if (!StringLen(_sender)) {
      string section = "Mail";
      string key     = "Sender";
      _sender = GetConfigString(section, key);
      if (!StringLen(_sender))                return(!catch("SendEmail(1)  missing global/local configuration ["+ section +"]->"+ key,                                 ERR_INVALID_CONFIG_PARAMVALUE));
      if (!StringIsEmailAddress(_sender))     return(!catch("SendEmail(2)  invalid global/local configuration ["+ section +"]->"+ key +" = "+ DoubleQuoteStr(_sender), ERR_INVALID_CONFIG_PARAMVALUE));
   }
   else if (!StringIsEmailAddress(_sender))   return(!catch("SendEmail(3)  invalid parameter sender = "+ DoubleQuoteStr(sender), ERR_INVALID_PARAMETER));
   sender = _sender;

   // Receiver
   string _receiver = StringTrim(receiver);
   if (!StringLen(_receiver)) {
      section   = "Mail";
      key       = "Receiver";
      _receiver = GetConfigString(section, key);
      if (!StringLen(_receiver))              return(!catch("SendEmail(4)  missing global/local configuration ["+ section +"]->"+ key,                                   ERR_INVALID_CONFIG_PARAMVALUE));
      if (!StringIsEmailAddress(_receiver))   return(!catch("SendEmail(5)  invalid global/local configuration ["+ section +"]->"+ key +" = "+ DoubleQuoteStr(_receiver), ERR_INVALID_CONFIG_PARAMVALUE));
   }
   else if (!StringIsEmailAddress(_receiver)) return(!catch("SendEmail(6)  invalid parameter receiver = "+ DoubleQuoteStr(receiver), ERR_INVALID_PARAMETER));
   receiver = _receiver;

   // Subject
   string _subject = StringTrim(subject);
   if (!StringLen(_subject))                  return(!catch("SendEmail(7)  invalid parameter subject = "+ DoubleQuoteStr(subject), ERR_INVALID_PARAMETER));
   _subject = StringReplace(StringReplace(StringReplace(_subject, "\r\n", "\n"), "\r", " "), "\n", " "); // Linebreaks mit Leerzeichen ersetzen
   _subject = StringReplace(_subject, "\"", "\\\"");                                                     // Double-Quotes in email-Parametern escapen
   _subject = StringReplace(_subject, "'", "'\"'\"'");                                                   // Single-Quotes im bash-Parameter escapen
   // bash -lc 'email -subject "single-quote:'"'"' double-quote:\" pipe:|" ...'


   // (2) Message (kann leer sein): in tempor�rer Datei speichern, wenn nicht leer
   message = StringTrim(message);
   string message.txt = CreateTempFile(filesDir, "msg");
   if (StringLen(message) > 0) {
      int hFile = FileOpen(StringRightFrom(message.txt, filesDir), FILE_BIN|FILE_WRITE);                 // FileOpen() ben�tigt einen MQL-Pfad
      if (hFile < 0)  return(!catch("SendEmail(8)->FileOpen()"));
      int bytes = FileWriteString(hFile, message, StringLen(message));
      FileClose(hFile);
      if (bytes <= 0) return(!catch("SendEmail(9)->FileWriteString() => "+ bytes +" written"));
   }


   // (3) ben�tigte Binaries ermitteln: Bash und Mailclient
   //section         = "Mail";
   //key             = "Sendmail";
   //string sendmail = GetConfigString(section, key);
   //if (!StringLen(sendmail)) {
   //   // kein Mailclient angegeben: Umgebungsvariable $SENDMAIL auswerten
   //   // sendmail suchen
   //}
   string bash     = "drive:\\path\\to\\bash.exe";
   string sendmail = "/bin/email";

   // Binaries auf Existenz pr�fen
   if (!IsFile(bash)) return(!catch("SendEmail(10)  bash executable not found: "+ DoubleQuoteStr(bash), ERR_FILE_NOT_FOUND));
   // (3.1) absoluter Pfad
   // (3.2) relativer Pfad: Systemverzeichnisse durchsuchen; Variable $PATH durchsuchen


   // (4) Befehlszeile f�r Shell-Aufruf zusammensetzen
   //
   //  � Redirection in der Befehlszeile ist ein Shell-Feature und erfordert eine Shell als ausf�hrendes Programm (direkter Client-Aufruf mit Umleitung ist nicht m�glich).
   //  � Redirection mit cmd.exe funktioniert nicht, wenn umgeleiteter Output oder �bergebene Parameter Sonderzeichen enthalten: cmd /c echo hello \n world | {program} => Fehler
   //  � Bei Verwendung der Shell als ausf�hrendem Programm steht jedoch der Exit-Code nicht zur Verf�gung (mu� vorerst in Kauf genommen werden).
   //  � Alternative ist die Verwendung von CreateProcess() und direktes Schreiben/Lesen von STDIN/STDOUT. In diesem Fall mu� der Versand jedoch in einem eigenen Thread erfolgen,
   //    wenn er nicht blockieren soll.
   //
   // Cleancode.email:
   // ----------------
   //  � unterst�tzt keine Exit-Codes
   //  � validiert die �bergebenen Adressen nicht
   //
   message.txt     = StringReplace(message.txt, "\\", "/");
   string mail.log = StringReplace(filesDir +"mail.log", "\\", "/");
   string cmdLine  = sendmail +" -subject \""+ _subject +"\" -from-addr \""+ sender +"\" \""+ receiver +"\" < \""+ message.txt +"\" >> \""+ mail.log +"\" 2>&1; rm -f \""+ message.txt +"\"";
          cmdLine  = bash +" -lc '"+ cmdLine +"'";
   //debug("SendEmail(11)  cmdLine="+ DoubleQuoteStr(cmdLine));


   // (5) Shell-Aufruf
   int result = WinExec(cmdLine, SW_HIDE);   // SW_SHOW | SW_HIDE
   if (result < 32) return(!catch("SendEmail(12)->kernel32::WinExec(cmdLine=\""+ cmdLine +"\")  "+ ShellExecuteErrorDescription(result), ERR_WIN32_ERROR+result));

   log("SendEmail(13)  Mail transmitted to "+ receiver +": \""+ subject +"\"");
   return(!catch("SendEmail(14)"));
}


/**
 * Schickt eine SMS an die angegebene Telefonnummer.
 *
 * @param  string receiver - Telefonnummer des Empf�ngers (internationales Format: +49-123-456789)
 * @param  string message  - Text der SMS
 *
 * @return bool - Erfolgsstatus
 */
bool SendSMS(string receiver, string message) {
   string _receiver = StringReplace.Recursive(StringReplace(StringTrim(receiver), "-", ""), " ", "");

   if      (StringStartsWith(_receiver, "+" )) _receiver = StringRight(_receiver, -1);
   else if (StringStartsWith(_receiver, "00")) _receiver = StringRight(_receiver, -2);

   if (!StringIsDigit(_receiver)) return(!catch("SendSMS(1)  invalid parameter receiver = "+ DoubleQuoteStr(receiver), ERR_INVALID_PARAMETER));


   // (1) Zugangsdaten f�r SMS-Gateway holen
   // Service-Provider
   string section  = "SMS";
   string key      = "Provider";
   string provider = GetGlobalConfigString(section, key);
   if (!StringLen(provider)) return(!catch("SendSMS(2)  missing global configuration ["+ section +"]->"+ key, ERR_INVALID_CONFIG_PARAMVALUE));

   // Username
   section = "SMS."+ provider;
   key     = "username";
   string username = GetGlobalConfigString(section, key);
   if (!StringLen(username)) return(!catch("SendSMS(3)  missing global configuration ["+ section +"]->"+ key, ERR_INVALID_CONFIG_PARAMVALUE));

   // Password
   key = "password";
   string password = GetGlobalConfigString(section, key);
   if (!StringLen(password)) return(!catch("SendSMS(4)  missing global configuration ["+ section +"]->"+ key, ERR_INVALID_CONFIG_PARAMVALUE));

   // API-ID
   key = "api_id";
   int api_id = GetGlobalConfigInt(section, key);
   if (api_id <= 0) {
      string value = GetGlobalConfigString(section, key);
      if (!StringLen(value)) return(!catch("SendSMS(5)  missing global configuration ["+ section +"]->"+ key,                       ERR_INVALID_CONFIG_PARAMVALUE));
                             return(!catch("SendSMS(6)  invalid global configuration ["+ section +"]->"+ key +" = \""+ value +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
   }


   // (2) Befehlszeile f�r Shellaufruf zusammensetzen
   string url          = "https://api.clickatell.com/http/sendmsg?user="+ username +"&password="+ password +"&api_id="+ api_id +"&to="+ _receiver +"&text="+ UrlEncode(message);
   string mqlDir       = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string filesDir     = TerminalPath() + mqlDir +"\\files";
   string responseFile = filesDir +"\\sms_"+ DateTimeToStr(TimeLocalEx("SendSMS(7)"), "Y-M-D H.I.S") +"_"+ GetCurrentThreadId() +".response";
   string logFile      = filesDir +"\\sms.log";
   string cmd          = TerminalPath() +"\\"+ mqlDir +"\\libraries\\wget.exe";
   string arguments    = "-b --no-check-certificate \""+ url +"\" -O \""+ responseFile +"\" -a \""+ logFile +"\"";
   string cmdLine      = cmd +" "+ arguments;


   // (3) Shellaufruf
   int result = WinExec(cmdLine, SW_HIDE);
   if (result < 32) return(!catch("SendSMS(8)->kernel32::WinExec(cmdLine="+ DoubleQuoteStr(cmdLine) +")  "+ ShellExecuteErrorDescription(result), ERR_WIN32_ERROR+result));

   /**
    * TODO: Fehlerauswertung nach dem Versand:
    *
    * --2011-03-23 08:32:06--  https://api.clickatell.com/http/sendmsg?user={user}&password={password}&api_id={api_id}&to={receiver}&text={text}
    * Resolving api.clickatell.com... failed: Unknown host.
    * wget: unable to resolve host address `api.clickatell.com'
    *
    *
    * --2014-06-15 22:44:21--  (try:20)  https://api.clickatell.com/http/sendmsg?user={user}&password={password}&api_id={api_id}&to={receiver}&text={text}
    * Connecting to api.clickatell.com|196.216.236.7|:443... failed: Permission denied.
    * Giving up.
    */
   log("SendSMS(9)  SMS sent to "+ receiver +": \""+ message +"\"");
   return(!catch("SendSMS(10)"));
}


/**
 * Unterdr�ckt unn�tze Compilerwarnungen.
 */
void __DummyCalls() {
   int    iNulls[];
   string sNulls[];

   __log.custom(NULL);
   _bool(NULL);
   _double(NULL);
   _EMPTY();
   _EMPTY_STR();
   _EMPTY_VALUE();
   _false();
   _int(NULL);
   _last_error();
   _NaT();
   _NO_ERROR();
   _NULL();
   _string(NULL);
   _true();
   Abs(NULL);
   AccountAlias(NULL, NULL);
   AccountCompanyId(NULL);
   AccountNumberFromAlias(NULL, NULL);
   ArrayUnshiftString(sNulls, NULL);
   catch(NULL, NULL, NULL);
   Ceil(NULL);
   Chart.Expert.Properties();
   Chart.Objects.UnselectAll();
   Chart.Refresh();
   Chart.SendTick(NULL);
   CharToHexStr(NULL);
   ColorToHtmlStr(NULL);
   ColorToStr(NULL);
   CompareDoubles(NULL, NULL);
   CopyMemory(NULL, NULL, NULL);
   CountDecimals(NULL);
   CreateString(NULL);
   DateTime(NULL);
   debug(NULL);
   DebugMarketInfo(NULL);
   DeinitReason();
   DeleteIniKey(NULL, NULL, NULL);
   Div(NULL, NULL);
   DoubleToStrMorePrecision(NULL, NULL);
   DummyCalls();
   EnumChildWindows(NULL);
   EQ(NULL, NULL);
   EventListener.NewTick();
   Expert.IsTesting();
   FileAccessModeToStr(NULL);
   Floor(NULL);
   ForceAlert(NULL);
   GE(NULL, NULL);
   GetAccountConfigPath(NULL, NULL);
   GetConfigBool(NULL, NULL);
   GetConfigDouble(NULL, NULL);
   GetConfigInt(NULL, NULL);
   GetConfigString(NULL, NULL);
   GetCurrency(NULL);
   GetCurrencyId(NULL);
   GetExternalAssets(NULL, NULL);
   GetFxtTime();
   GetGlobalConfigBool(NULL, NULL);
   GetGlobalConfigDouble(NULL, NULL);
   GetGlobalConfigInt(NULL, NULL);
   GetGlobalConfigString(NULL, NULL);
   GetIniBool(NULL, NULL, NULL);
   GetIniDouble(NULL, NULL, NULL);
   GetIniInt(NULL, NULL, NULL);
   GetIniString(NULL, NULL, NULL);
   GetLocalConfigBool(NULL, NULL);
   GetLocalConfigDouble(NULL, NULL);
   GetLocalConfigInt(NULL, NULL);
   GetLocalConfigString(NULL, NULL);
   GetRawConfigString(NULL, NULL);
   GetRawGlobalConfigString(NULL, NULL);
   GetRawLocalConfigString(NULL, NULL);
   GetServerTime();
   GT(NULL, NULL);
   HandleEvent(NULL);
   HistoryFlagsToStr(NULL);
   ifBool(NULL, NULL, NULL);
   ifDouble(NULL, NULL, NULL);
   ifInt(NULL, NULL, NULL);
   ifString(NULL, NULL, NULL);
   Indicator.IsTesting();
   InitReason();
   InitReasonDescription(NULL);
   IntegerToHexString(NULL);
   IsConfigKey(NULL, NULL);
   IsCurrency(NULL);
   IsEmpty(NULL);
   IsEmptyString(NULL);
   IsEmptyValue(NULL);
   IsError(NULL);
   IsExpert();
   IsGlobalConfigKey(NULL, NULL);
   IsIndicator();
   IsInfinity(NULL);
   IsLastError();
   IsLeapYear(NULL);
   IsLibrary();
   IsLocalConfigKey(NULL, NULL);
   IsLogging();
   IsLongTradeOperation(NULL);
   IsMqlDirectory(NULL);
   IsMqlFile(NULL);
   IsNaN(NULL);
   IsNaT(NULL);
   IsPendingTradeOperation(NULL);
   IsScript();
   IsShortAccountCompany(NULL);
   IsShortTradeOperation(NULL);
   IsSuperContext();
   IsTicket(NULL);
   IsTradeOperation(NULL);
   LE(NULL, NULL);
   log(NULL);
   LT(NULL, NULL);
   MaMethodDescription(NULL);
   MaMethodToStr(NULL);
   MarketWatch.Symbols();
   MathDiv(NULL, NULL);
   MathModFix(NULL, NULL);
   Max(NULL, NULL);
   MessageBoxCmdToStr(NULL);
   Min(NULL, NULL);
   ModuleTypesToStr(NULL);
   MovingAverageMethodDescription(NULL);
   MovingAverageMethodToStr(NULL);
   NE(NULL, NULL);
   NumberToStr(NULL, NULL);
   OperationTypeDescription(NULL);
   OperationTypeToStr(NULL);
   OrderLog(NULL);
   OrderPop(NULL);
   OrderPush(NULL);
   OrderTypeDescription(NULL);
   OrderTypeToStr(NULL);
   PeriodFlag();
   PeriodFlagsToStr(NULL);
   PipValue();
   PipValueEx(NULL);
   PriceTypeDescription(NULL);
   PriceTypeToStr(NULL);
   QuoteStr(NULL);
   RefreshExternalAssets(NULL, NULL);
   ResetLastError();
   Round(NULL);
   RoundCeil(NULL);
   RoundEx(NULL);
   RoundFloor(NULL);
   Script.IsTesting();
   SelectTicket(NULL, NULL);
   SendEmail(NULL, NULL, NULL, NULL);
   SendSMS(NULL, NULL);
   SetLastError(NULL, NULL);
   ShellExecuteErrorDescription(NULL);
   ShortAccountCompany();
   ShortAccountCompanyFromId(NULL);
   Sign(NULL);
   start.RelaunchInputDialog();
   StringCapitalize(NULL);
   StringCompareI(NULL, NULL);
   StringContains(NULL, NULL);
   StringContainsI(NULL, NULL);
   StringEndsWith(NULL, NULL);
   StringEndsWithI(NULL, NULL);
   StringFindR(NULL, NULL);
   StringIsDigit(NULL);
   StringIsEmailAddress(NULL);
   StringIsInteger(NULL);
   StringIsNumeric(NULL);
   StringIsPhoneNumber(NULL);
   StringLeft(NULL, NULL);
   StringLeftPad(NULL, NULL);
   StringLeftTo(NULL, NULL);
   StringPadLeft(NULL, NULL);
   StringPadRight(NULL, NULL);
   StringRepeat(NULL, NULL);
   StringReplace(NULL, NULL, NULL);
   StringReplace.Recursive(NULL, NULL, NULL);
   StringRight(NULL, NULL);
   StringRightFrom(NULL, NULL);
   StringRightPad(NULL, NULL);
   StringStartsWith(NULL, NULL);
   StringStartsWithI(NULL, NULL);
   StringSubstrFix(NULL, NULL);
   StringToHexStr(NULL);
   StringToLower(NULL);
   StringToUpper(NULL);
   StringTrim(NULL);
   StrToBool(NULL);
   StrToMaMethod(NULL);
   StrToMovingAverageMethod(NULL);
   StrToOperationType(NULL);
   StrToPeriod(NULL);
   StrToPriceType(NULL);
   StrToTimeframe(NULL);
   SumInts(iNulls);
   SwapCalculationModeToStr(NULL);
   Tester.IsPaused();
   Tester.IsStopped();
   Tester.Pause();
   This.IsTesting();
   TimeCurrentEx();
   TimeDayFix(NULL);
   TimeDayOfWeekFix(NULL);
   TimeFXT();
   TimeGMT();
   TimeLocalEx();
   TimeServer();
   TimeYearFix(NULL);
   Toolbar.Experts(NULL);
   TradeCommandToStr(NULL);
   UninitializeReasonDescription(NULL);
   UpdateProgramStatus();
   UrlEncode(NULL);
   WaitForTicket(NULL);
   warn(NULL);
   warnSMS(NULL);
   WindowHandleEx(NULL);
   WM_MT4();
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


/*
#import "library-does-not-exist.ex4"                                       // zum Testen von stdfunctions.mqh ohne core-Dateien
   bool     IsExpert();
   bool     IsScript();
   bool     IsIndicator();
   bool     IsLibrary();
   bool     Expert.IsTesting();
   bool     Script.IsTesting();
   bool     Indicator.IsTesting();
   bool     This.IsTesting();
   int      InitReason();
   int      DeinitReason();
   bool     IsSuperContext();
   int      SetLastError(int error, int param);
*/
#import "stdlib1.ex4"
   int      stdlib.GetLastError();

   bool     EventListener.AccountChange(int    data[], int param);
   bool     EventListener.BarOpen      (                        );
   bool     EventListener.BarOpen.MTF  (int    data[], int param);
   bool     EventListener.ChartCommand (string data[], int param);

   bool     onAccountChange(int    data[]);
   bool     onBarOpen      (             );
   bool     onBarOpen.MTF  (int    data[]);
   bool     onChartCommand (string data[]);

   int      ArrayPopInt(int array[]);
   int      ArrayPushInt(int array[], int value);
   int      ArrayPushString(string array[], string value);
   string   ByteToHexStr(int byte);
   string   ColorToRGBStr(color rgb);
   string   CreateTempFile(string path, string prefix);
   string   DateTimeToStr(datetime time, string mask);
   string   DoubleToStrEx(double value, int digits);
   void     DummyCalls();                                                  // Stub: kann lokal �berschrieben werden
   int      GetCustomLogID();
   string   GetGlobalConfigPath();
   string   GetLocalConfigPath();
   string   GetRawIniString(string fileName, string section, string key, string defaultValue);
   string   GetServerName();
   int      GetTesterWindow();
   string   GetWindowText(int hWnd);
   datetime GmtToFxtTime(datetime gmtTime);
   datetime GmtToServerTime(datetime gmtTime);
   int      InitializeStringBuffer(string buffer[], int length);
   bool     IsDirectory(string filename);
   bool     IsFile(string filename);
   bool     IsIniKey(string fileName, string section, string key);
   bool     ReverseStringArray(string array[]);
   datetime ServerToGmtTime(datetime serverTime);
   string   StdSymbol();

#import "stdlib2.ex4"
   int      GetIniKeys(string fileName, string section, string keys[]);

#import "Expander.dll"
   int      ec_hChart     (/*EXECUTION_CONTEXT*/int ec[]);
   int      ec_ProgramType(/*EXECUTION_CONTEXT*/int ec[]);
   int      ec_TestFlags  (/*EXECUTION_CONTEXT*/int ec[]);

   int      ec_SetMqlError(/*EXECUTION_CONTEXT*/int ec[], int lastError);

#import "kernel32.dll"
   int      GetCurrentProcessId();
   int      GetCurrentThreadId();
   int      GetPrivateProfileIntA(string lpSection, string lpKey, int nDefault, string lpFileName);
   void     OutputDebugStringA(string lpMessage);                          // funktioniert nur f�r Admins
   void     RtlMoveMemory(int destAddress, int srcAddress, int bytes);
   int      WinExec(string lpCmdLine, int cmdShow);
   bool     WritePrivateProfileStringA(string lpSection, string lpKey, string lpValue, string lpFileName);

#import "user32.dll"
   int      GetAncestor(int hWnd, int cmd);
   int      GetClassNameA(int hWnd, string lpBuffer, int bufferSize);
   int      GetDlgCtrlID(int hWndCtl);
   int      GetDlgItem(int hDlg, int itemId);
   int      GetParent(int hWnd);
   int      GetTopWindow(int hWnd);
   int      GetWindow(int hWnd, int cmd);
   int      GetWindowThreadProcessId(int hWnd, int lpProcessId[]);
   bool     IsWindow(int hWnd);
   int      MessageBoxA(int hWnd, string lpText, string lpCaption, int style);
   bool     PostMessageA(int hWnd, int msg, int wParam, int lParam);
   int      RegisterWindowMessageA(string lpString);
   int      SendMessageA(int hWnd, int msg, int wParam, int lParam);

#import "winmm.dll"
   bool     PlaySoundA(string lpSound, int hMod, int fSound);
#import
