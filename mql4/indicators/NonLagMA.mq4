/**
 * Zero-Lag Multi-Color Moving Average.
 *
 * Version 7 der Formel zur Berechnung der Gewichtungen reagiert ein klein wenig langsamer als Version 4 (und ist vermutlich die korrektere).
 * Die Trend-Umkehrpunkte beider Formeln sind jedoch in nahezu 100% aller F�lle identisch.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern int    Cycle.Length          = 20;
extern string Filter.Version        = "4* | 7";                      // Gewichtungsberechnung nach v4 oder v7.1

extern string Drawing.Type          = "Line | Dot*";
extern color  Color.UpTrend         = RoyalBlue;                     // Farbverwaltung hier, damit Code Zugriff hat
extern color  Color.DownTrend       = Red;

extern int    Max.Values            = 2000;                          // H�chstanzahl darzustellender Werte: -1 = keine Begrenzung
extern int    Shift.Vertical.Pips   = 0;                             // vertikale Shift in Pips
extern int    Shift.Horizontal.Bars = 0;                             // horizontale Shift in Bars

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <iFunctions/@MA.mqh>
#include <iFunctions/@ZLMA.mqh>

#define MODE_MA             MovingAverage.MODE_MA                    // Buffer-ID's
#define MODE_TREND          MovingAverage.MODE_TREND                 //
#define MODE_UPTREND        2                                        //
#define MODE_DOWNTREND      3                                        // Bei Unterbrechung eines Down-Trends um nur eine Bar wird dieser Up-Trend durch den sich fortsetzenden
#define MODE_UPTREND1       MODE_UPTREND                             // Down-Trend optisch verdeckt. Um auch solche kurzen Trendwechsel sichtbar zu machen, werden sie zus�tzlich
#define MODE_UPTREND2       4                                        // im Buffer MODE_UPTREND2 gespeichert, der im Chart den Buffer MODE_DOWNTREND optisch �berlagert.

#property indicator_chart_window

#property indicator_buffers 5

#property indicator_width1  0
#property indicator_width2  0
#property indicator_width3  1
#property indicator_width4  1
#property indicator_width5  1
int       indicator_drawingType = DRAW_ARROW;

double bufferMA       [];                                            // vollst. Indikator: unsichtbar (Anzeige im "Data Window")
double bufferTrend    [];                                            // Trend: +/-         unsichtbar
double bufferUpTrend1 [];                                            // UpTrend-Linie 1:   sichtbar
double bufferDownTrend[];                                            // DownTrend-Linie:   sichtbar (�berlagert UpTrend-Linie 1)
double bufferUpTrend2 [];                                            // UpTrend-Linie 2:   sichtbar (�berlagert DownTrend-Linie)

int    cycles = 4;
int    cycleLength;
int    cycleWindowSize;
int    version;                                                      // Berechnung nach Formel von Version

double ma.weights[];                                                 // Gewichtungen der einzelnen Bars des MA's

double shift.vertical;

string legendLabel;
string ma.shortName;                                                 // Name f�r Chart, Data-Window und Kontextmen�s


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) Validierung
   // (1.1) Cycle.Length
   if (Cycle.Length < 2) return(catch("onInit(1)  Invalid input parameter Cycle.Length = "+ Cycle.Length, ERR_INVALID_INPUT_PARAMETER));
   cycleLength     = Cycle.Length;
   cycleWindowSize = cycles*cycleLength + cycleLength-1;

   // (1.2) Filter.Version
   string elems[], strValue;
   if (Explode(Filter.Version, "*", elems, 2) > 1) {
      int size = Explode(elems[0], "|", elems, NULL);
      strValue = elems[size-1];
   }
   else strValue = Filter.Version;
   strValue = StringTrim(strValue);
   if      (strValue == "4") version = 4;
   else if (strValue == "7") version = 7;
   else return(catch("onInit(2)  Invalid input parameter Filter.Version = "+ DoubleQuoteStr(Filter.Version), ERR_INVALID_INPUT_PARAMETER));
   Filter.Version = strValue;

   // (1.3) Drawing.Type
   if (Explode(Drawing.Type, "*", elems, 2) > 1) {
      size     = Explode(elems[0], "|", elems, NULL);
      strValue = elems[size-1];
   }
   else strValue = Drawing.Type;
   strValue = StringToLower(StringTrim(strValue));
   if      (strValue == "line") indicator_drawingType = DRAW_LINE;
   else if (strValue == "dot" ) indicator_drawingType = DRAW_ARROW;
   else return(catch("onInit(3)  Invalid input parameter Drawing.Type = "+ DoubleQuoteStr(Drawing.Type), ERR_INVALID_INPUT_PARAMETER));
   Drawing.Type = StringCapitalize(strValue);

   // (1.4) Colors
   if (Color.UpTrend   == 0xFF000000) Color.UpTrend   = CLR_NONE;    // aus CLR_NONE = 0xFFFFFFFF macht das Terminal nach Recompilation oder Deserialisierung
   if (Color.DownTrend == 0xFF000000) Color.DownTrend = CLR_NONE;    // u.U. 0xFF000000 (entspricht Schwarz)

   // (1.5) Max.Values
   if (Max.Values < -1) return(catch("onInit(4)  Invalid input parameter Max.Values = "+ Max.Values, ERR_INVALID_INPUT_PARAMETER));


   // (2) Chart-Legende erzeugen
   ma.shortName = __NAME__ +"("+ cycleLength +")";
   legendLabel  = CreateLegendLabel(ma.shortName);
   ObjectRegister(legendLabel);


   // (3) MA-Gewichtungen berechnen
   @ZLMA.CalculateWeights(ma.weights, cycles, cycleLength, version);


   // (4.1) Bufferverwaltung
   SetIndexBuffer(MODE_MA,        bufferMA       );                     // vollst. Indikator: unsichtbar (Anzeige im "Data Window"
   SetIndexBuffer(MODE_TREND,     bufferTrend    );                     // Trend: +/-         unsichtbar
   SetIndexBuffer(MODE_UPTREND1,  bufferUpTrend1 );                     // UpTrend-Linie 1:   sichtbar
   SetIndexBuffer(MODE_DOWNTREND, bufferDownTrend);                     // DownTrend-Linie:   sichtbar
   SetIndexBuffer(MODE_UPTREND2,  bufferUpTrend2 );                     // UpTrend-Linie 2:   sichtbar

   // (4.2) Anzeigeoptionen
   IndicatorShortName(ma.shortName);                                    // Context Menu
   SetIndexLabel(MODE_MA,        ma.shortName);                         // Tooltip und "Data Window"
   SetIndexLabel(MODE_TREND,     NULL        );
   SetIndexLabel(MODE_UPTREND1,  NULL        );
   SetIndexLabel(MODE_DOWNTREND, NULL        );
   SetIndexLabel(MODE_UPTREND2,  NULL        );
   IndicatorDigits(SubPipDigits);

   // (4.3) Zeichenoptionen
   int startDraw = Max(cycleWindowSize-1, Bars-ifInt(Max.Values < 0, Bars, Max.Values)) + Shift.Horizontal.Bars;
   SetIndexDrawBegin(MODE_MA,        0        ); SetIndexShift(MODE_MA,        Shift.Horizontal.Bars);
   SetIndexDrawBegin(MODE_TREND,     0        ); SetIndexShift(MODE_TREND,     Shift.Horizontal.Bars);
   SetIndexDrawBegin(MODE_UPTREND1,  startDraw); SetIndexShift(MODE_UPTREND1,  Shift.Horizontal.Bars);
   SetIndexDrawBegin(MODE_DOWNTREND, startDraw); SetIndexShift(MODE_DOWNTREND, Shift.Horizontal.Bars);
   SetIndexDrawBegin(MODE_UPTREND2,  startDraw); SetIndexShift(MODE_UPTREND2,  Shift.Horizontal.Bars);

   shift.vertical = Shift.Vertical.Pips * Pips;                         // TODO: Digits/Point-Fehler abfangen

   // (4.4) Styles
   SetIndicatorStyles();                                                // Workaround um diverse Terminalbugs (siehe dort)
   return(catch("onInit(5)"));
}


/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   DeleteRegisteredObjects(NULL);
   RepositionLegend();
   return(catch("onDeinit(1)"));
}


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // Abschlu� der Buffer-Initialisierung �berpr�fen
   if (ArraySize(bufferMA) == 0)                                        // kann bei Terminal-Start auftreten
      return(debug("onTick(1)  size(bufferMA) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // vor kompletter Neuberechnung Buffer zur�cksetzen
   if (!ValidBars) {
      ArrayInitialize(bufferMA,        EMPTY_VALUE);
      ArrayInitialize(bufferTrend,               0);
      ArrayInitialize(bufferUpTrend1,  EMPTY_VALUE);
      ArrayInitialize(bufferDownTrend, EMPTY_VALUE);
      ArrayInitialize(bufferUpTrend2,  EMPTY_VALUE);
      SetIndicatorStyles();                                             // Workaround um diverse Terminalbugs (siehe dort)
   }


   // (1) Startbar der Berechnung ermitteln
   int startBar = Min(ChangedBars-1, Bars-cycleWindowSize-1);
   if (startBar < 0) {
      if (IsSuperContext()) return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));
      SetLastError(ERR_HISTORY_INSUFFICIENT);                           // Signalisieren, falls Bars f�r Berechnung nicht ausreichen (keine R�ckkehr)
   }


   // (2) ung�ltige Bars neuberechnen
   for (int bar=startBar; bar >= 0; bar--) {
      bufferMA[bar] = shift.vertical;

      // Moving Average
      for (int i=0; i < cycleWindowSize; i++) {
         bufferMA[bar] += ma.weights[i] * iMA(NULL, NULL, 1, 0, MODE_SMA, PRICE_CLOSE, bar+i);
      }

      // Trend aktualisieren
      @MA.UpdateTrend(bufferMA, bar, bufferTrend, bufferUpTrend1, bufferDownTrend, bufferUpTrend2, indicator_drawingType);
   }


   // (3) Legende aktualisieren
   @MA.UpdateLegend(legendLabel, ma.shortName, "", Color.UpTrend, Color.DownTrend, bufferMA[0], bufferTrend[0], Time[0]);

   return(catch("onTick(3)"));
}


/**
 * Indikator-Styles setzen. Workaround um diverse Terminalbugs (Farb-/Style�nderungen nach Recompilation), die erfordern, da� die Styles
 * in der Regel in init(), nach Recompilation jedoch in start() gesetzt werden m�ssen, um korrekt angezeigt zu werden.
 */
