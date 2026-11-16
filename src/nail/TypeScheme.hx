package nail;

/** Universally quantified type variables and optional Eq constraints. */
typedef TypeScheme = {
  var term:NType;
  var quantified:Array<Int>;
  var comparable:Array<Int>;
}
