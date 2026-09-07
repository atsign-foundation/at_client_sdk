import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

/// A principal change is a succession: one enrollment of an atSign replaced
/// by another over the store the outgoing client held. The default shape, a
/// client that built its own store from the preference, is the one that has
/// to survive it.
void main() {
  const atSign = '@principalchange';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('principal_change_');
    AtClientImpl.atClientInstanceMap.clear();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    await HiveInstances.closeAll();
    await Hive.close();
    AtClientImpl.atClientInstanceMap.clear();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AtClientPreference pref() => AtClientPreference()
    ..isLocalStoreRequired = true
    ..hiveStoragePath = dir.path
    ..commitLogPath = '${dir.path}/commit';

  test(
      'the store the outgoing client built crosses the switch open, and the '
      'incoming client closes it', () async {
    final manager = AtClientManager(atSign);
    await manager.setCurrentAtSign(atSign, 'wavi', pref());
    final outgoing = manager.atClient as AtClientImpl;
    final store = outgoing.storage;
    expect(store, isNotNull,
        reason: 'the default shape: a store the client built for itself');

    await manager.setCurrentAtSign(atSign, 'wavi', pref(),
        enrollmentId: 'successor', principalChange: true);
    final incoming = manager.atClient as AtClientImpl;

    expect(outgoing.isStopped, isTrue);
    expect(identical(incoming, outgoing), isFalse);
    expect(identical(incoming.storage, store), isTrue,
        reason: 'succession keeps ONE store: the incoming client runs over '
            'the one the outgoing client held, not a second at the same '
            'location');
    expect(store!.isHeldBy(incoming), isTrue);

    await incoming.stop();
    await expectLater(store.attach(incoming), throwsA(isA<StateError>()),
        reason: 'the store followed the hand-over: the incoming client closed '
            'it on its stop, so it cannot be reopened');
  });

  test('a client-closed bundle named by the caller survives the switch too',
      () async {
    final bundle = HiveAtClientStorage(
        atSign: atSign, storagePath: dir.path, closedByClient: true);
    final manager = AtClientManager(atSign);
    await manager.setCurrentAtSign(atSign, 'wavi', pref(), storage: bundle);
    final outgoing = manager.atClient;

    await manager.setCurrentAtSign(atSign, 'wavi', pref(),
        enrollmentId: 'successor', storage: bundle, principalChange: true);
    final incoming = manager.atClient;

    expect(outgoing.isStopped, isTrue);
    expect(bundle.isHeldBy(incoming), isTrue,
        reason: 'named or carried, the bundle the outgoing client held is '
            'handed over open rather than closed under it');
  });

  test('the same-atSign short-circuit does not swallow a principal change',
      () async {
    final manager = AtClientManager(atSign);
    await manager.setCurrentAtSign(atSign, 'wavi', pref());
    final outgoing = manager.atClient;

    await manager.setCurrentAtSign(atSign, 'wavi', pref(),
        principalChange: true);

    expect(outgoing.isStopped, isTrue,
        reason: 'a principal change is never a no-op; with nothing else in '
            'the call changed, the short-circuit handed the outgoing client '
            'back');
    expect(identical(manager.atClient, outgoing), isFalse);
  });
}
