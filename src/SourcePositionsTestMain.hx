import nail.Parser;
import nail.SourcePositions;
import nail.SyntaxEncoder;
import nail.BootstrapImage;
import nail.BindingAnalysis;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

class SourcePositionsTestMain {
  static var checks = 0;
  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'SOURCE POSITIONS: ' + label;
    checks++;
  }
  static function verify(source:String):Void {
    var parser = new Parser(source);
    var tokens = parser.tokenPositions;
    ok(tokens.length == SourcePositions.texts(source).length, 'token count');
    for (i in 0...tokens.length) {
      var t = tokens[i];
      ok(t.text == SourcePositions.texts(source)[i], 'token content');
      ok(t.start >= 0 && t.end <= source.length && t.start < t.end, 'offset bounds');
      var prefix = source.substr(0, t.start);
      var lines = prefix.split('\n');
      ok(t.line == lines.length && t.column == lines[lines.length - 1].length + 1, 'line and column');
    }
    // The parser still accepts the original source and emits ordinary AST.
    var forms = parser.parse();
    ok(BootstrapImage.encode(SyntaxEncoder.program(forms))
      == BootstrapImage.encode(SyntaxEncoder.program(new Parser(source).parse())), 'AST stability');
  }
  public static function main():Void {
    verify('');
    verify('def x = 7 ;');
    verify('  # comment\n type Person { name Text age Number } ;\n');
    verify('def p = Person " Ada Lovelace " 32 ;\np . name ;');
    verify('def x = 1 ; # trailing comment\ndef y = 2 ;');
    var tokens = SourcePositions.scan('  a\n  b ;');
    ok(tokens[0].start == 2 && tokens[0].line == 1 && tokens[0].column == 3, 'first position');
    ok(tokens[1].start == 6 && tokens[1].line == 2 && tokens[1].column == 3, 'second position');
    var quoted = SourcePositions.scan(' " hello world " ;');
    ok(quoted[0].start == 1 && quoted[0].end == 16, 'quoted span');
    var sample = 'def value = 1 ;\\ndef take value = fun other -> value + other ;\\ntake value 2 ;'.split('\\n').join('\n');
    var parser = new Parser(sample);
    var forms = parser.parseRaw();
    var provenance = parser.provenance;
    var firstSpan = provenance.spanOfForm(forms[0]);
    ok(firstSpan != null && firstSpan.start == 0
      && firstSpan.end == sample.indexOf(';') + 1, 'definition form span');
    var secondSpan = provenance.spanOfForm(forms[1]);
    ok(secondSpan != null && secondSpan.line == 2 && secondSpan.column == 1,
      'multiline form span');

    var analysis = BindingAnalysis.resolve(forms, provenance);
    var globalValue = analysis.bindingForDefinition(forms[0]);
    var take = analysis.bindingForDefinition(forms[1]);
    ok(globalValue != null && take != null && globalValue.id != take.id,
      'unique definition identities');

    var outer:Expr = switch (forms[1]) {
      case Define(_, body): body;
      case _: throw 'expected definition';
    };
    var localValue = analysis.bindingForParameter(outer);
    var inner = switch (outer) {
      case Lambda(_, body): body;
      case _: throw 'expected first parameter';
    };
    var localOther = analysis.bindingForParameter(inner);
    var plusBody = switch (inner) {
      case Lambda(_, body): body;
      case _: throw 'expected second parameter';
    };
    var shadowReference = switch (plusBody) {
      case Apply(Apply(_, variable), _): variable;
      case _: throw 'expected addition';
    };
    var otherReference = switch (plusBody) {
      case Apply(_, variable): variable;
      case _: throw 'expected addition argument';
    };
    ok(localValue != null && localOther != null && localValue.id != localOther.id,
      'distinct parameter identities');
    ok(analysis.bindingForVariable(shadowReference) == localValue,
      'parameter shadows outer global');
    ok(analysis.bindingForVariable(otherReference) == localOther,
      'second parameter resolved');
    ok(provenance.spanOfExpression(outer) != null
      && provenance.spanOfExpression(inner) != null, 'lambda spans');

    var call = switch (forms[2]) {
      case Evaluate(expr): expr;
      case _: throw 'expected evaluation';
    };
    var callName = switch (call) {
      case Apply(Apply(fn, _), _): fn;
      case _: throw 'expected application';
    };
    var globalArg = switch (call) {
      case Apply(Apply(_, argument), _): argument;
      case _: throw 'expected argument';
    };
    ok(analysis.bindingForVariable(callName) == take, 'top-level call resolved');
    ok(analysis.bindingForVariable(globalArg) == globalValue,
      'top-level argument not captured by parameter');

    var recursiveParser = new Parser('def loop x = loop x ;');
    var recursiveForms = recursiveParser.parseRaw();
    var recursive = BindingAnalysis.resolve(recursiveForms, recursiveParser.provenance);
    var recursiveBody = switch (recursiveForms[0]) {
      case Define(_, Lambda(_, body)): body;
      case _: throw 'expected recursive lambda';
    };
    var selfRef = switch (recursiveBody) {
      case Apply(fn, _): fn;
      case _: throw 'expected recursive call';
    };
    ok(recursive.bindingForVariable(selfRef) == recursive.bindingForDefinition(recursiveForms[0]),
      'self-recursive definition');

    var macroSource = 'macro identity x = quote ( unquote x ) ;\\nexpand identity 17 ;'.split('\\n').join('\n');
    var macroParser = new Parser(macroSource);
    var macroForms = macroParser.parse();
    ok(macroForms.length == 1, 'macro declaration removed');
    var macroSpan = macroParser.provenance.spanOfForm(macroForms[0]);
    ok(macroSpan != null && macroSpan.line == 2, 'macro-expanded form keeps call-site line');
    var expandedExpression = switch (macroForms[0]) {
      case Evaluate(expr): expr;
      case _: throw 'expected macro evaluation';
    };
    var expandedSpan = macroParser.provenance.spanOfExpression(expandedExpression);
    ok(expandedSpan != null && expandedSpan.start == macroSource.indexOf('17'),
      'macro argument keeps original source span');
    var expansionSite = macroParser.provenance.expansionSiteOfExpression(expandedExpression);
    ok(expansionSite != null && expansionSite.start == macroSource.indexOf('expand'),
      'macro expansion keeps separate call-site span');

    var hygieneForms:Array<Form> = [
      Define('value', Literal(Number(8))),
      Evaluate(Apply(Lambda('value', Var('#macro_global_value')), Literal(Number(9))))
    ];
    var hygiene = BindingAnalysis.resolve(hygieneForms);
    var hygienicRef = switch (hygieneForms[1]) {
      case Evaluate(Apply(Lambda(_, v), _)): v;
      case _: throw 'expected hygienic marker';
    };
    ok(hygiene.bindingForVariable(hygienicRef) == hygiene.bindingForDefinition(hygieneForms[0]),
      'macro global reference bypasses local scope');

    trace('Source position tests: ' + checks + ' passed');
  }
}
