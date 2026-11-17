import haxe.Json;
import nail.HostImportDeclarations;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.Value;
import nail.Vm;

/** Source imports use only explicitly supplied, checked compiled interfaces.
    Tests cover polymorphism, Eq evidence, Syntax, aliasing, missing interfaces,
    malformed public metadata, and link-time ABI verification. */
class ModuleSourceImportsTestMain {
  static var checks=0;
  static function ok(value:Bool, reason:String):Void {
    if (!value) throw 'MODULE SOURCE IMPORTS: '+reason;
    checks++;
  }
  static function eq(a:Dynamic,b:Dynamic,reason:String):Void
    ok(Json.stringify(a)==Json.stringify(b),
      reason+' expected '+Json.stringify(b)+' got '+Json.stringify(a));
  static function fails(f:Void->Void,expected:String):Void {
    var message='';
    try f() catch(e:Dynamic) message=Std.string(e);
    ok(message.indexOf(expected)>=0,
      'expected "'+expected+'" got "'+message+'"');
  }

  static function syntax():String return
    'nail 0.54 ; '
    +'def leaf kind value = syntaxLeaf kind value ; '
    +'def identity x = x ; '
    +'def same x y = x == y ;';

  static function client():String return
    'nail 0.54 ; '
    +'def create value = makeLeaf " Var " ( polyIdentity value ) ; '
    +'def compare value = polySame ( polyIdentity value ) value ; '
    +'import leaf as makeLeaf from Syntax ; '
    +'import identity as polyIdentity from Syntax ; '
    +'import same as polySame from Syntax ;';

  static function provider():String {
    var spec:PublicSourceModuleSpec={
      name:'Syntax',source:syntax(),
      exports:['leaf','identity','same']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  static function consumer(?image:String):String {
    var spec:PublicSourceModuleSpec={
      name:'User',source:client(),exports:['create','compare'],
      dependencies:image==null ? [] : [image]
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  public static function main():Void {
    var image=provider();
    var decoded=ModuleImage.decode(image);
    eq(decoded.exports.length,3,'public exports are retained');
    for (e in decoded.exports)
      ok(e.scheme!=null,'every modern public export has a typed scheme');
    ok(decoded.exports[0].signature.indexOf('Syntax')>=0,
      'exported leaf exposes a Syntax return type');
    ok(decoded.exports[1].scheme.quantified.length==1,
      'identity scheme retains quantified variable');
    ok(decoded.exports[2].scheme.comparable.length==1,
      'Eq constraint survives portable image');

    var extracted=HostImportDeclarations.extract(client(),true,true);
    eq(extracted.modules.length,3,'three source module imports');
    eq(extracted.imports.length,0,'normal imports are not host grants');
    eq(extracted.modules[0].module,'Syntax','provider is explicit');
    eq(extracted.modules[0].alias,'makeLeaf','alias is preserved');
    eq(extracted.source.length,client().length,'source offsets remain stable');
    ok(extracted.source.indexOf('from Syntax')<0,
      'compile-time imports are removed before source-free compilation');

    var user=consumer(image);
    var imported=ModuleImage.decode(user);
    eq(imported.imports.length,3,'image persists all checked imports');
    eq(imported.imports[0].signature,
      decoded.exports[0].signature,'consumer obtains provider canonical signature');
    var bundle=ModuleLinker.linkImages([user,image]);
    var node=Vm.toPlain(bundle.invoke('User','create',Text('x')));
    eq(node,{tag:'Var',value:'x'},'Syntax value travels across module boundary');
    eq(Vm.toPlain(bundle.invoke('User','compare',Text('a'))),true,
      'polymorphic Eq works for Text');
    eq(Vm.toPlain(bundle.invoke('User','compare',Boolean(true))),true,
      'same polymorphic import specializes independently for Bool');

    fails(() -> consumer(),'missing dependency interface Syntax');
    fails(() -> ModuleLinker.compilePublic({
      name:'Missing',source:'nail 0.54 ; def read x = missing x ; '
        +'import missing from Syntax ;',dependencies:[image],exports:['read']
    }), 'Syntax does not export missing');
    fails(() -> ModuleLinker.compilePublic({
      name:'BadAlias',source:client(),dependencies:[image],
      imports:[{module:'Syntax',symbol:'leaf',alias:'makeLeaf',
        scheme:decoded.exports[0].scheme}],
      exports:['create','compare']
    }), 'duplicate import alias');
    fails(() -> ModuleLinker.compilePublic({
      name:'WrongOwner',source:'nail 0.54 ; '
        +'def fake name = makeLeaf name name ; '
        +'import leaf as makeLeaf from Syntax ;',
      dependencies:[image,image],exports:['fake']
    }), 'duplicate or invalid dependency interface');

    var altered:Dynamic=Json.parse(image);
    var exports:Array<Dynamic>=cast Reflect.field(altered,'exports');
    Reflect.setField(exports[0],'signature','Text -> Text');
    fails(() -> ModuleImage.decode(Json.stringify(altered)),
      'canonical signature mismatch');

    var missingScheme:Dynamic=Json.parse(image);
    var omitted:Array<Dynamic>=cast Reflect.field(missingScheme,'exports');
    Reflect.deleteField(omitted[0],'scheme');
    var without=ModuleImage.decode(Json.stringify(missingScheme));
    ok(without.exports[0].scheme==null,'historic interfaces may lack a scheme');
    fails(() -> ModuleLinker.compilePublic({
      name:'NoScheme',
      source:'nail 0.54 ; def use x = makeLeaf " Var " x ; '
        +'import leaf as makeLeaf from Syntax ;',
      dependencies:[Json.stringify(missingScheme)],exports:['use']
    }), 'missing typed public scheme');

    // A dependency supplied during compilation is not automatically linked.
    fails(() -> ModuleLinker.linkImages([user]),
      'missing dependency Syntax');
    var changedProvider:Dynamic=Json.parse(image);
    var declared:Array<Dynamic>=cast Reflect.field(changedProvider,'exports');
    Reflect.setField(declared[0],'name','otherLeaf');
    var changed=ModuleImage.decode(Json.stringify(changedProvider));
    fails(() -> ModuleLinker.linkImages([user,
      ModuleImage.encode(changed)]),'missing exported definition otherLeaf');
    // A well-formed but incompatible provider is rejected separately.
    var changedType=ModuleImage.encode(ModuleLinker.compilePublic({
      name:'Syntax',source:'nail 0.54 ; '
        +'def leaf x = x ; def identity x = x ; '
        +'def same x y = x == y ;',
      exports:['leaf','identity','same']
    }));
    fails(() -> ModuleLinker.linkImages([user,changedType]),
      'import type mismatch');

    var noAlias='nail 0.54 ; def use x = identity x ; '
      +'import identity from Syntax ;';
    var shortSpec:PublicSourceModuleSpec={
      name:'Short',source:noAlias,dependencies:[image],exports:['use']
    };
    var shortImage=ModuleImage.encode(ModuleLinker.compilePublic(shortSpec));
    eq(Vm.toPlain(ModuleLinker.linkImages([shortImage,image])
      .invoke('Short','use',Text('hello'))),
      'hello','import alias defaults to exported name');
    trace('NailLang 0.54 source imports: '+checks+' checks passed');
  }
}
