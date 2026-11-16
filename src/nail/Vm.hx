package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Explicit evaluator continuations: no recursive host calls for Nail function
    application, including mutually recursive and non-tail source functions. */
private enum EvalFrame {
  NeedArgument(argument:Expr, scope:Env);
  ApplyFunction(fn:Value);
  ChooseBranch(yes:Expr, no:Expr, scope:Env);
}

/** Small, pure Nail evaluator. No JS / PHP target branches. */
class Vm {
  final root:Env;
  final maxSteps:Int;
  var steps:Int = 0;

  public function new(maxSteps:Int = 100000) {
    if (maxSteps <= 0) throw 'maxSteps must be positive';
    this.maxSteps = maxSteps;
    root = new Env();
    for (name in ['+', '-', '*', '/', '<', '<=', '>', '>=', '==', '!=', 'cons', '#cons', '#recordGet', 'textAt', 'textConcat', 'syntaxLeaf', 'syntaxNode'])
      root.bind(name, Native(name, 2, []));
    for (name in ['head', 'tail', 'isEmpty', '#head', '#tail', '#isEmpty', 'textLength', 'syntaxTag', 'syntaxText', 'syntaxChildren']) root.bind(name, Native(name, 1, []));
    // Result is a single shared generic algebraic type, not a source-provided
    // module type. Match lowering needs constructors, predicates and getters.
    for (name in ['CoreOk', 'CoreErr', 'CoreOk?', 'CoreErr?',
        'CoreOk.0', 'CoreErr.0'])
      root.bind(name, Native(name, 1, []));
    root.bind('vector', Native('vector', 1, []));
    root.bind('vectorLength', Native('vectorLength', 1, []));
    root.bind('vectorGet', Native('vectorGet', 2, []));
    root.bind('vectorSet', Native('vectorSet', 3, []));
    root.bind('#recordMake', Native('#recordMake', 3, []));
    root.bind('macroExpandSyntax', Native('macroExpandSyntax', 1, []));
    root.bind('#sumFail', Native('#sumFail', 1, []));
    root.bind('nil', Nil);
    for (name in ['+', '-', '*', '/', '<', '<=', '>', '>='])
      root.bind('#exact' + name, Native('#exact' + name, 2, []));
    root.bind('#exactEncode', Native('#exactEncode', 1, []));
    root.bind('exactEncode', Native('exactEncode', 1, []));
    for (name in ['exactFloor', 'exactCeil', 'exactTruncate',
        'exactRoundEven', 'exactIsInteger'])
      root.bind(name, Native(name, 1, []));
    for (name in ['textLengthExact', 'vectorLengthExact', 'exactFromText', 'exactToFloat'])
      root.bind(name, Native(name, 1, []));
    for (name in ['textAtExact', 'vectorGetExact'])
      root.bind(name, Native(name, 2, []));
    root.bind('vectorSetExact', Native('vectorSetExact', 3, []));
  }

  inline function tick():Void {
    steps++;
    if (steps > maxSteps) throw 'Execution budget exceeded';
  }

  static function number(v:Value):Float {
    return switch (v) {
      case Number(n): if (!Math.isFinite(n)) throw 'Expected finite number' else n;
      case _: throw 'Expected finite number';
    };
  }

  static function exact(v:Value):numeric.FastNumber.FastValue return switch (v) {
    case ExactNumber(n): n;
    case _: throw 'Expected exact number; explicit conversion required';
  };

  static function exactArithmetic(op:String, a:Value, b:Value):Value
    return ExactNumber(numeric.FastNumber.arithmetic(op, exact(a), exact(b)));

  static function exactCompare(op:String, a:Value, b:Value):Value {
    var compared = numeric.FastNumber.compare(exact(a), exact(b));
    return Boolean(switch (op) {
      case '<': compared < 0;
      case '<=': compared <= 0;
      case '>': compared > 0;
      case '>=': compared >= 0;
      case _: throw 'Unknown exact comparison';
    });
  }

  static function bool(v:Value):Bool {
    return switch (v) {
      case Boolean(b): b;
      case _: throw 'Expected boolean';
    };
  }

