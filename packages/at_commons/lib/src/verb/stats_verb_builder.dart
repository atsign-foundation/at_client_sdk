import 'package:at_commons/src/verb/verb_builder.dart';

/// Stats builder generates a command that returns various of the server statistics of current atSign.
/// ```
///  // specific stats
///  var builder = StatsVerbBuilder()..ids = '3,4';
///  // all stats
///  var builder = StatsVerbBuilder();
///  ```
class StatsVerbBuilder implements VerbBuilder {
  /// Comma separated stat ids.
  /// If no ids are supplied returns all the stats.
  /// 1. Inbound Connection statistics
  /// 2. Outbound Connection statistics
  /// 3. Sync statistics
  /// 4. Storage statistics
  /// 5. Most visited atSign statistics
  /// 6. Most read keys statistics
  String? statIds;

  /// Regular expression to filter keys.
  String? regex;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('stats');
    if (statIds != null) {
      serverCommandBuffer.write(':$statIds');
      if (regex != null) {
        serverCommandBuffer.write(':$regex');
      }
    }
    return (serverCommandBuffer..write('\n')).toString();
  }

  @override
  bool checkParams() {
    //#TODO check ids contain only number
    return true;
  }
}
