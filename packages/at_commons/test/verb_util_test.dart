import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of positive value formatter tests', () {
    test('newline in value', () {
      var value = 'charlies \n angels';
      value = VerbUtil.replaceNewline(value);
      expect(value, 'charlies ~NL~ angels');
    });

    test('multiple newline in values', () {
      var value = 'charlies \n angels\n angels';
      value = VerbUtil.replaceNewline(value);
      expect(value, 'charlies ~NL~ angels~NL~ angels');
    });
  });

  group('A group of negative value formatter tests', () {
    test('no newline in value', () {
      var value = 'charlies angels';
      value = VerbUtil.replaceNewline(value);
      expect(value, 'charlies angels');
    });
  });
}
