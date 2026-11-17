import haxe.Json;
import nail.SourceAnalysis;
import nail.SourceAnalysis.AnalysisResult;
import nail.SourceAnalysis.AnalysisSymbol;
import nail.SourceAnalysis.AnalysisReference;

/** 0.50 analysis is a tool-agnostic, read-only query of one source snapshot.
    The same structured result must work on Haxe, Node and PHP without LSP. */
class SourceAnalysisTestMain {
  static var checks = 0;

  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'SOURCE ANALYSIS: ' + label;
    checks++;
  }

  static function has(text:String, needle:String):Bool
    return text.indexOf(needle) >= 0;

  static function symbol(result:AnalysisResult, name:String,
      kind:String):AnalysisSymbol {
    for (entry in result.symbols)
      if (entry.name == name && entry.kind == kind) return entry;
    throw 'Missing analysis symbol: ' + kind + ' ' + name;
  }

  static function reference(result:AnalysisResult, name:String,
      from:Int):AnalysisReference {
    for (entry in result.references)
      if (entry.name == name && entry.span.start == from) return entry;
    throw 'Missing source reference at ' + from + ': ' + name;
  }

  public static function main():Void {
    var source = 'nail 0.49 ;\n'
      + 'def answer = 41 ;\n'
      + 'def choose x = x ;\n'
      + 'choose answer ;';
    var result = SourceAnalysis.analyze(source);
    ok(result.ok && result.diagnostics.length == 0,
      'valid source has no diagnostics');
    ok(result.version == '0.49', 'explicit version retained');
    ok(result.evaluations.length == 1 && result.evaluations[0].type == 'Int',
      'static type of last expression');
    ok(result.evaluations[0].span != null &&
      result.evaluations[0].span.line == 4,
      'evaluation carries original form location');

    var answer = symbol(result, 'answer', 'definition');
    var choose = symbol(result, 'choose', 'definition');
    var x = symbol(result, 'x', 'parameter');
    ok(answer.id != choose.id && x.id != choose.id,
      'stable distinct binding identities');
    ok(answer.span != null && answer.span.line == 2 &&
      answer.span.column == 5, 'definition name token is pinpointed');
    ok(x.span != null && x.span.line == 3 &&
      x.span.column == 12, 'parameter name token is pinpointed');
    ok(answer.signature == 'Int', 'inferred definition signature');
    ok(choose.signature == 'a -> a', 'polymorphic signature');

    var local = reference(result, 'x', source.indexOf('= x ;') + 2);
    ok(local.targetId == x.id, 'parameter reference resolves locally');
    var useChoose = reference(result, 'choose', source.lastIndexOf('choose'));
    var useAnswer = reference(result, 'answer', source.lastIndexOf('answer'));
    ok(useChoose.targetId == choose.id && useAnswer.targetId == answer.id,
      'top-level references resolve by identity');
    ok(result.references.length >= 3 &&
      result.references[0].span.start < result.references[1].span.start,
      'references are ordered by source location');

    var current = SourceAnalysis.analyze(
      'nail 0.50 ; Scale : Int Int ; def square x : Scale = x * x ; square 4 ;');
    ok(current.ok && current.version == '0.50' &&
      current.evaluations.length == 1 &&
      current.evaluations[0].type == 'Int',
      'v0.50 supports v0.49 n-ary relation definitions and analysis: '
        + Json.stringify(current));

    var again = SourceAnalysis.analyze(source);
    ok(Json.stringify(again) == Json.stringify(result),
      'analysis is deterministic and has no persistent state');

    var typeFail = SourceAnalysis.analyze('nail 0.49 ;\ndef broken = unknown ;');
    ok(!typeFail.ok && typeFail.diagnostics.length == 1,
      'type errors return structured diagnostics');
    ok(typeFail.diagnostics[0].phase == 'type' &&
      has(typeFail.diagnostics[0].message, 'unknown'),
      'type error remains actionable');
    ok(typeFail.diagnostics[0].span != null &&
      typeFail.diagnostics[0].span.line == 2,
      'type failures point at the actual enclosing form');
    ok(typeFail.symbols.length == 1 &&
      typeFail.symbols[0].signature == null,
      'symbols remain queryable on type failure without invented types');

    var badSyntax = 'nail 0.49 ;\ndef broken = 3';
    var syntaxFail = SourceAnalysis.analyze(badSyntax);
    ok(!syntaxFail.ok && syntaxFail.diagnostics.length == 1 &&
      syntaxFail.diagnostics[0].phase == 'parse',
      'parse errors are distinct from type errors');
    ok(syntaxFail.diagnostics[0].span != null &&
      syntaxFail.diagnostics[0].span.start == badSyntax.length &&
      syntaxFail.diagnostics[0].span.end == badSyntax.length,
      'missing final semicolon is a zero-width insertion at EOF');

    var unsupported = SourceAnalysis.analyze('nail 0.54 ; 1 ;');
    ok(!unsupported.ok &&
      unsupported.diagnostics[0].phase == 'parse' &&
      unsupported.diagnostics[0].span != null &&
      unsupported.diagnostics[0].span.start == 5,
      'unsupported language version points to its header');

    var macroResult = SourceAnalysis.analyze(
      'nail 0.49 ; macro next x = quote ( unquote x + 1 ) ;\nexpand next 41 ;');
    ok(macroResult.ok && macroResult.evaluations.length == 1 &&
      macroResult.evaluations[0].type == 'Int',
      'macro-generated source receives inferred type');
    ok(macroResult.evaluations[0].span != null &&
      macroResult.evaluations[0].span.line == 2,
      'macro call site provenance is preserved');

    var reads = 0;
    var resolver = (name:String) -> {
      if (name != 'numbers') return null;
      reads++;
      return 'nail 0.49 ; macro next x = quote ( unquote x + 1 ) ; export next ;';
    };
    var imported = SourceAnalysis.analyze(
      'nail 0.49 ; import next from numbers ; expand next 41 ;', resolver);
    ok(imported.ok && imported.evaluations.length == 1 &&
      imported.evaluations[0].type == 'Int',
      'macro import has a checked analysis');
    ok(reads == 1, 'analysis does not parse or fetch macro modules twice');

    var invalidImport = SourceAnalysis.analyze(
      'nail 0.49 ; import next from numbers ; expand next 41 ;',
      name -> name == 'numbers'
        ? 'macro next x = quote ( unquote x + 1 ) ; export next ;' : null);
    ok(!invalidImport.ok &&
      invalidImport.diagnostics[0].phase == 'parse' &&
      has(invalidImport.diagnostics[0].message, 'expected 0.49'),
      'import version error remains structured without a fictitious span');

    trace('NailLang source analysis: ' + checks + ' checks passed');
  }
}
