package nail;

/** Types of Nail expressions; independent from the five runtime AST constructors. */
enum NType {
  TNumber;
  /** Opt-in exact numeric type; separate from legacy floating Number. */
  TExact;
  TBoolean;
  TText;
  TRecord(name:String);
  TSum(name:String, parameters:Array<NType>);
  TSyntax;
  TVector(element:NType);
  TList(element:NType);
  TFunction(argument:NType, result:NType);
  TVariable(id:Int);
}

