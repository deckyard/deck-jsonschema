# @deckyard/jsonschema

[![test](https://github.com/deckyard/deck-jsonschema/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-jsonschema/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-jsonschema/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-jsonschema)](https://github.com/deckyard/deck-jsonschema/releases/latest)

Validates a `json.Value` against a [JSON Schema](https://json-schema.org/)
draft 2020-12 schema in [Jennifer](https://jennifer-lang.dev/), and reports
every failure with a JSON Pointer to the value and to the keyword. Passes every
required test in the official JSON-Schema-Test-Suite.

**[Documentation](https://deckyard.github.io/deck-jsonschema/)**

## Install

```sh
jvc add @deckyard/jsonschema
```

This vendors the deck to `vendor/deckyard/jsonschema/`. Without `jvc`, unpack
the `src/` subtree of a release archive (`deckyard-jsonschema-<version>.tar.gz`)
there.

## Usage

```jennifer
import "@deckyard/jsonschema/" as jsonschema;

def s as jsonschema.Schema init jsonschema.compile(json.decode(fs.readString("order.schema.json")));
def r as jsonschema.Result init jsonschema.validate($s, json.decode(fs.readString("order.json")));
if (not $r.valid) {
    io.printf("%s", jsonschema.describe($r));
}
```

`examples/validate.j` validates a good and a bad order.

## Scope

- All of draft 2020-12: `$ref`, `$dynamicRef`, `$anchor`, `unevaluatedProperties`,
  `unevaluatedItems`, vocabularies. Draft 7's `dependencies` is honoured too.
- No network: references resolve within the schema, to documents registered in
  a `Registry`, and to the embedded 2020-12 meta-schemas.
- `format` is checked on request for the common formats; see the
  [formats guide](https://deckyard.github.io/deck-jsonschema/formats.html).
- Patterns are RE2, Jennifer's regex dialect, with ECMA-262's `\s`, `.`, `\cX`
  and `\uXXXX` translated; lookaround and backreferences are not available.

## Requirements

Jennifer 0.25.0 or newer. Pure computation: no network, no capabilities. Not
tested on `jennifer-tiny`.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/jsonschema_test.j  # unit tests and the test suite
tools/gen-meta.sh                    # refresh the embedded meta-schemas
```

`testdata/suite` is the vendored JSON-Schema-Test-Suite (MIT);
`testdata/exclusions.txt` lists the cases the deck knowingly fails, and why.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

The embedded meta-schemas in `src/topics/meta.j` are the JSON Schema
Specification Authors' work under BSD-3-Clause or AFL-3.0; the notice is in
that file.
