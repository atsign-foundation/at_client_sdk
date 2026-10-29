import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';

void main() {
  late MockSecureSocketFactory socketFactory;
  late SecondaryUrlFinder finder;

  setUp(() {
    socketFactory = MockSecureSocketFactory();
    finder =
        SecondaryUrlFinder('root.example', 64, socketFactory: socketFactory);
  });

  for (final atSign in ['@al\nice', '@alice\n', '\n@alice', '@alice\n@exit']) {
    test(
        'an atSign holding a line feed is refused before the atDirectory is '
        'contacted: ${atSign.replaceAll('\n', r'\n')}', () async {
      await expectLater(finder.findSecondaryUrl(atSign),
          throwsA(isA<IllegalArgumentException>()));
      verifyZeroInteractions(socketFactory);
    });
  }
}
