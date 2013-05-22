/**
 * �ffnet eine Position in einer der LiteForex-Indizes.
 *
 *  Regeln:
 *  -------
 *  - automatisierter StopLoss aller Positionen bei 50% von MaxEquity
 *  - maximal 2 offene Positionen
 *  - weitere Positionen im selben Instrument werden erst nach Tagesende er�ffnet
 *  - Positionsgr��en: 0.7 - 1.0 - 1.3
 *  - nach Gewinnen ist ein MA(Equity) Ausgangsbasis f�r neue Positionen
 *  - zu jeder Position wird eine TakeProfit-Order in den Markt gelegt
 *  - Positionen m�glichst am Bollinger-Band eingehen
 *  - 25% aller Gewinne werden sofort aus dem Markt genommen (Reserve f�r Stop-Out-Fall)
 *
 *  TODO:
 *  -----
 *  - Fehler im Counter, wenn 2 Positionen gleichzeitig er�ffnet werden (2 x CHF.3)
 *  - Anzeige des Stoploss-Levels und des Stop-Out-Levels des Brokers
 *  - Buy-/Sell-Limits implementieren
 *  - TakeProfit-Limits implementieren
 *  - Breakeven-Orders implementieren
 *
 *
 *  Format von MagicNumber:
 *  -----------------------
 *  Strategy-Id:   10 bit (Bit 23-32) => Bereich 0-1023 (immer gr��er 100)
 *  Currency-Id:    4 bit (Bit 19-22) => Bereich 0-15
 *  Units:          5 bit (Bit 14-18) => Bereich 0-31   (Vielfaches von 0.1 zwischen 0.1 und 1.5)
 *  Instance-ID:    9 bit (Bit  5-13) => Bereich 0-511  (immer gr��er 0)
 *  Counter:        4 bit (Bit  1-4 ) => Bereich 0-15   (immer gr��er 0)
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/script.mqh>

#property show_inputs


//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern string Currency  = "";             // AUD | CAD | CHF | EUR | GBP | JPY | USD
extern string Direction = "long";         // buy | sell | long | short
extern double Units     = 1.0;            // Vielfaches von 0.1 im Bereich 0.1-1.5

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int Strategy.Id = 102;                    // eindeutige ID der Strategie (Bereich 101-1023)

int    iDirection;
double leverage;

int    positions.magic   [];              // Daten der aktuell offenen Positionen dieser Strategie
string positions.currency[];
double positions.units   [];
int    positions.instance[];
int    positions.counter [];


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // -- Beginn - Parametervalidierung
   // Currency
   string value = StringToUpper(StringTrim(Currency));
   string currencies[] = { "AUD", "CAD", "CHF", "EUR", "GBP", "JPY", "USD" };
   if (!StringInArray(currencies, value))
      return(catch("onInit(1)   Invalid input parameter Currency = \""+ Currency +"\"", ERR_INVALID_INPUT_PARAMVALUE));
   Currency = value;
   // Direction
   value = StringToUpper(StringTrim(Direction));
   if (value == "")
      return(catch("onInit(2)   Invalid input parameter Direction = \""+ Direction +"\"", ERR_INVALID_INPUT_PARAMVALUE));
   switch (StringGetChar(value, 0)) {
      case 'B':
      case 'L': Direction = "long";  iDirection = OP_BUY;  break;
      case 'S': Direction = "short"; iDirection = OP_SELL; break;
      default:
         return(catch("onInit(3)   Invalid input parameter Direction = \""+ Direction +"\"", ERR_INVALID_INPUT_PARAMVALUE));
   }
   // Units
   if (LT(Units, 0.1) || GT(Units, 1.5))
      return(catch("onInit(4)   Invalid input parameter Units = "+ NumberToStr(Units, ".+") +" (needs to be between 0.1 and 1.5)", ERR_INVALID_INPUT_PARAMVALUE));
   if (MathModFix(Units, 0.1) != 0)
      return(catch("onInit(5)   Invalid input parameter Units = "+ NumberToStr(Units, ".+") +" (needs to be a multiple of 0.1)", ERR_INVALID_INPUT_PARAMVALUE));
   Units = NormalizeDouble(Units, 1);
   // -- Ende - Parametervalidierung


   // Leverage-Konfiguration einlesen
   leverage = GetGlobalConfigDouble("Leverage", "CurrencyBasket", 0);
   if (LT(leverage, 1))
      return(catch("onInit(6)   Invalid configuration value [Leverage] CurrencyBasket = "+ NumberToStr(leverage, ".+"), ERR_INVALID_INPUT_PARAMVALUE));

   return(catch("onInit(7)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   string symbols   [6];
   double lots      [6];
   int    directions[6];
   int    tickets   [6];


   // (1) Pairs bestimmen
   if      (Currency == "AUD") { symbols[0] = "AUDCAD"; symbols[1] = "AUDCHF"; symbols[2] = "AUDJPY"; symbols[3] = "AUDUSD"; symbols[4] = "EURAUD"; symbols[5] = "GBPAUD"; }
   else if (Currency == "CAD") { symbols[0] = "AUDCAD"; symbols[1] = "CADCHF"; symbols[2] = "CADJPY"; symbols[3] = "EURCAD"; symbols[4] = "GBPCAD"; symbols[5] = "USDCAD"; }
   else if (Currency == "CHF") { symbols[0] = "AUDCHF"; symbols[1] = "CADCHF"; symbols[2] = "CHFJPY"; symbols[3] = "EURCHF"; symbols[4] = "GBPCHF"; symbols[5] = "USDCHF"; }
   else if (Currency == "EUR") { symbols[0] = "EURAUD"; symbols[1] = "EURCAD"; symbols[2] = "EURCHF"; symbols[3] = "EURGBP"; symbols[4] = "EURJPY"; symbols[5] = "EURUSD"; }
   else if (Currency == "GBP") { symbols[0] = "EURGBP"; symbols[1] = "GBPAUD"; symbols[2] = "GBPCAD"; symbols[3] = "GBPCHF"; symbols[4] = "GBPJPY"; symbols[5] = "GBPUSD"; }
   else if (Currency == "JPY") { symbols[0] = "AUDJPY"; symbols[1] = "CADJPY"; symbols[2] = "CHFJPY"; symbols[3] = "EURJPY"; symbols[4] = "GBPJPY"; symbols[5] = "USDJPY"; }
   else if (Currency == "USD") { symbols[0] = "AUDUSD"; symbols[1] = "EURUSD"; symbols[2] = "GBPUSD"; symbols[3] = "USDCAD"; symbols[4] = "USDCHF"; symbols[5] = "USDJPY"; }


   // (2) Lotsizes berechnen
   double equity = AccountEquity() - AccountCredit();

   for (int retry, i=0; i < 6; i++) {
      double bid       = MarketInfo(symbols[i], MODE_BID      );
      double tickSize  = MarketInfo(symbols[i], MODE_TICKSIZE );
      double tickValue = MarketInfo(symbols[i], MODE_TICKVALUE);
      double minLot    = MarketInfo(symbols[i], MODE_MINLOT   );
      double maxLot    = MarketInfo(symbols[i], MODE_MAXLOT   );
      double lotStep   = MarketInfo(symbols[i], MODE_LOTSTEP  );

      int error = GetLastError();                     // auf ERR_UNKNOWN_SYMBOL pr�fen
      if (error != NO_ERROR)
         return(catch("onStart(1)   \""+ symbols[i] +"\"", error));

      // auf ERR_INVALID_MARKET_DATA pr�fen
      string errorMsg = "";
      if      (LT(bid, 0.5)          || GT(bid, 150)      ) errorMsg = StringConcatenate("Bid(\""      , symbols[i], "\") = ", NumberToStr(bid      , ".+"));
      else if (LT(tickSize, 0.00001) || GT(tickSize, 0.01)) errorMsg = StringConcatenate("TickSize(\"" , symbols[i], "\") = ", NumberToStr(tickSize , ".+"));
      else if (LT(tickValue, 0.5)    || GT(tickValue, 20) ) errorMsg = StringConcatenate("TickValue(\"", symbols[i], "\") = ", NumberToStr(tickValue, ".+"));
      else if (LT(minLot, 0.01)      || GT(minLot, 0.1)   ) errorMsg = StringConcatenate("MinLot(\""   , symbols[i], "\") = ", NumberToStr(minLot   , ".+"));
      else if (LT(maxLot, 50)                             ) errorMsg = StringConcatenate("MaxLot(\""   , symbols[i], "\") = ", NumberToStr(maxLot   , ".+"));
      else if (LT(lotStep, 0.01)     || GT(lotStep, 0.1)  ) errorMsg = StringConcatenate("LotStep(\""  , symbols[i], "\") = ", NumberToStr(lotStep  , ".+"));

      // ERR_INVALID_MARKET_DATA behandeln
      if (StringLen(errorMsg) > 0) {
         if (retry < 3) {                                                                       // 3 stille Versuche, korrekte Werte zu lesen
            Sleep(200);
            i = -1;
            retry++;
            continue;
         }
         PlaySound("notify.wav");                                                               // danach Best�tigung per Dialog
         int button = MessageBox("Invalid MarketInfo() data.\n\n"+ errorMsg, __NAME__, MB_ICONINFORMATION|MB_RETRYCANCEL);
         if (button == IDRETRY) {
            i = -1;
            continue;
         }
         return(catch("onStart(2)"));
      }

      double lotValue = bid / tickSize * tickValue;                                             // Lotvalue in Account-Currency
      double unitSize = equity / lotValue * leverage;                                           // equity/lotValue entspricht einem Hebel von 1, dieser Wert wird mit leverage gehebelt
      lots[i] = Units * unitSize;
      lots[i] = NormalizeDouble(MathRound(lots[i]/lotStep) * lotStep, CountDecimals(lotStep));  // auf Vielfaches von MODE_LOTSTEP runden

      if (LT(lots[i], minLot))
         return(catch("onStart(3)   Invalid trade volume for "+ GetSymbolName(symbols[i]) +": "+ NumberToStr(lots[i], ".+") +"  (minLot="+ NumberToStr(minLot, ".+") +")", ERR_INVALID_TRADE_VOLUME));
      if (GT(lots[i], maxLot))
         return(catch("onStart(4)   Invalid trade volume for "+ GetSymbolName(symbols[i]) +": "+ NumberToStr(lots[i], ".+") +"  (maxLot="+ NumberToStr(maxLot, ".+") +")", ERR_INVALID_TRADE_VOLUME));
   }


   // (3) Directions bestimmen
   for (i=0; i < 6; i++) {
      if (StringStartsWith(symbols[i], Currency)) directions[i]  = iDirection;
      else                                        directions[i]  = iDirection ^ 1;              // 0=>1, 1=>0
      if (Currency == "JPY")                      directions[i] ^= 1;                           // JPY ist invers notiert
   }


   // (4) Sicherheitsabfrage
   PlaySound("notify.wav");
   button = MessageBox(ifString(!IsDemo(), "- Live Account -\n\n", "") +"Do you really want to "+ StringToLower(OperationTypeDescription(iDirection)) +" "+ NumberToStr(Units, ".+") + ifString(EQ(Units, 1), " unit ", " units ") + Currency +"?", __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
   if (button != IDOK)
      return(catch("onStart(5)"));


   // (5) Daten bereits offener Positionen einlesen
   if (!ReadOpenPositions())
      return(last_error);


   // (6) neue Position �ffnen
   int    counter     = GetPositionCounter() + 1;
   string comment     = StringConcatenate(Currency, ".", counter, "/", DoubleToStr(Units, 1));
   int    magicNumber = CreateMagicNumber(counter);

   for (i=0; i < 6; i++) {
      double   price       = NULL;
      double   slippage    = 0.1;
      double   sl          = NULL;
      double   tp          = NULL;
      datetime expiration  = NULL;
      color    markerColor = CLR_NONE;
      int      oeFlags     = NULL;

      if (IsError(stdlib_GetLastError())) return(SetLastError(stdlib_GetLastError()));    // vor Orderaufgabe alle aufgetretenen Fehler abfangen
      if (IsError(catch("onStart(6)")))   return(last_error);

      /*ORDER_EXECUTION*/int oe[]; InitializeByteBuffer(oe, ORDER_EXECUTION.size);
      tickets[i] = OrderSendEx(symbols[i], directions[i], lots[i], price, slippage, sl, tp, comment, magicNumber, expiration, markerColor, oeFlags, oe);
      if (tickets[i] == -1)
         return(SetLastError(stdlib_GetLastError()));
   }


   // (7) OpenPrice der neuen Position berechnen
   double openPrice = 1.0;

   for (i=0; i < 6; i++) {
      if (!SelectTicket(tickets[i], "onStart(7)"))
         return(last_error);
      if (StringStartsWith(OrderSymbol(), Currency)) openPrice *= OrderOpenPrice();
      else                                           openPrice /= OrderOpenPrice();
   }
   openPrice = MathPow(openPrice, 1.0/7);
   if (Currency == "JPY")
      openPrice = 1/openPrice;                                       // JPY ist invers notiert


   // (8) Logmessage ausgeben
   int    lfxDigits = ifInt(Currency=="JPY", 3, 5);
   string lfxFormat = ifString(Currency=="JPY", ".2'", ".4'");
          openPrice = NormalizeDouble(openPrice, lfxDigits);
   if (__LOG) log("onStart()   "+ comment +" "+ ifString(iDirection==OP_BUY, "long", "short") +" position opened at "+ NumberToStr(openPrice, lfxFormat));


   // (9) Position in ".\experts\files\SIG\remote_positions.ini" eintragen
   string file    = TerminalPath() +"\\experts\\files\\SIG\\remote_positions.ini";
   string section = ShortAccountCompany() +"."+ AccountNumber();
   string key     = Currency +"."+ counter;
   string value   = TimeToStr(ServerToGMT(OrderOpenTime()), TIME_FULL) +" | "+ ifString(iDirection==OP_BUY, "L", "S") +" | "+ DoubleToStr(Units, 1) +" | "+ DoubleToStr(openPrice, lfxDigits);

   if (!WritePrivateProfileStringA(section, key, value, file))
      return(catch("onStart(8)->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=\""+ value +"\", fileName=\""+ file +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));

   return(last_error);
}


