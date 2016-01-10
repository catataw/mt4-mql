/**
 *
 */
#property library

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/library.mqh>
#include <stdfunctions.mqh>
#include <functions/ExplodeStrings.mqh>
#include <functions/InitializeByteBuffer.mqh>
#include <functions/JoinBools.mqh>
#include <functions/JoinInts.mqh>
#include <functions/JoinDoubles.mqh>
#include <functions/JoinDoublesEx.mqh>
#include <functions/JoinStrings.mqh>
#include <stdlib.mqh>


/**
 * Gibt alle Schl�ssel eines Abschnitts einer .ini-Datei zur�ck.
 *
 * @param  string fileName - Name der .ini-Datei
 * @param  string section  - Name des Abschnitts
 * @param  string keys[]   - Array zur Aufnahme der gefundenen Schl�ssel
 *
 * @return int - Anzahl der gefundenen Schl�ssel oder -1 (EMPTY), falls ein Fehler auftrat
 */
int GetIniKeys(string fileName, string section, string keys[]) {
   string sNull;
   int bufferSize = 200;
   int buffer[]; InitializeByteBuffer(buffer, bufferSize);

   int chars = GetPrivateProfileStringA(section, sNull, "", buffer, bufferSize, fileName);

   // zu kleinen Buffer abfangen
   while (chars == bufferSize-2) {
      bufferSize <<= 1;
      InitializeByteBuffer(buffer, bufferSize);
      chars = GetPrivateProfileStringA(section, sNull, "", buffer, bufferSize, fileName);
   }

   if (!chars) int size = ArrayResize(keys, 0);                      // keine Schl�ssel gefunden (Datei/Abschnitt nicht gefunden oder Abschnitt ist leer)
   else            size = ExplodeStrings(buffer, keys);

   ArrayResize(buffer, 0);

   if (!catch("GetIniKeys(1)"))
      return(size);
   return(EMPTY);
}


/**
 * Konvertiert ein String-Array mit bis zu 3 Dimensionen in einen lesbaren String.
 *
 * @param  string values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string StringsToStr(string values[][], string separator=", ") {
   return(__StringsToStr(values, values, separator));
}


/**
 * Interne Hilfsfunktion (Workaround um Dimension-Check des Compilers)
 *
 * @private - Aufruf nur aus StringsToStr()
 */
