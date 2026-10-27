<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Conformance

The test overlay runs the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite)
for draft 2020-12, vendored in `testdata/suite`. Every test checks both
`isValid` and `validate`. The suite is part of the repository, not of the
installed deck: run from an installed deck, the suite tests pass without
running and only the unit tests check anything.

| Part of the suite | Result |
|---|---|
| Required: 46 files, 1302 cases | all pass |
| Optional, non-format: 13 files | all pass except one cross-draft case |
| Optional formats the deck checks | all pass except the cases below |

`testdata/exclusions.txt` lists every case the deck knowingly gets wrong, and
each test asserts its file fails exactly those: a new failure breaks the build,
and so does an exclusion that starts passing.

## Known gaps

- **Older drafts.** A `$ref` to a draft 2019-09 or earlier meta-schema is
  evaluated as 2020-12 (1 case).
- **IDNA host names.** `hostname` does not decode `xn--` labels, so it accepts
  Punycode that decodes to characters IDNA 2008 forbids (22 cases).
- **ECMA-262 regular expressions.** The `regex` format compiles patterns as
  RE2. It accepts Python-style named groups and inline flags, and rejects
  backreferences, lookbehind and empty classes (8 cases).

Formats the deck does not check (`idn-email`, `idn-hostname`, `iri`,
`iri-reference`, `uri-template`) are not run.
