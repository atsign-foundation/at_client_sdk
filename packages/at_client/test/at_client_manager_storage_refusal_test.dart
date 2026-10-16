import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

/// `AtClientManager.setCurrentAtSign` refuses a client it could not build
/// before it stops the one that is current.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('manager_refusal_');
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

  group('Given a current client of @alice on a store of its own', () {
    late AtClientManager manager;
    late AtClient alice;

    setUp(() async {
      manager = AtClientManager('@alice');
      await manager.setCurrentAtSign(
          '@alice', 'wavi', AtClientPreference()..hiveStoragePath = dir.path);
      alice = manager.atClient;
    });

    void expectAliceStillCurrent() {
      expect(manager.atClient, same(alice));
      expect(alice.isStopped, isFalse,
          reason: 'a switch that cannot build its client leaves the current '
              'one running, rather than stopping it for nothing');
    }

    test(
        'when setCurrentAtSign switches to @bob with isLocalStoreRequired '
        'false and no storage, then it throws an ArgumentError and @alice '
        'stays current and running', () async {
      await expectLater(
          () => manager.setCurrentAtSign('@bob', 'wavi',
              AtClientPreference()..isLocalStoreRequired = false),
          throwsA(isA<ArgumentError>()));
      expectAliceStillCurrent();
    });

    test(
        'when setCurrentAtSign switches to @bob with no storage and no '
        'hiveStoragePath, then it throws an ArgumentError and @alice stays '
        'current and running', () async {
      await expectLater(
          () => manager.setCurrentAtSign('@bob', 'wavi', AtClientPreference()),
          throwsA(isA<ArgumentError>()));
      expectAliceStillCurrent();
    });

    test(
        'when setCurrentAtSign switches @alice to another enrollment with no '
        'storage and no hiveStoragePath, then it throws an ArgumentError and '
        '@alice stays current and running', () async {
      await expectLater(
          () => manager.setCurrentAtSign('@alice', 'wavi', AtClientPreference(),
              enrollmentId: 'another'),
          throwsA(isA<ArgumentError>()));
      expectAliceStillCurrent();
    });

    test(
        'when setCurrentAtSign switches to @bob, whose client buildAtClient '
        'already built, with no storage, then that client becomes current',
        () async {
      final bob = await buildAtClient(
          atSign: '@bob',
          namespace: 'wavi',
          preference: AtClientPreference(),
          storage:
              InMemoryAtClientStorage(atSign: '@bob', closedByClient: true));

      await manager.setCurrentAtSign('@bob', 'wavi', AtClientPreference());

      expect(manager.atClient, same(bob),
          reason: 'a live client is adopted, so there is nothing to refuse');
    });
  });
}
