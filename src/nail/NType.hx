package nail;

/** A closed row: names are sorted canonically, types can be polymorphic. */
typedef StructuralField = {
  var name:String;
  var type:NType;
}

/** Types of Nail expressions; independent from the five runtime AST constructors. */
enum NType {
  TNumber;
  TInt;
  TRatio;
  TFloat;
  /** Opt-in exact numeric type; separate from legacy floating Number. */
  TExact;
  TBoolean;
  TText;
  TRecord(name:String);
  /** Closed, order-independent structural record. No open row variables. */
  TStructural(fields:Array<StructuralField>);
  /** Experimental open structural record: required fields plus unknown rest.
      Only the type checker interprets the rest; runtime representation is
      identical to a normal record. Not yet a public image type. */
  TOpenStructural(fields:Array<StructuralField>, rest:NType);
  /** Applied nominal record: Box[a], Pair[a,b]. */
  TRecordApplied(name:String, parameters:Array<NType>);
  TSum(name:String, parameters:Array<NType>);
  TSyntax;
  TVector(element:NType);
  TList(element:NType);
  TFunction(argument:NType, result:NType);
  TVariable(id:Int);
}

