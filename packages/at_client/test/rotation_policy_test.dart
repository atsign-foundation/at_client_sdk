import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The two policies the SDK ships, and the shape every application-supplied one
/// is written against.
///
/// Both are pinned as **values**, not as behaviour observed through a manager:
/// they are what an application inherits by saying nothing, so a change to
/// either is a change to what every deployment does, and it should have to be
/// made here.
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

  group('the content key default', () {
    test('a key younger than a week is left alone', () {
      expect(rotateCkAfterOneWeek(ckAged(Duration.zero)), isFalse);
      expect(rotateCkAfterOneWeek(ckAged(const Duration(days: 6, hours: 23))),
          isFalse,
          reason: 'an hour short is still short — the boundary is a week, not '
              '"about a week"');
    });

    test('a key a week old or older is replaced', () {
      expect(rotateCkAfterOneWeek(ckAged(const Duration(days: 7))), isTrue,
          reason: 'inclusive: a key that has reached the period is due, or a '
              'policy stated as "a week" fires a write later than it says');
      expect(rotateCkAfterOneWeek(ckAged(const Duration(days: 400))), isTrue);
    });

    test('the period is SEVEN days, pinned as a literal', () {
      // Not derived from a constant the policy also reads: the two would move
      // together and the assertion would say nothing. Every replacement writes
      // a conveyance record that is then retained, so this number decides how
      // fast records accumulate for every deployment that says nothing.
      expect(
          rotateCkAfterOneWeek(ckAged(
              const Duration(days: 7) - const Duration(microseconds: 1))),
          isFalse);
      expect(rotateCkAfterOneWeek(ckAged(const Duration(days: 7))), isTrue);
    });

    test('age is measured against the now it is given, not the clock', () {
      // A policy that read DateTime.now() would answer differently every run,
      // and an application could not test its own.
      final ctx = CkRotationContext(
        destination: destination,
        namespace: namespace,
        ckKid: 'a1b2c3d4e5f60718',
        cutAt: DateTime.utc(2020),
        now: DateTime.utc(2020, 1, 2),
      );
      expect(ctx.age, const Duration(days: 1));
      expect(rotateCkAfterOneWeek(ctx), isFalse,
          reason: 'six years ago by the wall clock, one day old by the two '
              'dates it was handed');
    });
  });

  group('the namespace key default', () {
    test('never, at any age', () {
      NskeyRotationContext aged(Duration age) => NskeyRotationContext(
            namespace: namespace,
            nskeyKid: '02f6b4312bd6c18b',
            createdAt: DateTime.utc(2026, 1, 1),
            now: DateTime.utc(2026, 1, 1).add(age),
          );

      expect(neverRotateNskey(aged(Duration.zero)), isFalse);
      expect(neverRotateNskey(aged(const Duration(days: 3650))), isFalse,
          reason: 'ten years and still no. Replacing a namespace key costs a '
              'conveyance to every authorised enrollment and makes every peer '
              'cut a fresh content key, so nothing in the SDK asks for one on '
              'its own — it fires on a cause, and an application deciding it '
              'is time is the cause');
    });

    test('it is a policy rather than an absent one', () {
      // A null would put a check at every call site, and a call site that
      // forgot it would silently never ask.
      const NskeyRotationPolicy configured = neverRotateNskey;
      expect(configured, isNotNull);
    });
  });
}
