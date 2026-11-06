# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - schema resources and how a reference finds one: indexing `$id`, `$anchor`
# and `$dynamicAnchor`, the `Registry` of known documents, and `compile`.
#
# Nothing is fetched. A `$ref` resolves to the schema being compiled, to a
# document registered beforehand, or to the embedded 2020-12 meta-schemas.
# Spliced into jsonschema.j via include - not a standalone module.

# Where the 2020-12 meta-schemas live; a reference there pulls them in.
def const META_HOST as string init "json-schema.org/draft/2020-12/";

# The 2020-12 meta-schema: a `$schema` naming it needs no lookup.
def const STANDARD_META as string init "https://json-schema.org/draft/2020-12/schema";

# The validation and format-assertion vocabularies, and the keywords the
# validation vocabulary owns.
def const VOCAB_VALIDATION as string init "https://json-schema.org/draft/2020-12/vocab/validation";
def const VOCAB_FORMAT_ASSERTION as string init "https://json-schema.org/draft/2020-12/vocab/format-assertion";

# Every 2020-12 vocabulary. A meta-schema that requires (`true`) any other
# is refused, as Core 8.1.2 asks.
def const VOCABULARIES as map of string to bool init {
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/applicator": true,
    "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
    "https://json-schema.org/draft/2020-12/vocab/validation": true,
    "https://json-schema.org/draft/2020-12/vocab/meta-data": true,
    "https://json-schema.org/draft/2020-12/vocab/format-annotation": true,
    "https://json-schema.org/draft/2020-12/vocab/format-assertion": true,
    "https://json-schema.org/draft/2020-12/vocab/content": true
};

# Bits of a `Schema.dialects` entry: the validation vocabulary is in force,
# the format-assertion vocabulary is in force.
def const DIALECT_VALIDATION as int init 1;
def const DIALECT_FORMATS as int init 2;
def const VALIDATION_KEYWORDS as list of string init [
    "type",
    "enum",
    "const",
    "multipleOf",
    "maximum",
    "exclusiveMaximum",
    "minimum",
    "exclusiveMinimum",
    "maxLength",
    "minLength",
    "pattern",
    "maxItems",
    "minItems",
    "uniqueItems",
    "maxContains",
    "minContains",
    "maxProperties",
    "minProperties",
    "required",
    "dependentRequired"
];

# Keywords whose value is one subschema.
def const SINGLE_KEYWORDS as list of string init [
    "additionalProperties",
    "propertyNames",
    "items",
    "contains",
    "not",
    "if",
    "then",
    "else",
    "unevaluatedItems",
    "unevaluatedProperties",
    "contentSchema"
];

# Keywords whose value is an object of subschemas.
def const MAP_KEYWORDS as list of string init [
    "properties",
    "patternProperties",
    "$defs",
    "dependentSchemas",
    "dependencies"
];

# Keywords whose value is an array of subschemas.
def const LIST_KEYWORDS as list of string init ["allOf", "anyOf", "oneOf", "prefixItems"];

/**
 * Every schema document a reference may point into, by URI.
 *
 * @field resources {map of string to json.Value} resource URI to its root schema
 * @field anchors {map of string to string} `uri#name` to `uri#pointer` of the anchored schema
 * @field dynamic {map of string to bool} `uri#name` of every `$dynamicAnchor`
 * @field meta {bool} whether the 2020-12 meta-schemas are in it
 */
export def struct Registry {
    resources as map of string to json.Value,
    anchors as map of string to string,
    dynamic as map of string to bool,
    meta as bool
};

/**
 * A schema ready to validate against.
 *
 * The last four fields are filled by `compile` from every resource the
 * schema can reach, so evaluation does not redo the work per value.
 *
 * @field root {json.Value} the schema document
 * @field base {string} its base URI: its `$id`, or `DEFAULT_BASE`
 * @field registry {Registry} every resource its references can reach
 * @field formats {bool} whether `assertFormats` switched `format` assertion on everywhere
 * @field validation {bool} whether the validation vocabulary is in force at the root
 * @field dialects {map of string to int} resource URI to its vocabularies, for each reachable resource with a `$schema`: 1 validation, plus 2 format assertion
 * @field targets {map of string to json.Value} `base + " " + ref` to the schema a `$ref` or `$dynamicRef` resolves to
 * @field bases {map of string to string} the same keys to that schema's base URI
 * @field patterns {map of string to string} each `pattern` and `patternProperties` name to its RE2 form
 */
