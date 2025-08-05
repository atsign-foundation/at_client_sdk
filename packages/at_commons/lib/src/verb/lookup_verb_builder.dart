import 'abstract_verb_builder.dart';

/// Lookup verb builder generates a command to lookup [atKey] on either the client user's secondary server(without authentication)
/// or secondary server of [sharedBy] (with authentication).
/// Assume @bob is the client atSign. @alice is atSign on another secondary server.
/// e.g if you want to lookup @bob:phone@alice on alice's secondary,
/// user this builder to lookup value of phone@alice from bob's secondary. Auth has to be true.
/// ```
/// var builder = LookupVerbBuilder()..key=’phone’..atSign=’alice’..auth=true;
/// ```
///
/// e.g if you want to lookup public key on bob's secondary without auth from bob's client.
/// ```
/// var builder = LookupVerbBuilder()..key=’phone’..atSign=’bob’;
/// ```
class LookupVerbBuilder extends AbstractVerbBuilder {
  /// Flag to specify whether to run this builder with or without auth.
  bool auth = false;

  String? operation;

  // if set to true, returns the value of key on the remote server instead of the cached copy
  bool bypassCache = false;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('lookup:');
    if (bypassCache == true) {
      serverCommandBuffer.write('bypassCache:$bypassCache:');
    }
    if (operation != null) {
      serverCommandBuffer.write('$operation:');
    }
    serverCommandBuffer.write('${atKey.toString()}\n');
    return serverCommandBuffer.toString();
  }

  @override
  bool checkParams() {
    return atKey.key.isNotEmpty && atKey.sharedBy != null;
  }
}
