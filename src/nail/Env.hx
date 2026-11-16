package nail;

import haxe.ds.StringMap;

/** Lexical scope. A shared global root also supports recursive definitions. */
class Env {
  public final parent:Null<Env>;
  final values:StringMap<Value>;

  public function new(parent:Null<Env> = null) {
    this.parent = parent;
    this.values = new StringMap<Value>();
  }

  public function hasHere(name:String):Bool return values.exists(name);

  public function bind(name:String, value:Value):Void values.set(name, value);

  public function lookup(name:String):Value {
    var scope:Null<Env> = this;
    while (scope != null) {
      if (scope.values.exists(name)) return scope.values.get(name);
      scope = scope.parent;
    }
    throw 'Unknown name: ' + name;
  }

  public function keys():Array<String> {
    var result:Array<String> = [];
    for (k in values.keys()) if (!StringTools.startsWith(k, '#')) result.push(k);
    result.sort(Reflect.compare);
    return result;
  }
}
