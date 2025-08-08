// ignore_for_file: unnecessary_string_escapes
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

void main() {
  group('A group of positive atsign tests', () {
    test('atsign in upper case', () {
      var atSign = '@BOB';
      atSign = AtUtils.fixAtSign(atSign);
      expect(atSign, '@bob');
    });

    test('atsign contains .', () {
      var atSign = '@colin.constable';
      atSign = AtUtils.fixAtSign(atSign);
      expect(atSign, '@colinconstable');
    });

    test('@ is prepended when atsign does not start with @', () {
      var atsign = 'randomFlex';
      atsign = AtUtils.fixAtSign(atsign);
      expect(atsign, '@randomflex');
    });
  });
  group('A group of invalid atsign test', () {
    test('empty atsign - InvalidAtSignException', () {
      var atSign = '';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: must include one @ character and at least one character on the right')));
    });

    test('atsign with more @ - InvalidAtSignException', () {
      var atSign = '@bob@alice';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot Contain more than one @ character')));
    });

    test('key with no atsign - InvalidAtSignException', () {
      var atSign = 'phone@';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot Contain more than one @ character')));
    });

    test('white spaces in atsign - InvalidAtSignException', () {
      var atSign = '@b ob';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot Contain whitespace characters')));
    });

    test('reserved characters in atsign : + - InvalidAtSignException', () {
      var atSign = '@\U+237E';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot contain \!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\} characters')));
    });

    test('reserved characters with ascii codes - InvalidAtsignException', () {
      var atSign = '@U${String.fromCharCode(43)}';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot contain \!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\} characters')));
    });

    test('reserved characters with unicode - InvalidAtsignException', () {
      var atSign = '@\u0021';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot contain \!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\} characters')));
    });

    test('special characters in atsign - * InvalidAtSignException', () {
      var atSign = '@b*b';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: Cannot contain \!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\} characters')));
    });

    test('control characters in atsign - InvalidAtSignException', () {
      var atSign = '@\u2400';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: must not include control characters')));
    });

    test('control characters - InvalidAtSignException', () {
      var atSign = '@\u0019';
      expect(
          () => AtUtils.fixAtSign(atSign),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtSignException &&
              e.message ==
                  'invalid @sign: must not include control characters')));
    });

    test('Test to validate when atSign is null', () {
      // ignore: deprecated_member_use_from_same_package
      var atSign = AtUtils.formatAtSign(null);
      expect(atSign, null);
    });
  });
}
