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
double long.profit   [50], short.profit   [50];                      // floating Profit

double long.startEquity,   short.startEquity;
int    long.level,         short.level;
double long.sumLots,       short.sumLots;
double long.sumProfit,     short.sumProfit;
double long.maxProfit,     short.maxProfit;
double long.lockedProfit,  short.lockedProfit;

int    magicNo  = 110412;
double slippage = 0.1;                                               // order slippage
string comment  = "ld04 PSAR";                                       // order comment


/**
 *
 */
int onTick() {
   UpdateStatus();
   ShowStatus();
   Robot();
   return(catch("onTick()"));
}


/**
 *
 */
void BuyResetAfterClose() {
   long.maxProfit    = 0;
   long.lockedProfit = 0;
   ObjectDelete("line_buy_tp");
   ObjectDelete("line_buy_ts");

   catch("BuyResetAfterClose()");
}


/**
 *
 */
void SellResetAfterClose() {
   short.maxProfit    = 0;
   short.lockedProfit = 0;
   ObjectDelete("line_sell_tp");
   ObjectDelete("line_sell_ts");

   catch("SellResetAfterClose()");
}


/**
 *
 */
void UpdateStatus() {
   // reset vars
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
   SortByLots();
   catch("UpdateStatus()");
}


/**
 *
 */
void SortByLots() {
   int    iTmp;
   double dTmp;

   // We are going to sort orders by volume
   // m[0] smallest volume m[size-1] largest volume

   // BUY ORDERS
   for (int i=0; i < long.level-1; i++) {
      // at least 2 orders
      for (int j=i+1; j < long.level; j++) {
         if (long.lots[j] < long.lots[i]) {
            // ...lots
            dTmp              = long.lots[i];
            long.lots[i]      = long.lots[j];
            long.lots[j]      = dTmp;
            // ...tickets
            iTmp              = long.ticket[i];
            long.ticket[i]    = long.ticket[j];
            long.ticket[j]    = iTmp;
            // ...profits
            dTmp              = long.profit[i];
            long.profit[i]    = long.profit[j];
            long.profit[j]    = dTmp;
            // ...open price
            dTmp              = long.openPrice[i];
            long.openPrice[i] = long.openPrice[j];
            long.openPrice[j] = dTmp;
         }
      }
   }

   // SELL ORDERS
   for (i=0; i < short.level-1; i++) {
      // at least 2 orders
      for (j=i+1; j < short.level; j++) {
         if (short.lots[j] < short.lots[i]) {
            // ...lots
            dTmp               = short.lots[i];
            short.lots[i]      = short.lots[j];
            short.lots[j]      = dTmp;
            // ...tickets
            iTmp               = short.ticket[i];
            short.ticket[i]    = short.ticket[j];
            short.ticket[j]    = iTmp;
            // ...profits
            dTmp               = short.profit[i];
            short.profit[i]    = short.profit[j];
            short.profit[j]    = dTmp;
            // ...open price
            dTmp               = short.openPrice[i];
            short.openPrice[i] = short.openPrice[j];
            short.openPrice[j] = dTmp;
         }
      }
   }
   catch("SortByLots()");
}


/**
 *
 */
