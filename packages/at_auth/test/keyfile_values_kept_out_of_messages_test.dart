import 'dart:convert';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
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

  Map<String, dynamic> material({String createdAt = '2026-01-01T00:00:00Z'}) =>
      {
        'role': 'publicEncryption',
        'algorithm': 'rsa2048',
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
}
