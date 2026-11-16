package nail;

import haxe.Json;
import nail.Value;

/** Dedicated transport for opt-in exact-number programs.
    Legacy bootstrap images always remain v1; a v2 image cannot be decoded
    by a legacy reader and cannot silently reinterpret exact literal digits
    as floating-point values. No JSON numeric field carries exact payloads. */
class ExactImage {
  public static inline var FORMAT = 'nailseed.postfix-image.v2-exact';
  public static inline var DIALECT = '0.29';

  static function inspect(records:Dynamic):Void {
    if (!Std.isOfType(records, Array)) throw 'Invalid exact image: records';
    var data:Array<Dynamic> = cast records;
    if (data.length == 0 || data.length > 500000)
      throw 'Invalid exact image: record count';
    for (row in data) {
      if (!Std.isOfType(row, Array)) throw 'Invalid exact image: row';
      var item:Array<Dynamic> = cast row;
      if (item.length != 3) throw 'Invalid exact image: record shape';
      if (item[0] == 'L' && item[1] == 'ExactNumber') {
        if (!Std.isOfType(item[2], String))
          throw 'Invalid exact image: numeric text';
        // Strict decoder verifies sign, fraction reduction, digit budgets
        // and canonical spelling; fast/large representation is not serialized.
        numeric.FastNumber.decodeExact(cast item[2]);
      }
    }
  }

  public static function encode(bytecode:Value):String {
    var legacy:Dynamic = Json.parse(BootstrapImage.encode(bytecode));
    inspect(Reflect.field(legacy, 'records'));
    Reflect.setField(legacy, 'format', FORMAT);
    Reflect.setField(legacy, 'sourceDialect', DIALECT);
    return Json.stringify(legacy);
  }

  public static function decode(encoded:String):Value {
    var data:Dynamic = Json.parse(encoded);
    if (data == null || Reflect.field(data, 'format') != FORMAT)
      throw 'Invalid exact image: format';
    if (Reflect.field(data, 'sourceDialect') != DIALECT)
      throw 'Invalid exact image: source dialect';
    inspect(Reflect.field(data, 'records'));
    Reflect.setField(data, 'format', BootstrapImage.FORMAT);
    // All structural/stack checks still belong to the existing v1 decoder.
    return BootstrapImage.decode(Json.stringify(data));
  }
}
