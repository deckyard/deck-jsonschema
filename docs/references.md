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

`register` indexes the document at once, including any `$id` inside it, and the
document's own absolute `$id` wins over the URI you give. Build the registry
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

They are loaded only when something refers to them.

## `$dynamicRef`

Supported as draft 2020-12 defines it: a `$dynamicRef` to a plain-name fragment
that first lands on a `$dynamicAnchor` resolves to the outermost resource in
the dynamic scope with the same anchor. This is what lets a schema extend a
recursive one, such as a tree whose nodes you constrain further.

## Vocabularies

When the root's `$schema` resolves to a meta-schema with a `$vocabulary`, two
vocabularies are honoured:

- without the validation vocabulary, `type`, `minimum`, `required` and the
  other assertions are ignored;
- with the format-assertion vocabulary, `format` is asserted.

## Older drafts

Only 2020-12 is implemented. A schema written for an older draft is evaluated
as 2020-12, which works for most of them: the one exception that matters,
draft 7's `dependencies`, is honoured as well. `definitions` is not special;
`$ref` to `#/definitions/x` still works because it is a plain JSON Pointer.
