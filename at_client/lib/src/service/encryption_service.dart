import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

class EncryptionService {
  RemoteSecondary remoteSecondary;

  LocalSecondary localSecondary;

  String currentAtSign;

  Future<String> encrypt(String key, String value, String sharedWith) async {
    var isSharedKeyAvailable = false;
    var isSharedWithPublicKeyAvailable = true;

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
    print('shared key:${sharedKey}');

    //2.a local lookup the cached public key of sharedWith atsign.
    var sharedWithPublicKey;
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.${sharedWithUser}'
      ..sharedBy = currentAtSign;
    sharedWithPublicKey =
        await localSecondary.executeVerb(cachedPublicKeyBuilder);
    //2.b If null, Lookup public key of sharedWith atsign
    if (sharedWithPublicKey == null || sharedWithPublicKey == 'data:null') {
      isSharedWithPublicKeyAvailable = false;
      var plookupBuilder = PLookupVerbBuilder()
        ..atKey = 'publickey'
        ..sharedBy = sharedWith;
      sharedWithPublicKey =
          await remoteSecondary.executeAndParse(plookupBuilder);
    }
    if (sharedWithPublicKey == 'null' || sharedWithPublicKey.isEmpty) {
      throw KeyNotFoundException(
          'public key not found. data sharing is forbidden.');
    }
    sharedWithPublicKey =
        sharedWithPublicKey.toString().replaceAll('data:', '');

    //3. Encrypt shared key with public key of sharedWith atsign and store
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
    var lookupEncryptionSharedKey = LLookupVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    var result = await localSecondary.executeVerb(lookupEncryptionSharedKey);
    if (result == null || result == 'data:null') {
      var updateSharedKeyBuilder = UpdateVerbBuilder()
        ..sharedWith = sharedWith
        ..sharedBy = currentAtSign
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..value = encryptedSharedKey
        ..ttr = 3888000;
      await localSecondary.executeVerb(updateSharedKeyBuilder, sync: true);
    }

    //4.a Store the shared key for future retrieval
    if (!isSharedKeyAvailable) {
      var encryptedSharedKeyForCurrentAtSign =
          EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey);
      var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
        ..sharedBy = currentAtSign
        ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
        ..value = encryptedSharedKeyForCurrentAtSign;
      await localSecondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder,
          sync: true);
    }
    if (!isSharedWithPublicKeyAvailable) {
      //4.b store sharedWith public key for future retrieval
      var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
        ..atKey = 'publickey.${sharedWithUser}'
        ..sharedBy = currentAtSign
        ..value = sharedWithPublicKey;
      await localSecondary.executeVerb(sharedWithPublicKeyBuilder, sync: true);
    }
    //4.b store sharedWith public key for future retrieval
    var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey.${sharedWithUser}'
      ..sharedBy = currentAtSign
      ..value = sharedWithPublicKey;
    await localSecondary.executeVerb(sharedWithPublicKeyBuilder, sync: true);

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
        ..sharedBy = sharedBy;
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
    print('sharedKey:${sharedKey}');

    //3. decrypt value using shared key

    //@bob 5. decrypt phone using decrypted aes shared key
    var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, sharedKey);
    print('decrypted value: ${decryptedValue}');
    return decryptedValue;
  }

  ///Returns `decrypted value` on successful decryption.
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
    var sharedWith = currentAtSign;
    var currentAtSignPublicKey =
        await localSecondary.getEncryptionPublicKey(currentAtSign);
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var sharedWithUser = currentAtSign.replaceFirst('@', '');
    // //1. Get/Generate AES key for sharedWith atsign
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AT_ENCRYPTION_SHARED_KEY}'
      ..sharedWith = currentAtSign
      ..sharedBy = currentAtSign;
    var sharedKey = await localSecondary.executeVerb(llookupVerbBuilder);
    if (sharedKey == null || sharedKey == 'data:null') {
      sharedKey = EncryptionUtil.generateAESKey();
      // Encrypt shared key with public key of sharedWith atsign and store
      var encryptedAESKey =
          EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey);

      var updateAESKeyBuilder = UpdateVerbBuilder()
        ..sharedBy = currentAtSign
        ..sharedWith = currentAtSign
        ..atKey = '${AT_ENCRYPTION_SHARED_KEY}'
        ..value = encryptedAESKey;
      await localSecondary.executeVerb(updateAESKeyBuilder, sync: true);
    } else {
      sharedKey = sharedKey.replaceFirst('data:', '');
      sharedKey = EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey);
    }
    print('shared key:${sharedKey}');

    // Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptValue(value, sharedKey);
    return encryptedValue;
  }

  /// returns decrypted value
  Future<String> decryptForSelf(String encryptedValue, bool isEncrypted) async {
    if (!isEncrypted) {
      return encryptedValue;
    }
    // local lookup the cached-shared key, if null lookup shared key
    var encryptedAESKey;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..sharedBy = currentAtSign
      ..sharedWith = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    encryptedAESKey =
        await localSecondary.executeVerb(localLookupSharedKeyBuilder);
    encryptedAESKey = encryptedAESKey.toString().replaceAll('data:', '');
    // decrypt shared key using private key
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var sharedKey =
        EncryptionUtil.decryptKey(encryptedAESKey, currentAtSignPrivateKey);
    print('sharedKey:${sharedKey}');

    // decrypt value using shared key
    var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, sharedKey);
    print('decrypted value: ${decryptedValue}');
    return decryptedValue;
  }
}
