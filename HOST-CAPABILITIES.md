# NailLang host capabilities — v0.38 to v0.39

This snapshot is independent from `v0.37`. It introduces **explicit,
read-only host capabilities** as first-class functions. The Nail compiler,
five expression forms and bytecode instruction set do not change.

## Threat boundary

A Nail program has **no ambient file reader**, network access, filesystem
path API, or source-level constructor for a host capability. The embedding
application elects to grant a function under a name such as `readAsset`.
The function carries a *host-defined allowlist* of resource identifiers and
a resolver callback. Unapproved names never reach the resolver.

`TextReadCapability` is a minimal cross-target interface, not a sandbox
for the host itself: the host must implement a trustworthy, bounded resolver
(e.g. a named virtual file store, or a carefully restricted file adapter).
This slice does **not** implement real filesystem traversal, HTTP, writes,
timeouts for blocking callbacks, cancellation, or resource quotas beyond
the returned Unicode scalar count. In particular the callback runs with the
host's privileges: never pass untrusted callbacks to it.

## Programming interface

An injected `readAsset` has the monomorphic type

```
Text -> {error: Text, ok: Bool, value: Text}
```

This is a *closed structural record*, reusing v0.35, with an explicit
recoverable status. The allowed error codes are `denied`, `missing`,
`too-large` and `backend-failure`. Backend exception messages are never
returned. Responses are immutable source values; users can branch or
project as usual.

```nail
def readOrExplain key =
  let result = readAsset key in
  if result . ok then result . value else result . error ;

readOrExplain " song " ;
```

The embedding Haxe application grants the capability to a **single VM**:

```haxe
var resources = new haxe.ds.StringMap<String>();
resources.set('song', 'Jazz 🪕');
var reader = new nail.TextReadCapability(
  ['song'], key -> resources.get(key), 65536);
var checker = new nail.TypeChecker();
checker.importSignature('readAsset', nail.TextReadCapability.signature());
checker.check(source);

var runtime = new nail.BootRuntime();
runtime.grantTextReader('readAsset', reader);
var output = runtime.runPlain(source);
```

Other hosts can construct exactly the same callback in JS or PHP emitted
from Haxe. Haxe AST and bytecode VMs also expose `grantTextReader`.
The host chooses the alias, allowlist, resolver, and maximum Unicode
scalar length (1..1,000,000; 65,536 default).

Capability values are function values (`Value.HostFunction`), *not* text
tokens, source constructs, opcodes or names of host primitives. They cannot
be fabricated in Nail, are not embedded in portable bytecode images, and
cannot be converted to the JSON-friendly `Vm.toPlain` format.

## Acceptance tests

```sh
haxe seed-image.hxml
haxe host-capabilities-test-interp.hxml
haxe host-capabilities-test-js.hxml && node build/tests/host-capabilities.js
haxe host-capabilities-test-php.hxml && php build/tests/php-host-capabilities/index.php
haxe rebootstrap-image.hxml
```

The suite covers permitted reads, denial before calling the resolver,
missing/too-long content, sanitized backend failures, no-grant rejection,
alias validation, Hindley–Milner type errors, VM/bytecode/compiler parity
and source-free bootstrapping across Haxe/JS/PHP.

## First-tranche acceptance list (historical)

The first tranche identified capability imports, a typed `Result` outcome,
a separately authorized writer, and concrete file/network adapters as follow-up
work. The first three are implemented in tranches two through four below.
Concrete filesystem/HTTP adapters, authenticated module identities, revocation
and host execution-time budgets remain unimplemented.


## Second v0.38 slice — separately compiled modules

Compiled Nail modules can now request an explicitly named, typed host read
capability through the **existing module manifest and image format v1**:
the provider `NailHost` is reserved by the runtime and is never a Nail module.

```haxe
var spec:nail.ModuleLinker.PublicSourceModuleSpec = {
  name:'Songs',
  source:'def load key = let r = readAsset key in '
    + 'if r . ok then r . value else r . error ;',
  imports:[{
    module:'NailHost', symbol:'readText', alias:'readAsset',
    scheme:{term:nail.TextReadCapability.signature(),
      quantified:[], comparable:[]}
  }],
  exports:['load']
};
var image = nail.ModuleImage.encode(nail.ModuleLinker.compilePublic(spec));

var grants = new nail.HostTextGrants();
grants.grantReadText('Songs',
  new nail.TextReadCapability(['setlist'], key -> 'Swing 🪕'));
var linked = nail.ModuleLinker.linkImages([image], 25000000, grants);
var result = linked.invoke('Songs','load',nail.Value.Text('setlist'));
```

