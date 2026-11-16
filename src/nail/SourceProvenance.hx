package nail;

import haxe.ds.ObjectMap;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.SourcePositions.SourceSpan;
import nail.SourcePositions.SourceToken;

/** An optional source map for parser-created AST nodes, kept outside Ast.Expr
    and the canonical Syntax/bytecode format. No host object references escape
    into Nail runtime values. Parser transformations may create synthetic nodes:
    their outer expression retains the source range of the lowered construct. */
class SourceProvenance {
  public final tokens:Array<SourceToken>;
  final expressionSpans:ObjectMap<Dynamic, SourceSpan> = new ObjectMap();
  final formSpans:ObjectMap<Dynamic, SourceSpan> = new ObjectMap();
  final expansionSites:ObjectMap<Dynamic, SourceSpan> = new ObjectMap();
  final expressionStarts:ObjectMap<Dynamic, Int> = new ObjectMap();

  public function new(tokens:Array<SourceToken>) {
    this.tokens = tokens;
  }

  public function expression(expr:Expr, first:Int, afterLast:Int):Expr {
    var source = SourcePositions.span(tokens, first, afterLast);
    if (source != null) {
      expressionSpans.set(expr, source);
      expressionStarts.set(expr, first);
    }
    return expr;
  }

  public function form(form:Form, first:Int, afterLast:Int):Form {
    var source = SourcePositions.span(tokens, first, afterLast);
    if (source != null) formSpans.set(form, source);
    return form;
  }

  /** Carry call-site provenance to a normalized form. Generated children
      have no invented locations; their source-origin arguments keep their own. */
  public function transfer(original:Form, normalized:Form):Void {
    var span = spanOfForm(original);
    if (span != null) formSpans.set(normalized, span);
    switch ([original, normalized]) {
      case [Define(_, before), Define(_, after)] | [Evaluate(before), Evaluate(after)]:
        var bodySpan = spanOfExpression(before);
        if (bodySpan != null) {
          expansionSites.set(after, bodySpan);
          // A macro may return a caller argument unchanged. Preserve that
          // argument's more precise original span rather than overwriting it.
          if (expressionSpans.get(after) == null) expressionSpans.set(after, bodySpan);
        }
        var first = expressionStarts.get(before);
        if (first != null && expressionStarts.get(after) == null)
          expressionStarts.set(after, first);
      case _:
    }
  }

  public function startToken(expr:Expr):Int {
    var position = expressionStarts.get(expr);
    return position == null ? -1 : position;
  }

  public function spanOfExpression(expr:Expr):Null<SourceSpan>
    return expressionSpans.get(expr);

  /** Outer macro call site, even if the result reuses a caller argument. */
  public function expansionSiteOfExpression(expr:Expr):Null<SourceSpan>
    return expansionSites.get(expr);

  public function spanOfForm(form:Form):Null<SourceSpan>
    return formSpans.get(form);
}
