import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for returning the appropriate [VerbBuilder] for given [AtKey]
class LookUpBuilderManager {
  ///Returns a [VerbBuilder] for the given AtKey instance
  static VerbBuilder get(
      AtKey atKey, String currentAtSign, AtClientPreference atClientPreference,
      {GetRequestOptions? getRequestOptions}) {
    // If isPublic is true in metadata, the key is a public key, return PLookupVerbHandler.
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            atKey.metadata!.isPublic! &&
            !atKey.metadata!.isCached)) {
      final plookUpVerbBuilder = PLookupVerbBuilder()
        ..atKey = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
        ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
        ..operation = 'all';
      if (getRequestOptions != null && getRequestOptions.bypassCache == true) {
        plookUpVerbBuilder.bypassCache = true;
      }
      return plookUpVerbBuilder;
    }
    // If sharedBy is not equal to currentAtSign and isCached is false, return LookupVerbHandler
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            !atKey.metadata!.isCached &&
            !atKey.metadata!.isPublic!)) {
      final lookupVerbBuilder = LookupVerbBuilder()
        ..atKey = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
        ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
        ..auth = true
        ..operation = 'all';
      if (getRequestOptions != null && getRequestOptions.bypassCache == true) {
        lookupVerbBuilder.bypassCache = true;
      }
      return lookupVerbBuilder;
    }
    return LLookupVerbBuilder()
      ..atKey = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
      ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
      ..sharedWith = AtUtils.formatAtSign(atKey.sharedWith)
      ..isPublic = (atKey.metadata != null && atKey.metadata?.isPublic != null)
          ? atKey.metadata!.isPublic!
          : false
      ..isCached = (atKey.metadata != null && atKey.metadata?.isCached != null)
          ? atKey.metadata!.isCached
          : false
      ..isLocal = atKey.isLocal
      ..operation = 'all';
  }
}

/// Returns the instance of [Secondary] server.
///
/// Basing the verb, the appropriate instance of secondary server is returned.
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
