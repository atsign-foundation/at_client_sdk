import 'package:at_client/at_client.dart';

/// Class to hold attributes for client preferences.
/// Set the preferences for your application and pass it to [AtClientManager.setCurrentAtSign].
class AtClientPreference {
  /// Local device path of hive storage
  String? hiveStoragePath;

  /// Local device path of commit log
  String? commitLogPath;

  /// Syncing strategy of the client [SyncStrategy]
  /// [Deprecated] Use [SyncService]
  @Deprecated("Use [SyncService]")
  SyncStrategy? syncStrategy;

  /// Specify whether local store is required
  bool isLocalStoreRequired = false;

  /// Shared secret of the atSign
  String? cramSecret;

  /// Private key of the atSign
  String? privateKey;

  /// Specifies the namespace of an app.
  String? namespace;

  /// Secret key to encrypt keystore data
  List<int>? keyStoreSecret;

  /// Domain of the root server. Defaults to root.atsign.org
  String rootDomain = 'root.atsign.org';

  /// Port of the root server. Defaults to 64
  int rootPort = 64;

  /// Frequency of sync task to run in minutes. Defaults to 10 minutes.
  int syncIntervalMins = 10;

  /// Idle time in milliseconds of connection to secondary server. Default to 10 minutes.
  int outboundConnectionTimeout = 600000;

  /// Maximum data size a secondary can store. Temporary solution. Have to fetch this from
  /// server using stats verb.
  int maxDataSize = 10230000;

  /// Default path to download stream files
  String? downloadPath;

  /// regex to perform sync
  String? syncRegex;

  /// Number of keys to batch for sync to secondary server
  int syncBatchSize = 5;

  /// The number of keys to pull from cloud secondary to local secondary in a single call.
  int syncPageLimit = 10;

  // Default chunk size for file encryption and decryption
  int fileEncryptionChunkSize = 4096;

  Duration monitorHeartbeatInterval = Duration(seconds: 10);

  ///[OptionalParameter] when set to true logs TLS Keys to file.
  bool decryptPackets = false;

  ///[OptionalParameter] location where the TLS keys will be saved when [decryptPackets] is set to true
  String? tlsKeysSavePath;

  ///[OptionalParameter] path to trusted certificates. Required to create security context.
  String? pathToCerts;

  // TODO Remove this in next major version
  @Deprecated(
      "namespace presence will become mandatory in next major version of the SDK")

  /// [AtClient.put] uses this parameter to decide whether to check for presence of a namespace in the
  /// string representation of the AtKey.
  /// * When set to true, keys such as public:foo@alice or @bob:foo@alice will be rejected
  /// because they do not have a namespace. But keys such as public:foo.bar@alice of @bob:foo.bar.baz.bash@alice will be accepted.
  /// * When set to false keys such as public:foo@alice or @bob:foo@alice will not be rejected
  /// * Defaults to true, as applications should always be placing keys within a namespace
  bool enforceNamespace = true;

  /// Fetch the notifications received when the client is offline. Defaults to true.
  /// Set to false to ignore the notifications received when device is offline.
  bool fetchOfflineNotifications = true;

  /// Temporary feature flag. Remove once tests are successful.
  bool useAtChops = false;
}

@Deprecated("Use SyncService")
enum SyncStrategy {
  /// Sync local keys immediately to secondary server for update and delete commands.
  immediate,
  onDemand,

  /// Sync periodically once every time interval specified by [AtClientPreference.syncIntervalMins].
  scheduled
}
