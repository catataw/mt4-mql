/**
 * Multi-Color/Multi-Timeframe Moving Average
 */
#include <core/define.mqh>
#define     __TYPE__   T_INDICATOR
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>

//////////////////////////////////////////////////////////////// Externe Parameter ////////////////////////////////////////////////////////////////

extern int    MA.Periods        = 200;                            // averaging period
extern string MA.Timeframe      = "";                             // averaging timeframe [M1 | M5 | M15] etc.: "" = aktueller Timeframe
extern string MA.Method         = "SMA";                          // averaging method
extern string MA.Method.Help    = "SMA | EMA | SMMA | LWMA";
extern string AppliedPrice      = "Close";                        // price used for MA calculation
extern string AppliedPrice.Help = "Open | High | Low | Close | Median | Typical | Weighted";
extern int    Max.Values        = 2000;                           // maximum number of indicator values to display: -1 = all

extern color  Color.UpTrend     = DodgerBlue;                     // Farbverwaltung hier, damit Code Zugriff hat
extern color  Color.DownTrend   = Orange;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>

#property indicator_chart_window

#property indicator_buffers 4

#property indicator_width1  0
#property indicator_width2  0
#property indicator_width3  2
#property indicator_width4  2


double bufferMA       [];                                         // vollst. Indikator: Anzeige im "Data Window" (im Chart unsichtbar)
double bufferTrend    [];                                         // Trend: +1/-1                                (im Chart unsichtbar)
double bufferUpTrend  [];                                         // UpTrend-Linie                               (sichtbar)
double bufferDownTrend[];                                         // DownTrendTrend-Linie                        (sichtbar)

