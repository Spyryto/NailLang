package nail;

import haxe.ds.StringMap;
import nail.NType;
import nail.Value;

/**
 * Explicit, write-only, synchronous text resource capability.
 *
 * The embedding host MUST provide an atomic replacement callback: it must
 * leave the existing resource untouched on false/exception, and make a
 * complete new value visible exactly once before returning true. This
 * wrapper validates input and authorization but CANNOT make an arbitrary
 * host callback transactional, durable, isolated or cancellable.
 */
class TextWriteCapability {
  final allowed:StringMap<Bool>;
  final replaceAtomically:String->String->Bool;
  final maxScalars:Int;
  final maxCommits:Int;
  var successful:Int = 0;
  var inCommit:Bool = false;
  var revoked:Bool = false;

  public function new(names:Array<String>, replaceAtomically:String->String->Bool,
      maxScalars:Int = 65536, maxCommits:Int = 128) {
    if (names == null || replaceAtomically == null ||
        maxScalars < 1 || maxScalars > 1000000 ||
        maxCommits < 1 || maxCommits > 1000000)
      throw 'Invalid text writer capability configuration';
    allowed = new StringMap<Bool>();
    for (name in names) {
      if (name == null || !~/^[A-Za-z][A-Za-z0-9_-]*$/.match(name)
          || allowed.exists(name))
        throw 'Invalid or duplicate resource name';
      allowed.set(name, true);
    }
    this.replaceAtomically = replaceAtomically;
    this.maxScalars = maxScalars;
    this.maxCommits = maxCommits;
  }

  /** Permanently revoke this instance, including any previously acquired
      partially applied write functions. No in-flight synchronous host callback
      can be retroactively rolled back. */
  public function revoke():Void revoked = true;

  /** A curried, closed, canonical cross-module signature. */
  public static function signature():NType
    return TFunction(TText,
      TFunction(TText, TSum(ResultValue.OWNER, [TText, TText])));

  static function error(reason:String):Value return ResultValue.error(Text(reason));

  /** Validate resource name at first application. No host access occurs until
      the second argument has passed the limits and permission checks. */
  public function writeKey(arg:Value):Value {
    var key = switch (arg) {
      case Text(value): value;
      case _: throw 'Text write capability requires a Text resource key';
    };
    return HostFunction('write-text-content', contents -> writeContent(key, contents));
  }

  function writeContent(key:String, arg:Value):Value {
    var contents = switch (arg) {
      case Text(value): value;
      case _: throw 'Text write capability requires Text content';
    };
    if (revoked) return error('revoked');
    if (!allowed.exists(key)) return error('denied');
    // Reentrant callbacks must not mutate a shared resource store recursively.
    if (inCommit) return error('busy');
    var fits = false;
    try {
      fits = UnicodeText.fitsScalarBudget(contents, maxScalars);
    } catch (_:Dynamic) {
      // A malformed Text (e.g. a lone UTF-16 surrogate on JS) is not
      // allowed to escape into the host replacement callback.
      return error('invalid-text');
    }
    if (!fits) return error('too-large');
    if (successful >= maxCommits) return error('quota-exhausted');
    var committed = false;
    inCommit = true;
    try {
      committed = replaceAtomically(key, contents);
    } catch (_:Dynamic) {
      inCommit = false;
      // Never reveal host exception strings or filesystem paths to Nail.
      return error('backend-failure');
    }
    inCommit = false;
    if (!committed) return error('not-committed');
    successful++;
    return ResultValue.ok(Text(key));
  }

  public function asValue():Value return HostFunction('write-text-key', writeKey);
}
