import 'dart:io';

import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  test('every passkey exception is an AtException', () {
    expect(PasskeyCeremonyException('x'), isA<AtException>());
    expect(PrfUnavailableException('x'), isA<AtException>());
    expect(UnsupportedPasskeyRecordException('x'), isA<AtException>());
    expect(PasskeyRecordAuthenticationException(), isA<AtException>());
  });

  test(
      'passkey sources declare no abstract interface class and no bare '
      'Exception supertype', () {
    final sources = Directory('lib/src/passkey')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(sources, isNotEmpty);
    for (final file in sources) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('abstract interface class')),
          reason: file.path);
      expect(text, isNot(contains('implements Exception')), reason: file.path);
    }
  });
}
