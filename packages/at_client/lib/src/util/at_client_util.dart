import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';

class AtClientUtil {
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
    var signature = key.createSHA256Signature(utf8.encode(challenge));
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
      Map<String, dynamic>? metadataMap, bool isPublic,
      {bool isCached = false}) {
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
    metadata.refreshAt = (metadataMap[AtConstants.refreshAt] != null &&
            metadataMap[AtConstants.refreshAt] != 'null')
        ? DateTime.parse(metadataMap[AtConstants.refreshAt])
        : null;
    metadata.createdAt = (metadataMap[AtConstants.createdAt] != null &&
            metadataMap[AtConstants.createdAt] != 'null')
        ? DateTime.parse(metadataMap[AtConstants.createdAt])
        : null;
    metadata.updatedAt = (metadataMap[AtConstants.updatedAt] != null &&
            metadataMap[AtConstants.updatedAt] != 'null')
        ? DateTime.parse(metadataMap[AtConstants.updatedAt])
        : null;
    metadata.ttr = metadataMap[AtConstants.ttr];
    metadata.ttl = metadataMap[AtConstants.ttl];
    metadata.ttb = metadataMap[AtConstants.ttb];
    metadata.ccd = metadataMap[AtConstants.ccd];
    metadata.isBinary = metadataMap[AtConstants.isBinary];
    metadata.isEncrypted = metadataMap[AtConstants.isEncrypted];
    metadata.dataSignature = metadataMap[AtConstants.publicDataSignature];
    metadata.sharedKeyEnc = metadataMap[AtConstants.sharedKeyEncrypted];
    metadata.pubKeyCS = metadataMap[AtConstants.sharedWithPublicKeyCheckSum];
    metadata.encoding = metadataMap[AtConstants.encoding];
    metadata.encKeyName = metadataMap[AtConstants.encryptingKeyName];
    metadata.encAlgo = metadataMap[AtConstants.encryptingAlgo];
    metadata.ivNonce = metadataMap[AtConstants.ivOrNonce];
    metadata.skeEncKeyName =
        metadataMap[AtConstants.sharedKeyEncryptedEncryptingKeyName];
    metadata.skeEncAlgo =
        metadataMap[AtConstants.sharedKeyEncryptedEncryptingAlgo];
    metadata.isPublic = isPublic;
    metadata.isCached = isCached;

    return metadata;
  }

  /// Accepts [AtKey] and returns [AtKey.key] with namespace appended
  /// Appends namespace if [atKey.metadata.namespaceAware] is set to true,
  /// else namespace is not appended
  static String getKeyWithNameSpace(
      AtKey atKey, AtClientPreference atClientPreference) {
    // If metadata is null, initialize with new Metadata.
    atKey.metadata ??= Metadata();
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

  // TODO Remove this once AtUtils.fixAtSign accepts and returns String?
  static String? fixAtSign(String? atSign) {
    if (atSign == null) {
      return atSign;
    } else {
      return AtUtils.fixAtSign(atSign);
    }
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

/// Parse [EncodingType] to String
extension ParseEncodingTypeToString on EncodingType {
  String toShortString() {
    return toString().split('.').last;
  }
}

CommitOp convertCommitOpSymbolToEnum(String commitOpSymbol) {
  switch (commitOpSymbol) {
    case '+':
      return CommitOp.UPDATE;
    case '#':
      return CommitOp.UPDATE_META;
    case '*':
      return CommitOp.UPDATE_ALL;
    case '-':
      return CommitOp.DELETE;
    default:
      return throw IllegalArgumentException(
          '$commitOpSymbol is not a valid CommitOperation symbol');
  }
}
