<?php
/** NailSeed 0.1 — PHP 8 reference interpreter.
 * Same source syntax and core semantics as NailSeed-0.1.js.
 * No dependencies. Run: php NailSeed-0.1.php
 */
declare(strict_types=1);

final class NailSeed {
    private array $dict = [];

    private static function quote(array $nodes): array { return ['t' => 'quote', 'code' => $nodes]; }
    private static function symbol(string $name): array { return ['t' => 'symbol', 'name' => $name]; }
    private static function word(string $name): array { return ['t' => 'word', 'name' => $name]; }
    private static function literal(mixed $value): array { return ['t' => 'literal', 'value' => $value]; }

    public static function parse(string $src): array {
        $clean = preg_replace('/(^|\s)#(?:\s|$).*$/m', '$1', $src);
        $tokens = preg_split('/\s+/', trim($clean), -1, PREG_SPLIT_NO_EMPTY);
        $i = 0;
        $sequence = function(bool $nested) use (&$sequence, &$i, $tokens): array {
            $result = [];
            while ($i < count($tokens)) {
                $t = $tokens[$i++];
                if ($t === ']') {
                    if (!$nested) throw new RuntimeException('Unexpected ]');
                    return $result;
                }
                if ($t === '[') $result[] = self::quote($sequence(true));
                elseif ($t === 'true') $result[] = true;
                elseif ($t === 'false') $result[] = false;
                elseif (preg_match('/^-?(?:\d+(?:\.\d+)?|\.\d+)$/D', $t))
                    $result[] = str_contains($t, '.') ? (float)$t : (int)$t;
                elseif (str_starts_with($t, 's:')) $result[] = rawurldecode(substr($t, 2));
                elseif (preg_match('/^:[A-Za-z_][\w.-]*$/D', $t)) $result[] = self::symbol(substr($t, 1));
                else $result[] = self::word($t);
            }
            if ($nested) throw new RuntimeException('Unclosed [');
            return $result;
        };
        return self::quote($sequence(false));
    }

    private static function pop(array &$s): mixed {
        if (!$s) throw new RuntimeException('Stack underflow');
        return array_pop($s);
    }
    private static function peek(array $s): mixed {
        if (!$s) throw new RuntimeException('Stack underflow');
        return $s[count($s)-1];
    }
    private static function getQuote(array &$s): array {
        $v = self::pop($s);
        if (!is_array($v) || ($v['t'] ?? null) !== 'quote') throw new RuntimeException('Expected quotation');
        return $v;
    }
    private static function getList(array &$s): array {
        $v = self::pop($s);
        if (!is_array($v) || array_key_exists('t', $v)) throw new RuntimeException('Expected list');
        return $v;
    }
    private static function number(mixed $x): bool { return is_int($x) || is_float($x); }
    private function native(string $name, Closure $fn): void { $this->dict[$name] = ['native' => $fn]; }
    private function numeric(string $name, Closure $fn): void {
        $this->native($name, function(array &$s) use ($name, $fn): void {
            $b = self::pop($s); $a = self::pop($s);
            if (!self::number($a) || !self::number($b)) throw new RuntimeException("$name: numbers required");
            $s[] = $fn($a, $b);
        });
    }

    private function execute(array $q, array &$s, array &$ctx, bool $topLevel = false): void {
        foreach ($q['code'] as $node) {
            if (++$ctx['steps'] > $ctx['maxSteps']) throw new RuntimeException('Execution budget exceeded');
            if (is_array($node) && ($node['t'] ?? null) === 'literal') {
                $s[] = $node['value'];
            } elseif (is_array($node) && ($node['t'] ?? null) === 'word') {
                $name = $node['name'];
                if (!isset($this->dict[$name])) throw new RuntimeException('Unknown word: '.$name);
                $entry = $this->dict[$name];
                if (isset($entry['native'])) $entry['native']($s, $ctx, $topLevel);
                else $this->execute($entry['quote'], $s, $ctx, false);
            } else $s[] = $node;
        }
    }
    private function apply(array $q, array $inputs, array &$ctx): mixed {
        $s = $inputs;
        $this->execute($q, $s, $ctx);
        if (count($s) !== 1) throw new RuntimeException('Quotation must produce exactly one value');
        return $s[0];
    }

