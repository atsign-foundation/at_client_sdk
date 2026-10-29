import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

/// What a ring does when it needs an own namespace-key private it does not
/// hold: for a generation its own atSign advertises, it fetches the
/// conveyance records addressed to this enrollment, and asks the other
/// enrollments only if none carried it.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.6
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(AtKey());
  });

  /// A client whose atServer answers each own advertisement read with what
  /// [published] holds for its namespace, recording the read, or throws what
  /// [unreachable] returns while that is not null.
  ({MockAtClient client, List<String> reads, AdvertisedKeyVerifier verifier})
      serving(Map<String, NskeyAdvertisement> published,
          {Exception? Function()? unreachable}) {
    final atClient = MockAtClient();
    final reads = <String>[];
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final atKey = inv.positionalArguments[0] as AtKey;
      reads.add('${atKey.namespace}');
      final down = unreachable?.call();
      if (down != null) throw down;
      if (!published.containsKey(atKey.namespace)) {
        throw AtKeyNotFoundException('$atKey');
      }
      return AtValue()..value = '${atKey.namespace}';
    });
    return (
      client: atClient,
      reads: reads,
      verifier: _ServedAsPublished(published),
    );
  }

  MockAtClient client() => serving({}).client;

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(alice, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: alice);
  }

  Future<({String kid, Uint8List seed, PackageKey key})> generation() async {
    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final seed = kem.newSeed();
    final key = PackageKey.fromBytes(
        use: SecretSharingAlgos.useEnc,
        alg: SecretSharingAlgos.xWing,
        pub: (await kem.keyPairFromSeed(seed)).publicKey);
    return (kid: key.kid, seed: seed, key: key);
  }

  NskeyAdvertisement naming(List<PackageKey> keys) => NskeyAdvertisement(
      v: nskeyAdvertisementVersion, createdAt: DateTime.utc(2026), keys: keys);

  Secret conveyed(({String kid, Uint8List seed, PackageKey key}) generation) =>
      Secret(
          namespace: namespace,
          name: '${NskeyPrivateFiling.secretNamePrefix}${generation.kid}',
          value: base64Encode(generation.seed));

  String secretOf(String kid) => '${NskeyPrivateFiling.secretNamePrefix}$kid';

  group(
      'Given an own generation its advertisement names, whose private this '
      'enrollment does not hold', () {
    late ({String kid, Uint8List seed, PackageKey key}) g1;

    setUp(() async => g1 = await generation());

    PublishedNskeyKeyRing advertising(PublishedNskeyKeyRing ring) =>
        ring..rememberOwn(alice, namespace, naming([g1.key]));

    test(
        'when a conveyance record for it is waiting, then the fetch files it '
        'and nothing is asked', () async {
      final privates = await filing();
      var fetched = 0;
      final asked = <String>[];
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: privates,
          fetchConveyance: () async {
            fetched++;
            await privates.file(conveyed(g1));
          },
          requestConveyance: (ns, name) async => asked.add(name)));

      expect(await ring.privateHalf(alice, namespace, g1.kid), isNotNull,
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
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add(name)));

      expect(await ring.privateHalf(alice, namespace, g1.kid), isNull);
      await pumpEventQueue();
      expect(fetched, 1, reason: 'the fetch comes first');
      expect(asked, [secretOf(g1.kid)]);
    });

    test('when two misses come at once, then one fetch serves both', () async {
      final privates = await filing();
      final arrived = Completer<void>();
      var fetched = 0;
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: privates, fetchConveyance: () async {
        fetched++;
        await arrived.future;
        await privates.file(conveyed(g1));
      }, requestConveyance: (ns, name) async {}));

      final first = ring.privateHalf(alice, namespace, g1.kid);
      final second = ring.privateHalf(alice, namespace, g1.kid);
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
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async {})
        ..askCooldown = const Duration(minutes: 10));

      expect(await ring.privateHalf(alice, namespace, g1.kid), isNull);
      expect(await ring.privateHalf(alice, namespace, g1.kid), isNull);
      expect(fetched, 1);
    });

    test('when the cooldown has passed, then it fetches again', () async {
      // NOTE: the control for the test above: without it a ring that fetched
      // only once ever would pass there.
      var fetched = 0;
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async {})
        ..askCooldown = Duration.zero);

      await ring.privateHalf(alice, namespace, g1.kid);
      await ring.privateHalf(alice, namespace, g1.kid);
      expect(fetched, 2);
    });

    test('when the fetch fails, then it still asks', () async {
      final asked = <String>[];
      final ring = advertising(PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async =>
              throw SecondaryConnectException('the atServer cannot be reached'),
          requestConveyance: (ns, name) async => asked.add(name)));

      expect(await ring.privateHalf(alice, namespace, g1.kid), isNull);
      await pumpEventQueue();
      expect(asked, hasLength(1));
    });

    test(
        'when the ring is built with askOnReadMiss false, then a miss reads, '
        'fetches and asks nothing', () async {
      final served = serving({
        namespace: naming([g1.key])
      });
      final privates = await filing();
      final g0 = await generation();
      await privates.store(
          namespace: namespace, nskeyKid: g0.kid, seed: NskeySeed(g0.seed));
      var fetched = 0;
      final asked = <String>[];
      PublishedNskeyKeyRing build({required bool askOnReadMiss}) =>
          PublishedNskeyKeyRing(served.client,
              verifier: served.verifier,
              privateFiling: privates,
              fetchConveyance: () async => fetched++,
              requestConveyance: (ns, name) async => asked.add(name),
              askOnReadMiss: askOnReadMiss);

      final off = build(askOnReadMiss: false);
      expect(await off.privateHalf(alice, namespace, g1.kid), isNull);
      off.rememberOwn(alice, namespace, naming([g1.key]));
      expect(await off.privateHalf(alice, namespace, g1.kid), isNull);
      await pumpEventQueue();
      expect(served.reads, isEmpty,
          reason: 'a kid no copy names, in a namespace the keyfile holds, '
              'reads nothing');
      expect(fetched, 0);
      expect(asked, isEmpty, reason: 'nor does an advertised kid fetch or ask');
      expect(off.asksOnReadMiss, isFalse);

      final on = build(askOnReadMiss: true);
      expect(await on.privateHalf(alice, namespace, g1.kid), isNull);
      await pumpEventQueue();
      expect(served.reads, [namespace]);
      expect(fetched, 1);
      expect(asked, [secretOf(g1.kid)],
          reason: 'the control: the same ring with the gate on reads, fetches '
              'and asks');
    });
  });

  group('Given misses on advertised generations no record carries', () {
    test(
        'when fifty come at once over three namespaces, then one fetch serves '
        'them all and each generation is asked once', () async {
      const namespaces = ['ns1.app', 'ns2.app', 'ns3.app'];
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
      final kids = <String, List<String>>{};
      for (final ns in namespaces) {
        final a = await generation();
        final b = await generation();
        ring.rememberOwn(alice, ns, naming([a.key, b.key]));
        kids[ns] = [a.kid, b.kid];
      }

      final misses = [
        for (var i = 0; i < 50; i++)
          ring.privateHalf(
              alice, namespaces[i % 3], kids[namespaces[i % 3]]![i % 2])
      ];
      await pumpEventQueue();
      release.complete();
      await Future.wait(misses);
      await pumpEventQueue();

      expect(fetched, 1,
          reason: 'every miss shares the one fetch in flight, whatever kid it '
              'names');
      expect(asked.toSet(), {
        for (final ns in namespaces)
          for (final kid in kids[ns]!) (ns, secretOf(kid))
      });
      expect(asked, hasLength(6));
    });

    test(
        'when kid A misses and then kid B in one namespace, then both are '
        'asked', () async {
      final a = await generation();
      final b = await generation();
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async {},
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = const Duration(minutes: 10)
        ..rememberOwn(alice, namespace, naming([a.key, b.key]));

      await ring.privateHalf(alice, namespace, a.kid);
      await ring.privateHalf(alice, namespace, a.kid);
      await ring.privateHalf(alice, namespace, b.kid);
      await pumpEventQueue();

      expect(
          asked, [(namespace, secretOf(a.kid)), (namespace, secretOf(b.kid))],
          reason: 'an ask names one generation, so a second generation in '
              'the namespace needs its own; A asked once is the control');
    });

    test(
        'when a generation misses again while its ask is outstanding, then '
        'nothing more is asked until the answer\'s wait ends', () async {
      final g1 = await generation();
      final answered = Completer<void>();
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async {}, requestConveyance: (ns, name) {
        asked.add(name);
        return answered.future;
      })
        ..askCooldown = Duration.zero
        ..rememberOwn(alice, namespace, naming([g1.key]));

      await ring.privateHalf(alice, namespace, g1.kid);
      await pumpEventQueue();
      await ring.privateHalf(alice, namespace, g1.kid);
      await pumpEventQueue();
      expect(asked, hasLength(1),
          reason: 'with no cooldown, only the outstanding ask holds the '
              'second miss back');

      answered.complete();
      await pumpEventQueue();
      await ring.privateHalf(alice, namespace, g1.kid);
      await pumpEventQueue();
      expect(asked, hasLength(2),
          reason: 'the control: once the wait ends, a miss asks again');
    });

    test(
        'when the cooldown has passed, then the next miss asks again and the '
        'quiet namespaces are forgotten', () async {
      const namespaces = ['ns1.app', 'ns2.app', 'ns3.app'];
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(client(),
          privateFiling: await filing(),
          fetchConveyance: () async {},
          requestConveyance: (ns, name) async => asked.add((ns, name)))
        ..askCooldown = const Duration(milliseconds: 50);
      final kids = <String, String>{};
      for (final ns in namespaces) {
        final g = await generation();
        ring.rememberOwn(alice, ns, naming([g.key]));
        kids[ns] = g.kid;
      }

      for (final ns in namespaces) {
        await ring.privateHalf(alice, ns, kids[ns]!);
      }
      await pumpEventQueue();
      expect(ring.namespacesAskedRecently, namespaces.length,
          reason: 'the control: each namespace was stamped');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await ring.privateHalf(alice, namespaces.first, kids[namespaces.first]!);
      await pumpEventQueue();

      expect(asked, hasLength(namespaces.length + 1));
      expect(ring.namespacesAskedRecently, 1,
          reason: 'stamps past the cooldown are dropped, so what is held is '
              'bounded by the asks one cooldown allows');
    });
  });

  group('Given a miss on a kid no own advertisement the ring holds names', () {
    test(
        'when the ring knows nothing of its namespace, then nothing is read, '
        'fetched or asked', () async {
      final served = serving({});
      var fetched = 0;
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(served.client,
          verifier: served.verifier,
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add(name))
        ..askCooldown = Duration.zero;

      for (var i = 0; i < 20; i++) {
        expect(await ring.privateHalf(alice, 'made.up$i', 'kid$i'), isNull);
      }
      await pumpEventQueue();

      expect(served.reads, isEmpty);
      expect(fetched, 0);
      expect(asked, isEmpty);
    });

    test(
        'when the ring holds its own advertisement for the namespace, then it '
        'reads the published one once per cooldown, and with the kid unnamed '
        'fetches and asks nothing', () async {
      final g1 = await generation();
      final served = serving({
        namespace: naming([g1.key])
      });
      var fetched = 0;
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(served.client,
          verifier: served.verifier,
          privateFiling: await filing(),
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add(name))
        ..askCooldown = const Duration(milliseconds: 200)
        ..rememberOwn(alice, namespace, naming([g1.key]));

      final burst = [
        for (var i = 0; i < 20; i++)
          ring.privateHalf(alice, namespace, 'unnamed$i')
      ];
      expect(await Future.wait(burst), everyElement(isNull));
      for (var i = 0; i < 20; i++) {
        expect(await ring.privateHalf(alice, namespace, 'later$i'), isNull);
      }
      await pumpEventQueue();
      expect(served.reads, [namespace],
          reason: 'concurrent misses share one read, and the cooldown holds '
              'the rest');
      expect(fetched, 0);
      expect(asked, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await ring.privateHalf(alice, namespace, 'unnamed');
      expect(served.reads, [namespace, namespace],
          reason: 'past the cooldown the next miss reads again');
    });

    test(
        'when the keyfile holds a private for the namespace and the published '
        'advertisement names a newer generation, then one read, then a fetch '
        'and an ask', () async {
      final g1 = await generation();
      final g2 = await generation();
      final served = serving({
        namespace: naming([g2.key, g1.key])
      });
      final privates = await filing();
      await privates.store(
          namespace: namespace, nskeyKid: g1.kid, seed: NskeySeed(g1.seed));
      var fetched = 0;
      final asked = <String>[];
      final ring = PublishedNskeyKeyRing(served.client,
          verifier: served.verifier,
          privateFiling: privates,
          fetchConveyance: () async => fetched++,
          requestConveyance: (ns, name) async => asked.add(name))
        ..askCooldown = const Duration(minutes: 10);

      expect(await ring.privateHalf(alice, namespace, g2.kid), isNull);
      await pumpEventQueue();
      expect(served.reads, [namespace]);
      expect(fetched, 1);
      expect(asked, [secretOf(g2.kid)]);

      expect(await ring.privateHalf(alice, 'other.app', g2.kid), isNull);
      await pumpEventQueue();
      expect(served.reads, [namespace],
          reason: 'the control: a namespace the keyfile holds nothing for is '
              'not read');
    });

    test(
        'when the atServer cannot be reached at the first miss, then the next '
        'miss after the cooldown reads again and heals', () async {
      final g1 = await generation();
      final g2 = await generation();
      var down = true;
      final served = serving({
        namespace: naming([g2.key, g1.key])
      },
          unreachable: () => down
              ? SecondaryConnectException('the atServer cannot be reached')
              : null);
      final privates = await filing();
      await privates.store(
          namespace: namespace, nskeyKid: g1.kid, seed: NskeySeed(g1.seed));
      var fetched = 0;
      final ring = PublishedNskeyKeyRing(served.client,
          verifier: served.verifier,
          privateFiling: privates, fetchConveyance: () async {
        fetched++;
        await privates.file(conveyed(g2));
      }, requestConveyance: (ns, name) async {})
        ..askCooldown = const Duration(milliseconds: 50);

      expect(await ring.privateHalf(alice, namespace, g2.kid), isNull);
      expect(fetched, 0, reason: 'an unread advertisement names nothing');

      down = false;
      expect(await ring.privateHalf(alice, namespace, g2.kid), isNull,
          reason: 'inside the cooldown the failed read is not retried');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await ring.privateHalf(alice, namespace, g2.kid), isNotNull);
      expect(served.reads, [namespace, namespace]);
      expect(fetched, 1);
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
      final advertised = NskeyAdvertisement.single(
          publicKey: publicKey, alg: SecretSharingAlgos.xWing);
      final ring = _Advertising(client(), advertised, privateFiling: privates,
          fetchConveyance: () async {
        await release.future;
        await privates.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
            value: base64Encode(seed)));
        filed.complete();
      }, requestConveyance: (ns, name) async {})
        ..fetchOnMissTimeout = const Duration(milliseconds: 50)
        ..rememberOwn(alice, namespace, advertised);
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

/// Trusts each served advertisement as the one published for the namespace
/// its payload names.
class _ServedAsPublished implements AdvertisedKeyVerifier {
  _ServedAsPublished(this.published);

  final Map<String, NskeyAdvertisement> published;

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async =>
      published[payload]!;
}
