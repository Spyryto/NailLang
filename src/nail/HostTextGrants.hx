package nail;

import haxe.ds.StringMap;
import nail.Value;
import nail.NType;

/** A deliberately narrow, per-module host grant table.
    Only the embedding host can construct this table and provide callbacks.
    The reserved NailHost provider is NOT a separately compiled Nail module.
    Grants are tied to module names, never ambient/global across VMs. */
class HostTextGrants {
  public static inline var PROVIDER = 'NailHost';
  public static inline var READ_TEXT = 'readText';
  /** Opt-in discriminated result, with an ABI fixed across compiled modules. */
  public static inline var READ_TEXT_RESULT = 'readTextResult';
  public static inline var WRITE_TEXT_RESULT = 'writeTextResult';
  public static inline var RESULT_SIGNATURE = 'Text -> CoreResult[Text, Text]';
  public static inline var WRITE_SIGNATURE = 'Text -> Text -> CoreResult[Text, Text]';
  // Canonical closed structural type checked against TypeChecker in CI.
  public static inline var READ_SIGNATURE =
    'Text -> {error: Text, ok: Bool, value: Text}';

  final readers:StringMap<TextReadCapability>;
  final writers:StringMap<TextWriteCapability>;
  final revokedReaders:StringMap<Bool>;
  final revokedWriters:StringMap<Bool>;
  /** All generic functions share the existing per-module grant boundary.
      There is no ambient FFI lookup or source-level host constructor. */
  final functions:StringMap<StringMap<HostFunctionGrant>>;
  final revokedFunctions:StringMap<Bool>;

  public function new() {
    readers = new StringMap<TextReadCapability>();
    writers = new StringMap<TextWriteCapability>();
    revokedReaders = new StringMap<Bool>();
    revokedWriters = new StringMap<Bool>();
    functions = new StringMap<StringMap<HostFunctionGrant>>();
    revokedFunctions = new StringMap<Bool>();
  }

  public function grantReadText(module:String, reader:TextReadCapability):Void {
    if (!ModuleImage.validName(module) || module == PROVIDER || reader == null)
      throw 'Host grants: invalid module or text reader';
    if (readers.exists(module))
      throw 'Host grants: duplicate text reader for module ' + module;
    readers.set(module, reader);
  }

  /** Write permission is a separate host grant with its own allowlist,
      scalar budget, and commit quota. A read grant never implies write. */
  public function grantWriteText(module:String, writer:TextWriteCapability):Void {
    if (!ModuleImage.validName(module) || module == PROVIDER || writer == null)
      throw 'Host grants: invalid module or text writer';
    if (writers.exists(module))
      throw 'Host grants: duplicate text writer for module ' + module;
    writers.set(module, writer);
  }

  /** Per-module revocation: previously captured imports still call the guard,
      so revocation works after linking. Another module may retain access
      even if the host intentionally shared the underlying capability object.
      These operations are idempotent and one-way. */
  public function revokeReadText(module:String):Void {
    if (!readers.exists(module))
      throw 'Host grants: missing text reader grant for ' + module;
    revokedReaders.set(module,true);
  }

  public function revokeWriteText(module:String):Void {
    if (!writers.exists(module))
      throw 'Host grants: missing text writer grant for ' + module;
    revokedWriters.set(module,true);
  }

