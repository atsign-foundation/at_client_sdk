import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:test/test.dart';

void main() {
  test('the atSign\'s own credential is no id, an empty id, or primary', () {
    expect(isAtSignCredential(null), isTrue);
    expect(isAtSignCredential(''), isTrue);
    // A raw literal: the name at_auth derives for a keyfile that predates
    // enrollments, and the one the verb builder keeps off the wire.
    expect(isAtSignCredential('primary'), isTrue);
  });

  test('an APKAM enrollment is not', () {
    expect(isAtSignCredential('a1b2c3'), isFalse);
    expect(isAtSignCredential('Primary'), isFalse);
  });
}
