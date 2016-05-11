/**
 * MT4 struct SYMBOL_GROUP (Dateiformat "symgroups.raw")
 *
 * Die Gr��e der Datei ist fix und enth�lt Platz f�r exakt 32 Gruppen. Einzelne Gruppen k�nnen undefiniert sein.
 *
 * @see  MT4Expander::header/mql/structs/mt4/SymbolGroup.h
 */
#import "Expander.dll"
   // Getter
   string sg_Name              (/*SYMBOL_GROUP*/int sg[]);                       string sgs_Name              (/*SYMBOL_GROUP*/int sg[], int i);
   string sg_Description       (/*SYMBOL_GROUP*/int sg[]);                       string sgs_Description       (/*SYMBOL_GROUP*/int sg[], int i);
   color  sg_BackgroundColor   (/*SYMBOL_GROUP*/int sg[]);                       color  sgs_BackgroundColor   (/*SYMBOL_GROUP*/int sg[], int i);

   // Setter
   bool   sg_SetName           (/*SYMBOL_GROUP*/int sg[], string name       );   bool   sgs_SetName           (/*SYMBOL_GROUP*/int sg[], int i, string name       );
   bool   sg_SetDescription    (/*SYMBOL_GROUP*/int sg[], string description);   bool   sgs_SetDescription    (/*SYMBOL_GROUP*/int sg[], int i, string description);
   bool   sg_SetBackgroundColor(/*SYMBOL_GROUP*/int sg[], color  bgColor    );   bool   sgs_SetBackgroundColor(/*SYMBOL_GROUP*/int sg[], int i, color  bgColor    );
#import
