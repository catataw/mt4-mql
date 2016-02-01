/**
 * Script, da� intern zur Ausf�hrung von TradeCommands benutzt wird. Ein manueller Aufruf ist nicht m�glich.
 *
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinStrings.mqh>
#include <stdlib.mqh>

#include <MT4iQuickChannel.mqh>
#include <lfx.mqh>
#include <structs/myfx/LFX_ORDER.mqh>
#include <core/script.ParameterProvider.mqh>

//////////////////////////////////////////////////////////////////////  Scriptparameter (�bergabe per QuickChannel)  //////////////////////////////////////////////////////////////////////

string command = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

int    lfxTicket;                                                    // geparste Details des �bergebenen TradeCommands
string action;
double leverage;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) TradeAccount initialisieren
   if (!InitTradeAccount())
      return(last_error);


   // (2) Scriptparameter einlesen
   string names[], values[];
   int size = GetScriptParameters(names, values);
   if (size == -1) return(last_error);
   for (int i=0; i < size; i++) {
      if (names[i] == "command") {
         command = values[i];
         break;
      }
   }
   if (i >= size) return(catch("onInit(1)  missing script parameter (command)", ERR_INVALID_INPUT_PARAMETER));


   // (3) Scriptparameter validieren, Format: "LFX:{iTicket}:{sAction}", z.B. "LFX:428371265:open"
   if (!StringStartsWith(command, "LFX:")) return(catch("onInit(2)  invalid parameter command = \""+ command +"\" (prefix)", ERR_INVALID_INPUT_PARAMETER));
   int pos = StringFind(command, ":", 4);
   if (pos == -1)                          return(catch("onInit(3)  invalid parameter command = \""+ command +"\" (action)", ERR_INVALID_INPUT_PARAMETER));
   string sValue = StringSubstrFix(command, 4, pos-4);
   if (!StringIsDigit(sValue))             return(catch("onInit(4)  invalid parameter command = \""+ command +"\" (ticket)", ERR_INVALID_INPUT_PARAMETER));
   lfxTicket = StrToInteger(sValue);
   if (!lfxTicket)                         return(catch("onInit(5)  invalid parameter command = \""+ command +"\" (ticket)", ERR_INVALID_INPUT_PARAMETER));
   action = StringToLower(StringSubstr(command, pos+1));
   if (action!="open" && action!="close")  return(catch("onInit(6)  invalid parameter command = \""+ command +"\" (action)", ERR_INVALID_INPUT_PARAMETER));


   // (4) ggf. Leverage-Konfiguration einlesen und validieren
   if (action == "open") {
      if (!IsGlobalConfigKey("MoneyManagement", "BasketLeverage"))
                                           return(catch("onInit(7)  Missing global MetaTrader config value [MoneyManagement]->BasketLeverage", ERR_INVALID_CONFIG_PARAMVALUE));
      sValue = GetGlobalConfigString("MoneyManagement", "BasketLeverage");
      if (!StringIsNumeric(sValue))        return(catch("onInit(8)  Invalid MetaTrader config value [MoneyManagement]->BasketLeverage = \""+ sValue +"\"", ERR_INVALID_CONFIG_PARAMVALUE));
      leverage = StrToDouble(sValue);
      if (leverage < 1)                    return(catch("onInit(9)  Invalid MetaTrader config value [MoneyManagement]->BasketLeverage = "+ NumberToStr(leverage, ".+"), ERR_INVALID_CONFIG_PARAMVALUE));
   }


   // (5) SMS-Konfiguration einlesen
   __SMS.alerts = GetLocalConfigBool("EventTracker", "SMS.Alerts");
   if (__SMS.alerts) {
      __SMS.receiver = GetConfigString("SMS", "Receiver");
      if (!StringLen(__SMS.receiver)) {
         __SMS.alerts = false;
         return(catch("onInit(10)  missing setting [SMS]->Receiver", ERR_INVALID_CONFIG_PARAMVALUE));
      }
   }
   return(catch("onInit(11)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   QC.StopChannels();
   QC.StopScriptParameterSender();
   return(last_error);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   int lfxOrder[LFX_ORDER.intSize];

   // Order holen (initialisiert TradeAccount-Variablen)
   int result = LFX.GetOrder(lfxTicket, lfxOrder);
   if (result < 1) { if (!result) return(last_error); return(catch("onStart(1)  LFX order "+ lfxTicket +" not found (command = \""+ command +"\")", ERR_INVALID_INPUT_PARAMETER)); }

   // Action ausf�hren
   if      (action == "open" ) OpenOrder    (lfxOrder);
   else if (action == "close") ClosePosition(lfxOrder);
   else                        warn("onStart(2)  unknown action command \""+ action +"\"");

   ArrayResize(lfxOrder, 0);
   return(last_error);
}


/**
 * �ffnet eine Pending-Order.
 *
 * @param  LFX_ORDER order - die zu �ffnende LFX-Order
 *
 * @return bool - Erfolgsstatus
 */
