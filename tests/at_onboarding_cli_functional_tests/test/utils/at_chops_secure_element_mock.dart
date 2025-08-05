import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:elliptic/elliptic.dart';

class AtChopsSecureElementMock extends AtChopsImpl {
  AtChopsSecureElementMock(AtChopsKeys atChopsKeys) : super(atChopsKeys);

  final eccAlgo = EccSigningAlgo();
  late PrivateKey eccPrivateKey;
  late PublicKey eccPublicKey;

  // initialising the public and private keys;
  void init() {
    var ec = getSecp256r1();
    eccPrivateKey = ec.generatePrivateKey();
    eccAlgo.privateKey = eccPrivateKey;
    eccPublicKey = eccPrivateKey.publicKey;
  }

  @override
  AtSigningResult sign(AtSigningInput signingInput) {
    var externalSignature = eccAlgo.sign(_getBytes(signingInput.data));
    String base64Signature = base64Encode(externalSignature);
    final atSigningMetadata = AtSigningMetaData(signingInput.signingAlgoType,
        signingInput.hashingAlgoType, DateTime.now().toUtc());
    final atSigningResult = AtSigningResult()
      ..result = base64Signature
      ..atSigningMetaData = atSigningMetadata
      ..atSigningResultType = AtSigningResultType.string;
    print('at signing result: $atSigningResult');
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
    print('public key in read public key: ${eccPublicKey.toString()}');
    return eccPublicKey.toString();
  }
}