  /** Register a synchronous, curried function under a statically checked
      Nail type. Inputs and returned values are validated at the boundary.
      No arbitrary Haxe/JS/PHP object passes into the portable VM.
      The budget counts attempted final invocations, including failures. */
  public function grantFunction(module:String, symbol:String, type:NType,
      callback:Array<Value>->Value, maxCalls:Int = 1024):Void {
    if (!ModuleImage.validName(module) || module == PROVIDER ||
        !ModuleImage.validName(symbol) || symbol == READ_TEXT ||
        symbol == READ_TEXT_RESULT || symbol == WRITE_TEXT_RESULT ||
        callback == null || maxCalls < 1 || maxCalls > 1000000)
      throw 'Host grants: invalid function grant';
    var checker = new TypeChecker();
    checker.importSignature('_hostGrant', type);
    var args:Array<NType> = [];
    var cursor = type;
    while (true) switch (cursor) {
      case TFunction(input,output):
        if (args.length >= 8 || !payloadType(input))
          throw 'Host grants: unsupported function input type';
        args.push(input);
        cursor = output;
      case _:
        if (args.length == 0 || !returnType(cursor))
          throw 'Host grants: unsupported function result type';
        break;
    }
    var bySymbol = functions.get(module);
    if (bySymbol == null) {
      bySymbol = new StringMap<HostFunctionGrant>();
      functions.set(module,bySymbol);
    }
    if (bySymbol.exists(symbol))
      throw 'Host grants: duplicate function for ' + module + '.' + symbol;
    bySymbol.set(symbol,{
      signature:checker.signature('_hostGrant'), args:args,
      result:cursor, invoke:callback, calls:0, maxCalls:maxCalls
    });
  }

  /** A function can be revoked after linking, even after partial application.
      Legacy specialized reader/writer grants retain their own revoke API. */
  public function revokeFunction(module:String, symbol:String):Void {
    var found=functions.get(module);
    if (found == null || !found.exists(symbol))
      throw 'Host grants: missing function grant for ' + module + '.' + symbol;
    revokedFunctions.set(module + '.' + symbol,true);
  }

  /** Host functions may exchange immutable linked lists, including nested
      lists and CoreResult payloads. The host cannot pass mutable vectors or
      nominal records: those need an ownership/copying contract first.
      Both type nesting and value traversal are bounded before invocation. */
  public static inline var MAX_HOST_VALUE_NODES = 4096;
  public static inline var MAX_HOST_VALUE_DEPTH = 8;

  static function payloadType(type:NType, depth:Int = 0):Bool {
    if (depth > MAX_HOST_VALUE_DEPTH) return false;
    return switch (type) {
      case TText | TBoolean | TInt | TRatio | TFloat: true;
      case TList(item): payloadType(item, depth + 1);
      case _: false;
    };
  }

  static function returnType(type:NType):Bool return switch (type) {
    case TSum('CoreResult', types) if (types.length == 2):
      payloadType(types[0]) && payloadType(types[1]);
    case _: payloadType(type);
  };

  static function validValue(type:NType, value:Value):Bool
    return validWithBudget(type, value, [0], 0);

  /** Reject improper tails, mixed-type cells, and unbounded/cyclic data.
      A shared node counter bounds long as well as nested lists. The loop
      walks list tails iteratively, avoiding stack growth for flat lists. */
  static function validWithBudget(type:NType, value:Value,
      budget:Array<Int>, depth:Int):Bool {
    if (value == null || depth > MAX_HOST_VALUE_DEPTH) return false;
    budget[0]++;
    if (budget[0] > MAX_HOST_VALUE_NODES) return false;
    return switch (type) {
      case TText: switch(value) {case Text(_): true; case _: false;}
      case TBoolean: switch(value) {case Boolean(_): true; case _: false;}
      case TInt: switch(value) {
        case IntNumber(number):
          try numeric.FastNumber.isInteger(number) catch (_:Dynamic) false;
        case _: false;
      }
      case TRatio: switch(value) {
        case RatioNumber(number):
          try {
            numeric.FastNumber.encodeExact(number);
            true;
          } catch (_:Dynamic) false;
        case _: false;
      }
      case TFloat: switch(value) {case Number(n): Math.isFinite(n); case _: false;}
      case TList(item):
        var cursor = value;
        var complete = false;
        var permitted = true;
        while (permitted && !complete) {
          switch (cursor) {
            case Nil: complete = true;
            case Cons(head, tail):
              if (!validWithBudget(item, head, budget, depth + 1))
                permitted = false;
              else {
                budget[0]++;
                if (budget[0] > MAX_HOST_VALUE_NODES) permitted = false;
                else cursor = tail;
              }
            case _: permitted = false;
          }
        }
        permitted && complete;
      case TSum('CoreResult', types) if (types.length == 2):
        try {
          var tag = ResultValue.tag(value);
          validWithBudget(tag == ResultValue.OK ? types[0] : types[1],
            ResultValue.get(value, tag), budget, depth + 1);
        } catch (_:Dynamic) false;
      case _: false;
    };
  }

