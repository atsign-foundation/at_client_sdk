import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:test/test.dart';

void main() {
  test('the atSign\'s own credential is no id, an empty id, or primary', () {
    expect(isAtSignCredential(null), isTrue);
    expect(isAtSignCredential(''), isTrue);
    // NOTE: a frozen raw literal — the credential name derived for a keyfile
    // that carries no enrollment.
    expect(isAtSignCredential('primary'), isTrue);
  });

  test('an APKAM enrollment is not', () {
    expect(isAtSignCredential('a1b2c3'), isFalse);
    expect(isAtSignCredential('Primary'), isFalse);
  });
}
