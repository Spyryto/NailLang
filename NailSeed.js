/* NailSeed 0.3 — minimal functional core, JS reference runtime.
 * Every source token MUST be separated by whitespace, including punctuation.
 * No external dependencies. Designed for Node.js and Scriptable.
 * Expression AST: literal, var, lambda, apply, if.
 */
var NailSeed3 = (() => {
  'use strict';
  const EMPTY = Object.freeze([]);
  const OWN = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  const PREC = Object.freeze({
    '==': 30, '!=': 30, '<': 30, '<=': 30, '>': 30, '>=': 30,
    '+': 40, '-': 40, '*': 50, '/': 50
  });
  const APP_PREC = 70;
  const RESERVED = new Set(['def', 'if', 'then', 'else', 'fun', 'true', 'false']);
  const isName = t => typeof t === 'string' && /^[A-Za-z_][A-Za-z_0-9]*$/.test(t) && !RESERVED.has(t);
  const isNumber = t => typeof t === 'string' && /^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(t);
  const isAtom = t => t === '(' || t === '[' || t === '[]' || t === 'fun' || t === 'if' ||
    t === 'true' || t === 'false' || isName(t) || isNumber(t);
  const node = (kind, ...items) => ({ kind, items });
  const literal = v => node('literal', v);
  const variable = n => node('var', n);
  const apply = (f, x) => node('apply', f, x);
  const lambda = (params, body) => params.reduceRight((b, p) => node('lambda', p, b), body);
  const privateCons = '#cons'; // cannot occur in user-written source

  function parse(source) {
    const clean = source.split(/\r?\n/).map(line => line.replace(/(^|\s)#.*$/, '$1')).join(' ');
    const tokens = clean.match(/\S+/g) || [];
    let i = 0;
    const peek = () => tokens[i];
    const take = () => tokens[i++];
    const expect = token => {
      if (take() !== token) throw Error(`Expected '${token}' at token ${i}`);
    };
    function atom() {
      const t = take();
      if (t === undefined) throw Error('Unexpected end of input');
      if (t === '[]') return literal(EMPTY);
      if (t === '(') {
        const e = expression(); expect(')'); return e;
      }
      if (t === '[') {
        const elements = [];
        if (peek() !== ']') {
          while (true) {
            elements.push(expression());
            if (peek() !== ',') break;
            take();
          }
        }
        expect(']');
        return elements.reduceRight((xs, x) =>
          apply(apply(variable(privateCons), x), xs), literal(EMPTY));
      }
      if (t === 'if') {
        const test = expression(); expect('then');
        const yes = expression(); expect('else');
        return node('if', test, yes, expression());
      }
      if (t === 'fun') {
        const params = [];
        while (peek() !== '->') {
          const p = take();
          if (!isName(p) || params.includes(p)) throw Error('Invalid or duplicate function parameter');
          params.push(p);
        }
        if (!params.length) throw Error('Function needs at least one parameter');
        expect('->');
        return lambda(params, expression());
      }
      if (isNumber(t)) {
        const n = Number(t);
        if (!Number.isFinite(n)) throw Error('Number out of range: ' + t);
        return literal(n);
      }
      if (t === 'true' || t === 'false') return literal(t === 'true');
      if (isName(t)) return variable(t);
      throw Error(`Unexpected token '${t}' at token ${i}`);
    }
    function expression(min = 0) {
      let left = atom();
      while (peek() !== undefined) {
        if (isAtom(peek()) && min <= APP_PREC) {
          left = apply(left, expression(APP_PREC + 1));
          continue;
        }
        const op = peek();
        const prec = OWN(PREC, op) ? PREC[op] : undefined;
        if (prec === undefined || prec < min) break;
        take();
        left = apply(apply(variable(op), left), expression(prec + 1));
      }
      return left;
    }
    const forms = [];
    while (i < tokens.length) {
      if (peek() === 'def') {
        take();
        const name = take();
        if (!isName(name)) throw Error('Expected definition name');
        const params = [];
        while (peek() !== '=') {
          const p = take();
          if (!isName(p) || params.includes(p)) throw Error('Invalid or duplicate definition parameter');
          params.push(p);
          if (p === undefined) throw Error('Expected =');
        }
        expect('=');
        const body = lambda(params, expression());
        expect(';');
        forms.push({ kind: 'def', name, body });
      } else {
        const expr = expression(); expect(';');
        forms.push({ kind: 'expr', body: expr });
      }
    }
    return forms;
  }

  function create(options = {}) {
    const limit = options.maxSteps === undefined ? 100000 : options.maxSteps;
    if (!Number.isSafeInteger(limit) || limit < 1) throw Error('maxSteps must be a positive integer');
    const root = { parent: null, values: Object.create(null) };
    let steps = 0;
    function tick() {
      if (++steps > limit) throw Error('Execution budget exceeded');
    }
    const bind = (env, name, value) => { env.values[name] = value; };
    function lookup(env, name) {
      for (let e = env; e; e = e.parent) {
        if (OWN(e.values, name)) return e.values[name];
      }
      throw Error('Unknown name: ' + name);
    }
    function unary(name, arity, fn) {
      bind(root, name, Object.freeze({ tag: 'native', name, arity, args: EMPTY, fn }));
    }
    const asNumber = v => {
      if (typeof v !== 'number' || !Number.isFinite(v)) throw Error('Expected finite number');
      return v;
    };
    const asBoolean = v => {
      if (typeof v !== 'boolean') throw Error('Expected boolean');
      return v;
    };
    const asList = v => {
      if (!Array.isArray(v)) throw Error('Expected list');
      return v;
    };
    const numberResult = v => {
      if (!Number.isFinite(v)) throw Error('Nonfinite arithmetic result');
      return v;
    };
    function equal(a, b) {
      if (Array.isArray(a) && Array.isArray(b)) {
        return a.length === b.length && a.every((v, i) => equal(v, b[i]));
      }
      if (typeof a === 'number' && typeof b === 'number') return a === b;
      if (typeof a === 'boolean' && typeof b === 'boolean') return a === b;
      throw Error('Cannot compare these values');
    }
    const numeric = (name, fn) => unary(name, 2, (a, b) => numberResult(fn(asNumber(a), asNumber(b))));
    numeric('+', (a, b) => a + b);
    numeric('-', (a, b) => a - b);
    numeric('*', (a, b) => a * b);
    numeric('/', (a, b) => { if (b === 0) throw Error('Division by zero'); return a / b; });
    for (const [name, cmp] of Object.entries({
      '<': (a, b) => a < b, '<=': (a, b) => a <= b,
      '>': (a, b) => a > b, '>=': (a, b) => a >= b
    })) unary(name, 2, (a, b) => cmp(asNumber(a), asNumber(b)));
    unary('==', 2, equal);
    unary('!=', 2, (a, b) => !equal(a, b));
    bind(root, 'nil', EMPTY);
    const cons = (head, tail) => Object.freeze([head, ...asList(tail)]);
    unary('cons', 2, cons);
    unary(privateCons, 2, cons);
    unary('isEmpty', 1, xs => asList(xs).length === 0);
    unary('head', 1, xs => {
      const list = asList(xs);
      if (!list.length) throw Error('head of empty list');
      return list[0];
    });
    unary('tail', 1, xs => {
      const list = asList(xs);
      if (!list.length) throw Error('tail of empty list');
      return Object.freeze(list.slice(1));
    });
    function call(fn, value) {
      tick();
      if (!fn || (fn.tag !== 'closure' && fn.tag !== 'native')) throw Error('Value is not a function');
      if (fn.tag === 'native') {
        const args = [...fn.args, value];
        return args.length < fn.arity
          ? Object.freeze({ ...fn, args: Object.freeze(args) })
          : fn.fn(...args);
      }
      const child = { parent: fn.env, values: Object.create(null) };
      bind(child, fn.param, value);
      return evaluate(fn.body, child);
    }
    function evaluate(ast, env) {
      tick();
      const a = ast.items;
      switch (ast.kind) {
        case 'literal': return a[0];
        case 'var': return lookup(env, a[0]);
        case 'lambda': return Object.freeze({ tag: 'closure', param: a[0], body: a[1], env });
        case 'apply': return call(evaluate(a[0], env), evaluate(a[1], env));
        case 'if': return evaluate(asBoolean(evaluate(a[0], env)) ? a[1] : a[2], env);
        default: throw Error('Unknown AST node ' + ast.kind);
      }
    }
    function run(source) {
      const results = [];
      steps = 0;
      for (const form of parse(source)) {
        if (form.kind === 'def') {
          if (OWN(root.values, form.name)) throw Error('Already defined: ' + form.name);
          const value = evaluate(form.body, root);
          bind(root, form.name, value);
        } else results.push(evaluate(form.body, root));
      }
      return results;
    }
    return Object.freeze({ run, names: () => Object.keys(root.values).filter(x => !x.startsWith('#')).sort() });
  }
  return Object.freeze({ create, parse });
})();

if (typeof module !== 'undefined' && module.exports) module.exports = { NailSeed3 };
