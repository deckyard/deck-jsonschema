<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Cheatsheet

Every export of `@deckyard/jsonschema`. `tools/check-docs.sh` checks this page
against the code.

```jennifer
import "@deckyard/jsonschema/" as jsonschema;
```

## Compiling

| Function | Returns | Does |
|---|---|---|
| `compile(schema)` | `Schema` | Compile a schema whose references stay inside it |
| `compileWith(schema, reg)` | `Schema` | Compile a schema whose references may reach documents in `reg` |
| `assertFormats(s, on)` | `Schema` | The same schema with `format` asserted (`true`) or only annotated (`false`, the default) |
| `registry()` | `Registry` | An empty registry |
| `register(reg, uri, schema)` | `Registry` | `reg` with `schema` added under the absolute URI `uri` |

`compile` and `compileWith` throw an `Error` of kind `jsonschema` when the
schema is not an object or a boolean, and `register` when `uri` is relative.

## Validating

| Function | Returns | Does |
|---|---|---|
| `validate(s, instance)` | `Result` | Check a value, collecting every failure |
| `isValid(s, instance)` | `bool` | Check a value, stopping at the first failure |
| `describe(r)` | `string` | One line per failure: `instancePath: message [schemaPath]` |

Both checks throw an `Error` of kind `jsonschema` when evaluation reaches a part
of the schema it cannot use: a `$ref` that resolves to nothing, a reference
cycle, a keyword with a value of the wrong type, or a `pattern` RE2 cannot
compile.

## Types

### `Schema`

| Field | Meaning |
|---|---|
| `root as json.Value` | the schema document |
| `base as string` | its base URI: its `$id`, or `DEFAULT_BASE` |
| `registry as Registry` | every resource its references can reach |
| `formats as bool` | whether `format` is asserted |
| `validation as bool` | whether the validation vocabulary is in force |

### `Registry`

| Field | Meaning |
|---|---|
| `resources as map of string to json.Value` | resource URI to its root schema |
| `anchors as map of string to string` | `uri#name` to `uri#pointer` |
| `dynamic as map of string to bool` | `uri#name` of every `$dynamicAnchor` |
| `meta as bool` | whether the 2020-12 meta-schemas are loaded |

### `Result`

| Field | Meaning |
|---|---|
| `valid as bool` | whether the value satisfies the schema |
| `errors as list of Issue` | why not; empty when `valid` |

### `Issue`

| Field | Meaning |
|---|---|
| `instancePath as string` | JSON Pointer to the failing value |
| `schemaPath as string` | JSON Pointer to the failing keyword, through every `$ref` followed |
| `keyword as string` | the keyword that failed |
| `message as string` | what is wrong |

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"jsonschema"` | the `kind` of every `Error` the deck throws |
| `DEFAULT_BASE` | `"jsonschema:/root.json"` | the base URI of a schema without an absolute `$id` |
