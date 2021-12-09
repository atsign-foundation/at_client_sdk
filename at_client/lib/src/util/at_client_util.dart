import 'dart:convert';
import 'dart:typed_data';

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
      updateKey += AtUtils.formatAtSign(builder.sharedBy)!;
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
}
