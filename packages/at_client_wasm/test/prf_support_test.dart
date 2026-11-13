import 'package:at_client_wasm/src/keys/prf_support.dart';
import 'package:test/test.dart';

import 'passkey_record_keys_test.dart' show FakePrfEnvironment;

void main() {
  late FakePrfEnvironment env;
  late PrfSupport support;

  setUp(() {
    env = FakePrfEnvironment();
    support = PrfSupport(env);
  });

  group('with the client capabilities API', () {
    test('extension:prf true is supported', () async {
      env.capability = true;
      expect(await support.supported(), isTrue);
    });

    test('extension:prf false is unsupported and require refuses', () async {
      env.capability = false;
      expect(await support.supported(), isFalse);
      await expectLater(
          support.require(),
          throwsA(isA<PrfUnavailableException>().having(
              (e) => e.message, 'message', contains('supported browser'))));
    });

    test('the capability answer wins over a recorded miss', () async {
      env.capability = true;
      env.missAt = env.clock;
      expect(await support.supported(), isTrue);
    });
  });

  group('without the client capabilities API', () {
    test('no recorded miss is supported', () async {
      expect(await support.supported(), isTrue);
      await support.require();
    });

    test('a recorded miss makes it unsupported', () async {
      support.recordMiss();
      expect(env.missAt, env.clock);
      expect(await support.supported(), isFalse);
      await expectLater(
          support.require(), throwsA(isA<PrfUnavailableException>()));
    });

    test('the miss is honoured just under 30 days', () async {
      support.recordMiss();
      env.clock =
          env.clock.add(const Duration(days: 30) - const Duration(seconds: 1));
      expect(await support.supported(), isFalse);
    });

    test('the miss is ignored from 30 days on', () async {
      support.recordMiss();
      env.clock = env.clock.add(const Duration(days: 30));
      expect(await support.supported(), isTrue);
    });

    test('a miss dated in the future is ignored', () async {
      env.missAt = env.clock.add(const Duration(days: 1));
      expect(await support.supported(), isTrue);
    });
  });
}