The canonical ABI is `Text -> {error: Text, ok: Bool, value: Text}`.
The linker validates the image's requested signature **exactly**, rejecting
missing, mismatched and unsupported host capabilities. The host can authorize
each consumer module independently. A name denied by the reader's allowlist
never reaches the resolver. Old module images and `linkImages(images)` work
unchanged; by default host capabilities are **not granted**.

No module can be named `NailHost` (including manually modified JSON
images). The provider is not included in dependency resolution, cannot be
forged by exporting an ordinary Nail symbol, and does not create a global
reader for all modules. A module that has a grant can explicitly expose
a public function that uses it; downstream modules can call that function
only through a declared typed import. **This is intentional delegation.**

**Important trust condition:** the host must authenticate or otherwise
trust the compiled module image before granting authority by module name.
Image decoding is structural validation, *not* cryptographic integrity;
an attacker able to replace the `Songs` image could exercise the same grant.
Host callbacks themselves remain responsible for sandboxing, resource
limits and blocking operations. This second tranche did not yet provide capability revocation, audit
hooks, asynchronous execution, concrete filesystem/HTTP adapters, arbitrary
host function signatures or a cross-module nominal `CoreResult` type.
`CoreResult` was subsequently introduced in the third tranche below.

The legacy capability outcome is a structural record with a checked failure
channel. The third tranche below adds the optional `readTextResult` import
using the shared `CoreResult` type without breaking that legacy interface.

```sh
haxe seed-image.hxml
haxe module-host-grants-test-interp.hxml
haxe module-host-grants-test-js.hxml && node build/tests/module-host-grants.js
haxe module-host-grants-test-php.hxml && php build/tests/php-module-host-grants/index.php
```


## Third v0.38 slice — built-in shared `CoreResult[a, e]`

Nail now has a **standard generic algebraic sum with a non-conflicting core name** with a fixed ABI identity
and constructors `CoreOk` and `CoreErr`. It is available everywhere,
including in imported/exported module signatures, without a source-level
`type Result` declaration. Both branches are checked exhaustively:

```nail
def describe key =
  match readAsset key with
  | CoreOk contents -> contents
  | CoreErr reason -> reason ;
```

The optional host import `NailHost.readTextResult` has canonical type

```
Text -> CoreResult[Text, Text]
```

The previous `NailHost.readText` and the per-VM `grantTextReader` keep their
existing, **binary-compatible** structural record response. The result-based
alternative shares the same allowlist, Unicode output budget and sanitized
error semantics; only its return representation differs. The host can opt
into it in a compiled module manifest:

```haxe
var spec:nail.ModuleLinker.PublicSourceModuleSpec = {
  name:'Songs',
  source:'def load key = readAsset key ;',
  imports:[{module:'NailHost', symbol:'readTextResult',
    alias:'readAsset', scheme:{
      term:nail.TextReadCapability.resultSignature(),
      quantified:[], comparable:[]
    }}],
  exports:['load']
};
var image = nail.ModuleImage.encode(nail.ModuleLinker.compilePublic(spec));
var grants = new nail.HostTextGrants();
grants.grantReadText('Songs',
  new nail.TextReadCapability(['song'], key -> 'Swing 🪕'));
var linked = nail.ModuleLinker.linkImages([image], 25000000, grants);
```

A second separately compiled module can import `Songs.load` with
`Text -> CoreResult[Text, Text]` and use a normal exhaustive `match` over
`CoreOk` and `CoreErr`. The linker compares canonical signatures
exactly; a consumer cannot silently reinterpret the payload types.
Type inference also handles polymorphic functions that construct or match
the standard `Result`. A module may export such functions with the normal
quantified public-scheme interface.

Internally `Result` uses the already existing immutable nominal sum record
format (`$type = CoreResult`, `#tag`, `#0`). The VM validates the tag and
payload envelope before executing its built-in predicates and getters.
No new expression variant, bytecode instruction, or module-image version is
needed. Public export of **other** algebraic sum types is still explicitly
rejected: this introduces one fixed shared standard type, not a general ABI
for arbitrary user-defined nominal sums. The constructors are not effectful
and do not confer host authority.

The capability cannot be made safe merely by checking its type signature:
module image authenticity, host callback sandboxing and revocation remain
embedder responsibilities.

```sh
haxe seed-image.hxml
haxe shared-result-test-interp.hxml
haxe shared-result-test-js.hxml && node build/tests/shared-result.js
haxe shared-result-test-php.hxml && php build/tests/php-shared-result/index.php
haxe rebootstrap-image.hxml
```

