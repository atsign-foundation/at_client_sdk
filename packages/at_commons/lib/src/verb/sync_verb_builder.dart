import 'package:at_commons/at_builders.dart';

class SyncVerbBuilder implements VerbBuilder {
  /// commitId from which entries will be synced from server to client
  late int commitId;

  /// if regex is set, then only keys matching the regex will be synced from server to client
  String? regex;

  /// Number of entries to be fetched from commit log on the server in one batch
  int limit = 25;

  @Deprecated(
      'This field is not used anymore even though it is set in client. Remove this in next major release')
  bool isPaginated = false;

  /// if skipDeletesUntil is set, then delete commit entries whose commitId is <= skipDeletesUntil will not be synced from server to client
  int? skipDeletesUntil;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('sync:');
    serverCommandBuffer.write('from:');
    serverCommandBuffer.write('$commitId');
    serverCommandBuffer.write(':limit:$limit');
    if (skipDeletesUntil != null) {
      serverCommandBuffer.write(':skipDeletesUntil:$skipDeletesUntil');
    }
    if (regex != null && regex!.isNotEmpty) {
      serverCommandBuffer.write(':$regex');
    }
    return (serverCommandBuffer..write('\n')).toString();
  }

  @override
  bool checkParams() {
    return true;
  }
}
