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
      string symbol = StringConcatenate(ifString(IsTesting(), "_", ""), comment);

      hHst = FindHistory(symbol);
      if (hHst > 0) {
         if (!ResetHistory(hHst))
            return(false);
      }
      else if (__STATUS_ERROR) {
         return(false);
      }
      else {
         hHst = CreateHistory(symbol, ea.name, 2);
         if (hHst <= 0)
            return(false);
      }
   }

   double value = AccountEquity() - AccountCredit();
   return(History.AddTick(hHst, Tick.Time, value, false));
}


// Daten einzelner History-Sets
int    h.hHst       [];                   // History-Handle: Arrayindex, wenn Handle gültig; kleiner/gleich 0, wenn Handle geschlossen/ungültig
int    h.hHst.valid = -1;                 // das zuletzt benutzte gültige Handle (um ein übergebenes Handle nicht ständig neu validieren zu müssen)
string h.symbol     [];                   // Symbol
string h.description[];                   // Symbolbeschreibung
int    h.digits     [];                   // Symboldigits
int    h.hFile      [][9];                // HistoryFile-Handles des Sets je Timeframe
int    h.periods    [] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};


/**
 * Erzeugt für das angegebene Symbol eine neue History und gibt deren Handle zurück. Existiert für das angegebene Symbol bereits eine History,
 * wird sie gelöscht. Offene History-Handles für dasselbe Symbol werden geschlossen.
 *
 * @param  string symbol      - Symbol
 * @param  string description - Beschreibung des Symbols
 * @param  int    digits      - Digits der Datenreihe
 *
 * @return int - History-Handle oder 0, falls ein Fehler auftrat
 */
int CreateHistory(string symbol, string description, int digits) {
   int size = Max(ArraySize(h.hHst), 1);                             // ersten Index überspringen (0 ist kein gültiges Handle)
   h.ResizeArrays(size+1);

   // (1) neuen History-Datensatz erstellen
   h.hHst       [size] = size;
   h.symbol     [size] = symbol;
   h.description[size] = description;
   h.digits     [size] = digits;

   int sizeOfPeriods = ArraySize(h.periods);

   for (int i=0; i < sizeOfPeriods; i++) {
      int hFile = HistoryFile.Open(symbol, description, digits, h.periods[i], FILE_READ|FILE_WRITE);
      if (hFile <= 0)
         return(_ZERO(h.ResizeArrays(size)));                        // interne Arrays auf Ausgangszustand zurücksetzen
      h.hFile[size][i] = hFile;
   }

   // (2) offene History-Handles desselben Symbols schließen
   for (i=size-1; i > 0; i--) {                                      // erstes (immer ungültiges) und letztes (gerade erzeugtes) Handle überspringen
      if (h.symbol[i] == symbol) {
         if (h.hHst[i] > 0)
            h.hHst[i] = -1;
      }
   }

   h.hHst.valid = size;
   return(size);
}


/**
 * Setzt die Größe der internen History-Datenarrays auf den angegebenen Wert.
 *
 * @param  int size - neue Größe
 *
 * @return int - neue Größe der Arrays
 */
/*private*/ int h.ResizeArrays(int size) {
   if (size != ArraySize(h.hHst)) {
      ArrayResize(h.hHst,        size);
      ArrayResize(h.symbol,      size);
      ArrayResize(h.description, size);
      ArrayResize(h.digits,      size);
      ArrayResize(h.hFile,       size);
   }
   return(size);
}


/**
 * Sucht die History des angegebenen Symbols und gibt ein Handle für sie zurück.
 *
 * @param  string symbol - Symbol
 *
 * @return int - History-Handle oder 0, falls keine History gefunden wurde oder ein Fehler auftrat
 */
int FindHistory(string symbol) {
   int size = ArraySize(h.hHst);

   for (int i=size-1; i > 0; i--) {                // Schleife, da es mehrere Handles je Symbol (jedoch nur ein offenes: das letzte) geben kann
      if (h.symbol[i] == symbol) {                 // auf Index 0 kann kein gültiges Handle liegen
         if (h.hHst[i] > 0)
            return(h.hHst[i]);
      }
   }
   return(0);
}


/**
 * Setzt die angegebene History zurück. Alle gespeicherten Kursreihen werden gelöscht.
 *
 * @param  int hHst - History-Handle
 *
 * @return bool - Erfolgsstatus
 */
bool ResetHistory(int hHst) {
   return(!catch("ResetHistory()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Fügt der History eines Symbols einen Tick hinzu. Der Tick wird in allen Timeframes als letzter Tick (Close) der entsprechenden Bars gespeichert.
 *
 * @param  int      hHst       - History-Handle des Symbols; @see GetHistory()
 * @param  datetime time       - Zeitpunkt des Ticks
 * @param  double   value      - Datenwert
 * @param  bool     tickByTick - TRUE:  der Tick wird sofort geschrieben (langsam)
 *                               FALSE: Ticks werden zwischengespeichert und nur beim BarOpen-Event geschrieben (schneller)
 * @return bool - Erfolgsstatus
 */
bool History.AddTick(int hHst, datetime time, double value, bool tickByTick) {
   // Validierung
   if (hHst <= 0)                    return(_false(catch("History.AddTick(1)   invalid parameter hHst = "+ hHst, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (hHst != h.hHst.valid) {
      if (hHst >= ArraySize(h.hHst)) return(_false(catch("History.AddTick(2)   invalid parameter hHst = "+ hHst, ERR_INVALID_FUNCTION_PARAMVALUE)));
      if (h.hHst[hHst] == 0)         return(_false(catch("History.AddTick(3)   invalid parameter hHst = "+ hHst +" (unknown handle)", ERR_INVALID_FUNCTION_PARAMVALUE)));
      if (h.hHst[hHst] <  0)         return(_false(catch("History.AddTick(4)   invalid parameter hHst = "+ hHst +" (closed handle)", ERR_INVALID_FUNCTION_PARAMVALUE)));
      h.hHst.valid = hHst;
   }
   if (time <= 0)                    return(_false(catch("History.AddTick(5)   invalid parameter time = "+ time, ERR_INVALID_FUNCTION_PARAMVALUE)));

   // Dateihandles bis D1 (=> 7) holen und Tick jeweils hinzufügen
   for (int i=0; i < 7; i++) {
      if (!HistoryFile.AddTick(h.hFile[hHst][i], time, value, HST_CACHE_TICKS))
         return(false);
   }
   return(true);
}


/**
 * Unterdrückt unnütze Compilerwarnungen.
 */
void DummyCalls() {
   CreateHistory(NULL, NULL, NULL);
   FindHistory(NULL);
   History.CloseFiles(NULL);
}
