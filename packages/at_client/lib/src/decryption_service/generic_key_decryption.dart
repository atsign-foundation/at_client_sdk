import 'package:at_chops/types.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';
import '../../at_client.dart';

class GenericKeyDecryption extends AtKeyDecryption {
  final AtSignLogger _logger = AtSignLogger('GenericKeyDecryption');
  final AtClient _atClient;
  GenericKeyDecryption(this._atClient);

  /// Returns the decrypted value for the given encrypted value.
  ///
  /// Throws [IllegalArgumentException] if encrypted value is null.
  ///
  /// Throws [KeyNotFoundException] if encryption keys are not found.
  Future<dynamic> decrypt(AtKey key, dynamic value) {
    AppMetadata appMetadata = key.metadata.appMetadata!;
  }

  Future<String> fetchKey({
    required Secondary secondary,
    required String sharedWith,
    required String sharedBy,
    required String keyName,
    required String algo,
  }) async {
    AtKey atKey = AtKey()
      ..key = '$keyName.${sharedWith.replaceAll('@', '')}'
      ..sharedBy = sharedBy;
    var llookupVerbBuilder = LLookupVerbBuilder()..atKey = atKey;

    // lookup
    String? value;
    try {
      value = await secondary.executeVerb(llookupVerbBuilder);
    } on KeyNotFoundException catch (_) {
      rethrow;
    }
    if (value == 'data:null') {
      throw KeyNotFoundException(
          '${llookupVerbBuilder.toString()} returned data:null');
    }

    //clean up value
    value = DefaultResponseParser().parse(value!).response;
    await storeKeyInLocal(atKey, value);
    //TODO: using String because we'll want to rip EncryptionKeyType out eventually
    //when the time comes, stop using EncryptionKeyType
    EncryptionKeyType algoType = EncryptionKeyType.values.byName(algo);
    final decryptionResult =
        await _atClient.atChops!.decryptString(value, algoType);
    return decryptionResult.result;
  }

  /// Stores the encryptedSharedKey for future use.
  Future<void> storeKeyInLocal(
    AtKey atKey,
    String value,
  ) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey = atKey
      ..value = value;
    await _atClient
        .getLocalSecondary()!
        .executeVerb(updateSharedKeyForCurrentAtSignBuilder, sync: false);
  }
}
