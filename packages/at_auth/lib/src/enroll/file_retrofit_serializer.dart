import 'package:at_auth/src/enroll/retrofit_serializer.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/file_lock.dart';

/// How long a retrofit waits for the keyfile lock before giving up.
///
/// **Must be longer than [fileRetrofitLockStaleAfter]**, which is the ordering
/// [AtKeysFileLock] documents as required: a waiter only breaks an abandoned
/// lock once its mtime is past the staleness threshold, so a timeout that
/// expires first means a holder killed mid-retrofit leaves a lock nobody may
/// break, and every retrofit from that keyfile throws until it ages out.
const Duration fileRetrofitLockTimeout = Duration(minutes: 3);

/// The age past which a lock held by a dead process is presumed abandoned and
/// broken.
///
/// Generous, because the critical section spans a network round trip: the
/// heartbeat keeps a live holder's lock fresh, so this need only exceed a stall
/// long enough to be indistinguishable from a crash.
const Duration fileRetrofitLockStaleAfter = Duration(minutes: 2);

/// Serialises a retrofit against other processes holding the same `.atKeys`
/// file, by taking a lock beside it.
///
/// Assign to [retrofitSerializer] in a process whose keys live on disk:
///
/// ```dart
/// retrofitSerializer = fileRetrofitSerializer;
/// ```
///
/// A store that is not a [FileAtKeysIo] runs unserialised — it is process-local
/// by construction, so there is no second writer to exclude. The lock is held
/// across the whole read-decide-write sequence, which is wider than the flush
/// [FileAtKeysIo.update] guards on its own: the decision of what to write is
/// made from what the read returned, so a second process must not be reading
/// while this one is still deciding.
Future<T> fileRetrofitSerializer<T>(
    AtKeysIo keysIo, String atSign, Future<T> Function() action) {
  if (keysIo is FileAtKeysIo) {
    return AtKeysFileLock('${keysIo.filePath!(atSign)}.retrofit',
            timeout: fileRetrofitLockTimeout,
            staleAfter: fileRetrofitLockStaleAfter)
        .synchronized(action);
  }
  return action();
}
