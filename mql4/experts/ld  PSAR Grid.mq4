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


int    long.ticket   [50], short.ticket   [50];                      // Ticket
double long.lots     [50], short.lots     [50];                      // Lots
double long.openPrice[50], short.openPrice[50];                      // OpenPrice
double long.profit   [50], short.profit   [50];                      // floating profit

double long.startEquity,   short.startEquity;
int    long.level,         short.level;
double long.sumLots,       short.sumLots;
double long.sumProfit,     short.sumProfit;
double long.maxProfit,     short.maxProfit;
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
 * NONSENSE: Aktualisiert nichts, liest nur bei jedem Tick alle Orders neu ein.
 */
int UpdateStatus() {
   long.level      = 0;
   long.sumLots    = 0;
   long.sumProfit  = 0;

   short.level     = 0;
   short.sumLots   = 0;
   short.sumProfit = 0;

   ArrayInitialize(long.ticket,     0);
   ArrayInitialize(long.lots,       0);
   ArrayInitialize(long.openPrice,  0);
   ArrayInitialize(long.profit,     0);

   ArrayInitialize(short.ticket,    0);
   ArrayInitialize(short.lots,      0);
   ArrayInitialize(short.openPrice, 0);
   ArrayInitialize(short.profit,    0);

   // we are going to introduce data from opened orders in arrays
   for (int i=0; i < OrdersTotal(); i++) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol()==Symbol()) /*&&*/ if (OrderMagicNumber()==magicNo) {
            if (OrderType() == OP_BUY) {
               long.ticket   [long.level] = OrderTicket();
               long.lots     [long.level] = OrderLots();
               long.openPrice[long.level] = OrderOpenPrice();
               long.profit   [long.level] = OrderProfit() + OrderCommission() + OrderSwap();
               long.sumLots              += OrderLots();
               long.sumProfit            += long.profit[long.level];
               long.level++;
            }
            else if (OrderType() == OP_SELL) {
               short.ticket   [short.level] = OrderTicket();
               short.lots     [short.level] = OrderLots();
               short.openPrice[short.level] = OrderOpenPrice();
               short.profit   [short.level] = OrderProfit() + OrderCommission() + OrderSwap();
               short.sumLots               += OrderLots();
               short.sumProfit             += short.profit[short.level];
               short.level++;
            }
         }
      }
   }
   ArrayResize(long.ticket,     long.level);
   ArrayResize(long.lots,       long.level);
   ArrayResize(long.openPrice,  long.level);
   ArrayResize(long.profit,     long.level);

   ArrayResize(short.ticket,    short.level);
   ArrayResize(short.lots,      short.level);
   ArrayResize(short.openPrice, short.level);
   ArrayResize(short.profit,    short.level);

   SortByTicket();
   return(catch("UpdateStatus()"));
}


/**
 *
 */
int SortByTicket() {
   int    tmpTicket, i1;
   double tmpLots, tmpOpenPrice, tmpProfit;

   // Long
   for (int i=0; i < long.level-1; i++) {
      i1 = 1;
      // we have at least 2 tickets: i1 - erstes Ticket, j2 - zweites Ticket
      for (int j2=i+1; j2 < long.level; j2++) {
         if (long.ticket[i1] > long.ticket[j2]) {
            tmpTicket          = long.ticket   [i1];
            tmpLots            = long.lots     [i1];
            tmpOpenPrice       = long.openPrice[i1];
            tmpProfit          = long.profit   [i1];

            long.ticket   [i1] = long.ticket   [j2];
            long.lots     [i1] = long.lots     [j2];
            long.openPrice[i1] = long.openPrice[j2];
            long.profit   [i1] = long.profit   [j2];

            long.ticket   [j2] = tmpTicket;
            long.lots     [j2] = tmpLots;
            long.openPrice[j2] = tmpOpenPrice;
            long.profit   [j2] = tmpProfit;
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
            tmpProfit           = short.profit   [i1];

            short.ticket   [i1] = short.ticket   [j2];
            short.lots     [i1] = short.lots     [j2];
            short.openPrice[i1] = short.openPrice[j2];
            short.profit   [i1] = short.profit   [j2];

            short.ticket   [j2] = tmpTicket;
            short.lots     [j2] = tmpLots;
            short.openPrice[j2] = tmpOpenPrice;
            short.profit   [j2] = tmpProfit;
         }
      }
   }
   return(catch("SortByTicket()"));
}


/**
 *
 */
