import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/encryption_service/stream_encryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

/// Contains the common code for [SharedKeyEncryption] and [StreamEncryption]
abstract class AbstractAtKeyEncryption implements AtKeyEncryption {
  final _logger = AtSignLogger('AbstractAtKeyEncryption');
  late String _sharedKey;

  String get sharedKey => _sharedKey;

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    // Get AES Key from the local storage
    _sharedKey = await _getSharedKey(atKey);

    // If sharedKey is empty, then -
    // Generate a new sharedKey
    // Encrypt the sharedKey with sharedWith public key
    // Notify the encryptedSharedKey with sharedWith user
    // Store the sharedKey for future use.
    if (_sharedKey.isEmpty) {
      // Generate sharedKey
      _sharedKey = EncryptionUtil.generateAESKey();
      // Get SharedWith encryption public key
      var sharedWithPublicKey = await _getSharedWithPublicKey(atKey);
      //Encrypt shared key with public key of sharedWith atSign.
      var encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
      // Store the encryptedSharedWith Key. Set ttr to enable sharedWith atSign
      // to cache the encryptedSharedKey.
      await _notifyEncryptedSharedKey(atKey, encryptedSharedKey);
      // Store the sharedKey for future retrieval.
      _storeSharedKey(atKey, sharedKey);
    }
  }

  /// Fetches the shared key in the local secondary
  /// If not found, fetches in the remote secondary
  /// If found, returns the decrypted sharedKey.
  Future<String> _getSharedKey(AtKey atKey) async {
    String? key = '';
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;
    try {
      key = await _getCachedSharedKey(llookupVerbBuilder);
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.key}${atKey.sharedBy} not found in local secondary. Fetching from cloud secondary.');
    }
    // If sharedKey is not found in localSecondary, fetch from remote secondary.
    try {
      if (key == null || key.isEmpty || key == 'data:null') {
        key = await _getSharedKeyFromRemote(llookupVerbBuilder);
      }
    } on AtLookUpException {
      _logger.finer(
          '${llookupVerbBuilder.atKey}${atKey.sharedBy} not found in remote secondary. Generating a new shared key');
    }
    // If sharedKey is found, decrypt the shared key and return.
    if (key != null && key.isNotEmpty && key != 'data:null') {
      key = DefaultResponseParser().parse(key).response;
      var encryptionPrivateKey = await AtClientManager.getInstance()
          .atClient
          .getLocalSecondary()!
          .getEncryptionPrivateKey();
      return EncryptionUtil.decryptKey(key, encryptionPrivateKey!);
    }
    return key!;
  }

  ///Get cached shared key from local storage
  Future<String?> _getCachedSharedKey(
      LLookupVerbBuilder llookupVerbBuilder) async {
    return await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(llookupVerbBuilder);
  }

  /// Get shared key from cloud secondary
  Future<String> _getSharedKeyFromRemote(
      LLookupVerbBuilder llookupVerbBuilder) async {
    return await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()!
        .executeVerb(llookupVerbBuilder);
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

    sharedWithPublicKey = await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()!
        .executeAndParse(plookupBuilder);

    // If SharedWith PublicKey is not found throw KeyNotFoundException.
    if (sharedWithPublicKey.isEmpty || sharedWithPublicKey == 'data:null') {
      throw KeyNotFoundException(
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

  /// Stores the sharedKey for future use.
  void _storeSharedKey(AtKey atKey, String sharedKey) async {
    // Encrypt the sharedKey with currentAtSign Public key and store it.
    var encryptedSharedKeyForCurrentAtSign = EncryptionUtil.encryptKey(
        sharedKey,
        (await AtClientManager.getInstance()
            .atClient
            .getLocalSecondary()!
            .getEncryptionPublicKey(atKey.sharedBy!))!);

    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy
      ..value = encryptedSharedKeyForCurrentAtSign;
    await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: true);
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
