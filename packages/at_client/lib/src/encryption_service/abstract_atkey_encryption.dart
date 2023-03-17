import 'dart:collection';

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

  @visibleForTesting
  static final HashMap<String, bool> encryptedSharedKeySyncStatusCacheMap =
      HashMap();

  SyncUtil syncUtil = SyncUtil();

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    String sharedWithPublicKey = '';
    String encryptedSharedKey = '';
    // 1. Get AES Key from the local storage
    _sharedKey = await getSharedKey(atKey);
    // Fetch the encryption public key of the sharedWith atSign
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
    if (_sharedKey.isEmpty) {
      // Generate sharedKey
      _sharedKey = EncryptionUtil.generateAESKey();
      // Encrypt shared key with public key of sharedWith atSign.
      encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
      // Update the encrypted sharedKey to local secondary with TTR
      await updateEncryptedSharedKeyToSecondary(atKey, encryptedSharedKey);
      // Encrypt the sharedKey with currentAtSignPublicKey and store it for future use.
      String? currentAtSignEncryptionPublicKey;
      try {
        currentAtSignEncryptionPublicKey = await _atClient
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
    }
    // For the existing shared_key, the encryptedSharedKey has to be fetched
    // from the local secondary
    if (encryptedSharedKey.isNull) {
      encryptedSharedKey =
          EncryptionUtil.encryptKey(sharedKey, sharedWithPublicKey);
    }
    // Check if the encryptedSharedKey is synced to remote secondary
    // If not synced, update the key to remote secondary directly
    if (!(await isEncryptedSharedKeyInSync(atKey))) {
      await updateEncryptedSharedKeyToSecondary(atKey, encryptedSharedKey,
          secondary: _atClient.getRemoteSecondary());
    }
    atKey.metadata!.sharedKeyEnc = encryptedSharedKey;
    atKey.metadata!.pubKeyCS = EncryptionUtil.md5CheckSum(sharedWithPublicKey);
  }

  /// Fetches the shared key in the local secondary
  /// If not found, fetches in the remote secondary
  /// If found, returns the decrypted sharedKey.
  ///
  /// If shared_key is not found in local secondary and remote secondary, returns an empty string
  ///
  /// Throws [KeyNotFoundException] if the encryptionPrivateKey is not found.
  Future<String> getSharedKey(AtKey atKey) async {
    String? encryptedSharedKey;
    try {
      // 1. Look for shared key in local secondary
      encryptedSharedKey =
          await _getEncryptedSharedKey(_atClient.getLocalSecondary()!, atKey);
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.key}${atKey.sharedBy} not found in local secondary. Fetching from remote secondary');
    }
    try {
      // 2. If sharedKey is not found in localSecondary, fetch from remote secondary.
      if (encryptedSharedKey.isNull || encryptedSharedKey == 'data:null') {
        encryptedSharedKey = await _getEncryptedSharedKey(
            _atClient.getRemoteSecondary()!, atKey);
      }
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.key}${atKey.sharedBy} not found in remote secondary. Generating a new shared key');
    }
    if (encryptedSharedKey.isNull || encryptedSharedKey == 'data:null') {
      return '';
    }
    encryptedSharedKey =
        defaultResponseParser.parse(encryptedSharedKey!).response;
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
    if (_atClient.getPreferences()!.useAtChops) {
      final decryptionResult = _atClient.atChops!
          .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
      return decryptionResult.result;
    } else {
      try {
        // ignore: deprecated_member_use_from_same_package
        return EncryptionUtil.decryptKey(
            encryptedSharedKey, encryptionPrivateKey!);
      } on KeyNotFoundException catch (e) {
        e.stack(AtChainedException(
            Intent.fetchEncryptionPrivateKey,
            ExceptionScenario.encryptionFailed,
            'Failed to decrypt the encrypted shared key'));
        rethrow;
      }
    }
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
  /// Optionally set shouldSync parameter to false to avoid the key to sync to cloud secondary
  /// Defaulted to sync the key to cloud secondary.
  void _storeSharedKey(AtKey atKey, String encryptedSharedKey,
      {bool shouldSync = true}) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy
      ..value = encryptedSharedKey;
    await _atClient
        .getLocalSecondary()!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: shouldSync);
  }

  /// Gets the encrypted shared key from the given secondary instance - Local Secondary or Remote Secondary
  ///
  /// Throws [KeyNotFoundException] is key is not found the secondary
  Future<String?> _getEncryptedSharedKey(
      Secondary secondary, AtKey atKey) async {
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = atKey.sharedBy;
    return await secondary.executeVerb(llookupVerbBuilder);
  }

  /// Checks if the encryptedSharedKey is synced to the cloud secondary
  ///
  /// If Synced, returns true; else returns false.
  Future<bool> isEncryptedSharedKeyInSync(AtKey atKey) async {
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedBy = atKey.sharedBy
      ..sharedWith = atKey.sharedWith;
    // If key is present in cache, return true
    if (encryptedSharedKeySyncStatusCacheMap
        .containsKey(llookupVerbBuilder.buildKey())) {
      return encryptedSharedKeySyncStatusCacheMap[
          llookupVerbBuilder.buildKey()]!;
    }
    // Set the commit log instance if not already set.
    atCommitLog ??= await AtCommitLogManagerImpl.getInstance()
        .getCommitLog(atKey.sharedBy!);

    CommitEntry sharedKeyCommitEntry = await syncUtil.getLatestCommitEntry(
        atCommitLog!, llookupVerbBuilder.buildKey());
    if (sharedKeyCommitEntry.commitId == null) {
      return false;
    }
    // If key is present, update the status to cache map and return true/
    encryptedSharedKeySyncStatusCacheMap.putIfAbsent(
        llookupVerbBuilder.buildKey(), () => true);
    return true;
  }

  Future<String?> updateEncryptedSharedKeyToSecondary(
      AtKey atKey, String encryptedSharedKeyValue,
      {Secondary? secondary}) async {
    secondary ??= _atClient.getLocalSecondary()!;
    var updateSharedKeyBuilder = UpdateVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedWith = atKey.sharedWith
      ..sharedBy = atKey.sharedBy
      ..ttr = 3888000
      ..value = encryptedSharedKeyValue;
    return await secondary.executeVerb(updateSharedKeyBuilder, sync: true);
  }
}
