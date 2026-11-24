package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/**
 * First semantic CoreIR boundary, deliberately independent of executable
 * Syntax bytecode and of any host-specific VM representation.
 *
 * Five expression constructors preserve pure, left-to-right evaluation
 * semantics; CInvoke/CChoose mark tail positions explicitly. Future passes
 * can normalize or optimize here without erasing the canonical source AST.
 */
enum CoreExpr {
  CValue(value:Value);
  CRead(name:String);
  CFunction(parameter:String,body:CoreExpr);
  CInvoke(fn:CoreExpr,arg:CoreExpr,tail:Bool);
  CChoose(condition:CoreExpr,yes:CoreExpr,no:CoreExpr,tail:Bool);
}

enum CoreForm {
  CDefine(name:String,body:CoreExpr);
  CExecute(body:CoreExpr);
}

class CoreIR {
  static function fail(message:String):Dynamic
    throw "CoreIR: "+message;

  /** Iterative lowering avoids host recursion limits on long expressions. */
  public static function lowerExpr(expr:Expr,tail:Bool):CoreExpr {
    var pending:Array<{source:Expr,tail:Bool,finish:Bool}>=[
      {source:expr,tail:tail,finish:false}
    ];
    var result:Array<CoreExpr>=[];
    while(pending.length>0) {
      var frame=pending.pop();
      if(frame.finish) {
        result.push(switch(frame.source) {
          case Lambda(param,_):
            CFunction(param,result.pop());
          case Apply(_,_):
            var arg=result.pop();
            var fn=result.pop();
            CInvoke(fn,arg,frame.tail);
          case If(_,_,_):
            var no=result.pop();
            var yes=result.pop();
            var condition=result.pop();
            CChoose(condition,yes,no,frame.tail);
          case _: fail("invalid lowering frame");
        });
        continue;
      }
      switch(frame.source) {
        case Literal(value):
          result.push(CValue(value));
        case Var(name):
          result.push(CRead(name));
        case Lambda(_,body):
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:body,tail:true,finish:false});
        case Apply(fn,arg):
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:arg,tail:false,finish:false});
          pending.push({source:fn,tail:false,finish:false});
        case If(condition,yes,no):
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:no,tail:frame.tail,finish:false});
          pending.push({source:yes,tail:frame.tail,finish:false});
          pending.push({source:condition,tail:false,finish:false});
      }
    }
    if(result.length!=1) fail("invalid lowered expression");
    return result[0];
  }

  /** Validate every explicit tail marker before recovering ordinary AST.
      No malformed or incorrectly positioned tail invocation is permitted. */
  public static function raiseExpr(expr:CoreExpr,tail:Bool):Expr {
    var pending:Array<{source:CoreExpr,tail:Bool,finish:Bool}>=[
      {source:expr,tail:tail,finish:false}
    ];
    var result:Array<Expr>=[];
    while(pending.length>0) {
      var frame=pending.pop();
      if(frame.finish) {
        result.push(switch(frame.source) {
          case CFunction(param,_):
            Lambda(param,result.pop());
          case CInvoke(_,_,_):
            var arg=result.pop();
            var fn=result.pop();
            Apply(fn,arg);
          case CChoose(_,_,_,_):
            var no=result.pop();
            var yes=result.pop();
            var condition=result.pop();
            If(condition,yes,no);
          case _: fail("invalid raising frame");
        });
        continue;
      }
      switch(frame.source) {
        case CValue(value):
          result.push(Literal(value));
        case CRead(name):
          if(name==null || name.length==0) fail("invalid read name");
          result.push(Var(name));
        case CFunction(param,body):
          if(param==null || param.length==0) fail("invalid lambda parameter");
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:body,tail:true,finish:false});
        case CInvoke(fn,arg,markedTail):
          if(markedTail!=frame.tail)
            fail("tail call marker does not match expression position");
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:arg,tail:false,finish:false});
          pending.push({source:fn,tail:false,finish:false});
        case CChoose(condition,yes,no,markedTail):
          if(markedTail!=frame.tail)
            fail("tail branch marker does not match expression position");
          pending.push({source:frame.source,tail:frame.tail,finish:true});
          pending.push({source:no,tail:frame.tail,finish:false});
          pending.push({source:yes,tail:frame.tail,finish:false});
          pending.push({source:condition,tail:false,finish:false});
      }
    }
    if(result.length!=1) fail("invalid raised expression");
    return result[0];
  }

  /** Canonical record/sum lowerings remain the same as the independent
      bytecode compiler. CoreIR itself carries only executable definitions
      and evaluations; type metadata stays with the checked front end. */
  public static function lower(forms:Array<Form>):Array<CoreForm> {
    if(forms==null) fail("missing source forms");
    var executable:Array<Form>=[];
    for(form in forms) switch(form) {
      case RecordType(name,_,fields):
        for(def in RecordLowering.definitions(name,fields))
          executable.push(def);
      case SumType(name,_,constructors):
        for(def in SumLowering.definitions(name,constructors))
          executable.push(def);
      case _: executable.push(form);
    }
    var program:Array<CoreForm>=[];
    for(form in executable) switch(form) {
      case Define(name,body):
        program.push(CDefine(name,lowerExpr(body,true)));
      case Evaluate(body):
        program.push(CExecute(lowerExpr(body,true)));
      case _:
        fail("non-executable declaration after lowering");
    }
    return program;
  }

  public static function raise(program:Array<CoreForm>):Array<Form> {
    if(program==null) fail("missing CoreIR program");
    var forms:Array<Form>=[];
    for(form in program) switch(form) {
      case CDefine(name,body):
        if(name==null || name.length==0) fail("invalid definition name");
        forms.push(Define(name,raiseExpr(body,true)));
      case CExecute(body):
        forms.push(Evaluate(raiseExpr(body,true)));
    }
    return forms;
  }

  /** Reference-only CoreIR codegen bridge; no performance claim. */
  public static function compile(forms:Array<Form>):Value
    return BytecodeCompiler.compile(raise(lower(forms)));
}
