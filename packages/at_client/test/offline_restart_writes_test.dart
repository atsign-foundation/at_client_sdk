import 'dart:convert';

import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show AtClientEnvelopeSigner, WithdrawnSigningKeyException;
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show verifiedAdvertisementKey;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

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
  late final NskeyPrivateFiling filing =
      NskeyPrivateFiling(keysIo: keys, atSign: _atSign);

  _Device(this.enrollmentId, this.server)
      : apkam = pkamKeyPairFor(_atSign, enrollmentId),
        keys = keysHoldingApkam(
            _atSign, enrollmentId, pkamKeyPairFor(_atSign, enrollmentId));

  /// A fresh start: a new client, so nothing it cached survives, and a new
  /// ring, over this device's keys and local storage.
  PublishedNskeyKeyRing start() =>
      PublishedNskeyKeyRing(_clientFor(this), privateFiling: filing);

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
  when(() => c.enrollmentId).thenReturn(d.enrollmentId);
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
      d.local[builder.atKey.toString()] = builder.value as String;
      return 'data:1';
    }
    if (builder is LLookupVerbBuilder) {
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
