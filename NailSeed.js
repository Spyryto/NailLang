/* NailSeed 0.1 — tiny functional concatenative interpreter
 * Works in Scriptable (iOS) and Node.js; no dependencies or build step.
 * Whitespace always separates tokens. [ and ] must be separate tokens.
 * :name denotes a symbol; name executes a word.
 * Strings use s: followed by URI-encoded text (e.g. s:Ciao%20mondo).
 * # starts a line comment when it is the first token or preceded by whitespace.
 * Definitions are permitted only in top-level code.
 */

const NailSeed = (() => {
  const quote = code => Object.freeze({ kind: 'quote', code: Object.freeze(code) });
  const symbol = name => Object.freeze({ kind: 'symbol', name });
  const word = name => Object.freeze({ kind: 'word', name });
  const literal = value => Object.freeze({ kind: 'literal', value });

  function parse(source) {
    const clean = source.split(/\r?\n/).map(line => line.replace(/(^|\s)#(?:\s|$).*$/, '$1')).join(' ');
    const tokens = clean.match(/\S+/g) || [];
    let index = 0;

    function sequence(nested) {
      const result = [];
      while (index < tokens.length) {
        const t = tokens[index++];
        if (t === ']') {
          if (!nested) throw Error('Unexpected ]');
          return result;
        }
        if (t === '[') result.push(quote(sequence(true)));
        else if (t === 'true') result.push(true);
        else if (t === 'false') result.push(false);
        else if (/^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(t)) result.push(Number(t));
        else if (t.startsWith('s:')) result.push(decodeURIComponent(t.slice(2)));
        else if (/^:[A-Za-z_][\w.-]*$/.test(t)) result.push(symbol(t.slice(1)));
        else result.push(word(t));
      }
      if (nested) throw Error('Unclosed [');
      return result;
    }
    return quote(sequence(false));
  }

  function create() {
    const dict = new Map();
    const pop = s => {
      if (!s.length) throw Error('Stack underflow');
      return s.pop();
    };
    const peek = s => {
      if (!s.length) throw Error('Stack underflow');
      return s[s.length - 1];
    };
    const getQuote = s => {
      const v = pop(s);
      if (!v || v.kind !== 'quote') throw Error('Expected quotation');
      return v;
    };
    const getList = s => {
      const v = pop(s);
      if (!Array.isArray(v)) throw Error('Expected list');
      return v;
    };
    const native = (name, fn) => dict.set(name, { native: fn });
    const numeric = (name, fn) => native(name, s => {
      const b = pop(s), a = pop(s);
      if (typeof a !== 'number' || typeof b !== 'number') throw Error(name + ': numbers required');
      s.push(fn(a, b));
    });

    function execute(q, s, ctx, topLevel = false) {
      for (const node of q.code) {
        if (++ctx.steps > ctx.maxSteps) throw Error('Execution budget exceeded');
        if (node && node.kind === 'literal') {
          s.push(node.value);
        } else if (node && node.kind === 'word') {
          const entry = dict.get(node.name);
          if (!entry) throw Error('Unknown word: ' + node.name);
          if (entry.native) entry.native(s, ctx, topLevel);
          else execute(entry.quote, s, ctx, false);
        } else {
          s.push(node);
        }
      }
    }
    const apply = (q, inputs, ctx) => {
      const s = inputs.slice();
      execute(q, s, ctx, false);
      if (s.length !== 1) throw Error('Quotation must produce exactly one value');
      return s[0];
    };

    // Pure stack combinators
    native('dup', s => s.push(peek(s)));
    native('drop', s => { pop(s); });
    native('swap', s => { const b = pop(s), a = pop(s); s.push(b, a); });
    native('over', s => {
      if (s.length < 2) throw Error('Stack underflow');
      s.push(s[s.length - 2]);
    });
    numeric('+', (a, b) => a + b);
    numeric('-', (a, b) => a - b);
    numeric('*', (a, b) => a * b);
    numeric('/', (a, b) => a / b);
    numeric('<', (a, b) => a < b);
    numeric('>', (a, b) => a > b);
    native('=', s => {
      const b = pop(s), a = pop(s);
      if (typeof a === 'object' || typeof b === 'object') throw Error('=: scalar values only');
      s.push(a === b);
    });
    native('not', s => { const v = pop(s); if (typeof v !== 'boolean') throw Error('not: boolean required'); s.push(!v); });
    native('call', (s, ctx) => execute(getQuote(s), s, ctx));
    native('dip', (s, ctx) => {
      const q = getQuote(s), saved = pop(s);
      execute(q, s, ctx);
      s.push(saved);
    });
    native('curry', s => {
      const q = getQuote(s), value = pop(s);
      s.push(quote([literal(value), ...q.code]));
    });
    native('compose', s => {
      const q2 = getQuote(s), q1 = getQuote(s);
      s.push(quote([...q1.code, ...q2.code]));
    });
    native('if', (s, ctx) => {
      const otherwise = getQuote(s), then = getQuote(s), condition = pop(s);
      if (typeof condition !== 'boolean') throw Error('if: boolean required');
      execute(condition ? then : otherwise, s, ctx);
    });

    // Immutable data and higher-order operations
    native('pack', s => {
      const n = pop(s);
      if (!Number.isSafeInteger(n) || n < 0 || n > s.length) throw Error('pack: invalid length');
      s.push(Object.freeze(s.splice(s.length - n, n)));
    });
    native('map', (s, ctx) => {
      const q = getQuote(s), xs = getList(s);
      s.push(Object.freeze(xs.map(x => apply(q, [x], ctx))));
    });
    native('fold', (s, ctx) => {
      const q = getQuote(s), start = pop(s), xs = getList(s);
      s.push(xs.reduce((acc, x) => apply(q, [acc, x], ctx), start));
    });

    // Only metaprogramming at top level mutates the dictionary.
    native('def', (s, _ctx, topLevel) => {
      if (!topLevel) throw Error('def is top-level only');
      const q = getQuote(s), name = pop(s);
      if (!name || name.kind !== 'symbol') throw Error('def: expected symbol');
      if (dict.has(name.name)) throw Error('Already defined: ' + name.name);
      dict.set(name.name, { quote: q });
    });

    function run(source, options = {}) {
      const stack = [];
      const ctx = { steps: 0, maxSteps: options.maxSteps || 100000 };
      execute(parse(source), stack, ctx, true);
      return stack;
    }
    return Object.freeze({ run, parse, words: () => [...dict.keys()].sort() });
  }
  return Object.freeze({ create, parse });
})();

// Smoke tests. Only run when executed directly, not when imported.
function nailSeedSelfTest() {
const vm = NailSeed.create();
const examples = [
  [':square [ dup * ] def :inc [ 1 + ] def 5 inc square', '[36]'],
  [':twice [ dup [ call ] dip call ] def 5 [ 1 + ] twice', '[7]'],
  [':fact [ dup 2 < [ drop 1 ] [ dup 1 - fact * ] if ] def 5 fact', '[120]'],
  [':sum [ 0 [ + ] fold ] def 4 5 6 3 pack sum', '[15]'],
  ['1 2 3 3 pack [ dup * ] map', '[[1,4,9]]'],
  ['1 2 3 3 pack 0 [ + ] fold', '[6]'],
  ['true [ 42 ] [ 0 ] if', '[42]'],
  ['5 [ 1 + ] [ 2 * ] compose call', '[12]'],
  ['3 5 [ + ] curry call', '[8]'],
  ['s:Ciao%20mondo', '["Ciao mondo"]'],
  ['3 [ 5 ] dip', '[5,3]'],
];
for (const [source, expected] of examples) {
  const actual = JSON.stringify(vm.run(source));
  if (actual !== expected) throw Error(source + ' => ' + actual + ', expected ' + expected);
  console.log('OK ' + source + ' => ' + actual);
}
console.log('NailSeed 0.1: ' + examples.length + ' tests passed');
}

if (typeof module !== 'undefined' && module.exports) module.exports = NailSeed;
if (typeof Script !== 'undefined' && Script.complete) {
  nailSeedSelfTest();
  Script.complete();
} else if (typeof require !== 'undefined' && typeof module !== 'undefined' && require.main === module) {
  nailSeedSelfTest();
}