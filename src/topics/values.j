# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - keywords on a single value: `type`, `enum`, `const`, the numeric bounds,
# the string length and pattern keywords, and `format`.
# Spliced into jsonschema.j via include - not a standalone module.

# ECMA-262 line terminators, which `.` does not match, as the body of an RE2 class.
def const ECMA_LINE_END as string init '\n\r\x{2028}\x{2029}';

# ECMA-262 white space and line terminators, as the body of an RE2 class.
def const ECMA_SPACE as string init '\t\n\v\f\r \x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}';

def const HEX_DIGITS as list of string init [
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f"
];

/**
 * Apply one value keyword. Keywords this topic does not own pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param k {string} the keyword
 * @return {Outcome} the keyword's outcome
 */
func valueKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value, k as string) {
    match ($k) {
        when "type" { return typeKeyword($node, $here, $inst); }
        when "enum" { return enumKeyword($node, $here, $inst); }
        when "const" { return constKeyword($node, $here, $inst); }
        when "format" { return formatKeyword($s, $node, $here, $inst); }
        else {
        }
    }
    if (isNumber($inst)) {
        return numberKeyword($node, $here, $inst, $k);
    }
    if (json.typeOf($inst) == "string") {
        return stringKeyword($s, $node, $here, $inst, $k);
    }
    return pass();
}

/**
 * `type`: one type name, or an array of them.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the outcome
 */
func typeKeyword(node as json.Value, here as Here, inst as json.Value) {
    def wanted as list of string init [];
    match (kindAt($node, "/type")) {
        when "string" { $wanted[] = json.asString($node, "/type"); }
        when "list" {
            for (def i in 0..json.length($node, "/type")) {
                def at as string init "/type/" + convert.toString($i);
                if (kindAt($node, $at) != "string") {
                    badSchema($here, "type must be a string or an array of strings");
                }
                $wanted[] = json.asString($node, $at);
            }
        }
        else { badSchema($here, "type must be a string or an array of strings"); }
    }
    def actual as string init typeName($inst);
    for (def w in $wanted) {
        if ($w == $actual or ($w == "number" and $actual == "integer")) {
            return pass();
        }
    }
    return fail($here, "type", "expected " + strings.join($wanted, " or ") + ", got " + $actual);
}

/**
 * `enum`: the value must equal one of the listed values.
 *
 * Equality is JSON Schema's: `1` equals `1.0`, `0` does not equal `false`,
 * and objects compare regardless of key order.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the outcome
 */
func enumKeyword(node as json.Value, here as Here, inst as json.Value) {
    if (kindAt($node, "/enum") != "list") {
        badSchema($here, "enum must be an array");
    }
    for (def i in 0..json.length($node, "/enum")) {
        if (json.get($node, "/enum/" + convert.toString($i)) == $inst) {
            return pass();
        }
    }
    return fail($here, "enum", show($inst) + " is not one of " + show(json.get($node, "/enum")));
}

/**
 * `const`: the value must equal one value.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the outcome
 */
func constKeyword(node as json.Value, here as Here, inst as json.Value) {
    if (json.get($node, "/const") == $inst) {
        return pass();
    }
    return fail($here, "const", "must be " + show(json.get($node, "/const")));
}

/**
 * The number a numeric keyword carries.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param k {string} the keyword
 * @return {float} its value
 * @throws {Error} kind `jsonschema` when it is not a number
 */
func bound(node as json.Value, here as Here, k as string) {
    if (not isNumber(json.get($node, "/" + $k))) {
        badSchema($here, $k + " must be a number");
    }
    return json.asFloat($node, "/" + $k);
}

/**
 * How a number compares with the bound a numeric keyword carries.
 *
 * Two integers compare exactly; anything else as floats, which past 2^53
 * cannot tell neighbouring integers apart.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, a number
 * @param k {string} the keyword
 * @return {int} -1, 0 or 1 as the value is below, at or above the bound
 * @throws {Error} kind `jsonschema` when the bound is not a number
 */
func compareBound(node as json.Value, here as Here, inst as json.Value, k as string) {
    def b as float init bound($node, $here, $k);
    if (json.typeOf($inst) == "int" and kindAt($node, "/" + $k) == "int") {
        def x as int init json.asInt($inst);
        def y as int init json.asInt($node, "/" + $k);
        if ($x < $y) {
            return -1;
        }
        if ($x > $y) {
            return 1;
        }
        return 0;
    }
    def v as float init json.asFloat($inst);
    if ($v < $b) {
        return -1;
    }
    if ($v > $b) {
        return 1;
    }
    return 0;
}

