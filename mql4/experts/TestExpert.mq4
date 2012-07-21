/**
 * TestExpert
 */
#include <types.mqh>
#define     __TYPE__    T_EXPERT
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>


bool done;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   if (!done) {

      /*ORDER_EXECUTION*/int oe[]; InitializeBuffer(oe, ORDER_EXECUTION.size);
      /*
      oe.setSymbol         (oe, Symbol());
      oe.setDigits         (oe, Digits);
      oe.setBid            (oe, Bid);
      oe.setAsk            (oe, Ask);
      oe.setTicket         (oe, 12345678);
      oe.setType           (oe, OP_BUY);
      oe.setLots           (oe, 0.03);
      oe.setOpenTime       (oe, TimeCurrent());
      oe.setOpenPrice      (oe, (Bid+Ask)/2);
      oe.setStopLoss       (oe, Bid-100*Pip);
      oe.setTakeProfit     (oe, Bid+100*Pip);
      oe.setCloseTime      (oe, TimeCurrent());
      oe.setClosePrice     (oe, (Bid+Ask)/2);
      oe.addSwap           (oe, 0.19);
      oe.addCommission     (oe, 8.00);
      oe.addProfit         (oe, -7.77);
      oe.setComment        (oe, "SR.12345.+5");
      oe.setDuration       (oe, 234);
      oe.setRequotes       (oe, 2);
      oe.setSlippage       (oe, 1.1);
      oe.setRemainingTicket(oe, 0);
      oe.setRemainingLots  (oe, 0.01);
      ORDER_EXECUTION.toStr(oe, true);
      */

      /*ORDER_EXECUTION*/int oes[1][ORDER_EXECUTION.length]; InitializeBuffer(oes, ORDER_EXECUTION.size);
      //ORDER_EXECUTION.toStr(oes, true);


      done = true;
   }
   return(catch("onTick()"));
}


string   oe.Symbol            (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Symbol         (oe, i));                              return(BufferCharsToStr.2(oe, 0, 12));                             }
int      oe.Digits            (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Digits         (oe, i));                                               return(oe[ 4]);                                 }
double   oe.Bid               (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Bid            (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[ 5]/MathPow(10, digits), digits));    }
double   oe.Ask               (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Ask            (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[ 6]/MathPow(10, digits), digits));    }
int      oe.Ticket            (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Ticket         (oe, i));                                               return(oe[ 7]);                                 }
int      oe.Type              (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Type           (oe, i));                                               return(oe[ 8]);                                 }
double   oe.Lots              (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Lots           (oe, i));                               return(NormalizeDouble(oe[ 9]/100.0, 2));                       }
datetime oe.OpenTime          (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.OpenTime       (oe, i));                                               return(oe[10]);                                 }
double   oe.OpenPrice         (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.OpenPrice      (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[11]/MathPow(10, digits), digits));    }
double   oe.StopLoss          (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.StopLoss       (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[12]/MathPow(10, digits), digits));    }
double   oe.TakeProfit        (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.TakeProfit     (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[13]/MathPow(10, digits), digits));    }
datetime oe.CloseTime         (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.CloseTime      (oe, i));                                               return(oe[14]);                                 }
double   oe.ClosePrice        (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.ClosePrice     (oe, i)); int digits=oe.Digits(oe);     return(NormalizeDouble(oe[15]/MathPow(10, digits), digits));    }
double   oe.Swap              (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Swap           (oe, i));                               return(NormalizeDouble(oe[16]/100.0, 2));                       }
double   oe.Commission        (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Commission     (oe, i));                               return(NormalizeDouble(oe[17]/100.0, 2));                       }
double   oe.Profit            (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Profit         (oe, i));                               return(NormalizeDouble(oe[18]/100.0, 2));                       }
string   oe.Comment           (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Comment        (oe, i));                              return(BufferCharsToStr.2(oe, 76, 27));                            }
int      oe.Duration          (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Duration       (oe, i));                                               return(oe[26]);                                 }
int      oe.Requotes          (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Requotes       (oe, i));                                               return(oe[27]);                                 }
double   oe.Slippage          (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.Slippage       (oe, i)); int digits=oe.Digits(oe);                     return(oe[28]/MathPow(10, digits<<31>>31));     }
int      oe.RemainingTicket   (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.RemainingTicket(oe, i));                                               return(oe[29]);                                 }
double   oe.RemainingLots     (/*ORDER_EXECUTION*/int oe[],   int i=NULL) { if (ArrayDimension(oe) != 1) return(oes.RemainingLots  (oe, i));                               return(NormalizeDouble(oe[30]/100.0, 2));                       }

