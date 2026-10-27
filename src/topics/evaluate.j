# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - evaluation: `validate` and `isValid`, the dispatcher that runs a schema
# object's keywords, references, and the in-place applicators (`allOf`,
# `anyOf`, `oneOf`, `not`, `if` / `then` / `else`).
# Spliced into jsonschema.j via include - not a standalone module.

# How many references in a row evaluation may follow without moving into the
# instance before it is taken to be a cycle. A recursive schema that walks a
# deep instance moves on every level, so it is not limited by this.
def const MAX_DEPTH as int init 200;

# Why evaluation stopped when it reached Jennifer's call-depth limit, which an
# instance nested several hundred levels deep does.
def const TOO_DEEP as string init "the instance is nested too deeply to evaluate";

# Keywords the dispatcher passes over: annotations, keywords another keyword
# reads (`then` is read by `if`, `minContains` by `contains`), and the two
# `unevaluated*` keywords, which `evaluate` runs last.
def const SKIPPED as map of string to bool init {
    "$schema": true,
    "$id": true,
    "$anchor": true,
    "$dynamicAnchor": true,
    "$vocabulary": true,
    "$comment": true,
    "$defs": true,
    "title": true,
    "description": true,
    "default": true,
    "examples": true,
    "deprecated": true,
    "readOnly": true,
    "writeOnly": true,
    "then": true,
    "else": true,
    "minContains": true,
    "maxContains": true,
    "unevaluatedProperties": true,
    "unevaluatedItems": true
};

# Keywords `valueKeyword` owns, whatever the instance type.
def const VALUE_KEYWORDS as map of string to bool init {
    "type": true,
    "enum": true,
    "const": true,
    "format": true,
    "multipleOf": true,
    "minimum": true,
    "maximum": true,
    "exclusiveMinimum": true,
    "exclusiveMaximum": true,
    "minLength": true,
    "maxLength": true,
    "pattern": true
};

/**
 * Validate a value against a compiled schema, collecting every failure.
 *
 * @param s {Schema} the compiled schema
 * @param instance {json.Value} the value to check
 * @return {Result} whether it is valid, and why not
 * @throws {Error} kind `jsonschema` if the schema is malformed where evaluation reaches
 *   it, or the instance is nested too deeply to evaluate
 * @example def r as jsonschema.Result init jsonschema.validate($s, json.decode('"hi"'));
 */
export func validate(s as Schema, instance as json.Value) {
    def o as Outcome init pass();
    try {
        $o = evaluate($s, $s.root, start($s, false), $instance);
    } catch (e) {
        if ($e.kind == "limit") {
            throw Error{kind: ERROR_KIND, message: TOO_DEEP};
        }
        throw $e;
    }
    return Result{valid: $o.valid, errors: $o.errors};
}

/**
 * Whether a value satisfies a compiled schema. Stops at the first failure,
 * so it is quicker than `validate` on an invalid value.
 *
 * @param s {Schema} the compiled schema
 * @param instance {json.Value} the value to check
 * @return {bool} whether it is valid
 * @throws {Error} kind `jsonschema` if the schema is malformed where evaluation reaches
 *   it, or the instance is nested too deeply to evaluate
 */
export func isValid(s as Schema, instance as json.Value) {
    def valid as bool init false;
    try {
        $valid = evaluate($s, $s.root, start($s, true), $instance).valid;
    } catch (e) {
        if ($e.kind == "limit") {
            throw Error{kind: ERROR_KIND, message: TOO_DEEP};
        }
        throw $e;
    }
    return $valid;
}

/**
 * The failures in a result, one line each: where, what, and which keyword.
 * An instance location holding a control character is written as a JSON
 * string, so each failure stays on one line.
 *
 * @param r {Result} a result from `validate`
 * @return {string} the report, `""` for a valid result
 * @example io.printf("%s", jsonschema.describe($r));
 */
