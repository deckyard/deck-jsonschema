# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the core topic, and the harness that runs
# the JSON-Schema-Test-Suite files in testdata/suite. Each topic's overlay runs
# the suite files for the keywords it owns.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

# Where the suite's remote documents claim to live.
def const SUITE_HOST as string init "http://localhost:1234/";

def const SUITE_DIR as string init "testdata/suite/";

# The suite lives in the repository, not in the deck: run from an installed
# deck there is no testdata/, so the suite cases pass without running and the
# unit tests still run. testSuiteIsThereInTheRepository keeps a repository run
# from skipping them.
def hasSuite as bool init fs.isDir(SUITE_DIR);

/**
 * A registry holding every remote document the suite references, under the
 * URL the suite gives it.
 *
 * @return {Registry} the registry
 */
func suiteRegistry() {
    def reg as Registry init registry();
    if (not $hasSuite) {
        return $reg;
    }
    def root as string init SUITE_DIR + "remotes/";
    for (def st in fs.walk($root)) {
        if ($st.isDir or not strings.endsWith($st.path, ".json")) {
            continue;
        }
        def rel as string init strings.substring($st.path, len($root), len($st.path));
        $reg = register($reg, SUITE_HOST + $rel, json.decode(fs.readString($st.path)));
    }
    return $reg;
}

# Built once for the whole run: indexing every remote takes longer than most
# suite files do.
def REMOTES as Registry init suiteRegistry();

/**
 * Run one suite file and list every case whose outcome is wrong.
 *
 * @param name {string} the file under tests/draft2020-12, such as `type.json`
 * @return {list of string} one line per wrong case; empty when all pass
 */
func runSuite(name as string) {
    return runSuiteFile($name, false);
}

/**
 * Run one suite file, optionally asserting formats, and list every case
 * whose outcome is wrong. A case that throws counts as wrong.
 *
 * @param name {string} the file under tests/draft2020-12
 * @param formats {bool} whether to compile with `assertFormats`
 * @return {list of string} `file: group / case` for each wrong case
 */
func runSuiteFile(name as string, formats as bool) {
    def path as string init SUITE_DIR + "tests/draft2020-12/" + $name;
    def doc as json.Value init json.decode(fs.readString($path));
    def wrong as list of string init [];
    for (def g in 0..json.length($doc)) {
        def group as json.Value init json.get($doc, "/" + convert.toString($g));
        def title as string init $name + ": " + json.asString($group, "/description");
        for (def t in 0..json.length($group, "/tests")) {
            def c as json.Value init json.get($group, "/tests/" + convert.toString($t));
            def want as string init "invalid";
            if (json.asBool($c, "/valid")) {
                $want = "valid";
            }
            if (caseOutcome(json.get($group, "/schema"), json.get($c, "/data"), $formats) != $want) {
                $wrong[] = $title + " / " + json.asString($c, "/description");
            }
        }
    }
    return $wrong;
}

/**
 * Compile a suite schema and evaluate one value against it, both ways.
 *
 * Compiling per case costs a little time and keeps one bad schema from
 * hiding the outcome of every case in its group.
 *
 * @param schema {json.Value} the group's schema
 * @param data {json.Value} the case's value
 * @param formats {bool} whether to assert formats
 * @return {string} `valid`, `invalid`, `split` when `isValid` and `validate` disagree, or `threw`
 */
func caseOutcome(schema as json.Value, data as json.Value, formats as bool) {
    try {
        def s as Schema init compileWith($schema, $REMOTES);
        if ($formats) {
            $s = assertFormats($s, true);
        }
        def quick as bool init isValid($s, $data);
        if (validate($s, $data).valid != $quick) {
            return "split";
        }
        if ($quick) {
            return "valid";
        }
        return "invalid";
    } catch (e) {
        return "threw";
    }
}

/**
 * The cases testdata/exclusions.txt lists for one suite file: the ones this
 * deck knowingly gets wrong.
 *
 * @param name {string} the suite file
 * @return {list of string} the excluded cases, as `runSuiteFile` names them
 */
