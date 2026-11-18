package nail;

import haxe.ds.StringMap;
import nail.Value;

/** Supplies source text only; all module parsing and macro binding/expansion
    is performed by functions compiled from stdlib.nail. The host merely
    discovers transitive module keys in Nail-produced Syntax. */
class NailMacroModuleInputs {
  public static function parsedModern(runtime:BootRuntime, source:String):Value {
    return runtime.invoke('modernRewrite',
      runtime.invoke('parseSource',Text(source)));
  }

  /** A resolver is called at most once per logical module key. We mark
      keys before visiting imports so cycles are discovered in Nail's
      nmModuleExports, without recursive host expansion or host parsing. */
  public static function collect(runtime:BootRuntime, mainSource:String,
      resolver:Null<String->Null<String>>, ?mainProgram:Value):Value {
    var modules:Array<Value> = [];
    if (resolver == null) return SyntaxNode('NMModules', Nil);
    var visited = new StringMap<Bool>();
    var count = 0;

    function visit(program:Value):Void {
      switch (program) {
        case SyntaxNode('Program',forms):
          var rest = forms;
          while (true) switch (rest) {
            case Nil: break;
            case Cons(form, tail):
              rest = tail;
              switch (form) {
                case SyntaxNode('Define', Cons(SyntaxLeaf('Name', label),
                    Cons(SyntaxLeaf('Var', moduleName), Nil)))
                    if (StringTools.startsWith(label, MacroExpander.IMPORT)):
                  if (!visited.exists(moduleName)) {
                    visited.set(moduleName,true);
                    if (++count > 256) throw 'Macro module discovery limit exceeded';
                    var source = resolver(moduleName);
                    if (source != null) {
                      MacroModuleDialect.requireCompatible(
                        numeric.LanguageVersion.declared(mainSource),
                        numeric.NumericDialect.isExact(mainSource), source,
                        moduleName);
                      var parsed = parsedModern(runtime,source);
                      modules.push(SyntaxNode('TCBinding',Cons(
                        SyntaxLeaf('TCName',moduleName),
                        Cons(parsed, Nil))));
                      visit(parsed);
                    }
                  }
                case _:
              }
            case _: throw 'Invalid Nail Program form list';
          }
        case SyntaxLeaf('Error', _):
          // A malformed source is rejected by Nail's parser/checker,
          // not repaired by the module discovery layer.
        case _: throw 'Expected Nail-parsed Program';
      }
    }

    visit(mainProgram == null ? parsedModern(runtime,mainSource) : mainProgram);
    var entries:Value = Nil;
    var i = modules.length;
    while (i > 0) entries=Cons(modules[--i],entries);
    return SyntaxNode('NMModules',entries);
  }

  public static function request(program:Value, modules:Value):Value
    return SyntaxNode('NMRequest',Cons(program,Cons(modules,Nil)));
}
