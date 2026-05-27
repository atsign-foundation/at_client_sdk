import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:version/version.dart';

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

  bool _isLocalStoreRequired = true;

  bool get isLocalStoreRequired => _isLocalStoreRequired;

  @Deprecated("LocalStore is always required")
  set isLocalStoreRequired(bool b) => _isLocalStoreRequired = b;

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

  /// The maximum size of the value that a secondary server can store.
  /// [BufferOverFlowException] is thrown when size of the value exceeds the [maxDataSize]
  int maxDataSize = 10230000;

  /// Default path to download stream files
  String? downloadPath;

  /// regex to perform sync
  String? syncRegex;

  /// Number of keys to batch for sync to secondary server
  int syncBatchSize = 5;

  /// The number of keys to pull from cloud secondary to local secondary in a single call.
  int syncPageLimit = 25;

  /// Default chunk size for file encryption and decryption
  int fileEncryptionChunkSize = 4096;

  /// The NotificationService maintains a connection which monitors for new
  /// notifications being delivered from the atServer. Because network weather
  /// is real, and because it is generally essential for client programs to
  /// receive notifications consistently, a heartbeat `no-op` command is sent
  /// to the atServer periodically, at this interval
  Duration monitorHeartbeatInterval = Duration(seconds: 59);

  /// When a heartbeat is sent by the notifications monitor, we wait for this
  /// length of time to receive a response. If no response is received, then
  /// the connection is closed, and the notifications monitor will reconnect.
  ///
  /// See also [monitorHeartbeatInterval]
  Duration monitorHeartbeatResponseTimeout = Duration(seconds: 10);

  /// - when true, then the notifications monitor will be started either the
  /// first time that [NotificationService.subscribe] is called by the
  /// application code, or 30 seconds after creation of the
  /// [NotificationService] if there have been no subscriptions.
  /// - when false, then the notifications monitor
  /// will not be started until explicitly requested to do so by the
  /// application calling [NotificationService.startListening]
  bool monitorAutoStart = true;

  /// Time interval for the scheduled task that removes expired keys from local keyStore
  ///
  /// Please provide duration ONLY in minutes e.g. Duration(minutes: x) [x should be between 1 and 59]
  Duration expiryCheckTimeInterval = Duration(minutes: 10);

  ///[OptionalParameter] when set to true logs TLS Keys to file.
  bool decryptPackets = false;

  ///[OptionalParameter] location where the TLS keys will be saved when [decryptPackets] is set to true
  String? tlsKeysSavePath;

  ///[OptionalParameter] path to trusted certificates. Required to create security context.
  String? pathToCerts;

  /// [AtClient.put] uses this parameter to decide whether to check for presence of a namespace in the
  /// string representation of the AtKey.
  /// * When set to true, keys such as public:foo@alice or @bob:foo@alice will be rejected
  /// because they do not have a namespace. But keys such as public:foo.bar@alice of @bob:foo.bar.baz.bash@alice will be accepted.
  /// * When set to false keys such as public:foo@alice or @bob:foo@alice will not be rejected
  /// * Defaults to true, as applications should always be placing keys within a namespace
  @Deprecated(
      "namespace presence will become mandatory in next major version of the SDK")
  bool enforceNamespace = true;

  /// Fetch the notifications received when the client is offline. Defaults to true.
  /// Set to false to ignore the notifications received when device is offline.
  bool fetchOfflineNotifications = true;

  @Deprecated('No longer needed. at_chops will be used by default')
  bool useAtChops = true;

  /// Poorly named variable which used to control some aspects of at_client's
  /// default data encryption. Is now fully ignored.
  @Deprecated('Ignored. Will be removed in next major version')
  Version atProtocolEmitted = Version(2, 0, 0);

  AtClientParticulars atClientParticulars = AtClientParticulars();

  /// signing algorithm to use for pkam authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// hashing algorithm to use for pkam authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  /// Set this to [RemoteLocalPref.remoteOnly]
  /// if you require all data operations (get / put / delete) to be performed
  /// on the remote atServer rather than on local storage. (When operations are
  /// performed locally, we depend on sync to get eventual consistency between
  /// local and remote.
  RemoteLocalPref remoteLocalPref = RemoteLocalPref.localOnly;

  /// Configures the crypto provider used for encrypted puts and reads.
  ///
  /// Defaults to the legacy Atsign encryption provider. Custom providers are
  /// initialized by [AtClientImpl] before sync and notification services start.
  CryptoConfig crypto = const CryptoConfig.legacy();
}

/// Default preference on how to handle get, put and delete requests with
/// regards to use of local storage vs the remote atServer.
enum RemoteLocalPref {
  /// The default - operate on local storage, and rely on the background
  /// sync processing to push changes to the remote atServer.
  localOnly,

  // /// Operate on remote first. If there is an exception, rethrow it back to
  // /// application code. If remote operation was successful, then perform the
  // /// operation on local storage.
  // remoteFirst,
  //
  /// Operate on remote only - i.e. do not interact with local storage at all.
  /// Note that if the application is syncing, then the change will be pulled
  /// to local from remote as part of the sync process.
  remoteOnly,
}

@Deprecated("Use SyncService")
enum SyncStrategy {
  /// Sync local keys immediately to secondary server for update and delete commands.
  immediate,
  onDemand,

  /// Sync periodically once every time interval specified by [AtClientPreference.syncIntervalMins].
  scheduled
}
