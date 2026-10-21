import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

typedef _Put = ({AtKey key, String value, PutRequestOptions? options});

/// The sibling copy: a shared content key conveyed a second time, to the
/// sender's own namespace key, so the sender's other enrollments — and the
/// sender after a restart — can open what it shared.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair aliceNskey;
  late XWingKeyPair bobNskey;
  final logs = RecordedLogs();

  setUpAll(() async {
    logs.installOn();
    aliceNskey = await XWingKeyPair.generate();
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
    registerFallbackValue(Duration.zero);
  });

  ContentKey ck() =>
      ContentKey(Uint8List.fromList(List.generate(32, (i) => i + 1)));

  group('a sibling copy, sealed and opened', () {
    // NOTE: alice's key sits one level above the namespace bob's was found at,
    // so the level the copy is sealed at and the scope it is filed under
    // differ, and an assertion that confused them would go red.
    const aliceLevel = 'my_apps';

    AtKey siblingCopy(ContentKey key) => AtKey()
      ..key = '${key.ckKid}.__ck'
      ..namespace = namespace
      ..sharedBy = alice
      ..metadata = (Metadata()
        ..appMetadata = AppMetadata(
            providerId: nskeyCryptoProviderId,
            additional: {'destination': bob, 'ns': aliceLevel}));

    ({NskeyProvider provider, ContentKeyCache cache, String kid})
        aliceEnrollment() {
      final ring = InMemoryNskeyKeyRing();
      final kid = ring.seedKeypair(alice, aliceLevel,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      final cache = ContentKeyCache();
      return (
        provider: NskeyProvider(keyRing: ring, cache: cache),
        cache: cache,
        kid: kid,
      );
    }

    test(
        'is sealed to the sender\'s key covering the namespace and names the '
        'recipient — raw literal', () async {
      final writer = aliceEnrollment();
      final key = siblingCopy(ck());

      final wire = await writer.provider.encrypt(
          CryptoContext(atClient: MockAtClient()), key, ck().toBase64());

      // NOTE: frozen — a reader files the key by `destination` and `ckNs`, and
      // opens it with the private at `ns`.
      expect(key.metadata.appMetadata!.additional, {
        'recipientKind': 'nskey',
        'ckKid': ck().ckKid,
        'nskeyKid': writer.kid,
        'ns': 'my_apps',
        'destination': '@bob',
        'ckNs': 'app_1.my_apps',
      });
      final opened = await pqOpen(XWingPureDartAlgo.instance,
          aliceNskey.privateKeyBytes, base64Decode(wire),
          info: Uint8List.fromList(utf8.encode('at/nskey:@alice:my_apps')));
      expect(opened, ck().bytes,
          reason: 'sealed at the level of the key that sealed it, bound as '
              'every other conveyance is');
    });

    test(
        'another enrollment of the sender opens it and files the key for the '
        'recipient', () async {
      final writer = aliceEnrollment();
      final written = siblingCopy(ck());
      final wire = await writer.provider.encrypt(
          CryptoContext(atClient: MockAtClient()), written, ck().toBase64());
      final sibling = aliceEnrollment();

      final synced = AtKey()
        ..key = written.key
        ..namespace = written.namespace
        ..sharedBy = alice
        ..metadata = (Metadata()..appMetadata = written.metadata.appMetadata);
      final opened = await sibling.provider
          .decrypt(CryptoContext(atClient: MockAtClient()), synced, wire);

      expect(opened, ck().toBase64());
      expect(sibling.cache.get(bob, namespace, ck().ckKid)?.bytes, ck().bytes,
          reason: 'values shared with bob cite it in bob\'s scope');
      expect(sibling.cache.get(alice, namespace, ck().ckKid), isNull);
      expect(sibling.cache.get(alice, aliceLevel, ck().ckKid), isNull,
          reason: 'it is not a key for alice\'s own data');
    });

    test('a record with a recipient cannot be sealed as one', () async {
      final writer = aliceEnrollment();
      final shared = siblingCopy(ck())..sharedWith = '@carol';

      await expectLater(
          writer.provider.encrypt(
              CryptoContext(atClient: MockAtClient()), shared, ck().toBase64()),
          throwsA(isA<AtEncryptionException>()
              .having((e) => e.message, 'message', contains('recipient'))));
    });

    test('a record with a recipient naming one is refused on open', () async {
      final writer = aliceEnrollment();
      final written = siblingCopy(ck());
      final wire = await writer.provider.encrypt(
          CryptoContext(atClient: MockAtClient()), written, ck().toBase64());
      final reader = aliceEnrollment();

      // The same record, presented as one @carol shared with alice.
      final inbound = AtKey()
        ..key = written.key
        ..namespace = written.namespace
        ..sharedBy = '@carol'
        ..sharedWith = alice
        ..metadata = (Metadata()..appMetadata = written.metadata.appMetadata);

      await expectLater(
          reader.provider
              .decrypt(CryptoContext(atClient: MockAtClient()), inbound, wire),
          throwsA(isA<AtDecryptionException>()
              .having((e) => e.message, 'message', contains('recipient'))),
          reason: 'only the sender\'s own record says whose scope a key is '
              'for; anyone else\'s could file a key under a third atSign');
      expect(reader.cache.get(bob, namespace, ck().ckKid), isNull);
    });
  });

  group('a sibling copy, written', () {
    /// A client of alice whose puts run the way the pipeline does: a record
    /// routed to a provider is sealed by it, and one sent with `shouldEncrypt`
    /// off goes as it is.
    ///
    /// [reach] answers `ensureReachable`, which a sender holding no key
    /// covering the namespace asks; it declines, as a client whose posture
    /// seeds nothing would, unless a test says otherwise.
    ({
      CkManager manager,
      SymmetricAesGcmProvider data,
      ContentKeyCache cache,
      CryptoContext context,
      List<_Put> puts,
      List<String> reachedFor,
    }) sender(
        {bool aliceHoldsKey = true,
        bool failSiblingWrite = false,
        Future<AtReachabilityResult> Function(
                String namespace, InMemoryNskeyKeyRing ring)?
            reach}) {
      final ring = InMemoryNskeyKeyRing()
        ..seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes);
      if (aliceHoldsKey) {
        ring.seedKeypair(alice, namespace,
            publicKey: aliceNskey.publicKeyBytes,
            privateKey: aliceNskey.privateKeyBytes);
      }
      final config = CryptoConfig.nskey(keyRing: ring);
      final client = MockAtClient();
      client.getPreferences().crypto = config;
      when(() => client.getCurrentAtSign()).thenReturn(alice);
      final reachedFor = <String>[];
      when(() => client.ensureReachable(any(), timeout: any(named: 'timeout')))
          .thenAnswer((inv) async {
        final ns = inv.positionalArguments[0] as String;
        reachedFor.add(ns);
        return reach == null
            ? const AtReachabilityResult(AtReachability.postureDoesNotSeed)
            : reach(ns, ring);
      });
      final puts = <_Put>[];
      when(() => client.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((inv) async {
        final key = inv.positionalArguments[0] as AtKey;
        var value = inv.positionalArguments[1] as String;
        final options =
            inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
        if (options?.shouldEncrypt ?? true) {
          key.metadata.appMetadata =
              AppMetadata(providerId: options!.cryptoProviderId!);
          value = await CryptoRuntime(client).encryptForPut(key, value);
        } else if (failSiblingWrite) {
          throw SecondaryConnectException('the sibling copy was not written');
        }
        puts.add((key: key, value: value, options: options));
        return true;
      });
      final data = config.lookup(symmetricAesGcmCryptoProviderId)
          as SymmetricAesGcmProvider;
      return (
        manager: data.ckManager!,
        data: data,
        cache: data.cache,
        context: CryptoContext(atClient: client),
        puts: puts,
        reachedFor: reachedFor,
      );
    }

    AtKey value({String? sharedWith = bob, String ns = namespace}) => AtKey()
      ..key = 'treaty'
      ..namespace = ns
      ..sharedBy = alice
      ..sharedWith = sharedWith
      ..metadata = Metadata();

    test('a share conveys its key to the recipient, then to the sender',
        () async {
      final s = sender();

      await s.manager.ensureCurrent(s.context, value());

      final ckKid = s.cache.current(bob, namespace)!.ckKid;
      expect(s.puts.map((p) => p.key.toString()), [
        '@bob:$ckKid.__ck.app_1.my_apps@alice',
        '$ckKid.__ck.app_1.my_apps@alice',
      ]);
    });

    test('the sibling copy goes sealed, on the route the recipient\'s took',
        () async {
      final s = sender();

      await s.manager
          .ensureCurrent(s.context, value(), useRemoteAtServer: true);

      final recipients = s.puts.first;
      final sibling = s.puts.last;
      expect(sibling.options?.shouldEncrypt, isFalse,
          reason: 'sealed before the put, since the pipeline would overwrite '
              'the appMetadata naming the recipient');
      expect(sibling.options?.alreadyEncrypted, isTrue,
          reason: 'a put the SDK does not encrypt otherwise rebuilds the '
              'metadata, dropping the flag and the recipient this copy names');
      expect(sibling.options?.useRemoteAtServer, isTrue);
      expect(recipients.options?.useRemoteAtServer, isTrue);

      final command = (await PutRequestTransformer().transform(
              Tuple<AtKey, dynamic>()
                ..one = sibling.key
                ..two = sibling.value,
              requestOptions: sibling.options))
          .buildCommand();
      final ckKid = s.cache.current(bob, namespace)!.ckKid;
      final shape = RegExp('^update:isEncrypted:true:appMetadata:'
          '([A-Za-z0-9+/=]+):'
          '${RegExp.escape('$ckKid.__ck.app_1.my_apps@alice')} '
          '[A-Za-z0-9+/=]+\\n\$');
      final match = shape.firstMatch(command);
      expect(match, isNotNull, reason: command);
      final sent = jsonDecode(utf8.decode(base64Decode(match!.group(1)!)))
          as Map<String, dynamic>;
      expect(sent['providerId'], nskeyCryptoProviderId);
      expect(sent['destination'], bob);
      expect(sent['ckNs'], namespace);
    });

    test('self data gets no sibling copy — the control', () async {
      final s = sender();

      await s.manager.ensureCurrent(s.context, value(sharedWith: null));

      expect(s.puts.map((p) => p.key.toString()), [
        '${s.cache.current(alice, namespace)!.ckKid}.__ck.app_1.my_apps@alice'
      ]);
    });

    test(
        'a sender holding no key covering the namespace mints one where the '
        'recipient\'s was found', () async {
      final s = sender(
          aliceHoldsKey: false,
          reach: (ns, ring) async {
            ring.seedKeypair(alice, ns,
                publicKey: aliceNskey.publicKeyBytes,
                privateKey: aliceNskey.privateKeyBytes);
            return const AtReachabilityResult(AtReachability.published);
          });

      // An AtCollection sub-collection's namespace carries an item id.
      await s.manager.ensureCurrent(s.context, value(ns: 'item-7.$namespace'));

      expect(s.reachedFor, [namespace],
          reason: 'at the level bob\'s key was found, never the value\'s own, '
              'or every item would get a key of its own');
      final ckKid = s.cache.current(bob, namespace)!.ckKid;
      expect(s.puts.map((p) => p.key.toString()), [
        '@bob:$ckKid.__ck.app_1.my_apps@alice',
        '$ckKid.__ck.app_1.my_apps@alice',
      ]);
    });

    test('with seedNamespaceKeys off a share goes without one, and says why',
        () async {
      final s = sender(aliceHoldsKey: false);

      await s.manager.ensureCurrent(s.context, value());

      expect(s.puts.single.key.sharedWith, bob);
      expect(s.cache.current(bob, namespace), isNotNull,
          reason: 'the share itself goes ahead');
      final ckKid = s.cache.current(bob, namespace)!.ckKid;
      expect(logs.at('WARNING').where((m) => m.contains(ckKid)),
          [contains('seedNamespaceKeys is off')]);
    });

    test('a sender that holds a key asks for none — the control', () async {
      final s = sender();

      await s.manager.ensureCurrent(s.context, value());

      expect(s.reachedFor, isEmpty);
      expect(s.puts, hasLength(2));
    });

    /// Another client of alice — a sibling enrollment, or this one after a
    /// restart — holding her namespace key and nothing in memory, whose local
    /// storage is empty and whose atServer holds what [written] put.
    ({
      SymmetricAesGcmProvider data,
      CryptoContext context,
      List<(String, bool?)> reads,
    }) reader(List<_Put> written) {
      final stored = {for (final p in written) p.key.toString(): p};
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair(alice, namespace,
            publicKey: aliceNskey.publicKeyBytes,
            privateKey: aliceNskey.privateKeyBytes);
      final config = CryptoConfig.nskey(keyRing: ring);
      final client = MockAtClient();
      client.getPreferences().crypto = config;
      when(() => client.getCurrentAtSign()).thenReturn(alice);
      final reads = <(String, bool?)>[];
      when(() => client.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((inv) async {
        final asked = inv.positionalArguments[0] as AtKey;
        final remote =
            (inv.namedArguments[#getRequestOptions] as GetRequestOptions?)
                ?.useRemoteAtServer;
        reads.add((asked.toString(), remote));
        final held = stored[asked.toString()];
        if (held == null || remote != true) {
          throw AtKeyNotFoundException('$asked');
        }
        // What the get pipeline does with a fetched record: route it to the
        // provider its appMetadata names.
        final fetched = AtKey()
          ..key = held.key.key
          ..namespace = held.key.namespace
          ..sharedBy = held.key.sharedBy
          ..sharedWith = held.key.sharedWith
          ..metadata = (Metadata()
            ..appMetadata = held.key.metadata.appMetadata
            ..isEncrypted = true);
        return AtValue()
          ..value =
              await CryptoRuntime(client).decryptForGet(fetched, held.value);
      });
      final data = config.lookup(symmetricAesGcmCryptoProviderId)
          as SymmetricAesGcmProvider;
      return (
        data: data,
        context: CryptoContext(atClient: client),
        reads: reads,
      );
    }

    AtKey asSynced(AtKey written) => AtKey()
      ..key = written.key
      ..namespace = written.namespace
      ..sharedBy = written.sharedBy
      ..sharedWith = written.sharedWith
      ..metadata = (Metadata()..appMetadata = written.metadata.appMetadata);

    test(
        'another client of the sender opens what it shared, from the sibling '
        'copy', () async {
      final s = sender();
      final shared = value();
      await s.manager.ensureCurrent(s.context, shared);
      final ciphertext = await s.data.encrypt(s.context, shared, 'the pact');
      final r = reader(s.puts);

      final read =
          await r.data.decrypt(r.context, asSynced(shared), ciphertext);

      expect(read, 'the pact');
      final sibling = '${s.cache.current(bob, namespace)!.ckKid}'
          '.__ck.app_1.my_apps@alice';
      expect(r.reads, [(sibling, null), (sibling, true)],
          reason: 'the sibling copy, from local storage and then the '
              'atServer; bob\'s conveyance is sealed to bob and never read');
      expect(logs.at('WARNING').where((m) => m.contains(sibling)), isEmpty,
          reason: 'a record absent from local storage is the ordinary answer '
              'on that leg, not something to warn about');
    });

    test('a share with no sibling copy reads as a key not yet available',
        () async {
      final s = sender(aliceHoldsKey: false);
      final shared = value();
      await s.manager.ensureCurrent(s.context, shared);
      final ciphertext = await s.data.encrypt(s.context, shared, 'the pact');
      final r = reader(s.puts);

      await expectLater(r.data.decrypt(r.context, asSynced(shared), ciphertext),
          throwsA(isA<ContentKeyUnavailableException>()),
          reason: 'not a failure to open bob\'s conveyance, which says '
              'nothing true about why alice cannot read her own share');
      expect(r.reads.where((read) => read.$1.startsWith('@bob:')), isEmpty);
    });

    test('a sibling copy that is not written leaves no current key', () async {
      final s = sender(failSiblingWrite: true);

      await expectLater(s.manager.ensureCurrent(s.context, value()),
          throwsA(isA<SecondaryConnectException>()));
      expect(s.cache.current(bob, namespace), isNull,
          reason: 'a key the sender cannot reopen would be cut again by '
              'every restart, the fault the copy exists to end');
    });
  });
}
