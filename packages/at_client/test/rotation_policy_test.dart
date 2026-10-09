import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The rotation policies the SDK ships, and which of them an application
/// inherits by saying nothing.
void main() {
  const destination = '@alice';
  const namespace = 'app_1.my_apps';

  CkRotationContext ckAged(Duration age) => CkRotationContext(
        destination: destination,
        namespace: namespace,
        ckKid: 'a1b2c3d4e5f60718',
        cutAt: DateTime.utc(2026, 1, 1),
        now: DateTime.utc(2026, 1, 1).add(age),
      );

  NskeyRotationContext nskeyAged(Duration age) => NskeyRotationContext(
        namespace: namespace,
        nskeyKid: '02f6b4312bd6c18b',
        createdAt: DateTime.utc(2026, 1, 1),
        now: DateTime.utc(2026, 1, 1).add(age),
      );

  group('the content key default', () {
    test('a key younger than a year is left alone', () {
      expect(rotateCkAfterOneYear(ckAged(Duration.zero)), isFalse);
      expect(rotateCkAfterOneYear(ckAged(const Duration(days: 364, hours: 23))),
          isFalse,
          reason: 'an hour short is still short — the boundary is a year, not '
              '"about a year"');
    });

    test('a key a year old or older is replaced', () {
      expect(rotateCkAfterOneYear(ckAged(const Duration(days: 365))), isTrue,
          reason: 'inclusive: a key that has reached the period is due, or a '
              'policy stated as "a year" fires a write later than it says');
      expect(rotateCkAfterOneYear(ckAged(const Duration(days: 4000))), isTrue);
    });

    test('the period is 365 days, pinned as a literal', () {
      // NOTE: the 365 is a literal on purpose — sharing the constant the
      // policy reads would move both together and assert nothing.
      expect(
          rotateCkAfterOneYear(ckAged(
              const Duration(days: 365) - const Duration(microseconds: 1))),
          isFalse);
      expect(rotateCkAfterOneYear(ckAged(const Duration(days: 365))), isTrue);
    });

    test('age is measured against the now it is given, not the clock', () {
      final ctx = CkRotationContext(
        destination: destination,
        namespace: namespace,
        ckKid: 'a1b2c3d4e5f60718',
        cutAt: DateTime.utc(2020),
        now: DateTime.utc(2020, 1, 2),
      );
      expect(ctx.age, const Duration(days: 1));
      expect(rotateCkAfterOneYear(ctx), isFalse,
          reason: 'six years ago by the wall clock, one day old by the two '
              'dates it was handed');
    });
  });

  group('the namespace key default', () {
    test('a generation younger than a year is left alone', () {
      expect(rotateNskeyAfterOneYear(nskeyAged(Duration.zero)), isFalse);
      expect(
          rotateNskeyAfterOneYear(
              nskeyAged(const Duration(days: 364, hours: 23))),
          isFalse);
    });

    test('the period is 365 days from the advertised mint, pinned as a literal',
        () {
      expect(
          rotateNskeyAfterOneYear(nskeyAged(
              const Duration(days: 365) - const Duration(microseconds: 1))),
          isFalse);
      expect(
          rotateNskeyAfterOneYear(nskeyAged(const Duration(days: 365))), isTrue,
          reason: 'inclusive, as the content key default is');
      expect(rotateNskeyAfterOneYear(nskeyAged(const Duration(days: 3650))),
          isTrue);
    });
  });

  group('what an application that says nothing inherits', () {
    final ring = InMemoryNskeyKeyRing();

    test('every config the SDK builds carries the yearly defaults', () {
      final configs = {
        'CryptoConfig()':
            const CryptoConfig(defaultProviderId: legacyCryptoProviderId),
        'CryptoConfig.nskey': CryptoConfig.nskey(keyRing: ring),
        'CryptoConfig.readsNskeyWritesLegacy':
            CryptoConfig.readsNskeyWritesLegacy(keyRing: ring),
      };
      for (final MapEntry(key: name, value: config) in configs.entries) {
        expect(config.ckRotationPolicy, same(rotateCkAfterOneYear),
            reason: name);
        expect(config.nskeyRotationPolicy, same(rotateNskeyAfterOneYear),
            reason: name);
      }
    });

    test('the content-key manager a config builds asks the same policy', () {
      expect(CryptoConfig.nskey(keyRing: ring).ckManager!.ckRotationPolicy,
          same(rotateCkAfterOneYear),
          reason: 'the era default is built through CryptoConfig.nskey, and '
              'the manager is what asks on the write path');
    });
  });

  group('the alternatives an application can choose', () {
    test('rotateCkAfterOneWeek replaces a key once it is SEVEN days old', () {
      expect(
          rotateCkAfterOneWeek(ckAged(
              const Duration(days: 7) - const Duration(microseconds: 1))),
          isFalse);
      expect(rotateCkAfterOneWeek(ckAged(const Duration(days: 7))), isTrue);
    });

    test('neverRotateNskey says no at any age', () {
      expect(neverRotateNskey(nskeyAged(Duration.zero)), isFalse);
      expect(neverRotateNskey(nskeyAged(const Duration(days: 3650))), isFalse);
    });
  });
}
