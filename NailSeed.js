/* NailSeed 0.2 — experimental F#-style source language, JS edition.
 * Whitespace separates EVERY token. For example: f ( x + 1 ) ;
 * Definitions: def f x = x * 2 ;
 * The source language exposes no stack manipulation.
 * No dependencies; works in Scriptable, Node.js and browsers.
 * Experimental AST interpreter: not yet a compiler to NailVM 0.1.
 */
const NailSeed2 = (() => {
  const binaryPrecedence = { '|>': 10, '==': 30, '!=': 30, '<': 30, '<=': 30,
    '>': 30, '>=': 30, '+': 40, '-': 40, '*': 50, '/': 50 };
  const op = (kind, ...args) => ({ kind, args });
  const isName = s => /^[A-Za-z_][A-Za-z_0-9]*$/.test(s) &&
    !['def','if','then','else','fun','true','false'].includes(s);
  const isNum = s => /^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(s);
  const isAtomStart = t => t === '(' || t === '[' || t === 'if' || t === 'fun' ||
    t === 'true' || t === 'false' || t?.startsWith('s:') || isName(t) || isNum(t);

  function parse(source) {
    const clean = source.split(/\r?\n/).map(x => x.replace(/(^|\s)#(?:\s|$).*$/, '$1')).join(' ');
    const ts = clean.trim().match(/\S+/g) || [];
    let i = 0;
    const peek = () => ts[i];
    const take = () => ts[i++];
    const need = token => { if (take() !== token) throw Error(`Expected ${token} at token ${i}`); };

    function expression(min = 0) {
      let lhs;
      const t = take();
      if (t === undefined) throw Error('Unexpected end of input');
      if (t === '(') { lhs = expression(); need(')'); }
      else if (t === '[') {
        const elements = [];
        if (peek() !== ']') {
          do { elements.push(expression()); if (peek() !== ',') break; take(); } while (true);
        }
        need(']'); lhs = op('list', elements);
      } else if (t === 'if') {
        const test = expression(); need('then');
        const yes = expression(); need('else');
        lhs = op('if', test, yes, expression());
      } else if (t === 'fun') {
        const params = [];
        while (peek() !== '->') {
          const p = take(); if (!p || !isName(p)) throw Error('Expected function parameter');
          params.push(p);
        }
        if (!params.length) throw Error('Function needs parameters');
        need('->'); lhs = op('lambda', params, expression());
      } else if (Object.hasOwn(binaryPrecedence, t) && t !== '|>' && t !== '==' && t !== '!=') {
        // Optional F#-like operator section: * 2 means fun x -> x * 2.
        lhs = op('section', t, expression(60));
      } else if (isNum(t)) lhs = op('literal', Number(t));
      else if (t === 'true' || t === 'false') lhs = op('literal', t === 'true');
      else if (t.startsWith('s:')) lhs = op('literal', decodeURIComponent(t.slice(2)));
      else if (isName(t)) lhs = op('name', t);
      else throw Error(`Unexpected token ${t}`);
      while (i < ts.length) {
        const next = peek();
        // Application binds tighter than multiplication (F# convention).
        if (isAtomStart(next) && min <= 70) {
          lhs = op('apply', lhs, expression(71)); continue;
        }
        const prec = binaryPrecedence[next];
        if (prec === undefined || prec < min) break;
        take();
        lhs = next === '|>'
          ? op('apply', expression(prec + 1), lhs)
          : op('binary', next, lhs, expression(prec + 1));
      }
      return lhs;
    }
    const forms = [];
    while (i < ts.length) {
      if (peek() === 'def') {
        take(); const name = take();
        if (!isName(name)) throw Error('Expected definition name');
        const params = [];
        while (peek() !== '=') {
          if (i >= ts.length || !isName(peek())) throw Error('Expected parameter or =');
          params.push(take());
        }
        need('='); const body = expression(); need(';');
        forms.push(op('def', name, params, body));
      } else {
        const e = expression(); need(';'); forms.push(op('expr', e));
      }
    }
    return forms;
  }

  function create(options = {}) {
    const globals = Object.create(null);
    let steps = 0;
    const limit = options.maxSteps || 100000;
    function native(name, n, fn) {
      globals[name] = { kind: 'native', name, n, fn, got: [] };
    }
    function lookup(env, name) {
      if (name in env) return env[name];
      if (name in globals) return globals[name];
      throw Error('Unknown name: ' + name);
    }
    function apply(f, x) {
      if (!f || (f.kind !== 'closure' && f.kind !== 'native')) throw Error('Value is not callable');
      if (f.kind === 'native') {
        const got = [...f.got, x];
        return got.length === f.n ? f.fn(...got) : { ...f, got };
      }
      const local = Object.create(f.env);
      local[f.params[0]] = x;
      return f.params.length === 1
        ? evalExpr(f.body, local)
        : { ...f, params: f.params.slice(1), env: local };
    }
    function binary(symbol, a, b) {
      switch (symbol) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/': return a / b;
        case '<': return a < b;
        case '<=': return a <= b;
        case '>': return a > b;
        case '>=': return a >= b;
        case '==': return a === b;
        case '!=': return a !== b;
        default: throw Error(`Unknown operator ${symbol}`);
      }
    }
    function evalExpr(node, env) {
      if (++steps > limit) throw Error('Execution budget exceeded');
      const [a, b, c, d] = node.args;
      switch (node.kind) {
        case 'literal': return a;
        case 'name': return lookup(env, a);
        case 'binary': return binary(a, evalExpr(b, env), evalExpr(c, env));
        case 'section': return { kind: 'native', name: `section ${a}`, n: 1,
          got: [], fn: x => binary(a, x, evalExpr(b, env)) };
        case 'if': return evalExpr(a, env) ? evalExpr(b, env) : evalExpr(c, env);
        case 'lambda': return { kind: 'closure', params: a, body: b, env };
        case 'apply': return apply(evalExpr(a, env), evalExpr(b, env));
        case 'list': return Object.freeze(a.map(x => evalExpr(x, env)));
        default: throw Error(`Unrecognized AST node ${node.kind}`);
      }
    }
    native('map', 2, (f, xs) => Object.freeze(xs.map(x => apply(f, x))));
    native('filter', 2, (f, xs) => Object.freeze(xs.filter(x => apply(f, x))));
    native('fold', 3, (f, init, xs) => xs.reduce((acc, x) => apply(apply(f, acc), x), init));
    function run(source) {
      const forms = parse(source), results = [];
      steps = 0;
      for (const form of forms) {
        const [a, b, c] = form.args;
        if (form.kind === 'def') {
          if (a in globals) throw Error('Already defined: ' + a);
          globals[a] = b.length
            ? { kind: 'closure', params: b, body: c, env: Object.create(null) }
            : evalExpr(c, Object.create(null));
        } else results.push(evalExpr(a, Object.create(null)));
      }
      return results;
    }
    return Object.freeze({ run, parse, names: () => Object.keys(globals).sort() });
  }
  return Object.freeze({ create, parse });
})();

function nailSeed2SelfTest() {
  const examples = [
    ['def twice x = x * 2 ; twice 5 ;', '[10]'],
    ['def square x = x * x ; square 7 ;', '[49]'],
    ['def twice = * 2 ; twice 5 ;', '[10]'],
    ['def sub a b = a - b ; sub 10 3 ;', '[7]'],
    ['def add a b = a + b ; def add3 = add 3 ; add3 8 ;', '[11]'],
    ['def fact n = if n < 2 then 1 else n * fact ( n - 1 ) ; fact 5 ;', '[120]'],
    ['def inc = + 1 ; map inc [ 1 , 2 , 3 ] ;', '[[2,3,4]]'],
    ['fold ( fun acc x -> acc + x ) 0 [ 1 , 2 , 3 ] ;', '[6]'],
    ['def twice x = x * 2 ; [ 1 , 2 , 3 ] |> map twice ;', '[[2,4,6]]'],
    ['def choose x = if x > 0 then x else 0 ; choose -4 ;', '[0]'],
    ['def f x = x + 2 * 3 ; f 1 ;', '[7]'],
    ['s:Ciao%20mondo ;', '["Ciao mondo"]'],
    ['def makeAdder x = fun y -> x + y ; def add10 = makeAdder 10 ; add10 8 ;', '[18]'],
    ['def halve = / 2 ; halve 9 ;', '[4.5]'],
    ['def twice x = x * 2 ; 3 |> twice |> twice ;', '[12]'],
  ];
  for (const [code, expected] of examples) {
    const actual = JSON.stringify(NailSeed2.create().run(code));
    if (actual !== expected) throw Error(`FAIL ${code}\n${actual} != ${expected}`);
  }
  return `${examples.length} tests passed`;
}
if (typeof module !== 'undefined') {
  module.exports = { NailSeed2, nailSeed2SelfTest };
  if (require.main === module) console.log(nailSeed2SelfTest());
}