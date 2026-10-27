# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests: jennifer test src/jsonschema_test.j
 *
 * Mirrors the include splice of jsonschema.j over the topic overlays, so the
 * tests reach unexported helpers. Most of the coverage is the official
 * JSON-Schema-Test-Suite in testdata/suite, run file by file.
 */
use testing;
use fs;

include "topics/core_test.j";
include "topics/registry_test.j";
include "topics/evaluate_test.j";
include "topics/values_test.j";
include "topics/arrays_test.j";
include "topics/objects_test.j";
include "topics/formats_test.j";
