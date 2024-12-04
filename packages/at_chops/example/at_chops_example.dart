import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:encrypt/encrypt.dart';

/// Usage:
/// Using new key pairs created at runtime
/// dart run at_chops_example.dart
/// or
/// Using key pairs from atKeys file
/// dart run at_chops_example.dart <path_to_atkeys_file>
void main(List<String> args) async {
  AtChops atChops;
  if (args.isNotEmpty) {
    var atKeysFilePath = args[0];
    if (!File(atKeysFilePath).existsSync()) {
      throw Exception('\n Unable to find .atKeys file : $atKeysFilePath');
    }
    String atAuthData = await File(atKeysFilePath).readAsString();
    Map<String, String> atKeysDataMap = <String, String>{};
    json.decode(atAuthData).forEach((String key, dynamic value) {
      atKeysDataMap[key] = value.toString();
    });
    atChops = _createAtChops(atKeysDataMap);
  } else {
    final atEncryptionKeyPair = AtChopsUtil
        .generateAtEncryptionKeyPair(); //use AtEncryptionKeyPair.create for using your own encryption key pair
    final atPkamKeyPair = AtChopsUtil
        .generateAtPkamKeyPair(); // use AtPkamKeyPair.create for using your own signing key pair
    // create AtChopsKeys instance using encryption and pkam key pair
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    // create an instance of AtChopsImpl
    atChops = AtChopsImpl(atChopsKeys);
  }

  var atEncryptionKeyPair = atChops.atChopsKeys.atEncryptionKeyPair;
  // 1 - Encryption and decryption using asymmetric key pair
  final data = 'Hello World';
  //1.1 encrypt the data using [atEncryptionKeyPair.publicKey]
  final encryptionResult =
      await atChops.encryptString(data, EncryptionKeyType.rsa2048);

  //1.2 decrypt the data using [atEncryptionKeyPair.privateKey]
  final decryptionResult = await atChops.decryptString(
      encryptionResult.result, EncryptionKeyType.rsa2048);
  assert(data == decryptionResult.result, true);

  // 2 - Signing and data verification using asymmetric key pair
  // Using sign() and verify()
  final dataToSign = 'sample data';
  // 2.1 create signing input and set signing and hashing algo type
  AtSigningInput signingInput = AtSigningInput(dataToSign);
  signingInput.signingAlgoType = SigningAlgoType.rsa2048;
  signingInput.hashingAlgoType = HashingAlgoType.sha512;
  AtSigningAlgorithm signingAlgorithm =
      DefaultSigningAlgo(atEncryptionKeyPair, signingInput.hashingAlgoType);
  signingInput.signingAlgorithm = signingAlgorithm;
  // 2.2 sign the data
  final dataSigningResult = atChops.sign(signingInput);

  // 2.3 create verification input and set signing and hashing algo type
  AtSigningVerificationInput? verificationInput = AtSigningVerificationInput(
      dataToSign,
      base64Decode(dataSigningResult.result),
      atEncryptionKeyPair!.atPublicKey.publicKey);
  verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
  verificationInput.hashingAlgoType = HashingAlgoType.sha512;
  AtSigningAlgorithm verifyAlgorithm = DefaultSigningAlgo(
      atEncryptionKeyPair, verificationInput.hashingAlgoType);
  verificationInput.signingAlgorithm = verifyAlgorithm;
  // 2.4 verify the signature
  AtSigningResult dataVerificationResult = atChops.verify(verificationInput);
  print('Signing result: ${dataVerificationResult.result}');
  assert(dataVerificationResult.result, true);
}

AtChops _createAtChops(Map<String, String> atKeysDataMap) {
  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
      _decryptValue(atKeysDataMap[AuthKeyType.encryptionPublicKey]!,
          atKeysDataMap[AuthKeyType.selfEncryptionKey]!)!,
      _decryptValue(atKeysDataMap[AuthKeyType.encryptionPrivateKey]!,
          atKeysDataMap[AuthKeyType.selfEncryptionKey]!)!);
  final atPkamKeyPair = AtPkamKeyPair.create(
      _decryptValue(atKeysDataMap[AuthKeyType.pkamPublicKey]!,
          atKeysDataMap[AuthKeyType.selfEncryptionKey]!)!,
      _decryptValue(atKeysDataMap[AuthKeyType.pkamPrivateKey]!,
          atKeysDataMap[AuthKeyType.selfEncryptionKey]!)!);
  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
  return AtChopsImpl(atChopsKeys);
}

class AuthKeyType {
  static const String pkamPublicKey = 'aesPkamPublicKey';
  static const String pkamPrivateKey = 'aesPkamPrivateKey';
  static const String encryptionPublicKey = 'aesEncryptPublicKey';
  static const String encryptionPrivateKey = 'aesEncryptPrivateKey';
  static const String selfEncryptionKey = 'selfEncryptionKey';
}

String? _decryptValue(String encryptedValue, String decryptionKey,
    {String? ivBase64}) {
  try {
    var aesKey = AES(Key.fromBase64(decryptionKey));
    var decrypter = Encrypter(aesKey);
    return decrypter.decrypt64(encryptedValue, iv: getIV(ivBase64));
  } on Exception catch (e, trace) {
    print(trace);
  } on Error catch (e) {
    print(e);
  }
  return null;
}

IV getIV(String? ivBase64) {
  if (ivBase64 == null) {
// From the bad old days when we weren't setting IVs
    return IV(Uint8List(16));
  } else {
    return IV.fromBase64(ivBase64);
  }
}
