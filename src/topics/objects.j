# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - keywords on objects: `properties`, `patternProperties`,
# `additionalProperties`, `required`, `dependentRequired`,
# `dependentSchemas`, `propertyNames`, `minProperties`, `maxProperties` and
# `unevaluatedProperties`.
# Spliced into jsonschema.j via include - not a standalone module.

/**
 * Apply one object keyword. Keywords this topic does not own pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, an object
 * @param k {string} the keyword
 * @return {Outcome} the keyword's outcome
 */
func objectKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value, k as string) {
    def n as int init json.length($inst);
    match ($k) {
        when "properties" { return properties($s, $node, $here, $inst); }
        when "patternProperties" { return patternProperties($s, $node, $here, $inst); }
        when "additionalProperties" { return additionalProperties($s, $node, $here, $inst); }
        when "propertyNames" { return propertyNames($s, $node, $here, $inst); }
        when "dependentSchemas" { return dependentSchemas($s, $node, $here, $inst); }
        when "required" { return required($node, $here, $inst); }
        when "dependentRequired" { return dependentRequired($node, $here, $inst); }
        when "dependencies" { return dependencies($s, $node, $here, $inst); }
        when "minProperties" {
            if ($n < count($node, $here, $k)) {
                return fail(
                    $here,
                    $k,
                    "must have at least " + limitText($node, "minProperties") +
                        " properties");
            }
        }
        when "maxProperties" {
            if ($n > count($node, $here, $k)) {
                return fail(
                    $here,
                    $k,
                    "must have at most " + limitText($node, "maxProperties") +
                        " properties");
            }
        }
        else {
        }
    }
    return pass();
}

/**
 * Evaluate one property's value against a subschema.
 *
 * @param s {Schema} the compiled schema
 * @param sub {json.Value} the subschema
 * @param here {Here} the object's position
 * @param step {string} the escaped pointer from the schema object to `sub`
 * @param inst {json.Value} the object
 * @param name {string} the property
 * @return {Outcome} the outcome, annotating the property when it passed
 */
func property(
    s as Schema,
    sub as json.Value,
    here as Here,
    step as string,
    inst as json.Value,
    name as string) {
    def at as string init childPointer("", $name);
    def o as Outcome init evaluate($s, $sub, into($here, $sub, $step, $at), json.get($inst, $at));
    if ($o.valid) {
        $o.props = {};
        $o.props[$name] = true;
        $o.items = 0;
        $o.hits = {};
    }
    return $o;
}

/**
 * `properties`: each listed property that is present must pass its schema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome, annotating the properties it evaluated
 */
