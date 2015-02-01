/**
 * MQL structure EXECUTION_CONTEXT
 *
 *                                    size         offset
 * struct EXECUTION_CONTEXT {         ----         ------
 *    int    signature;                  4      => ec[ 0]      // Signatur                                        (konstant)   => Validierung des Speicherblocks
 *    LPTSTR lpName;                     4      => ec[ 1]      // Zeiger auf Programmnamen                        (konstant)   => wie hei�e ich
 *    int    type;                       4      => ec[ 2]      // Programmtyp                                     (konstant)   => was bin ich
 *    int    hChart;                     4      => ec[ 3]      // Chart         (Handle f�r Ticks)                (konstant)   => habe ich einen Chart und welchen
 *    int    hChartWindow;               4      => ec[ 4]      // Chart-Fenster (Handle f�r Titelzeile)           (konstant)   => ...
 *    int    testFlags;                  4      => ec[ 5]      // Tester-Flags: Off|On|VisualMode|Optimization    (konstant)   => laufe ich im Tester und wie
 *    LPTR   lpSuperContext;             4      => ec[ 6]      // �bergeordneter Execution-Context                (konstant)   => wie wurde ich geladen
 *    int    initFlags;                  4      => ec[ 7]      // init-Flags                                      (konstant)   => wie werde ich initialisiert
 *    int    deinitFlags;                4      => ec[ 8]      // deinit-Flags                                    (konstant)   => wie werde ich deinitialisiert
 *    int    uninitializeReason;         4      => ec[ 9]      // letzter Uninitialize-Reason                     (variabel)   => woher komme ich
 *    int    whereami;                   4      => ec[10]      // MQL-Rootfunktion des Programms                  (variabel)   => wo bin ich
 *    BOOL   logging;                    4      => ec[11]      // Logstatus                                       (konstant)   => wie verhalte ich mich
 *    LPTSTR lpLogFile;                  4      => ec[12]      // Zeiger auf Pfad und Namen der Logdatei          (konstant)   => wie verhalte ich mich
 *    int    lastError;                  4      => ec[13]      // letzter aufgetretener Fehler                    (variabel)   => welche Fehler sind aufgetreten
 * } ec;                              = 56 byte = int[14]
 *
 *
 * @see  Importdeklarationen der entsprechenden Library am Ende dieser Datei
 *
 *
 * TODO: __SMS.alerts        integrieren
 *       __SMS.receiver      integrieren
 *       __STATUS_OFF        integrieren
 *       __STATUS_OFF.reason integrieren
 */

// Getter
int    ec.Signature            (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 0]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.lpName               (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 1]);                       EXECUTION_CONTEXT.toStr(ec); }
string ec.Name                 (/*EXECUTION_CONTEXT*/int ec[]                                ) { return(GetString(ec[ 1]));                      EXECUTION_CONTEXT.toStr(ec); }
int    ec.Type                 (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 2]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.hChart               (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 3]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.hChartWindow         (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 4]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.TestFlags            (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 5]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.lpSuperContext       (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 6]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.SuperContext         (/*EXECUTION_CONTEXT*/int ec[], /*EXECUTION_CONTEXT*/int sec[]) {
   if (ArrayDimension(sec) != 1)               return(catch("ec.SuperContext(1)  too many dimensions of parameter sec = "+ ArrayDimension(sec), ERR_INCOMPATIBLE_ARRAYS));
   if (ArraySize(sec) != EXECUTION_CONTEXT.intSize)
      ArrayResize(sec, EXECUTION_CONTEXT.intSize);

   int lpSuperContext = ec.lpSuperContext(ec);
   if (!lpSuperContext) {
      ArrayInitialize(sec, 0);
   }
   else {
      CopyMemory(lpSuperContext, GetBufferAddress(sec), EXECUTION_CONTEXT.size);
      // primitive Zeigervalidierung, es gilt: PTR==*PTR (der Wert des Zeigers ist an der Adresse selbst gespeichert)
      if (ec.Signature(sec) != lpSuperContext) return(catch("ec.SuperContext(2)  invalid super EXECUTION_CONTEXT found at address 0x"+ IntToHexStr(lpSuperContext), ERR_RUNTIME_ERROR));
   }
   return(catch("ec.SuperContext(3)"));                                                                                                          EXECUTION_CONTEXT.toStr(ec);
}
int    ec.InitFlags            (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 7]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.DeinitFlags          (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 8]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.UninitializeReason   (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[ 9]);                       EXECUTION_CONTEXT.toStr(ec); }
int    ec.Whereami             (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[10]);                       EXECUTION_CONTEXT.toStr(ec); }
bool   ec.Logging              (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[11] != 0);                  EXECUTION_CONTEXT.toStr(ec); }
int    ec.lpLogFile            (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[12]);                       EXECUTION_CONTEXT.toStr(ec); }
string ec.LogFile              (/*EXECUTION_CONTEXT*/int ec[]                                ) { return(GetString(ec[12]));                      EXECUTION_CONTEXT.toStr(ec); }
int    ec.LastError            (/*EXECUTION_CONTEXT*/int ec[]                                ) {           return(ec[13]);                       EXECUTION_CONTEXT.toStr(ec); }


