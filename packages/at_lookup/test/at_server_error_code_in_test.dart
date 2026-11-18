import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_lookup/error_reply_forms.feature
///
/// Reading the code out of an atServer's `error:` reply.
void main() {
  const prefix = 'Failed connecting to @alice. ';

  group('Given a reply in a form an atServer writes', () {
    final readable = {
      'the plain form': 'error:AT0027-Exception: revoked',
      'the colon form': 'error:AT0027:enrollment_id: e-1 is revoked',
      'the bare code': 'error:AT0027',
      'the JSON form':
          'error:{"errorCode":"AT0027","errorDescription":"revoked"}',
      'the JSON form, with a description naming a second error:':
          'error:{"errorCode":"AT0027","errorDescription":"was error:AT0401"}',
    };
    readable.forEach((form, reply) {
      test('when it is in $form, then its code is read', () {
        expect(atServerErrorCodeIn('$prefix$reply'), 'AT0027');
      });
    });
  });

  group('Given a JSON reply followed by other text', () {
    test('when it is read, then the code of the JSON is read', () {
      expect(
          atServerErrorCodeIn(
              '${prefix}error:{"errorCode":"AT0401","errorDescription":"x"} '
              'trailing'),
          'AT0401');
    });

    test(
        'when the JSON is cut short, then a code leading it is read, and one '
        'in its description is not', () {
      expect(atServerErrorCodeIn('${prefix}error:{"errorCode":"AT0027"'),
          'AT0027');
      expect(atServerErrorCodeIn('${prefix}error:{ "errorCode" : "AT0027",'),
          'AT0027');
      expect(
          atServerErrorCodeIn(
              '${prefix}error:{"errorDescription":"AT0401","errorCode":'),
          isNull);
    });
  });

  group('Given a reply whose code cannot be read', () {
    final unreadable = {
      'a message with no error: in it': 'data:refused',
      'a code followed by a digit': 'error:AT00271-x',
      'a JSON body that is not an object': 'error:["AT0027"]',
      'a JSON code that is a number': 'error:{"errorCode":27}',
      'a JSON code that is a list': 'error:{"errorCode":["AT0027"]}',
      'a JSON body with no code, naming one in its description':
          'error:{"errorDescription":"AT0401 refused"}',
      'a JSON body with a number for a code, naming one in its description':
          'error:{"errorCode":27,"errorDescription":"AT0401"}',
      'a code that does not lead the reply':
          'error:Exception: AT0027 enrollment revoked',
    };
    unreadable.forEach((what, reply) {
      test('when it is $what, then it reads as no code', () {
        expect(atServerErrorCodeIn('$prefix$reply'), isNull);
      });
    });
  });
}
