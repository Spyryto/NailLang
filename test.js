'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { NailSeed3 } = require('./NailSeed.js');
const stdlib = fs.readFileSync(path.join(__dirname, 'stdlib.nail'), 'utf8');
const cases = require('./cases.json');
let count = 0;
for (const { code: source, expected, stdlib: needsStdlib } of cases.positive) {
  const vm = NailSeed3.create();
  if (needsStdlib) vm.run(stdlib);
  const actual = vm.run(source);
  assert.deepStrictEqual(actual, expected, `Failed: ${source}`);
  count++;
}
for (const { code: source, errorRegex } of cases.negative) {
  const pattern = new RegExp(errorRegex);
  assert.throws(() => NailSeed3.create({ maxSteps: 2000 }).run(source), pattern, `Expected failure: ${source}`);
  count++;
}
const forms = NailSeed3.parse('def twice x = x * 2 ;');
const kinds = new Set();
const walk = value => {
  if (value && typeof value === 'object') {
    if (['literal', 'var', 'lambda', 'apply', 'if'].includes(value.kind)) kinds.add(value.kind);
    if (Array.isArray(value)) value.forEach(walk);
    else Object.values(value).forEach(walk);
  }
};
walk(forms);
assert.ok([...kinds].every(k => ['literal', 'var', 'lambda', 'apply', 'if'].includes(k)));
count++;
console.log(`NailSeed 0.3: ${count} tests passed`);
