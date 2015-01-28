/**
 * Globale Konstanten, Variablen und Funktionen
 */
#include <stderror.mqh>
#include <structs/sizes.mqh>


// globale Variablen, stehen �berall zur Verf�gung
int      __ExecutionContext[EXECUTION_CONTEXT.intSize];     // aktueller ExecutionContext
//int    __lpSuperContext;                                  // Zeiger auf ggf. existierenden SuperContext (wird je Modultyp definiert)

string   __NAME__;                                          // Name des aktuellen Programms
int      __WHEREAMI__;                                      // ID der aktuell ausgef�hrten MQL-Rootfunktion: FUNC_INIT | FUNC_START | FUNC_DEINIT
bool     IsChart;                                           // ob ein Chart existiert (z.B. nicht bei VisualMode=Off oder Optimization=On)
bool     IsOfflineChart;                                    // ob der Chart ein Offline-Chart ist
bool     __LOG;                                             // ob das Logging aktiviert ist
bool     __LOG_CUSTOM;                                      // ob ein eigenes Logfile benutzt wird
int        LOG_LEVEL;                                       // TODO: der konfigurierte Loglevel
bool     __SMS.alerts;                                      // ob SMS-Benachrichtigungen aktiviert sind
string   __SMS.receiver;                                    // Empf�nger-Nr. f�r SMS-Benachrichtigungen

bool     __STATUS_TERMINAL_NOT_READY;                       // Terminal noch nicht bereit
bool     __STATUS_HISTORY_UPDATE;                           // History-Update wurde getriggert
bool     __STATUS_HISTORY_INSUFFICIENT;                     // History ist oder war nicht ausreichend
bool     __STATUS_RELAUNCH_INPUT;                           // Anforderung, Input-Dialog erneut zu laden
bool     __STATUS_INVALID_INPUT;                            // ung�ltige Parametereingabe im Input-Dialog
bool     __STATUS_OFF;                                      // Programm komplett abgebrochen (switched off)
int      __STATUS_OFF.reason;                               // Ursache f�r Programmabbruch: Fehlercode (kann, mu� aber nicht gesetzt sein)


double   Pip, Pips;                                         // Betrag eines Pips des aktuellen Symbols (z.B. 0.0001 = Pip-Size)
int      PipDigits, SubPipDigits;                           // Digits eines Pips/Subpips des aktuellen Symbols (Annahme: Pips sind gradzahlig)
int      PipPoint, PipPoints;                               // Aufl�sung eines Pips des aktuellen Symbols (Anzahl der Punkte auf der Dezimalskala je Pip)
double   TickSize;                                          // kleinste �nderung des Preises des aktuellen Symbols je Tick (Vielfaches von Point)
string   PriceFormat, PipPriceFormat, SubPipPriceFormat;    // Preisformate des aktuellen Symbols f�r NumberToStr()
int      Tick;
datetime Tick.Time;
datetime Tick.prevTime;
int      ValidBars;
int      ChangedBars;

int      prev_error;                                        // der letzte Fehler des vorherigen start()-Aufrufs des Programms
int      last_error;                                        // der letzte Fehler des aktuellen start()-Aufrufs des Programms


// Special constants
#define NULL                        0
#define INT_MIN            0x80000000                       // kleinster negativer Integer-Value: -2147483648                              (datetime) INT_MIN = '1901-12-13 20:45:52'
#define INT_MAX            0x7FFFFFFF                       // gr��ter positiver Integer-Value:    2147483647                              (datetime) INT_MAX = '2038-01-19 03:14:07'
#define NaT                   INT_MIN                       // Not-a-Time = ung�ltiger DateTime-Value, f�r die eingebauten MQL-Funktionen gilt: min(datetime) = '1970-01-01 00:00:00'
#define EMPTY_VALUE           INT_MAX                       // empty custom indicator value (Integer, kein Double)                              max(datetime) = '2037-12-31 23:59:59'
#define EMPTY                      -1
#define CLR_NONE                   -1                       // no color
#define WHOLE_ARRAY                 0
#define MAX_SYMBOL_LENGTH          11
#define MAX_STRING_LITERAL          "..............................................................................................................................................................................................................................................................."
#define MAX_PATH                  260                       // for example the maximum path on drive D is "D:\some-256-characters-path-string<NUL>"
#define NL                          "\n"                    // new line (MQL schreibt 0x0D0A)
#define TAB                         "\t"                    // tab


// Log level
#define L_OFF                 INT_MIN                       // Tests umgekehrt zu log4j mit: if (LOG_LEVEL >= Event)
#define L_FATAL                 10000
#define L_ERROR                 20000
#define L_WARN                  30000
#define L_INFO                  40000
#define L_DEBUG                 50000
#define L_ALL                 INT_MAX


// Magic characters
#define PLACEHOLDER_NUL_CHAR        '�'                     // 0x85 - Platzhalter zur Visualisierung von NUL-Bytes in Strings,          siehe BufferToStr()
#define PLACEHOLDER_CTL_CHAR        '�'                     // 0x95 - Platzhalter zur Visualisierung von Control-Characters in Strings, siehe BufferToStr()


// Mathematische Konstanten
#define Math.PI                     3.1415926535897932384   // intern 15 korrekte Dezimalstellen


// Zeitkonstanten
#define SECOND                      1
#define MINUTE                     60  //  60 Sekunden
#define HOUR                     3600  //  60 Minuten
#define DAY                     86400  //  24 Stunden
#define WEEK                   604800  //   7 Tage
#define MONTH                 2678400  //  31 Tage                      // Die Werte sind auf das jeweilige Maximum ausgelegt, soda�
#define QUARTER               8035200  //   3 Monate (3 x 31 Tage)      // bei Datumsarithmetik immer ein Wechsel in die jeweils n�chste
#define YEAR                 31622400  // 366 Tage                      // Periode garantiert ist.

#define SECONDS                SECOND
#define MINUTES                MINUTE
#define HOURS                    HOUR
#define DAYS                      DAY
#define WEEKS                    WEEK
#define MONTHS                  MONTH
#define QUARTERS              QUARTER
#define YEARS                    YEAR


// Wochentage, wie von DayOfWeek() und TimeDayOfWeek() zur�ckgegeben
#define SUNDAY                      0
#define MONDAY                      1
#define TUESDAY                     2
#define WEDNESDAY                   3
#define THURSDAY                    4
#define FRIDAY                      5
#define SATURDAY                    6

#define SUN                    SUNDAY
#define MON                    MONDAY
#define TUE                   TUESDAY
#define WED                 WEDNESDAY
#define THU                  THURSDAY
#define FRI                    FRIDAY
#define SAT                  SATURDAY


// Monate, wie von Month() und TimeMonth() zur�ckgegeben
#define JANUARY                     1
#define FEBRUARY                    2
#define MARCH                       3
#define APRIL                       4
#define MAY                         5
#define JUNE                        6
#define JULY                        7
#define AUGUST                      8
#define SEPTEMBER                   9
#define OCTOBER                    10
#define NOVEMBER                   11
#define DECEMBER                   12

#define JAN                   JANUARY
#define FEB                  FEBRUARY
#define MAR                     MARCH
#define APR                     APRIL
#define MAY                       MAY
#define JUN                      JUNE
#define JUL                      JULY
#define AUG                    AUGUST
#define SEP                 SEPTEMBER
#define OCT                   OCTOBER
#define NOV                  NOVEMBER
#define DEC                  DECEMBER


// Account-Types
#define ACCOUNT_TYPE_DEMO           1
#define ACCOUNT_TYPE_REAL           2


// Time-Flags, siehe TimeToStr()
#define TIME_DATE                   1
#define TIME_MINUTES                2
#define TIME_SECONDS                4
#define TIME_FULL                   7           // TIME_DATE | TIME_MINUTES | TIME_SECONDS


// Timeframe-Identifier, siehe Period()
#define PERIOD_M1                   1           // 1 Minute
#define PERIOD_M5                   5           // 5 Minuten
#define PERIOD_M15                 15           // 15 Minuten
#define PERIOD_M30                 30           // 30 Minuten
#define PERIOD_H1                  60           // 1 Stunde
#define PERIOD_H4                 240           // 4 Stunden
#define PERIOD_D1                1440           // 1 Tag
#define PERIOD_W1               10080           // 1 Woche (7 Tage)
#define PERIOD_MN1              43200           // 1 Monat (30 Tage)
#define PERIOD_Q1              129600           // 1 Quartal (3 Monate)


// Arrayindizes f�r Timezone-Transitionsdaten
#define I_TRANSITION_TIME           0
#define I_TRANSITION_OFFSET         1
#define I_TRANSITION_DST            2


// MQL Moduletyp-Flags
#define T_INDICATOR                 1
#define T_EXPERT                    2
#define T_SCRIPT                    4
#define T_LIBRARY                   8


// MQL Root-Funktion-ID's (siehe __WHEREAMI__)
#define FUNC_INIT                   1
#define FUNC_START                  2
#define FUNC_DEINIT                 3


// init()-Flags
#define INIT_TIMEZONE               1           // stellt eine korrekte Timezone-Konfiguration sicher
#define INIT_PIPVALUE               2           // stellt sicher, da� der aktuelle PipValue berechnet werden kann (ben�tigt TickSize und TickValue)
#define INIT_BARS_ON_HIST_UPDATE    4           //
#define INIT_CUSTOMLOG              8           // das Programm verwendet ein eigenes Logfile


// Chart-Property-Flags
#define CP_CHART                    1           // impliziert VisualMode=On
#define CP_OFFLINE                  2           // nur in Verbindung mit CP_CHART gesetzt
#define CP_OFFLINE_CHART            3           // kurz f�r: CP_OFFLINE|CP_CHART


// Object property ids, siehe ObjectSet()
#define OBJPROP_TIME1               0
#define OBJPROP_PRICE1              1
#define OBJPROP_TIME2               2
#define OBJPROP_PRICE2              3
#define OBJPROP_TIME3               4
#define OBJPROP_PRICE3              5
#define OBJPROP_COLOR               6
#define OBJPROP_STYLE               7
#define OBJPROP_WIDTH               8
#define OBJPROP_BACK                9
#define OBJPROP_RAY                10
#define OBJPROP_ELLIPSE            11
#define OBJPROP_SCALE              12
#define OBJPROP_ANGLE              13
#define OBJPROP_ARROWCODE          14
#define OBJPROP_TIMEFRAMES         15
#define OBJPROP_DEVIATION          16
#define OBJPROP_FONTSIZE          100
#define OBJPROP_CORNER            101
#define OBJPROP_XDISTANCE         102
#define OBJPROP_YDISTANCE         103
#define OBJPROP_FIBOLEVELS        200
#define OBJPROP_LEVELCOLOR        201
#define OBJPROP_LEVELSTYLE        202
#define OBJPROP_LEVELWIDTH        203
#define OBJPROP_FIRSTLEVEL0       210
#define OBJPROP_FIRSTLEVEL1       211
#define OBJPROP_FIRSTLEVEL2       212
#define OBJPROP_FIRSTLEVEL3       213
#define OBJPROP_FIRSTLEVEL4       214
#define OBJPROP_FIRSTLEVEL5       215
#define OBJPROP_FIRSTLEVEL6       216
#define OBJPROP_FIRSTLEVEL7       217
#define OBJPROP_FIRSTLEVEL8       218
#define OBJPROP_FIRSTLEVEL9       219
#define OBJPROP_FIRSTLEVEL10      220
#define OBJPROP_FIRSTLEVEL11      221
#define OBJPROP_FIRSTLEVEL12      222
#define OBJPROP_FIRSTLEVEL13      223
#define OBJPROP_FIRSTLEVEL14      224
#define OBJPROP_FIRSTLEVEL15      225
#define OBJPROP_FIRSTLEVEL16      226
#define OBJPROP_FIRSTLEVEL17      227
#define OBJPROP_FIRSTLEVEL18      228
#define OBJPROP_FIRSTLEVEL19      229
#define OBJPROP_FIRSTLEVEL20      230
#define OBJPROP_FIRSTLEVEL21      231
#define OBJPROP_FIRSTLEVEL22      232
#define OBJPROP_FIRSTLEVEL23      233
#define OBJPROP_FIRSTLEVEL24      234
#define OBJPROP_FIRSTLEVEL25      235
#define OBJPROP_FIRSTLEVEL26      236
#define OBJPROP_FIRSTLEVEL27      237
#define OBJPROP_FIRSTLEVEL28      238
#define OBJPROP_FIRSTLEVEL29      239
#define OBJPROP_FIRSTLEVEL30      240
#define OBJPROP_FIRSTLEVEL31      241


// Object visibility flags, siehe ObjectSet(label, OBJPROP_TIMEFRAMES, ...)
#define OBJ_PERIOD_M1          0x0001           //   1: object is shown on 1-minute charts
#define OBJ_PERIOD_M5          0x0002           //   2: object is shown on 5-minute charts
#define OBJ_PERIOD_M15         0x0004           //   4: object is shown on 15-minute charts
#define OBJ_PERIOD_M30         0x0008           //   8: object is shown on 30-minute charts
#define OBJ_PERIOD_H1          0x0010           //  16: object is shown on 1-hour charts
#define OBJ_PERIOD_H4          0x0020           //  32: object is shown on 4-hour charts
#define OBJ_PERIOD_D1          0x0040           //  64: object is shown on daily charts
#define OBJ_PERIOD_W1          0x0080           // 128: object is shown on weekly charts
#define OBJ_PERIOD_MN1         0x0100           // 256: object is shown on monthly charts
#define OBJ_PERIODS_ALL        0x01FF           // 511: object is shown on all timeframes: {M1 | M5 | M15 | M30 | H1 | H4 | D1 | W1  | MN1}
#define OBJ_PERIODS_NONE       EMPTY            //  -1: object is hidden on all timeframes
#define OBJ_ALL_PERIODS        OBJ_PERIODS_ALL  // MetaQuotes-Alias (zus�tzlich hat NULL denselben Effekt wie OBJ_PERIODS_ALL)


// Timeframe-Flags, siehe EventListener.Baropen()
#define F_PERIOD_M1            OBJ_PERIOD_M1    //    1
#define F_PERIOD_M5            OBJ_PERIOD_M5    //    2
#define F_PERIOD_M15           OBJ_PERIOD_M15   //    4
#define F_PERIOD_M30           OBJ_PERIOD_M30   //    8
#define F_PERIOD_H1            OBJ_PERIOD_H1    //   16
#define F_PERIOD_H4            OBJ_PERIOD_H4    //   32
#define F_PERIOD_D1            OBJ_PERIOD_D1    //   64
#define F_PERIOD_W1            OBJ_PERIOD_W1    //  128
#define F_PERIOD_MN1           OBJ_PERIOD_MN1   //  256
#define F_PERIOD_Q1            0x200            //  512
#define F_PERIODS_ALL          0x3FF            // 1023: {M1 | M5 | M15 | M30 | H1 | H4 | D1 | W1  | MN1 | Q1}
#define F_ALL_PERIODS          F_PERIODS_ALL


// Array-Indizes f�r Timeframe-Operationen
#define I_PERIOD_M1            0
#define I_PERIOD_M5            1
#define I_PERIOD_M15           2
#define I_PERIOD_M30           3
#define I_PERIOD_H1            4
#define I_PERIOD_H4            5
#define I_PERIOD_D1            6
#define I_PERIOD_W1            7
#define I_PERIOD_MN1           8
#define I_PERIOD_Q1            9


// Operation-Types, siehe OrderType()
#define OP_UNDEFINED                  -1        // custom: Default-Wert f�r nicht initialisierte Variable
#define OP_BUY                         0        // long position
#define OP_LONG                   OP_BUY
#define OP_SELL                        1        // short position
#define OP_SHORT                 OP_SELL
#define OP_BUYLIMIT                    2        // buy limit order
#define OP_SELLLIMIT                   3        // sell limit order
#define OP_BUYSTOP                     4        // stop buy order
#define OP_SELLSTOP                    5        // stop sell order
#define OP_BALANCE                     6        // account debit or credit transaction
#define OP_CREDIT                      7        // margin credit facility (no transaction)
#define OP_TRANSFER                    8        // custom: OP_BALANCE initiiert durch Kunden (Ein-/Auszahlung)
#define OP_VENDOR                      9        // custom: OP_BALANCE initiiert durch Criminal (Swap, sonstiges)