string   oes.Symbol           (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Symbol         (oe)   );                              return(BufferCharsToStr.2(oe[i], 0, 12));                          }
int      oes.Digits           (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Digits         (oe)   );                                               return(oe[i][ 4]);                              }
double   oes.Bid              (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Bid            (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][ 5]/MathPow(10, digits), digits)); }
double   oes.Ask              (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Ask            (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][ 6]/MathPow(10, digits), digits)); }
int      oes.Ticket           (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Ticket         (oe)   );                                               return(oe[i][ 7]);                              }
int      oes.Type             (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Type           (oe)   );                                               return(oe[i][ 8]);                              }
double   oes.Lots             (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Lots           (oe)   );                               return(NormalizeDouble(oe[i][ 9]/100.0, 2));                    }
datetime oes.OpenTime         (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.OpenTime       (oe)   );                                               return(oe[i][10]);                              }
double   oes.OpenPrice        (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.OpenPrice      (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][11]/MathPow(10, digits), digits)); }
double   oes.StopLoss         (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.StopLoss       (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][12]/MathPow(10, digits), digits)); }
double   oes.TakeProfit       (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.TakeProfit     (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][13]/MathPow(10, digits), digits)); }
datetime oes.CloseTime        (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.CloseTime      (oe)   );                                               return(oe[i][14]);                              }
double   oes.ClosePrice       (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.ClosePrice     (oe)   ); int digits=oes.Digits(oe, i); return(NormalizeDouble(oe[i][15]/MathPow(10, digits), digits)); }
double   oes.Swap             (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Swap           (oe)   );                               return(NormalizeDouble(oe[i][16]/100.0, 2));                    }
double   oes.Commission       (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Commission     (oe)   );                               return(NormalizeDouble(oe[i][17]/100.0, 2));                    }
double   oes.Profit           (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Profit         (oe)   );                               return(NormalizeDouble(oe[i][18]/100.0, 2));                    }
string   oes.Comment          (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Comment        (oe)   );                              return(BufferCharsToStr.2(oe[i], 76, 27));                         }
int      oes.Duration         (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Duration       (oe)   );                                               return(oe[i][26]);                              }
int      oes.Requotes         (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Requotes       (oe)   );                                               return(oe[i][27]);                              }
double   oes.Slippage         (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.Slippage       (oe)   ); int digits=oes.Digits(oe, i);                 return(oe[i][28]/MathPow(10, digits<<31>>31));  }
int      oes.RemainingTicket  (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.RemainingTicket(oe)   );                                               return(oe[i][29]);                              }
double   oes.RemainingLots    (/*ORDER_EXECUTION*/int oe[][], int i     ) { if (ArrayDimension(oe) == 1) return( oe.RemainingLots  (oe)   );                               return(NormalizeDouble(oe[i][30]/100.0, 2));                    }





/**
 * Gibt die in einem Byte-Buffer im angegebenen Bereich gespeicherte und mit einem NULL-Byte terminierte ANSI-Charactersequenz zurück.
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur über ein Integer-Array abgebildet werden)
 * @param  int from     - Index des ersten Bytes des für die Charactersequenz reservierten Bereichs, beginnend mit 0
 * @param  int length   - Anzahl der im Buffer für die Charactersequenz reservierten Bytes
 *
 * @return string - ANSI-String
 */
