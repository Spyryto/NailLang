package nail;

import haxe.ds.StringMap;
import nail.NType;

/** Experimental bridge from checked, *closed* structural record contracts to
    opt-in parser context fields. No capitalization rule: Html and html are
    distinct value identifiers checked by the same mechanism.
    Not yet a source-language API or a row-polymorphic type solver. */
class ContextInterfaces {
  public static function fromChecked(checker:TypeChecker,
      names:Array<String>):StringMap<Array<String>> {
    if (checker==null || names==null)
      throw 'Context interface: missing type checker or requested names';
    var result=new StringMap<Array<String>>();
    for (name in names) {
      if (name==null || name.length==0 || result.exists(name))
        throw 'Context interface: invalid or duplicate value name';
      var scheme=checker.publicScheme(name);
      switch(scheme.term) {
        case TStructural(fields):
          if (!TypeChecker.validStructural(fields))
            throw 'Context interface: invalid closed structural record for '+name;
          result.set(name,[for (f in fields) f.name]);
        case _:
          throw 'Context interface: expected closed structural record value '+name;
      }
    }
    return result;
  }
}
