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
    var currentAtSignPublicKey =
        await localSecondary.getEncryptionPublicKey(currentAtSign);
    var currentAtSignPrivateKey =
        await localSecondary.getEncryptionPrivateKey();
    var sharedWithUser = sharedWith.replaceFirst('@', '');
    // //1. Get/Generate AES key for sharedWith atsign
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
      ..sharedBy = currentAtSign;
    var sharedKey = await localSecondary.executeVerb(llookupVerbBuilder);
    if (sharedKey == null || sharedKey == 'data:null') {
      sharedKey = EncryptionUtil.generateAESKey();
    } else {
      sharedKey = sharedKey.replaceFirst('data:', '');
      sharedKey = EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey);
    }
    print('shared key:${sharedKey}');
    //2. Lookup public key of sharedWith atsign
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = sharedWith;
    var sharedWithPublicKey =
        await remoteSecondary.executeAndParse(plookupBuilder);
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
    await localSecondary.executeVerb(updateSharedKeyBuilder, sync: true);

    //4. Store the shared key for future retrieval
    var encryptedSharedKeyForCurrentAtSign =
        EncryptionUtil.encryptKey(sharedKey, currentAtSignPublicKey);

    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..sharedBy = currentAtSign
      ..atKey = '${AT_ENCRYPTION_SHARED_KEY}.${sharedWithUser}'
      ..value = encryptedSharedKeyForCurrentAtSign;
    await localSecondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder,
        sync: true);

    //5. Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptValue(value, sharedKey);
    return encryptedValue;
  }

  Future<String> decrypt(String encryptedValue, String sharedBy) async {
    sharedBy = sharedBy.replaceFirst('@', '');

    //1.lookup shared key
    var sharedKeyLookUpBuilder = LookupVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedBy = sharedBy;
    var encryptedSharedKey =
        await remoteSecondary.executeAndParse(sharedKeyLookUpBuilder);
    if (encryptedSharedKey == 'null' || encryptedSharedKey.isEmpty) {
      throw KeyNotFoundException('encrypted Shared key not found');
    }
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
}
