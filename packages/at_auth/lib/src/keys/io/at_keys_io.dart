import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';

import '../at_keys.dart' show AtKeys;
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// An interface that defines methods for reading AtKeys.
/// It can be implemented by classes that read AtKeys from different sources,
sealed class AtKeysIo {
  final passphraseCodec = const AtKeysPassphraseEnvelopeCodec();
  final assurance = const AtKeysAssurance();
  FutureOr<AtKeys> read(String atsign);
}

//todo: remove atsign from method signature
/// An interface that defines methods for AtKeys that can be written.
/// It can be implemented by classes that write AtKeys to different sources,
/// such as file system or keychain.
abstract class WrittenAtKeysIo extends AtKeysIo with KeyIOMixin {
  /// Create-only initial persist (fresh onboard); implementations throw if
  /// the target already exists. Use [flush] to persist later mutations.
  //todo: futureOr & Atsign types
  Future write(String atsign, AtKeys atKeys);

  /// Persists [atKeys] as the complete new state for [atsign].
  ///
  /// This is the runtime counterpart to [write]: mutate the in-memory
  /// [AtKeys] (e.g. [AtKeys.addKey]), then flush the whole object.
  /// Implementations backed by durable storage must not lose data: when a
  /// target already exists, validate that everything in it is preserved in
  /// [atKeys] (see [AtKeysAssurance.validateMapUpdate]), then rewrite. When
  /// no target exists, flush creates it — there is nothing to lose.
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    throw UnimplementedError('new method for v4 WrittenAtKeysIo');
  }
}

/// An interface that defines methods for AtKeys that can be generated.
/// It can be implemented by classes that generate AtKeys using different methods,
/// such as secure element.
abstract class GeneratedAtKeysIo extends AtKeysIo with KeyIOMixin {
  AtKeys generateKeys(String publicKeyId);
}

