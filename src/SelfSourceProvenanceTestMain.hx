import haxe.Json;
import nail.BootRuntime;
import nail.Parser;
import nail.SourcePositions;
import nail.Vm;

/** The locations are computed in Nail, not by calling the host parser.
    Compare them to an independent offset/line/column reference on 3 targets. */
class SelfSourceProvenanceTestMain {
  static var assertions = 0;

  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'SELF SOURCE PROVENANCE: ' + label;
    assertions++;
  }

  static function field(value:Dynamic, key:String):Dynamic
    return Reflect.field(value, key);

  static function literal(value:String):String {
    var json = Json.stringify(value);
    // Nail quoted strings normalize raw whitespace. Encode spaces explicitly
    // so the source being tested is passed byte-for-byte to the self parser.
    var inner = json.substr(1, json.length - 2);
    return '" ' + StringTools.replace(inner, ' ', '\\u0020') + ' "';
  }

  static function command(name:String, source:String):String
    return name + ' ' + literal(source) + ' ;';

  static function verify(vm:Vm, source:String):Void {
    ok(vm.runPlain(command('id', source))[0] == source,
      'source argument preserved exactly');
    var tokens:Array<Dynamic> = cast vm.runPlain(command('tokenizeWithPositions', source))[0];
    var reference = SourcePositions.scan(source);
    ok(tokens.length == reference.length, 'token count in: ' + source);
    for (i in 0...tokens.length) {
      var positioned = tokens[i];
      ok(field(positioned, "$type") == 'LocatedToken', 'token record type');
      var span:Dynamic = field(positioned, 'tokenSpan');
      var expected = reference[i];
      ok(field(positioned, 'token') != null, 'original Syntax token present');
      ok(field(span, 'start') == expected.start && field(span, 'end') == expected.end,
        'token offset ' + i + ' source=' + Json.stringify(source) + ' expected='
          + expected.start + ':' + expected.end + ' actual='
          + Std.string(field(span, 'start')) + ':' + Std.string(field(span, 'end')));
      ok(field(span, 'line') == expected.line && field(span, 'column') == expected.column
        && field(span, 'endLine') == expected.endLine
        && field(span, 'endColumn') == expected.endColumn, 'token coordinates ' + i);
      var token:Dynamic = field(positioned, 'token');
      if (StringTools.startsWith(expected.text, '\u0001')) {
        ok(field(token, 'tag') == 'StringToken'
          && field(token, 'value') == expected.text.substr(1), 'string token value');
      } else {
        ok(field(token, 'tag') == 'Token'
          && field(token, 'value') == expected.text, 'ordinary token value');
      }
    }

    var program:Dynamic = vm.runPlain(command('parseSource', source))[0];
    var located:Array<Dynamic> = cast vm.runPlain(command('parseSourceWithPositions', source))[0];
    var forms:Array<Dynamic> = cast field(program, 'children');
    var parser = new Parser(source);
    var hostForms = parser.parseRaw();
    ok(located.length == forms.length && located.length == hostForms.length,
      'located form count');
    for (i in 0...located.length) {
      var entry = located[i];
      ok(field(entry, "$type") == 'LocatedForm', 'form record type');
      ok(Json.stringify(field(entry, 'tree')) == Json.stringify(forms[i]),
        'canonical self parser form unchanged');
      var actual = field(entry, 'formSpan');
      var expected = parser.provenance.spanOfForm(hostForms[i]);
      ok(expected != null, 'host source range exists');
      ok(field(actual, 'start') == expected.start && field(actual, 'end') == expected.end,
        'form offsets ' + i);
      ok(field(actual, 'line') == expected.line && field(actual, 'column') == expected.column
        && field(actual, 'endLine') == expected.endLine
        && field(actual, 'endColumn') == expected.endColumn, 'form coordinates ' + i);
    }
  }

  public static function main():Void {
    var vm = new Vm(30000000);
    vm.loadStdlib();
    var provenanceSource = haxe.Resource.getString('source_provenance');
    if (provenanceSource == null) throw 'Missing optional provenance library';
    vm.run(provenanceSource);

    for (source in [
      '',
      'def x = 7 ;',
      '  # first comment\n def x = 3 ;\n x + 2 ;',
      'def greet = " hello world " ; greet ;',
      'def f x = if x == 1 then 0 else x + 3 ;',
      'type Person { name Text age Number } ;\ndef p = Person " Ada " 37 ; p . age ;',
      'def seq = [ 3 , 5 , 8 ] ; # trailing\nseq ;',
      'def x = " quoted \\" phrase " ;',
      'def n = 4 ;\n\n# break\ndef square x = x * x ; square n ;',
      'macro identity x = quote ( unquote x ) ;\nexpand identity 17 ;'
    ]) verify(vm, source);

    var typedRecord = 'type Wrap { syntax Syntax } ; '
      + '( Wrap ( syntaxLeaf " Token " " x " ) ) . syntax ;';
    ok(Json.stringify(new nail.TypeChecker().check(typedRecord)) == '["Syntax"]',
      'Syntax can appear in nominal record fields');
    var typedSum = 'type Payload = Missing | Present Syntax ; '
      + 'Present ( syntaxLeaf " Token " " x " ) ;';
    ok(Json.stringify(new nail.TypeChecker().check(typedSum)) == '["Payload"]',
      'Syntax can appear in algebraic payloads');

    // The bytecode-only bootstrap executes the same Nail-created source map
    // without any source parser or host SourcePositions helper.
    var example = 'def x = 7 ; x ;';
    var boot = new BootRuntime(30000000);
    boot.runPlain(provenanceSource);
    ok(Json.stringify(boot.runPlain(command('tokenizeWithPositions', example)))
      == Json.stringify(vm.runPlain(command('tokenizeWithPositions', example))),
      'source-free runtime token parity');
    ok(Json.stringify(boot.runPlain(command('parseSourceWithPositions', example)))
      == Json.stringify(vm.runPlain(command('parseSourceWithPositions', example))),
      'source-free runtime form parity');
    trace('NailSeed v0.26 self-hosted source provenance: ' + assertions + ' passed');
  }
}
