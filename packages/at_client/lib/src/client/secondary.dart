import 'package:at_commons/at_builders.dart';

abstract class Secondary {
  /// Executes a verb on this secondary.
  ///
  /// [cameFromServer] signals the write is a server-originated replay
  /// (LocalSecondary uses it to skip enqueuing the write into the
  /// client→server sync queue); other implementations may ignore it.
  Future<String?> executeVerb(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it, so passing it suppresses '
          'nothing. Whether a local write is enqueued for '
          'client→server sync is decided by cameFromServer. '
          'Removed in 4.0.')
      bool? sync,
      bool cameFromServer = false});
}
