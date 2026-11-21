import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

/// `AtKeysFormatException.badField`, for a document that parsed as a JSON
/// object, or as data of another kind, of the wrong shape.
void main() {
  group('Given a JSON object whose field is not what it must be', () {
    test(
        'when badField reports it, then its message and reason name the '
        'field and what it must be, isJson is true and position is null', () {
      final error = AtKeysFormatException.badField(
          'the keychain atKeys entry header',
          'segmentCount',
          'a whole number from 0 to 9');

      expect(
          error,
          isA<AtKeysFormatException>()
              .having(
                  (e) => e.message,
                  'message',
                  'the keychain atKeys entry header is a JSON object whose '
                      'segmentCount is not a whole number from 0 to 9')
              .having(
                  (e) => e.reason,
                  'reason',
                  'a JSON object whose segmentCount is not a whole number '
                      'from 0 to 9')
              .having((e) => e.isJson, 'isJson', isTrue)
              .having((e) => e.position, 'position', isNull)
              .having((e) => e.offset, 'offset', isNull)
              .having((e) => e.source, 'source', isNull));
      expect(
          '$error',
          'AtKeysFormatException: the keychain atKeys entry header is a JSON '
              'object whose segmentCount is not a whole number from 0 to 9');
    });
  });

  group('Given data of another kind whose field is not what it must be', () {
    test(
        'when badField reports it with that kind, then its message and '
        'reason name the kind in place of a JSON object', () {
      final error = AtKeysFormatException.badField(
          'the keychain atKeys entry header',
          'segmentCount',
          'a whole number from 0 to 9',
          kind: 'a legacy segment header');

      expect(
          error,
          isA<AtKeysFormatException>()
              .having(
                  (e) => e.message,
                  'message',
                  'the keychain atKeys entry header is a legacy segment '
                      'header whose segmentCount is not a whole number from '
                      '0 to 9')
              .having(
                  (e) => e.reason,
                  'reason',
                  'a legacy segment header whose segmentCount is not a '
                      'whole number from 0 to 9')
              .having((e) => e.isJson, 'isJson', isTrue)
              .having((e) => e.position, 'position', isNull));
    });
  });
}
