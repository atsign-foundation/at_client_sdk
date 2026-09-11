import 'package:at_commons/at_builders.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_utils/at_logger.dart';
import 'legacy_encryption.dart';
import 'string_crypto.dart';

/// The hashing algorithm a record's `pubKeyHash.hashingAlgo` names.
///
/// The switch is exhaustive, so a new [HashingAlgoType] stops this compiling
/// rather than failing at runtime.
AtHashingAlgorithm _hashingAlgorithmFor(HashingAlgoType algoType) =>
    switch (algoType) {
      HashingAlgoType.sha256 => SHA256HashingAlgo(),
      HashingAlgoType.sha512 => SHA512HashingAlgo(),
      HashingAlgoType.md5 => Md5HashingAlgo(),
      HashingAlgoType.argon2id => Argon2idHashingAlgo(),
    };

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

    // The local secondary resolves this across every tier the client has:
    // an injected AtChops, then its key source, then the keystore.
    String? selfEncryptionKey =
        await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
    if (selfEncryptionKey.isNullOrEmpty) {
      throw SelfKeyNotFoundException(
          'Failed to decrypt the key: ${atKey.toString()} caused by self encryption key not found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }

    InitialisationVector iV;
    if (atKey.metadata.ivNonce != null) {
      iV = InitialisationVector.fromBase64(atKey.metadata.ivNonce!);
    } else {
      iV = InitialisationVector.legacy();
    }
    String decryptedValue;
    try {
      var encryptionAlgo = AESEncryptionAlgo(
          AESKey(DefaultResponseParser().parse(selfEncryptionKey!).response));
      decryptedValue =
          await decryptStringFromBase64(encryptedValue, encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during decryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptedValue;
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
      iV = InitialisationVector.fromBase64(atKey.metadata.ivNonce!);
    } else {
      iV = InitialisationVector.legacy();
    }
    String decryptedValue;
    try {
      var encryptionAlgo = AESEncryptionAlgo(AESKey(symmetricKey));
      decryptedValue =
          await decryptStringFromBase64(encryptedValue, encryptionAlgo, iv: iV);
      _logger.finer('decrypted value: $decryptedValue');
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptedValue;
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
            _hashingAlgorithmFor(HashingAlgoType.fromString(
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

    String decryptedValue;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = InitialisationVector.fromBase64(atKey.metadata.ivNonce!);
      } else {
        iV = InitialisationVector.legacy();
      }
      final sharedKey = await decryptStringFromBase64(
          encryptedSharedKey, await atSignDecryptionAlgo(_atClient));
      var encryptionAlgo = AESEncryptionAlgo(
          AESKey(DefaultResponseParser().parse(sharedKey).response));
      decryptedValue =
          await decryptStringFromBase64(encryptedValue, encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptedValue;
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
