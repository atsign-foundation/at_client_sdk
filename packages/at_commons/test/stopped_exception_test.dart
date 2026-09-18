import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  test('a stop is not an AtException, so an ordinary failure catch misses it',
      () {
    Object thrown = StoppedException('the client for @alice has stopped');

    expect(thrown, isNot(isA<AtException>()),
        reason: 'a catch choosing a fallback for an AtException (minting a '
            'fresh key, marking a package unverified) must not take a stop '
            'for one of those failures');
    expect(thrown, isA<Exception>(),
        reason: 'an Exception, not an Error, so a catch-all for recoverable '
            'failures can still let it through deliberately');
  });

  test('it names what stopped', () {
    expect('${StoppedException('the lookup for @alice is closed')}',
        'StoppedException: the lookup for @alice is closed');
  });
}
