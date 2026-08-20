// Reclaiming an expired record is storage internals, not an operation an
// enrollment is performing, so it is not subject to that enrollment's
// namespace scope.
//
// Before this, a record whose namespace the client's enrollment did not cover
// could never be reclaimed: it arrives in local storage by sync (a `_nskeylock`
// is created remote-only by MintLock and synced down like any other self key),
// expires, and then fails `LocalSecondary._delete`'s authorization check every
// time the sweep reaches it. Nothing removed it and nothing could. Measured in
// one functional pack run before the fix: three such records, 225,721 refused
// sweeps between them, 47% of the run's log lines — the expiry timer re-armed
// at zero each time because the earliest expiry never moved.
//
// The scoping the check exists to enforce is untouched: an expiry deletion is
// `localOnly`, so it is never enqueued for sync and cannot reach anyone else's
// copy of anything.
//
// Driven through a bare LocalSecondary rather than a built AtClientImpl on
// purpose: a real client arms its own expiry timer, which sweeps the record
// out from under the test before it can assert anything. That is the fix
// working, but it is not this test observing it.

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

void main() {
  final storageDir = '${Directory.current.path}/test/hive_expiry_auth';
  const atSignStr = '@alice';

  late LocalSecondary local;
  late HiveAtPersistenceFactory factory;

  setUp(() async {
    AtClientImpl.atClientInstanceMap.remove(atSignStr);
    factory = HiveAtPersistenceFactory();
    final bundle = await factory.initialize(atSignStr,
        HivePersistenceConfig.clientDefaults(storagePath: storageDir));

    final atClient = _MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSignStr);
    when(() => atClient.atSign).thenReturn(atSignStr.toAtsign());
    when(() => atClient.enrollmentId).thenReturn('enroll-1');
    when(() => atClient.persistenceBundle).thenReturn(bundle);

    local = LocalSecondary(atClient,
        keyStore: bundle.keyValueStore, onEvent: (_) {});
  });

  tearDown(() async {
    await factory.close();
    final dir = Directory(storageDir);
    if (await dir.exists()) dir.deleteSync(recursive: true);
  });

  /// A self key in `buzz`, shaped like the mint lock that provoked this.
  AtKey lockKey({int? ttlMs}) => AtKey()
    ..key = '_nskeylock.cooldown1'
    ..sharedBy = atSignStr
    ..sharedWith = atSignStr
    ..namespace = 'buzz'
    ..metadata = (Metadata()..ttl = ttlMs);

  test('the expiry sweep reclaims a record outside the enrollment\'s namespace',
      () async {
    // Written while the enrollment still covers everything — standing in for
    // the record arriving by sync, which no enrollment scope gates. The ttl
    // has to outlive the write itself: at ttl=1 the record is already expired
    // by the time putAll runs and never enters the store at all.
    local.enrollment = Enrollment()..namespace = {'*': 'rw'};
    final key = lockKey(ttlMs: 200);
    await local.executeVerb(
        UpdateVerbBuilder()
          ..atKey = key
          ..value = 'enroll-1',
        sync: false);
    expect(await local.keyStore!.exists(key.toString().toLowerCase()), isTrue,
        reason: 'the record must actually be in the store, or the sweep below '
            'has nothing to reclaim and passes for the wrong reason');

    // Narrow the enrollment so it no longer covers `buzz` — the state a scoped
    // client is in when another namespace's record has been synced to it.
    local.enrollment = Enrollment()..namespace = {'wavi': 'rw'};

    await Future.delayed(Duration(milliseconds: 400));

    // THE CONTROL. An ordinary delete is still refused, so this test would
    // fail against a build that had simply dropped the authorization check.
    await expectLater(
        local.executeVerb(DeleteVerbBuilder()..atKey = key, sync: false),
        throwsA(isA<UnAuthorizedException>()),
        reason: 'an enrollment-initiated delete outside its namespace must '
            'still be refused');

    // THE SUBJECT.
    expect(await local.deleteExpiredKeys(), equals(1),
        reason: 'the expiry sweep must reclaim the record the enrollment '
            'itself may not delete');
    expect(await local.keyStore!.exists(key.toString().toLowerCase()), isFalse,
        reason: 'the record must be gone, not merely counted as removed');
  });

  test('a sweep with nothing expired reports nothing removed', () async {
    // Guards the return value the expiry timer's backoff keys on: if an empty
    // sweep ever reported a non-zero count, the timer would read a fruitless
    // pass as progress and re-arm at zero.
    local.enrollment = Enrollment()..namespace = {'*': 'rw'};
    await local.executeVerb(
        UpdateVerbBuilder()
          ..atKey = lockKey()
          ..value = 'no ttl',
        sync: false);
    expect(await local.deleteExpiredKeys(), equals(0));
  });
}
