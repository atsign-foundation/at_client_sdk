import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

/// A parse refusal names the field the user's file actually has. The message
/// quotes no values, so the path is the only pointer to the bad entry.
void main() {
  Map<String, dynamic> part() => {
        'role': CryptographicMaterialRole.privateAuthentication,
        'algorithm': CryptographicMaterialAlgorithm.rsa2048,
        'createdAt': '2026-08-14T00:00:00.000Z',
        'bytes': 'dmFsdWU=',
      };

  test('a non-object material part is reported with its entry index', () {
    final document = {
      'version': AtKeys.supportedVersion,
      'atsign': '@alice',
      'enrollments': [
        {
          'enrollmentId': 'e1',
          'keys': [
            {
              'keyId': 'k1',
              'material': [part()],
            },
            {
              'keyId': 'k2',
              'material': ['not an object'],
            },
          ],
        },
      ],
    };

    expect(
        () => AtKeys.fromJson(document),
        throwsA(isA<AtKeysParseException>().having((e) => e.message, 'message',
            contains('enrollments[0].keys[1].material[0]'))));
  });
}
