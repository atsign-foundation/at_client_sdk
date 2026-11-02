import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientEnvelopeSigner;
import 'package:at_client/src/crypto/nskey/start_up_seeding.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/ml_dsa_keyfile.dart' show keysHoldingApkam;
import 'test_utils/recorded_logs.dart';
import 'test_utils/test_keypairs.dart';

const _alice = '@alice';
const _bob = '@bob';

/// A ring that records every level it is asked about.
class _Ring extends InMemoryNskeyKeyRing {
  final List<String> lookedUp = [];

  /// `owner:namespace` of each advertisement its owner has since withdrawn.
  final Set<String> withdrawn = {};

  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) {
    lookedUp.add('$owner:$namespace');
    if (withdrawn.contains('$owner:$namespace')) return Future.value(null);
    return super.currentPublic(owner, namespace);
  }
}

/// A ring whose every lookup fails with [failure].
class _FailingRing extends _Ring {
  final Object failure;

  _FailingRing(this.failure);

  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) =>
      Future.error(failure);
}

/// One client's post-quantum providers over [ring].
class _Client {
  final _Ring ring;
  final ContentKeyCache cache;
  final CkManager manager;
  late final NskeyProvider nskey = NskeyProvider(keyRing: ring, cache: cache);
  late final SymmetricAesGcmProvider data =
      SymmetricAesGcmProvider(cache: cache, ckManager: manager);

  _Client(_Ring ring) : this._(ring, ContentKeyCache(), null);

  /// A client whose content-key manager resolves with [resolver].
  _Client.over(_Ring ring, NskeyResolver resolver)
      : this._(ring, ContentKeyCache(), resolver);

  _Client._(this.ring, this.cache, NskeyResolver? resolver)
      : manager = CkManager(cache: cache, keyRing: ring, resolver: resolver);
}

/// The callbacks of an RPC that answers every request with an ack.
class _RpcCallbacks implements AtRpcCallbacks {
  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async =>
      AtRpcResp.ack(request: request);

  @override
  Future<void> handleResponse(AtRpcResp response) async {}
}

/// A provider registered under the legacy id, recording what it seals.
class _Legacy extends CryptoProvider {
  final List<String> sealed = [];

  @override
  String get id => legacyCryptoProviderId;

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    sealed.add(value);
    return 'legacy $value';
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

/// The atServers of every atSign here, as one store of public records, with
/// the batches asked of them and every record read on its own.
class _Network {
  final Map<String, String> records = {};
  final List<List<String>> batches = [];
  final List<String> reads = [];

  /// Whether the atServers can be reached at all.
  bool reachable = true;

  /// The error code a batch entry for each key is answered with instead.
  final Map<String, String> failing = {};

  /// The keys a batch entry answers with data that is not a record.
  final Set<String> malformed = {};

  /// How long a batch takes to be answered.
  Duration batchDelay = Duration.zero;

