# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the values topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testSuiteType() {
    assertSuite("type.json");
}

func testSuiteEnum() {
    assertSuite("enum.json");
}

func testSuiteConst() {
    assertSuite("const.json");
}

func testSuiteMinimum() {
    assertSuite("minimum.json");
}

func testSuiteMaximum() {
    assertSuite("maximum.json");
}

func testSuiteExclusiveMinimum() {
    assertSuite("exclusiveMinimum.json");
}

func testSuiteExclusiveMaximum() {
    assertSuite("exclusiveMaximum.json");
}

func testSuiteMultipleOf() {
    assertSuite("multipleOf.json");
}

func testSuiteMinLength() {
    assertSuite("minLength.json");
}

func testSuiteMaxLength() {
    assertSuite("maxLength.json");
}

func testSuitePattern() {
    assertSuite("pattern.json");
}

func testSuiteFormat() {
    assertSuite("format.json");
}

func testSuiteDefault() {
    assertSuite("default.json");
}

func testSuiteContent() {
    assertSuite("content.json");
}

func testOptionalBignum() {
    assertSuite("optional/bignum.json");
}

func testOptionalFloatOverflow() {
    assertSuite("optional/float-overflow.json");
}

func testOptionalNonBmpRegex() {
    assertSuite("optional/non-bmp-regex.json");
}

func testOptionalEcmascriptRegex() {
    assertSuite("optional/ecmascript-regex.json");
}

func testTypeAcceptsAList() {
    def s as Schema init compile(json.decode('{"type": ["string", "null"]}'));
    testing.assertTrue(isValid($s, json.decode("null")));
    testing.assertFalse(isValid($s, json.decode("1")));
}

func testMultipleOfToleratesBinaryFloats() {
    def s as Schema init compile(json.decode('{"multipleOf": 0.01}'));
    testing.assertTrue(isValid($s, json.decode("19.99")));
    testing.assertFalse(isValid($s, json.decode("19.995")));
}

func testLengthCountsCodePoints() {
    def s as Schema init compile(json.decode('{"maxLength": 2}'));
    testing.assertTrue(isValid($s, json.decode('"éé"')));
}

func testEcmaPatternTranslatesEscapes() {
    testing.assertEqual(ecmaPattern('^\cC$'), '^\x03$');
    testing.assertEqual(ecmaPattern('\d+'), '\d+');
    testing.assertTrue(strings.startsWith(ecmaPattern('\s'), '[\t'));
    testing.assertTrue(strings.startsWith(ecmaPattern('\S'), "[^"));
    testing.assertTrue(regex.matches(ecmaPattern('^\s$'), json.asString(json.decode('" "'))));
}

func testEcmaEscapeKeepsOthers() {
    testing.assertEqual(ecmaEscape("w", "", false), '\w');
}

func testEcmaPatternTranslatesUnicodeEscapesAndDot() {
    testing.assertEqual(ecmaPattern('^\u0041\u{1F600}$'), '^\x{0041}\x{1F600}$');
    testing.assertEqual(ecmaPattern('[.]'), '[.]');
    testing.assertEqual(ecmaPattern('ab'), 'ab');
    def s as Schema init compile(json.decode('{"pattern": "^.$"}'));
    testing.assertTrue(isValid($s, json.decode('"a"')));
    testing.assertFalse(isValid($s, json.decode('"\r"')));
    testing.assertTrue(isValid(
        compile(json.decode('{"pattern": "^\\u0041$"}')),
        json.decode('"A"')));
}

func testIntegerBoundsCompareExactly() {
    def s as Schema init compile(json.decode('{"maximum": 9007199254740992}'));
    testing.assertTrue(isValid($s, json.decode("9007199254740992")));
    testing.assertFalse(isValid($s, json.decode("9007199254740993")));
}

func testHugeNumbersDoNotOverflow() {
    testing.assertTrue(isValid(compile(json.decode('{"multipleOf": 3.0}')), json.decode("1e300")));
    testing.assertFalse(isValid(compile(json.decode('{"minLength": 1e20}')), json.decode('"a"')));
}

func failTypeListOfNumbers() {
    validate(compile(json.decode('{"type": [1]}')), json.decode("1"));
}

func failPatternNotAString() {
    validate(compile(json.decode('{"pattern": 1}')), json.decode('"a"'));
}

func testMalformedValueKeywordsAreSchemaErrors() {
    testing.assertThrows("failTypeListOfNumbers", ERROR_KIND);
    testing.assertThrows("failPatternNotAString", ERROR_KIND);
}

func failBadPattern() {
    validate(compile(json.decode('{"pattern": "(?<=a)b"}')), json.decode('"ab"'));
}

func testUnsupportedPatternIsASchemaError() {
    testing.assertThrows("failBadPattern", ERROR_KIND);
}

func failNegativeMinLength() {
    validate(compile(json.decode('{"minLength": -1}')), json.decode('"a"'));
}

func testCountRejectsNegativeBounds() {
    testing.assertThrows("failNegativeMinLength", ERROR_KIND);
}