bool OpenOrder(/*LFX_ORDER*/int order[]) {

   // Um die Implementierung �bersichtlich zu halten, wird der Funktionsablauf in Teilschritte aufgeteilt und jeder Schritt
   // in eine eigene Funktion ausgelagert:
   //
   //  - Order ausf�hren
   //  - Order speichern (Erfolgs- oder Fehlerstatus), dabei ERR_CONCURRENT_MODIFICATION ber�cksichtigen
   //  - LFX-Terminal benachrichtigen (Erfolgs- oder Fehlerstatus)
   //  - SMS-Benachrichtigung verschicken (Erfolgs- oder Fehlerstatus)

   if (__LOG) log("OpenOrder(1)  open #"+ lo.Ticket(order) +" on "+ tradeAccount.company +":"+ tradeAccount.number +" ("+ tradeAccount.currency +")");

   int  subPositions, error;

   bool success.open   = OpenOrder.Execute          (order, subPositions); error = last_error;
   bool success.save   = OpenOrder.Save             (order, !success.open);
   bool success.notify = OpenOrder.NotifyLfxTerminal(order);
   bool success.sms    = OpenOrder.SendSMS          (order, subPositions, error);

   return(success.open && success.save && success.notify && success.sms);
}


/**
 * �ffnet die Order.
 *
 * @param  LFX_ORDER  lo[]         - LFX-Order
 * @param  int       &subPositions - Zeiger auf Variable zur Aufnahme der Anzahl der ge�ffneten Subpositionen
 *
 * @return bool - Erfolgsstatus
 */
