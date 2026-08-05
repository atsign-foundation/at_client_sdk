import 'dart:io';

/// An inter-process advisory lock for a keyfile's read-modify-write.
///
/// Why it exists (`at_client_sdk` `docs/projects/pq/decisions.md` 38.4):
/// several CLI apps routinely share one `.atKeys` file, and `flush` is a
/// read-validate-write. The write itself is atomic (temp + rename) and
/// `validateMapUpdate` *detects* a candidate that drops existing material —
/// but two processes that both read before either writes both pass
/// validation, and the second rename silently discards the first's addition.
/// The severe case is a conveyed nskey private that appears filed and is not:
/// records that can never be read, presenting weeks later as corruption.
///
/// The lock is a sibling `<keyfile>.lock` created with `O_EXCL`, which is
/// atomic on every platform Dart runs on. It is advisory: only paths that
/// take it are serialised, which is exactly the keyfile read-modify-write.
///
/// **Staleness.** A crashed process must not deadlock every future run, so a
/// lock older than [staleAfter] is broken and retaken. That is safe here
/// because the critical section is a handful of file operations — a healthy
/// holder is done in milliseconds, and one that has held for thirty seconds
/// is dead. The lock file carries the holder's pid and acquisition time for
/// diagnosis, not for correctness.
class AtKeysFileLock {
  /// The file the lock protects; the lock file sits beside it.
  final String protectedPath;

  /// How long to keep retrying before giving up with a [FileSystemException].
  /// Bounded, because an unbreakable wait inside key-material code turns a
  /// stuck sibling process into a hung app with no diagnosis.
  final Duration timeout;

  /// The age past which a held lock is presumed abandoned and broken.
  final Duration staleAfter;

  /// How long to sleep between acquisition attempts.
  final Duration pollInterval;

  const AtKeysFileLock(
    this.protectedPath, {
    this.timeout = const Duration(seconds: 10),
    this.staleAfter = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 50),
  });

  String get lockPath => '$protectedPath.lock';

  /// Runs [action] holding the lock, releasing it however [action] exits.
  Future<T> synchronized<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    final deadline = DateTime.now().add(timeout);
    final parent = File(lockPath).parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    while (true) {
      try {
        // The atomic step: an O_EXCL create fails if the file exists, so
        // exactly one contender wins however many race.
        final sink = await File(lockPath).create(exclusive: true);
        await sink.writeAsString(
            '$pid ${DateTime.now().toUtc().toIso8601String()}\n');
        return;
      } on FileSystemException {
        // Held by someone. Stale?
        try {
          final stat = File(lockPath).statSync();
          if (DateTime.now().difference(stat.modified) > staleAfter) {
            // Presumed dead. Delete and contend again — the exclusive create
            // above stays the only way in, so two breakers cannot both win.
            File(lockPath).deleteSync();
            continue;
          }
        } on FileSystemException {
          // The holder released between our failure and the stat — contend.
          continue;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw FileSystemException(
              'Could not acquire the keyfile lock within $timeout — another '
              'process holds it and is not releasing. Nothing was written.',
              lockPath);
        }
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  void _release() {
    try {
      File(lockPath).deleteSync();
    } on FileSystemException {
      // Already gone — a stale-breaker took it. The next holder's exclusive
      // create still serialises correctly.
    }
  }
}