// OrderSelect-ID's zur Steuerung des Stacks der Orderkontexte, siehe OrderPush(), OrderPop() etc.
#define O_PUSH                         1
#define O_POP                          2


// Series array identifier, siehe ArrayCopySeries(), iLowest(), iHighest()
#define MODE_OPEN                      0        // open price
#define MODE_LOW                       1        // low price
#define MODE_HIGH                      2        // high price
#define MODE_CLOSE                     3        // close price
#define MODE_VOLUME                    4        // volume
#define MODE_TIME                      5        // bar open time


// MA method identifiers, siehe iMA()
#define MODE_SMA                       0        // simple moving average
#define MODE_EMA                       1        // exponential moving average
#define MODE_LWMA                      3        // linear weighted moving average
#define MODE_ALMA                      4        // Arnaud Legoux moving average


// Indicator line identifiers, siehe iMACD(), iRVI(), iStochastic()
#define MODE_MAIN                      0        // base indicator line
#define MODE_SIGNAL                    1        // signal line


// Indicator line identifiers, siehe iADX()
#define MODE_MAIN                      0        // base indicator line
#define MODE_PLUSDI                    1        // +DI indicator line
#define MODE_MINUSDI                   2        // -DI indicator line


// Indicator line identifiers, siehe iBands(), iEnvelopes(), iEnvelopesOnArray(), iFractals(), iGator()
#define MODE_UPPER                     1        // upper line
#define MODE_LOWER                     2        // lower line

#define B_LOWER                        0        // custom
#define B_UPPER                        1        // custom


// Indicator drawing shapes
#define DRAW_LINE                      0        // drawing line
#define DRAW_SECTION                   1        // drawing sections
#define DRAW_HISTOGRAM                 2        // drawing histogram
#define DRAW_ARROW                     3        // drawing arrows (symbols)
#define DRAW_ZIGZAG                    4        // drawing sections between even and odd indicator buffers
#define DRAW_NONE                     12        // no drawing


// Indicator line styles
#define STYLE_SOLID                    0        // pen is solid
#define STYLE_DASH                     1        // pen is dashed
#define STYLE_DOT                      2        // pen is dotted
#define STYLE_DASHDOT                  3        // pen has alternating dashes and dots
#define STYLE_DASHDOTDOT               4        // pen has alternating dashes and double dots


// Indicator buffer identifiers zur Verwendung mit iCustom()
#define BUFFER_INDEX_0                 0        // allgemein g�ltige ID's
#define BUFFER_INDEX_1                 1
#define BUFFER_INDEX_2                 2
#define BUFFER_INDEX_3                 3
#define BUFFER_INDEX_4                 4
#define BUFFER_INDEX_5                 5
#define BUFFER_INDEX_6                 6
#define BUFFER_INDEX_7                 7
#define BUFFER_1          BUFFER_INDEX_0
#define BUFFER_2          BUFFER_INDEX_1
#define BUFFER_3          BUFFER_INDEX_2
#define BUFFER_4          BUFFER_INDEX_3
#define BUFFER_5          BUFFER_INDEX_4
#define BUFFER_6          BUFFER_INDEX_5
#define BUFFER_7          BUFFER_INDEX_6
#define BUFFER_8          BUFFER_INDEX_7

#define MovingAverage.MODE_MA          0        // Wert des MA's
#define MovingAverage.MODE_TREND       1        // Trend des MA's

#define Bands.MODE_UPPER               0        // oberes Band
#define Bands.MODE_MAIN                1        // Basislinie
#define Bands.MODE_MA    Bands.MODE_MAIN        //
#define Bands.MODE_LOWER               2        // unteres Band


// EXECUTION_CONTEXT Array-Indizes
#define EC_SIGNATURE                   0
#define EC_LPNAME                      1
#define EC_TYPE                        2
#define EC_CHART_PROPERTIES            3
#define EC_LPSUPER_CONTEXT             4
#define EC_INIT_FLAGS                  5
#define EC_DEINIT_FLAGS                6
#define EC_UNINITIALIZE_REASON         7
#define EC_WHEREAMI                    8
#define EC_LOGGING                     9
#define EC_LPLOGFILE                  10
#define EC_LAST_ERROR                 11


// Sorting modes, siehe ArraySort()
#define MODE_ASC                       1        // aufsteigend
#define MODE_DESC                      2        // absteigend
#define MODE_ASCEND             MODE_ASC        // MetaQuotes-Aliasse
#define MODE_DESCEND           MODE_DESC


// Market info identifiers, siehe MarketInfo()
#define MODE_LOW                       1        // session low price (since midnight server time)
#define MODE_HIGH                      2        // session high price (since midnight server time)
//                                     3        // ???
//                                     4        // ???
#define MODE_TIME                      5        // last tick time
//                                     6        // ???
//                                     7        // ???
//                                     8        // ???
#define MODE_BID                       9        // last bid price                       (entspricht Bid bzw. Close[0])
#define MODE_ASK                      10        // last ask price                       (entspricht Ask)
#define MODE_POINT                    11        // point size in the quote currency     (entspricht Point)                                               0.0000'1
#define MODE_DIGITS                   12        // number of digits after decimal point (entspricht Digits)
#define MODE_SPREAD                   13        // spread value in points
#define MODE_STOPLEVEL                14        // stop level in points
#define MODE_LOTSIZE                  15        // unit size of 1 lot                                                                                    100.000
#define MODE_TICKVALUE                16        // tick value in the deposit currency
#define MODE_TICKSIZE                 17        // tick size in the quote currency                                                                       0.0000'5
#define MODE_SWAPLONG                 18        // swap of long positions
#define MODE_SWAPSHORT                19        // swap of short positions
#define MODE_STARTING                 20        // contract starting date (usually for futures)
#define MODE_EXPIRATION               21        // contract expiration date (usually for futures)
#define MODE_TRADEALLOWED             22        // if trading is allowed for the symbol
#define MODE_MINLOT                   23        // minimum lot size
#define MODE_LOTSTEP                  24        // minimum lot increment size
#define MODE_MAXLOT                   25        // maximum lot size
#define MODE_SWAPTYPE                 26        // swap calculation method: 0 - in points; 1 - in base currency; 2 - by interest; 3 - in margin currency
#define MODE_PROFITCALCMODE           27        // profit calculation mode: 0 - Forex; 1 - CFD; 2 - Futures
#define MODE_MARGINCALCMODE           28        // margin calculation mode: 0 - Forex; 1 - CFD; 2 - Futures; 3 - CFD for indices
#define MODE_MARGININIT               29        // units with margin requirement for opening a position of 1 lot (0 = entsprechend MODE_MARGINREQUIRED)  100.000  @see (1)
#define MODE_MARGINMAINTENANCE        30        // margin to maintain an open positions of 1 lot                 (0 = je nach Account-Stopoutlevel)               @see (2)
#define MODE_MARGINHEDGED             31        // units with margin maintenance requirement for a hedged position of 1 lot                               50.000
#define MODE_MARGINREQUIRED           32        // free margin requirement to open a position of 1 lot
#define MODE_FREEZELEVEL              33        // order freeze level in points
                                                //
                                                // (1) MARGIN_INIT (in Units) m��te, wenn es gesetzt ist, die eigentliche Marginrate sein. MARGIN_REQUIRED (in Account-Currency)
                                                //     k�nnte h�her und MARGIN_MAINTENANCE niedriger sein (MARGIN_INIT wird z.B. von IC Markets gesetzt).
                                                //
                                                // (2) Ein Account-Stopoutlevel < 100% ist gleichbedeutend mit einem einheitlichen MARGIN_MAINTENANCE < MARGIN_INIT �ber alle
                                                //     Instrumente. Eine vom Stopoutlevel des Accounts abweichende MARGIN_MAINTENANCE einzelner Instrumente ist vermutlich nur
                                                //     bei einem Stopoutlevel von 100% sinnvoll. Beides zusammen ist ziemlich verwirrend.

// Price identifiers, siehe iMA() etc.
#define PRICE_CLOSE                    0        // C
#define PRICE_OPEN                     1        // O
#define PRICE_HIGH                     2        // H
#define PRICE_LOW                      3        // L
#define PRICE_MEDIAN                   4        // (H+L)/2
#define PRICE_TYPICAL                  5        // (H+L+C)/3
#define PRICE_WEIGHTED                 6        // (H+L+C+C)/4
#define PRICE_BID                      7        // Bid
#define PRICE_ASK                      8        // Ask


// Rates array identifier, siehe ArrayCopyRates()
#define I_RATE_TIME                    0        // bar open time
#define I_RATE_OPEN                    1        // open price
#define I_RATE_LOW                     2        // low price
#define I_RATE_HIGH                    3        // high price
#define I_RATE_CLOSE                   4        // close price
#define I_RATE_VOLUME                  5        // volume

#define I_BAR_TIME           I_RATE_TIME
#define I_BAR_OPEN           I_RATE_OPEN
#define I_BAR_LOW             I_RATE_LOW
#define I_BAR_HIGH           I_RATE_HIGH
#define I_BAR_CLOSE         I_RATE_CLOSE
#define I_BAR_VOLUME       I_RATE_VOLUME


// Event-Identifier
#define EVENT_BAR_OPEN            0x0001
#define EVENT_ORDER_PLACE         0x0002
#define EVENT_ORDER_CHANGE        0x0004
#define EVENT_ORDER_CANCEL        0x0008
#define EVENT_ACCOUNT_CHANGE      0x0040
#define EVENT_ACCOUNT_PAYMENT     0x0080        // Ein- oder Auszahlung
#define EVENT_CHART_CMD           0x0100        // Chart-Command             (aktueller Chart)
#define EVENT_INTERNAL_CMD        0x0200        // terminal-internes Command (globale Variablen)
#define EVENT_EXTERNAL_CMD        0x0400        // externes Command          (QuickChannel)


// Array-Identifier zum Zugriff auf verschiedene Pivotlevel, siehe iPivotLevel()
#define PIVOT_R3                       0
#define PIVOT_R2                       1
#define PIVOT_R1                       2
#define PIVOT_PP                       3
#define PIVOT_S1                       4
#define PIVOT_S2                       5
#define PIVOT_S3                       6


// Konstanten zum Zugriff auf die in CSV-Dateien gespeicherte Accounthistory
#define AH_COLUMNS                    20
#define I_AH_TICKET                    0
#define I_AH_OPENTIME                  1
#define I_AH_OPENTIMESTAMP             2
#define I_AH_TYPEDESCRIPTION           3
#define I_AH_TYPE                      4
#define I_AH_SIZE                      5
#define I_AH_SYMBOL                    6
#define I_AH_OPENPRICE                 7
#define I_AH_STOPLOSS                  8
#define I_AH_TAKEPROFIT                9
#define I_AH_CLOSETIME                10
#define I_AH_CLOSETIMESTAMP           11
#define I_AH_CLOSEPRICE               12
#define I_AH_MAGICNUMBER              13
#define I_AH_COMMISSION               14
#define I_AH_SWAP                     15
#define I_AH_NETPROFIT                16
#define I_AH_GROSSPROFIT              17
#define I_AH_BALANCE                  18
#define I_AH_COMMENT                  19


// Margin calculation modes, siehe MarketInfo(symbol, MODE_MARGINCALCMODE)
#define MCM_FOREX                      0
#define MCM_CFD                        1
#define MCM_CFDFUTURES                 2
#define MCM_CFDINDEX                   3
#define MCM_CFDLEVERAGE                4        // siehe MQL5


// Swap calculation modes, siehe MarketInfo(symbol, MODE_SWAPTYPE): jeweils per Lot und Tag
#define SCM_POINTS                     0        // in points of quote currency
#define SCM_BASE_CURRENCY              1        // as amount of base currency   (see "symbols.raw")
#define SCM_INTEREST                   2
#define SCM_MARGIN_CURRENCY            3        // as amount of margin currency (see "symbols.raw")


// Profit calculation modes, siehe MarketInfo(symbol, MODE_PROFITCALCMODE)
#define PCM_FOREX                      0
#define PCM_CFD                        1
#define PCM_FUTURES                    2


// Account stopout modes, siehe AccountStopoutMode()
#define ASM_PERCENT                    0
#define ASM_ABSOLUTE                   1


// ID's zur Objektpositionierung, siehe ObjectSet(label, OBJPROP_CORNER,  int)
#define CORNER_TOP_LEFT                0        // default
#define CORNER_TOP_RIGHT               1
#define CORNER_BOTTOM_LEFT             2
#define CORNER_BOTTOM_RIGHT            3


// UninitializeReason-Codes                                                                    // MQL5: builds > 509
#define REASON_UNDEFINED               0        // no uninitialize reason                      // = REASON_PROGRAM: EA terminated by ExpertRemove()
#define REASON_REMOVE                  1        // program removed from chart                  //
#define REASON_RECOMPILE               2        // program recompiled                          //
#define REASON_CHARTCHANGE             3        // chart symbol or timeframe changed           //
#define REASON_CHARTCLOSE              4        // chart closed or template changed            // chart closed
#define REASON_PARAMETERS              5        // input parameters changed                    //
#define REASON_ACCOUNT                 6        // account changed                             // account or account settings changed
#define REASON_TEMPLATE                7        // n/a                                         // template changed
#define REASON_INITFAILED              8        // n/a                                         // OnInit() returned with an error
#define REASON_CLOSE                   9        // n/a                                         // terminal closed


// InitReason-Codes
#define INIT_REASON_USER               1
#define INIT_REASON_TEMPLATE           2
#define INIT_REASON_PROGRAM            3
#define INIT_REASON_PROGRAM_CLEARTEST  4
#define INIT_REASON_PARAMETERS         5
#define INIT_REASON_TIMEFRAMECHANGE    6
#define INIT_REASON_SYMBOLCHANGE       7
#define INIT_REASON_RECOMPILE          8


// Currency-ID's
#define CID_AUD                        1
#define CID_CAD                        2
#define CID_CHF                        3
#define CID_EUR                        4
#define CID_GBP                        5
#define CID_JPY                        6
#define CID_NZD                        7
#define CID_USD                        8        // zuerst die ID's der LFX-Indizes, dadurch "passen" diese in 3 Bits (f�r LFX-Basket)

#define CID_CNY                        9
#define CID_CZK                       10
#define CID_DKK                       11
#define CID_HKD                       12
#define CID_HRK                       13
#define CID_HUF                       14
#define CID_INR                       15
#define CID_LTL                       16
#define CID_LVL                       17
#define CID_MXN                       18
#define CID_NOK                       19
#define CID_PLN                       20
#define CID_RUB                       21
#define CID_SAR                       22
#define CID_SEK                       23
#define CID_SGD                       24
#define CID_THB                       25
#define CID_TRY                       26
#define CID_TWD                       27
#define CID_ZAR                       28


// Currency-K�rzel
#define C_AUD                   "AUD"
#define C_CAD                   "CAD"
#define C_CHF                   "CHF"
#define C_CNY                   "CNY"
#define C_CZK                   "CZK"
#define C_DKK                   "DKK"
#define C_EUR                   "EUR"
#define C_GBP                   "GBP"
#define C_HKD                   "HKD"
#define C_HRK                   "HRK"
#define C_HUF                   "HUF"
#define C_INR                   "INR"
#define C_JPY                   "JPY"
#define C_LTL                   "LTL"
#define C_LVL                   "LVL"
#define C_MXN                   "MXN"
#define C_NOK                   "NOK"
#define C_NZD                   "NZD"
#define C_PLN                   "PLN"
#define C_RUB                   "RUB"
#define C_SAR                   "SAR"
#define C_SEK                   "SEK"
#define C_SGD                   "SGD"
#define C_USD                   "USD"
#define C_THB                   "THB"
#define C_TRY                   "TRY"
#define C_TWD                   "TWD"
#define C_ZAR                   "ZAR"


// FileOpen() modes
#define FILE_READ                   1
#define FILE_WRITE                  2
#define FILE_BIN                    4
#define FILE_CSV                    8


// Data types, siehe FileRead()/FileWrite()
#define CHAR_VALUE                  1                    // integer: 1 byte
#define SHORT_VALUE                 2                    // integer: 2 bytes
#define LONG_VALUE                  4                    // integer: 4 bytes (default)
#define FLOAT_VALUE                 4                    // float:   4 bytes
#define DOUBLE_VALUE                8                    // float:   8 bytes (default)