int ShowStatus() {
   //if (IsTesting()) /*&&*/ if (!IsVisualMode())
   //   return(NO_ERROR);

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
                           "Maximum profit: ", DoubleToStr(long.maxProfit, 2),      NL,
                           "Locked profit: " , DoubleToStr(long.lockedProfit, 2),   NL);
   msg = StringConcatenate(msg,                                                     NL,
                           "SHORT"           ,                                      NL,
                           "Open orders: "   , short.level,                         NL,
                           "Open lots: "     , NumberToStr(short.sumLots, ".1+"),   NL,
                           "Current profit: ", DoubleToStr(short.sumProfit, 2),     NL,
                           "Maximum profit: ", DoubleToStr(short.maxProfit, 2),     NL,
                           "Locked profit: " , DoubleToStr(short.lockedProfit, 2),  NL);

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
   double psar1 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 1);     // Bar[1] (closed bar)
   double psar2 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 2);     // Bar[2] (previous bar)

   int oeFlags=NULL, /*ORDER_EXECUTION*/oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);
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
      BuyResetAfterClose();
      SellResetAfterClose();
   }
   */


   // ***************************************************************
   // (1) LONG
   // ***************************************************************
   if (long.level == 0) {
      if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {           // PSAR-Crossing von oben nach unten
         long.startEquity = AccountEquity() - AccountCredit();

         ticket = OrderSendEx(Symbol(), OP_BUY, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
      }
   }
   else {
      // (1.1) if we'v reached StopLoss (grid size) and PSAR crossed we send another order
      if (long.sumProfit < -GridValue(long.sumLots)) {
         if (psar2 > Close[2]) /*&&*/ if (Close[1] > psar1) {        // PSAR-Crossing von oben nach unten
            ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(long.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
            if (ticket <= 0)
               return(SetLastError(oe.Error(oe)));
         }
      }

      // (1.2) if we'v reached TakeProfit we activate trailing stop
      if (long.maxProfit==0 && long.sumProfit > GridValue(UnitSize)) {
         long.maxProfit    = long.sumProfit;
         long.lockedProfit = TrailingStop.Percent/100.0 * long.maxProfit;
      }

      // (1.3) we update lockedProfit
      if (long.maxProfit > 0) {
         if (long.sumProfit > long.maxProfit) {
            long.maxProfit    = long.sumProfit;
            long.lockedProfit = TrailingStop.Percent/100.0 * long.sumProfit;
         }
      }

      // (1.4) if lockedProfit is triggered we close the sequence
      if (long.maxProfit > 0) /*&&*/ if (long.lockedProfit > 0) /*&&*/ if (long.maxProfit > long.lockedProfit) /*&&*/ if (long.sumProfit < long.lockedProfit) {
         for (int i=0; i <= long.level-1; i++) {
            if (!OrderCloseEx(long.ticket[i], NULL, NULL, slippage, Blue, oeFlags, oe))
               return(SetLastError(oe.Error(oe)));
         }
         // all tickets are closed
         BuyResetAfterClose();
      }
   }


   // ***************************************************************
   // (2) SHORT
   // ***************************************************************
   if (short.level == 0) {
      if (psar2 < Close[2]) /*&&*/ if (Close[1] < psar1) {           // PSAR-Crossing von unten nach oben
         short.startEquity = AccountEquity() - AccountCredit();

         ticket = OrderSendEx(Symbol(), OP_SELL, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(SetLastError(oe.Error(oe)));
      }
   }
   else {
      // (2.1) if we'v reached StopLoss (grid size) we send another order
      if (short.sumProfit < -GridValue(short.sumLots)) {
         if (short.level < 50 && psar1 > Close[1] && psar2 < Close[2]) {
            ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
            if (ticket <= 0)
               return(SetLastError(oe.Error(oe)));
         }
      }

      // (2.2) if we'v reached TakeProfit we activate trailing stop
      if (short.maxProfit==0 && short.sumProfit > GridValue(UnitSize)) {
         short.maxProfit    = short.sumProfit;
         short.lockedProfit = TrailingStop.Percent/100.0 * short.maxProfit;
      }

      // (2.3) we update lockedProfit
      if (short.maxProfit > 0) {
         if (short.sumProfit > short.maxProfit) {
            short.maxProfit    = short.sumProfit;
            short.lockedProfit = TrailingStop.Percent/100.0 * short.maxProfit;
         }
      }

      // (2.4) if lockedProfit is triggered we close the sequence
      if (short.maxProfit>0 && short.lockedProfit>0 && short.maxProfit>short.lockedProfit && short.sumProfit<short.lockedProfit) {
         for (i=0; i<=short.level-1; i++) {
            if (!OrderCloseEx(short.ticket[i], NULL, NULL, slippage, Red, oeFlags, oe))
               return(SetLastError(oe.Error(oe)));
         }
         // all tickets are closed
         SellResetAfterClose();
      }
   }
   return(catch("Strategy()"));
}


/**
 *
 */
int BuyResetAfterClose() {
   long.maxProfit    = 0;
   long.lockedProfit = 0;
   ObjectDelete("line_buy_tp");
   ObjectDelete("line_buy_ts");

   return(catch("BuyResetAfterClose()"));
}


/**
 *
 */
int SellResetAfterClose() {
   short.maxProfit    = 0;
   short.lockedProfit = 0;
   ObjectDelete("line_sell_tp");
   ObjectDelete("line_sell_ts");

   return(catch("SellResetAfterClose()"));
}


/**
 * Postprocessing-Hook nach Initialisierung
 *
 * @return int - Fehlerstatus
 */
int afterInit() {
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

   int x=0, y[]={33, 148, 210}, fontSize=86;
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
