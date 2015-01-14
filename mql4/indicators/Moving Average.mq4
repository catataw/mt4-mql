/**
 * Multi-Color/Multi-Timeframe Moving Average
 *
 *
 * Unterst�tzte MA-Typen:
 *  � SMA  - Simple Moving Average:          Gewichtung aller Bars gleich
 *  � LWMA - Linear Weighted Moving Average: Gewichtung der Bars nach linearer Funktion
 *  � EMA  - Exponential Moving Average:     Gewichtung der Bars nach Exponentialfunktion
 *  � ALMA - Arnaud Legoux Moving Average:   Gewichtung der Bars nach konfigurierbarer Gau�scher Verteilungsfunktion
 *
 * Nicht mehr unterst�tzte MA-Typen:
 *  � SMMA - Smoothed Moving Average:        ist ein EMA anderer Periode (Relikt aus den 70'ern, neue Bars lassen sich schneller als mit EMA berechnen)
 *  � TMA  - Triangular Moving Average:      doppelter SMA(SMA(n)), also verdoppelte Response-Zeit und verdoppeltes Lag
 *
 * Der Timeframe des Indikators kann zur Verbesserung der Lesbarkeit mit einem Synonym konfiguriert werden, z.B.:
 *  � die Konfiguration "3 x D1=>H1"  ist gleichbedeutend mit "72 x H1"
 *  � die Konfiguration "2 x D1=>M15" ist gleichbedeutend mit "192 x M15"
 *
 * Ist der Timeframe des Indikators mit einem Synonym konfiguriert, kann f�r die Periodenl�nge ein gebrochener Wert angegeben werden, wenn die
 * Periodenl�nge nach Aufl�sung des Timeframe-Synonyms einen g�ltigen ganzzahligen Wert darstellt, z.B.:
 *  � die Konfiguration "1.5 x D1=>H1"  ist gleichbedeutend mit "36 x H1"
 *  � die Konfiguration "0.5 x D1=>M15" ist gleichbedeutend mit "48 x M15"
 *
 * Ist ein Timeframe konfiguriert, wird beim Umschalten des Chart-Timeframes die Indikatorkonfiguration NICHT auf die aktuelle Chartperiode umgerechnet.
 * Zur Berechnung wird immer die urspr�nglich konfigurierte Datenreihe verwendet, der Indikator zeigt in allen Chartaufl�sungen exakt dieselben Werte an.
 *
 * Sind die Hotkeys zur �nderung der Indikatorperiode f�r mehr als einen Indikator des aktuellen Charts aktiviert, empf�ngt nur der erste f�r diese Hotkeys
 * konfigurierte Indikator die entsprechenden Commands (in der Reihenfolge des "Indicators List" Window).
 *
 * Im Buffer MovingAverage.MODE_MA stehen die Werte des Moving Average und im Buffer MovingAverage.MODE_TREND Trendrichtung und Trendl�nge der jeweiligen Bar
 * zur Verf�gung (Werte: +1...+n f�r Aufw�rtstrends bzw. -1...-n f�r Abw�rtstrends). Der Absolutwert des Trends einer Bar weniger 1 ist die Distanz dieser Bar
 * vom letzten davor aufgetretenen Trendreversal.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

//////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////

extern string MA.Periods                 = "200";                    // f�r einige Timeframes sind gebrochene Werte zul�ssig (z.B. 1.5 x D1)
extern bool   MA.Periods.Hotkeys.Enabled = false;                    // ob Hotkeys zur schnellen �nderung der Periode aktiviert sind
extern string MA.Timeframe               = "current";                // Timeframe: [M1|M5|M15,...[=> M1|M5|M15,...]]    ("current"|"" = aktueller Timeframe)
extern string MA.Method                  = "SMA* | EMA | LWMA | ALMA";
extern string MA.AppliedPrice            = "Open | High | Low | Close* | Median | Typical | Weighted";

extern color  Color.UpTrend              = DodgerBlue;               // Farbverwaltung hier, damit Code Zugriff hat
extern color  Color.DownTrend            = Orange;

extern int    Max.Values                 = 2000;                     // H�chstanzahl darzustellender Werte: -1 = keine Begrenzung
extern int    Shift.Horizontal.Bars      = 0;                        // horizontale Indikator-Shift in Bars
extern int    Shift.Vertical.Pips        = 0;                        // vertikale Indikator-Shift in Pips

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <indicators/iMA.mqh>
#include <indicators/iALMA.mqh>

#define MovingAverage.MODE_MA          0                             // Buffer-ID's
#define MovingAverage.MODE_TREND       1
#define MovingAverage.MODE_UPTREND1    2                             // Bei Unterbrechung eines Down-Trends um nur eine Bar wird dieser Up-Trend durch den sich fortsetzenden Down-Trend
#define MovingAverage.MODE_DOWNTREND   3                             // optisch verdeckt. Um auch diese kurzfristigen Trendwechsel sichtbar zu machen, werden sie im Buffer MODE_UPTREND.2
#define MovingAverage.MODE_UPTREND2    4                             // gespeichert, der den Buffer MODE_DOWNTREND �berlagert.

#property indicator_chart_window

#property indicator_buffers 5

#property indicator_width1  0
#property indicator_width2  0
#property indicator_width3  2
#property indicator_width4  2
#property indicator_width5  2

#define MA_PERIODS_UP       1
#define MA_PERIODS_DOWN    -1

double bufferMA       [];                                            // vollst. Indikator (unsichtbar, Anzeige im "Data Window")
double bufferTrend    [];                                            // Trend: +/-        (unsichtbar)
double bufferUpTrend1 [];                                            // UpTrend-Linie 1   (sichtbar)
double bufferDownTrend[];                                            // DownTrend-Linie   (sichtbar, �berlagert UpTrend-Linie 1)
double bufferUpTrend2 [];                                            // UpTrend-Linie 2   (sichtbar, �berlagert DownTrend-Linie)

int    ma.periods;
int    ma.timeframe;
int    ma.method;
int    ma.appliedPrice;

double alma.weights[];                                               // ALMA: Gewichtungen der einzelnen Bars

double shift.vertical;
string legendLabel, legendName;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) Validierung
   // (1.1) MA.Timeframe zuerst, da G�ltigkeit von MA.Periods davon abh�ngt
   string sValue = StringToUpper(StringTrim(MA.Timeframe));
   if (sValue=="" || sValue=="CURRENT") {
      ma.timeframe = Period();
      MA.Timeframe = "";
   }
   else {
      string values[];
      if (Explode(sValue, "=>", values, 2) == 1) {
         ma.timeframe = StrToPeriod(sValue);
         if (ma.timeframe == -1)               return(catch("onInit(1)   Invalid input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT_PARAMVALUE));
         MA.Timeframe = PeriodDescription(ma.timeframe);
      }
      else {
         int timeframe1=StrToPeriod(StringTrim(values[0])), timeframe2=StrToPeriod(StringTrim(values[1]));
         if (timeframe1==-1 || timeframe2==-1) return(catch("onInit(2)   Invalid input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT_PARAMVALUE));
         if (timeframe1 < timeframe2)          return(catch("onInit(3)   Invalid input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT_PARAMVALUE));

         if (timeframe1 > timeframe2) {                         // Timeframes > W1 k�nnen nicht immer auf einen kleineren Timeframe heruntergerechnet werden
            if (timeframe1==PERIOD_MN1 || (timeframe1==PERIOD_Q1 && timeframe2!=PERIOD_MN1))
                                               return(catch("onInit(4)   Illegal input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT_PARAMVALUE));
            ma.timeframe = timeframe2;
            MA.Timeframe = PeriodDescription(timeframe1) +"=>"+ PeriodDescription(timeframe2);
         }
         else {
            ma.timeframe = timeframe1;
            MA.Timeframe = PeriodDescription(timeframe1);
         }
      }
   }




   // (1.2) MA.Periods
   sValue = StringTrim(MA.Periods);
   if (!StringIsNumeric(sValue))     return(catch("onInit(2)   Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMVALUE));
   double dValue = StrToDouble(sValue);
   if (dValue <= 0)                  return(catch("onInit(3)   Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMVALUE));
   if (MathModFix(dValue, 0.5) != 0) return(catch("onInit(4)   Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMVALUE));
   sValue = NumberToStr(dValue, ".+");
   if (StringEndsWith(sValue, ".5")) {                               // gebrochene Perioden in ganze Bars umrechnen
      switch (ma.timeframe) {
         case PERIOD_M30: dValue *=  2; ma.timeframe = PERIOD_M15; break;
         case PERIOD_H1 : dValue *=  2; ma.timeframe = PERIOD_M30; break;
         case PERIOD_H4 : dValue *=  4; ma.timeframe = PERIOD_H1;  break;
         case PERIOD_D1 : dValue *=  6; ma.timeframe = PERIOD_H4;  break;
         case PERIOD_W1 : dValue *= 30; ma.timeframe = PERIOD_H4;  break;
         default:                    return(catch("onInit(5)   Illegal input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMVALUE));
      }
   }
   switch (ma.timeframe) {                                           // Timeframes > H1 auf H1 umrechnen
      case PERIOD_H4: dValue *=   4; ma.timeframe = PERIOD_H1; break;
      case PERIOD_D1: dValue *=  24; ma.timeframe = PERIOD_H1; break;
      case PERIOD_W1: dValue *= 120; ma.timeframe = PERIOD_H1; break;
   }
   ma.periods = MathRound(dValue);
   if (ma.periods < 2)               return(catch("onInit(6)   Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMVALUE));
   if (ma.timeframe != Period()) {                                   // angegebenen auf aktuellen Timeframe umrechnen
      double minutes = ma.timeframe * ma.periods;                    // Timeframe * Anzahl_Bars = Range_in_Minuten
      ma.periods = MathRound(minutes/Period());
   }
   MA.Periods = sValue;

   // (1.3) MA.Method
   string elems[];
   if (Explode(MA.Method, "*", elems, 2) > 1) {
      int size = Explode(elems[0], "|", elems, NULL);
      sValue   = elems[size-1];
   }
   else sValue = MA.Method;
   ma.method = StrToMovAvgMethod(sValue);
   if (ma.method == -1)              return(catch("onInit(7)   Invalid input parameter MA.Method = \""+ MA.Method +"\"", ERR_INVALID_INPUT_PARAMVALUE));
   MA.Method = MovAvgMethodDescription(ma.method);

   // (1.4) MA.AppliedPrice
   if (Explode(MA.AppliedPrice, "*", elems, 2) > 1) {
      size   = Explode(elems[0], "|", elems, NULL);
      sValue = elems[size-1];
   }
   else sValue = MA.AppliedPrice;
   ma.appliedPrice = StrToPriceType(sValue);
   if (ma.appliedPrice==-1 || ma.appliedPrice > PRICE_WEIGHTED)
                                     return(catch("onInit(8)   Invalid input parameter MA.AppliedPrice = \""+ MA.AppliedPrice +"\"", ERR_INVALID_INPUT_PARAMVALUE));
   MA.AppliedPrice = PriceTypeDescription(ma.appliedPrice);

   // (1.5) Max.Values
   if (Max.Values < -1)              return(catch("onInit(9)   Invalid input parameter Max.Values = "+ Max.Values, ERR_INVALID_INPUT_PARAMVALUE));

   // (1.6) Colors
   if (Color.UpTrend   == 0xFF000000) Color.UpTrend   = CLR_NONE;    // aus CLR_NONE = 0xFFFFFFFF macht das Terminal nach Recompile oder Deserialisierung
   if (Color.DownTrend == 0xFF000000) Color.DownTrend = CLR_NONE;    // u.U. 0xFF000000 (entspricht Schwarz)


   // (2) Chart-Legende erzeugen
   string strTimeframe="", strAppliedPrice="";
   if (MA.Timeframe != "")             strTimeframe    = "x"+ MA.Timeframe;
   if (ma.appliedPrice != PRICE_CLOSE) strAppliedPrice = ", "+ PriceTypeDescription(ma.appliedPrice);
   legendName  = MA.Method +"("+ MA.Periods + strTimeframe + strAppliedPrice +")";
   legendLabel = CreateLegendLabel(legendName);
   ObjectRegister(legendLabel);


   // (3) ggf. ALMA-Gewichtungen berechnen
   if (ma.method==MODE_ALMA) /*&&*/ if (ma.periods > 1)              // ma.periods < 2 ist m�glich bei Umschalten auf zu gro�en Timeframe
      iALMA.CalculateWeights(alma.weights, ma.periods);


   // (4.1) Bufferverwaltung
   SetIndexBuffer(MovingAverage.MODE_MA,        bufferMA       );    // vollst. Indikator: unsichtbar (Anzeige im "Data Window"
   SetIndexBuffer(MovingAverage.MODE_TREND,     bufferTrend    );    // Trend: +/-         unsichtbar
   SetIndexBuffer(MovingAverage.MODE_UPTREND1,  bufferUpTrend1 );    // UpTrend-Linie 1:   sichtbar
   SetIndexBuffer(MovingAverage.MODE_DOWNTREND, bufferDownTrend);    // DownTrend-Linie:   sichtbar
   SetIndexBuffer(MovingAverage.MODE_UPTREND2,  bufferUpTrend2 );    // UpTrend-Linie 2:   sichtbar

   // (4.2) Anzeigeoptionen
   IndicatorShortName(legendName);                                   // Context Menu
   string dataName = MA.Method +"("+ MA.Periods + strTimeframe +")";
   SetIndexLabel(MovingAverage.MODE_MA,        dataName);            // Tooltip und "Data Window"
   SetIndexLabel(MovingAverage.MODE_TREND,     NULL);
   SetIndexLabel(MovingAverage.MODE_UPTREND1,  NULL);
   SetIndexLabel(MovingAverage.MODE_DOWNTREND, NULL);
   SetIndexLabel(MovingAverage.MODE_UPTREND2,  NULL);
   IndicatorDigits(SubPipDigits);

   // (4.3) Zeichenoptionen
   int startDraw = Max(ma.periods-1, Bars-ifInt(Max.Values < 0, Bars, Max.Values)) + Shift.Horizontal.Bars;
   SetIndexDrawBegin(MovingAverage.MODE_MA,        0        ); SetIndexShift(MovingAverage.MODE_MA,        Shift.Horizontal.Bars);
   SetIndexDrawBegin(MovingAverage.MODE_TREND,     0        ); SetIndexShift(MovingAverage.MODE_TREND,     Shift.Horizontal.Bars);
   SetIndexDrawBegin(MovingAverage.MODE_UPTREND1,  startDraw); SetIndexShift(MovingAverage.MODE_UPTREND1,  Shift.Horizontal.Bars);
   SetIndexDrawBegin(MovingAverage.MODE_DOWNTREND, startDraw); SetIndexShift(MovingAverage.MODE_DOWNTREND, Shift.Horizontal.Bars);
   SetIndexDrawBegin(MovingAverage.MODE_UPTREND2,  startDraw); SetIndexShift(MovingAverage.MODE_UPTREND2,  Shift.Horizontal.Bars);

   shift.vertical = Shift.Vertical.Pips * Pip;                       // TODO: Digits/Point-Fehler abfangen

   // (4.4) Styles
   SetIndicatorStyles();                                             // Workaround um diverse Terminalbugs (siehe dort)

   return(catch("onInit(10)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   DeleteRegisteredObjects(NULL);
   RepositionLegend();
   return(catch("onDeinit()"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // Abschlu� der Buffer-Initialisierung �berpr�fen
   if (ArraySize(bufferMA) == 0)                                        // kann bei Terminal-Start auftreten
      return(SetLastError(ERS_TERMINAL_NOT_YET_READY));

   // vor vollst�ndiger Neuberechnung Buffer zur�cksetzen
   if (!ValidBars) {
      ArrayInitialize(bufferMA,        EMPTY_VALUE);
      ArrayInitialize(bufferTrend,               0);
      ArrayInitialize(bufferUpTrend1,  EMPTY_VALUE);
      ArrayInitialize(bufferDownTrend, EMPTY_VALUE);
      ArrayInitialize(bufferUpTrend2,  EMPTY_VALUE);
      SetIndicatorStyles();                                             // Workaround um diverse Terminalbugs (siehe dort)
   }


   // (1) �nderungen der MA-Periode zur Laufzeit (per Hotkey) erkennen und �bernehmen
   if (MA.Periods.Hotkeys.Enabled)
      HandleEvent(EVENT_CHART_CMD);                                     // ChartCommands verarbeiten

   if (ma.periods < 2)                                                  // Abbruch bei ma.periods < 2 (m�glich bei Umschalten auf zu gro�en Timeframe)
      return(NO_ERROR);


   // (2) Startbar der Berechnung ermitteln
   int ma.ChangedBars = ChangedBars;
   if (ma.ChangedBars > Max.Values) /*&&*/ if (Max.Values >= 0)
      ma.ChangedBars = Max.Values;
   int ma.startBar = Min(ma.ChangedBars-1, Bars-ma.periods);
   if (ma.startBar < 0) {
      if (IsSuperContext())
         return(catch("onTick(1)", ERR_HISTORY_INSUFFICIENT));
      SetLastError(ERR_HISTORY_INSUFFICIENT);                           // Signalisieren, falls Bars f�r Berechnung nicht ausreichen (keine R�ckkehr)
   }


   // (3) ung�ltige Bars neuberechnen
   for (int bar=ma.startBar; bar >= 0; bar--) {
      // der eigentliche Moving Average
      if (ma.method == MODE_ALMA) {                                     // ALMA
         bufferMA[bar] = 0;
         for (int i=0; i < ma.periods; i++) {
            bufferMA[bar] += alma.weights[i] * iMA(NULL, NULL, 1, 0, MODE_SMA, ma.appliedPrice, bar+i);
         }
      }
      else {                                                            // alle �brigen MA's
         bufferMA[bar] = iMA(NULL, NULL, ma.periods, 0, ma.method, ma.appliedPrice, bar);
      }
      bufferMA[bar] += shift.vertical;

      // Trend aktualisieren
      iMA.UpdateTrend(bufferMA, bar, bufferTrend, bufferUpTrend1, bufferDownTrend, bufferUpTrend2);
   }


   // (4) Legende aktualisieren
   iMA.UpdateLegend(legendLabel, legendName, Color.UpTrend, Color.DownTrend, bufferMA[0], bufferTrend[0], Time[0]);
   return(last_error);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein ChartCommand f�r diesen Indikator eingetroffen ist.
 *
 * @param  string commands[] - Array zur Aufnahme der eingetroffenen Commands
 * @param  int    flags      - zus�tzliche eventspezifische Flags (default: keine)
 *
 * @return bool - Ergebnis
 */
bool EventListener.ChartCommand(string &commands[], int flags=NULL) {
   if (!IsChart)
      return(false);

   static string label, mutex; if (!StringLen(label)) {
      label = __NAME__ +".command";
      mutex = "mutex."+ label;
   }


   // (1) zuerst nur Lesezugriff (unsynchronisiert m�glich), um nicht bei jedem Tick das Lock erwerben zu m�ssen
   if (ObjectFind(label) == 0) {

      // (2) erst, wenn ein Command eingetroffen ist, Lock f�r Schreibzugriff holen
      if (!AquireLock(mutex, true))
         return(!SetLastError(stdlib.GetLastError()));

      // (3) Command auslesen und Command-Object l�schen
      ArrayResize(commands, 1);
      commands[0] = ObjectDescription(label);
      ObjectDelete(label);

      // (4) Lock wieder freigeben
      if (!ReleaseLock(mutex))
         return(!SetLastError(stdlib.GetLastError()));

      return(!catch("EventListener.ChartCommand(1)"));
   }
   return(false);
}


/**
 * Handler f�r ChartCommands.
 *
 * @param  string commands[] - die eingetroffenen Commands
 *
 * @return bool - Erfolgsstatus
 */
bool onChartCommand(string commands[]) {
   int size = ArraySize(commands);
   if (!size) return(!warn("onChartCommand(1)   empty parameter commands = {}"));

   for (int i=0; i < size; i++) {
      if      (commands[i] == "Periods=Up"  ) { if (!ModifyMaPeriods(MA_PERIODS_UP  )) return(false); }
      else if (commands[i] == "Periods=Down") { if (!ModifyMaPeriods(MA_PERIODS_DOWN)) return(false); }
      else
         warn("onChartCommand(2)   unknown chart command \""+ commands[i] +"\"");
   }
   return(!catch("onChartCommand(3)"));
}


/**
 * Erh�ht oder verringert den Parameter MA.Periods des Indikators.
 *
 * @param  int direction - Richtungs-ID:  MA_PERIODS_UP|MA_PERIODS_DOWN
 *
 * @return bool - Erfolgsstatus
 */
bool ModifyMaPeriods(int direction) {
   if (direction == MA_PERIODS_DOWN) {
   }
   else if (direction == MA_PERIODS_UP) {
   }
   else warn("ModifyMaPeriods(1)   unknown parameter direction = "+ direction);

   return(true);
}


/**
 * Indikator-Styles setzen. Workaround um diverse Terminalbugs (Farb-/Style�nderungen nach Recompile), die erfordern, da� die Styles
 * normalerweise in init(), nach Recompile jedoch in start() gesetzt werden m�ssen, um korrekt angezeigt zu werden.
 */
void SetIndicatorStyles() {
   SetIndexStyle(MovingAverage.MODE_MA,        DRAW_NONE, EMPTY, EMPTY, CLR_NONE       );
   SetIndexStyle(MovingAverage.MODE_TREND,     DRAW_NONE, EMPTY, EMPTY, CLR_NONE       );
   SetIndexStyle(MovingAverage.MODE_UPTREND1,  DRAW_LINE, EMPTY, EMPTY, Color.UpTrend  );
   SetIndexStyle(MovingAverage.MODE_DOWNTREND, DRAW_LINE, EMPTY, EMPTY, Color.DownTrend);
   SetIndexStyle(MovingAverage.MODE_UPTREND2,  DRAW_LINE, EMPTY, EMPTY, Color.UpTrend  );
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()   inputs: ",

                            "MA.Periods=\"",          MA.Periods                 , "\"; ",
                            "MA.Timeframe=\"",        MA.Timeframe               , "\"; ",
                            "MA.Method=\"",           MA.Method                  , "\"; ",
                            "MA.AppliedPrice=\"",     MA.AppliedPrice            , "\"; ",

                            "Color.UpTrend=",         ColorToStr(Color.UpTrend)  , "; ",
                            "Color.DownTrend=",       ColorToStr(Color.DownTrend), "; ",

                            "Max.Values=",            Max.Values                 , "; ",
                            "Shift.Horizontal.Bars=", Shift.Horizontal.Bars      , "; ",
                            "Shift.Vertical.Pips=",   Shift.Vertical.Pips        , "; ")
   );
}
