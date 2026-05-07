import 'package:at_commons/at_builders.dart';

abstract class Secondary {
  /// Executes a verb on this secondary.
  ///
  /// [sync] requests an immediate post-write sync trigger (LocalSecondary
  /// only; remote-secondary implementations ignore it). [cameFromServer]
  /// signals the write is a server-originated replay (LocalSecondary
  /// uses it to skip enqueuing the write into the client→server sync
  /// queue introduced by `distributed-tickling-moler`); other
  /// implementations may ignore it.
  Future<String?> executeVerb(VerbBuilder builder,
      {bool? sync, bool cameFromServer = false});
}