export def struct Schema {
    root as json.Value,
    base as string,
    registry as Registry,
    formats as bool,
    validation as bool,
    dialects as map of string to int,
    targets as map of string to json.Value,
    bases as map of string to string,
    patterns as map of string to string
};

/**
 * One schema node found while indexing, with where it sits.
 *
 * @field node {json.Value} the schema
 * @field resource {string} the URI of the resource enclosing it
 * @field pointer {string} its location inside that resource
 */
def struct Found {
    node as json.Value,
    resource as string,
    pointer as string
};

/**
 * One schema node found while preparing a compiled schema.
 *
 * @field node {json.Value} the schema
 * @field base {string} the base URI in effect at it: before its own `$id`, unless `root`
 * @field pointer {string} its location, for an error
 * @field flags {int} the `dialects` bits in force at it
 * @field root {bool} whether it is where evaluation enters a resource, its `base` final
 */
def struct Visit {
    node as json.Value,
    base as string,
    pointer as string,
    flags as int,
    root as bool
};

/**
 * Where a reference leads.
 *
 * @field node {json.Value} the target schema
 * @field base {string} the target's own base URI
 * @field location {string} `uri#fragment` the reference resolved to
 */
def struct Target {
    node as json.Value,
    base as string,
    location as string
};

/**
 * An empty registry.
 *
 * @return {Registry} a registry with no documents
 */
export func registry() {
    return Registry{resources: {}, anchors: {}, dynamic: {}, meta: false};
}

/**
 * Add a schema document to a registry under a URI, so `$ref`s can reach it.
 *
 * The document is indexed now: every `$id` inside it registers too. A
 * document with its own `$id` is reachable under both `uri` and that `$id`,
 * and relative references inside it resolve against the `$id`.
 *
 * @param reg {Registry} the registry
 * @param uri {string} the absolute URI the document is known by
 * @param schema {json.Value} the document
 * @return {Registry} the registry with the document added
 * @throws {Error} kind `jsonschema` if `uri` is not absolute
 * @example $reg = jsonschema.register($reg, "https://example.com/address.json", $doc);
 */
export func register(reg as Registry, uri as string, schema as json.Value) {
    if (not isAbsolute($uri)) {
        throw Error{kind: ERROR_KIND, message: "a registered URI must be absolute: " + $uri};
    }
    return indexDocument($reg, $schema, stripFragment($uri));
}

/**
 * Compile a schema whose references resolve within itself and to the
 * embedded 2020-12 meta-schemas.
 *
 * @param schema {json.Value} a draft 2020-12 schema
 * @return {Schema} the compiled schema
 * @throws {Error} kind `jsonschema` if the schema is not an object or a boolean, its
 *   meta-schema requires a vocabulary this deck does not know, or it asserts a format
 *   through the format-assertion vocabulary that this deck cannot check
 * @example def s as jsonschema.Schema init jsonschema.compile(json.decode('{"type": "string"}'));
 */
export func compile(schema as json.Value) {
    return compileWith($schema, registry());
}

/**
 * Compile a schema whose references may reach documents in a registry.
 *
 * @param schema {json.Value} a draft 2020-12 schema
 * @param reg {Registry} documents registered with `register`
 * @return {Schema} the compiled schema
 * @throws {Error} kind `jsonschema` as `compile` does
 */
export func compileWith(schema as json.Value, reg as Registry) {
    def t as string init json.typeOf($schema);
    if ($t != "map" and $t != "bool") {
        throw Error{kind: ERROR_KIND, message: "a schema is an object or a boolean, not " + $t};
    }
    def base as string init rootBase($schema, DEFAULT_BASE);
    def out as Schema init Schema{
        root: $schema,
        base: $base,
        registry: indexDocument($reg, $schema, $base),
        formats: false,
        validation: true,
        dialects: {},
        targets: {},
        bases: {},
        patterns: {}
    };
    $out = prepare($out);
    $out.validation = (rootFlags($out) & DIALECT_VALIDATION) != 0;
    return $out;
}

/**
 * The `dialects` bits at the root of a compiled schema.
 *
 * @param s {Schema} the compiled schema
 * @return {int} the bits; validation only when the root has no `$schema`
 */
