import 'dart:typed_data';

import 'package:at_client_web/src/keys/passkey_creation_options.dart';
import 'package:at_client_web/src/keys/passkey_request_options.dart';
import 'package:test/test.dart';

void main() {
  test('creation options carry the ceremony timeout', () {
    final options = passkeyCreationOptions(
        rpId: 'example.com',
        rpName: 'Example',
        atSign: '@alice',
        enrolledAt: DateTime.utc(2026),
        deviceName: 'Mac');
    expect((options['publicKey'] as Map)['timeout'], passkeyCeremonyTimeoutMs);
  });

  test('request options carry the ceremony timeout and inputs', () {
    final id = Uint8List.fromList([1, 2, 3]);
    final salt = Uint8List.fromList([for (var i = 0; i < 32; i++) i + 1]);
    final options = passkeyRequestOptions(
        rpId: 'example.com', evalInput: salt, allowCredential: id);
    final key = options['publicKey'] as Map;
    expect(key['timeout'], passkeyCeremonyTimeoutMs);
    expect(key['rpId'], 'example.com');
    expect((key['allowCredentials'] as List).single['id'], id);
    final prf = (key['extensions'] as Map)['prf'] as Map;
    expect(((prf['eval'] as Map)['first'] as Uint8List), orderedEquals(salt));
  });

  test('the ceremony timeout is two minutes', () {
    expect(passkeyCeremonyTimeoutMs, 120000);
  });

  test('the assertion requires user verification', () {
    final options =
        passkeyRequestOptions(rpId: 'example.com', evalInput: Uint8List(32));
    expect((options['publicKey'] as Map)['userVerification'], 'required');
  });
}
