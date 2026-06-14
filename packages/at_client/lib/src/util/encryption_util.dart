import 'dart:typed_data';
import 'dart:convert';

import 'package:at_chops/at_chops.dart'
    show AtPrivateKey, AtPublicKey, DefaultHash, RsaEncryptionAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:encrypt/encrypt.dart';

//#TODO Migrate the remaining AES methods (encryptValue/decryptValue/
// encryptBytes/decryptBytes/generate*/getIV) off package:encrypt onto
// at_chops and move this class to the test folder in the next major release.
// They are blocked on at_chops's AES being async (AESEncryptionAlgo) while
// these are sync — see PHASE6_AT_CHOPS_MIGRATION_AUDIT.md. RSA + md5 already
// route through at_chops.
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
    // Mirrors crypton's RSAPublicKey.encrypt(String):
    // base64(encryptData(utf8(msg))). RsaEncryptionAlgo.encrypt wraps the
    // same encryptData, so the output is interchangeable with the old path.
    final algo = RsaEncryptionAlgo()
      ..atPublicKey = AtPublicKey.fromString(publicKey);
    return base64Encode(algo.encrypt(Uint8List.fromList(utf8.encode(aesKey))));
  }

  @Deprecated('Use AtChops package')
  static String decryptKey(String aesKey, String privateKey) {
    // Mirrors crypton's RSAPrivateKey.decrypt(String):
    // utf8.decode(decryptData(base64.decode(msg))).
    final algo = RsaEncryptionAlgo()
      ..atPrivateKey = AtPrivateKey.fromString(privateKey);
    return utf8.decode(algo.decrypt(base64Decode(aesKey)));
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

  static String md5CheckSum(String data) {
    // DefaultHash.hash = md5.convert(data).toString() — identical output.
    return DefaultHash().hash(utf8.encode(data));
  }
}
