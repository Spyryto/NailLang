import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.TypeChecker;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.SyntaxEncoder;
import nail.Vm;

/** Experimental parser/typechecker study, deliberately not user-visible in
    ordinary Nail 0.54 compilation. No sixth core AST case or VM opcode.
    Known checked field names are supplied to Parser by the caller. */
class ContextBlockProbeTestMain {
  static var passed=0;
  static function ok(value:Bool, message:String):Void {
    if (!value) throw 'CONTEXT BLOCK PROBE: '+message;
    passed++;
  }
  static function equal(a:Dynamic,b:Dynamic,label:String):Void
    ok(Json.stringify(a)==Json.stringify(b),
      label+' expected '+Json.stringify(b)+' got '+Json.stringify(a));
  static function fails(f:Void->Void,needle:String,?label:String):Void {
    var error='';
    try f() catch(e:Dynamic) error=Std.string(e);
    ok(error.indexOf(needle)>=0,
      (label==null?'':label+': ')+'expected "'+needle+'" got "'+error+'"');
  }
  static function contexts():StringMap<Array<String>> {
    var result=new StringMap<Array<String>>();
    result.set('Html',['h2','div']);
    result.set('Svg',['circle','div']);
    result.set('html',['h2','div']);
    return result;
  }
  static function types(source:String,ctx:StringMap<Array<String>>):Array<String> {
    var forms=new Parser(source,ctx).parse();
    var checker=new TypeChecker();
    return checker.checkSyntax(SyntaxEncoder.program(forms));
  }
  static function run(source:String,ctx:StringMap<Array<String>>):Array<Dynamic> {
    var forms=new Parser(source,ctx).parse();
    return new ByteVm(15000000).runPlain(BytecodeCompiler.compile(forms));
  }
  static var setup='def Html = { '
      +'h2 = fun x -> textConcat " H: " x , '
      +'div = fun x -> textConcat " D: " x '
      +'} ; ';
  static var svg='def Svg = { '
      +'circle = fun x -> textConcat " C: " x , '
      +'div = fun x -> textConcat " S: " x '
      +'} ; ';

  public static function main():Void {
    var ctx=contexts();
    var simple=setup
      +'def view title text = Html { [ h2 title , div text ] } ; '
      +'view " One " " Two " ;';
    equal(types(simple,ctx),['[Text]'],
      'record of closures opens as a lexical typed context');
    equal(run(simple,ctx),[['H:One','D:Two']],
      'same lowered five-constructor AST executes in original VM');
    fails(() -> new Parser(simple).parse(),'Expected named record field',
      'feature must remain opt-in for the source parser');

    var nested=setup+svg
      +'Html { [ h2 " First " , Svg { div ( circle " Inner " ) } ] } ;';
    equal(types(nested,ctx),['[Text]'],
      'inner and outer contexts retain ordinary lexical types');
    equal(run(nested,ctx),[['H:First','S:C:Inner']],
      'inner context shadows an outer field with the same name');

    var global='def h2 x = textConcat " Global: " x ; '+setup
      +'Html { h2 " Selected " } ;';
    equal(run(global,ctx),['H:Selected'],
      'context field shadows a global binding');
    var local=setup
      +'Html { let h2 = fun x -> textConcat " Local: " x in h2 " Selected " } ;';
    equal(run(local,ctx),['Local:Selected'],
      'explicit local binding inside block shadows its context');

    var record=setup
      +'type Person { name Text } ; '
      +'Html { ( Person { name = h2 " N " } ) . name } ;';
    equal(types(record,ctx),['Text'],
      'nested named record construction retains distinct grammar');
    equal(run(record,ctx),['H:N'],
      'record constructor and context expression coexist');
    var anonymous=setup
      +'Html { ( { value = div " A " } ) . value } ;';
    equal(types(anonymous,ctx),['Text'],
      'anonymous record construction retains distinct grammar');
    equal(run(anonymous,ctx),['D:A'],
      'anonymous record field can use contextual names');

    var macroCase=setup
      +'macro identity x = quote ( unquote x ) ; '
      +'Html { expand identity ( h2 " M " ) } ;';
    equal(run(macroCase,ctx),['H:M'],
      'macro expansion works after contextual lowering to core AST');

    // The same context value can travel through a function parameter at
    // runtime, but closed structural HM cannot infer a free parameter row.
    var param=setup
      +'def display html title = html { h2 title } ; '
      +'display Html " Dynamic " ;';
    equal(run(param,ctx),['H:Dynamic'],
      'runtime record parameter is already executable without new VM opcodes');
    fails(() -> types(param,ctx),'unknown record field h2',
      'the type checker cannot infer an open structural row yet');

    // The parser chooses by the tokens after '{', never by a type lookup.
    var disambiguated='type Html { h2 Text } ; '
      +'def constructed = Html { h2 = " Named " } ; '
      +'constructed . h2 ;';
    equal(run(disambiguated,ctx),['Named'],
      'Name { field = value } still means named constructor');
    equal(types(disambiguated,ctx),['Text'],
      'the constructor type is verified normally');

    // Lowercase f { field = expr } is already ordinary application to an
    // anonymous record. The contextual syntax must not hijack that form.
    var applied='def html options = if options == { value = " Applied " } '
      +'then " Applied " else " Missing " ; '
      +'html { value = " Applied " } ;';
    equal(run(applied,ctx),['Applied'],
      'lowercase function application to a structural record is preserved');
    equal(types(applied,ctx),['Text'],
      'record argument grammar is selected without any type lookup');

    var bad=contexts();
    bad.set('Html',['h2','h2']);
    fails(() -> new Parser(simple,bad).parse(),
      'invalid or duplicate field h2','reject malformed context interface');
    var missing=contexts();
    missing.set('Html',['h2','missing']);
    fails(() -> types(simple,missing),
      'structural record has no field missing',
      'interface must agree with actual record fields');
    fails(() -> new Parser(setup+'Html { [ h2 " X " ] ;',ctx).parse(),
      'Expected }','missing context terminator is reported');

    trace('NailLang context block parser experiment: '+passed
      +' checks passed (opt-in; dynamic parameter type inference deferred)');
  }
}
