/**
 *  Format der LFX-MagicNumber:
 *  ---------------------------
 *  Strategy-Id:  10 bit (Bit 23-32) => Bereich 101-1023
 *  Currency-Id:   4 bit (Bit 19-22) => Bereich   1-15               entspricht stdlib::GetCurrencyId()
 *  Units:         4 bit (Bit 15-18) => Bereich   1-15               Vielfaches von 0.1 von 1 bis 10           // wird in MagicNumber nicht mehr verwendet
 *  Instance-ID:  10 bit (Bit  5-14) => Bereich   1-1023
 *  Counter:       4 bit (Bit  1-4 ) => Bereich   1-15                                                         // wird in MagicNumber nicht mehr verwendet
 */
#define STRATEGY_ID   102                                            // eindeutige ID der Strategie (Bereich 101-1023)


bool   mode.intern.trading = true;  // Default                       // Visualisierung, Orderdaten aus und Trading im aktuellen Account
bool   mode.remote.trading;                                          // Visualisierung im aktuellen Account, Orderdaten aus und Trading im entferntem Account
bool   mode.extern.notrading;                                        // Visualisierung im aktuellen Account, Orderdaten aus entferntem Account, kein Trading

string tradeAccount.company  = "";
int    tradeAccount.number;
string tradeAccount.currency = "";
int    tradeAccount.type;                                            // ACCOUNT_TYPE_DEMO|ACCOUNT_TYPE_REAL
string tradeAccount.name     = "";                                   // Inhaber
string tradeAccount.alias    = "";                                   // Alias f�r Logs, SMS etc.


string lfxCurrency = "";
int    lfxCurrencyId;
int    lfxOrders[][LFX_ORDER.intSize];                               // Array von LFX_ORDERs


#define NO_LIMIT_TRIGGERED         -1                                // Limitkontrolle
#define OPEN_LIMIT_TRIGGERED        1
#define STOPLOSS_LIMIT_TRIGGERED    2
#define TAKEPROFIT_LIMIT_TRIGGERED  3


// Trade-Terminal -> LFX-Terminal: P/L-Messages
string  qc.TradeToLfxChannels[9];                                    // ein Channel je LFX-W�hrung bzw. LFX-Chart
int    hQC.TradeToLfxSenders [9];                                    // jeweils ein Sender
string  qc.TradeToLfxChannel;                                        // Channel des aktuellen LFX-Charts (einer)
int    hQC.TradeToLfxReceiver;                                       // Receiver des aktuellen LFX-Charts (einer)


// LFX-Terminal -> Trade-Terminal: TradeCommands
string  qc.TradeCmdChannel;
int    hQC.TradeCmdSender;
int    hQC.TradeCmdReceiver;


/**
 * Initialisiert die Statusvariablen des zu verwendenden Trade-Accounts. Dazu wird die entsprechende TradeAccount-Konfiguration ausgewertet
 * und ein angegebener Account-Parameter vorrangig behandelt.
 *
 * @param  string accountKey - Account-Identifier im Format "{AccountCompany}:{Account}"
 *                             � {AccountCompany} kann ein String (CompanyName) oder ein Integer (CompanyID) sein
 *                             � {Account} kann ein String (AccountAlias) oder ein Integer (AccountNumber) sein. Ist dieser Wert ein Alias,
 *                               mu� dieser Alias f�r die AccountCompany eindeutig sein.
 *
 * @return bool - Erfolgsstatus. Nicht, ob ein angegebener Schl�ssel einen g�ltigen Account darstellt. Ist ein angegebener Schl�ssel ung�ltig,
 *                �ndert sich der selektierte TradeAccount nicht.
 */
bool InitTradeAccount(string accountKey="") {
   if (accountKey == "0")                                            // (string) NULL
      accountKey = "";

   // Im Verlauf modifizierte (globale) Variablen
   // -------------------------------------------
   // bool   mode.intern.trading;
   // bool   mode.remote.trading;
   // bool   mode.extern.notrading;
   //
   // string tradeAccount.company;
   // int    tradeAccount.number;
   // string tradeAccount.currency;
   // int    tradeAccount.type;
   // string tradeAccount.name;
   // string tradeAccount.alias;

   string _accountCompany;
   int    _accountNumber;
   string _accountCurrency;
   int    _accountType;
   string _accountName;
   string _accountAlias;


   if (!StringLen(accountKey)) {
      // (1) kein Account-Parameter angegeben: aktuellen Account bestimmen und durch einen ggf. konfigurierten TradeAccount ersetzen
      _accountCompany = ShortAccountCompany(); if (!StringLen(_accountCompany))                                   return(false);
      _accountNumber  = GetAccountNumber();    if (!_accountNumber)                                               return(false);

      string mqlDir  = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
      string file    = TerminalPath() + mqlDir +"\\files\\"+ _accountCompany +"\\"+ _accountNumber +"_config.ini";
      string section = "General";
      string key     = "TradeAccount" + ifString(This.IsTesting(), ".Tester", "");

      string sValue = GetIniString(file, section, key);
      if (StringLen(sValue) > 0) {
         if (!StringIsDigit(sValue))                                                                              return(_true(warn("InitTradeAccount(1)  invalid trade account setting ["+ section +"]->"+ key +" = \""+ sValue +"\"")));
         _accountNumber = StrToInteger(sValue); if (!_accountNumber)                                              return(_true(warn("InitTradeAccount(2)  invalid trade account setting ["+ section +"]->"+ key +" = \""+ sValue +"\"")));

         section = "Accounts";
         key     = _accountNumber +".company";
         sValue  = GetGlobalConfigString(section, key); if (!StringLen(sValue))                                   return(_true(warn("InitTradeAccount(3)  missing global account setting ["+ section +"]->"+ key)));
         _accountCompany = sValue;
      }
   }
   else {
      // (2) Account-Parameter validieren und Account ermitteln
      string sCompanyKey = StringLeftTo   (accountKey, ":"); if (!StringLen(sCompanyKey))                         return(_true(warn("InitTradeAccount(4)  invalid parameter accountKey = \""+ accountKey +"\"")));
      string sAccountKey = StringRightFrom(accountKey, ":"); if (!StringLen(sAccountKey))                         return(_true(warn("InitTradeAccount(5)  invalid parameter accountKey = \""+ accountKey +"\"")));

      bool sCompanyKey.isDigit = StringIsDigit(sCompanyKey);
      bool sAccountKey.isDigit = StringIsDigit(sAccountKey);

      // (2.1) sCompanyKey zuordnen
      if (sCompanyKey.isDigit) {
         _accountCompany = ShortAccountCompanyFromId(StrToInteger(sCompanyKey)); if (!StringLen(_accountCompany)) return(_true(warn("InitTradeAccount(6)  unsupported account key = \""+ accountKey +"\"")));
      }
      else {
         _accountCompany = sCompanyKey; if (!IsShortAccountCompany(_accountCompany))                              return(_true(warn("InitTradeAccount(7)  unsupported account key = \""+ accountKey +"\"")));
      }

      // (2.2) sAccountKey zuordnen
      if (sAccountKey.isDigit) {
         _accountNumber = StrToInteger(sAccountKey); if (!_accountNumber)                                         return(_true(warn("InitTradeAccount(8)  invalid parameter accountKey = \""+ accountKey +"\"")));
      }
      else {
         _accountNumber = AccountNumberFromAlias(_accountCompany, sAccountKey); if (!_accountNumber)              return(_true(warn("InitTradeAccount(9)  unsupported account key = \""+ accountKey +"\"")));
      }
   }


   // (3) Abbruch, wenn der ermittelte Account bereits selektiert ist
   if (tradeAccount.company==_accountCompany && tradeAccount.number==_accountNumber)
      return(true);


   // (4) Restliche Variablen ermitteln
   _accountAlias = AccountAlias(_accountCompany, _accountNumber); if (!StringLen(_accountAlias))                  return(_true(warn("InitTradeAccount(10)  missing account alias for account \""+ _accountCompany +":"+ _accountNumber +"\"")));

   if (StringCompareI(_accountCompany, AC.SimpleTrader)) {
      // (4.1) SimpleTrader-Account
      mqlDir = ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
      file   = TerminalPath() + mqlDir +"\\files\\"+ _accountCompany +"\\"+ _accountAlias +"_config.ini";
      if (!IsFile(file))                                                                                          return(_true(warn("InitTradeAccount(11)  account configuration file not found \""+ file +"\"")));

      // AccountCurrency
      section = "General";
      key     = "Account.Currency";
      sValue  = GetIniString(file, section, key); if (!StringLen(sValue))                                         return(_true(warn("InitTradeAccount(12)  missing account setting ["+ section +"]->"+ key +" for SimpleTrader account \""+ _accountAlias +"\"")));
      if (!IsCurrency(sValue))                                                                                    return(_true(warn("InitTradeAccount(13)  invalid account setting ["+ section +"]->"+ key +" = \""+ sValue +"\" for SimpleTrader account \""+ _accountAlias +"\"" )));
      _accountCurrency = StringToUpper(sValue);

      // AccountType
      _accountType = ACCOUNT_TYPE_DEMO;         // bei SimpleTrader immer DEMO

      // AccountName
      section = "General";
      key     = "Account.Name";
      sValue  = GetIniString(file, section, key); if (!StringLen(sValue))                                         return(_true(warn("InitTradeAccount(14)  missing account setting ["+ section +"]->"+ key +" for SimpleTrader account \""+ _accountAlias +"\"")));
      _accountName = sValue;
   }

   else {
      // (4.2) regul�rer Account
      // AccountCurrency
      section = "Accounts";
      key     = _accountNumber +".currency";
      sValue  = GetGlobalConfigString(section, key); if (!StringLen(sValue))                                      return(_true(warn("InitTradeAccount(15)  missing global account setting ["+ section +"]->"+ key)));
      if (!IsCurrency(sValue))                                                                                    return(_true(warn("InitTradeAccount(16)  invalid global account setting ["+ section +"]->"+ key +" = \""+ sValue +"\"")));
      _accountCurrency = StringToUpper(sValue);

      // AccountType
      section = "Accounts";
      key     = _accountNumber +".type";
      sValue  = StringToLower(GetGlobalConfigString(section, key)); if (!StringLen(sValue))                       return(_true(warn("InitTradeAccount(17)  missing global account setting ["+ section +"]->"+ key)));
      if      (sValue == "demo") _accountType = ACCOUNT_TYPE_DEMO;
      else if (sValue == "real") _accountType = ACCOUNT_TYPE_REAL; else                                           return(_true(warn("InitTradeAccount(18)  invalid global account setting ["+ section +"]->"+ key +" = \""+ GetGlobalConfigString(section, key) +"\"")));

      // AccountName
      section = "Accounts";
      key     = _accountNumber +".name";
      sValue  = GetGlobalConfigString(section, key); if (!StringLen(sValue))                                      return(_true(warn("InitTradeAccount(19)  missing global account setting ["+ section +"]->"+ key)));
      _accountName = sValue;
   }


   // (5) globale Variablen erst nach vollst�ndiger erfolgreicher Validierung �berschreiben
   mode.extern.notrading = StringCompareI(_accountCompany, AC.SimpleTrader);
   mode.intern.trading   = (_accountCompany==ShortAccountCompany() && _accountNumber==GetAccountNumber());
   mode.remote.trading   = !mode.intern.trading && !mode.extern.notrading;

   tradeAccount.company  = _accountCompany;
   tradeAccount.number   = _accountNumber;
   tradeAccount.currency = _accountCurrency;
   tradeAccount.type     = _accountType;
   tradeAccount.name     = _accountName;
   tradeAccount.alias    = _accountAlias;

   if (mode.remote.trading) {
      if (StringEndsWith(Symbol(), "LFX")) {
         lfxCurrency   = StringLeft(Symbol(), -3);                   // TODO: lfx-Variablen durch Symbol() ersetzen
         lfxCurrencyId = GetCurrencyId(lfxCurrency);
      }
   }
   return(true);
}


