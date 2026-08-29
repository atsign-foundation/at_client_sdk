import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

/// Two AtClients for one atSign, side by side in one process, each given its
/// own `hiveStoragePath`.
///
/// This is what the functional packs simulate: clients that would normally run
/// in separate processes with separate storage, co-located for convenience.
/// Until 2026-08-28 the simulation was a lie — a Hive box's identity is
/// `(instance registry, box name)`, box names derive from the atSign alone,
/// and everything ran through the one global instance `package:hive` exposes.
/// So the second client silently attached to the first's boxes whatever path
/// it was handed, and the path it asked for reached nothing but the
/// encryption-secret file beside them.
///
/// It failed silently in both directions: a write through one was visible to
/// the other, and a replay position advanced by one was consumed from the
/// other. No exception, no log, each side internally consistent.
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
  /// rather than handing back the previous one — the cache is keyed
  /// `(atSign, enrollmentId)` and these deliberately carry no enrollment id.
  /// Setting one instead would make `executeVerb` authorise the enrollment
  /// against an atServer, which no unit test has; the storage question is
  /// answered without it.
  Future<AtClient> clientAt(String name) async {
    final path =
        (Directory('${root.path}/$name')..createSync(recursive: true)).path;
    AtClientImpl.atClientInstanceMap.clear();
    return AtClientImpl.create(
      atSign,
      'wavi',
      AtClientPreference()
        ..isLocalStoreRequired = true
        ..syncRegex = ''
        ..hiveStoragePath = path
        ..commitLogPath = '$path/commit',
    );
  }

  test('their keystores are separate', () async {
    final a = await clientAt('a');
    final b = await clientAt('b');

    // Checked, not assumed: the instance cache is keyed (atSign, enrollmentId),
    // so if these were one object every assertion below would be a comparison
    // of one client with itself and would pass for that reason.
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

    // The control, and it is not drawn from the property under test: b must be
    // a working store. Without this, "b cannot see a's key" is equally
    // explained by b being broken, and the assertion above would pass for a
    // store that could see nothing at all.
    await localB.putValue('local:probe.wavi$atSign', 'written-by-b');
    expect((await localB.keyStore!.get('local:probe.wavi$atSign'))?.data,
        'written-by-b');
    expect((await localA.keyStore!.get('local:probe.wavi$atSign'))?.data,
        'written-by-a',
        reason: 'and a keeps its own value: the separation holds in both '
            'directions, not only the one the first write went');
  });

  test('their sync queues are separate', () async {
    // The keystore is not the only box. AtSyncQueue opens its own,
    // `syncqueue_<sha of atSign>` — also named from the atSign alone — and it
    // used to open on the global instance regardless of the path, so two
    // co-located clients shared one queue and each drained the other's
    // pending writes.
    //
    // ⚠️ ORDER IS THE WHOLE TEST, and the obvious arrangement proves nothing.
    // `syncQueueSize` reads an IN-MEMORY queue that AtSyncQueue populates by
    // replaying the box once, at open. Open both queues first and b's is
    // empty whether or not the box is shared — a mutation putting the queue
    // back on the global left that version green. So b must be built AFTER
    // a's write, where its replay is what reveals a shared box.
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

    // Built now, so its queue replays the box it resolves to.
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
