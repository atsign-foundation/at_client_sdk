library;

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The server mutex against a live atServer, with two clients of one atSign
/// each under its own enrollment.
///
/// The scenario tests share their titles with
/// `features/at_client/server_mutex.feature`. Every lock key is run-unique and
/// lives in a run-unique namespace, so a lock nothing releases cannot meet
/// another run or another file.
void main() {
  TestUtils.isolateStorage('server_mutex_live_test');
  late String atSign;
  late AtClient owner;
  late AtClient enrolled;
  final runId = DateTime.now().microsecondsSinceEpoch;
  // NOTE: a namespace of its own, because a client start asks every
  // enrollment holding its namespace for the keys it lacks.
  final namespace = 'servermutex$runId';
  const rootDomain = 'vip.ve.atsign.zone';
  const ttl = Duration(seconds: 30);
  var serial = 0;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    owner = (await TestUtils.initAtClient(atSign, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    enrolled = (await enrolAndAuthenticate(
      approver: owner,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: 'servermutex-$runId',
      storage: TestUtils.storage,
    ))
        .client;
  });

  tearDownAll(() async {
    await enrolled.stop();
    await owner.stop();
  });

  /// A lock key no earlier test or run has used.
  AtKey freshLock() =>
      AtKey.fromString('l${serial++}.session_mutexes.$namespace$atSign');

  /// What the atServer holds for [key]: its value and its metadata.
  Future<(String, Map<String, dynamic>)> stored(AtKey key) async {
    final remote = owner.getRemoteSecondary()!;
    final value = await remote.executeCommand('llookup:$key\n', auth: true);
    final meta = await remote.executeCommand('llookup:meta:$key\n', auth: true);
    return (
      value!.replaceFirst('data:', ''),
      jsonDecode(meta!.replaceFirst('data:', '')) as Map<String, dynamic>
    );
  }

  /// Creates [key] the way a client on an older release does: an immutable
  /// remote put, recording a commit.
  Future<void> takeWithoutTheExtension(AtKey key, {Duration ttl = ttl}) =>
      owner.put(
          key
            ..metadata = (Metadata()
              ..immutable = true
              ..ttl = ttl.inMilliseconds),
          'lock',
          putRequestOptions: PutRequestOptions()
            ..shouldEncrypt = false
            ..useRemoteAtServer = true);

  Future<int> serverCommitId() async =>
      await SyncUtil()
          .getLatestServerCommitId(owner.getRemoteSecondary()!, '') ??
      -1;

  test('The first client to ask takes the lock', () async {
    final key = freshLock();
    final asked = DateTime.now();

    final lease = await enrolled.tryAcquireServerMutex(key, ttl: ttl);
    final answered = DateTime.now();

    expect(lease, isNotNull);
    expect(lease!.expiresAt.isBefore(asked.add(ttl)), isFalse);
    expect(lease.expiresAt.isAfter(answered.add(ttl)), isFalse,
        reason: 'stamped before the create went out, so the lease cannot '
            'outlive the record');
    final (value, meta) = await stored(key);
    expect(meta['immutable'], isTrue);
    expect(meta['ttl'], 30000);
    expect(value, startsWith('${enrolled.enrollmentId}:'),
        reason: 'the record names the enrollment that holds it, then this '
            'isolate\'s nonce');
  });

  test('A client is refused while another holds the lock', () async {
    final key = freshLock();
    expect(await owner.tryAcquireServerMutex(key, ttl: ttl), isNotNull);

    expect(await enrolled.tryAcquireServerMutex(key, ttl: ttl), isNull,
        reason: 'the atServer refuses the second create, and that refusal '
            'alone means "held"');
  });

  test('Exactly one of two racing clients takes the lock', () async {
    // NOTE: several rounds, since one clean round is a claim about one
    // interleaving.
    for (var round = 0; round < 5; round++) {
      final key = freshLock();
      final leases = await Future.wait([
        owner.tryAcquireServerMutex(key, ttl: ttl),
        enrolled.tryAcquireServerMutex(key, ttl: ttl),
      ]);
      expect(leases.where((lease) => lease != null), hasLength(1),
          reason: 'round $round: one lease, never two and never none');
    }
  });

  test('A lock taken without the extension still excludes the extension',
      () async {
    final key = freshLock();
    await takeWithoutTheExtension(key);

    expect(
        await enrolled.tryAcquireServerMutex(freshLock(), ttl: ttl), isNotNull,
        reason: 'the control: this client takes a lock no one holds');
    expect(
        await enrolled.tryAcquireServerMutex(AtKey.fromString('$key'),
            ttl: ttl),
        isNull,
        reason: 'both name one record, so a client mid-upgrade still excludes '
            'one that has not upgraded');
  });

  test('A lock over an existing mutable record takes it', () async {
    final key = freshLock();
    await owner.put(key, 'data',
        putRequestOptions: PutRequestOptions()
          ..shouldEncrypt = false
          ..useRemoteAtServer = true);
    final (prior, before) = await stored(key);
    expect(prior, 'data', reason: 'the control: the record exists');
    expect(before['immutable'], isNot(isTrue),
        reason: 'the control: the record is mutable');

    final lease = await enrolled.tryAcquireServerMutex(AtKey.fromString('$key'),
        ttl: ttl);

    expect(lease, isNotNull);
    final (value, meta) = await stored(key);
    expect(meta['immutable'], isTrue);
    expect(meta['ttl'], 30000);
    expect(value, startsWith('${enrolled.enrollmentId}:'),
        reason: 'the lock replaced the record\'s value');
  });

  test('The lock frees itself when its ttl runs out', () async {
    final key = freshLock();
    expect(await owner.tryAcquireServerMutex(key, ttl: Duration(seconds: 2)),
        isNotNull);
    expect(await enrolled.tryAcquireServerMutex(key, ttl: ttl), isNull,
        reason: 'the control: held until the ttl runs out');

    await Future<void>.delayed(Duration(seconds: 3));

    expect(await enrolled.tryAcquireServerMutex(key, ttl: ttl), isNotNull,
        reason: 'nothing released it but its ttl');
  });

  test('Taking a lock writes no commit entry', () async {
    // NOTE: the control first: if an ordinary immutable create does not move
    // the commit log, the zero below means nothing.
    final committed = freshLock();
    var before = await serverCommitId();
    await takeWithoutTheExtension(committed, ttl: Duration(minutes: 1));
    expect(await serverCommitId() - before, greaterThan(0));

    final lock = freshLock();
    before = await serverCommitId();
    expect(await owner.tryAcquireServerMutex(lock, ttl: ttl), isNotNull);
    expect(await serverCommitId() - before, 0,
        reason: 'the create carried :nc');

    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: enrolled.syncService, label: 'enrolled');
    final local = enrolled.getLocalSecondary()!.keyStore!;
    expect(await local.exists('$committed'), isTrue,
        reason: 'the control: sync carried the committed record here');
    expect(await local.exists('$lock'), isFalse,
        reason: 'and never carries the lock');
  });
}
