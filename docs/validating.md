<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Validating

## Compile once

`compile` indexes the schema's identifiers and anchors, resolves every
reference it can reach and translates every pattern, so do it once and keep
the `Schema`:

```jennifer
def s as jsonschema.Schema init jsonschema.compile(json.decode(fs.readString("order.schema.json")));
```

A schema is an object or `true` / `false`. Anything else throws an `Error` of
kind `jsonschema`.

## Two ways to check

`isValid` answers yes or no. It stops at the first failing keyword of a
schema object, and `allOf`, `properties`, `items` and the other keywords that
apply subschemas stop at their first failing one. `anyOf`, `oneOf`, `contains`
and `if` still evaluate every branch or item, because their answer or their
annotations need it:

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

`describe` formats a `Result` one failure per line, writing the empty
instance path as `(root)`. `examples/validate.j`
prints this for an order with four problems:

```text
/id: is not a valid uuid [/properties/id/format]
/lines/0/sku: does not match the pattern ^[A-Z]{3}-[0-9]{4}$ [/properties/lines/items/$ref/properties/sku/pattern]
/lines/0/quantity: must be >= 1 [/properties/lines/items/$ref/properties/quantity/minimum]
/lines/0: property "note" is not allowed [/properties/lines/items/$ref/additionalProperties]
```

When no branch matches, `anyOf` and `oneOf` report their own failure first,
then every failure of each branch. When several `oneOf` branches match, the
one failure names their indices.

Messages quote property names as JSON strings (`missing required properties:
"a", "c"`, `"a" requires "b"`) and cut each name, like each value, to 60
characters; `instancePath` keeps the whole name.

## Equality and numbers

`enum`, `const` and `uniqueItems` use JSON Schema's equality: `1` equals `1.0`,
`0` does not equal `false`, and objects are equal regardless of key order.

A number with no fractional part is an `integer` for `type`, whether it was
written `3` or `3.0`.

`multipleOf` is exact. Two whole numbers within the int range use the int
remainder, however they were written: `1000000001` is not a multiple of `2.0`.
Otherwise both numbers are compared as decimals, read from their shortest
decimal text: `19.99` is a multiple of `0.01` and `0.0075` of `0.0001`,
although their binary quotients are not whole, and `1000000000000000.25` is
not a multiple of `0.5`. Only a whole divisor of 18 or more significant
digits against a value beyond 2^63 falls back to the float quotient, within
4 ulps.

`minLength` and `maxLength` count code points, not bytes.

## Patterns

`pattern` and `patternProperties` use Jennifer's `regex`, which is RE2, not
ECMA-262. `\s`, `\S`, `.`, `\cX`, `\uXXXX` and `\u{...}` are translated to
mean what ECMA-262 means, a surrogate pair `\uD83D\uDE00` as one code point;
`\S` inside a class keeps RE2's ASCII meaning. Lookaround and
backreferences have no RE2 equivalent: a schema that uses them throws an
`Error` of kind `jsonschema` when evaluation reaches the pattern, rather than
silently matching nothing. RE2 runs in linear time, so no pattern can make
matching hang.

## Limits

- Following more than 200 references in a row without moving into the
  instance is a reference cycle, and throws kind `jsonschema`. A recursive
  schema walking a deep instance moves on every level and is not limited.
- A deeply nested instance under a recursive schema reaches Jennifer's
  call-depth limit; `validate` and `isValid` then throw kind `jsonschema`
  with the message `the instance is nested too deeply to evaluate`. With
  `{"items": {"$ref": "#"}}` the limit is between 520 and 540 nested arrays;
  each extra keyword per level lowers it. `json.decode` refuses more than
  1000 levels.
- Property names from the instance are quoted as JSON strings in messages and
  cut to 60 characters, so `describe` prints one short line per failure
  whatever the instance holds.
- Against a fixed schema, run time grows linearly with the size of the value:
  every keyword visits each property, item or character a bounded number of
  times, `uniqueItems` included (20,000 distinct integers from 2^62: 137 ms).
  Throughput is roughly 0.7 ms per record of five typed properties (100,000
  records, 7.7 MB: 71 s on 0.25.0-dev+47), so bound the size of an untrusted
  value before validating it where run time matters.
- A schema can make evaluation take exponential time, for example `allOf`
  lists that repeat a `$ref` level after level. An untrusted schema is not
  safe where run time matters.
