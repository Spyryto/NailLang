# NailSeed v0.14 — Source-free runtime bootstrap

NailSeed v0.14 keeps the language, its five expression AST constructors, and the structured bytecode of v0.13 unchanged. It changes **how the runtime is started**.

## Main idea

The Haxe parser/compiler are necessary to **build** the initial standard-library image, but the minimal shipped JavaScript/PHP executables can start entirely from that **precompiled image**. They then use the **Nail-written** `parseSource` and `compileSource` functions (now stored as bytecode) to compile and run user programs. The runtime does not invoke the Haxe source parser on that path.

```
Build-time only:
  stdlib.nail -> Haxe Parser -> Haxe reference BytecodeCompiler
              -> portable postfix bootstrap-image.json

Runtime:
  embedded bootstrap-image.json -> BootstrapImage.decode -> ByteVm.run
                                 -> Nail parseSource / compileSource
                                 -> ByteVm.run(user bytecode)
```

The image format is a flat postorder JSON tape: `["L", tag, text]` for Syntax leaves and `["N", tag, numberOfChildren]` for Syntax nodes. Both encoder and decoder are iterative and validate the structure. The image is generated, never hand-edited, and is **not** a new Nail source or bytecode instruction format.

## Build (Haxe 4.3.7)

From `v0.14/`:

```sh
haxe seed-image.hxml
haxe boot-test-interp.hxml
haxe boot-test-js.hxml && node build/tests/boot.js
haxe boot-test-php.hxml && php build/tests/php-boot/index.php
haxe boot-js.hxml
haxe boot-php.hxml
```

In a Node project, use the generated `build/boot/js/nailseed-boot.js`:

```js
const { NailSeedBoot } = require('./build/boot/js/nailseed-boot.js');
const boot = NailSeedBoot.create();
console.log(boot.runPlain('def square x = x * x ; square 9 ;')); // [81]
```

In PHP CLI:

```sh
php build/boot/php/index.php example.nail
```

GitHub Actions builds the image first, tests the source-free interpreter across Haxe `--interp`, JavaScript and PHP, runs historical regression tests, and uploads both compiled distributions and the generated image.

## Deliberate boundaries

- The original AST interpreter, type checker and Haxe parser still exist in this **source repository** for comparison and the legacy API. The **new bootstrap-only distribution** uses `-D nail_seed_only` (host `Vm.run()` explicitly disabled) and does not rely on them for source parsing.
- The first stage is not yet fully self-hosting: **the initial image is generated using the Haxe reference parser/compiler at build time**. Rebuilding from absolutely no image still requires the Haxe stage.
- There is no new lexer, surface syntax, bytecode opcode or user-visible feature.
- A pure bytecode runtime is not a security sandbox; untrusted scripts require additional resource and capability isolation.

The standalone boot distribution and `BootstrapImage` are the new focus for future versions. Previous versions remain in their own folders.
