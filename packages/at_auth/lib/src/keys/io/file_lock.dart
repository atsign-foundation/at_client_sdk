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
/// is dead. Breaking claims the file by rename before deleting, so a breaker
/// racing a faster breaker cannot delete the fresh lock that replaced the
/// corpse. The lock file's content (pid + acquisition time) doubles as the
/// holder's release token: a holder whose lock was broken while it ran finds
/// someone else's content at release and leaves it in place.
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
    final token = await _acquire();
    try {
      return await action();
    } finally {
      _release(token);
    }
  }

  Future<String> _acquire() async {
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
        final token = '$pid ${DateTime.now().toUtc().toIso8601String()}\n';
        await sink.writeAsString(token);
        return token;
      } on FileSystemException {
        // Held by someone. Stale?
        try {
          final stat = File(lockPath).statSync();
          if (DateTime.now().difference(stat.modified) > staleAfter) {
            _breakStale();
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

  /// Breaks a lock whose mtime says its holder is dead.
  ///
  /// Deleting by path would be wrong: between our staleness check and the
  /// delete, a faster breaker may have broken the same corpse and a fresh
  /// holder acquired — a bare delete would then evict the fresh holder and
  /// let two contenders into the critical section. Renaming claims exactly
  /// one file, so re-checking the claimed file's age tells us which one we
  /// got: the corpse (delete it) or a live holder's lock (put it straight
  /// back and queue behind it).
  void _breakStale() {
    final claimPath =
        '$lockPath.breaking.$pid.${DateTime.now().microsecondsSinceEpoch}';
    final claimed = File(lockPath).renameSync(claimPath);
    if (DateTime.now().difference(claimed.statSync().modified) > staleAfter) {
      claimed.deleteSync();
    } else {
      claimed.renameSync(lockPath);
    }
  }

  void _release(String token) {
    try {
      final lockFile = File(lockPath);
      if (lockFile.readAsStringSync() == token) {
        lockFile.deleteSync();
      }
      // Someone else's content means our lock was broken as stale and a new
      // holder has since acquired — deleting here would evict them.
    } on FileSystemException {
      // Already gone — a stale-breaker took it. The next holder's exclusive
      // create still serialises correctly.
    }
  }
}
