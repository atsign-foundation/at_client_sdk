import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/crypto_storage.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockSyncService extends Mock implements SyncService {}

class FakeSyncProgressListener extends Fake implements SyncProgressListener {}

void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;
  late MockAtClient atClient;
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeSyncProgressListener());
  });

  setUp(() {
    remoteData = {};
    atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    final syncService = MockSyncService();
    when(() => atClient.syncService).thenReturn(syncService);
    when(() => syncService.addProgressListener(any())).thenReturn(null);
    when(() => syncService.removeProgressListener(any())).thenReturn(null);
    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn('enroll-a');
    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      remoteData[inv.positionalArguments[0].toString()] =
          inv.positionalArguments[1];
      return Future.value(true);
    });
    AtValue lookup(inv) {
      final v = remoteData[inv.positionalArguments[0].toString()];
      if (v == null) {
        throw AtKeyNotFoundException('${inv.positionalArguments[0]} not found');
      }
      return AtValue()..value = v;
    }

    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) => Future.value(lookup(inv)));
    when(() => atClient.get(any()))
        .thenAnswer((inv) => Future.value(lookup(inv)));
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return Future.value(
          remoteData.keys.where(regex.hasMatch).map(AtKey.fromString).toList());
    });
    when(() => atClient.delete(any())).thenAnswer((inv) {
      remoteData.remove(inv.positionalArguments[0].toString());
      return Future.value(true);
    });
    // Seed a deterministic identity on the shared instance the provider will
    // obtain via forClient(), so its registerClient()/startListening succeed.
    AtClientSecretSharing.forClient(atClient).loadClientKeys = () async =>
        PersistedClientKeys(clientId: 'cid-a', xWingSeed: base64Encode(seed));
  });

  tearDown(() => AtClientSecretSharing.forClient(atClient).stopListening());

  CryptoContext ctx() => CryptoContext(
        atClient: atClient,
        currentAtSign: atSign.toAtsign(),
        atChops: atClient.atChops,
        storage: CryptoSecondaryStorage(atClient),
      );

  AtKey selfKey(String key, {String namespace = 'myapp'}) => AtKey()
    ..key = key
    ..namespace = namespace
    ..sharedBy = atSign;

  group('GroupCryptoProvider', () {
    test('id is group', () {
      expect(GroupCryptoProvider().id, 'group');
    });

    test(
        'encrypt → decrypt round-trips a self key; AppMetadata carries the '
        'group coordinates', () async {
      final provider = GroupCryptoProvider();
      await provider.initialize(ctx());
      final atKey = selfKey('phone');

      final enc = await provider
          .encrypt(CryptoEncryptRequest(atKey: atKey, plaintext: 'hello'));
      expect(enc.isEncrypted, isTrue);
      expect(enc.metadata.providerId, 'group');
      final a = enc.metadata.additional!;
      expect(a['scope'], 'myapp');
      expect(a['epoch'], 1);
      expect(a['enc'], 'aes-256-gcm');
      expect(a['kid'], isA<String>());
      expect(a['iv'], isA<String>());
      // ciphertext is not the plaintext
      expect(enc.ciphertext, isNot('hello'));

      final dec = await provider.decrypt(CryptoDecryptRequest(
        atKey: atKey,
        ciphertext: enc.ciphertext,
        metadata: enc.metadata,
      ));
      expect(dec.plaintext, 'hello');
    });

    test('decrypt tolerates a string epoch (wire round-trip)', () async {
      final provider = GroupCryptoProvider();
      await provider.initialize(ctx());
      final atKey = selfKey('phone');
      final enc = await provider
          .encrypt(CryptoEncryptRequest(atKey: atKey, plaintext: 'wire'));
      final a = enc.metadata.additional!;
      // Simulate the wire turning the int epoch into a string.
      final wireMeta = AppMetadata(providerId: 'group', additional: {
        ...a,
        'epoch': a['epoch'].toString(),
      });
      final dec = await provider.decrypt(CryptoDecryptRequest(
          atKey: atKey, ciphertext: enc.ciphertext, metadata: wireMeta));
      expect(dec.plaintext, 'wire');
    });

    test('encrypt rejects a key shared with another atSign (v1 self-only)',
        () async {
      final provider = GroupCryptoProvider();
      await provider.initialize(ctx());
      final shared = AtKey()
        ..key = 'phone'
        ..namespace = 'myapp'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      await expectLater(
        provider.encrypt(CryptoEncryptRequest(atKey: shared, plaintext: 'x')),
        throwsA(isA<StateError>()),
      );
    });

    test('encrypt requires a namespace', () async {
      final provider = GroupCryptoProvider();
      await provider.initialize(ctx());
      final noNs = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign;
      await expectLater(
        provider.encrypt(CryptoEncryptRequest(atKey: noNs, plaintext: 'x')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