  static function text(v:Value):String {
    return switch (v) {
      case Text(s): s;
      case _: throw 'Expected text';
    };
  }

  static function index(v:Value, size:Int):Int {
    switch (v) {
      case ExactNumber(x): return numeric.FastNumber.index(x, size);
      case _:
    }
    var n = number(v);
    if (n < 0 || n >= size || n != Math.floor(n)) throw 'Text index out of range';
    return Std.int(n);
  }

  static function finite(n:Float):Value {
    if (!Math.isFinite(n)) throw 'Nonfinite arithmetic result';
    return Number(n);
  }

  static function equal(a:Value, b:Value):Bool {
    return switch ([a, b]) {
      case [Number(x), Number(y)]: x == y;
      case [ExactNumber(x), ExactNumber(y)]: numeric.FastNumber.equal(x, y);
      case [ExactNumber(_), Number(_)] | [Number(_), ExactNumber(_)]:
        throw 'Cannot compare exact and approximate numbers implicitly';
      case [Boolean(x), Boolean(y)]: x == y;
      case [Text(x), Text(y)]: x == y;
      case [SyntaxLeaf(tx, x), SyntaxLeaf(ty, y)]: tx == ty && x == y;
      case [SyntaxNode(tx, xs), SyntaxNode(ty, ys)]: tx == ty && equal(xs, ys);
      case [Vector(xs), Vector(ys)]:
        var same = xs.length == ys.length;
        var i = 0;
        while (same && i < xs.length) {
          same = equal(xs[i], ys[i]);
          i++;
        }
        same;
      case [Nil, Nil]: true;
      case [Record(nx, xs), Record(ny, ys)]:
        if (nx != ny) false;
        else {
          var same = true;
          for (key in xs.keys()) {
            if (!ys.exists(key) || !equal(xs.get(key), ys.get(key))) same = false;
          }
          for (key in ys.keys()) if (!xs.exists(key)) same = false;
          same;
        }
      case [Cons(x, xs), Cons(y, ys)]: equal(x, y) && equal(xs, ys);
      case [Nil, Cons(_, _)] | [Cons(_, _), Nil]: false;
      case _: throw 'Cannot compare these values';
    };
  }

  static function syntax(v:Value):Value {
    return switch (v) {
      case SyntaxLeaf(_, _) | SyntaxNode(_, _): v;
      case _: throw 'Expected Syntax';
    };
  }

  static function syntaxList(v:Value):Value {
    var rest = v;
    while (true) {
      switch (rest) {
        case Nil: return v;
        case Cons(item, tail): syntax(item); rest = tail;
        case _: throw 'Expected Syntax list';
      }
    }
    return v;
  }

  static function vectorItems(value:Value):Array<Value> return switch (value) {
    case Vector(items): items;
    case _: throw 'Expected vector';
  };

  static function vectorIndex(value:Value, size:Int):Int {
    switch (value) {
      case ExactNumber(x): return numeric.FastNumber.index(x, size);
      case _:
    }
    var index = number(value);
    if (index < 0 || index >= size || index != Math.floor(index)) throw 'Vector index out of range';
    return Std.int(index);
  }

