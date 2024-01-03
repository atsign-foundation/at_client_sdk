import 'dart:typed_data';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:crypton/crypton.dart';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:at_utils/at_logger.dart';

//#TODO Replace calls to methods in this class with at_chops methods and
// move this class to test folder in next major release
class EncryptionUtil {
  static final _logger = AtSignLogger('EncryptionUtil');

  static IV getIV(String? ivBase64) {
    if (ivBase64 == null) {
      // From the bad old days when we weren't setting IVs
      return IV(Uint8List(16));
    } else {
      return IV.fromBase64(ivBase64);
    }
  }

  static String generateAESKey() {
    return AES(Key.fromSecureRandom(32)).key.base64;
  }

  static String generateIV({int length = 16}) {
    return IV.fromSecureRandom(length).base64;
  }

  static String encryptValue(String value, String encryptionKey,
      {String? ivBase64}) {
    var aesEncrypter = Encrypter(AES(Key.fromBase64(encryptionKey)));
    var encryptedValue = aesEncrypter.encrypt(value, iv: getIV(ivBase64));
    return encryptedValue.base64;
  }

  static String decryptValue(String encryptedValue, String decryptionKey,
      {String? ivBase64}) {
    try {
      var aesKey = AES(Key.fromBase64(decryptionKey));
      var decrypter = Encrypter(aesKey);
      return decrypter.decrypt64(encryptedValue, iv: getIV(ivBase64));
    } on Exception catch (e, trace) {
      _logger
          .severe('Exception while decrypting value: ${e.toString()} $trace');
      throw AtKeyException(e.toString());
    } on Error catch (e) {
      // Catching error since underlying decryption library may throw Error e.g corrupt pad block
      _logger.severe('Error while decrypting value: ${e.toString()}');
      throw AtKeyException(e.toString(),
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
  }

  static String encryptKey(String aesKey, String publicKey) {
    var rsaPublicKey = RSAPublicKey.fromString(publicKey);
    return rsaPublicKey.encrypt(aesKey);
  }

  @Deprecated('Use AtChops package')
  static String decryptKey(String aesKey, String privateKey) {
    var rsaPrivateKey = RSAPrivateKey.fromString(privateKey);
    return rsaPrivateKey.decrypt(aesKey);
  }

  static List<int> encryptBytes(List<int> value, String encryptionKey,
      {String? ivBase64}) {
    var aesEncrypter = Encrypter(AES(Key.fromBase64(encryptionKey)));
    var encryptedValue = aesEncrypter.encryptBytes(value, iv: getIV(ivBase64));
    return encryptedValue.bytes;
  }

  static List<int> decryptBytes(List<int> encryptedValue, String decryptionKey,
      {String? ivBase64}) {
    var aesKey = AES(Key.fromBase64(decryptionKey));
    var decrypter = Encrypter(aesKey);
    return decrypter.decryptBytes(Encrypted(encryptedValue as Uint8List),
        iv: getIV(ivBase64));
  }

  @Deprecated('use at_chops hash method')
  static String md5CheckSum(String data) {
    return md5.convert(utf8.encode(data)).toString();
  }
}