void ShowLines() {
   int units, sumUnits;
   double sumOpenPrice, takeProfit, trailingStop;

   if (long.level > 0) {
      sumUnits     = 0;
      sumOpenPrice = 0;
      for (int i=0; i<long.level; i++) {
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
      for (i=0; i<short.level; i++) {
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
   catch("ShowLines()");
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
void HorizontalLine(double value, string name, color lineColor, int style, int thickness) {
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
   catch("HorizontalLine()");
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
void Robot() {
   double psar1 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 1);     // Bar 1 (closed bar)
   double psar2 = iSAR(Symbol(), 0, PSAR.Step, PSAR.Maximum, 2);     // Bar 2 (previous bar)

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

   // **************************************************
   // BUYS == 0
   // **************************************************
   if (long.level == 0) {
      if (psar1 < Close[1]) /*&&*/ if (psar2 > Close[2]) {
         ticket = OrderSendEx(Symbol(), OP_BUY, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
         if (ticket <= 0)
            return(_NULL(SetLastError(oe.Error(oe))));
         long.startEquity = AccountEquity() - AccountCredit();
      }
   }

   // **************************************************
   // BUYS > 0
   // **************************************************
   if (long.level > 0) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (long.sumProfit < -GridValue(long.sumLots)) {
         if (long.level < 50 && psar1 < Close[1] && psar2 > Close[2]) {
            ticket = OrderSendEx(Symbol(), OP_BUY, MartingaleVolume(long.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Blue, oeFlags, oe);
            if (ticket <= 0)
               return(_NULL(SetLastError(oe.Error(oe))));
         }
      }

      // CASE 2.1 >>> We reach TakeProfit so we activate trailing stop
      if (long.maxProfit==0 && long.sumProfit > GridValue(UnitSize)) {
         long.maxProfit    = long.sumProfit;
         long.lockedProfit = TrailingStop.Percent/100.0 * long.maxProfit;
      }

      // CASE 2.2 >>> lockedProfit is updated in real time
      if (long.maxProfit > 0) {
         if (long.sumProfit > long.maxProfit) {
            long.maxProfit    = long.sumProfit;
            long.lockedProfit = TrailingStop.Percent/100.0 * long.sumProfit;
         }
      }

      // CASE 2.3 >>> If profit falls below lockedProfit we close all positions
      if (long.maxProfit>0 && long.lockedProfit>0 && long.maxProfit>long.lockedProfit && long.sumProfit<long.lockedProfit) {
         for (int i=0; i<=long.level-1; i++) {
            if (!OrderCloseEx(long.ticket[i], NULL, NULL, slippage, Blue, oeFlags, oe))
               return(_NULL(SetLastError(oe.Error(oe))));
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateStatus() on next start() execution
         BuyResetAfterClose();
      }
   }

   // **************************************************
   // SELLS == 0
   // **************************************************
   if (short.level == 0) {
      if (psar1 > Close[1]) /*&&*/ if (psar2 < Close[2]) {
         ticket = OrderSendEx(Symbol(), OP_SELL, UnitSize, NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
         if (ticket <= 0)
            return(_NULL(SetLastError(oe.Error(oe))));
         short.startEquity = AccountEquity() - AccountCredit();
      }
   }

   // **************************************************
   // SELLS > 0
   // **************************************************
   if (short.level > 0) {
      // CASE 1 >>> We reach Stop Loss (grid size)
      if (short.sumProfit < -GridValue(short.sumLots)) {
         if (short.level < 50 && psar1 > Close[1] && psar2 < Close[2]) {
            ticket = OrderSendEx(Symbol(), OP_SELL, MartingaleVolume(short.sumProfit), NULL, slippage, 0, 0, comment, magicNo, 0, Red, oeFlags, oe);
            if (ticket <= 0)
               return(_NULL(SetLastError(oe.Error(oe))));
         }
      }

      // CASE 2.1 >>> We reach TakeProfit so we activate trailing stop
      if (short.maxProfit==0 && short.sumProfit > GridValue(UnitSize)) {
         short.maxProfit    = short.sumProfit;
         short.lockedProfit = TrailingStop.Percent/100.0 * short.maxProfit;
      }

      // CASE 2.2 >>> lockedProfit is updated in real time
      if (short.maxProfit > 0) {
         if (short.sumProfit > short.maxProfit) {
            short.maxProfit    = short.sumProfit;
            short.lockedProfit = TrailingStop.Percent/100.0 * short.maxProfit;
         }
      }

      // CASE 2.3 >>> If profit falls below lockedProfit we close all positions
      if (short.maxProfit>0 && short.lockedProfit>0 && short.maxProfit>short.lockedProfit && short.sumProfit<short.lockedProfit) {
         for (i=0; i<=short.level-1; i++) {
            if (!OrderCloseEx(short.ticket[i], NULL, NULL, slippage, Red, oeFlags, oe))
               return(_NULL(SetLastError(oe.Error(oe))));
         }
         // At this point all orders are closed. Global vars will be updated thanks to UpdateStatus() on next start() execution
         SellResetAfterClose();
      }
   }
   catch("Robot()");
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
