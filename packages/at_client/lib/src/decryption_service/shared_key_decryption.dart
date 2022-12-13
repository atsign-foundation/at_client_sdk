import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';
import 'package:at_chops/at_chops.dart';

/// Class responsible for decrypting the value of shared key's that are not owned
/// by currentAtSign
/// Example:
/// CurrentAtSign: @bob
/// lookup:phone@alice
class SharedKeyDecryption implements AtKeyDecryption {
  @visibleForTesting
  late AtClient? atClient;
  final _logger = AtSignLogger('SharedKeyDecryption');

  SharedKeyDecryption({this.atClient});

  @override
  Future decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    String? encryptedSharedKey;
    atClient ??= AtClientManager.getInstance().atClient;
    if (atKey.metadata != null && atKey.metadata!.pubKeyCS != null) {
      encryptedSharedKey = atKey.metadata!.sharedKeyEnc;
      String? currentAtSignPublicKey;
      try {
        currentAtSignPublicKey = (await atClient
                ?.getLocalSecondary()!
                .getEncryptionPublicKey(atClient!.getCurrentAtSign()!))
            ?.trim();
      } on KeyNotFoundException {
        throw AtPublicKeyNotFoundException(
            'Failed to fetch the current atSign public key - public:publickey${atClient!.getCurrentAtSign()!}',
            intent: Intent.fetchEncryptionPublicKey,
            exceptionScenario: ExceptionScenario.localVerbExecutionFailed);
      }
      if (currentAtSignPublicKey != null &&
          atKey.metadata!.pubKeyCS !=
              EncryptionUtil.md5CheckSum(currentAtSignPublicKey)) {
        throw AtPublicKeyChangeException(
            'Public key has changed. Cannot decrypt shared key ${atKey.toString()}',
            intent: Intent.fetchEncryptionPublicKey,
            exceptionScenario: ExceptionScenario.encryptionFailed);
      }
    } else {
      encryptedSharedKey = await _getEncryptedSharedKey(atKey);
    }
    if (encryptedSharedKey == null ||
        encryptedSharedKey.isEmpty ||
        encryptedSharedKey == 'null') {
      throw SharedKeyNotFoundException('shared encryption key not found',
          intent: Intent.fetchEncryptionSharedKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    String decryptedValue = '';
    try {
      //# TODO remove else block once atChops once testing is good
      if (atClient!.getPreferences()!.useAtChops) {
        final decryptionResult = atClient!.atChops!
            .decryptString(encryptedSharedKey, EncryptionKeyType.rsa2048);
        decryptedValue = EncryptionUtil.decryptValue(
            encryptedValue, decryptionResult.result);
      } else {
        var currentAtSignPrivateKey =
            await (atClient!.getLocalSecondary()!.getEncryptionPrivateKey());
        if (currentAtSignPrivateKey == null ||
            currentAtSignPrivateKey.isEmpty) {
          throw AtPrivateKeyNotFoundException('Encryption private not found',
              intent: Intent.fetchEncryptionPrivateKey,
              exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
        }
        decryptedValue = EncryptionUtil.decryptValue(
            encryptedValue,
            EncryptionUtil.decryptKey(
                encryptedSharedKey, currentAtSignPrivateKey));
      }
    } on AtKeyException catch (e) {
      e.stack(AtChainedException(
          Intent.decryptData,
          ExceptionScenario.decryptionFailed,
          'Failed to decrypt ${atKey.toString()}'));
      rethrow;
    }
    return decryptedValue;
  }

  Future<String> _getEncryptedSharedKey(AtKey atKey) async {
    String? encryptedSharedKey = '';
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedWith = AtClientManager.getInstance().atClient.getCurrentAtSign()
      ..sharedBy = atKey.sharedBy
      ..isCached = true;
    try {
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
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
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = atKey.sharedBy
        ..auth = true;
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
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