func properties(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    if (kindAt($node, "/properties") != "map") {
        badSchema($here, "properties must be an object");
    }
    def acc as Outcome init pass();
    for (def name in json.keys($node, "/properties")) {
        def step as string init childPointer("/properties", $name);
        if (not json.has($inst, childPointer("", $name))) {
            continue;
        }
        $acc = merge($acc, property($s, json.get($node, $step), $here, $step, $inst, $name));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    return $acc;
}

/**
 * `patternProperties`: each property whose name matches a pattern must pass
 * that pattern's schema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome, annotating the properties it evaluated
 */
func patternProperties(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    if (kindAt($node, "/patternProperties") != "map") {
        badSchema($here, "patternProperties must be an object");
    }
    def acc as Outcome init pass();
    for (def pattern in json.keys($node, "/patternProperties")) {
        def step as string init childPointer("/patternProperties", $pattern);
        for (def name in json.keys($inst)) {
            if (not patternMatches($here, $pattern, $name)) {
                continue;
            }
            $acc = merge($acc, property($s, json.get($node, $step), $here, $step, $inst, $name));
            if ($here.fast and not $acc.valid) {
                return $acc;
            }
        }
    }
    return $acc;
}

/**
 * Whether `properties` or `patternProperties` of the same schema object
 * covers a property name.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param name {string} the property
 * @return {bool} whether one of them applies to it
 */
func covered(node as json.Value, here as Here, name as string) {
    if (kindAt($node, "/properties") == "map") {
        if (json.has($node, childPointer("/properties", $name))) {
            return true;
        }
    }
    if (kindAt($node, "/patternProperties") != "map") {
        return false;
    }
    for (def pattern in json.keys($node, "/patternProperties")) {
        if (patternMatches($here, $pattern, $name)) {
            return true;
        }
    }
    return false;
}

/**
 * `additionalProperties`: every property neither `properties` nor
 * `patternProperties` covers must pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome, annotating the properties it evaluated
 */
func additionalProperties(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def sub as json.Value init json.get($node, "/additionalProperties");
    def acc as Outcome init pass();
    for (def name in json.keys($inst)) {
        if (covered($node, $here, $name)) {
            continue;
        }
        def o as Outcome init property($s, $sub, $here, "/additionalProperties", $inst, $name);
        if (not $o.valid and json.typeOf($sub) == "bool") {
            $o = fail(
                $here,
                "additionalProperties",
                "property " + quoted($name) + " is not allowed");
        }
        $acc = merge($acc, $o);
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    return $acc;
}

/**
 * `propertyNames`: every property name, as a string, must pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome
 */
func propertyNames(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def sub as json.Value init json.get($node, "/propertyNames");
    for (def name in json.keys($inst)) {
        def at as Here init into($here, $sub, "/propertyNames", childPointer("", $name));
        if (not evaluate($s, $sub, $at, json.decode(json.encode($name))).valid) {
            return fail(
                $here,
                "propertyNames",
                "property name " + quoted($name) + " is not allowed");
        }
    }
    return pass();
}

/**
 * `required`: every listed property must be present.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome, naming the missing properties
 */
func required(node as json.Value, here as Here, inst as json.Value) {
    def missing as list of string init absent($node, $here, "/required", $inst);
    if (len($missing) == 0) {
        return pass();
    }
    return fail($here, "required", "missing required properties: " + strings.join($missing, ", "));
}

/**
 * The names in an array of property names that an object lacks.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param at {string} the pointer to the array of names in the schema object
 * @param inst {json.Value} the object
 * @return {list of string} the names it does not have
 * @throws {Error} kind `jsonschema` unless `at` is an array of strings
 */
func absent(node as json.Value, here as Here, at as string, inst as json.Value) {
    if (kindAt($node, $at) != "list") {
        badSchema($here, strings.substring($at, 1, len($at)) + " must be an array of strings");
    }
    def out as list of string init [];
    for (def i in 0..json.length($node, $at)) {
        def item as string init $at + "/" + convert.toString($i);
        if (kindAt($node, $item) != "string") {
            badSchema($here, strings.substring($at, 1, len($at)) + " must be an array of strings");
        }
        def name as string init json.asString($node, $item);
        if (not json.has($inst, childPointer("", $name))) {
            $out[] = $name;
        }
    }
    return $out;
}

/**
 * Check that a keyword's value is an object.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param k {string} the keyword
 * @throws {Error} kind `jsonschema` when it is not
 */
func mapKeyword(node as json.Value, here as Here, k as string) {
    if (kindAt($node, "/" + $k) != "map") {
        badSchema($here, $k + " must be an object");
    }
}

/**
 * `dependentRequired`: when a property is present, the properties listed
 * for it must be too.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome
 */
func dependentRequired(node as json.Value, here as Here, inst as json.Value) {
    mapKeyword($node, $here, "dependentRequired");
    for (def name in json.keys($node, "/dependentRequired")) {
        if (not json.has($inst, childPointer("", $name))) {
            continue;
        }
        def missing as list of string init absent(
            $node,
            $here,
            childPointer("/dependentRequired", $name),
            $inst);
        if (len($missing) > 0) {
            return fail(
                $here,
                "dependentRequired",
                $name + " requires " + strings.join($missing, ", "));
        }
    }
    return pass();
}

/**
 * `dependentSchemas`: when a property is present, the whole object must pass
 * the schema listed for it.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome, with the annotations of the schemas applied
 */
func dependentSchemas(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    mapKeyword($node, $here, "dependentSchemas");
    def acc as Outcome init pass();
    for (def name in json.keys($node, "/dependentSchemas")) {
        if (not json.has($inst, childPointer("", $name))) {
            continue;
        }
        def step as string init childPointer("/dependentSchemas", $name);
        def sub as json.Value init json.get($node, $step);
        $acc = merge($acc, evaluate($s, $sub, into($here, $sub, $step, ""), $inst));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    return $acc;
}

/**
 * `dependencies`, the keyword `dependentRequired` and `dependentSchemas`
 * replaced in draft 2019-09. Still common in schemas written for draft 7, so
 * it is honoured: an array entry lists required properties, any other entry
 * is a schema.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the object
 * @return {Outcome} the outcome
 */
func dependencies(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    mapKeyword($node, $here, "dependencies");
    def acc as Outcome init pass();
    for (def name in json.keys($node, "/dependencies")) {
        if (not json.has($inst, childPointer("", $name))) {
            continue;
        }
        def step as string init childPointer("/dependencies", $name);
        if (kindAt($node, $step) == "list") {
            def missing as list of string init absent($node, $here, $step, $inst);
            if (len($missing) > 0) {
                $acc = merge(
                    $acc,
                    fail(
                        $here,
                        "dependencies",
                        $name + " requires " + strings.join($missing, ", ")));
            }
            continue;
        }
        def sub as json.Value init json.get($node, $step);
        $acc = merge($acc, evaluate($s, $sub, into($here, $sub, $step, ""), $inst));
    }
    return $acc;
}

/**
 * `unevaluatedProperties`: every property no other keyword evaluated must pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param seen {Outcome} what the schema object's other keywords evaluated
 * @return {Outcome} the outcome, annotating every property when it passed
 */
func unevaluatedProperties(
    s as Schema,
    node as json.Value,
    here as Here,
    inst as json.Value,
    seen as Outcome) {
    if (json.typeOf($inst) != "map" or not $seen.valid) {
        return pass();
    }
    def sub as json.Value init json.get($node, "/unevaluatedProperties");
    def acc as Outcome init pass();
    for (def name in json.keys($inst)) {
        if (maps.has($seen.props, $name)) {
            continue;
        }
        def o as Outcome init property($s, $sub, $here, "/unevaluatedProperties", $inst, $name);
        if (not $o.valid and json.typeOf($sub) == "bool") {
            $o = fail(
                $here,
                "unevaluatedProperties",
                "property " + quoted($name) + " is not allowed");
        }
        $acc = merge($acc, $o);
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    return $acc;
}
