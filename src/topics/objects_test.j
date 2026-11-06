# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the objects topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testSuiteProperties() {
    assertSuite("properties.json");
}

func testSuitePatternProperties() {
    assertSuite("patternProperties.json");
}

func testSuiteAdditionalProperties() {
    assertSuite("additionalProperties.json");
}

func testSuiteRequired() {
    assertSuite("required.json");
}

func testSuiteDependentRequired() {
    assertSuite("dependentRequired.json");
}

func testSuiteDependentSchemas() {
    assertSuite("dependentSchemas.json");
}

func testSuitePropertyNames() {
    assertSuite("propertyNames.json");
}

func testSuiteMinProperties() {
    assertSuite("minProperties.json");
}

func testSuiteMaxProperties() {
    assertSuite("maxProperties.json");
}

func testSuiteUnevaluatedProperties() {
    assertSuite("unevaluatedProperties.json");
}

func testOptionalDependenciesCompatibility() {
    assertSuite("optional/dependencies-compatibility.json");
}

func testAdditionalPropertiesNamesTheProperty() {
    def s as Schema init compile(json.decode('{"properties": {"a": true}, "additionalProperties": false}'));
    def r as Result init validate($s, json.decode('{"a": 1, "b": 2}'));
    testing.assertEqual($r.errors[0].message, 'property "b" is not allowed');
    testing.assertEqual($r.errors[0].instancePath, "");
}

func failRequiredNumbers() {
    validate(compile(json.decode('{"required": [1]}')), json.decode("\{\}"));
}

func failDependentRequiredNotAnObject() {
    validate(compile(json.decode('{"dependentRequired": 1}')), json.decode('{"a": 1}'));
}

func failDependenciesNotAnObject() {
    validate(compile(json.decode('{"dependencies": []}')), json.decode('{"a": 1}'));
}

func testMalformedObjectKeywordsAreSchemaErrors() {
    testing.assertThrows("failRequiredNumbers", ERROR_KIND);
    testing.assertThrows("failDependentRequiredNotAnObject", ERROR_KIND);
    testing.assertThrows("failDependenciesNotAnObject", ERROR_KIND);
}

func testRequiredListsWhatIsMissing() {
    def s as Schema init compile(json.decode('{"required": ["a", "b", "c"]}'));
    testing.assertEqual(
        validate($s, json.decode('{"b": 1}')).errors[0].message,
        'missing required properties: "a", "c"');
}

func testCoveredSeesBothKeywords() {
    def node as json.Value init json.decode('{"properties": {"a": true}, "patternProperties": {"^x": true}}');
    def s as Schema init compile(json.decode("true"));
    def here as Here init start($s, false);
    testing.assertTrue(covered($s, $node, $here, "a"));
    testing.assertTrue(covered($s, $node, $here, "xy"));
    testing.assertFalse(covered($s, $node, $here, "b"));
}

func testDependenciesKeywordBothForms() {
    def s as Schema init compile(json.decode('{"dependencies": {"a": ["b"], "c": {"required": ["d"]}}}'));
    testing.assertFalse(isValid($s, json.decode('{"a": 1}')));
    testing.assertFalse(isValid($s, json.decode('{"c": 1}')));
    testing.assertTrue(isValid($s, json.decode('{"a": 1, "b": 2, "c": 3, "d": 4}')));
}

func testMessagesQuoteAndShortenNames() {
    def long as string init strings.repeat("k", 1000);
    def inst as json.Value init json.decode('{"' + $long + '": 1, "a\nb": 2}');
    for (def schema in [
        '{"additionalProperties": false}',
        '{"propertyNames": {"maxLength": 3}}',
        '{"unevaluatedProperties": false}'
    ]) {
        def r as Result init validate(compile(json.decode($schema)), $inst);
        testing.assertFalse($r.valid);
        for (def e in $r.errors) {
            testing.assertTrue(len($e.message) < 100);
            testing.assertFalse(strings.contains($e.message, "\n"));
        }
    }
    def dep as Result init validate(
        compile(json.decode('{"dependentRequired": {"a\nb": ["c d"]}}')),
        $inst);
    testing.assertEqual($dep.errors[0].message, '"a\nb" requires "c d"');
    testing.assertEqual(
        validate(compile(json.decode('{"dependencies": {"a\nb": ["c"]}}')), $inst).errors[0].message,
        '"a\nb" requires "c"');
}

func testPropertiesWalksTheSmallerSide() {
    def s as Schema init compile(json.decode('{"properties": {"a": {"type": "string"}, "b": true, "c": true}}'));
    testing.assertFalse(isValid($s, json.decode('{"a": 1}')));
    testing.assertTrue(isValid($s, json.decode('{"a": "x", "z": 1}')));
    def small as Schema init compile(json.decode('{"properties": {"a": {"type": "string"}}}'));
    testing.assertFalse(isValid($small, json.decode('{"x": 1, "y": 2, "a": 3}')));
}
