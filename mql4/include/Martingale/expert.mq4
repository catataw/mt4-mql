/**
 * Martingale Grid EA
 */

#define D_LONG       1                                               // Trade-Directions
#define D_SHORT      2
string  directionDescr[] = {"undefined", "Long", "Short"};


int     long.ticket   [],       short.ticket   [];                   // Ticket
double  long.lots     [],       short.lots     [];                   // Lots
double  long.openPrice[],       short.openPrice[];                   // OpenPrice

int     long.level,             short.level;
double  long.sumLots,           short.sumLots;
double  long.sumOpenPrice,      short.sumOpenPrice;                  // für Breakeven-Berechnung
double  long.breakeven,         short.breakeven;

double  long.startEquity,       short.startEquity;
double  long.profit,            short.profit;
double  long.maxProfit,         short.maxProfit;
//      long.profitTarget,      short.profitTarget;
double  long.profitTargetPrice, short.profitTargetPrice;
double  long.lossTarget,        short.lossTarget;                    // Martingale-Trigger
double  long.lossTargetPrice,   short.lossTargetPrice;
bool    long.takeProfit,        short.takeProfit;                    // ProfitTarget erreicht
double  long.trailingProfit,    short.trailingProfit;

double  profitTarget;                                                // TakeProfit-Trigger (zur Zeit für Long/Short gleich)


/**
 *
 */
int onTick() {
   UpdateStatus();
   Strategy();
   RecordEquity();
   return(last_error);
}


/**
 *
 */
