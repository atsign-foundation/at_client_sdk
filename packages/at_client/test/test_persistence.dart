import 'dart:io';

import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Test-side wrapper around [HiveAtPersistenceFactory] so individual
/// test files don't have to spell out a full [HivePersistenceConfig]
/// (five required paths) for every setUp / tearDown.
///
/// Replaces the historical `AtCommitLogManagerImpl.getInstance()` +
/// `SecondaryPersistenceStoreFactory.getInstance()` pair that test
/// helpers used pre-overhaul.
///
/// ```dart
/// late TestPersistence persistence;
///
/// setUp(() async {
///   persistence = TestPersistence('${Directory.current.path}/test/hive');
///   final bundle = await persistence.init('@alice');
///   // bundle.keyStore, bundle.commitLog ...
/// });
///
/// tearDown(() => persistence.tearDown());
/// ```
class TestPersistence {
  final HiveAtPersistenceFactory factory = HiveAtPersistenceFactory();
  final String storageDir;
  final bool enableCommitId;

  TestPersistence(this.storageDir, {this.enableCommitId = false});

  /// Initialise (or fetch) the persistence bundle for [atSign].
  /// Repeated calls for the same [atSign] return the same bundle.
  Future<AtPersistenceBundle> init(String atSign) {
    return factory.initialize(
      atSign,
      HivePersistenceConfig(
        storagePath: storageDir,
        commitLogPath: storageDir,
        accessLogPath: storageDir,
        notificationStoragePath: storageDir,
        enableCommitId: enableCommitId,
      ),
    );
  }

  /// Look up an already-initialised bundle.
  AtPersistenceBundle? bundleFor(String atSign) => factory.bundleFor(atSign);

  /// Close all bundles and remove the storage directory.
  Future<void> tearDown() async {
    await factory.close();
    final dir = Directory(storageDir);
    if (await dir.exists()) {
      dir.deleteSync(recursive: true);
    }
  }
}
