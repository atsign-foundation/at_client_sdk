import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';

class EncryptionService {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  String? currentAtSign;

  var logger = AtSignLogger('EncryptionService');

  Future<String> encrypt(String? key, String value, String sharedWith) async {
    var isSharedKeyAvailable = false;
    var currentAtSignPublicKey =
        await localSecondary!.getEncryptionPublicKey(currentAtSign!);
    var currentAtSignPrivateKey =
        await localSecondary!.getEncryptionPrivateKey();
    var sharedWithUser = sharedWith.replaceFirst('@', '');

    //1. Get/Generate AES key for sharedWith atsign
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..sharedBy = currentAtSign;
    var sharedKey;
    try {
      sharedKey = await localSecondary!.executeVerb(llookupVerbBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${llookupVerbBuilder.atKey}$currentAtSign not found in local secondary. Fetching from cloud secondary.');
    }
    // If sharedKey is not found in localSecondary, search in remote secondary.
    try {
      if (sharedKey == null || sharedKey == 'data:null') {
        sharedKey = await remoteSecondary!.executeVerb(llookupVerbBuilder);
      }
    } on AtLookUpException {
      logger.finer(
          '${llookupVerbBuilder.atKey}$currentAtSign not found in remote secondary. Generating a new shared key');
    }
    // If sharedKey is null, generate a new sharedKey,
    // Else decrypt the existing shared key.
    if (sharedKey == null || sharedKey == 'data:null') {
      logger.finer('Generated a AES Key for $sharedWithUser');
      sharedKey = EncryptionUtil.generateAESKey();
    } else {
      isSharedKeyAvailable = true;
      sharedKey = sharedKey.replaceFirst('data:', '');
      sharedKey =
          EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey!);
    }
    //2. Verify if encryptedSharedKey for sharedWith atSign is available.
    var lookupEncryptionSharedKey = LLookupVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    String? result;
    try {
      result = await localSecondary!.executeVerb(lookupEncryptionSharedKey);
    } on KeyNotFoundException {
      logger.finer('$sharedWith:$AT_ENCRYPTION_SHARED_KEY@$currentAtSign not found in local secondary. Fetching from cloud secondary');
    }

    //3. Create the encryptedSharedKey if
    // a. encryptedSharedKey not available (or)
    // b. If the sharedKey is changed.
    if (result == null || result == 'data:null' || !isSharedKeyAvailable) {
      var sharedWithPublicKey;
      try {
        sharedWithPublicKey = await _getSharedWithPublicKey(sharedWithUser);
      } on Exception {
        rethrow;
      }
      //Encrypt shared key with public key of sharedWith atsign.
      var encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
      // Store the encryptedSharedWith Key. Set ttr to enable sharedWith atsign to cache the encryptedSharedKey.
      var updateSharedKeyBuilder = UpdateVerbBuilder()
        ..sharedWith = sharedWith
        ..sharedBy = currentAtSign
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..value = encryptedSharedKey
        ..ttr = 3888000;
      await localSecondary!.executeVerb(updateSharedKeyBuilder, sync: true);
    }

    //4. Store the sharedKey for future retrival.
    if (!isSharedKeyAvailable) {
      // Encrypt the sharedKey with currentAtSign Public key and store it.
      var encryptedSharedKeyForCurrentAtSign =
          EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey!);

      var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
        ..sharedBy = currentAtSign
        ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
        ..value = encryptedSharedKeyForCurrentAtSign;
      await localSecondary!
          .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: true);
    }

    //5. Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptValue(value, sharedKey);
    return encryptedValue;
  }

  Future<String> decrypt(String encryptedValue, String sharedBy) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    sharedBy = sharedBy.replaceFirst('@', '');
    var encryptedSharedKey;
    //1. Get encrypted shared key
    encryptedSharedKey = await _getEncryptedSharedKey(sharedBy);
    if (encryptedSharedKey == 'null' || encryptedSharedKey.isEmpty) {
      throw KeyNotFoundException('encrypted Shared key not found');
    }

    //2. decrypt shared key using private key
    var currentAtSignPrivateKey =
        await (localSecondary!.getEncryptionPrivateKey());
    if (currentAtSignPrivateKey == null) {
      throw KeyNotFoundException('encryption private not found');
    }
    var sharedKey =
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);

    //3. decrypt value using shared key
    var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, sharedKey);
    return decryptedValue;
  }

  ///Returns `decrypted value` on successful decryption.
  /// Used for local lookup @bob:phone@alice
  Future<String?> decryptLocal(String? encryptedValue, String? currentAtSign,
      String sharedWithUser) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    sharedWithUser = sharedWithUser.replaceFirst('@', '');
    var currentAtSignPrivateKey =
        await localSecondary!.getEncryptionPrivateKey();
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..sharedBy = currentAtSign;
    var sharedKey = await localSecondary!.executeVerb(llookupVerbBuilder);
    if (sharedKey == null) {
      logger.severe('Decryption failed. SharedKey is null');
      throw AtClientException('AT0014', 'Decryption failed. SharedKey is null');
    }
    //trying to llookup a value without shared key. throw exception or return null}
    sharedKey = sharedKey.replaceFirst('data:', '');
    var decryptedSharedKey =
        EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey!);
    var decryptedValue =
        EncryptionUtil.decryptValue(encryptedValue, decryptedSharedKey);

    return decryptedValue;
  }

  /// returns encrypted value
  Future<String?> encryptForSelf(String? key, String value) async {
    try {
      // //1. Get AES key for current atsign
      var selfEncryptionKey = await _getSelfEncryptionKey();
      if (selfEncryptionKey == null || selfEncryptionKey == 'data:null') {
        throw Exception(
            'Self encryption key is not set for atsign $currentAtSign');
      } else {
        selfEncryptionKey = selfEncryptionKey.replaceFirst('data:', '');
      }

      // Encrypt value using sharedKey
      var encryptedValue =
          EncryptionUtil.encryptValue(value, selfEncryptionKey);
      return encryptedValue;
    } on Exception catch (e) {
      logger.severe(
          'Exception while encrypting value for key $key: ${e.toString()}');
      return null;
    }
  }

  /// returns decrypted value
  /// Used for local lookup @alice:phone@alice
  Future<String?> decryptForSelf(
      String? encryptedValue, bool isEncrypted) async {
    if (encryptedValue == null || encryptedValue == 'null') {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    if (!isEncrypted) {
      logger.info(
          'isEncrypted is set to false, Returning the original value without decrypting');
      return encryptedValue;
    }
    try {
      var selfEncryptionKey = await _getSelfEncryptionKey();
      if (selfEncryptionKey == null || selfEncryptionKey == 'data:null') {
        return encryptedValue;
      }
      selfEncryptionKey = selfEncryptionKey.toString().replaceAll('data:', '');
      // decrypt value using self encryption key
      var decryptedValue =
          EncryptionUtil.decryptValue(encryptedValue, selfEncryptionKey);
      return decryptedValue;
    } on Exception catch (e) {
      logger.severe('Exception while decrypting value: ${e.toString()}');
      return null;
    } on Error catch (e) {
      logger.severe('Exception while decrypting value: ${e.toString()}');
      return null;
    }
  }

  //TODO remove code duplication - encrypt and encryptStream
  Future<List<int>> encryptStream(List<int> value, String sharedWith) async {
    var currentAtSignPublicKey =
        await (localSecondary!.getEncryptionPublicKey(currentAtSign!));
    var currentAtSignPrivateKey =
        await localSecondary!.getEncryptionPrivateKey();
    var sharedWithUser = sharedWith.replaceFirst('@', '');
    // //1. Get/Generate AES key for sharedWith atsign
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..sharedBy = currentAtSign;
    String? sharedKey;
    try {
      sharedKey = await localSecondary!.executeVerb(llookupVerbBuilder);
    } on KeyNotFoundException {
      logger.finer('${llookupVerbBuilder.atKey} not found in local secondary');
    }
    if (sharedKey == null || sharedKey == 'data:null') {
      sharedKey = EncryptionUtil.generateAESKey();
    } else {
      sharedKey = sharedKey.replaceFirst('data:', '');
      sharedKey =
          EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey!);
    }
    //2. Lookup public key of sharedWith atsign
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = sharedWith;
    var sharedWithPublicKey =
        await remoteSecondary!.executeAndParse(plookupBuilder);
    if (sharedWithPublicKey == 'null' || sharedWithPublicKey.isEmpty) {
      throw KeyNotFoundException(
          'shared key not found. data sharing is forbidden.');
    }
    //3. Encrypt shared key with public key of sharedWith atsign and store
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);

    var updateSharedKeyBuilder = UpdateVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..value = encryptedSharedKey;
    await localSecondary!.executeVerb(updateSharedKeyBuilder, sync: true);

    //4. Store the shared key for future retrieval
    if (currentAtSignPublicKey == null) {
      throw KeyNotFoundException('encryption public key not found');
    }
    var encryptedSharedKeyForCurrentAtSign =
        EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey);

    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..sharedBy = currentAtSign
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.$sharedWithUser'
      ..value = encryptedSharedKeyForCurrentAtSign;
    await localSecondary!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: true);

    //5. Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptBytes(value, sharedKey);
    return encryptedValue;
  }

  List<int> decryptStream(List<int> encryptedValue, String sharedKey) {
    //decrypt stream using decrypted aes shared key
    var decryptedValue = EncryptionUtil.decryptBytes(encryptedValue, sharedKey);
    return decryptedValue;
  }

  Future<bool> verifyPublicDataSignature(
      String sharedBy, String dataSignature, String value) async {
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.$sharedBy'
      ..sharedBy = currentAtSign;
    String? sharedByPublicKey;
    try {
      sharedByPublicKey =
          await localSecondary!.executeVerb(cachedPublicKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${cachedPublicKeyBuilder.atKey} not found in local secondary');
    }
    if (sharedByPublicKey == null || sharedByPublicKey == 'data:null') {
      var plookupBuilder = PLookupVerbBuilder()
        ..atKey = 'publickey'
        ..sharedBy = sharedBy;
      sharedByPublicKey =
          await remoteSecondary!.executeAndParse(plookupBuilder);
      //4.b store sharedWith public key for future retrieval
      var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
        ..atKey = 'publickey.$sharedBy'
        ..sharedBy = currentAtSign
        ..value = sharedByPublicKey;
      await localSecondary!
          .executeVerb(sharedWithPublicKeyBuilder, sync: false);
    } else {
      sharedByPublicKey = sharedByPublicKey.replaceFirst('data:', '');
    }
//    if (sharedByPublicKey == null) {
//      logger.severe('unable to verify public data sharedBy: $sharedBy');
//      return false;
//    }
    var publicKey = RSAPublicKey.fromString(sharedByPublicKey);
    var isDataValid = publicKey.verifySHA256Signature(
        utf8.encode(value) as Uint8List, base64Decode(dataSignature));
    return isDataValid;
  }

  String signPublicData(String encryptionPrivateKey, dynamic value) {
    var privateKey = RSAPrivateKey.fromString(encryptionPrivateKey);
    var dataSignature =
        privateKey.createSHA256Signature(utf8.encode(value) as Uint8List);
    return base64Encode(dataSignature);
  }

  @deprecated
  Future<void> encryptUnencryptedData() async {
    var atClient = await (AtClientImpl.getClient(currentAtSign));
    if (atClient == null) {
      return;
    }
    var selfKeys = await atClient.getAtKeys(sharedBy: currentAtSign);
    selfKeys.forEach((atKey) async {
      var key = atKey.key!;
      if (!(key.startsWith(AT_PKAM_PRIVATE_KEY) ||
          key.startsWith(AT_PKAM_PUBLIC_KEY) ||
          key.startsWith(AT_ENCRYPTION_PRIVATE_KEY) ||
          key.startsWith(AT_SIGNING_PRIVATE_KEY) ||
          key.startsWith(AT_ENCRYPTION_SHARED_KEY) ||
          key.startsWith('_'))) {
        var sharedWith = atKey.sharedWith;
        var isPublic = false;
        var isCached = false;
        if (atKey.metadata != null) {
          isPublic = atKey.metadata?.isPublic ?? false;
          isCached = atKey.metadata?.isCached ?? false;
        }
        if (!isPublic && !isCached) {
          if (sharedWith == null || sharedWith == currentAtSign) {
            var atValue = await atClient.get(atKey);
            var metadata =
                (atValue.metadata != null) ? atValue.metadata! : Metadata();
            var isEncrypted =
                (metadata.isEncrypted != null) ? metadata.isEncrypted! : false;
            if (!isEncrypted) {
              var value = atValue.value;
              metadata.isEncrypted = true;
              metadata.isBinary =
                  (metadata.isBinary != null) ? metadata.isBinary : false;
              atKey.metadata = metadata;
              await atClient.put(atKey, value);
            }
          }
        }
      }
    });
    await atClient.getSyncManager()!.sync();
  }

  Future<String?> _getSelfEncryptionKey() async {
    var selfEncryptionKey = await localSecondary!.getEncryptionSelfKey();
    return selfEncryptionKey;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String?> _getSharedWithPublicKey(String sharedWithUser) async {
    //a local lookup the cached public key of sharedWith atsign.
    var sharedWithPublicKey;
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.$sharedWithUser'
      ..sharedBy = currentAtSign;
    try {
      sharedWithPublicKey =
          await localSecondary!.executeVerb(cachedPublicKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '${cachedPublicKeyBuilder.atKey}@$currentAtSign not found in local secondary. Fetching from cloud secondary');
    }
    if (sharedWithPublicKey != null && sharedWithPublicKey != 'data:null') {
      sharedWithPublicKey =
          sharedWithPublicKey.toString().replaceAll('data:', '');
      return sharedWithPublicKey;
    }

    //b Lookup public key of sharedWith atsign
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = sharedWithUser;
    sharedWithPublicKey =
        await remoteSecondary!.executeAndParse(plookupBuilder);

    // If SharedWith PublicKey is not found throw KeyNotFoundException.
    if (sharedWithPublicKey == 'null' || sharedWithPublicKey.isEmpty) {
      throw KeyNotFoundException(
          'public key not found. data sharing is forbidden.');
    }
    //Cache the sharedWithPublicKey
    var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey.$sharedWithUser'
      ..sharedBy = currentAtSign
      ..value = sharedWithPublicKey;
    await localSecondary!.executeVerb(sharedWithPublicKeyBuilder, sync: true);

    return sharedWithPublicKey;
  }

  Future<String?> _getEncryptedSharedKey(String sharedBy) async {
    var encryptedSharedKey;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..isCached = true
      ..sharedBy = sharedBy
      ..sharedWith = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    try {
      encryptedSharedKey =
          await localSecondary!.executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      logger.finer(
          '$sharedBy:${localLookupSharedKeyBuilder.atKey}@$currentAtSign not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == null || encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = sharedBy
        ..auth = true;
      encryptedSharedKey =
          await remoteSecondary!.executeAndParse(sharedKeyLookUpBuilder);
    }
    if ((encryptedSharedKey != null) && (encryptedSharedKey.isNotEmpty)) {
      encryptedSharedKey = encryptedSharedKey.replaceFirst('data:', '');
    }
    return encryptedSharedKey;
  }

  Future<String> getSharedKey(String sharedBy) async {
    sharedBy = sharedBy.replaceFirst('@', '');

    var encryptedSharedKey = await _getEncryptedSharedKey(sharedBy);
    if (encryptedSharedKey == null || encryptedSharedKey == 'null') {
      throw KeyNotFoundException('encrypted Shared key not found');
    }
    //2. decrypt shared key using private key
    var currentAtSignPrivateKey =
        await (localSecondary!.getEncryptionPrivateKey());
    if (currentAtSignPrivateKey == null) {
      throw KeyNotFoundException('private encryption key not found');
    }
    var sharedKey =
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);
    return sharedKey;
  }

  String generateFileEncryptionKey() {
    return EncryptionUtil.generateAESKey();
  }

  List<int> encryptFile(List<int> fileContent, String fileEncryptionKey) {
    return EncryptionUtil.encryptBytes(fileContent, fileEncryptionKey);
  }

  List<int> decryptFile(List<int> fileContent, String decryptionKey) {
    var encryptedValue =
        EncryptionUtil.decryptBytes(fileContent, decryptionKey);
    return encryptedValue;
  }
}
