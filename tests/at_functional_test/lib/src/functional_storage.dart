import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';

/// A storage backend the functional pack can run its clients on.
enum FunctionalStorageBackend { hive, sqlite, memory }

/// The local storage the clients of one test file use: one bundle per atSign,
/// at a location no other test file opens.
///
/// Every file shared one directory before this existed, so a file inherited
/// whatever keystore entries and unpushed sync-queue entries the previous one
/// left behind. Each file now names itself and gets its own.
///
/// The backend comes from [environmentVariable] — Hive by default, which is
/// what the pack has always run on; `sqlite` and `memory` let the same tests
/// prove the other two implementations.
class FunctionalStorage {
  FunctionalStorage(this.testFile, {FunctionalStorageBackend? backend})
      : backend = backend ?? backendFromEnvironment();

  /// Names the backend to build. Unset means [FunctionalStorageBackend.hive].
  static const String environmentVariable = 'AT_FUNCTIONAL_STORAGE';

  /// Throws on a value that is not a backend name rather than falling back to
  /// Hive, so a typo cannot quietly run the backend it was meant to replace.
  static FunctionalStorageBackend backendFromEnvironment() {
    final raw = Platform.environment[environmentVariable];
    if (raw == null || raw.isEmpty) return FunctionalStorageBackend.hive;
    final wanted = raw.toLowerCase();
    return FunctionalStorageBackend.values.firstWhere(
        (backend) => backend.name == wanted,
        orElse: () => throw ArgumentError('$environmentVariable=$raw is not '
            'one of ${FunctionalStorageBackend.values.map((b) => b.name).join(', ')}'));
  }

  /// This test file's name, which is what keeps its on-disk backends apart
  /// from every other file's.
  final String testFile;

  final FunctionalStorageBackend backend;

  final Map<String, AtClientStorage> _byAtSign = {};
  final Map<String, AtClientStorage> _byPrincipal = {};

  /// Where this file's on-disk backends live, under the directory the pack's
  /// runner already clears before a run.
  String get storagePath => 'test/hive/$testFile';

  /// The bundle every client this file builds for [atSign] shares.
  ///
  /// Built once and kept, so a client stopped and rebuilt mid-file reads back
  /// what its predecessor wrote — which several tests assert.
  AtClientStorage forAtSign(String atSign) =>
      _byAtSign.putIfAbsent(atSign, () => _build(atSign));

  /// A bundle for a SECOND live principal on [atSign], told apart by [label].
  ///
  /// Two enrollments of one atSign that are live at the same moment get
  /// separate stores: each holds key material the other cannot read, and the
  /// claim guard refuses to let one attach to the other's.
  ///
  /// [label] must be stable for one logical principal across the file, since a
  /// client stopped and rebuilt under the same label reads back what it wrote.
  /// Succession does NOT come here: a retrofit replaces one enrollment with
  /// another over the same store, so it keeps [forAtSign]'s bundle and hands
  /// the store over.
  AtClientStorage forPrincipal(String atSign, String label) =>
      _byPrincipal.putIfAbsent(
          '$atSign|$label', () => _build(atSign, label: label));

  /// Lets the next client attach under a different enrollment while keeping
  /// the data.
  ///
  /// The claim guard otherwise refuses a second principal, which is right for
  /// an application and wrong for a fixture that deliberately re-authenticates
  /// as one of the atSign's own enrolments and expects to read what the owner
  /// wrote. Every client must be stopped first, or `forgetPrincipal` throws.
  Future<void> allowPrincipalChange() async {
    for (final storage in [..._byAtSign.values, ..._byPrincipal.values]) {
      await storage.forgetPrincipal();
    }
  }

  /// [label] separates a second principal's store from the atSign's own.
  AtClientStorage _build(String atSign, {String? label}) {
    final suffix = label == null ? '' : '-$label';
    return switch (backend) {
      FunctionalStorageBackend.hive => HiveAtClientStorage(
          atSign: atSign, storagePath: '$storagePath/$atSign$suffix'),
      FunctionalStorageBackend.sqlite => SqliteAtClientStorage.under(
          atSign: '$atSign$suffix', storagePath: storagePath),
      // Distinguished by object identity, so each call is already its own.
      FunctionalStorageBackend.memory =>
        InMemoryAtClientStorage(atSign: atSign),
    };
  }

  /// Closes every bundle this file opened. Nothing else does: these bundles
  /// are borrowed, so a client detaches from them on `stop()` without
  /// closing them.
  Future<void> closeAll() async {
    for (final storage in [..._byAtSign.values, ..._byPrincipal.values]) {
      await storage.close();
    }
    _byAtSign.clear();
    _byPrincipal.clear();
  }
}
