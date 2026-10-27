<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formats

Draft 2020-12 treats `format` as an annotation: by default
`{"format": "email"}` accepts any string. Turn assertion on per schema:

```jennifer
def s as jsonschema.Schema init jsonschema.assertFormats(jsonschema.compile($schema), true);
```

A schema whose meta-schema lists the format-assertion vocabulary has it on
from the start.

Only strings are checked; a number passes `"format": "email"`.

## Checked

| Format | Accepts |
|---|---|
| `date-time` | RFC 3339 date-time; a leap second only at 23:59:60 UTC |
| `date` | `YYYY-MM-DD`, a day that exists |
| `time` | RFC 3339 time with an offset |
| `duration` | ISO 8601 duration as RFC 3339 appendix A defines it |
| `email` | RFC 5321 mailbox: dot-atom or quoted local part, host name or address literal |
| `hostname` | RFC 1123 labels, 63 characters each, 253 in all |
| `ipv4` | dotted quad, no leading zeros |
| `ipv6` | RFC 4291 text form, with an optional trailing IPv4 address, no zone |
| `uri` | RFC 3986 URI with a scheme |
| `uri-reference` | RFC 3986 URI or relative reference |
| `uuid` | hyphenated hex |
| `json-pointer` | RFC 6901 |
| `relative-json-pointer` | relative JSON Pointer |
| `regex` | a pattern RE2 compiles (not ECMA-262: see [Validating](validating.md)) |

## Not checked

`idn-email`, `idn-hostname`, `iri`, `iri-reference` and `uri-template` pass any
string, as do formats the deck does not know. `hostname` checks an `xn--` label
for syntax only: decoding Punycode against the IDNA tables is not done.