/**
 * A numeric keyword: `multipleOf`, `minimum`, `maximum` and the exclusive pair.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, a number
 * @param k {string} the keyword
 * @return {Outcome} the outcome; a pass for any other keyword
 */
func numberKeyword(node as json.Value, here as Here, inst as json.Value, k as string) {
    match ($k) {
        when "multipleOf" { return multipleOf($node, $here, $inst); }
        when "minimum" {
            if (compareBound($node, $here, $inst, $k) < 0) {
                return fail($here, $k, "must be >= " + show(json.get($node, "/minimum")));
            }
        }
        when "maximum" {
            if (compareBound($node, $here, $inst, $k) > 0) {
                return fail($here, $k, "must be <= " + show(json.get($node, "/maximum")));
            }
        }
        when "exclusiveMinimum" {
            if (compareBound($node, $here, $inst, $k) <= 0) {
                return fail($here, $k, "must be > " + show(json.get($node, "/exclusiveMinimum")));
            }
        }
        when "exclusiveMaximum" {
            if (compareBound($node, $here, $inst, $k) >= 0) {
                return fail($here, $k, "must be < " + show(json.get($node, "/exclusiveMaximum")));
            }
        }
        else {
        }
    }
    return pass();
}

/**
 * A number as `coefficient * 10^exponent`, read from its shortest decimal
 * text: the digits `convert.toString` prints, which is what a JSON document
 * spelled unless it gave more digits than a float holds.
 *
 * @field coefficient {int} the significant digits, trailing zeros removed; -1 when they do not fit
 * @field exponent {int} the power of ten
 * @field digits {int} how many digits `coefficient` has
 */
def struct Decimal {
    coefficient as int,
    exponent as int,
    digits as int
};

/**
 * `multipleOf`: the value divided by the divisor must be a whole number.
 *
 * Exact, with no tolerance. Two whole numbers inside the int range use the
 * int remainder, whatever their JSON spelling (`2.0`, `1e9`). Otherwise both
 * are compared as decimals (`decimalOf`): `0.0075` is a multiple of
 * `0.0001` although the binary quotient is `75.00000000000001`, and
 * `1000000000000000.25` is not a multiple of `0.5`. Only a whole divisor
 * of 18 or more significant digits against a value past 2^63 falls back to
 * the float quotient, within 4 ulps.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, a number
 * @return {Outcome} the outcome
 */
func multipleOf(node as json.Value, here as Here, inst as json.Value) {
    def m as float init bound($node, $here, "multipleOf");
    if ($m <= 0.0) {
        badSchema($here, "multipleOf must be greater than 0");
    }
    def d as json.Value init json.get($node, "/multipleOf");
    def message as string init "must be a multiple of " + show($d);
    if (isIntValue($d)) {
        if (isIntValue($inst)) {
            if (intOf($inst) % intOf($d) != 0) {
                return fail($here, "multipleOf", $message);
            }
            return pass();
        }
        # A whole divisor goes only into a whole value.
        if (typeName($inst) != "integer") {
            return fail($here, "multipleOf", $message);
        }
    }
    def exact as int init decimalMultiple(decimalOf($inst), decimalOf($d));
    if ($exact == 1) {
        return pass();
    }
    if ($exact == 0) {
        return fail($here, "multipleOf", $message);
    }
    def q as float init json.asFloat($inst) / $m;
    # Past 2^53 every float is whole, and math.round would not fit an int.
    if (math.abs($q) >= 9007199254740992.0) {
        return pass();
    }
    if (math.abs($q - math.round($q)) > 8.9e-16 * math.max(1.0, math.abs($q))) {
        return fail($here, "multipleOf", $message);
    }
    return pass();
}

/**
 * Whether a number is a whole number `intOf` can return exactly.
 *
 * @param v {json.Value} the number
 * @return {bool} whether it is an int, or a whole float inside the int range
 */
func isIntValue(v as json.Value) {
    if (json.typeOf($v) == "int") {
        return true;
    }
    return fitsInt(json.asFloat($v));
}

