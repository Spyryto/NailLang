package nail;

import haxe.Json;
import nail.Value;

/** Import contracts stored in a compiled module's public interface.
    Text signatures are canonicalized by the Haxe type checker at build time. */
typedef LinkedModuleImport = {
  var module:String;
  var symbol:String;
  var alias:String;
  var signature:String;
}

typedef LinkedModuleExport = {
  var name:String;
  var signature:String;
}

/** A self-contained separately compiled unit: source is not needed to link. */
typedef CompiledModule = {
  var name:String;
  var dialect:String;
  var imports:Array<LinkedModuleImport>;
  var exports:Array<LinkedModuleExport>;
  var code:Value;
}

/** Portable module image. Compilation is a trusted build step; decoding
    validates metadata and bytecode envelope, but is not a cryptographic
    authenticity check or a replacement for type checking source. */
class ModuleImage {
  public static inline var FORMAT = 'nailseed.runtime-module.v1';
  static final identifier = ~/^[A-Za-z_][A-Za-z_0-9]*$/;

  public static function validName(name:String):Bool
    return name != null && identifier.match(name);

  static function requireName(raw:Dynamic, role:String):String {
    if (!Std.isOfType(raw, String) || !validName(cast raw))
      throw 'Module image: invalid ' + role;
    return cast raw;
  }

  static function signature(raw:Dynamic):String {
    if (!Std.isOfType(raw, String)) throw 'Module image: invalid signature';
    var value:String = cast raw;
    if (value.length == 0 || value.length > 1024)
      throw 'Module image: invalid signature';
    return value;
  }

  static function dialect(value:Dynamic):String {
    if (value != '0.27' && value != '0.29')
      throw 'Module image: unsupported numeric dialect';
    return cast value;
  }

  public static function encode(module:CompiledModule):String {
    var program = module.dialect == '0.29'
      ? ExactImage.encode(module.code)
      : BootstrapImage.encode(module.code);
    var data = {
      format:FORMAT,
      name:module.name,
      dialect:module.dialect,
      imports:[for (item in module.imports) {
        module:item.module, symbol:item.symbol,
        alias:item.alias, signature:item.signature
      }],
      exports:[for (item in module.exports)
        {name:item.name, signature:item.signature}],
      bytecode:program
    };
    return Json.stringify(data);
  }

  public static function decode(encoded:String):CompiledModule {
    if (encoded == null || encoded.length > 16000000)
      throw 'Module image: exceeds size limit';
    var data:Dynamic;
    try data = Json.parse(encoded)
    catch (e:Dynamic) throw 'Module image: invalid JSON';
    if (data == null || Reflect.field(data, 'format') != FORMAT)
      throw 'Module image: incompatible format';
    var name = requireName(Reflect.field(data, 'name'), 'module name');
    if (name == HostTextGrants.PROVIDER)
      throw 'Module image: reserved host provider name';
    var version = dialect(Reflect.field(data, 'dialect'));
    var rawImports:Dynamic = Reflect.field(data, 'imports');
    var rawExports:Dynamic = Reflect.field(data, 'exports');
    if (!Std.isOfType(rawImports, Array) || !Std.isOfType(rawExports, Array))
      throw 'Module image: invalid interface lists';
    var imports:Array<LinkedModuleImport> = [];
    var exports:Array<LinkedModuleExport> = [];
    var importAliases = new haxe.ds.StringMap<Bool>();
    var exportNames = new haxe.ds.StringMap<Bool>();
    var importsRaw:Array<Dynamic> = cast rawImports;
    var exportsRaw:Array<Dynamic> = cast rawExports;
    if (importsRaw.length > 512 || exportsRaw.length > 512)
      throw 'Module image: interface size limit exceeded';
    for (item in importsRaw) {
      if (item == null) throw 'Module image: invalid import';
      var alias = requireName(Reflect.field(item, 'alias'), 'import alias');
      if (importAliases.exists(alias)) throw 'Module image: duplicate import alias ' + alias;
      importAliases.set(alias, true);
      imports.push({
        module:requireName(Reflect.field(item, 'module'), 'import module'),
        symbol:requireName(Reflect.field(item, 'symbol'), 'import symbol'),
        alias:alias,
        signature:signature(Reflect.field(item, 'signature'))
      });
    }
    for (item in exportsRaw) {
      if (item == null) throw 'Module image: invalid export';
      var label = requireName(Reflect.field(item, 'name'), 'export name');
      if (exportNames.exists(label)) throw 'Module image: duplicate export ' + label;
      exportNames.set(label, true);
      if (importAliases.exists(label))
        throw 'Module image: cannot export an imported alias ' + label;
      exports.push({
        name:label,
        signature:signature(Reflect.field(item, 'signature'))
      });
    }
    var rawCode:Dynamic = Reflect.field(data, 'bytecode');
    if (!Std.isOfType(rawCode, String))
      throw 'Module image: invalid bytecode payload';
    var code = version == '0.29'
      ? ExactImage.decode(cast rawCode)
      : BootstrapImage.decode(cast rawCode);
    // A legacy module must never smuggle exact literal tags through a v1
    // bytecode image even if the generic v1 structural decoder accepts them.
    if (version == '0.27') {
      var stack:Array<Value> = [code];
      while (stack.length > 0) switch (stack.pop()) {
        case SyntaxLeaf('ExactNumber', _):
          throw 'Module image: exact literal in legacy module';
        case SyntaxNode(_, items): stack.push(items);
        case Cons(a, b): stack.push(a); stack.push(b);
        case _:
      }
    }
    return {
      name:name, dialect:version, imports:imports,
      exports:exports, code:code
    };
  }
}
