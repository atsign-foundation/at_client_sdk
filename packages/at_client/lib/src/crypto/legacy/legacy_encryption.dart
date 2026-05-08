import 'package:at_client/at_client.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

abstract class AtKeyEncryption {
  Future<dynamic> encrypt(AtKey atKey, dynamic value);
}

/// The manager class for [AtKeyEncryption]
class LegacyEncryption {
  static AtKeyEncryption build(AtKey atKey, AtClient atClient) {
    // If atKey is sharedKey, return sharedKeyEncryption
    // Eg. @bob:phone.wavi@alice. and @alice is currentAtSign.
    // else returns SelfKeyEncryption.
    //
    // For keys like '@alice:phone@alice', a self encryption should be performed.
    // Setting the following condition in OR clause as well to support instances of
    // concrete AtKey class - "atKey.sharedWith != null && atKey.sharedWith != currentAtSign"
    Atsign currentAtSign = atClient.getCurrentAtSign()!.toAtsign();
    if (_isSharedKey(atKey, currentAtSign)) {
      return SharedKeyEncryption(atClient);
    }
    return SelfKeyEncryption(atClient);
  }

  static bool _isSharedKey(AtKey key, Atsign atsign) {
    return key.sharedWith != null && key.sharedWith != atsign;
  }
}

/// Contains the common code for [SharedKeyEncryption] and [StreamEncryption]
abstract class AbstractAtKeyEncryption implements AtKeyEncryption {
  final AtSignLogger _logger = AtSignLogger('AtKeyEncryption');
  late String _sharedKey;
  final AtClient _atClient;
  AtCommitLog? atCommitLog;

  DefaultResponseParser defaultResponseParser = DefaultResponseParser();

  String get sharedKey => _sharedKey;

  AbstractAtKeyEncryption(this._atClient);

  SyncUtil syncUtil = SyncUtil();

  /// - Fetches the appropriate shared symmetric key by calling
  /// [getMyCopyOfSharedSymmetricKey]
  /// - Calls [createLegacySharedSymmetricKey] if
  ///   [getMyCopyOfSharedSymmetricKey] returns the empty string
  /// - Calls [getTheirCopyOfLegacySharedSymmetricKey]
  /// - Doesn't actually encrypt the value, leaves that to the relevant
  ///   subclass.
  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    _sharedKey = await getMyCopyOfSharedSymmetricKey(atKey);
    if (_sharedKey.isEmpty) {
      _sharedKey = await createLegacySharedSymmetricKey(atKey);
    }

