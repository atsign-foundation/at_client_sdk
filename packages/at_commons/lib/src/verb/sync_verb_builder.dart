import 'package:at_commons/at_builders.dart';

class SyncVerbBuilder implements VerbBuilder {
  late int commitId;

  String? regex;

  int limit = 10;

  bool isPaginated = false;

  int? skipDeletesUntil;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('sync:');
    if (isPaginated) {
      serverCommandBuffer.write('from:');
    }
    serverCommandBuffer.write('$commitId');
    if (isPaginated) {
      serverCommandBuffer.write(':limit:$limit');
    }
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
