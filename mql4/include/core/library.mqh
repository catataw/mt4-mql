
int __TYPE__    = T_LIBRARY;
int __iCustom__ = NULL;


/**
 * Initialisierung der Library.
 *
 * @return int - Fehlerstatus
 *
 */
int init() {
   // Im Tester globale Arrays zur�cksetzen (zur Zeit kein besserer Workaround).
   Tester.ResetGlobalArrays();
   return(NO_ERROR);
}


/**
 * Startfunktion f�r Libraries (Dummy).
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE: F�r den Compiler v224 mu� ab einer unbestimmten Komplexit�t der Library eine start()-Funktion existieren,
 *       *wenn* die init()-Funktion implementiert wird.
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
int deinit() {
   return(NO_ERROR);
}
*/


/**
 * Ob das aktuell ausgef�hrte Programm ein Expert ist.
 *
 * @return bool
 */
bool IsExpert() {
   if (__TYPE__ == T_LIBRARY)
      return(_false(catch("IsExpert()   function must not be used before library initialization", ERR_RUNTIME_ERROR)));
   return(__TYPE__ & T_EXPERT);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein im Tester laufender Expert ist.
 *
 * @return bool
 */
bool Expert.IsTesting() {
   if (__TYPE__ == T_LIBRARY)
      return(_false(catch("Expert.IsTesting()   function must not be used before library initialization", ERR_RUNTIME_ERROR)));

   if (IsTesting()) /*&&*/ if (IsExpert())
      return(true);

   return(false);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Indikator ist.
 *
 * @return bool
 */
bool IsIndicator() {
   if (__TYPE__ == T_LIBRARY)
      return(_false(catch("IsIndicator()   function must not be used before library initialization", ERR_RUNTIME_ERROR)));
   return(__TYPE__ & T_INDICATOR);
}


/**
 * Ob der aktuelle Indikator via iCustom() ausgef�hrt wird.
 *
 * @return bool
 */
bool Indicator.IsICustom() {
   if (__TYPE__ == T_LIBRARY)
      return(_false(catch("Indicator.IsICustom()   function must not be used before library initialization", ERR_RUNTIME_ERROR)));
   if (IsIndicator())
      return(__iCustom__);                // (bool) int
   return(false);
}


/**
 * Ob das aktuell ausgef�hrte Programm ein Script ist.
 *
 * @return bool
 */
bool IsScript() {
   if (__TYPE__ == T_LIBRARY)
      return(_false(catch("IsScript()   function must not be used before library initialization", ERR_RUNTIME_ERROR)));
   return(__TYPE__ & T_SCRIPT);
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
   // __STATUS_ERROR ist ein Status des Hauptprogramms und wird in Libraries nicht gesetzt
   return(error);
}
