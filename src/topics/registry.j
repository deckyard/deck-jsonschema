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

# The validation vocabulary, and the keywords it owns.
def const VOCAB_VALIDATION as string init "https://json-schema.org/draft/2020-12/vocab/validation";
def const VOCAB_FORMAT_ASSERTION as string init "https://json-schema.org/draft/2020-12/vocab/format-assertion";
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
 * @field root {json.Value} the schema document
 * @field base {string} its base URI: its `$id`, or `DEFAULT_BASE`
 * @field registry {Registry} every resource its references can reach
 * @field formats {bool} whether `format` is asserted rather than only annotated
 * @field validation {bool} whether the validation vocabulary is in force
 */
export def struct Schema {
    root as json.Value,
    base as string,
    registry as Registry,
    formats as bool,
    validation as bool
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
 * The document is indexed now: any `$id` inside it registers too. A
 * document's own absolute `$id` takes precedence over `uri`.
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
 * Compile a schema with nothing but itself to resolve references against.
 *
 * @param schema {json.Value} a draft 2020-12 schema
 * @return {Schema} the compiled schema
 * @throws {Error} kind `jsonschema` if the schema is not an object or a boolean
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
 * @throws {Error} kind `jsonschema` if the schema is not an object or a boolean
 */
export func compileWith(schema as json.Value, reg as Registry) {
    def t as string init json.typeOf($schema);
    if ($t != "map" and $t != "bool") {
        throw Error{kind: ERROR_KIND, message: "a schema is an object or a boolean, not " + $t};
    }
    def base as string init rootBase($schema, DEFAULT_BASE);
    def indexed as Registry init indexDocument($reg, $schema, $base);
    def out as Schema init Schema{
        root: $schema,
        base: $base,
        registry: $indexed,
        formats: false,
        validation: true
    };
    $out.validation = usesVocabulary($out, VOCAB_VALIDATION, true);
    $out.formats = usesVocabulary($out, VOCAB_FORMAT_ASSERTION, false);
    return $out;
}

/**
 * Whether a schema's meta-schema lists a vocabulary.
 *
 * A meta-schema that lists `$vocabulary` without the validation vocabulary
 * switches off `type`, `minimum`, `required` and the rest: the schema's
 * applicators still work, its assertions do not. One that lists the
 * format-assertion vocabulary switches `format` assertion on.
 *
 * @param s {Schema} the compiled schema
 * @param vocabulary {string} the vocabulary URI
 * @param fallback {bool} the answer when there is no `$schema`, it cannot be found, or it lists no `$vocabulary`
 * @return {bool} whether the vocabulary is in force
 */
func usesVocabulary(s as Schema, vocabulary as string, fallback as bool) {
    if (kindAt($s.root, "/$schema") != "string") {
        return $fallback;
    }
    def meta as Target init resolveRef($s, $s.base, json.asString($s.root, "/$schema"));
    if ($meta.location == "" or kindAt($meta.node, "/$vocabulary") != "map") {
        return $fallback;
    }
    return json.has($meta.node, childPointer("/$vocabulary", $vocabulary));
}

/**
 * The same schema with `format` asserted, or only annotated again.
 *
 * Draft 2020-12 treats `format` as an annotation unless asked: a string that
 * is not an email address passes `"format": "email"` by default.
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
 * Walks with a queue rather than by recursion, so the maps being built are
 * never copied into a call and back out of it.
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
        def pointer as string init $fragment;
        if (strings.contains($pointer, "%")) {
            try {
                $pointer = uri.decode($fragment);
            } catch (e) {
                return $none;
            }
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
