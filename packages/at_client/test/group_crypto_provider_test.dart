import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
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

  CryptoContext ctx() => CryptoContext(atClient: atClient);

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
      final atKey = selfKey('phone');

      final ciphertext = await provider.encrypt(ctx(), atKey, 'hello');
      // The provider stamps appMetadata.additional; the runtime adds
      // providerId + isEncrypted after this returns.
      final meta = atKey.metadata.appMetadata!;
      expect(meta.providerId, 'group');
      final a = meta.additional!;
      expect(a['scope'], 'myapp');
      expect(a['epoch'], 1);
      expect(a['enc'], 'aes-256-gcm');
      expect(a['kid'], isA<String>());
      expect(a['iv'], isA<String>());
      // ciphertext is not the plaintext
      expect(ciphertext, isNot('hello'));

      final plaintext = await provider.decrypt(ctx(), atKey, ciphertext);
      expect(plaintext, 'hello');
    });

    test('decrypt tolerates a string epoch (wire round-trip)', () async {
      final provider = GroupCryptoProvider();
      final atKey = selfKey('phone');
      final ciphertext = await provider.encrypt(ctx(), atKey, 'wire');
      final a = atKey.metadata.appMetadata!.additional!;
      // Simulate the wire turning the int epoch into a string.
      atKey.metadata.appMetadata =
          AppMetadata(providerId: 'group', additional: {
        ...a,
        'epoch': a['epoch'].toString(),
      });
      final plaintext = await provider.decrypt(ctx(), atKey, ciphertext);
      expect(plaintext, 'wire');
    });

    test('encrypt rejects a key shared with another atSign (v1 self-only)',
        () async {
      final provider = GroupCryptoProvider();
      final shared = AtKey()
        ..key = 'phone'
        ..namespace = 'myapp'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      await expectLater(
        provider.encrypt(ctx(), shared, 'x'),
        throwsA(isA<StateError>()),
      );
    });

    test('encrypt requires a namespace', () async {
      final provider = GroupCryptoProvider();
      final noNs = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign;
      await expectLater(
        provider.encrypt(ctx(), noNs, 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
