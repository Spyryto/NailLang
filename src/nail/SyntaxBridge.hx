package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Converts first-class Syntax values emitted by Nail back to the existing core AST.
    This is a validated representation boundary, not an additional expression kind.
    No parsing or pattern matching against Nail source text happens here. */
class SyntaxBridge {
  static final numberPattern = ~/^-?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$/;

  static function elements(value:Value):Array<Value> {
    var result:Array<Value> = [];
    var rest = value;
    var done = false;
    while (!done) {
      switch (rest) {
        case Nil: done = true;
        case Cons(head, tail): result.push(head); rest = tail;
        case _: throw 'Invalid Syntax: children must be a list';
      }
    }
    return result;
  }

  static function children(value:Value, tag:String, expected:Int):Array<Value> {
    return switch (value) {
      case SyntaxNode(actual, items) if (actual == tag):
        var values = elements(items);
        if (expected >= 0 && values.length != expected) throw 'Invalid Syntax ' + tag + ': expected ' + expected + ' children';
        values;
      case _: throw 'Invalid Syntax: expected ' + tag;
    };
  }

  static function label(value:Value, kind:String):String {
    return switch (value) {
      case SyntaxLeaf(actual, text) if (actual == kind): text;
      case _: throw 'Invalid Syntax: expected ' + kind + ' leaf';
    };
  }

  /** Bottom-up decoder with heap work frames: no host recursion per Syntax node. */
  public static function expr(value:Value):Expr {
    var pending:Array<{source:Value, finish:Bool}> = [{source:value, finish:false}];
    var done:Array<Expr> = [];
    while (pending.length > 0) {
      var frame = pending.pop();
      if (frame.finish) {
        switch (frame.source) {
          case SyntaxNode('Lambda', _):
            var items = children(frame.source, 'Lambda', 2);
            var body = done.pop();
            done.push(Lambda(label(items[0], 'Name'), body));
          case SyntaxNode('Apply', _):
            var arg = done.pop();
            var fn = done.pop();
            done.push(Apply(fn, arg));
          case SyntaxNode('If', _):
            var no = done.pop();
            var yes = done.pop();
            var cond = done.pop();
            done.push(If(cond, yes, no));
          case _: throw 'Invalid Syntax expression frame';
        }
        continue;
      }
      switch (frame.source) {
        case SyntaxLeaf('Var', name): done.push(Var(name));
        case SyntaxNode('Literal', parts):
          var xs = elements(parts);
          if (xs.length != 1) throw 'Invalid Syntax literal arity';
          var lit:Expr = switch (xs[0]) {
            case SyntaxLeaf('Number', text):
              if (!numberPattern.match(text)) throw 'Invalid Syntax number';
              var n = Std.parseFloat(text);
              if (!Math.isFinite(n)) throw 'Invalid Syntax nonfinite number';
              Literal(Number(n));
            case SyntaxLeaf('ExactNumber', text): Literal(ExactNumber(numeric.FastNumber.decodeExact(text)));
            case SyntaxLeaf('Bool', 'true'): Literal(Boolean(true));
            case SyntaxLeaf('Bool', 'false'): Literal(Boolean(false));
            case SyntaxLeaf('Nil', 'nil'): Literal(Nil);
            case SyntaxLeaf('Text', text): Literal(Text(text));
            case _: throw 'Invalid Syntax literal kind';
          };
          done.push(lit);
        case SyntaxNode('Lambda', _):
          var items = children(frame.source, 'Lambda', 2);
          label(items[0], 'Name');
          pending.push({source:frame.source, finish:true});
          pending.push({source:items[1], finish:false});
        case SyntaxNode('Apply', _):
          var items = children(frame.source, 'Apply', 2);
          pending.push({source:frame.source, finish:true});
          pending.push({source:items[1], finish:false});
          pending.push({source:items[0], finish:false});
        case SyntaxNode('If', _):
          var items = children(frame.source, 'If', 3);
          pending.push({source:frame.source, finish:true});
          pending.push({source:items[2], finish:false});
          pending.push({source:items[1], finish:false});
          pending.push({source:items[0], finish:false});
        case SyntaxLeaf('Error', message): throw 'Nail parser error: ' + message;
        case SyntaxLeaf('MacroError', message): throw 'Macro error: ' + message;
        case SyntaxLeaf('LexError', message): throw 'Nail lexer error: ' + message;
        case _: throw 'Invalid Syntax expression';
      }
    }
    if (done.length != 1) throw 'Invalid Syntax expression result';
    return done.pop();
  }

  public static function forms(value:Value):Array<Form> {
    var result:Array<Form> = [];
    switch (value) {
      case SyntaxNode('Program', items):
        for (form in elements(items)) {
          result.push(switch (form) {
            case SyntaxNode('Define', _):
              var parts = children(form, 'Define', 2);
              Define(label(parts[0], 'Name'), expr(parts[1]));
            case SyntaxNode('Evaluate', _):
              var parts = children(form, 'Evaluate', 1);
              Evaluate(expr(parts[0]));
            case SyntaxNode('SumType', _):
              var parts = children(form, 'SumType', 3);
              var typeName = label(parts[0], 'Name');
              var params:Array<String> = [];
              for (item in children(parts[1], 'Params', -1)) params.push(label(item, 'Name'));
              var ctors:Array<nail.Ast.SumConstructor> = [];
              for (node in children(parts[2], 'Constructors', -1)) {
                var entry = children(node, 'Constructor', 2);
                var fields:Array<String> = [];
                for (field in children(entry[1], 'Args', -1)) fields.push(label(field, 'Type'));
                ctors.push({name:label(entry[0], 'Name'), fieldTypes:fields});
              }
              SumType(typeName, params, ctors);
            case SyntaxNode('RecordType', _):
              var parts = children(form, 'RecordType', 2);
              var typeName = label(parts[0], 'Name');
              var raw = children(parts[1], 'Fields', -1);
              var fields:Array<nail.Ast.RecordField> = [];
              for (field in raw) {
                var pair = children(field, 'Field', 2);
                fields.push({name:label(pair[0], 'Name'), typeName:label(pair[1], 'Type')});
              }
              RecordType(typeName, fields);
            case _: throw 'Invalid Syntax program form';
          });
        }
      case SyntaxLeaf('Error', message): throw 'Nail parser error: ' + message;
      case SyntaxLeaf('MacroError', message): throw 'Macro error: ' + message;
      case SyntaxLeaf('LexError', message): throw 'Nail lexer error: ' + message;
      case _: throw 'Invalid Syntax: expected Program';
    }
    return result;
  }
}

