package nail;

import haxe.ds.StringMap;
import nail.Value;

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

  public function new() {
    readers = new StringMap<TextReadCapability>();
    writers = new StringMap<TextWriteCapability>();
    revokedReaders = new StringMap<Bool>();
    revokedWriters = new StringMap<Bool>();
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

  /** Resolve only an explicitly requested and statically compatible import.
      The grant is scoped to the *consumer module*, including when the host
      links several consumers with different allowlists. */
  public function resolve(consumer:String, symbol:String, requested:String):Value {
    var actual:String = switch (symbol) {
      case READ_TEXT: READ_SIGNATURE;
      case READ_TEXT_RESULT: RESULT_SIGNATURE;
      case WRITE_TEXT_RESULT: WRITE_SIGNATURE;
      case _: throw 'Host grants: unsupported capability ' + symbol;
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