**After the third tranche:** separate writer authorization was the next
milestone; the fourth tranche below implements it with a host callback
contract. Module identity authentication, robust execution-time budgets and
general user-defined nominal sum identity are still future milestones.


## v0.39 — separate controlled text writes

A module can request the **opt-in, write-only host import**
`NailHost.writeTextResult` with the following canonical curried type:

```text
Text -> Text -> CoreResult[Text, Text]
```

The first argument is a named resource key; the second is its complete
replacement text. On success the host returns `CoreOk key`. On expected
failure it returns `CoreErr reason`, where the reason is one of
`denied`, `invalid-text`, `too-large`, `quota-exhausted`, `not-committed`,
`busy` (reentrant call), or `backend-failure`. Host exception messages
are suppressed.

A standalone Nail program can write without adding I/O primitives to
the language:

```nail
def save key contents =
  match writeAsset key contents with
  | CoreOk savedKey -> savedKey
  | CoreErr why -> why ;
```

An embedding host grants authority **separately per consumer module**:

```haxe
var stored = new haxe.ds.StringMap<String>();
stored.set('song', 'old text');
var writer = new nail.TextWriteCapability(
  ['song'],
  (key, value) -> {
    // Virtual in-memory resource: one synchronous complete replacement.
    stored.set(key, value);
    return true;
  },
  65536, 128 // max Unicode scalars per write; max successful commits
);
var manifest:nail.ModuleLinker.PublicSourceModuleSpec = {
  name:'Composer',
  source:'def save value = writeAsset " song " value ;',
  imports:[{module:'NailHost', symbol:'writeTextResult',
    alias:'writeAsset', scheme:{
      term:nail.TextWriteCapability.signature(),
      quantified:[], comparable:[]
    }}],
  exports:['save']
};
var image = nail.ModuleImage.encode(
  nail.ModuleLinker.compilePublic(manifest));
var grants = new nail.HostTextGrants();
grants.grantWriteText('Composer', writer);
var linked = nail.ModuleLinker.linkImages([image], 25000000, grants);
```

A `grantReadText` does **not** authorize `writeTextResult` and a
`grantWriteText` does **not** authorize `readText` or
`readTextResult`. Resource names are allowlisted before the host callback.
Text is measured in Unicode scalar values using an early-exit scan that
does not allocate an array for oversized payloads. Invalid Unicode scalars
return `invalid-text` without calling the host, and a quota counts *successful*
commits only. Disallowed, too-long, quota-exhausted or reentrant calls never
reach the host's replacement callback. Rejected/exceptional callbacks
return sanitized, typed errors. Both the AST VM and the bytecode VM support
direct grants via `grantTextWriter`; source-free `BootRuntime` does too.
No global `writeFile`, filesystem path, network primitive, opcode or
module-image version is added.

### Atomicity is a contract on the embedding host

**The capability cannot guarantee atomic file writes by itself.**
Its callback `replaceAtomically(key, text):Bool` must obey all of the
following for a concrete resource: on `true`, publish a complete replacement
exactly once; on `false` or an exception, leave the resource untouched;
never expose intermediate partial content. For physical files, the embedder
would typically write to a temporary file on the same filesystem, flush
as required, then atomically rename into place using target-appropriate APIs.
Crash durability, directory sync, concurrent writes, timeouts and path
traversal protection are also host responsibilities, and their guarantees
vary by OS and filesystem. **No concrete disk adapter is bundled in this
tranche**, so do not assume durable, crash-safe or cross-process atomic
writes merely because a callback was provided. A callback that mutates a
file and then throws violates the contract; the capability cannot undo it.

The quota is scoped to the particular `TextWriteCapability` instance,
including when several modules deliberately share that instance. A grant
alone does not imply safe concurrency, cancellation or robust transaction
isolation. The resource store's initial contents and visibility rules
remain host-controlled. Compiled module images must be trusted before
binding host grants, as in the previous tranche.

```sh
haxe seed-image.hxml
haxe host-text-writes-test-interp.hxml
haxe host-text-writes-test-js.hxml && node build/tests/host-text-writes.js
haxe host-text-writes-test-php.hxml && php build/tests/php-host-text-writes/index.php
```

Tests cover read/write privilege separation, module-level typed imports,
quota and scalar boundaries, denied writes before callback invocation,
callback rejection and exception sanitization, reentrancy prevention,
source-free compiler parity and an in-memory atomic replacement fixture.

**Remaining work:** authenticated/verified module identity before granting
capabilities, production-ready filesystem/HTTP adapters with explicit
platform-specific security policies, write revocation, cancellation and
concurrency control. These are not implicitly supplied by the Nail VM.

