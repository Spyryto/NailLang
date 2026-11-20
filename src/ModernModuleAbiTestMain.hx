import haxe.Json;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.SourceModuleSpec;
import nail.ModuleLinker.InferredSourceModuleSpec;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.NType;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;
import numeric.FastNumber;
import numeric.LanguageVersion;

/** v0.48: independently compiled modern module numeric ABI on every target. */
class ModernModuleAbiTestMain {
  static var checks=0;
  static function ok(v:Bool,s:String):Void {
    if(!v) throw 'MODERN MODULE ABI: '+s;
    checks++;
  }
  static function equal(a:Dynamic,b:Dynamic,s:String):Void {
    ok(Json.stringify(a)==Json.stringify(b),
      s+' expected '+Json.stringify(b)+' got '+Json.stringify(a));
  }
  static function fails(f:Void->Void, needle:String):Void {
    var actual='';
    try f() catch (e:Dynamic) actual=Std.string(e);
    ok(actual.indexOf(needle)>=0,
      'expected error "'+needle+'" got "'+actual+'"');
  }
  static function src(version:String,body:String):String
    return 'nail '+version+' ;\n'+body;
  static function bare(name:String, body:String):InferredSourceModuleSpec
    return {name:name,source:src(LanguageVersion.CURRENT,body),
      imports:[],exports:[]};

