<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/jsonschema

Validates a `json.Value` against a [JSON Schema](https://json-schema.org/)
draft 2020-12 schema, and says where and why it fails. It passes every required
test in the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite);
[Conformance](conformance.md) lists the exceptions.

This deck is part of [Deckyard](https://github.com/deckyard), community decks for [Jennifer](https://jennifer-lang.dev/).

```jennifer
import "@deckyard/jsonschema/" as jsonschema;

def s as jsonschema.Schema init jsonschema.compile(json.decode('{"type": "integer", "minimum": 1}'));
jsonschema.isValid($s, json.decode("3"));                     # true
io.printf("%s", jsonschema.describe(jsonschema.validate($s, json.decode("0"))));
# (root): must be >= 1 [/minimum]
```

Compile a schema once and validate any number of values against it. Nothing
is fetched: references resolve within the schema, to documents you register,
and to the embedded 2020-12 meta-schemas.

## Guides

- [Validating](validating.md): `validate`, `isValid` and reading the errors
- [References](references.md): `$ref`, `$id`, anchors, and registering other documents
- [Formats](formats.md): which `format` values are checked, and how to turn that on
- [Conformance](conformance.md): test-suite results and known gaps

## Conventions

Snippets assume this import, which `tools/check-docs.sh` relies on:

```jennifer
import "@deckyard/jsonschema/" as jsonschema;
```

A schema the deck cannot use throws an `Error` of kind `jsonschema`, with a
message that names the place in the schema. A value that fails a schema does
not throw; it comes back in the `Result`.
