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
        "missing required properties: a, c");
}

func testCoveredSeesBothKeywords() {
    def node as json.Value init json.decode('{"properties": {"a": true}, "patternProperties": {"^x": true}}');
    def here as Here init start(compile(json.decode("true")), false);
    testing.assertTrue(covered($node, $here, "a"));
    testing.assertTrue(covered($node, $here, "xy"));
    testing.assertFalse(covered($node, $here, "b"));
}

func testDependenciesKeywordBothForms() {
    def s as Schema init compile(json.decode('{"dependencies": {"a": ["b"], "c": {"required": ["d"]}}}'));
    testing.assertFalse(isValid($s, json.decode('{"a": 1}')));
    testing.assertFalse(isValid($s, json.decode('{"c": 1}')));
    testing.assertTrue(isValid($s, json.decode('{"a": 1, "b": 2, "c": 3, "d": 4}')));
}
