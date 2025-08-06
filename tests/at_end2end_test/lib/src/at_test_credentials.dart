import 'package:at_demo_data/at_demo_data.dart';

/// Use this credentials file for local testing. Place these contents in at_credentials.dart
class AtTestCredentials {
  static final firstAtSign = '@alice🛠';
  static final secondAtSign = '@bob🛠';
  static final thirdAtSign = '@colin🛠';
  static final fourthAtSign = '@eve🛠';
  static var credentialsMap = <String, Map>{
    firstAtSign: {
      'pkamPublicKey': pkamPublicKeyMap[firstAtSign],
      'pkamPrivateKey': pkamPrivateKeyMap[firstAtSign],
      'encryptionPublicKey': encryptionPublicKeyMap[firstAtSign],
      'encryptionPrivateKey': encryptionPrivateKeyMap[firstAtSign],
      'selfEncryptionKey': aesKeyMap[firstAtSign]
    },
    secondAtSign: {
      'pkamPublicKey': pkamPublicKeyMap[secondAtSign],
      'pkamPrivateKey': pkamPrivateKeyMap[secondAtSign],
      'encryptionPublicKey': encryptionPublicKeyMap[secondAtSign],
      'encryptionPrivateKey': encryptionPrivateKeyMap[secondAtSign],
      'selfEncryptionKey': aesKeyMap[secondAtSign]
    },
    thirdAtSign: {
      'pkamPublicKey': pkamPublicKeyMap[thirdAtSign],
      'pkamPrivateKey': pkamPrivateKeyMap[thirdAtSign],
      'encryptionPublicKey': encryptionPublicKeyMap[thirdAtSign],
      'encryptionPrivateKey': encryptionPrivateKeyMap[thirdAtSign],
      'selfEncryptionKey': aesKeyMap[thirdAtSign]
    },
    fourthAtSign: {
      'pkamPublicKey': pkamPublicKeyMap[fourthAtSign],
      'pkamPrivateKey': pkamPrivateKeyMap[fourthAtSign],
      'encryptionPublicKey': encryptionPublicKeyMap[fourthAtSign],
      'encryptionPrivateKey': encryptionPrivateKeyMap[fourthAtSign],
      'selfEncryptionKey': aesKeyMap[fourthAtSign]
    },
  };
}