@Deprecated('legacy helpers for serialization')
mixin KeyIOMixin on AtKeysIo {
  final AtSignLogger _logger = AtSignLogger('AtKeysIOUtil -- legacy');

  @Deprecated(
      'legacy helpers for serialization, if we need to retain this turn it into a static helper')
  Future<AtKeys> decryptAtKeysWithSelfEncKey(
      Map<String, dynamic> jsonData, PkamAuthMode authMode) async {
    var securityKeys = AtKeys();
    String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey];
    var atChops =
        AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
    securityKeys.defaultSelfEncryptionKey = AtBytes.fromString(decryptionKey);
    securityKeys.defaultEncryptionPublicKey = AtBytes.fromString(
        (await atChops.decryptString(
                jsonData[auth_constants.defaultEncryptionPublicKey],
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result);
    securityKeys.defaultEncryptionPrivateKey = AtBytes.fromString(
        (await atChops.decryptString(
                jsonData[auth_constants.defaultEncryptionPrivateKey],
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result);
    securityKeys
        .apkamPublicKey = AtBytes.fromString((await atChops.decryptString(
            jsonData[auth_constants.apkamPublicKey], EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
        .result);
    // pkam private key will not be saved in keyfile if auth mode is sim/any other secure element.
    // decrypt the private key only when auth mode is keysFile
    if (authMode == PkamAuthMode.keysFile) {
      securityKeys.apkamPrivateKey = AtBytes.fromString(
          (await atChops.decryptString(jsonData[auth_constants.apkamPrivateKey],
                  EncryptionKeyType.aes256,
                  keyName: 'selfEncryptionKey',
                  iv: AtChopsUtil.generateIVLegacy()))
              .result);
    }
    securityKeys.apkamSymmetricKey =
        AtBytes.fromString(jsonData[auth_constants.apkamSymmetricKey] ?? '');
    securityKeys.enrollmentId = jsonData[AtConstants.enrollmentId];
    return securityKeys;
  }

  @Deprecated(
      'legacy helpers for serialization, if we need to retain this turn it into a static helper')
  Future<String> encryptAtKeysWithSelfEncKey(
      AtKeys atKeys, PkamAuthMode authMode, String atsign) async {
    Map<String, dynamic> atKeysMap = {};
    if (atKeys.defaultSelfEncryptionKey == null) {
      throw AtException('selfEncryptionKey is required to encrypt the atKeys');
    }
    var atChops = AtChopsImpl(AtChopsKeys()
      ..selfEncryptionKey =
          AESKey(atKeys.defaultSelfEncryptionKey!.toString()));
    atKeysMap[auth_constants.defaultEncryptionPublicKey] =
        (await atChops.encryptString(
                atKeys.defaultEncryptionPublicKey.toString(),
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result;

    atKeysMap[auth_constants.defaultEncryptionPrivateKey] =
        (await atChops.encryptString(
                atKeys.defaultEncryptionPrivateKey.toString(),
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result;

    atKeysMap[auth_constants.apkamPublicKey] = (await atChops.encryptString(
            atKeys.apkamPublicKey.toString(), EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
        .result;

    if (authMode == PkamAuthMode.keysFile) {
      atKeysMap[auth_constants.apkamPrivateKey] = (await atChops.encryptString(
              atKeys.apkamPrivateKey.toString(), EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
          .result;
    }

    atKeysMap[auth_constants.apkamSymmetricKey] =
        atKeys.apkamSymmetricKey.toString();
    atKeysMap[auth_constants.defaultSelfEncryptionKey] =
        atKeys.defaultSelfEncryptionKey.toString();
    atKeysMap[AtConstants.enrollmentId] = atKeys.enrollmentId;
    atKeysMap[atsign] = atKeys.defaultSelfEncryptionKey.toString();
    return jsonEncode(atKeysMap);
  }

  @Deprecated(
      'legacy helpers for serialization, if we need to retain this turn it into a static helper')
  AtKeys generateKeyPairs({
    PkamAuthMode authMode = PkamAuthMode.keysFile,
    @Deprecated(
        'ignored; kept so existing atSign: call sites compile — remove in v4')
    String? atSign,
  }) {
    var atKeysFile = AtKeys();
    // generate user encryption keypair
    _logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    //generate selfEncryptionKey
    var selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    _logger.info('Generating your encryption keys and .atKeys file\n');

    //generating pkamKeyPair only if authMode is keysFile
    String? pkamPublicKey;
    if (authMode == PkamAuthMode.keysFile) {
      _logger.info('Generating pkam keypair');
      var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
      pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
      atKeysFile.apkamPrivateKey = AtBytes.fromString(
          apkamRsaKeypair.atPrivateKey.privateKey.toString());
    }
    atKeysFile.apkamPublicKey = AtBytes.fromString(pkamPublicKey.toString());
    //Standard order of an atKeys file is ->
    // pkam keypair -> encryption keypair -> selfEncryption key -> enrollmentId --> apkam symmetric key -->
    // @sign: selfEncryptionKey[self encryption key again]
    // note: "->" stands for "followed by"
    atKeysFile.defaultEncryptionPublicKey = AtBytes.fromString(
        atEncryptionKeyPair.atPublicKey.publicKey.toString());
    atKeysFile.defaultEncryptionPrivateKey = AtBytes.fromString(
        atEncryptionKeyPair.atPrivateKey.privateKey.toString());
    atKeysFile.defaultSelfEncryptionKey =
        AtBytes.fromString(selfEncryptionKey.key);
    atKeysFile.apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key);

    return atKeysFile;
  }

  @Deprecated(
      'legacy helpers for serialization, if we need to retain this turn it into a static helper')
  Future<Map<String, dynamic>> decodeAtKeys(
      Map<String, dynamic> decodedAtKeysData,
      {String? passPhrase}) {
    return passphraseCodec.decode(decodedAtKeysData, passPhrase: passPhrase);
  }
}
