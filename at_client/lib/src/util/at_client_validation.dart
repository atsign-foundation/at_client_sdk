import 'package:at_client/at_client.dart';
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
}