func rootFlags(s as Schema) {
    if (maps.has($s.dialects, $s.base)) {
        return $s.dialects[$s.base];
    }
    return DIALECT_VALIDATION;
}

/**
 * Walk every resource a compiled schema can reach, starting at its root and
 * following each `$ref` and `$dynamicRef`, and record what evaluation would
 * otherwise work out per value: reference targets, the RE2 form of each
 * pattern, and each resource's vocabularies.
 *
 * A reference that does not resolve is left for evaluation to report, where
 * it reaches it.
 *
 * @param s {Schema} the schema, its fields up to `validation` set
 * @return {Schema} the schema with `dialects`, `targets`, `bases` and `patterns` filled
 * @throws {Error} kind `jsonschema` for a refused meta-schema or an unsupported asserted format
 */
func prepare(s as Schema) {
    def dialects as map of string to int init {};
    def targets as map of string to json.Value init {};
    def bases as map of string to string init {};
    def patterns as map of string to string init {};
    def walked as map of string to bool init {};
    $walked[$s.base] = true;
    def queue as list of Visit init [
        Visit{node: $s.root, base: $s.base, pointer: "", flags: DIALECT_VALIDATION, root: true}
    ];
    def at as int init 0;
    while ($at < len($queue)) {
        def v as Visit init $queue[$at];
        $at = $at + 1;
        if (json.typeOf($v.node) != "map") {
            continue;
        }
        if (not $v.root and kindAt($v.node, "/$id") == "string") {
            $v.base = stripFragment(uri.resolve($v.base, json.asString($v.node, "/$id")));
            $v.root = true;
            $walked[$v.base] = true;
        }
        if ($v.root and kindAt($v.node, "/$schema") == "string") {
            $v.flags = dialect($s, $v.base, json.asString($v.node, "/$schema"), $v.pointer);
            $dialects[$v.base] = $v.flags;
        }
        if (($v.flags & DIALECT_FORMATS) != 0) {
            checkAssertedFormat($v.node, $v.pointer);
        }
        if (kindAt($v.node, "/pattern") == "string") {
            def p as string init json.asString($v.node, "/pattern");
            $patterns[$p] = ecmaPattern($p);
        }
        if (kindAt($v.node, "/patternProperties") == "map") {
            for (def p in json.keys($v.node, "/patternProperties")) {
                $patterns[$p] = ecmaPattern($p);
            }
        }
        for (def k in ["$ref", "$dynamicRef"]) {
            if (kindAt($v.node, "/" + $k) != "string") {
                continue;
            }
            def ref as string init json.asString($v.node, "/" + $k);
            def t as Target init lookup($s, $v.base, $ref);
            if ($t.location == "") {
                continue;
            }
            $targets[$v.base + " " + $ref] = $t.node;
            $bases[$v.base + " " + $ref] = $t.base;
            if (not maps.has($walked, $t.base)) {
                $walked[$t.base] = true;
                $queue[] = Visit{
                    node: resourceRoot($s, $t),
                    base: $t.base,
                    pointer: $v.pointer + "/" + escapeToken($k),
                    flags: $v.flags,
                    root: true
                };
            }
        }
        for (def child in subschemas($v.node)) {
            $queue[] = Visit{
                node: json.get($v.node, $child),
                base: $v.base,
                pointer: $v.pointer + $child,
                flags: $v.flags,
                root: false
            };
        }
    }
    # A `$dynamicRef` that lands on a dynamic anchor is redirected to a
    # `#name` in some resource of the dynamic scope: resolve those too.
    for (def key in maps.keys($s.registry.dynamic)) {
        def home as string init stripFragment($key);
        if (not maps.has($walked, $home)) {
            continue;
        }
        def ref as string init "#" + fragmentOf($key);
        def t as Target init lookup($s, $home, $ref);
        if ($t.location != "") {
            $targets[$home + " " + $ref] = $t.node;
            $bases[$home + " " + $ref] = $t.base;
        }
    }
    def out as Schema init $s;
    $out.dialects = $dialects;
    $out.targets = $targets;
    $out.bases = $bases;
    $out.patterns = $patterns;
    return $out;
}

