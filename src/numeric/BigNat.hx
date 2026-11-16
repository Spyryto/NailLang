package numeric;

/**
 * Tiny, portable, NON-NEGATIVE arbitrary-precision integers.
 * Canonical representation: decimal ASCII digits, no leading zeroes.
 * No Haxe Int arithmetic is performed on values > 10*10*digits.length.
 * Algorithms prioritize auditability over performance.
 */
class BigNat {
  public static function clean(s:String):String {
    if (s == null || s.length == 0) throw 'Invalid natural integer';
    for (i in 0...s.length) {
      var c = s.charCodeAt(i);
      if (c < 48 || c > 57) throw 'Invalid natural integer: ' + s;
    }
    var i = 0;
    while (i < s.length - 1 && s.charAt(i) == '0') i++;
    return s.substr(i);
  }

  static inline function digit(s:String, i:Int):Int return s.charCodeAt(i) - 48;

  static function reverse(s:String):String {
    var out = new StringBuf();
    for (i in 0...s.length) out.add(s.charAt(s.length - 1 - i));
    return out.toString();
  }

  /** -1 if a<b, 0 if a==b, +1 if a>b, with canonical inputs. */
  public static function compare(a:String, b:String):Int {
    if (a.length < b.length) return -1;
    if (a.length > b.length) return 1;
    for (i in 0...a.length) {
      var da = digit(a, i), db = digit(b, i);
      if (da < db) return -1;
      if (da > db) return 1;
    }
    return 0;
  }

  public static function add(a:String, b:String):String {
    var i = a.length - 1, j = b.length - 1, carry = 0;
    var out = new StringBuf();
    while (i >= 0 || j >= 0 || carry != 0) {
      var sum = carry;
      if (i >= 0) sum += digit(a, i--);
      if (j >= 0) sum += digit(b, j--);
      out.add(Std.string(sum % 10));
      carry = Std.int(sum / 10);
    }
    return clean(reverse(out.toString()));
  }

  /** a>=b. */
  public static function subtract(a:String, b:String):String {
    if (compare(a, b) < 0) throw 'Negative BigNat subtraction';
    var i = a.length - 1, j = b.length - 1, borrow = 0;
    var out = new StringBuf();
    while (i >= 0) {
      var d = digit(a, i--) - borrow;
      if (j >= 0) d -= digit(b, j--);
      borrow = 0;
      if (d < 0) { d += 10; borrow = 1; }
      out.add(Std.string(d));
    }
    return clean(reverse(out.toString()));
  }

  public static function multiply(a:String, b:String):String {
    if (a == '0' || b == '0') return '0';
    var n = a.length, m = b.length;
    var digits = [for (i in 0...(n + m)) 0];
    for (i in 0...n) for (j in 0...m) {
      digits[i + j] += digit(a, n - 1 - i) * digit(b, m - 1 - j);
    }
    for (k in 0...(n + m - 1)) {
      digits[k + 1] += Std.int(digits[k] / 10);
      digits[k] = digits[k] % 10;
    }
    var out = new StringBuf();
    for (i in 0...(n + m)) out.add(Std.string(digits[n + m - 1 - i]));
    return clean(out.toString());
  }

  /** Grade-school long division. Remainder is always below divisor. */
  public static function divmod(a:String, b:String):{q:String, r:String} {
    if (b == '0') throw 'Division by zero';
    if (compare(a, b) < 0) return {q:'0', r:a};
    var remainder = '0';
    var quotient = new StringBuf();
    for (i in 0...a.length) {
      remainder = clean(remainder + a.charAt(i));
      var qdigit = 0;
      while (compare(remainder, b) >= 0) {
        remainder = subtract(remainder, b);
        qdigit++;
      }
      if (qdigit > 9) throw 'Internal long-division invariant violated';
      quotient.add(Std.string(qdigit));
    }
    return {q:clean(quotient.toString()), r:remainder};
  }

  public static function gcd(a:String, b:String):String {
    while (b != '0') {
      var r = divmod(a, b).r;
      a = b; b = r;
    }
    return a;
  }

  public static function divideExact(a:String, b:String):String {
    var x = divmod(a, b);
    if (x.r != '0') throw 'Not exactly divisible';
    return x.q;
  }
}
