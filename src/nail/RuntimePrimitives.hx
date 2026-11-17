package nail;

import nail.Value;

/** Single target-independent home for the runtime's native operations.
    Both evaluators share this environment and exact primitive semantics.
    The source-free compiler must not depend on the Haxe parser or AST VM. */
class RuntimePrimitives {
  public static function environment():Env {
    var root = new Env();
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
    root.bind('canonicalFloat', Native('canonicalFloat', 1, []));
    for (name in ['exactFloor', 'exactCeil', 'exactTruncate',
        'exactRoundEven', 'exactIsInteger'])
      root.bind(name, Native(name, 1, []));
    for (name in ['textLengthExact', 'vectorLengthExact', 'exactFromText', 'exactToFloat'])
      root.bind(name, Native(name, 1, []));
    for (name in ['textAtExact', 'vectorGetExact'])
      root.bind(name, Native(name, 2, []));
    root.bind('vectorSetExact', Native('vectorSetExact', 3, []));
    for (name in ['textLengthInt','vectorLengthInt'])
      root.bind(name, Native(name, 1, []));
    for (name in ['textAtInt','vectorGetInt'])
      root.bind(name, Native(name, 2, []));
    root.bind('vectorSetInt', Native('vectorSetInt', 3, []));
    for (name in ['+', '-', '*', '/', '<', '<=', '>', '>='])
      root.bind('#modern' + name, Native('#modern' + name, 2, []));
    for (name in ['toFloat','toRatio','ratioFromText','intFromText'])
      root.bind(name, Native(name, 1, []));
    return root;
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


  static function modernArithmetic(op:String,a:Value,b:Value):Value {
    switch ([a,b]) {
      case [Number(x),Number(y)]:
        if (op == '/' && y == 0) throw 'Division by zero';
        return finite(switch (op) {
          case '+': x+y;
          case '-': x-y;
          case '*': x*y;
          case '/': x/y;
          case _: throw 'Unknown numeric operation ' + op;
        });
      case [IntNumber(x),IntNumber(y)]:
        var result = numeric.FastNumber.arithmetic(op,x,y);
        return op == '/' ? RatioNumber(result) : IntNumber(result);
      case [IntNumber(x),RatioNumber(y)] |
           [RatioNumber(x),IntNumber(y)] |
           [RatioNumber(x),RatioNumber(y)]:
        return RatioNumber(numeric.FastNumber.arithmetic(op,x,y));
      case _:
        throw 'Mixed numeric domains: explicit conversion required';
    }
  }

  static function modernCompare(op:String,a:Value,b:Value):Value {
    var compared:Int = switch ([a,b]) {
      case [Number(x),Number(y)]: x < y ? -1 : x > y ? 1 : 0;
      case [IntNumber(x),IntNumber(y)] |
           [IntNumber(x),RatioNumber(y)] |
           [RatioNumber(x),IntNumber(y)] |
           [RatioNumber(x),RatioNumber(y)]:
        numeric.FastNumber.compare(x,y);
      case _:
        throw 'Mixed numeric domains: explicit conversion required';
    };
    return Boolean(switch (op) {
      case '<': compared < 0;
      case '<=': compared <= 0;
      case '>': compared > 0;
      case '>=': compared >= 0;
      case _: throw 'Unknown numeric comparison ' + op;
    });
  }

  static function floatFromExact(v:numeric.FastNumber.FastValue):Value {
    var r = numeric.FastNumber.rational(v);
    var n = Std.parseFloat(r.numerator), d = Std.parseFloat(r.denominator);
    if (!Math.isFinite(n) || !Math.isFinite(d))
      throw 'Exact number too large to convert to Float';
    return finite((r.negative ? -n : n) / d);
  }

  static function text(v:Value):String {
    return switch (v) {
      case Text(s): s;
      case _: throw 'Expected text';
    };
  }

  static function index(v:Value, size:Int):Int {
    switch (v) {
      case ExactNumber(x) | IntNumber(x): return numeric.FastNumber.index(x, size);
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
      case [IntNumber(x), IntNumber(y)] |
           [IntNumber(x), RatioNumber(y)] |
           [RatioNumber(x), IntNumber(y)] |
           [RatioNumber(x), RatioNumber(y)]:
        numeric.FastNumber.equal(x,y);
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
      case ExactNumber(x) | IntNumber(x): return numeric.FastNumber.index(x, size);
      case _:
    }
    var index = number(value);
    if (index < 0 || index >= size || index != Math.floor(index)) throw 'Vector index out of range';
    return Std.int(index);
  }

  public static function apply(name:String, args:Array<Value>):Value {
    var a = args[0];
    var b = args.length > 1 ? args[1] : Nil;
    return switch (name) {

      case 'intFromText':
        var v = numeric.FastNumber.exact(text(a));
        if (!numeric.FastNumber.isInteger(v)) throw 'Int requires an integer';
        IntNumber(v);
      case 'ratioFromText': RatioNumber(numeric.FastNumber.exact(text(a)));
      case 'toRatio': switch (a) {
        case IntNumber(v): RatioNumber(v);
        case _: throw 'toRatio requires Int';
      };
      case 'toFloat': switch (a) {
        case IntNumber(v) | RatioNumber(v): floatFromExact(v);
        case _: throw 'toFloat requires Int or Ratio';
      };
      case '#modern+': modernArithmetic('+',a,b);
      case '#modern-': modernArithmetic('-',a,b);
      case '#modern*': modernArithmetic('*',a,b);
      case '#modern/': modernArithmetic('/',a,b);
      case '#modern<': modernCompare('<',a,b);
      case '#modern<=': modernCompare('<=',a,b);
      case '#modern>': modernCompare('>',a,b);
      case '#modern>=': modernCompare('>=',a,b);
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
      case 'canonicalFloat':
        var raw = text(a);
        var num = Std.parseFloat(raw);
        if (!Math.isFinite(num)) throw 'Invalid Float literal';
        Text(Std.string(num));
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
      case 'vectorLengthInt': IntNumber(numeric.FastNumber.exact(Std.string(vectorItems(a).length)));
      case 'vectorGet' | 'vectorGetExact' | 'vectorGetInt':
        var items = vectorItems(a);
        items[vectorIndex(b, items.length)];
      case 'vectorSet' | 'vectorSetExact' | 'vectorSetInt':
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
      case 'textLengthInt': IntNumber(numeric.FastNumber.exact(Std.string(UnicodeText.length(text(a)))));
      case 'textAt' | 'textAtExact' | 'textAtInt':
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

}
