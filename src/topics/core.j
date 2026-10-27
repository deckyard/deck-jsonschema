# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - the public types, the error kind and the helpers every other topic uses:
# JSON Pointer tokens, JSON Schema's type names, and issue construction.
# Spliced into jsonschema.j via include - not a standalone module.

/** The `kind` of every `Error` this deck throws: a schema it cannot use. */
export def const ERROR_KIND as string init "jsonschema";

/** The base URI a schema without an absolute `$id` is resolved against. */
export def const DEFAULT_BASE as string init "jsonschema:/root.json";

/**
 * One way an instance fails a schema.
 *
 * @field instancePath {string} JSON Pointer to the failing value in the instance
 * @field schemaPath {string} JSON Pointer to the failing keyword, through every `$ref` followed
 * @field keyword {string} the keyword that failed, such as `minLength`
 * @field message {string} what is wrong, for a person to read
 */
export def struct Issue {
    instancePath as string,
    schemaPath as string,
    keyword as string,
    message as string
};

/**
 * The outcome of `validate`.
 *
 * @field valid {bool} whether the instance satisfies the schema
 * @field errors {list of Issue} why not; empty when `valid`
 */
export def struct Result {
    valid as bool,
    errors as list of Issue
};

/**
 * Where evaluation stands while it walks a schema and an instance together.
 *
 * @field base {string} the base URI of the schema resource in effect
 * @field schemaPath {string} the keyword location so far
 * @field instancePath {string} the instance location so far
 * @field scope {list of string} the dynamic scope: resource URIs entered, outermost first
 * @field depth {int} how many `$ref`s in a row were followed at `refAt`, to stop a cycle
 * @field refAt {string} the instance location `depth` counts at
 * @field fast {bool} whether to stop at the first error
 */
def struct Here {
    base as string,
    schemaPath as string,
    instancePath as string,
    scope as list of string,
    depth as int,
    refAt as string,
    fast as bool
};

/**
 * What evaluating one schema against one value found.
 *
 * The three annotation fields serve `unevaluatedProperties` and
 * `unevaluatedItems`; they are kept only for a schema that passed.
 *
 * @field valid {bool} whether the value passed
 * @field errors {list of Issue} the failures
 * @field props {map of string to bool} the property names some keyword evaluated
 * @field items {int} how many leading array items some keyword evaluated
 * @field hits {map of string to bool} other evaluated array indices, as strings
 */
def struct Outcome {
    valid as bool,
    errors as list of Issue,
    props as map of string to bool,
    items as int,
    hits as map of string to bool
};

/**
 * A passing outcome with no annotations.
 *
 * @return {Outcome} the outcome
 */
func pass() {
    return Outcome{valid: true, errors: [], props: {}, items: 0, hits: {}};
}

/**
 * A failing outcome carrying one issue.
 *
 * @param here {Here} where the failure is
 * @param keyword {string} the keyword that failed
 * @param message {string} what is wrong
 * @return {Outcome} the outcome
 */
func fail(here as Here, keyword as string, message as string) {
    def issue as Issue init Issue{
        instancePath: $here.instancePath,
        schemaPath: $here.schemaPath + "/" + escapeToken($keyword),
        keyword: $keyword,
        message: $message
    };
    return Outcome{valid: false, errors: [$issue], props: {}, items: 0, hits: {}};
}

/**
 * Throw the deck's error for a schema it cannot evaluate.
 *
 * @param here {Here} where in the schema the problem is
 * @param message {string} what is wrong with the schema
 * @throws {Error} always, of kind `jsonschema`
 */
func badSchema(here as Here, message as string) {
    def at as string init $here.schemaPath;
    if ($at == "") {
        $at = "the root";
    }
    throw Error{kind: ERROR_KIND, message: "invalid schema at " + $at + ": " + $message};
}

/**
 * Escape one JSON Pointer token: `~` becomes `~0` and `/` becomes `~1`.
 *
 * @param token {string} a property name or an index
 * @return {string} the escaped token
 */
func escapeToken(token as string) {
    return strings.replace(strings.replace($token, "~", "~0"), "/", "~1");
}

/**
 * Undo `escapeToken`.
 *
 * @param token {string} an escaped token
 * @return {string} the property name it stands for
 */
func unescapeToken(token as string) {
    return strings.replace(strings.replace($token, "~1", "/"), "~0", "~");
}

/**
 * A pointer one step below another.
 *
 * @param pointer {string} the parent pointer
 * @param token {string} the unescaped name or index to append
 * @return {string} the child pointer
 */
func childPointer(pointer as string, token as string) {
    return $pointer + "/" + escapeToken($token);
}

/**
 * The type of the node a pointer addresses, or `missing`.
 *
 * `json.typeOf` with a pointer is documented to answer `missing` for one that
 * does not resolve, but Jennifer 0.25.0 throws instead; this asks `has` first.
 *
 * @param v {json.Value} the node to start from
 * @param pointer {string} the JSON Pointer
 * @return {string} `null`, `bool`, `int`, `float`, `string`, `list`, `map` or `missing`
 */
func kindAt(v as json.Value, pointer as string) {
    if (not json.has($v, $pointer)) {
        return "missing";
    }
    return json.typeOf($v, $pointer);
}

/**
 * The JSON Schema type name of a value: `null`, `boolean`, `object`, `array`,
 * `string`, `integer` or `number`.
 *
 * A float with no fractional part is an `integer`, as the specification asks:
 * `1.0` is the integer one.
 *
 * @param v {json.Value} the value
 * @return {string} its type name
 */
func typeName(v as json.Value) {
    match (json.typeOf($v)) {
        when "null" { return "null"; }
        when "bool" { return "boolean"; }
        when "map" { return "object"; }
        when "list" { return "array"; }
        when "string" { return "string"; }
        when "int" { return "integer"; }
        else {
        }
    }
    if (isWhole(json.asFloat($v))) {
        return "integer";
    }
    return "number";
}

/**
 * Whether a float has no fractional part.
 *
 * @param f {float} the number
 * @return {bool} whether it is a whole number
 */
func isWhole(f as float) {
    # Past 2^53 every float is a whole number, and math.floor would not fit
    # the result in an int.
    if (math.abs($f) >= 9007199254740992.0) {
        return true;
    }
    return math.floor($f) == $f;
}

/**
 * Whether a value is any kind of number.
 *
 * @param v {json.Value} the value
 * @return {bool} whether it is an int or a float
 */
func isNumber(v as json.Value) {
    def t as string init json.typeOf($v);
    return $t == "int" or $t == "float";
}

/**
 * The number a bound keyword carries, as written in the schema.
 *
 * @param node {json.Value} the schema object
 * @param k {string} the keyword, such as `minLength`
 * @return {string} its value as JSON
 */
func limitText(node as json.Value, k as string) {
    return json.encode(json.get($node, "/" + $k));
}

/**
 * A property name as a JSON string, for a message: quoted, with control
 * characters escaped so a name cannot break a line of `describe`.
 *
 * @param name {string} the name
 * @return {string} the name as JSON
 */
func quoted(name as string) {
    return json.encode($name);
}

/**
 * A value as compact JSON, shortened for a message.
 *
 * @param v {json.Value} the value
 * @return {string} at most 60 characters of its JSON
 */
func show(v as json.Value) {
    def text as string init json.encode($v);
    if (len($text) > 60) {
        return strings.substring($text, 0, 57) + "...";
    }
    return $text;
}
