/**
 * Multi-Timeframe Keltner Channel (ATR-Channel)
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////////////////////////////////// Konfiguration ////////////////////////////////////////////////////////////////////////////////////

extern string MA.Periods            = "200";                         // f�r einige Timeframes sind gebrochene Werte zul�ssig (z.B. 1.5 x D1)
extern string MA.Timeframe          = "current";                     // Timeframe: [M1|M5|M15|...], "" = aktueller Timeframe
extern string MA.Method             = "SMA* | EMA | LWMA | ALMA";
extern string MA.AppliedPrice       = "Open | High | Low | Close* | Median | Typical | Weighted";

extern int    ATR.Periods           = 100;
extern string ATR.Timeframe         = "MA";                          // Timeframe: [M1|M5|M15|...], "MA" = wie MA
extern double ATR.Multiplicator     = 1;

extern color  Color.Bands           = Blue;                          // Farbverwaltung hier, damit Code Zugriff hat
extern color  Color.MA              = CLR_NONE;

extern int    Max.Values            = 2000;                          // H�chstanzahl darzustellender Werte: -1 = keine Begrenzung
extern int    Shift.Vertical.Pips   = 0;                             // vertikale Shift in Pips
extern int    Shift.Horizontal.Bars = 0;                             // horizontale Shift in Bars

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <iFunctions/@Bands.mqh>
#include <iFunctions/@ALMA.mqh>

#define Bands.MODE_UPPER      0                                      // oberes Band
#define Bands.MODE_MA         1                                      // MA
#define Bands.MODE_LOWER      2                                      // unteres Band

#property indicator_chart_window

#property indicator_buffers   3

#property indicator_style1    STYLE_SOLID
#property indicator_style2    STYLE_DOT
#property indicator_style3    STYLE_SOLID


double bufferUpperBand[];                                            // sichtbar
double bufferMA       [];                                            // sichtbar
double bufferLowerBand[];                                            // sichtbar

int    ma.periods;
int    ma.method;
int    ma.appliedPrice;

int    atr.timeframe;

double alma.weights[];                                               // Gewichtungen der einzelnen Bars eines ALMA

double shift.vertical;
string legendLabel, iDescription;


/**
 * Initialisierung
 *
 * @return int - Fehlerstatus
 */