// FindFileNames() flags
#define FF_SORT                     1                    // Ergebnisse von NTFS-Laufwerken sind immer sortiert
#define FF_DIRSONLY                 2
#define FF_FILESONLY                4


// Flag zum Schreiben von Historyfiles
#define HST_CACHE_TICKS             1
#define HST_FILL_GAPS               2


// MessageBox() flags
#define MB_OK                       0x00000000        // buttons
#define MB_OKCANCEL                 0x00000001
#define MB_YESNO                    0x00000004
#define MB_YESNOCANCEL              0x00000003
#define MB_ABORTRETRYIGNORE         0x00000002
#define MB_CANCELTRYCONTINUE        0x00000006
#define MB_RETRYCANCEL              0x00000005
#define MB_HELP                     0x00004000        // additional help button

#define MB_DEFBUTTON1               0x00000000        // default button
#define MB_DEFBUTTON2               0x00000100
#define MB_DEFBUTTON3               0x00000200
#define MB_DEFBUTTON4               0x00000300

#define MB_ICONEXCLAMATION          0x00000030        // icons
#define MB_ICONWARNING      MB_ICONEXCLAMATION
#define MB_ICONINFORMATION          0x00000040
#define MB_ICONASTERISK     MB_ICONINFORMATION
#define MB_ICONQUESTION             0x00000020
#define MB_ICONSTOP                 0x00000010
#define MB_ICONERROR               MB_ICONSTOP
#define MB_ICONHAND                MB_ICONSTOP
#define MB_USERICON                 0x00000080

#define MB_APPLMODAL                0x00000000        // modality
#define MB_SYSTEMMODAL              0x00001000
#define MB_TASKMODAL                0x00002000

#define MB_DEFAULT_DESKTOP_ONLY     0x00020000        // other
#define MB_RIGHT                    0x00080000
#define MB_RTLREADING               0x00100000
#define MB_SETFOREGROUND            0x00010000
#define MB_TOPMOST                  0x00040000
#define MB_NOFOCUS                  0x00008000
#define MB_SERVICE_NOTIFICATION     0x00200000


// MessageBox() return codes
#define IDOK                                    1
#define IDCANCEL                                2
#define IDABORT                                 3
#define IDRETRY                                 4
#define IDIGNORE                                5
#define IDYES                                   6
#define IDNO                                    7
#define IDCLOSE                                 8
#define IDHELP                                  9
#define IDTRYAGAIN                             10
#define IDCONTINUE                             11


// Arrow-Codes, siehe ObjectSet(label, OBJPROP_ARROWCODE, value)
#define SYMBOL_ORDEROPEN                        1     // right pointing arrow (default open order marker)               // docs MetaQuotes: right pointing up arrow
//                                              2     // wie SYMBOL_ORDEROPEN                                           // docs MetaQuotes: right pointing down arrow
#define SYMBOL_ORDERCLOSE                       3     // left pointing arrow  (default closed order marker)
#define SYMBOL_DASH                             4     // dash symbol          (default takeprofit and stoploss marker)
#define SYMBOL_LEFTPRICE                        5     // left sided price label
#define SYMBOL_RIGHTPRICE                       6     // right sided price label
#define SYMBOL_THUMBSUP                        67     // thumb up symbol
#define SYMBOL_THUMBSDOWN                      68     // thumb down symbol
#define SYMBOL_ARROWUP                        241     // arrow up symbol
#define SYMBOL_ARROWDOWN                      242     // arrow down symbol
#define SYMBOL_STOPSIGN                       251     // stop sign symbol
#define SYMBOL_CHECKSIGN                      252     // check sign symbol


// MT4 internal messages
#define MT4_TICK                                2     // k�nstlicher Tick: Ausf�hrung von start()

#define MT4_LOAD_STANDARD_INDICATOR            13
#define MT4_LOAD_CUSTOM_INDICATOR              15
#define MT4_LOAD_EXPERT                        14
#define MT4_LOAD_SCRIPT                        16

#define MT4_COMPILE_REQUEST                 12345
#define MT4_COMPILE_PERMISSION              12346
#define MT4_MQL_REFRESH                     12349     // Rescan und Reload modifizierter .ex4-Files


// MT4 command ids (Men�punkte, Toolbars, Hotkeys)
#define IDC_EXPERTS_ONOFF                   33020     // Toolbar: Experts on/off                    Ctrl+E

#define IDC_CHART_REFRESH                   33324     // Chart: Refresh
#define IDC_CHART_STEPFORWARD               33197     //        eine Bar vorw�rts                      F12
#define IDC_CHART_STEPBACKWARD              33198     //        eine Bar r�ckw�rts               Shift+F12
#define IDC_CHART_EXPERT_PROPERTIES         33048     //        Expert Properties-Dialog                F7
#define IDC_CHART_OBJECTS_UNSELECTALL       35462     //        Objects: Unselect All

#define IDC_MARKETWATCH_SYMBOLS             33171     // Market Watch: Symbols

#define IDC_TESTER_TICK     IDC_CHART_STEPFORWARD     // Tester: n�chster Tick                         F12


// MT4 item ids (Fenster, Controls)
#define IDD_MDI_CLIENT                      59648     // MDI-Container (enth�lt alle Charts)
#define IDD_DOCKABLES_CONTAINER             59422     // window containing all child windows docked *inside* the main application window
#define IDD_UNDOCKED_CONTAINER              59423     // window containing one undocked/floating child window (ggf. mehrere, sind kein Top-Level-Window)

#define IDD_MARKETWATCH                        80     // Market Watch
#define IDD_MARKETWATCH_SYMBOLS             35441     // Market Watch - Symbols
#define IDD_MARKETWATCH_TICKCHART           35442     // Market Watch - Tick Chart

#define IDD_NAVIGATOR                          82     // Navigator
#define IDD_NAVIGATOR_COMMON                35439     // Navigator - Common
#define IDD_NAVIGATOR_FAVOURITES            35440     // Navigator - Favourites

#define IDD_TERMINAL                           81     // Terminal
#define IDD_TERMINAL_TRADE                  33217     // Terminal - Trade
#define IDD_TERMINAL_ACCOUNTHISTORY         33208     // Terminal - Account History
#define IDD_TERMINAL_NEWS                   33211     // Terminal - News
#define IDD_TERMINAL_ALERTS                 33206     // Terminal - Alerts
#define IDD_TERMINAL_MAILBOX                33210     // Terminal - Mailbox
#define IDD_TERMINAL_COMPANY                 4078     // Terminal - Company
#define IDD_TERMINAL_MARKET                  4081     // Terminal - Market
#define IDD_TERMINAL_SIGNALS                 1405     // Terminal - Signals
#define IDD_TERMINAL_CODEBASE               33212     // Terminal - Code Base
#define IDD_TERMINAL_EXPERTS                35434     // Terminal - Experts
#define IDD_TERMINAL_JOURNAL                33209     // Terminal - Journal

#define IDD_TESTER                             83     // Tester
#define IDD_TESTER_SETTINGS                 33215     // Tester - Settings
#define IDC_TESTER_PAUSERESUME               1402     // Tester - Settings Pause/Resume button
#define IDC_TESTER_STARTSTOP                 1034     // Tester - Settings Start/Stop button
#define IDD_TESTER_RESULTS                  33214     // Tester - Results
#define IDD_TESTER_GRAPH                    33207     // Tester - Graph
#define IDD_TESTER_REPORT                   33213     // Tester - Report
#define IDD_TESTER_JOURNAL   IDD_TERMINAL_EXPERTS     // Tester - Journal (entspricht Terminal - Experts)


// Flags zur Fehlerbehandlung                         // korrespondierende Fehler werden statt "laut" "leise" gesetzt, wodurch sie individuell behandelt werden k�nnen
#define MUTE_ERR_INVALID_STOP                   1     // ERR_INVALID_STOP
#define MUTE_ERR_ORDER_CHANGED                  2     // ERR_ORDER_CHANGED
#define MUTE_ERR_CONCUR_MODIFICATION            4     // ERR_CONCURRENT_MODIFICATION
#define MUTE_ERR_SERIES_NOT_AVAILABLE           8     // ERR_SERIES_NOT_AVAILABLE
#define MUTE_ERS_HISTORY_UPDATE                16     // ERS_HISTORY_UPDATE            (Status)
#define MUTE_ERS_EXECUTION_STOPPING            32     // ERS_EXECUTION_STOPPING        (Status)
#define MUTE_ERS_TERMINAL_NOT_YET_READY        64     // ERS_TERMINAL_NOT_YET_READY    (Status)

// String padding types, siehe StringPad()
#define STR_PAD_LEFT                            1
#define STR_PAD_RIGHT                           2
#define STR_PAD_BOTH                            3


// History bar ID's
#define BAR_O                                   0
#define BAR_L                                   1
#define BAR_H                                   2
#define BAR_C                                   3
#define BAR_V                                   4


/**
 * L�dt den Input-Dialog des aktuellen Programms neu.
 *
 * @return int - Fehlerstatus
 */
int start.RelaunchInputDialog() {
   int error;

   if (IsExpert()) {
      if (!IsTesting())
         error = Chart.Expert.Properties();
   }
   else if (IsIndicator()) {
      //if (!IsTesting())
      //   error = Chart.Indicator.Properties();                     // TODO: implementieren
   }

   if (IsError(error))
      SetLastError(error, NULL);
   return(error);
}


/**
 * Schickt eine Debug-Message an den angeschlossenen Debugger. OutputDebugString() funktioniert nur f�r Admins zuverl�ssig.
 *
 * @param  string message - Message
 * @param  int    error   - Fehlercode
 *
 * @return int - derselbe Fehlercode
 */
int debug(string message, int error=NO_ERROR) {
   string name;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");

   OutputDebugStringA(StringConcatenate("MetaTrader::", Symbol(), ",", PeriodDescription(NULL), "::", name, "::", StringReplace(message, NL, " ")));

   return(error); __DummyCalls();
}


/**
 * Pr�ft, ob ein Fehler aufgetreten ist und zeigt diesen optisch und akustisch an. Der Fehler wird an die Debug-Ausgabe geschickt und in der
 * globalen Variable last_error gespeichert. Der mit der MQL-Funktion GetLastError() auslesbare letzte Fehler ist nach Aufruf dieser Funktion
 * immer zur�ckgesetzt.
 *
 * @param  string location - Ortsbezeichner des Fehlers, kann zus�tzlich eine anzuzeigende Nachricht enthalten
 * @param  int    error    - manuelles Forcieren eines bestimmten Fehlers
 * @param  bool   orderPop - ob ein zuvor gespeicherter Orderkontext wiederhergestellt werden soll (default: nein)
 *
 * @return int - der aufgetretene Fehler
 *
 *
 * NOTE: Nur bei Implementierung in der Headerdatei wird das aktuell laufende Modul als Ausl�ser angezeigt.
 */
int catch(string location, int error=NO_ERROR, bool orderPop=false) {
   orderPop = orderPop!=0;

   if      (!error                  ) { error  =                      GetLastError(); }
   else if (error == ERR_WIN32_ERROR) { error += GetLastWin32Error(); GetLastError(); }
   else                               {                               GetLastError(); }


   // rekursive Fehler erkennen und abfangen                         // mit Initializer: h�lt in EA's immer
   static bool recursive = false;                                    //                  h�lt in Indikatoren bis zum n�chsten init-Cycle (ok)


   if (error != NO_ERROR) {
      if (recursive)
         return(debug("catch()  recursive error: "+ location, error));
      recursive = true;

      // (1) Fehler immer auch an Debug-Ausgabe schicken
      debug("ERROR: "+ location, error);


      // (2) Programmnamen um Instanz-ID erweitern
      string name, nameInstanceId;
      if (StringLen(__NAME__) > 0) name = __NAME__;
      else                         name = WindowExpertName();        // falls __NAME__ noch nicht definiert ist

      int logId = GetCustomLogID();
      if (!logId)       nameInstanceId = name;
      else {
         int pos = StringFind(name, "::");
         if (pos == -1) nameInstanceId = StringConcatenate(           name,       "(", logId, ")");
         else           nameInstanceId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
      }


      // (3) Fehler loggen
      string message = StringConcatenate(location, "  [", ifString(error>=ERR_WIN32_ERROR, "win32:"+ (error-ERR_WIN32_ERROR), ErrorToStr(error)), "]");

      bool logged, alerted;
      if (__LOG_CUSTOM)
         logged = logged || __log.custom(StringConcatenate("ERROR: ", name, "::", message));                // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
      if (!logged) {
         Alert("ERROR:   ", Symbol(), ",", PeriodDescription(NULL), "  ", nameInstanceId, "::", message);   // global Log: ggf. mit Instanz-ID
         logged  = true;
         alerted = alerted || !IsExpert() || !IsTesting();
      }
      message = StringConcatenate(nameInstanceId, "::", message);


      // (4) Fehler anzeigen
      if (IsTesting()) {
         // weder Alert() noch MessageBox() k�nnen verwendet werden
         string caption = StringConcatenate("Strategy Tester ", Symbol(), ",", PeriodDescription(NULL));

         pos = StringFind(message, ") ");
         if (pos == -1) message = StringConcatenate("ERROR in ", message);                      // Message am ersten Leerzeichen nach der ersten schlie�enden Klammer umbrechen
         else           message = StringConcatenate("ERROR in ", StringLeft(message, pos+1), NL, StringTrimLeft(StringRight(message, -pos-2)));
                        message = StringConcatenate(TimeToStr(TimeCurrent(), TIME_FULL), NL, message);

         PlaySoundEx("alert.wav");
         ForceMessageBox(caption, message, MB_ICONERROR|MB_OK);
         alerted = true;
      }
      else if (!alerted) {
         // EA au�erhalb des Testers, Script/Indikator im oder au�erhalb des Testers
         Alert("ERROR:   ", Symbol(), ",", PeriodDescription(NULL), "  ", message);
         alerted = true;
      }


      // (5) last_error setzen
      SetLastError(error, NULL);                                                                // je nach Moduletyp unterschiedlich implementiert
      recursive = false;
   }

   if (orderPop)
      OrderPop(location);

   return(error); __DummyCalls();
}


/**
 * Gibt optisch und akustisch eine Warnung aus.
 *
 * @param  string message - anzuzeigende Nachricht
 * @param  int    error   - anzuzeigender Fehlercode
 *
 * @return int - derselbe Fehlercode
 *
 *
 * NOTE: Nur bei Implementierung in der Headerdatei wird das aktuell laufende Modul als Ausl�ser angezeigt.
 */
int warn(string message, int error=NO_ERROR) {
   // (1) Warnung zus�tzlich an Debug-Ausgabe schicken
   debug("WARN: "+ message, error);


   // (2) Programmnamen um Instanz-ID erweitern
   string name, name_wId;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

   int logId = GetCustomLogID();
   if (logId != 0) {
      int pos = StringFind(name, "::");
      if (pos == -1) name_wId = StringConcatenate(           name,       "(", logId, ")");
      else           name_wId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
   }
   else              name_wId = name;

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");


   // (3) Warnung loggen
   bool logged, alerted;
   if (__LOG_CUSTOM)
      logged = logged || __log.custom(StringConcatenate("WARN: ", name, "::", message));           // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
   if (!logged) {
      Alert("WARN:   ", Symbol(), ",", PeriodDescription(NULL), "  ", name_wId, "::", message);    // global Log: ggf. mit Instanz-ID
      logged  = true;
      alerted = alerted || !IsExpert() || !IsTesting();
   }
   message = StringConcatenate(name_wId, "::", message);


   // (4) Warnung anzeigen
   if (IsTesting()) {
      // weder Alert() noch MessageBox() k�nnen verwendet werden
      string caption = StringConcatenate("Strategy Tester ", Symbol(), ",", PeriodDescription(NULL));
      pos = StringFind(message, ") ");
      if (pos == -1) message = StringConcatenate("WARN in ", message);                       // Message am ersten Leerzeichen nach der ersten schlie�enden Klammer umbrechen
      else           message = StringConcatenate("WARN in ", StringLeft(message, pos+1), NL, StringTrimLeft(StringRight(message, -pos-2)));
                     message = StringConcatenate(TimeToStr(TimeCurrent(), TIME_FULL), NL, message);

      PlaySoundEx("alert.wav");
      ForceMessageBox(caption, message, MB_ICONERROR|MB_OK);
   }
   else if (!alerted) {
      // au�erhalb des Testers
      Alert("WARN:   ", Symbol(), ",", PeriodDescription(NULL), "  ", message);
      alerted = true;
   }

   return(error); __DummyCalls();
}