  public static function primitive(name:String, args:Array<Value>):Value {
    var a = args[0];
    var b = args.length > 1 ? args[1] : Nil;
    return switch (name) {
      case 'exactFromText': ExactNumber(numeric.FastNumber.exact(text(a)));
      case 'exactFloor': ExactNumber(numeric.FastNumber.roundInteger(exact(a), 'floor'));
      case 'exactCeil': ExactNumber(numeric.FastNumber.roundInteger(exact(a), 'ceil'));
      case 'exactTruncate': ExactNumber(numeric.FastNumber.roundInteger(exact(a), 'truncate'));
      case 'exactRoundEven': ExactNumber(numeric.FastNumber.roundInteger(exact(a), 'half-even'));
      case 'exactIsInteger': Boolean(numeric.FastNumber.isInteger(exact(a)));
      case 'exactToFloat':
        var value = numeric.FastNumber.rational(exact(a));
        var numerator = Std.parseFloat(value.numerator);
        var denominator = Std.parseFloat(value.denominator);
        if (!Math.isFinite(numerator) || !Math.isFinite(denominator))
          throw 'Exact number too large to convert to Float';
        finite((value.negative ? -numerator : numerator) / denominator);
      case '#exactEncode' | 'exactEncode':
        var raw = text(a);
        if (StringTools.startsWith(raw, '.')) raw = '0' + raw;
        if (StringTools.startsWith(raw, '-.')) raw = '-0' + raw.substr(1);
        Text(numeric.FastNumber.encodeExact(numeric.FastNumber.exact(raw)));
      case '#exact+': exactArithmetic('+', a, b);
      case '#exact-': exactArithmetic('-', a, b);
      case '#exact*': exactArithmetic('*', a, b);
      case '#exact/': exactArithmetic('/', a, b);
      case '#exact<': exactCompare('<', a, b);
      case '#exact<=': exactCompare('<=', a, b);
      case '#exact>': exactCompare('>', a, b);
      case '#exact>=': exactCompare('>=', a, b);
      case '+': finite(number(a) + number(b));
      case '-': finite(number(a) - number(b));
      case '*': finite(number(a) * number(b));
      case '/':
        switch ([a, b]) {
          case [ExactNumber(_), ExactNumber(_)]:
            exactArithmetic('/', a, b);
          case [Number(_), Number(_)]:
            var divisor = number(b);
            if (divisor == 0) throw 'Division by zero';
            finite(number(a) / divisor);
          case _:
            throw 'Mixed numeric domains: explicit conversion required';
        }
      case '<': Boolean(number(a) < number(b));
      case '<=': Boolean(number(a) <= number(b));
      case '>': Boolean(number(a) > number(b));
      case '>=': Boolean(number(a) >= number(b));
      case '==': Boolean(equal(a, b));
      case '!=': Boolean(!equal(a, b));
      case 'vector':
        var items:Array<Value> = [];
        var rest = a;
        while (true) switch (rest) {
          case Nil: break;
          case Cons(item, tail): items.push(item); rest = tail;
          case _: throw 'Expected list';
        }
        Vector(items);
      case 'vectorLength': Number(vectorItems(a).length);
      case 'vectorLengthExact': ExactNumber(numeric.FastNumber.exact(Std.string(vectorItems(a).length)));
      case 'vectorGet' | 'vectorGetExact':
        var items = vectorItems(a);
        items[vectorIndex(b, items.length)];
      case 'vectorSet' | 'vectorSetExact':
        var items = vectorItems(a);
        var index = vectorIndex(b, items.length);
        var copy = items.copy();
        copy[index] = args[2];
        Vector(copy);
      case 'CoreOk': ResultValue.ok(a);
      case 'CoreErr': ResultValue.error(a);
      case 'CoreOk?': Boolean(ResultValue.is(a, ResultValue.OK));
      case 'CoreErr?': Boolean(ResultValue.is(a, ResultValue.ERR));
      case 'CoreOk.0': ResultValue.get(a, ResultValue.OK);
      case 'CoreErr.0': ResultValue.get(a, ResultValue.ERR);
      case 'macroExpandSyntax': MacroExpander.syntax(a);
      case '#sumFail': throw 'Non-exhaustive or mismatched variant pattern';
      case '#recordMake':
        var label = text(a);
        var names:Array<String> = [];
        var values:Array<Value> = [];
        var cursor = b;
        var collecting = true;
        while (collecting) switch (cursor) {
          case Nil: collecting = false;
          case Cons(item, rest): names.push(text(item)); cursor = rest;
          case _: throw 'Expected list of record field names';
        }
        cursor = args[2];
        collecting = true;
        while (collecting) switch (cursor) {
          case Nil: collecting = false;
          case Cons(item, rest): values.push(item); cursor = rest;
          case _: throw 'Expected list of record field values';
        }
        if (names.length != values.length) throw 'Record field count mismatch';
        var fields = new haxe.ds.StringMap<Value>();
        for (i in 0...names.length) {
          if (fields.exists(names[i])) throw 'Duplicate record field ' + names[i];
          fields.set(names[i], values[i]);
        }
        Record(label, fields);
      case '#recordGet':
        var key = text(b);
        switch (a) {
          case Record(_, fields):
            if (!fields.exists(key)) throw 'Unknown record field: ' + key;
            fields.get(key);
          case _: throw 'Expected record';
        }
      case 'textLength': Number(UnicodeText.length(text(a)));
      case 'textLengthExact': ExactNumber(numeric.FastNumber.exact(Std.string(UnicodeText.length(text(a)))));
      case 'textAt' | 'textAtExact':
        var source = text(a);
        Text(UnicodeText.at(source, index(b, UnicodeText.length(source))));
      case 'textConcat': Text(text(a) + text(b));
      case 'syntaxLeaf': SyntaxLeaf(text(a), text(b));
      case 'syntaxNode': SyntaxNode(text(a), syntaxList(b));
      case 'syntaxTag': switch (syntax(a)) {
        case SyntaxLeaf(tag, _) | SyntaxNode(tag, _): Text(tag);
        case _: throw 'Expected Syntax';
      };
      case 'syntaxText': switch (syntax(a)) {
        case SyntaxLeaf(_, value): Text(value);
        case _: throw 'Expected syntax leaf';
      };
      case 'syntaxChildren': switch (syntax(a)) {
        case SyntaxNode(_, children): children;
        case _: throw 'Expected syntax node';
      };
      case 'cons' | '#cons':
        switch (b) {
          case Nil | Cons(_, _): Cons(a, b);
          case _: throw 'Expected list';
        }
      case 'isEmpty' | '#isEmpty':
        switch (a) {
          case Nil: Boolean(true);
          case Cons(_, _): Boolean(false);
          case _: throw 'Expected list';
        }
      case 'head' | '#head':
        switch (a) {
          case Cons(x, _): x;
          case Nil: throw 'head of empty list';
          case _: throw 'Expected list';
        }
      case 'tail' | '#tail':
        switch (a) {
          case Cons(_, xs): xs;
          case Nil: throw 'tail of empty list';
          case _: throw 'Expected list';
        }
      case _: throw 'Unknown primitive: ' + name;
    };
  }

