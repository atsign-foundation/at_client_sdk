import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_commons/at_builders.dart';

/// Class responsible for returning the appropriate [VerbBuilder] for given [AtKey]
class LookUpBuilderManager {
  ///Returns a [VerbBuilder] for the given AtKey instance
  static VerbBuilder get(
      AtKey atKey, String currentAtSign, AtClientPreference atClientPreference,
      {GetRequestOptions? getRequestOptions}) {
    // If isPublic is true in metadata, the key is a public key, return PLookupVerbHandler.
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata.isPublic && !atKey.metadata.isCached)) {
      final plookUpVerbBuilder = PLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
          ..sharedBy = AtClientUtil.fixAtSign(atKey.sharedBy))
        ..operation = 'all';
      if (getRequestOptions != null && getRequestOptions.bypassCache == true) {
        plookUpVerbBuilder.bypassCache = true;
      }
      return plookUpVerbBuilder;
    }
    // If sharedBy is not equal to currentAtSign and isCached is false, return LookupVerbHandler
    if (atKey.sharedBy != currentAtSign &&
        (!atKey.metadata.isCached && !atKey.metadata.isPublic)) {
      final lookupVerbBuilder = LookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
          ..sharedBy = AtClientUtil.fixAtSign(atKey.sharedBy))
        ..auth = true
        ..operation = 'all';
      if (getRequestOptions != null && getRequestOptions.bypassCache == true) {
        lookupVerbBuilder.bypassCache = true;
      }
      return lookupVerbBuilder;
    }
    return LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = AtClientUtil.getKeyWithNameSpace(atKey, atClientPreference)
        ..sharedBy = AtClientUtil.fixAtSign(atKey.sharedBy)
        ..sharedWith = AtClientUtil.fixAtSign(atKey.sharedWith)
        ..metadata = (Metadata()
          ..isPublic = atKey.metadata.isPublic
          ..isCached = atKey.metadata.isCached)
        ..isLocal = atKey.isLocal)
      ..operation = 'all';
  }
}

/// Returns the instance of [Secondary] server.
///
/// Basing the verb, the appropriate instance of secondary server is returned.
class SecondaryManager {
  static Secondary getSecondary(AtClient atClient, VerbBuilder verbBuilder) {
    if (verbBuilder is LookupVerbBuilder ||
        verbBuilder is PLookupVerbBuilder ||
        verbBuilder is NotifyVerbBuilder ||
        verbBuilder is StatsVerbBuilder) {
      return atClient.getRemoteSecondary()!;
    }
    return atClient.getLocalSecondary()!;
  }
}
