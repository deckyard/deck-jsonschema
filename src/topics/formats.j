# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - format assertion, for a schema compiled with `assertFormats($s, true)`.
#
# Checked: `date-time`, `date`, `time`, `duration`, `email`, `hostname`,
# `ipv4`, `ipv6`, `uri`, `uri-reference`, `uuid`, `json-pointer`,
# `relative-json-pointer` and `regex`. Every other format passes, as the
# specification allows for one an implementation does not know.
# Spliced into jsonschema.j via include - not a standalone module.

# An ISO 8601 duration as RFC 3339 appendix A defines it.
def const DURATION_TIME as string init "T(?:[0-9]+H(?:[0-9]+M(?:[0-9]+S)?)?|[0-9]+M(?:[0-9]+S)?|[0-9]+S)";
def const DURATION_DATE as string init "(?:[0-9]+D|[0-9]+M(?:[0-9]+D)?|[0-9]+Y(?:[0-9]+M(?:[0-9]+D)?)?)";

# The characters RFC 3986 allows in a URI, outside percent-encoding.
def const URI_CHARS as string init "[A-Za-z0-9._~:/?#@!$&'()*+,;=%\\[\\]-]*";

# An unquoted local part of an email address: RFC 5321 dot-atom text.
def const EMAIL_ATOM as string init "[A-Za-z0-9!#$%&'*+/=?^_`\{|\}~-]+";

/**
 * Whether a value satisfies a named format. Only strings are checked; any
 * other type, and any format this deck does not know, passes.
 *
 * @param name {string} the format, such as `email`
 * @param v {json.Value} the value
 * @return {bool} whether it conforms
 */
func formatMatches(name as string, v as json.Value) {
    if (json.typeOf($v) != "string") {
        return true;
    }
    def s as string init json.asString($v);
    match ($name) {
        when "date-time" { return isDateTime($s); }
        when "date" { return isDate($s); }
        when "time" { return isTime($s); }
        when "duration" { return isDuration($s); }
        when "email" { return isEmail($s); }
        when "hostname" { return isHostname($s); }
        when "ipv4" { return isIPv4($s); }
        when "ipv6" { return isIPv6($s); }
        when "uri" { return isUri($s, true); }
        when "uri-reference" { return isUri($s, false); }
        when "uuid" { return isUuid($s); }
        when "json-pointer" { return isJsonPointer($s); }
        when "relative-json-pointer" { return isRelativeJsonPointer($s); }
        when "regex" { return isRegex($s); }
        else { return true; }
    }
}

/**
 * The number a run of ASCII digits spells.
 *
 * @param s {string} the digits
 * @return {int} the value
 */
func digits(s as string) {
    return convert.toInt($s);
}

/**
 * Whether a year is a leap year in the Gregorian calendar.
 *
 * @param year {int} the year
 * @return {bool} whether February has 29 days
 */
func isLeapYear(year as int) {
    return ($year % 4 == 0 and $year % 100 != 0) or $year % 400 == 0;
}

/**
 * RFC 3339 `full-date`: `YYYY-MM-DD`, a day that exists.
 *
 * @param s {string} the text
 * @return {bool} whether it is a date
 */
