import 'package:at_auth/at_registrar.dart';
import 'package:test/test.dart';

void main() {
  test(
      'package:at_auth/at_registrar.dart exports RegistrarAdminService and its exceptions',
      () {
    expect(
      <Type>[
        RegistrarAdminService,
        RegistrarException,
        RegistrarFailure,
      ],
      hasLength(3),
    );
  });
}