export func describe(r as Result) {
    def lines as list of string init [];
    for (def e in $r.errors) {
        def at as string init $e.instancePath;
        if ($at == "") {
            $at = "(root)";
        }
        if (regex.matches('[\x00-\x1f\x7f]', $at)) {
            $at = json.encode($at);
        }
        $lines[] = $at + ": " + $e.message + " [" + $e.schemaPath + "]\n";
    }
    return strings.join($lines, "");
}

/**
 * The position evaluation starts from.
 *
 * @param s {Schema} the compiled schema
 * @param fast {bool} whether to stop at the first error
 * @return {Here} the root position
 */
func start(s as Schema, fast as bool) {
    return Here{
        base: $s.base,
        schemaPath: "",
        instancePath: "",
        scope: [$s.base],
        depth: 0,
        refAt: "",
        fast: $fast
    };
}

/**
 * The position for a subschema under the current one.
 *
 * @param here {Here} the current position
 * @param node {json.Value} the subschema
 * @param schemaStep {string} the escaped pointer from here to the subschema
 * @param instanceStep {string} the escaped pointer from the current value, or `""`
 * @return {Here} the subschema's position, its base and scope adjusted for any `$id`
 */
func into(here as Here, node as json.Value, schemaStep as string, instanceStep as string) {
    def next as Here init $here;
    $next.schemaPath = $here.schemaPath + $schemaStep;
    $next.instancePath = $here.instancePath + $instanceStep;
    if (kindAt($node, "/$id") == "string") {
        $next.base = stripFragment(uri.resolve($here.base, json.asString($node, "/$id")));
        $next.scope[] = $next.base;
    }
    return $next;
}

/**
 * Evaluate a schema against a value.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema to apply: an object or a boolean
 * @param here {Here} its position; `base` already accounts for its own `$id`
 * @param inst {json.Value} the value
 * @return {Outcome} the outcome, with annotations when it passed
 */
