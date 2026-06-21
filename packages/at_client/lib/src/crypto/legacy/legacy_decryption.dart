import 'package:at_commons/at_builders.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_utils/at_logger.dart';
import 'legacy_encryption.dart';

class LegacyDecryption {
  static AtKeyDecryption build(AtKey key, AtClient atClient) {
    AppMetadata? meta = key.metadata.appMetadata;
    // Legacy values carry either no appMetadata (old data / old clients) or
    // appMetadata{providerId:'legacy'} (the runtime stamps the default provider
    // id on encrypt). Both route here and must use the legacy strategy. Only a
    // NON-legacy providerId reaching this builder is a routing bug.
    if (meta == null || meta.providerId == legacyCryptoProviderId) {
      //legacy implementation
      Atsign myAtsign = atClient.getCurrentAtSign()!.toAtsign();
      if (key.sharedBy != myAtsign) {
        return SharedWithMeDecryption(atClient);
      }
      // Shared by me with others
      if (key.sharedWith != null && key.sharedWith != myAtsign) {
        return SharedByMeDecryption(atClient);
      }
      // Shared by me with myself
      // Eg: currentAtSign is @bob and _phone.wavi@bob (or) phone@bob (or) @bob:phone@bob
      if (((key.sharedWith == null || key.sharedWith == myAtsign) &&
              key.sharedBy == myAtsign) ||
          key.key.startsWith('_')) {
        return SelfKeyDecryption(atClient);
      }
      throw StateError(
        'Legacy $key is neither sharedByMe, sharedWithMe nor self',
      );
    }
    throw StateError('AppMetadata is not null, should be using non-legacy');
  }
}

abstract class AtKeyDecryption {
  Future<dynamic> decrypt(AtKey key, dynamic value);
}

/// Class responsible for decrypting values shared with myself
/// If I am @alice then an example would be @alice:foo.bar@alice
class SelfKeyDecryption implements AtKeyDecryption {
  late final AtSignLogger _logger;

  final AtClient _atClient;

