import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/encryption_service/stream_encryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';
import 'package:at_chops/at_chops.dart';

/// Contains the common code for [SharedKeyEncryption] and [StreamEncryption]
abstract class AbstractAtKeyEncryption implements AtKeyEncryption {
  late final AtSignLogger _logger;
  late String _sharedKey;
  final AtClient _atClient;
  AtCommitLog? atCommitLog;

  DefaultResponseParser defaultResponseParser = DefaultResponseParser();

  String get sharedKey => _sharedKey;

  AbstractAtKeyEncryption(this._atClient) {
    _logger = AtSignLogger(
        'AbstractAtKeyEncryption (${_atClient.getCurrentAtSign()})');
  }

  SyncUtil syncUtil = SyncUtil();

  /// - Fetches the appropriate shared symmetric key by calling
  /// [getMyCopyOfSharedSymmetricKey]
  /// - Calls [createMyCopyOfSharedSymmetricKey] if
  ///   [getMyCopyOfSharedSymmetricKey] returns the empty string
  /// - Calls [verifyTheirCopyOfSharedSymmetricKey]
  /// - Doesn't actually encrypt the value, leaves that to the relevant
  ///   subclass.
  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true}) async {
    _sharedKey = await getMyCopyOfSharedSymmetricKey(atKey);

    if (_sharedKey.isEmpty) {
      _sharedKey = await createMyCopyOfSharedSymmetricKey(atKey);
    }

    var theirEncryptedSymmetricKeyCopy =
        await verifyTheirCopyOfSharedSymmetricKey(atKey, _sharedKey);

    if (storeSharedKeyEncryptedWithData) {
      atKey.metadata!.sharedKeyEnc = theirEncryptedSymmetricKeyCopy;
      atKey.metadata!.pubKeyCS =
          EncryptionUtil.md5CheckSum(await _getSharedWithPublicKey(atKey));
    }
  }

  /// Fetches existing shared symmetric key
  /// - Look first in local storage.
  /// - If not found in local storage, tries atServer
  /// - If not found in atServer, return empty string
  /// - If found on atServer, save to local
  /// - If found existing in either local or atServer, decrypt it and return
  /// Throws [KeyNotFoundException] if the encryptionPrivateKey is not found.
  ///
  Future<String> getMyCopyOfSharedSymmetricKey(AtKey atKey) async {
    String? encryptedSharedKey;
    try {
      /// Look first in local storage
      encryptedSharedKey = await _getMyEncryptedCopyOfSharedSymmetricKey(
          _atClient.getLocalSecondary()!, atKey);
    } on KeyNotFoundException {
      encryptedSharedKey = null;
    }
    try {
      /// If not found in local storage, look in atServer
      if (encryptedSharedKey.isNull || encryptedSharedKey == 'data:null') {
        _logger.info(
            'Encrypted shared key for ${atKey.sharedBy} not found in local storage. Fetching from atServer');
        encryptedSharedKey = await _getMyEncryptedCopyOfSharedSymmetricKey(
            _atClient.getRemoteSecondary()!, atKey);
        if (encryptedSharedKey != null && encryptedSharedKey != 'data:null') {
          // If found on atServer, save to local
          _logger.info(
              'Retrieved my encrypted copy of shared symmetric key for ${atKey.sharedWith} from atServer - saving to local storage');
          await _storeMyEncryptedCopyOfSharedSymmetricKey(
              atKey, encryptedSharedKey, _atClient.getLocalSecondary()!);
        }
      }
    } on KeyNotFoundException {
      _logger.info(
          'Encrypted copy of shared symmetric key for ${atKey.sharedWith} not found in local storage or atServer. Need to generate one.');
    }

    /// If not found local or remote, return empty string
    if (encryptedSharedKey.isNull || encryptedSharedKey == 'data:null') {
      return '';
    }

    /// - If found existing in either local or atServer, decrypt it and return
    encryptedSharedKey =
        defaultResponseParser.parse(encryptedSharedKey!).response;
    if (_atClient.getPreferences()!.useAtChops) {
      final decryptionResult = _atClient.atChops!
          .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
      return decryptionResult.result;
    } else {
      String? encryptionPrivateKey;
      try {
        encryptionPrivateKey =
            await _atClient.getLocalSecondary()!.getEncryptionPrivateKey();
      } on KeyNotFoundException catch (e) {
        e.stack(AtChainedException(
            Intent.fetchEncryptionPrivateKey,
            ExceptionScenario.encryptionFailed,
            'Failed to decrypt the encrypted shared key'));
        rethrow;
      }
      try {
        _logger.finer(
            "Decrypting encryptedSharedKey $encryptedSharedKey using EncryptionUtil");
        // ignore: deprecated_member_use_from_same_package
        return EncryptionUtil.decryptKey(
            encryptedSharedKey, encryptionPrivateKey!);
      } on KeyNotFoundException catch (e) {
        _logger.severe(
            "Failed to decrypt my copy of shared symmetric key for ${atKey.sharedWith}");
        e.stack(AtChainedException(
            Intent.fetchEncryptionPrivateKey,
            ExceptionScenario.encryptionFailed,
            'Failed to decrypt the encrypted shared key'));
        rethrow;
      }
    }
  }

  /// Create a new symmetric shared key and share it.
  /// - cut key, encrypt copy for self, and save to remote atServer, then to
  ///   local storage, return the unencrypted symmetric key
  /// - If atServer save rejects it because it already exists, then call
  ///   [getMyCopyOfSharedSymmetricKey] again and return that value
  @visibleForTesting
  Future<String> createMyCopyOfSharedSymmetricKey(AtKey atKey) async {
    _logger.info(
        "Creating new shared symmetric key as ${atKey.sharedBy} for ${atKey.sharedWith}");
    // Fetch our encryption public key
    String? currentAtSignEncryptionPublicKey;
    try {
      currentAtSignEncryptionPublicKey = await _atClient
          .getLocalSecondary()!
          .getEncryptionPublicKey(atKey.sharedBy!);
    } on KeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.fetchEncryptionPublicKey,
          ExceptionScenario.fetchEncryptionKeys,
          'Failed to fetch encryption public key of current atSign'));
      rethrow;
    }
    // Generate new symmetric key
    var newSymmetricKeyBase64 = EncryptionUtil.generateAESKey();

    // Encrypt the new symmetric key with our public key
    var encryptedSharedKeyMyCopy = EncryptionUtil.encryptKey(
        newSymmetricKeyBase64, currentAtSignEncryptionPublicKey!);

    // Store my copy for future use
    // First, store to atServer
    // try {
    _logger.info("Storing new shared symmetric key to atServer");
    await _storeMyEncryptedCopyOfSharedSymmetricKey(
        atKey, encryptedSharedKeyMyCopy, _atClient.getRemoteSecondary()!);
    // // TODO
    // } on KeyAlreadyExistsException catch (e) {
    //  return await getMyCopyOfSharedSymmetricKey(atKey);
    // }

    // Now store to local
    _logger.info("Storing new shared symmetric key to local storage");
    await _storeMyEncryptedCopyOfSharedSymmetricKey(
        atKey, encryptedSharedKeyMyCopy, _atClient.getLocalSecondary()!);

    // Return the unencrypted symmetric key
    return newSymmetricKeyBase64;
  }

  /// - Verifies that 'their' copy is where it should be
  /// - Check if encrypted copy exists in local storage
  /// - If not in local storage, check atServer
  /// - If in atServer, save to local storage
  /// - If not in atServer
  ///   - (a) encrypt the unencrypted copy with their public key
  ///   - (b) save encrypted copy to atServer
  ///   - (c) save encrypted copy to local storage, and return
  Future<String> verifyTheirCopyOfSharedSymmetricKey(
      AtKey atKey, String symmetricKeyBase64) async {
    /// - Check if encrypted copy exists in local storage
    String? theirEncryptedCopy =
        await _getTheirEncryptedCopyOfSharedSymmetricKey(
            _atClient.getLocalSecondary()!, atKey);
    // Found it in local storage. Return it.
    if (theirEncryptedCopy != null) {
      return theirEncryptedCopy;
    }

    /// - If not in local storage, check atServer
    _logger.info("'Their' copy of shared symmetric key for ${atKey.sharedWith}"
        " not found in local storage - will check atServer");
    theirEncryptedCopy = await _getTheirEncryptedCopyOfSharedSymmetricKey(
        _atClient.getRemoteSecondary()!, atKey);

    /// - If in atServer, save to local storage and return
    if (theirEncryptedCopy != null) {
      _logger.info(
          "Found 'their' copy of shared symmetric key for ${atKey.sharedWith}"
          " in atServer - saving to local storage");
      await storeTheirCopyOfEncryptedSharedKeyToSecondary(
          atKey, theirEncryptedCopy,
          secondary: _atClient.getLocalSecondary()!);

      return theirEncryptedCopy;
    }

    /// - If not in atServer
    ///   - (a) encrypt the unencrypted copy with their public key
    ///         (i) Fetch their public key
    ///         (ii) Encrypt the symmetric key with their public key
    ///   - (b) save encrypted copy to atServer
    ///   - (c) save encrypted copy to local storage and return

    ///   - (a) encrypt the unencrypted copy with their public key
    ///         (i) Fetch their public key
    late String sharedWithPublicKey;
    try {
      sharedWithPublicKey = await _getSharedWithPublicKey(atKey);
    } on AtPublicKeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.shareData, ExceptionScenario.encryptionFailed, e.message));
      rethrow;
    }

    ///         (ii) Encrypt the symmetric key with their public key
    theirEncryptedCopy =
        EncryptionUtil.encryptKey(symmetricKeyBase64, sharedWithPublicKey);

    ///   - (b) save encrypted copy to atServer
    _logger.info(
        "Saving 'their' copy of shared symmetric key for ${atKey.sharedWith} to atServer");
    await storeTheirCopyOfEncryptedSharedKeyToSecondary(
        atKey, theirEncryptedCopy,
        secondary: _atClient.getRemoteSecondary()!);

    ///   - (c) save encrypted copy to local storage and return
    _logger.info(
        "Saving 'their' copy of shared symmetric key for ${atKey.sharedWith} to local storage");
    await storeTheirCopyOfEncryptedSharedKeyToSecondary(
        atKey, theirEncryptedCopy,
        secondary: _atClient.getLocalSecondary()!);

    return theirEncryptedCopy;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String> _getSharedWithPublicKey(AtKey atKey) async {
    String? sharedWithPublicKey;
    try {
      // 1. Get the cached public key
      var cachedEncryptionPublicKeyBuilder = LLookupVerbBuilder()
        ..atKey = 'publickey'
        ..sharedBy = atKey.sharedWith
        ..isPublic = true
        ..isCached = true;

      sharedWithPublicKey = await _atClient
          .getLocalSecondary()!
          .executeVerb(cachedEncryptionPublicKeyBuilder);
    } on KeyNotFoundException {
      _logger.finer('${atKey.sharedWith} encryption public key is not found');
    }
    try {
      if (sharedWithPublicKey.isNull || sharedWithPublicKey == 'data:null') {
        var encryptionPublicKeyBuilder = PLookupVerbBuilder()
          ..atKey = 'publickey'
          ..sharedBy = atKey.sharedWith;
        sharedWithPublicKey = await _atClient
            .getRemoteSecondary()!
            .executeVerb(encryptionPublicKeyBuilder);
      }
    } on AtException catch (exception) {
      throw AtPublicKeyNotFoundException(
          'Failed to fetch public key of ${atKey.sharedWith}')
        ..fromException(exception)
        ..stack(AtChainedException(Intent.shareData,
            ExceptionScenario.keyNotFound, exception.message));
    }
    if (sharedWithPublicKey.isNull || sharedWithPublicKey == 'data:null') {
      return throw AtPublicKeyNotFoundException(
          'Failed to fetch public key of ${atKey.sharedWith}');
    }
    return defaultResponseParser.parse(sharedWithPublicKey!).response;
  }

  /// Stores the encryptedSharedKey for future use.
  Future<void> _storeMyEncryptedCopyOfSharedSymmetricKey(
      AtKey atKey, String encryptedSharedKey, Secondary secondary) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy
      ..value = encryptedSharedKey;
    await secondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder,
        sync: false);
  }

  /// Gets the encrypted shared key from the given secondary instance - Local Secondary or Remote Secondary
  ///
  /// Throws [KeyNotFoundException] is key is not found the secondary
  Future<String?> _getMyEncryptedCopyOfSharedSymmetricKey(
      Secondary secondary, AtKey atKey) async {
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;
    String? myCopy;

    try {
      myCopy = await secondary.executeVerb(llookupVerbBuilder);
      // ignore: unused_catch_clause, empty_catches
    } on KeyNotFoundException catch (ignore) {}
    if (myCopy == 'data:null') {
      myCopy = null;
    }
    if (myCopy != null && myCopy.startsWith('data:')) {
      myCopy = myCopy.replaceFirst('data:', '');
    }
    return myCopy;
  }

  /// Gets the encrypted shared key from the given secondary instance - Local Secondary or Remote Secondary
  ///
  /// Throws [KeyNotFoundException] is key is not found the secondary
  Future<String?> _getTheirEncryptedCopyOfSharedSymmetricKey(
      Secondary secondary, AtKey atKey) async {
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedBy = atKey.sharedBy
      ..sharedWith = atKey.sharedWith;
    String? theirCopy;
    try {
      theirCopy = await secondary.executeVerb(llookupVerbBuilder);
      // ignore: empty_catches, unused_catch_clause
    } on KeyNotFoundException catch (ignore) {}
    if (theirCopy == 'data:null') {
      theirCopy = null;
    }
    if (theirCopy != null && theirCopy.startsWith('data:')) {
      theirCopy = theirCopy.replaceFirst('data:', '');
    }
    return theirCopy;
  }

  Future<String?> storeTheirCopyOfEncryptedSharedKeyToSecondary(
      AtKey atKey, String encryptedSharedKeyValue,
      {Secondary? secondary}) async {
    secondary ??= _atClient.getLocalSecondary()!;
    var updateSharedKeyBuilder = UpdateVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedWith = atKey.sharedWith
      ..sharedBy = atKey.sharedBy
      ..ttr = 3888000
      ..value = encryptedSharedKeyValue;
    return await secondary.executeVerb(updateSharedKeyBuilder, sync: false);
  }
}
