import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';

/// Class responsible for signing the public key value using the
/// encryptedPrivateKey and returns the signedValue
class SignInPublicData {
  static Future<String> signInData(
      dynamic value, String encryptedPrivateKey) async {
    try {
      var privateKey = RSAPrivateKey.fromString(encryptedPrivateKey);
      var dataSignature =
          privateKey.createSHA256Signature(utf8.encode(value) as Uint8List);
      return base64Encode(dataSignature);
    } on Exception catch (e) {
      throw AtException(e.toString());
    }
  }
}
