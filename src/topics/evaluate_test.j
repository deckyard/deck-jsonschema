# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the evaluate topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testSuiteAllOf() {
    assertSuite("allOf.json");
}

func testSuiteAnyOf() {
    assertSuite("anyOf.json");
}

func testSuiteOneOf() {
    assertSuite("oneOf.json");
}

func testSuiteNot() {
    assertSuite("not.json");
}

func testSuiteIfThenElse() {
    assertSuite("if-then-else.json");
}

func testSuiteRef() {
    assertSuite("ref.json");
}

func testSuiteDynamicRef() {
    assertSuite("dynamicRef.json");
}

func testSuiteInfiniteLoopDetection() {
    assertSuite("infinite-loop-detection.json");
}

func testSuiteDefs() {
    assertSuite("defs.json");
}

func testOptionalDynamicRef() {
    assertSuite("optional/dynamicRef.json");
}

func testValidateReportsEveryError() {
    def s as Schema init compile(json.decode('{"properties": {"a": {"type": "string"}, "b": {"minimum": 3}}, "required": ["c"]}'));
    def r as Result init validate($s, json.decode('{"a": 1, "b": 2}'));
    testing.assertFalse($r.valid);
    testing.assertEqual(len($r.errors), 3);
    testing.assertEqual($r.errors[0].instancePath, "/a");
    testing.assertEqual($r.errors[0].schemaPath, "/properties/a/type");
    testing.assertEqual($r.errors[0].keyword, "type");
    testing.assertEqual($r.errors[1].message, "must be >= 3");
}

func testIsValidStopsEarly() {
    def s as Schema init compile(json.decode('{"type": "integer", "minimum": 10}'));
    testing.assertTrue(isValid($s, json.decode("12")));
    testing.assertFalse(isValid($s, json.decode("1.5")));
}

func testSchemaPathFollowsRefs() {
    def s as Schema init compile(json.decode('{"$defs": {"pos": {"minimum": 1}}, "items": {"$ref": "#/$defs/pos"}}'));
    def r as Result init validate($s, json.decode("[1, 0]"));
    testing.assertEqual($r.errors[0].instancePath, "/1");
    testing.assertEqual($r.errors[0].schemaPath, "/items/$ref/minimum");
}

func testDescribe() {
    def s as Schema init compile(json.decode('{"type": "string"}'));
    testing.assertEqual(describe(validate($s, json.decode('"ok"'))), "");
    testing.assertEqual(
        describe(validate($s, json.decode("1"))),
        "(root): expected string, got integer [/type]\n");
}

func testMergeUnitesAnnotations() {
    def a as Outcome init pass();
    $a.props["x"] = true;
    $a.items = 2;
    def b as Outcome init pass();
    $b.props["y"] = true;
    $b.items = 1;
    $b.valid = false;
    def m as Outcome init merge($a, $b);
    testing.assertFalse($m.valid);
    testing.assertEqual(len($m.props), 2);
    testing.assertEqual($m.items, 2);
}

func failUnresolvableRef() {
    validate(compile(json.decode('{"$ref": "#/$defs/missing"}')), json.decode("1"));
}

func testUnresolvableRefIsASchemaError() {
    testing.assertThrows("failUnresolvableRef", ERROR_KIND);
}

func failRefCycle() {
    validate(
        compile(json.decode('{"$defs": {"a": {"$ref": "#/$defs/b"}, "b": {"$ref": "#/$defs/a"}}, "$ref": "#/$defs/a"}')),
        json.decode("1"));
}

func testRefCycleIsASchemaError() {
    testing.assertThrows("failRefCycle", ERROR_KIND);
}

func nested(depth as int) {
    def text as string init "0";
    for (def i in 0..$depth) {
        $text = "[" + $text + "]";
    }
    return json.decode($text);
}

func testDeepRecursiveInstanceIsNotACycle() {
    def s as Schema init compile(json.decode('{"items": {"$ref": "#"}}'));
    testing.assertTrue(isValid($s, nested(300)));
}

func failTooDeep() {
    isValid(compile(json.decode('{"items": {"$ref": "#"}}')), nested(999));
}

func testTooDeepIsASchemaError() {
    testing.assertThrows("failTooDeep", ERROR_KIND);
}

func testDescribeKeepsOneLinePerFailure() {
    def s as Schema init compile(json.decode('{"additionalProperties": {"type": "string"}}'));
    def text as string init describe(validate($s, json.decode('{"a\nb": 1}')));
    testing.assertEqual(len(strings.split($text, "\n")), 2);
}

func testIntoAppliesIds() {
    def here as Here init start(compile(json.decode("true")), false);
    def next as Here init into(
        $here,
        json.decode('{"$id": "https://x.test/s.json"}'),
        "/items",
        "/0");
    testing.assertEqual($next.base, "https://x.test/s.json");
    testing.assertEqual($next.schemaPath, "/items");
    testing.assertEqual($next.instancePath, "/0");
    testing.assertEqual(len($next.scope), 2);
}

func testOneOfNamesTheMatches() {
    def s as Schema init compile(json.decode('{"oneOf": [{"type": "integer"}, {"minimum": 0}]}'));
    testing.assertEqual(
        validate($s, json.decode("1")).errors[0].message,
        "matches oneOf schemas 0 and 1, not one");
}
