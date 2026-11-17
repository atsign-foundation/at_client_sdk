import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

void main() {
  test('package:at_auth/at_auth.dart exports the 4.0.0 registrar admin surface',
      () {
    expect(
      <Type>[
        RegistrarAdminService,
        RegisteredAtsign,
        DeleteTokenResult,
        DeleteAtSignsResult,
      ],
      hasLength(4),
    );
  });
}
