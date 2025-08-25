import 'package:at_chops/at_chops.dart';
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
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    _sharedKey = await getMyCopyOfSharedSymmetricKey(atKey);
    if (_sharedKey.isEmpty) {
      _sharedKey = await createMyCopyOfSharedSymmetricKey(atKey);
    }

    var theirEncryptedSymmetricKeyCopy =
        await verifyTheirCopyOfSharedSymmetricKey(atKey, _sharedKey);

    atKey.metadata.sharedKeyEnc = theirEncryptedSymmetricKeyCopy;
    // This is a legacy checksum with MD5 algo.
    atKey.metadata.pubKeyCS =
        EncryptionUtil.md5CheckSum(await _getSharedWithPublicKey(atKey));
    // Hashed the encryption public key with sha512. This is to ensure the encryption
    // public key of the receiver are same during encryption and decryption process.
    String hash = await AtChops.hashWith(HashingAlgoType.sha512)
        .hash((await _getSharedWithPublicKey(atKey)).codeUnits);
    atKey.metadata.pubKeyHash =
        PublicKeyHash(hash, HashingAlgoType.sha512.name);
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
      /// Also, delete *their* copy from our local storage
      if (encryptedSharedKey.isNull || encryptedSharedKey == 'data:null') {
        _logger.info(
            'Encrypted shared symmetric key for ${atKey.sharedBy} not found in local storage');

        _logger.info(
            'Fetching shared symmetric key for ${atKey.sharedBy} from atServer');
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
    final decryptionResult = _atClient.atChops!
        .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
    return decryptionResult.result;
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
    // Generate new symmetric key
    var newSymmetricKeyBase64 =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // Encrypt the new symmetric key with our public key
    var atChopsEncryptionResult = _atClient.atChops!
        .encryptString(newSymmetricKeyBase64, EncryptionKeyType.rsa2048);
    var encryptedSharedKeyMyCopy = atChopsEncryptionResult.result;
    _logger.info(
        'encryptedSharedKeyMyCopy from atChops: $encryptedSharedKeyMyCopy');

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

  /// Fetch public key of recipient
  /// Encrypt symmetric key with their public key
  Future<String> encryptSymmetricKeyForRecipient(
      AtKey atKey, String symmetricKeyBase64) async {
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
    var rsaEncryptionAlgo = RsaEncryptionAlgo();
    rsaEncryptionAlgo.atPublicKey = AtPublicKey.fromString(sharedWithPublicKey);
    var encryptionResult = _atClient.atChops!.encryptString(
        symmetricKeyBase64, EncryptionKeyType.rsa2048,
        encryptionAlgorithm: rsaEncryptionAlgo);
    String encryptedSharedSymmetricKey = encryptionResult.result!;
    inMemEncryptedSharedSymmetricKeyCache[atKey.sharedWith!] =
        encryptedSharedSymmetricKey;
    return encryptedSharedSymmetricKey;
  }

  Map<String, String> inMemEncryptedSharedSymmetricKeyCache = {};

  /// There was a whole set of legacy code here which has been removed
  /// since it is not actually useful other than causing race conditions.
  ///
  /// In order to mitigate race conditions caused by the soon-to-be-legacy
  /// behaviour of having a single symmetric key, we will always
  /// encrypt the actual symmetric key we are using, caching it in memory for
  /// reuse, rather than storing it to data stores etc. It is safe to do this
  /// because for a long time, clients will decrypt using the `sharedKeyEnc`
  /// in the metadata, which we are always setting.
  Future<String> verifyTheirCopyOfSharedSymmetricKey(
      AtKey atKey, String symmetricKeyBase64) async {
    // If it's not already in the cache, do the encryption.
    if (!inMemEncryptedSharedSymmetricKeyCache.containsKey(atKey.sharedWith)) {
      await encryptSymmetricKeyForRecipient(atKey, symmetricKeyBase64);
    }
    return inMemEncryptedSharedSymmetricKeyCache[atKey.sharedWith!]!;
  }

  /// Returns sharedWith atSign publicKey.
  /// Throws [KeyNotFoundException] if sharedWith atSign publicKey is not found.
  Future<String> _getSharedWithPublicKey(AtKey atKey) async {
    try {
      // 1. Try to fetch cached public key from local storage
      var cachedEncryptionPublicKeyBuilder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'publickey'
          ..sharedBy = atKey.sharedWith
          ..metadata = (Metadata()
            ..isPublic = true
            ..isCached = true));

      String? llookupResponse = await _atClient
          .getLocalSecondary()!
          .executeVerb(cachedEncryptionPublicKeyBuilder);

      // Got it - return
      if (llookupResponse != null && llookupResponse != 'data:null') {
        String cachedLocallyPK =
            defaultResponseParser.parse(llookupResponse).response;
        _logger.finest('Found public key locally: $cachedLocallyPK');
        return cachedLocallyPK;
      }
    } on KeyNotFoundException {
      _logger.finer('${atKey.sharedWith} encryption public key is not found');
    }

    // Didn't find in local storage - check on atServer
    try {
      var encryptionPublicKeyBuilder = PLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'publickey'
          ..sharedBy = atKey.sharedWith);
      final String fetchedPK = defaultResponseParser
          .parse(await _atClient
              .getRemoteSecondary()!
              .executeVerb(encryptionPublicKeyBuilder))
          .response;

      // Got it - first of all, cache it locally (in case sync is not enabled)
      final uvb = UpdateVerbBuilder()
        ..atKey = AtKey.fromString('cached:public:publickey${atKey.sharedWith}')
        ..value = fetchedPK;
      _logger.info('Updating public key locally: ${uvb.buildCommand()}');
      await _atClient.getLocalSecondary()!.executeVerb(uvb, sync: false);

      // Then return it
      return fetchedPK;
    } on AtException catch (exception) {
      throw AtPublicKeyNotFoundException(
          'Failed to fetch public key of ${atKey.sharedWith}')
        ..fromException(exception)
        ..stack(AtChainedException(Intent.shareData,
            ExceptionScenario.keyNotFound, exception.message));
    }
  }

  /// Stores the encryptedSharedKey for future use.
  Future<void> _storeMyEncryptedCopyOfSharedSymmetricKey(
      AtKey atKey, String encryptedSharedKey, Secondary secondary) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key =
            '${AtConstants.atEncryptionSharedKey}.${atKey.sharedWith?.replaceAll('@', '')}'
        ..sharedBy = atKey.sharedBy)
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
      ..atKey = (AtKey()
        ..key =
            '${AtConstants.atEncryptionSharedKey}.${atKey.sharedWith?.replaceAll('@', '')}'
        ..sharedBy = atKey.sharedBy);
    String? myCopy;

    try {
      myCopy = await secondary.executeVerb(llookupVerbBuilder);
      // ignore: unused_catch_clause, empty_catches
    } on KeyNotFoundException catch (ignore) {}
    if (myCopy == 'data:null') {
      myCopy = null;
    }
    if (myCopy != null && myCopy.startsWith('data:')) {
      myCopy = myCopy.replaceFirst(RegExp('^data:'), '');
    }
    return myCopy;
  }
}