  /** Host-stack independent CEK-style evaluator. All nested applications and
      conditional branches use explicit continuation frames, so even the Nail
      lexer/parser can make tens of thousands of recursive calls without
      exhausting the Haxe/JS/PHP call stack. Non-tail source calls may still
      require linear heap space, but never linear host-stack space. */
  function evaluate(expr:Expr, env:Env):Value {
    var current:Expr = expr;
    var scope:Env = env;
    var result:Value = Nil;
    var hasResult = false;
    var frames:Array<EvalFrame> = [];
    while (true) {
      tick();
      if (!hasResult) {
        switch (current) {
          case Literal(v): result = v; hasResult = true;
          case Var(name): result = scope.lookup(name); hasResult = true;
          case Lambda(param, body): result = Closure(param, body, scope); hasResult = true;
          case Apply(fn, arg):
            frames.push(NeedArgument(arg, scope));
            current = fn;
          case If(condition, yes, no):
            frames.push(ChooseBranch(yes, no, scope));
            current = condition;
        }
      } else {
        if (frames.length == 0) return result;
        switch (frames.pop()) {
          case NeedArgument(arg, captured):
            frames.push(ApplyFunction(result));
            current = arg;
            scope = captured;
            hasResult = false;
          case ChooseBranch(yes, no, captured):
            current = bool(result) ? yes : no;
            scope = captured;
            hasResult = false;
          case ApplyFunction(fn):
            // Count applications independently from expression visits, as in
            // the recursive v0.11 evaluator. A smaller maxSteps still bounds
            // even an unproductive loop of function applications.
            tick();
            switch (fn) {
              case Closure(param, body, captured):
                var local = new Env(captured);
                local.bind(param, result);
                current = body;
                scope = local;
                hasResult = false;
              case Native(name, arity, prior):
                var args = prior.copy();
                args.push(result);
                result = args.length < arity ? Native(name, arity, args) : primitive(name, args);
              case HostFunction(_, invoke): result = invoke(result);
              case _: throw 'Value is not a function';
            }
        }
      }
    }
    throw 'Unreachable iterative evaluator';
  }

