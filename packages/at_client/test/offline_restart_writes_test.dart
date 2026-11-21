import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole;
import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show AtClientEnvelopeSigner, WithdrawnSigningKeyException;
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show verifiedAdvertisementKey;
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/crypto/nskey/start_up_seeding.dart';
import 'package:at_client/src/crypto/nskey/verified_advertisement_record.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/envelope_signers.dart' show resigned;
import 'test_utils/fake_at_server.dart';
import 'test_utils/mocks.dart'
    show MockAtLookUp, MockLocalSecondary, MockRemoteSecondary;
import 'test_utils/ml_dsa_keyfile.dart' show keysHoldingApkam;
import 'test_utils/no_keys.dart';
import 'test_utils/nskey_generation.dart';
import 'test_utils/test_keypairs.dart';
import 'test_utils/transport.dart';

class _Client extends Mock implements AtClient {}

const _atSign = '@alice';
const _namespace = 'notes.my_app';
const _alg = SecretSharingAlgos.mlKem1024;

/// The atSign's atServer: its public records, and whether it can be reached.
class _AtServer {
  bool reachable = true;
  final Map<String, String> records = {};

  /// What the atServer answers a read of each key with instead of its value.
  final Map<String, Exception> refusing = {};

  void requireReachable() {
    if (!reachable) throw SecondaryConnectException('atServer unreachable');
  }
}

/// One client of `@alice`: its enrollment's keys, its local storage, and the
/// ring a start of it builds.
class _Device {
  final String enrollmentId;
  final _AtServer server;
  final RsaKeyPair apkam;
  final InMemoryAtKeysIo keys;
  final Map<String, String> local = {};

  /// Every read a client of this device made, `remote` or `local`, in order.
  final List<String> asked = [];

  /// The client the device minted and published with.
  late final _Client client = _clientFor(this);

  /// The filing of the latest start, since each start builds its own.
  late NskeyPrivateFiling filing =
      NskeyPrivateFiling(keysIo: keys, atSign: _atSign);

  /// Whether this is the primary enrollment on the atSign's root keys, whose
  /// client names no enrollment id.
  final bool onRootKeys;

  /// Whether the client has stopped, so its local reads say so.
  bool stopped = false;

  /// Awaited before each local write lands, with the key it writes.
  Future<void> Function(String key)? beforeLocalWrite;

  _Device(this.enrollmentId, this.server, {this.onRootKeys = false})
      : apkam = pkamKeyPairFor(_atSign, enrollmentId),
        keys = keysHoldingApkam(_atSign, onRootKeys ? null : enrollmentId,
            pkamKeyPairFor(_atSign, enrollmentId));

  /// A fresh start: a new client, so nothing it cached survives, and a new
  /// filing and ring, over this device's keys and local storage.
  PublishedNskeyKeyRing start(
      {Duration advertisementTtl = const Duration(minutes: 15)}) {
    filing = NskeyPrivateFiling(keysIo: keys, atSign: _atSign);
    return PublishedNskeyKeyRing(_clientFor(this),
        privateFiling: filing, advertisementTtl: advertisementTtl);
  }

  /// Publishes this enrollment's `_apsk` on the atServer.
  Future<void> publishApsk() async {
    server.records[_apskKey(enrollmentId)] =
        await AtClientEnvelopeSigner(client).publicSigningKeyValue;
  }

  /// What sync does for the advertisement: local storage takes the atServer's.
  void syncAdvertisement() =>
      local[_advertisementKey] = server.records[_advertisementKey]!;

  String get recordKey => verifiedAdvertisementKey(
          sharedBy: _atSign, enrollmentId: enrollmentId, namespace: _namespace)
      .toString();
}

String _apskKey(String enrollmentId) =>
    'public:_apsk.$enrollmentId.a.__e$_atSign';

final String _advertisementKey = 'public:__nskey.$_namespace$_atSign';

