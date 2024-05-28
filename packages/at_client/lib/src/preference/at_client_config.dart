/// The class contains all the client configurations.
class AtClientConfig {
  static final AtClientConfig _singleton = AtClientConfig._internal();

  AtClientConfig._internal();

  factory AtClientConfig.getInstance() {
    return _singleton;
  }

  /// Represents the at_client version.
  /// Must always be the same as the actual version in pubspec.yaml
  final String atClientVersion = '3.0.76';

  /// Represents the client commit log compaction time interval
  ///
  /// Triggers the compaction job for every 11 minutes.
  final int commitLogCompactionTimeIntervalInMins = 11;
}
