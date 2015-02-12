/**
 * Erzeugt eine neue LFX-"Sell Limit"-Order, die �berwacht und bei Erreichen des Limit-Preises ausgef�hrt wird.
 *
 *
 *  TODO: Fehler in Counter, wenn gleichzeitig zwei Orders erzeugt werden (2 x CHF.3)
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdlib.mqh>

#include <win32api.mqh>
#include <MT4iQuickChannel.mqh>

#include <LFX/functions.mqh>
#include <LFX/quickchannel.mqh>
#include <structs/pewa/LFX_ORDER.mqh>

#property show_inputs


//////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////

extern string Help  = "Sell Limit Order";
extern double Units = 1.0;                                           // Positionsgr��e (Vielfaches von 0.1 im Bereich von 0.1 bis 1.0)
extern double LimitPrice;
extern double StopLossPrice;
extern double TakeProfitPrice;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) LFX-Currency und ID bestimmen
   if      (StringStartsWith(Symbol(), "LFX")) lfxCurrency = StringRight(Symbol(), -3);
   else if (StringEndsWith  (Symbol(), "LFX")) lfxCurrency = StringLeft (Symbol(), -3);
   else                                  return(HandleScriptError("onInit(1)", "Cannot place LFX orders on a non LFX chart (\""+ Symbol() +"\")", ERR_RUNTIME_ERROR));
   lfxCurrencyId = GetCurrencyId(lfxCurrency);


   // (2) Parametervalidierung
   // Units
   if (NE(MathModFix(Units, 0.1), 0))    return(HandleScriptError("onInit(2)", "Invalid parameter Units = "+ NumberToStr(Units, ".+") +"\n(not a multiple of 0.1)", ERR_INVALID_INPUT_PARAMETER));
   if (Units < 0.1 || Units > 1)         return(HandleScriptError("onInit(3)", "Invalid parameter Units = "+ NumberToStr(Units, ".+") +"\n(valid range is from 0.1 to 1.0)", ERR_INVALID_INPUT_PARAMETER));
   Units = NormalizeDouble(Units, 1);

   // LimitPrice
   LimitPrice = NormalizeDouble(LimitPrice, SubPipDigits);
   if (LimitPrice <= 0)                  return(HandleScriptError("onInit(4)", "Illegal parameter LimitPrice = "+ NumberToStr(LimitPrice, ".+") +"\n(must be positive)", ERR_INVALID_INPUT_PARAMETER));

   // StopLossPrice
   StopLossPrice = NormalizeDouble(StopLossPrice, SubPipDigits);
   if (StopLossPrice != 0) {
      if (StopLossPrice < 0)             return(HandleScriptError("onInit(5)", "Illegal parameter StopLossPrice = "+ NumberToStr(StopLossPrice, ".+") +"\n(can't be negative)", ERR_INVALID_INPUT_PARAMETER));
      if (StopLossPrice <= LimitPrice)   return(HandleScriptError("onInit(6)", "Illegal parameter StopLossPrice = "+ NumberToStr(StopLossPrice, SubPipPriceFormat) +"\n(must be higher than the LimitPrice "+ NumberToStr(LimitPrice, SubPipPriceFormat) +")", ERR_INVALID_INPUT_PARAMETER));
   }

   // TakeProfitPrice
   TakeProfitPrice = NormalizeDouble(TakeProfitPrice, SubPipDigits);
   if (TakeProfitPrice != 0) {
      if (TakeProfitPrice < 0)           return(HandleScriptError("onInit(7)", "Illegal parameter TakeProfitPrice = "+ NumberToStr(TakeProfitPrice, ".+") +"\n(can't be negative)", ERR_INVALID_INPUT_PARAMETER));
      if (TakeProfitPrice >= LimitPrice) return(HandleScriptError("onInit(8)", "Illegal parameter TakeProfitPrice = "+ NumberToStr(TakeProfitPrice, SubPipPriceFormat) +"\n(must be lower than the LimitPrice "+ NumberToStr(LimitPrice, SubPipPriceFormat) +")", ERR_INVALID_INPUT_PARAMETER));
   }


   // (3) offene Orders einlesen
   int size = LFX.GetOrders(NULL, OF_OPEN, lfxOrders);
   if (size < 0)
      return(last_error);
   return(catch("onInit(9)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   QC.StopTradeToLfxSenders();
   return(last_error);
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   int button;

   // (1) Sicherheitsabfrage
   if (LimitPrice <= Bid) {
      PlaySoundEx("Windows Notify.wav");
      button = MessageBox(ifString(lfxAccountType==ACCOUNT_TYPE_REAL, "- Real Money Account -\n\n", "")
                        +"The limit of "+ NumberToStr(LimitPrice, SubPipPriceFormat) +" is already triggered (current price "+ NumberToStr(Bid, SubPipPriceFormat) +").\n\n"
                        +"Do you really want the order to immediately get executed?",
                        __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
      if (button != IDOK)
         return(catch("onStart(1)"));
      if (StopLossPrice   && StopLossPrice   <= Bid) return(HandleScriptError("onStart(2)", "Illegal parameter StopLossPrice = "+ NumberToStr(StopLossPrice, SubPipPriceFormat) +"\n(must be higher than the current price "+ NumberToStr(Bid, SubPipPriceFormat) +")", ERR_INVALID_INPUT_PARAMETER));
      if (TakeProfitPrice && TakeProfitPrice >= Bid) return(HandleScriptError("onStart(3)", "Illegal parameter TakeProfitPrice = "+ NumberToStr(TakeProfitPrice, SubPipPriceFormat) +"\n(must be lower than the current price "+ NumberToStr(Bid, SubPipPriceFormat) +")", ERR_INVALID_INPUT_PARAMETER));
      // TODO: Statt PendingOrder Order sofort hier ausf�hren, da sie sonst erst bei der n�chsten Preis�nderung ausgef�hrt wird (und evt. auch eben nicht).
   }
   else {
      PlaySoundEx("Windows Notify.wav");
      button = MessageBox(ifString(lfxAccountType==ACCOUNT_TYPE_REAL, "- Real Money Account -\n\n", "")
                        +"Do you really want to place a Sell Limit order for "+ NumberToStr(Units, ".+") + ifString(Units==1, " unit ", " units ") + lfxCurrency +"?\n\n"
                        +                                   "Limit: "+      NumberToStr(LimitPrice,      SubPipPriceFormat)
                        + ifString(!StopLossPrice  , "", "   StopLoss: "+   NumberToStr(StopLossPrice,   SubPipPriceFormat))
                        + ifString(!TakeProfitPrice, "", "   TakeProfit: "+ NumberToStr(TakeProfitPrice, SubPipPriceFormat)),
                        __NAME__, MB_ICONQUESTION|MB_OKCANCEL);
      if (button != IDOK)
         return(catch("onStart(4)"));
   }


   // (2) neue Order erzeugen und speichern
   double deviation = GetGlobalConfigDouble("LfxChartDeviation", lfxCurrency, 0);

   /*LFX_ORDER*/int lo[]; InitializeByteBuffer(lo, LFX_ORDER.size);
      lo.setTicket         (lo, CreateMagicNumber()          );      // Ticket immer zuerst, damit im Struct Currency-ID und Digits ermittelt werden k�nnen
      lo.setDeviation      (lo, deviation                    );      // LFX-Deviation immer vor allen Preisen
      lo.setType           (lo, OP_SELLLIMIT                 );
      lo.setUnits          (lo, Units                        );
      lo.setOpenTime       (lo, TimeGMT()                    );
      lo.setOpenPriceLfx   (lo, LimitPrice                   );
      lo.setStopLossLfx    (lo, StopLossPrice                );
      lo.setStopLossValue  (lo, EMPTY_VALUE                  );
      lo.setTakeProfitLfx  (lo, TakeProfitPrice              );
      lo.setTakeProfitValue(lo, EMPTY_VALUE                  );
      lo.setComment        (lo, "#"+ (GetPositionCounter()+1));
   if (!LFX.SaveOrder(lo))
      return(last_error);


   // (3) Orderbenachrichtigung an den Chart schicken
   if (!QC.SendOrderNotification(lo.CurrencyId(lo), "LFX:"+ lo.Ticket(lo) +":pending=1"))
      return(false);


   // (4) Best�tigungsmeldung
   PlaySoundEx("OrderOk.wav");
   MessageBox(ifString(lfxAccountType==ACCOUNT_TYPE_REAL, "- Real Money Account -\n\n", "")
            +"Sell Limit order for "+ NumberToStr(Units, ".+") + ifString(Units==1, " unit ", " units ") + lfxCurrency +" placed.\n\n"
            +                                   "Limit: "+      NumberToStr(LimitPrice,      SubPipPriceFormat)
            + ifString(!StopLossPrice  , "", "   StopLoss: "+   NumberToStr(StopLossPrice,   SubPipPriceFormat))
            + ifString(!TakeProfitPrice, "", "   TakeProfit: "+ NumberToStr(TakeProfitPrice, SubPipPriceFormat)),
            __NAME__, MB_ICONINFORMATION|MB_OK);
   return(last_error);
}


