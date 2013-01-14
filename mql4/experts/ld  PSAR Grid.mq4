/**
 * PSAR Martingale System
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_PIPVALUE};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

#include <core/expert.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern string ____________Common_____________ = "___________________________________";
extern int    GridSize                        = 40;
extern double UnitSize                        = 0.1;
extern double IncrementSize                   = 0.1;
extern int    TrailingStop.Percent            = 90;
extern int    MaxDrawdown.Percent             = 100;

extern string ___________Indicator___________ = "___________________________________";
extern double PSAR.Step                       = 0.02;
extern double PSAR.Maximum                    = 0.2;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int    long.ticket   [],   short.ticket   [];                        // Ticket
double long.lots     [],   short.lots     [];                        // Lots
double long.openPrice[],   short.openPrice[];                        // OpenPrice

double long.startEquity,   short.startEquity;
int    long.level,         short.level;
double long.sumLots,       short.sumLots;
double long.sumProfit,     short.sumProfit;
double long.maxProfit,     short.maxProfit;
bool   long.isTakeProfit,  short.isTakeProfit;
double long.lockedProfit,  short.lockedProfit;

int    magicNo  = 110413;
double slippage = 0.1;                                               // order slippage
string comment  = "ld04 PSAR";                                       // order comment


/**
 *
 */
int onTick() {
   UpdateStatus();
   Strategy();
   ShowStatus();
   return(last_error);
}


/**
 *
 */
