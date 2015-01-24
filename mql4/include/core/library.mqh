
int __TYPE__         = T_LIBRARY;
int __lpSuperContext = NULL;


/**
 * Initialisierung der Library.
 *
 * @return int - Fehlerstatus
 */
int init() {
   // Im Tester globale Arrays eines EA's zur�cksetzen.
   if (IsTesting()) {                                             // Zur Zeit kein besserer Workaround f�r die ansonsten im Speicher verbleibenden Variablen des vorherigen Tests.
      Tester.ResetGlobalArrays();                                 // K�nnte ein Feature f�r die Optimization sein, um Daten test�bergreifend verwalten zu k�nnen.
   }
   return(catch("init()"));
}


/**
 * Startfunktion f�r Libraries (Dummy).
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: F�r den Compiler v224 mu� ab einer unbestimmten Komplexit�t der Library eine start()-Funktion existieren,
 *       wenn die init()-Funktion implementiert wurde.
 */
int start() {
   return(catch("start()", ERR_WRONG_JUMP));
}


/**
 * Deinitialisierung der Library.
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: 1) Bei VisualMode=Off und regul�rem Testende (Testperiode zu Ende = REASON_UNDEFINED) bricht das Terminal komplexere EA-deinit()-Funktionen
 *          verfr�ht und nicht erst nach 2.5 Sekunden ab. In diesem Fall wird diese deinit()-Funktion u.U. auch nicht mehr ausgef�hrt.
 *
 *       2) Bei Testende wird diese deinit()-Funktion (wenn implementiert) u.U. zweimal aufgerufen. Beim zweiten mal ist die Library zur�ckgesetzt,
 *          der Variablen-Status also undefiniert.
*/
int deinit() {
   return(catch("deinit()"));
}


/**
 * Gibt die ID des aktuellen oder letzten Init()-Szenarios zur�ck. Kann au�er in deinit() �berall aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int InitReason() {
   return(_NULL(catch("InitReason()", ERR_NOT_IMPLEMENTED)));
}


/**
 * Gibt die ID des aktuellen Deinit()-Szenarios zur�ck. Kann nur in deinit() aufgerufen werden.
 *
 * @return int - ID oder NULL, falls ein Fehler auftrat
 */
int DeinitReason() {
   return(_NULL(catch("DeinitReason()", ERR_NOT_IMPLEMENTED)));
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Expert ist.
 *
 * @return bool
 */
bool IsExpert() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("IsExpert()   library not initialized", ERR_RUNTIME_ERROR));
   return(__TYPE__ & T_EXPERT != 0);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Script ist.
 *
 * @return bool
 */
bool IsScript() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("IsScript()   library not initialized", ERR_RUNTIME_ERROR));
   return(__TYPE__ & T_SCRIPT);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Indikator ist.
 *
 * @return bool
 */
bool IsIndicator() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("IsIndicator()   library not initialized", ERR_RUNTIME_ERROR));
   return(__TYPE__ & T_INDICATOR != 0);
}


/**
 * Ob das aktuell ausgef�hrte Modul eine Library ist.
 *
 * @return bool
 */
bool IsLibrary() {
   return(true);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Expert ist.
 *
 * @return bool
 */
bool Expert.IsTesting() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("Expert.IsTesting()   library not initialized", ERR_RUNTIME_ERROR));

   if (IsTesting()) /*&&*/ if (IsExpert())                           // IsTesting() allein reicht nicht, da auch in Indikatoren TRUE zur�ckgeben werden kann.
      return(true);
   return(false);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufendes Script ist.
 *
 * @return bool
 */