bool OpenOrder.Execute(/*LFX_ORDER*/int lo[], int &subPositions) {
   subPositions = 0;
   if (!lo.IsPendingOrder(lo)) return(!catch("OpenOrder.Execute(1)  #"+ lo.Ticket(lo) +" cannot open "+ ifString(lo.IsOpenPosition(lo), "an already open position", "a closed order"), ERR_RUNTIME_ERROR));

   // (1) Trade-Parameter einlesen
   string lfxCurrency  = lo.Currency(lo);
   int    direction    = IsShortTradeOperation(lo.Type(lo));
   double units        = lo.Units(lo);


   // (2) zu handelnde Pairs bestimmen                                                 // TODO: Brokerspezifische Symbole ermitteln
   string symbols    [7];
   int    symbolsSize;
   double preciseLots[7], roundedLots[7], realUnits;
   int    directions [7];
   int    tickets    [7];
   if      (lfxCurrency == "AUD") { symbols[0] = "AUDCAD"; symbols[1] = "AUDCHF"; symbols[2] = "AUDJPY"; symbols[3] = "AUDUSD"; symbols[4] = "EURAUD"; symbols[5] = "GBPAUD";                        symbolsSize = 6; }
   else if (lfxCurrency == "CAD") { symbols[0] = "AUDCAD"; symbols[1] = "CADCHF"; symbols[2] = "CADJPY"; symbols[3] = "EURCAD"; symbols[4] = "GBPCAD"; symbols[5] = "USDCAD";                        symbolsSize = 6; }
   else if (lfxCurrency == "CHF") { symbols[0] = "AUDCHF"; symbols[1] = "CADCHF"; symbols[2] = "CHFJPY"; symbols[3] = "EURCHF"; symbols[4] = "GBPCHF"; symbols[5] = "USDCHF";                        symbolsSize = 6; }
   else if (lfxCurrency == "EUR") { symbols[0] = "EURAUD"; symbols[1] = "EURCAD"; symbols[2] = "EURCHF"; symbols[3] = "EURGBP"; symbols[4] = "EURJPY"; symbols[5] = "EURUSD";                        symbolsSize = 6; }
   else if (lfxCurrency == "GBP") { symbols[0] = "EURGBP"; symbols[1] = "GBPAUD"; symbols[2] = "GBPCAD"; symbols[3] = "GBPCHF"; symbols[4] = "GBPJPY"; symbols[5] = "GBPUSD";                        symbolsSize = 6; }
   else if (lfxCurrency == "JPY") { symbols[0] = "AUDJPY"; symbols[1] = "CADJPY"; symbols[2] = "CHFJPY"; symbols[3] = "EURJPY"; symbols[4] = "GBPJPY"; symbols[5] = "USDJPY";                        symbolsSize = 6; }
   else if (lfxCurrency == "NZD") { symbols[0] = "AUDNZD"; symbols[1] = "EURNZD"; symbols[2] = "GBPNZD"; symbols[3] = "NZDCAD"; symbols[4] = "NZDCHF"; symbols[5] = "NZDJPY"; symbols[6] = "NZDUSD"; symbolsSize = 7; }
   else if (lfxCurrency == "USD") { symbols[0] = "AUDUSD"; symbols[1] = "EURUSD"; symbols[2] = "GBPUSD"; symbols[3] = "USDCAD"; symbols[4] = "USDCHF"; symbols[5] = "USDJPY";                        symbolsSize = 6; }


   // (3) Lotsizes je Pair berechnen
   double equity = MathMin(AccountBalance(), AccountEquity()-AccountCredit());
   string errorMsg, overLeverageMsg;

   for (int retry, i=0; i < symbolsSize; i++) {
      // (3.1) notwendige Daten ermitteln
      double bid           = MarketInfo(symbols[i], MODE_BID      );                   // TODO: bei ERR_SYMBOL_NOT_AVAILABLE Symbole laden
      double tickSize      = MarketInfo(symbols[i], MODE_TICKSIZE );
      double tickValue     = MarketInfo(symbols[i], MODE_TICKVALUE);
      double minLot        = MarketInfo(symbols[i], MODE_MINLOT   );
      double maxLot        = MarketInfo(symbols[i], MODE_MAXLOT   );
      double lotStep       = MarketInfo(symbols[i], MODE_LOTSTEP  );
      int    lotStepDigits = CountDecimals(lotStep);
      if (IsError(catch("OpenOrder.Execute(2)  \""+ symbols[i] +"\""))) return(false);

      // (3.2) auf ung�ltige MarketInfo()-Daten pr�fen
      errorMsg = "";
      if      (LT(bid, 0.5)          || GT(bid, 300)      ) errorMsg = "Bid(\""      + symbols[i] +"\") = "+ NumberToStr(bid      , ".+");
      else if (LT(tickSize, 0.00001) || GT(tickSize, 0.01)) errorMsg = "TickSize(\"" + symbols[i] +"\") = "+ NumberToStr(tickSize , ".+");
      else if (LT(tickValue, 0.5)    || GT(tickValue, 20) ) errorMsg = "TickValue(\""+ symbols[i] +"\") = "+ NumberToStr(tickValue, ".+");
      else if (LT(minLot, 0.01)      || GT(minLot, 0.1)   ) errorMsg = "MinLot(\""   + symbols[i] +"\") = "+ NumberToStr(minLot   , ".+");
      else if (LT(maxLot, 50)                             ) errorMsg = "MaxLot(\""   + symbols[i] +"\") = "+ NumberToStr(maxLot   , ".+");
      else if (LT(lotStep, 0.01)     || GT(lotStep, 0.1)  ) errorMsg = "LotStep(\""  + symbols[i] +"\") = "+ NumberToStr(lotStep  , ".+");

      // (3.3) ung�ltige MarketInfo()-Daten behandeln
      if (StringLen(errorMsg) > 0) {
         if (retry < 3) {                                                              // 3 stille Versuche, korrekte Werte zu lesen
            Sleep(200);                                                                // bei Mi�erfolg jeweils xxx Millisekunden warten
            i = -1;
            retry++;
            continue;
         }                                                                             // TODO: auf ERR_CONCURRENT_MODIFICATION pr�fen
         return(!catch("OpenOrder.Execute(3)  invalid MarketInfo() data: "+ errorMsg, ERR_INVALID_MARKET_DATA));
      }

      // (3.4) Lotsize berechnen
      double lotValue = bid / tickSize * tickValue;                                    // Lotvalue eines Lots in Account-Currency
      double unitSize = equity / lotValue * leverage / symbolsSize;                    // equity/lotValue entspricht einem Hebel von 1, dieser Wert wird mit leverage gehebelt
      preciseLots[i] = units * unitSize;                                               // perfectLots zun�chst auf Vielfaches von MODE_LOTSTEP abrunden
      roundedLots[i] = NormalizeDouble(MathRound(preciseLots[i]/lotStep) * lotStep, lotStepDigits);

      // Schrittweite mit zunehmender Lotsize �ber MODE_LOTSTEP hinaus erh�hen (entspricht Algorythmus in ChartInfos-Indikator)
      if      (roundedLots[i] <=    0.3 ) {                                                                                                       }   // Abstufung max. 6.7% je Schritt
      else if (roundedLots[i] <=    0.75) { if (lotStep <   0.02) roundedLots[i] = NormalizeDouble(MathRound(roundedLots[i]/  0.02) *   0.02, 2); }   // 0.3-0.75: Vielfaches von   0.02
      else if (roundedLots[i] <=    1.2 ) { if (lotStep <   0.05) roundedLots[i] = NormalizeDouble(MathRound(roundedLots[i]/  0.05) *   0.05, 2); }   // 0.75-1.2: Vielfaches von   0.05
      else if (roundedLots[i] <=    3.  ) { if (lotStep <   0.1 ) roundedLots[i] = NormalizeDouble(MathRound(roundedLots[i]/  0.1 ) *   0.1 , 1); }   //    1.2-3: Vielfaches von   0.1
      else if (roundedLots[i] <=    7.5 ) { if (lotStep <   0.2 ) roundedLots[i] = NormalizeDouble(MathRound(roundedLots[i]/  0.2 ) *   0.2 , 1); }   //    3-7.5: Vielfaches von   0.2
      else if (roundedLots[i] <=   12.  ) { if (lotStep <   0.5 ) roundedLots[i] = NormalizeDouble(MathRound(roundedLots[i]/  0.5 ) *   0.5 , 1); }   //   7.5-12: Vielfaches von   0.5
      else if (roundedLots[i] <=   30.  ) { if (lotStep <   1.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/  1   ) *   1      ); }   //    12-30: Vielfaches von   1
      else if (roundedLots[i] <=   75.  ) { if (lotStep <   2.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/  2   ) *   2      ); }   //    30-75: Vielfaches von   2
      else if (roundedLots[i] <=  120.  ) { if (lotStep <   5.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/  5   ) *   5      ); }   //   75-120: Vielfaches von   5
      else if (roundedLots[i] <=  300.  ) { if (lotStep <  10.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/ 10   ) *  10      ); }   //  120-300: Vielfaches von  10
      else if (roundedLots[i] <=  750.  ) { if (lotStep <  20.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/ 20   ) *  20      ); }   //  300-750: Vielfaches von  20
      else if (roundedLots[i] <= 1200.  ) { if (lotStep <  50.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/ 50   ) *  50      ); }   // 750-1200: Vielfaches von  50
      else                                { if (lotStep < 100.  ) roundedLots[i] =       MathRound(MathRound(roundedLots[i]/100   ) * 100      ); }   // 1200-...: Vielfaches von 100

      // (3.5) Lotsize validieren
      if (GT(roundedLots[i], maxLot)) return(!catch("OpenOrder.Execute(4)  #"+ lo.Ticket(lo) +" too large trade volume for "+ GetSymbolName(symbols[i]) +": "+ NumberToStr(roundedLots[i], ".+") +" lot (maxLot="+ NumberToStr(maxLot, ".+") +")", ERR_INVALID_TRADE_VOLUME));

      // (3.6) bei zu geringer Equity Leverage erh�hen und Details f�r Warnung in (3.8) hinterlegen
      if (LT(roundedLots[i], minLot)) {
         roundedLots[i]  = minLot;
         overLeverageMsg = StringConcatenate(overLeverageMsg, ", ", symbols[i], " ", NumberToStr(roundedLots[i], ".+"), " instead of ", preciseLots[i], " lot");
      }
      log("OpenOrder.Execute(5)  lot size "+ symbols[i] +": calculated="+ DoubleToStr(preciseLots[i], 4) +"  resulting="+ NumberToStr(roundedLots[i], ".+") +" ("+ NumberToStr(roundedLots[i]/preciseLots[i]*100-100, "+.0R") +"%)");

      // (3.7) tats�chlich zu handelnde Units berechnen (nach Auf-/Abrunden)
      realUnits += (roundedLots[i] / preciseLots[i] / symbolsSize);
   }
   realUnits = NormalizeDouble(realUnits * units, 1);
   log("OpenOrder.Execute(6)  units: parameter="+ DoubleToStr(units, 1) +"  resulting="+ DoubleToStr(realUnits, 1));

   // (3.8) bei Leverage�berschreitung Info loggen, jedoch nicht abbrechen
   if (StringLen(overLeverageMsg) > 0) log("OpenOrder.Execute(7)  #"+ lo.Ticket(lo) +" Not enough money! The following positions will over-leverage: "+ StringRight(overLeverageMsg, -2) +". Resulting position: "+ DoubleToStr(realUnits, 1) + ifString(EQ(realUnits, units), " units (unchanged)", " instead of "+ DoubleToStr(units, 1) +" units"+ ifString(LT(realUnits, units), " (not obtainable)", "")));


   // (4) Directions der Teilpositionen bestimmen
   for (i=0; i < symbolsSize; i++) {
      if (StringStartsWith(symbols[i], lfxCurrency)) directions[i] = direction;
      else                                           directions[i] = direction ^ 1;    // 0=>1, 1=>0
   }


   // (5) Teilorders ausf�hren und dabei Gesamt-OpenPrice berechnen
   string comment = lo.Comment(lo);
      if ( StringStartsWith(comment, lfxCurrency)) comment = StringRightFrom(comment, lfxCurrency);
      if ( StringStartsWith(comment, "."        )) comment = StringRight(comment, -1);
      if ( StringStartsWith(comment, "#"        )) comment = StringRight(comment, -1);
      if (!StringStartsWith(comment, lfxCurrency)) comment = lfxCurrency +"."+ comment;
   double openPrice = 1.0;

   for (i=0; i < symbolsSize; i++) {
      double   price       = NULL;
      double   slippage    = 0.1;
      double   sl          = NULL;
      double   tp          = NULL;
      datetime expiration  = NULL;
      color    markerColor = CLR_NONE;
      int      oeFlags     = NULL;

      /*ORDER_EXECUTION*/int oe[]; InitializeByteBuffer(oe, ORDER_EXECUTION.size);
      tickets[i] = OrderSendEx(symbols[i], directions[i], roundedLots[i], price, slippage, sl, tp, comment, lfxTicket, expiration, markerColor, oeFlags, oe);
      if (tickets[i] == -1)
         return(!SetLastError(stdlib.GetLastError()));
      subPositions++;

      if (StringStartsWith(symbols[i], lfxCurrency)) openPrice *= oe.OpenPrice(oe);
      else                                           openPrice /= oe.OpenPrice(oe);
   }
   openPrice = MathPow(openPrice, 1/7.);
   if (lfxCurrency == "JPY")
      openPrice *= 100;                                                                // JPY wird normalisiert


   // (6) LFX-Order aktualisieren
   datetime now.fxt = TimeFXT(); if (!now.fxt) return(false);

   lo.setType      (lo, direction);
   lo.setUnits     (lo, realUnits);
   lo.setOpenTime  (lo, now.fxt  );
   lo.setOpenPrice (lo, openPrice);
   lo.setOpenEquity(lo, equity   );


   // (7) Logmessage ausgeben
   if (__LOG) log("OpenOrder.Execute(8)  "+ comment +" "+ ifString(direction==OP_BUY, "long", "short") +" position opened at "+ NumberToStr(lo.OpenPrice(lo), ".4'"));

   return(!catch("OpenOrder.Execute(9)"));
}