  void requireReachable() {
    if (!reachable) throw SecondaryConnectException('atServer unreachable');
  }
}

class _PeerClient extends Mock implements AtClient {}

String _apskKey(String atSign, String enrollmentId) =>
    'public:_apsk.$enrollmentId.a.__e$atSign';

/// A client of [atSign] on [enrollmentId] whose public records and lookups go
/// to [net], answering a `batch:` of `plookup`s as the atServer does.
_PeerClient _peer(String atSign, String enrollmentId, _Network net) {
  final c = _PeerClient();
  final apkam = pkamKeyPairFor(atSign, enrollmentId);
  final local = MockLocalSecondary();
  final remote = MockRemoteSecondary();
  final lookUp = MockAtLookUp();
  final localRecords = <String, String>{};
  when(() => c.getCurrentAtSign()).thenReturn(atSign);
  when(() => c.enrollmentId).thenReturn(enrollmentId);
  when(() => c.atKeysIo)
      .thenReturn(keysHoldingApkam(atSign, enrollmentId, apkam));
  when(() => c.getPreferences()).thenReturn(AtClientPreference(
      posture: PqPosture.pqActive,
      keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]));
  when(() => c.dataEvents).thenAnswer((_) => const Stream<DataEvent>.empty());
  when(() => c.getLocalSecondary()).thenReturn(local);
  when(() => c.getRemoteSecondary()).thenReturn(remote);
  when(() => remote.atLookUp).thenReturn(lookUp);
  when(() => local.getPkamPublicKey())
      .thenAnswer((_) async => apkam.atPublicKey.publicKey);
  when(() => local.getPkamPrivateKey())
      .thenAnswer((_) async => apkam.atPrivateKey.privateKey);
  when(() => local.executeVerb(any(),
      cameFromServer: any(named: 'cameFromServer'))).thenAnswer((inv) async {
    final builder = inv.positionalArguments.first;
    if (builder is UpdateVerbBuilder) {
      localRecords[builder.atKey.toString()] = builder.value as String;
      return 'data:1';
    }
    if (builder is LLookupVerbBuilder) {
      final value = localRecords[builder.atKey.toString()];
      if (value == null) throw KeyNotFoundException('${builder.atKey}');
      return 'data:$value';
    }
    return 'data:null';
  });
  when(() => remote.executeCommand(any(that: startsWith('enroll:listns')),
      auth: any(named: 'auth'))).thenAnswer((_) async => 'data:[]');
  when(() => remote.executeCommand(any(that: startsWith('batch:')),
      auth: any(named: 'auth'))).thenAnswer((inv) async {
    final entries = jsonDecode((inv.positionalArguments.first as String)
        .trim()
        .substring('batch:'.length)) as List;
    net.batches.add([for (final e in entries) e['command'] as String]);
    net.requireReachable();
    await Future<void>.delayed(net.batchDelay);
    return 'data:${jsonEncode([
          for (final e in entries)
            {'id': e['id'], 'response': _plookup(net, e['command'] as String)}
        ])}';
  });
  when(() => remote.executeVerb(any())).thenAnswer((inv) async {
    final builder = inv.positionalArguments.first;
    if (builder is UpdateVerbBuilder) {
      net.records[builder.atKey.toString()] = builder.value as String;
    }
    return 'data:1';
  });
  when(() => c.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions')))
      .thenAnswer((_) async => true);
  when(() => c.ensureReachable(any(), timeout: any(named: 'timeout')))
      .thenAnswer((_) async =>
          const AtReachabilityResult(AtReachability.postureDoesNotSeed));
  when(() => c.get(any(), getRequestOptions: any(named: 'getRequestOptions')))
      .thenAnswer((inv) async {
    final key = (inv.positionalArguments.first as AtKey).toString();
    final options =
        inv.namedArguments[#getRequestOptions] as GetRequestOptions?;
    if (options?.useRemoteAtServer == true) {
      net.reads.add(key);
      net.requireReachable();
    }
    final value = options?.useRemoteAtServer == true
        ? net.records[key]
        : localRecords[key];
    if (value == null) throw AtKeyNotFoundException(key);
    return AtValue()..value = value;
  });
  return c;
}

/// The atServer's answer to one `plookup:...:all:` command inside a batch.
Map<String, Object?> _plookup(_Network net, String command) {
  final match = RegExp(r'^plookup:(?:bypassCache:true:)?all:(.+)@([^@]+)$')
      .firstMatch(command.trim());
  final key = 'public:${match!.group(1)}@${match.group(2)}';
  if (net.malformed.contains(key)) return {'data': 'not a record'};
  final failure = net.failing[key];
  if (failure != null) {
    return {'error_code': failure, 'error_message': '$failure for $key'};
  }
  final value = net.records[key];
  return value == null
      ? {'error_code': 'AT0015', 'error_message': 'key not found'}
      : {
          'data': jsonEncode({'key': key, 'data': value, 'metaData': {}})
        };
}

/// Publishes [atSign]'s namespace key in [namespace] from enrollment
/// [enrollmentId], signed with that enrollment's `_apsk`.
Future<void> _publishFrom(
    _Network net, String atSign, String enrollmentId, String namespace) async {
  final client = _peer(atSign, enrollmentId, net);
  net.records[_apskKey(atSign, enrollmentId)] =
      await AtClientEnvelopeSigner(client).publicSigningKeyValue;
  await PublishedNskeyKeyRing(client,
          privateFiling: NskeyPrivateFiling(
              keysIo: client.atKeysIo as WrittenAtKeysIo, atSign: atSign))
      .mintAndPublish(namespace);
}

/// A share of a key whose recipient is not the writer is sealed to the most
/// specific namespace key the recipient advertises over the key's whole name,
/// or to the one namespace the program requires.
///
/// Catalogue: features/at_client/pq_share_level.feature
void main() {
  final logs = RecordedLogs();
  late MockAtClient atClient;
  late CryptoContext context;
  late Map<String, ({AtKey key, String value})> store;

  setUpAll(() {
    logs.installOn(level: 'info');
    registerFallbackValue(AtKey());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(GetRequestOptions());
    registerFallbackValue(UpdateVerbBuilder());
    registerFallbackValue(NotificationParams());
  });

  setUp(() {
    store = {};
    logs.records.clear();
    atClient = MockAtClient(posture: PqPosture.pqActive);
    when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
    atClient.getPreferences().namespace = 'todos.demos';
    context = CryptoContext(atClient: atClient);
  });

  tearDown(() => StartUpSeeding.wait = const Duration(seconds: 30));

  /// Wires the mock so a conveyance [c] puts is sealed and kept, and so the
  /// writer can mint nothing unless [mint] does.
  void wire(_Client c,
      {Future<AtReachabilityResult> Function(String namespace)? mint}) {
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      store[key.toString()] = (
        key: key,
        value: options?.alreadyEncrypted == true
            ? value
            : await c.nskey.encrypt(context, key, value)
      );
      return true;
    });
    when(() => atClient.ensureReachable(any(), timeout: any(named: 'timeout')))
        .thenAnswer((inv) => mint != null
            ? mint(inv.positionalArguments.first as String)
            : Future.value(
                const AtReachabilityResult(AtReachability.postureDoesNotSeed)));
  }

  /// Gives the mock client [c]'s providers, which seal the writer's copy.
  void configure(_Client c) => atClient.getPreferences().crypto = CryptoConfig(
        defaultProviderId: c.data.id,
        providers: [c.data, c.nskey],
        keyRing: c.ring,
      );

  Future<String> write(_Client c, AtKey key, {String? sealTo}) async {
    await c.data.prepareForWrite(context, key, sealToNamespace: sealTo);
    return c.data.encrypt(context, key, 'memo');
  }

  Map<String, dynamic> stamped(AtKey key) =>
      key.metadata.appMetadata!.additional!;

  /// The kid of the namespace key the conveyance to [owner] in [ckNs] was
  /// sealed to.
  String? sealedTo(String owner, String ckNs) {
    final name = store.keys.where(
        (k) => k.startsWith('$owner:') && k.contains('.__ck.$ckNs$_alice'));
    if (name.isEmpty) return null;
    return store[name.single]!.key.metadata.appMetadata!.additional!['nskeyKid']
        as String?;
  }

  Future<String> publish(_Ring ring, String owner, String namespace) async {
    final pair = await XWingKeyPair.generate();
    return ring.seedPublicOnly(owner, namespace,
        publicKey: pair.publicKeyBytes);
  }

  Future<String> hold(_Ring ring, String owner, String namespace) async {
    final pair = await XWingKeyPair.generate();
    return ring.seedKeypair(owner, namespace,
        publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
  }

  Matcher refusedNaming(String atSign, String namespace) =>
      throwsA(isA<NamespaceKeyUnavailableException>()
          .having((e) => e.atSign, 'atSign', atSign)
          .having((e) => e.namespace, 'namespace', namespace));

  /// [future], failing the test rather than waiting past a second.
  Future<T> atOnce<T>(Future<T> future) =>
      future.timeout(const Duration(seconds: 1),
          onTimeout: () => fail('it waited, and was to answer at once'));

  test('The most specific key the recipient advertises seals the share',
      () async {
    final c = _Client(_Ring());
    await publish(c.ring, _bob, 'demos');
    final bobs = await publish(c.ring, _bob, 'todos.demos');
    wire(c);
    final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

    await write(c, key);

    expect(stamped(key)['ckNs'], 'todos.demos');
    expect(sealedTo(_bob, 'todos.demos'), bobs);
  });

  test("The writer's own namespaces do not decide a share's level", () async {
    final c = _Client(_Ring());
    await hold(c.ring, _alice, 'todos.demos');
    final bobs = await publish(c.ring, _bob, 'demos');
    wire(c);
    final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

    await write(c, key);

    expect(stamped(key)['ckNs'], 'demos');
    expect(sealedTo(_bob, 'demos'), bobs);
  });

  test("Every level of the key's name is walked", () async {
    final c = _Client(_Ring());
    final bobs = await publish(c.ring, _bob, 'notes.todos.demos');
    await publish(c.ring, _bob, 'todos.demos');
    wire(c);
    final key = AtKey.fromString('$_bob:note1.t42.notes.todos.demos$_alice');

    await write(c, key);

    expect(stamped(key)['ckNs'], 'notes.todos.demos');
    expect(sealedTo(_bob, 'notes.todos.demos'), bobs);
  });

  test(
      "A name that only ends with an advertised namespace's letters is not "
      'covered', () async {
    final c = _Client(_Ring());
    await publish(c.ring, _bob, 'demos');
    wire(c);

    await expectLater(write(c, AtKey.fromString('$_bob:x.mydemos$_alice')),
        throwsA(isA<NamespaceKeyUnavailableException>()));
    expect(store.keys.where((k) => k.contains('.__ck.demos')), isEmpty);
  });

  test(
      'A recipient advertising nothing for the name refuses a share at '
      'pqActive', () async {
    final c = _Client(_Ring());
    wire(c);

    await expectLater(
        atOnce(write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'))),
        refusedNaming(_bob, 'todos.demos'));
  });

  group(
      'Given a client at pqActive allowing legacy encryption, with the legacy '
      'fallback', () {
    /// A notification of [key] by a client in [namespace] over [c] whose
    /// legacy provider is [legacy], with [sealTo] as its required namespace.
    Future<NotifyVerbBuilder> notify(_Client c, _Legacy legacy, AtKey key,
        {String? sealTo, String namespace = 'todos.demos'}) {
      atClient = MockAtClient(
          posture:
              PqPosture.pqActive.copyWith(disallowLegacyEncryption: false));
      when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
      atClient.getPreferences()
        ..namespace = namespace
        ..allowLegacyCryptoFallback = true
        ..crypto = CryptoConfig(
          defaultProviderId: c.data.id,
          providers: [c.data, c.nskey, legacy],
          keyRing: c.ring,
        );
      context = CryptoContext(atClient: atClient);
      wire(c);
      key.metadata.isEncrypted = true;
      return NotificationRequestTransformer(atClient).transform(
          NotificationParams.forUpdate(key,
              value: 'memo', sealToNamespace: sealTo));
    }

    test(
        'A share to a recipient advertising nothing is sealed with legacy '
        'encryption', () async {
      final c = _Client(_Ring());
      final legacy = _Legacy();

      final builder = await notify(
          c, legacy, AtKey.fromString('$_bob:x.todos.demos$_alice'));

      expect(builder.value, 'legacy memo');
      expect(legacy.sealed, ['memo']);
      expect(
          logs
              .at('WARNING')
              .where((m) => m.contains('falling back to legacy encryption')),
          isNotEmpty);
    });

    test(
        'A required namespace the recipient has not advertised falls back to '
        'legacy where allowed', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'demos');
      final legacy = _Legacy();

      final builder = await notify(
          c, legacy, AtKey.fromString('$_bob:x.todos.demos$_alice'),
          sealTo: 'todos.demos');

      expect(builder.value, 'legacy memo');
      expect(store.keys.where((k) => k.contains('.__ck.demos')), isEmpty,
          reason: "never sealed under bob's broader key");
    });

    test(
        "A mixed fleet: each device's notification is sealed under its own "
        'namespace key, or sent with legacy encryption', () async {
      final c = _Client(_Ring());
      final d1 = await publish(c.ring, _bob, 'd1.sshnp');
      await publish(c.ring, _bob, 'sshnp');
      final legacy = _Legacy();

      final toD1 = await notify(
          c, legacy, AtKey.fromString('$_bob:npt_request.d1.sshnp$_alice'),
          sealTo: 'd1.sshnp', namespace: 'sshnp');
      final toD2 = await notify(
          c, legacy, AtKey.fromString('$_bob:npt_request.d2.sshnp$_alice'),
          sealTo: 'd2.sshnp', namespace: 'sshnp');

      expect(sealedTo(_bob, 'd1.sshnp'), d1);
      expect(toD1.value, isNot('legacy memo'));
      expect(toD2.value, 'legacy memo');
      expect(legacy.sealed, ['memo']);
      expect(store.keys.where((k) => k.contains('.__ck.sshnp')), isEmpty,
          reason: "bob's sshnp key seals neither");
    });
  });

  group(
      'Given a client at pqReady with the legacy fallback, choosing the '
      'provider per send', () {
    late _Legacy legacy;

    /// Alice's client over [c] at pqReady, writing legacy by default.
    void at(_Client c) {
      legacy = _Legacy();
      atClient = MockAtClient(posture: PqPosture.pqReady);
      when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
      atClient.getPreferences()
        ..namespace = 'sshnp'
        ..allowLegacyCryptoFallback = true
        ..crypto = CryptoConfig(
          defaultProviderId: legacy.id,
          providers: [c.data, c.nskey, legacy],
          keyRing: c.ring,
        );
      context = CryptoContext(atClient: atClient);
      wire(c);
    }

    /// A notification of [key] under [providerId], requiring [sealTo].
    Future<NotifyVerbBuilder> send(AtKey key,
        {String? providerId, String? sealTo}) {
      key.metadata.isEncrypted = true;
      return NotificationRequestTransformer(atClient).transform(
          NotificationParams.forUpdate(key,
              value: 'memo',
              cryptoProviderId: providerId,
              sealToNamespace: sealTo));
    }

    test(
        'At pqReady, a share that requests no provider is sealed with legacy '
        'encryption, and no namespace key is looked up', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'd1.sshnp');
      at(c);

      final builder =
          await send(AtKey.fromString('$_bob:npt_request.d1.sshnp$_alice'));

      expect(builder.value, 'legacy memo');
      expect(c.ring.lookedUp, isEmpty);
    });

    test(
        'A mixed fleet at pqReady: canSealTo picks the namespace-key provider '
        'for one device and legacy for the other', () async {
      final c = _Client(_Ring());
      final d1 = await publish(c.ring, _bob, 'd1.sshnp');
      await publish(c.ring, _bob, 'sshnp');
      at(c);
      final answers = <String, bool>{};
      final sent = <String, NotifyVerbBuilder>{};

      for (final namespace in ['d1.sshnp', 'd2.sshnp']) {
        final sealable = answers[namespace] =
            await CryptoRuntime(atClient).canSealTo(_bob, namespace);
        sent[namespace] = await send(
            AtKey.fromString('$_bob:npt_request.$namespace$_alice'),
            providerId: sealable
                ? symmetricAesGcmCryptoProviderId
                : legacyCryptoProviderId,
            sealTo: sealable ? namespace : null);
      }

      expect(answers, {'d1.sshnp': true, 'd2.sshnp': false});
      expect(sealedTo(_bob, 'd1.sshnp'), d1);
      expect(sent['d1.sshnp']!.value, isNot('legacy memo'));
      expect(sent['d2.sshnp']!.value, 'legacy memo');
      expect(legacy.sealed, ['memo']);
      expect(store.keys.where((k) => k.contains('.__ck.sshnp')), isEmpty,
          reason: "bob's sshnp key seals neither");
    });

    test(
        'At pqReady, a key withdrawn between canSealTo and the send goes with '
        'legacy encryption, with a warning', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'd1.sshnp');
      await publish(c.ring, _bob, 'sshnp');
      at(c);
      expect(await CryptoRuntime(atClient).canSealTo(_bob, 'd1.sshnp'), isTrue);
      c.ring.withdrawn.add('$_bob:d1.sshnp');

      final builder = await send(
          AtKey.fromString('$_bob:npt_request.d1.sshnp$_alice'),
          providerId: symmetricAesGcmCryptoProviderId,
          sealTo: 'd1.sshnp');

      expect(builder.value, 'legacy memo');
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('falling back to legacy encryption') &&
              m.contains('d1.sshnp')),
          isNotEmpty);
      expect(store.keys.where((k) => k.contains('.__ck.sshnp')), isEmpty,
          reason: "never sealed under bob's broader key");
    });
  });

  group(
      "Given alice's client right after opening, before start-up has "
      'published any key', () {
    test("A share does not wait for the writer's start-up", () async {
      final c = _Client(_Ring());
      c.manager.startUpSeeding = StartUpSeeding()..seeding({'todos.demos'});
      final bobs = await publish(c.ring, _bob, 'todos.demos');
      wire(c);
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

      await atOnce(write(c, key));

      expect(stamped(key)['ckNs'], 'todos.demos');
      expect(sealedTo(_bob, 'todos.demos'), bobs);
    });

    test("A notification does not wait for the writer's start-up", () async {
      final c = _Client(_Ring());
      c.manager.startUpSeeding = StartUpSeeding()..seeding({'todos.demos'});
      await publish(c.ring, _bob, 'todos.demos');
      atClient.getPreferences().crypto = CryptoConfig(
        defaultProviderId: c.data.id,
        providers: [c.data, c.nskey],
        keyRing: c.ring,
      );
      wire(c);
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice')
        ..metadata.isEncrypted = true;

      final builder = await atOnce(NotificationRequestTransformer(atClient)
          .transform(NotificationParams.forUpdate(key, value: 'memo')));

      expect(builder.value, isNotNull);
      expect(key.metadata.appMetadata!.additional!['ckNs'], 'todos.demos');
    });
  });

  group('Given a share remembered as finding nothing', () {
    /// A client whose share misses are remembered for [missMemory].
    _Client remembering(Duration missMemory) {
      final ring = _Ring();
      final c =
          _Client.over(ring, NskeyResolver(ring, shareMissMemory: missMemory));
      wire(c);
      return c;
    }

    test(
        'A share requiring a namespace canSealTo has since found is sealed '
        'there', () async {
      final c = remembering(const Duration(seconds: 30));
      final key = AtKey.fromString('$_bob:x.device1.sshnp$_alice');
      await expectLater(write(c, key, sealTo: 'device1.sshnp'),
          refusedNaming(_bob, 'device1.sshnp'));
      final bobs = await publish(c.ring, _bob, 'device1.sshnp');
      configure(c);
      expect(await CryptoRuntime(atClient).canSealTo(_bob, 'device1.sshnp'),
          isTrue);
      final after = AtKey.fromString('$_bob:y.device1.sshnp$_alice');

      await write(c, after, sealTo: 'device1.sshnp');

      expect(stamped(after)['ckNs'], 'device1.sshnp');
      expect(sealedTo(_bob, 'device1.sshnp'), bobs);
    });

    test('Misses older than 30 seconds are forgotten', () async {
      final c = remembering(const Duration(milliseconds: 300));
      for (var i = 0; i < 5; i++) {
        await expectLater(
            write(c, AtKey.fromString('$_bob:x.r$i.todos.demos$_alice')),
            throwsA(isA<NamespaceKeyUnavailableException>()));
      }
      expect(c.manager.resolver.shareMissesHeld, 7,
          reason: 'r0..r4, todos.demos and demos');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      await expectLater(
          write(c, AtKey.fromString('$_bob:y.todos.demos$_alice')),
          throwsA(isA<NamespaceKeyUnavailableException>()));

      expect(c.manager.resolver.shareMissesHeld, 2,
          reason: 'only the levels this share found missing');
    });

    test('A full miss is remembered for 30 seconds', () async {
      final c = remembering(const Duration(milliseconds: 300));
      await expectLater(
          write(c, AtKey.fromString('$_bob:x.todos.demos$_alice')),
          refusedNaming(_bob, 'todos.demos'));
      final bobs = await publish(c.ring, _bob, 'todos.demos');
      c.ring.lookedUp.clear();

      await expectLater(
          write(c, AtKey.fromString('$_bob:y.todos.demos$_alice')),
          refusedNaming(_bob, 'todos.demos'));
      expect(c.ring.lookedUp, isEmpty, reason: 'decided with no lookup');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final key = AtKey.fromString('$_bob:z.todos.demos$_alice');
      await write(c, key);

      expect(stamped(key)['ckNs'], 'todos.demos',
          reason: 'the first share after the window walks again');
      expect(sealedTo(_bob, 'todos.demos'), bobs);
    });

    test('A miss at a narrower level is remembered for 30 seconds', () async {
      final c = remembering(const Duration(seconds: 30));
      await publish(c.ring, _bob, 'demos');
      await write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      await publish(c.ring, _bob, 'todos.demos');
      c.ring.lookedUp.clear();
      final key = AtKey.fromString('$_bob:y.todos.demos$_alice');

      await write(c, key);

      expect(stamped(key)['ckNs'], 'demos');
      expect(c.ring.lookedUp.where((l) => l == '$_bob:todos.demos'), isEmpty);
    });

    test(
        'A narrower key published inside the miss window is used by the first '
        'write after it', () async {
      final c = remembering(const Duration(milliseconds: 300));
      await publish(c.ring, _bob, 'demos');
      await write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      final bobs = await publish(c.ring, _bob, 'todos.demos');
      final inside = AtKey.fromString('$_bob:y.todos.demos$_alice');
      await write(c, inside);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      c.ring.lookedUp.clear();
      final after = AtKey.fromString('$_bob:z.todos.demos$_alice');

      await write(c, after);

      expect(stamped(inside)['ckNs'], 'demos');
      expect(stamped(after)['ckNs'], 'todos.demos');
      expect(sealedTo(_bob, 'todos.demos'), bobs);
      expect(c.ring.lookedUp, contains('$_bob:todos.demos'));
    });

    test('canSealTo asks afresh, whatever a share found missing', () async {
      final c = remembering(const Duration(seconds: 30));
      await publish(c.ring, _bob, 'sshnp');
      await write(c, AtKey.fromString('$_bob:x.device1.sshnp$_alice'));
      await publish(c.ring, _bob, 'device1.sshnp');
      atClient.getPreferences().crypto = CryptoConfig(
        defaultProviderId: c.data.id,
        providers: [c.data, c.nskey],
        keyRing: c.ring,
      );
      c.ring.lookedUp.clear();

      expect(await CryptoRuntime(atClient).canSealTo(_bob, 'device1.sshnp'),
          isTrue);
      expect(c.ring.lookedUp, ['$_bob:device1.sshnp']);
    });
  });

  test(
      'The windows are 15 minutes for a found key, 15 more out of reach, and '
      '30 seconds for a miss', () {
    final ring = PublishedNskeyKeyRing(atClient);

    expect(ring.advertisementTtl, const Duration(minutes: 15));
    expect(ring.advertisementStaleGrace, const Duration(minutes: 15));
    expect(NskeyResolver(ring).shareMissMemory, const Duration(seconds: 30));
  });

  group('Given bob advertising keys for demos and todos.demos', () {
    test('A required namespace is sealed to without walking', () async {
      final c = _Client(_Ring());
      final bobs = await publish(c.ring, _bob, 'demos');
      await publish(c.ring, _bob, 'todos.demos');
      wire(c);
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

      await write(c, key, sealTo: 'demos');

      expect(stamped(key)['ckNs'], 'demos');
      expect(sealedTo(_bob, 'demos'), bobs);
      expect(c.ring.lookedUp.where((l) => l.startsWith('$_bob:')).toSet(),
          {'$_bob:demos'});
    });
  });

  test(
      'A required namespace the recipient has not advertised refuses at '
      'pqActive', () async {
    final c = _Client(_Ring());
    await publish(c.ring, _bob, 'demos');
    wire(c);

    await expectLater(
        write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'),
            sealTo: 'todos.demos'),
        refusedNaming(_bob, 'todos.demos'));
    expect(store.keys.where((k) => k.contains('.__ck.demos')), isEmpty);
    expect(c.ring.lookedUp.where((l) => l.startsWith('$_bob:')),
        ['$_bob:todos.demos'],
        reason: 'demos is not looked up');
  });

  test(
      "A required namespace the key's name does not end with is refused "
      'before any lookup', () async {
    final c = _Client(_Ring());
    wire(c);

    await expectLater(
        write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'),
            sealTo: 'other.app'),
        throwsArgumentError);
    expect(c.ring.lookedUp, isEmpty);
  });

  test("A required namespace on a write to the writer's own atSign is refused",
      () async {
    final c = _Client(_Ring());
    await hold(c.ring, _alice, 'todos.demos');
    wire(c);

    await expectLater(
        write(c, AtKey.fromString('x.todos.demos$_alice'),
            sealTo: 'todos.demos'),
        throwsArgumentError);
  });

  group('Given a required namespace that has nothing to seal', () {
    test(
        'when the provider seals to no namespace key, then the write is '
        'refused', () async {
      await expectLater(
          CryptoRuntime(atClient).prepareForPut(
              AtKey.fromString('$_bob:x.todos.demos$_alice'),
              legacyCryptoProviderId,
              sealToNamespace: 'todos.demos'),
          throwsArgumentError);
    });

    test(
        'when the content-key provider has no manager to seal with, then the '
        'write is refused', () async {
      await expectLater(
          SymmetricAesGcmProvider(cache: ContentKeyCache()).prepareForWrite(
              context, AtKey.fromString('$_bob:x.todos.demos$_alice'),
              sealToNamespace: 'todos.demos'),
          throwsArgumentError);
    });

    test('when the key has no namespace, then the write is refused', () async {
      final c = _Client(_Ring());
      wire(c);

      await expectLater(
          c.data.prepareForWrite(
              context,
              AtKey()
                ..key = 'x'
                ..sharedBy = _alice
                ..sharedWith = _bob,
              sealToNamespace: 'todos.demos'),
          throwsArgumentError);
    });

    test('when a notification carries no value, then it is refused', () async {
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice')
        ..metadata.isEncrypted = true;

      await expectLater(
          NotificationRequestTransformer(atClient).transform(
              NotificationParams.forUpdate(key,
                  sealToNamespace: 'todos.demos')),
          throwsArgumentError);
    });
  });

  group('canSealTo', () {
    test('canSealTo never throws, whatever asking fails with', () async {
      final client = MockAtClient(posture: PqPosture.pqActive);
      when(() => client.getCurrentAtSign()).thenReturn(_alice);
      client.getPreferences().crypto =
          CryptoConfig.nskey(keyRing: _FailingRing(StateError('broken ring')));

      expect(await CryptoRuntime(client).canSealTo(_bob, 'device1.sshnp'),
          isFalse);
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('$_bob:device1.sshnp') && m.contains('broken ring')),
          hasLength(1));
    });

    /// A client whose namespace keys come from [ring].
    MockAtClient over(NskeyKeyRing ring) {
      final client = MockAtClient(posture: PqPosture.pqActive);
      when(() => client.getCurrentAtSign()).thenReturn(_alice);
      client.getPreferences().crypto = CryptoConfig.nskey(keyRing: ring);
      return client;
    }

    test('A program can ask whether it can seal to a namespace', () async {
      final ring = _Ring();
      await publish(ring, _bob, 'device1.sshnp');

      expect(await CryptoRuntime(over(ring)).canSealTo(_bob, 'device1.sshnp'),
          isTrue);
    });

    test('A broader key does not answer canSealTo', () async {
      final ring = _Ring();
      await publish(ring, _bob, 'sshnp');

      expect(await CryptoRuntime(over(ring)).canSealTo(_bob, 'device1.sshnp'),
          isFalse);
      expect(ring.lookedUp, ['$_bob:device1.sshnp']);
    });

    test(
        "canSealTo answers false, with a warning, when the recipient's "
        'atServer cannot be reached', () async {
      final client = MockAtClient(posture: PqPosture.pqActive);
      when(() => client.getCurrentAtSign()).thenReturn(_alice);
      when(() => client.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenThrow(SecondaryConnectException('atServer unreachable'));
      client.getPreferences().crypto =
          CryptoConfig.nskey(keyRing: PublishedNskeyKeyRing(client));

      expect(await CryptoRuntime(client).canSealTo(_bob, 'device1.sshnp'),
          isFalse);
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('$_bob:device1.sshnp') &&
              m.contains('asking for its key there failed') &&
              m.contains('atServer unreachable')),
          hasLength(1),
          reason: 'the cause is named, so an outage is told from a recipient '
              'that advertises nothing');
    });
  });

  group("Given the writer's own copy of a share's content key", () {
    /// What alice's copy of the content key shared with bob in [ckNs] names,
    /// or null when she wrote none.
    Map<String, dynamic>? copyIn(String ckNs) {
      final copies = store.entries.where((e) =>
          !e.key.startsWith('$_bob:') && e.key.contains('.__ck.$ckNs$_alice'));
      return copies.isEmpty
          ? null
          : copies.single.value.key.metadata.appMetadata!.additional;
    }

    void neverMinted() => verifyNever(
        () => atClient.ensureReachable(any(), timeout: any(named: 'timeout')));

    test("The writer's copy is sealed to her key at her own level", () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'notes.todos.demos');
      await hold(c.ring, _alice, 'demos');
      final hers = await hold(c.ring, _alice, 'todos.demos');
      configure(c);
      wire(c);
      final key = AtKey.fromString('$_bob:x.notes.todos.demos$_alice');

      await write(c, key);

      expect(stamped(key)['ckNs'], 'notes.todos.demos');
      expect(
          copyIn('notes.todos.demos'),
          allOf(containsPair('nskeyKid', hers),
              containsPair('ns', 'todos.demos')),
          reason: 'named at bob\'s level, sealed at hers');
      neverMinted();
    });

    test(
        'Before her start-up has published her key, a share goes without her '
        'copy, with a warning', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'todos.demos');
      c.manager.startUpSeeding = StartUpSeeding()..seeding({'todos.demos'});
      configure(c);
      wire(c);
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

      await atOnce(write(c, key));

      expect(stamped(key)['ckNs'], 'todos.demos');
      expect(copyIn('todos.demos'), isNull);
      neverMinted();
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('has not yet published') &&
              m.contains(stamped(key)['ckKid'] as String)),
          hasLength(1));
    });

    test(
        'The first share after her start-up publishes her key gets a fresh '
        'content key with her copy', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'todos.demos');
      final seeding = StartUpSeeding()..seeding({'todos.demos'});
      c.manager.startUpSeeding = seeding;
      configure(c);
      wire(c);
      final before = AtKey.fromString('$_bob:x.todos.demos$_alice');
      await write(c, before);
      final hers = await hold(c.ring, _alice, 'todos.demos');
      seeding.finish();
      final after = AtKey.fromString('$_bob:y.todos.demos$_alice');

      await write(c, after);

      expect(stamped(after)['ckKid'], isNot(stamped(before)['ckKid']));
      expect(copyIn('todos.demos'), containsPair('nskeyKid', hers));
      neverMinted();
    });

    test('A value no namespace she holds covers gets no copy, with a warning',
        () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'other.app');
      await hold(c.ring, _alice, 'todos.demos');
      configure(c);
      wire(c);
      final key = AtKey.fromString('$_bob:x.other.app$_alice');

      await write(c, key);

      expect(copyIn('other.app'), isNull);
      neverMinted();
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('No namespace key $_alice holds covers x.other.app')),
          hasLength(1));
    });

    test(
        "Bob's key at a level broader than hers leaves the share without her "
        'copy, with a warning', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'demos');
      await hold(c.ring, _alice, 'todos.demos');
      configure(c);
      wire(c);
      final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

      await write(c, key);

      expect(stamped(key)['ckNs'], 'demos');
      expect(copyIn('demos'), isNull);
      neverMinted();
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('is at demos, broader than') &&
              m.contains('own level todos.demos')),
          hasLength(1));
    });

    test(
        "A share stamps the value's own namespace, not the level it walked from",
        () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'todos.demos');
      wire(c);
      final key = AtKey()
        ..key = 'memo.17936'
        ..namespace = 'todos.demos'
        ..sharedBy = _alice
        ..sharedWith = _bob;

      await write(c, key);

      expect(stamped(key)['ns'], 'todos.demos');
      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });

  test('A level containing a label that starts with __ is never sealed to',
      () async {
    final c = _Client(_Ring());
    await publish(c.ring, _bob, '__rpcs.app');
    final bobs = await publish(c.ring, _bob, 'app');
    wire(c);
    final key = AtKey.fromString('$_bob:x.__rpcs.app$_alice');

    await write(c, key);

    expect(stamped(key)['ckNs'], 'app');
    expect(sealedTo(_bob, 'app'), bobs);
    expect(c.ring.lookedUp, isNot(contains('$_bob:__rpcs.app')));
  });

  group('Given an RPC between alice and bob, who hold the same grants', () {
    late List<Object> failures;

    /// Alice's RPC in namespace `base` over [c], whose notifications are
    /// sealed as the notification service seals them, each failure recorded.
    AtRpc rpcOver(_Client c) {
      configure(c);
      wire(c);
      failures = [];
      final notifications = MockNotificationService();
      when(() => atClient.notificationService).thenReturn(notifications);
      when(() => atClient.isStopped).thenReturn(false);
      when(() => notifications.notify(any(),
          checkForFinalDeliveryStatus:
              any(named: 'checkForFinalDeliveryStatus'),
          waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
          onSuccess: any(named: 'onSuccess'),
          onError: any(named: 'onError'),
          onSentToSecondary:
              any(named: 'onSentToSecondary'))).thenAnswer((inv) async {
        try {
          await NotificationRequestTransformer(atClient)
              .transform(inv.positionalArguments.first as NotificationParams);
        } catch (e) {
          failures.add(e);
          rethrow;
        }
        return NotificationResult();
      });
      return AtRpc(
          atClient: atClient,
          baseNameSpace: 'base',
          domainNameSpace: 'dom',
          callbacks: _RpcCallbacks(),
          allowList: {},
          isClient: false,
          isServer: true)
        ..maxSendAttempts = 1;
    }

    Iterable<String> rpcLevelsLookedUp(_Client c) =>
        c.ring.lookedUp.where((l) => l.contains('__rpcs'));

    test(
        "An RPC request is sealed to its responder's key at the base namespace",
        () async {
      final c = _Client(_Ring());
      final bobs = await publish(c.ring, _bob, 'base');
      final rpc = rpcOver(c);

      await rpc.sendRequest(toAtSign: _bob, request: AtRpcReq.create({'q': 1}));

      expect(failures, isEmpty);
      expect(sealedTo(_bob, 'base'), bobs);
      expect(rpcLevelsLookedUp(c), isEmpty);
    });

    test(
        "An RPC response is sealed to its requester's key at the base namespace",
        () async {
      final c = _Client(_Ring());
      final bobs = await publish(c.ring, _bob, 'base');
      final rpc = rpcOver(c);
      final request = AtRpcReq.create({'q': 1});

      await rpc.sendResponse(
          AtNotification.empty()
            ..from = _bob
            ..metadata = (Metadata()
              ..appMetadata =
                  AppMetadata(providerId: symmetricAesGcmCryptoProviderId)),
          request,
          AtRpcResp.ack(request: request));

      expect(failures, isEmpty);
      expect(sealedTo(_bob, 'base'), bobs);
      expect(rpcLevelsLookedUp(c), isEmpty);
    });

    test(
        'An RPC to a peer advertising nothing is refused, or goes legacy where '
        'allowed, never under a broader key', () async {
      final c = _Client(_Ring());
      await publish(c.ring, _bob, 'dom.__rpcs.base');
      final rpc = rpcOver(c);

      await rpc.sendRequest(toAtSign: _bob, request: AtRpcReq.create({'q': 1}));

      expect(failures.single, isA<NamespaceKeyUnavailableException>(),
          reason: 'refused at pqActive');
      expect(store.keys.where((k) => k.startsWith('$_bob:')), isEmpty,
          reason: 'and nothing is sealed under the key at dom.__rpcs.base');

      final legacy = _Legacy();
      atClient = MockAtClient(
          posture:
              PqPosture.pqActive.copyWith(disallowLegacyEncryption: false));
      when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
      context = CryptoContext(atClient: atClient);
      final fallback = rpcOver(c);
      atClient.getPreferences()
        ..allowLegacyCryptoFallback = true
        ..crypto = CryptoConfig(
          defaultProviderId: c.data.id,
          providers: [c.data, c.nskey, legacy],
          keyRing: c.ring,
        );

      await fallback.sendRequest(
          toAtSign: _bob, request: AtRpcReq.create({'q': 2}));

      expect(failures, isEmpty);
      expect(legacy.sealed, hasLength(1),
          reason: 'sent with legacy encryption');
      expect(store.keys.where((k) => k.startsWith('$_bob:')), isEmpty);
    });
  });

  group("Given bob's keys published by his enrollments", () {
    late _Network net;

    setUp(() async {
      net = _Network();
      await _publishFrom(net, _bob, 'bob-demos', 'demos');
      await _publishFrom(net, _bob, 'bob-todos', 'todos.demos');
    });

    /// Alice's client over [net], with her key ring keeping a found key for
    /// [ttl] and, out of reach, [grace] more.
    ({_PeerClient client, PublishedNskeyKeyRing ring, CkManager manager})
        aliceOver({
      Duration ttl = const Duration(minutes: 15),
      Duration grace = const Duration(minutes: 15),
      Duration shareMiss = const Duration(seconds: 30),
    }) {
      final alice = _peer(_alice, 'alice-1', net);
      final ring = PublishedNskeyKeyRing(alice,
          privateFiling: NskeyPrivateFiling(
              keysIo: alice.atKeysIo as WrittenAtKeysIo, atSign: _alice),
          advertisementTtl: ttl,
          advertisementStaleGrace: grace);
      final manager = CkManager(
          cache: ContentKeyCache(),
          keyRing: ring,
          resolver: NskeyResolver(ring,
              shareMissMemory: shareMiss,
              sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024]));
      alice.getPreferences()!.crypto = CryptoConfig(
          defaultProviderId: symmetricAesGcmCryptoProviderId,
          providers: [
            SymmetricAesGcmProvider(cache: manager.cache, ckManager: manager),
            NskeyProvider(keyRing: ring, cache: manager.cache),
          ],
          keyRing: ring);
      return (client: alice, ring: ring, manager: manager);
    }

    /// The pre-pass of a share of [key] by [alice].
    Future<({String namespace, String ckNs})?> shareBy(
            ({
              _PeerClient client,
              PublishedNskeyKeyRing ring,
              CkManager manager
            }) alice,
            AtKey key) =>
        alice.manager.ensureCurrent(CryptoContext(atClient: alice.client), key);

    /// A pre-pass of a share of [key] by a fresh client of alice's.
    Future<({String namespace, String ckNs})?> share(AtKey key) =>
        shareBy(aliceOver(), key);

    test('A found advertisement is served from the cache for 15 minutes',
        () async {
      final alice = aliceOver();
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net
        ..batches.clear()
        ..reads.clear();

      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));

      expect(chosen?.ckNs, 'todos.demos');
      expect(net.batches, isEmpty);
      expect(net.reads.where((k) => k.endsWith(_bob)), isEmpty);
    });

    test(
        'An advertisement the re-fetch cannot refresh is served for 15 minutes '
        'more, then not at all', () async {
      final alice = aliceOver(ttl: Duration.zero);
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net.reachable = false;
      logs.records.clear();

      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));

      expect(chosen?.ckNs, 'todos.demos');
      expect(
          logs.at('WARNING').where((m) => m.contains(
              'Sealing to the advertised nskey for $_bob:todos.demos')),
          isNotEmpty);
      final past = aliceOver(ttl: Duration.zero, grace: Duration.zero);
      net.reachable = true;
      await shareBy(past, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net.reachable = false;
      await expectLater(
          shareBy(past, AtKey.fromString('$_bob:y.todos.demos$_alice')),
          throwsA(isA<SecondaryConnectException>()),
          reason: 'that failure, and not one the legacy fallback catches');
    });

    test(
        'A key fresh when the walk began seals the share, even if it expires '
        'during the lookup', () async {
      net.records.remove('public:__nskey.todos.demos$_bob');
      final alice = aliceOver(
          ttl: const Duration(milliseconds: 400), shareMiss: Duration.zero);
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      net
        ..batchDelay = const Duration(milliseconds: 400)
        ..batches.clear();

      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));

      expect(
          net.batches,
          [
            ['plookup:bypassCache:true:all:__nskey.todos.demos$_bob']
          ],
          reason: 'only the level not fresh is asked');
      expect(chosen?.ckNs, 'demos');
    });

    test(
        'A batch entry that is not a record fails that level, which seals to '
        'its cached key within the stale grace', () async {
      final alice = aliceOver(ttl: Duration.zero);
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net.malformed.add('public:__nskey.todos.demos$_bob');
      logs.records.clear();

      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));

      expect(chosen?.ckNs, 'todos.demos');
      expect(
          logs.at('WARNING').where((m) => m.contains(
              'Sealing to the advertised nskey for $_bob:todos.demos')),
          isNotEmpty);
    });

    test(
        'A share by a client with no atServer connection throws an AtException',
        () async {
      final alice = aliceOver();
      when(() => alice.client.getRemoteSecondary()).thenReturn(null);

      await expectLater(
          shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice')),
          throwsA(isA<AtException>()));
    });

    test('A not-found ends a cached advertisement at once', () async {
      final alice = aliceOver(ttl: Duration.zero);
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net.records.remove('public:__nskey.todos.demos$_bob');

      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));

      expect(chosen?.ckNs, 'demos');
      net.reachable = false;
      await expectLater(
          NskeyResolver(alice.ring, sealsToKeyAlgorithms: const [
            SecretSharingAlgos.mlKem1024
          ]).resolveShare(_bob, AtKey.fromString('$_bob:z.todos.demos$_alice')),
          throwsA(isA<SecondaryConnectException>()),
          reason: 'the key its atServer no longer had is gone from the cache, '
              'so its stale grace cannot bring it back');
    });

    test('A cached broader advertisement does not satisfy a required namespace',
        () async {
      net.records.remove('public:__nskey.todos.demos$_bob');
      final alice = aliceOver();
      await shareBy(alice, AtKey.fromString('$_bob:y.demos$_alice'));
      net.batches.clear();

      await expectLater(
          alice.manager.ensureCurrent(CryptoContext(atClient: alice.client),
              AtKey.fromString('$_bob:x.todos.demos$_alice'),
              sealToNamespace: 'todos.demos'),
          throwsA(isA<NamespaceKeyUnavailableException>()
              .having((e) => e.namespace, 'namespace', 'todos.demos')));
      expect(net.batches, [
        ['plookup:bypassCache:true:all:__nskey.todos.demos$_bob']
      ]);
    });

    test('A batch entry that fails for any reason but not-found stops the walk',
        () async {
      net.failing['public:__nskey.todos.demos$_bob'] = 'AT0011';
      final alice = aliceOver();

      await expectLater(
          shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice')),
          throwsA(isA<AtException>()
              .having((e) => e.message, 'message', contains('AT0011'))));
      net.failing.clear();
      net.batches.clear();
      final chosen =
          await shareBy(alice, AtKey.fromString('$_bob:y.todos.demos$_alice'));
      expect(chosen?.ckNs, 'todos.demos',
          reason: 'todos.demos was not remembered as a miss');
      expect(net.batches.single.first,
          'plookup:bypassCache:true:all:__nskey.todos.demos$_bob');
    });

    test('canSealTo answers from a key a share found', () async {
      final alice = aliceOver();
      await shareBy(alice, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      net
        ..batches.clear()
        ..reads.clear();

      expect(await CryptoRuntime(alice.client).canSealTo(_bob, 'todos.demos'),
          isTrue);
      expect(net.batches, isEmpty);
      expect(net.reads.where((k) => k.endsWith(_bob)), isEmpty);
    });

    test("The recipient's levels are looked up in one batch", () async {
      net.reads.clear();

      final chosen = await share(
          AtKey.fromString('$_bob:note1.t42.notes.todos.demos$_alice'));

      expect(chosen?.ckNs, 'todos.demos');
      expect(net.batches, [
        [
          for (final level in [
            't42.notes.todos.demos',
            'notes.todos.demos',
            'todos.demos',
            'demos',
          ])
            'plookup:bypassCache:true:all:__nskey.$level$_bob',
        ]
      ]);
      expect(net.reads.where((k) => k.contains('__nskey.') && k.endsWith(_bob)),
          isEmpty,
          reason: 'no level of bob\'s is looked up on its own');
      expect(net.reads.where((k) => k.contains('_apsk.') && k.endsWith(_bob)),
          [_apskKey(_bob, 'bob-todos')],
          reason: 'only the advertisement sealed to is verified');
    });

    test('A more specific advertisement that does not verify refuses the share',
        () async {
      final key = 'public:__nskey.todos.demos$_bob';
      final envelope = jsonDecode(net.records[key]!) as Map<String, dynamic>;
      final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(envelope['payload'] as String)));
      envelope['payload'] =
          base64Url.encode(utf8.encode('$payload ')).replaceAll('=', '');
      net.records[key] = jsonEncode(envelope);

      await expectLater(share(AtKey.fromString('$_bob:x.todos.demos$_alice')),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test(
        'canSealTo answers false, with a warning, when the advertisement does '
        'not verify', () async {
      final key = 'public:__nskey.todos.demos$_bob';
      final envelope = jsonDecode(net.records[key]!) as Map<String, dynamic>;
      final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(envelope['payload'] as String)));
      envelope['payload'] =
          base64Url.encode(utf8.encode('$payload ')).replaceAll('=', '');
      net.records[key] = jsonEncode(envelope);
      final alice = aliceOver();
      logs.records.clear();

      expect(await CryptoRuntime(alice.client).canSealTo(_bob, 'todos.demos'),
          isFalse);
      expect(
          logs.at('WARNING').where((m) =>
              m.contains('$_bob:todos.demos') &&
              m.contains('because its advertisement there does not verify')),
          hasLength(1));
      net.reads.clear();
      expect(await CryptoRuntime(alice.client).canSealTo(_bob, 'todos.demos'),
          isFalse);
      expect(net.reads, contains(key),
          reason: 'nothing was cached, so it is asked again');
    });
  });
}