/**
 * Gibt optisch und akustisch eine Warnung aus und verschickt diese Warnung per SMS, wenn SMS-Benachrichtigungen aktiv sind.
 *
 * @param  string message - anzuzeigende Nachricht
 * @param  int    error   - anzuzeigender Fehlercode
 *
 * @return int - derselbe Fehlercode
 */
int warnSMS(string message, int error=NO_ERROR) {
   int _error = warn(message, error);

   if (__SMS.alerts) {
      if (!This.IsTesting()) {                                             // (bool) int
         // Programmnamen um Instanz-ID erweitern
         string name, name_wId;
         if (StringLen(__NAME__) > 0) name = __NAME__;
         else                         name = WindowExpertName();           // falls __NAME__ noch nicht definiert ist

         int logId = GetCustomLogID();
         if (logId != 0) {
            int pos = StringFind(name, "::");
            if (pos == -1) name_wId = StringConcatenate(           name,       "(", logId, ")");
            else           name_wId = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
         }
         else              name_wId = name;

         if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
         else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");

         message = StringConcatenate("WARN:   ", Symbol(), ",", PeriodDescription(NULL), "  ", name_wId, "::", message);

         // SMS verschicken
         SendSMS(__SMS.receiver, TimeToStr(TimeLocal(), TIME_MINUTES) +" "+ message);
      }
   }
   return(_error); __DummyCalls();
}


/**
 * Loggt eine Message.
 *
 * @param  string message - Message
 * @param  int    error   - Fehlercode
 *
 * @return int - derselbe Fehlercode
 *
 *
 * NOTE: Nur bei Implementierung in der Headerdatei wird das aktuell laufende Modul als Ausl�ser angezeigt.
 */
int log(string message, int error=NO_ERROR) {
   if (!__LOG)
      return(error);


   // (1) ggf. ausschlie�liche/zus�tzliche Ausgabe via Debug oder ...
   static int static.logToDebug  = -1; if (static.logToDebug  == -1) static.logToDebug  = GetLocalConfigBool("Logging", "LogToDebug",  false);
   static int static.logTeeDebug = -1; if (static.logTeeDebug == -1) static.logTeeDebug = GetLocalConfigBool("Logging", "LogTeeDebug", false);

   if (static.logToDebug  == 1) return(debug(message, error));
   if (static.logTeeDebug == 1)        debug(message, error);


   string name;
   if (StringLen(__NAME__) > 0) name = __NAME__;
   else                         name = WindowExpertName();                 // falls __NAME__ noch nicht definiert ist

   if      (error >= ERR_WIN32_ERROR) message = StringConcatenate(message, "  [win32:", error-ERR_WIN32_ERROR, " - ", ErrorDescription(error), "]");
   else if (error != NO_ERROR       ) message = StringConcatenate(message, "  [",                                     ErrorToStr(error)      , "]");


   // (2) Custom-Log benutzen oder ...
   if (__LOG_CUSTOM)
      if (__log.custom(StringConcatenate(name, "::", message)))            // custom Log: ohne Instanz-ID, bei Fehler Fallback zum Standardlogging
         return(error);


   // (3) Global-Log benutzen
   int logId = GetCustomLogID();
   if (logId != 0) {
      int pos = StringFind(name, "::");
      if (pos == -1) name = StringConcatenate(           name,       "(", logId, ")");
      else           name = StringConcatenate(StringLeft(name, pos), "(", logId, ")", StringRight(name, -pos));
   }
   Print(StringConcatenate(name, "::", StringReplace(message, NL, " ")));  // global Log: ggf. mit Instanz-ID

   return(error); __DummyCalls();
}


/**
 * Loggt eine Message in das Instanz-eigene Logfile.
 *
 * @param  string message - vollst�ndige zu loggende Message (ohne Zeitstempel, Symbol, Timeframe)
 *
 * @return bool - Erfolgsstatus: u.a. FALSE, wenn das Instanz-eigene Logfile (noch) nicht definiert ist
 *
private*/bool __log.custom(string message) {
   bool old.LOG_CUSTOM = __LOG_CUSTOM;
   int logId = GetCustomLogID();
   if (logId == NULL)
      return(false);

   message = StringConcatenate(TimeToStr(TimeLocal(), TIME_FULL), "  ", StdSymbol(), ",", StringPadRight(PeriodDescription(NULL), 3, " "), "  ", StringReplace(message, NL, " "));

   string fileName = StringConcatenate(logId, ".log");

   int hFile = FileOpen(fileName, FILE_READ|FILE_WRITE);
   if (hFile < 0) {
      __LOG_CUSTOM = false; catch("__log.custom(1)->FileOpen(\""+ fileName +"\")"); __LOG_CUSTOM = old.LOG_CUSTOM;
      return(false);
   }

   if (!FileSeek(hFile, 0, SEEK_END)) {
      __LOG_CUSTOM = false; catch("__log.custom(2)->FileSeek()"); __LOG_CUSTOM = old.LOG_CUSTOM;
      FileClose(hFile);
      return(_false(GetLastError()));
   }

   if (FileWrite(hFile, message) < 0) {
      __LOG_CUSTOM = false; catch("__log.custom(3)->FileWrite()"); __LOG_CUSTOM = old.LOG_CUSTOM;
      FileClose(hFile);
      return(_false(GetLastError()));
   }

   FileClose(hFile);
   return(true);
}


/**
 * Gibt die Beschreibung eines Fehlercodes zur�ck.
 *
 * @param  int error - MQL- oder gemappter Win32-Fehlercode
 *
 * @return string
 *
 *
 * NOTE: In der Headerdatei implementiert, damit Logging/Debugging m�glichst nicht die StdLib laden m�ssen, was im Fehlerfall unn�tige Folgefehler ausl�sen kann.
 */
string ErrorDescription(int error) {
   if (error >= ERR_WIN32_ERROR)                                                                                  // 100000
      return(StringConcatenate("win32 error (", error-ERR_WIN32_ERROR, ")"));

   switch (error) {
      case NO_ERROR                       : return("no error"                                                  ); //      0

      // trade server errors
      case ERR_NO_RESULT                  : return("no result"                                                 ); //      1
      case ERR_COMMON_ERROR               : return("trade denied"                                              ); //      2
      case ERR_INVALID_TRADE_PARAMETERS   : return("invalid trade parameters"                                  ); //      3
      case ERR_SERVER_BUSY                : return("trade server busy"                                         ); //      4
      case ERR_OLD_VERSION                : return("old terminal version"                                      ); //      5
      case ERR_NO_CONNECTION              : return("no connection to trade server"                             ); //      6
      case ERR_NOT_ENOUGH_RIGHTS          : return("not enough rights"                                         ); //      7
      case ERR_TOO_FREQUENT_REQUESTS      : return("too frequent requests"                                     ); //      8
      case ERR_MALFUNCTIONAL_TRADE        : return("malfunctional trade operation"                             ); //      9
      case ERR_ACCOUNT_DISABLED           : return("account disabled"                                          ); //     64
      case ERR_INVALID_ACCOUNT            : return("invalid account"                                           ); //     65
      case ERR_TRADE_TIMEOUT              : return("trade timeout"                                             ); //    128
      case ERR_INVALID_PRICE              : return("invalid price"                                             ); //    129 Kurs bewegt sich zu schnell (aus dem Fenster)
      case ERR_INVALID_STOP               : return("invalid stop"                                              ); //    130
      case ERR_INVALID_TRADE_VOLUME       : return("invalid trade volume"                                      ); //    131
      case ERR_MARKET_CLOSED              : return("market closed"                                             ); //    132
      case ERR_TRADE_DISABLED             : return("trading disabled"                                          ); //    133
      case ERR_NOT_ENOUGH_MONEY           : return("not enough money"                                          ); //    134
      case ERR_PRICE_CHANGED              : return("price changed"                                             ); //    135
      case ERR_OFF_QUOTES                 : return("off quotes"                                                ); //    136
      case ERR_BROKER_BUSY                : return("broker busy"                                               ); //    137
      case ERR_REQUOTE                    : return("requote"                                                   ); //    138
      case ERR_ORDER_LOCKED               : return("order locked"                                              ); //    139
      case ERR_LONG_POSITIONS_ONLY_ALLOWED: return("long positions only allowed"                               ); //    140
      case ERR_TOO_MANY_REQUESTS          : return("too many requests"                                         ); //    141
    //case 142: ???                                                                                               //    see stderror.mqh
    //case 143: ???                                                                                               //    see stderror.mqh
    //case 144: ???                                                                                               //    see stderror.mqh
      case ERR_TRADE_MODIFY_DENIED        : return("modification denied because too close to market"           ); //    145
      case ERR_TRADE_CONTEXT_BUSY         : return("trade context busy"                                        ); //    146
      case ERR_TRADE_EXPIRATION_DENIED    : return("expiration setting denied by broker"                       ); //    147
      case ERR_TRADE_TOO_MANY_ORDERS      : return("number of open orders reached the broker limit"            ); //    148
      case ERR_TRADE_HEDGE_PROHIBITED     : return("hedging prohibited"                                        ); //    149
      case ERR_TRADE_PROHIBITED_BY_FIFO   : return("prohibited by FIFO rules"                                  ); //    150

      // runtime errors
      case ERR_RUNTIME_ERROR              : return("runtime error"                                             ); //   4000 common runtime error (no mql error)
      case ERR_WRONG_FUNCTION_POINTER     : return("wrong function pointer"                                    ); //   4001
      case ERR_ARRAY_INDEX_OUT_OF_RANGE   : return("array index out of range"                                  ); //   4002
      case ERR_NO_MEMORY_FOR_CALL_STACK   : return("no memory for function call stack"                         ); //   4003
      case ERR_RECURSIVE_STACK_OVERFLOW   : return("recursive stack overflow"                                  ); //   4004
      case ERR_NOT_ENOUGH_STACK_FOR_PARAM : return("not enough stack for parameter"                            ); //   4005
      case ERR_NO_MEMORY_FOR_PARAM_STRING : return("no memory for parameter string"                            ); //   4006
      case ERR_NO_MEMORY_FOR_TEMP_STRING  : return("no memory for temp string"                                 ); //   4007
      case ERR_NOT_INITIALIZED_STRING     : return("uninitialized string"                                      ); //   4008
      case ERR_NOT_INITIALIZED_ARRAYSTRING: return("uninitialized string in array"                             ); //   4009
      case ERR_NO_MEMORY_FOR_ARRAYSTRING  : return("no memory for string in array"                             ); //   4010
      case ERR_TOO_LONG_STRING            : return("string too long"                                           ); //   4011
      case ERR_REMAINDER_FROM_ZERO_DIVIDE : return("remainder from division by zero"                           ); //   4012
      case ERR_ZERO_DIVIDE                : return("division by zero"                                          ); //   4013
      case ERR_UNKNOWN_COMMAND            : return("unknown command"                                           ); //   4014
      case ERR_WRONG_JUMP                 : return("wrong jump"                                                ); //   4015
      case ERR_NOT_INITIALIZED_ARRAY      : return("array not initialized"                                     ); //   4016
      case ERR_DLL_CALLS_NOT_ALLOWED      : return("DLL calls not allowed"                                     ); //   4017
      case ERR_CANNOT_LOAD_LIBRARY        : return("cannot load library"                                       ); //   4018
      case ERR_CANNOT_CALL_FUNCTION       : return("cannot call function"                                      ); //   4019
      case ERR_EXTERNAL_CALLS_NOT_ALLOWED : return("library calls not allowed"                                 ); //   4020
      case ERR_NO_MEMORY_FOR_RETURNED_STR : return("no memory for temp string returned from function"          ); //   4021
      case ERR_SYSTEM_BUSY                : return("system busy"                                               ); //   4022
    //case 4023: ???
      case ERR_INVALID_FUNCTION_PARAMSCNT : return("invalid function parameter count"                          ); //   4050 invalid parameters count
      case ERR_INVALID_FUNCTION_PARAMVALUE: return("invalid function parameter value"                          ); //   4051 invalid parameter value
      case ERR_STRING_FUNCTION_INTERNAL   : return("string function internal error"                            ); //   4052
      case ERR_ARRAY_ERROR                : return("array error"                                               ); //   4053 some array error
      case ERR_SERIES_NOT_AVAILABLE       : return("requested time series not available"                       ); //   4054 time series not available
      case ERR_CUSTOM_INDICATOR_ERROR     : return("custom indicator error"                                    ); //   4055 custom indicator error
      case ERR_INCOMPATIBLE_ARRAYS        : return("incompatible arrays"                                       ); //   4056 incompatible arrays
      case ERR_GLOBAL_VARIABLES_PROCESSING: return("global variables processing error"                         ); //   4057
      case ERR_GLOBAL_VARIABLE_NOT_FOUND  : return("global variable not found"                                 ); //   4058
      case ERR_FUNC_NOT_ALLOWED_IN_TESTER : return("function not allowed in tester"                            ); //   4059
      case ERR_FUNCTION_NOT_CONFIRMED     : return("function not confirmed"                                    ); //   4060
      case ERR_SEND_MAIL_ERROR            : return("send mail error"                                           ); //   4061
      case ERR_STRING_PARAMETER_EXPECTED  : return("string parameter expected"                                 ); //   4062
      case ERR_INTEGER_PARAMETER_EXPECTED : return("integer parameter expected"                                ); //   4063
      case ERR_DOUBLE_PARAMETER_EXPECTED  : return("double parameter expected"                                 ); //   4064
      case ERR_ARRAY_AS_PARAMETER_EXPECTED: return("array parameter expected"                                  ); //   4065
      case ERS_HISTORY_UPDATE             : return("requested history is updating"                             ); //   4066 requested history is updating   - Status
      case ERR_TRADE_ERROR                : return("trade function error"                                      ); //   4067 trade function error
      case ERR_END_OF_FILE                : return("end of file"                                               ); //   4099 end of file
      case ERR_FILE_ERROR                 : return("file error"                                                ); //   4100 some file error
      case ERR_WRONG_FILE_NAME            : return("wrong file name"                                           ); //   4101
      case ERR_TOO_MANY_OPENED_FILES      : return("too many opened files"                                     ); //   4102
      case ERR_CANNOT_OPEN_FILE           : return("cannot open file"                                          ); //   4103
      case ERR_INCOMPATIBLE_FILEACCESS    : return("incompatible file access"                                  ); //   4104
      case ERR_NO_ORDER_SELECTED          : return("no order selected"                                         ); //   4105
      case ERR_UNKNOWN_SYMBOL             : return("unknown symbol"                                            ); //   4106
      case ERR_INVALID_PRICE_PARAM        : return("invalid price parameter for trade function"                ); //   4107
      case ERR_INVALID_TICKET             : return("invalid ticket"                                            ); //   4108
      case ERR_TRADE_NOT_ALLOWED          : return("live trading not enabled"                                  ); //   4109
      case ERR_LONGS_NOT_ALLOWED          : return("long trades not enabled"                                   ); //   4110
      case ERR_SHORTS_NOT_ALLOWED         : return("short trades not enabled"                                  ); //   4111
      case ERR_OBJECT_ALREADY_EXISTS      : return("object already exists"                                     ); //   4200
      case ERR_UNKNOWN_OBJECT_PROPERTY    : return("unknown object property"                                   ); //   4201
      case ERR_OBJECT_DOES_NOT_EXIST      : return("object doesn't exist"                                      ); //   4202
      case ERR_UNKNOWN_OBJECT_TYPE        : return("unknown object type"                                       ); //   4203
      case ERR_NO_OBJECT_NAME             : return("no object name"                                            ); //   4204
      case ERR_OBJECT_COORDINATES_ERROR   : return("object coordinates error"                                  ); //   4205
      case ERR_NO_SPECIFIED_SUBWINDOW     : return("no specified subwindow"                                    ); //   4206
      case ERR_OBJECT_ERROR               : return("object error"                                              ); //   4207 some object error
      case ERR_NOTIFICATION_SEND_ERROR    : return("error setting notification into sending queue"             ); //   4250
      case ERR_NOTIFICATION_WRONG_PARAM   : return("invalid notification function parameter"                   ); //   4251 empty string passed
      case ERR_NOTIFICATION_WRONG_SETTINGS: return("invalid notification settings"                             ); //   4252 ID not specified or notifications are not enabled
      case ERR_NOTIFICATION_TOO_FREQUENT  : return("too frequent notifications"                                ); //   4253

      // custom errors
      case ERR_NOT_IMPLEMENTED            : return("feature not implemented"                                   ); //   5000
      case ERR_INVALID_INPUT_PARAMVALUE   : return("invalid input parameter value"                             ); //   5001
      case ERR_INVALID_CONFIG_PARAMVALUE  : return("invalid configuration value"                               ); //   5002
      case ERS_TERMINAL_NOT_YET_READY     : return("terminal not yet ready"                                    ); //   5003 Status
      case ERR_INVALID_TIMEZONE_CONFIG    : return("invalid or missing timezone configuration"                 ); //   5004
      case ERR_INVALID_MARKET_DATA        : return("invalid market data"                                       ); //   5005
      case ERR_FILE_NOT_FOUND             : return("file not found"                                            ); //   5006
      case ERR_CANCELLED_BY_USER          : return("cancelled by user"                                         ); //   5007
      case ERR_FUNC_NOT_ALLOWED           : return("function not allowed"                                      ); //   5008
      case ERR_INVALID_COMMAND            : return("invalid or unknow command"                                 ); //   5009
      case ERR_ILLEGAL_STATE              : return("illegal runtime state"                                     ); //   5010
      case ERS_EXECUTION_STOPPING         : return("program execution stopping"                                ); //   5011 Status
      case ERR_ORDER_CHANGED              : return("order status changed"                                      ); //   5012
      case ERR_HISTORY_INSUFFICIENT       : return("insufficient history for calculation"                      ); //   5013
      case ERR_CONCURRENT_MODIFICATION    : return("concurrent modification"                                   ); //   5014
   }
   return(StringConcatenate("unknown error (", error, ")"));
}


