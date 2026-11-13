import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/passkey_creation_options.dart';
import 'package:test/test.dart';

Map<String, Object?> _options(String atSign) => passkeyCreationOptions(
    rpId: 'example.com', rpName: 'Example', atSign: atSign);

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

  test('the atSign appears only in user.name and displayName', () {
    final options = _options('@alice');
    final user = _user(options);
    expect(user['name'], '@alice');
    expect(user['displayName'], '@alice');
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
}