bool Script.IsTesting() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("Script.IsTesting(1)   library not initialized", ERR_RUNTIME_ERROR));

   if (!IsScript())
      return(false);

   static bool static.resolved, static.result;                                      // static: EA ok, Indikator ok
   if (static.resolved)
      return(static.result);

   int hWnd = WindowHandle(Symbol(), NULL); if (!hWnd) hWnd = __WND_HANDLE;
   if (!hWnd)
      return(!catch("Script.IsTesting(2)->WindowHandle() = 0 in context Script::"+ __whereamiDescription(__WHEREAMI__), ERR_RUNTIME_ERROR));

   static.result = StringEndsWith(GetWindowText(GetParent(hWnd)), "(visual)");      // "(visual)" ist nicht internationalisiert

   static.resolved = true;
   return(static.result);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Indikator ist.
 *
 * @param  int execFlags - die Ausf�hrung steuernde Flags (default: keine)
 *
 * @return int - TRUE (1), FALSE (0) oder EMPTY (-1), falls ein Fehler auftrat
 *
 * @throws ERS_TERMINAL_NOT_YET_READY - Falls der Teststatus w�hrend des Terminal-Starts noch nicht bestimmt werden kann. Wird still gesetzt, wenn im Parameter
 *                                      execFlags das Flag MUTE_ERS_TERMINAL_NOT_YET_READY gesetzt ist. Der R�ckgabewert der Funktion ist bei Auftreten dieses
 *                                      Fehlers -1 (EMPTY).
 */
int Indicator.IsTesting(int execFlags=NULL) {
   if (__TYPE__ == T_LIBRARY)
      return(_EMPTY(catch("Indicator.IsTesting(1)   library not initialized", ERR_RUNTIME_ERROR)));

   if (!IsIndicator())
      return(false);                                                 // (int) bool

   static bool static.resolved, static.result;
   if (static.resolved)
      return(static.result);                                         // (int) bool


   if (IsTesting()) {                                                // Indikator l�uft in EA::iCustom() im Tester
      static.result = true;
   }
   else if (GetCurrentThreadId() != GetUIThreadId()) {               // Indikator l�uft im Thread des Testers in Indicator::start()
      static.result = true;
   }
   else if (__WHEREAMI__ == FUNC_START) {                            // Indikator l�uft im UI-Thread in Indicator::start(), also im Hauptchart
      static.result = false;
   }
   else {                                                            // Indikator l�uft im UI-Thread in Indicator::init|deinit(): entweder im Hauptchart oder im Testchart
      bool resolved;

      int hWndChart = WindowHandle(Symbol(), NULL); if (!hWndChart) hWndChart = __WND_HANDLE;
      if (hWndChart != 0) {
         string title = GetWindowText(GetParent(hWndChart));
         if (StringLen(title) > 0) {
            static.result = StringEndsWith(title, "(visual)");       // Indikator l�uft im UI-Thread und im Haupt- oder Testchart, Unterscheidung durch "...(visual)" im Fenstertitel
            resolved      = true;
         }
         //else                                                      // Indikator wurde im UI-Thread per Template geladen, das Fenster ist bekannt, der Titel jedoch noch nicht gesetzt.
      }

      if (!resolved) {                                               // Entweder war das Fensterhandle unbekannt oder das Fenster noch nicht vollst�ndig initialisiert (kein Titel)
         // Lief der Tester, dann existiert immer sein Hauptfenster. Existiert es nicht, l�uft der Indikator im Hauptchart.
         int hWndTester = GetTesterWindow();
         if (!hWndTester) {
            static.result = false;                                   // Tester lief noch nicht: Indikator l�uft im UI-Thread in Indicator::init|deinit() im Hauptchart
            resolved      = true;
         }
      }

      if (!resolved) {
         // Der Test anhand einer ins file-Verzeichnis geschriebenen Datei funktioniert nicht, da die Datei auch im Tester ins Online-Verzeichnis geschrieben wird (bei VisualMode=Off).
         static.result = false;
         resolved      = true;
      }

      if (!resolved) {
         // TODO: Gesamte Erkennung in DLL auslagern, die das Terminal-Hauptfenster per Subclassing �berwacht.
         if (!execFlags & MUTE_ERS_TERMINAL_NOT_YET_READY) return(_EMPTY(catch("Indicator.IsTesting(5)   cannot determine testing status,  hWndChart="+ hWndChart +",  hWndTester="+ hWndTester +"  in context Indicator::"+ __whereamiDescription(__WHEREAMI__), ERS_TERMINAL_NOT_YET_READY)));
         else                                              return(_EMPTY(SetLastError(ERS_TERMINAL_NOT_YET_READY)));
      }
   }

   static.resolved = true;
   return(static.result);                                            // (int) bool
}


