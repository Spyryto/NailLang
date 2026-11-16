# NailSeed v0.38 — first host capability slice

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

## Next acceptance boundaries

- Capability imports in separately compiled module manifests, with host
  signatures verified at link time and no ambient fallback.
- Typed `Result`-style capability outcome and compositional IO programs.
- Write capability with explicit separate authorization and safe atomicity.
- Concrete filesystem and HTTP adapters scoped to named resources, with
  time/resource budgets; never bundle network or host access in VM defaults.


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
limits and blocking operations. This slice does not provide capability
revocation, audit hooks, asynchronous execution, concrete filesystem/HTTP
adapters, arbitrary host function signatures or a cross-module nominal
`Result` type.

For typed applications, the capability outcome is already a structural
record with a checked failure channel. Applications can convert that to a
local `Result` ADT if desired; sharing generic algebraic sum identities
across compiled modules remains a separate language milestone.

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

**Remaining v0.38 work:** separate write grants, explicit failure/
resource budgets for write adapters, module identity authentication and
general user-defined nominal sum identity (the latter may fit v0.39).