/**
 * Speichert die Order.
 *
 * @param  LFX_ORDER lo[]        - LFX-Order
 * @param  bool      isOpenError - ob bei der Orderausf�hrung ein Fehler auftrat (dieser Fehler ist u.U. nicht in der Order selbst gesetzt)
 *
 * @return bool - Erfolgsstatus
 */
bool OpenOrder.Save(/*LFX_ORDER*/int lo[], bool isOpenError) {
   isOpenError = isOpenError!=0;

   // (1) ggf. Open-Error setzen
   if (isOpenError) /*&&*/ if (!lo.IsOpenError(lo)) {
      datetime now.fxt = TimeFXT(); if (!now.fxt) return(false);
      lo.setOpenTime(lo, -now.fxt);
   }


   // (2) Order speichern
   if (!LFX.SaveOrder(lo, NULL, MUTE_ERR_CONCUR_MODIFICATION)) {     // ERR_CONCURRENT_MODIFICATION abfangen
      if (last_error != ERR_CONCURRENT_MODIFICATION)
         return(false);

      // ERR_CONCURRENT_MODIFICATION behandeln
      // -------------------------------------
      //  - Kann nur dann behandelt werden, wenn diese �nderung das Setzen von LFX_ORDER.OpenError war.
      //  - Bedeutet, da� ein Trade-Delay auftrat, der woanders bereits als Timeout (also als OpenError) interpretiert wurde.

      // (2.1) Order neu einlesen und gespeicherten OpenError-Status auswerten
      /*LFX_ORDER*/int stored[];
      int result = LFX.GetOrder(lo.Ticket(lo), stored);
      if (result != 1) { if (!result) return(last_error); return(!catch("OpenOrder.Save(1)->LFX.GetOrder()  order #"+ lo.Ticket(lo) +" not found", ERR_RUNTIME_ERROR)); }
      if (!lo.IsOpenError(stored))                        return(!catch("OpenOrder.Save(2)->LFX.SaveOrder()  concurrent modification of #"+ lo.Ticket(lo) +", expected version "+ lo.Version(lo) +" of '"+ TimeToStr(lo.ModificationTime(lo), TIME_FULL) +" FXT', found version "+ lo.Version(stored) +" of '"+ TimeToStr(lo.ModificationTime(stored), TIME_FULL) +" FXT'", ERR_CONCURRENT_MODIFICATION));


      // (2.2) ERR_CONCURRENT_MODIFICATION immer �berschreiben (auch bei fehlgeschlagener Ausf�hrung), um ein evt. "Mehr" an Ausf�rungsdetails nicht zu verlieren
      if (!isOpenError)
         if (__LOG) log("OpenOrder.Save(3)  over-writing LFX_ORDER.OpenError (was ERR_CONCURRENT_MODIFICATION)");

      lo.setVersion(lo, lo.Version(stored));
      if (!LFX.SaveOrder(lo))                                        // diesmal ohne irgendwelche Fehler abzufangen
         return(false);
   }
   return(true);
}


