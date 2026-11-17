import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

// ignore: unused_element
RegistrarAdminService _viaAtAuth({
  required String registrarUrl,
  required String superApiKey,
}) =>
    RegistrarAdminService(
      registrarUrl: registrarUrl,
      superApiKey: superApiKey,
    );

// ignore: unused_element
RegisteredAtsign? _registeredAtsignType(RegisteredAtsign value) => value;

// ignore: unused_element
DeleteTokenResult? _deleteTokenResultType(DeleteTokenResult value) => value;

// ignore: unused_element
DeleteAtSignsResult? _deleteAtSignsResultType(DeleteAtSignsResult value) =>
    value;

void main() {
  test('package:at_auth/at_auth.dart exports the 4.0.0 registrar admin surface',
      () {
    expect(_viaAtAuth, isNotNull);
  });
}
