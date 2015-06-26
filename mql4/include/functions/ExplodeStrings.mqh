/**
 * Konvertiert einen Multiple-String-Buffer in ein String-Array.
 *
 * @param  int    buffer[]  - Buffer mit durch NUL-Zeichen getrennten Strings, terminiert durch ein weiteres NUL-Zeichen
 * @param  string results[] - resultierendes String-Array (mit mindestens einem Leerstring)
 *
 * @return int - Anzahl der gefundenen Strings (immer gr��er 0) oder NULL, falls ein Fehler auftrat
 */
int ExplodeStrings(int buffer[], string &results[]) {
   string value;
   int length, fromAddr=GetIntsAddress(buffer), toAddr=fromAddr + ArraySize(buffer)*4, resultsSize=ArrayResize(results, 0);

   for (int addr=fromAddr; addr < toAddr; addr+=(length+1)) {
      value  = GetString(addr);
      length = StringLen(value);

      if (!length && resultsSize)
         break;

      resultsSize            = ArrayResize(results, resultsSize+1);
      results[resultsSize-1] = StringSubstr(value, 0, toAddr-addr);
   }

   if (!catch("ExplodeStrings(1)"))
      return(resultsSize);
   return(0);
}