/**
 * Schickt eine Benachrichtigung �ber Erfolg/Mi�erfolg der Orderausf�hrung ans LFX-Terminal.
 *
 * @param  LFX_ORDER lo[] - LFX-Order
 *
 * @return bool - Erfolgsstatus
 */
bool OpenOrder.NotifyLfxTerminal(/*LFX_ORDER*/int lo[]) {
   return(QC.SendOrderNotification(lo.CurrencyId(lo), "LFX:"+ lo.Ticket(lo) +":open="+ (!lo.IsOpenError(lo))));
}


/**
 * Verschickt eine SMS �ber Erfolg/Mi�erfolg der Orderausf�hrung.
 *
 * @param  LFX_ORDER lo[]         - LFX-Order
 * @param  int       subPositions - Anzahl der ge�ffneten Subpositionen
 * @param  int       error        - bei der Orderausf�hrung aufgetretener Fehler (falls zutreffend)
 *
 * @return bool - Erfolgsstatus
 */
bool OpenOrder.SendSMS(/*LFX_ORDER*/int lo[], int subPositions, int error) {
   if (__SMS.alerts) {
      string comment=lo.Comment(lo), currency=lo.Currency(lo);
         if (StringStartsWith(comment, currency)) comment = StringSubstr(comment, 3);
         if (StringStartsWith(comment, "."     )) comment = StringSubstr(comment, 1);
         if (StringStartsWith(comment, "#"     )) comment = StringSubstr(comment, 1);
      int    counter = StrToInteger(comment);
      string message = tradeAccount.alias +": ";
      if (lo.IsOpenError(lo)) message = StringConcatenate(message, "opening of ", OperationTypeDescription(lo.Type(lo)), " ", currency, ".", counter, " at ", NumberToStr(lo.OpenPrice(lo), ".4'"), " failed (", ErrorToStr(error), "), ", subPositions, " subposition", ifString(subPositions==1, "", "s"), " opened");
      else                    message = StringConcatenate(message, currency, ".", counter, " ", ifString(lo.Type(lo)==OP_BUY, "long", "short"), " position opened at ", NumberToStr(lo.OpenPrice(lo), ".4'"));

      if (!SendSMS(__SMS.receiver, TimeToStr(TimeLocalEx("OpenOrder.SendSMS(1)"), TIME_MINUTES) +" "+ message))
         return(!SetLastError(stdlib.GetLastError()));
   }
   return(true);
}