## v0.40 — host-pinned compiled-module integrity

Prior versions authorized a separately compiled module by its **self-declared name**.
Any actor able to replace an image and keep that name could gain an existing
`HostTextGrants` entry. The v0.40 introduces an explicit, **opt-in**
image-allowlist boundary before decoding, linking and VM initialization.

```haxe
var saverImage = nail.ModuleImage.encode(nail.ModuleLinker.compilePublic(spec));
var digest = nail.ModuleImageTrust.sha256(saverImage);
// The HOST must obtain this digest from a trusted release/deployment manifest,
// stored separately from the untrusted bundle being loaded.
var trust = new nail.ModuleImageTrust();
trust.pin('Saver', trustedDigestFromDeployment);
var linked = nail.ModuleLinker.linkTrustedImages(
  [untrustedSaverImage], trust, 25000000, grants);
```

All required images must be pinned. The linker hashes each **exact serialized
image string** using SHA-256 and compares it with an independently supplied
pin, then validates the decoded module's name. It rejects unknown, missing,
duplicated, substituted and misnamed artifacts **before any module can use a
host callback**. The complete module set is verified before linking starts.
Input ordering does not affect the result.

**Critical:** this is a digest-based integrity check, NOT a digital signature,
not provenance authentication, and not verification of authorship. If an
attacker controls both the image and its expected hash, the policy is useless.
Trust pins must be obtained through a separate trusted channel (e.g. a
version-controlled manifest or a trusted application build). No private key
is involved. SHA-256 cannot prove source-level type safety of bytecode from
a malicious *approved* builder; only approve artifacts from a trusted
compiler/build process.

The old `linkImages` and `link` methods still exist for backwards
compatibility and DO NOT perform this pin check. Hosts authorizing untrusted
modules **must** use `linkTrustedImages`, never derive their pins directly
from the bundle they receive. Update/revocation requires constructing a new
trust policy and runtime; existing linked closures are not invalidated.

```sh
haxe seed-image.hxml
haxe trusted-module-images-test-interp.hxml
haxe trusted-module-images-test-js.hxml && node build/tests/trusted-module-images.js
haxe trusted-module-images-test-php.hxml && php build/tests/php-trusted-module-images/index.php
```

Future work: signature verification with trusted publisher keys and key
rotation, an authenticated distribution manifest, revocation and time limits
for host callbacks, and concrete secure filesystem/network adapters.

## v0.41 — revocable read and write capability grants

The host can now withdraw access **after a module has been linked**
without replacing the entire module bundle:

```haxe
grants.revokeReadText('ReaderA');
grants.revokeWriteText('WriterA');
```

Each `HostTextGrants` import is returned as a guarded `HostFunction`
which checks the module's own one-way revocation flag on **every call**.
Unlike revoking a shared capability instance, per-module revocation leaves
other explicitly granted modules operational even when they share the same
reader/writer object. Attempting to link a *new* module using an already
revoked grant fails. An already-linked invocation returns the existing
recoverable result type: `CoreErr "revoked"` or, for legacy
`readText`, a structural outcome with `ok=false` and `error="revoked"`.

The embedding host can also revoke an entire **capability instance**:

```haxe
reader.revoke();
writer.revoke();
```

All direct or shared `TextReadCapability` and `TextWriteCapability`
instances capture this state. Even a writer closure acquired through the
**first curried application** before revocation checks again on the final
content argument, before invoking the host callback. Instance revocation
also works with direct AST VM, ByteVm and source-free BootRuntime grants.

Revocations are irreversible and idempotent for the same grant or
instance. There is no ambient Nail operation to undo them. Re-granting
requires new capability/grant objects and a new runtime.

**Limits:** This protects subsequent invocations, not work already started:
synchronous in-flight host callbacks cannot be interrupted or rolled back,
and no async cancellation or filesystem transaction guarantee is supplied.
A host callback already running can commit even if revocation occurs while
it runs. Readers and writers provided outside the guarded API must be
managed independently by the embedding host. Trusted module image pins
(v0.40) and revocable host functions solve distinct problems.

```sh
haxe seed-image.hxml
haxe revocable-capabilities-test-interp.hxml
haxe revocable-capabilities-test-js.hxml && node build/tests/revocable-capabilities.js
haxe revocable-capabilities-test-php.hxml && php build/tests/php-revocable-capabilities/index.php
```

Remaining milestones include cryptographic publisher signatures
(public-key verification), controlled real filesystem/HTTP adapters,
resource/time budgets for host callbacks and asynchronous cancellation.
