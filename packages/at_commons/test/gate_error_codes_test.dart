import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The codes an atServer's gate refuses with. They cross the wire between
/// atServers and to clients, and a sending atServer treats exactly these three
/// as final, so each is pinned as a literal.
void main() {
  group('Given the gate refusal codes', () {
    test('when each exception is looked up, then it has its code', () {
      expect(error_codes['NotAcceptedException'], 'AT0033');
      expect(error_codes['QuarantineLimitException'], 'AT0034');
      expect(error_codes['QuarantineSizeException'], 'AT0035');
    });

    test('when each code is looked up, then it has its description', () {
      expect(error_description['AT0033'], 'Not accepted');
      expect(error_description['AT0034'], 'Quarantine limit reached');
      expect(error_description['AT0035'], 'Too large for quarantine');
    });

    test('when each code is decoded, then it is its exception with the message',
        () {
      final AtException notAccepted =
          AtExceptionUtils.get('AT0033', 'refused');
      final AtException limit = AtExceptionUtils.get('AT0034', 'full');
      final AtException size = AtExceptionUtils.get('AT0035', 'too big');

      expect(notAccepted, isA<NotAcceptedException>());
      expect(notAccepted.message, 'refused');
      expect(limit, isA<QuarantineLimitException>());
      expect(limit.message, 'full');
      expect(size, isA<QuarantineSizeException>());
      expect(size.message, 'too big');
    });
  });
}