/**
 * A whole number as an int.
 *
 * @param v {json.Value} a number for which `isIntValue` holds
 * @return {int} its value
 */
func intOf(v as json.Value) {
    if (json.typeOf($v) == "int") {
        return json.asInt($v);
    }
    return convert.toInt(json.asFloat($v));
}

/**
 * A number's shortest decimal text as a `Decimal`.
 *
 * @param v {json.Value} the number
 * @return {Decimal} its digits and exponent, its sign dropped
 */
func decimalOf(v as json.Value) {
    def text as string init "";
    if (json.typeOf($v) == "int") {
        $text = convert.toString(json.asInt($v));
    } else {
        $text = convert.toString(json.asFloat($v));
    }
    if (strings.startsWith($text, "-")) {
        $text = strings.substring($text, 1, len($text));
    }
    def exponent as int init 0;
    def e as int init strings.indexOf($text, "e");
    if ($e >= 0) {
        def power as string init strings.substring($text, $e + 1, len($text));
        if (strings.startsWith($power, "+")) {
            $power = strings.substring($power, 1, len($power));
        }
        $exponent = convert.toInt($power);
        $text = strings.substring($text, 0, $e);
    }
    def dot as int init strings.indexOf($text, ".");
    if ($dot >= 0) {
        $exponent = $exponent - (len($text) - $dot - 1);
        $text = strings.substring($text, 0, $dot) + strings.substring($text, $dot + 1, len($text));
    }
    def from as int init 0;
    while ($from < len($text) and strings.substring($text, $from, $from + 1) == "0") {
        $from = $from + 1;
    }
    def to2 as int init len($text);
    while ($to2 > $from and strings.substring($text, $to2 - 1, $to2) == "0") {
        $to2 = $to2 - 1;
        $exponent = $exponent + 1;
    }
    if ($to2 == $from) {
        return Decimal{coefficient: 0, exponent: 0, digits: 0};
    }
    if ($to2 - $from > 18) {
        return Decimal{coefficient: -1, exponent: $exponent, digits: $to2 - $from};
    }
    return Decimal{
        coefficient: convert.toInt(strings.substring($text, $from, $to2)),
        exponent: $exponent,
        digits: $to2 - $from
    };
}

/**
 * Whether one decimal is a whole multiple of another, in int arithmetic.
 *
 * @param a {Decimal} the value
 * @param b {Decimal} the divisor, not zero
 * @return {int} 1 when it is, 0 when it is not, -1 when the digits do not fit an int
 */
func decimalMultiple(a as Decimal, b as Decimal) {
    if ($a.coefficient == 0) {
        return 1;
    }
    if ($a.coefficient < 0 or $b.coefficient < 0 or $b.digits > 17) {
        return -1;
    }
    if ($a.exponent >= $b.exponent) {
        # a.c * 10^k mod b.c, one power of ten at a time: r * 10 stays
        # below 10^18 because b.c has at most 17 digits.
        def r as int init $a.coefficient % $b.coefficient;
        def k as int init $a.exponent - $b.exponent;
        while ($k > 0 and $r != 0) {
            $r = ($r * 10) % $b.coefficient;
            $k = $k - 1;
        }
        if ($r == 0) {
            return 1;
        }
        return 0;
    }
    # b.c * 10^k must divide a.c; it is larger than a.c once it has more digits.
    def k as int init $b.exponent - $a.exponent;
    if ($b.digits + $k > $a.digits) {
        return 0;
    }
    if ($b.digits + $k > 18) {
        return -1;
    }
    def divisor as int init $b.coefficient;
    for (def i in 0..$k) {
        $divisor = $divisor * 10;
    }
    if ($a.coefficient % $divisor == 0) {
        return 1;
    }
    return 0;
}

/**
 * A string keyword: `minLength`, `maxLength` and `pattern`. Length counts
 * code points, not bytes.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, a string
 * @param k {string} the keyword
 * @return {Outcome} the outcome; a pass for any other keyword
 */
func stringKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value, k as string) {
    def text as string init json.asString($inst);
    match ($k) {
        when "minLength" {
            if (len($text) < count($node, $here, $k)) {
                return fail($here, $k, "must be at least " + limitText($node, $k) + " characters");
            }
        }
        when "maxLength" {
            if (len($text) > count($node, $here, $k)) {
                return fail($here, $k, "must be at most " + limitText($node, $k) + " characters");
            }
        }
        when "pattern" {
            if (kindAt($node, "/pattern") != "string") {
                badSchema($here, "pattern must be a string");
            }
            if (not patternMatches($s, $here, json.asString($node, "/pattern"), $text)) {
                return fail(
                    $here,
                    $k,
                    "does not match the pattern " + json.asString($node, "/pattern"));
            }
        }
        else {
        }
    }
    return pass();
}

/**
 * The non-negative integer a counting keyword carries, such as `minLength`.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param k {string} the keyword
 * @return {int} its value, at most 2^53: no length or count comes near it
 * @throws {Error} kind `jsonschema` unless it is a non-negative integer
 */
func count(node as json.Value, here as Here, k as string) {
    def v as json.Value init json.get($node, "/" + $k);
    if (typeName($v) != "integer" or json.asFloat($v) < 0.0) {
        badSchema($here, $k + " must be a non-negative integer");
    }
    if (json.asFloat($v) >= 9007199254740992.0) {
        return 9007199254740992;
    }
    return convert.toInt(json.asFloat($v));
}

/**
 * Whether a pattern matches anywhere in a string. Patterns are unanchored,
 * as in ECMA-262.
 *
 * Jennifer's regular expressions are RE2: there is no lookaround and no
 * backreference, and a pattern that needs them is reported as a schema error
 * rather than silently matching nothing.
 *
 * @param s {Schema} the compiled schema, holding the patterns `compile` translated
 * @param here {Here} the position, for the error
 * @param pattern {string} the pattern
 * @param text {string} the string
 * @return {bool} whether it matches
 * @throws {Error} kind `jsonschema` when the pattern does not compile
 */
func patternMatches(s as Schema, here as Here, pattern as string, text as string) {
    def translated as string init "";
    if (maps.has($s.patterns, $pattern)) {
        $translated = $s.patterns[$pattern];
    } else {
        $translated = ecmaPattern($pattern);
    }
    def matched as bool init false;
    try {
        $matched = regex.matches($translated, $text);
    } catch (e) {
        if ($e.kind == "limit") {
            throw $e;
        }
        badSchema($here, "pattern " + $pattern + " is not a supported regular expression");
    }
    return $matched;
}

/**
 * Rewrite the ECMA-262 syntax RE2 reads differently into ones it reads the
 * same way: `\s` and `\S` cover all Unicode white space in ECMA-262 but only
 * ASCII in RE2, `.` stops at every ECMA-262 line terminator, and RE2 has
 * neither the `\cX` control escape nor `\uXXXX` (a surrogate pair of them is
 * one code point) nor `\u{...}`.
 *
 * `\S` inside a class keeps RE2's ASCII meaning: RE2 cannot put a negated
 * class inside another.
 *
 * @param pattern {string} an ECMA-262 pattern
 * @return {string} the pattern for RE2
 */
func ecmaPattern(pattern as string) {
    if (not strings.contains($pattern, "\\") and not strings.contains($pattern, ".")) {
        return $pattern;
    }
    def chars as list of string init strings.chars($pattern);
    def out as list of string init [];
    def inClass as bool init false;
    def i as int init 0;
    while ($i < len($chars)) {
        def c as string init $chars[$i];
        $i = $i + 1;
        if ($c == "\\" and $i < len($chars)) {
            def next as string init $chars[$i];
            $i = $i + 1;
            def code as string init escapeCode($next, $chars, $i);
            $out[] = ecmaEscape($next, $code, $inClass);
            $i = $i + len($code);
            continue;
        }
        if ($c == "[") {
            $inClass = true;
        }
        if ($c == "]") {
            $inClass = false;
        }
        if ($c == "." and not $inClass) {
            $out[] = "[^" + ECMA_LINE_END + "]";
            continue;
        }
        $out[] = $c;
    }
    return strings.join($out, "");
}

/**
 * The characters after an escape letter that belong to the escape: the
 * letter of `\cX`, or the hex digits of `\uXXXX` or `\u{X...}` with
 * their braces. A lead surrogate (`\uD800`-`\uDBFF`) followed by a trail
 * (`\uDC00`-`\uDFFF`) takes both, `\u` included: ECMA-262 reads the pair as
 * one code point.
 *
 * @param letter {string} the character after the backslash
 * @param chars {list of string} the whole pattern
 * @param at {int} the index after `letter`
 * @return {string} the characters taken, `""` for none
 */