int UpdateStatus() {
   long.profit  = 0;
   short.profit = 0;

   // (1) Long
   for (int i=0; i < long.level; i++) {
      if (!SelectTicket(long.ticket[i], "UpdateStatus(1)"))
         return(last_error);
      long.profit = NormalizeDouble(long.profit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   long.maxProfit = MathMax(long.maxProfit, long.profit);

   if (long.maxProfit >= profitTarget)  {
      long.takeProfit     = true;
      long.trailingProfit = NormalizeDouble(TrailingStop.Percent/100.0 * long.maxProfit, Digits);
   }

   // (2) Short
   for (i=0; i < short.level; i++) {
      if (!SelectTicket(short.ticket[i], "UpdateStatus(2)"))
         return(last_error);
      short.profit = NormalizeDouble(short.profit + OrderProfit() + OrderCommission() + OrderSwap(), 2);
   }
   short.maxProfit = MathMax(short.maxProfit, short.profit);

   if (short.maxProfit >= profitTarget) {
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
double ProfitTarget() {
   return(NormalizeDouble(GridSize * PipValue(StartLotSize), 2));
}


/**
 *
 */
double LossTarget(int direction) {
   if (direction == D_LONG ) return(NormalizeDouble(-GridSize * PipValue(long.sumLots ), 2));
   if (direction == D_SHORT) return(NormalizeDouble(-GridSize * PipValue(short.sumLots), 2));

   return(_NULL(catch("LossTarget()   illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * - willkürliche Formel: keine Berücksichtigung der Relationen StartLotSize/IncrementSize und Loss/Level
 * - entsprechend willkürliche Exponentialfunktion
 * - entsprechend unvermeidbarer Martingale-Tod
 */
double MartingaleVolume(double loss) {
   loss = MathAbs(loss);
   int multiplier = loss / profitTarget;                             // minimale Martingale-Reduktion durch systematisches Abrunden
   return(multiplier * IncrementSize);                               // Es scheint so, als mußte es irgendwie ein Vielfaches von irgendwas sein.
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
   long.sumLots           = NormalizeDouble(long.sumLots + lots, 2);
   long.sumOpenPrice     += lots * openPrice;
   long.breakeven         = long.sumOpenPrice / long.sumLots;
   long.profit            = NormalizeDouble(long.profit + profit, 2);
   long.profitTargetPrice = long.breakeven + StartLotSize/long.sumLots * GridSize*Pips;
   long.lossTarget        = LossTarget(D_LONG);
   long.lossTargetPrice   = long.breakeven - GridSize*Pips;
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
   short.sumLots           = NormalizeDouble(short.sumLots + lots, 2);
   short.sumOpenPrice     += lots * openPrice;
   short.breakeven         = short.sumOpenPrice / short.sumLots;
   short.profit            = NormalizeDouble(short.profit + profit, 2);
   short.profitTargetPrice = short.breakeven - StartLotSize/short.sumLots * GridSize*Pips;
   short.lossTarget        = LossTarget(D_SHORT);
   short.lossTargetPrice   = short.breakeven + GridSize*Pips;
   return(last_error);
}


/**
 *
 */
int ResetLongStatus() {
   ArrayResize(long.ticket,    0);
   ArrayResize(long.lots,      0);
   ArrayResize(long.openPrice, 0);

   long.level             = 0;
   long.sumLots           = 0;
   long.sumOpenPrice      = 0;
   long.breakeven         = 0;

   long.startEquity       = 0;
   long.profit            = 0;
   long.maxProfit         = 0;
   long.profitTargetPrice = 0;
   long.lossTarget        = 0;
   long.lossTargetPrice   = 0;
   long.takeProfit        = false;
   long.trailingProfit    = 0;
   return(NO_ERROR);
}


/**
 *
 */
int ResetShortStatus() {
   ArrayResize(short.ticket,    0);
   ArrayResize(short.lots,      0);
   ArrayResize(short.openPrice, 0);

   short.level             = 0;
   short.sumLots           = 0;
   short.sumOpenPrice      = 0;
   short.breakeven         = 0;

   short.startEquity       = 0;
   short.profit            = 0;
   short.maxProfit         = 0;
   short.profitTargetPrice = 0;
   short.lossTarget        = 0;
   short.lossTargetPrice   = 0;
   short.takeProfit        = false;
   short.trailingProfit    = 0;
   return(NO_ERROR);
}


/**
 * Die Statusbox besteht aus untereinander angeordneten Quadraten (Font "Webdings", Zeichen 'g').
 *
 * @return bool - Erfolgsstatus
 */
bool CreateStatusBox() {
   if (!IsChart)
      return(false);

   int x=0, y[]={32, 142}, fontSize=83, rectangels=ArraySize(y);
   color  bgColor = C'248,248,248';                                  // entspricht Chart-Background
   string label;

   for (int i=0; i < rectangels; i++) {
      label = StringConcatenate(__NAME__, ".statusbox."+ (i+1));
      if (ObjectFind(label) != 0) {
         if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
            return(_false(catch("CreateStatusBox(1)")));
         PushChartObject(label);
      }
      ObjectSet(label, OBJPROP_CORNER, CORNER_TOP_LEFT);
      ObjectSet(label, OBJPROP_XDISTANCE, x   );
      ObjectSet(label, OBJPROP_YDISTANCE, y[i]);
      ObjectSetText(label, "g", fontSize, "Webdings", bgColor);
   }
   return(!catch("CreateStatusBox(2)"));
}


/**
 *
 */
int ShowStatus() {
   if (!IsChart)
      return(NO_ERROR);

   static bool statusBox;
   if (!statusBox)
      statusBox = CreateStatusBox(/*lines*/);      // TODO: Zeilenanzahl der Statusbox bei Änderung dynamisch anpassen


   string msg = StringConcatenate(ea.name,                                                   NL,
                                                                                             NL,
                                  "Grid size: "         , GridSize, " pips",                 NL,
                                  "Start lot size: "    , NumberToStr(StartLotSize, ".+"),   NL,
                                  "Increment lot size: ", NumberToStr(IncrementSize, ".+"),  NL,
                                  "Profit target: "     , DoubleToStr(profitTarget, 2),      NL,
                                  "Trailing stop: "     , TrailingStop.Percent, "%",         NL,
                                  "Max. drawdown: "     , MaxDrawdown.Percent, "%",          NL,
                                                                                             NL,
                                  "LONG: "              , long.level,                        NL,
                                  "Open lots: "         , NumberToStr(long.sumLots, ".1+"),  NL,
                                  "Profit: "            , DoubleToStr(long.profit, 2),       NL,
                                  "Max. profit: "       , DoubleToStr(long.maxProfit, 2),    NL,
                                                                                             NL,
                                  "SHORT: "             , short.level,                       NL,
                                  "Open lots: "         , NumberToStr(short.sumLots, ".1+"), NL,
                                  "Profit: "            , DoubleToStr(short.profit, 2),      NL,
                                  "Max. profit: "       , DoubleToStr(short.maxProfit, 2),   NL);

   // 3 Zeilen Abstand nach oben für Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, NL, msg));

   ShowTargets();
   return(catch("ShowStatus()"));
}


/**
 * Aufruf nur aus ShowStatus()
 */
int ShowTargets() {
   static int last.long.level=-1, last.short.level=-1;

   if (long.level != last.long.level) {
      if (long.level == 0)  ObjectDeleteSilent(__NAME__ +".ProfitTarget.long", "ShowTargets(1)");
      else                  HorizontalLine    (__NAME__ +".ProfitTarget.long", long.profitTargetPrice, DodgerBlue, STYLE_SOLID, 1);
      last.long.level = long.level;
   }
   if (short.level != last.short.level) {
      if (short.level == 0) ObjectDeleteSilent(__NAME__ +".ProfitTarget.short", "ShowTargets(2)");
      else                  HorizontalLine    (__NAME__ +".ProfitTarget.short", short.profitTargetPrice, Tomato, STYLE_SOLID, 1);
      last.short.level = short.level;
   }
   return(catch("ShowTargets(3)"));
}


/**
 * Aufruf nur aus ShowTargets()
 */
int HorizontalLine(string label, double value, color lineColor, int style, int thickness) {
   if (ObjectFind(label) != 0) {
      ObjectCreate(label, OBJ_HLINE, 0, Time[0], value);
      PushChartObject(label);
   }
   ObjectSet(label, OBJPROP_PRICE1, value    );
   ObjectSet(label, OBJPROP_STYLE , style    );
   ObjectSet(label, OBJPROP_COLOR , lineColor);
   ObjectSet(label, OBJPROP_WIDTH , thickness);
   ObjectSet(label, OBJPROP_BACK  , true     );
   return(catch("HorizontalLine()"));
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
 * Postprocessing-Hook nach Initialisierung
 *
 * @return int - Fehlerstatus
 */
int afterInit() {
   InitStatus();
   profitTarget = ProfitTarget();
   return(last_error);
}


/**
 * Postprocessing-Hook nach Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int afterDeinit() {
   History.CloseFiles(false);
   return(NO_ERROR);
}


/**
 * Zeichnet die Equity-Kurve des Tests auf.
 *
 * @return bool - Erfolgsstatus
 */
bool RecordEquity() {
   if (__STATUS_ERROR) return(false);
   if (!IsTesting())   return( true);

   static int hHst;
   if (!hHst) {
      hHst = GetHistory(NULL, NULL, NULL);
      if (hHst <= 0) {
         hHst = 0;
         return(false);
      }
   }
   return(WriteHistory(hHst, Tick.Time, AccountEquity()-AccountCredit(), false));
}


/**
 * Gibt ein Handle für die History des angegebenen Symbols zurück. Über das Handle kann das gesamte FileSet der History des Symbols
 * angesprochen werden.
 *
 * @param  string symbol      - Symbol
 * @param  string description - Beschreibung des Symbols (falls die History neu erstellt wird)
 * @param  int    digits      - Digits der Datenreihe    (falls die History neu erstellt wird)
 *
 * @return int - History-Handle oder 0, falls ein Fehler auftrat
 */
int GetHistory(string symbol, string description, int digits) {
   return(1);
}


/**
 * Schreibt einen Datenwert in die History.
 *
 * @param  int      hHst       - History-Handle, wie von GetHistory() zurückgegeben
 * @param  datetime tickTime   - Zeitpunkt des zu schreibenden Datenwertes
 * @param  double   tickValue  - zu schreibender Datenwert
 * @param  bool     tickByTick - TRUE:  jeder einzelne Datenwert wird sofort geschrieben
 *                               FALSE: nur komplette Bars werden geschrieben (Werte einer Bar werden zwischengespeichert)
 * @return bool - Erfolgsstatus
 */
bool WriteHistory(int hHst, datetime tickTime, double tickValue, bool tickByTick) {
   int timeframe=PERIOD_H1, timeframeSecs=timeframe*MINUTES;


   // (1) Filehandle holen
   static int hFile, hFileM1, hFileM5, hFileM15, hFileM30, hFileH1, hFileH4, hFileD1, digits=2;
   if (!hFile) {
      string symbol      = StringConcatenate(ifString(IsTesting(), "_", ""), comment);
      string description = ea.name;
      hFile = History.OpenFile(symbol, description, digits, timeframe, FILE_READ|FILE_WRITE);
      if (hFile <= 0)
         return(false);
   }


   static datetime barTime, nextBarTime;                                         // Timestamp der Zwischenspeicher- und der darauf folgenden Bar
   int    offset, iNulls[1];
   bool   barExists[1];
   double data[5];


   // (2) Ticks zwischenspeichern, nur komplette Bars schreiben
   if (!tickByTick) {
      if (tickTime >= nextBarTime) {
         offset = History.FindBar(hFile, tickTime, barExists);                   // bei bereits gespeicherten Ticks (nextBarTime != 0) immer 1 zu klein, da die ungeschriebene
         if (offset < 0)                                                         // Bar für FindBar() noch nicht sichtbar ist
            return(_false(SetLastError(hstlib_GetLastError())));

         if (!nextBarTime) {
            if (barExists[0]) {                                                  // erste Initialisierung
               if (!History.ReadBar(hFile, offset, iNulls, data))                // ggf. vorhandene Bar einlesen (von vorherigem Abbruch)
                  return(false);
             //data[BAR_O] = ...                                                 // unverändert
               data[BAR_H] = MathMax(data[BAR_H], tickValue);
               data[BAR_L] = MathMin(data[BAR_L], tickValue);
               data[BAR_C] = tickValue;
               data[BAR_V]++;
            }
            else {
               data[BAR_O] = tickValue;
               data[BAR_H] = tickValue;
               data[BAR_L] = tickValue;
               data[BAR_C] = tickValue;
               data[BAR_V] = 1;
            }
         }
         else {                                                                  // letzte Bar komplett, muß nach 'offset' geschrieben werden (nicht offset-1),
            if (!History.WriteBar(hFile, offset, barTime, data, HST_FILL_GAPS))  // da die ungeschriebene Bar für FindBar() noch nicht sichtbar ist
               return(false);
            data[BAR_O] = tickValue;                                             // Re-Initialisierung
            data[BAR_H] = tickValue;
            data[BAR_L] = tickValue;
            data[BAR_C] = tickValue;
            data[BAR_V] = 1;
         }
         barTime     = tickTime - tickTime%timeframeSecs;
         nextBarTime = barTime + timeframeSecs;
      }
      else {
       //data[BAR_O] = ...                                                       // unverändert
         data[BAR_H] = MathMax(data[BAR_H], tickValue);
         data[BAR_L] = MathMin(data[BAR_L], tickValue);
         data[BAR_C] = tickValue;
         data[BAR_V]++;
      }
      return(true);
   }


   // (3) falls keine zwischengespeicherten Ticks vorhanden sind, nur den aktuellen Tick schreiben
   if (!barTime)
      return(History.AddTick(hFile, tickTime, tickValue, NULL));


   // (4) barTime und nextBarTime sind gesetzt: zwischengespeicherte und aktuellen Tick schreiben
   offset = History.FindBar(hFile, barTime, barExists);
   if (offset < 0)
      return(_false(SetLastError(hstlib_GetLastError())));

   if (tickTime < nextBarTime) {                                                 // aktueller Tick gehört zur zwischengespeicherten Bar und wird in sie integriert
    //data[BAR_O] = ...                                                          // Open unverändert
      data[BAR_H] = MathMax(data[BAR_H], tickValue);
      data[BAR_L] = MathMin(data[BAR_L], tickValue);
      data[BAR_C] = tickValue;
      data[BAR_V]++;
      if (!History.WriteBar(hFile, offset, barTime, data, HST_FILL_GAPS))        // beide werden zusammen geschrieben
         return(false);
   }
   else {
      if (!History.WriteBar(hFile, offset, barTime, data, HST_FILL_GAPS))        // beide werden getrennt geschrieben
         return(false);
      if (!History.AddTick(hFile, tickTime, tickValue, NULL))
         return(false);
   }

   barTime     = 0;                                                              // writeEveryTick ist TRUE: für möglichen Wechsel immer zurücksetzen
   nextBarTime = 0;
   return(true);                                                                 // TODO: writeEveryTick läßt sich beschleunigen, wenn beide Werte nicht zurückgesetzt werden
}
