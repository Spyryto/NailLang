package nail;

/** A deferred numeric relation; all three terms share the scheme's quantifiers. */
typedef NumericPredicate = {
  var op:String;
  var left:NType;
  var right:NType;
  var result:NType;
}

/** Universally quantified type variables, Eq and experimental numeric constraints. */
typedef TypeScheme = {
  var term:NType;
  var quantified:Array<Int>;
  var comparable:Array<Int>;
  @:optional var numeric:Array<NumericPredicate>;
}
