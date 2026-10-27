# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# jsonschema - white-box tests for the formats topic.
# Spliced into jsonschema_test.j via include - run with:
#   jennifer test src/jsonschema_test.j

func testFormatDateTime() {
    assertFormatSuite("optional/format/date-time.json");
}

func testFormatDate() {
    assertFormatSuite("optional/format/date.json");
}

func testFormatTime() {
    assertFormatSuite("optional/format/time.json");
}

func testFormatDuration() {
    assertFormatSuite("optional/format/duration.json");
}

func testFormatEmail() {
    assertFormatSuite("optional/format/email.json");
}

func testFormatHostname() {
    assertFormatSuite("optional/format/hostname.json");
}

func testFormatIpv4() {
    assertFormatSuite("optional/format/ipv4.json");
}

func testFormatIpv6() {
    assertFormatSuite("optional/format/ipv6.json");
}

func testFormatUri() {
    assertFormatSuite("optional/format/uri.json");
}

func testFormatUriReference() {
    assertFormatSuite("optional/format/uri-reference.json");
}

func testFormatUuid() {
    assertFormatSuite("optional/format/uuid.json");
}

func testFormatJsonPointer() {
    assertFormatSuite("optional/format/json-pointer.json");
}

func testFormatRelativeJsonPointer() {
    assertFormatSuite("optional/format/relative-json-pointer.json");
}

func testFormatRegex() {
    assertFormatSuite("optional/format/regex.json");
}

func testFormatEcmascriptRegex() {
    assertFormatSuite("optional/format/ecmascript-regex.json");
}

func testFormatUnknown() {
    assertFormatSuite("optional/format/unknown.json");
}

func testFormatsIgnoreNonStrings() {
    testing.assertTrue(formatMatches("email", json.decode("12")));
    testing.assertTrue(formatMatches("no-such-format", json.decode('"x"')));
}

func testDates() {
    testing.assertTrue(isDate("2024-02-29"));
    testing.assertFalse(isDate("2023-02-29"));
    testing.assertTrue(isLeapYear(2000));
    testing.assertFalse(isLeapYear(1900));
    testing.assertTrue(isTime("23:59:60Z"));
    testing.assertFalse(isTime("23:58:60Z"));
    testing.assertTrue(isDateTime("1998-12-31T15:59:60.123-08:00"));
    testing.assertEqual(digits("0042"), 42);
}

func testDurations() {
    testing.assertTrue(isDuration("P1Y2M3DT4H5M6S"));
    testing.assertTrue(isDuration("P4W"));
    testing.assertFalse(isDuration("PT"));
}

func testEmailParts() {
    testing.assertTrue(isEmail("joe.bloggs@example.com"));
    testing.assertTrue(isLocalPart('"a b"'));
    testing.assertFalse(isLocalPart("a..b"));
    testing.assertTrue(isMailDomain("[IPv6:::1]"));
    testing.assertFalse(isMailDomain("[1.2.3]"));
}

func testHostsAndAddresses() {
    testing.assertTrue(isHostname("www.example.com"));
    testing.assertFalse(isHostname("ab--c.example"));
    testing.assertTrue(isIPv4("192.168.0.1"));
    testing.assertFalse(isIPv4("01.2.3.4"));
    testing.assertTrue(isIPv6("::ffff:192.168.0.1"));
    testing.assertFalse(isIPv6("1::2::3"));
    testing.assertEqual(ipv6Groups("1:2:3.4.5.6"), 4);
    testing.assertEqual(ipv6Groups("1:zz"), -1);
}

func testUris() {
    testing.assertTrue(isUri("https://user@[::1]:8080/a?b#c", true));
    testing.assertFalse(isUri("relative/path", true));
    testing.assertTrue(isUri("relative/path", false));
    testing.assertFalse(isUri("https://a b", true));
    testing.assertTrue(isAuthority("user@host:80"));
    testing.assertFalse(isAuthority("a@b@c"));
    testing.assertFalse(isUri("http://[::1]/[::1]", true));
    testing.assertFalse(isIPv6("1.2.3.4::1"));
    testing.assertTrue(isIPv6("::ffff:1.2.3.4"));
}

func testPointersUuidsAndRegexes() {
    testing.assertTrue(isUuid("2EB8AA08-AA98-11EA-B4AA-73B441D16380"));
    testing.assertFalse(isUuid("2eb8aa08-aa98-11ea-b4aa-73b441d1638"));
    testing.assertTrue(isJsonPointer("/a~1b/0"));
    testing.assertFalse(isJsonPointer("/a~2"));
    testing.assertTrue(isRelativeJsonPointer("1/a"));
    testing.assertTrue(isRelativeJsonPointer("0#"));
    testing.assertTrue(isRegex("^[a-z]+$"));
    testing.assertFalse(isRegex("(unclosed"));
}
