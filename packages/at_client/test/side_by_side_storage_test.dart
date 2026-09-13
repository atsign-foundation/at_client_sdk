import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Two AtClients for one atSign, side by side in one process, each given its
/// own `hiveStoragePath`.
///
/// A Hive box's identity is `(instance registry, box name)` and box names
/// derive from the atSign alone, so two clients sharing a registry silently
/// share their boxes whatever path each was handed — a write through one
/// visible to the other, a replay position advanced by one consumed from the
/// other, with no exception and no log.
void main() {
  const atSign = '@alice';
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('side_by_side');
    AtClientImpl.atClientInstanceMap.clear();
  });

  tearDown(() async {
    await HiveInstances.closeAll();
    await Hive.close();
    AtClientImpl.atClientInstanceMap.clear();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A client of [atSign] with its own storage directory.
  ///
  /// The instance cache is evicted first so each call really builds a client
  /// rather than handing back the previous one.
  Future<AtClient> clientAt(String name) async {
    final path =
        (Directory('${root.path}/$name')..createSync(recursive: true)).path;
    AtClientImpl.atClientInstanceMap.clear();
    final client = await AtClientImpl.create(
      atSign,
      'wavi',
      AtClientPreference()
        ..isLocalStoreRequired = true
        ..syncRegex = ''
        ..hiveStoragePath = path
        ..commitLogPath = '$path/commit',
    );
    // NOTE: AtClientImpl.create leaves the sync service to its caller - only
    // AtClientManager wires one - and a write on a client without one is
    // queued but says at warning that it could not ask for a drain.
    client.syncService = MockSyncService();
    return client;
  }

  test('their keystores are separate', () async {
    final a = await clientAt('a');
    final b = await clientAt('b');

    expect(identical(a, b), isFalse,
        reason: 'two clients, or every assertion below is a comparison of one '
            'client with itself and passes for that reason');

    final localA = a.getLocalSecondary() as LocalSecondary;
    final localB = b.getLocalSecondary() as LocalSecondary;

    await localA.putValue('local:probe.wavi$atSign', 'written-by-a');

    expect(await localB.keyStore!.exists('local:probe.wavi$atSign'), isFalse,
        reason: 'these clients were given different hiveStoragePaths, so a '
            'write through one must not appear in the other. When they shared '
            'a box, this key was simply there — and nothing on either side '
            'could tell');

    // NOTE: the control — without it, "b cannot see a's key" is equally
    // explained by b being a store that can see nothing at all.
    await localB.putValue('local:probe.wavi$atSign', 'written-by-b');
    expect((await localB.keyStore!.get('local:probe.wavi$atSign'))?.data,
        'written-by-b');
    expect((await localA.keyStore!.get('local:probe.wavi$atSign'))?.data,
        'written-by-a',
        reason: 'and a keeps its own value: the separation holds in both '
            'directions, not only the one the first write went');
  });

  test('their sync queues are separate', () async {
    // NOTE: order is the whole test. `syncQueueSize` reads an IN-MEMORY queue
    // that AtSyncQueue populates by replaying its box once, at open, so b must
    // be built AFTER a's write. Build both first and b is empty whether or not
    // the box is shared.
    final a = await clientAt('a');
    final localA = a.getLocalSecondary() as LocalSecondary;

    await localA.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = '555',
        sync: true);

    expect(await localA.syncQueueSize, 1,
        reason: 'the write must reach a\'s queue, or the check on b below is '
            'measuring an enqueue that never happened');

    final b = await clientAt('b');
    final localB = b.getLocalSecondary() as LocalSecondary;
    expect(identical(a, b), isFalse,
        reason: 'two clients, or this compares one with itself');

    expect(await localB.syncQueueSize, 0,
        reason: 'b was given its own hiveStoragePath, so it must open its own '
            'queue box and replay nothing. A shared queue hands one client\'s '
            'pending writes to another\'s sync, which drains them against a '
            'server state the first client never saw');

    expect(await localA.syncQueueSize, 1,
        reason: 'and a still holds its own entry — b opening must not consume '
            'it, which is the failure this separation prevents');
  });
}
