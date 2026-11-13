import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/passkey_creation_options.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 11, 6, 14, 5);

Map<String, Object?> _options(String atSign,
        {DateTime? at, String device = 'Alice Mac'}) =>
    passkeyCreationOptions(
        rpId: 'example.com',
        rpName: 'Example',
        atSign: atSign,
        enrolledAt: at ?? _at,
        deviceName: device);

String _displayName(DateTime at, String device) =>
    _user(_options('@alice', at: at, device: device))['displayName'] as String;

Map<String, Object?> _user(Map<String, Object?> options) =>
    (options['publicKey'] as Map)['user'] as Map<String, Object?>;

void main() {
  test('user.id is 64 random bytes', () {
    expect((_user(_options('@alice'))['id'] as Uint8List), hasLength(64));
  });

  test('user.id never contains the atSign bytes', () {
    final id = _user(_options('@alice'))['id'] as Uint8List;
    expect(utf8.decode(id, allowMalformed: true), isNot(contains('alice')));
    expect(id, isNot(Uint8List.fromList(utf8.encode('@alice'))));
  });

  test('two calls for the same atSign differ', () {
    expect(_user(_options('@alice'))['id'],
        isNot(_user(_options('@alice'))['id']));
  });

  test('the atSign appears only in user.name', () {
    final options = _options('@alice');
    final user = _user(options);
    expect(user['name'], '@alice');
    expect(user['displayName'], isNot(contains('alice')));
    final rest = {...(options['publicKey'] as Map)}..remove('user');
    expect(jsonEncode(rest, toEncodable: (o) => o.toString()),
        isNot(contains('alice')));
  });

  test('the challenge is 32 random bytes and PRF carries no eval input', () {
    final a = (_options('@alice')['publicKey'] as Map);
    final b = (_options('@alice')['publicKey'] as Map);
    expect(a['challenge'] as Uint8List, hasLength(32));
    expect(a['challenge'], isNot(b['challenge']));
    expect(a['extensions'], {'prf': <String, Object?>{}});
  });

  group('displayName', () {
    test('is the UTC minute, a middle dot and the device name', () {
      expect(
          _displayName(_at, 'Alice Mac'), '2026-11-06 14:05Z \u00b7 Alice Mac');
    });

    test('converts a non-UTC time to UTC and pads fields', () {
      final local = DateTime.parse('2026-01-02T03:04:59+05:30');
      expect(_displayName(local, 'Mac'), '2026-01-01 21:34Z \u00b7 Mac');
    });

    test('keeps a device name that fits 64 bytes whole', () {
      // The prefix is 21 bytes, leaving 43 for the device name.
      final device = 'a' * 43;
      final name = _displayName(_at, device);
      expect(utf8.encode(name), hasLength(64));
      expect(name, endsWith(device));
    });

    test('cuts a long ascii device name to exactly 64 bytes', () {
      final name = _displayName(_at, 'a' * 200);
      expect(utf8.encode(name), hasLength(64));
      expect(name, startsWith('2026-11-06 14:05Z \u00b7 aaaa'));
    });

    test('cuts an emoji device name at a code point', () {
      final name = _displayName(_at, '\u{1F600}' * 30);
      // 43 bytes remain; 4-byte emoji: 10 fit, never a partial one.
      expect(name, '2026-11-06 14:05Z \u00b7 ${'\u{1F600}' * 10}');
      expect(utf8.encode(name), hasLength(61));
    });

    test('cuts a CJK device name at a code point', () {
      final name = _displayName(_at, '\u4e2d' * 30);
      // 43 bytes remain; 3-byte CJK: 14 fit.
      expect(name, '2026-11-06 14:05Z \u00b7 ${'\u4e2d' * 14}');
      expect(utf8.encode(name), hasLength(63));
    });
  });
}
