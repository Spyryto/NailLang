import haxe.Json;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.TypeChecker;
import nail.TypeRelation;
import nail.Value;
import nail.Vm;

/** Verified finite relation contracts survive separate compilation/linking. */
class RelationModuleAbiTestMain {
  static var checks=0;
  static function ok(pass:Bool,label:String):Void {
    if (!pass) throw 'RELATION MODULE ABI: '+label;
    checks++;
  }
  static function eq(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+' got '+Json.stringify(actual)+' expected '+Json.stringify(expected));
  static function fails(f:Void->Void,message:String):Void {
    var actual='';
    try f() catch(e:Dynamic) actual=Std.string(e);
    ok(actual.indexOf(message)>=0,
      'expected "'+message+'" got "'+actual+'"');
  }
  static function source(body:String):String return 'nail 0.49 ;\n'+body;

  public static function main():Void {
    var provider:PublicSourceModuleSpec={
      name:'Functions',
      source:source(
        'Square : Int Int ; Square : Ratio Ratio ; Square : Float Float ; '
        +'Triple : Int Int Int Int ; Triple : Float Float Float Float ; '
        +'def square x : Square = x * x ; '
        +'def triple x y z : Triple = x * y + z ;'),
      imports:[],exports:['square','triple']
    };
    var compiled=ModuleLinker.compilePublic(provider);
    ok(compiled.dialect=='modern' && compiled.exports.length==2,
      'public constrained functions compile in isolation');
    ok(compiled.exports[0].relation!=null &&
      TypeRelation.arity(compiled.exports[0].relation)==1,
      'unary relation rows exported with typed metadata');
    ok(compiled.exports[1].relation!=null &&
      TypeRelation.arity(compiled.exports[1].relation)==3,
      'ternary relation rows exported with typed metadata');
    var encoded=ModuleImage.encode(compiled);
    var raw:Dynamic=Json.parse(encoded);
    ok(Reflect.field(raw,'format')==ModuleImage.RELATION_FORMAT,
      'relation-bearing module image uses runtime-module.v3');
    ok(Reflect.field(raw,'relationAbi')==ModuleImage.RELATION_ABI,
      'module ABI has independent relation version');
    var parsed=ModuleImage.decode(encoded);
    eq(parsed.exports[0].signature,
      TypeRelation.abiSignature(compiled.exports[0].relation),
      'serialized typed contract matches canonical signature');

    var client:PublicSourceModuleSpec={
      name:'Consumer',
      source:source(
        'def four = remoteSquare 2 ; '
        +'def quarter = remoteSquare ( 1 / 2 ) ; '
        +'def mix = remoteTriple 2 3 4 ; '
        +'def floating = remoteTriple 2.0 3.0 4.0 ;'),
      imports:[
        {module:'Functions',symbol:'square',alias:'remoteSquare',
          relation:compiled.exports[0].relation},
        {module:'Functions',symbol:'triple',alias:'remoteTriple',
          relation:compiled.exports[1].relation}
      ],
      exports:['four','quarter','mix','floating']
    };
    var clientArtifact=ModuleLinker.compilePublic(client);
    var bundle=ModuleLinker.linkImages([
      ModuleImage.encode(clientArtifact),encoded
    ]);
    eq(Vm.toPlain(bundle.read('Consumer','four')),'I:4/1',
      'imported unary relation evaluates Int');
    eq(Vm.toPlain(bundle.read('Consumer','quarter')),'R:1/4',
      'imported unary relation evaluates Ratio');
    eq(Vm.toPlain(bundle.read('Consumer','mix')),'I:10/1',
      'imported ternary relation evaluates Int');
    eq(Vm.toPlain(bundle.read('Consumer','floating')),10,
      'imported ternary relation evaluates Float');
    ok(clientArtifact.imports[0].relation!=null,
      'consumer image retains imported relation metadata');
    ok(bundle.signature('Functions','square').indexOf('relation:Square/1:')==0,
      'ABI signature retains relation name and arity');

    function corrupted(change:Dynamic->Void):String {
      var data:Dynamic=Json.parse(encoded);
      change(data);
      return Json.stringify(data);
    }
    fails(() -> ModuleImage.decode(corrupted(d ->
      Reflect.setField(d,'sourceVersion','0.48'))),
      'requires Nail 0.49');
    fails(() -> ModuleImage.decode(corrupted(d ->
      Reflect.setField(d,'relationAbi','finite-relations.v2'))),
      'incompatible relation ABI');
    fails(() -> ModuleImage.decode(corrupted(d ->
      Reflect.setField(d,'format',ModuleImage.MODERN_FORMAT))),
      'relation metadata requires v3 ABI');
    fails(() -> ModuleImage.decode(corrupted(d -> {
      var exports:Array<Dynamic>=cast Reflect.field(d,'exports');
      var relation:Dynamic=Reflect.field(exports[0],'relation');
      Reflect.setField(relation,'rows',[['Int','Float']]);
    })), 'relation signature mismatch');
    fails(() -> ModuleImage.decode(corrupted(d -> {
      var exports:Array<Dynamic>=cast Reflect.field(d,'exports');
      Reflect.setField(exports[0],'relation',null);
    })), 'requires relation metadata');
    fails(() -> ModuleImage.decode(corrupted(d -> {
      var exports:Array<Dynamic>=cast Reflect.field(d,'exports');
      var relation:Dynamic=Reflect.field(exports[0],'relation');
      Reflect.setField(relation,'rows',[['Int','Int'],['Int','Float']]);
    })), 'duplicate input types');

    var narrow=TypeRelation.validate({name:'Square',rows:[[nail.NType.TInt,nail.NType.TInt]]});
    var incompatible:PublicSourceModuleSpec={
      name:'WrongConsumer',
      source:source('def result = remoteSquare 3 ;'),
      imports:[{module:'Functions',symbol:'square',alias:'remoteSquare',
        relation:narrow}],
      exports:['result']
    };
    fails(() -> ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compilePublic(incompatible)),
      encoded
    ]), 'import type mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'OldImporter',
      source:'nail 0.48 ; def answer = remoteSquare 3 ;',
      imports:[{module:'Functions',symbol:'square',alias:'remoteSquare',
        relation:compiled.exports[0].relation}],
      exports:['answer']
    }), 'require Nail 0.49');
    // A v2 numeric module with monomorphic types can coexist in a graph;
    // relation-bearing exports are only in v3.
    var plain=ModuleLinker.compilePublic({
      name:'Plain49',source:source('def x = 3 ;'),imports:[],exports:['x']
    });
    ok(ModuleImage.encode(plain).indexOf('runtime-module.v2')>=0,
      'unconstrained module retains the smaller v2 image');
    trace('NailLang 0.49 relation module ABI: '+checks+' checks passed');
  }
}