/**
 * Ob das aktuell selektierte Ticket eine LFX-Order ist.
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
 * @return int - Currency-ID, entsprechend std::GetCurrencyId()
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
 * Erzeugt eine neue Instanz-ID.
 *
 * @param  LFX_ORDER orders[] - Array von LFX_ORDERs. Die generierte Instanz-ID wird unter Ber�cksichtigung dieser Orders eindeutig sein.
 *
 * @return int - Instanz-ID im Bereich 1-1023 (10 bit)
 */
int LFX.CreateInstanceId(/*LFX_ORDER*/int orders[][]) {
   int id, ids[], size=ArrayRange(orders, 0);
   ArrayResize(ids, 0);

   for (int i=0; i < size; i++) {
      ArrayPushInt(ids, LFX.InstanceId(los.Ticket(orders, i)));
   }

   MathSrand(GetTickCount());
   while (!id) {
      id = MathRand();
      while (id > 1023) {
         id >>= 1;
      }
      if (IntInArray(ids, id))                                       // sicherstellen, da� die ID nicht gerade benutzt wird
         id = 0;
   }
   return(id);
}


/**
 * Generiert eine neue LFX-Ticket-ID (Wert f�r OrderMagicNumber().
 *
 * @param  LFX_ORDER orders[] - Array von LFX_ORDERs. Das generierte Ticket wird unter Ber�cksichtigung dieser Orders eindeutig sein.
 * @param  string    currency - LFX-W�hrung, f�r die eine Ticket-ID erzeugt werden soll.
 *
 * @return int - LFX-Ticket-ID oder NULL, falls ein Fehler auftrat
 */
int LFX.CreateMagicNumber(/*LFX_ORDER*/int orders[][], string currency) {
   int iStrategy = STRATEGY_ID & 0x3FF << 22;                        // 10 bit (Bits 23-32)
   int iCurrency = GetCurrencyId(currency) & 0xF << 18;              //  4 bit (Bits 19-22)
   int iInstance = LFX.CreateInstanceId(orders) & 0x3FF << 4;        // 10 bit (Bits  5-14)
   return(iStrategy + iCurrency + iInstance);
}


/**
 * Gibt den gr��ten existierenden Marker der offenen Orders des angegebenen Symbols zur�ck.
 *
 * @param  LFX_ORDER orders[]   - Array von LFX_ORDERs
 * @param  int       currencyId - W�hrungs-ID
 *
 * @return int - positive Ganzzahl oder 0, falls keine markierte Order existiert
 */
int LFX.GetMaxOpenOrderMarker(/*LFX_ORDER*/int orders[][], int currencyId) {
   int marker, size=ArrayRange(orders, 0);

   for (int i=0; i < size; i++) {
      if (los.CurrencyId(orders, i) != currencyId) continue;
      if (los.IsClosed  (orders, i))               continue;

      string comment = los.Comment(orders, i);
      if      (StringStartsWith(comment, los.Currency(orders, i) +".")) comment = StringRightFrom(comment, ".");
      else if (StringStartsWith(comment, "#"))                          comment = StringRight    (comment,  -1);
      else
         continue;
      marker = Max(marker, StrToInteger(comment));
   }
   return(marker);
}


/**
 * Ob die angegebene LFX-Order eines ihrer konfigurierten Limite erreicht hat.
 *
 * @param  _In_     LFX_ORDER orders[] - Array von LFX-ORDERs
 * @param  _In_     int       i        - Index der zu pr�fenden Order innerhalb des �bergebenen LFX_ORDER-Arrays
 * @param  _In_opt_ double    bid      - zur Pr�fung zu benutzender Bid-Preis bei Price-Limits   (NULL:        keine Limitpr�fung gegen den Bid-Preis)
 * @param  _In_opt_ double    ask      - zur Pr�fung zu benutzender Ask-Preis bei Price-Limits   (NULL:        keine Limitpr�fung gegen den Ask-Preis)
 * @param  _In_opt_ double    profit   - zur Pr�fung zu benutzender P/L-Betrag bei Profit-Limits (EMPTY_VALUE: keine Limitpr�fung von Profitbetr�gen )
 *
 * @return int - Triggerstatus, NO_LIMIT_TRIGGERED:         wenn kein Limit erreicht wurde
 *                              OPEN_LIMIT_TRIGGERED:       wenn ein Entry-Limit erreicht wurde
 *                              STOPLOSS_LIMIT_TRIGGERED:   wenn ein StopLoss-Limit erreicht wurde
 *                              TAKEPROFIT_LIMIT_TRIGGERED: wenn ein TakeProfit-Limit erreicht wurde
 *                              0 (zero):                   wenn ein Fehler auftrat
 *
 * Nachdem ein Limit getriggert wurde, wird bis zum Eintreffen der Ausf�hrungsbest�tigung derselbe Triggerstatus zur�ckgegeben.
 */