  public static function main():Void {
    ok(LanguageVersion.supported('0.48'),'v0.48 source remains compatible');
    var source=src('0.48',
      'def beats = 4 ; def part = 1 / 3 ; def gain = 0.75 ;');
    var core:InferredSourceModuleSpec={
      name:'Core48', source:source, imports:[],
      exports:['beats','part','gain']
    };
    var first=ModuleLinker.compileInferred(core);
    ok(first.dialect=='modern' && first.sourceVersion=='0.48',
      'source version and numeric ABI are distinct metadata');
    equal([for(e in first.exports)e.signature],
      ['Int','Ratio','Float'],'inferred public numeric types');
    var image=ModuleImage.encode(first);
    var envelope:Dynamic=Json.parse(image);
    ok(Reflect.field(envelope,'format')==ModuleImage.RELATION_FORMAT,
      'all modern modules use runtime-module.v3');
    ok(Reflect.field(envelope,'numericAbi')==ModuleImage.MODERN_ABI,
      'v3 image records numerical ABI independently');
    ok(Reflect.field(envelope,'sourceVersion')=='0.48',
      'v3 module remembers actual source language');
    ok(image.indexOf('nailseed.postfix-image.v2')>=0,
      'module embeds validated, modern postfix bytecode');
    var imported=[
      {module:'Core48',symbol:'beats',alias:'core_beats',type:TInt},
      {module:'Core48',symbol:'part',alias:'core_part',type:TRatio},
      {module:'Core48',symbol:'gain',alias:'core_gain',type:TFloat}
    ];
    var client:InferredSourceModuleSpec={
      name:'Use48',
      source:src('0.48',
        'def total = core_beats + 38 ;'
        +' def fraction = core_part + ( 1 / 6 ) ;'
        +' def boosted = core_gain * 2.0 ;'),
      imports:imported,
      exports:['total','fraction','boosted']
    };
    var second=ModuleLinker.compileInferred(client);
    var linked=ModuleLinker.linkImages([
      ModuleImage.encode(second),image
    ]);
    equal(Vm.toPlain(linked.read('Use48','total')),
      'I:42/1','separately compiled Int import/export');
    equal(Vm.toPlain(linked.read('Use48','fraction')),
      'R:1/2','separately compiled exact Ratio import/export');
    equal(Vm.toPlain(linked.read('Use48','boosted')),
      1.5,'separately compiled Float import/export');
    ok(linked.signature('Use48','fraction')=='Ratio',
      'linker retains the correct public type');
    fails(() -> linked.read('Use48','core_part'),'does not export');
    var manual:SourceModuleSpec={
      name:'Manual48',
      source:src('0.48','def value = 7 / 2 ;'),
      imports:[], exports:[{name:'value',type:TRatio}]
    };
    equal(Vm.toPlain(ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compile(manual))
    ]).read('Manual48','value')),'R:7/2','explicit module manifest');

    // Int/Ratio/Float ABI is compatible across 0.45-0.48 source versions.
    var older=ModuleLinker.compileInferred({
      name:'Old45',
      source:src('0.45','def numerator = 9 ;'),
      imports:[],exports:['numerator']
    });
    var newer=ModuleLinker.compileInferred({
      name:'New47',
      source:src('0.47','def output = imported + 1 ;'),
      imports:[{module:'Old45',symbol:'numerator',alias:'imported',type:TInt}],
      exports:['output']
    });
    ok(older.sourceVersion=='0.45' && newer.sourceVersion=='0.47',
      'source-version metadata is preserved across modules');
    equal(Vm.toPlain(ModuleLinker.linkImages([
      ModuleImage.encode(newer),ModuleImage.encode(older)
    ]).read('New47','output')),'I:10/1',
      'compatible source versions link with same numeric ABI');

    // A concrete import typed incorrectly must fail *at link time*.
    var wrong=ModuleLinker.compileInferred({
      name:'Wrong48',
      source:src('0.48','def result = wrong_part + ( 1 / 6 ) ;'),
      imports:[{module:'Core48',symbol:'beats',alias:'wrong_part',type:TRatio}],
      exports:['result']
    });
    fails(() -> ModuleLinker.linkImages([
      image,ModuleImage.encode(wrong)
    ]),'import type mismatch');

    // Mixed legacy and modern modules cannot share numeric values, even
    // when a legacy source happens to use numbers with identical values.
    var legacy=ModuleLinker.compileInferred({
      name:'Legacy48',
      source:'def count = 4 ;',
      imports:[],exports:['count']
    });
    var mixed=ModuleLinker.compileInferred({
      name:'Mix48',source:src('0.48','def count = imported_count ;'),
      imports:[{module:'Legacy48',symbol:'count',alias:'imported_count',type:TInt}],
      exports:['count']
    });
    fails(() -> ModuleLinker.linkImages([
      ModuleImage.encode(legacy),ModuleImage.encode(mixed)
    ]),'incompatible numeric dialect');

    // Validate negative metadata, format, and downgrade/smuggling cases.
    function edited(edit:Dynamic->Void):String {
      var value:Dynamic=Json.parse(image);
      edit(value);
      return Json.stringify(value);
    }
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'numericAbi','int-ratio-float.v2'))),
      'incompatible numeric ABI');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.deleteField(x,'relationAbi'))),
      'incompatible relation ABI');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'format','nailseed.runtime-module.v2'))),
      'incompatible format');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'sourceVersion','0.56'))),
      'unsupported modern source version');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'format',ModuleImage.FORMAT))),
      'mixed legacy and modern metadata');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'bytecode',
        nail.BootstrapImage.encode(first.code)))),
      'incompatible modern bytecode format');
    fails(() -> ModuleImage.decode(edited(x ->
      Reflect.setField(x,'dialect','0.27'))),
      'incompatible numeric ABI');
    fails(() -> ModuleLinker.compile({
      name:'BadExport48',source:src('0.48','def item = 1 ;'),
      imports:[],exports:[{name:'item',type:TExact}]
    }), 'legacy Number/Exact type');
    fails(() -> ModuleLinker.compileInferred({
      name:'BadImport48',source:src('0.48','def item = bad ;'),
      imports:[{module:'Other',symbol:'item',alias:'bad',type:TNumber}],
      exports:['item']
    }), 'legacy Number/Exact type');
    fails(() -> ModuleLinker.compile({
      name:'WrongType48',source:src('0.48','def item = 1 / 2 ;'),
      imports:[],exports:[{name:'item',type:TInt}]
    }), 'export type mismatch');

    // Public HM schemes remain supported in the new format without
    // introducing relation-aware export signatures prematurely.
    var poly:PublicSourceModuleSpec={
      name:'Poly48',source:src('0.48','def identity x = x ;'),
      imports:[],exports:['identity']
    };
    var pol=ModuleLinker.compilePublic(poly);
    equal(pol.exports[0].signature,'a -> a',
      'public HM signature in modern v3 image');
    var ck=new TypeChecker();
    ck.check(poly.source);
    var sch=ck.publicScheme('identity');
    var consumer:PublicSourceModuleSpec={
      name:'UsePoly48',
      source:src('0.48','def chosen = foreign 12 ;'),
      imports:[{module:'Poly48',symbol:'identity',
        alias:'foreign',scheme:sch}],exports:['chosen']
    };
    var combo=ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compilePublic(consumer)),
      ModuleImage.encode(pol)
    ]);
    equal(Vm.toPlain(combo.read('UsePoly48','chosen')),
      'I:12/1','quantified HM module import with Int');
    fails(() -> ModuleLinker.compilePublic({
      name:'Constrained48',source:src('0.48',
        'def add x y : Add = x + y ;'),
      imports:[],exports:['add']
    }), 'relation-aware ABI');

    // Legacy ABIs remain readable until their consumers can be removed.
    ok(ModuleImage.encode(legacy).indexOf('runtime-module.v1')>=0,
      'legacy image keeps stable v1 transport');
    trace('NailLang v0.48 modern module ABI: '+checks+' checks passed');
  }
}
