package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Converts first-class Syntax values emitted by Nail back to the existing core AST.
    This is a validated representation boundary, not an additional expression kind.
    No parsing or pattern matching against Nail source text happens here. */
class SyntaxBridge {
  static final numberPattern = ~/^-?(?:\d+(?:\.\d+)?|\.\d+)$/;

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
        if (values.length != expected) throw 'Invalid Syntax ' + tag + ': expected ' + expected + ' children';
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

  public static function expr(value:Value):Expr {
    return switch (value) {
      case SyntaxLeaf('Var', name): Var(name);
      case SyntaxNode('Literal', parts):
        var xs = elements(parts);
        if (xs.length != 1) throw 'Invalid Syntax literal arity';
        switch (xs[0]) {
          case SyntaxLeaf('Number', text):
            if (!numberPattern.match(text)) throw 'Invalid Syntax number';
            var n = Std.parseFloat(text);
            if (!Math.isFinite(n)) throw 'Invalid Syntax nonfinite number';
            Literal(Number(n));
          case SyntaxLeaf('Bool', 'true'): Literal(Boolean(true));
          case SyntaxLeaf('Bool', 'false'): Literal(Boolean(false));
          case SyntaxLeaf('Nil', 'nil'): Literal(Nil);
          case SyntaxLeaf('Text', text): Literal(Text(text));
          case _: throw 'Invalid Syntax literal kind';
        };
      case SyntaxNode('Lambda', _):
        var items = children(value, 'Lambda', 2);
        Lambda(label(items[0], 'Name'), expr(items[1]));
      case SyntaxNode('Apply', _):
        var items = children(value, 'Apply', 2);
        Apply(expr(items[0]), expr(items[1]));
      case SyntaxNode('If', _):
        var items = children(value, 'If', 3);
        If(expr(items[0]), expr(items[1]), expr(items[2]));
      case SyntaxLeaf('Error', message): throw 'Nail parser error: ' + message;
      case SyntaxLeaf('LexError', message): throw 'Nail lexer error: ' + message;
      case _: throw 'Invalid Syntax expression';
    };
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
            case _: throw 'Invalid Syntax program form';
          });
        }
      case SyntaxLeaf('Error', message): throw 'Nail parser error: ' + message;
      case SyntaxLeaf('LexError', message): throw 'Nail lexer error: ' + message;
      case _: throw 'Invalid Syntax: expected Program';
    }
    return result;
  }
}
