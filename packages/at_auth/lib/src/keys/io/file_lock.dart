import 'dart:io';

import 'package:meta/meta.dart';

/// An inter-process advisory lock for a keyfile's read-modify-write.
///
/// Why it exists: several CLI apps routinely share one `.atKeys` file, and
/// `flush` is a
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
      File? created;
      // Kept so a timeout can name the real failure. A create that fails
      // because the directory is not writable, or the disk is full, is
      // indistinguishable here from one that failed because the lock is held
      // — and it is not something contention will ever fix.
      FileSystemException? lastFailure;
      try {
        // The atomic step: an O_EXCL create fails if the file exists, so
        // exactly one contender wins however many race.
        created = await File(lockPath).create(exclusive: true);
      } on FileSystemException catch (e) {
        created = null; // Held by someone — the contention path below.
        lastFailure = e;
      }

      if (created != null) {
        final token = '$pid ${DateTime.now().toUtc().toIso8601String()}\n';
        try {
          await created.writeAsString(token, flush: true);
          return token;
        } on FileSystemException {
          // The create succeeded but the token did not land (disk full, a
          // vanished parent). An empty lock we hold could never be released
          // by token comparison — a guaranteed stall for every contender
          // until staleness breaks it — so take it back down and let the
          // real IO failure propagate rather than proceed holding an
          // unreleasable lock, or retry a failure contention cannot fix.
          try {
            created.deleteSync();
          } on FileSystemException {
            // Already gone; nothing left to leak.
          }
          rethrow;
        }
      }

      // Held by someone. Stale?
      try {
        final stat = File(lockPath).statSync();
        if (DateTime.now().difference(stat.modified) > staleAfter) {
          _breakStale();
        }
      } on FileSystemException catch (e) {
        // Either the holder released between our failure and the stat, or
        // there is no lock file at all because the create above failed for a
        // reason contention cannot fix.
        lastFailure = e;
      }
      // ⚠️ Every outcome above falls through to here. Both of these used to
      // `continue`, which skipped the deadline AND the sleep: a create failing
      // on an unwritable directory then left nothing to stat, so the loop spun
      // on the CPU without bound and the documented timeout never applied.
      // Measured before the change: still spinning after 4s against a 300ms
      // timeout.
      if (DateTime.now().isAfter(deadline)) {
        throw FileSystemException(
            'Could not acquire the keyfile lock within $timeout. Nothing was '
            'written.'
            '${lastFailure == null ? ' Another process holds it and is not releasing.' : ' The last failure was: $lastFailure'}',
            lockPath);
      }
      await Future<void>.delayed(pollInterval);
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
    try {
      final claimed = File(lockPath).renameSync(claimPath);
      if (DateTime.now().difference(claimed.statSync().modified) > staleAfter) {
        claimed.deleteSync();
      } else {
        restoreClaimed(claimed);
      }
    } on FileSystemException {
      // The corpse vanished between our staleness check and the rename — the
      // holder released, or a faster breaker took it. Either way there is
      // nothing left to break; the caller loops and contends for the fresh
      // state. Letting this propagate would crash an acquire that merely
      // raced a release.
    }
  }

  /// Puts a claimed lock file back, unless someone has taken [lockPath] while
  /// we were inspecting it.
  ///
  /// Both [_breakStale] and [_release] rename [lockPath] aside before deciding
  /// what to do with it, and that rename leaves the path VACANT — measured: a
  /// contender's `create(exclusive: true)` succeeds there, where it fails
  /// against a lock simply held. In the common cases that is harmless, because
  /// both callers then delete the file they claimed and the new holder keeps
  /// its lock. It is the restore that does damage: `renameSync` replaces its
  /// target silently, so putting the claimed file back over a lock taken since
  /// evicts a live holder AND leaves a stale timestamp in its place, which the
  /// next contender breaks — two processes in the critical section, which is
  /// the one thing this class exists to prevent.
  ///
  /// ⚠️ This NARROWS that window rather than closing it: the existsSync and
  /// the rename are still two steps. Closing it properly means never vacating
  /// [lockPath] to inspect it — OS advisory locking via
  /// `RandomAccessFile.lock`, which is a different design from a lock file.
  /// Exposed only for testing: both callers reach it inside a fully
  /// synchronous sequence, so the branch where someone acquired during the
  /// window cannot be driven from a single isolate.
  @visibleForTesting
  void restoreClaimed(File claimed) {
    if (File(lockPath).existsSync()) {
      // Someone acquired while we were inspecting. Theirs is the live lock and
      // the one we hold is spent, so drop ours rather than overwrite theirs.
      claimed.deleteSync();
      return;
    }
    claimed.renameSync(lockPath);
  }

  void _release(String token) {
    // Claim-by-rename, the same discipline as [_breakStale]: a bare
    // read-then-delete has a window in which a stale-breaker could replace
    // our (over-held) lock with a new holder's between the two steps, and
    // the delete would evict that live holder. Renaming claims exactly one
    // file; reading the claim tells us whose it was.
    final claimPath =
        '$lockPath.releasing.$pid.${DateTime.now().microsecondsSinceEpoch}';
    try {
      final claimed = File(lockPath).renameSync(claimPath);
      if (claimed.readAsStringSync() == token) {
        claimed.deleteSync();
      } else {
        // Someone else's content: our lock was broken as stale and a new
        // holder has since acquired. Put their lock straight back.
        restoreClaimed(claimed);
      }
    } on FileSystemException {
      // Already gone — a stale-breaker took it. The next holder's exclusive
      // create still serialises correctly.
    }
  }
}