/**
 * Gibt die lesbare Konstante eines MQL-Fehlercodes zur�ck.
 *
 * @param  int error - MQL-Fehlercode
 *
 * @return string
 *
 *
 * NOTE: In der Headerdatei implementiert, damit Logging/Debugging m�glichst nicht die StdLib laden m�ssen, was im Fehlerfall unn�tige Folgefehler ausl�sen kann.
 */
string ErrorToStr(int error) {
   if (error >= ERR_WIN32_ERROR)                                                      // 100000
      return(StringConcatenate("ERR_WIN32_ERROR+", error-ERR_WIN32_ERROR));

   switch (error) {
      case NO_ERROR                       : return("NO_ERROR"                       ); //      0

      // trade server errors
      case ERR_NO_RESULT                  : return("ERR_NO_RESULT"                  ); //      1
      case ERR_COMMON_ERROR               : return("ERR_COMMON_ERROR"               ); //      2
      case ERR_INVALID_TRADE_PARAMETERS   : return("ERR_INVALID_TRADE_PARAMETERS"   ); //      3
      case ERR_SERVER_BUSY                : return("ERR_SERVER_BUSY"                ); //      4
      case ERR_OLD_VERSION                : return("ERR_OLD_VERSION"                ); //      5
      case ERR_NO_CONNECTION              : return("ERR_NO_CONNECTION"              ); //      6
      case ERR_NOT_ENOUGH_RIGHTS          : return("ERR_NOT_ENOUGH_RIGHTS"          ); //      7
      case ERR_TOO_FREQUENT_REQUESTS      : return("ERR_TOO_FREQUENT_REQUESTS"      ); //      8
      case ERR_MALFUNCTIONAL_TRADE        : return("ERR_MALFUNCTIONAL_TRADE"        ); //      9
      case ERR_ACCOUNT_DISABLED           : return("ERR_ACCOUNT_DISABLED"           ); //     64
      case ERR_INVALID_ACCOUNT            : return("ERR_INVALID_ACCOUNT"            ); //     65
      case ERR_TRADE_TIMEOUT              : return("ERR_TRADE_TIMEOUT"              ); //    128
      case ERR_INVALID_PRICE              : return("ERR_INVALID_PRICE"              ); //    129
      case ERR_INVALID_STOP               : return("ERR_INVALID_STOP"               ); //    130
      case ERR_INVALID_TRADE_VOLUME       : return("ERR_INVALID_TRADE_VOLUME"       ); //    131
      case ERR_MARKET_CLOSED              : return("ERR_MARKET_CLOSED"              ); //    132
      case ERR_TRADE_DISABLED             : return("ERR_TRADE_DISABLED"             ); //    133
      case ERR_NOT_ENOUGH_MONEY           : return("ERR_NOT_ENOUGH_MONEY"           ); //    134
      case ERR_PRICE_CHANGED              : return("ERR_PRICE_CHANGED"              ); //    135
      case ERR_OFF_QUOTES                 : return("ERR_OFF_QUOTES"                 ); //    136
      case ERR_BROKER_BUSY                : return("ERR_BROKER_BUSY"                ); //    137
      case ERR_REQUOTE                    : return("ERR_REQUOTE"                    ); //    138
      case ERR_ORDER_LOCKED               : return("ERR_ORDER_LOCKED"               ); //    139
      case ERR_LONG_POSITIONS_ONLY_ALLOWED: return("ERR_LONG_POSITIONS_ONLY_ALLOWED"); //    140
      case ERR_TOO_MANY_REQUESTS          : return("ERR_TOO_MANY_REQUESTS"          ); //    141
      case ERR_TRADE_MODIFY_DENIED        : return("ERR_TRADE_MODIFY_DENIED"        ); //    145
      case ERR_TRADE_CONTEXT_BUSY         : return("ERR_TRADE_CONTEXT_BUSY"         ); //    146
      case ERR_TRADE_EXPIRATION_DENIED    : return("ERR_TRADE_EXPIRATION_DENIED"    ); //    147
      case ERR_TRADE_TOO_MANY_ORDERS      : return("ERR_TRADE_TOO_MANY_ORDERS"      ); //    148
      case ERR_TRADE_HEDGE_PROHIBITED     : return("ERR_TRADE_HEDGE_PROHIBITED"     ); //    149
      case ERR_TRADE_PROHIBITED_BY_FIFO   : return("ERR_TRADE_PROHIBITED_BY_FIFO"   ); //    150

      // runtime errors
      case ERR_RUNTIME_ERROR              : return("ERR_RUNTIME_ERROR"              ); //   4000
      case ERR_WRONG_FUNCTION_POINTER     : return("ERR_WRONG_FUNCTION_POINTER"     ); //   4001
      case ERR_ARRAY_INDEX_OUT_OF_RANGE   : return("ERR_ARRAY_INDEX_OUT_OF_RANGE"   ); //   4002
      case ERR_NO_MEMORY_FOR_CALL_STACK   : return("ERR_NO_MEMORY_FOR_CALL_STACK"   ); //   4003
      case ERR_RECURSIVE_STACK_OVERFLOW   : return("ERR_RECURSIVE_STACK_OVERFLOW"   ); //   4004
      case ERR_NOT_ENOUGH_STACK_FOR_PARAM : return("ERR_NOT_ENOUGH_STACK_FOR_PARAM" ); //   4005
      case ERR_NO_MEMORY_FOR_PARAM_STRING : return("ERR_NO_MEMORY_FOR_PARAM_STRING" ); //   4006
      case ERR_NO_MEMORY_FOR_TEMP_STRING  : return("ERR_NO_MEMORY_FOR_TEMP_STRING"  ); //   4007
      case ERR_NOT_INITIALIZED_STRING     : return("ERR_NOT_INITIALIZED_STRING"     ); //   4008
      case ERR_NOT_INITIALIZED_ARRAYSTRING: return("ERR_NOT_INITIALIZED_ARRAYSTRING"); //   4009
      case ERR_NO_MEMORY_FOR_ARRAYSTRING  : return("ERR_NO_MEMORY_FOR_ARRAYSTRING"  ); //   4010
      case ERR_TOO_LONG_STRING            : return("ERR_TOO_LONG_STRING"            ); //   4011
      case ERR_REMAINDER_FROM_ZERO_DIVIDE : return("ERR_REMAINDER_FROM_ZERO_DIVIDE" ); //   4012
      case ERR_ZERO_DIVIDE                : return("ERR_ZERO_DIVIDE"                ); //   4013
      case ERR_UNKNOWN_COMMAND            : return("ERR_UNKNOWN_COMMAND"            ); //   4014
      case ERR_WRONG_JUMP                 : return("ERR_WRONG_JUMP"                 ); //   4015
      case ERR_NOT_INITIALIZED_ARRAY      : return("ERR_NOT_INITIALIZED_ARRAY"      ); //   4016
      case ERR_DLL_CALLS_NOT_ALLOWED      : return("ERR_DLL_CALLS_NOT_ALLOWED"      ); //   4017
      case ERR_CANNOT_LOAD_LIBRARY        : return("ERR_CANNOT_LOAD_LIBRARY"        ); //   4018
      case ERR_CANNOT_CALL_FUNCTION       : return("ERR_CANNOT_CALL_FUNCTION"       ); //   4019
      case ERR_EXTERNAL_CALLS_NOT_ALLOWED : return("ERR_EXTERNAL_CALLS_NOT_ALLOWED" ); //   4020
      case ERR_NO_MEMORY_FOR_RETURNED_STR : return("ERR_NO_MEMORY_FOR_RETURNED_STR" ); //   4021
      case ERR_SYSTEM_BUSY                : return("ERR_SYSTEM_BUSY"                ); //   4022
    //case 4023                           : // ???
      case ERR_INVALID_FUNCTION_PARAMSCNT : return("ERR_INVALID_FUNCTION_PARAMSCNT" ); //   4050
      case ERR_INVALID_FUNCTION_PARAMVALUE: return("ERR_INVALID_FUNCTION_PARAMVALUE"); //   4051
      case ERR_STRING_FUNCTION_INTERNAL   : return("ERR_STRING_FUNCTION_INTERNAL"   ); //   4052
      case ERR_ARRAY_ERROR                : return("ERR_ARRAY_ERROR"                ); //   4053
      case ERR_SERIES_NOT_AVAILABLE       : return("ERR_SERIES_NOT_AVAILABLE"       ); //   4054
      case ERR_CUSTOM_INDICATOR_ERROR     : return("ERR_CUSTOM_INDICATOR_ERROR"     ); //   4055
      case ERR_INCOMPATIBLE_ARRAYS        : return("ERR_INCOMPATIBLE_ARRAYS"        ); //   4056
      case ERR_GLOBAL_VARIABLES_PROCESSING: return("ERR_GLOBAL_VARIABLES_PROCESSING"); //   4057
      case ERR_GLOBAL_VARIABLE_NOT_FOUND  : return("ERR_GLOBAL_VARIABLE_NOT_FOUND"  ); //   4058
      case ERR_FUNC_NOT_ALLOWED_IN_TESTER : return("ERR_FUNC_NOT_ALLOWED_IN_TESTER" ); //   4059
      case ERR_FUNCTION_NOT_CONFIRMED     : return("ERR_FUNCTION_NOT_CONFIRMED"     ); //   4060
      case ERR_SEND_MAIL_ERROR            : return("ERR_SEND_MAIL_ERROR"            ); //   4061
      case ERR_STRING_PARAMETER_EXPECTED  : return("ERR_STRING_PARAMETER_EXPECTED"  ); //   4062
      case ERR_INTEGER_PARAMETER_EXPECTED : return("ERR_INTEGER_PARAMETER_EXPECTED" ); //   4063
      case ERR_DOUBLE_PARAMETER_EXPECTED  : return("ERR_DOUBLE_PARAMETER_EXPECTED"  ); //   4064
      case ERR_ARRAY_AS_PARAMETER_EXPECTED: return("ERR_ARRAY_AS_PARAMETER_EXPECTED"); //   4065
      case ERS_HISTORY_UPDATE             : return("ERS_HISTORY_UPDATE"             ); //   4066 Status
      case ERR_TRADE_ERROR                : return("ERR_TRADE_ERROR"                ); //   4067
      case ERR_END_OF_FILE                : return("ERR_END_OF_FILE"                ); //   4099
      case ERR_FILE_ERROR                 : return("ERR_FILE_ERROR"                 ); //   4100
      case ERR_WRONG_FILE_NAME            : return("ERR_WRONG_FILE_NAME"            ); //   4101
      case ERR_TOO_MANY_OPENED_FILES      : return("ERR_TOO_MANY_OPENED_FILES"      ); //   4102
      case ERR_CANNOT_OPEN_FILE           : return("ERR_CANNOT_OPEN_FILE"           ); //   4103
      case ERR_INCOMPATIBLE_FILEACCESS    : return("ERR_INCOMPATIBLE_FILEACCESS"    ); //   4104
      case ERR_NO_ORDER_SELECTED          : return("ERR_NO_ORDER_SELECTED"          ); //   4105
      case ERR_UNKNOWN_SYMBOL             : return("ERR_UNKNOWN_SYMBOL"             ); //   4106
      case ERR_INVALID_PRICE_PARAM        : return("ERR_INVALID_PRICE_PARAM"        ); //   4107
      case ERR_INVALID_TICKET             : return("ERR_INVALID_TICKET"             ); //   4108
      case ERR_TRADE_NOT_ALLOWED          : return("ERR_TRADE_NOT_ALLOWED"          ); //   4109
      case ERR_LONGS_NOT_ALLOWED          : return("ERR_LONGS_NOT_ALLOWED"          ); //   4110
      case ERR_SHORTS_NOT_ALLOWED         : return("ERR_SHORTS_NOT_ALLOWED"         ); //   4111
      case ERR_OBJECT_ALREADY_EXISTS      : return("ERR_OBJECT_ALREADY_EXISTS"      ); //   4200
      case ERR_UNKNOWN_OBJECT_PROPERTY    : return("ERR_UNKNOWN_OBJECT_PROPERTY"    ); //   4201
      case ERR_OBJECT_DOES_NOT_EXIST      : return("ERR_OBJECT_DOES_NOT_EXIST"      ); //   4202
      case ERR_UNKNOWN_OBJECT_TYPE        : return("ERR_UNKNOWN_OBJECT_TYPE"        ); //   4203
      case ERR_NO_OBJECT_NAME             : return("ERR_NO_OBJECT_NAME"             ); //   4204
      case ERR_OBJECT_COORDINATES_ERROR   : return("ERR_OBJECT_COORDINATES_ERROR"   ); //   4205
      case ERR_NO_SPECIFIED_SUBWINDOW     : return("ERR_NO_SPECIFIED_SUBWINDOW"     ); //   4206
      case ERR_OBJECT_ERROR               : return("ERR_OBJECT_ERROR"               ); //   4207
      case ERR_NOTIFICATION_SEND_ERROR    : return("ERR_NOTIFICATION_SEND_ERROR"    ); //   4250
      case ERR_NOTIFICATION_WRONG_PARAM   : return("ERR_NOTIFICATION_WRONG_PARAM"   ); //   4251
      case ERR_NOTIFICATION_WRONG_SETTINGS: return("ERR_NOTIFICATION_WRONG_SETTINGS"); //   4252
      case ERR_NOTIFICATION_TOO_FREQUENT  : return("ERR_NOTIFICATION_TOO_FREQUENT"  ); //   4253

      // custom errors
      case ERR_NOT_IMPLEMENTED            : return("ERR_NOT_IMPLEMENTED"            ); //   5000
      case ERR_INVALID_INPUT_PARAMVALUE   : return("ERR_INVALID_INPUT_PARAMVALUE"   ); //   5001
      case ERR_INVALID_CONFIG_PARAMVALUE  : return("ERR_INVALID_CONFIG_PARAMVALUE"  ); //   5002
      case ERS_TERMINAL_NOT_YET_READY     : return("ERS_TERMINAL_NOT_YET_READY"     ); //   5003 Status
      case ERR_INVALID_TIMEZONE_CONFIG    : return("ERR_INVALID_TIMEZONE_CONFIG"    ); //   5004
      case ERR_INVALID_MARKET_DATA        : return("ERR_INVALID_MARKET_DATA"        ); //   5005
      case ERR_FILE_NOT_FOUND             : return("ERR_FILE_NOT_FOUND"             ); //   5006
      case ERR_CANCELLED_BY_USER          : return("ERR_CANCELLED_BY_USER"          ); //   5007
      case ERR_FUNC_NOT_ALLOWED           : return("ERR_FUNC_NOT_ALLOWED"           ); //   5008
      case ERR_INVALID_COMMAND            : return("ERR_INVALID_COMMAND"            ); //   5009
      case ERR_ILLEGAL_STATE              : return("ERR_ILLEGAL_STATE"              ); //   5010
      case ERS_EXECUTION_STOPPING         : return("ERS_EXECUTION_STOPPING"         ); //   5011 Status
      case ERR_ORDER_CHANGED              : return("ERR_ORDER_CHANGED"              ); //   5012
      case ERR_HISTORY_INSUFFICIENT       : return("ERR_HISTORY_INSUFFICIENT"       ); //   5013
      case ERR_CONCURRENT_MODIFICATION    : return("ERR_CONCURRENT_MODIFICATION"    ); //   5014
   }
   return(error);
}


