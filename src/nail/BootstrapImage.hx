package nail;

import haxe.Json;
import nail.Value;

/** Portable postfix representation of Syntax bytecode.
    The image decoder needs neither the host Parser nor the host compiler.
    Serialization uses explicit stacks and does not recurse over Syntax. */
class BootstrapImage {
  public static inline var FORMAT = 'nailseed.postfix-image.v1';

  static function children(list:Value):Array<Value> {
    var items:Array<Value> = [];
    var rest = list;
    while (true) {
      switch (rest) {
        case Nil: return items;
        case Cons(head, tail): items.push(head); rest = tail;
        case _: throw 'Invalid bootstrap image: Syntax children are not a list';
      }
    }
    return items;
  }

  /** Flatten Syntax in postorder. Each record is ["L", tag, text] for a leaf
      or ["N", tag, childCount] for a node. No recursive JSON object trees. */
  public static function encode(tree:Value):String {
    var instructions:Array<Dynamic> = [];
    var pending:Array<{value:Value, finish:Bool}> = [{value:tree, finish:false}];
    while (pending.length > 0) {
      var frame = pending.pop();
      switch (frame.value) {
        case SyntaxLeaf(tag, text):
          instructions.push(['L', tag, text]);
        case SyntaxNode(tag, list):
          var values = children(list);
          if (frame.finish) instructions.push(['N', tag, values.length]);
          else {
            pending.push({value:frame.value, finish:true});
            var i = values.length;
            while (i > 0) {
              i--;
              pending.push({value:values[i], finish:false});
            }
          }
        case _: throw 'Invalid bootstrap image: expected Syntax';
      }
    }
    return Json.stringify({format:FORMAT, records:instructions});
  }

  /** Decode a trusted build artifact without calling the source parser.
      Shape and stack balance are checked even though the image is embedded. */
  public static function decode(source:String):Value {
    var document:Dynamic = Json.parse(source);
    if (document == null || Reflect.field(document, 'format') != FORMAT)
      throw 'Invalid bootstrap image: format';
    var records:Dynamic = Reflect.field(document, 'records');
    if (!Std.isOfType(records, Array)) throw 'Invalid bootstrap image: records';
    var rows:Array<Dynamic> = cast records;
    if (rows.length == 0 || rows.length > 500000) throw 'Invalid bootstrap image: record count';
    var values:Array<Value> = [];
    for (raw in rows) {
      if (!Std.isOfType(raw, Array)) throw 'Invalid bootstrap image: record';
      var record:Array<Dynamic> = cast raw;
      if (record.length != 3 || !Std.isOfType(record[0], String) || !Std.isOfType(record[1], String))
        throw 'Invalid bootstrap image: record shape';
      var tag:String = cast record[1];
      switch (record[0]) {
        case 'L':
          if (!Std.isOfType(record[2], String)) throw 'Invalid bootstrap image: leaf';
          values.push(SyntaxLeaf(tag, cast record[2]));
        case 'N':
          var countValue:Dynamic = record[2];
          if (!Std.isOfType(countValue, Int) && !Std.isOfType(countValue, Float))
            throw 'Invalid bootstrap image: arity';
          var count:Float = countValue;
          if (!Math.isFinite(count) || count < 0 || count != Math.floor(count) || count > values.length)
            throw 'Invalid bootstrap image: arity';
          var rest:Value = Nil;
          var i = Std.int(count);
          while (i > 0) {
            i--;
            rest = Cons(values.pop(), rest);
          }
          values.push(SyntaxNode(tag, rest));
        case _: throw 'Invalid bootstrap image: record kind';
      }
    }
    if (values.length != 1) throw 'Invalid bootstrap image: unbalanced records';
    var result = values.pop();
    switch (result) {
      case SyntaxNode('Bytecode', _): return result;
      case _: throw 'Invalid bootstrap image: expected Bytecode';
    }
  }
}
