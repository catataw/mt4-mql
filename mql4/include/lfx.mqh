/**
 *  Format der LFX-MagicNumber:
 *  ---------------------------
 *  Strategy-Id:  10 bit (Bit 23-32) => Bereich 101-1023
 *  Currency-Id:   4 bit (Bit 19-22) => Bereich   1-15               entspricht stdlib::GetCurrencyId()
 *  Units:         4 bit (Bit 15-18) => Bereich   1-15               Vielfaches von 0.1 von 1 bis 10           // wird nicht mehr verwendet, alle Referenzen gel�scht
 *  Instance-ID:  10 bit (Bit  5-14) => Bereich   1-1023
 *  Counter:       4 bit (Bit  1-4 ) => Bereich   1-15                                                         // wird nicht mehr verwendet, alle Referenzen gel�scht
 */
#define STRATEGY_ID   102                                            // eindeutige ID der Strategie (Bereich 101-1023)


bool   mode.intern = true;    // Default                             // - Interne Positionsdaten stammen aus dem Terminal selbst, sie werden bei jedem Tick zur�ckgesetzt und neu
bool   mode.extern;                                                  //   eingelesen. Order�nderungen werden automatisch erkannt.
bool   mode.remote;                                                  // - Externe und Remote-Positionsdaten stammen aus einer externen Quelle und werden nur bei Timeframe-Wechsel
                                                                     //   oder nach Eintreffen eines entsprechenden Events zur�ckgesetzt und neu eingelesen. Order�nderungen werden
int    tradeAccountNumber;                                           //   nicht automatisch erkannt.
string tradeAccountCurrency;
int    tradeAccountType;                                             // ACCOUNT_TYPE_DEMO|ACCOUNT_TYPE_REAL
string tradeAccountCompany;
string tradeAccountName;                                             // Inhaber
string tradeAccountAlias;                                            // Alias f�r Logs, SMS etc.


string lfxCurrency = "";
int    lfxCurrencyId;

int    lfxOrder   [LFX_ORDER.intSize];                               // struct LFX_ORDER
int    lfxOrders[][LFX_ORDER.intSize];                               // struct LFX_ORDER[]

int    lfxOrders.ivolatile[][3];                                     // ver�nderliche Positionsdaten: = {Ticket, IsOpen, IsLocked}
double lfxOrders.dvolatile[][1];                                     //                               = {Profit}
int    lfxOrders.openPositions;                                      // Anzahl der offenen Positionen in den offenen Orders (IsOpen = 1)

#define I_TICKET           0                                         // Arrayindizes von lfxOrders.~volatile[]
#define I_ISOPEN           1
#define I_ISLOCKED         2
#define I_PROFIT           0


/**
 * Initialisiert Status und Variablen des aktuellen TradeAccounts.
 *
 * @return bool - Erfolgsstatus
 */