/**
 * Liest die Daten der offenen Positionen dieser Strategie ein.
 *
 * @return bool - Erfolgsstatus
 */
bool ReadOpenPositions() {
   ArrayResize(positions.magic   , 0);
   ArrayResize(positions.currency, 0);
   ArrayResize(positions.units   , 0);
   ArrayResize(positions.instance, 0);
   ArrayResize(positions.counter , 0);

   for (int i=OrdersTotal()-1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine offene Order entfernt
         continue;

      // alle offenen Positionen dieser Strategie finden und Daten einlesen
      if (IsMyOrder()) {
         if (OrderType() > OP_SELL)
            continue;
         if (IntInArray(positions.magic, OrderMagicNumber()))
            continue;
         ArrayPushInt   (positions.magic   ,              OrderMagicNumber() );
         ArrayPushString(positions.currency, LFX.Currency(OrderMagicNumber()));
         ArrayPushDouble(positions.units   , LFX.Units   (OrderMagicNumber()));
         ArrayPushInt   (positions.instance, LFX.Instance(OrderMagicNumber()));
         ArrayPushInt   (positions.counter , LFX.Counter (OrderMagicNumber()));
      }
   }
   return(!catch("ReadOpenPositions()"));
}


/**
 * Ob die aktuell selektierte Order zu dieser Strategie geh�rt.
 *
 * @return bool
 */
