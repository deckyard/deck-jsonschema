# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - keywords on arrays: `prefixItems`, `items`, `contains` with its bounds,
# `minItems`, `maxItems`, `uniqueItems` and `unevaluatedItems`.
# Spliced into jsonschema.j via include - not a standalone module.

/**
 * Apply one array keyword. Keywords this topic does not own pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value, an array
 * @param k {string} the keyword
 * @return {Outcome} the keyword's outcome
 */
func arrayKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value, k as string) {
    def n as int init json.length($inst);
    match ($k) {
        when "prefixItems" { return prefixItems($s, $node, $here, $inst); }
        when "items" { return itemsKeyword($s, $node, $here, $inst); }
        when "contains" { return containsKeyword($s, $node, $here, $inst); }
        when "uniqueItems" { return uniqueItems($node, $here, $inst); }
        when "minItems" {
            if ($n < count($node, $here, $k)) {
                return fail(
                    $here,
                    $k,
                    "must have at least " + limitText($node, "minItems") + " items");
            }
        }
        when "maxItems" {
            if ($n > count($node, $here, $k)) {
                return fail(
                    $here,
                    $k,
                    "must have at most " + limitText($node, "maxItems") + " items");
            }
        }
        else {
        }
    }
    return pass();
}

/**
 * Evaluate one item against a subschema.
 *
 * @param s {Schema} the compiled schema
 * @param sub {json.Value} the subschema
 * @param here {Here} the array's position
 * @param step {string} the escaped pointer from the schema object to `sub`
 * @param inst {json.Value} the array
 * @param i {int} the item's index
 * @return {Outcome} the item's outcome
 */
func item(
    s as Schema,
    sub as json.Value,
    here as Here,
    step as string,
    inst as json.Value,
    i as int) {
    def at as string init "/" + convert.toString($i);
    return evaluate($s, $sub, into($here, $sub, $step, $at), json.get($inst, $at));
}

/**
 * `prefixItems`: item i must pass subschema i, for as many as both have.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the array
 * @return {Outcome} the outcome, annotating the leading items it evaluated
 */