func isDate(s as string) {
    def m as regex.Match init regex.find("^([0-9]\{4\})-([0-9]\{2\})-([0-9]\{2\})$", $s);
    if ($m.start < 0) {
        return false;
    }
    def month as int init digits($m.groups[1]);
    def day as int init digits($m.groups[2]);
    if ($month < 1 or $month > 12 or $day < 1) {
        return false;
    }
    def last as list of int init [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    def most as int init $last[$month - 1];
    if ($month == 2 and isLeapYear(digits($m.groups[0]))) {
        $most = 29;
    }
    return $day <= $most;
}

/**
 * RFC 3339 `full-time`: `HH:MM:SS[.frac]` and an offset. A leap second is
 * allowed only where it falls at 23:59:60 UTC.
 *
 * @param s {string} the text
 * @return {bool} whether it is a time
 */
func isTime(s as string) {
    def m as regex.Match init regex.find(
        "^([0-9]\{2\}):([0-9]\{2\}):([0-9]\{2\})(?:\\.[0-9]+)?(?:([Zz])|([+-])([0-9]\{2\}):([0-9]\{2\}))$",
        $s);
    if ($m.start < 0) {
        return false;
    }
    def hour as int init digits($m.groups[0]);
    def minute as int init digits($m.groups[1]);
    def second as int init digits($m.groups[2]);
    def offset as int init 0;
    if ($m.groups[3] == "") {
        def oh as int init digits($m.groups[5]);
        def om as int init digits($m.groups[6]);
        if ($oh > 23 or $om > 59) {
            return false;
        }
        $offset = $oh * 60 + $om;
        if ($m.groups[4] == "-") {
            $offset = 0 - $offset;
        }
    }
    if ($hour > 23 or $minute > 59 or $second > 60) {
        return false;
    }
    if ($second < 60) {
        return true;
    }
    def utc as int init (($hour * 60 + $minute - $offset) % 1440 + 1440) % 1440;
    return $utc == 23 * 60 + 59;
}

/**
 * RFC 3339 `date-time`: a date, `T`, and a time.
 *
 * @param s {string} the text
 * @return {bool} whether it is a date-time
 */
func isDateTime(s as string) {
    def m as regex.Match init regex.find("^([^Tt]+)[Tt](.+)$", $s);
    if ($m.start < 0) {
        return false;
    }
    return isDate($m.groups[0]) and isTime($m.groups[1]);
}

/**
 * An ISO 8601 duration as RFC 3339 appendix A has it: `P1Y2M`, `PT5M`, `P3W`.
 *
 * @param s {string} the text
 * @return {bool} whether it is a duration
 */
func isDuration(s as string) {
    def pattern as string init "^P(?:" + DURATION_DATE + "(?:" + DURATION_TIME + ")?|" +
        DURATION_TIME + "|[0-9]+W)$";
    return regex.matches($pattern, $s);
}

/**
 * RFC 5321 `Mailbox`: a dot-atom or quoted local part, `@`, and a host name
 * or an address literal.
 *
 * @param s {string} the text
 * @return {bool} whether it is an email address
 */
func isEmail(s as string) {
    def at as int init strings.lastIndexOf($s, "@");
    if ($at < 1) {
        return false;
    }
    def local as string init strings.substring($s, 0, $at);
    def domain as string init strings.substring($s, $at + 1, len($s));
    return isLocalPart($local) and isMailDomain($domain);
}

/**
 * The part of an email address before the `@`.
 *
 * @param s {string} the local part
 * @return {bool} whether it is a dot-atom or a quoted string
 */
func isLocalPart(s as string) {
    if (regex.matches("^" + EMAIL_ATOM + "(?:\\." + EMAIL_ATOM + ")*$", $s)) {
        return true;
    }
    # A quoted string: printable ASCII except `"` and `\`, or a quoted pair.
    return regex.matches('^"(?:[\x20\x21\x23-\x5b\x5d-\x7e]|\\[\x20-\x7e])*"$', $s);
}

/**
 * The part of an email address after the `@`.
 *
 * @param s {string} the domain
 * @return {bool} whether it is a host name or a bracketed address literal
 */
func isMailDomain(s as string) {
    if (not strings.startsWith($s, "[")) {
        return isHostname($s);
    }
    if (not strings.endsWith($s, "]")) {
        return false;
    }
    def inner as string init strings.substring($s, 1, len($s) - 1);
    if (strings.startsWith(strings.lower($inner), "ipv6:")) {
        return isIPv6(strings.substring($inner, 5, len($inner)));
    }
    return isIPv4($inner);
}

/**
 * RFC 1123 host name: dot-separated labels of letters, digits and inner
 * hyphens, each 1 to 63 characters, 253 in all.
 *
 * An `xn--` label is checked only for this syntax, not decoded: validating
 * Punycode against IDNA's rules needs Unicode tables this deck does not carry.
 *
 * @param s {string} the text
 * @return {bool} whether it is a host name
 */
func isHostname(s as string) {
    if (len($s) == 0 or len($s) > 253) {
        return false;
    }
    for (def label in strings.split($s, ".")) {
        if (not regex.matches("^[A-Za-z0-9](?:[A-Za-z0-9-]\{0,61\}[A-Za-z0-9])?$", $label)) {
            return false;
        }
        def lower as string init strings.lower($label);
        if (strings.startsWith($lower, "xn--") and len($label) < 6) {
            return false;
        }
        # RFC 5891: hyphens in the third and fourth places mark an A-label.
        if (len($label) >= 4 and strings.substring($label, 2, 4) == "--" and
            not strings.startsWith($lower, "xn--")) {
            return false;
        }
    }
    return true;
}

/**
 * Dotted-quad IPv4: four decimal numbers 0 to 255, no leading zeros.
 *
 * @param s {string} the text
 * @return {bool} whether it is an IPv4 address
 */
func isIPv4(s as string) {
    def parts as list of string init strings.split($s, ".");
    if (len($parts) != 4) {
        return false;
    }
    for (def p in $parts) {
        if (not regex.matches("^(?:0|[1-9][0-9]\{0,2\})$", $p) or digits($p) > 255) {
            return false;
        }
    }
    return true;
}

/**
 * RFC 4291 IPv6 text form: eight groups, `::` for a run of zero groups, and
 * optionally a dotted-quad IPv4 address in place of the last two. No zone.
 *
 * @param s {string} the text
 * @return {bool} whether it is an IPv6 address
 */
func isIPv6(s as string) {
    if (len(strings.split($s, "::")) > 2 or not regex.matches("^[0-9A-Fa-f:.]+$", $s)) {
        return false;
    }
    def halves as list of string init strings.split($s, "::");
    # A dotted quad may only end the address.
    if (len($halves) == 2 and strings.contains($halves[0], ".")) {
        return false;
    }
    def groups as int init 0;
    for (def h in $halves) {
        if ($h == "") {
            continue;
        }
        def counted as int init ipv6Groups($h);
        if ($counted < 0) {
            return false;
        }
        $groups = $groups + $counted;
    }
    if (strings.contains($s, ".") and not regex.matches("[0-9.]+$", lists.last($halves))) {
        return false;
    }
    if (len($halves) == 2) {
        return $groups <= 7;
    }
    return $groups == 8;
}

/**
 * How many 16-bit groups one side of an IPv6 `::` holds.
 *
 * @param part {string} colon-separated groups, the last possibly an IPv4 address
 * @return {int} the number of groups, an IPv4 address counting two; -1 if malformed
 */
func ipv6Groups(part as string) {
    def fields as list of string init strings.split($part, ":");
    def n as int init 0;
    for (def i in 0..len($fields)) {
        def f as string init $fields[$i];
        if ($i == len($fields) - 1 and strings.contains($f, ".")) {
            if (not isIPv4($f)) {
                return -1;
            }
            $n = $n + 2;
            continue;
        }
        if (not regex.matches("^[0-9A-Fa-f]\{1,4\}$", $f)) {
            return -1;
        }
        $n = $n + 1;
    }
    return $n;
}

/**
 * RFC 3986 URI, or with `absolute` false a URI reference, which may be
 * relative.
 *
 * Checks the scheme, the characters used, every percent-encoding, and that
 * square brackets appear only around an IP literal host.
 *
 * @param s {string} the text
 * @param absolute {bool} whether a scheme is required
 * @return {bool} whether it conforms
 */
func isUri(s as string, absolute as bool) {
    if (not regex.matches("^" + URI_CHARS + "$", $s)) {
        return false;
    }
    if (regex.matches("%(?:[^0-9A-Fa-f]|[0-9A-Fa-f][^0-9A-Fa-f]|[0-9A-Fa-f]?$)", $s)) {
        return false;
    }
    def hasScheme as bool init regex.matches("^[A-Za-z][A-Za-z0-9+.-]*:", $s);
    if ($absolute and not $hasScheme) {
        return false;
    }
    if (not $hasScheme and regex.matches("^[^/?#]*:", $s)) {
        return false;
    }
    def m as regex.Match init regex.find("^(?:[A-Za-z][A-Za-z0-9+.-]*:)?//([^/?#]*)", $s);
    def authority as string init "";
    def rest as string init $s;
    if ($m.start >= 0) {
        $authority = $m.groups[0];
        $rest = strings.substring($s, $m.end, len($s));
    }
    if (strings.contains($rest, "[") or strings.contains($rest, "]")) {
        return false;
    }
    return isAuthority($authority);
}

/**
 * The authority part of a URI: optional user info, a host, an optional port.
 *
 * @param a {string} the authority, without the leading `//`
 * @return {bool} whether it is well formed
 */
func isAuthority(a as string) {
    def host as string init $a;
    def at as int init strings.indexOf($host, "@");
    if ($at >= 0) {
        # User info may hold neither another `@` nor a bracket.
        if (regex.matches("[\\[\\]]", strings.substring($host, 0, $at))) {
            return false;
        }
        $host = strings.substring($host, $at + 1, len($host));
        if (strings.contains($host, "@")) {
            return false;
        }
    }
    if (strings.startsWith($host, "[")) {
        def close as int init strings.indexOf($host, "]");
        if ($close < 0) {
            return false;
        }
        def port as string init strings.substring($host, $close + 1, len($host));
        return isIPv6(strings.substring($host, 1, $close)) and
            regex.matches("^(?::[0-9]*)?$", $port);
    }
    if (strings.contains($host, "[") or strings.contains($host, "]")) {
        return false;
    }
    return regex.matches("^[^:]*(?::[0-9]*)?$", $host);
}

/**
 * RFC 4122 UUID in its hyphenated hex form.
 *
 * @param s {string} the text
 * @return {bool} whether it is a UUID
 */
func isUuid(s as string) {
    def hex as string init "[0-9A-Fa-f]";
    return regex.matches(
        "^" + $hex + "\{8\}-" + $hex + "\{4\}-" + $hex + "\{4\}-" + $hex + "\{4\}-" + $hex +
            "\{12\}$",
        $s);
}

/**
 * RFC 6901 JSON Pointer: `""`, or `/`-led tokens where `~` only starts `~0`
 * or `~1`.
 *
 * @param s {string} the text
 * @return {bool} whether it is a JSON Pointer
 */
func isJsonPointer(s as string) {
    return regex.matches("^(?:/(?:[^/~]|~[01])*)*$", $s);
}

/**
 * A relative JSON Pointer: a non-negative integer, then `#` or a JSON Pointer.
 *
 * @param s {string} the text
 * @return {bool} whether it is a relative JSON Pointer
 */
func isRelativeJsonPointer(s as string) {
    return regex.matches(
        "^(?:0|[1-9][0-9]*)(?:[+-](?:0|[1-9][0-9]*))?(?:#|(?:/(?:[^/~]|~[01])*)*)$",
        $s);
}

/**
 * Whether a string compiles as a regular expression.
 *
 * Compiled as RE2, Jennifer's dialect, not ECMA-262: the two disagree at the
 * edges, so this is an approximation.
 *
 * @param s {string} the text
 * @return {bool} whether it compiles
 */
func isRegex(s as string) {
    try {
        regex.matches(ecmaPattern($s), "");
    } catch (e) {
        return false;
    }
    return true;
}
