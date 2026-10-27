# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the arrays topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testSuiteItems() {
    assertSuite("items.json");
}

func testSuitePrefixItems() {
    assertSuite("prefixItems.json");
}

func testSuiteContains() {
    assertSuite("contains.json");
}

func testSuiteMinContains() {
    assertSuite("minContains.json");
}

func testSuiteMaxContains() {
    assertSuite("maxContains.json");
}

func testSuiteMinItems() {
    assertSuite("minItems.json");
}

func testSuiteMaxItems() {
    assertSuite("maxItems.json");
}

func testSuiteUniqueItems() {
    assertSuite("uniqueItems.json");
}

func testSuiteUnevaluatedItems() {
    assertSuite("unevaluatedItems.json");
}

func testItemsAfterAShortArray() {
    def s as Schema init compile(json.decode('{"prefixItems": [true, true, true], "items": false}'));
    testing.assertTrue(isValid($s, json.decode("[1]")));
    testing.assertFalse(isValid($s, json.decode("[1, 2, 3, 4]")));
}

func testContainsReportsItsBound() {
    def s as Schema init compile(json.decode('{"contains": {"type": "string"}, "minContains": 2}'));
    testing.assertEqual(validate($s, json.decode('["a", 1]')).errors[0].keyword, "minContains");
}

func testUniqueItemsNamesThePair() {
    def s as Schema init compile(json.decode('{"uniqueItems": true}'));
    testing.assertEqual(
        validate($s, json.decode("[1, 2, 1.0]")).errors[0].message,
        "items 0 and 2 are equal");
}

func testUniqueItemsGroupsEqualValues() {
    def s as Schema init compile(json.decode('{"uniqueItems": true}'));
    testing.assertFalse(isValid($s, json.decode('[{"a": 1, "b": [2]}, {"b": [2.0], "a": 1.0}]')));
    testing.assertTrue(isValid($s, json.decode('[0, false, "0", null, [], {}]')));
    testing.assertEqual(
        sameKey(json.decode('{"b": 1, "a": 2}')),
        sameKey(json.decode('{"a": 2.0, "b": 1}')));
    def big as list of string init [];
    for (def i in 0..5000) {
        $big[] = convert.toString($i);
    }
    testing.assertTrue(isValid($s, json.decode("[" + strings.join($big, ",") + "]")));
}