/**
 * Ob das aktuelle Programm im Tester ausgef�hrt wird.
 *
 * @param  int execFlags - die Ausf�hrung steuernde Flags (default: keine)
 *
 * @return int - TRUE (1), FALSE (0) oder EMPTY (-1), falls ein Fehler auftrat
 *
 * @throws ERS_TERMINAL_NOT_YET_READY - Falls das Programm ein Indikator ist und der Teststatus w�hrend des Terminal-Starts noch nicht bestimmt werden kann.
 *                                      Wird still gesetzt, wenn im Parameter execFlags das Flag MUTE_ERS_TERMINAL_NOT_YET_READY gesetzt ist. Der R�ckgabewert
 *                                      der Funktion ist bei Auftreten dieses Fehlers -1 (EMPTY).
 */
int This.IsTesting(int execFlags=NULL) {
   if (__TYPE__ == T_LIBRARY)
      return(_EMPTY(catch("This.IsTesting(1)   library not initialized", ERR_RUNTIME_ERROR)));

   if (   IsExpert()) return(   Expert.IsTesting());                 // (int) bool
   if (   IsScript()) return(   Script.IsTesting());                 // (int) bool
   if (IsIndicator()) return(Indicator.IsTesting(execFlags));

   return(_EMPTY(catch("This.IsTesting(2)   unreachable code reached", ERR_RUNTIME_ERROR)));
}


/**
 * Ob das aktuelle Programm durch ein anderes Programm ausgef�hrt wird.
 *
 * @return bool
 */
bool IsSuperContext() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("IsSuperContext()   library not initialized", ERR_RUNTIME_ERROR));
   return(__lpSuperContext != 0);
}


/**
 * Setzt den internen Fehlercode des Moduls.
 *
 * @param  int error - Fehlercode
 *
 * @return int - derselbe Fehlercode (for chaining)
 *
 *
 * NOTE: Akzeptiert einen weiteren beliebigen Parameter, der bei der Verarbeitung jedoch ignoriert wird.
 */
int SetLastError(int error, int param=NULL) {
   last_error = error;
   return(ec.setLastError(__ExecutionContext, last_error));
}


/**
 * �berpr�ft und aktualisiert den aktuellen Programmstatus. Darf in Libraries nicht verwendet werden, dort kann der Programmstatus aus dem
 * EXECUTION_CONTEXT ausgelesen, jedoch nicht modifiziert werden.
 *
 * @param  int value - zur�ckzugebender Wert, wird intern ignoriert (default: NULL)
 *
 * @return int - der �bergebene Wert
 */
int CheckProgramStatus(int value=NULL) {
   catch("CheckProgramStatus()", ERR_FUNC_NOT_ALLOWED);
   return(value);
}


// --------------------------------------------------------------------------------------------------------------------------------------------------


#import "stdlib1.ex4"
   int    GetTesterWindow();
   int    GetUIThreadId();
   string GetWindowText(int hWnd);
   bool   StringEndsWith(string object, string postfix);
   string __whereamiDescription(int id);

#import "stdlib2.ex4"
   int    GetTerminalRuntime();

#import "kernel32.dll"
   int    GetCurrentThreadId();

#import "user32.dll"
   int    GetParent(int hWnd);

#import "struct.EXECUTION_CONTEXT.ex4"
   int    ec.setLastError(/*EXECUTION_CONTEXT*/int ec[], int lastError);
#import
