import 'package:at_client/src/enroll/authorised_namespaces.dart';
import 'package:test/test.dart';

/// The expectations here are the atServer's: it reads a key's namespace as its
/// last dot segment and resolves that first, so the client's prediction of a
/// write must do the same or it skips writes the atServer accepts and tries
/// ones it refuses.
void main() {
  group('accessIn', () {
    test('a grant on the last segment wins over a narrower one', () {
      expect(accessIn({'app.wavi': 'r', 'wavi': 'rw'}, 'app.wavi'), 'rw',
          reason: 'the atServer resolves app.wavi by wavi, where this grant '
              'holds rw, so it accepts a write there');
      expect(accessIn({'app.wavi': 'rw', 'wavi': 'r'}, 'app.wavi'), 'r',
          reason: 'and refuses one when wavi is read-only, whatever the '
              'narrower grant says');
    });

    test('does not depend on the order of the grants', () {
      for (final (onWavi, onAppWavi) in [('rw', 'r'), ('r', 'rw')]) {
        expect(accessIn({'app.wavi': onAppWavi, 'wavi': onWavi}, 'app.wavi'),
            onWavi);
        expect(accessIn({'wavi': onWavi, 'app.wavi': onAppWavi}, 'app.wavi'),
            onWavi);
      }
    });

    test('takes the last segment of a deeper namespace too', () {
      expect(accessIn({'b.c': 'rw', 'c': 'r'}, 'a.b.c'), 'r');
      expect(accessIn({'b.c': 'rw'}, 'a.b.c'), 'rw',
          reason: 'with no grant on the last segment, a grant on a namespace '
              'above it covers it');
    });

    test('a narrower grant applies when the last segment has none', () {
      expect(accessIn({'app.wavi': 'r', '*': 'rw'}, 'app.wavi'), 'r',
          reason: '* answers only for a namespace no grant covers');
    });

    test('* answers for a namespace nothing else covers', () {
      expect(accessIn({'buzz': 'r', '*': 'rw'}, 'wavi'), 'rw');
      expect(accessIn({'buzz': 'r'}, 'wavi'), isNull);
    });

    test('a grant matches whole segments only', () {
      expect(accessIn({'avi': 'rw'}, 'app.wavi'), isNull,
          reason: 'avi is a suffix of wavi but not a namespace above it');
    });
  });

  group('mayWriteIn', () {
    test('follows the access accessIn resolves', () {
      expect(mayWriteIn({'app.wavi': 'r', 'wavi': 'rw'}, 'app.wavi'), isTrue);
      expect(mayWriteIn({'app.wavi': 'rw', 'wavi': 'r'}, 'app.wavi'), isFalse);
    });

    test('a client with no recorded grants may write anywhere', () {
      expect(mayWriteIn(null, 'app.wavi'), isTrue);
    });
  });
}
