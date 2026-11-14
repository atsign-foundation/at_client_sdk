import 'dart:convert';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/holds_none_of.dart';

/// Reading an atKeys document whose field does not parse, or repeats.
///
/// Catalogue: features/at_auth/keyfile_values_kept_out_of_messages.feature
void main() {
  final random = Random.secure();

  /// A value no message could hold by chance.
  String distinctive() =>
      base64Url.encode(List.generate(33, (_) => random.nextInt(256)));

  Map<String, dynamic> material(
          {String createdAt = '2026-01-01T00:00:00Z',
          String role = 'publicEncryption',
          String algorithm = 'rsa2048'}) =>
      {
        'role': role,
        'algorithm': algorithm,
        'bytes': base64Encode(utf8.encode('public')),
        'createdAt': createdAt,
      };

  Map<String, dynamic> document(List<Map<String, dynamic>> atsignKeys) => {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'atsignKeys': atsignKeys,
      };

  Object errorReading(Map<String, dynamic> json) {
    try {
      AtKeys.fromJson(json);
    } catch (e) {
      return e;
    }
    fail('the document parsed');
  }

  test('A date field that does not parse names the field and none of its value',
      () {
    final value = distinctive();
    late final FormatException parserError;
    try {
      DateTime.parse(value);
      fail('the value parsed as a date');
    } on FormatException catch (e) {
      parserError = e;
    }

    final error = errorReading(document([
      {
        'keyId': 'k1',
        'material': [material(createdAt: value)],
      },
    ]));

    expect('$error', holdsNoneOf(value),
        reason: 'the error holds none of the field\'s value');
    expect(error, isA<AtKeysParseException>());
    final message = (error as AtKeysParseException).message;
    expect(message, holdsNoneOf(value),
        reason: 'the message holds none of the field\'s value');
    expect(message, contains('createdAt'), reason: 'it names the field');
    expect(message, contains(parserError.message),
        reason: 'it gives the parser\'s reason');
  });

  test('A repeated keyId says a keyId repeats, holding none of it', () {
    final keyId = distinctive();

    final error = errorReading(document([
      {
        'keyId': keyId,
        'material': [material()],
      },
      {
        'keyId': keyId,
        'material': [material()],
      },
    ]));

    expect('$error', holdsNoneOf(keyId),
        reason: 'the error holds none of the keyId');
    expect(error, isA<AtKeysValidationException>());
    final message = (error as AtKeysValidationException).message;
    expect(message, holdsNoneOf(keyId),
        reason: 'the message holds none of the keyId');
    expect(message, contains('Duplicate atKeys keyId'),
        reason: 'it says a keyId repeats');
  });

  group('No other parse message quotes a stored value', () {
    test('a role that repeats under one keyId', () {
      final role = 'role${distinctive()}';
      final keyId = distinctive();

      final error = errorReading(document([
        {
          'keyId': keyId,
          'material': [material(role: role), material(role: role)],
        },
      ]));

      expect(error, isA<AtKeysValidationException>());
      final message = (error as AtKeysValidationException).message;
      expect(message, allOf(holdsNoneOf(role), holdsNoneOf(keyId)));
      expect(message, 'Duplicate role at atsignKeys[0].material[1].role');
    });

    test('a value an enumeration does not hold', () {
      final value = distinctive();

      expect(
          () => const AtKeysAssurance()
              .expectEnum(value, EnrollmentKeyExchangeMode.values, 'mode'),
          throwsA(isA<AtKeysValidationException>()
              .having((e) => e.message, 'message', 'Unsupported value at mode')
              .having((e) => e, 'text', holdsNoneOf(value))));
    });

    test('two active materials of one role and algorithm in an enrollment', () {
      final enrollmentId = distinctive();
      final role = 'role${distinctive()}';
      final algorithm = 'algo${distinctive()}';
      CryptographicMaterial active(String keyId) => CryptographicMaterial(
          keyId: keyId,
          enrollmentId: enrollmentId,
          role: CryptographicMaterialRole.of(role),
          algorithm: CryptographicMaterialAlgorithm.of(algorithm),
          bytes: AtBytes.fromString(base64Encode(utf8.encode('x'))),
          createdAt: DateTime.utc(2026));

      expect(
          () => const AtKeysAssurance()
              .validateKeyMaterials([active('k1'), active('k2')]),
          throwsA(isA<AtKeysEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(holdsNoneOf(enrollmentId), holdsNoneOf(role),
                  holdsNoneOf(algorithm)))));
    });

    test('a namespace whose value is not a string', () {
      final namespace = distinctive();

      final error = errorReading({
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'enrollments': [
          {
            'enrollmentId': 'e-1',
            'namespaces': {namespace: 5},
            'keys': <Object>[],
          },
        ],
      });

      expect(error, isA<AtKeysParseException>());
      final message = (error as AtKeysParseException).message;
      expect(message, holdsNoneOf(namespace));
      expect(message, contains('enrollments[0].namespaces[0]'),
          reason: 'it names the namespace by its position');
    });

    test('an algorithm this build cannot sign with', () {
      final algorithm = 'algo${distinctive()}';
      final enrollmentId = distinctive();
      final keys = AtKeys(atsign: '@alice'.toAtsign())
        ..fileApkamMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.of(algorithm),
            publicKey: base64Encode(utf8.encode('public')),
            privateKey: base64Encode(utf8.encode('private')));

      expect(
          () => keys.authenticationKeyPairFor(enrollmentId),
          throwsA(isA<AtKeyNotFoundException>().having(
              (e) => e.message,
              'message',
              allOf(holdsNoneOf(algorithm), holdsNoneOf(enrollmentId)))));
    });
  });
}