func escapeCode(letter as string, chars as list of string, at as int) {
    if ($at >= len($chars)) {
        return "";
    }
    if ($letter == "c" and regex.matches("^[A-Za-z]$", $chars[$at])) {
        return $chars[$at];
    }
    if ($letter != "u") {
        return "";
    }
    def taken as string init "";
    def j as int init $at;
    if ($chars[$at] == '{') {
        $j = $j + 1;
    }
    while ($j < len($chars) and regex.matches("^[0-9A-Fa-f]$", $chars[$j])) {
        $taken = $taken + $chars[$j];
        $j = $j + 1;
    }
    if ($chars[$at] != '{') {
        if (len($taken) < 4) {
            return "";
        }
        def unit as string init strings.substring($taken, 0, 4);
        if (isLeadSurrogate($unit) and $at + 10 <= len($chars)) {
            def trail as string init strings.join(lists.slice($chars, $at + 4, $at + 10), "");
            if (regex.matches('^\\u[dD][c-fC-F][0-9A-Fa-f]{2}$', $trail)) {
                return $unit + $trail;
            }
        }
        return $unit;
    }
    if ($taken == "" or $j >= len($chars) or $chars[$j] != '}') {
        return "";
    }
    return '{' + $taken + '}';
}

/**
 * Whether four hex digits name a UTF-16 lead surrogate, U+D800 to U+DBFF.
 *
 * @param hex {string} four hex digits
 * @return {bool} whether a trail surrogate should follow
 */
func isLeadSurrogate(hex as string) {
    def n as int init convert.toInt($hex, 16);
    return $n >= 55296 and $n <= 56319;
}

/**
 * The RE2 spelling of one ECMA-262 escape.
 *
 * @param letter {string} the character after the backslash
 * @param code {string} what `escapeCode` took after it
 * @param inClass {bool} whether the escape sits inside a character class
 * @return {string} the replacement text
 */
func ecmaEscape(letter as string, code as string, inClass as bool) {
    if ($letter == "s") {
        if ($inClass) {
            return ECMA_SPACE;
        }
        return "[" + ECMA_SPACE + "]";
    }
    if ($letter == "S" and not $inClass) {
        return "[^" + ECMA_SPACE + "]";
    }
    if ($letter == "c" and $code != "") {
        def n as int init convert.toCodepoint($code) % 32;
        def high as string init "0";
        if ($n >= 16) {
            $high = "1";
        }
        return "\\x" + $high + HEX_DIGITS[$n % 16];
    }
    if ($letter == "u" and strings.startsWith($code, '{')) {
        return "\\x" + $code;
    }
    if ($letter == "u" and len($code) == 10) {
        def high as int init convert.toInt(strings.substring($code, 0, 4), 16);
        def low as int init convert.toInt(strings.substring($code, 6, 10), 16);
        def point as int init 65536 + ($high - 55296) * 1024 + ($low - 56320);
        return "\\x" + '{' + convert.toString($point, 16) + '}';
    }
    if ($letter == "u" and $code != "") {
        return "\\x" + '{' + $code + '}';
    }
    return "\\" + $letter;
}

/**
 * `format`: an annotation, unless formats are asserted. `assertFormats`
 * checks the known formats and passes the rest; the format-assertion
 * vocabulary also fails a format name nobody knows.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} a pass, unless formats are asserted and the value is not one
 * @throws {Error} kind `jsonschema` for a format in `UNCHECKED_FORMATS` under the vocabulary
 */
func formatKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    if (not $here.strict and not $s.formats) {
        return pass();
    }
    if (kindAt($node, "/format") != "string") {
        return pass();
    }
    def name as string init json.asString($node, "/format");
    if ($here.strict and not maps.has(CHECKED_FORMATS, $name)) {
        if (maps.has(UNCHECKED_FORMATS, $name)) {
            badSchema(
                $here,
                "format " + quoted($name) + " is asserted, and this deck cannot check it");
        }
        return fail($here, "format", "format " + quoted($name) + " is unknown");
    }
    if (formatMatches($name, $inst)) {
        return pass();
    }
    return fail($here, "format", "is not a valid " + $name);
}
