import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/storage/memory/memory_at_key_value_store.dart';
import 'package:at_client/src/storage/memory/memory_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
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

/// A sync queue store whose deletes wait on [gate] once it is set, and which
/// completes [deleting] when one starts waiting.
class _GatedQueueStore extends MemorySyncQueueStore {
  Completer<void>? gate;
  final deleting = Completer<void>();

  @override
  Future<void> delete(String atKey) async {
    final held = gate;
    if (held != null) {
      if (!deleting.isCompleted) deleting.complete();
      await held.future;
    }
    return super.delete(atKey);
  }
}

/// A dotted namespace grant in the client's local access check, which decides
/// as the atServer's own check does, and sync pushing past a write the
/// atServer refuses for good.
///
/// Catalogue: features/at_client/dotted_namespace_grants.feature
/// Catalogue: features/at_client/sync_push.feature
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
      enrolled(Map<String, String> grants, {AtSyncQueue? syncQueue}) {
    final client = _MockAtClient();
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.atSign).thenReturn(atSign.toAtsign());
    when(() => client.enrollmentId).thenReturn(enrollmentId);
    when(() => client.syncService).thenReturn(_MockSyncService());
    final store = MemoryAtKeyValueStore(atSign);
    final local = LocalSecondary(client,
        syncQueue: syncQueue ?? memorySyncQueue(),
        keyStore: store,
        onEvent: (_) {});
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

  /// A sync service for [client] that pushes one queued entry per batch to an
  /// atServer answering each command as [answer] says: with a commit id,
  /// refusing it with an error code, or with a raw response map. Every
  /// command sent joins [sent].
  Future<SyncServiceImpl> syncPushing(_MockAtClient client, List<String> sent,
      Future<Object> Function(String command) answer) async {
    final remote = _MockRemoteSecondary();
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream<AtNotification>.empty());
    when(() => client.notificationService).thenReturn(notifications);
    when(() => client.getPreferences())
        .thenReturn(AtClientPreference()..syncBatchSize = 1);
    when(() => client.get(any()))
        .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
    when(() => client.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => remote.executeCommand(any(that: startsWith('batch:')),
        auth: any(named: 'auth'))).thenAnswer((inv) async {
      final batch = (inv.positionalArguments.first as String).trim();
      final responses = [];
      for (final request in jsonDecode(batch.substring('batch:'.length))) {
        final command = request['command'] as String;
        sent.add(command);
        final reply = await answer(command);
        responses.add({
          'id': request['id'],
          'response': switch (reply) {
            Map() => reply,
            (commitId: final int commitId, errorCode: null) => {
                'data': '$commitId'
              },
            (commitId: _, errorCode: final String code) => {
                'error_code': code,
                'error_message': 'refused'
              },
            _ => throw ArgumentError('an answer the fake cannot send: $reply'),
          },
        });
      }
      return 'data:${jsonEncode(responses)}';
    });
    final sync = await SyncServiceImpl.create(client,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
    addTearDown(sync.stop);
    return sync;
  }

  /// One round that pulls the atServer's first commit.
  Future<void> pull(SyncServiceImpl sync) =>
      sync.syncInternal(1, SyncRequest()..result = SyncResult(),
          localCommitIdBeforeSync: -1);

  Future<void> push(SyncServiceImpl sync) =>
      sync.syncInternal(-1, SyncRequest()..result = SyncResult(),
          localCommitIdBeforeSync: -1);

  /// A sync service for [client] whose atServer hands back [entries] on the
  /// pull, each an update, or each a delete when [deletes].
  Future<SyncServiceImpl> syncPulling(
      _MockAtClient client, List<String> entries,
      {bool deletes = false}) async {
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
                      'value': deletes ? null : 'synced',
                      'metadata': null,
                      'commitId': i + 1,
                      'operation': deletes ? '-' : '+',
                    }
                ])}');
    final sync = await SyncServiceImpl.create(client,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
    addTearDown(sync.stop);
    return sync;
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

    test(
        'when it reads a key shared with an atSign whose name ends in public, '
        'outside its grant, then it is refused', () async {
      final c = enrolled({'cmp.rotation': 'rw'});
      await c.store.put('@republic:x.other@bob', AtData()..data = 'held');

      await expectLater(llookup(c.local, '@republic:x.other@bob'),
          throwsA(isA<UnAuthorizedException>()),
          reason: 'only a key read as public skips the grant check');
    });

    test('when it reads a cached public key outside its grant, then it may',
        () async {
      final c = enrolled({'cmp.rotation': 'rw'});
      await c.store.put('cached:public:x.other@alice', AtData()..data = 'held');

      expect(
          await llookup(c.local, 'cached:public:x.other@alice'), 'data:held');
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

  test('No local operation reaches a __manage key', () async {
    for (final grants in [
      {'*': 'rw', '__manage': 'rw'},
      {'*': 'rw'},
      {'x.__manage': 'rw'},
    ]) {
      final c = enrolled(grants);
      for (final key in ['k.x.__manage@bob', 'x.__manage@bob']) {
        await c.store.put(key, AtData()..data = 'held');
        await expectLater(
            llookup(c.local, key), throwsA(isA<UnAuthorizedException>()),
            reason: 'a get of $key under $grants');
        await expectLater(
            put(c.local, key), throwsA(isA<UnAuthorizedException>()),
            reason: 'a put of $key under $grants');
      }
    }
  });

  /// The atServer's answer to a command it accepts.
  const accepted = (commitId: 7, errorCode: null);

  /// The atServer's answer to a write it refuses as unauthorized: the code
  /// its batch handler gives an UnAuthorizedException.
  const unauthorized = (commitId: -1, errorCode: 'AT0009');

  test(
      'A queued update the atServer refuses as unauthorized leaves the queue, '
      'and the entries behind it push', () async {
    final c = enrolled({'*': 'rw'});
    await put(c.local, 'k.wavi@bob');
    await put(c.local, 'l.wavi@bob');
    final sent = <String>[];
    final sync = await syncPushing(
        c.client,
        sent,
        (command) async =>
            command.contains('k.wavi@bob') ? unauthorized : accepted);

    await push(sync);

    expect(sent.where((s) => s.contains('l.wavi@bob')), hasLength(1),
        reason: 'the update behind the refused one reaches the atServer in '
            'the same round');
    expect(await c.local.peekSyncQueue(), isEmpty);
    expect(
        logs.at('SEVERE').where((m) => m.contains('k.wavi@bob')),
        allOf(
            isNotEmpty,
            everyElement(allOf(contains('update'), contains(enrollmentId),
                contains('AT0009')))));
    expect(logs.at('WARNING').where((m) => m.contains('k.wavi@bob')), isEmpty,
        reason: 'a dropped write is logged once, at severe');
    expect(await llookup(c.local, 'k.wavi@bob'), 'data:written',
        reason: 'the local copy stays as written');
  });

  test(
      'A queued delete the atServer refuses as unauthorized leaves the queue, '
      'and the entries behind it push', () async {
    final c = enrolled({'*': 'rw'});
    await c.local.executeVerb(
        UpdateVerbBuilder()
          ..atKey = AtKey.fromString('k.wavi@bob')
          ..value = 'held',
        cameFromServer: true);
    await c.local.executeVerb(
        DeleteVerbBuilder()..atKey = AtKey.fromString('k.wavi@bob'));
    await put(c.local, 'l.wavi@bob');
    final sent = <String>[];
    final sync = await syncPushing(
        c.client,
        sent,
        (command) async =>
            command.startsWith('delete:') ? unauthorized : accepted);

    await push(sync);

    expect(sent.where((s) => s.contains('l.wavi@bob')), hasLength(1),
        reason: 'the update behind the refused delete reaches the atServer in '
            'the same round');
    expect(await c.local.peekSyncQueue(), isEmpty);
    expect(
        logs.at('SEVERE').where((m) => m.contains('k.wavi@bob')),
        allOf(
            isNotEmpty,
            everyElement(allOf(contains('delete'), contains(enrollmentId),
                contains('AT0009')))));
    expect(logs.at('WARNING').where((m) => m.contains('k.wavi@bob')), isEmpty,
        reason: 'a dropped write is logged once, at severe');
    expect(await c.store.exists('k.wavi@bob'), isFalse,
        reason: 'the local copy stays as written: deleted');
  });

  test(
      'A queued update refused with any other listed code stays queued and '
      'retries', () async {
    final c = enrolled({'*': 'rw'});
    await put(c.local, 'k.wavi@bob');
    final queued = (await c.local.readSyncQueueEntry('k.wavi@bob'))!.seq;
    final sent = <String>[];
    final sync = await syncPushing(
        c.client, sent, (_) async => (commitId: -1, errorCode: 'AT0002'));

    await push(sync);
    expect((await c.local.readSyncQueueEntry('k.wavi@bob'))?.seq, queued,
        reason: 'a refusal a retry may get past leaves the entry');
    await push(sync);

    expect(sent, hasLength(2), reason: 'it is sent again on the next round');
    expect((await c.local.readSyncQueueEntry('k.wavi@bob'))?.seq, queued);
  });

  group(
      'A queued write refused for good with AT0032, AT0016, AT0022 or AT0003 '
      'leaves the queue', () {
    for (final code in ['AT0032', 'AT0016', 'AT0022', 'AT0003']) {
      test(
          'when the atServer answers $code, then the entry leaves the queue '
          'and the one behind it pushes', () async {
        final c = enrolled({'*': 'rw'});
        await put(c.local, 'k.wavi@bob');
        await put(c.local, 'l.wavi@bob');
        final sent = <String>[];
        final sync = await syncPushing(
            c.client,
            sent,
            (command) async => command.contains('k.wavi@bob')
                ? (commitId: -1, errorCode: code)
                : accepted);

        await push(sync);

        expect(sent.where((s) => s.contains('l.wavi@bob')), hasLength(1),
            reason: 'the update behind the refused one reaches the atServer '
                'in the same round');
        expect(await c.local.peekSyncQueue(), isEmpty);
        expect(
            logs.at('SEVERE').where((m) => m.contains('k.wavi@bob')),
            allOf(
                isNotEmpty,
                everyElement(allOf(contains('update'), contains(enrollmentId),
                    contains(code)))));
        expect(
            logs.at('WARNING').where((m) => m.contains('k.wavi@bob')), isEmpty,
            reason: 'a dropped write is logged once, at severe');
        expect(await llookup(c.local, 'k.wavi@bob'), 'data:written',
            reason: 'the local copy stays as written');
      });
    }
  });

  test(
      'Given a queued update the atServer refuses for good, when sync is '
      'stopped while it is being removed, then the line naming it is still '
      'logged', () async {
    final queueStore = _GatedQueueStore();
    final queue = AtSyncQueue(atSign: atSign);
    unawaited(queue.open(store: queueStore));
    final c = enrolled({'*': 'rw'}, syncQueue: queue);
    await put(c.local, 'k.wavi@bob');
    final sent = <String>[];
    final sync =
        await syncPushing(c.client, sent, (command) async => unauthorized);
    queueStore.gate = Completer<void>();

    final round = push(sync);
    await queueStore.deleting.future;
    final stopping = sync.stop();
    queueStore.gate!.complete();
    await round.then((_) {}, onError: (_) {});
    await stopping;

    expect(await c.local.peekSyncQueue(), isEmpty,
        reason: 'the premise: the removal finished after the stop');
    expect(
        logs
            .at('SEVERE')
            .where((m) => m.contains('k.wavi@bob') && m.contains('AT0009')),
        hasLength(1),
        reason: 'an entry sync removes is named at severe, stop or no stop');
  });

  test(
      'A queued update refused with a code at_commons does not list leaves the '
      'queue at once', () async {
    const unlisted = 'AT0099';
    expect(error_codes.values, isNot(contains(unlisted)),
        reason: 'the premise: at_commons lists no such code');
    final c = enrolled({'*': 'rw'});
    await put(c.local, 'k.wavi@bob');
    await put(c.local, 'l.wavi@bob');
    final sent = <String>[];
    final sync = await syncPushing(
        c.client,
        sent,
        (command) async => command.contains('k.wavi@bob')
            ? (commitId: -1, errorCode: unlisted)
            : accepted);

    await push(sync);

    expect(sent.where((s) => s.contains('k.wavi@bob')), hasLength(1),
        reason: 'it is sent once, and not again in the same round');
    expect(sent.where((s) => s.contains('l.wavi@bob')), hasLength(1),
        reason: 'the update behind it reaches the atServer in the same round');
    expect(await c.local.peekSyncQueue(), isEmpty);
    expect(
        logs.at('SEVERE').where((m) => m.contains('k.wavi@bob')),
        allOf(
            isNotEmpty,
            everyElement(allOf(contains('update'), contains(enrollmentId),
                contains(unlisted)))));
    expect(await llookup(c.local, 'k.wavi@bob'), 'data:written',
        reason: 'the local copy stays as written');
  });

  test(
      'A queued update answered with neither a commit id nor a code stays '
      'queued', () async {
    final c = enrolled({'*': 'rw'});
    await put(c.local, 'k.wavi@bob');
    final queued = (await c.local.readSyncQueueEntry('k.wavi@bob'))!.seq;
    final sent = <String>[];
    final sync = await syncPushing(c.client, sent, (_) async => const {});

    await push(sync);

    expect(sent, hasLength(1), reason: 'the premise: it was sent');
    expect((await c.local.readSyncQueueEntry('k.wavi@bob'))?.seq, queued,
        reason: 'an answer carrying no code is not a refusal for good');
  });

  group('Given an update of K refused for good while in flight', () {
    /// An enrollment that queued K, and a sync service whose atServer refuses
    /// K's first push with [code] once a newer write to K has landed.
    Future<
        ({
          LocalSecondary local,
          SyncServiceImpl sync,
          List<String> sent,
          int first
        })> rewrittenInFlight(String code) async {
      final c = enrolled({'*': 'rw'});
      await put(c.local, 'k.wavi@bob');
      final first = (await c.local.readSyncQueueEntry('k.wavi@bob'))!.seq;
      var inFlight = true;
      final sent = <String>[];
      final sync = await syncPushing(c.client, sent, (command) async {
        if (!inFlight) return accepted;
        inFlight = false;
        await c.local.executeVerb(UpdateVerbBuilder()
          ..atKey = AtKey.fromString('k.wavi@bob')
          ..value = 'newer');
        return (commitId: -1, errorCode: code);
      });
      return (local: c.local, sync: sync, sent: sent, first: first);
    }

    for (final code in ['AT0009', 'AT0032']) {
      test(
          'when a newer write to K lands before the $code answer, then the '
          'newer entry stays queued and pushes next round', () async {
        final k = await rewrittenInFlight(code);

        await push(k.sync);
        expect((await k.local.readSyncQueueEntry('k.wavi@bob'))?.seq,
            greaterThan(k.first),
            reason: 'the newer write was queued after the refused one was '
                'sent, so it is a different entry and must not leave with it');

        await push(k.sync);
        expect(k.sent, hasLength(2));
        expect(k.sent.last, contains('newer'));
        expect(await k.local.peekSyncQueue(), isEmpty);
      });

      test(
          'when a newer write to K lands before the $code answer, then sync '
          'does not report the queue as stalled', () async {
        final k = await rewrittenInFlight(code);

        await push(k.sync);
        expect(
            logs.at('WARNING').where((m) => m.contains('none of the in-batch')),
            isEmpty,
            reason: 'the refused entry was answered and a newer write took '
                'its place, so the queue moved');
      });
    }
  });

  test(
      'An enrollment granted read only stores what sync brings it, and its '
      'own put is still refused', () async {
    final c = enrolled({'ns': 'r'});
    final sync = await syncPulling(c.client, ['x.ns@bob']);

    await pull(sync);

    expect(await c.store.exists('x.ns@bob'), isTrue,
        reason: 'the atServer sends a record to an enrollment that may read '
            'it, and storing it is not a write by that enrollment');
    await expectLater(
        put(c.local, 'x.ns@bob'), throwsA(isA<UnAuthorizedException>()),
        reason: 'the enrollment itself still may not write ns');
  });

  group('Given an enrollment that may only read a namespace', () {
    test(
        'when it also holds `*: rw`, then sync still stores that '
        'namespace\'s advertisement', () async {
      final c = enrolled({'readonly': 'r', '*': 'rw', '__manage': 'rw'});
      final sync = await syncPulling(c.client, ['public:__nskey.readonly@bob']);

      await pull(sync);

      expect(await c.store.exists('public:__nskey.readonly@bob'), isTrue,
          reason: 'readonly gives read, which is enough to store what sync '
              'brings');
    });

    test('when sync brings a delete, then the record goes', () async {
      final c = enrolled({'ns': 'r'});
      await c.store.put('x.ns@bob', AtData()..data = 'held');
      final sync = await syncPulling(c.client, ['x.ns@bob'], deletes: true);

      await pull(sync);

      expect(await c.store.exists('x.ns@bob'), isFalse,
          reason: 'a delete the atServer sends applies as an update does');
    });
  });

  test(
      'An enrollment stores its own per-enrollment records from sync, and '
      'refuses another enrollment\'s', () async {
    final c = enrolled({'cmp.rotation': 'rw'});
    const own = '__ckcur.bob.cmp.rotation.$enrollmentId.a.__e@bob';
    const foreign = '__ckcur.bob.cmp.rotation.other-enrollment.a.__e@bob';
    final sync = await syncPulling(c.client, [own, foreign]);

    await pull(sync);

    expect(await c.store.exists(own), isTrue,
        reason: 'every enrollment reads and writes its own <id>.a.__e '
            'namespace on the atServer without being granted it');
    expect(await c.store.exists(foreign), isFalse,
        reason: 'another enrollment\'s namespace is not this one\'s');
  });

  group('Given an enrollment granted neither `*` nor __atserver', () {
    test('when it reads x.__atserver@bob, then it may, and it may not write it',
        () async {
      final c = enrolled({'cmp.rotation': 'rw'});
      await c.store.put('x.__atserver@bob', AtData()..data = 'held');

      expect(await llookup(c.local, 'x.__atserver@bob'), 'data:held',
          reason: 'every enrollment reads __atserver on the atServer');
      await expectLater(put(c.local, 'x.__atserver@bob'),
          throwsA(isA<UnAuthorizedException>()),
          reason: 'and none writes it');
    });
  });
}