/**
 * Refuse a schema object whose `format`, asserted by the format-assertion
 * vocabulary, is one this deck cannot check.
 *
 * @param node {json.Value} the schema object
 * @param pointer {string} where it sits, for the error
 * @throws {Error} kind `jsonschema` for a format in `UNCHECKED_FORMATS`
 */
func checkAssertedFormat(node as json.Value, pointer as string) {
    if (kindAt($node, "/format") != "string") {
        return;
    }
    def name as string init json.asString($node, "/format");
    if (maps.has(UNCHECKED_FORMATS, $name)) {
        throw Error{
            kind: ERROR_KIND,
            message: "invalid schema at " + atText($pointer) + ": format " + quoted($name) +
                " is asserted by the format-assertion vocabulary, and this deck cannot check it"
        };
    }
}

/**
 * The root of the resource a reference target sits in.
 *
 * @param s {Schema} the compiled schema
 * @param t {Target} a resolved target
 * @return {json.Value} the resource registered under the target's base, or the target itself
 */
func resourceRoot(s as Schema, t as Target) {
    if (maps.has($s.registry.resources, $t.base)) {
        return $s.registry.resources[$t.base];
    }
    return $t.node;
}

/**
 * `resolveRef`, with a reference that cannot be parsed counting as one that
 * resolves to nothing. Jennifer's `limit` error still escapes.
 *
 * @param s {Schema} the compiled schema
 * @param base {string} the base URI the reference appears under
 * @param ref {string} the reference
 * @return {Target} the target; `location` is `""` when nothing matches
 */
func lookup(s as Schema, base as string, ref as string) {
    try {
        return resolveRef($s, $base, $ref);
    } catch (e) {
        if ($e.kind == "limit") {
            throw $e;
        }
    }
    return Target{node: json.decode("false"), base: "", location: ""};
}

/**
 * The vocabularies a resource's `$schema` puts in force, as `dialects` bits.
 *
 * A meta-schema that cannot be found, or lists no `$vocabulary`, gives the
 * 2020-12 default: validation on, `format` an annotation. One whose
 * `$vocabulary` omits validation switches off `type`, `minimum`, `required`
 * and the rest; the resource's applicators still work.
 *
 * @param s {Schema} the compiled schema
 * @param base {string} the resource's base URI
 * @param meta {string} its `$schema`
 * @param pointer {string} where the resource sits, for an error
 * @return {int} the bits
 * @throws {Error} kind `jsonschema` when the meta-schema requires an unknown vocabulary
 */
func dialect(s as Schema, base as string, meta as string, pointer as string) {
    if ($meta == STANDARD_META) {
        return DIALECT_VALIDATION;
    }
    def m as Target init lookup($s, $base, $meta);
    if ($m.location == "" or kindAt($m.node, "/$vocabulary") != "map") {
        return DIALECT_VALIDATION;
    }
    def flags as int init 0;
    for (def v in json.keys($m.node, "/$vocabulary")) {
        def at as string init childPointer("/$vocabulary", $v);
        if (not maps.has(VOCABULARIES, $v) and kindAt($m.node, $at) == "bool") {
            if (json.asBool($m.node, $at)) {
                throw Error{
                    kind: ERROR_KIND,
                    message: "invalid schema at " + atText($pointer) +
                        ": its meta-schema requires the unknown vocabulary " + quoted($v)
                };
            }
        }
        if ($v == VOCAB_VALIDATION) {
            $flags = $flags | DIALECT_VALIDATION;
        }
        if ($v == VOCAB_FORMAT_ASSERTION) {
            $flags = $flags | DIALECT_FORMATS;
        }
    }
    return $flags;
}

/**
 * The same schema with `format` asserted, or only annotated again.
 *
 * Draft 2020-12 treats `format` as an annotation unless asked: a string that
 * is not an email address passes `"format": "email"` by default. Switched on
 * here, the 14 formats in `docs/formats.md` are checked and any other passes.
 * A resource whose meta-schema lists the format-assertion vocabulary asserts
 * formats whatever this says, and fails a format name it does not know.
 *
 * @param s {Schema} the compiled schema
 * @param on {bool} whether `format` should fail values it does not match
 * @return {Schema} the schema with the setting changed
 */
export func assertFormats(s as Schema, on as bool) {
    def out as Schema init $s;
    $out.formats = $on;
    return $out;
}

