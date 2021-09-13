import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

class AtClientValidation {
  /// This function is used to validate the [key].
  /// Throws [AtKeyException] if key has invalid values.
  static bool _validateKey(String? key) {
    /// Key cannot be null.
    if (key == null) {
      throw AtKeyException('AtKey is null');
    }

    /// Key cannot be empty.
    if (key.isEmpty) {
      throw AtKeyException('Key cannot be empty');
    }

    /// Key cannot contain @
    if (key.contains('@')) {
      throw AtKeyException('Key cannot contain @');
    }

    /// Key cannot contain whitespaces
    if (key.contains(' ')) {
      throw AtKeyException('Key cannot contain whitespaces');
    }
    return true;
  }

  /// Validates the metadata of the key.
  /// Throws [AtKeyException] if metadata has invalid values.
  static void _validateMetadata(Metadata? metadata) {
    if (metadata == null) {
      return;
    } else
    // validate TTL
    if (metadata.ttl != null && metadata.ttl! < 0) {
      throw AtKeyException('Invalid TTL value: ${metadata.ttl}. TTL value cannot be less than 0');
    } else

    // validate TTB
    if (metadata.ttb != null && metadata.ttb! < 0) {
      throw AtKeyException('Invalid TTB value: ${metadata.ttb}. TTB value cannot be less than 0');
    } else

    //validate TTR
    if (metadata.ttr != null && metadata.ttr! < -1) {
      throw AtKeyException(
          'Invalid TTR value: ${metadata.ttr}. valid values for TTR are -1 and greater than or equal to 1');
    }
  }

  /// Verify if the atSign exists in root server.
  /// Throws [InvalidAtSignException] if atSign does not exist.
  @Deprecated(
      'isAtSignExists function has been deprecated. Use `AtClientBase.validateAtSign()` function/method for validating atSign.')
  static void isAtSignExists(String atSign, String rootDomain, int rootPort) async {
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
  /// Throws [UnAuthorizedException] if atKey is a cached one.
  static Future<void> validateAtKey(AtKey atKey, {AtClientPreference? preferences}) async {
    _validateKey(atKey.key!);
    _validateNamespace(atKey.namespace);
    if ((atKey.metadata != null && atKey.metadata!.isCached) || atKey.key!.startsWith('cached:')) {
      throw UnAuthorizedException('Cannot update a cached key.');
    }
    _validateMetadata(atKey.metadata);
    if (atKey.sharedWith != null) {
      atKey.sharedWith = AtUtils.fixAtSign(atKey.sharedWith!);
      // verify only if network is available. validate if the sharedWith @sign exists.
      if (await NetworkUtil.isNetworkAvailable()) {
        validateAtSign(atKey.sharedWith!, preferences!.rootDomain, preferences.rootPort);
      }
    }
  }

  /// validateNamespace checks if the namespace is valid.
  /// Throws [AtNamespaceException] if namespace is empty or null.
  static bool _validateNamespace(String? namespace) {
    if (namespace == null || namespace.isEmpty || namespace == 'null') {
      throw AtNamespaceException('Namespace cannot be null or empty');
    }
    return true;
  }

  /// Verify if the atSign exists.
  /// Throws [InvalidAtSignException] if atSign does not exist.
  static Future<void> validateAtSign(String atSign, String rootDomain, int rootPort) async {
    if (atSign.isEmpty) {
      throw AtKeyException('@sign cannot be empty');
    }
    try {
      await AtClientUtil.findSecondary(atSign, rootDomain, rootPort);
    } on SecondaryNotFoundException {
      throw AtKeyException('$atSign does not exist');
    }
  }
}
