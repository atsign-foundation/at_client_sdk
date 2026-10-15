import 'dart:io';

/// Deletes each of [directories] that exists, and returns the ones it
/// deleted.
///
/// A client that failed before opening created no store, and the error that
/// stopped it is the one its test reports, so an absent directory is skipped.
List<String> deleteStoresThatExist(Iterable<String> directories) {
  final deleted = <String>[];
  for (final path in directories) {
    final directory = Directory(path);
    if (!directory.existsSync()) continue;
    directory.deleteSync(recursive: true);
    deleted.add(path);
  }
  return deleted;
}