/**
 * The base URI a document establishes: its `$id` resolved against `fallback`.
 *
 * @param schema {json.Value} the document
 * @param fallback {string} the base when it has no `$id`
 * @return {string} the base URI, without a fragment
 */
func rootBase(schema as json.Value, fallback as string) {
    if (kindAt($schema, "/$id") == "string") {
        return stripFragment(uri.resolve($fallback, json.asString($schema, "/$id")));
    }
    return $fallback;
}

/**
 * Index one document: every resource, anchor and dynamic anchor in it.
 *
 * Walks with a queue rather than by recursion: the maps are copied once on
 * entry, not into and out of a call per node.
 *
 * @param reg {Registry} the registry so far
 * @param schema {json.Value} the document
 * @param base {string} the URI the document is known by
 * @return {Registry} the registry with the document indexed
 */
func indexDocument(reg as Registry, schema as json.Value, base as string) {
    def resources as map of string to json.Value init $reg.resources;
    def anchors as map of string to string init $reg.anchors;
    def dynamic as map of string to bool init $reg.dynamic;
    def wantsMeta as bool init false;
    def root as string init rootBase($schema, $base);
    $resources[$base] = $schema;
    $resources[$root] = $schema;

    def queue as list of Found init [Found{node: $schema, resource: $base, pointer: ""}];
    def at as int init 0;
    while ($at < len($queue)) {
        def f as Found init $queue[$at];
        $at = $at + 1;
        if (json.typeOf($f.node) != "map") {
            continue;
        }
        if (kindAt($f.node, "/$id") == "string") {
            def id as string init stripFragment(uri.resolve(
                $f.resource,
                json.asString($f.node, "/$id")));
            $resources[$id] = $f.node;
            $f.resource = $id;
            $f.pointer = "";
        }
        if (kindAt($f.node, "/$anchor") == "string") {
            def name as string init $f.resource + "#" + json.asString($f.node, "/$anchor");
            $anchors[$name] = $f.resource + "#" + $f.pointer;
        }
        if (kindAt($f.node, "/$dynamicAnchor") == "string") {
            def name as string init $f.resource + "#" + json.asString($f.node, "/$dynamicAnchor");
            $anchors[$name] = $f.resource + "#" + $f.pointer;
            $dynamic[$name] = true;
        }
        if (refersToMeta($f.node)) {
            $wantsMeta = true;
        }
        for (def child in subschemas($f.node)) {
            $queue[] = Found{
                node: json.get($f.node, $child),
                resource: $f.resource,
                pointer: $f.pointer + $child
            };
        }
    }
    def out as Registry init Registry{
        resources: $resources,
        anchors: $anchors,
        dynamic: $dynamic,
        meta: $reg.meta
    };
    if ($wantsMeta and not $out.meta) {
        $out.meta = true;
        for (def text in metaDocuments()) {
            def doc as json.Value init json.decode($text);
            $out = indexDocument($out, $doc, rootBase($doc, DEFAULT_BASE));
        }
    }
    return $out;
}

/**
 * Whether a schema object references the 2020-12 meta-schemas.
 *
 * @param node {json.Value} a schema object
 * @return {bool} whether its `$ref` or `$dynamicRef` points at json-schema.org
 */
func refersToMeta(node as json.Value) {
    for (def k in ["$ref", "$dynamicRef"]) {
        if (kindAt($node, "/" + $k) == "string") {
            if (strings.contains(json.asString($node, "/" + $k), META_HOST)) {
                return true;
            }
        }
    }
    return false;
}

/**
 * The pointers, relative to a schema object, of every subschema it holds
 * under a keyword that takes one.
 *
 * Only known keywords are walked: an `$id` inside `enum`, `const` or an
 * unknown keyword is data, not an identifier.
 *
 * @param node {json.Value} a schema object
 * @return {list of string} relative pointers such as `/properties/name`
 */
func subschemas(node as json.Value) {
    def out as list of string init [];
    for (def k in SINGLE_KEYWORDS) {
        if (json.has($node, "/" + $k)) {
            $out[] = "/" + $k;
        }
    }
    for (def k in MAP_KEYWORDS) {
        if (kindAt($node, "/" + escapeToken($k)) == "map") {
            def at as string init "/" + escapeToken($k);
            for (def name in json.keys($node, $at)) {
                $out[] = childPointer($at, $name);
            }
        }
    }
    for (def k in LIST_KEYWORDS) {
        if (kindAt($node, "/" + $k) == "list") {
            for (def i in 0..json.length($node, "/" + $k)) {
                $out[] = "/" + $k + "/" + convert.toString($i);
            }
        }
    }
    return $out;
}