/**
 * Generiert eine neue LFX-Ticket-ID (Wert f�r OrderMagicNumber().
 *
 * @return int - LFX-Ticket-ID oder NULL, falls ein Fehler auftrat
 */
int CreateMagicNumber() {
   int iStrategy = STRATEGY_ID & 0x3FF << 22;                        // 10 bit (Bits 23-32)
   int iCurrency = lfxCurrencyId & 0xF << 18;                        //  4 bit (Bits 19-22)
   int iInstance = CreateInstanceId() & 0x3FF << 4;                  // 10 bit (Bits  5-14)
   return(iStrategy + iCurrency + iInstance);
}


/**
 * Erzeugt eine neue Instanz-ID.
 *
 * @return int - Instanz-ID im Bereich 1-1023 (10 bit)
 */
int CreateInstanceId() {
   int size=ArrayRange(lfxOrders, 0), id, ids[];
   ArrayResize(ids, 0);

   for (int i=0; i < size; i++) {
      ArrayPushInt(ids, LFX.InstanceId(los.Ticket(lfxOrders, i)));
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
 * Gibt den Positionsz�hler der letzten offenen Order im aktuellen Instrument zur�ck.
 *
 * @return int - Z�hler
 */
int GetPositionCounter() {
   int counter, size=ArrayRange(lfxOrders, 0);

   for (int i=0; i < size; i++) {
      if (los.CurrencyId(lfxOrders, i) != lfxCurrencyId)
         continue;

      string label = los.Comment(lfxOrders, i);
      if (StringStartsWith(label, lfxCurrency +".")) label = StringRight(label, -4);
      if (StringStartsWith(label,              "#")) label = StringRight(label, -1);

      counter = Max(counter, StrToInteger(label));
   }
   return(counter);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


/*abstract*/bool QC.StopScriptParameterSender()  { return(!catch("QC.StopScriptParameterSender()", ERR_WRONG_JUMP)); }
