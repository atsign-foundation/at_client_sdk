import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/encryption_service/stream_encryption.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_chops/at_chops.dart';

/// Contains the common code for [SharedKeyEncryption] and [StreamEncryption]
abstract class AbstractAtKeyEncryption implements AtKeyEncryption {
  final _logger = AtSignLogger('AbstractAtKeyEncryption');
  late String _sharedKey;

  String get sharedKey => _sharedKey;

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    // Get AES Key from the local storage
    _sharedKey = await getSharedKey(atKey);
    late String encryptedSharedKey;
    // Get SharedWith encryption public key
    String sharedWithPublicKey = '';
    try {
      sharedWithPublicKey = await _getSharedWithPublicKey(atKey);
    } on AtPublicKeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.shareData, ExceptionScenario.encryptionFailed, e.message));
      rethrow;
    }
    // If sharedKey is empty, then -
    // Generate a new sharedKey
    // Encrypt the sharedKey with sharedWith public key
    // Notify the encryptedSharedKey with sharedWith user
    // Store the sharedKey for future use.
    if (_sharedKey.isEmpty) {
      // Generate sharedKey
      _sharedKey = EncryptionUtil.generateAESKey();
      //Encrypt shared key with public key of sharedWith atSign.
      encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
      // Store the encryptedSharedWith Key. Set ttr to enable sharedWith atSign
      // to cache the encryptedSharedKey.
      await _notifyEncryptedSharedKey(atKey, encryptedSharedKey);
      // Store the sharedKey for future retrieval.
      // Encrypt the sharedKey with currentAtSignPublicKey and store it for future use.
      String? currentAtSignEncryptionPublicKey;
      try {
        currentAtSignEncryptionPublicKey = await AtClientManager.getInstance()
            .atClient
            .getLocalSecondary()!
            .getEncryptionPublicKey(atKey.sharedBy!);
      } on KeyNotFoundException catch (e) {
        e.stack(AtChainedException(
            Intent.fetchEncryptionPublicKey,
            ExceptionScenario.fetchEncryptionKeys,
            'Failed to encrypt and store the sharedKey'));
        rethrow;
      }
      var encryptedSharedKeyForCurrentAtSign = EncryptionUtil.encryptKey(
          sharedKey, currentAtSignEncryptionPublicKey!);
      _storeSharedKey(atKey, encryptedSharedKeyForCurrentAtSign);
    } else {
      encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
    }
    atKey.metadata!.sharedKeyEnc = encryptedSharedKey;
    atKey.metadata!.pubKeyCS = EncryptionUtil.md5CheckSum(sharedWithPublicKey);
  }

  /// Fetches the shared key in the local secondary
  /// If not found, fetches in the remote secondary
  /// If found, returns the decrypted sharedKey.
  static Future<String> getSharedKey(AtKey atKey) async {
    String? key = '';
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;
    try {
      key = await _getCachedSharedKey(llookupVerbBuilder);
    } on KeyNotFoundException {
      AtSignLogger('AbstractAtKeyEncryption').finer(
          '${atKey.key}${atKey.sharedBy} not found in local secondary. Fetching from cloud secondary.');
    }
    // If sharedKey is not found in localSecondary, fetch from remote secondary.
    try {
      if (key == null || key.isEmpty || key == 'data:null') {
        key = await _getSharedKeyFromRemote(atKey);
      }
    } on KeyNotFoundException {
      AtSignLogger('AbstractAtKeyEncryption').finer(
          '${llookupVerbBuilder.atKey}${atKey.sharedBy} not found in remote secondary. Generating a new shared key');
    }
    // If sharedKey is found, decrypt the shared key and return.
    if (key != null && key.isNotEmpty && key != 'data:null') {
      key = DefaultResponseParser().parse(key).response;
      //# TODO remove else once atChops once testing is good
      if (AtClientManager.getInstance().atClient.getPreferences()!.useAtChops) {
        final decryptionResult = AtClientManager.getInstance()
            .atClient
            .getAtChops()!
            .decryptString(key, EncryptionKeyType.rsa2048);
        return decryptionResult.result;
      } else {
        try {
          var encryptionPrivateKey = await AtClientManager.getInstance()
              .atClient
              .getLocalSecondary()!
              .getEncryptionPrivateKey();
          return EncryptionUtil.decryptKey(key, encryptionPrivateKey!);
        } on KeyNotFoundException catch (e) {
          e.stack(AtChainedException(
              Intent.fetchEncryptionPrivateKey,
              ExceptionScenario.encryptionFailed,
              'Failed to decrypt the encrypted shared key'));
          rethrow;
        }
      }
    }
    return key!;
  }

  ///Get cached shared key from local storage
  static Future<String?> _getCachedSharedKey(
      LLookupVerbBuilder llookupVerbBuilder) async {
    return await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(llookupVerbBuilder);
  }

  /// Get shared key from cloud secondary and caches it local secondary for
  /// further use.
  static Future<String> _getSharedKeyFromRemote(AtKey atKey) async {
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;

    var encryptedSharedKey = await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()!
        .executeVerb(llookupVerbBuilder);
    if (encryptedSharedKey.isNotEmpty && encryptedSharedKey != 'data:null') {
      // Cached the encryptedSharedKey in local secondary for further use.
      // Setting shouldSync to false because the key is retrieved from cloud secondary
      // and need to sync back again.
      encryptedSharedKey = encryptedSharedKey.replaceAll('data:', '');
      _storeSharedKey(atKey, encryptedSharedKey, shouldSync: false);
    }
    return encryptedSharedKey;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String> _getSharedWithPublicKey(AtKey atKey) async {
    //local lookup the cached public key of sharedWith atsign.
    String sharedWithPublicKey = '';
    var cachedPublicKeyBuilder = LLookupVerbBuilder()
      ..atKey = 'publickey.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;
    try {
      sharedWithPublicKey = (await AtClientManager.getInstance()
          .atClient
          .getLocalSecondary()!
          .executeVerb(cachedPublicKeyBuilder))!;
    } on KeyNotFoundException {
      _logger.finer(
          '${cachedPublicKeyBuilder.atKey}@${atKey.sharedBy} not found in local secondary. Fetching from cloud secondary');
    }
    if (sharedWithPublicKey.isNotEmpty && sharedWithPublicKey != 'data:null') {
      return sharedWithPublicKey.replaceAll('data:', '');
    }

    // Lookup public key of sharedWith atSign in cloud secondary
    var plookupBuilder = PLookupVerbBuilder()
      ..atKey = 'publickey'
      ..sharedBy = atKey.sharedWith?.replaceAll('@', '');

    try {
      sharedWithPublicKey = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()!
          .executeVerb(plookupBuilder);
    } on AtException catch (e) {
      throw AtPublicKeyNotFoundException(
          'Failed to fetch public key of ${atKey.sharedWith}')
        ..fromException(e)
        ..stack(AtChainedException(
            Intent.shareData, ExceptionScenario.keyNotFound, e.message));
    }
    sharedWithPublicKey =
        DefaultResponseParser().parse(sharedWithPublicKey).response;

    // If SharedWith PublicKey is not found throw KeyNotFoundException.
    if (sharedWithPublicKey.isEmpty || sharedWithPublicKey == 'data:null') {
      throw AtPublicKeyNotFoundException(
          'public key not found. data sharing is forbidden.');
    }
    //Cache the sharedWithPublicKey and return public key of sharedWith atSign
    var sharedWithPublicKeyBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy
      ..value = sharedWithPublicKey;
    await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(sharedWithPublicKeyBuilder, sync: true);
    return sharedWithPublicKey;
  }

  /// Stores the encryptedSharedKey for future use.
  /// Optionally set shouldSync parameter to false to avoid the key to sync to cloud secondary
  /// Defaulted to sync the key to cloud secondary.
  static void _storeSharedKey(AtKey atKey, String encryptedSharedKey,
      {bool shouldSync = true}) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy
      ..value = encryptedSharedKey;
    await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: shouldSync);
  }

  /// Stores the encryptedSharedKey in local secondary
  /// and cache's in the [atKey.sharedWith] atSign.
  Future<void> _notifyEncryptedSharedKey(
      AtKey atKey, String encryptedSharedKey) async {
    var updateSharedKeyBuilder = UpdateVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedWith = atKey.sharedWith
      ..sharedBy = atKey.sharedBy
      ..ttr = 3888000
      ..value = encryptedSharedKey;
    await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(updateSharedKeyBuilder, sync: true);
  }
}
