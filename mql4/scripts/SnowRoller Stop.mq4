/**
 * SnowRoller Stop
 */
#include <types.mqh>
#define     __TYPE__    T_SCRIPT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>

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


      // (2) f¸r Stop-Command unzutreffende Sequenzen herausfiltern
      for (int i=sizeOfIds-1; i >= 0; i--) {
         switch (status[i]) {
            case STATUS_WAITING    :                                       // STATUS_UNINITIALIZED:   // filtern
            case STATUS_PROGRESSING:                                       // STATUS_WAITING      :   // ok, solange es keine Testsequenz auﬂerhalb des Testers ist
               if (StringGetChar(ids[i], 0)!='T' || ScriptIsTesting())     // STATUS_PROGRESSING  :   // ok, solange es keine Testsequenz auﬂerhalb des Testers ist
                  continue;                                                // STATUS_STOPPING     :   // filtern
            default:                                                       // STATUS_STOPPED      :   // filtern
               ArraySpliceStrings(ids, i, 1);                              // STATUS_DISABLED     :   // filtern
               ArraySpliceInts(status, i, 1);
               sizeOfIds--;
         }
      }


      // (3) Best‰tigung einholen
      for (i=0; i < sizeOfIds; i++) {
         ForceSound("notify.wav");
         int button = ForceMessageBox(ifString(!IsDemo() && !ScriptIsTesting(), "- Live Account -\n\n", "") +"Do you really want to stop sequence "+ ids[i] +"?", __NAME__, MB_ICONQUESTION|ifInt(sizeOfIds==1, MB_OKCANCEL, MB_YESNOCANCEL));
         if (button == IDCANCEL)
            break;
         if (button == IDNO)
            continue;


         // (4) Command setzen
         string label = StringConcatenate("SnowRoller.", ids[i], ".command");
         if (ObjectFind(label) != 0) {
            if (!ObjectCreate(label, OBJ_LABEL, 0, 0, 0))
               return(catch("onStart(1)"));
            ObjectSet(label, OBJPROP_TIMEFRAMES, EMPTY);                // hidden on all timeframes
         }
         ObjectSetText(label, "stop", 1);


         // (5) Tick senden
         Chart.SendTick(false);
         return(catch("onStart(2)"));                                   // regular exit
      }
   }

   if (!IsLastError()) {
      if (sizeOfIds == 0) {
         ForceSound("chord.wav");
         ForceMessageBox("No sequence to stop found.", __NAME__, MB_ICONEXCLAMATION|MB_OK);
      }
      catch("onStart(3)");
   }
   return(last_error);
}