/*@private*/string __StringsToStr(string values2[][], string values3[][][], string separator) {
   if (separator == "0")      // (string) NULL
      separator = ", ";

   int dimensions=ArrayDimension(values2), dim1=ArrayRange(values2, 0), dim2, dim3;
   string result;


   // 1-dimensionales Array
   if (dimensions == 1) {
      if (dim1 == 0)
         return("{}");
      string copy[]; ArrayResize(copy, 0);
      ArrayCopy(copy, values2);
      DoubleQuoteStrings(copy);

      result = StringConcatenate("{", JoinStrings(copy, separator), "}");
      ArrayResize(copy, 0);
      return(result);
   }
   else dim2 = ArrayRange(values2, 1);


   // 2-dimensionales Array
   if (dimensions == 2) {
      string strValues2.X[]; ArrayResize(strValues2.X, dim1);
      string    values2.Y[]; ArrayResize(   values2.Y, dim2);

      for (int x=0; x < dim1; x++) {
         for (int y=0; y < dim2; y++) {
            values2.Y[y] = values2[x][y];             // TODO: NPE abfangen
         }
         strValues2.X[x] = StringsToStr(values2.Y, separator);
      }

      result = StringConcatenate("{", JoinStrings(strValues2.X, separator), "}");
      ArrayResize(strValues2.X, 0);
      ArrayResize(   values2.Y, 0);
      return(result);
   }
   else dim3 = ArrayRange(values3, 2);


   // 3-dimensionales Array
   if (dimensions == 3) {
      string strValues3.X[]; ArrayResize(strValues3.X, dim1);
      string strValues3.Y[]; ArrayResize(strValues3.Y, dim2);
      string    values3.Z[]; ArrayResize(   values3.Z, dim3);

      for (x=0; x < dim1; x++) {
         for (y=0; y < dim2; y++) {
            for (int z=0; z < dim3; z++) {
               values3.Z[z] = values3[x][y][z];      // TODO: NPE abfangen
            }
            strValues3.Y[y] = StringsToStr(values3.Z, separator);
         }
         strValues3.X[x] = StringConcatenate("{", JoinStrings(strValues3.Y, separator), "}");
      }

      result = StringConcatenate("{", JoinStrings(strValues3.X, separator), "}");
      ArrayResize(strValues3.X, 0);
      ArrayResize(strValues3.Y, 0);
      ArrayResize(   values3.Z, 0);
      return(result);
   }

   return(_EMPTY_STR(catch("__StringsToStr()  too many dimensions of parameter values = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS)));
}


/**
 * Fa�t jeden Wert eines String-Arrays in doppelte Anf�hrungszeichen ein. Nicht initialisierte Werte (NULL-Pointer) bleiben unver�ndert.
 *
 * @param  string values[]
 *
 * @return int - Fehlerstatus
 */
int DoubleQuoteStrings(string &values[]) {
   if (ArrayDimension(values) > 1)
      return(catch("DoubleQuoteStrings(1)  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS));

   string value;
   int error, size=ArraySize(values);

   for (int i=0; i < size; i++) {
      value = values[i];                                             // NPE provozieren
      error = GetLastError();
      if (!error) {
         values[i] = StringConcatenate("\"", values[i], "\"");
         continue;
      }
      if (error != ERR_NOT_INITIALIZED_ARRAYSTRING)                  // NULL-Werte bleiben unver�ndert
         return(catch("DoubleQuoteStrings(2)", error));
   }
   return(0);
}


/**
 * Konvertiert ein Array mit Kursen in einen mit dem aktuellen PriceFormat formatierten String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string RatesToStr(double values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("RatesToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (size == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      if (!values[i]) strings[i] = "0";
      else            strings[i] = NumberToStr(values[i], PriceFormat);

      if (!StringLen(strings[i]))
         return("");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Alias
 *
 * Konvertiert ein Array mit Kursen in einen mit dem aktuellen PriceFormat formatierten String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string PricesToStr(double values[], string separator=", ") {
   return(RatesToStr(values, separator));
}


/**
 * Konvertiert ein Array mit Geldbetr�gen in einen lesbaren String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String mit 2 Nachkommastellen je Wert oder Leerstring, falls ein Fehler auftrat
 */
string MoneysToStr(double values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("MoneysToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = NumberToStr(values[i], ".2");
      if (!StringLen(strings[i]))
         return("");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Konvertiert einen Indikatorbuffer in einen lesbaren String. Ganzzahlige Werte werden als Integer, gebrochene Werte
 * mit dem aktuellen PriceFormat formatiert.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string iBufferToStr(double values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("iBufferToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (size == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      if (!MathModFix(values[i], 1)) strings[i] = DoubleToStr(values[i], 0);
      else                           strings[i] = NumberToStr(values[i], PriceFormat);
      if (!StringLen(strings[i]))
         return("");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Konvertiert ein Doubles-Array mit bis zu 3 Dimensionen in einen lesbaren String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string DoublesToStr(double values[][], string separator=", ") {
   return(__DoublesToStr(values, values, separator));
}


/**
 * Interne Hilfsfunktion (Workaround um Dimension-Check des Compilers)
 *
 * @private - Aufruf nur aus DoublesToStr()
 */
/*@private*/string __DoublesToStr(double values2[][], double values3[][][], string separator) {
   if (separator == "0")                                             // (string) NULL
      separator = ", ";

   int dimensions=ArrayDimension(values2), dim1=ArrayRange(values2, 0), dim2, dim3;
   string result;


   // 1-dimensionales Array
   if (dimensions == 1) {
      if (dim1 == 0)
         return("{}");
      return(StringConcatenate("{", JoinDoubles(values2, separator), "}"));
   }
   else dim2 = ArrayRange(values2, 1);


   // 2-dimensionales Array
   if (dimensions == 2) {
      string strValues2.X[]; ArrayResize(strValues2.X, dim1);
      double    values2.Y[]; ArrayResize(   values2.Y, dim2);

      for (int x=0; x < dim1; x++) {
         for (int y=0; y < dim2; y++) {
            values2.Y[y] = values2[x][y];
         }
         strValues2.X[x] = DoublesToStr(values2.Y, separator);
      }

      result = StringConcatenate("{", JoinStrings(strValues2.X, separator), "}");
      ArrayResize(strValues2.X, 0);
      ArrayResize(   values2.Y, 0);
      return(result);
   }
   else dim3 = ArrayRange(values3, 2);


   // 3-dimensionales Array
   if (dimensions == 3) {
      string strValues3.X[]; ArrayResize(strValues3.X, dim1);
      string strValues3.Y[]; ArrayResize(strValues3.Y, dim2);
      double    values3.Z[]; ArrayResize(   values3.Z, dim3);

      for (x=0; x < dim1; x++) {
         for (y=0; y < dim2; y++) {
            for (int z=0; z < dim3; z++) {
               values3.Z[z] = values3[x][y][z];
            }
            strValues3.Y[y] = DoublesToStr(values3.Z, separator);
         }
         strValues3.X[x] = StringConcatenate("{", JoinStrings(strValues3.Y, separator), "}");
      }

      result = StringConcatenate("{", JoinStrings(strValues3.X, separator), "}");
      ArrayResize(strValues3.X, 0);
      ArrayResize(strValues3.Y, 0);
      ArrayResize(   values3.Z, 0);
      return(result);
   }

   return(_EMPTY_STR(catch("__DoublesToStr()  too many dimensions of parameter values = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS)));
}


/**
 * Konvertiert ein maximal 3-dimensionales Array von Doubles mit bis zu 16 Nachkommstaellen in einen lesbaren String.
 *
 * @param  double values[]  - zu konvertierende Werte
 * @param  string separator - Separator (default: NULL = ", ")
 * @param  int    digits    - Anzahl der Nachkommastellen (0-16)
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string DoublesToStrEx(double values[][], string separator, int digits) {
   return(__DoublesToStrEx(values, values, separator, digits));
}


/**
 * Interne Hilfsfunktion (Workaround um Dimension-Check des Compilers)
 *
 * @private - Aufruf nur aus DoublesToStrEx()
 */
/*@private*/string __DoublesToStrEx(double values2[][], double values3[][][], string separator, int digits) {
   if (digits < 0 || digits > 16)
      return(_EMPTY_STR(catch("__DoublesToStrEx(1)  illegal parameter digits = "+ digits, ERR_INVALID_PARAMETER)));

   if (separator == "0")                                             // (string) NULL
      separator = ", ";

   int dimensions=ArrayDimension(values2), dim1=ArrayRange(values2, 0), dim2, dim3;
   string result;


   // 1-dimensionales Array
   if (dimensions == 1) {
      if (dim1 == 0)
         return("{}");
      return(StringConcatenate("{", JoinDoublesEx(values2, separator, digits), "}"));
   }
   else dim2 = ArrayRange(values2, 1);


   // 2-dimensionales Array
   if (dimensions == 2) {
      string strValues2.X[]; ArrayResize(strValues2.X, dim1);
      double    values2.Y[]; ArrayResize(   values2.Y, dim2);

      for (int x=0; x < dim1; x++) {
         for (int y=0; y < dim2; y++) {
            values2.Y[y] = values2[x][y];
         }
         strValues2.X[x] = DoublesToStrEx(values2.Y, separator, digits);
      }

      result = StringConcatenate("{", JoinStrings(strValues2.X, separator), "}");
      ArrayResize(strValues2.X, 0);
      ArrayResize(   values2.Y, 0);
      return(result);
   }
   else dim3 = ArrayRange(values3, 2);


   // 3-dimensionales Array
   if (dimensions == 3) {
      string strValues3.X[]; ArrayResize(strValues3.X, dim1);
      string strValues3.Y[]; ArrayResize(strValues3.Y, dim2);
      double    values3.Z[]; ArrayResize(   values3.Z, dim3);

      for (x=0; x < dim1; x++) {
         for (y=0; y < dim2; y++) {
            for (int z=0; z < dim3; z++) {
               values3.Z[z] = values3[x][y][z];
            }
            strValues3.Y[y] = DoublesToStrEx(values3.Z, separator, digits);
         }
         strValues3.X[x] = StringConcatenate("{", JoinStrings(strValues3.Y, separator), "}");
      }

      result = StringConcatenate("{", JoinStrings(strValues3.X, separator), "}");
      ArrayResize(strValues3.X, 0);
      ArrayResize(strValues3.Y, 0);
      ArrayResize(   values3.Z, 0);
      return(result);
   }

   return(_EMPTY_STR(catch("__DoublesToStrEx(2)  too many dimensions of parameter values = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS)));
}


/**
 * Konvertiert ein DateTime-Array in einen lesbaren String.
 *
 * @param  datetime values[]
 * @param  string   separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string TimesToStr(datetime values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("TimesToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      if      (values[i] <  0) strings[i] = "-1";
      else if (values[i] == 0) strings[i] =  "0";
      else                     strings[i] = StringConcatenate("'", TimeToStr(values[i], TIME_FULL), "'");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Konvertiert ein OperationType-Array in einen lesbaren String.
 *
 * @param  int    values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string OperationTypesToStr(int values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("OperationTypesToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[]; ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = OperationTypeToStr(values[i]);
      if (!StringLen(strings[i]))
         return("");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Konvertiert ein Char-Array in einen lesbaren String.
 *
 * @param  int    values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string CharsToStr(int values[], string separator=", ") {
   if (ArrayDimension(values) > 1)
      return(_EMPTY_STR(catch("CharsToStr()  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = StringConcatenate("'", CharToStr(values[i]), "'");
   }

   string joined = JoinStrings(strings, separator);
   if (!StringLen(joined))
      return("");
   return(StringConcatenate("{", joined, "}"));
}


/**
 * Konvertiert ein Integer-Array mit bis zu 3 Dimensionen in einen lesbaren String.
 *
 * @param  int    values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string IntsToStr(int values[][], string separator=", ") {
   return(__IntsToStr(values, values, separator));
}


/**
 * Interne Hilfsfunktion (Workaround um Dimension-Check des Compilers)
 *
 * @private - Aufruf nur aus IntsToStr()
 */
/*@private*/string __IntsToStr(int values2[][], int values3[][][], string separator) {
   if (separator == "0")      // (string) NULL
      separator = ", ";

   int dimensions=ArrayDimension(values2), dim1=ArrayRange(values2, 0), dim2, dim3;
   string result;


   // 1-dimensionales Array
   if (dimensions == 1) {
      if (dim1 == 0)
         return("{}");
      return(StringConcatenate("{", JoinInts(values2, separator), "}"));
   }
   else dim2 = ArrayRange(values2, 1);


   // 2-dimensionales Array
   if (dimensions == 2) {
      string strValues2.X[]; ArrayResize(strValues2.X, dim1);
      int       values2.Y[]; ArrayResize(   values2.Y, dim2);

      for (int x=0; x < dim1; x++) {
         for (int y=0; y < dim2; y++) {
            values2.Y[y] = values2[x][y];
         }
         strValues2.X[x] = IntsToStr(values2.Y, separator);
      }

      result = StringConcatenate("{", JoinStrings(strValues2.X, separator), "}");
      ArrayResize(strValues2.X, 0);
      ArrayResize(   values2.Y, 0);
      return(result);
   }
   else dim3 = ArrayRange(values3, 2);


   // 3-dimensionales Array
   if (dimensions == 3) {
      string strValues3.X[]; ArrayResize(strValues3.X, dim1);
      string strValues3.Y[]; ArrayResize(strValues3.Y, dim2);
      int       values3.Z[]; ArrayResize(   values3.Z, dim3);

      for (x=0; x < dim1; x++) {
         for (y=0; y < dim2; y++) {
            for (int z=0; z < dim3; z++) {
               values3.Z[z] = values3[x][y][z];
            }
            strValues3.Y[y] = IntsToStr(values3.Z, separator);
         }
         strValues3.X[x] = StringConcatenate("{", JoinStrings(strValues3.Y, separator), "}");
      }

      result = StringConcatenate("{", JoinStrings(strValues3.X, separator), "}");
      ArrayResize(strValues3.X, 0);
      ArrayResize(strValues3.Y, 0);
      ArrayResize(   values3.Z, 0);
      return(result);
   }

   return(_EMPTY_STR(catch("__IntsToStr(1)  too many dimensions of parameter values = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS)));
}


/**
 * Konvertiert ein Array mit Ordertickets in einen lesbaren String.
 *
 * @param  int    tickets[] - f�r Tickets ung�ltige Werte werden entsprechend dargestellt
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string TicketsToStr(int tickets[], string separator=", ") {
   if (ArrayDimension(tickets) != 1)
      return(_EMPTY_STR(catch("TicketsToStr(1)  illegal dimensions of parameter tickets = "+ ArrayDimension(tickets), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(tickets);
   if (!size)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string result, sValue;

   for (int i=0; i < size; i++) {
      if   (tickets[i] > 0) sValue = StringConcatenate("#", tickets[i]);
      else if (!tickets[i]) sValue = "(NULL)";
      else                  sValue = StringConcatenate("(invalid ticket #", tickets[i], ")");
      result = StringConcatenate(result, separator, sValue);
   }

   return(StringConcatenate("{", StringRight(result, -StringLen(separator)), "}"));
}


/**
 * Konvertiert ein Array mit Ordertickets in einen lesbaren String, der zus�tzlich die Lotsize des jeweiligen Tickets enth�lt.
 *
 * @param  int    tickets[] - f�r Tickets ung�ltige Werte werden entsprechend dargestellt
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string TicketsToStr.Lots(int tickets[], string separator=", ") {
   if (ArrayDimension(tickets) != 1)
      return(_EMPTY_STR(catch("TicketsToStr.Lots(1)  illegal dimensions of parameter tickets = "+ ArrayDimension(tickets), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(tickets);
   if (!size)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string result, sValue;

   OrderPush("TicketsToStr.Lots(2)");

   for (int i=0; i < size; i++) {
      if (tickets[i] > 0) {
         if (OrderSelect(tickets[i], SELECT_BY_TICKET)) {
            if      (IsLongTradeOperation (OrderType())) sValue = StringConcatenate("#", tickets[i], ":+", NumberToStr(OrderLots(), ".1+"));
            else if (IsShortTradeOperation(OrderType())) sValue = StringConcatenate("#", tickets[i], ":-", NumberToStr(OrderLots(), ".1+"));
            else                                         sValue = StringConcatenate("#", tickets[i], ":none");
         }
         else                                            sValue = StringConcatenate("(unknown ticket #", tickets[i], ")");
      }
      else if (!tickets[i]) sValue = "(NULL)";
      else                  sValue = StringConcatenate("(invalid ticket #", tickets[i], ")");

      result = StringConcatenate(result, separator, sValue);
   }

   OrderPop("TicketsToStr.Lots(3)");

   return(StringConcatenate("{", StringRight(result, -StringLen(separator)), "}"));
}


/**
 * Konvertiert ein Array mit Ordertickets in einen lesbaren String, der zus�tzlich die Lotsize und das Symbol des jeweiligen Tickets enth�lt.
 *
 * @param  int    tickets[] - f�r Tickets ung�ltige Werte werden entsprechend dargestellt
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string TicketsToStr.LotsSymbols(int tickets[], string separator=", ") {
   if (ArrayDimension(tickets) != 1)
      return(_EMPTY_STR(catch("TicketsToStr.LotsSymbols(1)  illegal dimensions of parameter tickets = "+ ArrayDimension(tickets), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(tickets);
   if (!size)
      return("{}");

   if (separator == "0")      // (string) NULL
      separator = ", ";

   string result, sValue;

   OrderPush("TicketsToStr.LotsSymbols(2)");

   for (int i=0; i < size; i++) {
      if (tickets[i] > 0) {
         if (OrderSelect(tickets[i], SELECT_BY_TICKET)) {
            if      (IsLongTradeOperation (OrderType())) sValue = StringConcatenate("#", tickets[i], ":+", NumberToStr(OrderLots(), ".1+"), OrderSymbol());
            else if (IsShortTradeOperation(OrderType())) sValue = StringConcatenate("#", tickets[i], ":-", NumberToStr(OrderLots(), ".1+"), OrderSymbol());
            else                                         sValue = StringConcatenate("#", tickets[i], ":none");
         }
         else                                            sValue = StringConcatenate("(unknown ticket #", tickets[i], ")");
      }
      else if (!tickets[i]) sValue = "(NULL)";
      else                  sValue = StringConcatenate("(invalid ticket #", tickets[i], ")");

      result = StringConcatenate(result, separator, sValue);
   }

   OrderPop("TicketsToStr.LotsSymbols(3)");

   return(StringConcatenate("{", StringRight(result, -StringLen(separator)), "}"));
}


/**
 * Ermittelt die Gesamtposition der Tickets eines Arrays und gibt sie als einen lesbaren String zur�ck.
 *
 * @param  int tickets[]
 *
 * @return string - String mit Gesamtposition oder Leerstring, falls ein Fehler auftrat
 */
string TicketsToStr.Position(int tickets[]) {
   if (ArrayDimension(tickets) != 1)
      return(_EMPTY_STR(catch("TicketsToStr.Position(1)  illegal dimensions of parameter tickets = "+ ArrayDimension(tickets), ERR_INCOMPATIBLE_ARRAYS)));

   int ticketsSize = ArraySize(tickets);
   if (!ticketsSize)
      return("(empty)");

   double long, short, total, hedged;

   OrderPush("TicketsToStr.Position(2)");

   for (int i=0; i < ticketsSize; i++) {
      if (tickets[i] > 0) {
         if (OrderSelect(tickets[i], SELECT_BY_TICKET)) {
            if (IsLongTradeOperation(OrderType())) long  += OrderLots();
            else                                   short += OrderLots();
         }
         else GetLastError();
      }
   }

   OrderPop("TicketsToStr.Position(3)");

   long   = NormalizeDouble(long,  2);
   short  = NormalizeDouble(short, 2);
   total  = NormalizeDouble(long - short, 2);
   hedged = MathMin(long, short);
   bool isPosition = long || short;

   string result;
   if (!isPosition) result = "(none)";
   else if (!total) result = "�"+ NumberToStr(long,  ".+")                                                         +" lots (hedged)";
   else             result =      NumberToStr(total, ".+") + ifString(hedged, " �"+ NumberToStr(hedged, ".+"), "") +" lots";

   return(result);
}


/**
 * Konvertiert ein Boolean-Array mit bis zu 3 Dimensionen in einen lesbaren String.
 *
 * @param  bool   values[]
 * @param  string separator - Separator (default: NULL = ", ")
 *
 * @return string - resultierender String oder Leerstring, falls ein Fehler auftrat
 */
string BoolsToStr(bool values[][], string separator=", ") {
   return(__BoolsToStr(values, values, separator));
}


/**
 * Interne Hilfsfunktion (Workaround um Dimension-Check des Compilers)
 *
 * @private - Aufruf nur aus BoolsToStr()
 */
/*@private*/string __BoolsToStr(bool values2[][], bool values3[][][], string separator) {
   if (separator == "0")      // (string) NULL
      separator = ", ";

   int dimensions=ArrayDimension(values2), dim1=ArrayRange(values2, 0), dim2, dim3;
   string result;


   // 1-dimensionales Array
   if (dimensions == 1) {
      if (dim1 == 0)
         return("{}");
      return(StringConcatenate("{", JoinBools(values2, separator), "}"));
   }
   else dim2 = ArrayRange(values2, 1);


   // 2-dimensionales Array
   if (dimensions == 2) {
      string strValues2.X[]; ArrayResize(strValues2.X, dim1);
      bool      values2.Y[]; ArrayResize(   values2.Y, dim2);

      for (int x=0; x < dim1; x++) {
         for (int y=0; y < dim2; y++) {
            values2.Y[y] = values2[x][y];
         }
         strValues2.X[x] = BoolsToStr(values2.Y, separator);
      }

      result = StringConcatenate("{", JoinStrings(strValues2.X, separator), "}");
      ArrayResize(strValues2.X, 0);
      ArrayResize(   values2.Y, 0);
      return(result);
   }
   else dim3 = ArrayRange(values3, 2);


   // 3-dimensionales Array
   if (dimensions == 3) {
      string strValues3.X[]; ArrayResize(strValues3.X, dim1);
      string strValues3.Y[]; ArrayResize(strValues3.Y, dim2);
      bool      values3.Z[]; ArrayResize(   values3.Z, dim3);

      for (x=0; x < dim1; x++) {
         for (y=0; y < dim2; y++) {
            for (int z=0; z < dim3; z++) {
               values3.Z[z] = values3[x][y][z];
            }
            strValues3.Y[y] = BoolsToStr(values3.Z, separator);
         }
         strValues3.X[x] = StringConcatenate("{", JoinStrings(strValues3.Y, separator), "}");
      }

      result = StringConcatenate("{", JoinStrings(strValues3.X, separator), "}");
      ArrayResize(strValues3.X, 0);
      ArrayResize(strValues3.Y, 0);
      ArrayResize(   values3.Z, 0);
      return(result);
   }

   return(_EMPTY_STR(catch("__BoolsToStr()  too many dimensions of parameter values = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS)));
}


/**
 * Speichert LFX-Orderdaten in der Library oder restauriert sie aus in der Library gespeicherten Daten.
 *
 * @param  bool   store       - Richtung: TRUE = kopiert aus den Parametern in die Library; FALSE = kopiert aus der Library in die Parameter
 * @param  int    orders[]    - LFX-Orders
 * @param  int    iVolatile[] - volatile Integer-Daten
 * @param  double dVolatile[] - volatile Double-Daten
 *
 * @return int - Anzahl der kopierten Orders oder -1 (EMPTY), falls ein Fehler auftrat
 */
int ChartInfos.CopyLfxStatus(bool store, /*LFX_ORDER*/int orders[][], int iVolatile[][], double dVolatile[][]) {
   store = store!=0;

   static int    static.orders   [][LFX_ORDER.intSize];
   static int    static.iVolatile[][3];
   static double static.dVolatile[][1];

   if (store) {
      ArrayResize(static.orders,    0);
      ArrayResize(static.iVolatile, 0);
      ArrayResize(static.dVolatile, 0);

      if (ArrayRange(orders,    0) > 0) ArrayCopy(static.orders,    orders   );
      if (ArrayRange(iVolatile, 0) > 0) ArrayCopy(static.iVolatile, iVolatile);
      if (ArrayRange(dVolatile, 0) > 0) ArrayCopy(static.dVolatile, dVolatile);

      if (IsError(catch("ChartInfos.CopyLfxStatus(1)")))
         return(EMPTY);
   }
   else {
      ArrayResize(orders,    0);
      ArrayResize(iVolatile, 0);
      ArrayResize(dVolatile, 0);

      if (ArrayRange(static.orders,    0) > 0) ArrayCopy(orders,    static.orders   );
      if (ArrayRange(static.iVolatile, 0) > 0) ArrayCopy(iVolatile, static.iVolatile);
      if (ArrayRange(static.dVolatile, 0) > 0) ArrayCopy(dVolatile, static.dVolatile);

      if (IsError(catch("ChartInfos.CopyLfxStatus(2)")))
         return(EMPTY);
   }

   return(ArrayRange(orders, 0));
}


/**
 * F�gt an einem Offset eines zwei-dimensionalen Double-Arrays ein anderes Double-Array ein.
 *
 * @param  double array[][] - zu vergr��erndes zwei-dimensionales Ausgangs-Array
 * @param  int    offset    - Position im Ausgangs-Array, an dem das andere Array eingef�gt werden soll
 * @param  double values[]  - einzuf�gendes Array (mu� in seiner ersten Dimension der zweiten Dimension des Ausgangsarrays entsprechen)
 *
 * @return int - neue Gr��e des Ausgangsarrays oder -1 (EMPTY), falls ein Fehler auftrat
 */
int ArrayInsertDoubleArray(double array[][], int offset, double values[]) {
   if (ArrayDimension(array) != 2)         return(catch("ArrayInsertDoubleArray(1)  illegal dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS));
   if (ArrayDimension(values) != 1)        return(catch("ArrayInsertDoubleArray(2)  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS));
   int array.dim1   = ArrayRange(array, 0);
   int array.dim2   = ArrayRange(array, 1);
   if (ArraySize(values) != array.dim2)    return(catch("ArrayInsertDoubleArray(3)  array size mis-match of parameters array and values: array["+ array.dim1 +"]["+ array.dim2 +"] / values["+ ArraySize(values) +"]", ERR_INCOMPATIBLE_ARRAYS));
   if (offset < 0 || offset >= array.dim1) return(catch("ArrayInsertDoubleArray(4)  illegal parameter offset = "+ offset, ERR_INVALID_PARAMETER));

   // Ausgangsarray vergr��ern
   int newSize = array.dim1 + 1;
   ArrayResize(array, newSize);

   // Inhalt des Ausgangsarrays von offset nach hinten verschieben
   int array.dim2.size = array.dim2 * DOUBLE_VALUE;
   int src   = GetDoublesAddress(array) + offset * array.dim2.size;
   int dest  =                               src + array.dim2.size;
   int bytes =               (array.dim1-offset) * array.dim2.size;
   CopyMemory(dest, src, bytes);

   // Inhalt des anderen Arrays an den gew�nschten Offset schreiben
   dest  = src;
   src   = GetDoublesAddress(values);
   bytes = array.dim2.size;
   CopyMemory(dest, src, bytes);

   return(newSize);
}


/**
 * F�gt ein Element an der angegebenen Position eines String-Arrays ein.
 *
 * @param  string array[] - String-Array
 * @param  int    offset  - Position, an dem das Element eingef�gt werden soll
 * @param  string value   - einzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays oder -1 (nEMPTY), falls ein Fehler auftrat
 */
int ArrayInsertString(string &array[], int offset, string value) {
   if (ArrayDimension(array) > 1) return(_EMPTY(catch("ArrayInsertString(1)  too many dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS)));
   if (offset < 0)                return(_EMPTY(catch("ArrayInsertString(2)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER)));
   int size = ArraySize(array);
   if (size < offset)             return(_EMPTY(catch("ArrayInsertString(3)  invalid parameter offset = "+ offset +" (sizeOf(array) = "+ size +")", ERR_INVALID_PARAMETER)));

   // Einf�gen am Anfang des Arrays
   if (offset == 0)
      return(ArrayUnshiftString(array, value));

   // Einf�gen am Ende des Arrays
   if (offset == size)
      return(ArrayPushString(array, value));

   // Einf�gen innerhalb des Arrays: ArrayCopy() "zerst�rt" bei String-Arrays den sich �berlappenden Bereich, daher zus�tzliche Kopie n�tig
   string tmp[]; ArrayResize(tmp, 0);
   ArrayCopy(tmp, array, 0, offset, size-offset);                                // Kopie der Elemente hinterm Einf�gepunkt machen
   ArrayCopy(array, tmp, offset+1);                                              // Elemente hinterm Einf�gepunkt nach hinten schieben (Quelle: die Kopie)
   ArrayResize(tmp, 0);
   array[offset] = value;                                                        // L�cke mit einzuf�gendem Wert f�llen
   return(size + 1);
}


/**
 * F�gt in ein String-Array die Elemente eines anderen String-Arrays ein.
 *
 * @param  string array[]  - Ausgangs-Array
 * @param  int    offset   - Position im Ausgangs-Array, an dem die Elemente eingef�gt werden sollen
 * @param  string values[] - einzuf�gende Elemente
 *
 * @return int - neue Gr��e des Arrays oder -1 (EMPTY), falls ein Fehler auftrat
 */
int ArrayInsertStrings(string array[], int offset, string values[]) {
   if (ArrayDimension(array) > 1)  return(_EMPTY(catch("ArrayInsertStrings(1)  too many dimensions of parameter array = "+ ArrayDimension(array), ERR_INCOMPATIBLE_ARRAYS)));
   if (offset < 0)                 return(_EMPTY(catch("ArrayInsertStrings(2)  invalid parameter offset = "+ offset, ERR_INVALID_PARAMETER)));
   int sizeOfArray = ArraySize(array);
   if (sizeOfArray < offset)       return(_EMPTY(catch("ArrayInsertStrings(3)  invalid parameter offset = "+ offset +" (sizeOf(array) = "+ sizeOfArray +")", ERR_INVALID_PARAMETER)));
   if (ArrayDimension(values) > 1) return(_EMPTY(catch("ArrayInsertStrings(4)  too many dimensions of parameter values = "+ ArrayDimension(values), ERR_INCOMPATIBLE_ARRAYS)));
   int sizeOfValues = ArraySize(values);

   // Einf�gen am Anfang des Arrays
   if (offset == 0)
      return(MergeStringArrays(values, array, array));

   // Einf�gen am Ende des Arrays
   if (offset == sizeOfArray)
      return(MergeStringArrays(array, values, array));

   // Einf�gen innerhalb des Arrays
   int newSize = sizeOfArray + sizeOfValues;
   ArrayResize(array, newSize);

   // ArrayCopy() "zerst�rt" bei String-Arrays den sich �berlappenden Bereich, wir m�ssen mit einer zus�tzlichen Kopie arbeiten
   string tmp[]; ArrayResize(tmp, 0);
   ArrayCopy(tmp, array, 0, offset, sizeOfArray-offset);                         // Kopie der Elemente hinter dem Einf�gepunkt erstellen
   ArrayCopy(array, tmp, offset+sizeOfValues);                                   // Elemente hinter dem Einf�gepunkt nach hinten schieben
   ArrayCopy(array, values, offset);                                             // L�cke mit einzuf�genden Werten �berschreiben

   ArrayResize(tmp, 0);
   return(newSize);
}


/**
 * Sortiert die �bergebenen Ticketdaten nach {OpenTime, Ticket}.
 *
 * @param  int tickets[] - Array mit Ticketdaten
 *
 * @return bool - Erfolgsstatus
 */
bool SortOpenTickets(int tickets[][/*{OpenTime, Ticket}*/]) {
   if (ArrayRange(tickets, 1) != 2) return(!catch("SortOpenTickets(1)  invalid parameter tickets["+ ArrayRange(tickets, 0) +"]["+ ArrayRange(tickets, 1) +"]", ERR_INCOMPATIBLE_ARRAYS));

   int rows = ArrayRange(tickets, 0);
   if (rows < 2)
      return(true);                                                  // weniger als 2 Zeilen

   // Zeilen nach OpenTime sortieren
   ArraySort(tickets);

   // Zeilen mit gleicher OpenTime zus�tzlich nach Ticket sortieren
   int openTime, lastOpenTime, ticket, sameOpenTimes[][2];
   ArrayResize(sameOpenTimes, 1);

   for (int i=0, n; i < rows; i++) {
      openTime = tickets[i][0];
      ticket   = tickets[i][1];

      if (openTime == lastOpenTime) {
         n++;
         ArrayResize(sameOpenTimes, n+1);
      }
      else if (n > 0) {
         // in sameOpenTimes[] angesammelte Zeilen von keys[] nach Ticket sortieren
         if (!_SOT.SameOpenTimes(tickets, sameOpenTimes))
            return(false);
         ArrayResize(sameOpenTimes, 1);
         n = 0;
      }
      sameOpenTimes[n][0] = ticket;
      sameOpenTimes[n][1] = i;                                       // Originalposition der Zeile in keys[]

      lastOpenTime = openTime;
   }
   if (n > 0) {
      // im letzten Schleifendurchlauf in sameOpenTimes[] angesammelte Zeilen m�ssen auch sortiert werden
      if (!_SOT.SameOpenTimes(tickets, sameOpenTimes))
         return(false);
      n = 0;
   }
   ArrayResize(sameOpenTimes, 0);

   return(!catch("SortOpenTickets(2)"));
}


/**
 * Sortiert die in rowsToSort[] angegebenen Zeilen des Datenarrays ticketData[] nach Ticket. Die OpenTime-Felder dieser Zeilen
 * sind gleich und m�ssen nicht umsortiert werden.
 *
 * @param  int ticketData[] - zu sortierendes Datenarray
 * @param  int rowsToSort[] - Array mit aufsteigenden Indizes der umzusortierenden Zeilen des Datenarrays
 *
 * @return bool - Erfolgsstatus
 *
privat*/bool _SOT.SameOpenTimes(int &ticketData[][/*{OpenTime, Ticket}*/], int rowsToSort[][/*{Ticket, i}*/]) {
   int rows.copy[][2]; ArrayResize(rows.copy, 0);
   ArrayCopy(rows.copy, rowsToSort);                                 // auf Kopie von rowsToSort[] arbeiten, um das �bergebene Array nicht zu modifizieren

   // Zeilen nach Ticket sortieren
   ArraySort(rows.copy);

   int ticket, rows=ArrayRange(rowsToSort, 0);

   // Originaldaten mit den sortierten Werten �berschreiben
   for (int i, n=0; n < rows; n++) {
      i                = rowsToSort[n][1];
      ticketData[i][1] = rows.copy [n][0];
   }

   ArrayResize(rows.copy, 0);
   return(!catch("_SOT.SameOpenTimes(1)"));
}


/**
 * Sortiert die �bergebenen Ticketdaten nach {CloseTime, OpenTime, Ticket}.
 *
 * @param  int tickets[] - Array mit Ticketdaten
 *
 * @return bool - Erfolgsstatus
 */
bool SortClosedTickets(int tickets[][/*{CloseTime, OpenTime, Ticket}*/]) {
   if (ArrayRange(tickets, 1) != 3) return(!catch("SortClosedTickets(1)  invalid parameter tickets["+ ArrayRange(tickets, 0) +"]["+ ArrayRange(tickets, 1) +"]", ERR_INCOMPATIBLE_ARRAYS));

   int rows = ArrayRange(tickets, 0);
   if (rows < 2)
      return(true);                                                  // single row, nothing to do


   // (1) alle Zeilen nach CloseTime sortieren
   ArraySort(tickets);


   // (2) Zeilen mit gleicher CloseTime zus�tzlich nach OpenTime sortieren
   int closeTime, openTime, ticket, lastCloseTime, sameCloseTimes[][3];
   ArrayResize(sameCloseTimes, 1);

   for (int n, i=0; i < rows; i++) {
      closeTime = tickets[i][0];
      openTime  = tickets[i][1];
      ticket    = tickets[i][2];

      if (closeTime == lastCloseTime) {
         n++;
         ArrayResize(sameCloseTimes, n+1);
      }
      else if (n > 0) {
         // in sameCloseTimes[] angesammelte Zeilen von tickets[] nach OpenTime sortieren
         _SCT.SameCloseTimes(tickets, sameCloseTimes);
         ArrayResize(sameCloseTimes, 1);
         n = 0;
      }
      sameCloseTimes[n][0] = openTime;
      sameCloseTimes[n][1] = ticket;
      sameCloseTimes[n][2] = i;                                      // Originalposition der Zeile in keys[]

      lastCloseTime = closeTime;
   }
   if (n > 0) {
      // im letzten Schleifendurchlauf in sameCloseTimes[] angesammelte Zeilen m�ssen auch sortiert werden
      _SCT.SameCloseTimes(tickets, sameCloseTimes);
      n = 0;
   }
   ArrayResize(sameCloseTimes, 0);


   // (3) Zeilen mit gleicher Close- und OpenTime zus�tzlich nach Ticket sortieren
   int lastOpenTime, sameOpenTimes[][2];
   ArrayResize(sameOpenTimes, 1);
   lastCloseTime = 0;

   for (i=0; i < rows; i++) {
      closeTime = tickets[i][0];
      openTime  = tickets[i][1];
      ticket    = tickets[i][2];

      if (closeTime==lastCloseTime && openTime==lastOpenTime) {
         n++;
         ArrayResize(sameOpenTimes, n+1);
      }
      else if (n > 0) {
         // in sameOpenTimes[] angesammelte Zeilen von tickets[] nach Ticket sortieren
         _SCT.SameOpenTimes(tickets, sameOpenTimes);
         ArrayResize(sameOpenTimes, 1);
         n = 0;
      }
      sameOpenTimes[n][0] = ticket;
      sameOpenTimes[n][1] = i;                                       // Originalposition der Zeile in tickets[]

      lastCloseTime = closeTime;
      lastOpenTime  = openTime;
   }
   if (n > 0) {
      // im letzten Schleifendurchlauf in sameOpenTimes[] angesammelte Zeilen m�ssen auch sortiert werden
      _SCT.SameOpenTimes(tickets, sameOpenTimes);
   }
   ArrayResize(sameOpenTimes, 0);

   return(!catch("SortClosedTickets(2)"));
}


/**
 * Sortiert die in rowsToSort[] angegebenen Zeilen des Datenarrays ticketData[] nach {OpenTime, Ticket}. Die CloseTime-Felder dieser Zeilen
 * sind gleich und m�ssen nicht umsortiert werden.
 *
 * @param  int ticketData[] - zu sortierendes Datenarray
 * @param  int rowsToSort[] - Array mit aufsteigenden Indizes der umzusortierenden Zeilen des Datenarrays
 *
 * @return bool - Erfolgsstatus
 *
 * @private - Aufruf nur aus SortClosedTickets()
 */
/*@private*/bool _SCT.SameCloseTimes(int &ticketData[][/*{CloseTime, OpenTime, Ticket}*/], int rowsToSort[][/*{OpenTime, Ticket, i}*/]) {
   int rows.copy[][3]; ArrayResize(rows.copy, 0);
   ArrayCopy(rows.copy, rowsToSort);                                 // auf Kopie von rowsToSort[] arbeiten, um das �bergebene Array nicht zu modifizieren

   // Zeilen nach OpenTime sortieren
   ArraySort(rows.copy);

   // Original-Daten mit den sortierten Werten �berschreiben
   int openTime, ticket, rows=ArrayRange(rowsToSort, 0);

   for (int i, n=0; n < rows; n++) {                                 // Originaldaten mit den sortierten Werten �berschreiben
      i                = rowsToSort[n][2];
      ticketData[i][1] = rows.copy [n][0];
      ticketData[i][2] = rows.copy [n][1];
   }

   ArrayResize(rows.copy, 0);
   return(!catch("_SCT.SameCloseTimes()"));
}


/**
 * Sortiert die in rowsToSort[] angegebene Zeilen des Datenarrays ticketData[] nach {Ticket}. Die Open- und CloseTime-Felder dieser Zeilen
 * sind gleich und m�ssen nicht umsortiert werden.
 *
 * @param  int ticketData[] - zu sortierendes Datenarray
 * @param  int rowsToSort[] - Array mit aufsteigenden Indizes der umzusortierenden Zeilen des Datenarrays
 *
 * @return bool - Erfolgsstatus
 *
 * @private - Aufruf nur aus SortClosedTickets()
 */
/*@private*/bool _SCT.SameOpenTimes(int &ticketData[][/*{OpenTime, CloseTime, Ticket}*/], int rowsToSort[][/*{Ticket, i}*/]) {
   int rows.copy[][2]; ArrayResize(rows.copy, 0);
   ArrayCopy(rows.copy, rowsToSort);                                 // auf Kopie von rowsToSort[] arbeiten, um das �bergebene Array nicht zu modifizieren

   // Zeilen nach Ticket sortieren
   ArraySort(rows.copy);

   int ticket, rows=ArrayRange(rowsToSort, 0);

   for (int i, n=0; n < rows; n++) {                                 // Originaldaten mit den sortierten Werten �berschreiben
      i                = rowsToSort[n][1];
      ticketData[i][2] = rows.copy [n][0];
   }

   ArrayResize(rows.copy, 0);
   return(!catch("_SCT.SameOpenTimes()"));
}


/**
 * Gibt die Laufzeit des Terminals seit Programmstart in Millisekunden zur�ck.
 *
 * @return int - Millisekunden seit Programmstart
 */
int GetTerminalRuntime() {
   /*FILETIME*/  int ft[], iNull[]; InitializeByteBuffer(ft, FILETIME.size  ); InitializeByteBuffer(iNull, FILETIME.size);
   /*SYSTEMTIME*/int st[];          InitializeByteBuffer(st, SYSTEMTIME.size);

   int creationTime[2], currentTime[2], hProcess=GetCurrentProcess();

   if (!GetProcessTimes(hProcess, ft, iNull, iNull, iNull)) return(catch("GetTerminalRuntime(1)->kernel32::GetProcessTimes()", ERR_WIN32_ERROR));
   if (!RtlTimeToSecondsSince1970(ft, creationTime))        return(catch("GetTerminalRuntime(2)->kernel32::RtlTimeToSecondsSince1970()", ERR_WIN32_ERROR));
   if (!FileTimeToSystemTime(ft, st))                       return(catch("GetTerminalRuntime(3)->kernel32::FileTimeToSystemTime()", ERR_WIN32_ERROR));
   creationTime[1] = st_Milliseconds(st);

   GetSystemTime(st);
   if (!SystemTimeToFileTime(st, ft))                       return(catch("GetTerminalRuntime(4)->kernel32::SystemTimeToFileTime()", ERR_WIN32_ERROR));
   if (!RtlTimeToSecondsSince1970(ft, currentTime))         return(catch("GetTerminalRuntime(5)->ntdll.dll::RtlTimeToSecondsSince1970()", ERR_WIN32_ERROR));
   currentTime[1] = st_Milliseconds(st);

   int secDiff  = currentTime[0] - creationTime[0];                  // Sekunden
   int mSecDiff = currentTime[1] - creationTime[1];                  // Millisekunden
   if (mSecDiff < 0)
      mSecDiff += 1000;
   int runtime  = secDiff * 1000 + mSecDiff;                         // Gesamtlaufzeit in Millisekunden

   return(runtime);
}


/**
 * Wird nur im Tester aus Library::init() aufgerufen, um alle verwendeten globalen Arrays zur�ckzusetzen (EA-Bugfix).
 */
void Tester.ResetGlobalArrays() {
   ArrayResize(stack.orderSelections, 0);
}


#import "Expander.dll"
   int  st_Milliseconds(/*SYSTEMTIME*/int st[]);
   int  GetDoublesAddress(double array[]);

#import "kernel32.dll"
   bool FileTimeToSystemTime(int lpFileTime[], int lpSystemTime[]);
   int  GetCurrentProcess();

   // Diese Deklaration benutzt zur R�ckgabe statt eines String-Buffers einen Byte-Buffer. Die Performance ist geringer, da der Buffer
   // selbst geparst werden mu�. Dies erm�glicht jedoch die R�ckgabe mehrerer Werte.
   int  GetPrivateProfileStringA(string lpSection, string lpKey, string lpDefault, int lpBuffer[], int bufferSize, string lpFileName);

   bool GetProcessTimes(int hProcess, int lpCreationTime[], int lpExitTime[], int lpKernelTime[], int lpUserTime[]);
   void GetSystemTime(int lpSystemTime[]);
   bool SystemTimeToFileTime(int lpSystemTime[], int lpFileTime[]);

#import "ntdll.dll"
   bool RtlTimeToSecondsSince1970(int lpTime[], int lpElapsedSeconds[]);

#import
