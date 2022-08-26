import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';

class AtClientUtil {
  static String buildKey(UpdateVerbBuilder builder) {
    var updateKey = '';
    if (builder.isPublic) {
      updateKey += 'public:';
    }
    if (builder.sharedWith != null && builder.sharedWith!.isNotEmpty) {
      updateKey += '${AtUtils.formatAtSign(builder.sharedWith!)}:';
    }
    updateKey += builder.atKey!;
    if (builder.sharedBy != null) {
      updateKey += AtUtils.formatAtSign(builder.sharedBy)!;
    }
    return updateKey;
  }

  @Deprecated('use RemoteSecondary.findSecondaryUrl')
  static Future<String> findSecondary(
      String toAtSign, String rootDomain, int rootPort) async {
    var secondaryUrl =
        await AtLookupImpl.findSecondary(toAtSign, rootDomain, rootPort);
    if (secondaryUrl == null) {
      throw SecondaryNotFoundException(
          'No secondary url found for atsign: $toAtSign');
    }
    return secondaryUrl;
  }

  static List<String> getSecondaryInfo(String? url) {
    var result = <String>[];
    if (url != null && url.contains(':')) {
      var arr = url.split(':');
      result.add(arr[0]);
      result.add(arr[1]);
    }
    return result;
  }

  static String signChallenge(String challenge, String privateKey) {
    var key = RSAPrivateKey.fromString(privateKey);
    challenge = challenge.trim();
    var signature =
        key.createSHA256Signature(utf8.encode(challenge) as Uint8List);
    return base64Encode(signature);
  }

  static bool isAnyNotNull(
      {dynamic a1,
      dynamic a2,
      dynamic a3,
      dynamic a4,
      dynamic a5,
      dynamic a6}) {
    return ((a1 != null) ||
            (a2 != null) ||
            (a3 != null) ||
            (a4 != null) ||
            (a5 != null)) ||
        (a6 != null);
  }

  static Metadata? prepareMetadata(
      Map<String, dynamic>? metadataMap, bool? isPublic) {
    if (metadataMap == null) {
      return null;
    }
    var metadata = Metadata();
    metadata.expiresAt =
        (metadataMap['expiresAt'] != null && metadataMap['expiresAt'] != 'null')
            ? DateTime.parse(metadataMap['expiresAt'])
            : null;
    metadata.availableAt = (metadataMap['availableAt'] != null &&
            metadataMap['availableAt'] != 'null')
        ? DateTime.parse(metadataMap['availableAt'])
        : null;
    metadata.refreshAt =
        (metadataMap[REFRESH_AT] != null && metadataMap[REFRESH_AT] != 'null')
            ? DateTime.parse(metadataMap[REFRESH_AT])
            : null;
    metadata.createdAt =
        (metadataMap[CREATED_AT] != null && metadataMap[CREATED_AT] != 'null')
            ? DateTime.parse(metadataMap[CREATED_AT])
            : null;
    metadata.updatedAt =
        (metadataMap[UPDATED_AT] != null && metadataMap[UPDATED_AT] != 'null')
            ? DateTime.parse(metadataMap[UPDATED_AT])
            : null;
    metadata.ttr = metadataMap[AT_TTR];
    metadata.ttl = metadataMap[AT_TTL];
    metadata.ttb = metadataMap[AT_TTB];
    metadata.ccd = metadataMap[CCD];
    metadata.isBinary = metadataMap[IS_BINARY];
    metadata.isEncrypted = metadataMap[IS_ENCRYPTED];
    metadata.dataSignature = metadataMap[PUBLIC_DATA_SIGNATURE];
    metadata.sharedKeyEnc = metadataMap[SHARED_KEY_ENCRYPTED];
    metadata.pubKeyCS = metadataMap[SHARED_WITH_PUBLIC_KEY_CHECK_SUM];
    if (isPublic!) {
      metadata.isPublic = isPublic;
    }
    return metadata;
  }

  /// Accepts [AtKey] and returns [AtKey.key] with namespace appended
  /// Appends namespace if [atKey.metadata.namespaceAware] is set to true,
  /// else namespace is not appended
  static String getKeyWithNameSpace(
      AtKey atKey, AtClientPreference atClientPreference) {
    // Do not append namespace for encryption keys.
    if (!(atKey.metadata!.namespaceAware)) {
      return atKey.key!;
    }
    //Do not append namespace if already appended
    if (atKey.key?.substring(atKey.key!.lastIndexOf('.') + 1) ==
        atClientPreference.namespace) {
      return atKey.key!;
    }
    // If key does not have any namespace, append the namespace to the key.
    if (atKey.namespace.isNotNull) {
      return '${atKey.key}.${atKey.namespace!}';
    }
    if (atClientPreference.namespace.isNotNull) {
      return '${atKey.key}.${atClientPreference.namespace}';
    }
    return atKey.key!;
  }
}

class Tuple<T1, T2> {
  late T1 one;
  late T2 two;
}

/// Extending the String class to check null and empty.
extension NullCheck on String? {
  _isNull() {
    if (this == null || this!.isEmpty) {
      return true;
    }
    return false;
  }

  bool get isNull => _isNull();

  bool get isNotNull => !_isNull();
}
