const fs = require('node:fs');
const assert = require('node:assert/strict');
const { NailSeed } = require('../build/js/nailseed.js');
const { render } = require('./lesson-html.cjs');
const baseline = require('./lezione.cjs');
const source = fs.readFileSync(__dirname + '/lezione.nail', 'utf8');
const vm = NailSeed.create();
const [lesson] = vm.runPlain(source);
const portable = JSON.parse(JSON.stringify(lesson, (key, value) => key === '$type' ? undefined : value));
assert.deepEqual(portable, baseline);
assert.equal(render(lesson), render(baseline));
assert.deepEqual(NailSeed.createTypeChecker().check(source), ['Lesson']);
const view = NailSeed.expand('macro addTen x = quote ( let tmp = 10 in tmp + unquote x ) ; '
  + 'let tmp = 32 in expand addTen tmp ;');
assert.ok(view.includes('tmp@0') && view.includes('global[+]') && view.includes(' tmp )'));
assert.throws(() => NailSeed.expand('expand missing 1 ;'), /unknown macro missing/);
console.log('Lesson JSON, HTML, type and expansion verified');
