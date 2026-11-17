@TestOn('browser')
library;

import 'package:at_auth/passkey.dart';
import 'package:at_client_wasm/src/keys/web_prf_environment.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

const _missKey = 'at_client_wasm:prf-miss-at';

/// The page environment with the capability probe pinned to "unknown" and the
/// clock set by the test.
class _PinnedEnvironment extends WebPrfEnvironment {
  _PinnedEnvironment(this.clock);

  DateTime clock;

  @override
  Future<bool?> clientCapabilityPrf() async => null;

  @override
  DateTime now() => clock;
}

void main() {
  final start = DateTime.utc(2026, 11, 16, 12);

  setUp(() => window.localStorage.removeItem(_missKey));
  tearDown(() => window.localStorage.removeItem(_missKey));

  test('a recorded miss is read back from local storage', () {
    final env = WebPrfEnvironment();
    expect(env.missRecordedAt(), isNull);
    env.recordMiss(start);
    expect(env.missRecordedAt(), start);
    expect(window.localStorage.getItem(_missKey),
        start.millisecondsSinceEpoch.toString());
    expect(WebPrfEnvironment().missRecordedAt(), start);
  });

  test('a cleared miss reads as none', () {
    final env = WebPrfEnvironment();
    env.recordMiss(start);
    env.clearMiss();
    expect(env.missRecordedAt(), isNull);
    expect(window.localStorage.getItem(_missKey), isNull);
  });

  test('an unreadable stored value reads as no miss', () {
    window.localStorage.setItem(_missKey, 'not a number');
    expect(WebPrfEnvironment().missRecordedAt(), isNull);
  });

  test('the clock reads UTC', () {
    expect(WebPrfEnvironment().now().isUtc, isTrue);
  });

  group('PrfSupport over the page environment', () {
    test('supports PRF while no miss is recorded', () async {
      expect(await PrfSupport(_PinnedEnvironment(start)).supported(), isTrue);
    });

    test('records a miss stamped with the environment clock', () {
      PrfSupport(_PinnedEnvironment(start)).recordMiss();
      expect(WebPrfEnvironment().missRecordedAt(), start);
    });

    test('a recorded miss counts until the TTL passes on the clock', () async {
      final env = _PinnedEnvironment(start);
      final support = PrfSupport(env)..recordMiss();

      env.clock = start.add(prfMissTtl - const Duration(seconds: 1));
      expect(await support.supported(), isFalse);
      await expectLater(
          support.require(), throwsA(isA<PrfUnavailableException>()));

      env.clock = start.add(prfMissTtl);
      expect(await support.supported(), isTrue);
    });

    test('trying again clears the miss', () async {
      final support = PrfSupport(_PinnedEnvironment(start))..recordMiss();
      expect(await support.supported(), isFalse);
      support.tryAgain();
      expect(await support.supported(), isTrue);
      expect(WebPrfEnvironment().missRecordedAt(), isNull);
    });
  });
}