bool IsMyOrder() {
   return(StrategyId(OrderMagicNumber()) == Strategy.Id);
}


/**
 * Generiert aus den internen Daten einen Wert f�r OrderMagicNumber().
 *
 * @param  int counter - Position-Z�hler, f�r den eine MagicNumber erzeugt werden soll
 *
 * @return int - MagicNumber oder -1, falls ein Fehler auftrat
 */
int CreateMagicNumber(int counter) {
   if (counter < 1) {
      catch("CreateMagicNumber(1)   invalid parameter counter = "+ counter, ERR_INVALID_FUNCTION_PARAMVALUE);
      return(-1);
   }
   int strategy = Strategy.Id & 0x3FF << 22;                         // 10 bit (Bits 23-32)
   int currency = GetCurrencyId(Currency) & 0xF << 18;               //  4 bit (Bits 19-22)
   int units    = Round(Units * 10) & 0x1F << 13;                    //  5 bit (Bits 14-18)
   int instance = GetInstance() & 0x1FF << 4;                        //  9 bit (Bits  5-13)
   int pCounter = counter & 0xF;                                     //  4 bit (Bits  1-4 )

   int error = GetLastError();
   if (error != NO_ERROR) {
      catch("CreateMagicNumber(2)", error);
      return(-1);
   }
   return(strategy + currency + units + instance + pCounter);
}


/**
 * Gibt den Positionsz�hler der letzten offenen Position im aktuellen Instrument zur�ck.
 *
 * @return int - Anzahl
 */
int GetPositionCounter() {
   int counter, size=ArraySize(positions.currency);

   for (int i=0; i < size; i++) {
      if (positions.currency[i] == Currency) {
         if (positions.counter[i] > counter)
            counter = positions.counter[i];
      }
   }
   return(counter);
}


/**
 * Gibt die aktuelle Instanz-ID zur�ck. Existiert noch keine, wird eine neue erzeugt.
 *
 * @return int - Instanz-ID im Bereich 1-511 (9 bit)
 */
int GetInstance() {
   static int id;

   if (!id) {
      MathSrand(GetTickCount());
      while (!id) {
         id = MathRand();
         while (id > 511) {
            id >>= 1;
         }
         if (IntInArray(positions.instance, id))                     // sicherstellen, da� die Instanz-ID's aller im Moment offenen Positionen eindeutig sind
            id = 0;
      }
   }
   return(id);
}
