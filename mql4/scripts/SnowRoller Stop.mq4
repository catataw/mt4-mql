/**
 * SnowRoller Stop
 */
#include <core/define.mqh>
#define     __TYPE__    T_SCRIPT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stddefine.mqh>
#include <stdlib.mqh>

#include <core/script.mqh>
#include <SnowRoller/define.mqh>
#include <SnowRoller/functions.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   string ids [];
   int  status[], sizeOfIds;


   // (1) Sequenzen im aktuellen Chart ermitteln
   if (FindChartSequences(ids, status)) {
      sizeOfIds = ArraySize(ids);


      // (2) f¸r Command unzutreffende Sequenzen herausfiltern
      for (int i=sizeOfIds-1; i >= 0; i--) {
         switch (status[i]) {
            case STATUS_WAITING    :                                             // STATUS_UNINITIALIZED:   // entfernen
            case STATUS_STARTING   :                                             // STATUS_WAITING      :   // ok, solange es keine Testsequenz auﬂerhalb des Testers ist
            case STATUS_PROGRESSING:                                             // STATUS_STARTING     :   // ok, solange es keine Testsequenz auﬂerhalb des Testers ist
               if (StringGetChar(ids[i], 0)!='T' || ScriptIsTesting())           // STATUS_PROGRESSING  :   // ok, solange es keine Testsequenz auﬂerhalb des Testers ist
                  continue;                                                      // STATUS_STOPPING     :   // entfernen
            default:                                                             // STATUS_STOPPED      :   // entfernen
               ArraySpliceStrings(ids, i, 1);                                    // STATUS_DISABLED     :   // entfernen
               ArraySpliceInts(status, i, 1);
               sizeOfIds--;
         }
      }


      // (3) Best‰tigung einholen
      for (i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(__NAME__, ifString(!IsDemo() && !ScriptIsTesting(), "- Live Account -\n\n", "") +"Do you really want to stop sequence "+ ids[i] +"?", MB_ICONQUESTION|ifInt(sizeOfIds==1, MB_OKCANCEL, MB_YESNOCANCEL));
         if (button == IDCANCEL)
            break;
         if (button == IDNO)
            continue;


         // (4) Command setzen
         string mutex = "mutex.ChartCommand";
         if (!AquireLock(mutex))
            return(SetLastError(stdlib_PeekLastError()));

         string label = StringConcatenate("SnowRoller.", ids[i], ".command");    // TODO: Commands zu bereits existierenden Commands hinzuf¸gen
         if (ObjectFind(label) != 0) {
            if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
               return(_int(catch("onStart(1)"), ReleaseLock(mutex)));
            ObjectSet(label, OBJPROP_TIMEFRAMES, EMPTY);                         // hidden on all timeframes
         }
         ObjectSetText(label, "stop", 1);

         if (!ReleaseLock(mutex))
            return(SetLastError(stdlib_PeekLastError()));


         // (5) Tick senden
         Chart.SendTick(false);
         return(catch("onStart(2)"));                                            // regular exit
      }
   }

   if (!IsLastError()) {
      if (sizeOfIds == 0) {
         ForceSound("chord.wav");
         ForceMessageBox(__NAME__, "No running sequence found.", MB_ICONEXCLAMATION|MB_OK);
      }
      catch("onStart(3)");
   }
   return(last_error);
}
