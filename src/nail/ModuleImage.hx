package nail;

import haxe.Json;
import nail.Value;
import nail.TypeRelation.RelationContract;

/** Import contracts stored in a compiled module's public interface.
    Text signatures are canonicalized by the Haxe type checker at build time. */
typedef LinkedModuleImport = {
  var module:String;
  var symbol:String;
  var alias:String;
  var signature:String;
  @:optional var relation:RelationContract;
}

typedef LinkedModuleExport = {
  var name:String;
  var signature:String;
  @:optional var relation:RelationContract;
}

/** A self-contained separately compiled unit: source is not needed to link. */
typedef CompiledModule = {
  var name:String;
  var dialect:String;
  /** Source declaration, present for modern numeric modules only. */
  @:optional var sourceVersion:String;
  var imports:Array<LinkedModuleImport>;
  var exports:Array<LinkedModuleExport>;
  var code:Value;
}

/** Portable module image. Compilation is a trusted build step; decoding
    validates metadata and bytecode envelope, but is not a cryptographic
    authenticity check or a replacement for type checking source. */
class ModuleImage {
  public static inline var FORMAT = 'nailseed.runtime-module.v1';
  /** Modern separately compiled module format, independently versioned
      from compiler bootstrap images and source-language versions. */
  public static inline var MODERN_FORMAT = 'nailseed.runtime-module.v2';
  /** v3 extends modern numeric module images with finite type relations.
      v2 images without constrained interfaces remain decodable and linkable. */
  public static inline var RELATION_FORMAT = 'nailseed.runtime-module.v3';
  public static inline var RELATION_ABI = 'finite-relations.v1';
  public static inline var MODERN_ABI = 'int-ratio-float.v1';
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

  static function validSourceVersion(version:String):Bool
    return numeric.LanguageVersion.supported(version);

  /** Canonical, typed representation of a verified finite relation.
      Signatures are checked against this metadata, never trusted alone. */
  static function encodeRelation(contract:RelationContract):Dynamic {
    var safe=TypeRelation.validate(contract);
    return {
      name:safe.name,
      rows:[for (row in safe.rows) [for (type in row) TypeRelation.typeName(type)]]
    };
  }

  static function decodeRelation(raw:Dynamic, signed:String, versioned:Bool)
      :Null<RelationContract> {
    if (raw == null) {
      if (StringTools.startsWith(signed,'relation:'))
        throw 'Module image: relation signature requires relation metadata';
      return null;
    }
    if (!versioned)
      throw 'Module image: relation metadata requires v3 ABI';
    if (!Std.isOfType(Reflect.field(raw,'name'),String) ||
        !Std.isOfType(Reflect.field(raw,'rows'),Array))
      throw 'Module image: malformed relation metadata';
    var sourceRows:Array<Dynamic>=cast Reflect.field(raw,'rows');
    if (sourceRows.length == 0 || sourceRows.length > TypeRelation.MAX_ROWS)
      throw 'Module image: invalid relation rows';
    var rows:Array<Array<String>>=[];
    for (row in sourceRows) {
      if (!Std.isOfType(row,Array))
        throw 'Module image: invalid relation row';
      var types:Array<Dynamic>=cast row;
      if (types.length < 2 || types.length > TypeRelation.MAX_ARITY+1)
        throw 'Module image: invalid relation arity';
      var names:Array<String>=[];
      for (value in types) {
        if (!Std.isOfType(value,String))
          throw 'Module image: invalid relation type name';
        names.push(cast value);
      }
      rows.push(names);
    }
    var contract=TypeRelation.decode(cast Reflect.field(raw,'name'),rows);
    if (TypeRelation.abiSignature(contract) != signed)
      throw 'Module image: relation signature mismatch';
    return contract;
  }

  public static function encode(module:CompiledModule):String {
    var modern = module.dialect == 'modern';
    var relations=false;
    for (item in module.imports)
      if (item.relation != null) relations=true;
    for (item in module.exports)
      if (item.relation != null) relations=true;
    if (relations && !modern)
      throw 'Module image: relation metadata requires modern numeric ABI';
    if (modern && !validSourceVersion(module.sourceVersion))
      throw 'Module image: unsupported modern source version';
    if (!modern && module.dialect != '0.27' && module.dialect != '0.29')
      throw 'Module image: unsupported numeric dialect';
    var program = modern ? BootstrapImage.encodeModern(module.code)
      : module.dialect == '0.29' ? ExactImage.encode(module.code)
      : BootstrapImage.encode(module.code);
    var data:Dynamic = {
      format:relations ? RELATION_FORMAT : modern ? MODERN_FORMAT : FORMAT,
      name:module.name,
      dialect:module.dialect,
      imports:[for (item in module.imports) {
        module:item.module, symbol:item.symbol,
        alias:item.alias, signature:item.signature,
        relation:item.relation == null ? null : encodeRelation(item.relation)
      }],
      exports:[for (item in module.exports)
        {name:item.name, signature:item.signature,
         relation:item.relation == null ? null : encodeRelation(item.relation)}],
      bytecode:program
    };
    if (modern) {
      // A module ABI has its own version: 0.45/0.46/0.47 source programs
      // share the same Int/Ratio/Float runtime representation.
      Reflect.deleteField(data,'dialect');
      Reflect.setField(data,'numericAbi',MODERN_ABI);
      Reflect.setField(data,'sourceVersion',module.sourceVersion);
      if (relations) Reflect.setField(data,'relationAbi',RELATION_ABI);
    }
    return Json.stringify(data);
  }

