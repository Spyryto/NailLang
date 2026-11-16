package nail;

import haxe.Json;
import haxe.crypto.Sha256;
import nail.BootRuntime;
import nail.BootstrapImage;

/** A reproducible, source-level fixed point for the v0.14 structured ByteVM.
    All compilation below goes through the Nail-written compileSource function.
    No Haxe parser/compiler is invoked here. */
class Rebootstrap {
  public static function records(image:String):String {
    // Canonical comparison of ordered postfix instructions rather than JSON
    // object member order (which could vary across compilation targets).
    var document:Dynamic = Json.parse(image);
    var rows:Dynamic = Reflect.field(document, 'records');
    if (!Std.isOfType(rows, Array)) throw 'Invalid image tape';
    return Json.stringify(rows);
  }

  public static function fingerprint(image:String):String {
    return Sha256.encode(records(image));
  }

  public static function regenerate(seedImage:String, source:String, maxSteps:Int = 250000000):String {
    var runtime = new BootRuntime(maxSteps, seedImage);
    var program = runtime.compile(source);
    switch (program) {
      case SyntaxNode('Bytecode', _):
      case SyntaxLeaf(tag, message):
        throw 'Self-compiler returned leaf ' + tag + ': ' + message;
      case SyntaxNode(tag, _):
        throw 'Self-compiler returned node ' + tag + ' instead of Bytecode';
      case _:
        throw 'Self-compiler returned non-Syntax value';
    }
    var rebuilt = BootstrapImage.encode(program);
    // Decode validates arities, stack balance, and the Bytecode root.
    BootstrapImage.decode(rebuilt);
    return rebuilt;
  }

  /** Rebuild using Nail once, then rebuild again from the newly built image.
      At a valid fixed point, Haxe stage zero, Nail stage one and Nail stage two
      have exactly the same ordered tape (and SHA-256 fingerprint). */
  public static function verify(seedImage:String, source:String, maxSteps:Int = 250000000):String {
    BootstrapImage.decode(seedImage);
    var next = regenerate(seedImage, source, maxSteps);
    var firstTape = records(seedImage);
    var secondTape = records(next);
    if (firstTape != secondTape) throw difference('Stage 0 (Haxe) vs stage 1 (Nail)', firstTape, secondTape);
    var third = regenerate(next, source, maxSteps);
    var thirdTape = records(third);
    if (secondTape != thirdTape) throw difference('Stage 1 vs stage 2 (Nail)', secondTape, thirdTape);
    return next;
  }

  static function difference(where:String, expected:String, actual:String):String {
    var pos = 0;
    var limit = expected.length < actual.length ? expected.length : actual.length;
    while (pos < limit && expected.charCodeAt(pos) == actual.charCodeAt(pos)) pos++;
    var a = expected.substr(pos, 100);
    var b = actual.substr(pos, 100);
    return 'Non-reproducible bootstrap at ' + where + ', offset ' + pos
      + ' (lengths ' + expected.length + ' vs ' + actual.length + ')'
      + '\nHaxe/previous: ' + a + '\nNail/next: ' + b;
  }
}