  SelfKeyDecryption(this._atClient) {
    _logger =
        AtSignLogger('SelfKeyDecryption (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }

    // Get SelfEncryptionKey from atChops
    // https://github.com/atsign-foundation/at_client_sdk/issues/1294 causes selfEncryptionKey to be null in atChops.
    // Fetch from LocalSecondary until the above issue is fixed.
    String? selfEncryptionKey =
        _atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;
    if (selfEncryptionKey.isNullOrEmpty) {
      // Fetch Self Encryption Key from Local Secondary
      // Remove this call after the atChops has self encryption key populated from AtClientMobile.
      selfEncryptionKey =
          await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
    }
    // If selfEncryptionKey is null in atChops and in Local Secondary throw exception.
    if (selfEncryptionKey.isNullOrEmpty) {
      throw SelfKeyNotFoundException(
          'Failed to decrypt the key: ${atKey.toString()} caused by self encryption key not found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }

    InitialisationVector iV;
    if (atKey.metadata.ivNonce != null) {
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
    } else {
      iV = AtChopsUtil.generateIVLegacy();
    }
    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(
          AESKey(DefaultResponseParser().parse(selfEncryptionKey!).response));
      decryptionResultFromAtChops = await _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during decryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }
}

/// Class responsible for decrypting values shared by me TO others
/// If I am @alice then an example would be @bob:foo.bar@alice
class SharedByMeDecryption extends AbstractAtKeyEncryption
    implements AtKeyDecryption {
  late final AtSignLogger _logger;
  final AtClient _atClient;

  SharedByMeDecryption(this._atClient) : super(_atClient) {
    _logger =
        AtSignLogger('LocalKeyDecryption (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future<String> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    // Get the shared key.
    var symmetricKey = await getMyCopyOfSharedSymmetricKey(atKey);

    if (symmetricKey.isEmpty) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw SharedKeyNotFoundException('Empty or null SharedKey is found',
          intent: Intent.fetchEncryptionSharedKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    InitialisationVector iV;
    if (atKey.metadata.ivNonce != null) {
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
    } else {
      iV = AtChopsUtil.generateIVLegacy();
    }
    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(AESKey(symmetricKey));
      decryptionResultFromAtChops = await _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
      _logger.finer(
          'decryptionResultFromAtChops: ${decryptionResultFromAtChops.result}');
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }
}

/// Class responsible for decrypting values shared BY others with me
/// If I am @alice then an example would be @alice:foo.bar@charlie
class SharedWithMeDecryption implements AtKeyDecryption {
  final AtClient _atClient;
  late final AtSignLogger _logger;

  SharedWithMeDecryption(this._atClient) {
    _logger =
        AtSignLogger('SharedKeyDecryption (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    String? encryptedSharedKey;
    if (atKey.metadata.sharedKeyEnc != null) {
      encryptedSharedKey = atKey.metadata.sharedKeyEnc;
    }
    encryptedSharedKey ??= await _getEncryptedSharedKey(atKey);
    if (encryptedSharedKey.isEmpty || encryptedSharedKey == 'null') {
      throw SharedKeyNotFoundException('shared encryption key not found',
          intent: Intent.fetchEncryptionSharedKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    String? currentAtSignPublicKey;
    try {
      currentAtSignPublicKey = (await _atClient
              .getLocalSecondary()!
              .getEncryptionPublicKey(_atClient.getCurrentAtSign()!))
          ?.trim();
    } on KeyNotFoundException {
      throw AtPublicKeyNotFoundException(
          'Failed to fetch the current atSign public key - public:publickey${_atClient.getCurrentAtSign()!}',
          intent: Intent.fetchEncryptionPublicKey,
          exceptionScenario: ExceptionScenario.localVerbExecutionFailed);
    }
    if (currentAtSignPublicKey.isNullOrEmpty) {
      throw AtPublicKeyNotFoundException('Public key cannot be null or empty');
    }

    final isPubKeyHashMismatch = atKey.metadata.pubKeyHash != null &&
        atKey.metadata.pubKeyHash?.hash !=
            AtChops.hashWith(HashingAlgoType.fromString(
                    atKey.metadata.pubKeyHash!.hashingAlgo))
                .hash(currentAtSignPublicKey!.codeUnits);

    final isPubKeyCSMismatch = atKey.metadata.pubKeyCS != null &&
        atKey.metadata.pubKeyCS !=
            EncryptionUtil.md5CheckSum(currentAtSignPublicKey!);

    if (isPubKeyHashMismatch || isPubKeyCSMismatch) {
      throw AtPublicKeyChangeException(
        'Public key has changed. Cannot decrypt shared key ${atKey.toString()}',
        intent: Intent.fetchEncryptionPublicKey,
        exceptionScenario: ExceptionScenario.decryptionFailed,
      );
    }

    AtEncryptionResult decryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      final decryptionResult = await _atClient.atChops!
          .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
      var encryptionAlgo = AESEncryptionAlgo(AESKey(
          DefaultResponseParser().parse(decryptionResult.result).response));
      decryptionResultFromAtChops = await _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }

  Future<String> _getEncryptedSharedKey(AtKey atKey) async {
    String? encryptedSharedKey = '';
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = AtConstants.atEncryptionSharedKey
        ..sharedWith = _atClient.getCurrentAtSign()
        ..sharedBy = atKey.sharedBy
        ..metadata = (Metadata()..isCached = true));
    try {
      encryptedSharedKey = await _atClient
          .getLocalSecondary()!
          .executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.sharedBy}:${localLookupSharedKeyBuilder.atKey}@${atKey.sharedWith} not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == null ||
        encryptedSharedKey.isEmpty ||
        encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = AtConstants.atEncryptionSharedKey
          ..sharedBy = atKey.sharedBy)
        ..auth = true;
      encryptedSharedKey = await _atClient
          .getRemoteSecondary()!
          .executeVerb(sharedKeyLookUpBuilder);
      encryptedSharedKey =
          DefaultResponseParser().parse(encryptedSharedKey).response;
    }
    if (encryptedSharedKey.isNotEmpty) {
      return DefaultResponseParser().parse(encryptedSharedKey).response;
    }
    return encryptedSharedKey;
  }
}
