import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_commons.dart';

class AtClientValidation {
  static void validateKey(String? key) {
    if (key == null || key.isEmpty) {
      throw AtKeyException('Key cannot be null or empty')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidKeyFormed);
    }
    // Key cannot contain @
    if (key.contains('@')) {
      throw AtKeyException('Key cannot contain @')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidKeyFormed);
    }
    // Key cannot contain whitespaces
    if (key.contains(' ')) {
      throw AtKeyException('Key cannot contain whitespaces')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidKeyFormed);
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
          'Invalid TTL value: ${metadata.ttl}. TTL value cannot be less than 0')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidMetadataProvided);
    }
    // validate TTB
    if (metadata.ttb != null && metadata.ttb! < 0) {
      throw AtKeyException(
          'Invalid TTB value: ${metadata.ttb}. TTB value cannot be less than 0')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidMetadataProvided);
    }
    //validate TTR
    if (metadata.ttr != null && metadata.ttr! < -1) {
      throw AtKeyException(
          'Invalid TTR value: ${metadata.ttr}. valid values for TTR are -1 and greater than or equal to 1')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidMetadataProvided);
    }
  }

  /// Verify if the atSign exists in root server.
  /// Throws [InvalidAtSignException] if atSign does not exist.
  static Future<void> isAtSignExists(
      String atSign, String rootDomain, int rootPort) async {
    if (atSign.isEmpty) {
      throw AtKeyException('@sign cannot be empty')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidKeyFormed);
    }
    try {
      await AtClientManager.getInstance()
          .secondaryAddressFinder!
          .findSecondary(atSign);
    } on SecondaryNotFoundException {
      throw AtKeyException('$atSign does not exist')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidKeyFormed);
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
}
