import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// How often a ring asks this atSign's other enrollments for a namespace-key
/// private it does not hold.
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';

  group(
      'Given an own generation whose private this enrollment does not hold, '
      'and asking the other enrollments for it fails', () {
    test(
        'when it reads that generation twice within the ask cooldown, then it '
        'asks once', () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(alice);
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final advertised = NskeyAdvertisement.single(
          publicKey: (await kem.keyPairFromSeed(kem.newSeed())).publicKey,
          alg: SecretSharingAlgos.xWing);
      final kid = advertised.nskeyKid;
      final asked = <String>[];
      final ring =
          PublishedNskeyKeyRing(atClient, requestConveyance: (ns, name) async {
        asked.add(name);
        throw SecondaryConnectException('the atServer cannot be reached');
      })
            ..askCooldown = const Duration(minutes: 10)
            ..rememberOwn(alice, namespace, advertised);

      expect(await ring.privateHalf(alice, namespace, kid), isNull);
      await pumpEventQueue();
      expect(asked, hasLength(1),
          reason: 'the control: the first read asked, and the ask failed');

      expect(await ring.privateHalf(alice, namespace, kid), isNull);
      await pumpEventQueue();

      expect(asked, hasLength(1),
          reason: 'an ask that fails is bounded by the cooldown like one that '
              'went out, or a failing ask repeats on every read');
    });
  });
}
