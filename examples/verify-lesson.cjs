const fs = require('node:fs');
const assert = require('node:assert/strict');
const { NailSeed } = require('../build/js/nailseed.js');
const { render } = require('./lesson-html.cjs');
const baseline = require('./lezione.cjs');
const source = fs.readFileSync(__dirname + '/lezione.nail', 'utf8');
const vm = NailSeed.create();
const modules = name => name === 'guitar'
  ? fs.readFileSync(__dirname + '/macros/guitar.nail', 'utf8')
  : null;
const [lesson] = vm.runPlain(source, modules);
const portable = JSON.parse(JSON.stringify(lesson, (key, value) => key === '$type' ? undefined : value));
assert.deepEqual(portable, baseline);
assert.equal(render(lesson), render(baseline));
assert.deepEqual(NailSeed.createTypeChecker().check(source, modules), ['Lesson']);
const view = NailSeed.expand('macro addTen x = quote ( let tmp = 10 in tmp + unquote x ) ; '
  + 'let tmp = 32 in expand addTen tmp ;');
assert.ok(view.includes('tmp@0') && view.includes('global[+]') && view.includes(' tmp )'));
assert.throws(() => NailSeed.expand('expand missing 1 ;'), /unknown macro missing/);
const [vibrato] = NailSeed.create().runPlain(fs.readFileSync(__dirname + '/vibrato.nail', 'utf8'), modules);
assert.equal(vibrato.target, 'Fai quattro oscillazioni per battito a 60 BPM');
assert.equal(vibrato.success, '4 battiti regolari su 5 senza perdere il tempo');
const conditional = fs.readFileSync(__dirname + '/conditional.nail', 'utf8');
assert.deepEqual(vm.runPlain(conditional), [42, 42]);
console.log('Shared lessons, JSON, HTML, types, expansion and lazy conditional verified');
