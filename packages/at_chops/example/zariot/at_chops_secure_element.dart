import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:at_chops/at_chops.dart';

import 'external_signer.dart';

class AtChopsSecureElement extends AtChopsImpl {
  late ExternalSigner externalSigner;
  AtChopsSecureElement(super.atChopsKeys);

  @override
  AtSigningResult sign(AtSigningInput signingInput) {
    final dataHash = sha256.convert(_getBytes(signingInput.data));
    var externalSignature = externalSigner.sign(dataHash.toString());
    if (externalSignature == null) {
      throw Exception('error while computing signature');
    }
    var base64Signature = base64Encode(externalSignature.codeUnits);
    final atSigningMetadata = AtSigningMetaData(signingInput.signingAlgoType,
        signingInput.hashingAlgoType, DateTime.now().toUtc());
    final atSigningResult = AtSigningResult()
      ..result = base64Signature
      ..atSigningMetaData = atSigningMetadata
      ..atSigningResultType = AtSigningResultType.string;
    return atSigningResult;
  }

  Uint8List _getBytes(dynamic data) {
    if (data is String) {
      // ignore: unnecessary_cast
      return utf8.encode(data) as Uint8List;
    } else if (data is Uint8List) {
      return data;
    } else {
      throw Exception('Unrecognized type of data: $data');
    }
  }

  @override
  String readPublicKey(String publicKeyId) {
    return externalSigner.getPublicKey(publicKeyId).toLowerCase();
  }
}
