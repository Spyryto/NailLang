import haxe.Json;
import haxe.Resource;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.Value;
import numeric.LanguageVersion;

/** Full public API smoke test of the versioned **published** compiler image.
    Runs without using the Haxe source parser, including on Node/PHP. */
class OfficialBootstrapTestMain {
  static var count = 0;
  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'OFFICIAL BOOTSTRAP: '+label;
    count++;
  }
  static function same(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+' got '+Json.stringify(actual)+' expected '+Json.stringify(expected));
  static function fails(run:Void->Void, text:String):Void {
    var actual='';
    try run() catch (e:Dynamic) actual=Std.string(e);
    ok(actual.indexOf(text)>=0,'expected "'+text+'" but got "'+actual+'"');
  }
  static function modern(body:String):String
    return 'nail '+LanguageVersion.CURRENT+' ;\n'+body;

  public static function main():Void {
    var seed=Resource.getString('bootstrap_image');
    ok(seed!=null,'embedded image exists');
    ok(BootstrapImage.isModernImage(seed),'source-free compiler image is v2');
    var raw:Dynamic=Json.parse(seed);
    ok(Reflect.field(raw,'format')==BootstrapImage.MODERN_FORMAT,
      'image format is independent from language version');
    ok(Reflect.field(raw,'languageVersion')==LanguageVersion.CURRENT,
      'language semantic requirement recorded');
    var image=BootstrapImage.decode(seed);
    ok(image!=null,'modern image decodes');
    var vm=new BootRuntime(35000000);
    same(vm.runPlain(modern('1 / 3 + 1 / 6 ;')),
      ['R:1/2'],'exact rational arithmetic in published image');
    same(new BootRuntime(35000000).runPlain(
      modern('def add x y : Add = x + y ; add 1 41 ;')),
      ['I:42/1'],'v0.47 closed relation annotation source compilation');
    same(new BootRuntime(35000000).runPlain(
      'nail 0.46 ; 2 / 5 ;'),['R:2/5'],
      'compatible v0.46 source runs on v0.47 VM');
    same(new BootRuntime(35000000).runPlain(
      'nail 0.45 ; 2 / 5 ;'),['R:2/5'],
      'compatible v0.45 source runs on v0.47 VM');
    same(new BootRuntime(35000000).runPlain(
      modern('textLength " ciao " ;')),['I:4/1'],
      'Nail compiler uses Int for textLength');

    // Older bootstrap decoders reject the new image at the format gate.
    fails(() -> BootstrapImage.decode(Json.stringify({
      format:BootstrapImage.MODERN_FORMAT, languageVersion:'0.61',
      records:Reflect.field(raw,'records')
    })), 'language version');
    fails(() -> BootstrapImage.decode(Json.stringify({
      format:'nailseed.postfix-image.v3',
      languageVersion:LanguageVersion.CURRENT,
      records:Reflect.field(raw,'records')
    })), 'format');
    fails(() -> new BootRuntime(35000000).runPlain(
      'nail 0.61 ; 1 ;'), 'Unsupported Nail language version');
    var legacy=BootstrapImage.encode(image);
    ok(!BootstrapImage.isModernImage(legacy),
      'new image marker is not silently added to legacy envelope');
    // The encoding itself stays deterministic at the record tape level.
    same(Reflect.field(Json.parse(legacy),'records'),
      Reflect.field(raw,'records'), 'v1/v2 have identical postfix tape');

    trace('NailLang v0.47 modern published bootstrap: '+count+' checks passed');
  }
}
