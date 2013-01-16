/**
 * Martingale Grid EA
 */

#define D_LONG       1                                               // Trade-Directions
#define D_SHORT      2
string  directionDescr[] = {"undefined", "Long", "Short"};


int     long.ticket   [],    short.ticket   [];                      // Ticket
double  long.lots     [],    short.lots     [];                      // Lots
double  long.openPrice[],    short.openPrice[];                      // OpenPrice

double  long.startEquity,    short.startEquity;
int     long.level,          short.level;
double  long.sumLots,        short.sumLots;
double  long.sumOpenPrice,   short.sumOpenPrice;                     // für avgOpenPrice-Berechnung
double  long.avgOpenPrice,   short.avgOpenPrice;
double  long.sumProfit,      short.sumProfit;
double  long.maxProfit,      short.maxProfit;
bool    long.takeProfit,     short.takeProfit;
double  long.trailingProfit, short.trailingProfit;
double  long.targetLoss,     short.targetLoss;                       // Martingale-Trigger

double  targetProfit;                                                // TakeProfit-Trigger (Long/Short im Moment noch identisch)


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
      long.sumProfit = NormalizeDouble(long.sumProfit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   long.maxProfit = MathMax(long.maxProfit, long.sumProfit);

   if (GE(long.maxProfit, targetProfit))  {
      long.takeProfit     = true;
      long.trailingProfit = NormalizeDouble(TrailingStop.Percent/100.0 * long.maxProfit, Digits);
   }

   // (2) Short
   for (i=0; i < short.level; i++) {
      if (!SelectTicket(short.ticket[i], "UpdateStatus(2)"))
         return(last_error);
      short.sumProfit = NormalizeDouble(short.sumProfit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   short.maxProfit = MathMax(short.maxProfit, short.sumProfit);

   if (GE(short.maxProfit, targetProfit)) {
      short.takeProfit     = true;
      short.trailingProfit = NormalizeDouble(TrailingStop.Percent/100.0 * short.maxProfit, Digits);
   }
   return(catch("UpdateStatus(3)"));
}


/**
 *
 */
int Strategy() {
   /*
   // Drawdown control
   if ((100-MaxDrawdown.Percent)/100 * AccountBalance() > AccountEquity()-AccountCredit()) {
      int oeFlags=NULL, /*ORDER_EXECUTION*oes[][ORDER_EXECUTION.intSize];

      if (long.level != 0) {
         if (!OrderMultiClose(long.ticket, 0.1, Blue, oeFlags, oes))
            return(SetLastError(oes.Error(oes, 0)));
         ResetLongStatus();
      }
      if (short.level != 0) {
         if (!OrderMultiClose(short.ticket, 0.1, Red, oeFlags, oes))
            return(SetLastError(oes.Error(oes, 0)));
         ResetShortStatus();
      }
   }
   */
   Strategy.Long();
   Strategy.Short();
   return(last_error);
}


/**
 *
 */
double TargetProfit() {
   return(NormalizeDouble(GridSize * PipValue(StartLotSize), 2));
}


/**
 *
 */
double TargetLoss(int direction) {
   if (direction == D_LONG ) return(NormalizeDouble(-GridSize * PipValue(long.sumLots ), 2));
   if (direction == D_SHORT) return(NormalizeDouble(-GridSize * PipValue(short.sumLots), 2));

   return(_NULL(catch("TargetLoss()   illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * - willkürliche Formel: keine Berücksichtigung der Relationen StartLotSize/IncrementSize und Loss/Level
 * - entsprechend willkürliche Exponentialfunktion
 * - entsprechend unvermeidbarer Martingale-Tod
 */
double MartingaleVolume(double loss) {
   loss = MathAbs(loss);
   int multiplier = loss / targetProfit;                    // minimale Martingale-Reduktion durch systematisches Abrunden
   return(multiplier * IncrementSize);                      // Es scheint so, als mußte es irgendwie ein Vielfaches von irgendwas sein.
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
   long.sumLots       = NormalizeDouble(long.sumLots   + lots,   2);
   long.sumProfit     = NormalizeDouble(long.sumProfit + profit, 2);
   long.sumOpenPrice += lots * openPrice;
   long.avgOpenPrice  = long.sumOpenPrice / long.sumLots;
   long.targetLoss    = TargetLoss(D_LONG);
   return(last_error);
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
   short.sumLots       = NormalizeDouble(short.sumLots   + lots,   2);
   short.sumProfit     = NormalizeDouble(short.sumProfit + profit, 2);
   short.sumOpenPrice += lots * openPrice;
   short.avgOpenPrice  = short.sumOpenPrice / short.sumLots;
   short.targetLoss    = TargetLoss(D_SHORT);
   return(last_error);
}


/**
 *
 */
int ResetLongStatus() {
   ArrayResize(long.ticket,    0);
   ArrayResize(long.lots,      0);
   ArrayResize(long.openPrice, 0);

   long.startEquity    = 0;
   long.level          = 0;
   long.sumLots        = 0;
   long.sumOpenPrice   = 0;
   long.avgOpenPrice   = 0;
   long.sumProfit      = 0;
   long.maxProfit      = 0;
   long.takeProfit     = false;
   long.trailingProfit = 0;
   long.targetLoss     = 0;

   if (!IsTesting() || IsVisualMode()) {
      ObjectDelete(__NAME__ +".ProfitTarget.long");

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

   short.startEquity    = 0;
   short.level          = 0;
   short.sumLots        = 0;
   short.sumOpenPrice   = 0;
   short.avgOpenPrice   = 0;
   short.sumProfit      = 0;
   short.maxProfit      = 0;
   short.takeProfit     = false;
   short.trailingProfit = 0;
   short.targetLoss     = 0;

   if (!IsTesting() || IsVisualMode()) {
      ObjectDelete(__NAME__ +".ProfitTarget.short");

      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)
         return(catch("ResetLongStatus()", error));
   }
   return(NO_ERROR);
}


/**
 *
 */
int ShowStatus() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   string msg = StringConcatenate(ea.name,                                                   NL,
                                                                                             NL,
                                  "Grid size: "         , GridSize, " pips",                 NL,
                                  "Start lot size: "    , NumberToStr(StartLotSize, ".+"),   NL,
                                  "Increment lot size: ", NumberToStr(IncrementSize, ".+"),  NL,
                                  "Target profit: "     , DoubleToStr(targetProfit, 2),      NL,
                                  "Trailing stop: "     , TrailingStop.Percent, "%",         NL,
                                  "Max. drawdown: "     , MaxDrawdown.Percent, "%",          NL,
                                                                                             NL,
                                  "LONG: "              , long.level,                        NL,
                                  "Open lots: "         , NumberToStr(long.sumLots, ".1+"),  NL,
                                  "Current profit: "    , DoubleToStr(long.sumProfit, 2),    NL,
                                  "Max. profit: "       , DoubleToStr(long.maxProfit, 2),    NL,
                                                                                             NL,
                                  "SHORT: "             , short.level,                       NL,
                                  "Open lots: "         , NumberToStr(short.sumLots, ".1+"), NL,
                                  "Current profit: "    , DoubleToStr(short.sumProfit, 2),   NL,
                                  "Max. profit: "       , DoubleToStr(short.maxProfit, 2),   NL);

   // 3 Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, NL, msg));

   ShowTargets();
   return(catch("ShowStatus()"));
}


/**
 *
 */
int ShowTargets() {
   double distance, price;

   if (long.level > 0) {
      distance = GridSize * StartLotSize / long.sumLots;
      price    = NormalizeDouble(long.avgOpenPrice + distance*Pips, Digits);
      HorizontalLine(__NAME__ +".ProfitTarget.long", price, DodgerBlue, STYLE_SOLID, 1);
   }

   if (short.level > 0) {
      distance = GridSize * StartLotSize / short.sumLots;
      price    = NormalizeDouble(short.avgOpenPrice - distance*Pips, Digits);
      HorizontalLine(__NAME__ +".ProfitTarget.short", price, Tomato, STYLE_SOLID, 1);
   }
   return(catch("ShowTargets()"));
}


/**
 *
 */
int HorizontalLine(string label, double value, color lineColor, int style, int thickness) {
   if (ObjectFind(label) != 0)
      ObjectCreate(label, OBJ_HLINE, 0, Time[0], value);

   ObjectSet(label, OBJPROP_PRICE1, value    );
   ObjectSet(label, OBJPROP_STYLE , style    );
   ObjectSet(label, OBJPROP_COLOR , lineColor);
   ObjectSet(label, OBJPROP_WIDTH , thickness);
   ObjectSet(label, OBJPROP_BACK  , true     );
   return(catch("HorizontalLine()"));
}


/**
 * Die Statusbox besteht aus untereinander angeordneten Quadraten (Font "Webdings", Zeichen 'g').
 *
 * @return int - Fehlerstatus
 */
int CreateStatusBox() {
   if (IsTesting()) /*&&*/ if (!IsVisualMode())
      return(NO_ERROR);

   int x=0, y[]={32, 142}, fontSize=83, rectangels=ArraySize(y);
   color  bgColor = C'248,248,248';                                  // entspricht Chart-Background
   string label;

   for (int i=0; i < rectangels; i++) {
      label = StringConcatenate(__NAME__, ".statusbox."+ (i+1));
      if (ObjectFind(label) != 0) {
         if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
            return(catch("CreateStatusBox(1)"));
         PushChartObject(label);
      }
      ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
      ObjectSet(label, OBJPROP_XDISTANCE, x   );
      ObjectSet(label, OBJPROP_YDISTANCE, y[i]);
      ObjectSetText(label, "g", fontSize, "Webdings", bgColor);
   }
   return(catch("CreateStatusBox(2)"));
}


/**
 * Postprocessing-Hook nach Initialisierung
 *
 * @return int - Fehlerstatus
 */
int afterInit() {
   InitStatus();
   CreateStatusBox();
   targetProfit = TargetProfit();
   return(last_error);
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
