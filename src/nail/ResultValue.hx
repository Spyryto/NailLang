package nail;

import haxe.ds.StringMap;
import nail.Value;

/** Shared built-in Result[ok, error] representation.
    The owner and constructor tags are fixed and validated by the VM;
    existing sum pattern lowering uses the same #tag/#0 record envelope. */
class ResultValue {
  public static inline var OWNER = 'CoreResult';
  public static inline var OK = 'CoreOk';
  public static inline var ERR = 'CoreErr';

  static function make(tag:String, payload:Value):Value {
    var fields = new StringMap<Value>();
    fields.set('#tag', Text(tag));
    fields.set('#0', payload);
    return Record(OWNER, fields);
  }

  public static function ok(payload:Value):Value return make(OK, payload);
  public static function error(payload:Value):Value return make(ERR, payload);

  /** Fail closed if a host provides a malformed claimed Result. */
  public static function tag(value:Value):String return switch (value) {
    case Record(owner, fields) if (owner == OWNER):
      if (!fields.exists('#tag') || !fields.exists('#0')) throw 'Invalid CoreResult value';
      var count = 0;
      for (key in fields.keys()) {
        if (key != '#tag' && key != '#0') throw 'Invalid CoreResult value';
        count++;
      }
      if (count != 2) throw 'Invalid CoreResult value';
      switch (fields.get('#tag')) {
        case Text(label) if (label == OK): OK;
        case Text(label) if (label == ERR): ERR;
        case _: throw 'Invalid CoreResult value';
      }
    case _: throw 'Expected CoreResult value';
  };

  public static function is(value:Value, variant:String):Bool
    return tag(value) == variant;

  public static function get(value:Value, variant:String):Value {
    if (tag(value) != variant) throw 'Non-exhaustive or mismatched variant pattern';
    return switch (value) {
      case Record(_, fields): fields.get('#0');
      case _: throw 'Expected CoreResult value';
    };
  }
}
