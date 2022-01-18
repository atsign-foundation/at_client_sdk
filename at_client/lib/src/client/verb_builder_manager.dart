
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

class LookUpBuilderManager {
  ///Returns a [VerbBuilder] for the given Atkey instance.
  static VerbBuilder get(AtKey atKey, String currentAtSign) {
    // If isPublic is true in metadata, the key is a public key, return PLookupVerbHandler.
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            atKey.metadata!.isPublic &&
            !atKey.metadata!.isCached)) {
      return PLookupVerbBuilder()
        ..atKey = atKey.key
        ..sharedBy = atKey.sharedBy
        ..operation = 'all';
    }
    // If sharedBy is not equal to currentAtSign and isCached is false, return LookupVerbHandler
    if (atKey.sharedBy != currentAtSign &&
        (atKey.metadata != null &&
            !atKey.metadata!.isCached &&
            !atKey.metadata!.isPublic)) {
      return LookupVerbBuilder()
        ..atKey = atKey.key
        ..sharedBy = atKey.sharedBy
        ..auth = true
        ..operation = 'all';
    }
    return LLookupVerbBuilder()
      ..atKey = atKey.key
      ..sharedBy = atKey.sharedBy
      ..sharedWith = atKey.sharedWith
      ..isPublic = (atKey.metadata != null && atKey.metadata?.isPublic != null)
          ? atKey.metadata!.isPublic
          : false
      ..isCached = (atKey.metadata != null && atKey.metadata?.isCached != null)
          ? atKey.metadata!.isCached
          : false
      ..operation = 'all';
  }
}

class UpdateBuilderManager {
  static UpdateVerbBuilder prepareUpdateVerbBuilder(AtKey atKey) {
    var verbBuilder = UpdateVerbBuilder()
      ..atKey = atKey.key
      ..sharedBy = atKey.sharedBy
      ..sharedWith = atKey.sharedWith;
    if (atKey.metadata != null) {
      verbBuilder.isPublic = atKey.metadata!.isPublic;
      verbBuilder.isBinary = atKey.metadata?.isBinary;
      verbBuilder.isEncrypted = atKey.metadata?.isEncrypted;
      verbBuilder.ttl = atKey.metadata?.ttl;
      verbBuilder.ttb = atKey.metadata?.ttb;
      verbBuilder.ttr = atKey.metadata?.ttr;
      verbBuilder.ccd = atKey.metadata?.ccd;
    }
    return verbBuilder;
  }
}

class SecondaryManager {
  static Secondary getSecondary(VerbBuilder verbBuilder) {
    if (verbBuilder is LookupVerbBuilder ||
        verbBuilder is PLookupVerbBuilder ||
        verbBuilder is NotifyVerbBuilder ||
        verbBuilder is StatsVerbBuilder) {
      return AtClientManager.getInstance().atClient.getRemoteSecondary();
    }
    return AtClientManager.getInstance().atClient.getLocalSecondary();
  }
}
