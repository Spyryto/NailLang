import haxe.Json;
import nail.BootRuntime;
import nail.ResultValue;
import nail.Value;
import nail.TypeChecker;

/** End-to-end differential tests for the first Nail-written HM checker.
    The Nail checker is invoked via the source-free bytecode VM; it has no
    Haxe type-checker callback or privileged type primitive. */
class NailTypecheckerProbeTestMain {
  static var checks:Int=0;
  static function eq(a:Dynamic,b:Dynamic,label:String):Void {
    if (Json.stringify(a)!=Json.stringify(b))
      throw 'NAIL TYPECHECKER: '+label+' expected '+Json.stringify(b)+' got '+Json.stringify(a);
    checks++;
  }

  static function inspect(boot:BootRuntime,source:String):{ok:Bool,types:Array<String>,message:String} {
    var result=boot.invoke('tcCheckSource',Text(source));
    var tag=ResultValue.tag(result);
    if(tag==ResultValue.ERR)
      return switch(ResultValue.get(result,ResultValue.ERR)) {
        case Text(message): {ok:false,types:[],message:message};
        case _: throw 'Checker Error must contain Text';
      };
    var checked=ResultValue.get(result,ResultValue.OK);
    var values:Array<String>=[];
    switch(checked) {
      case SyntaxNode('TCChecked',Cons(_, _)) | SyntaxNode('TCChecked',Nil):
        var remaining:Value=switch(checked) {
          case SyntaxNode(_, xs): xs;
          case _: Nil;
        };
        while(true) switch(remaining) {
          case Nil: break;
          case Cons(item,tail):
            var shown=boot.invoke('tcPretty',item);
            switch shown {
              case Text(label): values.push(label);
              case _: throw 'tcPretty must return Text';
            }
            remaining=tail;
          case _: throw 'Checker returned invalid result list';
        }
      case _: throw 'Checker Ok must contain TCChecked';
    }
    return {ok:true,types:values,message:''};
  }

  static function checkGood(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,true,'expected checker success: '+body+' ('+found.message+')');
    eq(found.types,expected,'Nail result types: '+body);
    eq(new TypeChecker().check(source),expected,'Haxe parity: '+body);
  }

  static function checkBad(boot:BootRuntime,body:String,part:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'expected Nail rejection: '+body);
    if(found.message.indexOf(part)<0)
      throw 'NAIL TYPECHECKER: expected diagnostic '+part+', got '+found.message;
    checks++;
    var rejected=false;
    try new TypeChecker().check(source)
    catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must also reject '+body);
  }

  static function main():Void {
    var boot=new BootRuntime(60000000);
    checkGood(boot,'42 ;',['Int']);
    checkGood(boot,'true ;',['Bool']);
    checkGood(boot,'" Ciao " ;',['Text']);
    checkGood(boot,'if true then 1 else 2 ;',['Int']);
    checkGood(boot,'( fun x -> x ) 42 ;',['Int']);
    checkGood(boot,'def id x = x ; id 7 ; id true ;',['Int','Bool']);
    checkGood(boot,'let id = fun x -> x in id " Hello " ;',['Text']);
    checkGood(boot,'def f x = if x then f false else true ; f true ;',['Bool']);
    checkGood(boot,'textConcat " A " " B " ;',['Text']);
    checkGood(boot,'7 + 5 ;',['Int']);

    checkBad(boot,'unknownVar ;','Unknown name');
    checkBad(boot,'1 2 ;','Type mismatch');
    checkBad(boot,'if 1 then true else false ;','Type mismatch');
    checkBad(boot,'if true then 1 else false ;','Type mismatch');
    checkBad(boot,'fun x -> x x ;','Recursive type');
    trace('Nail-written typechecker core: '+checks+' differential checks passed');
  }
}
