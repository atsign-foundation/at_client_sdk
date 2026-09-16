/// The at-rest field names this package spells for itself, frozen: a file a
/// user already holds is read by them.
library;

import 'package:at_onboarding_cli/src/util/auth_key_type.dart';
import 'package:test/test.dart';

void main() {
  test('the AuthKeyType field names, as raw strings', () {
    // NOTE: a verbatim second declaration of at_auth's auth_constants
    // values — either package's copy moving breaks the other.
    expect(AuthKeyType.aesEncryptedPkamPublicKey, 'aesPkamPublicKey');
    expect(AuthKeyType.aesEncryptedPkamPrivateKey, 'aesPkamPrivateKey');
    expect(AuthKeyType.aesEncryptedEncryptionPublicKey, 'aesEncryptPublicKey');
    expect(
        AuthKeyType.aesEncryptedEncryptionPrivateKey, 'aesEncryptPrivateKey');
    expect(AuthKeyType.selfEncryptionKey, 'selfEncryptionKey');
    expect(AuthKeyType.apkamSymmetricKey, 'apkamSymmetricKey');
  });
}
