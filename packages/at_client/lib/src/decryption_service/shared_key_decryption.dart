import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_chops/at_chops.dart';

/// Class responsible for decrypting the value of shared key's that are not owned
/// by currentAtSign
/// Example:
/// CurrentAtSign: @bob
/// lookup:phone@alice
class SharedKeyDecryption implements AtKeyDecryption {
  final AtClient _atClient;
  late final AtSignLogger _logger;

  SharedKeyDecryption(this._atClient) {
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
    if (atKey.metadata != null) {
      encryptedSharedKey = atKey.metadata!.sharedKeyEnc;
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
    if (currentAtSignPublicKey != null &&
        atKey.metadata != null &&
        atKey.metadata!.pubKeyCS != null &&
        atKey.metadata!.pubKeyCS !=
            EncryptionUtil.md5CheckSum(currentAtSignPublicKey)) {
      throw AtPublicKeyChangeException(
          'Public key has changed. Cannot decrypt shared key ${atKey.toString()}',
          intent: Intent.fetchEncryptionPublicKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }

    AtEncryptionResult decryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata?.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata!.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      final decryptionResult = _atClient.atChops!
          .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
      var encryptionAlgo = AESEncryptionAlgo(AESKey(
          DefaultResponseParser().parse(decryptionResult.result).response));
      decryptionResultFromAtChops = _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtKeyException catch (e) {
      e.stack(AtChainedException(
          Intent.decryptData,
          ExceptionScenario.decryptionFailed,
          'Failed to decrypt ${atKey.toString()}'));
      rethrow;
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
      ..atKey = AtConstants.atEncryptionSharedKey
      ..sharedWith = _atClient.getCurrentAtSign()
      ..sharedBy = atKey.sharedBy
      ..isCached = true;
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
        ..atKey = AtConstants.atEncryptionSharedKey
        ..sharedBy = atKey.sharedBy
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
