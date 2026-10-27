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
        return stringKeyword($node, $here, $inst, $k);
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
 * `multipleOf`: the value divided by the divisor must be a whole number.
 *
 * Two integers are checked exactly. Otherwise the quotient is allowed a
 * relative error of 1e-9, so `0.0075` is a multiple of `0.0001` although the
 * binary floats say `75.00000000000001`.
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
    def message as string init "must be a multiple of " + show(json.get($node, "/multipleOf"));
    if (json.typeOf($inst) == "int" and kindAt($node, "/multipleOf") == "int") {
        if (json.asInt($inst) % json.asInt($node, "/multipleOf") != 0) {
            return fail($here, "multipleOf", $message);
        }
        return pass();
    }
    # Jennifer raises on float overflow rather than producing infinity, so a
    # quotient too large to represent is caught before the division. It is
    # not a whole number of anything this small.
    def v as float init math.abs(json.asFloat($inst));
    if ($m < 1.0 and $v > 1.0e308 * $m) {
        if (isWhole($v) and isWhole(1.0 / $m)) {
            return pass();
        }
        return fail($here, "multipleOf", $message);
    }
    def q as float init json.asFloat($inst) / $m;
    # Past 2^53 every float is whole, and math.round would not fit an int.
    if (math.abs($q) >= 9007199254740992.0) {
        return pass();
    }
    if (math.abs($q - math.round($q)) > 1.0e-9 * math.max(1.0, math.abs($q))) {
        return fail($here, "multipleOf", $message);
    }
    return pass();
}

/**
 * A string keyword: `minLength`, `maxLength` and `pattern`. Length counts
 * code points, not bytes.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, a string
 * @param k {string} the keyword
 * @return {Outcome} the outcome; a pass for any other keyword
 */
func stringKeyword(node as json.Value, here as Here, inst as json.Value, k as string) {
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
            if (not patternMatches($here, json.asString($node, "/pattern"), $text)) {
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
 * @param here {Here} the position, for the error
 * @param pattern {string} the pattern
 * @param text {string} the string
 * @return {bool} whether it matches
 * @throws {Error} kind `jsonschema` when the pattern does not compile
 */
func patternMatches(here as Here, pattern as string, text as string) {
    def matched as bool init false;
    try {
        $matched = regex.matches(ecmaPattern($pattern), $text);
    } catch (e) {
        badSchema($here, "pattern " + $pattern + " is not a supported regular expression");
    }
    return $matched;
}

/**
 * Rewrite the ECMA-262 syntax RE2 reads differently into ones it reads the
 * same way: `\s` and `\S` cover all Unicode white space in ECMA-262 but only
 * ASCII in RE2, `.` stops at every ECMA-262 line terminator, and RE2 has
 * neither the `\cX` control escape nor `\uXXXX`.
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
 * their braces.
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
        return strings.substring($taken, 0, 4);
    }
    if ($taken == "" or $j >= len($chars) or $chars[$j] != '}') {
        return "";
    }
    return '{' + $taken + '}';
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
    if ($letter == "u" and $code != "") {
        return "\\x" + '{' + $code + '}';
    }
    return "\\" + $letter;
}

/**
 * `format`: an annotation, unless the schema asserts formats.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} a pass, unless formats are asserted and the value is not one
 */
func formatKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    if (not $s.formats or kindAt($node, "/format") != "string") {
        return pass();
    }
    def name as string init json.asString($node, "/format");
    if (formatMatches($name, $inst)) {
        return pass();
    }
    return fail($here, "format", "is not a valid " + $name);
}