/**
 * Gibt die Beschreibung eines Timeframe-Codes zur�ck.
 *
 * @param  int period - Timeframe-Code bzw. Anzahl der Minuten je Chart-Bar (default: aktuelle Periode)
 *
 * @return string
 *
 *
 * NOTE: In der Headerdatei implementiert, damit Logging/Debugging m�glichst nicht die StdLib laden m�ssen, was im Fehlerfall unn�tige Folgefehler ausl�sen kann.
 */
string PeriodDescription(int period=NULL) {
   if (period == NULL)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return("M1" );     // 1 minute
      case PERIOD_M5 : return("M5" );     // 5 minutes
      case PERIOD_M15: return("M15");     // 15 minutes
      case PERIOD_M30: return("M30");     // 30 minutes
      case PERIOD_H1 : return("H1" );     // 1 hour
      case PERIOD_H4 : return("H4" );     // 4 hour
      case PERIOD_D1 : return("D1" );     // 1 day
      case PERIOD_W1 : return("W1" );     // 1 week
      case PERIOD_MN1: return("MN1");     // 1 month
      case PERIOD_Q1 : return("Q1" );     // 1 quarter
   }
   return(StringConcatenate("unknown period (", period, ")"));
}


/**
 * Ersetzt in einem String alle Vorkommen eines Substrings durch einen anderen String (kein rekursives Ersetzen).
 *
 * @param  string object  - Ausgangsstring
 * @param  string search  - Suchstring
 * @param  string replace - Ersatzstring
 *
 * @return string - modifizierter String
 */
string StringReplace(string object, string search, string replace) {
   if (!StringLen(object)) return(object);
   if (!StringLen(search)) return(object);
   if (search == replace)  return(object);

   int from=0, found=StringFind(object, search);
   if (found == -1)
      return(object);

   string result = "";

   while (found > -1) {
      result = StringConcatenate(result, StringSubstrFix(object, from, found-from), replace);
      from   = found + StringLen(search);
      found  = StringFind(object, search, from);
   }
   result = StringConcatenate(result, StringSubstr(object, from));

   return(result);
}


/**
 * Bugfix f�r StringSubstr(string, start, length=0), die MQL-Funktion gibt f�r length=0 Unfug zur�ck.
 * Erm�glicht zus�tzlich die Angabe negativer Werte f�r start und length.
 *
 * @param  string object
 * @param  int    start  - wenn negativ, Startindex vom Ende des Strings
 * @param  int    length - wenn negativ, Anzahl der zur�ckzugebenden Zeichen links vom Startindex
 *
 * @return string
 */
string StringSubstrFix(string object, int start, int length=INT_MAX) {
   if (length == 0)
      return("");

   if (start < 0)
      start = Max(0, start + StringLen(object));

   if (length < 0) {
      start += 1 + length;
      length = Abs(length);
   }
   return(StringSubstr(object, start, length));
}


#define SND_ASYNC           0x01       // play asynchronously
#define SND_FILENAME  0x00020000       // parameter is a file name


/**
 * Dropin-Ersatz f�r PlaySound()
 *
 * Spielt ein Soundfile ab, auch wenn dies im aktuellen Kontext des Terminals (z.B. im Tester) nicht unterst�tzt wird.
 * Pr�ft zus�tzlich, ob das angegebene Soundfile existiert.
 *
 * @param  string soundfile
 *
 * @return int - Fehlerstatus
 */
int PlaySoundEx(string soundfile) {
   string filename = StringReplace(soundfile, "/", "\\");
   string fullName = StringConcatenate(TerminalPath(), "\\sounds\\", filename);
   if (!IsFile(fullName)) return(catch("PlaySoundEx(1)  file not found: \""+ fullName +"\"", ERR_FILE_NOT_FOUND));

   if (IsTesting()) PlaySoundA(fullName, NULL, SND_FILENAME|SND_ASYNC);
   else             PlaySound(filename);

   return(catch("PlaySoundEx(2)"));
}


/**
 * Dropin-Ersatz f�r MessageBox()
 *
 * Zeigt eine MessageBox an, auch wenn dies im aktuellen Kontext des Terminals (z.B. im Tester oder in Indikatoren) nicht unterst�tzt wird.
 *
 * @param  string caption
 * @param  string message
 * @param  int    flags
 *
 * @return int - Tastencode
 */
int ForceMessageBox(string caption, string message, int flags=MB_OK) {
   string prefix = StringConcatenate(Symbol(), ",", PeriodDescription(NULL));

   if (!StringContains(caption, prefix))
      caption = StringConcatenate(prefix, " - ", caption);

   int button;

   if (!IsTesting() && !IsIndicator()) button = MessageBox(message, caption, flags);
   else                                button = MessageBoxA(NULL, message, caption, flags);  // TODO: hWndOwner fixen

   return(button);
}


#define GA_ROOT         2

#define GW_HWNDLAST     1
#define GW_HWNDNEXT     2
#define GW_HWNDPREV     3
#define GW_CHILD        5


/**
 * Dropin-Ersatz f�r WindowHandle()
 *
 * Wie WindowHandle(), kann aber das Fensterhandle des aktuellen Charts in allen F�llen ermitteln, in denen WindowHandle() dies nicht kann.
 *
 * @param string symbol    - Symbol des Charts, dessen Handle ermittelt werden soll.
 *                           Ist dieser Parameter NULL und es wurde kein Timeframe angegeben (kein zweiter Parameter oder NULL), wird das Handle des aktuellen
 *                           Chartfensters zur�ckgegeben oder -1, falls das Programm kein Chartfenster hat (im Tester bei VisualMode=Off).
 *                           Ist dieser oder der zweite Parameter nicht NULL, wird das eigene Chartfenster bei der Suche nicht ber�cksichtigt und das Handle
 *                           des ersten passenden weiteren Chartfensters zur�ckgegeben (in Z order) oder NULL, falls kein weiteres solches Chartfenster existiert.
 * @param int    timeframe - Timeframe des Charts, dessen Handle ermittelt werden soll (default: der aktuelle Timeframe)
 *
 * @return int - Fensterhandle oder NULL, falls kein entsprechendes Fenster existiert oder ein Fehler auftrat;
 *               -1, falls das Handle des eigenen Chartfensters gesucht ist und das Programm keinen Chart hat (im Tester bei VisualMode=Off)
 */
int WindowHandleEx(string symbol, int timeframe=NULL) {
   static int static.hWndSelf = 0;                                   // mit Initializer gegen Testerbug: wird in Library bei jedem lib::init() zur�ckgesetzt
   bool self = (symbol=="0" && !timeframe);                          // (string) NULL


   // (1) manuelle Suche nach eigenem Chart
   if (self) {
      if (static.hWndSelf != 0)
         return(static.hWndSelf);

      if (IsTesting()) /*&&*/ if (!IsVisualModeFix()) {              // Expert/Indikator im Tester bei VisualMode=Off: kein Chart
         static.hWndSelf = -1;                                       // R�ckgabewert -1
         return(static.hWndSelf);
      }

      int hWnd  = WindowHandle(Symbol(), NULL);
      int error = GetLastError();
      if (IsError(error)) return(!catch("WindowHandleEx(1)", error));

      if (!hWnd) {
         int hWndMain = GetApplicationWindow();               if (!hWndMain) return(NULL);
         int hWndMdi  = GetDlgItem(hWndMain, IDD_MDI_CLIENT); if (!hWndMdi)  return(!catch("WindowHandleEx(2)  MDIClient window not found (hWndMain = 0x"+ IntToHexStr(hWndMain) +")", ERR_RUNTIME_ERROR));

         bool missingWnd = false;
         string title, sError;

         // Es mu� genau ein Child des MDIClient-Windows mit leerer Titelzeile geben, und zwar das letzte in Z order:
         int hWndChild = GetWindow(hWndMdi, GW_CHILD);               // das erste Child in Z order
         if (!hWndChild) {
            missingWnd = true; sError = "WindowHandleEx(3)  no child window of MDIClient window found";
         }
         else {
            int hWndLast = GetWindow(hWndChild, GW_HWNDLAST);        // das letzte Child in Z order
            title = GetWindowText(hWndLast);
            if (StringLen(title) > 0) {
               missingWnd = true; sError = "WindowHandleEx(4)  last child window of MDIClient window doesn't have an empty title \""+ title +"\"";
            }
         }

         // Ein Indikator im Template "Tester.tpl" wird im Tester bei VisualMode=Off im UI-Thread geladen und seine init()-Funktion ausgef�hrt,
         // obwohl f�r den Test kein Chart existiert. Nur in dieser Kombination ist ein fehlendes Chartfenster ein g�ltiger Zustand.
         if (missingWnd) {
            if (IsIndicator()) /*&&*/ if (__WHEREAMI__!=FUNC_START) /*&&*/ if (GetCurrentThreadId()==GetUIThreadId()) {
               static.hWndSelf = -1;                                 // R�ckgabewert -1
               return(static.hWndSelf);
            }
            return(!catch(sError +" in context "+ ModuleTypeDescription(ec.Type(__ExecutionContext)) +"::"+ __whereamiDescription(__WHEREAMI__), ERR_RUNTIME_ERROR));
         }

         // Dieses letzte Child hat selbst wieder genau ein Child (AfxFrameOrView), welches das gesuchte ChartWindow mit dem MetaTrader-WindowHandle() ist.
         hWnd = GetWindow(hWndLast, GW_CHILD);
         if (!hWnd) return(!catch("WindowHandleEx(5)  no MetaTrader chart window inside of last MDIClient window 0x"+ IntToHexStr(hWndLast) +" found", ERR_RUNTIME_ERROR));
      }

      static.hWndSelf = hWnd;
      return(hWnd);
   }


   if (symbol == "0") symbol = Symbol();                             // (string) NULL
   if (!timeframe) timeframe = Period();
   string periodDescription  = PeriodDescription(timeframe);


   // (2) eingebaute Suche nach fremdem Chart
   hWnd  = WindowHandle(symbol, timeframe);
   error = GetLastError();
   if (!error)                                  return(hWnd);
   if (error != ERR_FUNC_NOT_ALLOWED_IN_TESTER) return(!catch("WindowHandleEx(6)", error));


   // (3) manuelle Suche nach fremdem Chart (dem ersten passenden in Z order)
   hWndMain  = GetApplicationWindow();               if (!hWndMain) return(NULL);
   hWndMdi   = GetDlgItem(hWndMain, IDD_MDI_CLIENT); if (!hWndMdi)  return(!catch("WindowHandleEx(7)  MDIClient window not found (hWndMain = 0x"+ IntToHexStr(hWndMain) +")", ERR_RUNTIME_ERROR));
   hWndChild = GetWindow(hWndMdi, GW_CHILD);                         // das erste Child in Z order
   hWnd      = 0;

   while (hWndChild != NULL) {
      title = GetWindowText(hWndChild);
      if (title == periodDescription) {
         // Das Child hat selbst wieder genau ein Child (AfxFrameOrView), welches das gesuchte ChartWindow mit dem MetaTrader-WindowHandle() ist.
         hWnd = GetWindow(hWndChild, GW_CHILD);
         if (!hWnd) return(!catch("WindowHandleEx(8)  no MetaTrader chart window inside of MDIClient window 0x"+ IntToHexStr(hWndChild) +" found", ERR_RUNTIME_ERROR));
         break;
      }
      hWndChild = GetWindow(hWndChild, GW_HWNDNEXT);                 // das n�chste Child in Z order
   }
   return(hWnd);
}


/**
 * Gibt das Handle des Terminal-Hauptfensters zur�ck.
 *
 * @return int - Handle oder 0, falls ein Fehler auftrat
 */
int GetApplicationWindow() {
   static int hWnd;                                                  // ohne Initializer, @see MQL.doc
   if (hWnd != 0)
      return(hWnd);

   // ClassName des Terminal-Hauptfensters (alle Builds)
   string terminalClassName = "MetaQuotes::MetaTrader::4.00";


   // (1) mit WindowHandle(), schl�gt jedoch in etlichen Situationen fehl: init(), deinit(), in start() bei Terminalstart, im Tester bei VisualMode=Off
   if (IsChart) {
      hWnd = WindowHandle(Symbol(), NULL);               // !!!!!! Hier nicht WindowHandleEx() verwenden, da das zu einer rekursiven Schleife f�hrt !!!!!!
      if (hWnd != 0) {                                   // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         hWnd = GetAncestor(hWnd, GA_ROOT);
         if (GetClassName(hWnd) == terminalClassName)
            return(hWnd);
         warn("GetApplicationWindow(1)  unknown terminal top-level window found (class \""+ GetClassName(hWnd) +"\"), hWndChild originated from WindowHandle()", ERR_RUNTIME_ERROR);
         hWnd = 0;
      }
   }


   // (2) ohne WindowHandle() alle Top-Level-Windows durchlaufen
   int processId[1], hWndNext=GetTopWindow(NULL), myProcessId=GetCurrentProcessId();

   while (hWndNext != 0) {
      GetWindowThreadProcessId(hWndNext, processId);
      if (processId[0]==myProcessId) /*&&*/ if (GetClassName(hWndNext)==terminalClassName)
         break;
      hWndNext = GetWindow(hWndNext, GW_HWNDNEXT);
   }
   if (!hWndNext) {
      catch("GetApplicationWindow(2)  cannot find application main window", ERR_RUNTIME_ERROR);
      hWnd = 0;
   }
   hWnd = hWndNext;

   return(hWnd);
}


/**
 * Gibt den Klassennamen des angegebenen Fensters zur�ck.
 *
 * @param  int hWnd - Handle des Fensters
 *
 * @return string - Klassenname oder Leerstring, falls ein Fehler auftrat
 */
string GetClassName(int hWnd) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   int chars = GetClassNameA(hWnd, buffer[0], bufferSize);

   while (chars >= bufferSize-1) {                                   // GetClassNameA() gibt beim Abschneiden zu langer Klassennamen {bufferSize-1} zur�ck.
      bufferSize <<= 1;
      InitializeStringBuffer(buffer, bufferSize);
      chars = GetClassNameA(hWnd, buffer[0], bufferSize);
   }

   if (!chars)
      return(_emptyStr(catch("GetClassName()->user32::GetClassNameA()", ERR_WIN32_ERROR)));

   return(buffer[0]);
}


/**
 * Ob das aktuelle Programm im Tester l�uft und der VisualMode-Status aktiv ist.
 *
 * Bugfix f�r IsVisualMode(). IsVisualMode() wird in Libraries zwischen aufeinanderfolgenden Tests nicht zur�ckgesetzt und gibt bis zur
 * Neuinitialisierung den Status des ersten Tests zur�ck.
 *
 * @return bool
 */
bool IsVisualModeFix() {
   if (IsTesting())
      return(ec.VisualMode(__ExecutionContext));
   return(false);
}


/**
 * Ob der angegebene Wert einen Fehler darstellt.
 *
 * @param  int value
 *
 * @return bool
 */
bool IsError(int value) {
   return(value != NO_ERROR);
}


