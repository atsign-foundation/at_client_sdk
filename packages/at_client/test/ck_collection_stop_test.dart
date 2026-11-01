import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/memory_sync_queue.dart';

class _Store extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final Map<String, AtData> data = {};

  @override
  Future<Stream<String>> getKeys({String? regex}) async => Stream.fromIterable(
      data.keys.where((k) => regex == null || RegExp(regex).hasMatch(k)));

  @override
  Future<AtData?> get(String key) async => data[key];

  @override
  Future<AtMetaData?> getMeta(String key) async => data[key]?.metaData;
}

class _FakeListener extends Fake implements SyncProgressListener {}

/// The collection a content-key replacement queues behind it, when the client
/// stops before sync has caught up.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair aliceNskey;
  late XWingKeyPair bobNskey;

  setUpAll(() async {
    aliceNskey = await XWingKeyPair.generate();
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
    registerFallbackValue(_FakeListener());
  });

  AtKey shared() => AtKey()
    ..key = 'pact'
    ..namespace = namespace
    ..sharedWith = bob
    ..sharedBy = alice
    ..metadata = Metadata();

  /// Replaces the content key shared with [bob] while sync has not caught up,
  /// the client stopping as it is asked, after which its sync-service getter
  /// throws what [stopped] makes. Returns every error that escaped to the
  /// zone.
  Future<List<Object>> replaceThenStop(Object Function() stopped) async {
    final escaped = <Object>[];
    final done = Completer<void>();
    unawaited(runZonedGuarded(() async {
      final ring = InMemoryNskeyKeyRing()
        ..seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes)
        ..seedKeypair(alice, namespace,
            publicKey: aliceNskey.publicKeyBytes,
            privateKey: aliceNskey.privateKeyBytes);
      final config = CryptoConfig.nskey(
          keyRing: ring,
          ckRotationPolicy: rotateCkAfterOneWeek,
          supersededCkGrace: Duration.zero);
      final client = MockAtClient();
      client.getPreferences().crypto = config;
      when(() => client.getCurrentAtSign()).thenReturn(alice);
      when(() => client.enrollmentId).thenReturn('enr-1');
      final store = _Store();
      when(() => client.getLocalSecondary()).thenReturn(LocalSecondary(client,
          syncQueue: memorySyncQueue(), keyStore: store));
      final sync = MockSyncService();
      var isStopped = false;
      when(() => client.syncService).thenAnswer((_) {
        if (isStopped) throw stopped();
        return sync;
      });
      when(() => sync.isInSync()).thenAnswer((_) async => true);
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
        }
        store.data[key.toString()] = AtData()
          ..data = value
          ..metaData = AtMetaData.fromCommonsMetadata(key.metadata, alice);
        return true;
      });
      final manager = (config.lookup(symmetricAesGcmCryptoProviderId)
              as SymmetricAesGcmProvider)
          .ckManager!;
      final context = CryptoContext(atClient: client);

      await manager.ensureCurrent(context, shared());
      when(() => sync.isInSync()).thenAnswer((_) async {
        isStopped = true;
        return false;
      });
      await manager.rotateContentKey(context, shared());
      await manager.idle;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      done.complete();
    }, (error, stack) => escaped.add(error)));
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return escaped;
  }

  test(
      'A client stopped while its collection waits for sync lets no error '
      'escape', () async {
    expect(
        await replaceThenStop(() => StoppedException(
            'the client for $alice has stopped, so it cannot hand out its '
            'sync service')),
        isEmpty);
  });

  test('A sync service not yet set lets no error escape either', () async {
    expect(
        await replaceThenStop(
            () => StateError('SyncService has not yet been set')),
        isEmpty);
  });
}