/**
 * Schlie�t eine offene Position.
 *
 * @param  LFX_ORDER order - die zu schlie�ende LFX-Order
 *
 * @return bool - Erfolgsstatus
 */
bool ClosePosition(/*LFX_ORDER*/int order[]) {

   // Um die Implementierung �bersichtlich zu halten, wird der Funktionsablauf in Teilschritte aufgeteilt und jeder Schritt
   // in eine eigene Funktion ausgelagert:
   //
   //  - Position schlie�en
   //  - Order speichern (Erfolgs- oder Fehlerstatus), dabei ERR_CONCURRENT_MODIFICATION ber�cksichtigen
   //  - LFX-Terminal benachrichtigen (Erfolgs- oder Fehlerstatus)
   //  - SMS-Benachrichtigung verschicken (Erfolgs- oder Fehlerstatus)

   if (__LOG) log("ClosePosition(1)  close #"+ lo.Ticket(order) +" on "+ tradeAccount.company +":"+ tradeAccount.number +" ("+ tradeAccount.currency +")");

   string comment = lo.Comment(order);
   int    error;

   bool success.close  = ClosePosition.Execute          (order); error = last_error;
   bool success.save   = ClosePosition.Save             (order, !success.close);
   bool success.notify = ClosePosition.NotifyLfxTerminal(order);
   bool success.sms    = ClosePosition.SendSMS          (order, comment, error);

   return(success.close && success.save && success.notify && success.sms);
}


