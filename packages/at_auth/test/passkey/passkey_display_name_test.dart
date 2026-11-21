import 'dart:convert';

import 'package:at_auth/passkey.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 11, 6, 14, 5);

/// A time whose own fields read 09:05 on 6 November 2026 and whose UTC
/// conversion is 14:05 that day, as a local time five hours behind UTC reads
/// whatever zone the test runs in.
class _FiveHoursBehindUtc extends Fake implements DateTime {
  @override
  bool get isUtc => false;

  @override
  int get year => 2026;

  @override
  int get month => 11;

  @override
  int get day => 6;

  @override
  int get hour => 9;

  @override
  int get minute => 5;

  @override
  DateTime toUtc() => _at;
}

void main() {
  test('Every platform names a passkey by the same rule', () {
    final enrolledAt = DateTime.parse('2026-11-06T14:05:59Z');
    expect(passkeyDisplayName(enrolledAt, 'Alice Mac'),
        '2026-11-06 14:05Z \u00b7 Alice Mac');
    final cut = passkeyDisplayName(enrolledAt, '\u{1F600}' * 30);
    expect(cut, '2026-11-06 14:05Z \u00b7 ${'\u{1F600}' * 10}');
    expect(utf8.encode(cut).length, lessThanOrEqualTo(64));
  });

  test('the bound is 64 UTF-8 bytes', () {
    expect(passkeyDisplayNameMaxBytes, 64);
  });

  test('formats the UTC fields of a time that is not UTC', () {
    expect(passkeyDisplayName(_FiveHoursBehindUtc(), 'Mac'),
        '2026-11-06 14:05Z \u00b7 Mac');
  });

  test('a local time names the same UTC minute', () {
    expect(passkeyDisplayName(_at.toLocal(), 'Mac'),
        '2026-11-06 14:05Z \u00b7 Mac');
  });

  test('pads every field to its width', () {
    expect(passkeyDisplayName(DateTime.utc(987, 1, 2, 3, 4), 'Mac'),
        '0987-01-02 03:04Z \u00b7 Mac');
  });

  test('keeps a device name that fits 64 bytes whole', () {
    final device = 'a' * 43;
    final name = passkeyDisplayName(_at, device);
    expect(utf8.encode(name), hasLength(64));
    expect(name, endsWith(device));
  });

  test('cuts a long ascii device name to exactly 64 bytes', () {
    final name = passkeyDisplayName(_at, 'a' * 200);
    expect(utf8.encode(name), hasLength(64));
    expect(name, '2026-11-06 14:05Z \u00b7 ${'a' * 43}');
  });

  test('cuts a CJK device name between code points', () {
    final name = passkeyDisplayName(_at, '\u4e2d' * 30);
    expect(name, '2026-11-06 14:05Z \u00b7 ${'\u4e2d' * 14}');
    expect(utf8.encode(name), hasLength(63));
  });
}
