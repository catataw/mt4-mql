/**
 * Startet den MetaEditor. Workaround f�r Terminals ab Build 509, die einen �lteren MetaEditor nicht mehr starten.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[] = { INIT_NO_BARS_REQUIRED };
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>
#include <stdlib.mqh>
#include <win32api.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   string file = TerminalPath() +"\\metaeditor.exe";
   if (!IsFile(file))
      return(HandleScriptError("", "File not found: \""+ file +"\"", ERR_RUNTIME_ERROR));


   // WinExec() kehrt ohne zu warten zur�ck
   int result = WinExec(file, SW_SHOWNORMAL);
   if (result < 32)
      return(catch("onStart(1)->kernel32::WinExec(cmd=\""+ file +"\")  "+ ShellExecuteErrorDescription(result), ERR_WIN32_ERROR+result));

   return(catch("onStart(2)"));
}
