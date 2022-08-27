/// The class contains all the client configurations.
class AtClientConfig {
  static final AtClientConfig _singleton = AtClientConfig._internal();

  AtClientConfig._internal();

  factory AtClientConfig.getInstance() {
    return _singleton;
  }

  /// Represents the at_client version.
  /// The version number is updated here through the github actions (Refrain from updating the version manually).
  /// workflow name: at_client_sdk
  /// job name: update_client_version
  String atClientVersion = '3.0.35';
}
