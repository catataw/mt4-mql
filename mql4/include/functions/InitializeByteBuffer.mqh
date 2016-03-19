/**
 * Initialisiert einen Integer-Buffer zur Aufnahme der gew�nschten Anzahl von Bytes. K�rzer f�r
 *
 *   int buffer[(bytes+4-bytes%4)/4];
 *   ArrayInitialize(buffer, 0);
 *
 * @param  int buffer[] - das f�r den Buffer zu verwendende Integer-Array
 * @param  int bytes    - Anzahl der im Buffer zu speichernden Bytes
 *
 * @return int - Fehlerstatus
 */
int InitializeByteBuffer(int buffer[], int bytes) {
   int dimensions = ArrayDimension(buffer);

   if (dimensions > 2) return(catch("InitializeByteBuffer(1)  too many dimensions of parameter buffer = "+ dimensions, ERR_INCOMPATIBLE_ARRAYS));
   if (bytes < 0)      return(catch("InitializeByteBuffer(2)  invalid parameter bytes = "+ bytes, ERR_INVALID_PARAMETER));

   int ints = bytes/4;
   if (ints % 4 != 0)
      ints++;

   if (dimensions == 1) {
      if (ArraySize(buffer) != ints)
         ArrayResize(buffer, ints);
   }
   else if (ArrayRange(buffer, 1) != ints) {                         // die 2. Dimension mehrdimensionaler Arrays kann nicht dynamisch angepa�t werden
      return(catch("InitializeByteBuffer(3)  cannot runtime adjust size of second dimension (size="+ ArrayRange(buffer, 1) +")", ERR_INCOMPATIBLE_ARRAYS));
   }

   if (ArraySize(buffer) > 0)
      ArrayInitialize(buffer, 0);

   return(catch("InitializeByteBuffer(4)"));
}
