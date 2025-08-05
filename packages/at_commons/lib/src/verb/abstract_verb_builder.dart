import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

/// An abstract class implementing the [VerbBuilder].
/// Class contains the implementation for validating the key data and building
/// the key (common for all verb builder) from the verb builder instances.
abstract class AbstractVerbBuilder implements VerbBuilder {
  /// Represents the AtKey instance to populate the verb builder data
  AtKey atKey = AtKey()..metadata = Metadata();

  /// Validates the [AtKey]
  ///
  ///
  /// Throws [InvalidAtKeyException] when the following conditions are met
  /// * When [metadata.isCached] is set to true on a local key
  ///
  /// * When [metadata.isPublic] is set to true on a local key
  ///
  /// * When sharedWith is populated on a local key
  ///
  /// * When [metadata.isPublic] is set to true on a shared key
  ///
  /// * When [AtKey.key] is set to null or empty
  ///
  /// * When [AtKey.key] contains @ or : characters
  void validateKey() {
    if (atKey.metadata.isCached == true && atKey.isLocal == true) {
      throw InvalidAtKeyException('Cached key cannot be a local key');
    }
    if (atKey.isLocal == true &&
        (atKey.metadata.isPublic == true ||
            atKey.sharedWith.isNotNullOrEmpty)) {
      throw InvalidAtKeyException(
          'When isLocal is set to true, cannot set isPublic to true or set a non-null sharedWith');
    }
    if (atKey.metadata.isPublic == true && atKey.sharedWith.isNotNullOrEmpty) {
      throw InvalidAtKeyException(
          'When isPublic is set to true, sharedWith cannot be populated');
    }
    if (atKey.key.isNullOrEmpty) {
      throw InvalidAtKeyException('Key cannot be null or empty');
    }
  }
}