/**
 * Ob der interne Fehler-Code des aktuellen Moduls gesetzt ist.
 *
 * @return bool
 */
bool IsLastError() {
   return(last_error != NO_ERROR);
}


/**
 * Setzt den internen Fehlercode des aktuellen Moduls zur�ck.
 *
 * @return int - der vorm Zur�cksetzen gesetzte Fehlercode
 */
int ResetLastError() {
   int error = last_error;
   SetLastError(NO_ERROR, NULL);
   return(error);
}


/**
 * Pr�ft, ob Events der angegebenen Typen aufgetreten sind und ruft bei Zutreffen deren Eventhandler auf.
 *
 * @param  int events - Event-Flags
 *
 * @return bool - ob mindestens eines der angegebenen Events aufgetreten ist
 *
 *
 * NOTE: Statt dieser Funktion kann HandleEvent() benutzt werden, um f�r die Pr�fung weitere event-spezifische Parameter anzugeben.
 */
bool HandleEvents(int events) {
   int status = 0;

   if (events & EVENT_BAR_OPEN        != 0) status |= HandleEvent(EVENT_BAR_OPEN       );
   if (events & EVENT_ORDER_PLACE     != 0) status |= HandleEvent(EVENT_ORDER_PLACE    );
   if (events & EVENT_ORDER_CHANGE    != 0) status |= HandleEvent(EVENT_ORDER_CHANGE   );
   if (events & EVENT_ORDER_CANCEL    != 0) status |= HandleEvent(EVENT_ORDER_CANCEL   );
   if (events & EVENT_ACCOUNT_CHANGE  != 0) status |= HandleEvent(EVENT_ACCOUNT_CHANGE );
   if (events & EVENT_ACCOUNT_PAYMENT != 0) status |= HandleEvent(EVENT_ACCOUNT_PAYMENT);
   if (events & EVENT_CHART_CMD       != 0) status |= HandleEvent(EVENT_CHART_CMD      );
   if (events & EVENT_INTERNAL_CMD    != 0) status |= HandleEvent(EVENT_INTERNAL_CMD   );
   if (events & EVENT_EXTERNAL_CMD    != 0) status |= HandleEvent(EVENT_EXTERNAL_CMD   );

   return(status != 0);
}


/**
 * Pr�ft, ob ein Event aufgetreten ist und ruft ggf. dessen Eventhandler auf. Erm�glicht die Angabe weiterer
 * eventspezifischer Pr�fungskriterien.
 *
 * @param  int event    - Event-Flag
 * @param  int criteria - weitere eventspezifische Pr�fungskriterien (default: keine)
 *
 * @return int - 1, wenn ein Event aufgetreten ist;
 *               0  andererseits
 */
int HandleEvent(int event, int criteria=NULL) {
   bool   status;
   int    iResults[];                                                // die Arrays m�ssen von den Listenern selbst zur�ckgesetzt werden
   string sResults[];

   switch (event) {
      case EVENT_BAR_OPEN       : if (EventListener.BarOpen        (iResults, criteria)) { status = true; onBarOpen        (iResults); } break;
      case EVENT_ORDER_PLACE    : if (EventListener.OrderPlace     (iResults, criteria)) { status = true; onOrderPlace     (iResults); } break;
      case EVENT_ORDER_CHANGE   : if (EventListener.OrderChange    (iResults, criteria)) { status = true; onOrderChange    (iResults); } break;
      case EVENT_ORDER_CANCEL   : if (EventListener.OrderCancel    (iResults, criteria)) { status = true; onOrderCancel    (iResults); } break;
      case EVENT_ACCOUNT_CHANGE : if (EventListener.AccountChange  (iResults, criteria)) { status = true; onAccountChange  (iResults); } break;
      case EVENT_ACCOUNT_PAYMENT: if (EventListener.AccountPayment (iResults, criteria)) { status = true; onAccountPayment (iResults); } break;
      case EVENT_CHART_CMD      : if (EventListener.ChartCommand   (sResults, criteria)) { status = true; onChartCommand   (sResults); } break;
      case EVENT_INTERNAL_CMD   : if (EventListener.InternalCommand(sResults, criteria)) { status = true; onInternalCommand(sResults); } break;
      case EVENT_EXTERNAL_CMD   : if (EventListener.ExternalCommand(sResults, criteria)) { status = true; onExternalCommand(sResults); } break;

      default:
         return(!catch("HandleEvent(1)  unknown event = "+ event, ERR_INVALID_FUNCTION_PARAMVALUE));
   }
   return(status);                                                   // (int) bool
}


int stack.orderSelections[];                                         // @see OrderPush(), OrderPop()


/**
 * Ob das angegebene Ticket existiert und erreichbar ist.
 *
 * @param  int ticket - Ticket-Nr.
 *
 * @return bool
 *
 *
 * NOTE: In der Headerdatei implementiert, da OrderSelect() und die Orderfunktionen nur im jeweils selben Modul benutzt werden k�nnen.
 */
bool IsTicket(int ticket) {
   OrderPush("IsTicket(1)");

   bool result = OrderSelect(ticket, SELECT_BY_TICKET);

   GetLastError();
   OrderPop("IsTicket(2)");

   return(result);
}


/**
 * Selektiert ein Ticket.
 *
 * @param  int    ticket                  - Ticket-Nr.
 * @param  string location                - Bezeichner f�r evt. Fehlermeldung
 * @param  bool   storeSelection          - ob die aktuelle Selektion gespeichert werden soll (default: nein)
 * @param  bool   onErrorRestoreSelection - ob im Fehlerfall die letzte Selektion wiederhergestellt werden soll
 *                                          (default: bei storeSelection=TRUE ja; bei storeSelection=FALSE nein)
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: In der Headerdatei implementiert, da OrderSelect() und die Orderfunktionen nur im jeweils selben Modul benutzt werden k�nnen.
 */
bool SelectTicket(int ticket, string location, bool storeSelection=false, bool onErrorRestoreSelection=false) {
   storeSelection          = storeSelection!=0;
   onErrorRestoreSelection = onErrorRestoreSelection!=0;

   if (storeSelection) {
      OrderPush(location);
      onErrorRestoreSelection = true;
   }

   if (OrderSelect(ticket, SELECT_BY_TICKET))
      return(true);                             // Success

   if (onErrorRestoreSelection)                 // Fehler
      OrderPop(location);

   int error = GetLastError();
   return(!catch(location +"->SelectTicket()   ticket="+ ticket, ifInt(!error, ERR_INVALID_TICKET, error)));
}


/**
 * Schiebt den aktuellen Orderkontext auf den Kontextstack (f�gt ihn ans Ende an).
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return int - Ticket des aktuellen Kontexts oder 0, wenn keine Order selektiert ist oder ein Fehler auftrat
 *
 *
 * NOTE: In der Headerdatei implementiert, da OrderSelect() und die Orderfunktionen nur im jeweils selben Modul benutzt werden k�nnen.
 */
int OrderPush(string location) {
   int error = GetLastError();
   if (IsError(error))
      return(_NULL(catch(location +"->OrderPush(1)", error)));

   int ticket = OrderTicket();

   error = GetLastError();
   if (IsError(error)) /*&&*/ if (error != ERR_NO_ORDER_SELECTED)
      return(_NULL(catch(location +"->OrderPush(2)", error)));

   ArrayPushInt(stack.orderSelections, ticket);
   return(ticket);
}


/**
 * Entfernt den letzten Orderkontext vom Ende des Kontextstacks und restauriert ihn.
 *
 * @param  string location - Bezeichner f�r eine evt. Fehlermeldung
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: In der Headerdatei implementiert, da OrderSelect() und die Orderfunktionen nur im jeweils selben Modul benutzt werden k�nnen.
 */
bool OrderPop(string location) {
   int ticket = ArrayPopInt(stack.orderSelections);

   if (ticket > 0)
      return(SelectTicket(ticket, StringConcatenate(location, "->OrderPop()")));

   OrderSelect(0, SELECT_BY_TICKET);
   return(true);
}


/**
 * Wartet darauf, da� das angegebene Ticket im OpenOrders- bzw. History-Pool des Accounts erscheint.
 *
 * @param  int  ticket    - Orderticket
 * @param  bool orderKeep - ob der aktuelle Orderkontext bewahrt werden soll (default: ja)
 *                          wenn FALSE, ist das angegebene Ticket nach R�ckkehr selektiert
 *
 * @return bool - Erfolgsstatus
 *
 *
 * NOTE: In der Headerdatei implementiert, um Default-Parameter zu erm�glichen.
 */
bool WaitForTicket(int ticket, bool orderKeep=true) {
   orderKeep = orderKeep!=0;

   if (ticket <= 0)
      return(!catch("WaitForTicket(1)  illegal parameter ticket = "+ ticket, ERR_INVALID_FUNCTION_PARAMVALUE));

   if (orderKeep) {
      if (!OrderPush("WaitForTicket(2)"))
         return(!last_error);
   }

   int i, delay=100;                                                 // je 0.1 Sekunden warten

   while (!OrderSelect(ticket, SELECT_BY_TICKET)) {
      if (IsTesting())       warn(StringConcatenate("WaitForTicket(3)  #", ticket, " not yet accessible"));
      else if (i && !(i%10)) warn(StringConcatenate("WaitForTicket(4)  #", ticket, " not yet accessible after ", DoubleToStr(i*delay/1000., 1), " s"));
      Sleep(delay);
      i++;
   }

   if (orderKeep) {
      if (!OrderPop("WaitForTicket(5)"))
         return(false);
   }

   return(true);
}


/**
 * Gibt den PipValue des aktuellen Instrument f�r die angegebene Lotsize zur�ck.
 *
 * @param  double lots       - Lotsize (default: 1 lot)
 * @param  bool   hideErrors - ob Laufzeitfehler abgefangen werden sollen (default: nein)
 *
 * @return double - PipValue oder 0, falls ein Fehler auftrat
 *
 *
 * NOTE: In der Headerdatei implementiert, um Default-Parameter zu erm�glichen.
 */
double PipValue(double lots=1, bool hideErrors=false) {
   hideErrors = hideErrors!=0;

   if (!TickSize) {
      TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);                   // schl�gt fehl, wenn kein Tick vorhanden ist
      int error = GetLastError();                                       // - Symbol (noch) nicht subscribed (Start, Account-/Templatewechsel), kann noch "auftauchen"
      if (IsError(error)) {                                             // - ERR_UNKNOWN_SYMBOL: synthetisches Symbol im Offline-Chart
         if (!hideErrors) catch("PipValue(1)", error);
         return(0);
      }
      if (!TickSize) {
         if (!hideErrors) catch("PipValue(2)  illegal TickSize = 0", ERR_INVALID_MARKET_DATA);
         return(0);
      }
   }

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);             // TODO: wenn QuoteCurrency == AccountCurrency, ist dies nur ein einziges Mal notwendig
   error = GetLastError();
   if (!error) {
      if (!tickValue) {
         if (!hideErrors) catch("PipValue(3)  illegal TickValue = 0", ERR_INVALID_MARKET_DATA);
         return(0);
      }
      return(Pip/TickSize * tickValue * lots);
   }

   if (!hideErrors) catch("PipValue(4)", error);
   return(0);
}


/**
 * Ob das Logging f�r das aktuelle Programm aktiviert ist. Standardm��ig ist das Logging au�erhalb des Testers ON und innerhalb des Testers OFF.
 *
 * @return bool
 *
 *
 * NOTE: In der Headerdatei implementiert, um Verwendung ohne Abh�ngigkeit von stdlib.init() zu erm�glichen.
 */
bool IsLogging() {
   string name = __NAME__;
   if (IsLibrary()) {
      if (!StringLen(__NAME__))
         return(!catch("IsLogging(1)  library not initialized", ERR_RUNTIME_ERROR));
      name = StringSubstr(__NAME__, 0, StringFind(__NAME__, ":")) ;
   }

   if (!This.IsTesting()) return(GetConfigBool("Logging", name,     true ));      // Online:    default=ON
   else                   return(GetConfigBool("Logging", "Tester", false));      // im Tester: default=OFF
}


/**
 * Inlined conditional Boolean-Statement.
 *
 * @param  bool condition
 * @param  bool thenValue
 * @param  bool elseValue
 *
 * @return bool
 */
bool ifBool(bool condition, bool thenValue, bool elseValue) {
   if (condition!=0)
      return(thenValue!=0);
   return(elseValue!=0);
}


/**
 * Inlined conditional Integer-Statement.
 *
 * @param  bool condition
 * @param  int  thenValue
 * @param  int  elseValue
 *
 * @return int
 */
