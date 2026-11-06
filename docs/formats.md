<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formats

Draft 2020-12 treats `format` as an annotation: by default
`{"format": "email"}` accepts any string. Turn assertion on per schema:

```jennifer
def s as jsonschema.Schema init jsonschema.assertFormats(jsonschema.compile($schema), true);
```

Only strings are checked; a number passes `"format": "email"`.

## The format-assertion vocabulary

A schema resource whose `$schema` names a meta-schema listing the
format-assertion vocabulary asserts `format` whatever `assertFormats` says,
and is stricter, as Validation 7.2.2 and 7.2.3 require:

- a format in "Not checked" below makes `compile` throw kind `jsonschema`;
- a format name the deck does not know fails every value, with the message
  `format "name" is unknown`.

The vocabulary applies per resource: a `$ref` into a resource with another
`$schema` uses that resource's vocabularies.

## Checked

| Format | Accepts |
|---|---|
| `date-time` | RFC 3339 date-time; a leap second only at 23:59:60 UTC |
| `date` | `YYYY-MM-DD`, a day that exists |
| `time` | RFC 3339 time with an offset; a leap second only at 23:59:60 UTC |
| `duration` | ISO 8601 duration as RFC 3339 appendix A defines it |
| `email` | RFC 5321 mailbox: dot-atom or quoted local part, host name or address literal |
| `hostname` | RFC 1123 labels, 63 characters each, 253 in all |
| `ipv4` | dotted quad, no leading zeros |
| `ipv6` | RFC 4291 text form, with an optional trailing IPv4 address, no zone |
| `uri` | RFC 3986 URI with a scheme |
| `uri-reference` | RFC 3986 URI or relative reference |
| `uuid` | 8-4-4-4-12 hex digits, any case, any version |
| `json-pointer` | RFC 6901 |
| `relative-json-pointer` | a non-negative integer, an optional `+N` / `-N` index offset, then `#` or a JSON Pointer |
| `regex` | a pattern RE2 compiles (not ECMA-262: see [Validating](validating.md)) |

## Not checked

`idn-email`, `idn-hostname`, `iri`, `iri-reference` and `uri-template` pass
any string under `assertFormats`, as do formats the deck does not know. Under
the format-assertion vocabulary they are refused (see above). `hostname`
checks an `xn--` label for syntax only: decoding Punycode against the IDNA
tables is not done.