bool InitTradeAccount() {
   if (tradeAccountNumber != 0)
      return(true);

   int    _accountNumber;
   string _accountCurrency;
   int    _accountType;
   string _accountCompany;
   string _accountName;
   string _accountAlias;


   // (1) AccountNumber bestimmen und dabei einen konfigurierten nicht-standardm��igen Account ber�cksichtigen
   _accountNumber = GetAccountNumber(); if (!_accountNumber) return(!SetLastError(stdlib.GetLastError()));

   string mqlDir   = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file     = TerminalPath() + mqlDir +"\\files\\"+ ShortAccountCompany() +"\\"+ GetAccountNumber() +"_config.ini";
   string section = "General";
   string key     = "TradeAccount" + ifString(This.IsTesting(), ".Tester", "");

   int nonStdAccount = GetIniInt(file, section, key);
   if (nonStdAccount <= 0) {
      string value = GetIniString(file, section, key);
      if (value != "")     return(!catch("InitTradeAccount(1)  invalid trade account setting ["+ section +"]->"+ key +" = \""+ value +"\"", ERR_RUNTIME_ERROR));
   }
   else {
      _accountNumber = nonStdAccount;
   }


   // (2) anhand des Accounts die restlichen Variablen ermitteln
   // AccountCurrency
   section = "Accounts";
   key     = _accountNumber +".currency";
   value   = GetGlobalConfigString(section, key);
   if (!StringLen(value))  return(!catch("InitTradeAccount(2)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   if (!IsCurrency(value)) return(!catch("InitTradeAccount(3)  invalid account setting ["+ section +"]->"+ key +" = \""+ value +"\"", ERR_RUNTIME_ERROR));
   _accountCurrency = StringToUpper(value);

   // AccountType
   section = "Accounts";
   key     = _accountNumber +".type";
   value   = StringToLower(GetGlobalConfigString(section, key));
   if (!StringLen(value))  return(!catch("InitTradeAccount(4)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   if      (value == "demo") _accountType = ACCOUNT_TYPE_DEMO;
   else if (value == "real") _accountType = ACCOUNT_TYPE_REAL;
   else                    return(!catch("InitTradeAccount(5)  invalid account setting ["+ section +"]->"+ key +" = \""+ GetGlobalConfigString(section, key) +"\"", ERR_RUNTIME_ERROR));

   // AccountCompany
   section = "Accounts";
   key     = _accountNumber +".company";
   value   = GetGlobalConfigString(section, key);
   if (!StringLen(value))  return(!catch("InitTradeAccount(6)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   _accountCompany = value;

   // AccountName
   section = "Accounts";
   key     = _accountNumber +".name";
   value   = GetGlobalConfigString(section, key);
   if (!StringLen(value))  return(!catch("InitTradeAccount(7)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   _accountName = value;

   // AccountAlias
   section = "Accounts";
   key     = _accountNumber +".alias";
   value   = GetGlobalConfigString(section, key);
   if (!StringLen(value))  return(!catch("InitTradeAccount(8)  missing account setting ["+ section +"]->"+ key, ERR_RUNTIME_ERROR));
   _accountAlias = value;


   // (3) globale Variablen erst nach vollst�ndiger erfolgreicher Validierung �berschreiben
   mode.intern = (_accountNumber == GetAccountNumber());
   mode.extern = false;                                              // Hier immer FALSE, wird ggf. sp�ter von RestoreWindowStatus() �berschrieben
   mode.remote = !mode.intern;

   tradeAccountNumber   = _accountNumber;
   tradeAccountCurrency = _accountCurrency;
   tradeAccountType     = _accountType;
   tradeAccountCompany  = _accountCompany;
   tradeAccountName     = _accountName;
   tradeAccountAlias    = _accountAlias;

   if (mode.remote) {
      if (StringEndsWith(Symbol(), "LFX")) {
         lfxCurrency   = StringLeft (Symbol(), -3);                  // TODO: lfx-Variablen durch Symbol() ersetzen
         lfxCurrencyId = GetCurrencyId(lfxCurrency);
      }
   }

   return(true);
}


/**
 * Ob die aktuell selektierte Order zu dieser Strategie geh�rt.
 *
 * @return bool
 */
bool LFX.IsMyOrder() {
   return(OrderMagicNumber() >> 22 == STRATEGY_ID);                  // 10 bit (Bit 23-32) => Bereich 101-1023
}


/**
 * Gibt die Currency-ID der MagicNumber einer LFX-Order zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Currency-ID, entsprechend stdlib1::GetCurrencyId()
 */
int LFX.CurrencyId(int magicNumber) {
   return(magicNumber >> 18 & 0xF);                                  // 4 bit (Bit 19-22) => Bereich 1-15
}


/**
 * Gibt die Instanz-ID der MagicNumber einer LFX-Order zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Instanz-ID
 */
int LFX.InstanceId(int magicNumber) {
   return(magicNumber >> 4 & 0x3FF);                                 // 10 bit (Bit 5-14) => Bereich 1-1023
}


/**
 * Gibt eine LFX-Order des TradeAccounts zur�ck.
 *
 * @param  int ticket - Ticket der zur�ckzugebenden Order
 * @param  int lo[]   - LFX_ORDER-Struct zur Aufnahme der gelesenen Daten
 *
 * @return int - Erfolgsstatus: +1, wenn die Order erfolgreich gelesen wurde
 *                              -1, wenn die Order nicht gefunden wurde
 *                               0, falls ein anderer Fehler auftrat
 */
int LFX.GetOrder(int ticket, /*LFX_ORDER*/int lo[]) {
   // Parametervaliderung
   if (ticket <= 0) return(!catch("LFX.GetOrder(1)  invalid parameter ticket = "+ ticket, ERR_INVALID_PARAMETER));

   int digits = ifInt(LFX.CurrencyId(ticket)==CID_JPY, 3, 5);


   // (1) Orderdaten lesen
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccountCompany +"\\"+ tradeAccountNumber +"_config.ini";
   string section = "RemoteOrders";
   string key     = ticket;
   string value   = GetIniString(file, section, key, "");
   if (!StringLen(value)) {
      if (IsIniKey(file, section, key)) return(!catch("LFX.GetOrder(2)  invalid order entry ["+ section +"]->"+ key +" in \""+ file +"\"", ERR_RUNTIME_ERROR));
                                        return(-1);                  // Ticket nicht gefunden
   }


   // (2) Orderdaten validieren
   //Ticket = Symbol, Comment, OrderType, Units, OpenEquity, (-)OpenTime, OpenPrice, OpenTriggerTime, StopLoss, StopLossValue, StopLossTriggered, TakeProfit, TakeProfitValue, TakeProfitTriggered, CloseTriggerTime, (-)CloseTime, ClosePrice, Profit, ModificationTime, Version
   string sValue, values[];
   if (Explode(value, ",", values, NULL) != 20)    return(!catch("LFX.GetOrder(3)  invalid order entry ("+ ArraySize(values) +" substrings) ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // Comment
   string _comment = StringTrim(values[1]);

   // OrderType
   sValue = StringTrim(values[2]);
   int _orderType = StrToOperationType(sValue);
   if (!IsTradeOperation(_orderType))              return(!catch("LFX.GetOrder(4)  invalid order type \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OrderUnits
   sValue = StringTrim(values[3]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(5)  invalid unit size \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _orderUnits = StrToDouble(sValue);
   if (_orderUnits <= 0)                           return(!catch("LFX.GetOrder(6)  invalid unit size \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _orderUnits = NormalizeDouble(_orderUnits, 1);

   // OpenEquity
   sValue = StringTrim(values[4]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(7)  invalid open equity \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _openEquity = StrToDouble(sValue);
   if (!IsPendingTradeOperation(_orderType))
      if (_openEquity <= 0)                        return(!catch("LFX.GetOrder(8)  invalid open equity \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _openEquity = NormalizeDouble(_openEquity, 2);

   // OpenTime
   sValue = StringTrim(values[5]);
   if      (StringIsInteger(sValue)) datetime _openTime =  StrToInteger(sValue);
   else if (StringStartsWith(sValue, "-"))    _openTime = -StrToTime(StringSubstr(sValue, 1));
   else                                       _openTime =  StrToTime(sValue);
   if (!_openTime)                                 return(!catch("LFX.GetOrder(9)  invalid open time \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   if (Abs(_openTime) > GetGmtTime())              return(!catch("LFX.GetOrder(10)  invalid open time \""+ TimeToStr(Abs(_openTime), TIME_FULL) +" GMT\" (current time \""+ TimeToStr(GetGmtTime(), TIME_FULL) +" GMT\") in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OpenPrice
   sValue = StringTrim(values[6]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(11)  invalid open price \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _openPrice = StrToDouble(sValue);
   if (_openPrice <= 0)                            return(!catch("LFX.GetOrder(12)  invalid open price \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _openPrice = NormalizeDouble(_openPrice, digits);

   // OpenTriggerTime
   sValue = StringTrim(values[7]);
   if (StringIsDigit(sValue)) datetime _openTriggerTime = StrToInteger(sValue);
   else                                _openTriggerTime =    StrToTime(sValue);
   if      (_openTriggerTime < 0)                  return(!catch("LFX.GetOrder(13)  invalid open-trigger time \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else if (_openTriggerTime > 0)
      if (_openTriggerTime > GetGmtTime())         return(!catch("LFX.GetOrder(14)  invalid open-trigger time \""+ TimeToStr(_openTriggerTime, TIME_FULL) +" GMT\" (current time \""+ TimeToStr(GetGmtTime(), TIME_FULL) +" GMT\") in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // StopLoss
   sValue = StringTrim(values[8]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(15)  invalid stoploss \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _stopLoss = StrToDouble(sValue);
   if (_stopLoss < 0)                              return(!catch("LFX.GetOrder(16)  invalid stoploss \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _stopLoss = NormalizeDouble(_stopLoss, digits);

   // StopLossValue
   sValue = StringTrim(values[9]);
   if      (!StringLen(sValue)) double _stopLossValue = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))              return(!catch("LFX.GetOrder(17)  invalid stoploss value \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else                                _stopLossValue = NormalizeDouble(StrToDouble(sValue), 2);

   // StopLossTriggered
   sValue = StringTrim(values[10]);
   if      (sValue == "0") bool _stopLossTriggered = false;
   else if (sValue == "1")      _stopLossTriggered = true;
   else                                            return(!catch("LFX.GetOrder(18)  invalid stoploss-triggered value \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // TakeProfit
   sValue = StringTrim(values[11]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(19)  invalid takeprofit \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _takeProfit = StrToDouble(sValue);
   if (_takeProfit < 0)                            return(!catch("LFX.GetOrder(20)  invalid takeprofit \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _takeProfit = NormalizeDouble(_takeProfit, digits);

   // TakeProfitValue
   sValue = StringTrim(values[12]);
   if      (!StringLen(sValue)) double _takeProfitValue = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))              return(!catch("LFX.GetOrder(21)  invalid takeprofit value \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {                              _takeProfitValue = NormalizeDouble(StrToDouble(sValue), 2);
      if (_stopLossValue!=EMPTY_VALUE && _takeProfitValue!=EMPTY_VALUE)
         if (_stopLossValue > _takeProfitValue)    return(!catch("LFX.GetOrder(22)  stoploss/takeprofit value mis-match "+ DoubleToStr(_stopLossValue, 2) +"/"+ DoubleToStr(_takeProfitValue, 2) +" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   }

   // TakeProfitTriggered
   sValue = StringTrim(values[13]);
   if      (sValue == "0") bool _takeProfitTriggered = false;
   else if (sValue == "1")      _takeProfitTriggered = true;
   else                                            return(!catch("LFX.GetOrder(23)  invalid takeProfit-triggered value \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // CloseTriggerTime
   sValue = StringTrim(values[14]);
   if (StringIsDigit(sValue)) datetime _closeTriggerTime = StrToInteger(sValue);
   else                                _closeTriggerTime =    StrToTime(sValue);
   if      (_closeTriggerTime < 0)                 return(!catch("LFX.GetOrder(24)  invalid close-trigger time \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else if (_closeTriggerTime > 0)
      if (_closeTriggerTime > GetGmtTime())        return(!catch("LFX.GetOrder(25)  invalid close-trigger time \""+ TimeToStr(_closeTriggerTime, TIME_FULL) +" GMT\" (current time \""+ TimeToStr(GetGmtTime(), TIME_FULL) +" GMT\") in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // CloseTime
   sValue = StringTrim(values[15]);
   if      (StringIsInteger(sValue)) datetime _closeTime =  StrToInteger(sValue);
   else if (StringStartsWith(sValue, "-"))    _closeTime = -StrToTime(StringSubstr(sValue, 1));
   else                                       _closeTime =  StrToTime(sValue);
   if (Abs(_closeTime) > GetGmtTime())             return(!catch("LFX.GetOrder(26)  invalid close time \""+ TimeToStr(Abs(_closeTime), TIME_FULL) +" GMT\" (current time \""+ TimeToStr(GetGmtTime(), TIME_FULL) +" GMT\") in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // ClosePrice
   sValue = StringTrim(values[16]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(27)  invalid close price \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _closePrice = StrToDouble(sValue);
   if (_closePrice < 0)                            return(!catch("LFX.GetOrder(28)  invalid close price \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _closePrice = NormalizeDouble(_closePrice, digits);
   if (!_closeTime && _closePrice)                 return(!catch("LFX.GetOrder(29)  close time/price mis-match 0/"+ NumberToStr(_closePrice, ".+") +" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   if (_closeTime > 0 && !_closePrice)             return(!catch("LFX.GetOrder(30)  close time/price mis-match \""+ TimeToStr(_closeTime, TIME_FULL) +"\"/0 in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OrderProfit
   sValue = StringTrim(values[17]);
   if (!StringIsNumeric(sValue))                   return(!catch("LFX.GetOrder(31)  invalid order profit \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _orderProfit = StrToDouble(sValue);
   _orderProfit = NormalizeDouble(_orderProfit, 2);

   // ModificationTime
   sValue = StringTrim(values[18]);
   if (StringIsDigit(sValue)) datetime _modificationTime = StrToInteger(sValue);
   else                                _modificationTime =    StrToTime(sValue);
   if (_modificationTime <= 0)                     return(!catch("LFX.GetOrder(32)  invalid modification time \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   if (_modificationTime > GetGmtTime())           return(!catch("LFX.GetOrder(33)  invalid modification time \""+ TimeToStr(_modificationTime, TIME_FULL) +" GMT\" (current time \""+ TimeToStr(GetGmtTime(), TIME_FULL) +" GMT\") in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // Version
   sValue = StringTrim(values[19]);
   if (!StringIsDigit(sValue))                     return(!catch("LFX.GetOrder(34)  invalid version \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   int _version = StrToInteger(sValue);
   if (_version <= 0)                              return(!catch("LFX.GetOrder(35)  invalid version \""+ sValue +"\" in order entry ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));


   // (3) Orderdaten in �bergebenes Array schreiben (erst nach vollst�ndiger erfolgreicher Validierung)
   InitializeByteBuffer(lo, LFX_ORDER.size);

   lo.setTicket             (lo,  ticket             );              // Ticket immer zuerst, damit im Struct Currency-ID und Digits ermittelt werden k�nnen
   lo.setType               (lo, _orderType          );
   lo.setUnits              (lo, _orderUnits         );
   lo.setLots               (lo,  NULL               );
   lo.setOpenEquity         (lo, _openEquity         );
   lo.setOpenTime           (lo, _openTime           );
   lo.setOpenPrice          (lo, _openPrice          );
   lo.setOpenTriggerTime    (lo, _openTriggerTime    );
   lo.setStopLoss           (lo, _stopLoss           );
   lo.setStopLossValue      (lo, _stopLossValue      );
   lo.setStopLossTriggered  (lo, _stopLossTriggered  );
   lo.setTakeProfit         (lo, _takeProfit         );
   lo.setTakeProfitValue    (lo, _takeProfitValue    );
   lo.setTakeProfitTriggered(lo, _takeProfitTriggered);
   lo.setCloseTriggerTime   (lo, _closeTriggerTime   );
   lo.setCloseTime          (lo, _closeTime          );
   lo.setClosePrice         (lo, _closePrice         );
   lo.setProfit             (lo, _orderProfit        );
   lo.setComment            (lo, _comment            );
   lo.setModificationTime   (lo, _modificationTime   );
   lo.setVersion            (lo, _version            );

   return(!catch("LFX.GetOrder(36)"));
}


// OrderType-Flags f�r LFX.GetOrders()
#define OF_OPEN                1
#define OF_CLOSED              2
#define OF_PENDINGORDER        4
#define OF_OPENPOSITION        8
#define OF_PENDINGPOSITION    16


/**
 * Gibt mehrere LFX-Orders des TradeAccounts zur�ck.
 *
 * @param  string currency   - LFX-W�hrung der Orders (default: alle W�hrungen)
 * @param  int    fSelection - Kombination von Selection-Flags (default: alle Orders werden zur�ckgegeben)
 *                             OF_OPEN            - gibt alle offenen Tickets zur�ck: Pending-Orders und offene Positionen, analog zu OrderSelect(MODE_TRADES)
 *                             OF_CLOSED          - gibt alle geschlossenen Tickets zur�ck: Trade History, analog zu OrderSelect(MODE_HISTORY)
 *                             OF_PENDINGORDER    - gibt alle herk�mmlichen Pending-Orders zur�ck: OP_BUYLIMIT, OP_BUYSTOP, OP_SELLLIMIT, OP_SELLSTOP
 *                             OF_OPENPOSITION    - gibt alle offenen Positionen zur�ck
 *                             OF_PENDINGPOSITION - gibt alle offenen Positionen mit wartendem StopLoss oder TakeProfit zur�ck
 * @param  int    los[]      - LFX_ORDER[]-Array zur Aufnahme der gelesenen Daten
 *
 * @return int - Anzahl der zur�ckgegebenen Orders oder -1 (EMPTY), falls ein Fehler auftrat
 */
int LFX.GetOrders(string currency, int fSelection, /*LFX_ORDER*/int los[][]) {
   // (1) Parametervaliderung
   int currencyId = 0;                                                     // 0: alle W�hrungen
   if (currency == "0")                                                    // (string) NULL
      currency = "";

   if (StringLen(currency) > 0) {
      currencyId = GetCurrencyId(currency);
      if (!currencyId)
         return(_EMPTY(SetLastError(stdlib.GetLastError())));
   }

   if (!fSelection)                                                        // ohne Angabe wird alles zur�ckgeben
      fSelection |= OF_OPEN | OF_CLOSED;
   if ((fSelection & OF_PENDINGORDER) && (fSelection & OF_OPENPOSITION))   // sind OF_PENDINGORDER und OF_OPENPOSITION gesetzt, werden alle OF_OPEN zur�ckgegeben
      fSelection |= OF_OPEN;

   ArrayResize(los, 0);
   int error = InitializeByteBuffer(los, LFX_ORDER.size);                  // validiert Dimensionierung
   if (IsError(error))
      return(_EMPTY(SetLastError(error)));


   // (2) alle Tickets einlesen
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccountCompany +"\\"+ tradeAccountNumber +"_config.ini";
   string section = "RemoteOrders";
   string keys[];
   int keysSize = GetIniKeys(file, section, keys);


   // (3) Orders nacheinander einlesen und gegen Currency und Selektionflags pr�fen
   int /*LFX_ORDER*/lo[];

   for (int i=0; i < keysSize; i++) {
      int ticket = StrToInteger(keys[i]);
      if (currencyId != 0)
         if (LFX.CurrencyId(ticket) != currencyId)
            continue;

      // falls ein Currency-Filter angegeben ist, sind hier alle Tickets gefiltert
      int result = LFX.GetOrder(ticket, lo);
      if (result != 1) {
         if (!result)                                                      // -1, wenn das Ticket nicht gefunden wurde
            return(EMPTY);                                                 //  0, falls ein anderer Fehler auftrat
         return(_EMPTY(catch("LFX.GetOrders(1)->LFX.GetOrder(ticket="+ ticket +")  order not found", ERR_RUNTIME_ERROR)));
      }

      bool match = false;
      while (true) {
         if (lo.IsClosed(lo)) {
            match = (fSelection & OF_CLOSED);
            break;
         }
         // ab hier immer offene Order
         if (fSelection & OF_OPEN && 1) {
            match = true;
            break;
         }
         if (lo.IsPending(lo)) {
            match = (fSelection & OF_PENDINGORDER);
            break;
         }
         // ab hier immer offene Position
         if (fSelection & OF_OPENPOSITION && 1) {
            match = true;
            break;
         }
         if (fSelection & OF_PENDINGPOSITION && 1)
            match = (lo.StopLoss(lo) || lo.TakeProfit(lo));
         break;
      }
      if (match)
         ArrayPushInts(los, lo);                                     // bei Match Order an �bergebenes LFX_ORDER-Array anf�gen
   }
   ArrayResize(keys, 0);
   ArrayResize(lo,   0);

   if (!catch("LFX.GetOrders(2)"))
      return(ArrayRange(los, 0));
   return(EMPTY);
}


/**
 * Speichert eine LFX-Order in der .ini-Datei des TradeAccounts.
 *
 * @param  LFX_ORDER los[]  - ein einzelnes oder ein Array von LFX_ORDER-Structs
 * @param  int       index  - Arrayindex der zu speichernden Order, wenn los[] ein LFX_ORDER[]-Array ist.
 *                            Der Parameter wird ignoriert, wenn los[] eine einzelne LFX_ORDER ist.
 * @param  int       fCatch - Flag mit leise zu setzenden Fehler, soda� sie vom Aufrufer behandelt werden k�nnen
 *
 * @return bool - Erfolgsstatus
 */
bool LFX.SaveOrder(/*LFX_ORDER*/int los[], int index=NULL, int fCatch=NULL) {
   // (1) �bergebene Order in eine einzelne Order umkopieren (Parameter los[] kann unterschiedliche Dimensionen haben)
   int dims = ArrayDimension(los); if (dims > 2)   return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(1)  invalid dimensions of parameter los = "+ dims, ERR_INCOMPATIBLE_ARRAYS, fCatch));

   /*LFX_ORDER*/int lo[]; ArrayResize(lo, LFX_ORDER.intSize);
   if (dims == 1) {
      // Parameter los[] ist einzelne Order
      if (ArrayRange(los, 0) != LFX_ORDER.intSize) return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(2)  invalid size of parameter los["+ ArrayRange(los, 0) +"]", ERR_INCOMPATIBLE_ARRAYS, fCatch));
      ArrayCopy(lo, los);
   }
   else {
      // Parameter los[] ist Order-Array
      if (ArrayRange(los, 1) != LFX_ORDER.intSize) return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(3)  invalid size of parameter los["+ ArrayRange(los, 0) +"]["+ ArrayRange(los, 1) +"]", ERR_INCOMPATIBLE_ARRAYS, fCatch));
      int losSize = ArrayRange(los, 0);
      if (index < 0 || index > losSize-1)          return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(4)  invalid parameter index = "+ index, ERR_ARRAY_INDEX_OUT_OF_RANGE, fCatch));
      int src  = GetIntsAddress(los) + index*LFX_ORDER.intSize*4;
      int dest = GetIntsAddress(lo);
      CopyMemory(dest, src, LFX_ORDER.intSize*4);
   }


   // (2) Aktuell gespeicherte Version der Order holen und konkurrierende Schreibzugriffe erkennen und behandeln
   /*LFX_ORDER*/int stored[], ticket=lo.Ticket(lo);
   int result = LFX.GetOrder(ticket, stored);                        // +1, wenn die Order erfolgreich gelesen wurden
   if (!result) return(false);                                       // -1, wenn die Order nicht gefunden wurde
   if (result > 0) {                                                 //  0, falls ein anderer Fehler auftrat
      if (lo.Version(stored) > lo.Version(lo))     return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(5)  concurrent modification of #"+ ticket +", expected version "+ lo.Version(lo) +" of '"+ TimeToStr(lo.ModificationTime(lo), TIME_FULL) +"', found version "+ lo.Version(stored) +" of '"+ TimeToStr(lo.ModificationTime(stored), TIME_FULL) +"'", ERR_CONCURRENT_MODIFICATION, fCatch));
   }


   // (3) Daten formatieren
   //Ticket = Symbol, Comment, OrderType, Units, OpenEquity, OpenTime, OpenPrice, OpenTriggerTime, StopLoss, StopLossValue, StopLossTriggered, TakeProfit, TakeProfitValue, TakeProfitTriggered, CloseTriggerTime, CloseTime, ClosePrice, Profit, ModificationTime, Version
   string sSymbol              =                          lo.Currency           (lo);
   string sComment             =                          lo.Comment            (lo);                                                                                               sComment          = StringPadRight(sComment         , 13, " ");
   string sOperationType       = OperationTypeDescription(lo.Type               (lo));                                                                                              sOperationType    = StringPadRight(sOperationType   , 10, " ");
   string sUnits               =              NumberToStr(lo.Units              (lo), ".+");                                                                                        sUnits            = StringPadLeft (sUnits           ,  5, " ");
   string sOpenEquity          =                ifString(!lo.OpenEquity         (lo), "0", DoubleToStr(lo.OpenEquity(lo), 2));                                                      sOpenEquity       = StringPadLeft (sOpenEquity      , 10, " ");
   string sOpenTime            =                 ifString(lo.OpenTime           (lo) < 0, "-", "") + TimeToStr(Abs(lo.OpenTime(lo)), TIME_FULL);                                    sOpenTime         = StringPadLeft (sOpenTime        , 20, " ");
   string sOpenPrice           =              DoubleToStr(lo.OpenPrice          (lo), lo.Digits(lo));                                                                               sOpenPrice        = StringPadLeft (sOpenPrice       ,  9, " ");
   string sOpenTriggerTime     =                ifString(!lo.OpenTriggerTime    (lo), "0", TimeToStr(lo.OpenTriggerTime(lo), TIME_FULL));                                           sOpenTriggerTime  = StringPadLeft (sOpenTriggerTime , 19, " ");
   string sStopLoss            =                ifString(!lo.StopLoss           (lo), "0", DoubleToStr(lo.StopLoss(lo), lo.Digits(lo)));                                            sStopLoss         = StringPadLeft (sStopLoss        ,  7, " ");
   string sStopLossValue       =                 ifString(lo.StopLossValue      (lo)==EMPTY_VALUE, "", DoubleToStr(lo.StopLossValue(lo), 2));                                       sStopLossValue    = StringPadLeft (sStopLossValue   ,  8, " ");
   string sStopLossTriggered   =                         (lo.StopLossTriggered  (lo)!=0);
   string sTakeProfit          =                ifString(!lo.TakeProfit         (lo), "0", DoubleToStr(lo.TakeProfit(lo), lo.Digits(lo)));                                          sTakeProfit       = StringPadLeft (sTakeProfit      ,  7, " ");
   string sTakeProfitValue     =                 ifString(lo.TakeProfitValue    (lo)==EMPTY_VALUE, "", DoubleToStr(lo.TakeProfitValue(lo), 2));                                     sTakeProfitValue  = StringPadLeft (sTakeProfitValue ,  8, " ");
   string sTakeProfitTriggered =                         (lo.TakeProfitTriggered(lo)!=0);
   string sCloseTriggerTime    =                ifString(!lo.CloseTriggerTime   (lo), "0", TimeToStr(lo.CloseTriggerTime(lo), TIME_FULL));                                          sCloseTriggerTime = StringPadLeft (sCloseTriggerTime, 19, " ");
   string sCloseTime           =                 ifString(lo.CloseTime          (lo) < 0, "-", "") + ifString(!lo.CloseTime(lo), "0", TimeToStr(Abs(lo.CloseTime(lo)), TIME_FULL)); sCloseTime        = StringPadLeft (sCloseTime       , 20, " ");
   string sClosePrice          =                ifString(!lo.ClosePrice         (lo), "0", DoubleToStr(lo.ClosePrice(lo), lo.Digits(lo)));                                          sClosePrice       = StringPadLeft (sClosePrice      , 10, " ");
   string sProfit              =                ifString(!lo.Profit             (lo), "0", DoubleToStr(lo.Profit(lo), 2));                                                          sProfit           = StringPadLeft (sProfit          ,  7, " ");

     datetime modificationTime = TimeGMT(); if (!modificationTime) return(false);
     int      version          = lo.Version(lo) + 1;

   string sModificationTime    = TimeToStr(modificationTime, TIME_FULL);
   string sVersion             = version;


   // (4) Daten schreiben
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccountCompany +"\\"+ tradeAccountNumber +"_config.ini";
   string section = "RemoteOrders";
   string key     = ticket;
   string value   = StringConcatenate(sSymbol, ", ", sComment, ", ", sOperationType, ", ", sUnits, ", ", sOpenEquity, ", ", sOpenTime, ", ", sOpenPrice, ", ", sOpenTriggerTime, ", ", sStopLoss, ", ", sStopLossValue, ", ", sStopLossTriggered, ", ", sTakeProfit, ", ", sTakeProfitValue, ", ", sTakeProfitTriggered, ", ", sCloseTriggerTime, ", ", sCloseTime, ", ", sClosePrice, ", ", sProfit, ", ", sModificationTime, ", ", sVersion);

   if (!WritePrivateProfileStringA(section, key, " "+ value, file))
      return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(6)->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=\""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\", fileName=\""+ file +"\")", ERR_WIN32_ERROR, fCatch));


   // (5) Version der �bergebenen Order aktualisieren
   if (dims == 1) {  lo.setModificationTime(los,        modificationTime);  lo.setVersion(los,        version); }
   else           { los.setModificationTime(los, index, modificationTime); los.setVersion(los, index, version); }
   return(true);
}


/**
 * Speichert die �bergebenen LFX-Orders in der .ini-Datei des TradeAccounts.
 *
 * @param  LFX_ORDER los[] - Array von LFX_ORDER-Structs
 *
 * @return bool - Erfolgsstatus
 */
bool LFX.SaveOrders(/*LFX_ORDER*/int los[][]) {
   int size = ArrayRange(los, 0);
   for (int i=0; i < size; i++) {
      if (!LFX.SaveOrder(los, i))
         return(false);
   }
   return(true);
}


/**
 * "Exception"-Handler f�r in LFX.SaveOrder() aufgetretene Fehler. Die angegebenen abzufangenden Fehler werden nur "leise" gesetzt,
 * wodurch eine individuelle Behandlung durch den Aufrufer m�glich wird.
 *
 * @param  string message - Fehlermeldung
 * @param  int    error   - der aufgetretene Fehler
 * @param  int    fCatch  - Flag mit leise zu setzenden Fehlern
 *
 * @return int - derselbe Fehler
 *
 * @private
 */
int __LFX.SaveOrder.HandleError(string message, int error, int fCatch) {
   if (!error)
      return(NO_ERROR);
   SetLastError(error);

   // (1) die angegebenen Fehler "leise" abfangen
   if (fCatch & MUTE_ERR_CONCUR_MODIFICATION && 1) {
      if (error == ERR_CONCURRENT_MODIFICATION) {
         if (__LOG) log(message, error);
         return(error);
      }
   }

   // (2) f�r alle restlichen Fehler harten Laufzeitfehler ausl�sen
   return(catch(message, error));
}


/**
 * Dummy-Calls: unterdr�cken unn�tze Compilerwarnungen
 */
void DummyCalls() {
   int    iNull, iNulls[];
   double dNull;
   string sNull;
   LFX.CurrencyId(NULL);
   LFX.GetOrder(NULL, iNulls);
   LFX.GetOrders(NULL, NULL, iNulls);
   LFX.InstanceId(NULL);
   LFX.IsMyOrder();
   LFX.SaveOrder(iNulls, NULL);
   LFX.SaveOrders(iNulls);
   LFX_ORDER.toStr(iNulls);
}


#import "stdlib1.ex4"
   int      ArrayPushInts(int array[][], int values[]);
   int      GetAccountNumber();
   string   GetCurrency(int id);
   int      GetCurrencyId(string currency);
   bool     IsIniKey(string fileName, string section, string key);
   bool     IsPendingTradeOperation(int value);
   bool     IsTradeOperation(int value);
   string   OperationTypeDescription(int type);
   string   OperationTypeToStr(int type);
   string   StringReplace.Recursive(string object, string search, string replace);
   int      StrToOperationType(string value);

#import "stdlib2.ex4"
   int      GetIniKeys(string fileName, string section, string names[]);
#import
