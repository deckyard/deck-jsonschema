# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * JSON Schema draft 2020-12 validation over `json.Value`.
 *
 * Compile a schema once with `compile`, then `validate` or `isValid` any
 * number of values against it. References resolve within the schema, to
 * documents added to a `Registry`, and to the embedded 2020-12 meta-schemas;
 * nothing is fetched.
 *
 * A topics deck: this file `include`s every file in `topics/`, so it is the
 * one namespace.
 *
 * @module jsonschema
 */
use json;
use strings;
use convert;
use lists;
use maps;
use math;
use regex;

import "uri.j";

include "topics/core.j";
include "topics/meta.j";
include "topics/registry.j";
include "topics/evaluate.j";
include "topics/values.j";
include "topics/arrays.j";
include "topics/objects.j";
include "topics/formats.j";
