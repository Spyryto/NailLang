// Build-time regression guard: the distributed source-free VMs must not
// package the Haxe source parser, reference compiler, or their type passes.
// Intentionally check emitted artifacts, not only source-level #if branches.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';

const jsPath = 'build/boot/js/nailseed-boot.js';
const phpPath = 'build/boot/php';
const forbidden = ['Parser', 'BytecodeCompiler', 'RecordLowering',
  'SumLowering', 'TypeChecker', 'Vm'];
if (!existsSync(jsPath) || !existsSync(phpPath))
  throw new Error('Build boot-js.hxml and boot-php.hxml before checking the bootstrap boundary');

const javascript = readFileSync(jsPath, 'utf8');
for (const symbol of forbidden) {
  // Haxe JS emits top-level classes as nail_Parser, nail_TypeChecker, ...
  if (new RegExp('\\bnail_' + symbol + '\\b').test(javascript))
    throw new Error('Haxe stage-zero compiler leaked into JS runtime: ' + symbol);
}

function checkPhpTree(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) checkPhpTree(full);
    else if (forbidden.some(symbol => basename(full) === symbol + '.php'))
      throw new Error('Haxe stage-zero compiler leaked into PHP runtime: ' + full);
  }
}
checkPhpTree(phpPath);
console.log('Source-free JS/PHP boundary: Haxe parser, compiler, lowering, and type checker are absent');
