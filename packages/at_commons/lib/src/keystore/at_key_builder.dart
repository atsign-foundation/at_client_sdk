import 'package:at_commons/at_commons.dart';

/// Builder to build instances of AtKey's
abstract class KeyBuilder {
  /// Returns an instance of AtKey
  AtKey build();

  /// Validates AtKey and throws Exception for a given issue
  void validate();

  /// Set simple key without any namespace. For example "phone", "email" etc...
  /// This is required.
  void key(String key);

  /// Each app should write to a specific namespace.
  /// This is required.
  void namespace(String namespace);

  /// Set this value to set an expiry to a key in milliseconds.
  /// Time until expiry
  void timeToLive(int ttl);

  /// Set this value to set time after which the key should be available in milliseconds.
  /// Time until availability
  void timeToBirth(int ttb);

  /// Set the current AtSign
  /// This is required.
  void sharedBy(String atSign);
}
