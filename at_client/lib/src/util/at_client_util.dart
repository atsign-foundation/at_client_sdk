import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';

class AtClientUtil {
  static String buildKey(UpdateVerbBuilder builder) {
    var updateKey = '';
    if (builder.isPublic) {
      updateKey += 'public:';
    }
    if (builder.sharedWith != null) {
      updateKey += '${AtUtils.formatAtSign(builder.sharedWith!)}:';
    }
    updateKey += builder.atKey!;
    if (builder.sharedBy != null) {
      updateKey += AtUtils.formatAtSign(builder.sharedBy!);
    }
    return updateKey;
  }

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

  /// Accepts the response from the [VerbBuilder] and returns the
  /// populated [AtValue] as a response.
  static AtValue prepareAtValue(String response, AtKey atKey) {
    var parsedResponse = DefaultResponseParser().parse(response);
    if (parsedResponse.response == 'null') {
      return AtValue()..value = 'null';
    }
    var decodedResponse = JsonUtils.decodeJson(parsedResponse.response);
    //Construct atValue
    var atValue = AtValue()
      ..value = decodedResponse['data']
      ..metadata = _prepareMetadata(decodedResponse['metaData'], atKey);
    return atValue;
  }

  static Metadata? _prepareMetadata(
      Map<String, dynamic>? metadataMap, AtKey atKey) {
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
    if (atKey.key!.contains('public:')) {
      metadata.isPublic = true;
    }
    return metadata;
  }
}
