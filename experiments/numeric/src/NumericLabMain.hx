import numeric.BigNat;
import numeric.Rational;
import numeric.LanguageVersion;
import haxe.Json;
import haxe.Resource;

class NumericLabMain {
  static var checks = 0;

  static function eq(actual:String, expected:String, name:String):Void {
    checks++;
    if (actual != expected) throw name + ': expected ' + expected + ', got ' + actual;
  }

  static function fail(f:Void->Void, label:String):Void {
    checks++;
    var failed = false;
    try f() catch (_:Dynamic) { failed = true; }
    if (!failed) throw label + ': expected an error';
  }

  static function operation(a:String, op:String, b:String, expected:String):Void {
    var x = Rational.parse(a), y = Rational.parse(b);
    var result = switch (op) {
      case '+': x.add(y);
      case '-': x.subtract(y);
      case '*': x.multiply(y);
      case '/': x.divide(y);
      case _: throw 'Unknown op';
    }
    eq(result.toString(), expected, a + ' ' + op + ' ' + b);
  }

  static function main():Void {
    // Normalization, integers and decimals
    for (pair in [
      ['0','0'], ['-0','0'], ['0007','7'], ['-0007','-7'],
      ['6/8','3/4'], ['-14/21','-2/3'], ['0/12','0'],
      ['0.1','1/10'], ['0.2','1/5'], ['12.50','25/2'],
      ['-0.125','-1/8'], ['0000.000','0'],
      ['999999999999999999999999999999','999999999999999999999999999999']
    ]) eq(Rational.parse(pair[0]).toString(),pair[1],'parse '+pair[0]);

    operation('1/3','+','1/6','1/2');
    operation('0.1','+','0.2','3/10');
    operation('10','/','4','5/2');
    operation('7/3','-','2/3','5/3');
    operation('2/3','*','9/4','3/2');
    operation('1/2','/','3/4','2/3');
    operation('-3/4','+','1/2','-1/4');
    operation('-3/4','-','1/2','-5/4');
    operation('-2/3','*','-3/5','2/5');
    operation('-2/3','/','-3/5','10/9');
    operation('3/7','+','-3/7','0');
    operation('-3/7','+','3/7','0');
    operation('1/2','-','3/4','-1/4');
    operation('3/4','-','1/2','1/4');
    operation('999999999999999999999999','+','1','1000000000000000000000000');
    operation('999999999999999999999999999999','*','9','8999999999999999999999999999991');
    operation('1/999999999999999999999999999999','*','999999999999999999999999999999','1');
    operation('1/1000000000000000000000000','+','1/1000000000000000000000000','1/500000000000000000000000');

    eq(Std.string(Rational.parse('1/3').compare(Rational.parse('1/2'))),'-1','compare fraction');
    eq(Std.string(Rational.parse('-5').compare(Rational.parse('-3'))),'-1','compare negative');
    eq(Std.string(Rational.parse('8/12').equals(Rational.parse('2/3'))),'true','canonical equality');

    // Core arbitrary-precision algorithms (including quotient + remainder)
    for (entry in [
      ['17','5','3','2'], ['100','25','4','0'], ['1','7','0','1'],
      ['99999999999999999999999999999','9','11111111111111111111111111111','0'],
      ['1000000000000000000000001','10','100000000000000000000000','1']
    ]) {
      var qr = BigNat.divmod(entry[0],entry[1]);
      eq(qr.q,entry[2],'quotient '+entry[0]);
      eq(qr.r,entry[3],'remainder '+entry[0]);
    }
    eq(BigNat.gcd('123456789123456789','987654321987654321'),'9000000009','gcd');
    eq(BigNat.multiply('12345678901234567890','98765432109876543210'),
       '1219326311370217952237463801111263526900','large product');

    // Errors must not silently wrap, truncate or turn into Infinity/NaN
    for (bad in ['','-','1/0','1/','/2','1/2/3','1.','0..1','1e3','+1','abc'])
      fail(() -> { Rational.parse(bad); },'reject '+bad);
    fail(() -> { Rational.parse('1').divide(Rational.parse('0')); },'division by zero');
    fail(() -> { BigNat.subtract('1','2'); },'negative natural subtraction');

    eq(LanguageVersion.detect('def x = 1 ;'),'0.15','default source version');
    eq(LanguageVersion.detect('  \n# nail: 0.16\ndef x = 1/3 ;'),'0.16','exact source header');
    eq(LanguageVersion.detect('# nail: 0.15\ndef x = 1 / 3 ;'),'0.15','legacy source header');
    fail(() -> { LanguageVersion.detect('# nail: 0.17\ndef x = 1 ;'); },'unsupported language version');

    var samples:Array<Dynamic> = cast Json.parse(Resource.getString('numeric-cases'));
    if (samples.length != 270) throw 'Expected 270 independent numeric cases, found ' + samples.length;
    for (c in samples) {
      var a:Rational = Rational.parse(c.a);
      var b:Rational = Rational.parse(c.b);
      var got = switch (c.op) {
        case '+': a.add(b).toString();
        case '-': a.subtract(b).toString();
        case '*': a.multiply(b).toString();
        case '/': a.divide(b).toString();
        case 'cmp': Std.string(a.compare(b));
        case _: throw 'Unknown vector operation';
      };
      eq(got, c.expected, 'Python Fraction oracle: ' + c.a + ' ' + c.op + ' ' + c.b);
    }
    trace('NumericLab: ' + checks + ' tests passed');
  }
}