int    ma.periods;
int    ma.method;
int    appliedPrice;
string legendLabel, indicatorName;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) Validierung
   // MA.Periods
   if (MA.Periods < 2)     return(catch("onInit(1)   Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT));
   ma.periods = MA.Periods;

   // MA.Timeframe
   MA.Timeframe = StringToUpper(StringTrim(MA.Timeframe));
   if (MA.Timeframe == "") int ma.timeframe = Period();
   else                        ma.timeframe = PeriodToId(MA.Timeframe);
   if (ma.timeframe == -1) return(catch("onInit(2)   Invalid input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT));

   // MA.Method
   MA.Method = StringToUpper(StringTrim(MA.Method));
   if      (MA.Method == "SMA" ) ma.method = MODE_SMA;
   else if (MA.Method == "EMA" ) ma.method = MODE_EMA;
   else if (MA.Method == "SMMA") ma.method = MODE_SMMA;
   else if (MA.Method == "LWMA") ma.method = MODE_LWMA;
   else                    return(catch("onInit(3)   Invalid input parameter MA.Method = \""+ MA.Method +"\"", ERR_INVALID_INPUT));

   // AppliedPrice
   string char = StringToUpper(StringLeft(StringTrim(AppliedPrice), 1));
   if      (char == "O") appliedPrice = PRICE_OPEN;
   else if (char == "H") appliedPrice = PRICE_HIGH;
   else if (char == "L") appliedPrice = PRICE_LOW;
   else if (char == "C") appliedPrice = PRICE_CLOSE;
   else if (char == "M") appliedPrice = PRICE_MEDIAN;
   else if (char == "T") appliedPrice = PRICE_TYPICAL;
   else if (char == "W") appliedPrice = PRICE_WEIGHTED;
   else                    return(catch("onInit(4)   Invalid input parameter AppliedPrice = \""+ AppliedPrice +"\"", ERR_INVALID_INPUT));


   // (2) Periodenanzahl auf aktuellen Timeframe umrechnen
   if (ma.timeframe == Period()) {
      ma.periods = MA.Periods;
   }
   else {
      double minutes = ma.timeframe * MA.Periods;                    // Timeframe * Anzahl Bars = Range in Minuten
      ma.periods = Round(minutes/Period());
   }


   // (3.1) Bufferverwaltung
   SetIndexBuffer(0, bufferMA       );                               // vollst. Indikator: Anzeige im "Data Window" (im Chart unsichtbar)
   SetIndexBuffer(1, bufferTrend    );                               // Trendsignalisierung: +1/-1                  (im Chart unsichtbar)
   SetIndexBuffer(2, bufferUpTrend  );                               // UpTrend-Linie                               (sichtbar)
   SetIndexBuffer(3, bufferDownTrend);                               // DownTrendTrend-Linie                        (sichtbar)

   // (3.2) Anzeigeoptionen
   string strTimeframe, strAppliedPrice;
   if (MA.Timeframe != "")          strTimeframe    = StringConcatenate("x", MA.Timeframe);
   if (appliedPrice != PRICE_CLOSE) strAppliedPrice = StringConcatenate(" / ", AppliedPriceDescription(appliedPrice));
   indicatorName = StringConcatenate(MA.Method, "(", MA.Periods, strTimeframe, strAppliedPrice, ")");

   IndicatorShortName(indicatorName);
   SetIndexLabel(0, indicatorName);
   SetIndexLabel(1, NULL);
   SetIndexLabel(2, NULL);
   SetIndexLabel(3, NULL);
   IndicatorDigits(Digits);

   // (3.3) Zeichenoptionen
   int startDraw = Max(ma.periods-1, Bars-ifInt(Max.Values < 0, Bars, Max.Values));
   SetIndexDrawBegin(0, startDraw);
   SetIndexDrawBegin(1, startDraw);
   SetIndexDrawBegin(2, startDraw);
   SetIndexDrawBegin(3, startDraw);

   // (3.4) Styles
   SetIndicatorStyles();                                             // Workaround um diverse Terminalbugs (siehe dort)


   // (4) Chart-Legende erzeugen
   legendLabel = CreateLegendLabel(indicatorName);
   ArrayPushString(objects, legendLabel);

   return(catch("onInit(5)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   RemoveChartObjects(objects);
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
      return(SetLastError(ERR_TERMINAL_NOT_YET_READY));

   // vor kompletter Neuberechnung alle Buffer zur�cksetzen
   if (ValidBars == 0) {
      ArrayInitialize(bufferMA,        EMPTY_VALUE);
      ArrayInitialize(bufferTrend,               0);
      ArrayInitialize(bufferUpTrend,   EMPTY_VALUE);
      ArrayInitialize(bufferDownTrend, EMPTY_VALUE);
      SetIndicatorStyles();                                             // Workaround um diverse Terminalbugs (siehe dort)
   }

   if (ma.periods < 2)                                                  // Abbruch bei ma.periods < 2 (m�glich bei Umschalten auf zu gro�en Timeframe)
      return(NO_ERROR);


   // (1) Startbar f�r Neuberechnung ermitteln
   if (ChangedBars > Max.Values) /*&&*/ if (Max.Values >= 0)
      ChangedBars = Max.Values;
   int startBar = Min(ChangedBars-1, Bars-ma.periods);

   double curValue, prevValue;


   // (2) ge�nderte Bars (neu-)berechnen
   for (int bar=startBar; bar >= 0; bar--) {
      // der eigentliche Moving Average
      bufferMA[bar] = iMA(NULL, NULL, ma.periods, 0, ma.method, appliedPrice, bar);

      // Trend coloring (minimalste Reversal-Gl�ttung um 1 Point durch Normalisierung)
      curValue  = NormalizeDouble(bufferMA[bar  ], Digits);
      prevValue = NormalizeDouble(bufferMA[bar+1], Digits);

      if (curValue > prevValue) {
         bufferTrend    [bar] = 1;
         bufferUpTrend  [bar] = bufferMA[bar];
         bufferDownTrend[bar] = EMPTY_VALUE;

         if (bufferTrend[bar+1] < 0) bufferUpTrend  [bar+1] = bufferMA[bar+1];
         else                        bufferDownTrend[bar+1] = EMPTY_VALUE;
      }
      else if (curValue < prevValue) {
         bufferTrend    [bar] = -1;
         bufferUpTrend  [bar] = EMPTY_VALUE;
         bufferDownTrend[bar] = bufferMA[bar];

         if (bufferTrend[bar+1] > 0) bufferDownTrend[bar+1] = bufferMA[bar+1];
         else                        bufferUpTrend  [bar+1] = EMPTY_VALUE;
      }
      else /*(curValue == prevValue)*/ {
         bufferTrend[bar] = bufferTrend[bar+1];

         if (bufferTrend[bar] > 0) {
            bufferUpTrend  [bar  ] = bufferMA[bar];
            bufferDownTrend[bar  ] = EMPTY_VALUE;
            bufferDownTrend[bar+1] = EMPTY_VALUE;
         }
         else {
            bufferUpTrend  [bar  ] = EMPTY_VALUE;
            bufferDownTrend[bar  ] = bufferMA[bar];
            bufferUpTrend  [bar+1] = EMPTY_VALUE;
         }
      }
   }
   if (startBar < 0)                                                    // Signalisieren, wenn Bars f�r Berechnung nicht ausreichen.
      SetLastError(ERR_HISTORY_INSUFFICIENT);


   static double lastTrend, lastValue;                                  // Trend und Value des letzten Ticks


   // (3.1) Legende aktualisieren: Farbe bei Trendwechsel
   if (NE(bufferTrend[0], lastTrend)) {
      ObjectSetText(legendLabel, ObjectDescription(legendLabel), 9, "Arial Fett", ifInt(bufferTrend[0]>0, Color.UpTrend, Color.DownTrend));
      int error = GetLastError();
      if (IsError(error)) /*&&*/ if (error!=ERR_OBJECT_DOES_NOT_EXIST)  // bei offenem Properties-Dialog oder Object::onDrag()
         return(catch("onTick(1)", error));
   }
   lastTrend = bufferTrend[0];


   // (3.2) Wert in Legende aktualisieren
   if (NE(curValue, lastValue)) {
      ObjectSetText(legendLabel,
                    StringConcatenate(indicatorName, "    ", NumberToStr(curValue, PriceFormat)),
                    ObjectGet(legendLabel, OBJPROP_FONTSIZE));
   }
   lastValue = curValue;

   return(catch("onTick(2)"));
}


/**
 * Indikator-Styles setzen. Workaround um diverse Terminalbugs (Farb-/Style�nderungen nach Recompile), die erfordern, da� die Styles
 * in der Regel in init(), nach Recompile jedoch in start() gesetzt werden m�ssen, um korrekt angezeigt zu werden.
 */
void SetIndicatorStyles() {
   SetIndexStyle(0, DRAW_NONE, EMPTY, EMPTY, CLR_NONE       );
   SetIndexStyle(1, DRAW_NONE, EMPTY, EMPTY, CLR_NONE       );
   SetIndexStyle(2, DRAW_LINE, EMPTY, EMPTY, Color.UpTrend  );
   SetIndexStyle(3, DRAW_LINE, EMPTY, EMPTY, Color.DownTrend);
}