_Client _clientFor(_Device d) {
  final c = _Client();
  final remote = MockRemoteSecondary();
  final lookUp = MockAtLookUp();
  final local = MockLocalSecondary();
  when(() => c.getCurrentAtSign()).thenReturn(_atSign);
  when(() => c.enrollmentId).thenReturn(d.onRootKeys ? null : d.enrollmentId);
  when(() => c.atKeysIo).thenReturn(d.keys);
  when(() => c.getPreferences())
      .thenReturn(AtClientPreference(keyEstablishmentAlgorithms: const [_alg]));
  when(() => c.dataEvents).thenAnswer((_) => const Stream<DataEvent>.empty());
  when(() => c.getLocalSecondary()).thenReturn(local);
  when(() => c.getRemoteSecondary()).thenReturn(remote);
  when(() => remote.atLookUp).thenReturn(lookUp);
  when(() => local.getPkamPublicKey())
      .thenAnswer((_) async => d.apkam.atPublicKey.publicKey);
  when(() => local.getPkamPrivateKey())
      .thenAnswer((_) async => d.apkam.atPrivateKey.privateKey);
  when(() => local.executeVerb(any(),
      cameFromServer: any(named: 'cameFromServer'))).thenAnswer((inv) async {
    final builder = inv.positionalArguments.first;
    if (builder is UpdateVerbBuilder) {
      await d.beforeLocalWrite?.call(builder.atKey.toString());
      d.local[builder.atKey.toString()] = builder.value as String;
      return 'data:1';
    }
    if (builder is LLookupVerbBuilder) {
      if (d.stopped) throw StoppedException('the client has stopped');
      final value = d.local[builder.atKey.toString()];
      if (value == null) throw KeyNotFoundException('${builder.atKey}');
      return 'data:$value';
    }
    return 'data:null';
  });
  when(() => remote.executeCommand(any(that: startsWith('enroll:listns')),
      auth: any(named: 'auth'))).thenAnswer((_) async {
    d.server.requireReachable();
    return 'data:[]';
  });
  when(() => remote.executeVerb(any())).thenAnswer((inv) async {
    d.server.requireReachable();
    final builder = inv.positionalArguments.first;
    if (builder is UpdateVerbBuilder) {
      d.server.records[builder.atKey.toString()] = builder.value as String;
    }
    return 'data:1';
  });
  when(() => c.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions')))
      .thenAnswer((_) async => true);
  when(() => c.get(any(), getRequestOptions: any(named: 'getRequestOptions')))
      .thenAnswer((inv) async {
    final key = (inv.positionalArguments.first as AtKey).toString();
    final options =
        inv.namedArguments[#getRequestOptions] as GetRequestOptions?;
    if (options?.useRemoteAtServer == true) {
      d.asked.add('remote $key');
      d.server.requireReachable();
      final refusal = d.server.refusing[key];
      if (refusal != null) throw refusal;
      final value = d.server.records[key];
      if (value == null) throw AtKeyNotFoundException(key);
      return AtValue()..value = value;
    }
    d.asked.add('local $key');
    final value = d.local[key];
    if (value == null) throw AtKeyNotFoundException(key);
    return AtValue()..value = value;
  });
  return c;
}

/// Catalogue: features/at_client/offline_restart_writes.feature
void main() {
  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(UpdateVerbBuilder());
  });

  final namesTheKey = isA<SecondaryConnectException>().having(
      (e) => e.message,
      'message',
      allOf(contains(_advertisementKey), contains('atServer unreachable')));

  /// A device that minted the namespace key online, then started once more
  /// online and verified it, as every start does.
  Future<({_Device device, String kid})> mintedAndVerified() async {
    final server = _AtServer();
    final d = _Device('enroll-self', server);
    await d.publishApsk();
    final kid = (await d.start().mintAndPublish(_namespace)).nskeyKid;
    await d.start().currentPublic(_atSign, _namespace);
    return (device: d, kid: kid);
  }

  /// A write of [key] by a fresh start of [device], through a content-key
  /// pre-pass wired as start-up wires it: the rotation policy is asked, and
  /// [seeding] is what writes wait on. Returns the namespace it sealed at.
  Future<String?> writeAsStarted(_Device device, AtKey key,
      {StartUpSeeding? seeding}) async {
    final client = _clientFor(device);
    final ring = PublishedNskeyKeyRing(client, privateFiling: device.filing);
    final cache = ContentKeyCache();
    final rotation = NskeySeeding(
        atClient: client, ring: ring, privateFiling: device.filing);
    final manager = CkManager(cache: cache, keyRing: ring)
      ..startUpSeeding = seeding
      ..rotateOwnNamespaceKeyIfAsked =
          ((namespace) => rotation.rotateIfPolicyAsks(_atSign, namespace));
    final nskey = NskeyProvider(keyRing: ring, cache: cache, keyAlgo: _alg);
    final data = SymmetricAesGcmProvider(cache: cache, ckManager: manager);
    final context = CryptoContext(atClient: client);
    when(() => client.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      if (options?.shouldEncrypt != false) {
        await nskey.encrypt(context, inv.positionalArguments[0] as AtKey,
            inv.positionalArguments[1] as String);
      }
      return true;
    });
    await data.prepareForWrite(context, key);
    await data.encrypt(context, key, 'memo');
    return key.metadata.appMetadata?.additional?['ckNs'] as String?;
  }

  AtKey selfKey(String namespace) => AtKey()
    ..key = 'x'
    ..namespace = namespace
    ..sharedBy = _atSign;

  /// The namespace keys [device]'s local record names, or null with no record.
  List<Object?>? recordHeld(_Device device) {
    final stored = device.local[device.recordKey];
    if (stored == null) return null;
    final record =
        SignedEnvelope.fromJson(jsonDecode(stored) as Map).payload as Map;
    return record['held'] as List<Object?>;
  }

  /// Lets the event loop run until [done] holds, for at most [within].
  Future<void> settle(bool Function() done,
      {Duration within = const Duration(seconds: 2)}) async {
    final deadline = DateTime.now().add(within);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Files a fresh generation of N's namespace key through [device]'s latest
  /// start, as a conveyance does, and returns its kid.
  Future<String> fileNext(_Device device,
      {String namespace = _namespace}) async {
    final next = await nskeyGeneration(_alg);
    await device.filing.file(Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}${next.kid}',
        value: base64Encode(next.seed)));
    return next.kid;
  }

  test(
      'A client restarted with no atServer writes in a namespace it verified '
      'and holds the key for', () async {
    final (:device, :kid) = await mintedAndVerified();
    device.server.reachable = false;

    final restarted = device.start();
    final advertised = await restarted.currentPublic(_atSign, _namespace);

    expect(advertised?.nskeyKid, kid);
    expect(await restarted.privateHalf(_atSign, _namespace, kid), isNotNull,
        reason: 'the write seals to the key this client holds');
    expect(await writeAsStarted(device, selfKey(_namespace)), _namespace,
        reason: 'the write itself succeeds, its pre-pass asking the rotation '
            'policy as start-up wires it');
  });

  test(
      'The primary enrollment, restarted with no atServer, writes in a '
      'namespace it verified and holds the key for', () async {
    final device = _Device('primary', _AtServer(), onRootKeys: true);
    await device.publishApsk();
    final kid = (await device.start().mintAndPublish(_namespace)).nskeyKid;
    await device.start().currentPublic(_atSign, _namespace);
    device.server.reachable = false;

    expect((await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
        kid);
  });

  test(
      'An advertisement verified under one spelling of its namespace is '
      'vouched for under another', () async {
    final device = _Device('enroll-self', _AtServer());
    await device.publishApsk();
    await device.start().mintAndPublish(_namespace);
    final record =
        VerifiedAdvertisementRecord(device.client, filing: device.filing);
    final payload = device.server.records[_advertisementKey]!;
    await record.remember(_namespace.toUpperCase(), payload);

    expect(await record.vouchesFor(_namespace, payload), isTrue);
  });

  test(
      "Every envelope at_client signs names its signer's Atsign: its "
      'verified-advertisement record through VerifiedAdvertisementRecord.'
      'remember', () async {
    final device = _Device('enroll-self', _AtServer());
    await device.publishApsk();
    await device.start().mintAndPublish(_namespace);
    final record =
        VerifiedAdvertisementRecord(device.client, filing: device.filing);
    device.local.remove(device.recordKey);

    await record.remember(
        _namespace, device.server.records[_advertisementKey]!);

    final envelope = SignedEnvelope.fromJson(
        jsonDecode(device.local[device.recordKey]!) as Map);
    expect(envelope.signatures.map((s) => s.iss).toSet(), {_atSign});
    expect(envelope.signerAtSign, _atSign);
  });

  test(
      'A record that names another Atsign does not vouch for the '
      'advertisement', () async {
    final device = _Device('enroll-self', _AtServer());
    await device.publishApsk();
    await device.start().mintAndPublish(_namespace);
    final record =
        VerifiedAdvertisementRecord(device.client, filing: device.filing);
    final payload = device.server.records[_advertisementKey]!;
    await record.remember(_namespace, payload);
    final keys = await AtClientEnvelopeSigner(device.client).signingKeys;
    final stored = SignedEnvelope.fromJson(
        jsonDecode(device.local[device.recordKey]!) as Map);

    SignedEnvelope namingAs(String atSign) =>
        resigned(stored, keys, (header) => header..['iss'] = atSign);

    device.local[device.recordKey] = jsonEncode(namingAs('@bob').toJson());
    expect(await record.vouchesFor(_namespace, payload), isFalse);

    device.local[device.recordKey] = jsonEncode(namingAs(_atSign).toJson());
    expect(await record.vouchesFor(_namespace, payload), isTrue,
        reason: 'the control: re-signed naming its own Atsign, it vouches');
  });

  test('A client stopped as it reads its local record says so', () async {
    final (:device, kid: _) = await mintedAndVerified();
    device.server.reachable = false;
    device.stopped = true;

    await expectLater(device.start().currentPublic(_atSign, _namespace),
        throwsA(isA<StoppedException>()));
  });

  group(
      'Given a client that verified its own advertisement online without '
      'reading it through currentPublic', () {
    test(
        'when it minted the key, then after a restart with no atServer it '
        'writes in that namespace', () async {
      final device = _Device('enroll-self', _AtServer());
      await device.publishApsk();
      final kid = (await device.start().mintAndPublish(_namespace)).nskeyKid;
      device.server.reachable = false;

      expect(
          (await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
          kid);
    });

    test(
        'when its start-up read the key with publishedAdvertisement, then '
        'after a restart with no atServer it writes in that namespace',
        () async {
      final device = _Device('enroll-self', _AtServer());
      await device.publishApsk();
      final kid = (await device.start().mintAndPublish(_namespace)).nskeyKid;
      device.local.remove(device.recordKey);
      await device.start().publishedAdvertisement(_atSign, _namespace);
      device.server.reachable = false;

      expect(
          (await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
          kid);
    });
  });

  test('A write the offline restart already allows does not wait', () async {
    final (:device, kid: _) = await mintedAndVerified();
    device.server.reachable = false;

    expect(
        await writeAsStarted(device, selfKey(_namespace),
                seeding: StartUpSeeding()..seeding({_namespace}))
            .timeout(const Duration(seconds: 1),
                onTimeout: () => fail('it waited for start-up')),
        _namespace);
  });

  test('A grant spelt in capitals covers its key', () async {
    final server = _AtServer();
    final device = _Device('enroll-self', server);
    await device.publishApsk();
    await device.start().mintAndPublish('Todos.Demos');

    expect(
        await writeAsStarted(device, AtKey.fromString('x.todos.demos$_atSign')),
        'todos.demos',
        reason: 'the private start-up filed under the grant\'s spelling is the '
            'one the write seals its content key to');
  });

  test(
      'The same holds when another enrollment of the atSign published the '
      'namespace key', () async {
    final server = _AtServer();
    final sibling = _Device('enroll-sibling', server);
    await sibling.publishApsk();
    final kid = (await sibling.start().mintAndPublish(_namespace)).nskeyKid;
    final self = _Device('enroll-self', server);
    await self.publishApsk();
    self.syncAdvertisement();
    final seed = await sibling.filing.readSeed(_namespace, kid);
    expect(
        await self.filing.file(Secret(
            namespace: _namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
            value: base64Encode(seed!.bytes))),
        isTrue,
        reason: 'the premise: the private was conveyed to this client');
    await self.start().currentPublic(_atSign, _namespace);
    server.reachable = false;

    final advertised = await self.start().currentPublic(_atSign, _namespace);

    expect(advertised?.nskeyKid, kid);
  });

  test(
      'A namespace key conveyed after the online verification counts at an '
      'offline restart', () async {
    final server = _AtServer();
    final sibling = _Device('enroll-sibling', server);
    await sibling.publishApsk();
    final kid = (await sibling.start().mintAndPublish(_namespace)).nskeyKid;
    final self = _Device('enroll-self', server);
    await self.publishApsk();
    self.syncAdvertisement();
    await self.start().currentPublic(_atSign, _namespace);
    expect(recordHeld(self), isEmpty,
        reason: 'the premise: it verified holding none of N\'s keys');
    final seed = await sibling.filing.readSeed(_namespace, kid);
    expect(
        await self.filing.file(Secret(
            namespace: _namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
            value: base64Encode(seed!.bytes))),
        isTrue,
        reason: 'the premise: the key was conveyed in the same session');
    await settle(() => recordHeld(self)?.contains(kid) ?? false);
    server.reachable = false;

    expect(
        (await self.start().currentPublic(_atSign, _namespace))?.nskeyKid, kid,
        reason: 'the record was rewritten for the bytes verified online, '
            'naming the key conveyed after');
  });

  test(
      'Given a client that accepted its advertisement offline on its record, '
      'when a namespace key is filed for N, then the record is not rewritten',
      () async {
    final (:device, kid: _) = await mintedAndVerified();
    final before = device.local[device.recordKey];
    device.server.reachable = false;
    await device.start().currentPublic(_atSign, _namespace);

    await fileNext(device);
    await settle(() => device.local[device.recordKey] != before,
        within: const Duration(milliseconds: 500));

    expect(device.local[device.recordKey], before,
        reason: 'a record is written only for bytes verified online in this '
            'session');
  });

  test(
      'Given a namespace key filed after the online verification, when it is '
      'retired, then a restart with no atServer still accepts N', () async {
    final (:device, :kid) = await mintedAndVerified();
    await device.start().currentPublic(_atSign, _namespace);
    final next = await fileNext(device);
    await settle(() => recordHeld(device)?.contains(next) ?? false);
    expect(recordHeld(device), contains(next),
        reason: 'the premise: the record names the key filed after');

    await device.filing.retire(_namespace, [next]);
    device.server.reachable = false;

    expect((await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
        kid,
        reason: 'a retired key is still filed, so the record names it');
  });

  test(
      'Given a namespace key filed under N spelt in capitals after the online '
      'verification, when the client restarts with no atServer, then it '
      'accepts N', () async {
    final (:device, :kid) = await mintedAndVerified();
    await device.start().currentPublic(_atSign, _namespace);
    final next = await fileNext(device, namespace: _namespace.toUpperCase());
    await settle(() => recordHeld(device)?.contains(next) ?? false);
    device.server.reachable = false;

    expect((await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
        kid);
  });

  test(
      'Given a namespace key filed for a namespace below N after the online '
      'verification, when the client restarts with no atServer, then it '
      'accepts N', () async {
    final (:device, :kid) = await mintedAndVerified();
    await device.start().currentPublic(_atSign, _namespace);
    await fileNext(device, namespace: '$_namespace.v2');
    await settle(() => false, within: const Duration(milliseconds: 300));
    device.server.reachable = false;

    expect((await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
        kid,
        reason: 'a key below N is not one of N\'s');
  });

  test(
      'Given bytes verified online that local storage has since replaced, and '
      'that were accepted offline on their own record, when a namespace key is '
      'filed for N, then the record is not rewritten for the earlier bytes',
      () async {
    final (:device, kid: _) = await mintedAndVerified();
    final session = device.start(advertisementTtl: Duration.zero);
    final sessionFiling = device.filing;
    await session.currentPublic(_atSign, _namespace);
    final sibling = _Device('enroll-sibling', device.server);
    await sibling.publishApsk();
    final (:rotated, superseded: _) = await sibling.start().rotate(_namespace);
    device.syncAdvertisement();
    await device.start().currentPublic(_atSign, _namespace);
    final before = device.local[device.recordKey];
    device.filing = sessionFiling;
    device.server.reachable = false;
    device.asked.clear();
    expect((await session.currentPublic(_atSign, _namespace))?.nskeyKid,
        rotated.nskeyKid,
        reason: 'the premise: the session accepted the newer bytes');
    expect(device.asked, contains('remote ${_apskKey('enroll-sibling')}'),
        reason: 'the premise: it could not verify them, so its record vouched '
            'for them');

    await fileNext(device);
    await settle(() => device.local[device.recordKey] != before,
        within: const Duration(milliseconds: 500));

    expect(device.local[device.recordKey], before,
        reason: 'a record is written only for the bytes the session verified '
            'online, and those are no longer what it holds');
  });

  test(
      'Given a client stopped after verifying N online, when a namespace key '
      'is filed for N, then nothing is raised', () async {
    final (:device, kid: _) = await mintedAndVerified();
    await device.start().currentPublic(_atSign, _namespace);
    device.stopped = true;

    await fileNext(device);
    await settle(() => false, within: const Duration(milliseconds: 300));
  });

  test(
      'Given two namespace keys filed one after the other, when the record '
      'for the first is still being written, then the record names both',
      () async {
    final (:device, kid: _) = await mintedAndVerified();
    await device.start().currentPublic(_atSign, _namespace);
    final release = Completer<void>();
    var held = false;
    device.beforeLocalWrite = (key) async {
      if (key != device.recordKey || held) return;
      held = true;
      await release.future;
    };

    final first = await fileNext(device);
    await settle(() => held);
    expect(held, isTrue, reason: 'the premise: the first rewrite is writing');
    final second = await fileNext(device);
    await settle(() => recordHeld(device)?.contains(second) ?? false,
        within: const Duration(milliseconds: 200));
    release.complete();
    await settle(() =>
        (recordHeld(device)?.contains(first) ?? false) &&
        (recordHeld(device)?.contains(second) ?? false));

    expect(recordHeld(device), containsAll([first, second]),
        reason: 'each rewrite reads the keys filed when it runs, after the '
            'one before it has written');
  });

  test('An advertisement altered in local storage is not accepted offline',
      () async {
    final (:device, kid: _) = await mintedAndVerified();
    final stored = jsonDecode(device.local[_advertisementKey]!) as Map;
    final payload = stored['payload'] as String;
    stored['payload'] =
        '${payload.substring(0, 10)}${payload[10] == 'A' ? 'B' : 'A'}'
        '${payload.substring(11)}';
    device.local[_advertisementKey] = jsonEncode(stored);
    device.server.reachable = false;

    await expectLater(device.start().currentPublic(_atSign, _namespace),
        throwsA(namesTheKey));
  });

  group(
      'A local record not signed with this client\'s data signing key is '
      'not accepted', () {
    test('altered', () async {
      final (:device, kid: _) = await mintedAndVerified();
      final record = jsonDecode(device.local[device.recordKey]!) as Map;
      final payload = record['payload'] as String;
      record['payload'] =
          '${payload.substring(0, 10)}${payload[10] == 'A' ? 'B' : 'A'}'
          '${payload.substring(11)}';
      device.local[device.recordKey] = jsonEncode(record);
      device.server.reachable = false;

      await expectLater(device.start().currentPublic(_atSign, _namespace),
          throwsA(namesTheKey));
    });

    test('written by another enrollment', () async {
      final (:device, kid: _) = await mintedAndVerified();
      final genuine = jsonDecode(device.local[device.recordKey]!) as Map;
      final other = _Device('enroll-other', device.server);
      final forged = await AtClientEnvelopeSigner(other.client).wrapAndSign(
          SignedEnvelope.fromJson(genuine).payload,
          type: EnvelopeType.verifiedAdvertisement);
      device.local[device.recordKey] = jsonEncode(forged.toJson());
      device.server.reachable = false;

      await expectLater(device.start().currentPublic(_atSign, _namespace),
          throwsA(namesTheKey));
    });
  });

  test(
      'A local record not signed with this client\'s data signing key is '
      'replaced at the next online start', () async {
    final (:device, :kid) = await mintedAndVerified();
    final genuine = jsonDecode(device.local[device.recordKey]!) as Map;
    final other = _Device('enroll-other', device.server);
    final signedByOther = await AtClientEnvelopeSigner(other.client)
        .wrapAndSign(SignedEnvelope.fromJson(genuine).payload,
            type: EnvelopeType.verifiedAdvertisement);
    device.local[device.recordKey] = jsonEncode(signedByOther.toJson());

    await device.start().currentPublic(_atSign, _namespace);
    device.server.reachable = false;

    await expectLater(
        device.start().currentPublic(_atSign, _namespace),
        completion(isA<NskeyAdvertisement>()
            .having((a) => a.nskeyKid, 'nskeyKid', kid)),
        reason: 'the online start wrote a record of its own over it');
  });

  group('Given a local record that cannot be read as a record', () {
    final unreadable = <String, String Function(Map genuine)>{
      'an empty object': (_) => '{}',
      'a payload that is not JSON': (genuine) => jsonEncode({
            ...genuine,
            'payload':
                base64Url.encode(utf8.encode('not json')).replaceAll('=', ''),
          }),
      'text that is not JSON': (_) => 'not json',
    };
    for (final MapEntry(key: shape, value: corrupt) in unreadable.entries) {
      test(
          'when it holds $shape, then the next online start replaces it and a '
          'start with no atServer accepts the key', () async {
        final (:device, :kid) = await mintedAndVerified();
        final genuine = jsonDecode(device.local[device.recordKey]!) as Map;
        device.local[device.recordKey] = corrupt(genuine);

        await device.start().currentPublic(_atSign, _namespace);
        device.server.reachable = false;

        await expectLater(
            device.start().currentPublic(_atSign, _namespace),
            completion(isA<NskeyAdvertisement>()
                .having((a) => a.nskeyKid, 'nskeyKid', kid)));
      });
    }
  });

  test(
      'The record is kept under a local key, naming the atSign, the '
      'namespace, the bytes verified and the keys held', () async {
    final (:device, :kid) = await mintedAndVerified();
    final digest =
        sha256.convert(utf8.encode(device.local[_advertisementKey]!));

    // NOTE: an at-rest format that every later start reads back; the literals
    // change only with a migration of what earlier builds wrote.
    final stored = device
        .local['local:__nskeyverified.notes.my_app.enroll-self.a.__e@alice'];
    expect(stored, isNotNull, reason: 'kept local, so it never syncs');
    expect(
        jsonEncode(SignedEnvelope.fromJson(jsonDecode(stored!) as Map).payload),
        '{"atSign":"@alice","namespace":"notes.my_app","sha256":"$digest",'
        '"held":["$kid"]}');
  });

  test(
      'A restored older copy of local storage is not accepted once a newer '
      'namespace key is held', () async {
    final (:device, kid: _) = await mintedAndVerified();
    final olderCopy = Map.of(device.local);
    final next = await nskeyGeneration(_alg);
    await device.filing.file(Secret(
        namespace: _namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}${next.kid}',
        value: base64Encode(next.seed)));
    await device.start().currentPublic(_atSign, _namespace);
    device.local
      ..clear()
      ..addAll(olderCopy);
    device.server.reachable = false;

    await expectLater(device.start().currentPublic(_atSign, _namespace),
        throwsA(namesTheKey));
  });

  test(
      'Online, a restart verifies the advertisement against the atServer as '
      'before', () async {
    final (:device, :kid) = await mintedAndVerified();
    final next = await nskeyGeneration(_alg);
    await device.filing.file(Secret(
        namespace: _namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}${next.kid}',
        value: base64Encode(next.seed)));
    device.asked.clear();

    await device.start().currentPublic(_atSign, _namespace);

    expect(device.asked, contains('remote ${_apskKey('enroll-self')}'),
        reason: 'online, the advertisement is verified against the _apsk the '
            'atServer serves');
    device.server.reachable = false;
    expect((await device.start().currentPublic(_atSign, _namespace))?.nskeyKid,
        kid,
        reason: 'the record was refreshed for the namespace keys now held');
  });

  test(
      'A write whose rotation check the atServer answers with an error is '
      'refused with it', () async {
    final (:device, kid: _) = await mintedAndVerified();
    device.syncAdvertisement();
    device.server.refusing[_advertisementKey] =
        AtException('the atServer could not read the record');

    await expectLater(
        writeAsStarted(device, selfKey(_namespace)),
        throwsA(isA<AtException>().having((e) => e.message, 'message',
            contains('could not read the record'))));
  });

  test(
      'A private filed under a namespace spelt in capitals makes a miss in '
      'that namespace ask the other enrollments', () async {
    final server = _AtServer();
    final sibling = _Device('enroll-sibling', server);
    await sibling.publishApsk();
    final kid = (await sibling.start().mintAndPublish(_namespace)).nskeyKid;
    final self = _Device('enroll-self', server);
    final earlier = await nskeyGeneration(_alg);
    await self.keys.update(_atSign.toAtsign(), (keys) {
      keys.addKey(CryptographicMaterial(
          keyId: 'nskey.${_namespace.toUpperCase()}.${earlier.kid}',
          role: CryptographicMaterialRole.privateDecapsulation,
          algorithm: CryptographicMaterialAlgorithm.mlKem1024,
          bytes: AtBytes(earlier.seed),
          createdAt: DateTime.now().toUtc()));
      return true;
    });
    final asked = <String>[];
    final ring = PublishedNskeyKeyRing(_clientFor(self),
        privateFiling: self.filing,
        requestConveyance: (namespace, name) async => asked.add(namespace));

    expect(await ring.privateHalf(_atSign, _namespace, kid), isNull);
    await Future<void>.delayed(Duration.zero);

    expect(asked, [_namespace]);
  });

  test('A refusal from the atServer is not overridden by the local record',
      () async {
    final (:device, kid: _) = await mintedAndVerified();
    final apsk = device.server.records.remove(_apskKey('enroll-self'))!;
    device.server.records['public:_apsk.enroll-self.r.__e$_atSign'] = apsk;

    await expectLater(device.start().currentPublic(_atSign, _namespace),
        throwsA(isA<WithdrawnSigningKeyException>()));
  });

  test(
      'An offline write before the client holds a namespace key names that '
      'key', () async {
    final server = _AtServer();
    final sibling = _Device('enroll-sibling', server);
    await sibling.publishApsk();
    await sibling.start().mintAndPublish(_namespace);
    final self = _Device('enroll-self', server);
    self.syncAdvertisement();
    server.reachable = false;

    await expectLater(
        self.start().currentPublic(_atSign, _namespace), throwsA(namesTheKey));
  });

  test(
      'the record is kept from an application\'s key listing, like the '
      'SDK\'s other reserved records', () async {
    const atSign = '@listing';
    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor(atSign),
        lookUps: FakeAtServer(atSign: atSign).lookUps,
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true));
    addTearDown(client.stop);
    final record = verifiedAdvertisementKey(
        sharedBy: atSign, enrollmentId: 'enroll-x', namespace: 'notes.wavi');
    await client.getLocalSecondary()!.executeVerb(UpdateVerbBuilder()
      ..atKey = record
      ..value = '{}');

    expect(
        await client.getKeys(showHiddenKeys: true), contains(record.toString()),
        reason: 'the premise: a local scan lists the record');
    expect(await client.getKeys(), isNot(contains(record.toString())));
  });
}
