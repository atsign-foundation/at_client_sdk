import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyAdvertisementRecordName;
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show apskRecordName;
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_commons/at_builders.dart';

/// Class responsible for returning the appropriate [VerbBuilder] for given [AtKey]
class LookUpBuilderManager {
  ///Returns a [VerbBuilder] for the given AtKey instance
  ///
  /// A lookup of an nskey advertisement or an `_apsk` record always bypasses
  /// the cache, whatever [getRequestOptions] asks, so a cached copy that some
  /// writer gave a `ttr` is never served in place of the owner's record.
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
      if (_bypassesCache(plookUpVerbBuilder.atKey.key, getRequestOptions)) {
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
      if (_bypassesCache(lookupVerbBuilder.atKey.key, getRequestOptions)) {
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

bool _bypassesCache(String name, GetRequestOptions? options) =>
    options?.bypassCache == true ||
    name.startsWith('$nskeyAdvertisementRecordName.') ||
    name.startsWith('$apskRecordName.');

class SecondaryManager {
  /// - If [useRemoteAtServer] is true, return RemoteLocalPref.remoteOnly
  /// - Else return [remoteLocalPref], or [RemoteLocalPref.localOnly]
  /// if [remoteLocalPref] is null
  static RemoteLocalPref getRemoteLocalPrefForOp(
    bool? useRemoteAtServer,
    RemoteLocalPref? remoteLocalPref,
  ) {
    if (useRemoteAtServer == true) {
      return RemoteLocalPref.remoteOnly;
    } else if (useRemoteAtServer == false) {
      return RemoteLocalPref.localOnly;
    } else {
      return remoteLocalPref ?? RemoteLocalPref.localOnly;
    }
  }

  /// - Return the [atClient]'s localSecondary or remoteSecondary as appropriate.
  /// - Always returns the remoteSecondary if the [verbBuilder] is Lookup,
  /// PLookup, Notify or Stats.
  /// - Otherwise returns local or remote based on the [prefForOp]
  static Secondary getSecondary(
    AtClient atClient,
    VerbBuilder verbBuilder,
    RemoteLocalPref prefForOp,
  ) {
    if (verbBuilder is LookupVerbBuilder ||
        verbBuilder is PLookupVerbBuilder ||
        verbBuilder is NotifyVerbBuilder ||
        verbBuilder is StatsVerbBuilder) {
      return atClient.getRemoteSecondary()!;
    }

    switch (prefForOp) {
      case RemoteLocalPref.localOnly:
        return atClient.getLocalSecondary()!;
      case RemoteLocalPref.remoteOnly:
        return atClient.getRemoteSecondary()!;
    }
  }
}
