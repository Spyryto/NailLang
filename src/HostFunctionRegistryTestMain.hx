import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.NType;
import nail.ResultValue;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;

class HostFunctionRegistryTestMain {
  static var checks=0;
  static function ok(pass:Bool,label:String):Void {
    if (!pass) throw 'HOST FUNCTION: '+label;
    checks++;
  }
  static function eq(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+' expected '+Json.stringify(expected)+' got '+Json.stringify(actual));
  static function fails(f:Void->Void,needle:String):Void {
    var message='';
    try f() catch(e:Dynamic) message=Std.string(e);
    ok(message.indexOf(needle)>=0,
      'expected "'+needle+'" got "'+message+'"');
  }

  static function greetType():NType
    return TFunction(TText,TSum('CoreResult',[TText,TText]));
  static function source():String
    return 'nail 0.51 ; def greet name = match greetHost name with '
      +'| Ok text -> text | Error why -> why ;';
  static function manifest():PublicSourceModuleSpec return {
    name:'Greeter',source:source(),
    imports:[{module:HostTextGrants.PROVIDER,symbol:'greet',
      alias:'greetHost',scheme:{
        term:greetType(),quantified:[],comparable:[]
      }}],
    exports:['greet']
  };

  public static function main():Void {
    var checker=new TypeChecker();
    eq(checker.signature('Ok'),'a -> CoreResult[a, b]',
      'Ok is a polymorphic alias');
    eq(checker.signature('Error'),'a -> CoreResult[b, a]',
      'Error is a polymorphic alias');
    eq(checker.check('nail 0.51 ; def identity x = match Ok x with '
      +'| Ok y -> y | Error e -> x ; identity " jazz " ;'),
      ['Text'],'short Result constructors are exhaustively checked');
    // A local alias is an ordinary Nail binding, not a new core variant.
    // The matcher still resolves the stable CoreResult constructor tag.
    eq(new BootRuntime(40000000).runPlain(
      'nail 0.51 ; let Ok = CoreOk in '
      +'match Ok " scoped " with | CoreOk x -> x | CoreErr e -> e ;'),
      ['scoped'],'a context-limited Ok binding constructs CoreResult');
    fails(() -> new TypeChecker().check('nail 0.51 ; '
      +'def f x = match Ok x with '
      +'| Ok a -> a | CoreOk b -> b | Error e -> x ;'),
      'duplicate constructor branch');

    var alias='nail 0.51 ; match CoreOk " fine " with '
      +'| Ok x -> x | CoreErr e -> e ;';
    var boot=new BootRuntime(40000000);
    ok(BootstrapImage.encode(BytecodeCompiler.compileSource(alias))
      ==BootstrapImage.encode(boot.compile(alias)),
      'Haxe and Nail compilers agree on mixed Result alias bytecode');
    eq(boot.runPlain(alias),['fine'],
      'source-free runtime matches short and historical constructors');
    eq(new Vm().runPlain('nail 0.51 ; match Error " unavailable " with '
      +'| Ok x -> x | Error e -> e ;'),['unavailable'],
      'Error is a source-level constructor, not a parser error');

    var image=ModuleImage.encode(ModuleLinker.compilePublic(manifest()));
    var grants=new HostTextGrants();
    var seen:Array<String>=[];
    grants.grantFunction('Greeter','greet',greetType(), args -> {
      return switch(args[0]) {
        case Text(name):
          seen.push(name);
          name=='bad' ? ResultValue.error(Text('unavailable'))
            : ResultValue.ok(Text('Ciao, '+name));
        case _: throw 'invalid host value';
      };
    },3);
    var linked=ModuleLinker.linkImages([image],40000000,grants);
    eq(Vm.toPlain(linked.invoke('Greeter','greet',Text('Nail'))),
      'Ciao, Nail','host function returns success');
    eq(Vm.toPlain(linked.invoke('Greeter','greet',Text('bad'))),
      'unavailable','host function returns error');
    fails(() -> linked.invoke('Greeter','greet',Boolean(true)),
      'invalid function argument');
    eq(seen,['Nail','bad'],'bad inputs never reach the callback');
    eq(Vm.toPlain(linked.invoke('Greeter','greet',Text('Last'))),
      'Ciao, Last','last permitted invocation works');
    fails(() -> linked.invoke('Greeter','greet',Text('Over')),
      'invocation quota exhausted');
    grants.revokeFunction('Greeter','greet');
    fails(() -> linked.invoke('Greeter','greet',Text('After')),
      'revoked function grant');

    fails(() -> ModuleLinker.linkImages([image],40000000,new HostTextGrants()),
      'missing function grant');
    var other=new HostTextGrants();
    other.grantFunction('Other','greet',greetType(),
      _ -> ResultValue.ok(Text('wrong')));
    fails(() -> ModuleLinker.linkImages([image],40000000,other),
      'missing function grant');
    var mismatched=new HostTextGrants();
    mismatched.grantFunction('Greeter','greet',TFunction(TText,TText),
      _ -> Text('wrong'));
    fails(() -> ModuleLinker.linkImages([image],40000000,mismatched),
      'capability type mismatch');

    var badResult=new HostTextGrants();
    badResult.grantFunction('Greeter','greet',greetType(),_ -> Boolean(true));
    fails(() -> ModuleLinker.linkImages([image],40000000,badResult)
      .invoke('Greeter','greet',Text('x')),'invalid function result');
    var exploding=new HostTextGrants();
    exploding.grantFunction('Greeter','greet',greetType(),_ -> {
      throw 'secret /private/token';
      return ResultValue.ok(Text('unreachable'));
    });
    var message='';
    try ModuleLinker.linkImages([image],40000000,exploding)
      .invoke('Greeter','greet',Text('x'))
    catch(e:Dynamic) message=Std.string(e);
    ok(message.indexOf('host callback failed')>=0
      && message.indexOf('private')<0,'host exceptions are sanitized');


    // Curried callbacks receive arguments as one typed array, but Nail
    // observes an ordinary first-class partially applicable function.
    var joinType=NType.TFunction(NType.TText,
      NType.TFunction(NType.TText,NType.TText));
    var partial:PublicSourceModuleSpec={
      name:'Curried',
      source:'nail 0.51 ; def captured = hostJoin " pre " ; '
        +'def append suffix = captured suffix ;',
      imports:[{module:HostTextGrants.PROVIDER,symbol:'combine',
        alias:'hostJoin',scheme:{
          term:joinType,quantified:[],comparable:[]
        }}],
      exports:['append']
    };
    var joint=new HostTextGrants();
    joint.grantFunction('Curried','combine',joinType,values -> {
      return switch([values[0],values[1]]) {
        case [Text(a),Text(b)]: Text(a+b);
        case _: throw 'host argument type violation';
      };
    });
    var partialImage=ModuleImage.encode(ModuleLinker.compilePublic(partial));
    var partialLinked=ModuleLinker.linkImages([partialImage],40000000,joint);
    eq(Vm.toPlain(partialLinked.invoke('Curried','append',Text('fix'))),
      'prefix','curried host functions can be partially applied');
    joint.revokeFunction('Curried','combine');
    fails(() -> partialLinked.invoke('Curried','append',Text('later')),
      'revoked function grant');

    var reserved=new HostTextGrants();
    fails(() -> reserved.grantFunction('Greeter','readText',greetType(),
      _ -> ResultValue.ok(Text('wrong'))),'invalid function grant');
    fails(() -> reserved.grantFunction('Greeter','broken',TText,
      _ -> Text('wrong')),'unsupported function result type');
    fails(() -> reserved.grantFunction('Greeter','greet',greetType(),
      _ -> Text('wrong'),0),'invalid function grant');

    trace('NailLang v0.51 host registry: '+checks+' checks passed');
  }
}
