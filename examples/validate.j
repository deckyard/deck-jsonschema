#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Validate two orders against one schema: jennifer run examples/validate.j
 *
 * Compiles the schema once, checks a good order with `isValid`, then lists
 * what is wrong with a bad one using `validate` and `describe`.
 */

use io;
use json;

import "../src/jsonschema.j" as jsonschema;

def schema as json.Value init json.decode('{
    "$defs": {
        "line": {
            "type": "object",
            "properties": {
                "sku": {"type": "string", "pattern": "^[A-Z]{3}-[0-9]{4}$"},
                "quantity": {"type": "integer", "minimum": 1}
            },
            "required": ["sku", "quantity"],
            "additionalProperties": false
        }
    },
    "type": "object",
    "properties": {
        "id": {"type": "string", "format": "uuid"},
        "email": {"type": "string", "format": "email"},
        "lines": {"type": "array", "items": {"$ref": "#/$defs/line"}, "minItems": 1}
    },
    "required": ["id", "lines"]
}');

def s as jsonschema.Schema init jsonschema.assertFormats(jsonschema.compile($schema), true);

def good as json.Value init json.decode('{
    "id": "2eb8aa08-aa98-11ea-b4aa-73b441d16380",
    "email": "ada@example.com",
    "lines": [{"sku": "ABC-0001", "quantity": 2}]
}');
io.printf("good order valid: %t\n", jsonschema.isValid($s, $good));

def bad as json.Value init json.decode('{
    "id": "not-a-uuid",
    "lines": [{"sku": "abc-1", "quantity": 0, "note": "gift"}]
}');
def r as jsonschema.Result init jsonschema.validate($s, $bad);
io.printf("bad order valid: %t, %d errors\n", $r.valid, len($r.errors));
io.printf("%s", jsonschema.describe($r));
