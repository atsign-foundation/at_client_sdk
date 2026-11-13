import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/passkey_creation_options.dart';
import 'package:at_client_wasm/src/keys/passkey_request_options.dart';
import 'package:test/test.dart';

void main() {
  test('creation options carry the ceremony timeout', () {
    final options = passkeyCreationOptions(
        rpId: 'example.com', rpName: 'Example', atSign: '@alice');
    expect((options['publicKey'] as Map)['timeout'], passkeyCeremonyTimeoutMs);
  });

  test('request options carry the ceremony timeout and inputs', () {
    final id = Uint8List.fromList([1, 2, 3]);
    final options = passkeyRequestOptions(
        rpId: 'example.com', evalInput: Uint8List(32), allowCredential: id);
    final key = options['publicKey'] as Map;
    expect(key['timeout'], passkeyCeremonyTimeoutMs);
    expect(key['rpId'], 'example.com');
    expect((key['allowCredentials'] as List).single['id'], id);
  });

  test('the ceremony timeout is two minutes', () {
    expect(passkeyCeremonyTimeoutMs, 120000);
  });
}