func evaluate(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    match (json.typeOf($node)) {
        when "bool" {
            if (json.asBool($node)) {
                return pass();
            }
            return fail($here, "false", "no value is valid here");
        }
        when "map" {
        }
        else { badSchema($here, "a schema is an object or a boolean"); }
    }
    def acc as Outcome init pass();
    for (def k in json.keys($node)) {
        if (maps.has(SKIPPED, $k)) {
            continue;
        }
        def part as Outcome init keyword($s, $node, $here, $inst, $k);
        $acc = merge($acc, $part);
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    # Last, because they depend on what every other keyword here evaluated.
    if (json.has($node, "/unevaluatedItems")) {
        $acc = merge($acc, unevaluatedItems($s, $node, $here, $inst, $acc));
    }
    if (json.has($node, "/unevaluatedProperties")) {
        $acc = merge($acc, unevaluatedProperties($s, $node, $here, $inst, $acc));
    }
    if (not $acc.valid) {
        $acc.props = {};
        $acc.items = 0;
        $acc.hits = {};
    }
    return $acc;
}

/**
 * Apply one keyword of a schema object.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param k {string} the keyword
 * @return {Outcome} the keyword's outcome; a pass for one it does not act on
 */
func keyword(s as Schema, node as json.Value, here as Here, inst as json.Value, k as string) {
    match ($k) {
        when "$ref" { return reference($s, $node, $here, $inst, false); }
        when "$dynamicRef" { return reference($s, $node, $here, $inst, true); }
        when "allOf" { return allOf($s, $node, $here, $inst); }
        when "anyOf" { return anyOf($s, $node, $here, $inst); }
        when "oneOf" { return oneOf($s, $node, $here, $inst); }
        when "not" { return notKeyword($s, $node, $here, $inst); }
        when "if" { return ifThenElse($s, $node, $here, $inst); }
        else {
        }
    }
    if (not $s.validation and lists.contains(VALIDATION_KEYWORDS, $k)) {
        return pass();
    }
    if (maps.has(VALUE_KEYWORDS, $k)) {
        return valueKeyword($s, $node, $here, $inst, $k);
    }
    match (json.typeOf($inst)) {
        when "map" { return objectKeyword($s, $node, $here, $inst, $k); }
        when "list" { return arrayKeyword($s, $node, $here, $inst, $k); }
        else { return pass(); }
    }
}

/**
 * Combine two outcomes of keywords on the same schema and value.
 *
 * Changes and returns `a`, so `$acc = merge($acc, ...)` costs no copy.
 *
 * @param a {Outcome} the outcome so far
 * @param b {Outcome} another keyword's outcome
 * @return {Outcome} both together: valid only if both are, annotations united
 */
func merge(a as Outcome, b as Outcome) {
    if ($b.valid and $b.items == 0 and len($b.props) == 0 and len($b.hits) == 0) {
        return $a;
    }
    $a.valid = $a.valid and $b.valid;
    for (def e in $b.errors) {
        $a.errors[] = $e;
    }
    for (def p in maps.keys($b.props)) {
        $a.props[$p] = true;
    }
    for (def h in maps.keys($b.hits)) {
        $a.hits[$h] = true;
    }
    if ($b.items > $a.items) {
        $a.items = $b.items;
    }
    return $a;
}

/**
 * `$ref` and `$dynamicRef`: evaluate the referenced schema in place.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object holding the reference
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param dynamic {bool} whether this is `$dynamicRef`
 * @return {Outcome} the referenced schema's outcome, annotations included
 * @throws {Error} kind `jsonschema` when the reference resolves to nothing, or loops
 */
func reference(s as Schema, node as json.Value, here as Here, inst as json.Value, dynamic as bool) {
    def k as string init "$ref";
    if ($dynamic) {
        $k = "$dynamicRef";
    }
    if (kindAt($node, "/" + $k) != "string") {
        badSchema($here, $k + " must be a string");
    }
    def ref as string init json.asString($node, "/" + $k);
    def t as Target init resolveRef($s, $here.base, $ref);
    if ($t.location == "") {
        badSchema($here, "cannot resolve " + $k + " " + $ref);
    }
    if ($dynamic) {
        $t = dynamicTarget($s, $here, $t);
    }
    def next as Here init $here;
    if ($here.instancePath != $here.refAt) {
        $next.depth = 0;
        $next.refAt = $here.instancePath;
    }
    if ($next.depth >= MAX_DEPTH) {
        badSchema($here, $k + " " + $ref + " recurses without end");
    }
    $next.schemaPath = $here.schemaPath + "/" + escapeToken($k);
    $next.base = $t.base;
    $next.depth = $next.depth + 1;
    if (lists.last($next.scope) != $t.base) {
        $next.scope[] = $t.base;
    }
    return evaluate($s, $t.node, $next, $inst);
}

/**
 * Where a `$dynamicRef` really goes: the outermost resource in the dynamic
 * scope that has a matching `$dynamicAnchor`, if the reference first lands on
 * a dynamic anchor itself; otherwise where it first landed.
 *
 * @param s {Schema} the compiled schema
 * @param here {Here} the position, carrying the dynamic scope
 * @param first {Target} where the reference resolves statically
 * @return {Target} the target to evaluate
 */
func dynamicTarget(s as Schema, here as Here, first as Target) {
    def name as string init fragmentOf($first.location);
    if ($name == "" or strings.startsWith($name, "/")) {
        return $first;
    }
    if (not maps.has($s.registry.dynamic, stripFragment($first.location) + "#" + $name)) {
        return $first;
    }
    for (def resource in $here.scope) {
        if (maps.has($s.registry.dynamic, $resource + "#" + $name)) {
            return resolveRef($s, $resource, "#" + $name);
        }
    }
    return $first;
}

/**
 * The subschemas of an array-valued applicator, checked for shape.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param k {string} the keyword
 * @return {int} how many subschemas there are
 * @throws {Error} kind `jsonschema` unless the value is a non-empty array
 */
func branchCount(node as json.Value, here as Here, k as string) {
    if (kindAt($node, "/" + $k) != "list" or json.length($node, "/" + $k) == 0) {
        badSchema($here, $k + " must be a non-empty array of schemas");
    }
    return json.length($node, "/" + $k);
}

/**
 * Evaluate the i-th subschema of an array-valued applicator.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param k {string} the keyword
 * @param i {int} which subschema
 * @return {Outcome} its outcome
 */
func branch(
    s as Schema,
    node as json.Value,
    here as Here,
    inst as json.Value,
    k as string,
    i as int) {
    def step as string init "/" + $k + "/" + convert.toString($i);
    def sub as json.Value init json.get($node, $step);
    return evaluate($s, $sub, into($here, $sub, $step, ""), $inst);
}

/**
 * `allOf`: the value must pass every subschema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} every subschema's outcome merged
 */
func allOf(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def acc as Outcome init pass();
    for (def i in 0..branchCount($node, $here, "allOf")) {
        $acc = merge($acc, branch($s, $node, $here, $inst, "allOf", $i));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    return $acc;
}

/**
 * `anyOf`: the value must pass at least one subschema. Every subschema is
 * evaluated, because each one that passes contributes annotations.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the passing subschemas' annotations, or the failures of all
 */
func anyOf(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def passed as Outcome init pass();
    def failed as Outcome init pass();
    def any as bool init false;
    for (def i in 0..branchCount($node, $here, "anyOf")) {
        def o as Outcome init branch($s, $node, $here, $inst, "anyOf", $i);
        if ($o.valid) {
            $any = true;
            $passed = merge($passed, $o);
        } else {
            $failed = merge($failed, $o);
        }
    }
    if ($any) {
        return $passed;
    }
    def out as Outcome init fail($here, "anyOf", "matches none of the anyOf schemas");
    for (def e in $failed.errors) {
        $out.errors[] = $e;
    }
    return $out;
}

/**
 * `oneOf`: the value must pass exactly one subschema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the one passing subschema's outcome, or a failure
 */
func oneOf(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def matched as list of string init [];
    def winner as Outcome init pass();
    def failed as Outcome init pass();
    for (def i in 0..branchCount($node, $here, "oneOf")) {
        def o as Outcome init branch($s, $node, $here, $inst, "oneOf", $i);
        if ($o.valid) {
            $matched[] = convert.toString($i);
            $winner = $o;
        } else {
            $failed = merge($failed, $o);
        }
    }
    if (len($matched) == 1) {
        return $winner;
    }
    if (len($matched) > 1) {
        return fail(
            $here,
            "oneOf",
            "matches oneOf schemas " + strings.join($matched, " and ") + ", not one");
    }
    def out as Outcome init fail($here, "oneOf", "matches none of the oneOf schemas");
    for (def e in $failed.errors) {
        $out.errors[] = $e;
    }
    return $out;
}

/**
 * `not`: the value must fail the subschema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} a pass when the subschema failed, without its annotations
 */
func notKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def sub as json.Value init json.get($node, "/not");
    def inner as Here init into($here, $sub, "/not", "");
    $inner.fast = true;
    if (evaluate($s, $sub, $inner, $inst).valid) {
        return fail($here, "not", "matches the schema under not");
    }
    return pass();
}

/**
 * `if` / `then` / `else`: `then` applies when `if` passes, `else` when it fails.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @return {Outcome} the outcome of `if` (when it passed) merged with the branch taken
 */
func ifThenElse(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def cond as json.Value init json.get($node, "/if");
    def test as Here init into($here, $cond, "/if", "");
    $test.fast = false;
    def o as Outcome init evaluate($s, $cond, $test, $inst);
    def next as string init "/else";
    def acc as Outcome init pass();
    if ($o.valid) {
        $next = "/then";
        $acc = $o;
    }
    if (not json.has($node, $next)) {
        return $acc;
    }
    def sub as json.Value init json.get($node, $next);
    return merge($acc, evaluate($s, $sub, into($here, $sub, $next, ""), $inst));
}
