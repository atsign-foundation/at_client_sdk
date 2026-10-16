import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

import 'storage_contract.dart' show FakeClient;

/// One atSign's sync queue under one directory belongs to one client at a
/// time, as its keystore there does.
void main() {
  const atSign = '@queueclaim';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('queue_claim_');
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

  AtClientPreference pref() => AtClientPreference()..hiveStoragePath = dir.path;

  /// A client of [atSign] as enrollment `e2`, on a bare keystore, whose sync
  /// queue lives under [dir].
  Future<AtClient> bareKeystoreClient() async {
    final keys = InMemoryAtClientStorage(atSign: atSign);
    await keys.attach(FakeClient(atSign, 'e2'));
    addTearDown(keys.close);
    return AtClientImpl.create(atSign, 'wavi', pref(),
        enrollmentId: 'e2', localSecondaryKeyStore: keys.keyStore);
  }

  group('Given a client of @alice whose sync queue is open under a directory',
      () {
    late AtClient first;

    setUp(() async {
      first = await buildAtClient(
          atSign: atSign, namespace: 'wavi', preference: pref());
      expect(await first.getLocalSecondary()!.syncQueueSize, 0,
          reason: 'its queue is open');
    });

    test(
        'when a client of @alice built on a bare keystore under that '
        'directory opens its sync queue, then the open is refused with a '
        'StateError naming the directory', () async {
      final bare = await bareKeystoreClient();

      await expectLater(
          bare.getLocalSecondary()!.syncQueueSize,
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains(dir.path))),
          reason: 'sharing the box, each client would replay the other\'s '
              'writes, and stopping one would close the other\'s queue');
    });

    test(
        'when the first client stops, then a bare-keystore client of @alice '
        'under that directory opens its sync queue', () async {
      await first.stop();
      final bare = await bareKeystoreClient();

      expect(await bare.getLocalSecondary()!.syncQueueSize, 0);
    });
  });
}
