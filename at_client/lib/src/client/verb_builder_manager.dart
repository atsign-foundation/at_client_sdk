import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for returning the appropriate [VerbBuilder] for given [AtKey]
class LookUpBuilderManager {
  ///Returns a [VerbBuilder] for the given AtKey instance
  static VerbBuilder get(AtKey atKey, String currentAtSign) {
    // If isPublic is true in metadata, the key is a public key, return PLookupVerbHandler.
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            atKey.metadata!.isPublic! &&
            !atKey.metadata!.isCached)) {
      return PLookupVerbBuilder()
        ..atKey = _getKeyWithNameSpace(atKey)
        ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
        ..operation = 'all';
    }
    // If sharedBy is not equal to currentAtSign and isCached is false, return LookupVerbHandler
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            !atKey.metadata!.isCached &&
            !atKey.metadata!.isPublic!)) {
      return LookupVerbBuilder()
        ..atKey = _getKeyWithNameSpace(atKey)
        ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
        ..auth = true
        ..operation = 'all';
    }
    return LLookupVerbBuilder()
      ..atKey = _getKeyWithNameSpace(atKey)
      ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
      ..sharedWith = AtUtils.formatAtSign(atKey.sharedWith)
      ..isPublic = (atKey.metadata != null && atKey.metadata?.isPublic != null)
          ? atKey.metadata!.isPublic!
          : false
      ..isCached = (atKey.metadata != null && atKey.metadata?.isCached != null)
          ? atKey.metadata!.isCached
          : false
      ..operation = 'all';
  }
}

/// Accepts [AtKey] and returns [AtKey.key] with namespace appended
/// Appends namespace if [atKey.metadata.namespaceAware] is set to true,
/// else namespace is not appended
String _getKeyWithNameSpace(AtKey atKey) {
  // Do not append namespace for encryption keys.
  if (!(atKey.metadata!.namespaceAware)) {
    return atKey.key!;
  }
  //Do not append namespace if already appended
  if (atKey.key?.substring(atKey.key!.lastIndexOf('.') + 1) ==
      AtClientManager.getInstance().atClient.getPreferences()?.namespace) {
    return atKey.key!;
  }
  // If key does not have any namespace, append the namespace to the key.
  if (atKey.namespace != null && atKey.namespace!.isNotEmpty) {
    return '${atKey.key}.${atKey.namespace!}';
  }
  if (AtClientManager.getInstance().atClient.getPreferences()!.namespace !=
      null) {
    return '${atKey.key}.${AtClientManager.getInstance().atClient.getPreferences()!.namespace}';
  }
  return atKey.key!;
}

class SecondaryManager {
  static Secondary getSecondary(VerbBuilder verbBuilder) {
    if (verbBuilder is LookupVerbBuilder ||
        verbBuilder is PLookupVerbBuilder ||
        verbBuilder is NotifyVerbBuilder ||
        verbBuilder is StatsVerbBuilder) {
      return AtClientManager.getInstance().atClient.getRemoteSecondary()!;
    }
    return AtClientManager.getInstance().atClient.getLocalSecondary()!;
  }
}
