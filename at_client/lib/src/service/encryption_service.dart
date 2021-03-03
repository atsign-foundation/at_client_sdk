import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';

class EncryptionService {
  RemoteSecondary remoteSecondary;

  LocalSecondary localSecondary;

  String currentAtSign;

  var logger = AtSignLogger('EncryptionService');

  Future<String> encrypt(String key, String value, String sharedWith) async {
    var isSharedKeyAvailable = false;
    var currentAtSignPublicKey =
        await localSecondary.getEncryptionPublicKey(currentAtSign);
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var sharedWithUser = sharedWith.replaceFirst('@', '');

    //1. Get/Generate AES key for sharedWith atsign
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
      ..sharedBy = currentAtSign;
    var sharedKey = await localSecondary.executeVerb(llookupVerbBuilder);
    if (sharedKey == null || sharedKey == 'data:null') {
      sharedKey = EncryptionUtil.generateAESKey();
    } else {
      isSharedKeyAvailable = true;
      sharedKey = sharedKey.replaceFirst('data:', '');
      sharedKey = EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey);
    }

    //2. Verify if encryptedSharedKey for sharedWith atSign is available.
    var lookupEncryptionSharedKey = LLookupVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    var result = await localSecondary.executeVerb(lookupEncryptionSharedKey);

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
      await localSecondary.executeVerb(updateSharedKeyBuilder, sync: true);
    }

    //4. Store the sharedKey for future retrival.
    if (!isSharedKeyAvailable) {
      // Encrypt the sharedKey with currentAtSign Public key and store it.
      var encryptedSharedKeyForCurrentAtSign =
          EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey);

      var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
        ..sharedBy = currentAtSign
        ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
        ..value = encryptedSharedKeyForCurrentAtSign;
      await localSecondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder,
          sync: true);
    }

    //5. Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptValue(value, sharedKey);
    return encryptedValue;
  }

  Future<String> decrypt(String encryptedValue, String sharedBy) async {
    sharedBy = sharedBy.replaceFirst('@', '');

    //1.local lookup the cached-shared key, if null lookup shared key
    var encryptedSharedKey;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..isCached = true
      ..sharedBy = sharedBy
      ..sharedWith = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    encryptedSharedKey =
        await localSecondary.executeVerb(localLookupSharedKeyBuilder);
    if (encryptedSharedKey == null || encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = sharedBy
        ..auth = true;
      encryptedSharedKey =
          await remoteSecondary.executeAndParse(sharedKeyLookUpBuilder);
    }
    if (encryptedSharedKey == 'null' || encryptedSharedKey.isEmpty) {
      throw KeyNotFoundException('encrypted Shared key not found');
    }
    encryptedSharedKey = encryptedSharedKey.toString().replaceAll('data:', '');
    //2. decrypt shared key using private key
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var sharedKey =
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);

    //3. decrypt value using shared key

    //@bob 5. decrypt phone using decrypted aes shared key
    var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, sharedKey);
    return decryptedValue;
  }

  ///Returns `decrypted value` on successful decryption.
  /// Used for local lookup @bob:phone@alice
  Future<String> decryptLocal(String encryptedValue, String currentAtSign,
      String sharedWithUser) async {
    sharedWithUser = sharedWithUser.replaceFirst('@', '');
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
      ..sharedBy = currentAtSign;
    var sharedKey = await localSecondary.executeVerb(llookupVerbBuilder);
    if (sharedKey == null) {
      return null;
    }
    //trying to llookup a value without shared key. throw exception or return null}
    sharedKey = sharedKey.replaceFirst('data:', '');
    var decryptedSharedKey =
        EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey);
    var decryptedValue =
        EncryptionUtil.decryptValue(encryptedValue, decryptedSharedKey);

    return decryptedValue;
  }

  /// returns encrypted value
  Future<String> encryptForSelf(String key, String value) async {
    try {
      // //1. Get AES key for current atsign
      var selfEncryptionKey = await _getSelfEncryptionKey();
      if (selfEncryptionKey == null || selfEncryptionKey == 'data:null') {
        throw Exception(
            'Self encryption key is not set for atsign ${currentAtSign}');
      } else {
        selfEncryptionKey = selfEncryptionKey.replaceFirst('data:', '');
      }

      // Encrypt value using sharedKey
      var encryptedValue =
          EncryptionUtil.encryptValue(value, selfEncryptionKey);
      return encryptedValue;
    } on Exception catch (e) {
      print('Exception while encrypting value for key ${key}: ${e.toString()}');
      return null;
    }
  }

  /// returns decrypted value
  /// Used for local lookup @alice:phone@alice
  Future<String> decryptForSelf(String encryptedValue, bool isEncrypted) async {
    if (!isEncrypted || encryptedValue == null || encryptedValue == 'null') {
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
    } on Error catch(e) {
      logger.severe('Exception while decrypting value: ${e.toString()}');
      return null;
    }
  }

  Future<bool> verifyPublicDataSignature(
      String sharedBy, String dataSignature, String value) async {
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.${sharedBy}'
      ..sharedBy = currentAtSign;
    var sharedByPublicKey =
        await localSecondary.executeVerb(cachedPublicKeyBuilder);
    if (sharedByPublicKey == null || sharedByPublicKey == 'data:null') {
      var plookupBuilder = PLookupVerbBuilder()
        ..atKey = 'publickey'
        ..sharedBy = sharedBy;
      sharedByPublicKey = await remoteSecondary.executeAndParse(plookupBuilder);
      //4.b store sharedWith public key for future retrieval
      var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
        ..atKey = 'publickey.${sharedBy}'
        ..sharedBy = currentAtSign
        ..value = sharedByPublicKey;
      await localSecondary.executeVerb(sharedWithPublicKeyBuilder, sync: false);
    } else {
      sharedByPublicKey = sharedByPublicKey.replaceFirst('data:', '');
    }
    if (sharedByPublicKey == null) {
      logger.severe('unable to verify public data sharedBy: ${sharedBy}');
      return false;
    }
    var publicKey = RSAPublicKey.fromString(sharedByPublicKey);
    var isDataValid = publicKey.verifySHA256Signature(
        utf8.encode(value), base64Decode(dataSignature));
    return isDataValid;
  }

  void signOldPublicData() async {
    var atClient = await AtClientImpl.getClient(currentAtSign);
    var selfKeys = await atClient.getAtKeys(regex: '^public:');
    await Future.forEach(
        selfKeys, (atKey) => _updateSignature(atClient, atKey));
  }

  void _updateSignature(atClient, atKey) async {
    if (atKey.metadata != null) {
      if (atKey.metadata.isPublic != null && atKey.metadata.isPublic) {
        var atValue = await atClient.get(atKey);
        if (atValue.metadata?.dataSignature == null) {
          var value = atValue.value;
          var encryptionPrivateKey =
              await localSecondary.getEncryptionPrivateKey();
          var dataSignature = signPublicData(encryptionPrivateKey, value);
          atKey.metadata.dataSignature = dataSignature;
          await atClient.put(atKey, value);
          logger.finer('update data signature for key: ${atKey.key}');
        }
      }
    }
  }

  String signPublicData(String encryptionPrivateKey, dynamic value) {
    var privateKey = RSAPrivateKey.fromString(encryptionPrivateKey);
    var dataSignature = privateKey.createSHA256Signature(utf8.encode(value));
    return base64Encode(dataSignature);
  }

  Future<void> encryptUnencryptedData() async {
    var atClient = await AtClientImpl.getClient(currentAtSign);
    var selfKeys = await atClient.getAtKeys(sharedBy: currentAtSign);
    selfKeys.forEach((atKey) async {
      var key = atKey.key;
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
          isPublic =
              atKey.metadata.isPublic != null ? atKey.metadata.isPublic : false;
          isCached =
              atKey.metadata.isCached != null ? atKey.metadata.isCached : false;
        }
        if (!isPublic && !isCached) {
          if (sharedWith == null || sharedWith == currentAtSign) {
            var atValue = await atClient.get(atKey);
            var metadata =
                (atValue.metadata != null) ? atValue.metadata : Metadata();
            var isEncrypted =
                (metadata.isEncrypted != null) ? metadata.isEncrypted : false;
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
    await atClient.getSyncManager().sync();
  }

  Future<String> _getSelfEncryptionKey() async {
    var selfEncryptionKey = await localSecondary.getEncryptionSelfKey();
    //#TODO remove before pushing to prod
    logger.finer('self encryption key: ${selfEncryptionKey}');
    return selfEncryptionKey;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String> _getSharedWithPublicKey(String sharedWithUser) async {
    //a local lookup the cached public key of sharedWith atsign.
    var sharedWithPublicKey;
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.${sharedWithUser}'
      ..sharedBy = currentAtSign;
    sharedWithPublicKey =
        await localSecondary.executeVerb(cachedPublicKeyBuilder);
    if (sharedWithPublicKey != null && sharedWithPublicKey != 'data:null') {
      sharedWithPublicKey =
          sharedWithPublicKey.toString().replaceAll('data:', '');
      return sharedWithPublicKey;
    }

    //b Lookup public key of sharedWith atsign
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = sharedWithUser;
    sharedWithPublicKey = await remoteSecondary.executeAndParse(plookupBuilder);

    // If SharedWith PublicKey is not found throw KeyNotFoundException.
    if (sharedWithPublicKey == 'null' || sharedWithPublicKey.isEmpty) {
      throw KeyNotFoundException(
          'public key not found. data sharing is forbidden.');
    }
    //Cache the sharedWithPublicKey
    var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey.${sharedWithUser}'
      ..sharedBy = currentAtSign
      ..value = sharedWithPublicKey;
    await localSecondary.executeVerb(sharedWithPublicKeyBuilder, sync: true);

    return sharedWithPublicKey;
  }
}