func excluded(name as string) {
    def out as list of string init [];
    for (def line in strings.split(fs.readString("testdata/exclusions.txt"), "\n")) {
        if (strings.startsWith($line, $name + ": ")) {
            $out[] = $line;
        }
    }
    return $out;
}

/**
 * Assert a suite file gets exactly its listed exclusions wrong: no new
 * failure, and no exclusion that has started passing and should go.
 *
 * @param name {string} the file under tests/draft2020-12
 */
func assertSuite(name as string) {
    if (not $hasSuite) {
        return;
    }
    def wrong as list of string init runSuiteFile($name, false);
    testing.assertEqual(strings.join($wrong, "\n"), strings.join(excluded($name), "\n"));
}

/**
 * As `assertSuite`, with formats asserted.
 *
 * @param name {string} the file under tests/draft2020-12
 */
func assertFormatSuite(name as string) {
    if (not $hasSuite) {
        return;
    }
    def wrong as list of string init runSuiteFile($name, true);
    testing.assertEqual(strings.join($wrong, "\n"), strings.join(excluded($name), "\n"));
}

func testSuiteIsThereInTheRepository() {
    if (fs.isFile("src/jsonschema.j")) {
        testing.assertTrue($hasSuite);
    }
}

func testEscapeTokenRoundTrips() {
    testing.assertEqual(escapeToken("a/b~c"), "a~1b~0c");
    testing.assertEqual(unescapeToken(escapeToken("a/b~c")), "a/b~c");
    testing.assertEqual(unescapeToken("~01"), "~1");
}

func testChildPointer() {
    testing.assertEqual(childPointer("/properties", "a/b"), "/properties/a~1b");
    testing.assertEqual(childPointer("", "x"), "/x");
}

func testTypeNameTreatsWholeFloatsAsIntegers() {
    testing.assertEqual(typeName(json.decode("1.0")), "integer");
    testing.assertEqual(typeName(json.decode("1.5")), "number");
    testing.assertEqual(typeName(json.decode("3")), "integer");
    testing.assertEqual(typeName(json.decode("true")), "boolean");
    testing.assertEqual(typeName(json.decode("null")), "null");
    testing.assertEqual(typeName(json.decode("[]")), "array");
    testing.assertEqual(typeName(json.decode('{}')), "object");
    testing.assertEqual(typeName(json.decode('"x"')), "string");
}

func testIsWhole() {
    testing.assertTrue(isWhole(2.0));
    testing.assertFalse(isWhole(2.5));
    testing.assertTrue(isWhole(1.0e300));
}

func testIsNumber() {
    testing.assertTrue(isNumber(json.decode("1")));
    testing.assertTrue(isNumber(json.decode("1.5")));
    testing.assertFalse(isNumber(json.decode('"1"')));
}

func testShowShortensLongValues() {
    testing.assertEqual(show(json.decode("[1,2]")), "[1,2]");
    testing.assertEqual(len(show(json.decode(json.encode(strings.repeat("x", 100))))), 60);
}

func testFailRecordsWhereAndWhat() {
    def here as Here init Here{
        base: DEFAULT_BASE,
        schemaPath: "/properties/a",
        instancePath: "/a",
        scope: [],
        depth: 0,
        refAt: "",
        fast: false
    };
    def o as Outcome init fail($here, "minimum", "too small");
    testing.assertFalse($o.valid);
    testing.assertEqual($o.errors[0].schemaPath, "/properties/a/minimum");
    testing.assertEqual($o.errors[0].instancePath, "/a");
    testing.assertTrue(pass().valid);
}

func failBadSchema() {
    badSchema(start(compile(json.decode('{}')), false), "broken");
}

func testBadSchemaThrows() {
    testing.assertThrows("failBadSchema", ERROR_KIND);
}

func testSuiteBooleanSchema() {
    assertSuite("boolean_schema.json");
}
