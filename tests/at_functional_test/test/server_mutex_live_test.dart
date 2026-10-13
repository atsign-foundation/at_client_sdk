// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

library;

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/server_mutex.dart' show ServerMutexHolder;
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

  String holderOf(AtClient client) =>
      client.enrollmentId ?? EnrollmentConstants.primaryEnrollmentId;

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
    expect(value, enrolled.enrollmentId,
        reason: 'the record names the enrollment that holds it');
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

  test(
      'Given a lock this enrollment took, when it reads the lock back, then '
      'it holds it', () async {
    final key = freshLock();
    expect(await enrolled.tryAcquireServerMutex(key, ttl: ttl), isNotNull);

    expect(await enrolled.holdsServerMutex(key), isTrue);
  });

  test(
      'Given a lock another enrollment took, when this one reads it back, '
      'then it does not hold it', () async {
    final key = freshLock();
    expect(await owner.tryAcquireServerMutex(key, ttl: ttl), isNotNull);
    expect(holderOf(owner), isNot(holderOf(enrolled)),
        reason: 'the precondition: two holders this check can tell apart');

    expect(await enrolled.holdsServerMutex(key), isFalse);
    expect(await owner.holdsServerMutex(key), isTrue,
        reason: 'the control: the lock is there, and is the owner\'s');
  });

  test(
      'Given no record for a lock, when a client reads it back, then it does '
      'not hold it', () async {
    final key = freshLock();

    expect(await enrolled.holdsServerMutex(key), isFalse);
  });

  test(
      'Given a lock this enrollment took, when it reads its own lease back, '
      'then the lease ends at the record\'s own expiry', () async {
    final key = freshLock();
    final taken = await enrolled.tryAcquireServerMutex(key, ttl: ttl);
    expect(taken, isNotNull);
    // NOTE: read back 2 s after the take, so the lease's cap at the ttl from
    // the read lies past the record's expiry unless the atServer's clock runs
    // about 2 s ahead of this one.
    await Future<void>.delayed(Duration(seconds: 2));

    final own = await enrolled.ownServerMutexLease(key, ttl: ttl);

    final (_, meta) = await stored(key);
    expect(own, isNotNull,
        reason: 'the record carries an expiry this client could read back');
    expect(own!.expiresAt, DateTime.parse(meta['expiresAt'] as String).toUtc(),
        reason: 'the expiry the atServer serves, not one this client made up');
  });
}