int onInit() {
   // (1) Validierung
   // (1.1) MA.Timeframe zuerst, da G�ltigkeit von MA.Periods davon abh�ngt
   MA.Timeframe = StringToUpper(StringTrim(MA.Timeframe));
   if (MA.Timeframe == "CURRENT")     MA.Timeframe = "";
   if (MA.Timeframe == ""       ) int ma.timeframe = Period();
   else                               ma.timeframe = StrToPeriod(MA.Timeframe);
   if (ma.timeframe == -1)           return(catch("onInit(1)  Invalid input parameter MA.Timeframe = \""+ MA.Timeframe +"\"", ERR_INVALID_INPUT_PARAMETER));

   // (1.2) MA.Periods
   string strValue = StringTrim(MA.Periods);
   if (!StringIsNumeric(strValue))   return(catch("onInit(2)  Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   double dValue = StrToDouble(strValue);
   if (dValue <= 0)                  return(catch("onInit(3)  Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   if (MathModFix(dValue, 0.5) != 0) return(catch("onInit(4)  Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   strValue = NumberToStr(dValue, ".+");
   if (StringEndsWith(strValue, ".5")) {                             // gebrochene Perioden in ganze Bars umrechnen
      switch (ma.timeframe) {
         case PERIOD_M30: dValue *=   2; ma.timeframe = PERIOD_M15; break;
         case PERIOD_H1 : dValue *=   2; ma.timeframe = PERIOD_M30; break;
         case PERIOD_H4 : dValue *=   4; ma.timeframe = PERIOD_H1;  break;
         case PERIOD_D1 : dValue *=   6; ma.timeframe = PERIOD_H4;  break;
         case PERIOD_W1 : dValue *=  30; ma.timeframe = PERIOD_H4;  break;
         default:                    return(catch("onInit(5)  Illegal input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
      }
   }
   switch (ma.timeframe) {                                           // Timeframes > H1 auf H1 umrechnen
         case PERIOD_H4 : dValue *=   4; ma.timeframe = PERIOD_H1;  break;
         case PERIOD_D1 : dValue *=  24; ma.timeframe = PERIOD_H1;  break;
         case PERIOD_W1 : dValue *= 120; ma.timeframe = PERIOD_H1;  break;
   }
   ma.periods = MathRound(dValue);
   if (ma.periods < 2)               return(catch("onInit(6)  Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   if (ma.timeframe != Period()) {                                   // angegebenen auf aktuellen Timeframe umrechnen
      double minutes = ma.timeframe * ma.periods;                    // Timeframe * Anzahl_Bars = Range_in_Minuten
      ma.periods = MathRound(minutes/Period());
   }
   MA.Periods = strValue;

   // (1.3) MA.Method
   string elems[];
   if (Explode(MA.Method, "*", elems, 2) > 1) {
      int size = Explode(elems[0], "|", elems, NULL);
      strValue = elems[size-1];
   }
   else strValue = MA.Method;
   ma.method = StrToMaMethod(strValue, MUTE_ERR_INVALID_PARAMETER);
   if (ma.method == -1)              return(catch("onInit(7)  Invalid input parameter MA.Method = \""+ MA.Method +"\"", ERR_INVALID_INPUT_PARAMETER));
   MA.Method = MaMethodDescription(ma.method);

   // (1.4) MA.AppliedPrice
   if (Explode(MA.AppliedPrice, "*", elems, 2) > 1) {
      size     = Explode(elems[0], "|", elems, NULL);
      strValue = elems[size-1];
   }
   else strValue = MA.AppliedPrice;
   ma.appliedPrice = StrToPriceType(strValue);
   if (ma.appliedPrice==-1 || ma.appliedPrice > PRICE_WEIGHTED)
                                     return(catch("onInit(8)  Invalid input parameter MA.AppliedPrice = \""+ MA.AppliedPrice +"\"", ERR_INVALID_INPUT_PARAMETER));
   MA.AppliedPrice = PriceTypeDescription(ma.appliedPrice);

   // (1.5) ATR.Periods
   if (ATR.Periods < 1)              return(catch("onInit(9)  Invalid input parameter ATR.Periods = "+ ATR.Periods, ERR_INVALID_INPUT_PARAMETER));

   // (1.6) ATR.Timeframe
   ATR.Timeframe = StringToUpper(StringTrim(ATR.Timeframe));
   if (ATR.Timeframe == "MA"     ) ATR.Timeframe = StringToUpper(MA.Timeframe);
   if (ATR.Timeframe == "CURRENT") ATR.Timeframe = "";
   if (ATR.Timeframe == ""       ) atr.timeframe = Period();
   else                            atr.timeframe = StrToPeriod(ATR.Timeframe);
   if (atr.timeframe == -1)          return(catch("onInit(10)  Invalid input parameter ATR.Timeframe = \""+ ATR.Timeframe +"\"", ERR_INVALID_INPUT_PARAMETER));

   // (1.7) ATR.Multiplicator
   if (ATR.Multiplicator < 0)        return(catch("onInit(11)  Invalid input parameter ATR.Multiplicator = "+ NumberToStr(ATR.Multiplicator, ".+"), ERR_INVALID_INPUT_PARAMETER));

   // (1.8) Colors
   if (Color.Bands == 0xFF000000) Color.Bands = CLR_NONE;            // aus CLR_NONE = 0xFFFFFFFF macht das Terminal nach Recompilation oder Deserialisierung
   if (Color.MA    == 0xFF000000) Color.MA    = CLR_NONE;            // u.U. 0xFF000000 (entspricht Schwarz)

   // (1.9) Max.Values
   if (Max.Values < -1)              return(catch("onInit(12)  Invalid input parameter Max.Values = "+ Max.Values, ERR_INVALID_INPUT_PARAMETER));


   // (2) Chart-Legende erzeugen
   string strMaTimeframe="", strAtrTimeframe="";
   if (MA.Timeframe  != "") strMaTimeframe  = "x"+ MA.Timeframe;
   if (ATR.Timeframe != "") strAtrTimeframe = "x"+ ATR.Timeframe;
   iDescription = "Keltner Channel "+ NumberToStr(ATR.Multiplicator, ".+") +"*ATR("+ ATR.Periods + strAtrTimeframe +")  "+ MA.Method +"("+ MA.Periods +strMaTimeframe +")";
   legendLabel  = CreateLegendLabel(iDescription);
   ObjectRegister(legendLabel);


   // (3) ggf. ALMA-Gewichtungen berechnen
   if (ma.method==MODE_ALMA) /*&&*/ if (ma.periods > 1)              // ma.periods < 2 ist m�glich bei Umschalten auf zu gro�en Timeframe
      @ALMA.CalculateWeights(alma.weights, ma.periods);


   // (4.1) Bufferverwaltung
   SetIndexBuffer(Bands.MODE_UPPER, bufferUpperBand);                // sichtbar
   SetIndexBuffer(Bands.MODE_MA,    bufferMA       );                // sichtbar
   SetIndexBuffer(Bands.MODE_LOWER, bufferLowerBand);                // sichtbar

   // (4.2) Anzeigeoptionen
   string atrDescription = NumberToStr(ATR.Multiplicator, ".+") +"*ATR("+ ATR.Periods + strAtrTimeframe +")";
   IndicatorShortName("Keltner Channel "+ atrDescription);              // Context Menu
   SetIndexLabel(Bands.MODE_UPPER, "Keltner Upper "+ atrDescription);   // Tooltip und "Data Window"
   SetIndexLabel(Bands.MODE_LOWER, "Keltner Lower "+ atrDescription);
   if (Color.MA == CLR_NONE) SetIndexLabel(Bands.MODE_MA, NULL);
   else                      SetIndexLabel(Bands.MODE_MA, "Keltner Channel "+ MA.Method +"("+ MA.Periods + strMaTimeframe + ")");
   IndicatorDigits(SubPipDigits);

   // (4.3) Zeichenoptionen
   int startDraw = Max(ma.periods-1, Bars-ifInt(Max.Values < 0, Bars, Max.Values)) + Shift.Horizontal.Bars;
   SetIndexDrawBegin(Bands.MODE_UPPER, startDraw); SetIndexShift(Bands.MODE_UPPER, Shift.Horizontal.Bars);
   SetIndexDrawBegin(Bands.MODE_MA,    startDraw); SetIndexShift(Bands.MODE_MA,    Shift.Horizontal.Bars);
   SetIndexDrawBegin(Bands.MODE_LOWER, startDraw); SetIndexShift(Bands.MODE_LOWER, Shift.Horizontal.Bars);

   shift.vertical = Shift.Vertical.Pips * Pips;                      // TODO: Digits/Point-Fehler abfangen

   // (4.4) Styles
   @Bands.SetIndicatorStyles(Color.MA, Color.Bands);                 // Workaround um diverse Terminalbugs (siehe dort)

   return(catch("onInit(13)"));
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
 *
 * @throws ERS_TERMINAL_NOT_YET_READY
 */
int onTick() {
   // Abschlu� der Buffer-Initialisierung �berpr�fen
   if (ArraySize(bufferUpperBand) == 0)                              // kann bei Terminal-Start auftreten
      return(debug("onTick(1)  size(bufferUpperBand) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // vor kompletter Neuberechnung Buffer zur�cksetzen
   if (!ValidBars) {
      ArrayInitialize(bufferUpperBand, EMPTY_VALUE);
      ArrayInitialize(bufferMA,        EMPTY_VALUE);
      ArrayInitialize(bufferLowerBand, EMPTY_VALUE);
      @Bands.SetIndicatorStyles(Color.MA, Color.Bands);              // Workaround um diverse Terminalbugs (siehe dort)
   }

   if (ma.periods < 2)                                               // Abbruch bei ma.periods < 2 (m�glich bei Umschalten auf zu gro�en Timeframe)
      return(NO_ERROR);


   // (1) Startbar der Berechnung ermitteln
   if (ChangedBars > Max.Values) /*&&*/ if (Max.Values >= 0)
      ChangedBars = Max.Values;
   int startBar = Min(ChangedBars-1, Bars-ma.periods);
   if (startBar < 0) {
      if (IsSuperContext())
         return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));
      SetLastError(ERR_HISTORY_INSUFFICIENT);                        // Signalisieren, falls Bars f�r Berechnung nicht ausreichen (keine R�ckkehr)
   }


   // (2) ung�ltige Bars neuberechnen
   if (ma.method <= MODE_LWMA) {
      double atr;
      for (int bar=startBar; bar >= 0; bar--) {
         bufferMA       [bar] = iMA(NULL, NULL, ma.periods, 0, ma.method, ma.appliedPrice, bar) + shift.vertical;
         atr                  = iATR(NULL, atr.timeframe, ATR.Periods, bar) * ATR.Multiplicator;
         bufferUpperBand[bar] = bufferMA[bar] + atr;
         bufferLowerBand[bar] = bufferMA[bar] - atr;
      }
   }
   else if (ma.method == MODE_ALMA) {
      RecalcALMAChannel(startBar);
   }


   // (3) Legende aktualisieren
   @Bands.UpdateLegend(legendLabel, iDescription, Color.Bands, bufferUpperBand[0], bufferLowerBand[0]);
   return(last_error);
}


/**
 * Berechnet die ung�ltigen Bars eines ALMA-basierten Keltner Channels neu.
 *
 * @param  int startBar
 *
 * @return bool - Erfolgsstatus
 */
bool RecalcALMAChannel(int startBar) {
   double atr;

   for (int i, j, bar=startBar; bar >= 0; bar--) {
      bufferMA[bar] = shift.vertical;
      for (i=0; i < ma.periods; i++) {
         bufferMA[bar] += alma.weights[i] * iMA(NULL, NULL, 1, 0, MODE_SMA, ma.appliedPrice, bar+i);
      }
      atr                  = iATR(NULL, atr.timeframe, ATR.Periods, bar) * ATR.Multiplicator;
      bufferUpperBand[bar] = bufferMA[bar] + atr;
      bufferLowerBand[bar] = bufferMA[bar] - atr;
   }
   return(!catch("RecalcALMAChannel()"));
}


/**
 * String-Repr�sentation der Input-Parameter f�rs Logging bei Aufruf durch iCustom().
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("init()  inputs: ",

                            "MA.Periods=\"",          MA.Periods                           , "\"; ",
                            "MA.Timeframe=\"",        MA.Timeframe                         , "\"; ",
                            "MA.Method=\"",           MA.Method                            , "\"; ",
                            "MA.AppliedPrice=\"",     MA.AppliedPrice                      , "\"; ",

                            "ATR.Periods=",           ATR.Periods                          , "; ",
                            "ATR.Timeframe=\"",       ATR.Timeframe                        , "\"; ",
                            "ATR.Multiplicator=",     NumberToStr(ATR.Multiplicator, ".1+"), "\"; ",

                            "Color.Bands=",           ColorToStr(Color.Bands)              , "; ",
                            "Color.MA=",              ColorToStr(Color.MA)                 , "; ",

                            "Max.Values=",            Max.Values                           , "; ",
                            "Shift.Vertical.Pips=",   Shift.Vertical.Pips                  , "; ",
                            "Shift.Horizontal.Bars=", Shift.Horizontal.Bars                , "; ")
   );
}