string BufferCharsToStr.2(int buffer[], int from, int length) {
   int fromChar=from, toChar=fromChar+length, bufferChars=ArraySize(buffer)<<2;

   if (fromChar < 0)            return(_empty(catch("BufferCharsToStr.2(1)  invalid parameter from: "+ from, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (fromChar >= bufferChars) return(_empty(catch("BufferCharsToStr.2(2)  invalid parameter from: "+ from, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (length < 0)              return(_empty(catch("BufferCharsToStr.2(3)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (toChar >= bufferChars)   return(_empty(catch("BufferCharsToStr.2(4)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (length == 0)
      return("");

   string result = "";
   int    chars, fromInt=fromChar>>2, toInt=toChar>>2, n=fromChar&0x03;    // Indizes der relevanten Array-Integers und des ersten Chars (liegt evt. nicht auf Integer-Boundary)

   for (int i=fromInt; i <= toInt; i++) {
      int byte, integer=buffer[i];

      for (; n < 4; n++) {                                                 // n: 0-1-2-3
         if (chars == length)
            break;
         byte = integer >> (n<<3) & 0xFF;                                  // integer >> 0-8-16-24
         if (byte == 0x00)                                                 // NULL-Byte: Ausbruch aus innerer Schleife
            break;
         result = StringConcatenate(result, CharToStr(byte));
         chars++;
      }
      if (byte == 0x00)                                                    // NULL-Byte: Ausbruch aus äußerer Schleife
         break;
      n = 0;
   }

   if (IsError(catch("BufferCharsToStr.2(5)")))
      return("");
   return(result);
}








string   oe.setSymbol         (/*ORDER_EXECUTION*/int  oe[], string   symbol    ) {
   if (StringLen(symbol) == 0) return(_empty(catch(StringConcatenate("oe.setSymbol(1)  invalid parameter symbol = \"", symbol, "\""), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (StringLen(symbol) > 12) return(_empty(catch(StringConcatenate("oe.setSymbol(2)  invalid parameter symbol = \"", symbol, "\""), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (IsError(BufferSetString(oe, 0, symbol))) return("");                                                                                        return(symbol    ); }
int      oe.setDigits         (/*ORDER_EXECUTION*/int &oe[], int      digits    ) { oe[ 4] = digits;                                               return(digits    ); }
double   oe.setBid            (/*ORDER_EXECUTION*/int &oe[], double   bid       ) { oe[ 5] = Round(bid * MathPow(10, oe.Digits(oe)));              return(bid       ); }
double   oe.setAsk            (/*ORDER_EXECUTION*/int &oe[], double   ask       ) { oe[ 6] = Round(ask * MathPow(10, oe.Digits(oe)));              return(ask       ); }
int      oe.setTicket         (/*ORDER_EXECUTION*/int &oe[], int      ticket    ) { oe[ 7] = ticket;                                               return(ticket    ); }
int      oe.setType           (/*ORDER_EXECUTION*/int &oe[], int      type      ) { oe[ 8] = type;                                                 return(type      ); }
double   oe.setLots           (/*ORDER_EXECUTION*/int &oe[], double   lots      ) { oe[ 9] = Round(lots * 100);                                    return(lots      ); }
datetime oe.setOpenTime       (/*ORDER_EXECUTION*/int &oe[], datetime openTime  ) { oe[10] = openTime;                                             return(openTime  ); }
double   oe.setOpenPrice      (/*ORDER_EXECUTION*/int &oe[], double   openPrice ) { oe[11] = Round(openPrice * MathPow(10, oe.Digits(oe)));        return(openPrice ); }
double   oe.setStopLoss       (/*ORDER_EXECUTION*/int &oe[], double   stopLoss  ) { oe[12] = Round(stopLoss * MathPow(10, oe.Digits(oe)));         return(stopLoss  ); }
double   oe.setTakeProfit     (/*ORDER_EXECUTION*/int &oe[], double   takeProfit) { oe[13] = Round(takeProfit * MathPow(10, oe.Digits(oe)));       return(takeProfit); }
datetime oe.setCloseTime      (/*ORDER_EXECUTION*/int &oe[], datetime closeTime ) { oe[14] = closeTime;                                            return(closeTime ); }
double   oe.setClosePrice     (/*ORDER_EXECUTION*/int &oe[], double   closePrice) { oe[15] = Round(closePrice * MathPow(10, oe.Digits(oe)));       return(closePrice); }
double   oe.setSwap           (/*ORDER_EXECUTION*/int &oe[], double   swap      ) { oe[16] = Round(swap * 100);                                    return(swap      ); }
double   oe.addSwap           (/*ORDER_EXECUTION*/int &oe[], double   swap      ) { oe[16]+= Round(swap * 100);                                    return(swap      ); }
double   oe.setCommission     (/*ORDER_EXECUTION*/int &oe[], double   comission ) { oe[17] = Round(comission * 100);                               return(comission ); }
double   oe.addCommission     (/*ORDER_EXECUTION*/int &oe[], double   comission ) { oe[17]+= Round(comission * 100);                               return(comission ); }
double   oe.setProfit         (/*ORDER_EXECUTION*/int &oe[], double   profit    ) { oe[18] = Round(profit * 100);                                  return(profit    ); }
double   oe.addProfit         (/*ORDER_EXECUTION*/int &oe[], double   profit    ) { oe[18]+= Round(profit * 100);                                  return(profit    ); }
string   oe.setComment        (/*ORDER_EXECUTION*/int  oe[], string   comment   ) {
   if (StringLen(comment) > 27) return(_empty(catch(StringConcatenate("oe.setComment()  invalid parameter comment = \"", comment, "\""), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (IsError(BufferSetString(oe, 76, comment))) return("");                                                                                      return(comment   ); }
int      oe.setDuration       (/*ORDER_EXECUTION*/int &oe[], int      milliSec  ) { oe[26] = milliSec;                                             return(milliSec  ); }
int      oe.setRequotes       (/*ORDER_EXECUTION*/int &oe[], int      requotes  ) { oe[27] = requotes;                                             return(requotes  ); }
double   oe.setSlippage       (/*ORDER_EXECUTION*/int &oe[], double   slippage  ) { oe[28] = Round(slippage * MathPow(10, oe.Digits(oe)<<31>>31)); return(slippage  ); }
int      oe.setRemainingTicket(/*ORDER_EXECUTION*/int &oe[], int      ticket    ) { oe[29] = ticket;                                               return(ticket    ); }
double   oe.setRemainingLots  (/*ORDER_EXECUTION*/int &oe[], double   lots      ) { oe[30] = Round(lots * 100);                                    return(lots      ); }


/**
 * Gibt die lesbare Repräsentation einer ORDER_EXECUTION-Struktur zurück.
 *
 * @param  int  oe[]        - ORDER_EXECUTION
 * @param  bool debugOutput - ob die Ausgabe zusätzlich zum Debugger geschickt werden soll (default: nein)
 *
 * @return string
 */
string ORDER_EXECUTION.toStr(/*ORDER_EXECUTION*/int oe[], bool debugOutput=false) {
   int dimensions = ArrayDimension(oe);

   if (dimensions > 2)                                         return(_empty(catch("ORDER_EXECUTION.toStr(1)  invalid parameter oe, too many dimensions ("+ dimensions +")", ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (ArrayRange(oe, dimensions-1) != ORDER_EXECUTION.length) return(_empty(catch("ORDER_EXECUTION.toStr(2)  invalid size of parameter oe ("+ ArrayRange(oe, dimensions-1) +")", ERR_INVALID_FUNCTION_PARAMVALUE)));

   int    digits, pipDigits;
   string priceFormat, output="";

   // oe ist struct ORDER_EXECUTION (eine Dimension)
   if (dimensions == 1) {
      digits      = oe.Digits(oe);
      pipDigits   = digits & (~1);
      priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
      output      = StringConcatenate("{symbol=\""       ,                          oe.Symbol         (oe), "\"",
                                      ", digits="         ,                          oe.Digits         (oe),
                                      ", bid="            ,              NumberToStr(oe.Bid            (oe), priceFormat),
                                      ", ask="            ,              NumberToStr(oe.Ask            (oe), priceFormat),
                                      ", ticket="         ,                          oe.Ticket         (oe),
                                      ", type=\""         , OperationTypeDescription(oe.Type           (oe)), "\"",
                                      ", lots="           ,              NumberToStr(oe.Lots           (oe), ".+"),
                                      ", openTime="       ,                 ifString(oe.OpenTime       (oe), "'"+ TimeToStr(oe.OpenTime(oe), TIME_FULL) +"'", "0"),
                                      ", openPrice="      ,              NumberToStr(oe.OpenPrice      (oe), priceFormat),
                                      ", stopLoss="       ,              NumberToStr(oe.StopLoss       (oe), priceFormat),
                                      ", takeProfit="     ,              NumberToStr(oe.TakeProfit     (oe), priceFormat),
                                      ", closeTime="      ,                 ifString(oe.CloseTime      (oe), "'"+ TimeToStr(oe.CloseTime(oe), TIME_FULL) +"'", "0"),
                                      ", closePrice="     ,              NumberToStr(oe.ClosePrice     (oe), priceFormat),
                                      ", swap="           ,              DoubleToStr(oe.Swap           (oe), 2),
                                      ", commission="     ,              DoubleToStr(oe.Commission     (oe), 2),
                                      ", profit="         ,              DoubleToStr(oe.Profit         (oe), 2),
                                      ", duration="       ,                          oe.Duration       (oe),
                                      ", requotes="       ,                          oe.Requotes       (oe),
                                      ", slippage="       ,              DoubleToStr(oe.Slippage       (oe), 1),
                                      ", comment=\""      ,                          oe.Comment        (oe), "\"",
                                      ", remainingTicket=",                          oe.RemainingTicket(oe),
                                      ", remainingLots="  ,              NumberToStr(oe.RemainingLots  (oe), ".+"), "}");
   }
   else {
      // oe ist struct ORDER_EXECUTION[] (zwei Dimensionen)
      int size = ArrayRange(oe, 0);
      for (int i=0; i < size; i++) {
         digits      = oe.Digits(oe, i); catch("ORDER_EXECUTION.toStr(0.1)");
         pipDigits   = digits & (~1);
         priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
         /*
         output      = StringConcatenate(output,
                              "[", i, "]={symbol=\""       ,                          oe.Symbol         (oe, i), "\"",
                                       ", digits="         ,                          oe.Digits         (oe, i),
                                       ", bid="            ,              NumberToStr(oe.Bid            (oe, i), priceFormat),
                                       ", ask="            ,              NumberToStr(oe.Ask            (oe, i), priceFormat),
                                       ", ticket="         ,                          oe.Ticket         (oe, i),
                                       ", type=\""         , OperationTypeDescription(oe.Type           (oe, i)), "\"",
                                       ", lots="           ,              NumberToStr(oe.Lots           (oe, i), ".+"),
                                       ", openTime="       ,                 ifString(oe.OpenTime       (oe, i), "'"+ TimeToStr(oe.OpenTime(oe, i), TIME_FULL) +"'", "0"),
                                       ", openPrice="      ,              NumberToStr(oe.OpenPrice      (oe, i), priceFormat),
                                       ", stopLoss="       ,              NumberToStr(oe.StopLoss       (oe, i), priceFormat),
                                       ", takeProfit="     ,              NumberToStr(oe.TakeProfit     (oe, i), priceFormat),
                                       ", closeTime="      ,                 ifString(oe.CloseTime      (oe, i), "'"+ TimeToStr(oe.CloseTime(oe, i), TIME_FULL) +"'", "0"),
                                       ", closePrice="     ,              NumberToStr(oe.ClosePrice     (oe, i), priceFormat),
                                       ", swap="           ,              DoubleToStr(oe.Swap           (oe, i), 2),
                                       ", commission="     ,              DoubleToStr(oe.Commission     (oe, i), 2),
                                       ", profit="         ,              DoubleToStr(oe.Profit         (oe, i), 2),
                                       ", duration="       ,                          oe.Duration       (oe, i),
                                       ", requotes="       ,                          oe.Requotes       (oe, i),
                                       ", slippage="       ,              DoubleToStr(oe.Slippage       (oe, i), 1),
                                       ", comment=\""      ,                          oe.Comment        (oe, i), "\"",
                                       ", remainingTicket=",                          oe.RemainingTicket(oe, i),
                                       ", remainingLots="  ,              NumberToStr(oe.RemainingLots  (oe, i), ".+"), "}", NL);
         */
         oe.Symbol         (oe, i); catch("ORDER_EXECUTION.toStr(0.2)");
         oe.Digits         (oe, i); catch("ORDER_EXECUTION.toStr(0.3)");
         oe.Bid            (oe, i); catch("ORDER_EXECUTION.toStr(0.4)");
         oe.Ask            (oe, i); catch("ORDER_EXECUTION.toStr(0.5)");
         oe.Ticket         (oe, i); catch("ORDER_EXECUTION.toStr(0.6)");
         oe.Type           (oe, i); catch("ORDER_EXECUTION.toStr(0.7)");
         oe.Lots           (oe, i); catch("ORDER_EXECUTION.toStr(0.8)");
         oe.OpenTime       (oe, i); catch("ORDER_EXECUTION.toStr(0.9)");
         oe.OpenPrice      (oe, i); catch("ORDER_EXECUTION.toStr(0.10)");
         oe.StopLoss       (oe, i); catch("ORDER_EXECUTION.toStr(0.11)");
         oe.TakeProfit     (oe, i); catch("ORDER_EXECUTION.toStr(0.12)");
         oe.CloseTime      (oe, i); catch("ORDER_EXECUTION.toStr(0.13)");
         oe.ClosePrice     (oe, i); catch("ORDER_EXECUTION.toStr(0.14)");
         oe.Swap           (oe, i); catch("ORDER_EXECUTION.toStr(0.15)");
         oe.Commission     (oe, i); catch("ORDER_EXECUTION.toStr(0.16)");
         oe.Profit         (oe, i); catch("ORDER_EXECUTION.toStr(0.17)");
         oe.Duration       (oe, i); catch("ORDER_EXECUTION.toStr(0.18)");
         oe.Requotes       (oe, i); catch("ORDER_EXECUTION.toStr(0.19)");
         oe.Slippage       (oe, i); catch("ORDER_EXECUTION.toStr(0.20)");
         oe.Comment        (oe, i); catch("ORDER_EXECUTION.toStr(0.21)");
         oe.RemainingTicket(oe, i); catch("ORDER_EXECUTION.toStr(0.22)");
         oe.RemainingLots  (oe, i); catch("ORDER_EXECUTION.toStr(0.23)");
      }
      output = StringTrimRight(output);
   }

   if (debugOutput)
      debug("ORDER_EXECUTION.toStr()   "+ output);
   return(output);
}
