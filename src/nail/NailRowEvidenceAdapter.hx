package nail;

import haxe.ds.StringMap;
import nail.Value;

/** Pure, deliberately non-inferential bridge from the canonical Syntax IR
    created by Nail's tcCanonicalRowEvidence to the isolated preview JSON.
    This class does not construct HM types, impose row requirements, reorder
    fields, freshen variables or affect the public module ABI. */
class NailRowEvidenceAdapter {
  static function fail(message:String):Dynamic
    throw 'Nail row evidence adapter: '+message;

  static function elements(list:Value):Array<Value> {
    var out:Array<Value>=[];
    var remaining=list;
    while (true) switch (remaining) {
      case Nil: return out;
      case Cons(head,tail):
        if (out.length>=RowSchemePreview.MAX_NODES)
          fail('too many Syntax children');
        out.push(head);
        remaining=tail;
      case _: fail('not a Syntax list');
    }
    return out;
  }

  static function children(tree:Value,tag:String,arity:Int=-1):Array<Value> {
    return switch (tree) {
      case SyntaxNode(actual,items) if (actual==tag):
        var values=elements(items);
        if (arity>=0 && values.length!=arity) fail('invalid '+tag+' arity');
        values;
      case _: fail('expected '+tag);
    };
  }

  static function leaf(tree:Value,tag:String):String {
    return switch (tree) {
      case SyntaxLeaf(actual,value) if (actual==tag): StringTools.trim(value);
      case _: fail('expected '+tag+' leaf');
    };
  }

  static function variable(tree:Value,ids:StringMap<Int>):Int {
    var name=leaf(tree,'TCVar');
    var id=ids.get(name);
    if (id==null) fail('free canonical variable '+name);
    return id;
  }

  static function field(tree:Value,ids:StringMap<Int>,depth:Int):Dynamic {
    var parts=children(tree,'TCField',2);
    return [leaf(parts[0],'TCName'),typeTerm(parts[1],ids,depth+1)];
  }

  static function typeTerm(tree:Value,ids:StringMap<Int>,depth:Int):Dynamic {
    if (depth>RowSchemePreview.MAX_DEPTH) fail('type depth limit');
    return switch (tree) {
      case SyntaxLeaf('TCBase',raw):
        [StringTools.trim(raw)];
      case SyntaxLeaf('TCVar',_):
        ['var',variable(tree,ids)];
      case SyntaxNode('TCList',_):
        var p=children(tree,'TCList',1);
        ['list',typeTerm(p[0],ids,depth+1)];
      case SyntaxNode('TCFun',_):
        var p=children(tree,'TCFun',2);
        ['fn',typeTerm(p[0],ids,depth+1),typeTerm(p[1],ids,depth+1)];
      case SyntaxNode('TCStruct',_) | SyntaxNode('TCRowField',_):
        var all:Array<Dynamic>=[];
        var rest=tree;
        var finished=false;
        var tail:Dynamic=null;
        var steps=0;
        while (!finished) {
          if (++steps>RowSchemePreview.MAX_DEPTH) fail('row depth limit');
          switch(rest) {
            case SyntaxNode('TCRowField',_):
              var p=children(rest,'TCRowField',3);
              all.push([leaf(p[0],'TCName'),typeTerm(p[1],ids,depth+1)]);
              rest=p[2];
            case SyntaxNode('TCStruct',_):
              for (part in children(rest,'TCStruct'))
                all.push(field(part,ids,depth));
              finished=true;
            case SyntaxLeaf('TCVar',_):
              tail=['var',variable(rest,ids)];
              finished=true;
            case _: fail('invalid canonical row tail');
          }
        }
        ['row',all,tail];
      case _: fail('unsupported canonical type');
    };
  }

  /** Called only on an Ok payload created by Nail bytecode. */
  public static function encode(evidence:Value):String {
    var parts=children(evidence,'TCWireScheme',4);
    var variables=children(parts[1],'TCWireQuant');
    var ids=new StringMap<Int>();
    var n=0;
    for (v in variables) {
      var key=leaf(v,'TCVar');
      if (ids.exists(key)) fail('duplicate variable');
      ids.set(key,n++);
    }
    var eq:Array<Int>=[];
    for (v in children(parts[2],'TCWireEq')) eq.push(variable(v,ids));
    var lacks:Array<Dynamic>=[];
    for (entry in children(parts[3],'TCWireLacksSet')) {
      var xs=children(entry,'TCWireLacks',2);
      var labels=[for (label in children(xs[1],'TCWireAbsent'))
        leaf(label,'TCName')];
      lacks.push([variable(xs[0],ids),labels]);
    }
    return RowSchemePreview.encode(
      [RowSchemePreview.FORMAT,typeTerm(parts[0],ids,0),
        [for (i in 0...n) i],eq,lacks]);
  }
}