void SetIndicatorStyles() {
   int lineWidth = ifInt(indicator_drawingType==DRAW_ARROW, 1, EMPTY);

   SetIndexStyle(MODE_MA,        DRAW_NONE, EMPTY, EMPTY, CLR_NONE);
   SetIndexStyle(MODE_TREND,     DRAW_NONE, EMPTY, EMPTY, CLR_NONE);

   SetIndexStyle(MODE_UPTREND1,  indicator_drawingType, EMPTY, lineWidth, Color.UpTrend  ); SetIndexArrow(MODE_UPTREND1,  159);
   SetIndexStyle(MODE_DOWNTREND, indicator_drawingType, EMPTY, lineWidth, Color.DownTrend); SetIndexArrow(MODE_DOWNTREND, 159);
   SetIndexStyle(MODE_UPTREND2,  indicator_drawingType, EMPTY, lineWidth, Color.UpTrend  ); SetIndexArrow(MODE_UPTREND2,  159);
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "Cycle.Length=",          Cycle.Length                , "; ",
                            "Filter.Version=",        Filter.Version              , "; ",

                            "Drawing.Type=",          DoubleQuoteStr(Drawing.Type), "; ",
                            "Color.UpTrend=",         ColorToStr(Color.UpTrend)   , "; ",
                            "Color.DownTrend=",       ColorToStr(Color.DownTrend) , "; ",

                            "Max.Values=",            Max.Values                  , "; ",
                            "Shift.Vertical.Pips=",   Shift.Vertical.Pips         , "; ",
                            "Shift.Horizontal.Bars=", Shift.Horizontal.Bars       , "; ")
   );
}