  function resolveFunction(consumer:String, symbol:String, requested:String):Value {
    var bySymbol=functions.get(consumer);
    var found=bySymbol == null ? null : bySymbol.get(symbol);
    if (found == null)
      throw 'Host grants: missing function grant for ' + consumer + '.' + symbol;
    if (requested != found.signature)
      throw 'Host grants: capability type mismatch for ' + consumer;
    var key=consumer + '.' + symbol;
    function stage(captured:Array<Value>):Value {
      var index=captured.length;
      return HostFunction('host-function-' + symbol, arg -> {
        if (revokedFunctions.exists(key))
          throw 'Host grants: revoked function grant for ' + key;
        if (!validValue(found.args[index],arg))
          throw 'Host grants: invalid function argument for ' + key;
        var values=captured.concat([arg]);
        if (values.length != found.args.length) return stage(values);
        if (found.calls >= found.maxCalls)
          throw 'Host grants: invocation quota exhausted for ' + key;
        found.calls++;
        var output:Value;
        try output=found.invoke(values)
        catch (_:Dynamic) throw 'Host grants: host callback failed';
        if (!validValue(found.result,output))
          throw 'Host grants: invalid function result for ' + key;
        return output;
      });
    }
    return stage([]);
  }

  /** Resolve only an explicitly requested and statically compatible import.
      The grant is scoped to the *consumer module*, including when the host
      links several consumers with different allowlists. */
  public function resolve(consumer:String, symbol:String, requested:String):Value {
    var actual:String = switch (symbol) {
      case READ_TEXT: READ_SIGNATURE;
      case READ_TEXT_RESULT: RESULT_SIGNATURE;
      case WRITE_TEXT_RESULT: WRITE_SIGNATURE;
      case _: return resolveFunction(consumer,symbol,requested);
    };
    if (requested != actual)
      throw 'Host grants: capability type mismatch for ' + consumer;
    if (symbol == WRITE_TEXT_RESULT) {
      var writer = writers.get(consumer);
      if (writer == null)
        throw 'Host grants: missing text writer grant for ' + consumer;
      if (revokedWriters.exists(consumer))
        throw 'Host grants: revoked text writer grant for ' + consumer;
      // The outer HostFunction must always return a callable (curried ABI),
      // including when revocation happens between the two applications.
      return HostFunction('write-text-key-guarded', key -> {
        var staged = writer.writeKey(key);
        return HostFunction('write-text-content-guarded', content -> {
          if (revokedWriters.exists(consumer))
            return ResultValue.error(Text('revoked'));
          return switch (staged) {
            case HostFunction(_, invoke): invoke(content);
            case _: throw 'Host grants: invalid staged writer';
          };
        });
      });
    }
    var reader = readers.get(consumer);
    if (reader == null)
      throw 'Host grants: missing text reader grant for ' + consumer;
    if (revokedReaders.exists(consumer))
      throw 'Host grants: revoked text reader grant for ' + consumer;
    return HostFunction('read-text-guarded', key -> {
      if (revokedReaders.exists(consumer))
        return symbol == READ_TEXT
          ? TextReadCapability.revokedOutcome()
          : ResultValue.error(Text('revoked'));
      return symbol == READ_TEXT ? reader.read(key) : reader.readResult(key);
    });
  }
}

/** Private typed grant, shared by host function wrappers and quota logic. */
private typedef HostFunctionGrant = {
  var signature:String;
  var args:Array<NType>;
  var result:NType;
  var invoke:Array<Value>->Value;
  var calls:Int;
  var maxCalls:Int;
}