/**
 * Resolve a reference from a base URI to the schema it names.
 *
 * @param s {Schema} the compiled schema
 * @param base {string} the base URI the reference appears under
 * @param ref {string} the `$ref` or `$dynamicRef` value
 * @return {Target} the target; `location` is `""` when nothing matches
 */
func resolveRef(s as Schema, base as string, ref as string) {
    def none as Target init Target{node: json.decode("false"), base: "", location: ""};
    # A fragment alone, the common case, needs no URI parsing.
    def location as string init $base + $ref;
    if (not strings.startsWith($ref, "#")) {
        $location = uri.resolve($base, $ref);
    }
    def resource as string init stripFragment($location);
    def fragment as string init fragmentOf($location);
    if (not maps.has($s.registry.resources, $resource)) {
        return $none;
    }
    if ($fragment == "") {
        return Target{node: $s.registry.resources[$resource], base: $resource, location: $location};
    }
    if (strings.startsWith($fragment, "/")) {
        def pointer as string init percentDecoded($fragment);
        if ($pointer == "") {
            return $none;
        }
        return walkPointer($s.registry.resources[$resource], $resource, $pointer, $location);
    }
    def key as string init $resource + "#" + $fragment;
    if (not maps.has($s.registry.anchors, $key)) {
        return $none;
    }
    def at as string init $s.registry.anchors[$key];
    def home as string init stripFragment($at);
    return walkPointer($s.registry.resources[$home], $home, fragmentOf($at), $location);
}

/**
 * A pointer fragment with its percent-escapes decoded.
 *
 * @param fragment {string} the fragment, starting with `/`
 * @return {string} the decoded pointer, `""` when an escape is malformed
 */
func percentDecoded(fragment as string) {
    if (not strings.contains($fragment, "%")) {
        return $fragment;
    }
    try {
        return uri.decode($fragment);
    } catch (e) {
        if ($e.kind == "limit") {
            throw $e;
        }
    }
    return "";
}

/**
 * Follow a JSON Pointer down from a resource, picking up any `$id` passed on
 * the way so the target gets the right base URI.
 *
 * @param node {json.Value} the resource's root
 * @param base {string} the resource's URI
 * @param pointer {string} the pointer, already percent-decoded
 * @param location {string} the location being resolved, for the result
 * @return {Target} the target; `location` is `""` when the pointer does not resolve
 */
func walkPointer(node as json.Value, base as string, pointer as string, location as string) {
    def here as json.Value init $node;
    def at as string init $base;
    if (not json.has($node, $pointer)) {
        return Target{node: json.decode("false"), base: "", location: ""};
    }
    def tokens as list of string init strings.split($pointer, "/");
    for (def i in 1..len($tokens)) {
        $here = json.get($here, "/" + $tokens[$i]);
        if (kindAt($here, "/$id") == "string") {
            $at = stripFragment(uri.resolve($at, json.asString($here, "/$id")));
        }
    }
    return Target{node: $here, base: $at, location: $location};
}

/**
 * A URI without its fragment.
 *
 * @param u {string} the URI
 * @return {string} everything before the first `#`
 */
func stripFragment(u as string) {
    def hash as int init strings.indexOf($u, "#");
    if ($hash < 0) {
        return $u;
    }
    return strings.substring($u, 0, $hash);
}

/**
 * The fragment of a URI, without the `#`.
 *
 * @param u {string} the URI
 * @return {string} the fragment, `""` when there is none
 */
func fragmentOf(u as string) {
    def hash as int init strings.indexOf($u, "#");
    if ($hash < 0) {
        return "";
    }
    return strings.substring($u, $hash + 1, len($u));
}

/**
 * Whether a URI has a scheme, and so does not depend on a base.
 *
 * @param u {string} the URI
 * @return {bool} whether it is absolute
 */
func isAbsolute(u as string) {
    return regex.matches("^[A-Za-z][A-Za-z0-9+.-]*:", $u);
}
