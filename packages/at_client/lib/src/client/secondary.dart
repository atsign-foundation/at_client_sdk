import 'package:at_commons/at_builders.dart';

abstract class Secondary {
  /// Executes a verb on this secondary.
  ///
  /// [sync] is retained for back-compat and is ignored. [cameFromServer]
  /// signals the write is a server-originated replay (LocalSecondary
  /// uses it to skip enqueuing the write into the client→server sync
  /// queue); other implementations may ignore it.
  Future<String?> executeVerb(VerbBuilder builder,
      {bool? sync, bool cameFromServer = false});
}
