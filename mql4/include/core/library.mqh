
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

   int hChart = WindowHandle(Symbol(), NULL);
   if (!hChart)
      return(!catch("Script.IsTesting(2)->WindowHandle() = 0 in context Script::"+ __whereamiDescription(__WHEREAMI__), ERR_RUNTIME_ERROR));

   static.result = StringEndsWith(GetWindowText(GetParent(hChart)), "(visual)");    // "(visual)" ist nicht internationalisiert

   static.resolved = true;
   return(static.result);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Indikator ist.
 *
 * @return bool
 */
bool Indicator.IsTesting() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("Indicator.IsTesting(1)   library not initialized", ERR_RUNTIME_ERROR));

   if (!IsIndicator())
      return(false);

   static bool static.resolved, static.result;
   if (static.resolved)
      return(static.result);

   if (IsTesting()) {                                                // Indikator l�uft in EA::iCustom() im Tester
      static.result = true;
   }
   else if (GetCurrentThreadId() != GetUIThreadId()) {               // Indikator l�uft im Testchart in Indicator::start()
      static.result = true;
   }
   else if (__WHEREAMI__ != FUNC_START) {                            // Indikator l�uft in Indicator::init|deinit() und im UI-Thread: entweder Hauptchart oder Testchart
      int hChart = WindowHandle(Symbol(), NULL);
      if (!hChart)
         return(!catch("Indicator.IsTesting(2)->WindowHandle() = 0 in context Indicator::"+ __whereamiDescription(__WHEREAMI__), ERR_RUNTIME_ERROR));
      string title = GetWindowText(GetParent(hChart));
      if (title == "")                                               // Indikator wurde mit Template geladen, Ergebnis kann nicht erkannt werden
         return(!catch("Indicator.IsTesting(3)->GetWindowText() = \"\"   undefined result in context Indicator::"+ __whereamiDescription(__WHEREAMI__), ERR_RUNTIME_ERROR));
      static.result = StringEndsWith(title, "(visual)");             // Indikator l�uft im Haupt- oder Testchart ("(visual)" ist nicht internationalisiert)
   }
   else {
      static.result = false;                                         // Indikator l�uft in Indicator::start() im Hauptchart
   }

   static.resolved = true;
   return(static.result);
}


/**
 * Ob das aktuelle Programm im Tester ausgef�hrt wird.
 *
 * @return bool
 */
bool This.IsTesting() {
   if (__TYPE__ == T_LIBRARY)
      return(!catch("This.IsTesting()   library not initialized", ERR_RUNTIME_ERROR));

   if (   IsExpert()) return(   Expert.IsTesting());
   if (   IsScript()) return(   Script.IsTesting());
   if (IsIndicator()) return(Indicator.IsTesting());

   return(false);
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
   int    GetUIThreadId();
   string GetWindowText(int hWnd);
   bool   StringEndsWith(string object, string postfix);
   string __whereamiDescription(int id);

#import "kernel32.dll"
   int    GetCurrentThreadId();

#import "user32.dll"
   int    GetParent(int hWnd);

#import "struct.EXECUTION_CONTEXT.ex4"
   int    ec.setLastError(/*EXECUTION_CONTEXT*/int ec[], int lastError);
#import
