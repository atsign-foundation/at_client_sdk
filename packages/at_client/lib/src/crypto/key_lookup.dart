import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';

class KeyLookup {
  final AtClient _atClient;
  KeyLookup(this._atClient);

  // leaving keyType as a string in hopes of deprecating EncryptionKeyType?
  Future<AbstractKey> fetchKey({
    required String keyName,
    required String sharedWith,
    required String sharedBy,
    required String algo,
  }) async {
    AbstractKey encryptionKey;
    try {
      encryptionKey = await _fetchKey(
        _atClient.getLocalSecondary()!,
        sharedWith,
        sharedBy,
        keyName,
        keyType: algo,
      );
    } catch (_) {
      encryptionKey = await _fetchKey(
        _atClient.getRemoteSecondary()!,
        sharedWith,
        sharedBy,
        keyName,
        keyType: algo,
      );
    }
    return encryptionKey;
  }

  Future<AbstractKey> _fetchKey(
    Secondary secondary,
    String sharedWith,
    String sharedBy,
    String keyName, {
    String? keyType,
  }) async {
    AtKey atKey = AtKey()
      ..key = '$keyName.${sharedWith.replaceAll('@', '')}'
      ..sharedBy = sharedBy;
    var llookupVerbBuilder = LookupVerbBuilder()..atKey = atKey;

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

    //keep encryptionKeyType open ended (we'll leave as a string)
    EncryptionKeyType type;
    if (keyType != null) {
      type = EncryptionKeyType.values.byName(keyType);
    } else {
      //fallback to rsa2048
      type = EncryptionKeyType.rsa2048;
    }
    await _storeKeyInLocal(atKey, value);
    final decryptionResult = await _atClient.atChops!.decryptString(
      value,
      type,
    );
    return decryptionResult.result;
  }

  /// Stores the encryptedSharedKey for future use.
  Future<void> _storeKeyInLocal(
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