func prefixItems(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def n as int init math.min(branchCount($node, $here, "prefixItems"), json.length($inst));
    def acc as Outcome init pass();
    for (def i in 0..$n) {
        def step as string init "/prefixItems/" + convert.toString($i);
        $acc = merge($acc, item($s, json.get($node, $step), $here, $step, $inst, $i));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    $acc.items = $n;
    return $acc;
}

/**
 * `items`: every item after those `prefixItems` covers must pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the array
 * @return {Outcome} the outcome, annotating every item
 */
func itemsKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def from as int init 0;
    if (kindAt($node, "/prefixItems") == "list") {
        $from = json.length($node, "/prefixItems");
    }
    def sub as json.Value init json.get($node, "/items");
    def acc as Outcome init pass();
    def n as int init json.length($inst);
    if ($from > $n) {
        $from = $n;
    }
    for (def i in $from..$n) {
        $acc = merge($acc, item($s, $sub, $here, "/items", $inst, $i));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    $acc.items = json.length($inst);
    return $acc;
}

/**
 * `contains`, bounded by `minContains` (default 1) and `maxContains`.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the array
 * @return {Outcome} the outcome, annotating the items that matched
 */
func containsKeyword(s as Schema, node as json.Value, here as Here, inst as json.Value) {
    def sub as json.Value init json.get($node, "/contains");
    def probe as Here init $here;
    $probe.fast = true;
    def hits as map of string to bool init {};
    for (def i in 0..json.length($inst)) {
        if (item($s, $sub, $probe, "/contains", $inst, $i).valid) {
            $hits[convert.toString($i)] = true;
        }
    }
    def least as int init 1;
    if (json.has($node, "/minContains")) {
        $least = count($node, $here, "minContains");
    }
    if (len($hits) < $least) {
        if (json.has($node, "/minContains")) {
            return fail(
                $here,
                "minContains",
                "must contain at least " + convert.toString($least) + " matching items");
        }
        return fail($here, "contains", "contains no item matching the schema");
    }
    if (json.has($node, "/maxContains") and len($hits) > count($node, $here, "maxContains")) {
        return fail(
            $here,
            "maxContains",
            "must contain at most " + limitText($node, "maxContains") +
                " matching items");
    }
    def out as Outcome init pass();
    $out.hits = $hits;
    return $out;
}

/**
 * `uniqueItems`: no two items may be equal, by JSON Schema's equality.
 *
 * Items are grouped by `sameKey`, so only items in one group are compared:
 * linear time rather than quadratic.
 *
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the array
 * @return {Outcome} the outcome
 */
func uniqueItems(node as json.Value, here as Here, inst as json.Value) {
    if (kindAt($node, "/uniqueItems") != "bool") {
        badSchema($here, "uniqueItems must be a boolean");
    }
    if (not json.asBool($node, "/uniqueItems")) {
        return pass();
    }
    def groups as map of string to list of int init {};
    for (def i in 0..json.length($inst)) {
        def a as json.Value init json.get($inst, "/" + convert.toString($i));
        def key as string init sameKey($a);
        if (not maps.has($groups, $key)) {
            $groups[$key] = [$i];
            continue;
        }
        for (def j in $groups[$key]) {
            if (json.get($inst, "/" + convert.toString($j)) == $a) {
                def which as string init convert.toString($j) + " and " + convert.toString($i);
                return fail($here, "uniqueItems", "items " + $which + " are equal");
            }
        }
        def group as list of int init $groups[$key];
        $group[] = $i;
        $groups[$key] = $group;
    }
    return pass();
}

/**
 * A text that is the same for any two values JSON Schema calls equal:
 * numbers by their float value, objects with their keys sorted.
 *
 * Different values may share one, so a match still needs `==`.
 *
 * @param v {json.Value} the value
 * @return {string} its key
 */
func sameKey(v as json.Value) {
    match (json.typeOf($v)) {
        when "int" { return "n" + convert.toString(json.asFloat($v)); }
        when "float" { return "n" + convert.toString(json.asFloat($v)); }
        when "list" {
            def parts as list of string init [];
            for (def i in 0..json.length($v)) {
                $parts[] = sameKey(json.get($v, "/" + convert.toString($i)));
            }
            return "[" + strings.join($parts, ",") + "]";
        }
        when "map" {
            def parts as list of string init [];
            for (def k in json.keys($v)) {
                $parts[] = json.encode($k) + ":" + sameKey(json.get($v, childPointer("", $k)));
            }
            return '{' + strings.join(lists.sort($parts), ",") + '}';
        }
        else { return json.encode($v); }
    }
}

/**
 * `unevaluatedItems`: every item no other keyword evaluated must pass.
 *
 * @param s {Schema} the compiled schema
 * @param node {json.Value} the schema object
 * @param here {Here} its position
 * @param inst {json.Value} the value
 * @param seen {Outcome} what the schema object's other keywords evaluated
 * @return {Outcome} the outcome, annotating every item when it passed
 */
func unevaluatedItems(
    s as Schema,
    node as json.Value,
    here as Here,
    inst as json.Value,
    seen as Outcome) {
    if (json.typeOf($inst) != "list" or not $seen.valid) {
        return pass();
    }
    def sub as json.Value init json.get($node, "/unevaluatedItems");
    def acc as Outcome init pass();
    for (def i in $seen.items..json.length($inst)) {
        if (maps.has($seen.hits, convert.toString($i))) {
            continue;
        }
        $acc = merge($acc, item($s, $sub, $here, "/unevaluatedItems", $inst, $i));
        if ($here.fast and not $acc.valid) {
            return $acc;
        }
    }
    $acc.items = json.length($inst);
    return $acc;
}
