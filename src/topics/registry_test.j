# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the registry topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testSuiteAnchor() {
    assertSuite("anchor.json");
}

func testSuiteRefRemote() {
    assertSuite("refRemote.json");
}

func testSuiteVocabulary() {
    assertSuite("vocabulary.json");
}

func testOptionalAnchor() {
    assertSuite("optional/anchor.json");
}

func testOptionalId() {
    assertSuite("optional/id.json");
}

func testOptionalNoSchema() {
    assertSuite("optional/no-schema.json");
}

func testOptionalRefOfUnknownKeyword() {
    assertSuite("optional/refOfUnknownKeyword.json");
}

func testOptionalUnknownKeyword() {
    assertSuite("optional/unknownKeyword.json");
}

func testOptionalCrossDraft() {
    assertSuite("optional/cross-draft.json");
}

func testOptionalFormatAssertion() {
    assertSuite("optional/format-assertion.json");
}

func failRegisterRelative() {
    register(registry(), "relative.json", json.decode("true"));
}

func failBadPercentRef() {
    validate(compile(json.decode('{"$ref": "#/%ZZ"}')), json.decode("1"));
}

func testBadPercentRefIsASchemaError() {
    testing.assertThrows("failBadPercentRef", ERROR_KIND);
}

func testRegisterNeedsAnAbsoluteUri() {
    testing.assertThrows("failRegisterRelative", ERROR_KIND);
}

func failCompileScalar() {
    compile(json.decode("3"));
}

func testCompileRejectsAScalar() {
    testing.assertThrows("failCompileScalar", ERROR_KIND);
}

func testRegisteredDocumentIsReachable() {
    def reg as Registry init register(
        registry(),
        "https://example.com/positive.json",
        json.decode('{"minimum": 1}'));
    def s as Schema init compileWith(
        json.decode('{"$ref": "https://example.com/positive.json"}'),
        $reg);
    testing.assertTrue(isValid($s, json.decode("5")));
    testing.assertFalse(isValid($s, json.decode("0")));
}

func testCompileUsesTheRootId() {
    def s as Schema init compile(json.decode('{"$id": "https://example.com/a/root.json"}'));
    testing.assertEqual($s.base, "https://example.com/a/root.json");
    testing.assertEqual(compile(json.decode("true")).base, DEFAULT_BASE);
}

func testIndexRecordsAnchorsAndEmbeddedResources() {
    def doc as json.Value init json.decode('{"$id": "https://x.test/r", "$defs": {"a": {"$anchor": "here"}, "b": {"$id": "b.json", "$dynamicAnchor": "d"}}}');
    def reg as Registry init indexDocument(registry(), $doc, DEFAULT_BASE);
    testing.assertTrue(maps.has($reg.resources, "https://x.test/r"));
    testing.assertTrue(maps.has($reg.resources, "https://x.test/b.json"));
    testing.assertEqual($reg.anchors["https://x.test/r#here"], "https://x.test/r#/$defs/a");
    testing.assertTrue(maps.has($reg.dynamic, "https://x.test/b.json#d"));
}

func testMetaSchemasLoadOnlyWhenReferenced() {
    testing.assertFalse(compile(json.decode('{"type": "string"}')).registry.meta);
    def s as Schema init compile(json.decode('{"$ref": "https://json-schema.org/draft/2020-12/schema"}'));
    testing.assertTrue($s.registry.meta);
    testing.assertTrue(isValid($s, json.decode('{"type": "string"}')));
    testing.assertFalse(isValid($s, json.decode('{"type": 3}')));
    testing.assertEqual(len(metaDocuments()), 8);
}

func testRefersToMeta() {
    testing.assertTrue(refersToMeta(json.decode('{"$ref": "https://json-schema.org/draft/2020-12/meta/core"}')));
    testing.assertFalse(refersToMeta(json.decode('{"$ref": "#/$defs/a"}')));
}

func testSubschemasSkipsData() {
    def node as json.Value init json.decode('{"properties": {"a/b": true}, "allOf": [true, false], "not": true, "enum": [{"$id": "x"}]}');
    def found as list of string init subschemas($node);
    testing.assertContains($found, "/properties/a~1b");
    testing.assertContains($found, "/allOf/1");
    testing.assertContains($found, "/not");
    testing.assertEqual(len($found), 4);
}

func testResolveRefFollowsPointersAndAnchors() {
    def s as Schema init compile(json.decode('{"$defs": {"n": {"$anchor": "num", "type": "number"}}}'));
    testing.assertEqual(resolveRef($s, $s.base, "#/$defs/n").location, DEFAULT_BASE + "#/$defs/n");
    testing.assertEqual(json.asString(resolveRef($s, $s.base, "#num").node, "/type"), "number");
    testing.assertEqual(resolveRef($s, $s.base, "#nowhere").location, "");
    testing.assertEqual(resolveRef($s, $s.base, "https://elsewhere.test/x").location, "");
}

func testWalkPointerPicksUpIds() {
    def doc as json.Value init json.decode('{"$defs": {"inner": {"$id": "sub/inner.json", "type": "string"}}}');
    def t as Target init walkPointer($doc, "https://x.test/root.json", "/$defs/inner", "loc");
    testing.assertEqual($t.base, "https://x.test/sub/inner.json");
    testing.assertEqual(
        walkPointer($doc, "https://x.test/root.json", "/missing", "loc").location,
        "");
}

func testUriHelpers() {
    testing.assertEqual(stripFragment("https://a.test/x#frag"), "https://a.test/x");
    testing.assertEqual(stripFragment("https://a.test/x"), "https://a.test/x");
    testing.assertEqual(fragmentOf("https://a.test/x#/a/b"), "/a/b");
    testing.assertEqual(fragmentOf("https://a.test/x"), "");
    testing.assertTrue(isAbsolute("urn:example:a"));
    testing.assertFalse(isAbsolute("a/b.json"));
}

func testAssertFormatsTogglesFormat() {
    def s as Schema init compile(json.decode('{"format": "ipv4"}'));
    testing.assertTrue(isValid($s, json.decode('"not an address"')));
    testing.assertFalse(isValid(assertFormats($s, true), json.decode('"not an address"')));
}

func testUsesVocabularyFallsBack() {
    def s as Schema init compile(json.decode('{"type": "string"}'));
    testing.assertTrue(usesVocabulary($s, VOCAB_VALIDATION, true));
    testing.assertFalse(usesVocabulary($s, VOCAB_FORMAT_ASSERTION, false));
}
