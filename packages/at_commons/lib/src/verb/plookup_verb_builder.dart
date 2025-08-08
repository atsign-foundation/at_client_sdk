import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/verb_util.dart';

/// Plookup builder generates a command to lookup public value of [atKey] on secondary server of another atSign [sharedBy].
/// e.g If @alice has a public key e.g. public:phone@alice then use this builder to
/// lookup value of phone@alice from bob's secondary
/// ```
/// var builder = PlookupVerbBuilder()..key=’phone’..atSign=’alice’;
/// ```
class PLookupVerbBuilder extends AbstractVerbBuilder {
  String? operation;

  // if set to true, returns the value of key on the remote server instead of the cached copy
  bool bypassCache = false;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('plookup:');
    if (bypassCache == true) {
      serverCommandBuffer.write('bypassCache:$bypassCache:');
    }
    if (operation != null) {
      serverCommandBuffer.write('$operation:');
    }
    serverCommandBuffer.write(atKey.key);
    return (serverCommandBuffer
          ..write('${VerbUtil.formatAtSign(atKey.sharedBy)}\n'))
        .toString();
  }

  @override
  bool checkParams() {
    return atKey.key.isNotEmpty && atKey.sharedBy != null;
  }
}
