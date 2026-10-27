<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Validating

## Compile once

`compile` indexes the schema's identifiers and anchors, so do it once and keep
the `Schema`:

```jennifer
def s as jsonschema.Schema init jsonschema.compile(json.decode(fs.readString("order.schema.json")));
```

A schema is an object or `true` / `false`. Anything else throws an `Error` of
kind `jsonschema`.

## Two ways to check

`isValid` answers yes or no and stops at the first failure:

```jennifer
if (not jsonschema.isValid($s, $doc)) {
    io.printf("rejected\n");
}
```

`validate` keeps going and returns every failure:

```jennifer
def r as jsonschema.Result init jsonschema.validate($s, $doc);
for (def e in $r.errors) {
    io.printf("%s: %s\n", $e.instancePath, $e.message);
}
```

## Reading an `Issue`

| Field | Example | Meaning |
|---|---|---|
| `instancePath` | `/lines/0/quantity` | the failing value, as a JSON Pointer into the instance |
| `schemaPath` | `/properties/lines/items/$ref/properties/quantity/minimum` | the keyword that failed, including every `$ref` taken to reach it |
| `keyword` | `minimum` | the keyword alone |
| `message` | `must be >= 1` | a sentence for a person |

`describe` formats a `Result` one failure per line. `examples/validate.j`
prints this for an order with four problems:

```text
/id: is not a valid uuid [/properties/id/format]
/lines/0/sku: does not match the pattern ^[A-Z]{3}-[0-9]{4}$ [/properties/lines/items/$ref/properties/sku/pattern]
/lines/0/quantity: must be >= 1 [/properties/lines/items/$ref/properties/quantity/minimum]
/lines/0: property "note" is not allowed [/properties/lines/items/$ref/additionalProperties]
```

`anyOf` and `oneOf` report their own failure first, then the failures of each
branch, so the list says both that no branch matched and why each did not.

## Equality and numbers

`enum`, `const` and `uniqueItems` use JSON Schema's equality: `1` equals `1.0`,
`0` does not equal `false`, and objects are equal regardless of key order.

A number with no fractional part is an `integer` for `type`, whether it was
written `3` or `3.0`. `multipleOf` is exact for two integers; otherwise it
allows a relative error of 1e-9, so `19.99` is a multiple of `0.01`.

`minLength` and `maxLength` count code points, not bytes.

## Patterns

`pattern` and `patternProperties` use Jennifer's `regex`, which is RE2, not
ECMA-262. `\s`, `\S`, `.`, `\cX` and `\uXXXX` are translated to mean what
ECMA-262 means; `\S` inside a class keeps RE2's ASCII meaning. Lookaround and
backreferences have no RE2 equivalent: a schema that uses them throws an
`Error` of kind `jsonschema` when evaluation reaches the pattern, rather than
silently matching nothing. RE2 runs in linear time, so no pattern can make
matching hang.

## Limits

- Following more than 200 references in a row without moving into the
  instance is a reference cycle, and throws kind `jsonschema`. A recursive
  schema walking a deep instance moves on every level and is not limited.
- An instance nested several hundred levels deep under a recursive schema
  reaches Jennifer's call-depth limit; `validate` and `isValid` then throw
  kind `jsonschema`. `json.decode` refuses more than 1000 levels anyway.
- Property names from the instance are quoted as JSON strings in messages, so
  `describe` prints one line per failure whatever the instance holds.
- A schema can make evaluation take exponential time, for example `allOf`
  lists that repeat a `$ref` level after level. Untrusted values are safe to
  validate; an untrusted schema is not, wherever a slow call matters.