/**
 * Schlie�t die Position.
 *
 * @param  LFX_ORDER lo[] - LFX-Order
 *
 * @return bool - Erfolgsstatus
 */
bool ClosePosition.Execute(/*LFX_ORDER*/int lo[]) {
   if (!lo.IsOpenPosition(lo)) return(!catch("ClosePosition.Execute(1)  #"+ lo.Ticket(lo) +" cannot close "+ ifString(lo.IsPendingOrder(lo), "a pending", "an already closed") +" order", ERR_RUNTIME_ERROR));


   // (1) zu schlie�ende Einzelpositionen selektieren
   int tickets[], orders=OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: in einem anderen Thread wurde eine aktive Order geschlossen oder gestrichen
         break;
      if (OrderType() > OP_SELL)
         continue;
      if (OrderMagicNumber() == lo.Ticket(lo))
         ArrayPushInt(tickets, OrderTicket());
   }
   int ticketsSize = ArraySize(tickets);
   if (!ticketsSize) return(!catch("ClosePosition.Execute(2)  #"+ lo.Ticket(lo) +" no matching open subpositions found ", ERR_RUNTIME_ERROR));


   // (2) Einzelpositionen schlie�en
   double slippage    = 0.1;
   color  markerColor = CLR_NONE;
   int    oeFlags     = NULL;

   /*ORDER_EXECUTION*/int oes[][ORDER_EXECUTION.intSize]; ArrayResize(oes, ticketsSize); InitializeByteBuffer(oes, ORDER_EXECUTION.size);
   if (!OrderMultiClose(tickets, slippage, markerColor, oeFlags, oes))
      return(!SetLastError(stdlib.GetLastError()));


   // (3) Gesamt-ClosePrice und -Profit berechnen
   string currency = lo.Currency(lo);
   double closePrice=1.0, profit=0;
   for (i=0; i < ticketsSize; i++) {
      if (StringStartsWith(oes.Symbol(oes, i), currency)) closePrice *= oes.ClosePrice(oes, i);
      else                                                closePrice /= oes.ClosePrice(oes, i);
      profit += oes.Swap(oes, i) + oes.Commission(oes, i) + oes.Profit(oes, i);
   }
   closePrice = MathPow(closePrice, 1/7.);
   if (currency == "JPY")
      closePrice *= 100;                                             // JPY wird normalisiert


   // (4) LFX-Order aktualisieren
   datetime now.fxt  = TimeFXT(); if (!now.fxt) return(false);
   string oldComment = lo.Comment(lo);
   lo.setCloseTime (lo, now.fxt   );
   lo.setClosePrice(lo, closePrice);
   lo.setProfit    (lo, profit    );
   lo.setComment   (lo, ""        );


   // (5) Logmessage ausgeben                                        // letzten Counter ermitteln
   if (StringStartsWith(oldComment, lo.Currency(lo))) oldComment = StringRight(oldComment, -3);
   if (StringStartsWith(oldComment, "."            )) oldComment = StringRight(oldComment, -1);
   if (StringStartsWith(oldComment, "#"            )) oldComment = StringRight(oldComment, -1);
   int counter = StrToInteger(oldComment);

   if (__LOG) log("ClosePosition.Execute(3)  "+ currency +"."+ counter +" closed at "+ NumberToStr(lo.ClosePrice(lo), ".4'") +", profit: "+ DoubleToStr(lo.Profit(lo), 2));

   return(true);
}


/**
 * Speichert die Order.
 *
 * @param  LFX_ORDER lo[]         - LFX-Order
 * @param  bool      isCloseError - ob bei der Orderausf�hrung ein Fehler auftrat (dieser Fehler ist u.U. nicht in der Order selbst gesetzt)
 *
 * @return bool - Erfolgsstatus
 */
