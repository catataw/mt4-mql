
// eindeutige ID der Strategie (Bereich 101-1023)
#define STRATEGY_ID            103


// Grid-Directions
#define D_BIDIR                  0                    // default
#define D_LONG                   1
#define D_SHORT                  2
#define D_LONG_SHORT             3


// Sequenzstatus-Werte
#define STATUS_UNINITIALIZED     0                    // default
#define STATUS_WAITING           1
#define STATUS_PROGRESSING       2
#define STATUS_STOPPING          3
#define STATUS_STOPPED           4
#define STATUS_DISABLED          5


// OrderDisplay-Modes
#define DM_NONE                  0                    // - keine Anzeige -
#define DM_STOPS                 1                    // Pending,       ClosedByStop
#define DM_PYRAMID               2                    // Pending, Open,               Closed (default)
#define DM_ALL                   3                    // Pending, Open, ClosedByStop, Closed


// OrderDisplay-Farben
#define CLR_LONG           Blue
#define CLR_SHORT          Red
#define CLR_CLOSE          Orange
