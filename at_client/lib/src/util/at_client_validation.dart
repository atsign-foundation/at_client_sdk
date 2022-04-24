import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_commons.dart';

class AtClientValidation {
  static void validateKey(String? key) {
    if (key == null || key.isEmpty) {
      throw AtKeyException('Key cannot be null or empty');
    }
    // Key cannot contain @
    if (key.contains('@')) {
      throw AtKeyException('Key cannot contain @');
    }
    // Key cannot contain whitespaces
    if (key.contains(' ')) {
      throw AtKeyException('Key cannot contain whitespaces');
    }
  }

  /// Validates the metadata of the key.
  /// Throws [AtKeyException] if metadata has invalid values.
  static void validateMetadata(Metadata? metadata) {
    if (metadata == null) {
      return;
    }
    // validate TTL
    if (metadata.ttl != null && metadata.ttl! < 0) {
      throw AtKeyException(
          'Invalid TTL value: ${metadata.ttl}. TTL value cannot be less than 0');
    }
    // validate TTB
    if (metadata.ttb != null && metadata.ttb! < 0) {
      throw AtKeyException(
          'Invalid TTB value: ${metadata.ttb}. TTB value cannot be less than 0');
    }
    //validate TTR
    if (metadata.ttr != null && metadata.ttr! < -1) {
      throw AtKeyException(
          'Invalid TTR value: ${metadata.ttr}. valid values for TTR are -1 and greater than or equal to 1');
    }
  }

  /// Verify if the atSign exists in root server.
  /// Throws [InvalidAtSignException] if atSign does not exist.
  static Future<void> isAtSignExists(
      String atSign, String rootDomain, int rootPort) async {
    if (atSign.isEmpty) {
      throw AtKeyException('@sign cannot be empty');
    }
    try {
      await AtClientUtil.findSecondary(atSign, rootDomain, rootPort);
    } on SecondaryNotFoundException {
      throw AtKeyException('$atSign does not exist');
    }
  }

  /// Validates the atKey.
  static Future<void> validateAtKey(AtKey atKey) async {
    // validates the atKey
    validateKey(atKey.key);
    // validates the metadata
    validateMetadata(atKey.metadata);
    // verifies if the sharedWith atSign exists.
    if (atKey.sharedWith != null && await NetworkUtil.isNetworkAvailable()) {
      await isAtSignExists(
          atKey.sharedWith!,
          AtClientManager.getInstance().atClient.getPreferences()!.rootDomain,
          AtClientManager.getInstance().atClient.getPreferences()!.rootPort);
    }
  }

  /// Performs the validations on the PutRequest
  static void validatePutRequest(
      AtKey atKey, dynamic value, AtClientPreference atClientPreference) {
    // If length of value exceeds maxDataSize, throw AtClientException
    if (value.length > atClientPreference.maxDataSize) {
      // TODO Throw AtValueException or BufferOverFlowException
      throw AtClientException('AT0005', 'BufferOverFlowException');
    }
    // If key is cached, throw exception
    if (atKey.metadata != null && atKey.metadata!.isCached) {
      // TODO Throw AtKeyException
      throw AtClientException('AT0014', 'User cannot create a cached key');
    }
    // If namespace is not set on key and in preferences, throw exception
    if ((atKey.namespace == null || atKey.namespace!.isEmpty) &&
        (atClientPreference.namespace == null ||
            atClientPreference.namespace!.isEmpty)) {
      // TODO Throw AtKeyException
      throw AtClientException('AT0014', 'namespace is mandatory');
    }
  }
}
