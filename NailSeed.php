<?php
/* NailSeed 0.2 — experimental F#-style source language, PHP 8 edition.
 * ALL tokens must be separated by whitespace, including ( ) [ ] , ;
 * Prototype AST interpreter, not yet a compiler to NailVM 0.1.
 */
final class NailSeed2 {
    private array $tokens = [];
    private int $i = 0;
    private array $globals = [];
    private int $steps = 0;
    private int $maxSteps;
    private const PRIORITY = [
        '|>' => 10, '==' => 30, '!=' => 30, '<' => 30, '<=' => 30,
        '>' => 30, '>=' => 30, '+' => 40, '-' => 40, '*' => 50, '/' => 50,
    ];
    public function __construct(int $maxSteps = 100000) {
        $this->maxSteps = $maxSteps;
        $this->native('map', 2, fn ($f, $xs) => array_map(fn ($x) => $this->apply($f, $x), $xs));
        $this->native('filter', 2, fn ($f, $xs) => array_values(array_filter($xs, fn ($x) => $this->apply($f, $x))));
        $this->native('fold', 3, fn ($f, $initial, $xs) => array_reduce($xs,
            fn ($acc, $x) => $this->apply($this->apply($f, $acc), $x), $initial));
    }
    private static function ast(string $kind, mixed ...$args): array {
        return ['kind' => $kind, 'args' => $args];
    }
    private static function isName(?string $t): bool {
        return $t !== null && preg_match('/^[A-Za-z_][A-Za-z_0-9]*$/D', $t) === 1
            && !in_array($t, ['def', 'if', 'then', 'else', 'fun', 'true', 'false'], true);
    }
    private static function isNumber(?string $t): bool {
        return $t !== null && preg_match('/^-?(?:\d+(?:\.\d+)?|\.\d+)$/D', $t) === 1;
    }
    private static function isAtomStart(?string $t): bool {
        return $t === '(' || $t === '[' || $t === 'if' || $t === 'fun'
            || $t === 'true' || $t === 'false' || ($t !== null && str_starts_with($t, 's:'))
            || self::isName($t) || self::isNumber($t);
    }
    private function peek(): ?string { return $this->tokens[$this->i] ?? null; }
    private function take(): ?string { return $this->tokens[$this->i++] ?? null; }
    private function need(string $token): void {
        if ($this->take() !== $token) throw new RuntimeException("Expected $token at token {$this->i}");
    }
    private function expression(int $min = 0): array {
        $t = $this->take();
        if ($t === null) throw new RuntimeException('Unexpected end of input');
        if ($t === '(') {
            $lhs = $this->expression(); $this->need(')');
        } elseif ($t === '[') {
            $elements = [];
            if ($this->peek() !== ']') {
                do {
                    $elements[] = $this->expression();
                    if ($this->peek() !== ',') break;
                    $this->take();
                } while (true);
            }
            $this->need(']'); $lhs = self::ast('list', $elements);
        } elseif ($t === 'if') {
            $test = $this->expression(); $this->need('then');
            $yes = $this->expression(); $this->need('else');
            $lhs = self::ast('if', $test, $yes, $this->expression());
        } elseif ($t === 'fun') {
            $params = [];
            while ($this->peek() !== '->') {
                $p = $this->take();
                if (!self::isName($p)) throw new RuntimeException('Expected function parameter');
                $params[] = $p;
            }
            if (!$params) throw new RuntimeException('Function needs parameters');
            $this->need('->'); $lhs = self::ast('lambda', $params, $this->expression());
        } elseif (isset(self::PRIORITY[$t]) && !in_array($t, ['|>', '==', '!='], true)) {
            // Operator section: * 2 means fun x -> x * 2.
            $lhs = self::ast('section', $t, $this->expression(60));
        } elseif (self::isNumber($t)) {
            $lhs = self::ast('literal', strpos($t, '.') !== false ? (float)$t : (int)$t);
        } elseif ($t === 'true' || $t === 'false') {
            $lhs = self::ast('literal', $t === 'true');
        } elseif (str_starts_with($t, 's:')) {
            $lhs = self::ast('literal', rawurldecode(substr($t, 2)));
        } elseif (self::isName($t)) {
            $lhs = self::ast('name', $t);
        } else {
            throw new RuntimeException("Unexpected token $t");
        }
        while ($this->peek() !== null) {
            $next = $this->peek();
            if (self::isAtomStart($next) && $min <= 70) {
                $lhs = self::ast('apply', $lhs, $this->expression(71));
                continue;
            }
            $precedence = self::PRIORITY[$next] ?? null;
            if ($precedence === null || $precedence < $min) break;
            $this->take();
            $lhs = $next === '|>'
                ? self::ast('apply', $this->expression($precedence + 1), $lhs)
                : self::ast('binary', $next, $lhs, $this->expression($precedence + 1));
        }
        return $lhs;
    }
    public function parse(string $source): array {
        $source = preg_replace('/(^|\s)#(?=\s|$).*$/m', '$1', $source);
        $this->tokens = preg_split('/\s+/', trim($source), -1, PREG_SPLIT_NO_EMPTY);
        $this->i = 0;
        $forms = [];
        while ($this->peek() !== null) {
            if ($this->peek() === 'def') {
                $this->take(); $name = $this->take();
                if (!self::isName($name)) throw new RuntimeException('Expected definition name');
                $params = [];
                while ($this->peek() !== '=') {
                    if (!self::isName($this->peek())) throw new RuntimeException('Expected parameter or =');
                    $params[] = $this->take();
                }
                $this->need('='); $body = $this->expression(); $this->need(';');
                $forms[] = self::ast('def', $name, $params, $body);
            } else {
                $e = $this->expression(); $this->need(';');
                $forms[] = self::ast('expr', $e);
            }
        }
        return $forms;
    }
    private function native(string $name, int $arity, Closure $fn): void {
        $this->globals[$name] = ['kind' => 'native', 'arity' => $arity, 'fn' => $fn, 'got' => []];
    }
    private function apply(mixed $f, mixed $x): mixed {
        if (!is_array($f) || !in_array($f['kind'] ?? null, ['closure', 'native'], true))
            throw new RuntimeException('Value is not callable');
        if ($f['kind'] === 'native') {
            $got = [...$f['got'], $x];
            if (count($got) === $f['arity']) return ($f['fn'])(...$got);
            $f['got'] = $got; return $f;
        }
        $local = $f['env'];
        $local[$f['params'][0]] = $x;
        if (count($f['params']) === 1) return $this->evalExpr($f['body'], $local);
        $f['params'] = array_slice($f['params'], 1);
        $f['env'] = $local;
        return $f;
    }
    private function binary(string $op, mixed $a, mixed $b): mixed {
        return match ($op) {
            '+' => $a + $b, '-' => $a - $b, '*' => $a * $b, '/' => $a / $b,
            '<' => $a < $b, '<=' => $a <= $b, '>' => $a > $b, '>=' => $a >= $b,
            '==' => $a === $b, '!=' => $a !== $b,
            default => throw new RuntimeException("Unknown operator $op"),
        };
    }
    private function evalExpr(array $node, array $env): mixed {
        if (++$this->steps > $this->maxSteps) throw new RuntimeException('Execution budget exceeded');
        $p = $node['args'];
        return match ($node['kind']) {
            'literal' => $p[0],
            'name' => array_key_exists($p[0], $env) ? $env[$p[0]] :
                ($this->globals[$p[0]] ?? throw new RuntimeException("Unknown name: {$p[0]}")),
            'binary' => $this->binary($p[0], $this->evalExpr($p[1], $env), $this->evalExpr($p[2], $env)),
            'section' => [ 'kind' => 'native', 'arity' => 1, 'got' => [],
                'fn' => fn ($x) => $this->binary($p[0], $x, $this->evalExpr($p[1], $env)) ],
            'if' => $this->evalExpr($p[0], $env) ? $this->evalExpr($p[1], $env) :
                $this->evalExpr($p[2], $env),
            'lambda' => ['kind' => 'closure', 'params' => $p[0], 'body' => $p[1], 'env' => $env],
            'apply' => $this->apply($this->evalExpr($p[0], $env), $this->evalExpr($p[1], $env)),
            'list' => array_map(fn ($x) => $this->evalExpr($x, $env), $p[0]),
            default => throw new RuntimeException("Unknown AST node {$node['kind']}"),
        };
    }
    public function run(string $source): array {
        $forms = $this->parse($source);
        $this->steps = 0;
        $results = [];
        foreach ($forms as $form) {
            [$a, $b, $c] = array_pad($form['args'], 3, null);
            if ($form['kind'] === 'def') {
                if (array_key_exists($a, $this->globals)) throw new RuntimeException("Already defined: $a");
                $this->globals[$a] = $b
                    ? ['kind' => 'closure', 'params' => $b, 'body' => $c, 'env' => []]
                    : $this->evalExpr($c, []);
            } else {
                $results[] = $this->evalExpr($a, []);
            }
        }
        return $results;
    }
}

function nailSeed2SelfTest(): string {
    $examples = [
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
    foreach ($examples as [$code, $expected]) {
        $actual = json_encode((new NailSeed2())->run($code));
        if ($actual !== $expected) throw new RuntimeException("FAIL $code\n$actual != $expected");
    }
    return count($examples) . ' tests passed';
}
if (isset($_SERVER['SCRIPT_FILENAME']) && realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    echo nailSeed2SelfTest(), PHP_EOL;
}