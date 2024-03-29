import 'dart:convert';
import 'package:crypton/crypton.dart';

/// Class responsible for signing the public key value using the
/// encryptedPrivateKey and returns the signedValue
@Deprecated('use at_chops signing method')
class SignInPublicData {
  static Future<String> signInData(
      dynamic value, String encryptedPrivateKey) async {
    var privateKey = RSAPrivateKey.fromString(encryptedPrivateKey);
    var dataSignature = privateKey.createSHA256Signature(utf8.encode(value));
    return base64Encode(dataSignature);
  }
}
