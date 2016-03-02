/**
 * MT4 structure TICK (Format der Datei "ticks.raw")
 *
 *                                  size        offset
 * struct TICK {                    ----        ------
 *    char   symbol[12];             12            0        // Symbol (szchar)
 *    int    time;                    4           12        // Timestamp
 *    double bid;                     8           16
 *    double ask;                     8           24
 *    int    counter;                 4           32        // fortlaufender Z�hler innerhalb der Datei
 *    BYTE   undocumented[4];         4           36
 * } t;                            = 40 byte
 */