    public function __construct() {
        $this->native('dup', fn(array &$s) => $s[] = self::peek($s));
        $this->native('drop', fn(array &$s) => self::pop($s));
        $this->native('swap', function(array &$s): void {
            $b = self::pop($s); $a = self::pop($s); $s[] = $b; $s[] = $a;
        });
        $this->native('over', function(array &$s): void {
            if (count($s) < 2) throw new RuntimeException('Stack underflow');
            $s[] = $s[count($s)-2];
        });
        $this->numeric('+', fn($a,$b) => $a+$b);
        $this->numeric('-', fn($a,$b) => $a-$b);
        $this->numeric('*', fn($a,$b) => $a*$b);
        $this->numeric('/', fn($a,$b) => $a/$b);
        $this->numeric('<', fn($a,$b) => $a<$b);
        $this->numeric('>', fn($a,$b) => $a>$b);
        $this->native('=', function(array &$s): void {
            $b = self::pop($s); $a = self::pop($s);
            if (!is_scalar($a) || !is_scalar($b)) throw new RuntimeException('=: scalar values only');
            $s[] = self::number($a) && self::number($b) ? (float)$a === (float)$b : $a === $b;
        });
        $this->native('not', function(array &$s): void {
            $x = self::pop($s);
            if (!is_bool($x)) throw new RuntimeException('not: boolean required');
            $s[] = !$x;
        });
        $this->native('call', function(array &$s, array &$ctx): void {
            $this->execute(self::getQuote($s), $s, $ctx);
        });
        $this->native('dip', function(array &$s, array &$ctx): void {
            $q = self::getQuote($s); $saved = self::pop($s);
            $this->execute($q, $s, $ctx); $s[] = $saved;
        });
        $this->native('curry', function(array &$s): void {
            $q = self::getQuote($s); $value = self::pop($s);
            $s[] = self::quote([self::literal($value), ...$q['code']]);
        });
        $this->native('compose', function(array &$s): void {
            $b = self::getQuote($s); $a = self::getQuote($s);
            $s[] = self::quote([...$a['code'], ...$b['code']]);
        });
        $this->native('if', function(array &$s, array &$ctx): void {
            $otherwise = self::getQuote($s); $then = self::getQuote($s); $condition = self::pop($s);
            if (!is_bool($condition)) throw new RuntimeException('if: boolean required');
            $this->execute($condition ? $then : $otherwise, $s, $ctx);
        });
        $this->native('pack', function(array &$s): void {
            $n = self::pop($s);
            if (!self::number($n) || !is_finite((float)$n) || floor((float)$n) !== (float)$n || $n < 0 || $n > count($s))
                throw new RuntimeException('pack: invalid length');
            $s[] = array_splice($s, count($s)-(int)$n, (int)$n);
        });
        $this->native('map', function(array &$s, array &$ctx): void {
            $q = self::getQuote($s); $xs = self::getList($s); $out = [];
            foreach ($xs as $x) $out[] = $this->apply($q, [$x], $ctx);
            $s[] = $out;
        });
        $this->native('fold', function(array &$s, array &$ctx): void {
            $q = self::getQuote($s); $acc = self::pop($s); $xs = self::getList($s);
            foreach ($xs as $x) $acc = $this->apply($q, [$acc, $x], $ctx);
            $s[] = $acc;
        });
        $this->native('def', function(array &$s, array &$ctx, bool $topLevel): void {
            if (!$topLevel) throw new RuntimeException('def is top-level only');
            $q = self::getQuote($s); $name = self::pop($s);
            if (!is_array($name) || ($name['t'] ?? null) !== 'symbol')
                throw new RuntimeException('def: expected symbol');
            if (isset($this->dict[$name['name']])) throw new RuntimeException('Already defined: '.$name['name']);
            $this->dict[$name['name']] = ['quote' => $q];
        });
    }

    public function run(string $src, int $maxSteps = 100000): array {
        $s = []; $ctx = ['steps' => 0, 'maxSteps' => $maxSteps];
        $this->execute(self::parse($src), $s, $ctx, true);
        return $s;
    }
    public function words(): array { return array_keys($this->dict); }
}

// Run identical smoke tests only when invoked directly.
if (isset($_SERVER['SCRIPT_FILENAME']) && realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    $vm = new NailSeed();
    $tests = [
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
    foreach ($tests as [$src, $expected]) {
        $actual = json_encode($vm->run($src), JSON_UNESCAPED_UNICODE);
        if ($actual !== $expected) throw new RuntimeException("$src => $actual, expected $expected");
        echo "OK $src => $actual\n";
    }
    echo 'NailSeed PHP 0.1: '.count($tests)." tests passed\n";
}