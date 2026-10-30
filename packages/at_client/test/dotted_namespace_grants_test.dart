import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/storage/memory/memory_at_key_value_store.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    hide AtNotification;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/memory_sync_queue.dart';
import 'test_utils/recorded_logs.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockSyncService extends Mock implements SyncService {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockEnrollmentService extends Mock implements EnrollmentService {}

class _MockPairwiseSecretSharing extends Mock
    implements PairwiseSecretSharing {}

/// Answers every advertisement with [advertisement], so a test reaches what
/// follows a successful read without an `_apsk` to verify against.
class _AcceptingVerifier implements AdvertisedKeyVerifier {
  final NskeyAdvertisement advertisement;

  _AcceptingVerifier(this.advertisement);

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async =>
      advertisement;
}

/// A dotted namespace grant in the client's local access check, which decides
/// as the atServer's own check does.
///
/// Catalogue: features/at_client/dotted_namespace_grants.feature
void main() {
  const atSign = '@bob';
  const enrollmentId = 'enroll-1';
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn(level: 'finer');
    registerFallbackValue(AtKey());
    registerFallbackValue(SyncVerbBuilder());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(Duration.zero);
  });

  setUp(logs.records.clear);

  /// A client of [atSign] whose enrollment holds [grants], over a local store
  /// of its own. Its local `get` runs through the local secondary, as the
  /// client's does for a key of its own atSign.
  ({_MockAtClient client, MemoryAtKeyValueStore store, LocalSecondary local})
      enrolled(Map<String, String> grants) {
    final client = _MockAtClient();
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.atSign).thenReturn(atSign.toAtsign());
    when(() => client.enrollmentId).thenReturn(enrollmentId);
    when(() => client.syncService).thenReturn(_MockSyncService());
    final store = MemoryAtKeyValueStore(atSign);
    final local = LocalSecondary(client,
        syncQueue: memorySyncQueue(), keyStore: store, onEvent: (_) {});
    local.enrollment = Enrollment()
      ..enrollmentId = enrollmentId
      ..namespace = grants;
    when(() => client.getLocalSecondary()).thenReturn(local);
    return (client: client, store: store, local: local);
  }

  Future<String?> llookup(LocalSecondary local, String key) =>
      local.executeVerb(LLookupVerbBuilder()..atKey = AtKey.fromString(key));

  Future<String?> put(LocalSecondary local, String key) =>
      local.executeVerb(UpdateVerbBuilder()
        ..atKey = AtKey.fromString(key)
        ..value = 'written');

  /// A sync service for [client] whose atServer hands back [entries] on the
  /// pull, each an update.
  Future<SyncServiceImpl> syncPulling(
      _MockAtClient client, List<String> entries) async {
    final remote = _MockRemoteSecondary();
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream<AtNotification>.empty());
    when(() => client.notificationService).thenReturn(notifications);
    when(() => client.getPreferences()).thenReturn(AtClientPreference());
    when(() => client.get(any()))
        .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
    when(() => client.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => remote.executeVerb(any()))
        .thenAnswer((_) async => 'data:${jsonEncode([
                  for (final (i, atKey) in entries.indexed)
                    {
                      'atKey': atKey,
                      'value': 'synced',
                      'metadata': null,
                      'commitId': i + 1,
                      'operation': '+',
                    }
                ])}');
    return await SyncServiceImpl.create(client,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  }

  test(
      'An enrollment granted a dotted namespace puts, gets, deletes and lists '
      'its keys locally', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    const key = 'x.cmp.rotation@bob';

    await c.local.executeVerb(UpdateVerbBuilder()
      ..atKey = AtKey.fromString(key)
      ..value = 'written');
    expect(await llookup(c.local, key), 'data:written');
    expect(jsonDecode((await c.local.executeVerb(ScanVerbBuilder()))!),
        contains(key));
    await c.local
        .executeVerb(DeleteVerbBuilder()..atKey = AtKey.fromString(key));
    expect(await c.store.exists(key), isFalse,
        reason: 'the delete reached the store');
  });

  test('Sync stores a record under a dotted grant locally', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    const key = 'y.cmp.rotation@bob';
    final sync = await syncPulling(c.client, [key]);

    await sync.syncInternal(1, SyncRequest()..result = SyncResult(),
        localCommitIdBeforeSync: -1);

    expect(await c.store.exists(key), isTrue,
        reason: 'the atServer sent this record to an enrollment its grant '
            'covers, so it is stored on this device');
  });

  test('A dotted grant does not cover a key beside or above it', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    for (final key in ['x.rotation@bob', 'x.other.rotation@bob']) {
      await c.store.put(key, AtData()..data = 'held');
      await expectLater(
          llookup(c.local, key), throwsA(isA<UnAuthorizedException>()),
          reason: 'cmp.rotation does not cover $key');
    }
    // NOTE: the control. The same grant reads a key it does cover, so the
    // refusals above are about the keys and not the fixture.
    await c.store.put('x.cmp.rotation@bob', AtData()..data = 'held');
    expect(await llookup(c.local, 'x.cmp.rotation@bob'), 'data:held');
  });

  test('A grant covers a key in a dotted namespace beneath it', () async {
    final c = enrolled({'rotation': 'rw'});
    await c.store.put('x.cmp.rotation@bob', AtData()..data = 'held');

    expect(await llookup(c.local, 'x.cmp.rotation@bob'), 'data:held');
  });

  test(
      'PQ seeding reads the advertisement of a dotted namespace it was '
      'granted', () async {
    const namespace = 'cmp.rotation';
    final c = enrolled({namespace: 'rw'});
    when(() => c.client.get(any())).thenAnswer((inv) async {
      final atKey = inv.positionalArguments.single as AtKey;
      final answer = await llookup(c.local, atKey.toString());
      return AtValue()..value = answer!.replaceFirst('data:', '');
    });
    final enrollments = _MockEnrollmentService();
    when(() => enrollments.fetchEnrollmentRequests()).thenAnswer((_) async => [
          Enrollment()
            ..enrollmentId = enrollmentId
            ..namespace = {namespace: 'rw'}
        ]);
    when(() => c.client.enrollmentService).thenReturn(enrollments);
    when(() => c.client.getPreferences()).thenReturn(AtClientPreference());
    await c.store.put('public:__nskey.$namespace$atSign',
        AtData()..data = 'the published advertisement');

    final pair = await XWingKeyPair.generate();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final ring = PublishedNskeyKeyRing(c.client,
        privateFiling: NskeyPrivateFiling(keysIo: io, atSign: atSign),
        verifier: _AcceptingVerifier(NskeyAdvertisement.single(
          publicKey: pair.publicKeyBytes,
          alg: SecretSharingAlgos.xWing,
          suites:
              SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
        )));
    final sharing = _MockPairwiseSecretSharing();
    when(() => sharing.requestSecretsFromNamespace(any(),
        names: any(named: 'names'))).thenAnswer((_) async => 1);
    when(() =>
            sharing.waitForSecret(any(), any(), timeout: any(named: 'timeout')))
        .thenAnswer((_) => Completer<Secret>().future);

    final asked = await NskeySeeding(
            atClient: c.client, ring: ring, privateFiling: ring.privateFiling)
        .requestMissingPrivates(sharing);

    expect(
        logs.at('WARNING').where((m) => m.contains('insufficient privilege')),
        isEmpty);
    expect(asked, {namespace},
        reason: 'the advertisement was read, so the private it names was '
            'asked for');
  });

  test(
      'A record sync refuses is logged at warning, naming the key and the '
      'enrollment', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    const refused = 'x.other.rotation@bob';
    final sync = await syncPulling(c.client, [refused]);

    await sync.syncInternal(1, SyncRequest()..result = SyncResult(),
        localCommitIdBeforeSync: -1);

    expect(await c.store.exists(refused), isFalse,
        reason: 'the premise: the grant does not cover this record');
    expect(logs.at('WARNING').where((m) => m.contains(refused)),
        allOf(isNotEmpty, everyElement(contains(enrollmentId))),
        reason: 'a record this device drops is named at warning, with the '
            'enrollment whose grants refused it');
  });

  test(
      'A public key outside the grant is read locally, as the atServer '
      'allows, and not written', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    const key = 'public:x.other@bob';
    await c.store.put(key, AtData()..data = 'held');

    expect(await llookup(c.local, key), 'data:held');
    await expectLater(put(c.local, key), throwsA(isA<UnAuthorizedException>()),
        reason: 'the atServer checks a write to a public key like any other');
  });

  group('Given an enrollment granted {cmp.rotation: rw}', () {
    test(
        'when it lists its keys, then a public key outside its grant is listed',
        () async {
      final c = enrolled({'cmp.rotation': 'rw'});
      await c.store.put('public:x.other@bob', AtData()..data = 'held');
      await c.store.put('x.other@bob', AtData()..data = 'held');

      final listed =
          jsonDecode((await c.local.executeVerb(ScanVerbBuilder()))!);
      expect(listed, contains('public:x.other@bob'));
      expect(listed, isNot(contains('x.other@bob')),
          reason: 'the control: the same key, not public, is still checked');
    });

    test('when it deletes a public key outside its grant, then it is refused',
        () async {
      final c = enrolled({'cmp.rotation': 'rw'});
      await c.store.put('public:x.other@bob', AtData()..data = 'held');

      await expectLater(
          c.local.executeVerb(DeleteVerbBuilder()
            ..atKey = AtKey.fromString('public:x.other@bob')),
          throwsA(isA<UnAuthorizedException>()));
    });
  });

  test(
      'A grant naming the namespace wins over * locally, even when it gives '
      'less', () async {
    final c = enrolled({'*': 'rw', 'wavi': 'r'});

    await expectLater(
        put(c.local, 'x.wavi@bob'), throwsA(isA<UnAuthorizedException>()),
        reason: 'wavi gives read only, and the atServer refuses the write');
    // NOTE: the control. `*` still answers for a namespace no grant names.
    expect(await put(c.local, 'x.buzz@bob'), isNotNull);
  });
}
