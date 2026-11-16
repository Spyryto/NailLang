const assert = require('node:assert/strict');
const fs = require('node:fs');
const { NailSeed } = require('../build/js/nailseed.js');
const source = fs.readFileSync(__dirname + '/../stdlib.nail', 'utf8');
const guard = /if parseFailed (\w+) then \1\n(\s*)else /g;
const matches = [...source.matchAll(guard)];
assert.ok(matches.length > 0);
const expanded = 'if parseFailed result then result else next';
const call = 'expand guard result ( next )';
const definition = 'macro guard result next = quote ( if parseFailed ( unquote result ) then unquote result else unquote next ) ;';
const draft = definition + '\n'
  + 'def parseFailed result = result < 0 ; '
  + 'expand guard -1 ( 1 / 0 ) ; expand guard 1 42 ;';
const runtime = NailSeed.create();
assert.deepEqual(runtime.runPlain(draft), [-1, 42]);
assert.deepEqual(NailSeed.createTypeChecker().check(draft), ['Number', 'Number']);
const tokenize = text => text.trim().split(/\s+/).length;
console.log(JSON.stringify({
  matchingParserGuards: matches.length,
  explicitTokensPerGuard: tokenize(expanded),
  macroTokensPerGuard: tokenize(call),
  macroDeclarationTokens: tokenize(definition),
  estimatedTokenSavings: matches.length * (tokenize(expanded) - tokenize(call)) - tokenize(definition)
}, null, 2));
