import 'package:at_auth/src/enroll/retrofit_serializer.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/file_lock.dart';

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
            timeout: const Duration(seconds: 30),
            staleAfter: const Duration(minutes: 2))
        .synchronized(action);
  }
  return action();
}