// Setter
int    ec.setSignature         (/*EXECUTION_CONTEXT*/int &ec[], int    signature         ) { ec[ 0] = signature;          return(signature         ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setLpName            (/*EXECUTION_CONTEXT*/int &ec[], int    lpName            ) { ec[ 1] = lpName;             return(lpName            ); EXECUTION_CONTEXT.toStr(ec); }
string ec.setName              (/*EXECUTION_CONTEXT*/int &ec[], string name              ) {
   if (!StringLen(name))           return(_emptyStr(catch("ec.setName(1)  invalid parameter name = "+ StringToStr(name), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (StringLen(name) > MAX_PATH) return(_emptyStr(catch("ec.setName(2)  illegal parameter name = \""+ name +"\" (max "+ MAX_PATH +" chars)", ERR_TOO_LONG_STRING)));
   int lpName = ec.lpName(ec);
   if (!lpName)                    return(_emptyStr(catch("ec.setName(3)  no memory allocated for string name (lpName = NULL)", ERR_RUNTIME_ERROR)));
   CopyMemory(GetStringAddress(name), lpName, StringLen(name)+1); /*terminierendes <NUL> wird mitkopiert*/                return(name              ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setType              (/*EXECUTION_CONTEXT*/int &ec[], int    type              ) { ec[ 2] = type;               return(type              ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setHChart            (/*EXECUTION_CONTEXT*/int &ec[], int    hChart            ) { ec[ 3] = hChart;             return(hChart            ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setHChartWindow      (/*EXECUTION_CONTEXT*/int &ec[], int    hChartWindow      ) { ec[ 4] = hChartWindow;       return(hChartWindow      ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setTestFlags         (/*EXECUTION_CONTEXT*/int &ec[], int    testFlags         ) { ec[ 5] = testFlags;          return(testFlags         ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setLpSuperContext    (/*EXECUTION_CONTEXT*/int &ec[], int    lpSuperContext    ) { ec[ 6] = lpSuperContext;     return(lpSuperContext    ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setInitFlags         (/*EXECUTION_CONTEXT*/int &ec[], int    initFlags         ) { ec[ 7] = initFlags;          return(initFlags         ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setDeinitFlags       (/*EXECUTION_CONTEXT*/int &ec[], int    deinitFlags       ) { ec[ 8] = deinitFlags;        return(deinitFlags       ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setUninitializeReason(/*EXECUTION_CONTEXT*/int &ec[], int    uninitializeReason) { ec[ 9] = uninitializeReason; return(uninitializeReason); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setWhereami          (/*EXECUTION_CONTEXT*/int &ec[], int    whereami          ) { ec[10] = whereami;           return(whereami          ); EXECUTION_CONTEXT.toStr(ec); }
bool   ec.setLogging           (/*EXECUTION_CONTEXT*/int &ec[], bool   logging           ) { ec[11] = logging != 0;       return(logging != 0      ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setLpLogFile         (/*EXECUTION_CONTEXT*/int &ec[], int    lpLogFile         ) { ec[12] = lpLogFile;          return(lpLogFile         ); EXECUTION_CONTEXT.toStr(ec); }
string ec.setLogFile           (/*EXECUTION_CONTEXT*/int &ec[], string logFile           ) {
   if (!StringLen(logFile))           return(_emptyStr(catch("ec.setLogFile(1)  invalid parameter logFile = "+ StringToStr(logFile), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (StringLen(logFile) > MAX_PATH) return(_emptyStr(catch("ec.setLogFile(2)  illegal parameter logFile = \""+ logFile +"\" (max. "+ MAX_PATH +" chars)", ERR_TOO_LONG_STRING)));
   int lpLogFile = ec.lpLogFile(ec);
   if (!lpLogFile)                    return(_emptyStr(catch("ec.setLogFile(3)  no memory allocated for string logfile (lpLogFile = NULL)", ERR_RUNTIME_ERROR)));
   CopyMemory(GetStringAddress(logFile), lpLogFile, StringLen(logFile)+1); /*terminierendes <NUL> wird mitkopiert*/       return(logFile           ); EXECUTION_CONTEXT.toStr(ec); }
int    ec.setLastError         (/*EXECUTION_CONTEXT*/int &ec[], int    lastError         ) {
   ec[12] = lastError;
   int lpSuperContext = ec.lpSuperContext(ec);
   if (lpSuperContext != 0)
      CopyMemory(ec.Signature(ec)+13*4, lpSuperContext+13*4, 4);     // Fehler immer auch im SuperContext setzen
   return(lastError);                                                                                                                                 EXECUTION_CONTEXT.toStr(ec);
}


/**
 * Gibt die lesbare Repr�sentation eines EXECUTION_CONTEXT zur�ck.
 *
 * @param  int  ec[]        - EXECUTION_CONTEXT
 * @param  bool outputDebug - ob die Ausgabe zus�tzlich zum Debugger geschickt werden soll (default: nein)
 *
 * @return string
 */
string EXECUTION_CONTEXT.toStr(/*EXECUTION_CONTEXT*/int ec[], bool outputDebug=false) {
   outputDebug = outputDebug!=0;

   if (ArrayDimension(ec) > 1)                     return(_emptyStr(catch("EXECUTION_CONTEXT.toStr(1)  too many dimensions of parameter ec: "+ ArrayDimension(ec), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (ArraySize(ec) != EXECUTION_CONTEXT.intSize) return(_emptyStr(catch("EXECUTION_CONTEXT.toStr(2)  invalid size of parameter ec: "+ ArraySize(ec), ERR_INVALID_FUNCTION_PARAMVALUE)));

   string result = StringConcatenate("{signature="         ,               ifString(!ec.Signature         (ec), "0", "0x"+ IntToHexStr(ec.Signature(ec))),
                                    ", name=\""            ,                         ec.Name              (ec), "\"");
   if (!ec.Type(ec))
          result = result          +", type="+                                       ec.Type              (ec);   // ModuleTypeToStr() gibt f�r ung�ltige ID Leerstring zur�ck
   else   result = result          +", type="+                       ModuleTypeToStr(ec.Type              (ec));
          result = StringConcatenate(result,
                                    ", hChart="            ,               ifString(!ec.hChart            (ec), "0", "0x"+ IntToHexStr(ec.hChart        (ec))),
                                    ", hChartWindow="      ,               ifString(!ec.hChartWindow      (ec), "0", "0x"+ IntToHexStr(ec.hChartWindow  (ec))),
                                    ", testFlags="         ,          TestFlagsToStr(ec.TestFlags         (ec)),
                                    ", superContext="      ,               ifString(!ec.lpSuperContext    (ec), "0", "0x"+ IntToHexStr(ec.lpSuperContext(ec))),
                                    ", initFlags="         ,          InitFlagsToStr(ec.InitFlags         (ec)),
                                    ", deinitFlags="       ,        DeinitFlagsToStr(ec.DeinitFlags       (ec)),
                                    ", uninitializeReason=", UninitializeReasonToStr(ec.UninitializeReason(ec)));
   if (!ec.Whereami(ec))
          result = result          +", whereami="+                                   ec.Whereami          (ec);   // __whereamiToStr() l�st f�r ung�ltige ID Fehler aus
   else   result = result          +", whereami="+                   __whereamiToStr(ec.Whereami          (ec));
          result = StringConcatenate(result,
                                    ", logging="           ,               BoolToStr(ec.Logging           (ec)),
                                    ", logFile=\""         ,                         ec.LogFile           (ec), "\"",
                                    ", lastError="         ,              ErrorToStr(ec.LastError         (ec)), "}");
   if (outputDebug)
      debug("EXECUTION_CONTEXT.toStr()  "+ result);

   catch("EXECUTION_CONTEXT.toStr(3)");
   return(result);


   // Dummy-Calls: unterdr�cken unn�tze Compilerwarnungen
   ec.Signature         (ec    ); ec.setSignature         (ec, NULL);
   ec.lpName            (ec    ); ec.setLpName            (ec, NULL);
   ec.Name              (ec    ); ec.setName              (ec, NULL);
   ec.Type              (ec    ); ec.setType              (ec, NULL);
   ec.hChart            (ec    ); ec.setHChart            (ec, NULL);
   ec.hChartWindow      (ec    ); ec.setHChartWindow      (ec, NULL);
   ec.TestFlags         (ec    ); ec.setTestFlags         (ec, NULL);
   ec.lpSuperContext    (ec    ); ec.setLpSuperContext    (ec, NULL);
   ec.SuperContext      (ec, ec);
   ec.InitFlags         (ec    ); ec.setInitFlags         (ec, NULL);
   ec.DeinitFlags       (ec    ); ec.setDeinitFlags       (ec, NULL);
   ec.UninitializeReason(ec    ); ec.setUninitializeReason(ec, NULL);
   ec.Whereami          (ec    ); ec.setWhereami          (ec, NULL);
   ec.Logging           (ec    ); ec.setLogging           (ec, NULL);
   ec.lpLogFile         (ec    ); ec.setLpLogFile         (ec, NULL);
   ec.LogFile           (ec    ); ec.setLogFile           (ec, NULL);
   ec.LastError         (ec    ); ec.setLastError         (ec, NULL);
   lpEXECUTION_CONTEXT.toStr(NULL);
}


/**
 * Gibt die lesbare Repr�sentation eines an einer Adresse gespeicherten EXECUTION_CONTEXT zur�ck.
 *
 * @param  int  lpContext   - Adresse des EXECUTION_CONTEXT
 * @param  bool outputDebug - ob die Ausgabe zus�tzlich zum Debugger geschickt werden soll (default: nein)
 *
 * @return string
 */
string lpEXECUTION_CONTEXT.toStr(int lpContext, bool outputDebug=false) {
   outputDebug = outputDebug!=0;

   // TODO: pr�fen, ob lpContext ein g�ltiger Zeiger ist
   if (lpContext <= 0)                return(_emptyStr(catch("lpEXECUTION_CONTEXT.toStr(1)  invalid parameter lpContext = "+ lpContext, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int ec[EXECUTION_CONTEXT.intSize];
   CopyMemory(lpContext, GetBufferAddress(ec), EXECUTION_CONTEXT.size);

   // primitive Validierung, es gilt: PTR==*PTR (der Wert des Zeigers ist an der Adresse selbst gespeichert)
   if (ec.Signature(ec) != lpContext) return(_emptyStr(catch("lpEXECUTION_CONTEXT.toStr(2)  invalid EXECUTION_CONTEXT found at address 0x"+ IntToHexStr(lpContext), ERR_RUNTIME_ERROR)));

   string result = EXECUTION_CONTEXT.toStr(ec, outputDebug);
   ArrayResize(ec, 0);
   return(result);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   string BoolToStr(bool value);
   void   CopyMemory(int source, int destination, int bytes);
   string DeinitFlagsToStr(int flags);
   string ErrorToStr(int error);
   string InitFlagsToStr(int flags);
   string ModuleTypeToStr(int type);
   string StringToStr(string value);
   string TestFlagsToStr(int flags);
   string UninitializeReasonToStr(int reason);
   string __whereamiToStr(int id);

#import "Expander.dll"
   int    GetBufferAddress(int buffer[]);
   int    GetStringAddress(string value);
   string GetString(int address);
#import


// --------------------------------------------------------------------------------------------------------------------------------------------------


//#import "struct.EXECUTION_CONTEXT.ex4"
//   int    ec.Signature            (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.lpName               (/*EXECUTION_CONTEXT*/int ec[]                                );
//   string ec.Name                 (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.Type                 (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.hChart               (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.hChartWindow         (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.TestFlags            (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.lpSuperContext       (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.SuperContext         (/*EXECUTION_CONTEXT*/int ec[], /*EXECUTION_CONTEXT*/int sec[]);
//   int    ec.InitFlags            (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.DeinitFlags          (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.UninitializeReason   (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.Whereami             (/*EXECUTION_CONTEXT*/int ec[]                                );
//   bool   ec.Logging              (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.lpLogFile            (/*EXECUTION_CONTEXT*/int ec[]                                );
//   string ec.LogFile              (/*EXECUTION_CONTEXT*/int ec[]                                );
//   int    ec.LastError            (/*EXECUTION_CONTEXT*/int ec[]                                );

//   int    ec.setSignature         (/*EXECUTION_CONTEXT*/int ec[], int    signature         );
//   int    ec.setLpName            (/*EXECUTION_CONTEXT*/int ec[], int    lpName            );
//   string ec.setName              (/*EXECUTION_CONTEXT*/int ec[], string name              );
//   int    ec.setType              (/*EXECUTION_CONTEXT*/int ec[], int    type              );
//   int    ec.setHChart            (/*EXECUTION_CONTEXT*/int ec[], int    hChart            );
//   int    ec.setHChartWindow      (/*EXECUTION_CONTEXT*/int ec[], int    hChartWindow      );
//   int    ec.setTestFlags         (/*EXECUTION_CONTEXT*/int ec[], int    testFlags         );
//   int    ec.setLpSuperContext    (/*EXECUTION_CONTEXT*/int ec[], int    lpSuperContext    );
//   int    ec.setInitFlags         (/*EXECUTION_CONTEXT*/int ec[], int    initFlags         );
//   int    ec.setDeinitFlags       (/*EXECUTION_CONTEXT*/int ec[], int    deinitFlags       );
//   int    ec.setUninitializeReason(/*EXECUTION_CONTEXT*/int ec[], int    uninitializeReason);
//   int    ec.setWhereami          (/*EXECUTION_CONTEXT*/int ec[], int    whereami          );
//   bool   ec.setLogging           (/*EXECUTION_CONTEXT*/int ec[], bool   logging           );
//   int    ec.setLpLogFile         (/*EXECUTION_CONTEXT*/int ec[], int    lpLogFile         );
//   string ec.setLogFile           (/*EXECUTION_CONTEXT*/int ec[], string logFile           );
//   int    ec.setLastError         (/*EXECUTION_CONTEXT*/int ec[], int    lastError         );

//   string EXECUTION_CONTEXT.toStr (/*EXECUTION_CONTEXT*/int ec[], bool outputDebug);
//   string lpEXECUTION_CONTEXT.toStr(int lpContext, bool outputDebug);
//#import
