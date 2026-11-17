import 'package:at_auth/at_registrar.dart';
import 'package:test/test.dart';

// ignore: unused_element
RegistrarAdminService _viaAtRegistrar({
  required String registrarUrl,
  required String superApiKey,
}) =>
    RegistrarAdminService(
      registrarUrl: registrarUrl,
      superApiKey: superApiKey,
    );

// ignore: unused_element
RegistrarException? _registrarExceptionType(RegistrarException value) => value;

// ignore: unused_element
RegistrarFailure? _registrarFailureType(RegistrarFailure value) => value;

void main() {
  test('package:at_auth/at_registrar.dart exports RegistrarException by type',
      () {
    expect(_viaAtRegistrar, isNotNull);
  });
}
