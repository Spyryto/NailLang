import haxe.Json;
import nail.BootRuntime;
import nail.TypeChecker;
import nail.Vm;

/** v0.60: unannotated field projection is structural, typed binders nominal. */
class StructuralProjectionTestMain {
  static var checks=0;
  static function ok(value:Bool,label:String):Void {
    if (!value) throw 'STRUCTURAL PROJECTION: '+label;
    checks++;
  }
  static function eq(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+': expected '+Json.stringify(expected)+', got '+Json.stringify(actual));
  static function rejects(source:String,needle:String,label:String):Void {
    var error='';
    try new TypeChecker().check(source)
    catch (e:Dynamic) error=Std.string(e);
    ok(error.indexOf(needle)>=0,label+': expected '+needle+', got '+error);
  }
  static function accepts(source:String,expected:Array<Dynamic>,label:String):Void {
    var checker=new TypeChecker();
    checker.check(source);
    eq(new Vm(60000000).runPlain(source),expected,label+' Haxe AST VM');
    eq(new BootRuntime(60000000).runPlain(source),expected,label+' Nail bootstrap JS/PHP');
  }

  public static function main():Void {
    var header='nail 0.60 ;\n';
    var people='type Person { name Text age Float } ;\n'
      +'type Pet { name Text age Int } ;\n';
    var generic='def getName data = data . name ;\n';
    var program=header+people+generic
      +'getName { name = " Daniele " , age = 19.0 } ;\n'
      +'getName { name = " Eleonora " } ;\n'
      +'getName ( Person " Mario " 46.0 ) ;\n'
      +'getName ( Pet " Rafiki " 3 ) ;\n';
    accepts(program,['Daniele','Eleonora','Mario','Rafiki'],
      'structural projection accepts anonymous and different nominal records');
    var checker=new TypeChecker();
    checker.check(header+people+generic);
    var signature=checker.signature('getName');
    ok(signature.indexOf('name:')>=0 && signature.indexOf(' | ')>=0
      && signature.indexOf('Person')<0,
      'unannotated field accessor has an open structural principal type: '+signature);

    var numbers=header+'def getName data = data . name ;\n'
      +'getName { name = 42 , age = 19.0 } ;\n';
    accepts(numbers,['I:42/1'],'field result can be Int, not forced to Text');

    var nominal=header+people
      +'def getName ( data : Person ) = data . name ;\n'
      +'getName ( Person " Daniele " 46.0 ) ;\n';
    accepts(nominal,['Daniele'],'nominal annotated argument works');
    var nominalChecker=new TypeChecker();
    nominalChecker.check(nominal);
    eq(nominalChecker.signature('getName'),'Person -> Text',
      'explicit Person annotation retains nominal function type');

    rejects(header+people
      +'def getName ( data : Person ) = data . name ;\n'
      +'getName { name = " Daniele " , age = 19.0 } ;\n',
      'cannot unify','anonymous record rejected by explicit Person constraint');
    rejects(header+people
      +'def getName ( data : Person ) = data . name ;\n'
      +'getName ( Pet " Rafiki " 3 ) ;\n',
      'cannot unify','distinct nominal types remain distinct');

    rejects(header+generic
      +'getName { age = 19.0 } ;\n',
      'missing structural record fields','structural projection requires name');
    rejects(header+'def getName ( data : Unknown ) = data . name ;\n',
      'unknown type','explicit unknown type rejected');
    rejects(header+'type Box a { value a } ;\n'
      +'def getValue ( data : Box ) = data . value ;\n',
      'generic record needs type arguments','generic annotation cannot lose type arguments');

    // An annotation applies only to its original outer binder, not a
    // nested same-named lambda that introduces a new structural record.
    accepts(header+people
      +'def nested ( data : Person ) = ( fun data -> data . name ) '
      +'{ name = " Local " , age = 1 } ;\n'
      +'nested ( Person " Outer " 46.0 ) ;\n',
      ['Local'],'shadowed inner data is not captured by nominal annotation');

    trace('Nail v0.60 structural / nominal projection: '+checks+' checks passed');
  }
}
