
/**
 * Ermittelt die Daten der im aktuellen Chart gemanagten Sequenzen.
 *
 * @param  string ids[]    - Array zur Aufnahme der gefundenen Sequenz-ID's
 * @param  int    status[] - Array zur Aufnahme der gefundenen Sequenz-Statuswerte
 *
 * @return bool - ob mindestens eine aktive Sequenz gefunden wurde
 */
bool FindChartSequences(string ids[], int status[]) {
   ArrayResize(ids,    0);
   ArrayResize(status, 0);

   string label = "SnowRoller.status";

   if (ObjectFind(label) == 0) {
      string values[], data[], strValue, text=StringToUpper(StringTrim(ObjectDescription(label)));
      int sizeOfValues = Explode(text, ",", values, NULL);

      for (int i=0; i < sizeOfValues; i++) {
         if (Explode(values[i], "|", data, NULL) != 2) return(_false(catch("FindChartSequences(1)  illegal chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));

         // Sequenz-ID
         strValue  = StringTrim(data[0]);
         bool test = false;
         if (StringLeft(strValue, 1) == "T") {
            test     = true;
            strValue = StringRight(strValue, -1);
         }
         if (!StringIsDigit(strValue))                 return(_false(catch("FindChartSequences(2)  illegal sequence id in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         int iValue = StrToInteger(strValue);
         if (iValue == 0)
            continue;
         string sequenceId = ifString(test, "T", "") + iValue;

         // Sequenz-Status
         strValue = StringTrim(data[1]);
         if (!StringIsDigit(strValue))                 return(_false(catch("FindChartSequences(3)  illegal sequence status in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         iValue = StrToInteger(strValue);
         if (!IsSequenceStatus(iValue))                return(_false(catch("FindChartSequences(4)  illegal sequence status in chart label "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_RUNTIME_ERROR)));
         int sequenceStatus = iValue;

         ArrayPushString(ids,    sequenceId    );
         ArrayPushInt   (status, sequenceStatus);
         //debug("GetCurrentChartSequences()   "+ label +" = "+ sequenceId +"|"+ sequenceStatus);
      }
   }

   return(ArraySize(ids));                                           // (bool) int
}


/**
 * Ob ein Wert einen gültigen Sequenzstatus-Code darstellt.
 *
 * @param  int value
 *
 * @return bool
 */
bool IsSequenceStatus(int value) {
   switch (value) {
      case STATUS_UNINITIALIZED: return(true);
      case STATUS_WAITING      : return(true);
      case STATUS_PROGRESSING  : return(true);
      case STATUS_STOPPING     : return(true);
      case STATUS_STOPPED      : return(true);
      case STATUS_DISABLED     : return(true);
   }
   return(false);
}