  public static function decode(encoded:String):CompiledModule {
    if (encoded == null || encoded.length > 16000000)
      throw 'Module image: exceeds size limit';
    var data:Dynamic;
    try data = Json.parse(encoded)
    catch (e:Dynamic) throw 'Module image: invalid JSON';
    var format = data == null ? null : Reflect.field(data, 'format');
    var relational=format == RELATION_FORMAT;
    var modern = format == MODERN_FORMAT || relational;
    if (format != FORMAT && !modern)
      throw 'Module image: incompatible format';
    var name = requireName(Reflect.field(data, 'name'), 'module name');
    if (name == HostTextGrants.PROVIDER)
      throw 'Module image: reserved host provider name';
    var version:String;
    var sourceVersion:Null<String> = null;
    if (modern) {
      if (Reflect.hasField(data,'dialect') ||
          Reflect.field(data,'numericAbi') != MODERN_ABI)
        throw 'Module image: incompatible numeric ABI';
      var versionField:Dynamic=Reflect.field(data,'sourceVersion');
      if (!Std.isOfType(versionField,String) ||
          !validSourceVersion(cast versionField))
        throw 'Module image: unsupported modern source version';
      if (relational) {
        if (Reflect.field(data,'relationAbi') != RELATION_ABI)
          throw 'Module image: incompatible relation ABI';
      } else if (Reflect.hasField(data,'relationAbi'))
        throw 'Module image: relation metadata requires v3 ABI';
      sourceVersion=cast versionField;
      version='modern';
    } else {
      if (Reflect.hasField(data,'numericAbi') ||
          Reflect.hasField(data,'sourceVersion') ||
          Reflect.hasField(data,'relationAbi'))
        throw 'Module image: mixed legacy and modern metadata';
      version = dialect(Reflect.field(data, 'dialect'));
    }
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
      var signed=signature(Reflect.field(item,'signature'));
      imports.push({
        module:requireName(Reflect.field(item, 'module'), 'import module'),
        symbol:requireName(Reflect.field(item, 'symbol'), 'import symbol'),
        alias:alias, signature:signed,
        relation:decodeRelation(Reflect.field(item,'relation'),signed,relational)
      });
    }
    for (item in exportsRaw) {
      if (item == null) throw 'Module image: invalid export';
      var label = requireName(Reflect.field(item, 'name'), 'export name');
      if (exportNames.exists(label)) throw 'Module image: duplicate export ' + label;
      exportNames.set(label, true);
      if (importAliases.exists(label))
        throw 'Module image: cannot export an imported alias ' + label;
      var signed=signature(Reflect.field(item,'signature'));
      exports.push({
        name:label, signature:signed,
        relation:decodeRelation(Reflect.field(item,'relation'),signed,relational)
      });
    }
    if (relational) {
      var has=false;
      for (item in imports) if (item.relation != null) has=true;
      for (item in exports) if (item.relation != null) has=true;
      if (!has) throw 'Module image: unused relation ABI';
    }
    var rawCode:Dynamic = Reflect.field(data, 'bytecode');
    if (!Std.isOfType(rawCode, String))
      throw 'Module image: invalid bytecode payload';
    if (modern && !BootstrapImage.isModernImage(cast rawCode))
      throw 'Module image: incompatible modern bytecode format';
    if (!modern && BootstrapImage.isModernImage(cast rawCode))
      throw 'Module image: modern bytecode in legacy module';
    var code = version == '0.29'
      ? ExactImage.decode(cast rawCode)
      : BootstrapImage.decode(cast rawCode);
    // Never allow a v1 envelope to carry modern numeric literals, or
    // the modern ABI to disguise values of the obsolete Exact domain.
    var stack:Array<Value> = [code];
    while (stack.length > 0) switch (stack.pop()) {
      case SyntaxLeaf('ExactNumber', _) if (modern || version == '0.27'):
        throw 'Module image: legacy ExactNumber literal incompatible with numeric ABI';
      case SyntaxLeaf('Int', _) | SyntaxLeaf('Ratio', _) if (!modern):
        throw 'Module image: modern numeric literal in legacy module';
      case SyntaxNode(_, items): stack.push(items);
      case Cons(a, b): stack.push(a); stack.push(b);
      case _:
    }
    return {
      name:name, dialect:version, sourceVersion:sourceVersion,
      imports:imports, exports:exports, code:code
    };
  }
}