bool ClosePosition.Save(/*LFX_ORDER*/int lo[], bool isCloseError) {
   isCloseError = isCloseError!=0;

   // (1) ggf. CloseError setzen
   if (isCloseError) /*&&*/ if (!lo.IsCloseError(lo)) {
      datetime now.fxt = TimeFXT(); if (!now.fxt) return(false);
      lo.setCloseTime(lo, -now.fxt);
   }


   // (2) Order speichern
   if (!LFX.SaveOrder(lo, NULL, MUTE_ERR_CONCUR_MODIFICATION)) {     // ERR_CONCURRENT_MODIFICATION abfangen
      if (last_error != ERR_CONCURRENT_MODIFICATION)
         return(false);

      // ERR_CONCURRENT_MODIFICATION behandeln
      // -------------------------------------
      //  - Kann nur dann behandelt werden, wenn diese �nderung das Setzen von LFX_ORDER.CloseError war.
      //  - Bedeutet, da� ein Trade-Delay auftrat, der woanders bereits als Timeout (also als CloseError) interpretiert wurde.

      // (2.1) Order neu einlesen und gespeicherten CloseError-Status auswerten
      /*LFX_ORDER*/int stored[];
      int result = LFX.GetOrder(lo.Ticket(lo), stored);
      if (result != 1) { if (!result) return(last_error); return(!catch("ClosePosition.Save(1)->LFX.GetOrder()  order #"+ lo.Ticket(lo) +" not found", ERR_RUNTIME_ERROR)); }
      if (!lo.IsCloseError(stored))                       return(!catch("ClosePosition.Save(2)->LFX.SaveOrder()  concurrent modification of #"+ lo.Ticket(lo) +", expected version "+ lo.Version(lo) +" of '"+ TimeToStr(lo.ModificationTime(lo), TIME_FULL) +" FXT', found version "+ lo.Version(stored) +" of '"+ TimeToStr(lo.ModificationTime(stored), TIME_FULL) +" FXT'", ERR_CONCURRENT_MODIFICATION));


      // (2.2) ERR_CONCURRENT_MODIFICATION immer �berschreiben (auch bei fehlgeschlagener Ausf�hrung), um ein evt. "Mehr" an Ausf�rungsdetails nicht zu verlieren
      if (!isCloseError)
         if (__LOG) log("ClosePosition.Save(3)  over-writing LFX_ORDER.CloseError (was ERR_CONCURRENT_MODIFICATION)");

      lo.setVersion(lo, lo.Version(stored));
      if (!LFX.SaveOrder(lo))                                        // diesmal ohne irgendwelche Fehler abzufangen
         return(false);
   }
   return(true);
}


/**
 * Schickt eine Benachrichtigung �ber Erfolg/Mi�erfolg der Orderausf�hrung ans LFX-Terminal.
 *
 * @param  LFX_ORDER lo[] - LFX-Order
 *
 * @return bool - Erfolgsstatus
 */
bool ClosePosition.NotifyLfxTerminal(/*LFX_ORDER*/int lo[]) {
   return(QC.SendOrderNotification(lo.CurrencyId(lo), "LFX:"+ lo.Ticket(lo) +":close="+ (!lo.IsCloseError(lo))));
}


/**
 * Verschickt eine SMS �ber Erfolg/Mi�erfolg der Orderausf�hrung.
 *
 * @param  LFX_ORDER lo[]    - LFX-Order
 * @param  string    comment - das urspr�ngliche Label bzw. der Comment der Order
 * @param  int       error   - bei der Orderausf�hrung aufgetretener Fehler (falls zutreffend)
 *
 * @return bool - Erfolgsstatus
 */
bool ClosePosition.SendSMS(/*LFX_ORDER*/int lo[], string comment, int error) {
   if (__SMS.alerts) {
      string currency = lo.Currency(lo);
      if (StringStartsWith(comment, currency)) comment = StringSubstr(comment, 3);
      if (StringStartsWith(comment, "."     )) comment = StringSubstr(comment, 1);
      if (StringStartsWith(comment, "#"     )) comment = StringSubstr(comment, 1);
      int    counter = StrToInteger(comment);
      string message = tradeAccount.alias +": ";
      if (lo.IsCloseError(lo)) message = StringConcatenate(message, "closing of ", ifString(lo.Type(lo)==OP_BUY, "long", "short"), " position ", currency, ".", counter, " failed (", ErrorToStr(error), ")");
      else                     message = StringConcatenate(message, currency, ".", counter, " ", ifString(lo.Type(lo)==OP_BUY, "long", "short"), " position closed at ", NumberToStr(lo.ClosePrice(lo), ".4'"));

      if (!SendSMS(__SMS.receiver, TimeToStr(TimeLocalEx("ClosePosition.SendSMS(1)"), TIME_MINUTES) +" "+ message))
         return(!SetLastError(stdlib.GetLastError()));
   }
   return(true);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "struct.ORDER_EXECUTION.ex4"
   double oe.OpenPrice  (/*ORDER_EXECUTION*/int oe[]         );
   double oes.ClosePrice(/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Commission(/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Profit    (/*ORDER_EXECUTION*/int oe[][], int i);
   double oes.Swap      (/*ORDER_EXECUTION*/int oe[][], int i);
   string oes.Symbol    (/*ORDER_EXECUTION*/int oe[][], int i);
#import
