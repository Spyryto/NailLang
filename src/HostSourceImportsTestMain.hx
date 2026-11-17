import haxe.Json;
import nail.HostImportDeclarations;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.NType;
import nail.ResultValue;
import nail.Value;
import nail.Vm;

/** v0.53: host imports are source-level declarations, not ambient FFI. */
class HostSourceImportsTestMain {
  static var checks=0;
  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'SOURCE HOST IMPORTS: ' + label;
    checks++;
  }
  static function eq(a:Dynamic,b:Dynamic,label:String):Void
    ok(Json.stringify(a)==Json.stringify(b),
      label+' expected '+Json.stringify(b)+' got '+Json.stringify(a));
  static function fails(task:Void->Void, needle:String):Void {
    var message='';
    try task() catch(e:Dynamic) message=Std.string(e);
    ok(message.indexOf(needle)>=0, 'expected '+needle+' in '+message);
  }

  static function source():String return 'nail 0.53 ;\n'
    +'def first key = match readMany key with '
    +'| Ok xs -> head xs | Error why -> why ;\n'
    +'# Source imports can be placed at the end.\n'
    +'import fetchMany as readMany from NailHost : '
    +'Text -> CoreResult [ List [ Text ] , Text ] ;\n';

  static function listType():NType return
    TFunction(TText,TSum('CoreResult',[TList(TText),TText]));

  public static function main():Void {
    var extracted=HostImportDeclarations.extract(source(),true);
    eq(extracted.imports.length,1,'one declaration extracted');
    eq(extracted.imports[0].symbol,'fetchMany','host symbol');
    eq(extracted.imports[0].alias,'readMany','explicit local alias');
    ok(extracted.source.length==source().length,
      'erasure retains source offsets');
    ok(extracted.source.indexOf('def first')>=0 &&
      extracted.source.indexOf('from NailHost')<0,
      'erasure keeps ordinary Nail definitions');

    var spec:PublicSourceModuleSpec={
      name:'Songs',source:source(),exports:['first']
    };
    var image=ModuleImage.encode(ModuleLinker.compilePublic(spec));
    var decoded=ModuleImage.decode(image);
    eq(decoded.imports.length,1,'compiled image has one ordinary typed import');
    eq(decoded.imports[0].module,'NailHost','canonical host provider');
    eq(decoded.imports[0].symbol,'fetchMany','symbol survives compilation');
    eq(decoded.imports[0].alias,'readMany','alias survives compilation');
    var typed=new nail.TypeChecker();
    typed.importSignature('readMany',listType());
    eq(decoded.imports[0].signature,typed.signature('readMany'),
      'exact canonical signature derived from source');

    var grants=new HostTextGrants();
    var seen:Array<String>=[];
    grants.grantFunction('Songs','fetchMany',listType(),args -> {
      return switch(args[0]) {
        case Text(key):
          seen.push(key);
          key=='missing' ? ResultValue.error(Text('not-found')) :
            ResultValue.ok(Cons(Text('Jazz'),Cons(Text('Blues'),Nil)));
        case _: throw 'must be typed before callback';
      };
    });
    var linked=ModuleLinker.linkImages([image],40000000,grants);
    eq(Vm.toPlain(linked.invoke('Songs','first',Text('favorites'))),
      'Jazz','source-only host import invokes granted function');
    eq(Vm.toPlain(linked.invoke('Songs','first',Text('missing'))),
      'not-found','explicit Error path remains checked');
    eq(seen,['favorites','missing'],'callback called only for valid inputs');
    grants.revokeFunction('Songs','fetchMany');
    fails(() -> linked.invoke('Songs','first',Text('after')),
      'revoked function grant');

    var blank=new HostTextGrants();
    fails(() -> ModuleLinker.linkImages([image],40000000,blank),
      'missing function grant');

    var explicit:PublicSourceModuleSpec={
      name:'Duplicate',source:source(),exports:['first'],
      imports:[{module:'NailHost',symbol:'other',alias:'readMany',
        scheme:{term:listType(),quantified:[],comparable:[]}}]
    };
    fails(() -> ModuleLinker.compilePublic(explicit),
      'duplicate import alias');

    var before:PublicSourceModuleSpec={
      name:'Before',
      source:'nail 0.53 ; import greet from NailHost : Text -> Text ; '
        +'def greeting name = greet name ;',
      exports:['greeting']
    };
    var helloType=NType.TFunction(TText,TText);
    var g=new HostTextGrants();
    g.grantFunction('Before','greet',helloType,
      _ -> Text('hello'));
    var early=ModuleImage.encode(ModuleLinker.compilePublic(before));
    eq(Vm.toPlain(ModuleLinker.linkImages([early],40000000,g)
      .invoke('Before','greeting',Text('Nail'))),
      'hello','declaration also works before definitions');

    var same:PublicSourceModuleSpec={
      name:'Same',
      source:'nail 0.53 ; def greeting name = greet name ; '
        +'import greet from NailHost : Text -> Text ;',
      exports:['greeting']
    };
    var local=new HostTextGrants();
    local.grantFunction('Same','greet',helloType,_ -> Text('ok'));
    eq(Vm.toPlain(ModuleLinker.linkImages(
      [ModuleImage.encode(ModuleLinker.compilePublic(same))],
      40000000,local).invoke('Same','greeting',Text('x'))),
      'ok','alias defaults to imported symbol');

    var noTouch='nail 0.53 ; import next from Syntax ; '
      +'def t = " import fetchMany from NailHost : Text ; " ;';
    var noExtraction=HostImportDeclarations.extract(noTouch,true);
    eq(noExtraction.source,noTouch,
      'macro imports and quoted strings are left untouched');
    var text='nail 0.53 ; # import fake from NailHost : Text ;\n'
      +'def x = 1 ;';
    eq(HostImportDeclarations.extract(text,true).imports.length,0,
      'host import in a comment is ignored');

    var old=HostImportDeclarations.extract(source(),false);
    eq(old.source,source(),'old source is not rewritten');

    var rejects=[
      'nail 0.53 ; import missing from NailHost ;',
      'nail 0.53 ; import read from NailHost : Vector [ Text ] ;',
      'nail 0.53 ; import read from NailHost : List [ Text ;',
      'nail 0.53 ; import read from NailHost : Text -> ;'
    ];
    for (invalid in rejects)
      fails(() -> HostImportDeclarations.extract(invalid,true),
        'Host import:');
    trace('NailLang 0.53 typed source host imports: '+checks+' checks passed');
  }
}
