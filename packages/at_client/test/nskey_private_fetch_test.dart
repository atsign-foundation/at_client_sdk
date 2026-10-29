import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

/// What a ring does when it needs an own namespace-key private it does not
/// hold: it fetches the conveyance records addressed to this enrollment, and
/// asks the other enrollments only if none carried it.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.6
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';
  final logs = RecordedLogs();

  setUpAll(logs.installOn);

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

  group('Given misses on many own generations no record carries', () {
    final kids = [for (var i = 0; i < 50; i++) 'kid$i'];
    const namespaces = ['ns1.app', 'ns2.app', 'ns3.app'];

    test(
        'when they come at once, then one fetch serves them all and each '
        'namespace is asked once', () async {
      final release = Completer<void>();
      var fetched = 0;
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async {
            fetched++;
            await release.future;
          },
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = const Duration(minutes: 10);

      final misses = [
        for (final (i, kid) in kids.indexed)
          ring.privateHalf(alice, namespaces[i % namespaces.length], kid)
      ];
      await pumpEventQueue();
      release.complete();
      await Future.wait(misses);
      await pumpEventQueue();

      expect(fetched, 1,
          reason: 'every miss shares the one fetch in flight, whatever kid it '
              'names');
      expect(asked.map((a) => a.$1).toSet(), namespaces.toSet());
      expect(asked, hasLength(namespaces.length));
    });

    test(
        'when they come one after another, then the cooldown holds the fetch '
        'and the asks to one each per namespace', () async {
      var fetched = 0;
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = const Duration(minutes: 10);

      for (final kid in kids) {
        expect(await ring.privateHalf(alice, namespaces.first, kid), isNull);
      }
      await pumpEventQueue();

      expect(fetched, 1);
      expect(asked,
          [(namespaces.first, '${NskeyPrivateFiling.secretNamePrefix}kid0')]);
    });

    test(
        'when the cooldown has passed, then the next miss asks again and the '
        'quiet namespaces are forgotten', () async {
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async {},
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = const Duration(milliseconds: 50);

      for (final ns in namespaces) {
        await ring.privateHalf(alice, ns, 'kid1');
      }
      expect(ring.namespacesAskedRecently, namespaces.length,
          reason: 'the control: each namespace was stamped');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await ring.privateHalf(alice, namespaces.first, 'kid2');
      await pumpEventQueue();

      expect(asked, hasLength(namespaces.length + 1));
      expect(ring.namespacesAskedRecently, 1,
          reason: 'stamps past the cooldown are dropped, so what is held is '
              'bounded by the asks one cooldown allows');
    });
  });

  group('Given asks for kids no own advertisement names', () {
    late NskeyAdvertisement advertised;

    setUp(() async {
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      advertised = NskeyAdvertisement.single(
          publicKey: (await kem.keyPairFromSeed(kem.newSeed())).publicKey,
          alg: SecretSharingAlgos.xWing);
    });

    ({PublishedNskeyKeyRing ring, List<(String, String)> asked}) asking(
        {Duration cooldown = const Duration(minutes: 10)}) {
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          fetchConveyance: () async {},
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = cooldown;
      return (ring: ring, asked: asked);
    }

    String secretOf(String kid) => '${NskeyPrivateFiling.secretNamePrefix}$kid';

    test(
        'when one has gone out in a namespace, then a miss of the kid its '
        'advertisement names still asks', () async {
      final a = asking();
      a.ring.rememberOwn(alice, namespace, advertised);

      await a.ring.privateHalf(alice, namespace, 'unnamed1');
      await a.ring.privateHalf(alice, namespace, 'unnamed2');
      await a.ring.privateHalf(alice, namespace, advertised.nskeyKid);
      await pumpEventQueue();

      expect(
          a.asked,
          [
            (namespace, secretOf('unnamed1')),
            (namespace, secretOf(advertised.nskeyKid)),
          ],
          reason: 'the second unnamed kid shares the first one\'s stamp, the '
              'control; the advertised kid has a stamp of its own');
    });

    test(
        'when the ring holds no copy of its own advertisement, then the kid it '
        'would name shares the other kids\' stamp', () async {
      final a = asking();

      await a.ring.privateHalf(alice, namespace, 'unnamed1');
      await a.ring.privateHalf(alice, namespace, advertised.nskeyKid);
      await pumpEventQueue();

      expect(a.asked, [(namespace, secretOf('unnamed1'))],
          reason: 'the copy is never fetched on a miss, so without one the '
              'kid cannot be told apart from any other');
    });

    test(
        'when more than the cap come within a cooldown, then the rest ask '
        'nothing and the first held back is named in a warning', () async {
      final a = asking(cooldown: const Duration(milliseconds: 200));
      const cap = PublishedNskeyKeyRing.maxUnadvertisedAsksPerCooldown;
      final crowded = [for (var i = 0; i < cap + 2; i++) 'ns$i.app'];
      logs.records.clear();

      for (final ns in crowded) {
        await a.ring.privateHalf(alice, ns, 'unnamed');
      }
      a.ring.rememberOwn(alice, 'own.app', advertised);
      await a.ring.privateHalf(alice, 'own.app', advertised.nskeyKid);
      await pumpEventQueue();

      expect(
          a.asked.map((a) => a.$1).toList(),
          [
            ...crowded.take(cap),
            'own.app',
          ],
          reason: 'an ask for an advertised kid is bounded by this atSign\'s '
              'own namespaces, so the cap does not hold it back');
      final warnings =
          logs.at('WARNING').where((m) => m.contains('Not asking')).toList();
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('${crowded[cap]}:unnamed'));

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await a.ring.privateHalf(alice, crowded.last, 'unnamed');
      await pumpEventQueue();
      expect(a.asked.last, (crowded.last, secretOf('unnamed')),
          reason: 'past the cooldown a held-back namespace is asked');
    });
  });

  group('Given a fetch that is still filing when the miss stops waiting', () {
    test(
        'when a write seals to its own key, then it is refused once '
        'fetchOnMissTimeout passes, and goes through after the filing lands',
        () async {
      final privates = await filing();
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final seed = kem.newSeed();
      final publicKey = (await kem.keyPairFromSeed(seed)).publicKey;
      final kid = nskeyKidOf(publicKey);
      final release = Completer<void>();
      final filed = Completer<void>();
      final ring = _Advertising(
          client(),
          NskeyAdvertisement.single(
              publicKey: publicKey, alg: SecretSharingAlgos.xWing),
          privateFiling: privates, fetchConveyance: () async {
        await release.future;
        await privates.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
            value: base64Encode(seed)));
        filed.complete();
      }, requestConveyance: (ns, name) async {})
        ..fetchOnMissTimeout = const Duration(milliseconds: 50);
      final provider = NskeyProvider(keyRing: ring, cache: ContentKeyCache());
      final context = CryptoContext(atClient: client());
      final ck =
          ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));
      final conveyance = AtKey()
        ..key = '${ck.ckKid}.__ck'
        ..namespace = namespace
        ..sharedBy = alice
        ..metadata = Metadata();
      logs.records.clear();

      await expectLater(provider.encrypt(context, conveyance, ck.toBase64()),
          throwsA(isA<NskeyPrivateNotHeldException>()));
      expect(filed.isCompleted, isFalse,
          reason: 'the fetch was still held when the write gave up, so the '
              'bound ended the wait and not the fetch');
      expect(logs.at('INFO').where((m) => m.contains('has run past 50ms')),
          hasLength(1),
          reason: 'the miss took the timeout path');

      release.complete();
      await filed.future;
      expect(await provider.encrypt(context, conveyance, ck.toBase64()),
          isNotEmpty,
          reason: 'the fetch went on past the bound, and once its filing '
              'landed the same write seals');
    });
  });
}

/// A ring advertising [advertised] as this atSign's current generation, with
/// no lookup behind it.
class _Advertising extends PublishedNskeyKeyRing {
  _Advertising(super.atClient, this.advertised,
      {super.privateFiling, super.fetchConveyance, super.requestConveyance});

  final NskeyAdvertisement advertised;

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      advertised;
}