int UpdateStatus() {
   long.sumProfit  = 0;
   short.sumProfit = 0;


   // (1) Long
   for (int i=0; i < long.level; i++) {
      if (!SelectTicket(long.ticket[i], "UpdateStatus(1)"))
         return(last_error);
      long.sumProfit  = NormalizeDouble(long.sumProfit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   if (long.sumProfit  > long.maxProfit)           long.maxProfit     = long.sumProfit;
   if (GE(long.maxProfit, GridValue(UnitSize)))  { long.lockedProfit  = NormalizeDouble(TrailingStop.Percent/100.0 * long.maxProfit,  Digits); long.isTakeProfit  = true; }


   // (2) Short
   for (i=0; i < short.level; i++) {
      if (!SelectTicket(short.ticket[i], "UpdateStatus(2)"))
         return(last_error);
      short.sumProfit = NormalizeDouble(short.sumProfit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   if (short.sumProfit > short.maxProfit)          short.maxProfit    = short.sumProfit;
   if (GE(short.maxProfit, GridValue(UnitSize))) { short.lockedProfit = NormalizeDouble(TrailingStop.Percent/100.0 * short.maxProfit, Digits); short.isTakeProfit = true; }

   return(catch("UpdateStatus(3)"));
}


/**
 *
 */
int InitStatus() {
   ResetLongStatus();
   ResetShortStatus();

   for (int i=0; i < OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol()==Symbol()) /*&&*/ if (OrderMagicNumber()==magicNo) {
            if (OrderType() == OP_BUY ) AddLongOrder (OrderTicket(), OrderLots(), OrderOpenPrice(), OrderProfit() + OrderCommission() + OrderSwap());
            if (OrderType() == OP_SELL) AddShortOrder(OrderTicket(), OrderLots(), OrderOpenPrice(), OrderProfit() + OrderCommission() + OrderSwap());
         }
      }
   }
   SortTickets();
   return(catch("InitStatus()"));
}


/**
 *
 */
int SortTickets() {
   int    tmpTicket, i1;
   double tmpLots, tmpOpenPrice;

   // Long
   for (int i=0; i < long.level-1; i++) {
      i1 = 1;
      // we have at least 2 tickets: i1 - erstes Ticket, j2 - zweites Ticket
      for (int j2=i+1; j2 < long.level; j2++) {
         if (long.ticket[i1] > long.ticket[j2]) {
            tmpTicket          = long.ticket   [i1];
            tmpLots            = long.lots     [i1];
            tmpOpenPrice       = long.openPrice[i1];

            long.ticket   [i1] = long.ticket   [j2];
            long.lots     [i1] = long.lots     [j2];
            long.openPrice[i1] = long.openPrice[j2];

            long.ticket   [j2] = tmpTicket;
            long.lots     [j2] = tmpLots;
            long.openPrice[j2] = tmpOpenPrice;
         }
      }
   }

   // Short
   for (i=0; i < short.level-1; i++) {
      // we have at least 2 tickets: i1 - erstes Ticket, j2 - zweites Ticket
      for (j2=i+1; j2 < short.level; j2++) {
         if (short.ticket[i1] > short.ticket[j2]) {
            tmpTicket           = short.ticket   [i1];
            tmpLots             = short.lots     [i1];
            tmpOpenPrice        = short.openPrice[i1];

            short.ticket   [i1] = short.ticket   [j2];
            short.lots     [i1] = short.lots     [j2];
            short.openPrice[i1] = short.openPrice[j2];

            short.ticket   [j2] = tmpTicket;
            short.lots     [j2] = tmpLots;
            short.openPrice[j2] = tmpOpenPrice;
         }
      }
   }
   return(catch("SortTickets()"));
}


/**
 *
 */
double MartingaleVolume(double loss) {
   int multiplier = Round(MathAbs(loss) / GridValue(UnitSize));
   return(multiplier * IncrementSize);             // Vielfaches der IncrementSize: völliger Blödsinn
}


/**
 *
 */
double GridValue(double lots) {
   return(GridSize * PipValue(lots));
}


/**
 *
 */
int Strategy() {
   double equity;
   double psar1 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 1);     // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 2);     // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[], /*ORDER_EXECUTION*/oes[][ORDER_EXECUTION.intSize]; if (!ArraySize(oe)) InitializeBuffer(oe, ORDER_EXECUTION.size);
   int ticket;


   // *************************
   // ACCOUNT RISK CONTROL
   // *************************
   /*
   if ((100-MaxDrawdown.Percent)/100 * AccountBalance() > AccountEquity()-AccountCredit()) {
      // Closing buy orders
      for (int i=0; i<=long.level-1; i++) {
         if (!OrderCloseEx(long.ticket[i], NULL, NULL, slippage, Blue, oeFlags, oe))
            return(_NULL(SetLastError(oe.Error(oe))));
      }
      // Closing sell orders
      for (i=0; i<=short.level-1; i++) {
         if (!OrderCloseEx(short.ticket[i], NULL, NULL, slippage, Red, oeFlags, oe))
            return(_NULL(SetLastError(oe.Error(oe))));
      }
      ResetLongStatus();
      ResetShortStatus();
   }
   */


   // ***************************************************************
   // (1) LONG
   // ***************************************************************
   if (long.level == 0) {
      if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {           // erstes PSAR-Crossing von oben nach unten
         long.startEquity = AccountEquity() - AccountCredit();

         ticket = OrderSendEx(Symbol(), OP_BUY, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddLongOrder(ticket, UnitSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   else {
      // (1.1) if lockedProfit is triggered we close everything
      if (long.isTakeProfit) /*&&*/ if (LE(long.sumProfit, long.lockedProfit)) {
         if (!OrderMultiClose(long.ticket, slippage, Blue, oeFlags, oes))
            return(SetLastError(oes.Error(oes, 0)));
         ResetLongStatus();                                          // long.level ist jetzt 0
      }

      // (1.2) if we'v reached StopLoss (grid size) and PSAR crossed we send another order
      // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
      if (long.level > 0) /*&&*/ if (LE(long.sumProfit, -GridValue(long.sumLots))) {
         if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {        // erneutes PSAR-Crossing von oben nach unten
            ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(long.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
            if (ticket <= 0)
               return(SetLastError(oe.Error(oe)));
            AddLongOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
         }
      }
   }


   // ***************************************************************
   // (2) SHORT
   // ***************************************************************
   if (short.level == 0) {
      if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {           // erstes PSAR-Crossing von unten nach oben
         short.startEquity = AccountEquity() - AccountCredit();

         ticket = OrderSendEx(Symbol(), OP_SELL, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
         AddShortOrder(ticket, UnitSize, oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
      }
   }
   else {
      // (2.1) if lockedProfit is triggered we close everything
      if (short.isTakeProfit) /*&&*/ if (LE(short.sumProfit, short.lockedProfit)) {
         if (!OrderMultiClose(short.ticket, slippage, Red, oeFlags, oes))
            return(SetLastError(oes.Error(oes, 0)));
         ResetShortStatus();                                         // short.level ist jetzt 0
      }

      // (2.2) if we'v reached StopLoss (grid size) and PSAR crossed we send another order
      // Tödlich: Martingale-Spirale, da mehrere neue Orders während derselben Bar geöffnet werden können
      if (short.level > 0) /*&&*/ if (LE(short.sumProfit, -GridValue(short.sumLots))) {
         if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {        // erneutes PSAR-Crossing von unten nach oben
            ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
            if (ticket <= 0)
               return(SetLastError(oe.Error(oe)));
            AddShortOrder(ticket, oe.Lots(oe), oe.OpenPrice(oe), oe.Profit(oe) + oe.Commission(oe) + oe.Swap(oe));
         }
      }
   }
   return(catch("Strategy()"));
}


/**
 *
 */
int ResetLongStatus() {
   ArrayResize(long.ticket,    0);
   ArrayResize(long.lots,      0);
   ArrayResize(long.openPrice, 0);

   long.startEquity  = 0;
   long.level        = 0;
   long.sumLots      = 0;
   long.sumProfit    = 0;
   long.maxProfit    = 0;
   long.isTakeProfit = false;
   long.lockedProfit = 0;

   if (!IsTesting() || IsVisualMode()) {
      ObjectDelete("line_buy_tp");
      ObjectDelete("line_buy_ts");

      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)
         return(catch("ResetLongStatus()", error));
   }
   return(NO_ERROR);
}


/**
 *
 */
int ResetShortStatus() {
   ArrayResize(short.ticket,    0);
   ArrayResize(short.lots,      0);
   ArrayResize(short.openPrice, 0);

   short.startEquity  = 0;
   short.level        = 0;
   short.sumLots      = 0;
   short.sumProfit    = 0;
   short.maxProfit    = 0;
   short.isTakeProfit = false;
   short.lockedProfit = 0;

   if (!IsTesting() || IsVisualMode()) {
      ObjectDelete("line_buy_tp");
      ObjectDelete("line_buy_ts");

      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)
         return(catch("ResetLongStatus()", error));
   }
   return(NO_ERROR);
}


/**
 * Fügt den Long-Daten eine weitere Order hinzu.
 *
 * @param  int    ticket
 * @param  double lots
 * @param  double openPrice
 * @param  double profit    - PL: profit + commission + swap
 */
int AddLongOrder(int ticket, double lots, double openPrice, double profit) {
   ArrayPushInt   (long.ticket,    ticket   );
   ArrayPushDouble(long.lots,      lots     );
   ArrayPushDouble(long.openPrice, openPrice);

   long.level++;
   long.sumLots   = NormalizeDouble(long.sumLots   + lots,   2);
   long.sumProfit = NormalizeDouble(long.sumProfit + profit, 2);
}


/**
 * Fügt den Short-Daten eine weitere Order hinzu.
 *
 * @param  int    ticket
 * @param  double lots
 * @param  double openPrice
 * @param  double profit    - PL: profit + commission + swap
 */
int AddShortOrder(int ticket, double lots, double openPrice, double profit) {
   ArrayPushInt   (short.ticket,    ticket   );
   ArrayPushDouble(short.lots,      lots     );
   ArrayPushDouble(short.openPrice, openPrice);

   short.level++;
   short.sumLots   = NormalizeDouble(short.sumLots   + lots,   2);
   short.sumProfit = NormalizeDouble(short.sumProfit + profit, 2);
}


/**
 *
 */
int ShowStatus() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   string msg;
   msg = StringConcatenate("PSAR Martingale System",                                NL,
                                                                                    NL,
                           "Grid size: "     , GridSize, " pips",                   NL,
                           "Unit size: "     , NumberToStr(UnitSize, ".+"),         NL,
                           "Increment size: ", NumberToStr(IncrementSize, ".+"),    NL,
                           "Profit target: " , DoubleToStr(GridValue(UnitSize), 2), NL,
                           "Trailing stop: " , TrailingStop.Percent, "%",           NL,
                           "Max. drawdown: " , MaxDrawdown.Percent, "%",            NL,
                           "PSAR step: "     , NumberToStr(PSAR.Step, ".1+"),       NL,
                           "PSAR maximum: "  , NumberToStr(PSAR.Maximum, ".1+"),    NL,
                                                                                    NL,
                           "LONG"            ,                                      NL,
                           "Open orders: "   , long.level,                          NL,
                           "Open lots: "     , NumberToStr(long.sumLots, ".1+"),    NL,
                           "Current profit: ", DoubleToStr(long.sumProfit, 2),      NL,
                           "Maximum profit: ", DoubleToStr(long.maxProfit, 2),      NL);
   msg = StringConcatenate(msg,                                                     NL,
                           "SHORT"           ,                                      NL,
                           "Open orders: "   , short.level,                         NL,
                           "Open lots: "     , NumberToStr(short.sumLots, ".1+"),   NL,
                           "Current profit: ", DoubleToStr(short.sumProfit, 2),     NL,
                           "Maximum profit: ", DoubleToStr(short.maxProfit, 2),     NL);

   // 3 Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, NL, msg));

   ShowLines();

   return(catch("ShowStatus()"));
}


/**
 *
 */
int ShowLines() {
   int units, sumUnits;
   double sumOpenPrice, takeProfit, trailingStop;

   if (long.level > 0) {
      sumUnits     = 0;
      sumOpenPrice = 0;
      for (int i=0; i < long.level; i++) {
         units         = Round(long.lots[i] / UnitSize);
         sumUnits     +=  units;
         sumOpenPrice += (units * long.openPrice[i]);
      }
      takeProfit = (sumOpenPrice + GridSize*Pip) / sumUnits;
      HorizontalLine(takeProfit, "line_buy_tp", DodgerBlue, STYLE_SOLID, 2);

      if (long.lockedProfit > 0) {
         trailingStop = (sumOpenPrice + long.lockedProfit/PipValue(UnitSize)*Pip) / sumUnits;
         HorizontalLine(trailingStop, "line_buy_ts", DodgerBlue, STYLE_DASH, 1);
      }
   }

   if (short.level > 0) {
      sumUnits     = 0;
      sumOpenPrice = 0;
      for (i=0; i < short.level; i++) {
         units         =  Round(short.lots[i] / UnitSize);
         sumUnits     +=  units;
         sumOpenPrice += (units * short.openPrice[i]);
      }
      takeProfit = (sumOpenPrice - GridSize*Pip) / sumUnits;
      HorizontalLine(takeProfit, "line_sell_tp", Tomato, STYLE_SOLID, 2);

      if (short.lockedProfit > 0) {
         trailingStop = (sumOpenPrice - short.lockedProfit/PipValue(UnitSize)*Pip) / sumUnits;
         HorizontalLine(trailingStop, "line_sell_ts", Tomato, STYLE_DASH, 1);
      }
   }
   return(catch("ShowLines()"));
}


/**
 *
 */
int HorizontalLine(double value, string name, color lineColor, int style, int thickness) {
   if (ObjectFind(name) == -1) {
      ObjectCreate(name, OBJ_HLINE, 0, Time[0], value);
      ObjectSet   (name, OBJPROP_STYLE, style    );
      ObjectSet   (name, OBJPROP_COLOR, lineColor);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   else {
      ObjectSet   (name, OBJPROP_PRICE1, value);
      ObjectSet   (name, OBJPROP_STYLE, style    );
      ObjectSet   (name, OBJPROP_COLOR, lineColor);
      ObjectSet   (name, OBJPROP_WIDTH, thickness);
   }
   return(catch("HorizontalLine()"));
}


/**
 * Postprocessing-Hook nach Initialisierung
 *
 * @return int - Fehlerstatus
 */
int afterInit() {
   InitStatus();
   CreateStatusBox();
   return(last_error);
}


/**
 * Die Statusbox besteht aus 3 untereinander angeordneten "Quadraten" (Font "Webdings", Zeichen 'g').
 *
 * @return int - Fehlerstatus
 */
int CreateStatusBox() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   int x=0, y[]={33, 148, 187}, fontSize=86;
   color color.Background = C'248,248,248';                          // Chart-Background-Farbe


   // 1. Quadrat
   string label = StringConcatenate(__NAME__, ".statusbox.1");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(1)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x   );
   ObjectSet(label, OBJPROP_YDISTANCE, y[0]);
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);


   // 2. Quadrat
   label = StringConcatenate(__NAME__, ".statusbox.2");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(2)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x   );
   ObjectSet(label, OBJPROP_YDISTANCE, y[1]);
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);


   // 3. Quadrat (überlappt 2.)
   label = StringConcatenate(__NAME__, ".statusbox.3");
   if (ObjectFind(label) != 0) {
      if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
         return(catch("CreateStatusBox(3)"));
      //PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
   ObjectSet(label, OBJPROP_XDISTANCE, x   );
   ObjectSet(label, OBJPROP_YDISTANCE, y[2]);
   ObjectSetText(label, "g", fontSize, "Webdings", color.Background);

   return(catch("CreateStatusBox(4)"));
}