  /** Run an existing callable, e.g. the Nail-written parser/compiler, through
      the same iterative evaluator. No separate recursive call path exists. */
  function call(f:Value, arg:Value):Value {
    return evaluate(Apply(Literal(f), Literal(arg)), root);
  }

  /** Public, budgeted invocation of an already defined Nail function.
      Used by opt-in procedural transformations of first-class Syntax. */
  public function invoke(name:String, argument:Value):Value {
    steps = 0;
    return call(root.lookup(name), argument);
  }

  /** Only the embedding host can grant this value; Nail has no capability
      constructor or ambient read primitive. Use the same signature with
      TypeChecker.importSignature when checking sources statically. */
  public function grantTextReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text reader grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asValue());
  }

  /** Opt-in discriminated Result[Text,Text] host read grant. */
  public function grantTextResultReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text reader grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asResultValue());
  }

  /** Explicit write-only grant; separate from every text-reader binding. */
  public function grantTextWriter(alias:String, capability:TextWriteCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text writer grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asValue());
  }

  /** Execute validated core forms using the same evaluator on every target. */
  function executeForms(forms:Array<Form>):Array<Value> {
    var output:Array<Value> = [];
    for (form in forms) {
      switch (form) {
        case SumType(name, _, constructors):
          for (definition in SumLowering.definitions(name, constructors)) switch (definition) {
            case Define(generatedName, body):
              if (root.hasHere(generatedName)) throw 'Already defined: ' + generatedName;
              root.bind(generatedName, evaluate(body, root));
            case _: throw 'Invalid sum lowering';
          }
        case RecordType(name, _, fields):
          for (definition in RecordLowering.definitions(name, fields)) switch (definition) {
            case Define(generatedName, body):
              if (root.hasHere(generatedName)) throw 'Already defined: ' + generatedName;
              root.bind(generatedName, evaluate(body, root));
            case _: throw 'Invalid record lowering';
          }
        case Define(name, body):
          if (root.hasHere(name)) throw 'Already defined: ' + name;
          var value = evaluate(body, root);
          root.bind(name, value);
        case Evaluate(body): output.push(evaluate(body, root));
      }
    }
    return output;
  }

  public function run(source:String, ?modules:String->Null<String>):Array<Value> {
    #if nail_seed_only
    // A bootstrap-only build cannot even use the host parser accidentally.
    throw 'Host source parser disabled in bootstrap-only build';
    #else
    steps = 0;
    return executeForms(new Parser(source).parse(modules));
    #end
  }

  /** Execute a first-class Syntax Program built by code running in Nail. */
  public function runSyntax(tree:Value):Array<Value> {
    steps = 0;
    return executeForms(SyntaxBridge.forms(MacroExpander.syntax(tree)));
  }

  /** Parse source with the tokenizer and Pratt parser written in Nail. */
  public function parseWithNail(source:String, ?modules:String->Null<String>):Value {
    steps = 0;
    var parse = root.lookup('parseSource');
    var resolve = modules == null ? null : (name:String) -> {
      var moduleSource = modules(name);
      if (moduleSource == null) return null;
      if (numeric.NumericDialect.isExact(moduleSource) != numeric.NumericDialect.isExact(source))
        throw 'Imported macro module uses incompatible numeric dialect: ' + name;
      return call(parse, Text(moduleSource));
    };
    var expanded = MacroExpander.syntax(call(parse, Text(source)), resolve);
    return numeric.NumericDialect.isExact(source)
      ? call(root.lookup('exactRewrite'), expanded) : expanded;
  }

  /** Inspect the trusted standard record transformer before code generation.
      Call checkSyntax on the retained source, not on erased declarations. */
  public function expandRecordsWithNail(source:String, ?modules:String->Null<String>):Value {
    var tree = parseWithNail(source, modules);
    return call(root.lookup('expandRecordDeclarations'), tree);
  }

  /** Opt-in contract validation for the trusted Nail record transformer.
      The original nominal Program is checked before the expanded Program
      is returned; malformed/extra generated forms are rejected. */
  public function validatedRecordsWithNail(source:String, ?modules:String->Null<String>):Value
    return GeneratedDeclarationValidator.validate(expandRecordsWithNail(source, modules));

  /** Compile only after validating the transformer output against its source.
      This path is separate from the existing compileWithNail compatibility API. */
  public function compileValidatedWithNail(source:String, ?modules:String->Null<String>):Value
    return compileSyntaxWithNail(validatedRecordsWithNail(source, modules));

  /** Compile a generated Program only after checking explicit monomorphic
      signatures. Source declarations supply nominal types and existing
      definitions. Does not mutate the source checker or add VM instructions. */
  public function compileCheckedGenerated(source:Value, generated:Value,
      contracts:Array<{name:String, type:nail.NType}>):Value
    return compileSyntaxWithNail(
      GeneratedDeclarationValidator.validateTyped(source, generated, contracts));

  /** Use Nail's own parseSource function, then execute its output.
      The bootstrap Haxe parser is used only to load stdlib.nail. */
  public function runWithNail(source:String, ?modules:String->Null<String>):Array<Value> {
    var tree = parseWithNail(source, modules);
    return executeForms(SyntaxBridge.forms(MacroExpander.syntax(tree)));
  }

  public function runPlainWithNail(source:String, ?modules:String->Null<String>):Array<Dynamic>
    return plainResults(runWithNail(source, modules));

  /** Shared primitive environment for a bytecode executor; no source parsing. */
  public function bytecodeRoot():Env return root;

  /** Compile source using the compiler function written in Nail. */
  public function compileWithNail(source:String, ?modules:String->Null<String>):Value {
    if (modules != null) return compileSyntaxWithNail(parseWithNail(source, modules));
    steps = 0;
    var compiler = numeric.NumericDialect.isExact(source) ? 'compileExactSource' : 'compileSource';
    return call(root.lookup(compiler), Text(source));
  }

  /** Compile an already-parsed Syntax program using Nail code only.
      Used to bootstrap the compiler without hitting the recursive lexer limit. */
  public function compileSyntaxWithNail(tree:Value):Value {
    steps = 0;
    return call(root.lookup('compileSyntax'), tree);
  }

  public function names():Array<String> return root.keys();

  public function loadStdlib():Void {
    var source = haxe.Resource.getString('stdlib');
    if (source == null) throw 'Missing stdlib resource';
    run(source);
  }

  /** Values converted into JSON-compatible primitive data (functions intentionally excluded). */
  public static function toPlain(value:Value):Dynamic {
    return switch (value) {
      case Number(n): n;
      case ExactNumber(n): numeric.FastNumber.encodeExact(n);
      case Boolean(b): b;
      case Text(s): s;
      case Vector(items): items.map(toPlain);
      case Record(typeName, fields):
        var data:Dynamic = {};
        Reflect.setField(data, "$type", typeName);
        for (name in fields.keys()) Reflect.setField(data, name, toPlain(fields.get(name)));
        data;
      case SyntaxLeaf(kind, value): {tag:kind, value:value};
      case SyntaxNode(kind, children): {tag:kind, children:toPlain(children)};
      case Nil: ([] : Array<Dynamic>);
      case Cons(_, _):
        var items:Array<Dynamic> = [];
        var rest = value;
        var complete = false;
        while (!complete) {
          switch (rest) {
            case Nil: complete = true;
            case Cons(head, tail): items.push(toPlain(head)); rest = tail;
            case _: throw 'Malformed list';
          }
        }
        items;
      case _: throw 'Cannot serialize function value';
    };
  }

  /** Public convenience API, usable from the generated JS runtime. */
  public function runPlain(source:String, ?modules:String->Null<String>):Array<Dynamic> return plainResults(run(source, modules));

  public static function plainResults(values:Array<Value>):Array<Dynamic> {
    return [for (v in values) toPlain(v)];
  }
}