int LFX.CheckLimits(/*LFX_ORDER*/int orders[][], int i, double bid, double ask, double profit) {
   if (los.IsClosed(orders, i)) return(NO_LIMIT_TRIGGERED);


   // (1) fehlerhafte Orders und bereits getriggerte Limits (auf Ausf�hrungsbest�tigung wartende Order) abfangen
   int type = los.Type(orders, i);
   switch (type) {
      case OP_BUYLIMIT :
      case OP_BUYSTOP  :
      case OP_SELLLIMIT:
      case OP_SELLSTOP :
         if (los.IsOpenError    (orders, i))        return(NO_LIMIT_TRIGGERED);
         if (los.OpenTriggerTime(orders, i) != 0)   return(OPEN_LIMIT_TRIGGERED);
         break;

      case OP_BUY :
      case OP_SELL:
         if (los.IsCloseError(orders, i))           return(NO_LIMIT_TRIGGERED);
         if (los.CloseTriggerTime(orders, i) != 0) {
            if (los.StopLossTriggered  (orders, i)) return(STOPLOSS_LIMIT_TRIGGERED  );
            if (los.TakeProfitTriggered(orders, i)) return(TAKEPROFIT_LIMIT_TRIGGERED);
            return(_NULL(catch("LFX.CheckLimits(1)  business rule violation in #"+ los.Ticket(orders, i) +": closeTriggerTime="+ los.CloseTriggerTime(orders, i) +", slTriggered=false, tpTriggered=false", ERR_RUNTIME_ERROR)));
         }
         break;

      default:
         return(NO_LIMIT_TRIGGERED);
   }


   // (2) Open-Limits pr�fen
   int digits = los.Digits(orders, i);
   switch (type) {
      case OP_BUYLIMIT:
      case OP_SELLSTOP:
         if (ask!=NULL) /*&&*/ if (LE(ask, los.OpenPrice(orders, i), digits)) {
            los.setClosePrice(orders, i, ask);
            return(OPEN_LIMIT_TRIGGERED);
         }
         return(NO_LIMIT_TRIGGERED);

      case OP_SELLLIMIT:
      case OP_BUYSTOP  :
         if (bid!=NULL) /*&&*/ if (GE(bid, los.OpenPrice(orders, i), digits)) {
            los.setClosePrice(orders, i, bid);
            return(OPEN_LIMIT_TRIGGERED);
         }
         return(NO_LIMIT_TRIGGERED);
   }


   // (3) Close-Limits pr�fen
   if (los.IsStopLoss(orders, i)) {
      switch (type) {
         case OP_BUY:
            if (ask!=NULL) /*&&*/ if (los.IsStopLossPrice(orders, i)) /*&&*/ if (LE(ask, los.StopLossPrice(orders, i), digits)) {
               los.setClosePrice(orders, i, ask        );
               los.setProfit    (orders, i, EMPTY_VALUE);
               return(STOPLOSS_LIMIT_TRIGGERED);
            }
            break;

         case OP_SELL:
            if (bid!=NULL) /*&&*/ if (los.IsStopLossPrice(orders, i)) /*&&*/ if (GE(bid, los.StopLossPrice(orders, i), digits)) {
               los.setClosePrice(orders, i, bid        );
               los.setProfit    (orders, i, EMPTY_VALUE);
               return(STOPLOSS_LIMIT_TRIGGERED);
            }
            break;
      }
      if (profit != EMPTY_VALUE) {
         if (los.IsStopLossValue(orders, i)) /*&&*/ if (LE(profit, los.StopLossValue(orders, i), 2)) {
            los.setClosePrice(orders, i, NULL  );
            los.setProfit    (orders, i, profit);
            return(STOPLOSS_LIMIT_TRIGGERED);
         }
         if (los.IsStopLossPercent(orders, i)) /*&&*/ if (LE(profit/los.OpenEquity(orders, i)*100, los.StopLossPercent(orders, i), 2)) {
            los.setClosePrice(orders, i, NULL  );
            los.setProfit    (orders, i, profit);
            return(STOPLOSS_LIMIT_TRIGGERED);
         }
      }
   }

   if (los.IsTakeProfit(orders, i)) {
      switch (type) {
         case OP_BUY:
            if (bid!=NULL) /*&&*/ if (los.IsTakeProfitPrice(orders, i)) /*&&*/ if (GE(bid, los.TakeProfitPrice(orders, i), digits)) {
               los.setClosePrice(orders, i, bid        );
               los.setProfit    (orders, i, EMPTY_VALUE);
               return(TAKEPROFIT_LIMIT_TRIGGERED);
            }
            break;

         case OP_SELL:
            if (ask!=NULL) /*&&*/ if (los.IsTakeProfitPrice(orders, i)) /*&&*/ if (LE(ask, los.TakeProfitPrice(orders, i), digits)) {
               los.setClosePrice(orders, i, ask        );
               los.setProfit    (orders, i, EMPTY_VALUE);
               return(TAKEPROFIT_LIMIT_TRIGGERED);
            }
            break;
      }
      if (profit != EMPTY_VALUE) {
         if (los.IsTakeProfitValue(orders, i)) /*&&*/ if (GE(profit, los.TakeProfitValue(orders, i), 2)) {
            los.setClosePrice(orders, i, NULL  );
            los.setProfit    (orders, i, profit);
            return(TAKEPROFIT_LIMIT_TRIGGERED);
         }
         if (los.IsTakeProfitPercent(orders, i)) /*&&*/ if (GE(profit/los.OpenEquity(orders, i)*100, los.TakeProfitPercent(orders, i), 2)) {
            los.setClosePrice(orders, i, NULL  );
            los.setProfit    (orders, i, profit);
            return(TAKEPROFIT_LIMIT_TRIGGERED);
         }
      }
   }

   return(NO_LIMIT_TRIGGERED);
}


/**
 * Verarbeitet das getriggerte Limit einer LFX-Order. Schickt dem TradeTerminal ein TradeCommand zur Orderausf�hrung und pr�ft diese.
 *
 * @param  LFX_ORDER orders[]  - Array von LFX_ORDERs
 * @param  int       i         - Index der getriggerten Order innerhalb des �bergebenen LFX_ORDER-Arrays
 * @param  int       limitType - Typ des getriggerten Limits
 *
 * @return bool - Erfolgsstatus
 */
bool LFX.SendTradeCommand(/*LFX_ORDER*/int orders[][], int i, int limitType) {
   string   symbol.i = los.Currency(orders, i) +"."+ StrToInteger(StringRight(los.Comment(orders, i), -1));
   string   logMsg, trigger, limitValue="", currentValue="", separator="", limitPercent="", currentPercent="", priceFormat="R.4'";
   int      /*LFX_ORDER*/order[];
   datetime triggerTime, now=TimeFXT(); if (!now) return(false);

   switch (limitType) {
      case NO_LIMIT_TRIGGERED: return(true);

      case OPEN_LIMIT_TRIGGERED:
         triggerTime = los.OpenTriggerTime(orders, i); break;

      case STOPLOSS_LIMIT_TRIGGERED:
      case TAKEPROFIT_LIMIT_TRIGGERED:
         triggerTime = los.CloseTriggerTime(orders, i); break;

      default:
         return(!catch("LFX.SendTradeCommand(1)  invalid parameter limitType = "+ limitType +" (no limit type)", ERR_INVALID_PARAMETER));
   }

   /*
   �berblick:
   ----------
   if (!triggerTime) {
      // (1) Das Limit wurde gerade getriggert (w�hrend des aktuellen Ticks), die Orderausf�hrung noch nicht eingeleitet.
   }
   else if (now < triggerTime + 30*SECONDS) {
      // (2) Die Orderausf�hrung wurde eingeleitet und wir warten auf die Ausf�hrungsbest�tigung.
   }
   else {
      // (3) Die Orderausf�hrung wurde eingeleitet und die Ausf�hrungsbest�tigung ist �berf�llig.
   }
   */

   // F�r F�lle (1) und (3) die Bestandteile eines Betrags-Limits einer Close-Logmessage definieren
   if (now >= triggerTime + 30*SECONDS) {                                              // schlie�t !triggerTime mit ein
      if (limitType == STOPLOSS_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i)) {
            if (los.IsStopLossValue  (orders, i)) { limitValue   = DoubleToStr(los.StopLossValue  (orders, i), 2);      currentValue   = DoubleToStr(los.Profit(orders, i), 2); }
            if (los.IsStopLossPercent(orders, i)) { limitPercent = DoubleToStr(los.StopLossPercent(orders, i), 2) +"%"; currentPercent = DoubleToStr(los.Profit(orders, i)/los.OpenEquity(orders, i)*100, 2) +"%"; }
            if (los.IsStopLossValue(orders, i) && los.IsStopLossPercent(orders, i)) separator = "|";
         }
      }
      if (limitType == TAKEPROFIT_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i)) {
            if (los.IsTakeProfitValue  (orders, i)) { limitValue   = DoubleToStr(los.TakeProfitValue  (orders, i), 2);      currentValue   = DoubleToStr(los.Profit(orders, i), 2); }
            if (los.IsTakeProfitPercent(orders, i)) { limitPercent = DoubleToStr(los.TakeProfitPercent(orders, i), 2) +"%"; currentPercent = DoubleToStr(los.Profit(orders, i)/los.OpenEquity(orders, i)*100, 2) +"%"; }
            if (los.IsTakeProfitValue(orders, i) && los.IsTakeProfitPercent(orders, i)) separator = "|";
         }
      }
   }


   if (!triggerTime) {
      // (1.1) Die Orderausf�hrung wurde noch nicht eingeleitet. Logmessage zusammenstellen und loggen
      if (limitType == OPEN_LIMIT_TRIGGERED) { trigger = StringToLower(OperationTypeDescription(los.Type(orders, i))) +" at "+ NumberToStr(los.OpenPrice(orders, i), priceFormat) +" triggered"; logMsg = trigger +" (current="+ NumberToStr(los.ClosePrice(orders, i), priceFormat) +")"; }
      if (limitType == STOPLOSS_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i))     { trigger = "SL amount of "+ limitValue + separator + limitPercent +" triggered";                                                                   logMsg = trigger +" (current="+ currentValue + separator + currentPercent +")";           }
         else                                { trigger = "SL price at "+ NumberToStr(los.StopLossPrice(orders, i), priceFormat) +" triggered";                                                   logMsg = trigger +" (current="+ NumberToStr(los.ClosePrice(orders, i), priceFormat) +")"; }
      }
      if (limitType == TAKEPROFIT_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i))     { trigger = "TP amount of "+ limitValue + separator + limitPercent +" triggered";                                                                   logMsg = trigger +" (current="+ currentValue + separator + currentPercent +")";           }
         else                                { trigger = "TP price at "+ NumberToStr(los.TakeProfitPrice(orders, i), priceFormat) +" triggered";                                                 logMsg = trigger +" (current="+ NumberToStr(los.ClosePrice(orders, i), priceFormat) +")"; }
      }
      logMsg = symbol.i +" #"+ los.Ticket(orders, i) +" "+ logMsg;
      log("LFX.SendTradeCommand(2)  "+ logMsg);

      // (1.2) Ausl�sen speichern und TradeCommand verschicken
      if (limitType == OPEN_LIMIT_TRIGGERED)        los.setOpenTriggerTime    (orders, i, now );
      else {                                        los.setCloseTriggerTime   (orders, i, now );
         if (limitType == STOPLOSS_LIMIT_TRIGGERED) los.setStopLossTriggered  (orders, i, true);
         else                                       los.setTakeProfitTriggered(orders, i, true);
      }
      if (!LFX.SaveOrder(orders, i)) return(false);         // TODO: !!! Fehler in LFX.SaveOrder() behandeln, wenn die Order schon verarbeitet wurde (z.B. von anderem Terminal)

                                                            // "LfxOrder{Type}Command {ticket:12345, trigger:"trigger"}"
      if (limitType == OPEN_LIMIT_TRIGGERED) string tradeCmd = "LfxOrderOpenCommand{ticket:" + los.Ticket(orders, i) +", trigger:"+ DoubleQuoteStr(StringReplace(StringReplace(trigger, ",", HTML_COMMA), "\"", HTML_DQUOTE)) +"}";
      else                                          tradeCmd = "LfxOrderCloseCommand{ticket:"+ los.Ticket(orders, i) +", trigger:"+ DoubleQuoteStr(StringReplace(StringReplace(trigger, ",", HTML_COMMA), "\"", HTML_DQUOTE)) +"}";

      if (!QC.SendTradeCommand(tradeCmd)) {
         if (limitType == OPEN_LIMIT_TRIGGERED) los.setOpenTime (orders, i, -now);     // Bei einem Fehler in QC.SendTradeCommand() diesen Fehler auch
         else                                   los.setCloseTime(orders, i, -now);     // in der Order speichern. Ansonsten wartet die Funktion auf eine
         LFX.SaveOrder(orders, i);                                                     // Ausf�hrungsbest�tigung, die nicht kommen kann.
         return(false);
      }
   }
   else if (now < triggerTime + 30*SECONDS) {
      // (2) Die Orderausf�hrung wurde eingeleitet und wir warten auf die Ausf�hrungsbest�tigung.
   }
   else {
      // (3) Die Orderausf�hrung wurde eingeleitet und die Ausf�hrungsbest�tigung ist �berf�llig.
      // Logmessage zusammenstellen
      if (limitType == OPEN_LIMIT_TRIGGERED) logMsg = "missing trade confirmation for triggered "+ StringToLower(OperationTypeDescription(los.Type(orders, i))) +" at "+ NumberToStr(los.OpenPrice(orders, i), priceFormat);
      if (limitType == STOPLOSS_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i))     logMsg = "missing trade confirmation for triggered SL amount of "+ limitValue + separator + limitPercent;
         else                                logMsg = "missing trade confirmation for triggered SL price at "+ NumberToStr(los.StopLossPrice(orders, i), priceFormat);
      }
      if (limitType == TAKEPROFIT_LIMIT_TRIGGERED) {
         if (!los.ClosePrice(orders, i))     logMsg = "missing trade confirmation for triggered TP amount of "+ limitValue + separator + limitPercent;
         else                                logMsg = "missing trade confirmation for triggered TP price at "+ NumberToStr(los.TakeProfitPrice(orders, i), priceFormat);
      }

      // aktuell gespeicherte Version der Order holen
      int result = LFX.GetOrder(los.Ticket(orders, i), order); if (result != 1) return(!catch("LFX.SendTradeCommand(3)->LFX.GetOrder(ticket="+ los.Ticket(orders, i) +") => "+ result, ERR_RUNTIME_ERROR));

      if (lo.Version(order) != los.Version(orders, i)) {                               // Gespeicherte Version ist modifiziert (kann nur neuer sein)
         // Die Order wurde ausgef�hrt oder ein Fehler trat auf. In beiden F�llen erfolgte jedoch keine Benachrichtigung.
         // Diese Pr�fung wird als ausreichende Benachrichtigung gewertet und fortgefahren.
         log("LFX.SendTradeCommand(4)  "+ symbol.i +" #"+ los.Ticket(orders, i) +" "+ logMsg +", continuing...");    // TODO: !!! Keine Warnung, solange m�glicherweise gar kein Receiver existiert.
         if (limitType == OPEN_LIMIT_TRIGGERED) log("LFX.SendTradeCommand(5)  "+ symbol.i +" #"+ lo.Ticket(order) +" "+ ifString(!lo.IsOpenError (order), "position was opened", "opening of position failed"));
         else                                   log("LFX.SendTradeCommand(6)  "+ symbol.i +" #"+ lo.Ticket(order) +" "+ ifString(!lo.IsCloseError(order), "position was closed", "closing of position failed"));
         ArraySetInts(orders, i, order);                                               // lokale Order mit neu eingelesener Order �berschreiben
      }
      else {
         // Order ist unver�ndert, Fehler melden und speichern.
         warn("LFX.SendTradeCommand(7)  "+ symbol.i +" #"+ los.Ticket(orders, i) +" "+ logMsg +", continuing...");
         if (limitType == OPEN_LIMIT_TRIGGERED) los.setOpenTime (orders, i, -now);     // Sollte die Order nach dieser Zeit doch noch erfolgreich ausgef�hrt werden, wird dieser
         else                                   los.setCloseTime(orders, i, -now);     // Fehler mit dem letztendlichen Erfolg �berschrieben. Dies tritt z.B. auf, wenn der
         if (!LFX.SaveOrder(orders, i)) return(false);                                 // Trade-Server vor der letztendlichen Ausf�hrung mehrere Minuten h�ngt (z.B. Demo-Server).
      }
   }
   return(true);
}


