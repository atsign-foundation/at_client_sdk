import 'package:at_commons/at_commons.dart';

class AtKeys {
  AtBytes? apkamPublicKey;
  AtBytes? apkamPrivateKey;
  AtBytes? defaultEncryptionPublicKey;
  AtBytes? defaultEncryptionPrivateKey;
  AtBytes? defaultSelfEncryptionKey;
  AtBytes? apkamSymmetricKey;
  String? enrollmentId;

  AtKeys();

  Map<String, dynamic> toJson() {
    return {
      'apkamPublicKey': apkamPublicKey?.toString(),
      'apkamPrivateKey': apkamPrivateKey?.toString(),
      'defaultEncryptionPublicKey': defaultEncryptionPublicKey?.toString(),
      'defaultEncryptionPrivateKey': defaultEncryptionPrivateKey?.toString(),
      'defaultSelfEncryptionKey': defaultSelfEncryptionKey?.toString(),
      'apkamSymmetricKey': apkamSymmetricKey?.toString(),
      'enrollmentId': enrollmentId
    };
  }

  factory AtKeys.fromJson(Map<String, dynamic> json) {
    return AtKeys()
      ..apkamPublicKey = AtBytes.fromString(json['apkamPublicKey'])
      ..apkamPrivateKey = AtBytes.fromString(json['apkamPrivateKey'])
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(json['defaultEncryptionPublicKey'])
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(json['defaultEncryptionPrivateKey'])
      ..defaultSelfEncryptionKey =
          AtBytes.fromString(json['defaultSelfEncryptionKey'])
      ..apkamSymmetricKey = AtBytes.fromString(json['apkamSymmetricKey'])
      ..enrollmentId = json['enrollmentId'];
  }
}