int ifInt(bool condition, int thenValue, int elseValue) {
   if (condition!=0)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional Double-Statement.
 *
 * @param  bool   condition
 * @param  double thenValue
 * @param  double elseValue
 *
 * @return double
 */
double ifDouble(bool condition, double thenValue, double elseValue) {
   if (condition!=0)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional String-Statement.
 *
 * @param  bool   condition
 * @param  string thenValue
 * @param  string elseValue
 *
 * @return string
 */
string ifString(bool condition, string thenValue, string elseValue) {
   if (condition!=0)
      return(thenValue);
   return(elseValue);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Then".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool LT(double double1, double double2, int digits=8) {
   if (EQ(double1, double2, digits))
      return(false);
   return(double1 < double2);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Or-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool LE(double double1, double double2, int digits=8) {
   if (double1 < double2)
      return(true);
   return(EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf Gleichheit "Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool EQ(double double1, double double2, int digits=8) {
   if (digits < 0 || digits > 8)
      return(!catch("EQ()  illegal parameter digits = "+ digits, ERR_INVALID_FUNCTION_PARAMVALUE));

   double diff = NormalizeDouble(double1, digits) - NormalizeDouble(double2, digits);
   if (diff < 0)
      diff = -diff;
   return(diff < 0.000000000000001);

   /*
   switch (digits) {
      case  0: return(diff <= 0                 );
      case  1: return(diff <= 0.1               );
      case  2: return(diff <= 0.01              );
      case  3: return(diff <= 0.001             );
      case  4: return(diff <= 0.0001            );
      case  5: return(diff <= 0.00001           );
      case  6: return(diff <= 0.000001          );
      case  7: return(diff <= 0.0000001         );
      case  8: return(diff <= 0.00000001        );
      case  9: return(diff <= 0.000000001       );
      case 10: return(diff <= 0.0000000001      );
      case 11: return(diff <= 0.00000000001     );
      case 12: return(diff <= 0.000000000001    );
      case 13: return(diff <= 0.0000000000001   );
      case 14: return(diff <= 0.00000000000001  );
      case 15: return(diff <= 0.000000000000001 );
      case 16: return(diff <= 0.0000000000000001);
   }
   return(!catch("EQ()  illegal parameter digits = "+ digits, ERR_INVALID_FUNCTION_PARAMVALUE));
   */
}


/**
 * Korrekter Vergleich zweier Doubles auf Ungleichheit "Not-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool NE(double double1, double double2, int digits=8) {
   return(!EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Or-Equal".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool GE(double double1, double double2, int digits=8) {
   if (double1 > double2)
      return(true);
   return(EQ(double1, double2, digits));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Then".
 *
 * @param  double double1 - erster Wert
 * @param  double double2 - zweiter Wert
 * @param  int    digits  - Anzahl der zu ber�cksichtigenden Nachkommastellen (default: 8)
 *
 * @return bool
 */
bool GT(double double1, double double2, int digits=8) {
   if (EQ(double1, double2, digits))
      return(false);
   return(double1 > double2);
}


/**
 * Ob der Wert eines Doubles NaN (Not-a-Number) ist.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsNaN(double value) {
   string s = value;
   return(s == "-1.#IND0000");
}


/**
 * Ob der Wert eines Doubles Infinite ist.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsInfinite(double value) {
   string s = value;
   return(s == "-1.#INF0000");
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als boolean TRUE zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return bool - TRUE
 */
bool _true(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(true);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als boolean FALSE zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return bool - FALSE
 */
bool _false(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(false);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als NULL = 0 (int) zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - NULL
 */
int _NULL(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NULL);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den Fehlerstatus NO_ERROR zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden. Ist funktional identisch zu _NULL().
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - NO_ERROR
 */
int _NO_ERROR(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NO_ERROR);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den letzten Fehlercode zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - last_error
 */
int _last_error(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(last_error);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante EMPTY (0xFFFFFFFF = -1) zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - EMPTY
 */
int _EMPTY(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(EMPTY);
}


/**
 * Ob der angegebene Wert die Konstante EMPTY darstellt.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsEmpty(double value) {
   return(value == EMPTY);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante EMPTY_VALUE (0x7FFFFFFF = 2147483647 = INT_MAX) zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - EMPTY_VALUE
 */
int _EMPTY_VALUE(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(EMPTY_VALUE);
}


/**
 * Ob der angegebene Wert die Konstante EMPTY_VALUE darstellt.
 *
 * @param  double value
 *
 * @return bool
 */
bool IsEmptyValue(double value) {
   return(value == EMPTY_VALUE);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als einen Leerstring ("") zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return string - Leerstring
 */
string _emptyStr(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return("");
}


/**
 * Ob der angegebene Wert einen Leerstring darstellt.
 *
 * @param  string value
 *
 * @return bool
 */
bool IsEmptyString(string value) {
   return(value == "");
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als die Konstante NaT (NotATime: 0x80000000 = -2147483648 = INT_MIN = D'1901-12-13 20:45:52') zur�ckzugeben.
 * Kann zur Verbesserung der �bersichtlichkeit und Lesbarkeit verwendet werden.
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return int - NaT (NotATime)
 */
int _NaT(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(NaT);
}


/**
 * Ob der angegebene Wert die Konstante NaT (Not-A-Time) darstellt.
 *
 * @param  datetime value
 *
 * @return bool
 */
bool IsNaT(datetime value) {
   return(value == NaT);
}


/**
 * Pseudo-Funktion, die nichts tut oder zur�ckgibt. Dummy-Statement
 *
 * @param  beliebige Parameter (werden ignoriert)
 *
 * @return void
 */
void _void(int param1=NULL, int param2=NULL, int param3=NULL, int param4=NULL) {
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  bool param1 - Boolean
 * @param  ...         - beliebige weitere Parameter (werden ignoriert)
 *
 * @return bool - der erste Parameter
 */
bool _bool(bool param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1!=0);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  int param1 - Integer
 * @param  ...        - beliebige weitere Parameter (werden ignoriert)
 *
 * @return int - der erste Parameter
 */
int _int(int param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  double param1 - Double
 * @param  ...           - beliebige weitere Parameter (werden ignoriert)
 *
 * @return double - der erste Parameter
 */
double _double(double param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Pseudo-Funktion, die nichts weiter tut, als den ersten Parameter zur�ckzugeben. Kann zur Verbesserung der �bersichtlichkeit
 * und Lesbarkeit verwendet werden.
 *
 * @param  string param1 - String
 * @param  ...           - beliebige weitere Parameter (werden ignoriert)
 *
 * @return string - der erste Parameter
 */
string _string(string param1, int param2=NULL, int param3=NULL, int param4=NULL) {
   return(param1);
}


/**
 * Integer-Version von MathMin()
 *
 * Ermittelt die kleinere zweier Ganzzahlen.
 *
 * @param  int  value1
 * @param  int  value2
 *
 * @return int
 */
int Min(int value1, int value2) {
   if (value1 < value2)
      return(value1);
   return(value2);
}


/**
 * Integer-Version von MathMax()
 *
 * Ermittelt die gr��ere zweier Ganzzahlen.
 *
 * @param  int  value1
 * @param  int  value2
 *
 * @return int
 */
int Max(int value1, int value2) {
   if (value1 > value2)
      return(value1);
   return(value2);
}


/**
 * Integer-Version von MathAbs()
 *
 * Ermittelt den Absolutwert einer Ganzzahl.
 *
 * @param  int  value
 *
 * @return int
 */
int Abs(int value) {
   if (value < 0)
      return(-value);
   return(value);
}


/**
 * Gibt das Vorzeichen einer Zahl zur�ck.
 *
 * @param  double number - Zahl
 *
 * @return int - Vorzeichen (+1, 0, -1)
 */
int Sign(double number) {
   if (GT(number, 0)) return( 1);
   if (LT(number, 0)) return(-1);
   return(0);
}


/**
 * Integer-Version von MathRound()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Round(double value) {
   return(MathRound(value));
}


/**
 * Erweiterte Version von MathRound(), rundet auf die angegebene Anzahl von positiven oder negativen Dezimalstellen.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundEx(double number, int decimals=0) {
   if (decimals > 0)
      return(NormalizeDouble(number, decimals));

   if (decimals == 0)
      return(MathRound(number));

   // decimals < 0
   double factor = MathPow(10, decimals);                            // -1:  1234.5678 => 1230
          number = MathRound(number * factor) / factor;              // -2:  1234.5678 => 1200
          number = MathRound(number);                                // -3:  1234.5678 => 1000
   return(number);
}


/**
 * Erweiterte Version von MathFloor(), rundet mit der angegebenen Anzahl von positiven oder negativen Dezimalstellen ab.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundFloor(double number, int decimals=0) {
   if (decimals > 0) {
      double factor = MathPow(10, decimals);                         // +1:  1234.5678 => 1234.5
             number = MathFloor(number * factor) / factor;           // +2:  1234.5678 => 1234.56
             number = NormalizeDouble(number, decimals);             // +3:  1234.5678 => 1234.567
      return(number);
   }

   if (decimals == 0)
      return(MathFloor(number));

   // decimals < 0
   factor = MathPow(10, decimals);                                   // -1:  1234.5678 => 1230
   number = MathFloor(number * factor) / factor;                     // -2:  1234.5678 => 1200
   number = MathRound(number);                                       // -3:  1234.5678 => 1000
   return(number);
}


/**
 * Erweiterte Version von MathCeil(), rundet mit der angegebenen Anzahl von positiven oder negativen Dezimalstellen auf.
 *
 * @param  double number
 * @param  int    decimals (default: 0)
 *
 * @return double - rounded value
 */
double RoundCeil(double number, int decimals=0) {
   if (decimals > 0) {
      double factor = MathPow(10, decimals);                         // +1:  1234.5678 => 1234.6
             number = MathCeil(number * factor) / factor;            // +2:  1234.5678 => 1234.57
             number = NormalizeDouble(number, decimals);             // +3:  1234.5678 => 1234.568
      return(number);
   }

   if (decimals == 0)
      return(MathCeil(number));

   // decimals < 0
   factor = MathPow(10, decimals);                                   // -1:  1234.5678 => 1240
   number = MathCeil(number * factor) / factor;                      // -2:  1234.5678 => 1300
   number = MathRound(number);                                       // -3:  1234.5678 => 2000
   return(number);
}


/**
 * Integer-Version von MathFloor()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Floor(double value) {
   return(MathFloor(value));
}


/**
 * Integer-Version von MathCeil()
 *
 * @param  double value - Zahl
 *
 * @return int
 */
int Ceil(double value) {
   return(MathCeil(value));
}


/**
 * Dividiert zwei Doubles und f�ngt dabei eine Division durch 0 ab.
 *
 * @param  double a      - Divident
 * @param  double b      - Divisor
 * @param  double onZero - Ergebnis f�r den Fall, das der Divisor 0 ist (default: 0)
 *
 * @return double
 */
double MathDiv(double a, double b, double onZero=0) {
   if (!b)
      return(onZero);
   return(a/b);
}


/**
 * Integer-Version von MathDiv(). Dividiert zwei Integers und f�ngt dabei eine Division durch 0 ab.
 *
 * @param  int a      - Divident
 * @param  int b      - Divisor
 * @param  int onZero - Ergebnis f�r den Fall, das der Divisor 0 ist (default: 0)
 *
 * @return int
 */
int Div(int a, int b, int onZero=0) {
   if (!b)
      return(onZero);
   return(a/b);
}


/**
 * Pr�ft, ob eine Stringvariable initialisiert oder nicht-initialisiert (NULL-Pointer) ist.
 *
 * @param  string value - zu pr�fende Stringvariable
 *
 * @return bool
 */
bool StringIsNull(string value) {
   int error = GetLastError();

   if (error == ERR_NOT_INITIALIZED_STRING)
      return(true);

   if (error != NO_ERROR)
      catch("StringIsNull()", error);

   return(false);
}


/**
 * F�gt ein Element am Beginn eines String-Arrays an.
 *
 * @param  string array[] - String-Array
 * @param  string value   - hinzuzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays oder -1 (EMPTY), falls ein Fehler auftrat
 *
 *
 * NOTE: Mu� global definiert werden. Die intern benutzte Funktion ReverseStringArray() ruft ihrerseits ArraySetAsSeries() auf, dessen Verhalten mit einem
 *       String-Parameter fehlerhaft (offiziell: nicht unterst�tzt) ist. Unter ungekl�rten Umst�nden wird das �bergebene Array zerschossen, es enth�lt dann
 *       Zeiger auf andere im Programm existierende Strings. Dieser Fehler trat in Indikatoren auf, wenn ArrayUnshiftString() in einer MQL-Library definiert
 *       war und �ber Modulgrenzen aufgerufen wurde, nicht jedoch bei globaler Definition. Au�erdem trat der Fehler nicht sofort, sondern erst nach Aufruf
 *       anderer Array-Funktionen auf, die mit v�llig unbeteiligten Arrays/String arbeiteten.
 */
int ArrayUnshiftString(string array[], string value) {
   if (ArrayDimension(array) > 1) return(_EMPTY(catch("ArrayUnshiftString()  too many dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS)));

   ReverseStringArray(array);
   int size = ArrayPushString(array, value);
   ReverseStringArray(array);
   return(size);
}


/**
 * Gibt die ID des Userinterface-Threads zur�ck.
 *
 * @return int - Thread-ID (nicht das Pseudo-Handle) oder 0, falls ein Fehler auftrat
 */
int GetUIThreadId() {
   static int threadId;                                              // ohne Initializer, @see MQL.doc
   if (threadId != 0)
      return(threadId);

   int iNull[], hWnd=GetApplicationWindow();
   if (!hWnd)
      return(0);

   threadId = GetWindowThreadProcessId(hWnd, iNull);

   return(threadId);
}


/**
 * Unterdr�ckt unn�tze Compilerwarnungen.
 */
void __DummyCalls() {
   int    iNull;
   string sNulls[];

   IsExpert();
   IsScript();
   IsIndicator();
   IsLibrary();

   Expert.IsTesting();
   Script.IsTesting();
   Indicator.IsTesting();
   This.IsTesting();

   InitReason();
   DeinitReason();

   IsSuperContext();
   SetLastError(NULL, NULL);
   UpdateProgramStatus();

   __log.custom(NULL);
   _bool(NULL);
   _double(NULL);
   _emptyStr();
   _EMPTY();
   _EMPTY_VALUE();
   _false();
   _int(NULL);
   _last_error();
   _NaT();
   _NO_ERROR();
   _NULL();
   _string(NULL);
   _true();
   _void();
   Abs(NULL);
   ArrayUnshiftString(sNulls, NULL);
   catch(NULL, NULL, NULL);
   Ceil(NULL);
   debug(NULL);
   Div(NULL, NULL);
   DummyCalls();
   EQ(NULL, NULL);
   Floor(NULL);
   GE(NULL, NULL);
   GetUIThreadId();
   GT(NULL, NULL);
   HandleEvent(NULL);
   HandleEvents(NULL);
   ifBool(NULL, NULL, NULL);
   ifDouble(NULL, NULL, NULL);
   ifInt(NULL, NULL, NULL);
   ifString(NULL, NULL, NULL);
   IsEmpty(NULL);
   IsEmptyString(NULL);
   IsEmptyValue(NULL);
   IsError(NULL);
   IsInfinite(NULL);
   IsLastError();
   IsLogging();
   IsNaN(NULL);
   IsNaT(NULL);
   IsTicket(NULL);
   LE(NULL, NULL);
   log(NULL);
   LT(NULL, NULL);
   MathDiv(NULL, NULL);
   Max(NULL, NULL);
   Min(NULL, NULL);
   NE(NULL, NULL);
   OrderPop(NULL);
   OrderPush(NULL);
   PipValue();
   ResetLastError();
   Round(NULL);
   RoundCeil(NULL);
   RoundEx(NULL);
   RoundFloor(NULL);
   SelectTicket(NULL, NULL);
   Sign(NULL);
   start.RelaunchInputDialog();
   StringIsNull(NULL);
   StringReplace(NULL, NULL, NULL);
   StringSubstrFix(NULL, NULL);
   WaitForTicket(NULL);
   warn(NULL);
   warnSMS(NULL);
   WindowHandleEx(NULL);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


/*
#import "this-library-doesnt-exist.ex4"                              // zum Testen von stddefine.mqh ohne "core"-Dateien
   bool   IsExpert();
   bool   IsScript();
   bool   IsIndicator();
   bool   IsLibrary();
   bool   Expert.IsTesting();
   bool   Script.IsTesting();
   int    Indicator.IsTesting();
   int    This.IsTesting();
   int    InitReason();
   int    DeinitReason();
   bool   IsSuperContext();
   int    SetLastError(int error, int param);
*/
#import "stdlib1.ex4"
   bool   EventListener.AccountChange  (int    data[], int criteria);
   bool   EventListener.AccountPayment (int    data[], int criteria);
   bool   EventListener.BarOpen        (int    data[], int criteria);
   bool   EventListener.ChartCommand   (string data[], int criteria);
   bool   EventListener.ExternalCommand(string data[], int criteria);
   bool   EventListener.InternalCommand(string data[], int criteria);
   bool   EventListener.OrderCancel    (int    data[], int criteria);
   bool   EventListener.OrderChange    (int    data[], int criteria);
   bool   EventListener.OrderPlace     (int    data[], int criteria);

   bool   onAccountChange  (int    data[]);
   bool   onAccountPayment (int    data[]);
   bool   onBarOpen        (int    data[]);
   bool   onChartCommand   (string data[]);
   bool   onExternalCommand(string data[]);
   bool   onInternalCommand(string data[]);
   bool   onOrderCancel    (int    data[]);
   bool   onOrderChange    (int    data[]);
   bool   onOrderPlace     (int    data[]);

   int    ArrayPopInt(int array[]);
   int    ArrayPushInt(int array[], int value);
   int    ArrayPushString(string array[], string value);
   int    Chart.Expert.Properties();
   void   DummyCalls();                                              // Library-Stub: kann lokal �berschrieben werden (mu� aber nicht)
   int    GetApplicationWindow();
   bool   GetConfigBool(string section, string key, bool defaultValue);
   int    GetCustomLogID();
   bool   GetLocalConfigBool(string section, string key, bool defaultValue);
   string GetWindowText(int hWnd);
   int    InitializeStringBuffer(string buffer[], int length);
   string IntToHexStr(int integer);
   bool   IsFile(string filename);
   string ModuleTypeDescription(int type);
   bool   ReverseStringArray(string array[]);
   bool   SendSMS(string receiver, string message);
   string StdSymbol();
   bool   StringContains(string object, string substring);
   string StringLeft(string value, int n);
   string StringRight(string value, int n);
   string StringPadRight(string input, int length, string pad_string);

#import "struct.EXECUTION_CONTEXT.ex4"
   int    ec.Type      (/*EXECUTION_CONTEXT*/int ec[]);
   bool   ec.VisualMode(/*EXECUTION_CONTEXT*/int ec[]);

#import "StdLib.dll"
   int    GetLastWin32Error();
   bool   IsBuiltinTimeframe(int timeframe);

#import "kernel32.dll"
   int    GetCurrentProcessId();
   int    GetCurrentThreadId();
   void   OutputDebugStringA(string lpMessage);                      // funktioniert nur f�r Admins zuverl�ssig

#import "user32.dll"
   int    GetAncestor(int hWnd, int cmd);
   int    GetClassNameA(int hWnd, string lpBuffer, int bufferSize);
   int    GetDlgItem(int hDlg, int nIDDlgItem);
   int    GetTopWindow(int hWnd);
   int    GetWindow(int hWnd, int cmd);
   int    GetWindowThreadProcessId(int hWnd, int lpProcessId[]);
   int    MessageBoxA(int hWnd, string lpText, string lpCaption, int style);

#import "winmm.dll"
   bool   PlaySoundA(string lpSound, int hMod, int fSound);
#import
