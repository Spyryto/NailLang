package nail;

import haxe.ds.StringMap;
import nail.NType;
import nail.Value;

/**
 * Read-only resource capability. The host chooses both the allowlist and
 * resolver; Nail never receives a filesystem path or an ambient file API.
 * A resolver may read files, call an API, or be a deterministic test fixture.
 */
class TextReadCapability {
  final allowed:StringMap<Bool>;
  final resolver:String->Null<String>;
  final maxScalars:Int;

  public function new(names:Array<String>, resolve:String->Null<String>,
      maxScalars:Int = 65536) {
    if (names == null || resolve == null || maxScalars < 1 || maxScalars > 1000000)
      throw 'Invalid text reader capability configuration';
    allowed = new StringMap<Bool>();
    for (name in names) {
      if (name == null || !~/^[A-Za-z][A-Za-z0-9_-]*$/.match(name)
          || allowed.exists(name))
        throw 'Invalid or duplicate resource name';
      allowed.set(name, true);
    }
    this.resolver = resolve;
    this.maxScalars = maxScalars;
  }

  /** Closed, field-sorted structural type suitable for TypeChecker.importSignature.
      No special type or VM opcode is required for this first capability slice. */
  public static function signature():NType return TFunction(TText, TStructural([
    {name:'error', type:TText},
    {name:'ok', type:TBoolean},
    {name:'value', type:TText}
  ]));

  /** Opt-in v0.38 Result outcome. Legacy readText keeps its closed-record ABI. */
  public static function resultSignature():NType
    return TFunction(TText, TSum(ResultValue.OWNER, [TText, TText]));

  static function outcome(ok:Bool, value:String, error:String):Value {
    var fields = new StringMap<Value>();
    fields.set('error', Text(error));
    fields.set('ok', Boolean(ok));
    fields.set('value', Text(value));
    return Record('#struct', fields);
  }

  /** This method is invoked only by the injected HostFunction value.
      Denied resource identifiers never reach the resolver. */
  public function read(arg:Value):Value {
    var name = switch (arg) {
      case Text(v): v;
      case _: throw 'Text read capability requires a Text resource key';
    };
    if (!allowed.exists(name)) return outcome(false, '', 'denied');
    try {
      var result = resolver(name);
      if (result == null) return outcome(false, '', 'missing');
      if (UnicodeText.length(result) > maxScalars)
        return outcome(false, '', 'too-large');
      return outcome(true, result, '');
    } catch (_:Dynamic) {
      // Do not leak host exception messages, path names, or stack traces.
      return outcome(false, '', 'backend-failure');
    }
  }

  /** Reuses the same authorization and error handling as the v0.38
      structural API; changes only the result's representation. */
  public function readResult(arg:Value):Value {
    return switch (read(arg)) {
      case Record(_, fields):
        switch ([fields.get('ok'), fields.get('value'), fields.get('error')]) {
          case [Boolean(true), Text(value), Text(_)]: ResultValue.ok(Text(value));
          case [Boolean(false), Text(_), Text(reason)]: ResultValue.error(Text(reason));
          case _: throw 'Invalid text capability outcome';
        }
      case _: throw 'Invalid text capability outcome';
    };
  }

  public function asResultValue():Value return HostFunction('read-text-result', readResult);

  public function asValue():Value return HostFunction('read-text', read);
}
