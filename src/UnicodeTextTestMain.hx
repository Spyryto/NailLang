import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.Parser;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.TypeChecker;
import nail.UnicodeText;
import nail.Value;
import nail.Vm;

/** Portable codepoint semantics: never confuse graphemes with scalars. */
class UnicodeTextTestMain {
  static var passed = 0;
  static function ok(condition:Bool, description:String):Void {
    if (!condition) throw 'UNICODE TEXT: ' + description;
    passed++;
  }
  static function fails(task:Void->Void, expected:String):Void {
    var message = '';
    try task() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(expected) >= 0, 'expected ' + expected + ', got ' + message);
  }
  static function same(source:String, expected:String):Void {
    // PHP's JSON encoder may use \\u escapes while JS/eval use literal
    // Unicode. Compare canonically serialized parsed values instead.
    expected = Json.stringify(Json.parse(expected));
    var reference = BytecodeCompiler.compileSource(source);
    var host = new Vm(60000000);
    host.loadStdlib();
    var parsed = host.parseWithNail(source);
    var selfCode = host.compileWithNail(source);
    var image = BootstrapImage.encode(reference);
    ok(image == BootstrapImage.encode(selfCode), 'Haxe/Nail bytecode parity');
    ok(image == BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(parsed))),
      'Nail parser bytecode parity');
    ok(image == BootstrapImage.encode(BytecodeCompiler.compile(
      SyntaxBridge.forms(SyntaxEncoder.program(new Parser(source).parse())))),
      'host Syntax bridge roundtrip');
    ok(Json.stringify(new Vm(60000000).runPlain(source)) == expected, 'AST runtime');
    ok(Json.stringify(new ByteVm(60000000).runPlain(reference)) == expected,
      'bytecode runtime');
    ok(Json.stringify(host.runPlainWithNail(source)) == expected, 'Nail AST runtime');
    ok(Json.stringify(new BootRuntime(60000000).runPlain(source)) == expected,
      'source-free compiler');
    ok(image == BootstrapImage.encode(BootstrapImage.decode(image)),
      'Unicode bytecode image roundtrip');
  }
  public static function main():Void {
    var s = 'Aé🪕漢';
    ok(UnicodeText.length(s) == 4, 'portable count across 1-4 byte characters');
    ok(UnicodeText.at(s,0) == 'A', 'ASCII character');
    ok(UnicodeText.at(s,1) == 'é', 'BMP accented scalar');
    ok(UnicodeText.at(s,2) == '🪕', 'non-BMP scalar');
    ok(UnicodeText.at(s,3) == '漢', 'CJK scalar');
    ok(UnicodeText.length('') == 0, 'empty source');
    ok(UnicodeText.length('é') == 2, 'combining mark is separate codepoint');
    ok(UnicodeText.length('👩‍💻') == 3, 'ZWJ emoji contains three scalars');
    ok(UnicodeText.length('café') == 4, 'accented letter counts once');
    ok(UnicodeText.length(s) == 4, 'repeat query keeps counts stable');

    same('def word = " Aé🪕漢 " ; textLength word ; '
      + 'textAt word 0 ; textAt word 1 ; textAt word 2 ; textAt word 3 ;',
      '[4,"A","é","🪕","漢"]');
    same('def combined = textConcat " café " " 🦊 " ; '
      + 'textLength combined ; textAt combined 4 ; combined ;',
      '[5,"🦊","café🦊"]');
    same('textLength " 👩‍💻 " ; textAt " 👩‍💻 " 0 ; '
      + 'textAt " 👩‍💻 " 1 ; textAt " 👩‍💻 " 2 ;',
      '[3,"👩","‍","💻"]');
    same('textLength " " ; textLength " こんにちは " ; '
      + 'textAt " こんにちは " 4 ;',
      '[0,5,"は"]');
    same('# nail: 0.29\ntextLengthExact " 🪕é " ; '
      + 'textAtExact " 🪕é " 0 ; textAtExact " 🪕é " 1 ;',
      '["E:2/1","🪕","é"]');

    fails(() -> new Vm().runPlain('textAt " 🪕 " 1 ;'), 'Text index out of range');
    fails(() -> new Vm().runPlain('textAt " 🪕 " -1 ;'), 'Text index out of range');
    fails(() -> new Vm().runPlain('textAt " 🪕 " 0.5 ;'), 'Text index out of range');
    fails(() -> new Vm().runPlain('# nail: 0.29\ntextAtExact " 🪕 " 1 ;'), 'index');
    ok(Json.stringify(new TypeChecker().check(
      'def first x = textAt x 0 ; first " 🪕 " ;')) == '["Text"]',
      'Unicode preserves HM Text type');
    ok(Json.stringify(new TypeChecker().check(
      '# nail: 0.29\ntextLengthExact " 🪕 " ;')) == '["Exact"]',
      'Exact Unicode length remains exact numeric type');

    var providerSource = 'def initial x = textAt x 0 ;';
    var tc = new TypeChecker();
    tc.check(providerSource);
    var provider:PublicSourceModuleSpec = {
      name:'Strings',source:providerSource,imports:[],exports:['initial']
    };
    var client:PublicSourceModuleSpec = {
      name:'UseStrings',source:'def firstEmoji x = importedInitial x ;',
      imports:[{module:'Strings',symbol:'initial',alias:'importedInitial',
        scheme:tc.publicScheme('initial')}],exports:['firstEmoji']
    };
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compilePublic(client)),
      ModuleImage.encode(ModuleLinker.compilePublic(provider))
    ]);
    ok(Vm.toPlain(linked.invoke('UseStrings','firstEmoji',Text('🪕é'))) == '🪕',
      'separately linked module respects Unicode index');
    var many = [for (_ in 0...4096) 'a'].join('') + '🪕';
    ok(UnicodeText.length(many) == 4097, 'long ASCII prefix counted consistently');
    ok(UnicodeText.at(many,4096) == '🪕',
      'correct last scalar after 4096 ASCII characters');
    trace('NailSeed v0.37 Unicode text: ' + passed + ' checks passed');
  }
}
