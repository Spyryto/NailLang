"""Deterministic independent oracle for NailSeed exact-number lab."""
from fractions import Fraction
import json
import random


def format_fraction(value):
    return (str(value.numerator) if value.denominator == 1
            else f"{value.numerator}/{value.denominator}")


def cases(count=54):
    random.seed(16022026)
    result = []
    for _ in range(count):
        a = Fraction((-1 if random.randint(0, 1) else 1)
                     * random.randrange(1, 10 ** random.randint(3, 38)),
                     random.randrange(1, 10 ** random.randint(1, 25)))
        b = Fraction((-1 if random.randint(0, 1) else 1)
                     * random.randrange(1, 10 ** random.randint(3, 38)),
                     random.randrange(1, 10 ** random.randint(1, 25)))
        for op, expected in [('+', a + b), ('-', a - b),
                             ('*', a * b), ('/', a / b),
                             ('cmp', (a > b) - (a < b))]:
            result.append({'a': format_fraction(a), 'op': op,
                           'b': format_fraction(b),
                           'expected': str(expected) if op == 'cmp'
                           else format_fraction(expected)})
    return result


if __name__ == '__main__':
    print(json.dumps(cases(), indent=2))