    var theirEncryptedSymmetricKeyCopy =
        await getTheirCopyOfLegacySharedSymmetricKey(atKey, _sharedKey);

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
    final decryptionResult = await _atClient.atChops!
        .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
    return decryptionResult.result;
  }

  /// Create a new symmetric shared key and share it.
  /// - cut key, encrypt copy for self, and save to remote atServer, then to
  ///   local storage, return the unencrypted symmetric key
  ///
  /// This is 'legacy' because it is a singleton, and we should and will have
  /// many many symmetric keys.
  @visibleForTesting
  Future<String> createLegacySharedSymmetricKey(AtKey atKey) async {
    _logger.info(
        "Creating new shared symmetric key as ${atKey.sharedBy} for ${atKey.sharedWith}");
    // Generate new symmetric key
    var newSymmetricKeyBase64 =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // Encrypt the new symmetric key with our public key
    var atChopsEncryptionResult = await _atClient.atChops!
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

    // Now store to local
    _logger.info("Storing new shared symmetric key to local storage");
    await _storeMyEncryptedCopyOfSharedSymmetricKey(
        atKey, encryptedSharedKeyMyCopy, _atClient.getLocalSecondary()!);

    // Store 'their' copy - this is for backwards compatibility.
    await _shareEncryptedCopyOfLegacySymmetricKey(atKey,
        await encryptSymmetricKeyForRecipient(atKey, newSymmetricKeyBase64));
    // Return the unencrypted symmetric key
    return newSymmetricKeyBase64;
  }

  Future<void> _shareEncryptedCopyOfLegacySymmetricKey(
    AtKey atKey,
    String encryptedSharedKeyValue,
  ) async {
    var updateSharedKeyBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = AtConstants.atEncryptionSharedKey
        ..sharedWith = atKey.sharedWith
        ..sharedBy = atKey.sharedBy
        ..metadata = (Metadata()..ttr = 3888000))
      ..value = encryptedSharedKeyValue;
    await _atClient
        .getRemoteSecondary()!
        .executeVerb(updateSharedKeyBuilder, sync: false);
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
    var encryptionResult = await _atClient.atChops!.encryptString(
        symmetricKeyBase64, EncryptionKeyType.rsa2048,
        encryptionAlgorithm: rsaEncryptionAlgo);
    String encryptedSharedSymmetricKey = encryptionResult.result!;
    return encryptedSharedSymmetricKey;
  }

  /// There was a whole set of legacy code here which has been removed
  /// since it is not actually useful other than causing race conditions.
  ///
  /// In order to mitigate race conditions caused by the soon-to-be-legacy
  /// behaviour of having a single symmetric key, we will always
  /// encrypt the actual symmetric key we are using and set it in the
  /// metadata, rather than storing it to data stores etc. It is safe to do
  /// this because for a long time, clients have been decrypting using the
  /// `sharedKeyEnc` in the metadata, which we are always setting.
  Future<String> getTheirCopyOfLegacySharedSymmetricKey(
      AtKey atKey, String symmetricKeyBase64) async {
    return await encryptSymmetricKeyForRecipient(atKey, symmetricKeyBase64);
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

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  final _logger = AtSignLogger('SelfKeyEncryption');
  final AtClient atClient;

  SelfKeyEncryption(this.atClient);

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    String? selfEncryptionKey;
    if (value is! String) {
      _logger.severe(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    // Get SelfEncryptionKey from atChops
    // https://github.com/atsign-foundation/at_client_sdk/issues/1294 causes selfEncryptionKey to be null in atChops.
    // Fetch from LocalSecondary until the above issue is fixed.
    selfEncryptionKey = atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;
    if (selfEncryptionKey.isNullOrEmpty) {
      // Fetch Self Encryption Key from Local Secondary
      // Remove this call after the atChops has self encryption key populated from AtClientMobile.
      selfEncryptionKey =
          await _getSelfEncryptionKey(atClient.getLocalSecondary()!);
    }
    // If selfEncryptionKey is null in atChops and in Local Secondary throw exception.
    if (selfEncryptionKey.isNullOrEmpty) {
      throw SelfKeyNotFoundException(
          'Failed to encrypt the data caused by Self encryption key not found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }

    AtEncryptionResult encryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      var encryptionAlgo = AESEncryptionAlgo(AESKey(selfEncryptionKey!));
      encryptionResultFromAtChops = await atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during self encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return encryptionResultFromAtChops.result;
  }

  Future<String?> _getSelfEncryptionKey(LocalSecondary localSecondary) async {
    String? selfEncryptionKey;
    try {
      selfEncryptionKey = await localSecondary.getEncryptionSelfKey();
    } on KeyNotFoundException {
      throw SelfKeyNotFoundException(
          'Self encryption key is not set for current atSign',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }
    return selfEncryptionKey;
  }
}

class SharedKeyEncryption extends AbstractAtKeyEncryption {
  SharedKeyEncryption(super._atClient);

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    // Call super.encrypt to take care of getting hold of the correct
    // encryption key and setting it in super.sharedKey
    await super.encrypt(atKey, value);
    AtEncryptionResult encryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      var encryptionAlgo = AESEncryptionAlgo(AESKey(sharedKey));
      encryptionResultFromAtChops = await _atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during shared key encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return encryptionResultFromAtChops.result;
  }
}