/**
 * Gibt eine LFX-Order des TradeAccounts zur�ck.
 *
 * @param  int ticket - Ticket der zur�ckzugebenden Order
 * @param  int lo[]   - struct LFX_ORDER zur Aufnahme der gelesenen Daten
 *
 * @return int - Erfolgsstatus: +1, wenn die Order erfolgreich gelesen wurde
 *                              -1, wenn die Order nicht gefunden wurde
 *                               0, falls ein anderer Fehler auftrat
 */
int LFX.GetOrder(int ticket, /*LFX_ORDER*/int lo[]) {
   // Parametervaliderung
   if (ticket <= 0) return(!catch("LFX.GetOrder(1)  invalid parameter ticket = "+ ticket, ERR_INVALID_PARAMETER));


   // (1) Orderdaten lesen
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.number +"_config.ini";
   string section = "LFX-Orders";
   string key     = ticket;
   string value   = GetIniString(file, section, key);
   if (!StringLen(value)) {
      if (IsIniKey(file, section, key)) return(!catch("LFX.GetOrder(2)  invalid order entry ["+ section +"]->"+ key +" in \""+ file +"\"", ERR_RUNTIME_ERROR));
                                        return(-1);                  // Ticket nicht gefunden
   }


   // (2) Orderdaten validieren
   //Ticket = Symbol, Comment, OrderType, Units, OpenEquity, OpenTriggerTime, (-)OpenTime, OpenPrice, TakeProfitPrice, TakeProfitValue, TakeProfitPercent, TakeProfitTriggered, StopLossPrice, StopLossValue, StopLossPercent, StopLossTriggered, CloseTriggerTime, (-)CloseTime, ClosePrice, Profit, ModificationTime, Version
   string sValue, values[];
   if (Explode(value, ",", values, NULL) != 22)       return(!catch("LFX.GetOrder(3)  invalid order entry ("+ ArraySize(values) +" substrings) ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   int digits = 5;

   // Comment
   string _comment = StringTrim(values[1]);

   // OrderType
   sValue = StringTrim(values[2]);
   int _orderType = StrToOperationType(sValue);
   if (!IsTradeOperation(_orderType))                 return(!catch("LFX.GetOrder(4)  invalid order type \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OrderUnits
   sValue = StringTrim(values[3]);
   if (!StringIsNumeric(sValue))                      return(!catch("LFX.GetOrder(5)  invalid unit size \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _orderUnits = StrToDouble(sValue);
   if (_orderUnits <= 0)                              return(!catch("LFX.GetOrder(6)  invalid unit size \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _orderUnits = NormalizeDouble(_orderUnits, 1);

   // OpenEquity
   sValue = StringTrim(values[4]);
   if (!StringIsNumeric(sValue))                      return(!catch("LFX.GetOrder(7)  invalid open equity \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _openEquity = StrToDouble(sValue);
   if (!IsPendingTradeOperation(_orderType))
      if (_openEquity <= 0)                           return(!catch("LFX.GetOrder(8)  invalid open equity \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _openEquity = NormalizeDouble(_openEquity, 2);

   // OpenTriggerTime
   sValue = StringTrim(values[5]);
   if (StringIsDigit(sValue)) datetime _openTriggerTime = StrToInteger(sValue);
   else                                _openTriggerTime =    StrToTime(sValue);
   if      (_openTriggerTime < 0)                     return(!catch("LFX.GetOrder(9)  invalid open-trigger time \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else if (_openTriggerTime > 0)
      if (_openTriggerTime > GetFxtTime())            return(!catch("LFX.GetOrder(10)  invalid open-trigger time \""+ TimeToStr(_openTriggerTime, TIME_FULL) +" FXT\" (current time \""+ TimeToStr(GetFxtTime(), TIME_FULL) +" FXT\") in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OpenTime
   sValue = StringTrim(values[6]);
   if      (StringIsInteger(sValue)) datetime _openTime =  StrToInteger(sValue);
   else if (StringStartsWith(sValue, "-"))    _openTime = -StrToTime(StringSubstr(sValue, 1));
   else                                       _openTime =  StrToTime(sValue);
   if (!_openTime)                                    return(!catch("LFX.GetOrder(11)  invalid open time \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   if (Abs(_openTime) > GetFxtTime())                 return(!catch("LFX.GetOrder(12)  invalid open time \""+ TimeToStr(Abs(_openTime), TIME_FULL) +" FXT\" (current time \""+ TimeToStr(GetFxtTime(), TIME_FULL) +" FXT\") in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OpenPrice
   sValue = StringTrim(values[7]);
   if (!StringIsNumeric(sValue))                      return(!catch("LFX.GetOrder(13)  invalid open price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _openPrice = StrToDouble(sValue);
   if (_openPrice <= 0)                               return(!catch("LFX.GetOrder(14)  invalid open price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _openPrice = NormalizeDouble(_openPrice, digits);

   // TakeProfitPrice
   sValue = StringTrim(values[8]);
   if (!StringLen(sValue)) double _takeProfitPrice = 0;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(15)  invalid takeprofit price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {
      _takeProfitPrice = StrToDouble(sValue);
      if (_takeProfitPrice < 0)                       return(!catch("LFX.GetOrder(16)  invalid takeprofit price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
      _takeProfitPrice = NormalizeDouble(_takeProfitPrice, digits);
   }

   // TakeProfitValue
   sValue = StringTrim(values[9]);
   if      (!StringLen(sValue)) double _takeProfitValue = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(17)  invalid takeprofit value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else                               _takeProfitValue = NormalizeDouble(StrToDouble(sValue), 2);

   // TakeProfitPercent
   sValue = StringTrim(values[10]);
   if      (!StringLen(sValue)) double _takeProfitPercent = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(18)  invalid takeprofit percent value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {
      _takeProfitPercent = NormalizeDouble(StrToDouble(sValue), 2);
      if (_takeProfitPercent < -100)                  return(!catch("LFX.GetOrder(19)  invalid takeprofit percent value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   }

   // TakeProfitTriggered
   sValue = StringTrim(values[11]);
   if      (sValue == "0") bool _takeProfitTriggered = false;
   else if (sValue == "1")      _takeProfitTriggered = true;
   else                                               return(!catch("LFX.GetOrder(20)  invalid takeProfit-triggered value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // StopLossPrice
   sValue = StringTrim(values[12]);
   if (!StringLen(sValue)) double _stopLossPrice = 0;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(21)  invalid stoploss price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {
      _stopLossPrice = StrToDouble(sValue);
      if (_stopLossPrice < 0)                         return(!catch("LFX.GetOrder(22)  invalid stoploss price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
      _stopLossPrice = NormalizeDouble(_stopLossPrice, digits);
      if (_stopLossPrice && _takeProfitPrice) {
         if (IsLongTradeOperation(_orderType)) {
            if (_stopLossPrice >= _takeProfitPrice)   return(!catch("LFX.GetOrder(23)  stoploss/takeprofit price mis-match "+ DoubleToStr(_stopLossPrice, digits) +"/"+ DoubleToStr(_takeProfitPrice, digits) +" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
         }
         else if (_stopLossPrice <= _takeProfitPrice) return(!catch("LFX.GetOrder(24)  stoploss/takeprofit price mis-match "+ DoubleToStr(_stopLossPrice, digits) +"/"+ DoubleToStr(_takeProfitPrice, digits) +" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
      }
   }

   // StopLossValue
   sValue = StringTrim(values[13]);
   if      (!StringLen(sValue)) double _stopLossValue = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(25)  invalid stoploss value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {
      _stopLossValue = NormalizeDouble(StrToDouble(sValue), 2);
      if (!IsEmptyValue(_stopLossValue) && !IsEmptyValue(_takeProfitValue))
         if (_stopLossValue >= _takeProfitValue)      return(!catch("LFX.GetOrder(26)  stoploss/takeprofit value mis-match "+ DoubleToStr(_stopLossValue, 2) +"/"+ DoubleToStr(_takeProfitValue, 2) +" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   }

   // StopLossPercent
   sValue = StringTrim(values[14]);
   if      (!StringLen(sValue)) double _stopLossPercent = EMPTY_VALUE;
   else if (!StringIsNumeric(sValue))                 return(!catch("LFX.GetOrder(27)  invalid stoploss percent value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else {
      _stopLossPercent = NormalizeDouble(StrToDouble(sValue), 2);
      if (_stopLossPercent < -100)                    return(!catch("LFX.GetOrder(28)  invalid stoploss percent value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
      if (!IsEmptyValue(_stopLossPercent) && !IsEmptyValue(_takeProfitPercent))
         if (_stopLossPercent >= _takeProfitPercent)  return(!catch("LFX.GetOrder(29)  stoploss/takeprofit percent mis-match "+ DoubleToStr(_stopLossPercent, 2) +"/"+ DoubleToStr(_takeProfitPercent, 2) +" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   }

   // StopLossTriggered
   sValue = StringTrim(values[15]);
   if      (sValue == "0") bool _stopLossTriggered = false;
   else if (sValue == "1")      _stopLossTriggered = true;
   else                                               return(!catch("LFX.GetOrder(30)  invalid stoploss-triggered value \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // CloseTriggerTime
   sValue = StringTrim(values[16]);
   if (StringIsDigit(sValue)) datetime _closeTriggerTime = StrToInteger(sValue);
   else                                _closeTriggerTime =    StrToTime(sValue);
   if      (_closeTriggerTime < 0)                    return(!catch("LFX.GetOrder(31)  invalid close-trigger time \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   else if (_closeTriggerTime > 0)
      if (_closeTriggerTime > GetFxtTime())           return(!catch("LFX.GetOrder(32)  invalid close-trigger time \""+ TimeToStr(_closeTriggerTime, TIME_FULL) +" FXT\" (current time \""+ TimeToStr(GetFxtTime(), TIME_FULL) +" FXT\") in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // CloseTime
   sValue = StringTrim(values[17]);
   if      (StringIsInteger(sValue)) datetime _closeTime =  StrToInteger(sValue);
   else if (StringStartsWith(sValue, "-"))    _closeTime = -StrToTime(StringSubstr(sValue, 1));
   else                                       _closeTime =  StrToTime(sValue);
   if (Abs(_closeTime) > GetFxtTime())                return(!catch("LFX.GetOrder(33)  invalid close time \""+ TimeToStr(Abs(_closeTime), TIME_FULL) +" FXT\" (current time \""+ TimeToStr(GetFxtTime(), TIME_FULL) +" FXT\") in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // ClosePrice
   sValue = StringTrim(values[18]);
   if (!StringIsNumeric(sValue))                      return(!catch("LFX.GetOrder(34)  invalid close price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _closePrice = StrToDouble(sValue);
   if (_closePrice < 0)                               return(!catch("LFX.GetOrder(35)  invalid close price \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   _closePrice = NormalizeDouble(_closePrice, digits);
   if (_closeTime > 0 && !_closePrice)                return(!catch("LFX.GetOrder(36)  close time/price mis-match \""+ TimeToStr(_closeTime, TIME_FULL) +"\"/0 in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // OrderProfit
   sValue = StringTrim(values[19]);
   if (!StringIsNumeric(sValue))                      return(!catch("LFX.GetOrder(37)  invalid order profit \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   double _orderProfit = StrToDouble(sValue);
   _orderProfit = NormalizeDouble(_orderProfit, 2);

   // ModificationTime
   sValue = StringTrim(values[20]);
   if (StringIsDigit(sValue)) datetime _modificationTime = StrToInteger(sValue);
   else                                _modificationTime =    StrToTime(sValue);
   if (_modificationTime <= 0)                        return(!catch("LFX.GetOrder(38)  invalid modification time \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   if (_modificationTime > GetFxtTime())              return(!catch("LFX.GetOrder(39)  invalid modification time \""+ TimeToStr(_modificationTime, TIME_FULL) +" FXT\" (current time \""+ TimeToStr(GetFxtTime(), TIME_FULL) +" FXT\") in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));

   // Version
   sValue = StringTrim(values[21]);
   if (!StringIsDigit(sValue))                        return(!catch("LFX.GetOrder(40)  invalid version \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));
   int _version = StrToInteger(sValue);
   if (_version <= 0)                                 return(!catch("LFX.GetOrder(41)  invalid version \""+ sValue +"\" in order ["+ section +"]->"+ ticket +" = \""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\" in \""+ file +"\"", ERR_RUNTIME_ERROR));


   // (3) Orderdaten in �bergebenes Array schreiben (erst nach vollst�ndiger erfolgreicher Validierung)
   InitializeByteBuffer(lo, LFX_ORDER.size);

   lo.setTicket             (lo,  ticket             );              // Ticket immer zuerst, damit im Struct Currency-ID und Digits ermittelt werden k�nnen
   lo.setType               (lo, _orderType          );
   lo.setUnits              (lo, _orderUnits         );
   lo.setLots               (lo,  NULL               );
   lo.setOpenEquity         (lo, _openEquity         );
   lo.setOpenTriggerTime    (lo, _openTriggerTime    );
   lo.setOpenTime           (lo, _openTime           );
   lo.setOpenPrice          (lo, _openPrice          );
   lo.setStopLossPrice      (lo, _stopLossPrice      );
   lo.setStopLossValue      (lo, _stopLossValue      );
   lo.setStopLossPercent    (lo, _stopLossPercent    );
   lo.setStopLossTriggered  (lo, _stopLossTriggered  );
   lo.setTakeProfitPrice    (lo, _takeProfitPrice    );
   lo.setTakeProfitValue    (lo, _takeProfitValue    );
   lo.setTakeProfitPercent  (lo, _takeProfitPercent  );
   lo.setTakeProfitTriggered(lo, _takeProfitTriggered);
   lo.setCloseTriggerTime   (lo, _closeTriggerTime   );
   lo.setCloseTime          (lo, _closeTime          );
   lo.setClosePrice         (lo, _closePrice         );
   lo.setProfit             (lo, _orderProfit        );
   lo.setComment            (lo, _comment            );
   lo.setModificationTime   (lo, _modificationTime   );
   lo.setVersion            (lo, _version            );

   return(!catch("LFX.GetOrder(42)"));
}


// OrderType-Flags, siehe LFX.GetOrders()
#define OF_OPEN                1
#define OF_CLOSED              2
#define OF_PENDINGORDER        4
#define OF_OPENPOSITION        8
#define OF_PENDINGPOSITION    16


/**
 * Gibt mehrere LFX-Orders des TradeAccounts zur�ck.
 *
 * @param  string currency    - LFX-W�hrung der Orders (default: alle W�hrungen)
 * @param  int    fSelection  - Kombination von Selection-Flags (default: alle Orders werden zur�ckgegeben)
 *                              OF_OPEN            - gibt alle offenen Tickets zur�ck:                   Pending-Orders und offene Positionen, analog zu OrderSelect(MODE_TRADES)
 *                              OF_CLOSED          - gibt alle geschlossenen Tickets zur�ck:             Trade-History, analog zu OrderSelect(MODE_HISTORY)
 *                              OF_PENDINGORDER    - gibt alle Orders mit aktivem OpenLimit zur�ck:      OP_BUYLIMIT, OP_BUYSTOP, OP_SELLLIMIT, OP_SELLSTOP
 *                              OF_OPENPOSITION    - gibt alle offenen Positionen zur�ck
 *                              OF_PENDINGPOSITION - gibt alle Positionen mit aktivem CloseLimit zur�ck: StopLoss, TakeProfit
 * @param  LFX_ORDER orders[] - LFX_ORDER-Array zur Aufnahme der gelesenen Daten
 *
 * @return int - Anzahl der zur�ckgegebenen Orders oder -1 (EMPTY), falls ein Fehler auftrat
 */
int LFX.GetOrders(string currency, int fSelection, /*LFX_ORDER*/int orders[][]) {
   // (1) Parametervaliderung
   int currencyId = 0;                                                     // 0: alle W�hrungen
   if (currency == "0")                                                    // (string) NULL
      currency = "";

   if (StringLen(currency) > 0) {
      currencyId = GetCurrencyId(currency); if (!currencyId) return(-1);
   }

   if (!fSelection)                                                        // ohne Angabe wird alles zur�ckgeben
      fSelection  = OF_OPEN | OF_CLOSED;
   if ((fSelection & OF_PENDINGORDER) && (fSelection & OF_OPENPOSITION))   // sind OF_PENDINGORDER und OF_OPENPOSITION gesetzt, werden alle OF_OPEN zur�ckgegeben
      fSelection |= OF_OPEN;

   ArrayResize(orders, 0);
   int error = InitializeByteBuffer(orders, LFX_ORDER.size);               // validiert Dimensionierung
   if (IsError(error)) return(_EMPTY(SetLastError(error)));


   // (2) alle Tickets einlesen
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.number +"_config.ini";
   string section = "LFX-Orders";
   string keys[];
   int keysSize = GetIniKeys(file, section, keys);


   // (3) Orders nacheinander einlesen und gegen Currency und Selektionflags pr�fen
   /*LFX_ORDER*/int order[];

   for (int i=0; i < keysSize; i++) {
      if (!StringIsDigit(keys[i])) continue;
      int ticket = StrToInteger(keys[i]);

      if (currencyId != 0)
         if (LFX.CurrencyId(ticket) != currencyId)
            continue;

      // Ist ein Currency-Filter angegeben, sind ab hier alle Tickets gefiltert.
      int result = LFX.GetOrder(ticket, order);
      if (result != 1) {
         if (!result)                                                      // -1, wenn das Ticket nicht gefunden wurde
            return(EMPTY);                                                 //  0, falls ein anderer Fehler auftrat
         return(_EMPTY(catch("LFX.GetOrders(1)->LFX.GetOrder(ticket="+ ticket +")  order not found", ERR_RUNTIME_ERROR)));
      }

      bool match = false;
      while (true) {
         if (lo.IsClosed(order)) {
            match = (fSelection & OF_CLOSED);
            break;
         }
         // ab hier immer offene Order
         if (fSelection & OF_OPEN && 1) {
            match = true;
            break;
         }
         if (lo.IsPendingOrder(order)) {
            match = (fSelection & OF_PENDINGORDER);
            break;
         }
         // ab hier immer offene Position
         if (fSelection & OF_OPENPOSITION && 1) {
            match = true;
            break;
         }
         if (fSelection & OF_PENDINGPOSITION && 1)
            match = (lo.IsStopLoss(order) || lo.IsTakeProfit(order));
         break;
      }
      if (match)
         ArrayPushInts(orders, order);                                     // bei Match Order an �bergebenes LFX_ORDER-Array anf�gen
   }
   ArrayResize(keys,  0);
   ArrayResize(order, 0);

   if (!catch("LFX.GetOrders(2)"))
      return(ArrayRange(orders, 0));
   return(EMPTY);
}


/**
 * Speichert eine oder mehrere LFX-Orders in der .ini-Datei des TradeAccounts.
 *
 * @param  LFX_ORDER orders[] - eine einzelne LFX_ORDER oder ein Array von LFX_ORDERs
 * @param  int       index    - Arrayindex der zu speichernden Order, wenn orders[] ein LFX_ORDER[]-Array ist.
 *                              Der Parameter wird ignoriert, wenn orders[] eine einzelne LFX_ORDER ist.
 * @param  int       fCatch   - Flag mit leise zu setzenden Fehler, soda� sie vom Aufrufer behandelt werden k�nnen
 *
 * @return bool - Erfolgsstatus
 */
bool LFX.SaveOrder(/*LFX_ORDER*/int orders[], int index=NULL, int fCatch=NULL) {
   // (1) �bergebene Order in eine einzelne Order umkopieren (Parameter orders[] kann unterschiedliche Dimensionen haben)
   int dims = ArrayDimension(orders); if (dims > 2)   return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(1)  invalid dimensions of parameter orders = "+ dims, ERR_INCOMPATIBLE_ARRAYS, fCatch));

   /*LFX_ORDER*/int order[]; ArrayResize(order, LFX_ORDER.intSize);
   if (dims == 1) {
      // Parameter orders[] ist einzelne Order
      if (ArrayRange(orders, 0) != LFX_ORDER.intSize) return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(2)  invalid size of parameter orders["+ ArrayRange(orders, 0) +"]", ERR_INCOMPATIBLE_ARRAYS, fCatch));
      ArrayCopy(order, orders);
   }
   else {
      // Parameter orders[] ist Order-Array
      if (ArrayRange(orders, 1) != LFX_ORDER.intSize) return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(3)  invalid size of parameter orders["+ ArrayRange(orders, 0) +"]["+ ArrayRange(orders, 1) +"]", ERR_INCOMPATIBLE_ARRAYS, fCatch));
      int ordersSize = ArrayRange(orders, 0);
      if (index < 0 || index > ordersSize-1)          return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(4)  invalid parameter index = "+ index, ERR_ARRAY_INDEX_OUT_OF_RANGE, fCatch));
      int src  = GetIntsAddress(orders) + index*LFX_ORDER.intSize*4;
      int dest = GetIntsAddress(order);
      CopyMemory(dest, src, LFX_ORDER.intSize*4);
   }


   // (2) Aktuell gespeicherte Version der Order holen und konkurrierende Schreibzugriffe abfangen
   /*LFX_ORDER*/int stored[], ticket=lo.Ticket(order);
   int result = LFX.GetOrder(ticket, stored);                        // +1, wenn die Order erfolgreich gelesen wurden
   if (!result) return(false);                                       // -1, wenn die Order nicht gefunden wurde
   if (result > 0) {                                                 //  0, falls ein anderer Fehler auftrat
      if (lo.Version(stored) > lo.Version(order)) {
         log("LFX.SaveOrder(5)  to-store="+ LFX_ORDER.toStr(order ));
         log("LFX.SaveOrder(6)  stored  ="+ LFX_ORDER.toStr(stored));
         return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(7)  concurrent modification of #"+ ticket +", expected version "+ lo.Version(order) +", found version "+ lo.Version(stored), ERR_CONCURRENT_MODIFICATION, fCatch));
      }
   }


   // (3) Daten formatieren
   //Ticket = Symbol, Comment, OrderType, Units, OpenEquity, OpenTriggerTime, OpenTime, OpenPrice, TakeProfitPrice, TakeProfitValue, TakeProfitPercent, TakeProfitTriggered, StopLossPrice, StopLossValue, StopLossPercent, StopLossTriggered, CloseTriggerTime, CloseTime, ClosePrice, Profit, ModificationTime, Version
   string sSymbol              =                          lo.Currency           (order);
   string sComment             =                          lo.Comment            (order);                                                                                                     sComment           = StringPadRight(sComment          , 13, " ");
   string sOperationType       = OperationTypeDescription(lo.Type               (order));                                                                                                    sOperationType     = StringPadRight(sOperationType    , 10, " ");
   string sUnits               =              NumberToStr(lo.Units              (order), ".+");                                                                                              sUnits             = StringPadLeft (sUnits            ,  5, " ");
   string sOpenEquity          =                ifString(!lo.OpenEquity         (order), "0", DoubleToStr(lo.OpenEquity(order), 2));                                                         sOpenEquity        = StringPadLeft (sOpenEquity       , 10, " ");
   string sOpenTriggerTime     =                ifString(!lo.OpenTriggerTime    (order), "0", TimeToStr(lo.OpenTriggerTime(order), TIME_FULL));                                              sOpenTriggerTime   = StringPadLeft (sOpenTriggerTime  , 19, " ");
   string sOpenTime            =                 ifString(lo.OpenTime           (order) < 0, "-", "") + TimeToStr(Abs(lo.OpenTime(order)), TIME_FULL);                                       sOpenTime          = StringPadLeft (sOpenTime         , 19, " ");
   string sOpenPrice           =              DoubleToStr(lo.OpenPrice          (order), lo.Digits(order));                                                                                  sOpenPrice         = StringPadLeft (sOpenPrice        ,  9, " ");
   string sTakeProfitPrice     =                ifString(!lo.IsTakeProfitPrice  (order), "", DoubleToStr(lo.TakeProfitPrice  (order), lo.Digits(order)));                                    sTakeProfitPrice   = StringPadLeft (sTakeProfitPrice  ,  7, " ");
   string sTakeProfitValue     =                ifString(!lo.IsTakeProfitValue  (order), "", DoubleToStr(lo.TakeProfitValue  (order), 2));                                                   sTakeProfitValue   = StringPadLeft (sTakeProfitValue  ,  7, " ");
   string sTakeProfitPercent   =                ifString(!lo.IsTakeProfitPercent(order), "", DoubleToStr(lo.TakeProfitPercent(order), 2));                                                   sTakeProfitPercent = StringPadLeft (sTakeProfitPercent,  5, " ");
   string sTakeProfitTriggered =                         (lo.TakeProfitTriggered(order)!=0);
   string sStopLossPrice       =                ifString(!lo.IsStopLossPrice    (order), "", DoubleToStr(lo.StopLossPrice  (order), lo.Digits(order)));                                      sStopLossPrice     = StringPadLeft (sStopLossPrice    ,  7, " ");
   string sStopLossValue       =                ifString(!lo.IsStopLossValue    (order), "", DoubleToStr(lo.StopLossValue  (order), 2));                                                     sStopLossValue     = StringPadLeft (sStopLossValue    ,  7, " ");
   string sStopLossPercent     =                ifString(!lo.IsStopLossPercent  (order), "", DoubleToStr(lo.StopLossPercent(order), 2));                                                     sStopLossPercent   = StringPadLeft (sStopLossPercent  ,  5, " ");
   string sStopLossTriggered   =                         (lo.StopLossTriggered  (order)!=0);
   string sCloseTriggerTime    =                ifString(!lo.CloseTriggerTime   (order), "0", TimeToStr(lo.CloseTriggerTime(order), TIME_FULL));                                             sCloseTriggerTime  = StringPadLeft (sCloseTriggerTime , 19, " ");
   string sCloseTime           =                 ifString(lo.CloseTime          (order) < 0, "-", "") + ifString(!lo.CloseTime(order), "0", TimeToStr(Abs(lo.CloseTime(order)), TIME_FULL)); sCloseTime         = StringPadLeft (sCloseTime        , 19, " ");
   string sClosePrice          =                ifString(!lo.ClosePrice         (order), "0", DoubleToStr(lo.ClosePrice(order), lo.Digits(order)));                                          sClosePrice        = StringPadLeft (sClosePrice       , 10, " ");
   string sProfit              =                ifString(!lo.Profit             (order), "0", DoubleToStr(lo.Profit    (order), 2));                                                         sProfit            = StringPadLeft (sProfit           ,  7, " ");

     datetime modificationTime = TimeFXT(); if (!modificationTime) return(false);
     int      version          = lo.Version(order) + 1;

   string sModificationTime    = TimeToStr(modificationTime, TIME_FULL);
   string sVersion             = version;


   // (4) Daten schreiben
   string mqlDir  = TerminalPath() + ifString(GetTerminalBuild()<=509, "\\experts", "\\mql4");
   string file    = mqlDir +"\\files\\"+ tradeAccount.company +"\\"+ tradeAccount.number +"_config.ini";
   string section = "LFX-Orders";
   string key     = ticket;
   string value   = StringConcatenate(sSymbol, ", ", sComment, ", ", sOperationType, ", ", sUnits, ", ", sOpenEquity, ", ", sOpenTriggerTime, ", ", sOpenTime, ", ", sOpenPrice, ", ", sTakeProfitPrice, ", ", sTakeProfitValue, ", ", sTakeProfitPercent, ", ", sTakeProfitTriggered, ", ", sStopLossPrice, ", ", sStopLossValue, ", ", sStopLossPercent, ", ", sStopLossTriggered, ", ", sCloseTriggerTime, ", ", sCloseTime, ", ", sClosePrice, ", ", sProfit, ", ", sModificationTime, ", ", sVersion);

   if (!WritePrivateProfileStringA(section, key, " "+ value, file))
      return(!__LFX.SaveOrder.HandleError("LFX.SaveOrder(8)->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=\""+ StringReplace.Recursive(StringReplace.Recursive(value, " ,", ","), ",  ", ", ") +"\", fileName=\""+ file +"\")", ERR_WIN32_ERROR, fCatch));


   // (5) Version der �bergebenen Order aktualisieren
   if (dims == 1) {  lo.setModificationTime(orders,        modificationTime);  lo.setVersion(orders,        version); }
   else           { los.setModificationTime(orders, index, modificationTime); los.setVersion(orders, index, version); }
   return(true);
}


/**
 * Speichert die �bergebenen LFX-Orders in der .ini-Datei des TradeAccounts.
 *
 * @param  LFX_ORDER orders[] - Array von LFX_ORDERs
 *
 * @return bool - Erfolgsstatus
 */
bool LFX.SaveOrders(/*LFX_ORDER*/int orders[][]) {
   int size = ArrayRange(orders, 0);
   for (int i=0; i < size; i++) {
      if (!LFX.SaveOrder(orders, i))
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
 * @access private - Aufruf nur aus LFX.SaveOrder()
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
 * Sendet dem aktuellen TradeAccount per QuickChannel ein TradeCommand. Zum Empfang l�uft im ChartInfos-Indikator eines jeden TradeAccounts
 * ein entsprechender TradeCommand-Listener.
 *
 * @param  string cmd - Command
 *
 * @return bool - Erfolgsstatus
 */
bool QC.SendTradeCommand(string cmd) {
   if (!StringLen(cmd)) return(!catch("QC.SendTradeCommand(1)  invalid parameter cmd = "+ DoubleQuoteStr(cmd), ERR_INVALID_PARAMETER));

   cmd = StringReplace(cmd, TAB, HTML_TAB);

   while (true) {
      if (!hQC.TradeCmdSender) /*&&*/ if (!QC.StartTradeCmdSender())
         return(false);

      int result = QC_SendMessage(hQC.TradeCmdSender, cmd, QC_FLAG_SEND_MSG_IF_RECEIVER);
      if (!result)
         return(!catch("QC.SendTradeCommand(2)->MT4iQuickChannel::QC_SendMessage() = QC_SEND_MSG_ERROR", ERR_WIN32_ERROR));

      if (result == QC_SEND_MSG_IGNORED) {
         debug("QC.SendTradeCommand(3)  receiver on \""+ qc.TradeCmdChannel +"\" gone");
         QC.StopTradeCmdSender();
         continue;
      }
      break;
   }

   QC.StopTradeCmdSender();
   return(true);
}


/**
 * Startet einen QuickChannel-Sender f�r TradeCommands.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StartTradeCmdSender() {
   if (hQC.TradeCmdSender != 0)
      return(true);

   // aktiven Channel ermitteln
   string file    = TerminalPath() +"\\..\\quickchannel.ini";
   string section = tradeAccount.number;
   string keys[], value;
   int error, iValue, keysSize = GetIniKeys(file, section, keys);

   for (int i=0; i < keysSize; i++) {
      if (StringStartsWithI(keys[i], "TradeCommands.")) {
         value = GetIniString(file, section, keys[i]);
         if (value!="") /*&&*/ if (value!="0") {
            // Channel sollte aktiv sein, testen...
            int result = QC_ChannelHasReceiver(keys[i]);
            if (result == QC_CHECK_RECEIVER_OK)                   // Receiver ist da, Channel ist ok
               break;
            if (result == QC_CHECK_CHANNEL_NONE) {                // orphaned Channeleintrag aus .ini-Datei l�schen
               if (!DeleteIniKey(file, section, keys[i]))         // kann auftreten, wenn das TradeTerminal oder der dortige Indikator crashte (z.B. bei Recompile)
                  return(false);
               continue;
            }
            if (result == QC_CHECK_RECEIVER_NONE) return(!catch("QC.StartTradeCmdSender(1)->MT4iQuickChannel::QC_ChannelHasReceiver(name=\""+ keys[i] +"\") has no reiver but a sender",          ERR_WIN32_ERROR));
            if (result == QC_CHECK_CHANNEL_ERROR) return(!catch("QC.StartTradeCmdSender(2)->MT4iQuickChannel::QC_ChannelHasReceiver(name=\""+ keys[i] +"\") = QC_CHECK_CHANNEL_ERROR",            ERR_WIN32_ERROR));
                                                  return(!catch("QC.StartTradeCmdSender(3)->MT4iQuickChannel::QC_ChannelHasReceiver(name=\""+ keys[i] +"\") = unexpected return value: "+ result, ERR_WIN32_ERROR));
         }
      }
   }
   if (i >= keysSize) {                                            // break wurde nicht getriggert
      warn("QC.StartTradeCmdSender(4)  No TradeCommand receiver for account "+ DoubleQuoteStr(tradeAccount.company +":"+ tradeAccount.number) +" account found (keys="+ keysSize +"). Is the trade terminal running?");
      return(false);
   }

   // Sender auf gefundenem Channel starten
   qc.TradeCmdChannel = keys[i];
   hQC.TradeCmdSender = QC_StartSender(qc.TradeCmdChannel);
   if (!hQC.TradeCmdSender)
      return(!catch("QC.StartTradeCmdSender(5)->MT4iQuickChannel::QC_StartSender(channel=\""+ qc.TradeCmdChannel +"\")", ERR_WIN32_ERROR));
   //debug("QC.StartTradeCmdSender(6)  sender on \""+ qc.TradeCmdChannel +"\" started");
   return(true);
}


/**
 * Stoppt einen QuickChannel-Sender f�r TradeCommands.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StopTradeCmdSender() {
   if (!hQC.TradeCmdSender)
      return(true);

   int hTmp = hQC.TradeCmdSender;
              hQC.TradeCmdSender = NULL;

   if (!QC_ReleaseSender(hTmp))
      return(!catch("QC.StopTradeCmdSender(1)->MT4iQuickChannel::QC_ReleaseSender(ch=\""+ qc.TradeCmdChannel +"\")  error stopping sender", ERR_WIN32_ERROR));

   //debug("QC.StopTradeCmdSender()  sender on \""+ qc.TradeCmdChannel +"\" stopped");
   return(true);
}


/**
 * Startet einen QuickChannel-Receiver f�r TradeCommands.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StartTradeCmdReceiver() {
   if (hQC.TradeCmdReceiver != NULL) return(true);
   if (!__CHART)                     return(false);

   // Channelnamen definieren
   int hWnd = ec_hChart(__ExecutionContext);
   qc.TradeCmdChannel = "TradeCommands."+ IntToHexStr(hWnd);

   // Receiver starten
   hQC.TradeCmdReceiver = QC_StartReceiver(qc.TradeCmdChannel, hWnd);
   if (!hQC.TradeCmdReceiver)
      return(!catch("QC.StartTradeCmdReceiver(1)->MT4iQuickChannel::QC_StartReceiver(channel=\""+ qc.TradeCmdChannel +"\", hWnd="+ IntToHexStr(hWnd) +") => 0", ERR_WIN32_ERROR));
   //debug("QC.StartTradeCmdReceiver(2)  receiver on \""+ qc.TradeCmdChannel +"\" started");

   // Channelnamen und -status in .ini-Datei hinterlegen
   string file    = TerminalPath() +"\\..\\quickchannel.ini";
   string section = GetAccountNumber();
   string key     = qc.TradeCmdChannel;
   string value   = "1";
   if (!WritePrivateProfileStringA(section, key, value, file))
      return(!catch("QC.StartTradeCmdReceiver(3)->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=\""+ value +"\", fileName=\""+ file +"\")", ERR_WIN32_ERROR));

   return(true);
}


/**
 * Stoppt einen QuickChannel-Receiver f�r TradeCommands.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StopTradeCmdReceiver() {
   if (hQC.TradeCmdReceiver != NULL) {
      // Channelstatus in .ini-Datei aktualisieren (vorm Stoppen des Receivers)
      string file    = TerminalPath() +"\\..\\quickchannel.ini";
      string section = GetAccountNumber();
      string key     = qc.TradeCmdChannel;
      if (!DeleteIniKey(file, section, key)) return(false);

      // Receiver stoppen
      int hTmp = hQC.TradeCmdReceiver;
                 hQC.TradeCmdReceiver = NULL;                        // Handle immer zur�cksetzen, um mehrfache Stopversuche bei Fehlern zu vermeiden

      if (!QC_ReleaseReceiver(hTmp)) return(!catch("QC.StopTradeCmdReceiver(1)->MT4iQuickChannel::QC_ReleaseReceiver(channel="+ DoubleQuoteStr(qc.TradeCmdChannel) +")  error stopping receiver", ERR_WIN32_ERROR));

      //debug("QC.StopTradeCmdReceiver()  receiver on "+ DoubleQuoteStr(qc.TradeCmdChannel) +" stopped");
   }
   return(true);
}


/**
 * Sendet dem LFX-Terminal eine Orderbenachrichtigung.
 *
 * @param  int    cid - Currency-ID des f�r die Nachricht zu benutzenden Channels
 * @param  string msg - Nachricht
 *
 * @return bool - Erfolgsstatus
 */
bool QC.SendOrderNotification(int cid, string msg) {
   if (cid < 1 || cid >= ArraySize(hQC.TradeToLfxSenders))
      return(!catch("QC.SendOrderNotification(1)  illegal parameter cid = "+ cid, ERR_ARRAY_INDEX_OUT_OF_RANGE));

   if (!hQC.TradeToLfxSenders[cid]) /*&&*/ if (!QC.StartLfxSender(cid))
      return(false);

   if (!QC_SendMessage(hQC.TradeToLfxSenders[cid], msg, QC_FLAG_SEND_MSG_IF_RECEIVER))
      return(!catch("QC.SendOrderNotification(2)->MT4iQuickChannel::QC_SendMessage() = QC_SEND_MSG_ERROR", ERR_WIN32_ERROR));
   return(true);
}


/**
 * Startet einen QuickChannel-Sender f�r "TradeToLfxTerminal"-Messages. Das LFX-Terminal kann sich �ber diesen Channel auch selbst Messages schicken.
 *
 * @param  int cid - Currency-ID des zu startenden Channels
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StartLfxSender(int cid) {
   if (cid < 1 || cid >= ArraySize(hQC.TradeToLfxSenders))
      return(!catch("QC.StartLfxSender(1)  illegal parameter cid = "+ cid, ERR_ARRAY_INDEX_OUT_OF_RANGE));
   if (hQC.TradeToLfxSenders[cid] > 0)
      return(true);
                                                                     // Channel-Name: "{AccountCompanyId}:{AccountNumber}:LFX.Profit.{Currency}"
   qc.TradeToLfxChannels[cid] = AccountCompanyId(tradeAccount.company) +":"+ tradeAccount.number +":LFX.Profit."+ GetCurrency(cid);
   hQC.TradeToLfxSenders[cid] = QC_StartSender(qc.TradeToLfxChannels[cid]);
   if (!hQC.TradeToLfxSenders[cid])
      return(!catch("QC.StartLfxSender(2)->MT4iQuickChannel::QC_StartSender(channel="+ DoubleQuoteStr(qc.TradeToLfxChannels[cid]) +")", ERR_WIN32_ERROR));

   //debug("QC.StartLfxSender(3)  sender on "+ DoubleQuoteStr(qc.TradeToLfxChannels[cid]) +" started");
   return(true);
}


/**
 * Stoppt alle QuickChannel-Sender f�r "TradeToLfxTerminal"-Messages.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StopLfxSenders() {
   for (int i=ArraySize(hQC.TradeToLfxSenders)-1; i >= 0; i--) {
      if (hQC.TradeToLfxSenders[i] != NULL) {
         int hTmp = hQC.TradeToLfxSenders[i];
                    hQC.TradeToLfxSenders[i] = NULL;                 // Handle immer zur�cksetzen, um mehrfache Stopversuche bei Fehlern zu vermeiden

         if (!QC_ReleaseSender(hTmp)) return(!catch("QC.StopLfxSenders()->MT4iQuickChannel::QC_ReleaseSender(channel="+ DoubleQuoteStr(qc.TradeToLfxChannels[i]) +")  error stopping sender", ERR_WIN32_ERROR));
      }
   }
   return(true);
}


/**
 * Startet einen QuickChannel-Receiver f�r "TradeToLfxTerminal"-Messages.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StartLfxReceiver() {
   if (hQC.TradeToLfxReceiver != NULL)   return(true);
   if (!__CHART)                         return(false);
   if (!StringEndsWith(Symbol(), "LFX")) return(false);              // kein LFX-Chart

   int hWnd = ec_hChart(__ExecutionContext);                         // Channel-Name: "{AccountCompanyId}:{AccountNumber}:LFX.Profit.{Currency}"
   qc.TradeToLfxChannel = AccountCompanyId(tradeAccount.company) +":"+ tradeAccount.number +":LFX.Profit."+ StringLeft(Symbol(), -3);

   hQC.TradeToLfxReceiver = QC_StartReceiver(qc.TradeToLfxChannel, hWnd);
   if (!hQC.TradeToLfxReceiver)
      return(!catch("QC.StartLfxReceiver(1)->MT4iQuickChannel::QC_StartReceiver(channel="+ DoubleQuoteStr(qc.TradeToLfxChannel) +", hWnd="+ IntToHexStr(hWnd) +") => 0", ERR_WIN32_ERROR));
   //debug("QC.StartLfxReceiver(2)  receiver on "+ DoubleQuoteStr(qc.TradeToLfxChannel) +" started");
   return(true);
}


/**
 * Stoppt den QuickChannel-Receiver f�r "TradeToLfxTerminal"-Messages.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StopLfxReceiver() {
   if (hQC.TradeToLfxReceiver != NULL) {
      int hTmp = hQC.TradeToLfxReceiver;
                 hQC.TradeToLfxReceiver = NULL;                      // Handle immer zur�cksetzen, um mehrfache Stopversuche bei Fehlern zu vermeiden
      if (!QC_ReleaseReceiver(hTmp)) return(!catch("QC.StopLfxReceiver(1)->MT4iQuickChannel::QC_ReleaseReceiver(channel="+ DoubleQuoteStr(qc.TradeToLfxChannel) +")  error stopping receiver", ERR_WIN32_ERROR));
      //debug("QC.StopLfxReceiver(2)  receiver on "+ DoubleQuoteStr(qc.TradeToLfxChannel) +" stopped");
   }
   return(true);
}


/**
 * Stoppt alle laufenden Sender und Receiver.
 *
 * @return bool - Erfolgsstatus
 */
bool QC.StopChannels() {
   if (!QC.StopLfxSenders())       return(false);
   if (!QC.StopLfxReceiver())      return(false);

   if (!QC.StopTradeCmdSender())   return(false);
   if (!QC.StopTradeCmdReceiver()) return(false);
   return(true);
}


/**
 * Dummy-Calls unterdr�cken unn�tze Compilerwarnungen.
 */
void DummyCalls() {
   int iNull, iNulls[];
   LFX.CheckLimits(iNulls, NULL, NULL, NULL, NULL);
   LFX.CreateInstanceId(iNulls);
   LFX.CreateMagicNumber(iNulls, NULL);
   LFX.CurrencyId(NULL);
   LFX.GetMaxOpenOrderMarker(iNulls, NULL);
   LFX.GetOrder(NULL, iNulls);
   LFX.GetOrders(NULL, NULL, iNulls);
   LFX.InstanceId(NULL);
   LFX.IsMyOrder();
   LFX.SaveOrder(iNulls, NULL);
   LFX.SaveOrders(iNulls);
   LFX.SendTradeCommand(iNulls, NULL, NULL);
   LFX_ORDER.toStr(iNulls);
   QC.SendOrderNotification(NULL, NULL);
   QC.SendTradeCommand(NULL);
   QC.StartLfxReceiver();
   QC.StartLfxSender(NULL);
   QC.StartTradeCmdReceiver();
   QC.StartTradeCmdSender();
   QC.StopChannels();
   QC.StopLfxReceiver();
   QC.StopLfxSenders();
   QC.StopTradeCmdReceiver();
   QC.StopTradeCmdSender();
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   string ArrayPopString(string array[]);
   int    ArrayPushInts(int array[][], int values[]);
   int    ArraySetInts(int array[][], int i, int values[]);
   int    GetAccountNumber();
   bool   IntInArray(int haystack[], int needle);
   bool   IsIniKey(string fileName, string section, string key);
#import
