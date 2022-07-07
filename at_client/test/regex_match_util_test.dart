import 'package:at_client/src/util/regex_match_util.dart';
import 'package:test/test.dart';

void main() {
  group('A group of regex match tests', () {
    test('test regex match - wild card', () async {
      final testKey = '@alice:phone.wavi@bob';
      final regex = '.*';
      expect(hasRegexMatch(testKey, regex), true);
    });
    test('test regex match - compound', () async {
      final testKey = '@alice:phone.wavi@bob';
      final regex = '.*phone.*';
      expect(hasRegexMatch(testKey, regex), true);
    });
    test('test regex match - exact - backward compatibility', () async {
      final testKey = '@alice:phone.wavi@bob';
      final regex = 'phone';
      expect(hasRegexMatch(testKey, regex), true);
    });
    test('test regex match - exact with namespace - backward compatibility',
        () async {
      final testKey = '@alice:phone.wavi@bob';
      final regex = 'phone.wavi';
      expect(hasRegexMatch(testKey, regex), true);
    });
  });
}
