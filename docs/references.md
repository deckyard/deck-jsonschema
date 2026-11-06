<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# References

## Inside one schema

`$ref` takes a JSON Pointer fragment or an anchor:

```json
{
    "$defs": {
        "positive": {"$anchor": "pos", "type": "integer", "minimum": 1}
    },
    "properties": {
        "count": {"$ref": "#/$defs/positive"},
        "limit": {"$ref": "#pos"}
    }
}
```

`$id` starts a new resource with its own base URI, and relative references
inside it resolve against that base. A schema with no absolute `$id` gets
`DEFAULT_BASE`, `jsonschema:/root.json`.

## Other documents

Nothing is fetched. A reference to another document resolves only if that
document is in the `Registry` the schema was compiled with:

```jennifer
def reg as jsonschema.Registry init jsonschema.registry();
$reg = jsonschema.register($reg, "https://example.com/address.json", json.decode(fs.readString("address.json")));
def s as jsonschema.Schema init jsonschema.compileWith(json.decode(fs.readString("customer.json")), $reg);
```

`register` indexes the document at once, including every `$id` inside it. A
document with its own `$id` is reachable under both `uri` and that `$id`;
relative references inside it resolve against the `$id`. Build the registry
once and compile any number of schemas against it.

A reference that resolves to nothing throws an `Error` of kind `jsonschema`
when evaluation reaches it, naming the reference.

## The meta-schemas

The draft 2020-12 meta-schema and its seven vocabulary meta-schemas are
embedded. A schema that references one, such as
`{"$ref": "https://json-schema.org/draft/2020-12/schema"}`, works without
registering anything, which is how you validate a schema itself:

```jennifer
def meta as jsonschema.Schema init jsonschema.compile(json.decode('{"$ref": "https://json-schema.org/draft/2020-12/schema"}'));
jsonschema.isValid($meta, json.decode('{"type": 3}'));    # false
```

They are indexed only when a `$ref` or `$dynamicRef` in the schema or the
registry contains `json-schema.org/draft/2020-12/`.

## `$dynamicRef`

As draft 2020-12 defines it: a `$dynamicRef` to a plain-name fragment that
first lands on a `$dynamicAnchor` resolves to the outermost resource in the
dynamic scope with the same anchor. Any other `$dynamicRef` behaves as `$ref`.
A schema can so extend a recursive one, such as a tree whose nodes it
constrains further.

## Vocabularies

Each schema resource with a `$schema` (the root, an `$id` subschema, a
registered document) gets the vocabularies its meta-schema lists in
`$vocabulary`; a resource without one keeps those of the schema that reached
it. Two vocabularies take effect:

- without the validation vocabulary, `type`, `minimum`, `required` and the
  other validation keywords pass every value; applicators still run;
- with the format-assertion vocabulary, `format` is asserted strictly (see
  [Formats](formats.md)).

A meta-schema that requires (`true`) a vocabulary other than the eight of
2020-12 makes `compile` throw kind `jsonschema`; an unknown optional one
(`false`) is ignored. A `$schema` that does not resolve, or a meta-schema
without `$vocabulary`, leaves the defaults: validation on, `format`
annotation-only. `compile` reads the vocabularies of every resource it can
reach through `$ref`; one reached only through a `$dynamicRef` redirect keeps
the vocabularies in force.

## Older drafts

Only 2020-12 is implemented; a schema written for an older draft is evaluated
as 2020-12:

- draft 7's `dependencies` is honoured (array entries as `dependentRequired`,
  schema entries as `dependentSchemas`);
- `definitions` is not special, but `$ref` to `#/definitions/x` resolves
  because it is a plain JSON Pointer;
- array-form `items` (drafts 4 to 2019-09) throws kind `jsonschema`, and
  `additionalItems` is ignored;
- draft 4's boolean `exclusiveMinimum` / `exclusiveMaximum` throws;
- 2019-09's `$recursiveRef` and `$recursiveAnchor` are ignored.
