import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// What a ring does when it needs an own namespace-key private it does not
/// hold: it fetches the conveyance records addressed to this enrollment, and
/// asks the other enrollments only if none carried it.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.6
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';

  MockAtClient client() {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    return atClient;
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(alice, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: alice);
  }

  Secret conveyed(String kid) => Secret(
      namespace: namespace,
      name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
      value: base64Encode(
          SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!.newSeed()));

  group('Given an own generation whose private this enrollment does not hold',
      () {
    test(
        'when a conveyance record for it is waiting, then the fetch files it '
        'and nothing is asked', () async {
      final privates = await filing();
      var fetched = 0;
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: privates,
          fetchConveyance: () async {
            fetched++;
            await privates.file(conveyed('kid1'));
          },
          requestConveyance: (ns, name) async => asked.add(name));

      expect(await ring.privateHalf(alice, namespace, 'kid1'), isNotNull,
          reason: 'the record was on the atServer, so a write needs no other '
              'enrollment to be online');
      await pumpEventQueue();
      expect(fetched, 1);
      expect(asked, isEmpty,
          reason: 'asking is for a private nobody has conveyed yet');
    });

    test('when no record is waiting, then it asks and holds nothing', () async {
      var fetched = 0;
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add(name));

      expect(await ring.privateHalf(alice, namespace, 'kid1'), isNull);
      await pumpEventQueue();
      expect(fetched, 1, reason: 'the fetch comes first');
      expect(asked, ['${NskeyPrivateFiling.secretNamePrefix}kid1']);
    });

    test('when two misses come at once, then one fetch serves both', () async {
      final privates = await filing();
      final arrived = Completer<void>();
      var fetched = 0;
      final ring = PublishedNskeyKeyRing(client(), privateFiling: privates,
          fetchConveyance: () async {
        fetched++;
        await arrived.future;
        await privates.file(conveyed('kid1'));
      }, requestConveyance: (ns, name) async {});

      final first = ring.privateHalf(alice, namespace, 'kid1');
      final second = ring.privateHalf(alice, namespace, 'kid1');
      await pumpEventQueue();
      arrived.complete();

      expect(await first, isNotNull);
      expect(await second, isNotNull,
          reason: 'the second miss waits for the fetch in flight rather than '
              'reading before it lands');
      expect(fetched, 1);
    });

    test(
        'when it misses again within askCooldown of an on-miss fetch that '
        'found nothing, then it does not fetch again', () async {
      var fetched = 0;
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async {})
        ..askCooldown = const Duration(minutes: 10);

      expect(await ring.privateHalf(alice, namespace, 'kid1'), isNull);
      expect(await ring.privateHalf(alice, namespace, 'kid1'), isNull);
      expect(fetched, 1);
    });

    test('when the cooldown has passed, then it fetches again', () async {
      // NOTE: the control for the test above: without it a ring that fetched
      // only once ever would pass there.
      var fetched = 0;
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async {})
        ..askCooldown = Duration.zero;

      await ring.privateHalf(alice, namespace, 'kid1');
      await ring.privateHalf(alice, namespace, 'kid1');
      expect(fetched, 2);
    });

    test('when the fetch fails, then it still asks', () async {
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async =>
              throw SecondaryConnectException('the atServer cannot be reached'),
          requestConveyance: (ns, name) async => asked.add(name));

      expect(await ring.privateHalf(alice, namespace, 'kid1'), isNull);
      await pumpEventQueue();
      expect(asked, hasLength(1));
    });
  });
}
