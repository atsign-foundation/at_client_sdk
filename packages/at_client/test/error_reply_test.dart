import 'package:at_client/src/util/error_reply.dart';
import 'package:test/test.dart';

/// Reading the code out of an atServer's `error:` reply.
void main() {
  const prefix = 'Failed connecting to @alice. ';

  group('Given a reply in a form an atServer writes', () {
    final readable = {
      'the plain form': 'error:AT0027-Exception: revoked',
      'the colon form': 'error:AT0027:enrollment_id: e-1 is revoked',
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

  group('Given a reply whose code cannot be read', () {
    final unreadable = {
      'a message with no error: in it': 'data:refused',
      'a JSON body that does not parse': 'error:{"errorCode":"AT0027"',
      'a JSON body that is not an object': 'error:["AT0027"]',
      'a JSON code that is a number': 'error:{"errorCode":27}',
      'a JSON code that is a list': 'error:{"errorCode":["AT0027"]}',
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
