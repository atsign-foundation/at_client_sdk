import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockSyncService extends Mock implements SyncService {}

/// The expiry sweep reclaims a record whose namespace the client's enrollment
/// does not cover: reclaiming an expired record is storage internals, not an
/// operation the enrollment performs, so it is not subject to that
/// enrollment's namespace scope.
///
/// NOTE: driven through a bare LocalSecondary rather than a built
/// AtClientImpl, which arms its own expiry timer and sweeps the record out
/// from under the test before it can assert anything.
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
    when(() => atClient.syncService).thenReturn(_MockSyncService());

    local = LocalSecondary(atClient,
        keyStore: bundle.keyValueStore, onEvent: (_) {});
  });

  tearDown(() async {
    await factory.close();
    final dir = Directory(storageDir);
    if (await dir.exists()) dir.deleteSync(recursive: true);
  });

  /// A self key in the `buzz` namespace, shaped like a mint lock.
  AtKey lockKey({int? ttlMs}) => AtKey()
    ..key = '_nskeylock.cooldown1'
    ..sharedBy = atSignStr
    ..sharedWith = atSignStr
    ..namespace = 'buzz'
    ..metadata = (Metadata()..ttl = ttlMs);

  test('the expiry sweep reclaims a record outside the enrollment\'s namespace',
      () async {
    // NOTE: the ttl has to outlive the write itself — at ttl=1 the record is
    // already expired by the time putAll runs and never enters the store.
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

    local.enrollment = Enrollment()..namespace = {'wavi': 'rw'};

    await Future.delayed(Duration(milliseconds: 400));

    // The control: a build that simply dropped the authorization check fails
    // here.
    await expectLater(
        local.executeVerb(DeleteVerbBuilder()..atKey = key, sync: false),
        throwsA(isA<UnAuthorizedException>()),
        reason: 'an enrollment-initiated delete outside its namespace must '
            'still be refused');

    expect(await local.deleteExpiredKeys(), equals(1),
        reason: 'the expiry sweep must reclaim the record the enrollment '
            'itself may not delete');
    expect(await local.keyStore!.exists(key.toString().toLowerCase()), isFalse,
        reason: 'the record must be gone, not merely counted as removed');
  });

  test('a sweep with nothing expired reports nothing removed', () async {
    // NOTE: the expiry timer's backoff keys on this count — a non-zero count
    // from a fruitless sweep re-arms the timer at zero.
    local.enrollment = Enrollment()..namespace = {'*': 'rw'};
    await local.executeVerb(
        UpdateVerbBuilder()
          ..atKey = lockKey()
          ..value = 'no ttl',
        sync: false);
    expect(await local.deleteExpiredKeys(), equals(0));
  });
}
